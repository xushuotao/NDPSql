import ISSPTypes::*;
import NDPCommon::*;
import Pipe::*;
import FIFOF::*;
import GetPut::*;
import ClientServer::*;
import ClientServerHelper::*;
import FlashCtrlIfc::*;
import RowMask::*;
import FIFO::*;
import ControllerTypes::*;
import Vector::*;
import ColReader::*;
import DualFlashPageBuffer::*;

Bool debug = False;

typedef struct{
   Bit#(64) firstRow;
   Bit#(64) lastRow;
   Bool last;
   } RowBatchRequest deriving (Bits, Eq, FShow);

interface FirstColReader;
   // interactions with flash and rowMasks
   // interface Client#(DualFlashAddr, Bit#(256)) flashRdClient;
   interface PipeIn#(Tuple2#(Bit#(64), Bool)) pageInPipe;
   interface PageBufferClient#(PageBufSz) pageBufClient;
      
   interface Client#(Bit#(9), void) reserveRowVecs;
   
   interface PipeOut#(RowVecReq) rowVecReqOut;

   // outPipe to next Accel
   interface NDPStreamOut streamOut;
   
   // set up parameter
   interface NDPConfigure configure;
   
   // method Action start();
endinterface


(* synthesize *)
module mkFirstColReader(FirstColReader);
   let colReader <- mkColReader();
   
   Reg#(Bit#(64)) totalRowVecs <- mkRegU;
   Reg#(Bool) busy <- mkReg(False);
   Reg#(Bit#(64)) rowVecCnt <- mkRegU;
   
   Reg#(Bit#(9)) rowVecsPerPage <- mkRegU;
   
   FIFO#(Bit#(9)) reserveRowVecQ <- mkFIFO;
   FIFO#(void) reserveRespQ <- mkFIFO;
   
   FIFO#(RowVecReq) rowVecReqQ <- mkSizedFIFO(5);
   
   FIFO#(RowVecReq) rowVecReqOutQ <- mkFIFO;
   
   Reg#(Bool) forward <- mkRegU;
   
   rule genRowVecReq if ( busy );
      Bit#(9) rowVecIncr = forward? 1: rowVecsPerPage;
      
      rowVecCnt <= rowVecCnt + zeroExtend(rowVecIncr);
      
      Bool last = False;
      if ( rowVecCnt +  zeroExtend(rowVecIncr) >= totalRowVecs) begin
         busy <= False;
         last = True;
      end
      
      let rowVecsToReserve = min(zeroExtend(rowVecIncr), totalRowVecs - rowVecCnt);
      
      if (debug) $display("(%m) rowVecsPerPage = %d, totalRowVecs = %d, rowVecCnt = %d, last = %d", rowVecsPerPage, totalRowVecs, rowVecCnt, last);
      
      rowVecReqQ.enq(RowVecReq{numRowVecs: rowVecsToReserve,
                               maskZero: False,
                               last: last});
      
      reserveRowVecQ.enq(truncate(rowVecsToReserve));
   endrule
   
   rule issuRowVecReq;
      reserveRespQ.deq;
      let v <- toGet(rowVecReqQ).get;
      colReader.rowVecReqIn.enq(v);
   endrule
   
   // interface Client flashRdClient = colReader.flashRdClient;
   interface pageInPipe = colReader.pageInPipe;
   interface pageBufClient = colReader.pageBufClient;
   interface Client reserveRowVecs = toClient(reserveRowVecQ, reserveRespQ);
   interface PipeOut rowVecReqOut = colReader.rowVecReqOut;
   interface NDPStreamOut streamOut = colReader.streamOut;
   interface NDPConfigure configure;
      method Action setColBytes(Bit#(5) colBytes) if (!busy);
         $display("(%m) setColBytes %d ", colBytes);
         colReader.configure.setColBytes(colBytes);
         rowVecsPerPage <= toRowVecsPerPage(colBytes);
      endmethod
      method Action setParameters(ParamT params) if (!busy);
         $display("(%m) setParameters ", fshow(params));
         colReader.configure.setParameters(params);
         Bit#(64) numRows = truncate(params[0]);
         rowVecCnt <= 0;
         totalRowVecs <= (numRows + 31) >> 5;
         forward <= unpack(params[2][2]);
         busy <= True;
      endmethod

   endinterface
endmodule
