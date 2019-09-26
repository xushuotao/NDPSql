import Bitonic::*;
import MergeSort::*;
import MergeSortVar::*;
import MergeSortFold::*;

import Vector::*;
import FIFO::*;
import GetPut::*;
import Pipe::*;
import Randomizable::*;
import BuildVector::*;
import Assert::*;

Bool descending = True;
typedef 16 VecSz;

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

   Integer testLen = 10;
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
         $display("FAIL: StreamingMerge2 not streaming");
         $finish();
      end
      
      if ( outGear+vecSz == fromInteger(2*valueOf(SortedSz)) ) begin
         outGear <= 0;
         resultCnt <= resultCnt + 1;
         let expected <- toGet(expectedQ).get;
         if ( expected != resultV ) begin
            $display("FAILED: StreamingMerge2 result not sorted resultV vs expected");
            $display("result   = ",  fshow(resultV));
            $display("expected = ",  fshow(expected));
            $finish;
         end
         if ( resultCnt + 1 == fromInteger(testLen) ) begin
            $display("PASSED: StreamingMerge2 ");
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
   
   Reg#(UInt#(32)) prevMax <- mkReg(descending?minBound:maxBound);
   
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
         prevMax <= descending?minBound:maxBound;
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

typedef 32 MaxBeats;
typedef TMul#(VecSz,MaxBeats) MaxSz;

