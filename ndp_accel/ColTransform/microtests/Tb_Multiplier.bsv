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
import Multipliers::*;
import GetPut::*;

import "BDPI" function Bit#(32) log2_c(Bit#(32) x);
import "BDPI" function Action rand_seed();
import "BDPI" function ActionValue#(Bit#(32)) randu32(Bit#(32) dummy);
import "BDPI" function ActionValue#(Bit#(64)) randu64(Bit#(32) dummy);
import "BDPI" function Action init_test(Bit#(64) lv, Bit#(64) hv, Bit#(8) bytes, Bool sign);
import "BDPI" function Action inject_mask(Bit#(32) mask);
import "BDPI" function Action inject_data(Bit#(256) data);
import "BDPI" function Bool check_mask(Bit#(32) mask);
import "BDPI" function Bool check_data(Bit#(256) data);
import "BDPI" function Bool check_count(Bit#(64) v);
Bool doRandSeq = False;
                 
function Bit#(w) mod(Bit#(w) a, Integer i);
   return a%fromInteger(i);
endfunction


typedef 4 ColBytes;
Integer colBytes = valueOf(ColBytes);
Bool isSigned = False;
                 
typedef enum{ConfigColBytes, ConfigParam, Run} State deriving (Bits, Eq, FShow);


(* synthesize *)
module mkTb_Multiplier();
   // Multiplier#(64) testEng <- mkPipelinedMultiplier;
   // Multiplier#(64) testEng <- mkRadix4UnsignedMultiplier;
   Multiplier#(64) testEng <- mkRadix4SignedMultiplier;
   
   Reg#(Bit#(64)) testCnt <- mkReg(0);
   Reg#(Bit#(64)) resCnt <- mkReg(0);
   
   Bit#(64) testLength = 128;
   
   FIFO#(Vector#(2, Bit#(64))) operandQ <- mkSizedFIFO(64);
   
   rule doTest if ( testCnt < testLength) ;
      testCnt <= testCnt + 1;
      
      Vector#(2, Bit#(64)) operands <- mapM(randu64, genWith(fromInteger));
      // Vector#(2, Bit#(64)) operands = vec(5,9);
      testEng.start(truncate(operands[0]), truncate(operands[1]));
      operandQ.enq(operands);
      // resultQ.enq(multiply_unsigned(operands[0],operands[1]));
   endrule
   

   rule doResult;
      resCnt <= resCnt + 1;
      
      let tester <- testEng.result;
      
      let operands <- toGet(operandQ).get;
      
      Bit#(128) testee = multiply_signed(truncate(operands[0]),truncate(operands[1]));
      
      $display("Test[%d]: %d times %d = %d (expected %d)", resCnt, operands[0], operands[1], tester, testee);      
      if ( testee != tester ) begin
         $display("Failed: %h times %h = %h (expected %h)", operands[0], operands[1], tester, testee);
         $finish();
      end
      
      if ( resCnt == testLength -1 ) begin
         $display("Passed: Multiplier");
         $finish();
      end
   endrule
   
endmodule
                 
