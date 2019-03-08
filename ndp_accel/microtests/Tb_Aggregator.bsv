import Vector::*;
import BuildVector::*;
import Aggregator::*;
import PECommon::*;

import "BDPI" function Bit#(32) log2_c(Bit#(32) x);
import "BDPI" function Action rand_seed();
import "BDPI" function ActionValue#(Bit#(32)) randu32(Bit#(32) dummy);
import "BDPI" function ActionValue#(Bit#(64)) randu64(Bit#(32) dummy);
import "BDPI" function Action init_test_aggr(Bool isSigned);
import "BDPI" function Action inject_test_aggr(Bit#(64) x, Bit#(8) mask, Bit#(64) group);
import "BDPI" function Bool check_test_aggr(Bit#(64) my_min, Bit#(64) my_max, Bit#(64) my_sum, Bit#(64) my_cnt, Bit#(64) group, Bool mask);

Bool doRandSeq = False;

                 
(* synthesize *)
module mkTb_Aggregator();
   Reg#(Bit#(32)) testCnt <- mkReg(0);
   Reg#(Bit#(32)) cycle <- mkReg(0);
   
   let testEng <- mkAggregator;
   
   Reg#(Bool) configured <- mkReg(False);
   
   Reg#(Bit#(32)) testLength <- mkRegU;
   
   Bool isSigned = True;
   
   rule incrCycle;
      cycle <= cycle + 1;
   endrule
   
   rule configEng (!configured);
      testEng.configure(isSigned);
      init_test_aggr(isSigned);
      configured <= True;
      // rand_seed();
      let randv <- randu64(0);
      testLength <= 1000;//truncate(randv%1000+1);
   endrule
   
  
   
   rule testInput (testCnt < testLength && configured);
      Vector#(16, Bit#(64)) vals <- mapM(randu64, genWith(fromInteger));
      Vector#(8, Bit#(64)) data = take(vals);
      Vector#(8, GroupIdT) groupIds = map(truncate,takeAt(8 ,vals));
      let randBits <- randu64(16);
      Bit#(8) mask = truncate(randBits);
             
      let last = (testCnt == testLength-1);
      
      for (Integer i = 0; i < 8; i=i+1 ) begin
         inject_test_aggr(vals[i], extend(mask[i]), extend(groupIds[i]));
      end

      // Vector#(8, Bit#(64)) vals = replicate(100);
      testEng.put(FlitT{data: data,
                        groupIds: groupIds,
                        mask: mask,
                        last: last});
      testCnt <= testCnt + 1;
      // $display(fshow(vals));
   endrule
   Reg#(Bit#(64)) count <- mkReg(0);
   
   rule testOutput;
      let v <- testEng.get;
      $display(fshow(v));
      Bool result = True;
      for (Integer i = 0; i < 8; i=i+1 ) begin
         result = result && check_test_aggr(v[i].min, v[i].max, v[i].sum, v[i].cnt, fromInteger(i), v[i].valid);
         if ( !result ) begin
            $display("FAILED: test on group %d value mismatch", i);
         end
      end
      if (result) $display("Passed: Aggregator test");
      $display("cycle = %d, testLength = %d", cycle, testLength);
      $finish();
   endrule
      
endmodule
