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
import SelectFilter::*;
import PECommon::*;

import "BDPI" function Bit#(32) log2_c(Bit#(32) x);
import "BDPI" function Action rand_seed();
import "BDPI" function ActionValue#(Bit#(32)) randu32(Bit#(32) dummy);
import "BDPI" function ActionValue#(Bit#(64)) randu64(Bit#(32) dummy);
import "BDPI" function Action init_test(Bit#(64) lv, Bit#(64) hv);
import "BDPI" function Action inject_test(Bit#(64) x, Bit#(8) mask);
import "BDPI" function Bool check_result(Bit#(512) mypos, Bit#(8) mask);
import "BDPI" function Bool check_count(Bit#(64) v);
Bool doRandSeq = False;
                 
function Bit#(w) mod(Bit#(w) a, Integer i);
   return a%fromInteger(i);
endfunction

(* synthesize *)
module mkTb_SelectFilter();
   Reg#(Bit#(32)) cycle <- mkReg(0);
   
   let testEng <- mkSelectFilter;
   
   Reg#(Bool) configured <- mkReg(False);
   
   Bit#(64) l = 100;
   Bit#(64) h = 120;
   
   Reg#(Bit#(32)) testLength <- mkRegU;
   
   rule configEng (!configured);
      Vector#(2, Int#(64)) lhs = vec(unpack(l), unpack(h));
      Vector#(8, Int#(64)) configV = append(lhs, newVector);
      testEng.configure(map(pack, configV));
      configured <= True;
      $display("Configure Vec == ", fshow(configV));
      rand_seed();
      init_test(l,h);
      let randv <- randu64(0);
      testLength <= 1000;//truncate(randv%1000+1);
   endrule
   
   rule testInput (cycle < testLength && configured);
      Vector#(8, Bit#(64)) vals <- mapM(randu64, genWith(fromInteger));
      vals = zipWith(mod, vals, replicate(300));
      let last = (cycle == testLength-1);
      
      for (Integer i = 0; i < 8; i=i+1 ) begin
         inject_test(vals[i], 1);
      end

      // Vector#(8, Bit#(64)) vals = replicate(100);
      testEng.put(FlitT{data:vals,
                        mask: -1,
                        last: last});
      cycle <= cycle + 1;
      // $display(fshow(vals));
   endrule
   Reg#(Bit#(64)) count <- mkReg(0);
   
   rule testOutput;
      let v <- testEng.get;
      Vector#(8, UInt#(64)) vInts = map(unpack, v.data);
      $display(fshow(vInts));
      $display("mask = %b",v.mask);
      count <= count + extend(pack(countOnes(v.mask)));
      if ( !check_result(pack(v.data), v.mask)) begin
         $display("FAILED: SelectFilter wrong result");
         $finish();
      end
         
      if ( v.last ) begin
         if( check_count(count + extend(pack(countOnes(v.mask)))))
            $display("Passed: SelectFilter");
         else
            $display("Passed: WrongCount");
         $finish();
      end
   endrule
      
endmodule
                 
