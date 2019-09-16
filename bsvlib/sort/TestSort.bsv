import Bitonic::*;
import MergeSort::*;

import Vector::*;
import FIFO::*;
import GetPut::*;
import Pipe::*;
import Randomizable::*;
import BuildVector::*;

Bool descending = True;
typedef 8 VecSz;

module mkBitonicTest(Empty);
   Reg#(Bit#(32)) testCnt <- mkReg(0);
   Integer testLen = 10000;

   rule doTest;
      testCnt <= testCnt + 1;
      Vector#(VecSz, UInt#(32)) inV;
      for (Integer i = 0; i < valueOf(VecSz); i = i + 1) begin
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

typedef 32 SortedSz;

module mkStreamingMerge2Test(Empty);
   Merge2#(UInt#(32), VecSz, SortedSz) merger <- mkStreamingMerge2(descending);

   Integer testLen = 1000;
   Bit#(32) vecSz = fromInteger(valueOf(VecSz));
   
   Reg#(Bit#(32)) cycle <- mkReg(0);
   Reg#(Bit#(32)) prevCycle <- mkReg(0);   
   rule incrCycle;
      cycle <= cycle + 1;
   endrule
   
   Vector#(2, FIFO#(Vector#(SortedSz, UInt#(32)))) inputQs <- replicateM(mkFIFO);
   
   for (Integer i = 0; i < 2; i = i + 1) begin
      Reg#(Bit#(32)) testCnt <- mkReg(0);

      
      Reg#(Bit#(32)) gear <- mkReg(0);
      
      Reg#(Vector#(SortedSz, UInt#(32))) inBuf <- mkRegU;

      rule doGenInput if ( testCnt < fromInteger(testLen) );
         if ( gear+vecSz == fromInteger(valueOf(SortedSz)) ) begin
            gear <= 0;
            testCnt <= testCnt + 1;
         end
         else begin
            gear <= gear + vecSz;
         end
         
         let in = inBuf;
         if ( gear == 0) begin
            Vector#(SortedSz, UInt#(32)) inV;
            for (Integer i = 0; i < valueOf(SortedSz); i = i + 1) begin
               let v <- rand32();
               inV[i] = unpack(v);
            end
            let sortedStream = bitonic_sort(inV, descending);
            in = sortedStream;
            inputQs[i].enq(sortedStream);
         end

         inBuf <= shiftOutFrom0(?, in, valueOf(VecSz));

         merger.inPipes[i].enq(take(in));
      endrule
   end
   
   FIFO#(Vector#(TMul#(2,SortedSz), UInt#(32))) expectedQ <- mkFIFO;
   
   rule genExpectedResult;
      function doGet(x)=x.get;
      let v <- mapM(doGet, map(toGet, inputQs));
      expectedQ.enq(bitonic_sort(concat(v), descending));
   endrule
      

   Reg#(Vector#(TMul#(SortedSz,2), UInt#(32))) outBuf <- mkRegU;   
   Reg#(Bit#(32)) outGear <- mkReg(0);
   Reg#(Bit#(32)) resultCnt <- mkReg(0);
   
   rule doResult;
      merger.outPipe.deq;
      let merged = merger.outPipe.first;
      Vector#(TMul#(SortedSz,2), UInt#(32)) resultV = drop(append(outBuf, merged));
      outBuf <= resultV;
      $display("(@%t)Merged Sequence = ", $time, fshow(merged));
      prevCycle <= cycle;
      
      if ( cycle - prevCycle != 1 && !(resultCnt == 0 && outGear == 0)) begin
         $display("FAIL: StreamingMerge not streaming");
         $finish();
      end
      
      if ( outGear+vecSz == fromInteger(2*valueOf(SortedSz)) ) begin
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
         outGear <= outGear + vecSz;
      end
   endrule
endmodule

// typedef TDiv#(8192, 8) TotalElms;
typedef TMul#(8, VecSz) TotalElms;

module mkStreamingMergeSortTest(Empty);
   MergeSort#(UInt#(32), VecSz, TotalElms) sorter <- mkStreamingMergeSort(descending);
   
   Reg#(Bit#(32)) inCnt <- mkReg(0);
   
   Integer totalElms = valueOf(TotalElms);
   Integer vecSz = valueOf(VecSz);

   Reg#(Bit#(32)) cycle <- mkReg(0);
   Reg#(Bit#(32)) prevCycle <- mkReg(0);
   
   Reg#(Bit#(32)) testCntIn <- mkReg(0);
   Reg#(Bit#(32)) testCntOut <- mkReg(0);
   
   Integer testLen = 1000;
   
   rule incrCycle;
      cycle <= cycle + 1;
   endrule
   
   rule genInput if ( testCntIn < fromInteger(testLen) );
      if ( inCnt + fromInteger(vecSz) >= fromInteger(totalElms) ) begin              
         inCnt <= 0;
         testCntIn <= testCntIn + 1;
      end
      else begin
         inCnt <= inCnt + fromInteger(vecSz);
      end
      
      Vector#(VecSz, UInt#(32)) inV;
      for (Integer i = 0; i < valueOf(VecSz); i = i + 1) begin
         let v <- rand32();
         inV[i] = unpack(v);
      end
      sorter.inPipe.enq(inV);
   endrule
   
   Reg#(UInt#(32)) prevMax <- mkReg(minBound);
   
   Reg#(Bit#(32)) outCnt <- mkReg(0);
   
   rule getOutput;
      let d = sorter.outPipe.first;
      sorter.outPipe.deq;


      $display("Sort Result [%d] [@%d] = ", outCnt, cycle, fshow(d));
      
      prevCycle <= cycle;
      if ( cycle - prevCycle != 1 && !(outCnt == 0&&testCntOut==0)) begin
         $display("FAIL: StreamingMergeSort not streaming");
         $finish();
      end

      if ( !isSorted(d, descending) || !isSorted(vec(prevMax, head(d)), descending)) begin
         $display("FAILED: StreamingMergeSort result not sorted");
         $finish();
      end

      if (outCnt + fromInteger(vecSz) >= fromInteger(totalElms) ) begin
         outCnt <= 0;
         prevMax <= minBound;
         testCntOut <= testCntOut + 1;
         if ( testCntOut + 1 == fromInteger(testLen) ) begin
            $display("PASSED: StreamingMergeSort");
            $finish();
         end
      end
      else begin
         outCnt <= outCnt + fromInteger(vecSz);
         prevMax <= last(d);
      end
   endrule
endmodule
