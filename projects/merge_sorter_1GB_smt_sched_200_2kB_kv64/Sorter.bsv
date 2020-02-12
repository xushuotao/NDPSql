
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

import KeyValue::*;
import LFSR::*;
import DataGen::*;
import SortCheck::*;
import Pipe::*;
import BuildVector::*;
import Bitonic::*;

// import DRAM stuff
import DDR4Controller::*;
import DDR4Common::*;

import DRAMMux::*;

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
   method Action initSeed(Bit#(64) seed);
   method Action startSorting(Bit#(32) iter, Bit#(2) sortness);
   method Action getStatus();
   method Action getDramSorterStatus();
   method Action getDramCntrStatus();
   method Action getDramCntrsDump();
endinterface

interface SorterIndication;
   method Action sortingDone(Bool sumMatch, Bit#(64) int_unsorted_cnt, Bit#(64) ext_unsorted_cnt, Bit#(64) cycles);
   method Action ackStatus(Bit#(32) iterCnt, Bit#(32) inCnt, Bit#(32) iterCnt_out, Bit#(32) outCnt);
   method Action dramSorterStatus(Bit#(64) writes0, Bit#(64) reads0, Bit#(64) readResps0,
                                  Bit#(64) writes1, Bit#(64) reads1, Bit#(64) readResps1);
   method Action dramCtrlStatus(Bit#(64) writes0, Bit#(64) reads0, Bit#(64) readResps0,
                                Bit#(64) writes1, Bit#(64) reads1, Bit#(64) readResps1);
   method Action dramCntrDump0(Bit#(64) req_cycle, Bit#(64) req_addr, Bool req_rnw, Bit#(64) resp_cycle, Bit#(64) resp_addr);
   method Action dramCntrDump1(Bit#(64) req_cycle, Bit#(64) req_addr, Bool req_rnw, Bit#(64) resp_cycle, Bit#(64) resp_addr);
endinterface

interface Sorter;
   interface SorterRequest request;
   interface Top_Pins pins;
endinterface

typedef KVPair#(UInt#(64), UInt#(64)) ElemType;

typedef SizeOf#(ElemType) ElemSz;

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

`ifdef PREFETCH_SZ
typedef `PREFETCH_SZ Prefetch_Sz;
`else
typedef 2048 Prefetch_Sz;
`endif

typedef TDiv#(SortSz_L0,TDiv#(ElemSz,8)) TotalElms_L0;

typedef TDiv#(SortSz_L1,TDiv#(ElemSz,8)) TotalElms_L1;

typedef TDiv#(SortSz_L2,TDiv#(ElemSz,8)) TotalElms_L2;


typedef TDiv#(TotalElms_L1, TotalElms_L0) N_L1;
Bool ascending = True;

Integer vecSz = valueOf(VecSz);
Integer totalElms = valueOf(TotalElms_L2);

(* synthesize *)
module mkStreamingMergeSort_synth(MergeSortSMTSched#(ElemType, VecSz, TotalElms_L0));
   let sorter_L0 <- mkStreamingMergeSortSMTSched(ascending);
   return sorter_L0;
endmodule

(* synthesize *)
module mkStreamingMerger_synth(StreamingMergerSMTSched#(ElemType, VecSz, TotalElms_L0, TDiv#(TotalElms_L1, TotalElms_L0)));
   let sorter_L1 <- mkStreamingMergeNSMTSched(ascending);
   return sorter_L1;
endmodule

(* synthesize *)
module mkStreamingMergerDRAM_synth(DRAMStreamingMergerSMTSched#(ElemType, VecSz, TotalElms_L1, TDiv#(TotalElms_L2, TotalElms_L1), TDiv#(Prefetch_Sz,TDiv#(ElemSz,8))));
   let sorter_L2_dram <- mkDRAMStreamingMergeNSMTSched(ascending);
   return sorter_L2_dram;
endmodule


(* synthesize *)
module mkDataGen_synth(DataGen#(VecSz, ElemType));
   function KVPair#(UInt#(64), UInt#(64)) genElm(Bit#(32) v) = KVPair{key:unpack(zeroExtend(v)), value:unpack(zeroExtend(v))};
   let feed = 128'h80000000000000000000000000000043;
   function module#(LFSR#(Bit#(128))) mkLFSR_128() = mkFeedLFSR(feed);

   DataGen#(VecSz, ElemType) dataGen <- mkDataGen(totalElms,
                                                   mkLFSR_128,
                                                   genElm
                                                   );

   return dataGen;
endmodule

(* synthesize *)
module mkSortCheck_synth(SortCheck#(VecSz, ElemType));
   SortCheck#(VecSz, ElemType) check <- mkSortCheck(totalElms, ascending);
   return check;
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
   
   let sorter_reg <- mkStreamingMergeSort_synth;
   let sorter_bram <- mkStreamingMerger_synth;
   let sorter_dram <- mkStreamingMergerDRAM_synth;
   
   DRAMMux#(2, 2) dramMux <- mkRwDualDRAMMux;
   zipWithM_(mkConnection, sorter_dram.dramMuxClients, dramMux.dramServers);
   
   Vector#(2, DDR4Client) ddr4Clients = ?;
   `ifdef DEBUG
   Vector#(2, DDR4TrafficCapture) trafficCaps <- replicateM(mkDDR4TrafficCapture);
   zipWithM_(mkConnection, dramMux.dramControllers, vec(trafficCaps[0].ddr4Server,trafficCaps[1].ddr4Server) );
   ddr4Clients = vec(trafficCaps[0].ddr4Client, trafficCaps[1].ddr4Client);
   `else
   ddr4Clients = dramMux.dramControllers;
   `endif
   
////////////////////////////////////////////////////////////////////////////////
/// DRAM Section
////////////////////////////////////////////////////////////////////////////////
   `ifdef SIMULATION
   let ddr4_ctrl_users <- replicateM(mkDDR4Simulator);
   zipWithM_(mkConnection, ddr4Clients, ddr4_ctrl_users);   
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
   
   // let ddr_cli_300mhz_0 <- mkDDR4ClientSync(sorter_dram.dramClients[0], curr_clk, curr_rst_n, ddr4clk0, ddr4rstn0);
   let ddr_cli_300mhz_0 <- mkDDR4ClientSync(ddr4Clients[0], curr_clk, curr_rst_n, ddr4clk0, ddr4rstn0);

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
   
   // let ddr_cli_300mhz_1 <- mkDDR4ClientSync(sorter_dram.dramClients[1], curr_clk, curr_rst_n, ddr4clk1, ddr4rstn1);
   let ddr_cli_300mhz_1 <- mkDDR4ClientSync(ddr4Clients[1], curr_clk, curr_rst_n, ddr4clk1, ddr4rstn1);
   mkConnection(ddr_cli_300mhz_1, ddr4_ctrl_1.user);
   `endif
////////////////////////////////////////////////////////////////////////////////
/// End of DRAM Section
////////////////////////////////////////////////////////////////////////////////
   
   mkConnection(sorter_reg.outPipe, sorter_bram.inPipe);
   mkConnection(sorter_bram.outPipe, sorter_dram.inPipe);
   
   let inputGen <- mkDataGen_synth;
   
   mkConnection(inputGen.dataPort, sorter_reg.inPipe);
   
   let outputChk <- mkSortCheck_synth;
   
   mkConnection(sorter_dram.outPipe, outputChk.inPipe);

   rule getOutput;
      let {internalUnsortedCnt, externalUnsortedCnt} <- outputChk.checkDone;
      let sumIn <- inputGen.getSum;
      let sumOut <- outputChk.getSum;
      $display("done = %d, %d", sumIn, sumOut);
      indication.sortingDone(sumIn == sumOut, internalUnsortedCnt, externalUnsortedCnt, cycleCnt);
   endrule
   
   `ifdef Debug
   rule doDumpInd0;
      let {req_cycle, req_addr, req_rnw, resp_cycle, resp_addr} <- trafficCaps[0].dumpResp;
      indication.dramCntrDump0(req_cycle, req_addr, req_rnw, resp_cycle, resp_addr);
   endrule
   
   rule doDumpInd1;
      let {req_cycle, req_addr, req_rnw, resp_cycle, resp_addr} <- trafficCaps[1].dumpResp;
      indication.dramCntrDump1(req_cycle, req_addr, req_rnw, resp_cycle, resp_addr);
   endrule
   `endif
      
   Reg#(Maybe#(Bit#(64))) lowerReg <- mkReg(tagged Invalid);
   interface SorterRequest request;
      method Action initSeed(Bit#(64) seed);
         if ( lowerReg matches tagged Valid .lower ) begin
            inputGen.initSeed(unpack({seed,lower}));
            lowerReg <= tagged Invalid;
         end
         else
            lowerReg <= tagged Valid seed;
      endmethod
      method Action startSorting(Bit#(32) iter, Bit#(2) sortness);// if (iterCnt == 0&&iterCnt_out==0);
         cycleCnt <= 0;
         inputGen.start(iter, sortness);
         outputChk.start(iter);
      endmethod
   
      method Action getStatus();
         let {iterCnt, elemCnt} = inputGen.status;
         let {iterCnt_out, elemCnt_out} = outputChk.status;
         indication.ackStatus(iterCnt, elemCnt, iterCnt_out, elemCnt_out);
      endmethod
   
      method Action getDramSorterStatus();
         `ifdef Debug
         let statusV = sorter_dram.debug.dumpStatus;
         let {writes0, reads0, readResps0} = statusV[0];
         let {writes1, reads1, readResps1} = statusV[1];
         indication.dramSorterStatus(writes0, reads0, readResps0,
                                     writes1, reads1, readResps1);
         `endif
      endmethod
   
   
      method Action getDramCntrStatus();
         `ifdef Debug
         let {writes0, reads0, readResps0} = trafficCaps[0].status;
         let {writes1, reads1, readResps1} = trafficCaps[1].status;
         indication.dramCtrlStatus(writes0, reads0, readResps0,
                                   writes1, reads1, readResps1);
         `endif
      endmethod
   
      method Action getDramCntrsDump();
         `ifdef Debug
         trafficCaps[0].dumpTraffic;
         trafficCaps[1].dumpTraffic;
         `endif
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
