import ISSPTypes::*;
import NDPCommon::*;
import Pipe::*;
import FIFOF::*;
import Vector::*;
import BuildVector::*;

import ColProcReader::*;
import ColXForm::*;
import ColProc::*;
import Connectable::*;

module mkInColProgramIfc#(ProgramColProcReader programIfc)(InColProgramIfc);
   FIFOF#(Tuple2#(ColIdT, InColParamT)) programQ <- mkFIFOF;
   
   Reg#(Bool) doSetDims <- mkReg(True);
   
   Reg#(ColNumT) colCnt <- mkReg(0);
   Reg#(ColNumT) colNum <- mkRegU;
   
   rule programCols if (!doSetDims);
      let { colId, param } = programQ.first;
      programQ.deq;
      if ( colCnt + 1 == colNum) begin
         doSetDims <= True;
         colCnt <= 0;
      end
      else begin
         colCnt <= colCnt + 1;
      end
      programIfc.colInfoPort.enq(tuple4(colId, param.colType, param.baseAddr, colCnt + 1 == colNum));
   endrule
  
   method Action setDim(Bit#(64) numRows, Bit#(8) numCols) if ( doSetDims);
      $display("(%m) setDim numRows = %d, numCols = %d", numRows, numCols);
      programIfc.setDims(numRows, truncate(numCols));
      colNum <= truncate(numCols);
      doSetDims <= False;
   endmethod
   
   method Action setParam(Bit#(8) colId, InColParamT param);
      $display("(%m) setParam colId = %d, param = ", colId, fshow(param));
      programQ.enq(tuple2(truncate(colId), param));
   endmethod
endmodule

module mkInColAutoProgram#(Bit#(64) numRows, Vector#(numCols, InColParamT) colInfo, ProgramColProcReader programIfc)(Empty);
   let programmer <- mkInColProgramIfc(programIfc);
   Reg#(Bool) doDim <- mkReg(True);
   rule doSetDim if (doDim);

      programmer.setDim(numRows, fromInteger(valueOf(numCols)));
      doDim <= False;
   endrule
   Reg#(Bit#(8)) colCnt <- mkReg(0);
   rule doProgram if ( colCnt < fromInteger(valueOf(numCols)) );
      programmer.setParam(colCnt, colInfo[colCnt]);
      colCnt <= colCnt + 1;
   endrule
endmodule
      

module mkColXFormProgramIfc#(ProgramColXForm#(engs) programIfc)(ColXFormProgramIfc) provisos(
    Add#(a__, TLog#(engs), 8));
   Integer numEngs = valueOf(engs);
   Reg#(Bit#(TLog#(TAdd#(engs,1)))) engCnt_Length <- mkReg(0);
   Vector#(engs, Reg#(Bit#(8))) progLengths <- replicateM(mkRegU);
   
   FIFOF#(Bit#(32)) programQ <- mkFIFOF;
   Reg#(Bit#(8)) pc <- mkReg(0);
   Reg#(Bit#(TLog#(engs))) engCnt <- mkReg(0);
   rule programEngs if ( engCnt_Length == fromInteger(numEngs));
      let inst = programQ.first;
      programQ.deq;
      programIfc.enq(tuple2(engCnt, tuple3(truncate(pc), False, inst)));
      
      if ( pc + 1 == progLengths[engCnt] ) begin
         pc <= 0;
         if (engCnt == fromInteger(numEngs - 1) ) begin
            engCnt_Length <= 0;
            engCnt <= 0;
         end
         else begin
            engCnt <= engCnt + 1;
         end
      end
      else begin
         pc <= pc + 1;
      end
   endrule
   
   method Action setProgramLength(Bit#(8) engId, Bit#(8) progLength) if ( engCnt_Length < fromInteger(numEngs) );
      $display("(%m) setProgramLength endId = %d, progLength = %d",  engId, progLength);
      engCnt_Length <=  engCnt_Length + 1;
      progLengths[engId] <= progLength;
      programIfc.enq(tuple2(truncate(engId), tuple3(?, True, zeroExtend(progLength))));
   endmethod
   
   method Action setInstruction(Bit#(32) inst);
      DecodeInst decodeInst = unpack(inst);
      $display("(%m) setInstruction = ",  fshow(decodeInst));
      programQ.enq(inst);
   endmethod
endmodule

module mkColXFormAutoProgram#(Vector#(engs, Bit#(w)) progLength,
                              Vector#(engs, Vector#(8, Bit#(32))) insts,
                              ProgramColXForm#(engs) programIfc)(Empty) provisos(Add#(a__, w, 8), Add#(b__, TLog#(engs), 8));
   
   let programmer <- mkColXFormProgramIfc(programIfc);
   Reg#(Bit#(8)) engCnt <- mkReg(0);
   Reg#(Bool) programLength <- mkReg(True);
   rule doProgramLength if ( programLength);
      if ( engCnt == fromInteger(valueOf(engs) -1 )) begin
         engCnt <= 0;
         programLength <= False;
      end
      else begin
         engCnt <= engCnt + 1;
      end
      programmer.setProgramLength(engCnt, zeroExtend(progLength[engCnt]));
   endrule
   
   Reg#(Bit#(TLog#(TAdd#(engs,1)))) engCnt2 <- mkReg(0);
   Reg#(Bit#(8)) pc <- mkReg(0);
   
   rule doPrograms if ( engCnt2 < fromInteger(valueOf(engs)));
      if ( pc + 1 == zeroExtend(progLength[engCnt2]) ) begin
         pc <= 0;
         engCnt2 <= engCnt2 + 1;
      end
      else begin
         pc <= pc + 1;
      end
      programmer.setInstruction(insts[engCnt2][pc]);
   endrule
endmodule



module mkOutColProgramIfc#(ProgramOutputCol programIfc)(OutColProgramIfc);
   FIFOF#(Tuple2#(ColIdT, OutColParamT)) programQ <- mkFIFOF;
   
   Reg#(Bool) doSetDims <- mkReg(True);
   
   Reg#(ColNumT) colCnt <- mkReg(0);
   Reg#(ColNumT) colNum <- mkRegU;
   
   FIFOF#(Tuple3#(ColIdT, ParamT, Bool)) ndpParamQ <- mkSizedFIFOF(valueOf(MaxNumCol));
   
   mkConnection(toPipeOut(ndpParamQ), programIfc.colNDPParamPort);
   
   rule programSetColInfo if (!doSetDims);
      let { colId, param } = programQ.first;
      programQ.deq;
      if ( colCnt + 1 == colNum) begin
         doSetDims <= True;
         colCnt <= 0;
      end
      else begin
         colCnt <= colCnt + 1;
      end
      $display("(%m) outColProgramIfc colId = %d, programCols = ", colId, fshow(programQ.first));      
      programIfc.colInfoPort.enq(tuple4(colId, param.colType, param.dest, colCnt + 1 == colNum));
      ndpParamQ.enq(tuple3(colId, vec({?,pack(param.isSigned)},?,?,?), colCnt + 1 == colNum));
   endrule
  
   method Action setColNum(Bit#(8) numCols) if ( doSetDims);
      colNum <= truncate(numCols);
      doSetDims <= False;
      programIfc.setColNum(truncate(numCols));
   endmethod
   
   method Action setParam(Bit#(8) colId, OutColParamT param);
      programQ.enq(tuple2(truncate(colId), param));
   endmethod
endmodule

module mkOutColAutoProgram#(Vector#(numCols, OutColParamT) colInfo, ProgramOutputCol programIfc)(Empty);
   let programmer <- mkOutColProgramIfc(programIfc);
   Reg#(Bool) doDim <- mkReg(True);
   rule doColNums if (doDim);
      programmer.setColNum(fromInteger(valueOf(numCols)));
      doDim <= False;
   endrule
   Reg#(Bit#(8)) colCnt <- mkReg(0);
   rule doProgram if ( colCnt < fromInteger(valueOf(numCols)) );
      programmer.setParam(colCnt, colInfo[colCnt]);
      colCnt <= colCnt + 1;
   endrule
endmodule

