// Copyright (C) 2019

// Shuotao Xu <shuotao@csail.mit.edu>

// Permission is hereby granted, free of charge, to any person obtaining a copy of this
// software and associated documentation files (the "Software"), to deal in the Software
// without restriction, including without limitation the rights to use, copy, modify,
// merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
// permit persons to whom the Software is furnished to do so, subject to the following
// conditions:

// The above copyright notice and this permission notice shall be included in all copies
// or substantial portions of the Software.  

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
// INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
// PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
// HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
// CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE
// OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import Pipe::*;
import FIFOF::*;
import SpecialFIFOs::*;
import GetPut::*;
import Vector::*;
import BuildVector::*;
import Connectable::*;
import FIFO::*;
import Bitonic::*;
import TopHalfUnit::*;

import OneToNRouter::*;



Bool debug = False;

interface MergeSort#(type iType,
                     numeric type vSz,
                     numeric type totalSz);
   interface PipeIn#(Vector#(vSz, iType)) inPipe;
   interface PipeOut#(Vector#(vSz, iType)) outPipe;
endinterface


////////////////////////////////////////////////////////////////////////////////
/// module:      mkStreamingMergeSort
/// Description: this module takes a in-stream of unsorted elements of totalSz,
///              which is streaming @ vSz elements per beat and sort them into a
///              sorted out-stream using merge-sort algorithm
////////////////////////////////////////////////////////////////////////////////
module mkStreamingMergeSort#(Bool descending)(MergeSort#(iType, vSz, totalSz)) provisos(
   Div#(totalSz, vSz, n),
   MergeSort::RecursiveMerger#(iType, vSz, vSz, n),
   Bitonic::RecursiveBitonic#(vSz, iType),
   Bits#(Vector::Vector#(vSz, iType), a__),
   Add#(1, b__, n),
   Add#(1, c__, TMul#(TDiv#(n, 2), 2)),
   Add#(n, d__, TMul#(TDiv#(n, 2), 2))
   );
   
   function Vector#(n, PipeIn#(Vector#(vSz, iType))) takeInPipes(MergeN#(iType, vSz, vSz, n) merger) = merger.inPipes;
   function f_sort(d) = bitonic_sort(d, descending);

   MergeN#(iType, vSz, vSz, n) mergerTree <- mkStreamingMergeN(descending);         

   OneToNRouter#(n, Vector#(vSz, iType)) distributor  = ?;
   if ( valueOf(n) > 16 ) begin
      distributor <- mkOneToNRouterPipelined;   
      zipWithM_(mkConnection, takeOutPorts(distributor), takeInPipes(mergerTree));
   end
   
   StreamNode#(vSz, iType) sorter <- mkBitonicSort(descending);
   Reg#(Bit#(TLog#(n))) fanInSel <- mkReg(0);
   rule doEnqMergeTree;
      let d = sorter.outPipe.first;
      sorter.outPipe.deq;
      fanInSel <= fanInSel + 1;
      if ( valueOf(n) > 16 )
         distributor.inPort.enq(tuple2(fanInSel, d));
      else
         mergerTree.inPipes[fanInSel].enq(d);
   endrule

   interface PipeIn inPipe = sorter.inPipe;
   interface PipeOut outPipe = mergerTree.outPipe;
endmodule


interface MergeN#(type iType,
                  numeric type vSz,
                  numeric type sortedSz,
                  numeric type n);
   interface Vector#(n, PipeIn#(Vector#(vSz, iType))) inPipes;
   interface PipeOut#(Vector#(vSz, iType)) outPipe;
endinterface

typeclass RecursiveMerger#(type iType,
                           numeric type vSz,
                           numeric type sortedSz,
                           numeric type n);
////////////////////////////////////////////////////////////////////////////////
/// module:      mkStreamingMergeN
/// Description: this module takes N in-streams, each has sorted elements of 
///              sortedSz streaming @ vSz elements per beat, and merge them into 
///              a single sorted out-stream of N*sortedSz elements with a binary
///              merge-tree
////////////////////////////////////////////////////////////////////////////////
   module mkStreamingMergeN#(Bool descending)(MergeN#(iType,vSz,sortedSz,n));
