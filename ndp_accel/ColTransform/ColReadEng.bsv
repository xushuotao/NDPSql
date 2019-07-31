import NDPCommon::*;
import FIFO::*;
import SpecialFIFOs::*;
import FlashCtrlIfc::*;

interface ColReadEng#(type tagT);
   method ActionValue#(Tuple2#(DualFlashAddr, Bool)) getNextPageAddr(tagT tag, Bool needRead);
   method Tuple2#(tagT, Bit#(9)) firstInflightTag;
   method Action doneFirstInflight;
   
   method Action setParam(Bit#(64) numRows, ColType colType, Bit#(64) basePage);
   
   // TODO: interface for dma
endinterface

// (* synthesize *)
module mkColReadEng(ColReadEng#(tagT)) provisos (Bits#(tagT, tagTsz));
   FIFO#(Tuple3#(DualFlashAddr, Bit#(9), Bool)) addrQ <- mkFIFO;
   
   FIFO#(Tuple2#(tagT, Bit#(9))) inflightTagQ <- mkSizedFIFO(valueOf(TExp#(tagTsz)));
   
   FIFO#(DualFlashAddr) respQ <- mkPipelineFIFO;
   
   FIFO#(Tuple3#(Bit#(64), Bit#(64), Bit#(8))) colMetaQ <- mkFIFO;
   
   Reg#(Bit#(64)) pageCnt <- mkReg(0);
   
   rule genPageId;
      Bit#(9) usefulBeats = 256;
      Bool last = False;
      let {numPages, basePage, lastPageBeats} = colMetaQ.first;
      if ( pageCnt + 1 == numPages ) begin
         colMetaQ.deq;
         pageCnt <= 0;
         last = True;
         if (lastPageBeats != 0) 
            usefulBeats = zeroExtend(lastPageBeats);
      end
      else begin
         pageCnt <= pageCnt + 1;
      end
      $display("(%m) genPageId, pageCnt = %d, numPages = %d, usefulBeats = %d", pageCnt, numPages, usefulBeats);
      addrQ.enq(tuple3(toDualFlashAddr(basePage + pageCnt), usefulBeats, last));
   endrule
   
   method ActionValue#(Tuple2#(DualFlashAddr, Bool)) getNextPageAddr(tagT tag, Bool needRead);
      let {addr, beats, last} = addrQ.first;
      addrQ.deq;
      // $display("(%m) queuedepth = %d", valueOf(TExp#(tagTsz)));
      if ( needRead )
         inflightTagQ.enq(tuple2(tag, beats));
      // respQ.enq(addr);
      return tuple2(addr, last);
   endmethod
   
   method Tuple2#(tagT, Bit#(9)) firstInflightTag = inflightTagQ.first;
   method Action doneFirstInflight = inflightTagQ.deq;
   
   method Action setParam(Bit#(64) numRows, ColType colType, Bit#(64) basePage);
      $display("%m setParam, numRows = %d, basePage = %d, colType = ", numRows, basePage, fshow(colType));
      $display("%m setParam, numPages = %d, basePage = %d, numRowVecs = %d, lastPageBeats = ", toNumPages(numRows, colType), basePage, toNumRowVecs(numRows), lastPageBeats(numRows, colType));
      colMetaQ.enq(tuple3(toNumPages(numRows, colType), basePage, lastPageBeats(numRows, colType)));
   endmethod
endmodule
   
