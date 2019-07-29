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
import NDPSelect::*;
import NDPCommon::*;
import Pipe::*;

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
module mkTb_Select();

   
   let testEng <- mkNDPSelect;
   
   Reg#(Bool) configured <- mkReg(False);
   
   Bit#(64) l = 1;
   Bit#(64) h = 18;
   
   Reg#(Bit#(64)) testLength <- mkRegU;
   
   Reg#(State) state <- mkReg(ConfigColBytes);
   
   rule configColBytes ( state == ConfigColBytes );
      testEng.configure.setColBytes(fromInteger(colBytes));
      state <= ConfigParam;
   endrule
   
   rule configParam ( state == ConfigParam );
      
      Vector#(4, Bit#(128)) param = vec(extend(l), extend(h), extend(pack(isSigned)), 1);
      testEng.configure.setParameters(param);
      state <= Run;

      $display("Configure Vec == ", fshow(param));
      rand_seed();
      init_test(l,h, fromInteger(colBytes), isSigned);
      let randv <- randu64(0);
      testLength <= 1000;//truncate(randv%1000+1);
   endrule
   
   Reg#(Bit#(64)) maskCnt <- mkReg(0);
   rule inputMask (state == Run && maskCnt < testLength);
      if ( maskCnt + 1 < testLength ) begin
         testEng.streamIn.rowMask.enq(RowMask{isLast:False, mask: -1, hasData:True, rowVecId:maskCnt});
         $display("Tb: inputMask mask");
      end
      else begin
         testEng.streamIn.rowMask.enq(RowMask{isLast:True, mask: -1, hasData:True, rowVecId:maskCnt});
         $display("Tb: inputMask LAST");
      end
      
      maskCnt <= maskCnt + 1;
   endrule
   
   function Bit#(w) resize(Bit#(w) in, Bit#(w) lb, Bit#(w) hb);
      return in%(hb-lb) + lb;
   endfunction
   
   Reg#(Bit#(64)) dataCnt <- mkReg(0);
   rule inputData (state == Run && dataCnt < testLength*fromInteger(colBytes));
      Vector#(4, Bit#(64)) randV <- mapM(randu64, genWith(fromInteger));
      Bit#(256) randD = pack(randV);
      Bit#(64) ll = 3*l;
      Bit#(64) hh = 3*h;
      dataCnt <= dataCnt + 1;
      case (colBytes)
         1: begin
               Vector#(32, Bit#(8)) v  = zipWith3(resize, unpack(randD), replicate(truncate(ll)), replicate(truncate(hh)));
               randD = pack(v);
            end
         2: begin
               Vector#(16, Bit#(16)) v = zipWith3(resize, unpack(randD), replicate(truncate(ll)), replicate(truncate(hh)));
               randD = pack(v);
            end
         4: begin
               Vector#(8, Bit#(32)) v  = zipWith3(resize, unpack(randD), replicate(truncate(ll)), replicate(truncate(hh)));
               randD = pack(v);
            end
         8: begin
               Vector#(4, Bit#(64)) v  = zipWith3(resize, unpack(randD), replicate(truncate(ll)), replicate(truncate(hh)));
               randD = pack(v);
            end
         default: $display("Tb:: colBytes = %d not supported", colBytes);
      endcase

      
      testEng.streamIn.rowData.enq(randD);
      inject_data(randD);
   endrule
   
   Reg#(Bit#(64)) count <- mkReg(0);
   
   rule outputMask;
      let d = testEng.streamOut.rowMask.first;
      testEng.streamOut.rowMask.deq;
      
      
      
      
      // $display("Tb outMask = %b, count = %d", v.mask, count);
      $display("Tb outMask count = %d, maskData = ", count, fshow(d));
      
      if ( d.hasData) begin
         count <= count + extend(pack(countOnes(d.mask)));
         if ( !check_mask(d.mask) ) begin
            $display("FAILED: Select check mask wrong result");
            $finish();
         end
      end
      
      
      if (d.isLast) begin
         $display("OUTMASK:: LAST");
         if( check_count(count+extend(pack(countOnes(d.mask)))) )
            $display("Passed: SelectFilter");
         else
            $display("Failed: WrongCount");
         $finish();
      end
      

      // case (d) matches
      //    tagged Mask .v:
      //       begin
      //          count <= count + extend(pack(countOnes(v.mask)));
      //          $display("Tb outMask = %b, count = %d", v.mask, count);
      //          if ( !check_mask(v.mask) ) begin
      //             $display("FAILED: Select check mask wrong result");
      //             $finish();
      //          end
      //       end
      //    tagged Last:
      //       begin
      //          $display("OUTMASK:: LAST");
      //          if( check_count(count) )
      //             $display("Passed: SelectFilter");
      //          else
      //             $display("Failed: WrongCount");
      //          $finish();
      //       end
      // endcase
   endrule
   
   rule outputData;
      let v = testEng.streamOut.rowData.first;
      testEng.streamOut.rowData.deq;
      if ( !check_data(v) ) begin
         $display("FAILED: Select check mask wrong result");
         $finish();
      end
   endrule
endmodule
                 
