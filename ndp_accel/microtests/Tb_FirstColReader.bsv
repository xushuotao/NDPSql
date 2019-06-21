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
import ClientServer::*;
import GetPut::*;


// flash controller stuff
import ControllerTypes::*;
import AuroraCommon::*;
import AuroraImportFmc1::*;
import FlashCtrlVirtex::*;
import FlashCtrlModel::*;
import EmptyFlash::*;

import FlashCtrlIfc::*;

import FirstColReader::*;
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

// `define PassThru

`ifdef PassThru
Bool isPassThru = True;
typedef 1 ColBytes;
`else                 
Bool isPassThru = False;
typedef 4 ColBytes;
`endif
              
Integer colBytes = valueOf(ColBytes); 


typedef enum {Init0, Init1, Run} StatusT deriving (Bits, Eq, FShow);


(* synthesize *)
module mkTb_FirstColReader(Empty);
   
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
   FirstColReader colReader <- mkFirstColReader();
   
   mkConnection(flashMux.flashReadServers[0], colReader.flashRdClient);
   
   Reg#(StatusT) state <- mkReg(Init0);
   Reg#(Bit#(32)) reqCnt <- mkReg(0);
   
   rule init_colWidth if (state == Init0);
      rand_seed();
      colReader.configure.setColBytes(fromInteger(colBytes));
      init_test(fromInteger(colBytes));
      state <= Init1;
   endrule
   
   Reg#(Bit#(64)) numRowsReg <- mkRegU();

   rule init_param if ( state == Init1);
      Bit#(64) base = 0;
      let randv <- randu64(0);
      Bit#(64) numRows = randv%8192 + 1;
      numRowsReg <= numRows;
      Bool isMasked = False;
      colReader.configure.setParameters(vec(extend(base), extend(numRows), isPassThru?1:0, ?));
      state <= Run;
      reqCnt <= 1;
      rand_seed();
   endrule
   
   Reg#(Bit#(64)) vecCnt <- mkReg(0);
   rule handeReserveReq;
      let req <- colReader.reserveRowVecs.request.get();
      vecCnt <= vecCnt + extend(req);
      $display("vecCnt = %d", vecCnt);
      
      if ( vecCnt + fromInteger(8192/colBytes/32) >= ((numRowsReg+31)>>5) ) begin
         if ( req != truncate(((numRowsReg+31)>>5) - vecCnt) ) begin
            $display("WARNING: Wrong row vector reserved (%d, %d), %d", req, ((numRowsReg+31)>>5) - vecCnt, ((numRowsReg+31)>>5));
            $finish();
         end
      end
      else begin
         if ( req != fromInteger(8192/colBytes/32) ) begin
            $display("WARNING: Wrong row vector reserved (%d, %d)", req, 8192/colBytes);
            $finish();
         end
      end
      colReader.reserveRowVecs.response.put(?);
   endrule
      
   Reg#(Bit#(64)) totalBeat <- mkRegU;

   rule sendReq if ( state == Run && reqCnt > 0);
      colReader.start;
      
      reqCnt <= reqCnt - 1;
      init_test1(0, numRowsReg-1);
      
      Bit#(4) lgRPP = case (colBytes)
                         1: 13;
                         2: 12;
                         4: 10;
                         8: 9;
                         16: 8;
                         endcase;
      
      // Bit#(3) lg
      
      // let startpage = startRow >> lgRPP;
      // let endpage = endRow >> lgRPP;
      
      totalBeat <= ((numRowsReg+31) >> 5) * fromInteger(colBytes);
   endrule
   
   Reg#(Bool) maskDone <- mkReg(False);
   Reg#(Bool) dataDone <- mkReg(False);
   
   
   Reg#(Bit#(32)) maskRespCnt <- mkReg(0);
   
   Reg#(Bit#(64)) rowAggr <- mkReg(0);
   rule collectRowMask if ( state == Run);
      let d = colReader.streamOut.rowMask.first;
      colReader.streamOut.rowMask.deq();
      case (d) matches
         tagged Mask .maskD:
            begin
               maskRespCnt <= maskRespCnt + 1;
               $display("RowMask, cnt = %d, mask = %b, rowAggr = %d", maskRespCnt, maskD.mask, rowAggr);
               let v <- inject_rowMask(maskD.mask);
      
               rowAggr <= rowAggr + pack(zeroExtend(countOnes(maskD.mask)));
               if ( !v ) begin
                  $display("Error RowMask finish");
                  $finish;
               end
            end
         tagged Last:
            begin
               $display("all RowMask done correctly");
               maskDone <= True;
            end
      endcase
   endrule
   
   `ifndef PassThru
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
   `endif

   rule passTest if (maskDone 
                    `ifndef PassThru
                    && dataDone
                    `endif
                     );
      
      $display("RowAggr = %d, numRows = %d", rowAggr, numRowsReg);
      if ( rowAggr == numRowsReg) 
         $display("Test Passed");
      else
         $display("Test Failed");
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
