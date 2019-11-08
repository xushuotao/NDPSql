import Vector::*;
import List::*;
import ConfigReg::*;

interface DelayPipe#(numeric type n, type dtype);
   method Action enq(dtype d);
   method Bool notEmpty;
   method dtype first;
   method Action deq;
endinterface

// interface DelayPipe#(numeric type n, type dtype);
//    method Action enq(dtype d);
//    method Bool notEmpty;
//    method dtype first;
//    method Action deq;
// endinterface


module mkDelayPipe(DelayPipe#(n, dtype)) provisos (Bits#(dtype, dSz), Add#(1, a__, n));
   Vector#(n, Reg#(Maybe#(dtype))) dataReg <- replicateM(mkReg(tagged Invalid));
   
   RWire#(dtype) inWire <- mkRWire;
   rule doFlow;
      dataReg[0] <= inWire.wget;
      for (Integer i = 1; i < valueOf(n); i = i + 1) begin
         dataReg[i] <= dataReg[i-1];
      end
   endrule
   
   method Action enq(dtype d);
      inWire.wset(d);
   endmethod
   method Bool notEmpty = isValid(last(dataReg)._read);
   method dtype first = fromMaybe(?, last(dataReg)._read);
   method Action deq = noAction;
endmodule

interface DelayReg#(type dtype);
   method Action _write(dtype d);
   method Maybe#(dtype) _read;
endinterface


module mkDelayReg#(Integer depth)(DelayReg#(dtype)) provisos(Bits#(dtype, dSz));
   // List#(Reg#(data)) delayRegA <- replicateM(pipeline_depth, mkRegU);

   List#(Reg#(Maybe#(dtype))) ppReg <- List::replicateM(depth, mkConfigReg(tagged Invalid));
   RWire#(dtype) inWire <- mkRWire;
   rule doFlow;
      ppReg[0] <= inWire.wget;
      for (Integer i = 1; i < depth; i = i + 1) begin
         ppReg[i] <= ppReg[i-1];
      end
   endrule
   
   method Action _write(dtype d);
      inWire.wset(d);
   endmethod
   
   method Maybe#(dtype) _read = List::last(ppReg)._read;
endmodule

