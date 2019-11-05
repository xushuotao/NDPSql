import ISSPTypes::*;
import NDPCommon::*;
import FIFO::*;
import FIFOF::*;
import Pipe::*;
import SpecialFIFOs::*;
import FlashCtrlIfc::*;
import GetPut::*;

Bool debug = False;

interface ColPageEng;
   interface PipeIn#(Tuple2#(Bit#(64), Bool)) pageInPipe;
   method ActionValue#(Tuple2#(DualFlashAddr, Bool)) getNextPageAddr();

   method Action setParam(Bit#(64) numRows, ColType colType, Bit#(64) basePage);   
endinterface


(* synthesize *)
module mkColPageEng(ColPageEng);
   FIFOF#(Tuple2#(DualFlashAddr, Bool)) addrQ <- 
   `ifndef HOST   
   mkFIFOF;
   `else
   mkSizedFIFOF(128);
   `endif
   

`ifndef HOST   
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
      
      if (debug) $display("(%m) genPageId, pageCnt = %d, numPages = %d, usefulBeats = %d, rowVecsPerPage = %d", pageCnt, numPages, usefulBeats, rowVecsPerPage);
      addrQ.enq(tuple2(toDualFlashAddr(basePage + pageCnt), last));
   endrule
   
`else
   function Tuple2#(DualFlashAddr, Bool) mapfunc(Tuple2#(Bit#(64), Bool) v);
      let {addr, last} = v;
      return tuple2(toDualFlashAddr(addr), last);
   endfunction
   interface PipeIn pageInPipe = mapPipeIn(mapfunc, toPipeIn(addrQ));
`endif
   method ActionValue#(Tuple2#(DualFlashAddr, Bool)) getNextPageAddr();
      let v = addrQ.first;
      addrQ.deq;
      if (debug) $display("(%m) genNextPageAddr, addr = ", fshow(v));
      return v;
   endmethod
   
   method Action setParam(Bit#(64) numRows, ColType colType, Bit#(64) basePage);

      $display("%m setParam, numRows = %d, basePage = %d, colType = ", numRows, basePage, fshow(colType));
      $display("%m setParam, numPages = %d, basePage = %d, numRowVecs = %d, lastPageBeats = ", toNumPages(numRows, colType), basePage, toNumRowVecs(numRows), lastPageBeats(numRows, colType));
      `ifndef HOST   
      colMetaQ.enq(tuple4(toNumPages(numRows, colType), basePage, lastPageBeats(numRows, colType), toRowVecsPerPage2(colType)));
      `endif
   endmethod
endmodule
   
