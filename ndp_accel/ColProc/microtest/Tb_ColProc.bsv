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


import FlashReadMultiplex::*;
import EmulatedFlash::*;
import DualFlashPageBuffer::*;

import Connectable::*;
import RowMask::*;

import FlashSwitch::*;
import AlgFuncs::*;

import RowSelector::*;
import ColProc::*;
import ColProcReader::*;

import Aggregate::*;

import RowSelectorProgrammer::*;
import ColProcProgrammer::*;

import NDPCommon::*;

import TableTaskTest::*;


(* synthesize *)
module mkTb_ColProc(Empty);
   Vector#(2,FlashCtrlVirtexIfc) flashCtrls <- mapM(mkEmulatedFlashCtrl, genWith(fromInteger));
   
   Vector#(2, FlashSwitch#(1)) flashSwitches <- replicateM(mkFlashSwitch());
   
   mkConnection(flashSwitches[0].flashCtrlClient, flashCtrls[0].user);
   mkConnection(flashSwitches[1].flashCtrlClient, flashCtrls[1].user);
   
   // FlashReadMultiplex#(TAdd#(ColCount_RowSel,1)) flashMux <- mkFlashReadMultiplex;
   FlashReadMultiplexOO#(1) flashMux <- mkFlashReadMultiplexOO;

   zipWithM_(mkConnection, flashMux.flashClient, vec(flashSwitches[0].users[0], flashSwitches[1].users[0]));
   
   DualFlashPageBuffer#(TAdd#(ColCount_RowSel,1), PageBufSz) pageBuf <- mkDualFlashPageBuffer;
   
   mkConnection(pageBuf.flashRdClient, flashMux.flashReadServers[0]);

   
   RowSelector#(ColCount_RowSel) rowSel <- mkRowSelector;
   
   ColProc colProc <- mkColProc;
      
   zipWithM_(mkConnection, cons(colProc.pageBufferClient, reverse(rowSel.pageBufferClients)), pageBuf.pageBufferServers);
   
   mkConnection(rowSel.rowVecReq, colProc.rowVecReq);

   RowMaskBuff#(TAdd#(ColCount_RowSel,1)) rowMaskBuff <- mkRowMaskBuff;
   
   mkConnection(rowSel.reserveRowVecs, rowMaskBuff.reserveRowVecs);
   mkConnection(colProc.releaseRowVecs, rowMaskBuff.releaseRowVecs);

   
   zipWithM_(mkConnection, reverse(rowSel.rowMaskWrites), take(rowMaskBuff.writePorts));
   zipWithM_(mkConnection, cons(colProc.maskReadClient, reverse(rowSel.rowMaskReads)), rowMaskBuff.readPorts);

////////////////////////////////////////////////////////////////////////////////
/// Auto Program Part
////////////////////////////////////////////////////////////////////////////////
   let totalRows = getNumRows("l_shipdate")/denom;//genTotalRows();
   let rowSelInfo = genRowSelInfo();
   mkRowSelectAutoProgram(rowSelInfo, rowSel.programIfc);

   
   mkInColAutoProgram(totalRows, inColInfos, colProc.programColProcReader);
   let {progLength_bit, peInsts} = genTest();
   mkColXFormAutoProgram(progLength_bit, peInsts, colProc.programColXForm);
   mkOutColAutoProgram(outColInfos, colProc.programOutputCol); 
////////////////////////////////////////////////////////////////////////////////
/// End of Auto Program Part
////////////////////////////////////////////////////////////////////////////////
   
   
   Reg#(Bit#(64)) cycleCnt <- mkReg(0);
   rule incrCycle;
      cycleCnt <= cycleCnt + 1;
   endrule
   
   Vector#(MaxNumCol, Reg#(Maybe#(AggrResp))) aggrResult <- replicateM(mkReg(tagged Invalid));
   for (Integer i = 0; i < valueOf(MaxNumCol); i = i + 1) begin
      rule doResp;
         let v = colProc.colProcOutput.aggrResultOut[i].first;
         colProc.colProcOutput.aggrResultOut[i].deq;
         $display("Output column %d got resp = ", i, fshow(v));
         aggrResult[i] <= tagged Valid v;
      endrule
   end
   
   Vector#(4, Bool) validSignals = takeAt(2, map(isValid, readVReg(aggrResult)));
   rule checkResult if ( pack(validSignals) == maxBound);
      $display("ColProc Test done, please check the result with q24 in software run");
      $display("Totalbeats = %d, cycle = %d", fold(add2, columnBeats)*toNumRowVecs(genTotalRows()), cycleCnt);
      for ( Integer i = 0; i < valueOf(MaxNumCol); i = i + 1 ) begin
         if ( aggrResult[i] matches tagged Valid .aggr) begin
            $display("col %d sum = %d, cnt = %d, min = %d, max = %d", i, aggr.sum, aggr.cnt, aggr.min, aggr.max);
         end
         else begin
            $display("col %d is Invalid", i);
         end
      end
      
      $display("RowSelectorParamT size = %d", valueOf(SizeOf#(RowSelectorParamT)));
      $display("InColParamT size = %d", valueOf(SizeOf#(InColParamT)));
      $display("ColXFormParamT size = %d", valueOf(SizeOf#(Bit#(32))));
      $display("OutColParamT size = %d", valueOf(SizeOf#(OutColParamT)));
      $finish();
   endrule

   
   rule fakeDrive;
      flashCtrls[0].aurora.rxn_in(?);
      flashCtrls[1].aurora.rxn_in(?);
      
      flashCtrls[0].aurora.rxp_in(?);
      flashCtrls[1].aurora.rxp_in(?);
   endrule
endmodule
