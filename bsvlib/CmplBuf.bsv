import Pipe::*;
import Cntrs::*;
import Assert::*;
import Vector::*;
import RegFile::*;
import FIFOF::*;

interface CmplBuf#(numeric type n, type dtype);
   interface PipeOut#(Bit#(TLog#(n))) reserve;
   method Action complete(Bit#(TLog#(n)) token, dtype data);
   interface PipeOut#(dtype) drain;
endinterface


module mkCmplBuf(CmplBuf#(n, dtype)) provisos(
   Bits#(dtype, dSz),
   Alias#(Bit#(TLog#(n)), tokenT));
   
   RegFile#(tokenT, dtype) buff <- mkRegFile(0, fromInteger(valueOf(n)-1));
   Count#(UInt#(TLog#(TAdd#(n,1)))) freeTokens <- mkCount(fromInteger(valueOf(n)));
   
   Vector#(n, Array#(Reg#(Bool))) flag <- replicateM(mkCReg(2, False));
   Reg#(tokenT) head <- mkReg(0);
   Reg#(tokenT) tail <- mkReg(0);
   
   function Bool tokenReady();
      return !flag[head][0] && freeTokens > 0;
   endfunction

   function Bool drainReady();
      return flag[tail][0];
   endfunction

   
   interface PipeOut reserve;
      method Bool notEmpty;
         return tokenReady();
      endmethod
      method Bit#(TLog#(n)) first;
         return head;
      endmethod
      method Action deq if (tokenReady());
         head <= head == fromInteger(valueOf(n)-1) ? 0 :  head + 1;
         freeTokens.decr(1);
      endmethod
   endinterface
   
   method Action complete(Bit#(TLog#(n)) token, dtype data);
      // dynamicAssert(!flag[token][1], "complete slot must not be taken");
      buff.upd(token, data);
      flag[token][1] <= True;
   endmethod
   
   interface PipeOut drain;
      method Bool notEmpty = drainReady();
      method dtype first;
         return buff.sub(tail);
      endmethod
      method Action deq if (drainReady());
         // dynamicAssert(freeTokens < fromInteger(valueOf(n)), "drain_Only_When_Reserved"); 
         tail <= tail == fromInteger(valueOf(n)-1) ? 0 : tail + 1;
         freeTokens.incr(1);
         flag[tail][0] <= False;
      endmethod
   endinterface
endmodule
  
   
module mkCmplBufPP(CmplBuf#(n, dtype)) provisos(
   Bits#(dtype, dSz),
   Alias#(Bit#(TLog#(n)), tokenT));
   
   RegFile#(tokenT, dtype) buff <- mkRegFile(0, fromInteger(valueOf(n)-1));
   Count#(UInt#(TLog#(TAdd#(n,1)))) freeTokens <- mkCount(fromInteger(valueOf(n)));
   
   Vector#(n, Array#(Reg#(Bool))) flag <- replicateM(mkCReg(2, False));
   Reg#(tokenT) head <- mkReg(0);
   Reg#(tokenT) tail <- mkReg(0);
   
   function Bool tokenReady();
      return !flag[head][0] && freeTokens > 0;
   endfunction

   function Bool drainReady();
      return flag[tail][0];
   endfunction
   
   FIFOF#(tokenT) reserveQ <- mkFIFOF;
   
   rule doReserve if (tokenReady());
      head <= head == fromInteger(valueOf(n)-1) ? 0 :  head + 1;
      freeTokens.decr(1);
      reserveQ.enq(head);
   endrule
   
   interface PipeOut reserve = toPipeOut(reserveQ);
   
   method Action complete(Bit#(TLog#(n)) token, dtype data);
      // dynamicAssert(!flag[token][1], "complete slot must not be taken");
      buff.upd(token, data);
      flag[token][1] <= True;
   endmethod
   
   interface PipeOut drain;
      method Bool notEmpty = drainReady();
      method dtype first;
         return buff.sub(tail);
      endmethod
      method Action deq if (drainReady());
         // dynamicAssert(freeTokens < fromInteger(valueOf(n)), "drain_Only_When_Reserved"); 
         tail <= tail == fromInteger(valueOf(n)-1) ? 0 : tail + 1;
         freeTokens.incr(1);
         flag[tail][0] <= False;
      endmethod
   endinterface
endmodule
  
   
