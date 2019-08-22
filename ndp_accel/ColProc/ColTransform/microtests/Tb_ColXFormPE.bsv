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
import SimdAlu256::*;
import NDPCommon::*;
import ColXFormPE::*;
import GetPut::*;
import Pipe::*;

////////////////////////////////////////////////////////////////////////////////
/// Test Vector Section
////////////////////////////////////////////////////////////////////////////////
typedef 10 NumTests;
Integer numTests = valueOf(NumTests);
Bit#(64) most_negative = 1<<63;
////////////////////////////////////////////////////////////////////////////////
/// End of Test Vector Section
////////////////////////////////////////////////////////////////////////////////


import "BDPI" function Bit#(32) log2_c(Bit#(32) x);
import "BDPI" function Action rand_seed();
import "BDPI" function ActionValue#(Bit#(32)) randu32(Bit#(32) dummy);
import "BDPI" function ActionValue#(Bit#(64)) randu64(Bit#(32) dummy);
                 

(* synthesize *)
module mkTb_ColXFormPE();
   ////////////////////////////////////////////////////////////////////////////////
   /// Test Vector Section
   ////////////////////////////////////////////////////////////////////////////////
   Vector#(NumTests, Vector#(8, DecodeInst)) insts = ?;// vec(insts_0, insts_1);
   Vector#(NumTests, Integer) progLength = ?;//vec(maxProg_0, maxProg_1);
   Vector#(NumTests, Bit#(64)) beatsPerRowVec = ?;//vec(ratio_0, ratio_1);
   Vector#(NumTests, Bit#(64)) rowVecLengths = ?;//vec(ratio_0, ratio_1);
   Vector#(NumTests, Bit#(64)) testLengths = ?;//vec(ratio_0, ratio_1);
   Vector#(NumTests, Tuple2#(Integer, Integer)) ioRatio = ?;//vec(ratio_0, ratio_1);
   Integer i = 0;
   
   // test 0
   Vector#(8, DecodeInst) inst = vec(DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, inType: Int, outType: ?, imm: ?},
                                     ?,
                                     ?,      
                                     ?,
                                     ?,
                                     ?,
                                     ?,
                                     ?);
   Integer numInsts = 1;
   Tuple2#(Integer, Integer) ratio = tuple2(1,1);
   Bit#(64) numRowVecs = 100;
   Bit#(64) beatsPerIter = zeroExtend(toBeatsPerRowVec(Int));
   Bit#(64) testLength = numRowVecs*beatsPerIter;

   insts[i] = inst;
   progLength[i] = numInsts;
   ioRatio[i] = ratio;
   beatsPerRowVec[i] = beatsPerIter;
   rowVecLengths[i] = numRowVecs;
   testLengths[i] = testLength;
   i = i + 1;

   // test 1                 
   inst = vec(DecodeInst{iType: AluImm, aluOp: Add, isSigned: True, inType: Int, outType: ?, imm: 1},
              ?,      
              ?,
              ?,
              ?,
              ?,
              ?,
              ?);

   numInsts = 1;   
   ratio = tuple2(1,1);
   numRowVecs = 100;
   beatsPerIter = zeroExtend(toBeatsPerRowVec(Int));
   testLength = numRowVecs*beatsPerIter;
   
   insts[i] = inst;
   progLength[i] = numInsts;
   ioRatio[i] = ratio;
   beatsPerRowVec[i] = beatsPerIter;
   rowVecLengths[i] = numRowVecs;
   testLengths[i] = testLength;
   i = i + 1;
   
   // test 2
   inst = vec(DecodeInst{iType: Store, aluOp: ?, isSigned: ?, inType: Int, outType: Int, imm: ?},
              DecodeInst{iType: Alu, aluOp: Add, isSigned: True, inType: Int, outType: ?, imm: 1},
              ?,
              ?,
              ?,
              ?,
              ?,
              ?);

   numInsts = 2;   
   ratio = tuple2(1,2);
   numRowVecs = 100;
   beatsPerIter = 2*zeroExtend(toBeatsPerRowVec(Int));
   testLength = numRowVecs*beatsPerIter;
   
   insts[i] = inst;
   progLength[i] = numInsts;
   ioRatio[i] = ratio;
   beatsPerRowVec[i] = beatsPerIter;
   rowVecLengths[i] = numRowVecs;
   testLengths[i] = testLength;
   i = i + 1;
   
   // test 3
   inst = vec(DecodeInst{iType: Copy, aluOp: ?, isSigned: ?, inType: Int, outType: Int, imm: ?},
              DecodeInst{iType: Alu, aluOp: Add, isSigned: True, inType: Int, outType: ?, imm: 1},
              ?,
              ?,
              ?,
              ?,
              ?,
              ?);

   numInsts = 2;   
   ratio = tuple2(1,1);
   numRowVecs = 100;
   beatsPerIter = 2*zeroExtend(toBeatsPerRowVec(Int));
   testLength = numRowVecs*beatsPerIter;


   insts[i] = inst;
   progLength[i] = numInsts;
   ioRatio[i] = ratio;
   beatsPerRowVec[i] = beatsPerIter;
   rowVecLengths[i] = numRowVecs;
   testLengths[i] = testLength;
   i = i + 1;
   
   // test 4
   inst = vec(DecodeInst{iType: Store, aluOp: ?, isSigned: ?, inType: Int, outType: Int, imm: ?},
              DecodeInst{iType: Alu, aluOp: Mul, isSigned: True, inType: Int, outType: Int, imm: 1},
              ?,
              ?,
              ?,
              ?,
              ?,
              ?);

   numInsts = 2;   
   ratio = tuple2(1,1);
   numRowVecs = 100;
   beatsPerIter = 2*zeroExtend(toBeatsPerRowVec(Int));
   testLength = numRowVecs*beatsPerIter;
   
   insts[i] = inst;
   progLength[i] = numInsts;
   ioRatio[i] = ratio;
   beatsPerRowVec[i] = beatsPerIter;
   rowVecLengths[i] = numRowVecs;
   testLengths[i] = testLength;
   i = i + 1;
   
      
   // test 5
   inst = vec(DecodeInst{iType: Copy, aluOp: ?, isSigned: ?, inType: Int, outType: Int, imm: ?},
              DecodeInst{iType: Alu, aluOp: Mul, isSigned: True, inType: Int, outType: ?, imm: 1},
              ?,
              ?,
              ?,
              ?,
              ?,
              ?);

   numInsts = 2;   
   ratio = tuple2(3,2);
   numRowVecs = 100;
   beatsPerIter = 2*zeroExtend(toBeatsPerRowVec(Int));
   testLength = numRowVecs*beatsPerIter;
      
   insts[i] = inst;
   progLength[i] = numInsts;
   ioRatio[i] = ratio;
   beatsPerRowVec[i] = beatsPerIter;
   rowVecLengths[i] = numRowVecs;
   testLengths[i] = testLength;
   i = i + 1;
   

   // test 6
   inst = vec(DecodeInst{iType: Store, aluOp: ?, isSigned: ?, inType: BigInt, outType: Long, imm: ?},
              DecodeInst{iType: Alu, aluOp: Mul, isSigned: True, inType: Long, outType: ?, imm: 1},
              ?,
              ?,
              ?,
              ?,
              ?,
              ?);

   numInsts = 2;   
   ratio = tuple2(2,3);
   numRowVecs = 100;
   beatsPerIter = zeroExtend(toBeatsPerRowVec(Long)) + zeroExtend(toBeatsPerRowVec(BigInt));
   testLength = numRowVecs*beatsPerIter;
   
   insts[i] = inst;
   progLength[i] = numInsts;
   ioRatio[i] = ratio;
   beatsPerRowVec[i] = beatsPerIter;
   rowVecLengths[i] = numRowVecs;
   testLengths[i] = testLength;
   i = i + 1;
   
            
   // test 7
   inst = vec(DecodeInst{iType: Copy, aluOp: ?, isSigned: ?, inType: BigInt, outType: Long, imm: ?},
              DecodeInst{iType: Alu, aluOp: Mul, isSigned: True, inType: Long, outType: ?, imm: 1},
              ?,
              ?,
              ?,
              ?,
              ?,
              ?);


   numInsts = 2;   
   ratio = tuple2(4,3);
   numRowVecs = 100;
   beatsPerIter = zeroExtend(toBeatsPerRowVec(Long)) + zeroExtend(toBeatsPerRowVec(BigInt));
   testLength = numRowVecs*beatsPerIter;
   
   insts[i] = inst;
   progLength[i] = numInsts;
   ioRatio[i] = ratio;
   beatsPerRowVec[i] = beatsPerIter;
   rowVecLengths[i] = numRowVecs;
   testLengths[i] = testLength;
   i = i + 1;
      
   // test 8
   inst = vec(DecodeInst{iType: Store, aluOp: ?, isSigned: ?, inType: Long, outType: Long, imm: ?},
              DecodeInst{iType: Alu, aluOp: Mullo, isSigned: True, inType: Long, outType: ?, imm: 1},
              ?,
              ?,
              ?,
              ?,
              ?,
              ?);


   numInsts = 2;   
   ratio = tuple2(1,2);
   numRowVecs = 100;
   beatsPerIter = 2*zeroExtend(toBeatsPerRowVec(Long));
   testLength = numRowVecs*beatsPerIter;
   
   insts[i] = inst;
   progLength[i] = numInsts;
   ioRatio[i] = ratio;
   beatsPerRowVec[i] = beatsPerIter;
   rowVecLengths[i] = numRowVecs;
   testLengths[i] = testLength;
   i = i + 1;

   // test 9
   inst = vec(DecodeInst{iType: Copy, aluOp: ?, isSigned: ?, inType: Long, outType: Long, imm: ?},
              DecodeInst{iType: Alu, aluOp: Mullo, isSigned: True, inType: Long, outType: ?, imm: 1},
              ?,
              ?,
              ?,
              ?,
              ?,
              ?);


   numInsts = 2;   
   ratio = tuple2(1,1);
   numRowVecs = 100;
   beatsPerIter = 2*zeroExtend(toBeatsPerRowVec(Long));
   testLength = numRowVecs*beatsPerIter;
   
   insts[i] = inst;
   progLength[i] = numInsts;
   ioRatio[i] = ratio;
   beatsPerRowVec[i] = beatsPerIter;
   rowVecLengths[i] = numRowVecs;
   testLengths[i] = testLength;
   i = i + 1;

