import ClientServer::*;
import ClientServerHelper::*;
import GetPut::*;
import FIFOF::*;
import FIFO::*;

import RWBramCore::*;
import RegFile::*;

import Vector::*;

import FlashCtrlIfc::*;
import ControllerTypes::*;

import Connectable::*;

Bool debug = True;

interface PageBufferClient#(numeric type numPages);
   interface Client#(DualFlashAddr, Bit#(TLog#(numPages))) bufReserve;
   interface Client#(Bit#(TLog#(numPages)), Bit#(256)) circularRead;
   interface Get#(Bit#(TLog#(numPages))) doneBuf;
endinterface


interface PageBufferServer#(numeric type numPages);
   interface Server#(DualFlashAddr, Bit#(TLog#(numPages))) bufReserve;
   interface Server#(Bit#(TLog#(numPages)), Bit#(256)) circularRead;
   interface Put#(Bit#(TLog#(numPages))) doneBuf;
endinterface
      
instance Connectable#(PageBufferClient#(numPages), PageBufferServer#(numPages));
   module mkConnection#(PageBufferClient#(numPages) cli, PageBufferServer#(numPages) ser)(Empty);
      mkConnection(cli.bufReserve, ser.bufReserve);
      mkConnection(cli.circularRead, ser.circularRead);
      mkConnection(cli.doneBuf, ser.doneBuf);
   endmodule
endinstance

interface DualFlashPageBuffer#(numeric type numSlaves, numeric type numPages);
   interface Vector#(numSlaves, PageBufferServer#(numPages)) pageBufferServers;
   interface Client#(Tuple2#(TagT, DualFlashAddr), Tuple2#(TagT, Bit#(256))) flashRdClient;
endinterface


module mkDualFlashPageBuffer(DualFlashPageBuffer#(numSlaves,  numPages)) provisos (
   Add#(a__, TLog#(numPages), 7),
   Add#(b__, TLog#(numPages), TLog#(TAdd#(numPages, 1))),
   Alias#(Bit#(TLog#(numPages)), tagT),
   Alias#(Bit#(TLog#(numSlaves)), slaveIdT));
   
   Reg#(Bit#(TLog#(TAdd#(numPages,1)))) initCnt <- mkReg(0);
   FIFO#(tagT) freeBufIdQ <- mkSizedFIFO(valueOf(numPages)+1);
      
   rule doInit if ( initCnt != fromInteger(valueOf(numPages)) );
      $display("(%m) doInit %d", initCnt);
      initCnt <= initCnt + 1;
      freeBufIdQ.enq(truncate(initCnt));
   endrule
   
   RWBramCore#(Bit#(TAdd#(TLog#(numPages), 8)), Bit#(256)) buffer <- mkRWBramCore;
   
   function Bit#(TAdd#(TLog#(numPages), 8)) toBufferIdx(Bit#(TLog#(numPages)) tag, Bit#(w) ptr);
      return {tag, ptr[7:0]};
   endfunction
      
   // replicated ptrs for ease of synthesizing
   Vector#(numSlaves, Vector#(numPages, Reg#(Bit#(9)))) enqPtrs <- replicateM(replicateM(mkReg(0)));
   Vector#(numSlaves, Vector#(numPages, Reg#(Bit#(8)))) deqPtrs <- replicateM(replicateM(mkReg(0)));
   
   FIFO#(Tuple2#(TagT, DualFlashAddr)) flashReqQ <- mkFIFO;

   Vector#(numSlaves, FIFO#(tagT)) tagRespQs <- replicateM(mkSizedFIFO(valueOf(numPages)+1));
   Vector#(numSlaves, FIFO#(tagT)) deqReqQs <- replicateM(mkFIFO);
   
   RegFile#(tagT, slaveIdT) tagTable <- mkRegFileFull;
   
   Vector#(numSlaves, FIFO#(Tuple2#(TagT, Bit#(256)))) flashRespQs <- replicateM(mkFIFO);
   
   FIFO#(slaveIdT) readDst <- mkFIFO;
   
   Vector#(numSlaves, FIFO#(Bit#(256))) deqRespQs <- replicateM(mkFIFO);
   
   for (Integer i = 0; i < valueOf(numSlaves); i = i + 1) begin
      rule processDeqReq;
         let tag = deqReqQs[i].first;
         // this is safe only since we know that we will not write exceed the capacity
         if ( zeroExtend(deqPtrs[i][tag]) < enqPtrs[i][tag] ) begin
            deqPtrs[i][tag] <= deqPtrs[i][tag] + 1;
            buffer.rdReq(toBufferIdx(tag, deqPtrs[i][tag]));
            readDst.enq(fromInteger(i));
            deqReqQs[i].deq;
            if (debug) $display("(@%t) execute deq for tag = %d, client = %d, enqPtr = %d, deqPtr = %d", $time, tag, i, enqPtrs[i][tag], deqPtrs[i][tag]);
         end
      endrule
      
      
      rule processEnqReq;
         let {fTag, data} <- toGet(flashRespQs[i]).get;
         tagT tag = truncate(fTag);
         // only write data within 8kB
         if (debug) $display("(@%t) execute enq for tag = %d, client = %d, enqPtr = %d", $time, tag, i, enqPtrs[i][tag]);//, deqPtrs[i][tag]);
         if ( enqPtrs[i][tag] < 256 ) begin
            buffer.wrReq(toBufferIdx(tag, enqPtrs[i][tag]), data);
            // enq is unguarded since we know that we will not write exceed the capacity
            enqPtrs[i][tag] <= enqPtrs[i][tag] + 1;
         end
      endrule
   end
   
   rule distrbuteRead;
      let slaveId <- toGet(readDst).get();
      let data = buffer.rdResp;
      buffer.deqRdResp;
      deqRespQs[slaveId].enq(data);
   endrule

   
   function PageBufferServer#(numPages) genPageBufferServer(Integer i);
      return (interface PageBufferServer;
                 interface Server bufReserve;
                    interface Put request;
                       method Action put(DualFlashAddr addr);
                          let tag <- toGet(freeBufIdQ).get;
                          tagTable.upd(tag, fromInteger(i));
                          flashReqQ.enq(tuple2(zeroExtend(tag), addr));
                          tagRespQs[i].enq(tag);

                       endmethod
                    endinterface
                    interface Get response = toGet(tagRespQs[i]);
                 endinterface
         
                 interface Server circularRead;
                    interface Put request = toPut(deqReqQs[i]);
                    interface Get response = toGet(deqRespQs[i]);
                 endinterface

                 interface Put doneBuf;
                    method Action put(Bit#(TLog#(numPages)) tag);
                       freeBufIdQ.enq(tag);
                       deqPtrs[i][tag] <= 0;
                       enqPtrs[i][tag] <= 0;
                    endmethod
                 endinterface
              endinterface);
   endfunction


   interface pageBufferServers = genWith(genPageBufferServer);
   
   interface Client flashRdClient;
      interface Get request = toGet(flashReqQ);
      interface Put response;
         method Action put(Tuple2#(TagT, Bit#(256)) v);
            let {tag, data} = v;
            let slaveId = tagTable.sub(truncate(tag));
            flashRespQs[slaveId].enq(v);
         endmethod
      endinterface
   endinterface
   
endmodule
