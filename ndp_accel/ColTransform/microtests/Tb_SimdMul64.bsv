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
   
   FIFO#(Tuple3#(Vector#(2, Bit#(64)), Bit#(1), Bool)) operandQ <- mkSizedFIFO(64);
   
   Vector#(4, Tuple3#(Vector#(2, Bit#(64)), Bit#(1), Bool)) testVec = vec(tuple3(vec(most_negative, -1), 1, True),
                                                                          tuple3(vec(most_negative, -1), 1, True),
                                                                          tuple3(vec(-1,-1), 1, True),
                                                                          tuple3(vec(most_negative-1, most_negative-1), 1, True));
   
   rule doTest if ( testCnt < testLength + 4) ;
      testCnt <= testCnt + 1;
      
      let {operands, mode, isSigned} = testVec[testCnt];
      
      if ( testCnt >= 4) begin
         operands <- mapM(randu64, genWith(fromInteger));
         let rand_32 <- randu32(0);
         mode = rand_32[0];
         isSigned = unpack(rand_32[1]);
      end
      // Vector#(2, Bit#(64)) operands = vec(1<<63,(1<<63)-1);
      testEng.req(operands[0], operands[1], mode, isSigned);
      operandQ.enq(tuple3(operands, mode, isSigned));
   endrule
   

   rule doResult;
      resCnt <= resCnt + 1;
      
      let tester = testEng.product;
      testEng.deqResp;
      
      let {operands, mode, isSigned} <- toGet(operandQ).get;
      
      let testee = combSimdMul64(operands[0], operands[1], mode, isSigned);

      $display("(@%t) Test: %h simdx %h = %h, testId = %d, mode = %d, isSigned = %d", $time, operands[0], operands[1], tester, resCnt, mode, isSigned);
      $display("(@%t) Ref : %h simdx %h = %h, testId = %d, mode = %d, isSigned = %d", $time, operands[0], operands[1], testee, resCnt, mode, isSigned);

      // $display("(@%t) Test[%d]: %b times %b = %d (expected %b)", $time, resCnt, operands[0], operands[1], tester, testee);
      if ( testee != tester ) begin
         $display("Failed: SimdMul64");
         $finish();
      end
      
      if ( resCnt == testLength -1 + 4) begin
         $display("Passed: SimdMul64");
         $finish();
      end
   endrule
   
endmodule
                 
