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
import FIFO::*;
import SimdCommon::*;
import SimdAlu256::*;
import SimdAddSub128::*;
import SimdMul64::*;
import GetPut::*;

import "BDPI" function Bit#(32) log2_c(Bit#(32) x);
import "BDPI" function Action rand_seed();
import "BDPI" function ActionValue#(Bit#(32)) randu32(Bit#(32) dummy);
import "BDPI" function ActionValue#(Bit#(64)) randu64(Bit#(32) dummy);

(* synthesize *)
module mkTb_SimdAlu256();
   Bit#(64) most_negative = 1<<63;
   
   SimdAlu256 testEng <- mkSimdAlu256;
   
   Reg#(Bit#(64)) testCnt <- mkReg(0);
   Reg#(Bit#(64)) resCnt <- mkReg(0);
   
   Bit#(64) testLength = 1024;
   
   FIFO#(Tuple4#(Vector#(2, Bit#(256)), Op, SimdMode, Bool)) operandQ <- mkSizedFIFO(128);
   
   rule doTest if ( testCnt < testLength );
      testCnt <= testCnt + 1;

      Vector#(2, Bit#(256)) operands = ?;
      Op op = ?;
      SimdMode mode = ?;
      Bool isSigned = ?;

      Vector#(8, Bit#(64)) rands <- mapM(randu64, genWith(fromInteger));
      operands = unpack(pack(rands));      
      let rand_32 <- randu32(0);
      let rand_32_1 <- randu32(1);
      mode = unpack(truncate(rand_32%5));
      op = unpack(truncate(rand_32_1%3));
      isSigned = unpack(truncateLSB(rand_32));
      
      testEng.start(operands[0], operands[1], op, mode, isSigned);
      $display("enqueing Test");
      $display(operands[0], operands[1], op, mode, isSigned);
      operandQ.enq(tuple4(operands,op,mode,isSigned));
   endrule
   

   rule doResult;
      resCnt <= resCnt + 1;
      
      let {tester, half} <- testEng.result;
      
      let {operands, op, mode, isSigned} <- toGet(operandQ).get;
      
      Vector#(2, Bit#(256)) testee = ?;
      
      case (op)
         Sub:
         begin
            let testee_0 = combSimdAddSub128(truncate(operands[0]),truncate(operands[1]), True, mode);
            let testee_1 = combSimdAddSub128(truncateLSB(operands[0]),truncateLSB(operands[1]), True, mode);
            testee[0] = {testee_1, testee_0};
            $display("(@%t) Test: %h simd- %h = %h, testId = %d, mode = ", $time, operands[0], operands[1], tester[0], resCnt, fshow(mode));
            $display("(@%t) Ref : %h simd- %h = %h, testId = %d, mode = ", $time, operands[0], operands[1], testee[0], resCnt, fshow(mode));
         end
         Add:
         begin
            let testee_0 = combSimdAddSub128(truncate(operands[0]),truncate(operands[1]), False, mode);
            let testee_1 = combSimdAddSub128(truncateLSB(operands[0]),truncateLSB(operands[1]), False, mode);
            testee[0] = {testee_1, testee_0};
            $display("(@%t) Test: %h simd+ %h = %h, testId = %d, mode = ", $time, operands[0], operands[1], tester[0], resCnt, fshow(mode));
            $display("(@%t) Ref : %h simd+ %h = %h, testId = %d, mode = ", $time, operands[0], operands[1], testee[0], resCnt, fshow(mode));
         end
         Mul:
         begin
            function Bit#(128) combSimdMul64_2(Bit#(64) a, Bit#(64) b) = combSimdMul64(a,b, pack(mode==Long), isSigned);
            Vector#(4, Bit#(128)) testee_v = zipWith(combSimdMul64_2, unpack(operands[0]), unpack(operands[1]));
            testee = unpack(pack(testee_v));
            $display("(@%t) Test: %h simdx %h = %h, testId = %d, isSigned = %d, mode = ", $time, operands[0], operands[1], pack(tester), resCnt, isSigned, fshow(mode));
            $display("(@%t) Ref : %h simdx %h = %h, testId = %d, isSigned = %d, mode = ", $time, operands[0], operands[1], pack(testee), resCnt, isSigned, fshow(mode));
         end
      endcase
      
     if ( (half && (tester[0] != testee[0])) || (!half &&(tester != testee)) ) begin
         $display("Failed: SimdAlu256");
         $finish();
      end
      
      if ( resCnt == testLength -1) begin
         $display("Passed: SimdAlu256");
         $finish();
      end
   endrule
   
endmodule
                 
