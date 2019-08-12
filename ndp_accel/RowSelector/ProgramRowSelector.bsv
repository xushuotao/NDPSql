import Pipe::*;
import FIFOF::*;
import Vector::*;
import BuildVector::*;
import NDPCommon::*;

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


interface ProgramRowSelectorClient#(numeric type num);
   interface PipeOut#(Tuple2#(Bit#(TLog#(TMul#(num,2))), Bit#(5))) setColBytesPort;
   interface PipeOut#(Tuple2#(Bit#(TLog#(TMul#(num,2))), ParamT)) setParamPort;
endinterface


// ColType, numRows, baseAddr, {forward,allRows,maskRdport}, lowTh, hiTh, isSigned, andNotOr,
interface ProgramRowSelector#(numeric type numCols);
   interface PipeIn#(Tuple2#(Bit#(TLog#(numCols)), RowSelectorParamT)) programPort; 
   interface ProgramRowSelectorClient#(numCols) programClient;
endinterface


module mkProgramRowSelector(ProgramRowSelector#(numCols)) provisos(
   Add#(TLog#(numCols), a__, TLog#(TMul#(numCols, 2))),
   Add#(a__, TLog#(numCols), TLog#(TAdd#(numCols, 1))));
   
   FIFOF#(Tuple2#(Bit#(TLog#(numCols)), RowSelectorParamT)) programFifo <- mkFIFOF;
   
   FIFOF#(Tuple2#(Bit#(TLog#(TMul#(numCols,2))), Bit#(5))) colBytesQ <- mkFIFOF;
   FIFOF#(Tuple2#(Bit#(TLog#(TMul#(numCols,2))), ParamT)) paramQ <- mkFIFOF;
   
   Reg#(Bool) doColReader <- mkReg(True);
   Reg#(Bool) doSetBytes <- mkReg(True);
   
   rule doProgramColReader if ( doColReader );
      let {colId, param} = programFifo.first;
      Bit#(TLog#(TMul#(numCols, 2))) ndpId = {colId,0};
      if ( doSetBytes) begin
         colBytesQ.enq(tuple2(ndpId, toColBytes(param.colType)));
      end
      else begin
         paramQ.enq(tuple2(ndpId, vec({?, param.numRows},
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
         colBytesQ.enq(tuple2(ndpId, toColBytes(param.colType)));
      end
      else begin
         paramQ.enq(tuple2(ndpId, vec({?, param.lowTh},
                                      {?, param.hiTh}, 
                                      {?, pack(param.isSigned)},
                                      {?, pack(param.andNotOr)})));
         doColReader <= True;
         programFifo.deq;
      end
      doSetBytes <= !doSetBytes;
   endrule


   interface PipeIn programPort = toPipeIn(programFifo); 
      
   interface ProgramRowSelectorClient programClient;
      interface setColBytesPort = toPipeOut(colBytesQ);
      interface setParamPort = toPipeOut(paramQ);
   endinterface
   
endmodule
   

module mkRowSelectAutoProgram#(Vector#(numCols, RowSelectorParamT) programInfo)(ProgramRowSelectorClient#(numCols)) provisos(
   Add#(TLog#(numCols), a__, TLog#(TMul#(numCols, 2))),
   Add#(a__, TLog#(numCols), TLog#(TAdd#(numCols, 1))));
   
   ProgramRowSelector#(numCols) programmer <- mkProgramRowSelector;
   
   Reg#(Bit#(TLog#(TAdd#(numCols,1)))) colCnt <- mkReg(0);
   rule doProgram if ( colCnt < fromInteger(valueOf(numCols)));
      programmer.programPort.enq(tuple2(truncate(colCnt), programInfo[colCnt]));
      colCnt <= colCnt + 1;
   endrule
   
   interface setColBytesPort = programmer.programClient.setColBytesPort;
   interface setParamPort = programmer.programClient.setParamPort;
endmodule

// Vector#(NDPCount_RowSel, ParamT) params = vec(vec(zeroExtend(totalRows), zeroExtend(getBaseAddr("l_shipdate")), zeroExtend(010), ?),
//                                               vec(int_min, 729999, 1, 1),
//                                               vec(zeroExtend(totalRows), 0, zeroExtend(3'b100), ?),
//                                               ?,
//                                               vec(zeroExtend(totalRows), 0, zeroExtend(3'b100), ?),
//                                               ?,
//                                               vec(zeroExtend(totalRows), 0, zeroExtend(3'b100), ?),
//                                               ?);
