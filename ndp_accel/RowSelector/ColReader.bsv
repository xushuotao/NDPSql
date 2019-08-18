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
import Assert::*;

import FlashPageReader::*;
import DualFlashPageBuffer::*;

// typedef struct{
//    Bit#(64) pageId;
//    // Bit#(64) baseRowVecId;
//    // Bool isLast;
//    } FlashRespMetaT deriving (Bits, Eq, FShow);

Bool debug = True;

typedef struct{
   Bool isNop;
   Bool isLast;
   Maybe#(Bit#(1)) maskRdPort;
   Bit#(64) rowVecId;
   Bit#(32) maskGen;
   } MaskRdMeta deriving (Bits, Eq, FShow);

typedef enum {Idle, SetParam, Forward, AllRows, PartialRows} ColReaderState deriving (Bits, Eq, FShow);

interface ColReader;
   // interactions with flash and rowMasks
   // interface Client#(DualFlashAddr, Bit#(256)) flashRdClient;
   interface PageBufferClient#(PageBufSz) pageBufClient;
   
   interface Client#(RowMaskRead, RowVectorMask) maskRdClient;   
      
   interface PipeIn#(RowVecReq) rowVecReqIn;
   // bypass rowVec
   interface PipeOut#(RowVecReq) rowVecReqOut;
   
   // outPipe to next Accel
   interface NDPStreamOut streamOut;
   
   // // set up parameter
   interface NDPConfigure configure;
   // method Action configure(Bit#(5) colBytes, Bit#(64) numRows, Bit#(64) baseAddr, Bit#(1) maskRdPort, Bool allRows, Bool byPass);
endinterface



(* synthesize *)
module mkColReader(ColReader);
   
   Reg#(ColReaderState) state <- mkReg(Idle);
   
   Reg#(Bit#(64)) totalRowVecs <- mkRegU;
   
   Reg#(Bit#(64)) rowVecCnt <- mkReg(0);
   
   FIFOF#(RowVecReq) rowVecReqQ <- mkFIFOF;
   FIFOF#(RowVecReq) bypassRowVecReqQ <- mkFIFOF;
   
   Reg#(Bit#(9)) rowVecsPerPage <- mkRegU;
   
   Reg#(Bit#(64)) basePage <- mkRegU;
   Reg#(Bit#(64)) pageReqCnt <- mkReg(0);
   
   // FIFO#(FlashRespMetaT) flashRespMetaQ <- mkSizedFIFO(128); // this size could be over-provisioned
   FIFO#(Tuple2#(Bit#(64), Bool)) flashRespMetaQ <- mkSizedFIFO(valueOf(PageBufSz)); // this size could be over-provisioned
   
   // 1 2 4 8 16
   // 0 1 2 3 4
   Reg#(Bit#(5)) colBytes <- mkRegU;
   Reg#(Bit#(3)) lgColBytes <- mkRegU; 
   
   Reg#(Bit#(1)) maskRdPortId <- mkRegU;
   
   function Bit#(64) rowVecToPageId(Bit#(64) rowVecId);
      return case (lgColBytes)
                0: (rowVecId >> 8); // 1 byte:  rowVedId/256
                1: (rowVecId >> 7); // 2 byte:  rowVedId/128
                2: (rowVecId >> 6); // 4 byte:  rowVedId/64
                3: (rowVecId >> 5); // 8 byte:  rowVedId/32
                4: (rowVecId >> 4); // 16 byte: rowVedId/16
             endcase;
   endfunction
   
   function Bit#(64) pageIdToRowVec(Bit#(64) pageId);
      return case (lgColBytes)
                0: (pageId << 8); // 1 byte:  pageId*256
                1: (pageId << 7); // 2 byte:  pageId*128
                2: (pageId << 6); // 4 byte:  pageId*64
                3: (pageId << 5); // 8 byte:  pageId*32
                4: (pageId << 4); // 16 byte: pageId*16
             endcase;
   endfunction
   
