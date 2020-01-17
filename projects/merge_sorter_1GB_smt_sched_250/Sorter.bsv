
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

import SorterTypes::*;
import MergeSortSMTSched::*;
import DRAMMergerSMTSched::*;

import LFSR::*;
import Pipe::*;
import BuildVector::*;
import Bitonic::*;

// import DRAM stuff
import DDR4Controller::*;
import DDR4Common::*;

`ifdef SIMULATION
import DDR4Sim::*;
`else
import Clocks          :: *;
import DefaultValue    :: *;
`endif

import GetPut::*;
import ClientServerHelper::*;
import DRAMControllerTypes::*;


interface Top_Pins;
   `ifndef SIMULATION
   interface DDR4_Pins_Dual_VCU108 pins_ddr4;
   `endif
endinterface




interface SorterRequest;
   method Action initSeed(Bit#(32) seed);
   method Action startSorting(Bit#(32) iter);
endinterface

interface SorterIndication;
   method Action sortingDone(Bit#(64) int_unsorted_cnt, Bit#(64) ext_unsorted_cnt, Bit#(64) cycles);
endinterface

interface Sorter;
   interface SorterRequest request;
   interface Top_Pins pins;
endinterface

typedef 32 ElemSz;

typedef TDiv#(512, ElemSz) VecSz;

`ifdef SORT_SZ_L0
typedef `SORT_SZ_L0 SortSz_L0;
`else
typedef 16384 SortSz_L0;
`endif

`ifdef SORT_SZ_L1
typedef `SORT_SZ_L1 SortSz_L1;
`else
typedef 4194304 SortSz_L1;
`endif

`ifdef SORT_SZ_L2
typedef `SORT_SZ_L2 SortSz_L2;
`else
typedef 1073741824 SortSz_L2;
`endif


typedef TDiv#(SortSz_L0,TDiv#(ElemSz,8)) TotalElms_L0;

typedef TDiv#(SortSz_L1,TDiv#(ElemSz,8)) TotalElms_L1;

typedef TDiv#(SortSz_L2,TDiv#(ElemSz,8)) TotalElms_L2;


typedef TDiv#(TotalElms_L1, TotalElms_L0) N_L1;
Bool descending = True;

(* synthesize *)
module mkStreamingMergeSort_synth(MergeSortSMTSched#(UInt#(32), VecSz, TotalElms_L0));
   let sorter_L0 <- mkStreamingMergeSortSMTSched(descending);
   return sorter_L0;
endmodule

(* synthesize *)
module mkStreamingMerger_synth(StreamingMergerSMTSched#(UInt#(32), VecSz, TotalElms_L0, TDiv#(TotalElms_L1, TotalElms_L0)));
   let sorter_L1 <- mkStreamingMergeNSMTSched(descending);
   return sorter_L1;
endmodule

(* synthesize *)
module mkStreamingMergerDRAM_synth(DRAMStreamingMergerSMTSched#(UInt#(32), VecSz, TotalElms_L1, TDiv#(TotalElms_L2, TotalElms_L1), TDiv#(1024,TDiv#(ElemSz,8))));
   let sorter_L2_dram <- mkDRAMStreamingMergeNSMTSched(descending);
   return sorter_L2_dram;
endmodule



module mkSorter#(HostInterface host, SorterIndication indication)(Sorter);
   
   Reg#(Bool) started <- mkReg(False);
   Reg#(Bit#(64)) cycleCnt <- mkReg(0);
   
   Reg#(Bit#(TLog#(VecSz))) cnt_init <- mkReg(0);
   
   Vector#(VecSz, LFSR#(Bit#(32))) lfsr <- replicateM(mkLFSR_32);
   
   (* fire_when_enabled, no_implicit_conditions *)
   rule increCycle;
      cycleCnt <= cycleCnt + 1;
   endrule

   
   Reg#(Bit#(32)) iterCnt <- mkReg(0);
   Reg#(Bit#(32)) iterCnt_out <- mkReg(0);
   
   Reg#(Bit#(32)) elemCnt <- mkReg(0);
   
   Integer vecSz = valueOf(VecSz);
   Integer totalElms = valueOf(TotalElms_L1);
   
   let sorter_reg <- mkStreamingMergeSort_synth;
   let sorter_bram <- mkStreamingMerger_synth;
   let sorter_dram <- mkStreamingMergerDRAM_synth;
   
////////////////////////////////////////////////////////////////////////////////
/// DRAM Section
////////////////////////////////////////////////////////////////////////////////
   `ifdef SIMULATION
   let ddr4_ctrl_users <- replicateM(mkDDR4Simulator);
   zipWithM_(mkConnection, sorter_dram.dramClients, ddr4_ctrl_users);   
   `else 
   Clock curr_clk <- exposeCurrentClock();
   Reset curr_rst_n <- exposeCurrentReset();
   
   
   // DDR4 C1
   `ifdef VirtexUltrascalePlus // vcu118
   let sys_clk1 = host.tsys_clk1_250mhz;
   `else // vcu108
   let sys_clk1 = host.tsys_clk1_300mhz;
   `endif
   let sys_rst1 <- mkAsyncResetFromCR(20, sys_clk1);

   DDR4_Controller_VCU108 ddr4_ctrl_0 <- mkDDR4Controller_VCU108(defaultValue, clocked_by sys_clk1, reset_by sys_rst1);
      
   Clock ddr4clk0 = ddr4_ctrl_0.user.clock;
   Reset ddr4rstn0 = ddr4_ctrl_0.user.reset_n;
   
   let ddr_cli_300mhz_0 <- mkDDR4ClientSync(sorter_dram.dramClients[0], curr_clk, curr_rst_n, ddr4clk0, ddr4rstn0);
   mkConnection(ddr_cli_300mhz_0, ddr4_ctrl_0.user);
   
   // DDR4 C2
   `ifdef VirtexUltrascalePlus // vcu118
   let sys_clk2 = host.tsys_clk2_250mhz;
   `else
   let sys_clk2 = host.tsys_clk1_300mhz_buf;
   `endif
   let sys_rst2 <- mkAsyncResetFromCR(20, sys_clk2);
      
   DDR4_Controller_VCU108 ddr4_ctrl_1 <- mkDDR4Controller_VCU108(defaultValue, clocked_by sys_clk2, reset_by sys_rst2);
      
   Clock ddr4clk1 = ddr4_ctrl_1.user.clock;
   Reset ddr4rstn1 = ddr4_ctrl_1.user.reset_n;
   
   let ddr_cli_300mhz_1 <- mkDDR4ClientSync(sorter_dram.dramClients[1], curr_clk, curr_rst_n, ddr4clk1, ddr4rstn1);
   mkConnection(ddr_cli_300mhz_1, ddr4_ctrl_1.user);
   `endif
