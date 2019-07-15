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
import SimdAdd128::*;
import GetPut::*;

import "BDPI" function Bit#(32) log2_c(Bit#(32) x);
import "BDPI" function Action rand_seed();
import "BDPI" function ActionValue#(Bit#(32)) randu32(Bit#(32) dummy);
import "BDPI" function ActionValue#(Bit#(64)) randu64(Bit#(32) dummy);

typedef 1 TestVecLength;
Bit#(64) testVecLength = fromInteger(valueOf(TestVecLength));
(* synthesize *)
module mkTb_SimdAdd128();
   Bit#(64) most_negative = 1<<63;
   
   SimdAdd128 testEng <- mkSimdAdd128;
   
   Reg#(Bit#(64)) testCnt <- mkReg(0);
   Reg#(Bit#(64)) resCnt <- mkReg(0);
   
   Bit#(64) testLength = 1024;
   
   FIFO#(Tuple2#(Vector#(2, Bit#(128)), SimdMode)) operandQ <- mkSizedFIFO(7);
   
   Vector#(TestVecLength, Tuple2#(Vector#(2,Bit#(128)), SimdMode)) testVec = vec(tuple2(vec(1<<63,1<<63), BigInt));
   
   rule doTest if ( testCnt < testLength + testVecLength );
      testCnt <= testCnt + 1;

      let {operands, mode} = testVec[testCnt];

      if ( testCnt >= testVecLength) begin
         Vector#(4, Bit#(64)) rands <- mapM(randu64, genWith(fromInteger));
         operands = unpack(pack(rands));      
         let rand_32 <- randu32(0);
         mode = unpack(truncate(rand_32%5));
      end

      // Vector#(2, Bit#(64)) operands = vec(1<<63,(1<<63)-1);
      testEng.req(operands[0], operands[1], mode); 
      operandQ.enq(tuple2(operands,mode));
   endrule
   

   rule doResult;
      resCnt <= resCnt + 1;
      
      let tester = testEng.sum;
      testEng.deqResp;
      
      let {operands, mode} <- toGet(operandQ).get;
      
      let testee = combSimdAdd128(truncate(operands[0]),truncate(operands[1]), mode);
      $display("(@%t) Test: %h simd+ %h = %h, testId = %d, mode = ", $time, operands[0], operands[1], tester, resCnt, fshow(mode));
      $display("(@%t) Ref : %h simd+ %h = %h, testId = %d, mode = ", $time, operands[0], operands[1], testee, resCnt, fshow(mode));
      
      if ( testee != tester ) begin
         $display("Failed: SimdAdd128");
         $finish();
      end
      
      if ( resCnt == testLength -1 + testVecLength) begin
         $display("Passed: SimdAdd128");
         $finish();
      end
   endrule
   
endmodule
                 
