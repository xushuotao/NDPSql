import RWBramCore::*;
import Vector::*;
import FIFO::*;

interface PageBuffer#(numeric type numPages);
   method ActionValue#(Bit#(TLog#(numPages))) reserveBuf();
   method Action doneBuffer((Bit#(TLog#(numPages))) v);
   
   method Action enqRequest(Bit#(256) data, Bit#(TLog#(numPages)) bufferId);
   
   method Action deqRequest(Bit#(TLog#(numPages)) tag);
   method ActionValue#(Bit#(256)) deqResponse;
endinterface


////////////////////////////////////////////////////////////////////////////////
/// enqRequest is unguarded and user has to make sure to never exceed the capacity
/// deqRequest is guarded given that enq will never exceed capacity of pageBuffer
////////////////////////////////////////////////////////////////////////////////

module mkUGPageBuffer(PageBuffer#(numPages)) provisos (
   NumAlias#(TLog#(numPages),lgNumPages),
   NumEq#(TExp#(lgNumPages), numPages));
   
   Reg#(Bit#(TLog#(numPages))) initCnt <- mkReg(0);
   
   FIFO#(Bit#(TLog#(numPages))) freeBufIdQ <- mkSizedFIFO(valueOf(numPages)+1);
   
   // TLog#(8192/32 = 256) =
   RWBramCore#(Bit#(TAdd#(TLog#(numPages), 8)), Bit#(256)) buffer <- mkRWBramCore;
   
   Vector#(numPages, Reg#(Bit#(9))) enqPtrs <- replicateM(mkReg(0));
   Vector#(numPages, Reg#(Bit#(9))) deqPtrs <- replicateM(mkReg(0));
   
   function Bit#(TAdd#(TLog#(numPages), 8)) toBufferIdx(Bit#(lgNumPages) tag, Bit#(9) ptr);
      return {tag, ptr[7:0]};
   endfunction
   
   rule doInit if ( initCnt != -1 );
      initCnt <= initCnt + 1;
      freeBufIdQ.enq(initCnt);
   endrule
   
   FIFO#(Bit#(TLog#(numPages))) deqReqQ <- mkFIFO;
   rule processDeqReq;
      let tag = deqReqQ.first;
      // this is safe only since we know that we will not write exceed the capacity
      if ( enqPtrs[tag] != deqPtrs[tag] ) begin
         deqPtrs[tag] <= deqPtrs[tag] + 1;
         buffer.rdReq(toBufferIdx(tag, deqPtrs[tag]));
         deqReqQ.deq;
      end
   endrule
   
   method ActionValue#(Bit#(TLog#(numPages))) reserveBuf();
      freeBufIdQ.deq;
      return freeBufIdQ.first;
   endmethod
   
   method Action doneBuffer((Bit#(TLog#(numPages))) tag);
      freeBufIdQ.enq(tag);
   endmethod
   
   method Action enqRequest(Bit#(256) data, Bit#(TLog#(numPages)) tag);
      buffer.wrReq(toBufferIdx(tag, enqPtrs[tag]), data);
      // enq is unguarded since we know that we will not write exceed the capacity
      enqPtrs[tag] <= enqPtrs[tag] + 1;
      // $display("%m enqRequest tag = %d, enqPtr = %d", tag, enqPtrs[tag]);
   endmethod
   
   method Action deqRequest(Bit#(TLog#(numPages)) tag);
      deqReqQ.enq(tag);
   endmethod
   
   method ActionValue#(Bit#(256)) deqResponse;
      buffer.deqRdResp;
      return buffer.rdResp;
   endmethod
   
endmodule
