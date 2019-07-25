import NDPCommon::*;
import FIFO::*;
import SpecialFIFOs::*;
import FlashCtrlIfc::*;

interface ColReadEng;
   method Action getNextPageAddr(Bit#(7) tag);
   method ActionValue#(DualFlashAddr) pageAddrResp;
   
   method Bit#(7) firstInflightTag;
   method Action doneFirstInflight;
   
   method Action setParam(Bit#(64) numRows, ColType colType, Bit#(64) basePage);
   
   // TODO: interface for dma
endinterface

(* synthesize *)
module mkColReadEng(ColReadEng);
   FIFO#(DualFlashAddr) addrQ <- mkFIFO;
   
   FIFO#(Bit#(7)) inflightTagQ <- mkSizedFIFO(128);
   
   FIFO#(void) requestQ <- mkPipelineFIFO;
   
   FIFO#(Tuple2#(Bit#(64), Bit#(64))) colMetaQ <- mkFIFO;
   
   Reg#(Bit#(64)) pageCnt <- mkReg(0);
   
   rule genPageId;
      let {numPages, basePage} = colMetaQ.first;
      if ( pageCnt + 1 == numPages ) begin
         colMetaQ.deq;
         pageCnt <= 0;
      end
      else begin
         pageCnt <= pageCnt + 1;
      end
      addrQ.enq(toDualFlashAddr(basePage + pageCnt));
   endrule
   
   method Action getNextPageAddr(Bit#(7) tag);
      inflightTagQ.enq(tag);
      requestQ.enq(?);
   endmethod
   
   method ActionValue#(DualFlashAddr) pageAddrResp;
      requestQ.deq;
      addrQ.deq;
      return addrQ.first;
   endmethod
   
   method Bit#(7) firstInflightTag = inflightTagQ.first;
   method Action doneFirstInflight = inflightTagQ.deq;
   
   method Action setParam(Bit#(64) numRows, ColType colType, Bit#(64) basePage);
      $display("%m setParam, numRows = %d, basePage = %d, colType = ", numRows, basePage, fshow(colType));
      colMetaQ.enq(tuple2(toNumPages(numRows, colType), basePage));
   endmethod
endmodule
   
