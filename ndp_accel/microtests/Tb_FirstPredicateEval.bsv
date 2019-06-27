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

import PredicateEval::*;
import FlashReadMultiplex::*;
import EmulatedFlash::*;


import Connectable::*;
import OneToNRouter::*;
import RowMask::*;

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
                 
typedef 2 NDPCount;
              
Integer colBytes = valueOf(ColBytes); 

Int#(32) int_min = minBound;
                 
typedef enum {Init0, Init1, Run} StatusT deriving (Bits, Eq, FShow);


(* synthesize *)
module mkTb_FirstPredicateEval(Empty);
   
   
   Vector#(2,FlashCtrlVirtexIfc) flashCtrls <- mapM(mkEmulatedFlashCtrl, genWith(fromInteger));
   
   Vector#(2, FlashSwitch#(1)) flashSwitches <- replicateM(mkFlashSwitch());
   
   mkConnection(flashSwitches[0].flashCtrlClient, flashCtrls[0].user);
   mkConnection(flashSwitches[1].flashCtrlClient, flashCtrls[1].user);
   
   FlashReadMultiplex#(1) flashMux <- mkFlashReadMultiplex;
   
   zipWithM_(mkConnection, flashMux.flashClient, vec(flashSwitches[0].users[0], flashSwitches[1].users[0]));
   FirstPredicateEval ndp <- mkFirstPredicateEval();
   
   mkConnection(flashMux.flashReadServers[0], ndp.flashRdClient);
   
   OneToNRouter#(2, Bit#(5)) setBytePort <- mkOneToNRouterPipelined;
   OneToNRouter#(2, ParamT) setParamPort <- mkOneToNRouterPipelined;
   
   zipWithM_(mkConnection, setBytePort.outPorts, ndp.configurePorts);
   zipWithM_(mkConnection, setParamPort.outPorts, ndp.configurePorts);

   Reg#(StatusT) state <- mkReg(Init0);
   Reg#(Bit#(32)) reqCnt <- mkReg(0);
   
   Reg#(Bit#(64)) ndpCnt <- mkReg(0);
   
   Integer ndpCount = valueOf(NDPCount);
   
   Vector#(NDPCount, Bit#(5)) colBytesV = replicate(fromInteger(colBytes));
   
   rule init_colWidth if (state == Init0);
      if (ndpCnt == 0) rand_seed();
      // ndp.configure.setColBytes(fromInteger(colBytes));
      setBytePort.inPort.enq(tuple2(truncate(ndpCnt), colBytesV[ndpCnt]));
      // init_test(fromInteger(colBytes));
      if ( ndpCnt + 1 == fromInteger(ndpCount) ) begin
         ndpCnt <= 0;
         state <= Init1;
      end
      else begin
         ndpCnt <= ndpCnt + 1;
      end
   endrule
   

   Bit#(64) totalRows = getNumRows("l_shipdate")/100000;
   
   Bit#(3) configBits = ?;
   configBits[0] = 0; // maskRdPort
   configBits[1] = 1; // allRows
   configBits[2] = pack(isPassThru);
   
   Bit#(64) totalRowsExpected = 2810;

   
   Vector#(NDPCount, ParamT) params = vec(vec(zeroExtend(totalRows), zeroExtend(getBaseAddr("l_shipdate")), zeroExtend(configBits), ?),vec(728294, 728658, 1, 1));
   
   Reg#(Bit#(64)) numRowsReg <- mkRegU();
   
   rule init_param if ( state == Init1);
      setParamPort.inPort.enq(tuple2(truncate(ndpCnt), params[ndpCnt]));
      if ( ndpCnt + 1 == fromInteger(ndpCount) ) begin
         ndpCnt <= 0;
         reqCnt <= 1;
         state <= Run;
         numRowsReg <= totalRows; 
      end
      else begin
         ndpCnt <= ndpCnt + 1;
      end
   endrule
   
   
   Reg#(Bit#(64)) vecCnt <- mkReg(0);
   rule handeReserveReq;
      let req <- ndp.reserveRowVecs.request.get();
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
      ndp.reserveRowVecs.response.put(?);
   endrule
      
   // Reg#(Bit#(64)) totalBeat <- mkRegU;

   // rule sendReq if ( state == Run && reqCnt > 0);
   //    ndp.start;
   //    reqCnt <= reqCnt - 1;
   //    // $finish();
   // endrule
   
   // Reg#(Bool) maskDone <- mkReg(False);
   // Reg#(Bool) dataDone <- mkReg(False);
   
   
   // Reg#(Bit#(32)) maskRespCnt <- mkReg(0);
   
   Reg#(Bit#(64)) rowAggr <- mkReg(0);
   rule collectRowMask if ( state == Run);
      let d <- ndp.rowMaskWrite.get();
      
      // ndp.streamOut.rowMask.deq();
      // maskRespCnt <= maskRespCnt + 1;
      $display("RowMask, rowAddr = %d, mask = %b, rowAggr = %d", d.id, d.mask, rowAggr+pack(zeroExtend(countOnes(d.mask))));
      // let v <- inject_rowMask(d.mask);
      
      rowAggr <= rowAggr + pack(zeroExtend(countOnes(d.mask)));
      // if ( !v ) begin
      //    $display("Error RowMask finish");
      //    $finish;
      // end
      
      // if ( d.last ) begin
      //    $display("all RowMask done correctly");
      //    maskDone <= True;
      //    $display("total rows = %d", rowAggr+pack(zeroExtend(countOnes(d.mask))));
      // end
   endrule
   
   Reg#(Bit#(64)) prevRowVec <- mkReg(-1);
   rule doRowVecReq;
      ndp.rowVecReq.deq();
      let d = ndp.rowVecReq.first;
      
      // prevRowVec <= prevRowVec + 1;
      
      $display(fshow(d));
      
      if (d.numRowVecs != 1 ) begin
         $display("Test Failed, numVecCnts should be 1 vs %d", d.numRowVecs);
         $finish();
      end
      
      if ( d.last ) begin
         $display("Test Done, rowAggr = %d, expected = %d", rowAggr, totalRowsExpected);
         $finish();
      end

      // case (d) matches
      //    tagged RowVecId .rowVecId:
      //       begin
      //          // if ( prevRowVec + 1 != rowVecId ) begin
      //          //    $display("FAILED:: FirstPredicateEva ~ RowVecId is not continous (%d vs %d)", prevRowVec+1, rowVecId);
      //          //    $finish();
      //          // end
      //       end
      //    tagged Last: 
      //       begin
      //          $display("Test Done, rowAggr = %d", rowAggr);
      //          $finish();
      //       end
      // endcase
   endrule
            
            
   // `ifndef PassThru
   // Reg#(Bit#(64)) dataRespCnt <- mkReg(0);
   // rule collectRowData if ( state == Run);
   //    let d = ndp.streamOut.rowData.first;
   //    ndp.streamOut.rowData.deq();
   //    dataRespCnt <= dataRespCnt + 1;
   //    $display("RowData, cnt = %d, data = %h", dataRespCnt, d);
   //    let v <- inject_rowData(d);
   //    if ( !v ) $finish;
      
   //    if ( dataRespCnt + 1 == totalBeat ) begin
   //       $display("all RowData done correctly");
   //       dataDone <= True;
   //    end
         
   // endrule
   // `endif

   // rule passTest if (maskDone 
   //                  `ifndef PassThru
   //                  && dataDone
   //                  `endif
   //                   );
      
   //    $display("RowAggr = %d, numRows = %d", rowAggr, numRowsReg);
   //    if ( rowAggr == numRowsReg) 
   //       $display("Test Passed");
   //    else
   //       $display("Test Failed");
   //    $finish();
   // endrule
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
