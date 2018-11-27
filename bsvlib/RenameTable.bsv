import RWBramCore::*;
import FIFO::*;

interface RenameTable#(numeric type numTags, type dataT);
   method ActionValue#(Bit#(TLog#(numTags))) writeEntry(dataT d);
   method Action readEntry(Bit#(TLog#(numTags)) tag);
   method ActionValue#(dataT) readResp;
   method Action invalidEntry(Bit#(TLog#(numTags)) tag);
endinterface


module mkRenameTable(RenameTable#(numTags, dataT)) provisos(
   NumAlias#(TExp#(TLog#(numTags)), numTags),
   Bits#(dataT, a__)
   );
   Reg#(Bit#(TLog#(numTags))) initCnt <- mkReg(0);
   Reg#(Bool) init <- mkReg(False);
   
   FIFO#(Bit#(TLog#(numTags))) freeTagQ <- mkSizedFIFO(valueOf(numTags));
   
   RWBramCore#(Bit#(TLog#(numTags)), dataT) tb <- mkRWBramCore;
   
   rule initialize (!init);
      $display("initCnt = %d", initCnt);
      initCnt <= initCnt + 1;
      freeTagQ.enq(initCnt);
      if (initCnt == fromInteger(valueOf(numTags) - 1))
         init <= True;
   endrule
                   
   
   method ActionValue#(Bit#(TLog#(numTags))) writeEntry(dataT d) if (init);
      let freeTag = freeTagQ.first;
      freeTagQ.deq;
      tb.wrReq(freeTag, d);
      return freeTag;
   endmethod
   
   method Action readEntry(Bit#(TLog#(numTags)) tag);
      tb.rdReq(tag);
   endmethod
   
   method ActionValue#(dataT) readResp;
      tb.deqRdResp;
      return tb.rdResp;
   endmethod
   
   method Action invalidEntry(Bit#(TLog#(numTags)) tag) if (init); 
      freeTagQ.enq(tag);
   endmethod   
endmodule
   
