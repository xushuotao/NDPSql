import Pipe::*;
import FIFOF::*;
import Vector::*;
import BuildVector::*;
import NDPCommon::*;
import RowSelector::*;

typedef struct{
   ColType colType;
   Bit#(64) numRows;
   Bit#(64) baseAddr;
   Bool forward;
   Bool allRows;
   Bit#(1) rdPort;
   Bit#(64) lowTh;
   Bit#(64) hiTh;
   Bool isSigned;
   Bool andNotOr; 
   } RowSelectorParamT deriving (Bits, Eq, FShow);

// ColType, numRows, baseAddr, {forward,allRows,maskRdport}, lowTh, hiTh, isSigned, andNotOr,
interface RowSelectorProgrammer;
   method Action setParam(Bit#(8) colId, RowSelectorParamT param);
endinterface


module mkRowSelectorProgrammer#(ProgramRowSelector#(TMul#(numCols,2)) programIfc)(RowSelectorProgrammer) provisos(
   Add#(TLog#(numCols), a__, TLog#(TMul#(numCols, 2))),
   Add#(a__, TLog#(numCols), TLog#(TAdd#(numCols, 1))),
   Add#(b__, TLog#(numCols), 8));
   
   FIFOF#(Tuple2#(Bit#(TLog#(numCols)), RowSelectorParamT)) programFifo <- mkFIFOF;
   
   FIFOF#(Tuple2#(Bit#(TLog#(TMul#(numCols,2))), Bit#(5))) colBytesQ <- mkFIFOF;
   FIFOF#(Tuple2#(Bit#(TLog#(TMul#(numCols,2))), ParamT)) paramQ <- mkFIFOF;
   
   Reg#(Bool) doColReader <- mkReg(True);
   Reg#(Bool) doSetBytes <- mkReg(True);
   
   rule doProgramColReader if ( doColReader );
      let {colId, param} = programFifo.first;
      Bit#(TLog#(TMul#(numCols, 2))) ndpId = {colId,0};
      if ( doSetBytes) begin
         programIfc.setColBytesPort.enq(tuple2(ndpId, toColBytes(param.colType)));
      end
      else begin
         programIfc.setParamPort.enq(tuple2(ndpId, vec({?, param.numRows},
                                                       {?, param.baseAddr}, 
                                                       {?, pack(param.forward), pack(param.allRows), param.rdPort},
                                                       ?)));

         doColReader <= False;
      end
      doSetBytes <= !doSetBytes;
   endrule
   
   rule doProgramFilter if ( !doColReader );
      let {colId, param} = programFifo.first;
      Bit#(TLog#(TMul#(numCols, 2))) ndpId = {colId,1};
      if ( doSetBytes) begin
         programIfc.setColBytesPort.enq(tuple2(ndpId, toColBytes(param.colType)));
      end
      else begin
         programIfc.setParamPort.enq(tuple2(ndpId, vec({?, param.lowTh},
                                                       {?, param.hiTh}, 
                                                       {?, pack(param.isSigned)},
                                                       {?, pack(param.andNotOr)})));
         doColReader <= True;
         programFifo.deq;
      end
      doSetBytes <= !doSetBytes;
   endrule

   method Action setParam(Bit#(8) colId, RowSelectorParamT param);
      programFifo.enq(tuple2(truncate(colId), param));
   endmethod
endmodule
   
module mkRowSelectAutoProgram#(Vector#(numCols, RowSelectorParamT) programInfo, ProgramRowSelector#(TMul#(numCols,2)) programIfc)(Empty) provisos(
   Add#(TLog#(numCols), a__, TLog#(TMul#(numCols, 2))),
   Add#(a__, TLog#(numCols), TLog#(TAdd#(numCols, 1))),
   Add#(b__, TLog#(numCols), 8));
   
   RowSelectorProgrammer programmer <- mkRowSelectorProgrammer(programIfc);
   
   Reg#(Bit#(8)) colCnt <- mkReg(0);
   rule doProgram if ( colCnt < fromInteger(valueOf(numCols)));
      programmer.setParam(colCnt, programInfo[colCnt]);
      colCnt <= colCnt + 1;
   endrule
endmodule

// Vector#(NDPCount_RowSel, ParamT) params = vec(vec(zeroExtend(totalRows), zeroExtend(getBaseAddr("l_shipdate")), zeroExtend(010), ?),
//                                               vec(int_min, 729999, 1, 1),
//                                               vec(zeroExtend(totalRows), 0, zeroExtend(3'b100), ?),
//                                               ?,
//                                               vec(zeroExtend(totalRows), 0, zeroExtend(3'b100), ?),
//                                               ?,
//                                               vec(zeroExtend(totalRows), 0, zeroExtend(3'b100), ?),
//                                               ?);