import NDPCommon::*;
import NDPSelect::*;
import FirstColReader::*;
import ColReader::*;
import PredicateResult::*;

import BuildVector::*;

import GetPut::*;
import ClientServer::*;
import ClientServerHelper::*;
import FlashCtrlIfc::*;
import RowMask::*;

import Pipe::*;
import Vector::*;

import Connectable::*;

import DualFlashPageBuffer::*;

interface FirstPredicateEval;
   interface PageBufferClient#(PageBufSz) pageBufClient;
   interface Client#(Bit#(9), void) reserveRowVecs;
   interface Get#(RowMaskWrite) rowMaskWrite;
   interface PipeOut#(RowVecReq) rowVecReq;
   interface Vector#(2, NDPConfigure) configurePorts;
endinterface

interface PredicateEval;
   interface PageBufferClient#(PageBufSz) pageBufClient;
   
   interface Client#(RowMaskRead, RowVectorMask) rowMaskRead;
   interface Get#(RowMaskWrite) rowMaskWrite;

   interface PipeIn#(RowVecReq) rowVecReqIn;
   interface PipeOut#(RowVecReq) rowVecReqOut;

   interface Vector#(2, NDPConfigure) configurePorts;
endinterface


(* synthesize *)
module mkFirstPredicateEval(FirstPredicateEval);
   let colReader <- mkFirstColReader;
   let predEval <- mkNDPSelect;
   let predResult <- mkPredicateResult;
   
   mkConnection(colReader.streamOut, predEval.streamIn);
   mkConnection(predEval.streamOut, predResult.streamIn);
   
   Reg#(Bit#(1)) rowVecReqOutSel <- mkReg(0);
   
   
   Vector#(2, PipeOut#(RowVecReq)) rowVecReqOuts = vec(colReader.rowVecReqOut, predResult.rowVecReq);
   
   let readerConfig = (interface NDPConfigure;
                          method Action setColBytes(Bit#(5) colBytes);
                             colReader.configure.setColBytes(colBytes);
                          endmethod
                          method Action setParameters(ParamT params);
                             colReader.configure.setParameters(params);
                             Bool forward = unpack(params[2][2]);
                             rowVecReqOutSel <= forward ? 0 : 1;
                          endmethod
                       endinterface);

   // interface Client flashRdClient = colReader.flashRdClient;
   interface pageBufClient = colReader.pageBufClient;
   interface Client reserveRowVecs = colReader.reserveRowVecs;
   interface Get rowMaskWrite = predResult.rowMaskWrite;
   interface PipeOut rowVecReq = rowVecReqOuts[rowVecReqOutSel];
   interface configurePorts = vec(readerConfig,
                                  predEval.configure);
endmodule


(* synthesize *)
module mkPredicateEval(PredicateEval);
   let colReader <- mkColReader;
   let predEval <- mkNDPSelect;
   let predResult <- mkPredicateResult;
   
   mkConnection(colReader.streamOut, predEval.streamIn);
   mkConnection(predEval.streamOut, predResult.streamIn);
   
   Reg#(Bit#(1)) rowVecReqOutSel <- mkReg(0);
   
   
   Vector#(2, PipeOut#(RowVecReq)) rowVecReqOuts = vec(colReader.rowVecReqOut, predResult.rowVecReq);
   
   let readerConfig = (interface NDPConfigure;
                          method Action setColBytes(Bit#(5) colBytes);
                             colReader.configure.setColBytes(colBytes);
                          endmethod
                          method Action setParameters(ParamT params);
                             colReader.configure.setParameters(params);
                             Bool forward = unpack(params[2][2]);
                             rowVecReqOutSel <= forward ? 0 : 1;
                          endmethod
                       endinterface);

   interface pageBufClient = colReader.pageBufClient;
   interface Client rowMaskRead = colReader.maskRdClient;
   interface Get rowMaskWrite = predResult.rowMaskWrite;
   
   interface PipeIn rowVecReqIn = colReader.rowVecReqIn;
   interface PipeOut rowVecReqOut = rowVecReqOuts[rowVecReqOutSel];
   interface configurePorts = vec(readerConfig,
                                  predEval.configure);
endmodule
