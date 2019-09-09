import ISSPTypes::*;
import NDPCommon::*;
import FIFO::*;
import FIFOF::*;
import Pipe::*;
import SpecialFIFOs::*;
import FlashCtrlIfc::*;
import GetPut::*;

Bool debug = True;

interface ColReadEng#(type tagT);

   interface PipeIn#(Tuple2#(Bit#(64), Bool)) pageInPipe;

   method ActionValue#(Tuple2#(DualFlashAddr, Bool)) getNextPageAddr(Bool needRead);//(tagT tag, Bool needRead);
   method Action enqBufResp(tagT tag);
   method Tuple4#(tagT, Bit#(9), Bit#(64), Bool) firstInflightTag;
   method Action doneFirstInflight;
   
   method Action setParam(Bit#(64) numRows, ColType colType, Bit#(64) basePage);
   
   // TODO: interface for dma
endinterface

// (* synthesize *)
module mkColReadEng(ColReadEng#(tagT)) provisos( Bits#(tagT, tagSz) );
   FIFO#(Tuple4#(DualFlashAddr, Bit#(9), Bool, Bit#(64))) addrQ <- mkFIFO;
   
   FIFO#(Tuple3#(Bit#(9), Bit#(64), Bool)) outstandingReqQ <- mkSizedFIFO(3);
   
   FIFO#(Tuple4#(tagT, Bit#(9), Bit#(64), Bool)) inflightTagQ <- mkSizedFIFO(1+valueOf(TExp#(tagSz)));
   
   FIFO#(DualFlashAddr) respQ <- mkPipelineFIFO;
   
   FIFO#(Tuple4#(Bit#(64), Bit#(64), Bit#(8), Bit#(9))) colMetaQ <- mkFIFO;
   
   Reg#(Bit#(64)) pageCnt <- mkReg(0);
   
   Reg#(Bit#(64)) rowVecCnt <- mkReg(0);
   
   FIFOF#(Tuple2#(Bit#(64), Bool)) pageInQ <- mkSizedFIFOF(128);

`ifndef HOST   
   rule genPageId;
      Bit#(9) usefulBeats = 256;
      Bool last = False;
      let {numPages, basePage, lastPageBeats, rowVecsPerPage} = colMetaQ.first;
      if ( pageCnt + 1 == numPages ) begin
         colMetaQ.deq;
         pageCnt <= 0;
         rowVecCnt <= 0;
         last = True;
         if (lastPageBeats != 0) 
            usefulBeats = zeroExtend(lastPageBeats);
      end
      else begin
         rowVecCnt <= rowVecCnt + zeroExtend(rowVecsPerPage);
         pageCnt <= pageCnt + 1;
      end
      if (debug) $display("(%m) genPageId, pageCnt = %d, numPages = %d, usefulBeats = %d, rowVecCnt = %d, rowVecsPerPage = %d", pageCnt, numPages, usefulBeats, rowVecCnt, rowVecsPerPage);
      addrQ.enq(tuple4(toDualFlashAddr(basePage + pageCnt), usefulBeats, last, rowVecCnt));
   endrule
`else
   rule genPageId;
      let {numPages, basePage, lastPageBeats, rowVecsPerPage} = colMetaQ.first;
      Bit#(9) usefulBeats = 256;
      Bool last = False;
      let {addr, hostlast} <- toGet(pageInQ).get();
      
      if ( pageCnt + 1 == numPages ) begin
         colMetaQ.deq;
         pageCnt <= 0;
         rowVecCnt <= 0;
         last = True;
         if (lastPageBeats != 0) 
            usefulBeats = zeroExtend(lastPageBeats);
      end
      else begin
         rowVecCnt <= rowVecCnt + zeroExtend(rowVecsPerPage);
         pageCnt <= pageCnt + 1;
      end
      if (debug) $display("(%m) genPageId, pageCnt = %d, numPages = %d, usefulBeats = %d, rowVecsPerPage = %d, last = %d, addr = %d hostlast = %d", pageCnt, numPages, usefulBeats, rowVecsPerPage, last, addr, hostlast);
      if (debug) $display("(%m) flashaddr = ", fshow(toDualFlashAddr(addr)));
      addrQ.enq(tuple4(toDualFlashAddr(addr), usefulBeats, last, rowVecCnt));
   endrule
   
   interface PipeIn pageInPipe = toPipeIn(pageInQ);
`endif
   
   method ActionValue#(Tuple2#(DualFlashAddr, Bool)) getNextPageAddr(Bool needRead);
      let {addr, beats, last, baseRowVec} = addrQ.first;
      addrQ.deq;
      // $display("(%m) queuedepth = %d", valueOf(TExp#(tagTsz)));
      if ( needRead )
         outstandingReqQ.enq(tuple3(beats, baseRowVec, last));
      // respQ.enq(addr);
      return tuple2(addr, last);
   endmethod
   
   method Action enqBufResp(tagT tag);
      let {beats, baseRowVec, last} <- toGet(outstandingReqQ).get;
      if (debug) $display("(%m) (@%t) enqBufResp tag = %d, beats = %d, baseRowVec = %d, last = %d", $time, tag, beats, baseRowVec, last);
      inflightTagQ.enq(tuple4(tag, beats, baseRowVec, last));
   endmethod
   
   method Tuple4#(tagT, Bit#(9), Bit#(64), Bool) firstInflightTag = inflightTagQ.first;
   method Action doneFirstInflight = inflightTagQ.deq;
   
   method Action setParam(Bit#(64) numRows, ColType colType, Bit#(64) basePage);
      $display("%m setParam, numRows = %d, basePage = %d, colType = ", numRows, basePage, fshow(colType));
      $display("%m setParam, numPages = %d, basePage = %d, numRowVecs = %d, lastPageBeats = ", toNumPages(numRows, colType), basePage, toNumRowVecs(numRows), lastPageBeats(numRows, colType));
      colMetaQ.enq(tuple4(toNumPages(numRows, colType), basePage, lastPageBeats(numRows, colType), toRowVecsPerPage2(colType)));
   endmethod
endmodule
   