////////////////////////////////////////////////////////////////////////////////
/// When this ColReader is an NOP, all it does is forwarding RowVec requests to
/// the next guy.
////////////////////////////////////////////////////////////////////////////////
   rule doBypass if ( state == Forward );
      let req <- toGet(rowVecReqQ).get();
      if (debug) $display("%m, doBypass forwarding, reqCnt = %d, numRowVecs = %d, totalRowVecs = %d, req = ", rowVecCnt, req.numRowVecs, totalRowVecs, fshow(req));
      if (req.last ) begin
         dynamicAssert(rowVecCnt + req.numRowVecs == totalRowVecs, "(%m) (Forward) totalRows should be the same");
         state <= Idle;
         rowVecCnt <= 0;
      end
      else begin
         rowVecCnt <= rowVecCnt + req.numRowVecs;
      end

      bypassRowVecReqQ.enq(req);
   endrule

////////////////////////////////////////////////////////////////////////////////
/// When this ColReader requires read all the rows of the column, for cases like
/// the first colreader or there is an OR operation with the previous predicate
/// result.
/// When in AllRows mode, you don't read from Mask Array but generates rowVec
/// masks which are all ones.
////////////////////////////////////////////////////////////////////////////////
   Reg#(Maybe#(Bit#(64))) lastPageId <- mkReg(tagged Invalid);
   Reg#(Bit#(64)) endPageId <- mkRegU;
   Reg#(Bit#(64)) rowVec_reqCnt <- mkReg(0);
   
   FIFO#(void) releaseflashReq <- mkFIFO;
   
   Reg#(Bit#(64)) lastRowVecId <- mkReg(0);
   
   FIFO#(Bit#(64)) pageReqQ <- mkFIFO();
   
   Reg#(Bool) allRowVecsFinished <- mkRegU();
   
   Reg#(Bool) needRead <- mkReg(False);
      
   // FIFO#(DualFlashAddr) addrQ <- mkFIFO;
   // FIFO#(Bit#(256)) flashRespQ <- mkFIFO;
   
   let flashReader <- mkFlashPageReaderIO;

   
   rule doAllRows_flashReq if ( state == AllRows || state == PartialRows);
      let req = rowVecReqQ.first();
      
      // maximum step should
      Bit#(64) rowVecIncr = min(req.numRowVecs-rowVec_reqCnt, zeroExtend(rowVecsPerPage));
      
      // make suring that we are increase rowVecs page by page
      // so that we don't miss a page request;
      
      Bool isLast = False;

      if ( rowVec_reqCnt + zeroExtend(rowVecsPerPage) >= req.numRowVecs ) begin
         rowVec_reqCnt <= 0;
         rowVecCnt <= rowVecCnt + req.numRowVecs;
         rowVecReqQ.deq;
         
         if ( req.last ) begin
            isLast = True;
            dynamicAssert(rowVecCnt + req.numRowVecs == totalRowVecs, "(%m) (Nonforward) totalRows should equal");
            allRowVecsFinished <= True;
            // state <= Idle;
         end
      end
      else begin
         rowVec_reqCnt <= rowVec_reqCnt + rowVecIncr;
      end
      

      let nextPageId = rowVecToPageId(rowVecCnt + rowVec_reqCnt + rowVecIncr);
      
      // lastRowVecId <= rowVecCnt + rowVec_reqCnt + rowVecIncr;
      
      let currPageId = rowVecToPageId(rowVecCnt + rowVec_reqCnt);
      

      
      
      Bool needRead_next = needRead || (state == AllRows || !req.maskZero);
      if (debug) $display("(%m):gen flash req rowVecCnt = %d, rowVec_reqCnt = %d, req.numRowVecs = %d, totalRowVecs = %d, req.last = %d", rowVecCnt, rowVec_reqCnt, req.numRowVecs, totalRowVecs, req.last);
      if (debug) $display("(%m): currPageId = %d, nextPageId = %d, needRead = %d, needRead_next = %d, isLast = %d", currPageId, nextPageId, needRead, needRead_next, isLast);
      

      // on last RowVec of a page;
      if ( currPageId != nextPageId || isLast) begin
         dynamicAssert( nextPageId - currPageId == 1 || isLast, "pageReq only increase by one, or it is last");
         if ( needRead_next ) begin
            pageReqQ.enq(currPageId);
            // addrQ.enq(toDualFlashAddr(currPageId+basePageReg));
         end
         flashRespMetaQ.enq(tuple2(rowVec_reqCnt, needRead_next));
         
         needRead <= False;
      end
      else begin
         needRead <= needRead_next;
      end
      

      // lastPageId <= tagged Valid currPageId;

      // // issue flashRead request only when there is page change
      // if ( lastPageId !=  tagged Valid currPageId ) begin      
      //    Bool cond = isValid(lastPageId) && (fromMaybe(?, lastPageId) + 1 == currPageId);
      //    dynamicAssert( cond || currPageId == 0, "pageReq only increase by one");
      //    Bool doRead = False;
      //    if ( state == AllRows ) begin
      //       pageReqQ.enq(currPageId);
      //       doRead = True;
      //    end
      //    else if ( !req.maskZero ) begin
      //       pageReqQ.enq(currPageId);
      //       doRead = True;
      //    end
      //    flashRespMetaQ.enq(doRead);
      // end
   endrule
   
   // issue page request only if when all the rowvec in the page has been seen;
   Reg#(Bit#(64)) totalPageIssued <- mkReg(0);
   rule issuePageReq;// if ( pageReqQ.first() < rowVecToPageId(lastRowVecId) || allRowVecsFinished);
      let pageId <- toGet(pageReqQ).get;
      if (debug) $display("(%m): issuing page Read Request for basePageAddr = %d, pageId = %d, lastRowVecId = %d, totalPageIssued = %d", basePage, pageId, lastRowVecId, totalPageIssued);
      // addrQ.enq(toDualFlashAddr(pageId+basePage));
      flashReader.readServer.request.put(toDualFlashAddr(pageId+basePage));
      totalPageIssued <= totalPageIssued + 1;
   endrule

