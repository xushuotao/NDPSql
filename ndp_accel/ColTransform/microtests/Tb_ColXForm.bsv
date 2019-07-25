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
/// ColEng Instruction Section
////////////////////////////////////////////////////////////////////////////////
typedef 1 NumColEngs;
Integer numColEngs = valueOf(NumColEngs);
Bit#(64) most_negative = 1<<63;
Vector#(8, DecodeInst) peProg = replicate(DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, colType: ?, strType: ?, imm: ?});
Vector#(NumColEngs, Vector#(8, DecodeInst)) pePrograms = replicate(peProg);
Vector#(NumColEngs, Integer) progLength = replicate(1);
Vector#(NumColEngs, Integer) numInsts = replicate(1);
////////////////////////////////////////////////////////////////////////////////
/// End of ColEng Instruction Section
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
/// ColProcReader Parameter Section
////////////////////////////////////////////////////////////////////////////////
typedef 6 NumCols; 
Integer numCols = valueOf(NumCols);
Bit#(64) totalRows = 8192;//getNumRows("l_shipdate")/100000;
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


typedef enum{Prog_Reader, Prog_ColX, Run} State deriving (Bits, Eq, FShow);
(* synthesize *)
module mkTb_ColXForm();
   
   Vector#(2,FlashCtrlVirtexIfc) flashCtrls <- mapM(mkEmulatedFlashCtrl, genWith(fromInteger));
   
   Vector#(2, FlashSwitch#(1)) flashSwitches <- replicateM(mkFlashSwitch());
   
   mkConnection(flashSwitches[0].flashCtrlClient, flashCtrls[0].user);
   mkConnection(flashSwitches[1].flashCtrlClient, flashCtrls[1].user);
   
   FlashReadMultiplex#(1) flashMux <- mkFlashReadMultiplex;
   
   zipWithM_(mkConnection, flashMux.flashClient, vec(flashSwitches[0].users[0], flashSwitches[1].users[0]));
   

   ColProcReader colProcReader <- mkColProcReader;
   
   mkConnection(colProcReader.flashRdClient, flashMux.flashReadServers[0]);
   
   ColXForm#(NumColEngs) testEng <- mkColXForm;
   
   mkConnection(colProcReader.outPipe, testEng.inPipe);
   
                    
////////////////////////////////////////////////////////////////////////////////
/// Test Section
////////////////////////////////////////////////////////////////////////////////
   Reg#(State) state <- mkReg(Prog_ColX);

   Reg#(Bit#(TLog#(TAdd#(NumColEngs, 1)))) colXEngCnt <- mkReg(0);
   Reg#(Bit#(4)) prog_cnt <- mkReg(0);   

   rule doProgramColX if (state == Prog_ColX);
      if ( prog_cnt  < fromInteger(progLength[colXEngCnt]) ) begin
         testEng.programPorts.enq(tuple2(truncate(colXEngCnt),
                                         tuple3(truncate(prog_cnt), False, pack(pePrograms[colXEngCnt][prog_cnt]))));
         prog_cnt <= prog_cnt + 1;
      end
      else if ( prog_cnt  == fromInteger(progLength[colXEngCnt])) begin
         prog_cnt <= 0;
         testEng.programPorts.enq(tuple2(truncate(colXEngCnt),
                                         tuple3(?, True, extend(prog_cnt))));
         if ( colXEngCnt + 1 == fromInteger(numColEngs)) begin
            state <= Prog_Reader;
            colXEngCnt <= 0;
         end
         else begin
            colXEngCnt <= colXEngCnt + 1;
         end
      end
   endrule
   
   Reg#(Bool) rowSet <- mkReg(False);
   rule doProgramReader_0 if (state == Prog_Reader && !rowSet);
      colProcReader.setRowNums(totalRows, fromInteger(numCols));
      rowSet <= True;
   endrule
   
   Reg#(Bit#(4)) colCnt <- mkReg(0);
   rule doProgramReader_1 if (state == Prog_Reader && rowSet);
      dynamicAssert(tpl_2(colInfos[colCnt])%8192 == 0, "baseAddr should be page aligned!");
      if ( colCnt + 1 == fromInteger(numCols)) begin
         colCnt <= 0;
         state <= Run;
         rowSet <= False;
         colProcReader.colInfoPort.enq(tuple4(truncate(colCnt), tpl_1(colInfos[colCnt]), tpl_2(colInfos[colCnt])>>13, True));
      end
      else begin
         colCnt <= colCnt + 1;
         colProcReader.colInfoPort.enq(tuple4(truncate(colCnt), tpl_1(colInfos[colCnt]), tpl_2(colInfos[colCnt])>>13, False));
      end
   endrule

   Reg#(Bit#(64)) outputCnt <- mkReg(0);

   rule doOutput if (state == Run);
      let tester = testEng.outPipe.first;
      testEng.outPipe.deq;
      
      $display("Output cnt = %d, tester = %h", outputCnt, tester);
      
      outputCnt <= outputCnt + 1;
   endrule
  

   rule fakeDrive;
      flashCtrls[0].aurora.rxn_in(?);
      flashCtrls[1].aurora.rxn_in(?);
      
      flashCtrls[0].aurora.rxp_in(?);
      flashCtrls[1].aurora.rxp_in(?);
 
   endrule
   
endmodule
                 
