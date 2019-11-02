
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
import Connectable::*;
import HostInterface::*;

import GetPut::*;
import ClientServerHelper::*;

import DelayPipe::*;
import Assert::*;
import URAMCore::*;


interface UltraRAMPerfRequest;
   method Action startWriteDram(Bit#(64) numCL, Bit#(32) stride);
   method Action startReadDram(Bit#(64) numCL, Bit#(32) stride);
endinterface

interface UltraRAMPerfIndication;
   method Action writeDone(Bit#(32) cycles_0, Bit#(32) cycles_1);
   method Action readDone(Bit#(32) cycles_0, Bit#(32) missMatch_0, Bit#(32) cycles_1, Bit#(32) missMatch_1);
endinterface

interface UltraRAMPerf;
   interface UltraRAMPerfRequest request;
endinterface

typedef 5 PPL;

module mkUltraRAMPerf#(UltraRAMPerfIndication indication)(UltraRAMPerf);
   
   Reg#(Bool) started <- mkReg(False);
   Reg#(Bit#(32)) cycleCnt <- mkReg(0);
   
   rule increCycle (started);
      cycleCnt <= cycleCnt + 1;
   endrule
   
   URAM_DUAL_PORT#(Bit#(17), Bit#(512)) ram <- mkURAMCore2(valueOf(PPL));

   
   Vector#(2,FIFO#(Bit#(32))) cntRdMaxQ <- replicateM(mkFIFO());
   Vector#(2,FIFO#(Bit#(32))) respMaxQ <- replicateM(mkFIFO());
   Vector#(2,FIFO#(Bit#(32))) cntWrMaxQ <- replicateM(mkFIFO());
   
   Vector#(2,FIFO#(Tuple2#(Bit#(32),Bit#(32)))) readDoneQs <- replicateM(mkFIFO());
   Vector#(2, FIFO#(Bit#(32))) writeDoneQs <- replicateM(mkFIFO());
   
   Reg#(Bit#(5)) strideReg <- mkReg(0);
   


   for (Integer i = 0; i < 2; i = i + 1) begin
      Reg#(Bit#(16)) cntRd <- mkReg(0);
      DelayPipe#(TAdd#(PPL,1),void) rdReq <- mkDelayPipe;
      rule doRdReq;
         let cntRdMax = cntRdMaxQ[i].first();
         $display("(%t)Read Req cntRd = %d, cntRdMax = %d", $time, cntRd, cntRdMax);

         if ( zeroExtend(cntRd) == cntRdMax -1  ) begin
            cntRd <= 0;
            cntRdMaxQ[i].deq();
         end
         else begin
            cntRd <= cntRd + 1;
         end
 
         if ( i == 0 ) begin
            ram.a.put(False, {cntRd,1'b0}, ?);
         end
         else if ( i== 1) begin
            ram.b.put(False, {cntRd,1'b1}, ?);
         end
         rdReq.enq(?);
      endrule
      
      Reg#(Bit#(32)) respCnt <- mkReg(0);
      Reg#(Bit#(32)) missCnt <- mkReg(0);
      
      rule doResp;
         let respMax = respMaxQ[i].first;
         if ( zeroExtend(respCnt) < respMax && rdReq.notEmpty ) begin
            respCnt <= respCnt + 1;
            let d = ?;
            if ( i == 0 ) begin
               d = ram.a.read;
            end
            else begin
               d = ram.b.read;
            end

            dynamicAssert(d == zeroExtend(respCnt), "ram result must match");
            // let d <- toGet(resps[i]).get();
            if ( d != zeroExtend(respCnt) ) begin
               missCnt <= missCnt + 1;
            end
            $display("(%t)Get Val[%d] from %d = %h", $time, respCnt, i, d);
         end
         else if ( zeroExtend(respCnt) == respMax) begin
            readDoneQs[i].enq(tuple2(cycleCnt, missCnt));
            respCnt <= 0;
            missCnt <= 0;
            respMaxQ[i].deq();
         end
      endrule
      

      Reg#(Bit#(16)) cntWr <- mkReg(0);
      
      rule doWrReq;
         let cntWrMax = cntWrMaxQ[i].first();
         $display("(%t)Write Req[%d] cntWr = %d, cntWrMax = %d", $time, i, cntWr, cntWrMax);
         if ( zeroExtend(cntWr) == cntWrMax-1 ) begin
            cntWr <= 0;
            cntWrMaxQ[i].deq();
            writeDoneQs[i].enq(cycleCnt);
         end
         else begin
            cntWr <= cntWr + 1;
         end
            
         if ( i == 0 ) begin
            ram.a.put(True, {cntWr,1'b0}, zeroExtend(cntWr));
         end
         else if (i==1) begin
            ram.b.put(True, {cntWr,1'b1}, zeroExtend(cntWr));
         end
      endrule
   end
         
   rule doRdDone;
      let rdDone_0 <- toGet(readDoneQs[0]).get();
      let rdDone_1 <- toGet(readDoneQs[1]).get();
      indication.readDone(tpl_1(rdDone_0),tpl_2(rdDone_0),tpl_1(rdDone_1),tpl_2(rdDone_1));
   endrule
   
   rule doWrDone;
      let wrDone_0 <- toGet(writeDoneQs[0]).get();
      let wrDone_1 <- toGet(writeDoneQs[1]).get();
      indication.writeDone(wrDone_0,wrDone_1);
   endrule
   
      
      
   interface UltraRAMPerfRequest request;   
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
         cycleCnt <= 0;
         strideReg <= truncate(stride);
         started <= True;
         cntWrMaxQ[0].enq(truncate(numCL));
         cntWrMaxQ[1].enq(truncate(numCL));
      endmethod
   endinterface

endmodule