////////////////////////////////////////////////////////////////////////////////
/// End of Test Vector Section
////////////////////////////////////////////////////////////////////////////////


   ColXFormPE testEng <- mkColXFormPE;
   
   Reg#(Bit#(32)) testCnt <- mkReg(0);
   Reg#(Bit#(4)) prog_cnt <- mkReg(0);
   Integer maxProg = 1;
   Reg#(Bool) doProgram <- mkReg(True);
   Reg#(Bool) doInput <- mkReg(False);
   rule doProgramPE if (doProgram);
      if ( prog_cnt  < fromInteger(progLength[testCnt]) ) begin
         testEng.programPort.enq(tuple3(truncate(prog_cnt), False, pack(insts[testCnt][prog_cnt])));
         prog_cnt <= prog_cnt + 1;
      end
      else if (prog_cnt  == fromInteger(progLength[testCnt])) begin
         testEng.programPort.enq(tuple3(?, True, fromInteger(progLength[testCnt])));
         prog_cnt <= 0;
         doProgram <= False;
         doInput <= True;
      end
   endrule
   
   Reg#(Bit#(64)) inputCnt <- mkReg(0);
   Reg#(Bit#(64)) outputCnt <- mkReg(0);

   rule doTest if (!doProgram && doInput);
      if ( inputCnt == testLengths[testCnt] - 1 ) begin
         inputCnt <= 0;
         doInput <= False;
      end
      else begin
         inputCnt <= inputCnt + 1;
      end

      Vector#(4, Bit#(64)) rands <- mapM(randu64, genWith(fromInteger));
      testEng.inPipe.enq(pack(rands));
      $display("(@%t) Input cnt = %d, streamIn = %h", $time, inputCnt, pack(rands));
      if ( inputCnt % beatsPerRowVec[testCnt] == 0 ) begin
         testEng.rowVecIn.enq(tuple2(inputCnt/beatsPerRowVec[testCnt], False));
         $display("Input RowVecId = %d, beatsPerRowVec = %d", inputCnt/beatsPerRowVec[testCnt], beatsPerRowVec[testCnt]);
      end

   endrule
   

   rule doOutput if (!doProgram);
      let tester = testEng.outPipe.first;
      testEng.outPipe.deq;
      
      $display("(@%t) Output cnt = %d, tester = %h", $time, outputCnt, tester);
      
      // if ( outputCnt % (beatsPerRowVec[testCnt]*fromInteger(tpl_1(ioRatio[testCnt]))/fromInteger(tpl_2(ioRatio[testCnt]))) == 0) begin
      //    let rowVec = testEng.rowVecOut.first;
      //    testEng.rowVecOut.deq;
      // end
      
      if ( outputCnt == testLengths[testCnt]*fromInteger(tpl_1(ioRatio[testCnt]))/fromInteger(tpl_2(ioRatio[testCnt])) -1) begin
         $display("Passed: ColXFormPE test %d instCnt = %d", testCnt, fromInteger(progLength[testCnt]));
         for ( Integer i = 0; i < fromInteger(progLength[testCnt]); i = i + 1) begin
            $display("@ %d : ", i, fshow(insts[testCnt][i]));
         end
         doProgram <= True;
         testCnt <= testCnt + 1;
         if ( testCnt + 1 == fromInteger(numTests) ) begin
            $finish();
         end
         outputCnt <= 0;
      end
      else begin
         outputCnt <= outputCnt + 1;
      end
   endrule
   
   rule doRowVecOut;
      let rowVec = testEng.rowVecOut.first;
      testEng.rowVecOut.deq;
      $display("(@%t) Output RowVecId = ", $time, fshow(rowVec));
   endrule
   
endmodule
                 