endtypeclass

(* synthesize *)
module mkStreamingMerge2_32bit_1#(Bool descending)(MergeN#(UInt#(32),8,8,2));
   let merger <- mkStreamingMerge2(descending);
   return merger;
endmodule
instance RecursiveMerger#(UInt#(32),8,8,2);
   module mkStreamingMergeN#(Bool descending)(MergeN#(UInt#(32),8,8,2));
      let merger <- mkStreamingMerge2_32bit_1(descending);
      return merger;
   endmodule
endinstance

(* synthesize *)
module mkStreamingMerge2_32bit_2#(Bool descending)(MergeN#(UInt#(32),8,16,2));
   let merger <- mkStreamingMerge2(descending);
   return merger;
endmodule
instance RecursiveMerger#(UInt#(32),8,16,2);
   module mkStreamingMergeN#(Bool descending)(MergeN#(UInt#(32),8,16,2));
      let merger <- mkStreamingMerge2_32bit_2(descending);
      return merger;
   endmodule
endinstance


(* synthesize *)
module mkStreamingMerge2_32bit_4#(Bool descending)(MergeN#(UInt#(32),8,32,2));
   let merger <- mkStreamingMerge2(descending);
   return merger;
endmodule
instance RecursiveMerger#(UInt#(32),8,32,2);
   module mkStreamingMergeN#(Bool descending)(MergeN#(UInt#(32),8,32,2));
      let merger <- mkStreamingMerge2_32bit_4(descending);
      return merger;
   endmodule
endinstance

(* synthesize *)
module mkStreamingMerge2_32bit_8#(Bool descending)(MergeN#(UInt#(32),8,64,2));
   let merger <- mkStreamingMerge2(descending);
   return merger;
endmodule
instance RecursiveMerger#(UInt#(32),8,64,2);
   module mkStreamingMergeN#(Bool descending)(MergeN#(UInt#(32),8,64,2));
      let merger <- mkStreamingMerge2_32bit_8(descending);
      return merger;
   endmodule
endinstance


(* synthesize *)
module mkStreamingMerge2_32bit_16#(Bool descending)(MergeN#(UInt#(32),8,128,2));
   let merger <- mkStreamingMerge2(descending);
   return merger;
endmodule
instance RecursiveMerger#(UInt#(32),8,128,2);
   module mkStreamingMergeN#(Bool descending)(MergeN#(UInt#(32),8,128,2));
      let merger <- mkStreamingMerge2_32bit_16(descending);
      return merger;
   endmodule
endinstance


(* synthesize *)
module mkStreamingMerge2_32bit_32#(Bool descending)(MergeN#(UInt#(32),8,256,2));
   let merger <- mkStreamingMerge2(descending);
   return merger;
endmodule
instance RecursiveMerger#(UInt#(32),8,256,2);
   module mkStreamingMergeN#(Bool descending)(MergeN#(UInt#(32),8,256,2));
      let merger <- mkStreamingMerge2_32bit_32(descending);
      return merger;
   endmodule
endinstance


// BASE CASE
instance RecursiveMerger#(iType,vSz,sortedSz,2) provisos(
   Bitonic::RecursiveBitonic#(vSz, iType),
   Ord#(iType),
   Add#(vSz, a__, sortedSz),
   Add#(1, b__, vSz),
   Bits#(iType, c__),
   Mul#(vSz, c__, d__),
   FShow#(iType)
   );
   module mkStreamingMergeN#(Bool descending)(MergeN#(iType,vSz,sortedSz,2));
      Merge2#(iType,vSz,sortedSz) merger <- mkStreamingMerge2(descending);
      return merger;
   endmodule
endinstance

