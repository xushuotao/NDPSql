import NDPCommon::*;
import NDPSelect::*;
import FirstColReader::*;
// import ColReader::*;
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

interface FirstPredicateEval;
   interface Client#(DualFlashAddr, Bit#(256)) flashRdClient;
      
   interface Client#(Bit#(9), void) reserveRowVecs;
   
   interface Get#(RowMaskWrite) rowMaskWrite;

   interface PipeOut#(RowVecReq) rowVecReq;

   // set up parameter
   interface Vector#(2, NDPConfigure) configurePorts;
   
   // method Action start();
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



   interface Client flashRdClient = colReader.flashRdClient;
   interface Client reserveRowVecs = colReader.reserveRowVecs;
   interface Get rowMaskWrite = predResult.rowMaskWrite;
   interface PipeOut rowVecReq = rowVecReqOuts[rowVecReqOutSel];
   interface configurePorts = vec(readerConfig,
                                  predEval.configure);
   
   // method Action start();
   //    colReader.start;
   // endmethod

endmodule


// interface FirstPredicateEval;
//    interface Client#(DualFlashAddr, Bit#(256)) flashRdClient;
//    interface Client#(RowVectorId, RowVectorMask)) maskRdPort;   
//    interface PipeIn#(Tuple2#(Bool,Bool)) rowVecReqIn;
   
//    interface PipeOut#(Tuple2#(Bool,Bool)) rowVecReqOut;
//    // set up parameter
//    interface Vector#(2, NDPConfigure) configurePorts;
// endinterface


// (* synthesize *)
// module mkPredicateEval(FirstPredicateEval);
//    let colReader <- mkColReader;
//    let predEval <- mkNDPSelect;
//    let predResult <- mkPredicateResult;
   
//    mkConnection(colReader.streamOut, predEval.streamIn);
//    mkConnection(predEval.streamOut, predResult.streamIn);

//    interface Client#(DualFlashAddr, Bit#(256)) flashRdClient;
//    interface Client#(RowVectorId, RowVectorMask)) maskRdPort;   
//    interface PipeIn#(Tuple2#(Bool,Bool)) rowVecReqIn;
   
//    interface PipeOut#(Tuple2#(Bool,Bool)) rowVecReqOut;
//    interface configurePorts = vec(colReader.configure,
//                                   predEval.configure);
   
//    method Action start();
//       colReader.start;
//    endmethod

// endmodule
