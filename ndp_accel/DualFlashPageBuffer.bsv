import ISSPTypes::*;
import NDPCommon::*;
import ClientServer::*;
import ClientServerHelper::*;
import GetPut::*;
import FIFOF::*;
import FIFO::*;
import SpecialFIFOs::*;
import Cntrs::*;

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
   method Action dumpTrace();
   method ActionValue#(Tuple4#(Bit#(8), Bit#(64), Bit#(8), Bit#(64))) traceResp;
endinterface


module mkDualFlashPageBuffer(DualFlashPageBuffer#(numSlaves,  numPages)) provisos (
   Add#(a__, TLog#(numPages), 7),
   Add#(b__, TLog#(numPages), TLog#(TAdd#(numPages, 1))),
   Add#(c__, TLog#(numPages), 8),
   Alias#(Bit#(TLog#(numPages)), tagT),
   Alias#(Bit#(TLog#(numSlaves)), slaveIdT));
   
   Reg#(Bit#(TLog#(TAdd#(numPages,1)))) initCnt <- mkReg(0);
   FIFO#(tagT) freeBufIdQ <- mkSizedFIFO(valueOf(numPages)+1);
   
   `ifdef TRACE_BUF
   Reg#(PageBufTraceIdx) reserveIdx <- mkReg(0);
   Reg#(PageBufTraceIdx) releaseIdx <- mkReg(0);
   Reg#(PageBufTraceIdx) dumpIdx <- mkReg(0);
   FIFOF#(void) dumpReq <- mkFIFOF;
   RWBramCore#(PageBufTraceIdx, Tuple2#(tagT, Bit#(64))) bufReserveTrace <- mkRWBramCore;
   RWBramCore#(PageBufTraceIdx, Tuple2#(tagT, Bit#(64))) bufReleaseTrace <- mkRWBramCore;
   Reg#(Bit#(64)) cycle <- mkReg(0);
   rule incrCycle;
      cycle <= cycle + 1;
   endrule
   
   rule doDump if (dumpReq.notEmpty);
      if ( dumpIdx == maxBound ) dumpReq.deq;
      dumpIdx <= dumpIdx + 1;
      bufReserveTrace.rdReq(dumpIdx);
      bufReleaseTrace.rdReq(dumpIdx);
   endrule
   `endif
   
      
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
   Vector#(numSlaves, Vector#(numPages, Array#(Reg#(Bool)))) isFull <- replicateM(replicateM(mkCReg(2,False)));
   Vector#(numSlaves, Vector#(numPages, Reg#(Bit#(8)))) deqPtrs <- replicateM(replicateM(mkReg(0)));
   // Vector#(numPages, Reg#(Bit#(9))) enqPtrs <- replicateM(mkReg(0));
   // Vector#(numPages, Reg#(Bit#(8))) deqPtrs <- replicateM(mkReg(0));

   
   FIFO#(Tuple2#(TagT, DualFlashAddr)) flashReqQ <- mkFIFO;

   Vector#(numSlaves, FIFO#(tagT)) tagRespQs <- replicateM(mkSizedFIFO(valueOf(numPages)+1));
   Vector#(numSlaves, FIFOF#(tagT)) deqReqQs <- replicateM(mkFIFOF);
   
   RegFile#(tagT, slaveIdT) tagTable <- mkRegFileFull;
   
   Vector#(numSlaves, FIFO#(Tuple2#(TagT, Bit#(256)))) flashRespQs <- replicateM(mkFIFO);
   // FIFO#(Tuple2#(TagT, Bit#(256))) flashRespQ <- mkFIFO;
   
   FIFO#(slaveIdT) readDst <- mkPipelineFIFO;
   
   Vector#(numSlaves, FIFO#(Bit#(256))) deqRespQs <- replicateM(mkFIFO);
   Vector#(numSlaves, FIFO#(tagT)) doneBufQs <- replicateM(mkFIFO);
   
   Reg#(Bit#(TLog#(TAdd#(numPages,1)))) outstandingBufCnt[2] <- mkCReg(2,0);
   
   Vector#(numSlaves, Array#(Reg#(UInt#(3)))) inPipeElemCnts <- replicateM(mkCReg(2,0));
   
   // delaying the bram req by one cycle to cut down critical path
   FIFO#(Tuple3#(slaveIdT, tagT, Bit#(8))) bramRdReqQ <- mkPipelineFIFO;
   FIFO#(Tuple3#(Bit#(256), tagT, Bit#(8))) bramWrReqQ <- mkPipelineFIFO;
   
   
   for (Integer i = 0; i < valueOf(numSlaves); i = i + 1) begin
      // (* descending_urgency = "processDoneBuf, processEnqReq, processDeqReq" *)
      
      // rule displayFull if ( !deqReqQs[i].notFull );
      //    $display("(%m) warning deqReqQs[%d] is full...", i);
      // endrule
      rule processDoneBuf if (  doneBufQs[i].first matches .tag &&& isFull[i][tag][1]);        //if ( enqPtrs[i][doneBufQs[i].first] == 257);
         // let tag = doneBufQs[i].first;
         outstandingBufCnt[1] <= outstandingBufCnt[1] - 1;
         if (debug) $display("(@%t) execute doneBuf tag = %d, client = %d, outstandingBuf = %d", $time, tag, i, outstandingBufCnt[1]);
         freeBufIdQ.enq(tag);
         doneBufQs[i].deq;
         // deqPtrs[tag] <= 0;
         // enqPtrs[i][tag][1] <= 0;
         isFull[i][tag][1] <= False;
         `ifdef TRACE_BUF
         bufReleaseTrace.wrReq(releaseIdx, tuple2(tag,cycle));
         releaseIdx <= releaseIdx + 1;
         `endif
         
      endrule
      
      rule processDeqReq if ( deqReqQs[i].first matches .tag &&& ((zeroExtend(deqPtrs[i][tag]) < enqPtrs[i][tag] || isFull[i][tag][0]) && inPipeElemCnts[i][1] <= 2) );
         // let tag = deqReqQs[i].first;
         // this is safe only since we know that we will not write exceed the capacity
         // when ( zeroExtend(deqPtrs[i][tag]) >= enqPtrs[i][tag], noAction); 
         // if ( zeroExtend(deqPtrs[i][tag]) < enqPtrs[i][tag] ) begin
         // if ( inPipeElemCnts[i][1] < 2 ) begin
         deqPtrs[i][tag] <= deqPtrs[i][tag] + 1;
         // buffer.rdReq(toBufferIdx(tag, deqPtrs[tag]));
         // readDst.enq(fromInteger(i));
         bramRdReqQ.enq(tuple3(fromInteger(i), tag, deqPtrs[i][tag]));  // for the sake of pipelining
         deqReqQs[i].deq;
         if (debug) $display("(@%t) execute deq for tag = %d, client = %d, enqPtr = %d, deqPtr = %d, inPipeElems = %d", $time, tag, i, enqPtrs[i][tag], deqPtrs[i][tag], inPipeElemCnts[i][1]);
         inPipeElemCnts[i][1] <= inPipeElemCnts[i][1] + 1; 
         // end 
      endrule
      
      rule processEnqReq;
         // let {fTag, data} <- toGet(flashRespQ).get;
         let {fTag, data} <- toGet(flashRespQs[i]).get;
         tagT tag = truncate(fTag);
         // only write data within 8kB
         if (debug) $display("(@%t) execute enq for tag = %d, enqPtr = %d", $time, tag, enqPtrs[i][tag]);//, deqPtrs[i][tag]);
            
         if ( enqPtrs[i][tag] < 256 ) begin
            // buffer.wrReq(toBufferIdx(tag, enqPtrs[i][tag]), data);
            bramWrReqQ.enq(tuple3(data, tag, truncate(enqPtrs[i][tag])));
            // enq is unguarded since we know that we will not write exceed the capacity
         end
         
         if ( enqPtrs[i][tag] + 1 == 257 ) begin
            enqPtrs[i][tag] <= 0;
            isFull[i][tag][0] <= True;
         end
         else begin
            enqPtrs[i][tag] <= enqPtrs[i][tag] + 1;
         end
      endrule
   end
   
   rule doBRAMRead;
      let {slaveId, tag, deqPtr} <- toGet(bramRdReqQ).get;
      buffer.rdReq(toBufferIdx(tag, deqPtr));
      readDst.enq(slaveId);
   endrule
   
   rule doBRAMWrite;
      let {data, tag, enqPtr} <- toGet(bramWrReqQ).get;
      buffer.wrReq(toBufferIdx(tag, enqPtr), data);
   endrule

   
   rule distrbuteRead;
      let slaveId <- toGet(readDst).get();
      let data = buffer.rdResp;
      buffer.deqRdResp;
      if (debug) $display("(@%t) got deq response to client = %d", $time, slaveId);
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
                          outstandingBufCnt[0] <= outstandingBufCnt[0] + 1;
                          `ifdef TRACE_BUF
                          bufReserveTrace.wrReq(reserveIdx, tuple2(tag,cycle));
                          reserveIdx <= reserveIdx + 1;
                          `endif
                          if (debug) $display("(%m) Reserved tag = %d for client = %d, outstandingBuf = %d", tag, i, outstandingBufCnt[0]);
                       endmethod
                    endinterface
                    interface Get response = toGet(tagRespQs[i]);
                 endinterface
         
                 interface Server circularRead;
                    interface Put request = toPut(deqReqQs[i]);
                    interface Get response;// = toGet(deqRespQs[i]);
                       method ActionValue#(Bit#(256)) get();
                          let v <- toGet(deqRespQs[i]).get;
                          inPipeElemCnts[i][0] <= inPipeElemCnts[i][0] - 1; 
                          if (debug) $display("(%m) circularRead deq client = %d, elems = %d", i, inPipeElemCnts[i][0]);
                          // inPipeElemCnts[i].decr(1);
                          return v;
                       endmethod
                    endinterface
                 endinterface

                 interface Put doneBuf;
                    method Action put(tagT tag);
                       let clientId = tagTable.sub(tag);
                       doneBufQs[clientId].enq(tag);
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
            // flashRespQ.enq(v);
         endmethod
      endinterface
   endinterface
   
   `ifdef TRACE_BUF
   method Action dumpTrace();
      dumpReq.enq(?);
   endmethod
   
   method ActionValue#(Tuple4#(Bit#(8), Bit#(64), Bit#(8), Bit#(64))) traceResp;
      let {tag_res, cycle_res} = bufReserveTrace.rdResp;
      let {tag_rel, cycle_rel} = bufReleaseTrace.rdResp;
      bufReserveTrace.deqRdResp;
      bufReleaseTrace.deqRdResp;
      return tuple4(extend(tag_res), cycle_res, extend(tag_rel), cycle_rel);
   endmethod
   `else 
      method Action dumpTrace();
      endmethod
   
      method ActionValue#(Tuple4#(Bit#(8), Bit#(64), Bit#(8), Bit#(64))) traceResp if (False);
         return ?;
      endmethod
   `endif
   
endmodule
