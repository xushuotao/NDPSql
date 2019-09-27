
// Copyright (c) 2013 Nokia, Inc.

// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use, copy,
// modify, merge, publish, distribute, sublicense, and/or sell copies
// of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
// BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
// ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.


`include "ConnectalProjectConfig.bsv"

import FIFO::*;
import Vector::*;
import DRAMController::*;
import Connectable::*;
import HostInterface::*;

import MergeSort::*;
import LFSR::*;
import Pipe::*;
import BuildVector::*;
import Bitonic::*;
// // import DRAM stuff
// import DDR4Controller::*;
// import DDR4Common::*;

// `ifdef SIMULATION
// import DDR4Sim::*;
// `else
// import Clocks          :: *;
// import DefaultValue    :: *;
// `endif

// import GetPut::*;
// import ClientServerHelper::*;
// import DRAMControllerTypes::*;


// interface Top_Pins;
//    `ifndef SIMULATION
//    interface DDR4_Pins_Dual_VCU108 pins_ddr4;
//    `endif
// endinterface




interface SorterRequest;
   method Action initSeed(Bit#(32) seed);
   method Action startSorting(Bit#(64) iter);
endinterface

interface SorterIndication;
   method Action sortingDone(Bit#(64) int_unsorted_cnt, Bit#(64) ext_unsorted_cnt, Bit#(64) cycles);
endinterface

interface Sorter;
   interface SorterRequest request;
   // interface Top_Pins pins;
endinterface

typedef TDiv#(256, 32) VecSz;

`ifdef SORT_SZ
typedef `SORT_SZ SortSz;
`else
typedef 1024 SortSz;
`endif

typedef TDiv#(SortSz,4) TotalElms;
Bool descending = True;

(* synthesize *)
module mkStreamingMergeSort_synth(MergeSort#(UInt#(32), VecSz, TotalElms));
   let sorter <- mkStreamingMergeSort(descending);
   return sorter;
endmodule


module mkSorter#(HostInterface host, SorterIndication indication)(Sorter);
   
   Reg#(Bool) started <- mkReg(False);
   Reg#(Bit#(64)) cycleCnt <- mkReg(0);
   
   Reg#(Bit#(3)) cnt_init <- mkReg(0);
   
   Vector#(VecSz, LFSR#(Bit#(32))) lfsr <- replicateM(mkLFSR_32);
   
   rule increCycle;
      cycleCnt <= cycleCnt + 1;
   endrule

   
   Reg#(Bit#(64)) iterCnt <- mkReg(0);
   Reg#(Bit#(64)) iterCnt_out <- mkReg(0);
   
   Reg#(Bit#(32)) elemCnt <- mkReg(0);
   
   Integer vecSz = valueOf(VecSz);
   Integer totalElms = valueOf(TotalElms);
   
   let sorter <- mkStreamingMergeSort_synth;
   
   rule genInput if ( iterCnt > 0);
      if ( elemCnt + fromInteger(vecSz) >= fromInteger(totalElms) ) begin              
         elemCnt <= 0;
         iterCnt <= iterCnt - 1;
      end
      else begin
         elemCnt <= elemCnt + fromInteger(vecSz);
      end
      
      function t getValue(LFSR#(t) x) = x.value;
      function nextValue(x) = x.next;
      
      Vector#(VecSz, UInt#(32)) inV = map(unpack, map(getValue, lfsr));
      mapM_(nextValue, lfsr);
      sorter.inPipe.enq(inV);
   endrule
   
   Reg#(UInt#(32)) prevMax <- mkReg(descending?minBound:maxBound);
   
   Reg#(Bit#(32)) elemCnt_out <- mkReg(0);
   
   Reg#(Bit#(64)) internalUnsortedCnt <- mkReg(0);
   Reg#(Bit#(64)) externalUnsortedCnt <- mkReg(0);
   
   rule getOutput;
      let d = sorter.outPipe.first;
      sorter.outPipe.deq;

      // $display("Sort Result [%d] [@%d] = ", elemCnt_out, cycle, fshow(d));

      if (!isSorted(d, descending) ) internalUnsortedCnt <= internalUnsortedCnt + 1;
      if (!isSorted(vec(prevMax, head(d)), descending)) externalUnsortedCnt <= externalUnsortedCnt + 1;
      
      if (elemCnt_out + fromInteger(vecSz) >= fromInteger(totalElms) ) begin
         elemCnt_out <= 0;
         prevMax <= descending?minBound:maxBound;
         iterCnt_out <= iterCnt_out - 1;
         if ( iterCnt_out == 1) begin
            indication.sortingDone(internalUnsortedCnt, externalUnsortedCnt, cycleCnt);
         end
      end
      else begin
         elemCnt_out <= elemCnt_out + fromInteger(vecSz);
         prevMax <= last(d);
      end
   endrule
      
      
   interface SorterRequest request;
      method Action initSeed(Bit#(32) seed);
         lfsr[cnt_init].seed(seed);
         cnt_init <= cnt_init + 1;
      endmethod
      method Action startSorting(Bit#(64) iter) if (iterCnt == 0&&iterCnt_out==0);
         iterCnt <= iter;
         iterCnt_out <= iter;
         cycleCnt <= 0;
         internalUnsortedCnt <= 0;
         externalUnsortedCnt <= 0;
      endmethod
   endinterface
   
endmodule
