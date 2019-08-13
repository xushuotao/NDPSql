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
import ColProcReader::*;
import ColXFormPE::*;
import ColXForm::*;
import GetPut::*;
import Pipe::*;
import AlgFuncs::*;
import Aggregate::*;

import ColProcProgrammer::*;
import ColXProgram::*;

// flash releted
import ControllerTypes::*;
import AuroraCommon::*;
import AuroraImportFmc1::*;
import FlashCtrlVirtex::*;
import FlashCtrlModel::*;
import EmptyFlash::*;

import FlashCtrlIfc::*;

import FlashSwitch::*;
import FlashReadMultiplex::*;
import EmulatedFlash::*;


import Connectable::*;
import BDPIHelper::*;

import Assert::*;


////////////////////////////////////////////////////////////////////////////////
/// ColProcReader Parameter Section
////////////////////////////////////////////////////////////////////////////////
typedef 6 NumCols; 
Integer numCols = valueOf(NumCols);
InColParamT colInfo_returnflag  = InColParamT{colType:Byte, baseAddr:getBaseAddr("l_returnflag")>>13};
InColParamT colInfo_linestatus  = InColParamT{colType:Byte, baseAddr:getBaseAddr("l_linestatus")>>13};
InColParamT colInfo_quantity    = InColParamT{colType:Int,  baseAddr:getBaseAddr("l_quantity")>>13};
InColParamT colInfo_extendprice = InColParamT{colType:Long, baseAddr:getBaseAddr("l_extendedprice")>>13};
InColParamT colInfo_discount    = InColParamT{colType:Long, baseAddr:getBaseAddr("l_discount")>>13};
InColParamT colInfo_tax         = InColParamT{colType:Long, baseAddr:getBaseAddr("l_tax")>>13};
Vector#(NumCols, InColParamT) colInfos = vec(colInfo_returnflag  ,
                                             colInfo_linestatus  ,
                                             colInfo_quantity    ,
                                             colInfo_extendprice ,
                                             colInfo_discount    ,
                                             colInfo_tax         );
////////////////////////////////////////////////////////////////////////////////
/// End of ColProcReader Parameter Section
////////////////////////////////////////////////////////////////////////////////


typedef enum{Init, Run, CheckResult} State deriving (Bits, Eq, FShow);
(* synthesize *)
module mkTb_ColXForm();
   
   Bit#(64) totalRows = (getNumRows("l_shipdate")/100000)/32*32;
   
   Vector#(2,FlashCtrlVirtexIfc) flashCtrls <- mapM(mkEmulatedFlashCtrl, genWith(fromInteger));
   
   Vector#(2, FlashSwitch#(1)) flashSwitches <- replicateM(mkFlashSwitch());
   
   mkConnection(flashSwitches[0].flashCtrlClient, flashCtrls[0].user);
   mkConnection(flashSwitches[1].flashCtrlClient, flashCtrls[1].user);
   
   FlashReadMultiplex#(1) flashMux <- mkFlashReadMultiplex;
   
   zipWithM_(mkConnection, flashMux.flashClient, vec(flashSwitches[0].users[0], flashSwitches[1].users[0]));
   

   ColProcReader colProcReader <- mkColProcReader;
   
   mkConnection(colProcReader.flashRdClient, flashMux.flashReadServers[0]);
   
   ColXForm#(NumColEngs) testEng <- mkColXForm;
   
   mkConnection(colProcReader.rowVecOut, testEng.rowVecIn);
   mkConnection(colProcReader.outPipe, testEng.inPipe);
   
                    