////////////////////////////////////////////////////////////////////////////////
/// End of DRAM Section
////////////////////////////////////////////////////////////////////////////////
   
   mkConnection(sorter_reg.outPipe, sorter_bram.inPipe);
   mkConnection(sorter_bram.outPipe, sorter_dram.inPipe);
   
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
      sorter_reg.inPipe.enq(inV);
   endrule
   
   Reg#(UInt#(32)) prevMax <- mkReg(descending?minBound:maxBound);
   
   Reg#(Bit#(32)) elemCnt_out <- mkReg(0);
   
   Reg#(Bit#(64)) internalUnsortedCnt <- mkReg(0);
   Reg#(Bit#(64)) externalUnsortedCnt <- mkReg(0);
   
   FIFO#(Tuple3#(Bit#(64), Bit#(64), Bit#(64))) indicationFifo <- mkFIFO;
   
   rule getOutput;
      let d = sorter_dram.outPipe.first;
      sorter_dram.outPipe.deq;

      // $display("Sort Result [%d] [@%d] = ", elemCnt_out, cycleCnt, fshow(d));
      `ifdef SIMULATION
      if (!isSorted(d, descending) ) internalUnsortedCnt <= internalUnsortedCnt + 1;
      if (!isSorted(vec(prevMax, head(d)), descending)) externalUnsortedCnt <= externalUnsortedCnt + 1;
      `endif
      if (elemCnt_out + fromInteger(vecSz) >= fromInteger(totalElms) ) begin
         elemCnt_out <= 0;
         prevMax <= descending?minBound:maxBound;
         iterCnt_out <= iterCnt_out - 1;
         if ( iterCnt_out == 1) begin
            indicationFifo.enq(tuple3(internalUnsortedCnt, externalUnsortedCnt, cycleCnt));

         end
      end
      else begin
         elemCnt_out <= elemCnt_out + fromInteger(vecSz);
         prevMax <= last(d);
      end
   endrule
   
   
   rule sendInd;
      let {intCnt,extCnt,cycle} = indicationFifo.first;
      indicationFifo.deq;
      indication.sortingDone(intCnt,extCnt,cycle);
   endrule
      
      
   interface SorterRequest request;
      method Action initSeed(Bit#(32) seed);
         lfsr[cnt_init].seed(seed);
         cnt_init <= cnt_init + 1;
      endmethod
      method Action startSorting(Bit#(32) iter) if (iterCnt == 0&&iterCnt_out==0);
         iterCnt <= iter;
         iterCnt_out <= iter;
         cycleCnt <= 0;
         internalUnsortedCnt <= 0;
         externalUnsortedCnt <= 0;
      endmethod
   endinterface
   
   interface Top_Pins pins;      
      `ifndef SIMULATION
      interface DDR4_Pins_Dual_VCU108 pins_ddr4;
         interface pins_c0 = ddr4_ctrl_0.ddr4;
         interface pins_c1 = ddr4_ctrl_1.ddr4;
      endinterface      
      `endif
   endinterface
   
endmodule