import "BDPI" function Action genSortedSeq0(UInt#(32) size, Bool descending);
// import "BDPI" function UInt#(32) getNextData0();
import "BDPI" function UInt#(32) getNextData0(UInt#(32) size,Bool descending, UInt#(32) offset, Bit#(32) gear);

import "BDPI" function Action genSortedSeq1(UInt#(32) size, Bool descending);
// import "BDPI" function UInt#(32) getNextData1();
import "BDPI" function UInt#(32) getNextData1(UInt#(32) size,Bool descending, UInt#(32) offset, Bit#(32) gear);
                 

module mkStreamingMerge2VarTest(Empty);
   Merge2Var#(UInt#(32), VecSz) merger <- mkStreamingMerge2Var(descending, 0, 0);

   Integer testLen = 1000;
   Bit#(32) vecSz = fromInteger(valueOf(VecSz));
   
   Reg#(Bit#(32)) cycle <- mkReg(0);
   Reg#(Bit#(32)) prevCycle <- mkReg(0);   
   rule incrCycle;
      cycle <= cycle + 1;
   endrule
   
   Vector#(2, FIFO#(UInt#(128))) sumQs <- replicateM(mkFIFO);
   
   for (Integer i = 0; i < 2; i = i + 1) begin
      Reg#(Bit#(32)) testCnt <- mkReg(0);

      
      Reg#(Bit#(32)) gear <- mkReg(0);
      
      Reg#(Vector#(MaxSz, UInt#(32))) inBuf <- mkRegU;
      Reg#(UInt#(128)) sum <- mkReg(0);
      
      Reg#(Bit#(32)) sortedSz <- mkReg(0);
      
      Reg#(UInt#(32)) prevMaxIn <- mkReg(descending?minBound:maxBound);
      
      function genSortedSeq(x,y) = (i==0)?genSortedSeq0(x,y):genSortedSeq1(x,y);
      // function getNextData(x,y,z) = (i==0)?getNextData0(x,y,z):getNextData1(x,y,z);
      function getNextData(x,y,z,w) = (i==0)?getNextData0(x,y,z,w):getNextData1(x,y,z,w);
      // function getNextData() = (i==0)?getNextData0():getNextData1();

      rule doGenInput if ( testCnt < fromInteger(testLen) );
         let frameSz = sortedSz;
         if ( gear == 0) begin
            frameSz <- rand32();
            frameSz=frameSz%fromInteger(valueOf(MaxBeats))+1;
         end
         sortedSz <= frameSz;
         
         if ( gear+1 == frameSz ) begin
            gear <= 0;
            testCnt <= testCnt + 1;
         end
         else begin
            gear <= gear + 1;
         end
         

         


         if ( gear == 0 ) begin 
            $display("Merge inStream-%0d [%d], frameSz = %d", i, testCnt, frameSz);
            merger.inStreams[i].lenChannel.enq(unpack(frameSz));
         end
         
         
         
         // if ( gear == 0) begin
         //    genSortedSeq(unpack(frameSz*vecSz), !descending);
         // end
         
         Vector#(VecSz, UInt#(32)) beatIn = ?;
         for (Integer j = 0; j < valueOf(VecSz); j = j + 1 )begin
            beatIn[j] = getNextData(unpack(frameSz*vecSz), !descending, fromInteger(j), gear*vecSz);
         end
         
         $display("Merge inStream-%0d [%d] data = ", i, gear, fshow(beatIn));         
         dynamicAssert(isSorted(beatIn, descending),"input vec not sorted internally");
         dynamicAssert(isSorted(vec(prevMaxIn, head(beatIn)), descending),"input vec not sorted externally");

         
         
         merger.inStreams[i].dataChannel.enq(beatIn);
         
         if ( gear+1 == frameSz )begin
            prevMaxIn <= descending?minBound:maxBound;
            sum <= 0;
            sumQs[i].enq(sum+fold(\+ , map(zeroExtend, beatIn)));
         end
         else begin
            prevMaxIn <= last(beatIn);
            sum <= sum+fold(\+ , map(zeroExtend, beatIn));
         end
      endrule
   end
   
  

   Reg#(Vector#(TMul#(SortedSz,2), UInt#(32))) outBuf <- mkRegU;   
   Reg#(Bit#(32)) outGear <- mkReg(0);
   Reg#(Bit#(32)) resultCnt <- mkReg(0);
   
   Reg#(UInt#(128)) accumulate <- mkReg(0);
   
   Reg#(UInt#(32)) prevMax <- mkReg(descending?minBound:maxBound);
   
   rule doResult;
      let frameSz = pack(merger.outStream.lenChannel.first);
      
      merger.outStream.dataChannel.deq;
      let merged = merger.outStream.dataChannel.first;
      Vector#(TMul#(SortedSz,2), UInt#(32)) resultV = drop(append(outBuf, merged));
      outBuf <= resultV;

      prevCycle <= cycle;
      
      if ( cycle - prevCycle != 1 && !(resultCnt == 0 && outGear == 0)) begin
         $display("FAIL: StreamingMerge2Var not streaming");
         $finish();
      end
      
      if ( outGear == 0 ) begin 
         $display("Merge outStream resultCnt = %d, frameSz = %d", resultCnt, frameSz);
      end
      $display("(@%t)Merged Sequence [beat=%d] = ", $time, outGear, fshow(merged));
      
      if ( !isSorted(merged, descending) ) begin
         $display("FAILED: StreamingMergeSort2Var result not sorted internally");
         $finish();
      end
      
      if ( !isSorted(vec(prevMax, head(merged)), descending) ) begin
         $display("FAILED: StreamingMergeSort2Var result not sorted externally");
         $finish();
      end


      
      if ( outGear+1 == frameSz ) begin
         accumulate <= 0;
         merger.outStream.lenChannel.deq;
         outGear <= 0;
         resultCnt <= resultCnt + 1;
         function doGet(x)=x.get;
         let sums <- mapM(doGet, map(toGet, sumQs));
         let expected = fold(\+ , sums);
         let result = accumulate + fold(\+ ,map(zeroExtend, merged));
         prevMax <= descending?minBound:maxBound;
         
         if ( expected !=  result) begin
            $display("FAILED: StreamingMerge2Var result sum not as expected");
            $display("result   = %d",  result);
            $display("expected = %d", expected);
            $finish;
         end
         else begin
            $display("TestPassed for testCnt = %d",resultCnt);
         end
         if ( resultCnt + 1 == fromInteger(testLen) ) begin
            $display("PASSED: StreamingMerge2Var ");
            $finish;
         end
      end
      else begin
         accumulate <= accumulate + fold(\+ ,map(zeroExtend, merged));
         outGear <= outGear + 1;
         prevMax <= last(merged);
      end
   endrule
endmodule

                 
typedef TDiv#(8192, 4) PageSz;
typedef 64 NumPages;                 
typedef 4 FanIn;                 
                 
module mkMergeNFoldBRAMTest(Empty);
   MergeNFold#(UInt#(32), VecSz, PageSz, NumPages, FanIn) merger <- mkMergeNFoldBRAM(descending);

   Integer testLen = 100;
   Bit#(32) vecSz = fromInteger(valueOf(VecSz));
   
   Reg#(Bit#(32)) cycle <- mkReg(0);
   Reg#(Bit#(32)) prevCycle <- mkReg(0);   
   rule incrCycle;
      cycle <= cycle + 1;
   endrule
   
   FIFO#(UInt#(128)) sumQ <- mkFIFO;
   
   
   Reg#(Bit#(32)) testCnt <- mkReg(0);
      
   Reg#(Vector#(MaxSz, UInt#(32))) inBuf <- mkRegU;
   Reg#(UInt#(128)) sum <- mkReg(0);
      
      
   Reg#(UInt#(32)) prevMaxIn <- mkReg(descending?minBound:maxBound);
      
   // function genSortedSeq(x,y) = genSortedSeq0(x,y);
   function getNextData(x,y,z,w) = getNextData0(x,y,z,w);
   
   Bit#(32) sortedBeats = fromInteger(valueOf(PageSz)/valueOf(VecSz));
   Reg#(Bit#(32)) pageCnt <- mkReg(0);
   Reg#(Bit#(32)) beatCnt <- mkReg(0);

   rule doGenInput if ( testCnt < fromInteger(testLen) );
      if ( beatCnt+1 == sortedBeats ) begin
         beatCnt <= 0;
         if ( pageCnt + 1 == fromInteger(valueOf(NumPages))) begin
            pageCnt <= 0;
            testCnt <= testCnt + 1;
         end
         else begin
            pageCnt <= pageCnt + 1;
         end
      end
      else begin
         beatCnt <= beatCnt + 1;
      end
      
      Vector#(VecSz, UInt#(32)) beatIn = ?;
      for (Integer j = 0; j < valueOf(VecSz); j = j + 1 )begin
         beatIn[j] = getNextData(unpack(sortedBeats*vecSz)// *fromInteger(valueOf(NumPages))
            , !descending, fromInteger(j), beatCnt*vecSz);
      end
         
      $display("Merge inStream [%d][%d][%d] data = ", testCnt, pageCnt, beatCnt, fshow(beatIn));         
      dynamicAssert(isSorted(beatIn, descending),"input vec not sorted internally");
      dynamicAssert(isSorted(vec(prevMaxIn, head(beatIn)), descending),"input vec not sorted externally");
         
      merger.inPipe.enq(beatIn);
         
      if ( beatCnt+1 == sortedBeats ) begin
         prevMaxIn <= descending?minBound:maxBound;
         if ( pageCnt + 1 == fromInteger(valueOf(NumPages))) begin
            sum <= 0;
            sumQ.enq(sum+fold(\+ , map(zeroExtend, beatIn)));
         end
         else begin
            sum <= sum+fold(\+ , map(zeroExtend, beatIn));
         end
      end
      else begin
         prevMaxIn <= last(beatIn);
         sum <= sum+fold(\+ , map(zeroExtend, beatIn));
      end
   endrule

   
  

   // Reg#(Vector#(TMul#(SortedSz,2), UInt#(32))) outBuf <- mkRegU;   
   Reg#(Bit#(32)) outBeat <- mkReg(0);
   Reg#(Bit#(32)) resultCnt <- mkReg(0);
   
   Reg#(UInt#(128)) accumulate <- mkReg(0);
   
   Reg#(UInt#(32)) prevMax <- mkReg(descending?minBound:maxBound);
   
   rule doResult;
       
      merger.outPipe.deq;
      let merged = merger.outPipe.first;

      prevCycle <= cycle;
      
      if ( cycle - prevCycle != 1 && !(outBeat == 0)) begin
         $display("FAIL: StreamingMerge2Var not streaming for a specific merge");
         // $finish();
      end
      
      $display("(@%t)Merged Sequence [%d][%d] = ", $time, resultCnt, outBeat, fshow(merged));
      
      if ( !isSorted(merged, descending) ) begin
         $display("FAILED: StreamingMergeSort2Var result not sorted internally");
         $finish();
      end
      
      if ( !isSorted(vec(prevMax, head(merged)), descending) ) begin
         $display("FAILED: StreamingMergeSort2Var result not sorted externally");
         $finish();
      end

      
      if ( outBeat+1 == sortedBeats*fromInteger(valueOf(NumPages)) ) begin
         accumulate <= 0;
         outBeat <= 0;
         resultCnt <= resultCnt + 1;
         function doGet(x)=x.get;
         let expected <- toGet(sumQ).get;
         let result = accumulate + fold(\+ ,map(zeroExtend, merged));
         prevMax <= descending?minBound:maxBound;
         
         if ( expected !=  result) begin
            $display("FAILED: StreamingMerge2Var result sum not as expected");
            $display("result   = %d",  result);
            $display("expected = %d", expected);
            $finish;
         end
         else begin
            $display("TestPassed for testCnt = %d",resultCnt);
         end
         if ( resultCnt + 1 == fromInteger(testLen) ) begin
            $display("PASSED: StreamingMerge2Var ");
            $display("Throughput cycles for beat = (%d/%d) %d, log_fanIn_N = %d", cycle, sortedBeats*fromInteger(valueOf(NumPages)*testLen), cycle/(sortedBeats*fromInteger(valueOf(NumPages)*testLen)), log2(valueOf(NumPages))/log2(valueOf(FanIn)));
            $finish;
         end
      end
      else begin
         accumulate <= accumulate + fold(\+ ,map(zeroExtend, merged));
         outBeat <= outBeat + 1;
         prevMax <= last(merged);
      end
   endrule
endmodule

                 
