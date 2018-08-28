
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
import FIFOF::*;
import Vector::*;
import Connectable::*;
import HostInterface::*;
import Assert::*;

import GetPut::*;
import ClientServer::*;
import ClientServerHelper::*;

// flash controller stuff
import AuroraCommon::*;
import AuroraImportFmc1::*;
import FlashCtrlVirtex::*;
import FlashCtrlModel::*;

//flash test bench
import FlashTestBench::*;


interface Top_Pins;
   `ifndef SIMULATION
   interface Aurora_Pins#(4) aurora_fmc1;
   interface Aurora_Clock_Pins aurora_clk_fmc1;
   interface Aurora_Pins#(4) aurora_fmc2;
   interface Aurora_Clock_Pins aurora_clk_fmc2;
   // interface DDR4_Pins_Dual_VCU108 pins_ddr4;
   `endif
endinterface


interface FlashTestRequest;
   method Action start(Bit#(64) randSeed);
   method Action auroraStatus();
endinterface



interface FlashTestIndication;
   method Action eraseDone1(Bit#(64) cycles, Bit#(32) erased_blocks, Bit#(32) bad_blocks);
   method Action writeDone1(Bit#(64) cycles, Bit#(32) writen_pages);
   method Action readDone1(Bit#(64) cycles, Bit#(32) read_pages, Bit#(32) wrong_words, Bit#(32) wrong_pages);
   method Action auroraStatus1(Bit#(8) channel_up, Bit#(8) lane_up);
   method Action eraseDone2(Bit#(64) cycles, Bit#(32) erased_blocks, Bit#(32) bad_blocks);
   method Action writeDone2(Bit#(64) cycles, Bit#(32) writen_pages);
   method Action readDone2(Bit#(64) cycles, Bit#(32) read_pages, Bit#(32) wrong_words, Bit#(32) wrong_pages);
   method Action auroraStatus2(Bit#(8) channel_up, Bit#(8) lane_up);

endinterface

interface FlashTest;
   interface FlashTestRequest request;
   interface Top_Pins pins;
endinterface


module mkFlashTest#(HostInterface host, FlashTestIndication indication)(FlashTest);
   
   Clock clk110 = host.derivedClock;
   Reset rst110 = host.derivedReset;
////////////////////////////////////////////////////////////////////////////////
/// Flash Controllers Instantiation 
////////////////////////////////////////////////////////////////////////////////
   Vector#(2,FlashCtrlVirtexIfc) flashCtrls;
   Vector#(2,GtClockImportIfc) gtx_clk_fmcs <- replicateM(mkGtClockImport);
   `ifdef BSIM
   flashCtrls[0] <- mkFlashCtrlModel(gtx_clk_fmcs[0].gt_clk_p_ifc, gtx_clk_fmcs[0].gt_clk_n_ifc, clk110, rst110);
   flashCtrls[1] <- mkFlashCtrlModel(gtx_clk_fmcs[1].gt_clk_p_ifc, gtx_clk_fmcs[1].gt_clk_n_ifc, clk110, rst110);
   `else
   flashCtrls[0] <- mkFlashCtrlVirtex1(gtx_clk_fmcs[0].gt_clk_p_ifc, gtx_clk_fmcs[0].gt_clk_n_ifc, clk110, rst110);
   flashCtrls[1] <- mkFlashCtrlVirtex2(gtx_clk_fmcs[1].gt_clk_p_ifc, gtx_clk_fmcs[1].gt_clk_n_ifc, clk110, rst110);
   `endif
   
   Vector#(2, FlashTestBenchIfc) flashTests;
   flashTests[0] <- mkFlashTestBench(flashCtrls[0].user);
   flashTests[1] <- mkFlashTestBench(flashCtrls[1].user);
   
   rule eraseDone1Ind;
      let v <- flashTests[0].eraseDone;
      indication.eraseDone1(v.cycles, v.erased_blocks, v.bad_blocks);
   endrule
   
   rule writeDone1Ind;
      let v <- flashTests[0].writeDone;
      indication.writeDone1(v.cycles, v.written_pages);
   endrule

   rule readDone1Ind;
      let v <- flashTests[0].readDone;
      indication.readDone1(v.cycles, v.read_pages, v.wrong_words, v.wrong_pages);
   endrule
   
   rule eraseDone2Ind;
      let v <- flashTests[1].eraseDone;
      indication.eraseDone2(v.cycles, v.erased_blocks, v.bad_blocks);
   endrule
   
   rule writeDone2Ind;
      let v <- flashTests[1].writeDone;
      indication.writeDone2(v.cycles, v.written_pages);
   endrule

   rule readDone2Ind;
      let v <- flashTests[1].readDone;
      indication.readDone2(v.cycles, v.read_pages, v.wrong_words, v.wrong_pages);
   endrule

      
      
   interface FlashTestRequest request;   
      method Action auroraStatus();
      `ifndef SIMULATION
         indication.auroraStatus1(extend(flashCtrls[0].auroraStatus.channel_up), extend(flashCtrls[0].auroraStatus.lane_up));
         indication.auroraStatus2(extend(flashCtrls[1].auroraStatus.channel_up), extend(flashCtrls[1].auroraStatus.lane_up));
       `else
         indication.auroraStatus1(1, 3);
         indication.auroraStatus2(1, 3);
       `endif
      endmethod
      method Action start(Bit#(64) randSeed);
         flashTests[0].start(randSeed);
         flashTests[1].start(randSeed);
      endmethod
   endinterface

   interface Top_Pins pins;      

      `ifndef SIMULATION
      interface Aurora_Pins aurora_fmc1 = flashCtrls[0].aurora;
      interface Aurora_Clock_Pins aurora_clk_fmc1 = gtx_clk_fmcs[0].aurora_clk;
      interface Aurora_Pins aurora_fmc2 = flashCtrls[1].aurora;
      interface Aurora_Clock_Pins aurora_clk_fmc2 = gtx_clk_fmcs[1].aurora_clk;

      // interface ddr4_clock = ddr4_clocks.ddr4_sys_clk;
      // interface DDR4_Pins_Dual_VCU108 pins_ddr4;
      //    interface pins_c0 = ddr4_ctrl_0.ddr4;
      //    interface pins_c1 = ddr4_ctrl_1.ddr4;
      // endinterface      
      `endif
   endinterface
   
endmodule