// NORMAL CASE
instance RecursiveMerger#(iType,vSz,sortedSz,n) provisos (
   Add#(2, a__, n),               // n >= 2
   NumAlias#(TExp#(TLog#(n)), n), //n is power of 2
   Bitonic::RecursiveBitonic#(vSz, iType),
   Ord#(iType),
   Add#(vSz, b__, sortedSz),
   Add#(1, c__, vSz),
   Bits#(iType, d__),
   Mul#(vSz, d__, e__),
   MergeSort::RecursiveMerger#(iType, vSz, TMul#(sortedSz, 2), TDiv#(n, 2)),
   Mul#(TDiv#(n, 2), 2, n),
   FShow#(iType)
);
   module mkStreamingMergeN#(Bool descending)(MergeN#(iType,vSz,sortedSz,n));
      Vector#(TDiv#(n,2), Merge2#(iType, vSz, sortedSz)) mergers <- replicateM(mkStreamingMerge2(descending));
   
      function PipeOut#(Vector#(vSz,iType)) getPipeOut(Merge2#(iType, vSz, sortedSz) ifc) = ifc.outPipe;
      function getPipeIn(ifc) = ifc.inPipes;
   
      MergeN#(iType, vSz, TMul#(sortedSz,2), TDiv#(n,2)) mergeN_2 <- mkStreamingMergeN(descending);

      zipWithM_(mkConnection, map(getPipeOut,mergers), mergeN_2.inPipes);
   
      MergeN#(iType,vSz,sortedSz,n) retifc = (interface MergeN;
                                                 interface inPipes = concat(map(getPipeIn,mergers));
                                                 interface outPipe = mergeN_2.outPipe;
                                             endinterface);
      return retifc;
   endmodule
endinstance



// merge two sorted streams of same size of sortedSz
typedef MergeN#(iType, vSz, sortedSz, 2) Merge2#(type iType,
                                                 numeric type vSz,
                                                 numeric type sortedSz); 

