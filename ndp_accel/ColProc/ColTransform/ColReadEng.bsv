import NDPCommon::*;
import FIFO::*;
import SpecialFIFOs::*;
import FlashCtrlIfc::*;

interface ColReadEng#(type tagT);
   method ActionValue#(Tuple2#(DualFlashAddr, Bool)) getNextPageAddr(tagT tag, Bool needRead);
   method Tuple4#(tagT, Bit#(9), Bit#(64), Bool) firstInflightTag;
   method Action doneFirstInflight;
   
   method Action setParam(Bit#(64) numRows, ColType colType, Bit#(64) basePage);
   
   // TODO: interface for dma
endinterface

// (* synthesize *)
module mkColReadEng(ColReadEng#(tagT)) provisos (Bits#(tagT, tagTsz));
   FIFO#(Tuple4#(DualFlashAddr, Bit#(9), Bool, Bit#(64))) addrQ <- mkFIFO;
   
   FIFO#(Tuple4#(tagT, Bit#(9), Bit#(64), Bool)) inflightTagQ <- mkSizedFIFO(valueOf(TExp#(tagTsz)));
   
   FIFO#(DualFlashAddr) respQ <- mkPipelineFIFO;
   
   FIFO#(Tuple4#(Bit#(64), Bit#(64), Bit#(8), Bit#(9))) colMetaQ <- mkFIFO;
   
   Reg#(Bit#(64)) pageCnt <- mkReg(0);
   
   Reg#(Bit#(64)) rowVecCnt <- mkReg(0);
   
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
      $display("(%m) genPageId, pageCnt = %d, numPages = %d, usefulBeats = %d, rowVecsPerPage", pageCnt, numPages, usefulBeats, rowVecsPerPage);
      addrQ.enq(tuple4(toDualFlashAddr(basePage + pageCnt), usefulBeats, last, rowVecCnt));
   endrule
   
   method ActionValue#(Tuple2#(DualFlashAddr, Bool)) getNextPageAddr(tagT tag, Bool needRead);
      let {addr, beats, last, baseRowVec} = addrQ.first;
      addrQ.deq;
      // $display("(%m) queuedepth = %d", valueOf(TExp#(tagTsz)));
      if ( needRead )
         inflightTagQ.enq(tuple4(tag, beats, baseRowVec, last));
      // respQ.enq(addr);
      return tuple2(addr, last);
   endmethod
   
   method Tuple4#(tagT, Bit#(9), Bit#(64), Bool) firstInflightTag = inflightTagQ.first;
   method Action doneFirstInflight = inflightTagQ.deq;
   
   method Action setParam(Bit#(64) numRows, ColType colType, Bit#(64) basePage);
      $display("%m setParam, numRows = %d, basePage = %d, colType = ", numRows, basePage, fshow(colType));
      $display("%m setParam, numPages = %d, basePage = %d, numRowVecs = %d, lastPageBeats = ", toNumPages(numRows, colType), basePage, toNumRowVecs(numRows), lastPageBeats(numRows, colType));
      colMetaQ.enq(tuple4(toNumPages(numRows, colType), basePage, lastPageBeats(numRows, colType), toRowVecsPerPage2(colType)));
   endmethod
endmodule
   
