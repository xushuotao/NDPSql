import NDPCommon::*;
import Pipe::*;
import ClientServer::*;
import ClientServerHelper::*;
import ColReadEng::*;
import FlashCtrlIfc::*;
import PageBuffer::*;
import FIFO::*;
import Vector::*;
import GetPut::*;
import ControllerTypes::*;
import SpecialFIFOs::*;
import FIFOF::*;

typedef 8 MaxNumCol;

typedef Bit#(TLog#(MaxNumCol)) ColIdT;
typedef Bit#(TLog#(TAdd#(MaxNumCol,1))) ColNumT;

typedef 128 NumPageBufs;
typedef Bit#(TLog#(NumPageBufs)) BufIdT;

interface ColProcReader;
   interface PipeIn#(RowVecReq) rowVecReq;
   //interface Client#(RowMaskRead, RowVectorMask) rowMaskReadClient;
 
   interface PipeOut#(RowData) outPipe;

   // For now we assume that the col file sits on continuous pages;
   interface PipeIn#(Tuple4#(ColIdT, ColType, Bit#(64), Bool)) colInfoPort;

   interface Client#(DualFlashAddr, Bit#(256)) flashRdClient;
   
   method Action setRowNums(Bit#(64) numRows, ColNumT numCols);
   
endinterface

typedef enum{SetRow, SetCol, Normalize, Ready} State deriving (FShow, Bits, Eq);

(* synthesize *)
module mkColReadEng128(ColReadEng#(BufIdT));
   ColReadEng#(BufIdT) m <- mkColReadEng;
   return m;
endmodule

(* synthesize *)
module mkColProcReader(ColProcReader);
   
   Reg#(State) state <- mkReg(SetRow);
   
   Reg#(Bit#(64)) rowCnt <- mkReg(0);
   Reg#(Bit#(64)) rowsPerIter <- mkRegU;
   
   Reg#(Bit#(64)) rowNum <- mkReg(0);
   
   Reg#(ColIdT) colCnt <- mkReg(0);
   Reg#(ColNumT) colNum <- mkRegU;
   
   Reg#(Bit#(4)) minLgColBeatsPerIter <- mkReg(maxBound);
   Vector#(MaxNumCol, Reg#(Bit#(6))) colBeatsPerIter_V <- replicateM(mkRegU);

   Vector#(MaxNumCol, ColReadEng#(BufIdT)) colReadEng_V <- replicateM(mkColReadEng128);
   
   PageBuffer#(NumPageBufs) pageBuffer <- mkUGPageBuffer;
   
   Reg#(Bit#(5)) pageReqCnt <- mkReg(0);
   
   FIFO#(Tuple2#(ColIdT, BufIdT)) colScheduleQ <- mkFIFO;
   
   FIFO#(DualFlashAddr) flashReqQ <- mkFIFO;
   FIFO#(Bit#(256)) flashRespQ <- mkFIFO;
   
   // tagId, busId
   // RegFile#(Bit#(7), Bit#(4)) tagInfo <- mkRegFileFull;
   // assumes that page request returns in order
   FIFO#(BufIdT) outstandingReadQ <- mkSizedFIFO(valueOf(NumPageBufs));
   
   rule schedulePageReq if ( state == Ready );
      let tag <- pageBuffer.reserveBuf;
      let {addr, last} <- colReadEng_V[colCnt].getNextPageAddr(tag);
      
      $display("issue flash page request for col = %d, tag = %d, addr = ", colCnt, tag, fshow(addr));
      flashReqQ.enq(addr);
      outstandingReadQ.enq(tag);

      // colScheduleQ.enq(tuple2(truncate(colCnt), tag));

      // scheduling logic
      // make sure that same amount of row vecs are issued per iteration
      if ( zeroExtend(pageReqCnt) + 1 == colBeatsPerIter_V[colCnt] || last ) begin
         pageReqCnt <= 0;
         if ( zeroExtend(colCnt) + 1 < colNum ) begin
            colCnt <= colCnt + 1;
         end
         else begin
            colCnt <= 0;

            if ( rowCnt + rowsPerIter >= rowNum ) begin
               state <= SetRow;
               rowCnt <= 0;
               minLgColBeatsPerIter <= maxBound;
            end
            else begin
               rowCnt <= rowCnt + rowsPerIter;
            end
         end
      end
      else begin
         pageReqCnt <= pageReqCnt + 1;
      end

   endrule
   /*
   rule issuePageReq;
      colScheduleQ.deq;
      let {col, tag} = colScheduleQ.first;
      let addr <- colReadEng_V[col].pageAddrResp;
   endrule
    */

   // // maxbeat > 256
   // Vector#(16, Reg#(Bit#(9))) flashBeatCnts <- replicateM(mkReg(0));
   Reg#(Bit#(9)) flashBeatCnt <- mkReg(0);
   rule enqFlashResp;
      // assumes that flash return is continous
      let d <- toGet(flashRespQ).get;
      let tag = outstandingReadQ.first;
      
      if ( flashBeatCnt == fromInteger((pageWords/2) - 1)) begin
         outstandingReadQ.deq;
         flashBeatCnt <= 0;
      end
      else begin
         flashBeatCnt <= flashBeatCnt + 1;
      end
      // filter out unwanted data;
      if ( flashBeatCnt < fromInteger(8192/32) )
         pageBuffer.enqRequest(d, tag);
   endrule
   
   Reg#(ColIdT) colId <- mkReg(0);
   Vector#(MaxNumCol, Reg#(Bit#(6))) beatsPerRowVec_V <- replicateM(mkReg(0));
   
   Reg#(Bit#(6)) beatCnt <- mkReg(0);
   
   // maxbeat = 256
   Vector#(MaxNumCol, Reg#(Bit#(8))) colBeatCnts <- replicateM(mkReg(0));
   
   FIFO#(Tuple3#(Bit#(7), Bool, Bool)) flashRespMetaQ <- mkPipelineFIFO;
   
   rule deqFlashResp;
      let {tag, maxBeats} = colReadEng_V[colId].firstInflightTag;
      
      colBeatCnts[colId] <= colBeatCnts[colId] + 1;
            
      if ( beatCnt + 1 == beatsPerRowVec_V[colId] ) begin
         beatCnt <= 0;         
         if ( zeroExtend(colId) + 1 == colNum ) begin
            colId <= 0;
         end
         else begin
            colId <= colId + 1;
         end
      end
      else begin
         beatCnt <= beatCnt + 1;
      end
      
      pageBuffer.deqRequest(tag);
      
      Bool needDeqTag = (colBeatCnts[colId] == maxBound);
      flashRespMetaQ.enq(tuple3(tag, needDeqTag, zeroExtend(beatCnt) < maxBeats));
      if ( needDeqTag ) colReadEng_V[colId].doneFirstInflight;
      $display("%m sending pageBuffer deqRequest tag = %d, colBeatsCnts[%d] = %b", tag, colId, colBeatCnts[colId]);
   endrule
   
   FIFOF#(Bit#(256)) dataOutQ <- mkFIFOF;
   rule flashRespData;
      let {tag, needDeq, needEnq} <- toGet(flashRespMetaQ).get;
      let d <- pageBuffer.deqResponse;
      if ( needEnq)
         dataOutQ.enq(d);
      
      if ( needDeq ) 
         pageBuffer.doneBuffer(tag);
   endrule
   
   rule doNormalize ( state == Normalize );
      function Bit#(6) normalize(Bit#(6) colBeatsPerIter);
         return colBeatsPerIter >> minLgColBeatsPerIter;
      endfunction

      writeVReg(colBeatsPerIter_V, map(normalize, readVReg(colBeatsPerIter_V)));
      
      $display("%m doNormalize, minLgColBeatsPerIter = %d, colBeatsPerIter_V <= ", minLgColBeatsPerIter, fshow(map(normalize, readVReg(colBeatsPerIter_V))));
      rowsPerIter <= 8192 >> minLgColBeatsPerIter;
      state <= Ready;
   endrule
   
   
   // TODO:: 
   interface PipeIn rowVecReq = ?;
   //interface Client#(RowMaskRead, RowVectorMask) rowMaskReadClient;

   interface PipeOut outPipe = toPipeOut(dataOutQ);

   interface PipeIn colInfoPort;
      method Action enq(Tuple4#(ColIdT, ColType, Bit#(64), Bool) v) if ( state == SetCol );
         let {colIdT, colType, baseAddr, isLast } = v;
         $display("%m colInfo set:: colIdT = %d, baseAddr = %d, isLast = %d, colType = ", colIdT, baseAddr, isLast, fshow(colType));
         colBeatsPerIter_V[colIdT] <= toBeatsPerRowVec(colType);
         minLgColBeatsPerIter <= min(toLgBeatsPerRowVec(colType), minLgColBeatsPerIter);
         beatsPerRowVec_V[colIdT] <= toBeatsPerRowVec(colType);
         colReadEng_V[colIdT].setParam(rowNum, colType, baseAddr);
         if ( isLast ) state <= Normalize;
      endmethod
      method Bool notFull;
         return state == SetCol;
      endmethod
   endinterface

   interface Client flashRdClient = toClient(flashReqQ, flashRespQ);
   
   method Action setRowNums(Bit#(64) numRows, ColNumT numCols) if (state == SetRow);
      $display("%m setRowNums:: numRows = %d, numCols = %d", numRows, numCols);
      rowNum <= numRows;
      colNum <= numCols;
      state <= SetCol;
   endmethod   
endmodule
