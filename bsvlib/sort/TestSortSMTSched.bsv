import Bitonic::*;
// import MergeSort::*;
// import MergeSortVar::*;
// import MergeSortFold::*;
import SorterTypes::*;
import MergerSchedulerTypes::*;
import MergerScheduler::*;
import MergerSMTSched::*;
import MergeSortSMTSched::*;


import DRAMMergerSMTSched::*;
import DDR4Common::*;
import DDR4Controller::*;
import DRAMControllerTypes::*;
import DRAMController::*;
import DDR4Sim::*;
import Connectable::*;
import DRAMMux::*;


import ClientServer::*;
import DelayPipe::*;

import Counter::*;

import Vector::*;
import FIFO::*;
import FIFOF::*;
import GetPut::*;
import Pipe::*;
import Randomizable::*;
import BuildVector::*;
import Assert::*;

// import Randomizable::*;

Bool ascending = True;
typedef 16 VecSz;

function Bit#(256) f_bitonic_sort(Bit#(256) in);
   Vector#(8, Bit#(32)) inV = unpack(in);
   return pack(bitonic_sort(inV, ascending));
endfunction

function Bit#(32) f_sort_bitonic(Bit#(32) in);
   Vector#(8, Bit#(4)) inV = unpack(in);
   return pack(sort_bitonic(inV, ascending));
endfunction
   

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
      
      let outV = bitonic_sort(inV, ascending);
      
      $display("Seq[%d] Input  = ", testCnt, fshow(inV));
      $display("Seq[%d] Output = ", testCnt, fshow(outV));
      
      if ( !isSorted(outV, ascending) || (fold(\+ ,inV) != fold(\+ ,outV)) ) begin
         $display("FAILED: BitonicSort");
         $finish;
      end
      
      if (testCnt + 1 == fromInteger(testLen)) begin
         $display("PASSED: BitonicSort");
         $finish;
      end
   endrule
endmodule

module mkBitonicPipelinedTest(Empty);
   Reg#(Bit#(32)) testCnt <- mkReg(0);
   Reg#(Bit#(32)) testCnt_out <- mkReg(0);
   Integer testLen = 10000;
   
   StreamNode#(VecSz, UInt#(32)) sorter <- mkBitonicSort(ascending);
   
   FIFO#(Vector#(VecSz, UInt#(32))) inQ <- mkSizedFIFO(128);

   rule doEnqTest if ( testCnt < fromInteger(testLen) );
      testCnt <= testCnt + 1;
      Vector#(VecSz, UInt#(32)) inV;
      for (Integer i = 0; i < valueOf(VecSz); i = i + 1) begin
         let v <- rand32();
         inV[i] = unpack(v);
      end
      
      sorter.inPipe.enq(inV);
      inQ.enq(inV);     
      $display("(@%t)Seq[%d] Input  = ", $time, testCnt, fshow(inV));

      
   endrule
   
   rule doDeqTest;
      testCnt_out <= testCnt_out + 1;
      
      let inV <- toGet(inQ).get();
      let outV = sorter.outPipe.first;
      sorter.outPipe.deq;
      
      $display("(@%t)Seq[%d] Output = ", $time, testCnt_out, fshow(outV));
      if ( !isSorted(outV, ascending) ) begin
         $display("FAILED: BitonicSort not sorted");
         $finish;
      end
      
      if (fold(\+ ,inV) != fold(\+ ,outV))  begin
         $display("FAILED: BitonicSort Sum not match");
         $finish;
      end
      
      if (testCnt_out + 1 == fromInteger(testLen)) begin
         $display("PASSED: BitonicSort");
         $finish;
      end

   endrule
endmodule