////////////////////////////////////////////////////////////////////////////////
/// Handles flash read responses for all cases
////////////////////////////////////////////////////////////////////////////////
   // Reg#(Bit#(TLog#(TDiv#(PageWords, 2)))) pageBeatCnt <- mkReg(0);
   Reg#(Bit#(8)) pageBeatCnt <- mkReg(0);
   Reg#(Bit#(8)) lastBeat <- mkRegU;
   Reg#(Bit#(9)) rowVecCnt_resp <- mkReg(0);
   Reg#(Bit#(32)) lastMask <- mkRegU;
   Reg#(Bit#(64)) pageCnt_resp <- mkReg(0);
   
   
   // size of 8 allows a maximum 8 read contentions from all colreaders
   FIFO#(RowMaskRead) maskRdReqQ <- mkSizedFIFO(8);
   FIFO#(MaskRdMeta) rowMaskMetaQ <- mkSizedFIFO(8);
   // row vector mask read response from the rowMask buffer
   FIFO#(RowVectorMask) rowMaskRespQ <- mkFIFO;
   
   // size of 17 because maximum 16 beats per rowVec
   FIFOF#(Bit#(256)) rowDataQ <- mkSizedFIFOF(17);
   
   
   rule doFlashResp if ( state != Idle );
      let {firstRowVecId, doRead} = flashRespMetaQ.first;
      // skip the flashRead
      let pageId = pageCnt_resp;
      Bool isLastPage = (pageId == endPageId);

      if ( !doRead ) begin
         flashRespMetaQ.deq();
         pageCnt_resp <= pageCnt_resp + 1;
         rowMaskMetaQ.enq(MaskRdMeta{isNop: True,
                                     maskRdPort: ?,
                                     rowVecId: firstRowVecId,
                                     maskGen: ?,
                                     isLast: isLastPage});

         if ( isLastPage ) state <= Idle;
      end
      else begin
         // let flashWord <- toGet(flashRespQ).get;
         let flashWord <- flashReader.readServer.response.get;
      
         let beatsPerRowVec = colBytes;
      
         let baseRowVecId = pageIdToRowVec(pageId);
         
         // if ( pageBeatCnt == fromInteger(pageWords/2-1) ) begin
         //    pageBeatCnt <= 0;
         //    flashRespMetaQ.deq();
         //    pageCnt_resp <= pageCnt_resp + 1;
         //    if ( isLastPage ) state <= Idle;
         // end
         // else begin
         //    pageBeatCnt <= pageBeatCnt + 1;
         // end
         pageBeatCnt <= pageBeatCnt + 1;
         
         if ( pageBeatCnt == maxBound ) begin
            pageCnt_resp <= pageCnt_resp + 1;
            flashRespMetaQ.deq();
            if ( isLastPage ) state <= Idle;
         end
      
         // if ( pageBeatCnt < fromInteger(8192/32) ) begin // useful 8k data
            // this part is needed for page misAlignment e.g. 3 pages of 4-byte col only generate 1 page of 1-byte col
         Bool validData = !isLastPage || (pageBeatCnt <= lastBeat);
         if (debug) $display("(%m) pageCnt_resp = %d, endPageId = %d, pageBeatCnt = %d, lastBeat = %d", pageCnt_resp, endPageId, pageBeatCnt, lastBeat);
            // on the last beat per rowVec, rowVec mask read request is issued or mask is generated
         if ( (({1'b0,pageBeatCnt}+1) & zeroExtend(beatsPerRowVec-1)) == 0 ) begin

            // increment rowVecCnt per Page
            // no need to reset to zero since it is of power of 2
            rowVecCnt_resp <= rowVecCnt_resp + 1;
            let rowVecId_page = rowVecCnt_resp & (rowVecsPerPage-1);

            Bool isLastBeat = isLastPage && pageBeatCnt == lastBeat;
               
            if (debug) $display("(%m) producing mask request or generating a mask, pageBeatCnt = %h, isLastBeat = %d, validData = %d", pageBeatCnt, isLastBeat, validData);
            let mask = isLastBeat ? lastMask : maxBound;

            Bit#(64) rowVecId = baseRowVecId + zeroExtend(rowVecId_page);
            if ( validData ) begin
               rowMaskMetaQ.enq(MaskRdMeta{isNop: False,
                                           maskRdPort: state == PartialRows ? tagged Valid maskRdPortId : tagged Invalid,
                                           rowVecId: rowVecId,
                                           maskGen: mask,
                                           isLast: isLastBeat});
               
               if ( state == PartialRows ) begin
                  maskRdReqQ.enq(RowMaskRead{id:truncate(rowVecId),
                                                src: maskRdPortId});
               end
            end
         end
         
         if (validData) rowDataQ.enq(flashWord);
         // end
      end
   endrule
   
   FIFOF#(RowMask) rowMaskQ <- mkFIFOF;
   
   rule produceMask;
      let meta <- toGet(rowMaskMetaQ).get();
      
      let mask = meta.maskGen;
      let rowVecId = meta.rowVecId;
      let isLast = meta.isLast;
      if (debug) $display("(%m) produceMask ", fshow(meta));
      if ( !meta.isNop ) begin
         if ( meta.maskRdPort matches tagged Valid .portId ) begin
            mask <- toGet(rowMaskRespQ).get();
         end
         rowMaskQ.enq(RowMask{rowVecId: rowVecId,
                              mask: mask,
                              isLast: isLast,
                              hasData: True});
      end
      else if ( meta.isLast ) begin
         rowMaskQ.enq(RowMask{rowVecId: rowVecId,
                              mask: mask,
                              isLast: True,
                              hasData: False});
      end
   endrule
   
   // interface Client flashRdClient = toClient(addrQ, flashRespQ);
   interface pageBufClient = flashReader.pageBufferClient;
   interface Client maskRdClient = toClient(maskRdReqQ, rowMaskRespQ);
   // interface Client maskRdClient = ?;//toClient(maskRdReqQ, rowMaskRespQ);
   
   interface PipeIn rowVecReqIn = toPipeIn(rowVecReqQ);
   interface PipeOut rowVecReqOut = toPipeOut(bypassRowVecReqQ);
   
   interface NDPStreamOut streamOut = toNDPStreamOut(rowDataQ, rowMaskQ);

   interface NDPConfigure configure;
      method Action setColBytes(Bit#(5) bytes) if (state == Idle);
         lgColBytes <= toLgColBytes(bytes);
         colBytes <= bytes;
         state <= SetParam;
      endmethod
      method Action setParameters(ParamT param) if (state == SetParam);
         Bit#(64) numRows = truncate(param[0]);
         Bit#(64) baseAddr = truncate(param[1]);
         Bit#(1) maskRdPort = param[2][0];
         Bool allRows = unpack(param[2][1]);
         Bool forward = unpack(param[2][2]);
   
         $display("(%m) setParameters numRows = %d, baseAddr = %d, maskRdPort = %d, allRows = %d, forward = %d", numRows, baseAddr, maskRdPort, allRows, forward);   
         allRowVecsFinished <= False;   
   
         rowVecCnt <= 0;
      
         Bit#(64) totalRowVecs_var = toNumRowVecs(numRows);//(numRows + 31) >> 5;
   
         totalRowVecs <= totalRowVecs_var;
   
         // 256 beats per Page
         lastBeat <= truncate(totalRowVecs_var<< lgColBytes)-1;//toLgColBytes(colBytes));
   
         rowVecsPerPage <= toRowVecsPerPage(colBytes);
   
         // basePage <= baseAddr;
         dynamicAssert(baseAddr%8192 == 0, "baseAddr should be page alighed!");
         basePage <= baseAddr>>13;
   
         pageReqCnt <= 0;
      
         endPageId <= toEndPageId(numRows-1, colBytes);
      
         Bit#(5) rowVRmd_last = truncate(numRows - 1);
   
      // Bit#(32)
         lastMask <= truncate((33'b10<<rowVRmd_last) - 1);
      
         if ( forward ) begin
            state <= Forward;
         end
         else if ( allRows ) begin
            state <= AllRows;
         end
         else begin
            state <= PartialRows;
         end
   
         maskRdPortId <= maskRdPort;
   
      endmethod
   endinterface

   // method Action configure(Bit#(5) colBytes, Bit#(64) numRows, Bit#(64) baseAddr, Bit#(1) maskRdPort, Bool allRows, Bool forward) if (state == Idle);
   //    allRowVecsFinished <= False;   
   //    // rowVecCnt <= 0;
      
   //    Bit#(64) totalRowVecs_var = (numRows + 31) >> 5;
   
   //    totalRowVecs <= totalRowVecs_var;
   
   //    // 256 beats per Page
   //    lastBeat <= truncate((totalRowVecs_var-1)<< toLgColBytes(colBytes));
   
   //    rowVecsPerPage <= toRowsVecPerPage(colBytes);
   
   //    basePage <= baseAddr;
   
   //    pageReqCnt <= 0;
      
   //    endPageId <= toEndPageId(numRows-1, colBytes);
      
   //    Bit#(5) rowVRmd_last = truncate(numRows - 1);
   
   //    // Bit#(32)
   //    lastMask <= truncate((33'b10<<rowVRmd_last) - 1);
      
   //    if ( forward ) begin
   //       state <= Bypass;
   //    end
   //    else if ( allRows ) begin
   //       state <= AllRows;
   //    end
   //    else begin
   //       state <= ParitalRows;
   //    end
   // endmethod
endmodule
