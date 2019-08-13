import ColProcReader::*;
import ColProc::*;
import NDPCommon::*;
import Pipe::*;
import FIFOF::*;
import Vector::*;
import BuildVector::*;

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

interface ColXFormProgrammer;
   method Action maxProgramCnt(Bit#(TLog#(ColXFormEngs)) colId, Bit#(4) progLength);
   interface PipeIn#( Bit#(32)) programPort;
endinterface

interface ProgramOutCol;
   method Action setColNums(ColNumT numCols);
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
      
/*
module mkColXFormProgrammer#(ProgramColXForm#(ColXFormEngs) programIfc)(ColXFormProgrammer);
   Integer numEngs = valueOf(ColXFormEngs);
   Reg#(Bit#(TLog#(ColXFormEngs))) maxProgramCnt <- mkReg(0);
   Vector#(ColXFormEngs, Reg#(Bit#(4))) progLengths <- replicateM(mkRegU);
   Vector#(ColXFormEngs, Reg#(Bit#(4))) progCnt <- replicateM(mkReg(0));
   
   FIFOF#(Tuple2#(Bit#(TLog#(ColXFormEngs)), Tuple2#(Bit#(3), Bit#(32)))) programQ <- mkFIFOF;
   Reg#(Bit#(3)) pc <- mkReg(0);
   Reg#(Bit#(TLog#(ColXFormEngs))) engCnt <- mkReg(0);
   rule programEngs if ( maxProgramCnt == fromInteger(numEngs));
      let inst = programQ.first;
      programIfc.enq(tuple2(engCnt, tuple3(pc, False, inst)));
      
      if ( zeroExtend(pc) + 1 == progCnt[engId] ) begin
         pc <= 0;
         if ( engCnt == fromInteger(numEngs - 1) begin
            maxProgramCnt <= 0;
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
   
   method Action maxProgramCnt(Bit#(TLog#(ColXFormEngs)) engId, Bit#(4) progLength) if ( maxProgramCnt < fromInteger(numEngs) );
      maxProgramCnt <=  maxProgramCnt + 1;
      progLengths[engId] <= progLength;
      programIfc.enq(tuple2(engId, tuple3(?, True, zeroExtend(programLength))));
   endmethod
   
   interface PipeIn programPort = toPipeIn(programQ);
endmodule

module mkOutColProgrammer#(ProgramColOutputCol programIfc)(OutColProgrammer);
   FIFOF#(Tuple2#(ColIdT, OutColParamT)) programQ <- mkFIFOF;
   
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
      programIfc.colInfoPort.enq(tuple4(colId, param.colType, param.ndpDest, colCnt + 1 == colNum)));
      programIfc.colNDPParamPort.enq(tuple3(colId, vec({?,pack(param.isSigned)},?,?,?), colCnt + 1 == colNum));
   endrule
  
   method Action setColNums(ColNumT numCols) if ( doSetDims);
      colNum <= numCols;
      doSetDims <= False;
   endmethod
   
   interface PipeIn programPort = toPipeIn(programQ);   
endmodule
*/
