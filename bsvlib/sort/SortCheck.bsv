import FIFOF::*;
import Pipe::*;
import Vector::*;
import Bitonic::*;
import GetPut::*;
import BuildVector::*;

interface SortCheck#(numeric type vSz, type dType);
   method Action start(Bit#(32) totalIter);
   method Tuple2#(Bit#(32), Bit#(32)) status;
   interface PipeIn#(Vector#(vSz, dType)) inPipe;
   method ActionValue#(Tuple2#(Bit#(64), Bit#(64))) checkDone;
   method ActionValue#(Bit#(TAdd#(TLog#(vSz),128))) getSum;
endinterface

module mkSortCheck#(Integer totalElms, Bool ascending)(SortCheck#(vSz, dType)) provisos(
   Bits#(dType, dSz), 
   Ord#(dType), 
   Bounded#(dType),
   Add#(2, a__, vSz), 
   Add#(1, b__, vSz),
   Add#(c__, dSz, 128),
   FShow#(dType));
   Reg#(dType) prevMax <- mkReg(ascending?minBound:maxBound);
   
   Reg#(Bit#(32)) iterCnt <- mkReg(0);
   Reg#(Bit#(32)) elemCnt <- mkReg(0);
   
   Reg#(Bit#(64)) internalUnsortedCnt <- mkReg(0);
   Reg#(Bit#(64)) externalUnsortedCnt <- mkReg(0);
   // $display("Sort Result [%d] [@%d] = ", elemCnt, cycleCnt, fshow(d));
   
   Reg#(Bit#(TAdd#(TLog#(vSz),128))) sumReg <- mkReg(0);
   FIFOF#(Bit#(TAdd#(TLog#(vSz),128))) sumQ <- mkFIFOF;
      
   Vector#(vSz, FIFOF#(Tuple3#(Bool, Bit#(TAdd#(TLog#(vSz),dSz)), Vector#(vSz, dType)))) pipes <- replicateM(mkFIFOF);
   FIFOF#(Tuple2#(Bit#(64), Bit#(64))) resultQ <- mkFIFOF;
   
   for (Integer i = 0; i < valueOf(vSz)-1; i = i + 1) begin
      rule doCheckInter;
         let {sorted, sum, d} = pipes[i].first;
         pipes[i].deq;
         sorted = sorted && isSorted(vec(d[i],d[i+1]), ascending);
         sum = sum + zeroExtend(pack(d[i+1]));
         pipes[i+1].enq(tuple3(sorted, sum, d));
      endrule
   end
   
   rule checkOutput if ( iterCnt > 0);
      let {intSorted, sum, d} = last(pipes).first; 
      last(pipes).deq;
      
      if (!intSorted ) internalUnsortedCnt <= internalUnsortedCnt + 1;
      if (!isSorted(vec(prevMax, head(d)), ascending)) externalUnsortedCnt <= externalUnsortedCnt + 1;
      
      let l = False;
      
      if (elemCnt + fromInteger(valueOf(vSz)) >= fromInteger(totalElms) ) begin
         elemCnt <= 0;
         prevMax <= ascending?minBound:maxBound;
         iterCnt <= iterCnt - 1;
         if ( iterCnt == 1) begin
            l = True;
            resultQ.enq(tuple2(internalUnsortedCnt, externalUnsortedCnt));
         end
      end
      else begin
         elemCnt <= elemCnt + fromInteger(valueOf(vSz));
         prevMax <= last(d);
      end
      
      if ( l ) begin
         sumReg <= 0;
         sumQ.enq(sumReg + zeroExtend(sum));
      end
      else begin
         sumReg <= sumReg + zeroExtend(sum);
      end
   endrule
   
   interface PipeIn inPipe;
      method Action enq(Vector#(vSz, dType) v);
         $display("%t ", $time, fshow(v));
         pipes[0].enq(tuple3(True, zeroExtend(pack(v[0])), v));
      endmethod
      method Bool notFull = pipes[0].notFull;
   endinterface
   
   method Action start(Bit#(32) totalIter) if (iterCnt == 0);
      iterCnt <= totalIter;
      internalUnsortedCnt <= 0;
      externalUnsortedCnt <= 0;
   endmethod
   
   method Tuple2#(Bit#(32), Bit#(32)) status;
      return tuple2(iterCnt, elemCnt);
   endmethod
   
   method ActionValue#(Tuple2#(Bit#(64), Bit#(64))) checkDone = toGet(resultQ).get;
   method ActionValue#(Bit#(TAdd#(TLog#(vSz),128))) getSum = toGet(sumQ).get;

endmodule
   


