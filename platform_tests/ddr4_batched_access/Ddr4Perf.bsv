
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

import Arith::*;
import FIFO::*;
import Vector::*;
import DRAMController::*;
import Connectable::*;
import HostInterface::*;

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
import GetPutWithClocks::*;
import ClientServerHelper::*;
import DRAMControllerTypes::*;

import DRAMBatchRdServer::*;

import LFSR::*;


interface Top_Pins;
   `ifndef SIMULATION
   interface DDR4_Pins_Dual_VCU108 pins_ddr4;
   `endif
endinterface



interface Ddr4PerfRequest;
   method Action startWriteDram(Bit#(64) numCL, Bit#(32) stride);
   method Action startReadDram(Bit#(64) numCL, Bit#(32) stride);
endinterface

interface Ddr4PerfIndication;
   method Action writeDone(Bit#(32) cycles_0, Bit#(32) cycles_1);
   method Action readDone(Bit#(32) cycles_0, Bit#(32) missMatch_0, Bit#(32) cycles_1, Bit#(32) missMatch_1);
endinterface

interface Ddr4Perf;
   interface Ddr4PerfRequest request;
   interface Top_Pins pins;
endinterface


typedef 4 BatchSz;


module mkDdr4Perf#(HostInterface host, Ddr4PerfIndication indication)(Ddr4Perf);
   
   // Vector#(2,FIFO#(DDRRequest)) reqs <- replicateM(mkFIFO());
   // Vector#(2,FIFO#(DDRResponse)) resps <- replicateM(mkFIFO());

   
   Vector#(2,FIFO#(DRAMBatchRdRequest#(BatchSz,28,6))) reqs <- replicateM(mkFIFO());
   Vector#(2,FIFO#(DRAMBatchRdResponse#(BatchSz,8))) resps <- replicateM(mkFIFO());
      
   Vector#(2,DRAMBatchRdClient#(BatchSz, 28, 8, 6)) batch_clients = zipWith(toClient, reqs, resps);
   
   Vector#(2, DRAMRdBatch#(BatchSz, 28, 8, 6)) dramBatchServers;
   
      
   function DDR4Client getDRAMClient(DRAMRdBatch#(n, a, s, d) v) = v.ddrClient;
   function DRAMBatchRdServer#(n, a, s, d) getBatchServer(DRAMRdBatch#(n, a, s, d) v) = v.batchServer;
   
   `ifdef SIMULATION
   Vector#(2, DDR4_User_VCU108) ddr4_ctrl_users <- replicateM(mkDDR4Simulator);
   dramBatchServers <- replicateM(mkDRAMBatchServer);

   zipWithM_(mkConnection, map(getDRAMClient, dramBatchServers), ddr4_ctrl_users);
   zipWithM_(mkConnection, map(getBatchServer, dramBatchServers), batch_clients);
   `else 
   Clock curr_clk <- exposeCurrentClock();
   Reset curr_rst_n <- exposeCurrentReset();
   
   
   // DDR4 C1
   let sys_clk1_300 = host.tsys_clk1_300mhz;
   let sys_rst1_300 <- mkAsyncResetFromCR(20, sys_clk1_300);

   DDR4_Controller_VCU108 ddr4_ctrl_0 <- mkDDR4Controller_VCU108(defaultValue, clocked_by sys_clk1_300, reset_by sys_rst1_300);
      
   Clock ddr4clk0 = ddr4_ctrl_0.user.clock;
   Reset ddr4rstn0 = ddr4_ctrl_0.user.reset_n;
   
   dramBatchServers[0] <- mkDRAMBatchServer(clocked_by ddr4clk0, reset_by ddr4rstn0);
   
   mkConnection(dramBatchServers[0].ddrClient, ddr4_ctrl_0.user, clocked_by ddr4clk0, reset_by ddr4rstn0);
   // mkConnectionWithClocks(curr_clk, curr_rst_n, ddr4clk0, ddr4rstn0, batch_clients[0], dramBatchServers[0].batchServer);
   
   // let ddr_cli_300mhz_0 <- mkDDR4ClientSync(ddr_clients[0], curr_clk, curr_rst_n, ddr4clk0, ddr4rstn0);
   // mkConnection(ddr_cli_300mhz_0, ddr4_ctrl_0.user);
   
   // DDR4 C2
   let sys_clk2_300 = host.tsys_clk1_300mhz_buf;
   let sys_rst2_300 <- mkAsyncResetFromCR(20, sys_clk2_300);
   
   DDR4_Controller_VCU108 ddr4_ctrl_1 <- mkDDR4Controller_VCU108(defaultValue, clocked_by sys_clk2_300, reset_by sys_rst2_300);
      
   Clock ddr4clk1 = ddr4_ctrl_1.user.clock;
   Reset ddr4rstn1 = ddr4_ctrl_1.user.reset_n;
   
   dramBatchServers[1] <- mkDRAMBatchServer(clocked_by ddr4clk1, reset_by ddr4rstn1);
   
   mkConnection(dramBatchServers[1].ddrClient, ddr4_ctrl_1.user, clocked_by ddr4clk1, reset_by ddr4rstn1);
   // mkConnectionWithClocks(curr_clk, curr_rst_n, ddr4clk1, ddr4rstn1, batch_clients[1], dramBatchServers[1].batchServer);
   
   // let ddr_cli_300mhz_1 <- mkDDR4ClientSync(ddr_clients[1], curr_clk, curr_rst_n, ddr4clk1, ddr4rstn1);
   // mkConnection(ddr_cli_300mhz_1, ddr4_ctrl_1.user);
   
   zipWithM_(mkConnectionWithClocks2, batch_clients, map(getBatchServer, dramBatchServers));
   
   `endif
   
   Reg#(Bool) started <- mkReg(False);
   Reg#(Bit#(32)) cycleCnt <- mkReg(0);
   
   rule increCycle (started);
      cycleCnt <= cycleCnt + 1;
   endrule

   
   Vector#(2,FIFO#(Bit#(32))) cntRdMaxQ <- replicateM(mkFIFO());
   Vector#(2,FIFO#(Bit#(32))) respMaxQ <- replicateM(mkFIFO());
   Vector#(2,FIFO#(Bit#(32))) cntWrMaxQ <- replicateM(mkFIFO());
   
   Vector#(2,FIFO#(Tuple2#(Bit#(32),Bit#(32)))) readDoneQs <- replicateM(mkFIFO());
   Vector#(2, FIFO#(Bit#(32))) writeDoneQs <- replicateM(mkFIFO());
   
   Reg#(Bit#(5)) strideReg <- mkReg(0);
   

   function Bit#(TAdd#(TAdd#(a,b),c)) concat3(Bit#(a) x, Bit#(b) y, Bit#(c) z) = {x,y,z};
      
   
   for (Integer i = 0; i < 2; i = i + 1) begin
      Vector#(BatchSz, LFSR#(Bit#(32))) vrandAddrGen <- replicateM(mkLFSR_32);
      
      function ActionValue#(Bit#(32)) getRandV(LFSR#(Bit#(32)) ifc);
      actionvalue
         ifc.next();
         return ifc.value;
      endactionvalue
      endfunction
         
      Reg#(Bit#(32)) cntRd <- mkReg(0);
      
      Reg#(Bit#(8)) baseBankAddr <- mkReg(0);
      rule doRdReq;
         let cntRdMax = cntRdMaxQ[i].first();
         $display("(%t)Read Req cntRd = %d, cntRdMax = %d", $time, cntRd, cntRdMax);
         if ( cntRd < cntRdMax ) begin
            Vector#(BatchSz, Bit#(32)) vrand32<- mapM(getRandV, vrandAddrGen);
         
            Vector#(BatchSz, Bit#(10)) vcolAddr = map(truncate, zipWith(bitwiseand, 
                                                                        vrand32,
                                                                        replicate('b1000)));
            Vector#(BatchSz, Bit#(15)) vrowAddr = replicate(truncate(cntRd));//map(truncateLSB, vrand32);
            Vector#(BatchSz, Bit#(3)) vbankAddr = zipWith(add,
                                                          replicate(truncate(baseBankAddr)), 
                                                          map(fromInteger, genVector)); 
            baseBankAddr <= baseBankAddr + fromInteger(valueOf(BatchSz));
         
            Vector#(BatchSz, Bit#(28)) vAddr = zipWith3(concat3, vbankAddr, vrowAddr, vcolAddr);

            $display("ctrl_%d, vcolAddr =  ", i, fshow(vcolAddr));         
            $display("ctrl_%d, vrowAddr =  ", i, fshow(vrowAddr));
            $display("ctrl_%d, baseBandaddr = %h  ", i, baseBankAddr, fshow(vbankAddr));

            //reqs[i].enq(DDRRequest{address: extend(cntRd<<(3+strideReg)), writeen: 80'b0, datain:?});
            DRAMBatchRdRequest#(BatchSz, 28, 6) batchreq = DRAMBatchRdRequest{addrV: vAddr,
                                                                              sftV: replicate(0)};
            reqs[i].enq(batchreq);
            $display("ctrl_%d ",i, fshow(batchreq));
            cntRd <= cntRd + 1;
         end
         else begin
            cntRd <= 0;
            cntRdMaxQ[i].deq();
         end
      endrule
      
      Reg#(Bit#(32)) respCnt <- mkReg(0);
      Reg#(Bit#(32)) missCnt <- mkReg(0);
      
      rule doResp;
         let respMax = respMaxQ[i].first;
         if ( respCnt < respMax ) begin
            respCnt <= respCnt + 1;
            let d <- toGet(resps[i]).get();
            // if ( truncate(d) != respCnt ) begin
            //    missCnt <= missCnt + 1;
            // end
            $display("(%t)Get Val[%d] from %d = %h", $time, respCnt, i, d);
         end
         else begin
            readDoneQs[i].enq(tuple2(cycleCnt, missCnt));
            respCnt <= 0;
            missCnt <= 0;
            respMaxQ[i].deq();
         end
      endrule
   end
      
   rule doRdDone;
      let rdDone_0 <- toGet(readDoneQs[0]).get();
      let rdDone_1 <- toGet(readDoneQs[1]).get();
      indication.readDone(tpl_1(rdDone_0),tpl_2(rdDone_0),tpl_1(rdDone_1),tpl_2(rdDone_1));
   endrule
      
      
   interface Ddr4PerfRequest request;   
      method Action startReadDram(Bit#(64) numCL, Bit#(32) stride);
         $display("(%t)Read Req numCL = %h", $time, numCL);
         cycleCnt <= 0;
         strideReg <= truncate(stride);
         started <= True;
         cntRdMaxQ[0].enq(truncate(numCL));
         respMaxQ[0].enq(truncate(numCL));
         cntRdMaxQ[1].enq(truncate(numCL));
         respMaxQ[1].enq(truncate(numCL));
      endmethod
      
      method Action startWriteDram(Bit#(64) numCL, Bit#(32) stride);
         $display("(%t)Write Req numCL = %h", $time, numCL);
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
