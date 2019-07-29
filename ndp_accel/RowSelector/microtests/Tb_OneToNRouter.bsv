import Pipe::*;
import Vector::*;
import OneToNRouter::*;

typedef 120 Num;

import "BDPI" function Bit#(32) log2_c(Bit#(32) x);
import "BDPI" function Action rand_seed();
import "BDPI" function ActionValue#(Bit#(32)) randu32(Bit#(32) dummy);
import "BDPI" function ActionValue#(Bit#(64)) randu64(Bit#(32) dummy);


module mkTb_OneToNRouter(Empty);
   OneToNRouter#(Num, Bit#(TLog#(Num))) router <- mkOneToNRouterPipelined;
   
   Reg#(Bool) init <- mkReg(False);
   
   rule doInit (!init);
      init <= True;
      rand_seed();
   endrule
   
   Bit#(32) totalReqs = 1024;
   
   Reg#(Bit#(32)) reqCnt <- mkReg(0);
   
   rule doReq (init && reqCnt < totalReqs);
      let v <- randu32(0);
      reqCnt <= reqCnt + 1;
      Bit#(TLog#(Num)) id = truncate(v)%fromInteger(valueOf(Num));
      // if ( id >= fromInteger(valueOf(Num)) ) minus
      $display("Input to dest %d", id);
      router.inPort.enq(tuple2(id, id));
   endrule
   
   Reg#(Bit#(32)) respCnt <- mkReg(0);
   for ( Integer i = 0; i < valueOf(Num); i = i + 1) begin
      rule checkResp;
         let v = router.outPorts[i].first();
         router.outPorts[i].deq();
         
         respCnt <= respCnt + 1;
         
         if ( v != fromInteger(i)) begin
            $display("Failed:: Router output %d found incorrect data", i);
            $finish();
         end
         else if ( respCnt + 1 == totalReqs) begin
            $display("Passed");
            $finish();
         end
      endrule
   end
   
endmodule
