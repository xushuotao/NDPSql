/*
Copyright (C) 2018

Shuotao Xu <shuotao@csail.mit.edu>

Permission is hereby granted, free of charge, to any person obtaining a copy of this
software and associated documentation files (the "Software"), to deal in the Software
without restriction, including without limitation the rights to use, copy, modify,
merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be included in all copies
or substantial portions of the Software.  

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE
OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

import Vector::*;
import BuildVector::*;
import NDPCommon::*;
import Pipe::*;
import FIFO::*;
import SimdMul64::*;
import GetPut::*;

import "BDPI" function Bit#(32) log2_c(Bit#(32) x);
import "BDPI" function Action rand_seed();
import "BDPI" function ActionValue#(Bit#(32)) randu32(Bit#(32) dummy);
import "BDPI" function ActionValue#(Bit#(64)) randu64(Bit#(32) dummy);

Bool isSigned = True;

(* synthesize *)
module mkTb_SimdMul64();
   Bit#(64) most_negative = 1<<63;
   
   SimdMul64 testEng <- mkSimdMul64;
   
   Reg#(Bit#(64)) testCnt <- mkReg(0);
   Reg#(Bit#(64)) resCnt <- mkReg(0);
   
   Bit#(64) testLength = 1000;
   
   FIFO#(Tuple4#(Vector#(2, Bit#(64)), Bit#(1), Bool, Bool)) operandQ <- mkSizedFIFO(64);
   
   Vector#(4, Tuple4#(Vector#(2, Bit#(64)), Bit#(1), Bool, Bool)) testVec = vec(tuple4(vec(most_negative, -1), 1, False, True),
                                                                                tuple4(vec(most_negative, -1), 1, False, True),
                                                                                tuple4(vec(-1,-1), 1, False, True),
                                                                                tuple4(vec(most_negative-1, most_negative-1), 1, False, True));
   
   rule doTest if ( testCnt < testLength + 4) ;
      testCnt <= testCnt + 1;
      
      let {operands, mode, mullo, isSigned} = testVec[testCnt];
      
      if ( testCnt >= 4) begin
         operands <- mapM(randu64, genWith(fromInteger));
         let rand_32 <- randu32(0);
         mode = rand_32[0];
         isSigned = unpack(rand_32[1]);
         mullo = unpack(rand_32[2]);
      end
      // Vector#(2, Bit#(64)) operands = vec(1<<63,(1<<63)-1);
      testEng.req(operands[0], operands[1], mode, mullo, isSigned);
      operandQ.enq(tuple4(operands, mode, mullo, isSigned));
   endrule
   

   rule doResult;
      resCnt <= resCnt + 1;
      
      let tester = testEng.product;
      testEng.deqResp;
      
      let {operands, mode, mullo, isSigned} <- toGet(operandQ).get;
      
      let testee = combSimdMul64(operands[0], operands[1], mode, mullo, isSigned);

      $display("(@%t) Test: %h simdx %h = %h, testId = %d, mode = %d, mullo = %d, isSigned = %d", $time, operands[0], operands[1], tester, resCnt, mode, mullo, isSigned);
      $display("(@%t) Ref : %h simdx %h = %h, testId = %d, mode = %d, mullo = %d, isSigned = %d", $time, operands[0], operands[1], testee, resCnt, mode, mullo, isSigned);

      // $display("(@%t) Test[%d]: %b times %b = %d (expected %b)", $time, resCnt, operands[0], operands[1], tester, testee);
      if ( (!mullo && testee != tester) || (mullo && testee[63:0] != tester[63:0]) ) begin
         $display("Failed: SimdMul64");
         $finish();
      end
      
      if ( resCnt == testLength -1 + 4) begin
         $display("Passed: SimdMul64");
         $finish();
      end
   endrule
   
endmodule
                 
