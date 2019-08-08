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
Tuple2#(ColType, Bit#(64)) colInfo_returnflag  = tuple2(Byte, getBaseAddr("l_returnflag"));
Tuple2#(ColType, Bit#(64)) colInfo_linestatus  = tuple2(Byte, getBaseAddr("l_linestatus"));
Tuple2#(ColType, Bit#(64)) colInfo_quantity    = tuple2(Int, getBaseAddr("l_quantity"));
Tuple2#(ColType, Bit#(64)) colInfo_extendprice = tuple2(Long, getBaseAddr("l_extendedprice"));
Tuple2#(ColType, Bit#(64)) colInfo_discount    = tuple2(Long, getBaseAddr("l_discount"));
Tuple2#(ColType, Bit#(64)) colInfo_tax         = tuple2(Long, getBaseAddr("l_tax"));
Vector#(NumCols, Tuple2#(ColType, Bit#(64))) colInfos = vec(colInfo_returnflag  ,
                                                            colInfo_linestatus  ,
                                                            colInfo_quantity    ,
                                                            colInfo_extendprice ,
                                                            colInfo_discount    ,
                                                            colInfo_tax         );
////////////////////////////////////////////////////////////////////////////////
/// End of ColProcReader Parameter Section
////////////////////////////////////////////////////////////////////////////////


typedef enum{Prog_Reader, Run, CheckResult} State deriving (Bits, Eq, FShow);
(* synthesize *)
module mkTb_ColProcReader();

   Bit#(64) totalRows = getNumRows("l_shipdate")/100000/32*32;   
   
   Vector#(2,FlashCtrlVirtexIfc) flashCtrls <- mapM(mkEmulatedFlashCtrl, genWith(fromInteger));
   
   Vector#(2, FlashSwitch#(1)) flashSwitches <- replicateM(mkFlashSwitch());
   
   mkConnection(flashSwitches[0].flashCtrlClient, flashCtrls[0].user);
   mkConnection(flashSwitches[1].flashCtrlClient, flashCtrls[1].user);
   
   FlashReadMultiplex#(1) flashMux <- mkFlashReadMultiplex;
   
   zipWithM_(mkConnection, flashMux.flashClient, vec(flashSwitches[0].users[0], flashSwitches[1].users[0]));
   

   ColProcReader colProcReader <- mkColProcReader;
   
   mkConnection(colProcReader.flashRdClient, flashMux.flashReadServers[0]);
   
                    
////////////////////////////////////////////////////////////////////////////////
/// Test Section
////////////////////////////////////////////////////////////////////////////////
   Reg#(State) state <- mkReg(Prog_Reader);
   
   Reg#(Bool) rowSet <- mkReg(False);
   rule doProgramReader_0 if (state == Prog_Reader && !rowSet);
      colProcReader.programIfc.setRowNums(totalRows, fromInteger(numCols));
      rowSet <= True;
   endrule
   
   Reg#(Bit#(4)) colCnt <- mkReg(0);
   rule doProgramReader_1 if (state == Prog_Reader && rowSet);
      dynamicAssert(tpl_2(colInfos[colCnt])%8192 == 0, "baseAddr should be page aligned!");
      if ( colCnt + 1 == fromInteger(numCols)) begin
         colCnt <= 0;
         state <= Run;
         rowSet <= False;
         colProcReader.programIfc.colInfoPort.enq(tuple4(truncate(colCnt), tpl_1(colInfos[colCnt]), tpl_2(colInfos[colCnt])>>13, True));
      end
      else begin
         colCnt <= colCnt + 1;
         colProcReader.programIfc.colInfoPort.enq(tuple4(truncate(colCnt), tpl_1(colInfos[colCnt]), tpl_2(colInfos[colCnt])>>13, False));
      end
   endrule
   
   Reg#(Bit#(64)) cycleCnt <- mkReg(0);
   rule incrCnt if (state == Run);
      cycleCnt <= cycleCnt + 1;
   endrule
   
   Reg#(Bit#(64)) rowVecCnt <- mkReg(0);
   rule doInput if ( state == Run && rowVecCnt < toNumRowVecs(totalRows) );
      rowVecCnt <= rowVecCnt + 1;
      colProcReader.rowVecReq.enq(RowVecReq{numRowVecs: 1,
                                            maskZero: False,
                                            rowAggr: 32,
                                            last: rowVecCnt + 1 == toNumRowVecs(totalRows)});
      
   endrule

   Reg#(Bit#(64)) outputCnt <- mkReg(0);
   Reg#(Bit#(64)) cnt <- mkReg(0);
   Bit#(64) gap = 10000;

   rule doOutput if (state == Run);
      let tester = colProcReader.outPipe.first;
      colProcReader.outPipe.deq;
      
      $display("(@%t) Output cnt = %d, tester = %h", $time, outputCnt, tester);
      
      outputCnt <= outputCnt + 1;
      
      if ( outputCnt + 1 == (toNumRowVecs(totalRows) * (1+1+4+8+8+8) )) begin

         // $finish;
         state <= CheckResult;
         cnt <= 0;
      end
   endrule
   
   rule doRowVec;
      let rowVec = colProcReader.rowVecOut.first;
      colProcReader.rowVecOut.deq;
      $display("(@%t) RowVecId = ", $time, fshow(rowVec));
   endrule
   
   rule doIncrCont if (state == CheckResult && cnt < gap);
      cnt <= cnt + 1;
   endrule
      
  
   rule doCheckResult if (state == CheckResult && cnt == gap);
      if ( colProcReader.outPipe.notEmpty ) begin
         $display( "Failed:: ColProcReader produced more beats than expected");
      end
      else begin
         $display( "Pass:: ColProcReader, total Data Beats = %d, cycle = %d", toNumRowVecs(totalRows) * (1+1+4+8+8+8), cycleCnt);
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
                 
