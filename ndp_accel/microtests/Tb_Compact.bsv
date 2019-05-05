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
import Compact::*;
import NDPCommon::*;
import Pipe::*;
import AlgFuncs::*;

import "BDPI" function Bit#(32) log2_c(Bit#(32) x);
import "BDPI" function Action rand_seed();
import "BDPI" function ActionValue#(Bit#(32)) randu32(Bit#(32) dummy);
import "BDPI" function ActionValue#(Bit#(64)) randu64(Bit#(32) dummy);

import "BDPI" function Action init_test(Bit#(32) colbytes);                 
import "BDPI" function Action inject_rowData(Bit#(256) x);
import "BDPI" function Action inject_rowMask(Bit#(32) x);
import "BDPI" function Bool check_result(Bit#(256) result, Bit#(32) bytes);
import "BDPI" function Bool check_count(Bit#(64) v);


                 
function Bit#(w) mod(Bit#(w) a, Integer i);
   return a%fromInteger(i);
endfunction
                 
typedef 1 ColBytes;                 


(* synthesize *)
module mkTb_Compact();
   Reg#(Bit#(64)) cycle <- mkReg(0);
   
   Compact#(ColBytes) testEng <- mkCompact;
   
   // Compact#(1) testEng_char <- mkCompact;
   
   Reg#(Bool) configured <- mkReg(False);
   
   Reg#(Bit#(64)) testLength <- mkRegU;
   
   rule configEng (!configured);
      // Vector#(2, Int#(64)) lhs = vec(unpack(l), unpack(h));
      // Vector#(8, Int#(64)) configV = append(lhs, newVector);
      // testEng.configure(map(pack, configV));
      configured <= True;
      // $display("Configure Vec == ", fshow(configV));
      rand_seed();
      init_test(fromInteger(valueOf(ColBytes)));
      // let randv <- randu64(0);
      testLength <= 256;//truncate(randv%1000+1);
   endrule
   

   
   rule testInput (cycle < testLength && configured);
      Vector#(TDiv#(32, ColBytes), Bit#(TMul#(8, ColBytes))) vals = zipWith(add2, map(truncate, replicate(cycle*fromInteger(valueOf(TDiv#(32,ColBytes))))), genWith(fromInteger));//<- mapM(randu32, genWith(fromInteger));
      
      let last = (cycle == testLength-1);
      
      inject_rowData(pack(vals));

      testEng.streamIn.rowData.enq(RowData{data:pack(vals),
                                           last: last});
      // $display(fshow(vals));
      
      if ( valueOf(ColBytes) == 1) begin
         let randMask <- randu32(0);
         testEng.streamIn.rowMask.enq(randMask);
         inject_rowMask(randMask);
         // $display("inject mask = %b", randMask);
      end
      else if ( cycle % fromInteger(valueOf(ColBytes)) == fromInteger(valueOf(ColBytes)-1) ) begin
         let randMask <- randu32(0);
         testEng.streamIn.rowMask.enq(randMask);
         inject_rowMask(randMask);
         // $display("inject mask = %b", randMask);
      end
      cycle <= cycle + 1;

   endrule
   
   Reg#(Bit#(64)) count <- mkReg(0);
   
   rule testOutput;
      let v = testEng.outPipe.first;
      testEng.outPipe.deq();
      
      Vector#(8, Bit#(32)) vData = unpack(v.data);
      Bit#(32) bytes = extend(v.bytes);
      $display(fshow(vData));
      $display("bytes = %d",bytes);
      count <= count + extend(bytes);
      if ( !check_result(pack(v.data), bytes) ) begin
         $display("FAILED: Compact wrong result");
         $finish();
      end
         
      if ( v.last ) begin
         if( check_count(count+extend(bytes)))
            $display("Passed: Compact");
         else
            $display("Passed: WrongCount");
         $finish();
      end
   endrule
      
endmodule
