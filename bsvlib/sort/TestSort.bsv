import Bitonic::*;
import MergeSort::*;

import Vector::*;
import FIFO::*;
import GetPut::*;
import Pipe::*;
import Randomizable::*;

Bool descending = True;
typedef 16 ElemCnt;

module mkBitonicTest(Empty);
   Reg#(Bit#(32)) testCnt <- mkReg(0);
   Integer testLen = 10000;

   rule doTest;
      testCnt <= testCnt + 1;
      Vector#(ElemCnt, UInt#(32)) inV;
      for (Integer i = 0; i < valueOf(ElemCnt); i = i + 1) begin
         let v <- rand32();
         inV[i] = unpack(v);
      end
      
      let outV = bitonic_sort(inV, descending);
      
      $display("Seq[%d] Input  = ", testCnt, fshow(inV));
      $display("Seq[%d] Output = ", testCnt, fshow(outV));
      
      if ( !isSorted(outV, descending) || (fold(\+ ,inV) != fold(\+ ,outV)) ) begin
         $display("FAILED: BitonicSort");
         $finish;
      end
      
      if (testCnt + 1 == fromInteger(testLen)) begin
         $display("PASSED: BitonicSort");
         $finish;
      end
   endrule
endmodule

typedef 32 TotalCnt;

module mkStreamingMergeTest(Empty);
   Merge#(UInt#(32), 8, TotalCnt) merger <- mkStreamingMerge(descending);

   Integer testLen = 1000;
   
   Reg#(Bit#(32)) cycle <- mkReg(0);
   Reg#(Bit#(32)) prevCycle <- mkReg(0);   
   rule incrCycle;
      cycle <= cycle + 1;
   endrule
   
   Vector#(2, FIFO#(Vector#(TotalCnt, UInt#(32)))) inputQs <- replicateM(mkFIFO);
   
   for (Integer i = 0; i < 2; i = i + 1) begin
      Reg#(Bit#(32)) testCnt <- mkReg(0);

      
      Reg#(Bit#(32)) gear <- mkReg(0);
      
      Reg#(Vector#(TotalCnt, UInt#(32))) inBuf <- mkRegU;

      rule doGenInput if ( testCnt < fromInteger(testLen) );
         if ( gear+8 == fromInteger(valueOf(TotalCnt)) ) begin
            gear <= 0;
            testCnt <= testCnt + 1;
         end
         else begin
            gear <= gear + 8;
         end
         
         let in = inBuf;
         if ( gear == 0) begin
            Vector#(TotalCnt, UInt#(32)) inV;
            for (Integer i = 0; i < valueOf(TotalCnt); i = i + 1) begin
               let v <- rand32();
               inV[i] = unpack(v);
            end
            let sortedStream = bitonic_sort(inV, descending);
            in = sortedStream;
            inputQs[i].enq(sortedStream);
         end

         inBuf <= shiftOutFrom0(?, in, 8);

         merger.inPipes[i].enq(take(in));
      endrule
   end
   
   FIFO#(Vector#(TMul#(2,TotalCnt), UInt#(32))) expectedQ <- mkFIFO;
   
   rule genExpectedResult;
      function doGet(x)=x.get;
      let v <- mapM(doGet, map(toGet, inputQs));
      expectedQ.enq(bitonic_sort(concat(v), descending));
   endrule
      

   Reg#(Vector#(TMul#(TotalCnt,2), UInt#(32))) outBuf <- mkRegU;   
   Reg#(Bit#(32)) outGear <- mkReg(0);
   Reg#(Bit#(32)) resultCnt <- mkReg(0);
   
   rule doResult;
      merger.outPipe.deq;
      let merged = merger.outPipe.first;
      Vector#(TMul#(TotalCnt,2), UInt#(32)) resultV = drop(append(outBuf, merged));
      outBuf <= resultV;
      $display("(@%t)Merged Sequence = ", $time, fshow(merged));
      prevCycle <= cycle;
      
      if ( cycle - prevCycle != 1 && !(resultCnt == 0 && outGear == 0)) begin
         $display("FAIL: StreamingMerge not streaming");
         $finish();
      end
      
      if ( outGear+8 == fromInteger(2*valueOf(TotalCnt)) ) begin
         outGear <= 0;
         resultCnt <= resultCnt + 1;
         let expected <- toGet(expectedQ).get;
         if ( expected != resultV ) begin
            $display("FAILED: StreamingMerge result not sorted resultV vs expected");
            $display("result   = ",  fshow(resultV));
            $display("expected = ",  fshow(expected));
            $finish;
         end
         if ( resultCnt + 1 == fromInteger(testLen) ) begin
            $display("PASSED: StreamingMerge ");
            $finish;
         end
      end
      else begin
         outGear <= outGear + 8;
      end
   endrule
endmodule
