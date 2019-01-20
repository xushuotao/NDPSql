import RWBramCore::*;
import FIFO::*;
import BRAM::*;

`define USE_BRAM2PORT


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
   
   `ifndef USE_BRAM2PORT
   RWBramCore#(Bit#(TLog#(numTags)), dataT) tb <- mkRWBramCore;
   `else
   BRAM2Port#(Bit#(TLog#(numTags)), dataT) tb <- mkBRAM2Server(defaultValue); 
   `endif
   
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
      `ifndef USE_BRAM2PORT
      tb.wrReq(freeTag, d);
      `else
      tb.portA.request.put(BRAMRequest{write:True, responseOnWrite:False, address:freeTag, datain:d});
      `endif
      return freeTag;
   endmethod
   
   method Action readEntry(Bit#(TLog#(numTags)) tag);
      `ifndef USE_BRAM2PORT
      tb.rdReq(tag);
      `else
      tb.portB.request.put(BRAMRequest{write:False, responseOnWrite:False, address:tag, datain:?});
      `endif
   endmethod

   method ActionValue#(dataT) readResp;
      `ifndef USE_BRAM2PORT   
      tb.deqRdResp;
      return tb.rdResp;
      `else
      let v <- tb.portB.response.get;
      return v;
      `endif
   endmethod
   
   method Action invalidEntry(Bit#(TLog#(numTags)) tag) if (init); 
      freeTagQ.enq(tag);
   endmethod   
endmodule
   
