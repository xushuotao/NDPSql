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


import OneToNRouter::*;

import MergerSMT::*;



Bool debug = False;

interface MergeSortSMT#(type iType,
                     numeric type vSz,
                     numeric type totalSz);
   interface PipeIn#(Vector#(vSz, iType)) inPipe;
   interface PipeOut#(Vector#(vSz, iType)) outPipe;
endinterface


////////////////////////////////////////////////////////////////////////////////
/// module:      mkStreamingMergeSortSMT
/// Description: this module takes a in-stream of unsorted elements of totalSz,
///              which is streaming @ vSz elements per beat and sort them into a
///              sorted out-stream using merge-sort algorithm
////////////////////////////////////////////////////////////////////////////////
module mkStreamingMergeSortSMT#(Bool ascending)(MergeSortSMT#(iType, vSz, totalSz)) provisos(
   Div#(totalSz, vSz, n),
   MergerSMT::RecursiveMergerSMT#(iType, vSz, n),
   Bitonic::RecursiveBitonic#(vSz, iType),
   Bits#(Vector::Vector#(vSz, iType), a__),
   Add#(1, b__, n),
   Add#(1, c__, TMul#(TDiv#(n, 2), 2)),
   Add#(n, d__, TMul#(TDiv#(n, 2), 2))
   );
   
   function Vector#(n, PipeIn#(SortedPacket#(vSz, iType))) takeInPipes(MergeNSMT#(iType, vSz, n) merger) = merger.inPipes;
   function f_sort(d) = bitonic_sort(d, ascending);

   MergeNSMT#(iType, vSz, n) mergerTree <- mkMergeNSMT(ascending, 0);         

   OneToNRouter#(n, SortedPacket#(vSz, iType)) distributor  = ?;
   if ( valueOf(n) > 16 ) begin
      distributor <- mkOneToNRouterPipelined;   
      zipWithM_(mkConnection, takeOutPorts(distributor), takeInPipes(mergerTree));
   end
   
   StreamNode#(vSz, iType) sorter <- mkBitonicSort(ascending);
   Reg#(Bit#(TLog#(n))) fanInSel <- mkReg(0);
   rule doEnqMergeTree;
      let d = sorter.outPipe.first;
      sorter.outPipe.deq;
      let packet = SortedPacket{d:d, first:True, last:True};
      fanInSel <= fanInSel + 1;
      if ( valueOf(n) > 16 )
         distributor.inPort.enq(tuple2(fanInSel, packet));
      else
         mergerTree.inPipes[fanInSel].enq(packet);
   endrule
   
   function f(x) = x.d;

   interface PipeIn inPipe = sorter.inPipe;
   interface PipeOut outPipe = mapPipe(f, mergerTree.outPipe);
endmodule