typedef enum {DRAIN_IN, DRAIN_SORTER, MERGE} Scenario deriving(Bits, Eq, FShow);
module mkStreamingMerge2#(Bool descending)(Merge2#(iType, vSz, sortedSz)) provisos (
   Bits#(Vector::Vector#(vSz, iType), a__),
   Add#(1, c__, vSz),
   Div#(sortedSz, vSz, totalbeats),
   Add#(vSz, e__, sortedSz),
   Ord#(iType),
   RecursiveBitonic#(vSz, iType),
   FShow#(iType)
   );
   
   // Note: mkFIFOF is used to cut combintational path between mergers
   Vector#(2, FIFOF#(Vector#(vSz, iType))) vInQ <- replicateM(mkFIFOF);

   Reg#(Bit#(1)) portSel <- mkRegU;
  
   Reg#(Maybe#(iType)) prevTail <- mkReg(tagged Invalid);
   
   Integer initCnt = valueOf(totalbeats);
   
   Vector#(2, Reg#(Bit#(TLog#(TAdd#(totalbeats,1))))) vInCnt <- replicateM(mkReg(fromInteger(initCnt)));
   
   StreamNode#(vSz, iType) sort_bitonic_pipeline <- mkSortBitonic(descending);
   TopHalfUnit#(vSz, iType) topHalfUnit <- mkTopHalfUnit;
   
   function gtZero(cnt)=(cnt > 0);
   function minusOne(x)=x-1;
   function sorter(x) = sort_bitonic(x, descending);   

   // Note: selectedInQ has to be PipelineFIFO to avoid rightOperand to be
   // overwritten by the heads of next sorted sequences
   FIFO#(Tuple2#(Scenario, Vector#(vSz, iType))) selectedInQ <- mkPipelineFIFO;//mkSizedFIFO(valueOf(vSz) + 1);
   Reg#(Vector#(vSz, iType)) rightOperand <- mkRegU;
   Reg#(Bool) init <- mkReg(False);
   rule mergeTwoInQs (!isValid(prevTail) && !init);
      function doGet(x) = x.get;
      let inVec <- mapM(doGet, map(toGet, vInQ));
      // decrement both counters by one
      writeVReg(vInCnt, map(minusOne, readVReg(vInCnt)));
      let cleaned = halfClean(inVec, descending);
      selectedInQ.enq(tuple2(DRAIN_IN, cleaned[0]));
      // rightOperand <= cleaned[1];
      topHalfUnit.enqData(inVec[0], Init);
      rightOperand <= inVec[1];
      // lowerHalfQ.enq(clean[0]);
      init <= True;
      prevTail <= tagged Valid getTop(vec(last(inVec[0]), last(inVec[1])),descending);
      portSel <= ~pack(isSorted(vec(last(inVec[0]), last(inVec[1])), descending));
   endrule
   
   rule mergeTwoInQs2 (init);
      init <= False;
      topHalfUnit.enqData(rightOperand, Normal);
   endrule

   rule mergeWithBuf (isValid(prevTail) && !init);

      let prevTail_d = fromMaybe(?, prevTail);
      
      Vector#(vSz, iType) in = ?;
      
      Bool noInput = False;
      if ( all(gtZero, readVReg(vInCnt)) ) begin
         let inVec0 = vInQ[0].first;
         let inVec1 = vInQ[1].first;
         in = inVec0;
         if ( portSel == 1 ) begin
            in = inVec1;
            vInCnt[1] <= vInCnt[1] - 1;
            vInQ[1].deq;
         end
         else begin
            vInCnt[0] <= vInCnt[0] - 1;
            vInQ[0].deq;
         end
      end
      else if ( vInCnt[0] > 0 ) begin
         in <- toGet(vInQ[0]).get;
         vInCnt[0] <= vInCnt[0] - 1;
      end
      else if ( vInCnt[1] > 0 ) begin
         in <- toGet(vInQ[1]).get;
         vInCnt[1] <= vInCnt[1] - 1;
      end
      else begin
         writeVReg(vInCnt, map(fromInteger, replicate(initCnt)));
         noInput = True;
      end
      
      if ( noInput) begin
         prevTail <= tagged Invalid;
         selectedInQ.enq(tuple2(DRAIN_SORTER, ?));
      end
      else begin
         prevTail <= tagged Valid getTop(vec(prevTail_d, last(in)), descending);
         topHalfUnit.enqData(in, Normal);
         selectedInQ.enq(tuple2(MERGE, in));
      end
      
      if ( isSorted(vec(prevTail_d, last(in)), descending)) begin
         portSel <= ~portSel;
      end
   endrule
   
   Reg#(Vector#(vSz,iType)) prevTop <- mkRegU;
   rule combWithTopHalf;
      let {scenario, in} <- toGet(selectedInQ).get;
      Vector#(vSz, iType) out = ?;

      case (scenario)
         DRAIN_IN: 
         begin
            // feedback = rightOperand;
            out = in;
         end
         DRAIN_SORTER:
         begin
            out = prevTop;
         end
         MERGE:
         begin
            let topHalf <- topHalfUnit.getCurrTop;
            let cleaned = halfClean(vec(topHalf,in), descending);
            out = cleaned[0];
            prevTop <= cleaned[1];
         end
      endcase
      sort_bitonic_pipeline.inPipe.enq(out);
   endrule
   
   // Reg#(Vector#(vSz, iType)) feedbackBuf <- mkRegU();
   // rule doOutput;
   //    let {scenario, in} <- toGet(selectedInQ).get;
   //    // $display(fshow(scenario));
   //    Vector#(vSz, iType) prevTop = ?;
   //    Vector#(vSz, iType) feedback = ?;
   //    Vector#(vSz, iType) out = ?;
      
   //    case (scenario)
   //       DRAIN_IN: 
   //       begin
   //          feedback = rightOperand;
   //          out = in;
   //       end
   //       DRAIN_SORTER:
   //       begin
   //          out = feedbackBuf;
   //       end
   //       MERGE:
   //       begin
   //          let cleaned = halfClean(vec(feedbackBuf,in), descending);
   //          out = cleaned[0];
   //          feedback = cleaned[1];
   //       end
   //    endcase
      
   //    sort_bitonic_pipeline.inPipe.enq(out);
   //    feedbackBuf <= sorter(feedback);
   // endrule
   
   interface inPipes = map(toPipeIn, vInQ);
   interface PipeOut outPipe = sort_bitonic_pipeline.outPipe;
endmodule



