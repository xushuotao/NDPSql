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
import Assert::*;

typedef 8 MaxNumCol;

typedef Bit#(TLog#(MaxNumCol)) ColIdT;
typedef Bit#(TLog#(TAdd#(MaxNumCol,1))) ColNumT;

typedef 32 NumPageBufs;
typedef Bit#(TLog#(NumPageBufs)) BufIdT;

interface ProgramColProcReader;
   // step 1
   method Action setRowNums(Bit#(64) numRows, ColNumT numCols);
   // step 2
   //TODO:: For now we assume that the col file sits on continuous pages;
   interface PipeIn#(Tuple4#(ColIdT, ColType, Bit#(64), Bool)) colInfoPort;
endinterface

interface ColProcReader;
   interface PipeIn#(RowVecReq) rowVecReq;
   //interface Client#(RowMaskRead, RowVectorMask) rowMaskReadClient;
   interface PipeOut#(Bit#(64)) rowVecOut;
   interface PipeOut#(RowData) outPipe;
   interface Client#(DualFlashAddr, Bit#(256)) flashRdClient;
   interface ProgramColProcReader programIfc;
endinterface

typedef enum{SetRow, SetCol, Normalize, Ready} State deriving (FShow, Bits, Eq);

(* synthesize *)
module mkColReadEng_synth(ColReadEng#(BufIdT));
   ColReadEng#(BufIdT) m <- mkColReadEng;
   return m;
endmodule

(* synthesize *)
module mkPageBuffer_synth(PageBuffer#(NumPageBufs));
   let m <- mkUGPageBuffer;
   return m;
endmodule


(* synthesize *)
module mkColProcReader(ColProcReader);
   
   Reg#(State) state <- mkReg(SetRow);
   
   Reg#(Bit#(64)) rowCnt <- mkReg(0);
   Reg#(Bit#(64)) rowsPerIter <- mkRegU;
   // max rowVecPerIter = 256 lg.. = 8
   Reg#(Bit#(4)) lgRowVecsPerIter <- mkRegU;
   
   Reg#(Bit#(64)) rowNum <- mkReg(0);
   
   Reg#(ColIdT) colCnt <- mkReg(0);
   Reg#(ColNumT) colNum <- mkRegU;
   
   Reg#(Bit#(4)) minLgColBeatsPerIter <- mkReg(maxBound);
   Vector#(MaxNumCol, Reg#(Bit#(6))) colBeatsPerIter_V <- replicateM(mkRegU);

   Vector#(MaxNumCol, ColReadEng#(BufIdT)) colReadEng_V <- replicateM(mkColReadEng_synth);
   
   let pageBuffer <- mkPageBuffer_synth;
   
   Reg#(Bit#(5)) pageReqCnt <- mkReg(0);
   
   FIFO#(DualFlashAddr) flashReqQ <- mkFIFO;
   FIFO#(Bit#(256)) flashRespQ <- mkFIFO;
   
   // tagId, busId
   // RegFile#(Bit#(7), Bit#(4)) tagInfo <- mkRegFileFull;
   // assumes that page request returns in order
   
   FIFOF#(RowVecReq) rowVecReqQ <- mkFIFOF;
   
   Reg#(Bool) hasData <- mkReg(False);
   
   FIFO#(Bool) pageBatchQ <- mkFIFO;
   
   function Bit#(64) toIterId(Bit#(64) rowVecCnt);
      return rowVecCnt >> lgRowVecsPerIter;
   endfunction
   
   Reg#(Bit#(64)) rowVecCnt <- mkReg(0);
   rule collectRowReq if ( state == Ready);
      let req = rowVecReqQ.first;
      rowVecReqQ.deq;
      dynamicAssert(req.numRowVecs == 1, "numRowVecs needs to be one");
      rowVecCnt <= rowVecCnt + 1;
      $display("%m, rowVecCnt = %d, rowVecReq = ", rowVecCnt, fshow(req));
      if ( (toIterId(rowVecCnt) != toIterId(rowVecCnt + 1)) || req.last ) begin
         hasData <= False;
         $display("%m, issue pageBatch = %d", hasData || !req.maskZero);
         pageBatchQ.enq(hasData || !req.maskZero);
      end
      else begin
         hasData <= hasData || !req.maskZero ; 
      end
   endrule
   
   
   FIFO#(BufIdT) outstandingReadQ <- mkSizedFIFO(valueOf(NumPageBufs));
   
   Reg#(Bit#(6)) max_colBeatsPerIter <- mkRegU;
   
   Vector#(MaxNumCol, Reg#(Bool)) colDones <- replicateM(mkRegU);
   
   rule schedulePageReq if ( state == Ready );
      if ( zeroExtend(pageReqCnt) < colBeatsPerIter_V[colCnt] && !colDones[colCnt] ) begin
         let needRead = pageBatchQ.first;
         let tag = ?;
      
         if ( needRead ) begin
            tag <- pageBuffer.reserveBuf;
         end

         let {addr, last} <- colReadEng_V[colCnt].getNextPageAddr(tag, needRead);      
         colDones[colCnt] <= last;
      
         if (needRead) begin
            $display("issue flash page request for col = %d, tag = %d, addr = ", colCnt, tag, fshow(addr));
            flashReqQ.enq(addr);
            outstandingReadQ.enq(tag);
         end
      end
      else begin
         $display("skipping flash page request this time, colCnt = %d, pageReqCnt = %d", colCnt, pageReqCnt);
      end
      $display("schedulePageReq colCnt = %d, pageReqCnt = %d, rowCnt = %d, rowsPerIter = %d, rowNum = %d", colCnt, pageReqCnt, rowCnt, rowsPerIter, rowNum);
      
      // scheduling logic
      // make sure that same amount of row vecs are issued per iteration
      if ( zeroExtend(colCnt) + 1 == colNum ) begin
         colCnt <= 0;
         if ( zeroExtend(pageReqCnt) + 1 == max_colBeatsPerIter ) begin
            pageReqCnt <= 0;
            pageBatchQ.deq;
            
            if ( rowCnt + rowsPerIter >= rowNum ) begin
               state <= SetRow;
               rowCnt <= 0;
               max_colBeatsPerIter <= 0;
               minLgColBeatsPerIter <= maxBound;
            end
            else begin
               rowCnt <= rowCnt + rowsPerIter;
            end

         end
         else begin
            pageReqCnt <= pageReqCnt + 1;
         end
      end
      else begin
         colCnt <= colCnt + 1;
      end

   endrule

   // maxbeat > 256
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
      if ( flashBeatCnt < fromInteger(8192/32) ) begin
         $display("(@%t) pageBuffer flashBeatCnt = %d, tag = %d", $time, flashBeatCnt, tag);
         pageBuffer.enqRequest(d, tag);
      end
   endrule
   
   Reg#(ColIdT) colId <- mkReg(0);
   Vector#(MaxNumCol, Reg#(Bit#(6))) beatsPerRowVec_V <- replicateM(mkReg(0));
   
   Reg#(Bit#(6)) beatCnt <- mkReg(0);
   
   // maxbeat = 256
   Vector#(MaxNumCol, Reg#(Bit#(8))) colBeatCnts <- replicateM(mkReg(0));
   
   FIFO#(Tuple4#(BufIdT, Bool, Bool, Maybe#(Bit#(64)))) flashRespMetaQ <- mkSizedFIFO(3);
   
   Reg#(Bit#(9)) rowVecCnt_fRsp <- mkReg(0);
   
   rule deqFlashResp;
      let {tag, maxBeats, baseRowVecId} = colReadEng_V[colId].firstInflightTag;
      
      colBeatCnts[colId] <= colBeatCnts[colId] + 1;
      

            
      if ( beatCnt + 1 == beatsPerRowVec_V[colId] ) begin
         beatCnt <= 0;         
         if ( zeroExtend(colBeatCnts[colId]) < maxBeats || colBeatCnts[colId] == maxBound ) begin
            if ( zeroExtend(colId) + 1 == colNum ) begin
               colId <= 0;
            end
            else begin
               colId <= colId + 1;
            end
         end
      end
      else begin
         beatCnt <= beatCnt + 1;
      end

      Bit#(64) rowVecId = baseRowVecId + zeroExtend(rowVecCnt_fRsp);
      Maybe#(Bit#(64)) maybeRowVec = tagged Invalid;

      if ( colId == 0 && beatCnt == 0) begin
         maybeRowVec = tagged Valid rowVecId;
         if (colBeatCnts[0] == maxBound ) begin
            rowVecCnt_fRsp <= 0;
         end
         else begin
            rowVecCnt_fRsp <= rowVecCnt_fRsp + 1;
         end
      end

      
      pageBuffer.deqRequest(tag);
      
      Bool needDeqTag = (colBeatCnts[colId] == maxBound);
      flashRespMetaQ.enq(tuple4(tag, needDeqTag, zeroExtend(colBeatCnts[colId]) < maxBeats, maybeRowVec));
      if ( needDeqTag ) colReadEng_V[colId].doneFirstInflight;
      $display("%m sending pageBuffer deqRequest tag = %d, colBeatsCnts[%d] = %b, maxBeats = %d, needDeqTag = %d, maybeRowVec = ", tag, colId, colBeatCnts[colId], maxBeats, needDeqTag, fshow(maybeRowVec));
   endrule
   
   FIFOF#(Bit#(64)) rowVecOutQ <- mkFIFOF;
   FIFOF#(Bit#(256)) dataOutQ <- mkFIFOF;
   rule flashRespData;
      let {tag, needDeq, needEnq, maybeRowVec} <- toGet(flashRespMetaQ).get;
      let d <- pageBuffer.deqResponse;
      if ( needEnq)
         dataOutQ.enq(d);
      
      if ( needEnq &&& maybeRowVec matches tagged Valid .rowVec) begin
         rowVecOutQ.enq(rowVec);
      end
      
      if ( needDeq ) 
         pageBuffer.doneBuffer(tag);
   endrule
   
   rule doNormalize ( state == Normalize );
      function Bit#(6) normalize(Bit#(6) colBeatsPerIter);
         return colBeatsPerIter >> minLgColBeatsPerIter;
      endfunction

      writeVReg(colBeatsPerIter_V, map(normalize, readVReg(colBeatsPerIter_V)));

      $display("%m doNormalize, minLgColBeatsPerIter = %d, max_colBeatsPerIter = %d, colBeatsPerIter_V <= ", minLgColBeatsPerIter, max_colBeatsPerIter >> minLgColBeatsPerIter,  fshow(map(normalize, readVReg(colBeatsPerIter_V))));
      max_colBeatsPerIter <= max_colBeatsPerIter >> minLgColBeatsPerIter;
      rowsPerIter <= 8192 >> minLgColBeatsPerIter;
      lgRowVecsPerIter <= (8 >> minLgColBeatsPerIter);
      
      state <= Ready;
   endrule
   
 
   interface PipeIn rowVecReq = toPipeIn(rowVecReqQ);
   interface PipeOut rowVecOut = toPipeOut(rowVecOutQ);
   interface PipeOut outPipe = toPipeOut(dataOutQ);
   interface Client flashRdClient = toClient(flashReqQ, flashRespQ);

   interface ProgramColProcReader programIfc;
      method Action setRowNums(Bit#(64) numRows, ColNumT numCols) if (state == SetRow);
         $display("%m setRowNums:: numRows = %d, numCols = %d", numRows, numCols);
         rowNum <= numRows;
         colNum <= numCols;
         state <= SetCol;
      endmethod   
      interface PipeIn colInfoPort;
         method Action enq(Tuple4#(ColIdT, ColType, Bit#(64), Bool) v) if ( state == SetCol );
            let {colIdT, colType, baseAddr, isLast } = v;
            $display("%m colInfo set:: colIdT = %d, baseAddr = %d, isLast = %d, colType = ", colIdT, baseAddr, isLast, fshow(colType));
            colBeatsPerIter_V[colIdT] <= toBeatsPerRowVec(colType);
            minLgColBeatsPerIter <= min(toLgBeatsPerRowVec(colType), minLgColBeatsPerIter);
            max_colBeatsPerIter <= max(toBeatsPerRowVec(colType), max_colBeatsPerIter);
            beatsPerRowVec_V[colIdT] <= toBeatsPerRowVec(colType);
            colReadEng_V[colIdT].setParam(rowNum, colType, baseAddr);
            writeVReg(colDones, replicate(False));
            if ( isLast ) state <= Normalize;
         endmethod
         method Bool notFull;
            return state == SetCol;
         endmethod
      endinterface
   endinterface
endmodule