import "BDPI" function Action genSortedSeq0(UInt#(32) size, Bool ascending);
// import "BDPI" function UInt#(32) getNextData0();
import "BDPI" function UInt#(32) getNextData0(UInt#(32) size,Bool ascending, UInt#(32) offset, Bit#(32) gear);

typedef 64 SortedSz;

module mkMergeSMT2SchedTest(Empty);
   MergeNSMTSched#(UInt#(32), VecSz,1) merger <- mkMergeNSMTSched(ascending,0);

   Integer testLen = 100;
   Bit#(32) vecSz = fromInteger(valueOf(VecSz));
   
   Reg#(Bit#(32)) cycle <- mkReg(0);
   Reg#(Bit#(32)) prevCycle <- mkReg(0);   
   rule incrCycle;
      cycle <= cycle + 1;
   endrule
   
   Vector#(2, FIFO#(Vector#(SortedSz, UInt#(32)))) inputQs <- replicateM(mkFIFO);
   
   Vector#(2, FIFO#(SortedPacket#(VecSz, UInt#(32)))) delayQs <- replicateM(mkSizedFIFO(128)); 
   
   FIFO#(UInt#(1)) selQ <- mkFIFO;
   
   for (Integer i = 0; i < 2; i = i + 1) begin
      Reg#(Bit#(32)) testCnt <- mkReg(0);

      
      Reg#(Bit#(32)) gear <- mkReg(0);
      
      Reg#(Vector#(SortedSz, UInt#(32))) inBuf <- mkRegU;
      

      rule doGenInput if ( testCnt < fromInteger(testLen) );//&& merger.in.ready[0][i].notEmpty);
         if ( gear+vecSz == fromInteger(valueOf(SortedSz)) ) begin
            gear <= 0;
            testCnt <= testCnt + 1;
         end
         else begin
            gear <= gear + vecSz;
         end
         $display("(@%t)Merging[%d] Sequence = ", $time, i);
         let in = inBuf;
         if ( gear == 0) begin
            Vector#(SortedSz, UInt#(32)) inV;
            for (Integer i = 0; i < valueOf(SortedSz); i = i + 1) begin
               let v <- rand32();
               inV[i] = unpack(v);
            end
            let sortedStream = bitonic_sort(inV, ascending);
            in = sortedStream;
            inputQs[i].enq(sortedStream);
         end

         inBuf <= shiftOutFrom0(?, in, valueOf(VecSz));
         // merger.in.ready[0][i].deq;
         Vector#(VecSz, UInt#(32)) indata = take(in);
         merger.in.scheduleReq.enq(TaggedSchedReq{tag: fromInteger(i), topItem:last(indata),last:gear+vecSz == fromInteger(valueOf(SortedSz))});
         delayQs[i].enq(SortedPacket{first: gear==0, 
                                     last: gear+vecSz == fromInteger(valueOf(SortedSz)),
                                     d: indata});
         // selQ.enq(fromInteger(i));
      endrule
            
   end
   
   rule issueReq if ( merger.in.scheduleResp.notEmpty);
      merger.in.scheduleResp.deq;
      let tag = merger.in.scheduleResp.first;
      let d <- toGet(delayQs[tag]).get;
      merger.in.dataChannel.enq(TaggedSortedPacket{tag:?, packet:d});
   endrule
      

   
   FIFO#(Vector#(TMul#(2,SortedSz), UInt#(32))) expectedQ <- mkFIFO;
   
   rule genExpectedResult;
      function doGet(x)=x.get;
      let v <- mapM(doGet, map(toGet, inputQs));
      expectedQ.enq(bitonic_sort(concat(v), ascending));
   endrule
      

   Reg#(Vector#(TMul#(SortedSz,2), UInt#(32))) outBuf <- mkRegU;   
   Reg#(Bit#(32)) outGear <- mkReg(0);
   Reg#(Bit#(32)) resultCnt <- mkReg(0);
   
   FIFO#(void) resultPull <- mkFIFO;

   DelayPipe#(1, void) delayReq <- mkDelayPipe;
   
   Counter#(32) outPending <- mkCounter(0);
   
   FIFO#(TaggedSortedPacket#(1, VecSz, UInt#(32))) outQ <- mkSizedFIFO(5);
   
   rule doReceivScheReq if (outPending.value < 4);
      let d = merger.out.scheduleReq.first;
      merger.out.scheduleReq.deq;
      // delayReq.enq(?);
      merger.out.server.request.put(?);
      outPending.up;     
   endrule
   
   // rule pullResult if ( delayReq.notEmpty);
   //    merger.out.server.request.put(?);
   // endrule
   
   rule enqResult;
      let merged <- merger.out.server.response.get;
      outQ.enq(merged);
   endrule
   
   rule doResult;
      let coin <- rand32();
      if ( coin % 3 != 0 ) begin
      let merged <- toGet(outQ).get;
         outPending.down;
      // let merged = merger.outPipe.first;
      Vector#(TMul#(SortedSz,2), UInt#(32)) resultV = drop(append(outBuf, merged.packet.d));
      outBuf <= resultV;
      $display("(@%t)Merged Sequence = ", $time, fshow(merged));
      prevCycle <= cycle;
      
      if ( merged.packet.first) dynamicAssert(outGear == 0, "first flag not produced correctly");
      if (merged.packet.last) dynamicAssert(outGear+vecSz == fromInteger(2*valueOf(SortedSz)), "last flag not produced correctly");
      
      if ( cycle - prevCycle != 1 && !(resultCnt == 0 && outGear == 0)) begin
         $display("FAIL: StreamingMerge2 not streaming");
         // $finish();
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
         else begin
            $display("TestCnt %d: Passed", resultCnt);
         end
         if ( resultCnt + 1 == fromInteger(testLen) ) begin
            $display("PASSED: MergeSMT2Sched ");
            $finish;
         end
      end
      else begin
         outGear <= outGear + vecSz;
      end
      end
   endrule
endmodule


// typedef TDiv#(8192, 8) TotalElms;
// typedef TMul#(1024, VecSz) TotalElms;
typedef TMul#(32, VecSz) TotalElms;
                 

module mkStreamingMergeSortSMTSchedTest(Empty);
   MergeSortSMTSched#(UInt#(32), VecSz, TotalElms) sorter <- mkStreamingMergeSortSMTSched(ascending);
   
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
   
   FIFOF#(UInt#(128)) sumQ <- mkUGSizedFIFOF(128);
   Reg#(UInt#(128)) sumReg <- mkReg(0);
   
   Reg#(UInt#(128)) grandTotal <- mkReg(0);
   
   FIFO#(UInt#(128)) grandTotalQ <- mkFIFO;
   
   rule genInput if ( testCntIn < fromInteger(testLen) );
      Vector#(VecSz, UInt#(32)) inV;
      for (Integer i = 0; i < valueOf(VecSz); i = i + 1) begin
         let v <- rand32();
         inV[i] = unpack(v);
      end
      
      inV = map(unpack, zipWith(\- , replicate(fromInteger(totalElms-1) - inCnt), genWith(fromInteger))); 

      sorter.inPipe.enq(inV);
      
      $display("Sort Input [%d] [%d] [@%d] = ", testCntIn, inCnt, cycle, fshow(inV));
      
      if ( inCnt + fromInteger(vecSz) >= fromInteger(totalElms) ) begin              
         inCnt <= 0;
         testCntIn <= testCntIn + 1;
         sumReg <= 0;
         sumQ.enq(sumReg + fold(\+ , map(extend, inV)));
         
         if ( testCntIn == fromInteger(testLen-1)) 
            grandTotalQ.enq(grandTotal + fold(\+ , map(extend, inV)));
      end
      else begin
         inCnt <= inCnt + fromInteger(vecSz);
         sumReg <= sumReg + fold(\+ , map(extend, inV));
      end
         
      grandTotal <= grandTotal+fold(\+ , map(extend, inV));
      
   endrule
   
   Reg#(UInt#(32)) prevMax <- mkReg(ascending?minBound:maxBound);
   
   Reg#(Bit#(32)) outCnt <- mkReg(0);
   Reg#(UInt#(128)) sumRegOut <- mkReg(0);   
   Reg#(UInt#(128)) grandTotalOut <- mkReg(0);   
   rule getOutput;
      let coin <- rand32();
      if ( coin%3 != 3 ) begin
         let d = sorter.outPipe.first;
         sorter.outPipe.deq;


         $display("\t\t\t\tSort Result [%d] [%d] [@%d] = ", testCntOut, outCnt, cycle, fshow(d));
      
         prevCycle <= cycle;
         if ( cycle - prevCycle != 1 && !(outCnt == 0&&testCntOut==0)) begin
            $display("FAIL: StreamingMergeSort not streaming");
            // $finish();
         end
         grandTotalOut <= grandTotalOut + fold(\+ , map(extend, d));
         
         if ( !isSorted(d, ascending) ) begin
            $display("FAILED: StreamingMergeSort result not sorted internally");
            $finish();
         end
      
         if ( !isSorted(vec(prevMax, head(d)), ascending)) begin
            $display("FAILED: StreamingMergeSort result not sorted externally");
            $finish();
         end
         
         if (outCnt + fromInteger(vecSz) >= fromInteger(totalElms) ) begin
            outCnt <= 0;
            prevMax <= ascending?minBound:maxBound;
            testCntOut <= testCntOut + 1;
         
            if ( sumRegOut + fold(\+ , map(extend, d)) != sumQ.first) begin
               $display("Warning: StreamingMergeSort result sum not matched %d vs %d", sumRegOut + fold(\+ ,map(extend,d)), sumQ.first);
            // $finish();
            end
            sumQ.deq;
            sumRegOut <= 0;
            $display("TestCnt[%d] Passed", testCntOut);
            if ( testCntOut + 1 == fromInteger(testLen) ) begin
               if ( grandTotalOut + fold(\+ , map(extend, d)) == grandTotalQ.first) begin
                  $display("PASSED: StreamingMergeSort %d vs %d", grandTotalOut + fold(\+ , map(extend, d)), grandTotalQ.first);
               end
               else begin
                  $display("FAILED: StreamingMergeSort grand total not matched %d vs %d", grandTotalOut + fold(\+ , map(extend, d)), grandTotalQ.first);
               end
               grandTotalQ.deq;
               $finish();
               
            end
         end
         else begin
            sumRegOut <= sumRegOut + fold(\+ , map(extend, d));
            outCnt <= outCnt + fromInteger(vecSz);
            prevMax <= last(d);
         end
      end
   endrule
endmodule



// typedef TDiv#(1024, 4) ChunkSz;
// typedef 128 NumChunks;
typedef TMul#(16,TDiv#(1024, 4)) ChunkSz;
typedef 256 NumChunks;

module mkStreamingMergeNSMTSchedTest(Empty);
   StreamingMergerSMTSched#(UInt#(32), VecSz, ChunkSz, NumChunks) merger <- mkStreamingMergeNSMTSched(ascending);

   Integer testLen = 100;
   Bit#(32) vecSz = fromInteger(valueOf(VecSz));
   
   Reg#(Bit#(32)) cycle <- mkReg(0);
   Reg#(Bit#(32)) prevCycle <- mkReg(0);   
   rule incrCycle;
      cycle <= cycle + 1;
   endrule
   
   FIFO#(UInt#(128)) sumQ <- mkFIFO;
   
   
   Reg#(Bit#(32)) testCnt <- mkReg(0);
      
   Reg#(UInt#(128)) sum <- mkReg(0);
      
      
   Reg#(UInt#(32)) prevMaxIn <- mkReg(ascending?minBound:maxBound);
      
   // function genSortedSeq(x,y) = genSortedSeq0(x,y);
   function getNextData(x,y,z,w) = getNextData0(x,y,z,w);
   
   Bit#(32) sortedBeats = fromInteger(valueOf(ChunkSz)/valueOf(VecSz));
   Reg#(Bit#(32)) pageCnt <- mkReg(0);
   Reg#(Bit#(32)) beatCnt <- mkReg(0);

   rule doGenInput if ( testCnt < fromInteger(testLen) );
      if ( beatCnt+1 == sortedBeats ) begin
         beatCnt <= 0;
         if ( pageCnt + 1 == fromInteger(valueOf(NumChunks))) begin
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
         beatIn[j] = getNextData(unpack(sortedBeats*vecSz)// *fromInteger(valueOf(NumChunks))
                                 , !ascending, fromInteger(j), beatCnt*vecSz);
      end
         
      // $display("Merge inStream [%d][%d][%d] data = ", testCnt, pageCnt, beatCnt, fshow(beatIn));         
      dynamicAssert(isSorted(beatIn, ascending),"input vec not sorted internally");
      dynamicAssert(isSorted(vec(prevMaxIn, head(beatIn)), ascending),"input vec not sorted externally");
         
      merger.inPipe.enq(beatIn);
         
      if ( beatCnt+1 == sortedBeats ) begin
         prevMaxIn <= ascending?minBound:maxBound;
         if ( pageCnt + 1 == fromInteger(valueOf(NumChunks))) begin
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
   
   Reg#(UInt#(32)) prevMax <- mkReg(ascending?minBound:maxBound);
   
   rule doResult;
      let coin <- rand32();
      if ( coin%3 != 0) begin
      merger.outPipe.deq;
      let merged = merger.outPipe.first;

      prevCycle <= cycle;
      
      if ( cycle - prevCycle != 1 && !(outBeat == 0)) begin
         $display("FAIL: MergeNFoldSMTBRAM not streaming for a specific merge, cycle diff = %d, outBeat = %d", cycle-prevCycle, outBeat);
         // $finish();
      end
      
      // $display("(@%t)Merged Sequence [%d][%d] = ", $time, resultCnt, outBeat, fshow(merged));
      
      if ( !isSorted(merged, ascending) ) begin
         $display("FAILED: StreamingMergeSort2Var result not sorted internally");
         $finish();
      end
      
      if ( !isSorted(vec(prevMax, head(merged)), ascending) ) begin
         $display("FAILED: StreamingMergeSort2Var result not sorted externally");
         $finish();
      end

      
      if ( outBeat+1 == sortedBeats*fromInteger(valueOf(NumChunks)) ) begin
         accumulate <= 0;
         outBeat <= 0;
         resultCnt <= resultCnt + 1;
         function doGet(x)=x.get;
         let expected <- toGet(sumQ).get;
         let result = accumulate + fold(\+ ,map(zeroExtend, merged));
         prevMax <= ascending?minBound:maxBound;
         
         if ( expected !=  result) begin
            $display("FAILED: MergeNFoldSMTBRAM result sum not as expected");
            $display("result   = %d",  result);
            $display("expected = %d", expected);
            $finish;
         end
         else begin
            $display("TestPassed for testCnt = %d",resultCnt);
         end
         if ( resultCnt + 1 == fromInteger(testLen) ) begin
            $display("PASSED: MergeNFoldSMTBRAM ");
            $display("Throughput cycles for beat = (%d/%d) %d, log_fanIn_N = %d", cycle, sortedBeats*fromInteger(valueOf(NumChunks)*testLen), cycle/(sortedBeats*fromInteger(valueOf(NumChunks)*testLen)), log2(valueOf(NumChunks))/log2(valueOf(NumChunks)));
            $finish;
         end
      end
      else begin
         accumulate <= accumulate + fold(\+ ,map(zeroExtend, merged));
         outBeat <= outBeat + 1;
         prevMax <= last(merged);
      end
      end
   endrule
endmodule

                 
typedef TMul#(1024,TDiv#(1024, 4)) SegSz;
typedef 16 NumSegs;
typedef TDiv#(1024, 4) FDepth;                 
                 
module mkStreamingDRAMMergeNSMTSchedTest(Empty);
   // StreamingMergerSMTSched#(UInt#(32), VecSz, ChunkSz, NumChunks) merger <- mkStreamingMergeNSMTSched(ascending);
   DRAMStreamingMergerSMTSched#(UInt#(32), VecSz, SegSz, NumSegs, FDepth) merger <- mkDRAMStreamingMergeNSMTSched(ascending);
   
   DRAMMux#(2, 2) dramMux <- mkRwDualDRAMMux;
   // Vector#(2, Client#(Tuple2#(Bit#(1), DDRRequest), DDRResponse)) dramClis = zipWith(toClient, dramReqQ, dramRespQ);
   zipWithM_(mkConnection, merger.dramMuxClients, dramMux.dramServers);

   Vector#(2, DDR4_User_VCU108) dramCtrs <- replicateM(mkDDR4Simulator);
   zipWithM_(mkConnection, dramMux.dramControllers, dramCtrs);   

   Integer testLen = 10;
   Bit#(32) vecSz = fromInteger(valueOf(VecSz));
   
   Reg#(Bit#(32)) cycle <- mkReg(0);
   Reg#(Bit#(32)) prevCycle <- mkReg(0);   
   rule incrCycle;
      cycle <= cycle + 1;
   endrule
   
   FIFO#(UInt#(128)) sumQ <- mkFIFO;
   
   Reg#(Bit#(32)) testCnt <- mkReg(0);
      
   Reg#(UInt#(128)) sum <- mkReg(0);
      
      
   Reg#(UInt#(32)) prevMaxIn <- mkReg(ascending?minBound:maxBound);
      
   // function genSortedSeq(x,y) = genSortedSeq0(x,y);
   function getNextData(x,y,z,w) = getNextData0(x,y,z,w);
   
   Bit#(32) sortedBeats = fromInteger(valueOf(SegSz)/valueOf(VecSz));
   Reg#(Bit#(32)) pageCnt <- mkReg(0);
   Reg#(Bit#(32)) beatCnt <- mkReg(0);

   rule doGenInput if ( testCnt < fromInteger(testLen) );
      if ( beatCnt+1 == sortedBeats ) begin
         beatCnt <= 0;
         if ( pageCnt + 1 == fromInteger(valueOf(NumSegs))) begin
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
         beatIn[j] = getNextData(unpack(sortedBeats*vecSz)// *fromInteger(valueOf(NumSegs))
                                 , !ascending, fromInteger(j), beatCnt*vecSz);
      end
         
      // $display("Merge inStream [%d][%d][%d] data = ", testCnt, pageCnt, beatCnt, fshow(beatIn));         
      dynamicAssert(isSorted(beatIn, ascending),"input vec not sorted internally");
      dynamicAssert(isSorted(vec(prevMaxIn, head(beatIn)), ascending),"input vec not sorted externally");
         
      merger.inPipe.enq(beatIn);
         
      if ( beatCnt+1 == sortedBeats ) begin
         prevMaxIn <= ascending?minBound:maxBound;
         if ( pageCnt + 1 == fromInteger(valueOf(NumSegs))) begin
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
   
   Reg#(UInt#(32)) prevMax <- mkReg(ascending?minBound:maxBound);
   
   rule doResult;
      
      let coin <- rand32();
      if ( coin % 3 != 3 ) begin
      merger.outPipe.deq;
      let merged = merger.outPipe.first;

      prevCycle <= cycle;
      
      if ( cycle - prevCycle != 1 && !(outBeat == 0)) begin
         $display("FAIL: MergeNFoldSMTDRAM not streaming for a specific merge, cycle diff = %d, outBeat = %d", cycle-prevCycle, outBeat);
         // $finish();
      end
      
      // $display("(@%t)Merged Sequence [%d][%d] = ", $time, resultCnt, outBeat, fshow(merged));
      
      if ( !isSorted(merged, ascending) ) begin
         $display("FAILED: StreamingMergeSort2Var result not sorted internally");
         $finish();
      end
      
      if ( !isSorted(vec(prevMax, head(merged)), ascending) ) begin
         $display("FAILED: StreamingMergeSort2Var result not sorted externally");
         $finish();
      end

      
      if ( outBeat+1 == sortedBeats*fromInteger(valueOf(NumSegs)) ) begin
         accumulate <= 0;
         outBeat <= 0;
         resultCnt <= resultCnt + 1;
         function doGet(x)=x.get;
         let expected <- toGet(sumQ).get;
         let result = accumulate + fold(\+ ,map(zeroExtend, merged));
         prevMax <= ascending?minBound:maxBound;
         
         if ( expected !=  result) begin
            $display("FAILED: MergeNFoldSMTDRAM result sum not as expected");
            $display("result   = %d",  result);
            $display("expected = %d", expected);
            $finish;
         end
         else begin
            $display("TestPassed for testCnt = %d",resultCnt);
         end
         if ( resultCnt + 1 == fromInteger(testLen) ) begin
            $display("PASSED: MergeNFoldSMTDRAM ");
            $display("Throughput cycles for beat = (%d/%d) %d, log_fanIn_N = %d", cycle, sortedBeats*fromInteger(valueOf(NumSegs)*testLen), cycle/(sortedBeats*fromInteger(valueOf(NumSegs)*testLen)), log2(valueOf(NumSegs))/log2(valueOf(NumSegs)));
            $finish;
         end
      end
      else begin
         accumulate <= accumulate + fold(\+ ,map(zeroExtend, merged));
         outBeat <= outBeat + 1;
         prevMax <= last(merged);
      end
      end
   endrule
endmodule
