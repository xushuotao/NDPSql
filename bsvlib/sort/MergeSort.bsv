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

import Bitonic::*;

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
   Bitonic::RecursiveBitonic#(vSz, iType)
   );
   MergeN#(iType, vSz, vSz, n) mergerTree <- mkStreamingMergeN(descending);
   
   Reg#(Bit#(TLog#(n))) fanInSel <- mkReg(0);
   
   interface PipeIn inPipe;
      method Action enq(Vector#(vSz, iType) d);
         mergerTree.inPipes[fanInSel].enq(bitonic_sort(d, descending));
         fanInSel <= fanInSel + 1;
      endmethod
      method Bool notFull = mergerTree.inPipes[fanInSel].notFull;
   endinterface
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


// BASE CASE
instance RecursiveMerger#(iType,vSz,sortedSz,2) provisos(
   Bitonic::RecursiveBitonic#(vSz, iType),
   Ord#(iType),
   Add#(vSz, a__, sortedSz),
   Add#(1, b__, vSz),
   Bits#(iType, c__),
   Mul#(vSz, c__, d__)
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
   Mul#(TDiv#(n, 2), 2, n)
);
   module mkStreamingMergeN#(Bool descending)(MergeN#(iType,vSz,sortedSz,n));
      Vector#(TDiv#(n,2), Merge2#(iType, vSz, sortedSz)) mergers <- replicateM(mkStreamingMerge2(descending));
   

      function Vector#(2, PipeIn#(Vector#(vSz, iType))) getPipeIn(Merge2#(iType, vSz, sortedSz) ifc) = ifc.inPipes;
      function PipeOut#(Vector#(vSz, iType)) getPipeOut(Merge2#(iType, vSz, sortedSz) ifc) = ifc.outPipe;
      // function getPipeIn(ifc) = ifc.inPipes;
   
      MergeN#(iType, vSz, TMul#(sortedSz,2), TDiv#(n,2)) mergeN_2 <- mkStreamingMergeN(descending);
      zipWithM_(mkConnection, map(getPipeOut, mergers), mergeN_2.inPipes);
   
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


module mkStreamingMerge2#(Bool descending)(Merge2#(iType, vSz, sortedSz)) provisos (
   Bits#(Vector::Vector#(vSz, iType), a__),
   Add#(1, c__, vSz),
   Div#(sortedSz, vSz, totalbeats),
   Add#(vSz, e__, sortedSz),
   Ord#(iType),
   RecursiveBitonic#(vSz, iType)
   );
   
   Vector#(2, FIFOF#(Vector#(vSz, iType))) vInQ <- replicateM(mkPipelineFIFOF);

   Reg#(Maybe#(Vector#(vSz, iType))) prevTopBuf <- mkReg(tagged Invalid);
   
   Integer initCnt = valueOf(totalbeats);
   
   Vector#(2, Reg#(Bit#(TLog#(TAdd#(totalbeats,1))))) vInCnt <- replicateM(mkReg(fromInteger(initCnt)));
   
   FIFOF#(Vector#(vSz, iType)) bitonicOutQ <- mkFIFOF;
   
   function gtZero(cnt)=(cnt > 0);
   function minusOne(x)=x-1;
   
   rule mergeTwoInQs (!isValid(prevTopBuf) && all(gtZero, readVReg(vInCnt)));
      function doGet(x) = x.get;
      let inVec <- mapM(doGet, map(toGet, vInQ));

      writeVReg(vInCnt, map(minusOne, readVReg(vInCnt)));
         
      let cleaned = halfClean(inVec, descending);
      bitonicOutQ.enq(cleaned[0]);
      prevTopBuf <= tagged Valid sort_bitonic(cleaned[1], descending);
   endrule

   rule mergeWithBuf (isValid(prevTopBuf));
      let prevTop = fromMaybe(?, prevTopBuf);
      
      Vector#(vSz, iType) in = ?;
      
      Bool noInput = False;
      if ( all(gtZero, readVReg(vInCnt)) ) begin
         let inVec0 = vInQ[0].first;
         let inVec1 = vInQ[1].first;
         in = inVec0;
         if ( isSorted(vec(last(prevTop), head(inVec0)), descending) ) begin
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
         prevTopBuf <= tagged Invalid;
         bitonicOutQ.enq(prevTop);
      end
      else begin
         let cleaned = halfClean(vec(prevTop,in), descending);
         bitonicOutQ.enq(cleaned[0]);
         prevTopBuf <= tagged Valid sort_bitonic(cleaned[1], descending);
      end
   endrule
   
   function sortOut(x) = sort_bitonic(x, descending);
   interface inPipes = map(toPipeIn, vInQ);
   interface PipeOut outPipe = mapPipe(sortOut, toPipeOut(bitonicOutQ));
endmodule



