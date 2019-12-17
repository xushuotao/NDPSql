import DRAMMux::*;
import DDR4Common::*;
import DDR4Controller::*;
import DRAMControllerTypes::*;
import DRAMController::*;
import DDR4Sim::*;
import Connectable::*;

import Vector::*;
import FIFO::*;
import FIFOF::*;

import ClientServer::*;
import ClientServerHelper::*;
   

module mkDRAMMuxTest(Empty);
   Vector#(2, DDR4_User_VCU108) dramCtrs <- replicateM(mkDDR4Simulator);
   Vector#(2, FIFOF#(Tuple2#(Bit#(1), DDRRequest))) reqQ <- replicateM(mkFIFOF); 
   Vector#(2, FIFOF#(DDRResponse)) respQ <- replicateM(mkFIFOF); 
   
   Vector#(2, Client#(Tuple2#(Bit#(1), DDRRequest), DDRResponse)) dramClients = zipWith(toClient, reqQ, respQ);
   
   DRAMMux#(2, 2) dramMux <- mkDRAMMux;
   
   zipWithM_(mkConnection, dramClients, dramMux.dramServers);
   zipWithM_(mkConnection, dramMux.dramControllers, dramCtrs);   

   
   FIFO#(Bit#(1)) rdDone <- mkFIFO;
   FIFO#(Bit#(1)) wrDone <- mkFIFO;
   
   Reg#(Bit#(1)) initCnt <- mkReg(0);
   Reg#(Bool) initReg <- mkReg(False);
   
   Reg#(Bit#(32)) cycleCnt <- mkReg(0);
   (* fire_when_enabled, no_implicit_conditions *)
   rule doIncrCycle;
      cycleCnt <= cycleCnt + 1;
   endrule

   
   rule doInit ( !initReg);
      initCnt <= initCnt + 1;
      rdDone.enq(initCnt);
      if ( initCnt == maxBound) initReg <= True;
   endrule
   
   
   Bit#(32) burstLen = 200;
   Bit#(32) iterLen = 100;
   
   Reg#(Bit#(32)) wrCnt <- mkReg(0);
   Reg#(Bit#(32)) wrIterCnt <- mkReg(0);
   
   Reg#(Bit#(32)) prevCnt_wr <- mkRegU;

   rule doWrTest if (initReg && wrIterCnt < iterLen);
      
      prevCnt_wr <= cycleCnt;
      if ( wrCnt > 0 || wrIterCnt > 0 ) begin
         if ( cycleCnt - 1 != prevCnt_wr ) begin
            $display("Warning:: cycle gap in write request detected, gap = %d, wrCnt = %d, wrIterCnt = %d", cycleCnt - prevCnt_wr, wrCnt, wrIterCnt);
         end
      end

      let ctrId = rdDone.first;
      if ( wrCnt + 1 == burstLen) begin
         wrCnt <= 0;
         wrDone.enq(ctrId);
         rdDone.deq;
         wrIterCnt <= wrIterCnt + 1;
      end
      else begin
         wrCnt <= wrCnt + 1;
      end
      
      reqQ[0].enq(tuple2(ctrId, DDRRequest{writeen:-1, address: extend(wrCnt<<3), datain:zeroExtend(wrCnt+wrIterCnt*burstLen)}));
   endrule
      
   Reg#(Bit#(32)) rdCnt <- mkReg(0);
   Reg#(Bit#(32)) rdIterCnt <- mkReg(0);
   
   Reg#(Bit#(32)) prevCnt_rd <- mkRegU;
   
   FIFO#(Bit#(1)) inflightRdQ <- mkSizedFIFO(3);

   rule doRdReqTest if (initReg);
      
      prevCnt_rd <= cycleCnt;
      if ( rdCnt > 0 || rdIterCnt > 0 ) begin
         if ( cycleCnt - 1 != prevCnt_rd ) begin
            $display("Warning:: cycle gap in rdite request detected, gap = %d, rdCnt = %d, rdIterCnt = %d", cycleCnt - prevCnt_rd, rdCnt, rdIterCnt);
         end
      end

      let ctrId = wrDone.first;
      if ( rdCnt + 1 == burstLen) begin
         rdCnt <= 0;
         wrDone.deq;
         rdIterCnt <= rdIterCnt + 1;
         // rdDone.enq(ctrId);
      end
      else begin
         rdCnt <= rdCnt + 1;
      end
      
      if ( rdCnt == 0 ) inflightRdQ.enq(ctrId);
      
      reqQ[1].enq(tuple2(ctrId, DDRRequest{writeen:0, address: extend(rdCnt<<3), datain:?}));
   endrule
   
   
   
   
   Reg#(Bit#(32)) rdRespCnt <- mkReg(0);
   Reg#(Bit#(32)) prevCnt_rdResp <- mkRegU;
   rule doRdRespTest if (initReg);
      let resp = respQ[1].first; respQ[1].deq;
      
      prevCnt_rdResp <= cycleCnt;
      if ( rdRespCnt > 0) begin
         if ( cycleCnt - 1 != prevCnt_rdResp ) begin
            $display("Warning:: cycle gap detected, gap = %d, rdRespCnt = %d", cycleCnt - prevCnt_rdResp, rdRespCnt);
         end
      end
      
      $display("rdRespCnt = %0d, resp = %h", rdRespCnt, resp);
      if ( truncate(resp) != rdRespCnt ) begin
         $display("Failed: resp = %0d, expected = %0d", resp, rdRespCnt);
         $finish;
      end
      
      if ( (rdRespCnt + 1 )% burstLen == 0 ) begin
         let ctrId = inflightRdQ.first;
         inflightRdQ.deq;
         rdDone.enq(ctrId);
      end

      if ( rdRespCnt + 1 == iterLen*burstLen ) begin
         rdRespCnt <= 0;
         $display("Passed: DRAMMux");
         $finish();
      end
      else begin
         rdRespCnt <= rdRespCnt + 1;
      end

   endrule

   
endmodule
