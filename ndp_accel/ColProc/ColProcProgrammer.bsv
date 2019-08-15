import NDPCommon::*;
import Pipe::*;
import FIFOF::*;
import Vector::*;
import BuildVector::*;

import ColProcReader::*;
import ColXForm::*;
import ColProc::*;
import Connectable::*;


typedef struct{
   ColType colType;
   Bit#(64) baseAddr;
   } InColParamT deriving (Bits, Eq, FShow);


typedef struct{
   ColType colType;
   NDPDest dest;
   Bool isSigned;
   } OutColParamT deriving (Bits, Eq, FShow);


interface InColProgrammer;
   method Action setDim(Bit#(64) numRows, ColNumT numCols);
   interface PipeIn#(Tuple2#(ColIdT, InColParamT)) programPort;
   // interface ProgramInColClient programClient;
endinterface

interface ColXFormProgrammer#(numeric type engs);
   method Action setProgramLength(Bit#(TLog#(engs)) colId, Bit#(4) progLength);
   interface PipeIn#( Bit#(32)) programPort;
endinterface

interface OutColProgrammer;
   method Action setColNum(ColNumT numCols);
   interface PipeIn#(Tuple2#(ColIdT, OutColParamT)) programPort;
   // interface ProgramOutColClient programClient;
endinterface

module mkInColProgrammer#(ProgramColProcReader programIfc)(InColProgrammer);
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
  
   method Action setDim(Bit#(64) numRows, ColNumT numCols) if ( doSetDims);
      programIfc.setDims(numRows, numCols);
      colNum <= numCols;
      doSetDims <= False;
   endmethod
   
   interface PipeIn programPort = toPipeIn(programQ);
endmodule

module mkInColAutoProgram#(Bit#(64) numRows, Vector#(numCols, InColParamT) colInfo, ProgramColProcReader programIfc)(Empty);
   let programmer <- mkInColProgrammer(programIfc);
   Reg#(Bool) doDim <- mkReg(True);
   rule doSetDim if (doDim);
      programmer.setDim(numRows, fromInteger(valueOf(numCols)));
      doDim <= False;
   endrule
   Reg#(ColNumT) colCnt <- mkReg(0);
   rule doProgram if ( colCnt < fromInteger(valueOf(numCols)) );
      programmer.programPort.enq(tuple2(truncate(colCnt), colInfo[colCnt]));
      colCnt <= colCnt + 1;
   endrule
endmodule
      

module mkColXFormProgrammer#(ProgramColXForm#(engs) programIfc)(ColXFormProgrammer#(engs));
   Integer numEngs = valueOf(engs);
   Reg#(Bit#(TLog#(TAdd#(engs,1)))) engCnt_Length <- mkReg(0);
   Vector#(engs, Reg#(Bit#(4))) progLengths <- replicateM(mkRegU);
   
   FIFOF#(Bit#(32)) programQ <- mkFIFOF;
   Reg#(Bit#(3)) pc <- mkReg(0);
   Reg#(Bit#(TLog#(engs))) engCnt <- mkReg(0);
   rule programEngs if ( engCnt_Length == fromInteger(numEngs));
      let inst = programQ.first;
      programQ.deq;
      programIfc.enq(tuple2(engCnt, tuple3(pc, False, inst)));
      
      if ( zeroExtend(pc) + 1 == progLengths[engCnt] ) begin
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
   
   method Action setProgramLength(Bit#(TLog#(engs)) engId, Bit#(4) progLength) if ( engCnt_Length < fromInteger(numEngs) );
      engCnt_Length <=  engCnt_Length + 1;
      progLengths[engId] <= progLength;
      programIfc.enq(tuple2(engId, tuple3(?, True, zeroExtend(progLength))));
   endmethod
   
   interface PipeIn programPort = toPipeIn(programQ);
endmodule

module mkColXFormAutoProgram#(Vector#(engs, Bit#(4)) progLength,
                              Vector#(engs, Vector#(8, Bit#(32))) insts,
                              ProgramColXForm#(engs) programIfc)(Empty);
   
   let programmer <- mkColXFormProgrammer(programIfc);
   Reg#(Bit#(TLog#(engs))) engCnt <- mkReg(0);
   Reg#(Bool) programLength <- mkReg(True);
   rule doProgramLength if ( programLength);
      if ( engCnt == fromInteger(valueOf(engs) -1 )) begin
         engCnt <= 0;
         programLength <= False;
      end
      else begin
         engCnt <= engCnt + 1;
      end
      programmer.setProgramLength(engCnt, progLength[engCnt]);
   endrule
   
   Reg#(Bit#(TLog#(TAdd#(engs,1)))) engCnt2 <- mkReg(0);
   Reg#(Bit#(3)) pc <- mkReg(0);
   
   rule doPrograms if ( engCnt2 < fromInteger(valueOf(engs)));
      if ( zeroExtend(pc) + 1 == progLength[engCnt2] ) begin
         pc <= 0;
         engCnt2 <= engCnt2 + 1;
      end
      else begin
         pc <= pc + 1;
      end
      programmer.programPort.enq(insts[engCnt2][pc]);
   endrule
endmodule



module mkOutColProgrammer#(ProgramOutputCol programIfc)(OutColProgrammer);
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
      $display("(%m) outColProgrammer programCols = ", fshow(programQ.first));
      programIfc.colInfoPort.enq(tuple4(colId, param.colType, param.dest, colCnt + 1 == colNum));
      ndpParamQ.enq(tuple3(colId, vec({?,pack(param.isSigned)},?,?,?), colCnt + 1 == colNum));
   endrule
  
   method Action setColNum(ColNumT numCols) if ( doSetDims);
      colNum <= numCols;
      doSetDims <= False;
      programIfc.setColNum(numCols);
   endmethod
   
   
   interface PipeIn programPort = toPipeIn(programQ);   
endmodule

module mkOutColAutoProgram#(Vector#(numCols, OutColParamT) colInfo, ProgramOutputCol programIfc)(Empty);
   let programmer <- mkOutColProgrammer(programIfc);
   Reg#(Bool) doDim <- mkReg(True);
   rule doColNums if (doDim);
      programmer.setColNum(fromInteger(valueOf(numCols)));
      doDim <= False;
   endrule
   Reg#(ColNumT) colCnt <- mkReg(0);
   rule doProgram if ( colCnt < fromInteger(valueOf(numCols)) );
      programmer.programPort.enq(tuple2(truncate(colCnt), colInfo[colCnt]));
      colCnt <= colCnt + 1;
   endrule
endmodule

