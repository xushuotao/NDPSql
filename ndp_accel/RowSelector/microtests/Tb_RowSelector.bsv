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


import Connectable::*;
import RowMask::*;

import FlashSwitch::*;
import AlgFuncs::*;

import RowSelector::*;
import ProgramRowSelector::*;

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

typedef 4 ColCount;                 
typedef TMul#(ColCount,2) NDPCount;
                 

Integer colBytes = valueOf(ColBytes); 

Int#(32) int_min = minBound;
                 
typedef enum {Init0, Init1, Run} StatusT deriving (Bits, Eq, FShow);



(* synthesize *)
module mkTb_RowSelector(Empty);
   
   
   Vector#(2,FlashCtrlVirtexIfc) flashCtrls <- mapM(mkEmulatedFlashCtrl, genWith(fromInteger));
   
   Vector#(2, FlashSwitch#(1)) flashSwitches <- replicateM(mkFlashSwitch());
   
   mkConnection(flashSwitches[0].flashCtrlClient, flashCtrls[0].user);
   mkConnection(flashSwitches[1].flashCtrlClient, flashCtrls[1].user);
   
   FlashReadMultiplex#(ColCount) flashMux <- mkFlashReadMultiplex;
   
   zipWithM_(mkConnection, flashMux.flashClient, vec(flashSwitches[0].users[0], flashSwitches[1].users[0]));
   
   RowSelector#(ColCount) ndp <- mkRowSelector;
   
   zipWithM_(mkConnection, ndp.flashRdClients, flashMux.flashReadServers);
   
   // RowSelector#(ColCount)
   RowMaskBuff#(ColCount) rowMaskBuff <- mkRowMaskBuff;
   
   mkConnection(ndp.reserveRowVecs, rowMaskBuff.reserveRowVecs);
   
   zipWithM_(mkConnection, ndp.rowMaskWrites, rowMaskBuff.writePorts);
   zipWithM_(mkConnection, ndp.rowMaskReads, rowMaskBuff.readPorts);

   Reg#(StatusT) state <- mkReg(Run);

   Bit#(64) totalRows = getNumRows("l_shipdate")/100000;
   Bit#(64) totalRowsExpected = 333; //732; //2801;
   Int#(32) int_min = minBound;
   
                 
   Vector#(ColCount, RowSelectorParamT) programInfo = vec(RowSelectorParamT{colType: Int,
                                                                            numRows: totalRows,
                                                                            baseAddr: getBaseAddr("l_shipdate"),
                                                                            forward: False,
                                                                            allRows: True,
                                                                            rdPort: 0,
                                                                            lowTh:728294, 
                                                                            hiTh:728658, 
                                                                            isSigned:True, 
                                                                            andNotOr:True },
                 
                                                          RowSelectorParamT{colType: Long,
                                                                            numRows: totalRows,
                                                                            baseAddr: getBaseAddr("l_discount"),
                                                                            forward: False,
                                                                            allRows: False,
                                                                            rdPort: 0,
                                                                            lowTh:5, 
                                                                            hiTh:7, 
                                                                            isSigned:True, 
                                                                            andNotOr:True },
                 
                                                          RowSelectorParamT{colType: Int,
                                                                            numRows: totalRows,
                                                                            baseAddr: getBaseAddr("l_quantity"),
                                                                            forward: False,
                                                                            allRows: False,
                                                                            rdPort: 0,
                                                                            lowTh:zeroExtend(pack(int_min)), 
                                                                            hiTh:23, 
                                                                            isSigned:True, 
                                                                            andNotOr:True },
                 
                                                          RowSelectorParamT{colType: ?,
                                                                            numRows: totalRows,
                                                                            baseAddr: 0,
                                                                            forward: True,
                                                                            allRows: ?,
                                                                            rdPort: ?,
                                                                            lowTh:?,
                                                                            hiTh:?, 
                                                                            isSigned:?, 
                                                                            andNotOr:? });
   
   ProgramRowSelectorClient#(ColCount) programmer <- mkRowSelectAutoProgram(programInfo);

   mkConnection(programmer.setColBytesPort, ndp.programIfc.setColBytesPort);
   mkConnection(programmer.setParamPort, ndp.programIfc.setParamPort);
                 
   
   Reg#(Bit#(64)) rowAggr <- mkReg(0);
   Reg#(Bit#(64)) prevRowVec <- mkReg(-1);
   
   Reg#(Bit#(64)) numRowVecs <- mkReg(0);
   rule doRowVecReq;
      ndp.rowVecReq.deq();
      let d = ndp.rowVecReq.first;
      
      $display(fshow(d));
      rowAggr <= rowAggr + d.rowAggr;
      
      if (d.numRowVecs != 1 ) begin
         $display("Test Message: numVecCnts is greater than 1 vs %d", d.numRowVecs);
         // $finish();
      end
      
      rowMaskBuff.releaseRowVecs.put(truncate(d.numRowVecs));
      
      numRowVecs <= numRowVecs + d.numRowVecs;
      
      if ( d.last ) begin
         $display("Test Done, rowAggr = %d, expected = %d, numRowVecs = %d, expected = %d", rowAggr + d.rowAggr, totalRowsExpected, numRowVecs + d.numRowVecs, (totalRows+31)/32);
         $finish();
      end
      

   endrule
            
   rule fakeDrive;
      flashCtrls[0].aurora.rxn_in(?);
      flashCtrls[1].aurora.rxn_in(?);
      
      flashCtrls[0].aurora.rxp_in(?);
      flashCtrls[1].aurora.rxp_in(?);
 
   endrule
endmodule
