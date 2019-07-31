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
typedef 4 NumColEngs;
////////////////////////////////////////////////////////////////////////////////
/// End of ColEng Instruction Section
////////////////////////////////////////////////////////////////////////////////

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


typedef enum{Prog_Reader, Prog_ColX, Run, CheckResult} State deriving (Bits, Eq, FShow);
(* synthesize *)
module mkTb_ColXForm();
   
   Bit#(64) totalRows = (getNumRows("l_shipdate")/100000)/32*32;
   
////////////////////////////////////////////////////////////////////////////////
/// ColEng Instruction Section
////////////////////////////////////////////////////////////////////////////////

   Integer numColEngs = valueOf(NumColEngs);
   Bit#(64) most_negative = 1<<63;
   Vector#(NumColEngs, Vector#(8, DecodeInst)) pePrograms = ?;//replicate(peProg);
   Vector#(NumColEngs, Integer) progLength = ?;//replicate(1);
   Integer i = 0;
   
   Vector#(8, DecodeInst) peProg = append(vec(DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, colType: Byte, strType: ?, imm: ?}, //rf
                                              DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, colType: Byte, strType: ?, imm: ?}, //ls
                                              DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, colType: Int, strType: ?, imm: ?}, //quantity
                                              DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, colType: Long, strType: ?, imm: ?}, // extended_price
                                              DecodeInst{iType: AluImm, aluOp: Sub, isSigned: True, colType: Long, strType: ?, imm: 100}, // 1 - discount
                                              DecodeInst{iType: AluImm, aluOp: Add, isSigned: True, colType: Long, strType: ?, imm: 100}), // 1 + tax
                                          ?);
                                              
   pePrograms[i] = peProg;
   progLength[i] = 6;
   i = i + 1;

      
   peProg = append(vec(DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, colType: Byte, strType: ?, imm: ?}, //rf
                       DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, colType: Byte, strType: ?, imm: ?}, //ls
                       DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, colType: Int, strType: ?, imm: ?}, //quantity
                       DecodeInst{iType: Copy, aluOp: ?, isSigned: ?, colType: Long, strType: Long, imm: ?}, // copy extended_price
                       DecodeInst{iType: Alu,  aluOp: Mullo, isSigned: True, colType: Long, strType: ?, imm: 100}, // 1 - discount * extended_price
                       DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, colType: Long, strType: ?, imm: ?}), // pass 1 + tax
                   ?);
      
   pePrograms[i] = peProg;
   progLength[i] = 6;
   i = i + 1;
   
   
   peProg = append(vec(DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, colType: Byte, strType: ?, imm: ?}, //rf
                       DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, colType: Byte, strType: ?, imm: ?}, //ls
                       DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, colType: Int, strType: ?, imm: ?}, //quantity
                       DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, colType: Long, strType: ?, imm: ?}, // pass extended_price
                       DecodeInst{iType: Copy, aluOp: ?, isSigned: ?, colType: Long, strType: Long, imm: ?}, // copy 1 - discount * extended_price
                       DecodeInst{iType: Alu,  aluOp: Mullo, isSigned: True, colType: Long, strType: ?, imm: ?}), // (1 + tax) * (1 - discount * extended_price)
                   ?);
      
   pePrograms[i] = peProg;
   progLength[i] = 6;
   i = i + 1;

   peProg = append(vec(DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, colType: Byte, strType: ?, imm: ?}, //rf
                       DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, colType: Byte, strType: ?, imm: ?}, //ls
                       DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, colType: Int, strType: ?, imm: ?}, //quantity
                       DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, colType: Long, strType: ?, imm: ?}, // pass extended_price
                       DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, colType: Long, strType: ?, imm: ?}, // pass 1 - discount * extended_price
                       DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, colType: Long, strType: ?, imm: ?}), // pass (1 + tax) * (1 - discount * extended_price)
                   ?);
      
   pePrograms[i] = peProg;
   progLength[i] = 6;
   i = i + 1;

////////////////////////////////////////////////////////////////////////////////
/// End of ColEng Instruction Section
////////////////////////////////////////////////////////////////////////////////

   
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
   Reg#(Bit#(64)) cnt <- mkReg(0);
   Bit#(64) gap = 10000;
   
   // Vector#(Bit#(6)
   
   Reg#(Bit#(6)) beatCnt <- mkReg(0);
   
   Vector#(6, Bit#(64)) beatMax = vec(1, 1, 4, 8, 8, 8);
   
   Vector#(4, Reg#(Bit#(128))) sumV <- replicateM(mkReg(0));
   Vector#(4, Reg#(Bit#(64))) cntV <- replicateM(mkReg(0));
   
   Aggregate#(4) aggr_quantity <- mkAggregate(True);
   Aggregate#(8) aggr_extended_price <- mkAggregate(True);
   Aggregate#(8) aggr_discount_price <- mkAggregate(True);
   Aggregate#(8) aggr_charge_price <- mkAggregate(True);
   
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
         if ( beatCnt + 1 == truncate(beatMax[colCnt]) ) begin
            inStreams[colCnt-2].rowMask.enq(RowMask{rowVecId:?,
                                                    hasData:True,
                                                    isLast: False,
                                                    mask: maxBound});   
         end
      end
      
      if ( outputCnt + 1 == (toNumRowVecs(totalRows) * fold(add2, beatMax) )) begin
         cnt <= 0;
         state <= CheckResult;
      end
      
      $display("Output cnt = %d, tester = %h", outputCnt, tester);
      
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
            $display("Pass:: ColXForm");
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
                 