////////////////////////////////////////////////////////////////////////////////
/// Test Section
////////////////////////////////////////////////////////////////////////////////
   Reg#(State) state <- mkReg(Init);
   let {progLength_bit, peInsts} = genTest();
   let dummpy <- mkColXFormAutoProgram(progLength_bit, peInsts, testEng.programIfc);
      
   let programmer <- mkInColAutoProgram(totalRows, colInfos, colProcReader.programIfc);

   Aggregate#(4) aggr_quantity <- mkAggregate(True);
   Aggregate#(8) aggr_extended_price <- mkAggregate(True);
   Aggregate#(8) aggr_discount_price <- mkAggregate(True);
   Aggregate#(8) aggr_charge_price <- mkAggregate(True);

   rule doReset if (state == Init);
      aggr_quantity.reset;
      aggr_extended_price.reset;
      aggr_discount_price.reset;
      aggr_charge_price.reset;
      state <= Run;
   endrule

   Reg#(Bit#(64)) outputCnt <- mkReg(0);
   Reg#(Bit#(64)) cnt <- mkReg(0);
   Bit#(64) gap = 10000;
   
   // Vector#(Bit#(6)
   
   Reg#(Bit#(6)) beatCnt <- mkReg(0);
   
   Vector#(6, Bit#(64)) beatMax = vec(1, 1, 4, 8, 8, 8);
   
   Vector#(4, Reg#(Bit#(128))) sumV <- replicateM(mkReg(0));
   Vector#(4, Reg#(Bit#(64))) cntV <- replicateM(mkReg(0));
   Vector#(4, NDPStreamIn) inStreams = vec(aggr_quantity.streamIn,
                                           aggr_extended_price.streamIn,
                                           aggr_discount_price.streamIn,
                                           aggr_charge_price.streamIn);
      
   rule runAggr;
      Integer i = 0;
      if ( aggr_quantity.aggrResp.notEmpty) begin
         aggr_quantity.aggrResp.deq;
         let aggr = aggr_quantity.aggrResp.first;
         cntV[i] <= cntV[i] + aggr.cnt;
         sumV[i] <= sumV[i] + truncate(aggr.sum);
      end
      i = i + 1;

      if ( aggr_extended_price.aggrResp.notEmpty) begin
         aggr_extended_price.aggrResp.deq;
         let aggr = aggr_extended_price.aggrResp.first;
         cntV[i] <= cntV[i] + aggr.cnt;
         sumV[i] <= sumV[i] + truncate(aggr.sum);
      end
      i = i + 1;

      if ( aggr_discount_price.aggrResp.notEmpty) begin
         aggr_discount_price.aggrResp.deq;
         let aggr = aggr_discount_price.aggrResp.first;
         cntV[i] <= cntV[i] + aggr.cnt;
         sumV[i] <= sumV[i] + truncate(aggr.sum);
      end
      i = i + 1;

      if ( aggr_charge_price.aggrResp.notEmpty) begin
         aggr_charge_price.aggrResp.deq;
         let aggr = aggr_charge_price.aggrResp.first;
         cntV[i] <= cntV[i] + aggr.cnt;
         sumV[i] <= sumV[i] + truncate(aggr.sum);
      end
      i = i + 1;
   endrule
   
   Reg#(Bit#(64)) rowVecCnt <- mkReg(0);
   rule doInput if ( state == Run && rowVecCnt < toNumRowVecs(totalRows) );
      rowVecCnt <= rowVecCnt + 1;
      colProcReader.rowVecReq.enq(RowVecReq{numRowVecs: 1,
                                            maskZero: False,
                                            rowAggr: 32,
                                            last: rowVecCnt + 1 == toNumRowVecs(totalRows)});
      
   endrule
   
   rule doRowVecDeq;
      let {rowVec, last} = testEng.rowVecOut.first;
      testEng.rowVecOut.deq;
      function Action enqMask(NDPStreamIn inStream);
         return (action
                  inStream.rowMask.enq(RowMask{rowVecId:rowVec,
                                               hasData:True,
                                               isLast: last,
                                               mask: maxBound});
                 endaction);
      endfunction
      mapM_(enqMask, inStreams);
      $display("(@%t) RowVecId = %d, last = %d", $time, rowVec, last);
   endrule
   
   Reg#(Bit#(64)) cycleCnt <- mkReg(0);
   rule incrCnt if (state == Run);
      cycleCnt <= cycleCnt + 1;
   endrule
      
   Reg#(Bit#(64)) rowVecIdCnt <- mkReg(0);
   
   Reg#(Bit#(4)) colCnt <- mkReg(0);

   rule doOutput if (state == Run);
      let tester = testEng.outPipe.first;
      testEng.outPipe.deq;
      
      if ( beatCnt + 1 == truncate(beatMax[colCnt]) ) begin
         beatCnt <= 0;
         colCnt <= (colCnt + 1) % 6;
      end
      else begin
         beatCnt <= beatCnt + 1;
      end
      
      if ( colCnt > 1 ) begin
         inStreams[colCnt-2].rowData.enq(tester);
      end
      
      if ( outputCnt + 1 == (toNumRowVecs(totalRows) * fold(add2, beatMax) )) begin
         cnt <= 0;
         state <= CheckResult;
      end
      
      $display("(@%t) Output cnt = %d, tester = %h", $time, outputCnt, tester);
      
      outputCnt <= outputCnt + 1;
   endrule
  
   rule doIncrCont if (state == CheckResult && cnt < gap);
      cnt <= cnt + 1;
   endrule
      
   Vector#(4, Bit#(128)) expectedSum = vec(460501, 69015402074, 6558152859838, 682286850929479);
   Vector#(4, Bit#(64)) expectedCnt = replicate(17984);
  
   rule doCheckResult if (state == CheckResult && cnt == gap);
      if ( colProcReader.outPipe.notEmpty ) begin
         $display( "Failed:: ColXForm produced more beats than expected");
      end
      else begin
         $display("Columns:: \tquantity, \textended_price, \tdiscount_price, \tcharge_price");
         $display("ColXForm_Sums:: \t%32d, \t%32d, \t%32d, \t%32d", sumV[0], sumV[1], sumV[2], sumV[3]);
         $display("Expected_Sums:: \t%32d, \t%32d, \t%32d, \t%32d", expectedSum[0], expectedSum[1], expectedSum[2], expectedSum[3]);
         $display("ColXForm_Cnts:: \t%32d, \t%32d, \t%32d, \t%32d", cntV[0], cntV[1], cntV[2], cntV[3]);
         $display("Expected_Cnts:: \t%32d, \t%32d, \t%32d, \t%32d", expectedCnt[0], expectedCnt[1], expectedCnt[2], expectedCnt[3]);

         if ( readVReg(sumV) == expectedSum && readVReg(cntV) == expectedCnt)
            $display("Pass:: ColXForm, , total Data Beats = %d, cycle = %d", toNumRowVecs(totalRows) * fold(add2, beatMax), cycleCnt);
         else
            $display("Fail:: ColXForm, aggregate result doesn't match");
      end
         
      $finish;
   endrule


   rule fakeDrive;
      flashCtrls[0].aurora.rxn_in(?);
      flashCtrls[1].aurora.rxn_in(?);
      
      flashCtrls[0].aurora.rxp_in(?);
      flashCtrls[1].aurora.rxp_in(?);
 
   endrule
   
endmodule       
