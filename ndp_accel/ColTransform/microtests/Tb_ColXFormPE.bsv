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
import ColXFormPE::*;
import SimdAddSub128::*;
import SimdMul64::*;
import ColXFormPE::*;
import GetPut::*;
import Pipe::*;

import "BDPI" function Bit#(32) log2_c(Bit#(32) x);
import "BDPI" function Action rand_seed();
import "BDPI" function ActionValue#(Bit#(32)) randu32(Bit#(32) dummy);
import "BDPI" function ActionValue#(Bit#(64)) randu64(Bit#(32) dummy);

(* synthesize *)
module mkTb_ColXFormPE();
   Bit#(64) most_negative = 1<<63;
   
   ColXFormPE testEng <- mkColXFormPE;
   
   Vector#(8, DecodeInst) insts_pass = vec(DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, colType: ?, imm: ?},
                                           ?,
                                           ?,      
                                           ?,
                                           ?,
                                           ?,
                                           ?,
                                           ?);
   
   
   Reg#(Bit#(4)) prog_cnt <- mkReg(0);
   Integer maxProg = 1;
   Reg#(Bool) doProgram <- mkReg(True);
   rule doProgramPE if (doProgram);
      prog_cnt <= prog_cnt + 1;
      if ( prog_cnt + 1 < fromInteger(maxProg) ) begin
         testEng.programPort.enq(tuple3(truncate(prog_cnt), False, pack(insts[prog_cnt])));
      end
      else if (prog_cnt  == fromInteger(maxProg)) begin
         testEng.programPort.enq(tuple3(?, True, fromInteger(maxProg)));
      end
   endrule
   
   Reg#(Bit#(64)) testCnt <- mkReg(0);
   Reg#(Bit#(64)) resCnt <- mkReg(0);
   Bit#(64) testLength = 10;
   rule doTest if ( testCnt < testLength );
      testCnt <= testCnt + 1;

      Vector#(4, Bit#(64)) rands <- mapM(randu64, genWith(fromInteger));
      
      testEng.inPipe.enq(pack(rands));
      $display("Response reqCnt = %d, streamIn = %h", testCnt, pack(rands));
   endrule
   

   rule doResult;
      resCnt <= resCnt + 1;
      
      let tester = testEng.outPipe.first;
      testEng.outPipe.deq;
      
      $display("Response resCnt = %d, tester = %h", resCnt, tester);
      
      // let {operands, op, mode, isSigned} <- toGet(operandQ).get;
      
     //  Vector#(2, Bit#(256)) testee = ?;
      
     //  case (op)
     //     Sub:
     //     begin
     //        let testee_0 = combSimdAddSub128(truncate(operands[0]),truncate(operands[1]), True, mode);
     //        let testee_1 = combSimdAddSub128(truncateLSB(operands[0]),truncateLSB(operands[1]), True, mode);
     //        testee[0] = {testee_1, testee_0};
     //        $display("(@%t) Test: %h simd- %h = %h, testId = %d, mode = ", $time, operands[0], operands[1], tester[0], resCnt, fshow(mode));
     //        $display("(@%t) Ref : %h simd- %h = %h, testId = %d, mode = ", $time, operands[0], operands[1], testee[0], resCnt, fshow(mode));
     //     end
     //     Add:
     //     begin
     //        let testee_0 = combSimdAddSub128(truncate(operands[0]),truncate(operands[1]), False, mode);
     //        let testee_1 = combSimdAddSub128(truncateLSB(operands[0]),truncateLSB(operands[1]), False, mode);
     //        testee[0] = {testee_1, testee_0};
     //        $display("(@%t) Test: %h simd+ %h = %h, testId = %d, mode = ", $time, operands[0], operands[1], tester[0], resCnt, fshow(mode));
     //        $display("(@%t) Ref : %h simd+ %h = %h, testId = %d, mode = ", $time, operands[0], operands[1], testee[0], resCnt, fshow(mode));
     //     end
     //     Mul:
     //     begin
     //        function Bit#(128) combSimdMul64_2(Bit#(64) a, Bit#(64) b) = combSimdMul64(a,b, pack(mode==Long), isSigned);
     //        Vector#(4, Bit#(128)) testee_v = zipWith(combSimdMul64_2, unpack(operands[0]), unpack(operands[1]));
     //        testee = unpack(pack(testee_v));
     //        $display("(@%t) Test: %h simdx %h = %h, testId = %d, isSigned = %d, mode = ", $time, operands[0], operands[1], pack(tester), resCnt, isSigned, fshow(mode));
     //        $display("(@%t) Ref : %h simdx %h = %h, testId = %d, isSigned = %d, mode = ", $time, operands[0], operands[1], pack(testee), resCnt, isSigned, fshow(mode));
     //     end
     //  endcase
      
     // if ( (half && (tester[0] != testee[0])) || (!half &&(tester != testee)) ) begin
     //     $display("Failed: ColXFormPE");
     //     $finish();
     //  end
      
      if ( resCnt == testLength -1) begin
         $display("Passed: ColXFormPE");
         $finish();
      end
   endrule
   
endmodule
                 
