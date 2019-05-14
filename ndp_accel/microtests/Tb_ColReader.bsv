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
import AlgFuncs::*;


// flash controller stuff
import ControllerTypes::*;
import AuroraCommon::*;
import AuroraImportFmc1::*;
import FlashCtrlVirtex::*;
import FlashCtrlModel::*;
import EmptyFlash::*;

import FlashCtrlIfc::*;

import ColReader::*;
import FlashReadMultiplex::*;
import EmptyFlash::*;

import Connectable::*;

import FlashSwitch::*;
import AlgFuncs::*;

import "BDPI" function Bit#(32) log2_c(Bit#(32) x);
import "BDPI" function Action rand_seed();
import "BDPI" function ActionValue#(Bit#(32)) randu32(Bit#(32) dummy);
import "BDPI" function ActionValue#(Bit#(64)) randu64(Bit#(32) dummy);

import "BDPI" function Action init_test(Bit#(32) colbytes);                 
import "BDPI" function Action init_test1(Bit#(64) start, Bit#(64) endRow);                 
import "BDPI" function ActionValue#(Bool) inject_rowData(Bit#(256) x);
import "BDPI" function ActionValue#(Bool) inject_rowMask(Bit#(32) x);



                 
function Bit#(w) mod(Bit#(w) a, Integer i);
   return a%fromInteger(i);
endfunction
                 
typedef 8 ColBytes;
Integer colBytes = valueOf(ColBytes);                 


typedef enum {Init0, Init1, Run} StatusT deriving (Bits, Eq, FShow);


(* synthesize *)
module mkTb_ColReader(Empty);
   
   function Bit#(128) genData_0(Bit#(64) beatCnt);
      Vector#(TDiv#(16, ColBytes), Bit#(TMul#(8, ColBytes))) dataV = zipWith(add2, replicate(truncate(beatCnt*fromInteger(16/colBytes)*fromInteger(16/colBytes*512))), genWith(fromInteger));
      return pack(dataV);
   endfunction
   
   function Bit#(128) genData_1(Bit#(64) beatCnt);
      Vector#(TDiv#(16, ColBytes), Bit#(TMul#(8, ColBytes))) dataV = zipWith(add2, replicate(truncate(beatCnt*fromInteger(16/colBytes)*fromInteger(16/colBytes*512)+fromInteger(16/colBytes*512))), genWith(fromInteger));
      return pack(dataV);
   endfunction

   
   
   Vector#(2,FlashCtrlVirtexIfc) flashCtrls;// <- replicateM(mkEmptyFlashCtrl);
   flashCtrls[0] <- mkEmptyFlashCtrl(genData_0);
   flashCtrls[1] <- mkEmptyFlashCtrl(genData_1);
   
   Vector#(2, FlashSwitch#(1)) flashSwitches <- replicateM(mkFlashSwitch());
   
   mkConnection(flashSwitches[0].flashCtrlClient, flashCtrls[0].user);
   mkConnection(flashSwitches[1].flashCtrlClient, flashCtrls[1].user);
   
   FlashReadMultiplex#(1) flashMux <- mkFlashReadMultiplex;
   
   zipWithM_(mkConnection, flashMux.flashClient, vec(flashSwitches[0].users[0], flashSwitches[1].users[0]));
   ColReader colReader <- mkColReader();
   
   mkConnection(flashMux.flashReadServers[0], colReader.flashRdClient);
   
   Reg#(StatusT) state <- mkReg(Init0);
   Reg#(Bit#(32)) reqCnt <- mkReg(0);
   
   rule init_colWidth if (state == Init0);
      colReader.configure.setColBytes(fromInteger(colBytes));
      init_test(fromInteger(colBytes));
      state <= Init1;
   endrule
   
   Reg#(Bit#(64)) numRowsReg <- mkRegU();

   rule init_param if ( state == Init1);
      Bit#(64) base = 0;
      Bit#(64) numRows = 8192;
      numRowsReg <= numRows;
      Bool isMasked = False;
      colReader.configure.setParameters(vec(extend(base), extend(numRows), extend(pack(isMasked)), ?));
      state <= Run;
      reqCnt <= 1;
      rand_seed();
   endrule
      
   Reg#(Bit#(64)) totalBeat <- mkRegU;

   rule sendReq if ( state == Run && reqCnt > 0);
      Bit#(64) startRow <- randu64(0);//%numRowReg;
      Bit#(64) endRow <- randu64(1);//%numRowReg;
      startRow = startRow % numRowsReg;
      endRow = endRow % numRowsReg;
      
      if ( startRow > endRow ) begin
         let temp = startRow;
         startRow = endRow;
         endRow = temp;
      end
      
      
      colReader.rowReq.enq(RowBatchRequest{firstRow:startRow, 
                                           lastRow:endRow,
                                           last:True});
      reqCnt <= reqCnt - 1;
      init_test1(startRow, endRow);
      
      Bit#(4) lgRPP = case (colBytes)
                         1: 13;
                         2: 12;
                         4: 10;
                         8: 9;
                         16: 8;
                         endcase;
      
      let startpage = startRow >> lgRPP;
      let endpage = endRow >> lgRPP;
      
      totalBeat <= (endpage - startpage) * 256;
   endrule
   
   Reg#(Bool) maskDone <- mkReg(False);
   Reg#(Bool) dataDone <- mkReg(False);
   
   
   Reg#(Bit#(32)) maskRespCnt <- mkReg(0);
   rule collectRowMask if ( state == Run);
      let d = colReader.streamOut.rowMask.first;
      colReader.streamOut.rowMask.deq();
      maskRespCnt <= maskRespCnt + 1;
      $display("RowMask, cnt = %d, mask = %b, last = %d", maskRespCnt, d.mask, d.last);
      let v <- inject_rowMask(d.mask);
      if ( !v ) begin
         $display("Error RowMask finish");
         $finish;
      end
      
      if ( d.last ) begin
         $display("all RowMask done correctly");
         maskDone <= True;
      end
   endrule
   
   Reg#(Bit#(64)) dataRespCnt <- mkReg(0);
   rule collectRowData if ( state == Run);
      let d = colReader.streamOut.rowData.first;
      colReader.streamOut.rowData.deq();
      dataRespCnt <= dataRespCnt + 1;
      $display("RowData, cnt = %d, data = %h", dataRespCnt, d);
      let v <- inject_rowData(d);
      if ( !v ) $finish;
      
      if ( dataRespCnt + 1 == totalBeat ) begin
         $display("all RowData done correctly");
         dataDone <= True;
      end
         
   endrule

   rule passTest if (dataDone && maskDone);
      $display("Test Passed");
      $finish();
   endrule
   // (* always_enabled, always_ready *)
   rule fakeDrive;
      flashCtrls[0].aurora.rxn_in(?);
      flashCtrls[1].aurora.rxn_in(?);
      
      flashCtrls[0].aurora.rxp_in(?);
      flashCtrls[1].aurora.rxp_in(?);
 
   endrule

   // (* always_enabled, always_ready *)
   // rule fakeDrive;
   //    flashCtrls[0].aurora.rxn_in(?);
   //    flashCtrls[1].aurora.rxn_in(?);
   // endrule

endmodule
