import Vector::*;
import Pipe::*;
import Connectable::*;

import ISSPTypes::*;
import NDPCommon::*;
import RowSelector::*;
import RowSelectorProgrammer::*;
import ColProc::*;
import ColProcProgrammer::*;
import Aggregate::*;

import FlashCtrlIfc::*;
import FlashReadMultiplex::*;
import DualFlashPageBuffer::*;
import RowMask::*;



interface ISSPProgram;
   interface RowSelectorProgramIfc rowSel;
   interface InColProgramIfc inCol;
   interface ColXFormProgramIfc colXForm;
   interface OutColProgramIfc outCol;
endinterface

interface ISSPDebugResp;
   method ActionValue#(Tuple4#(Bit#(8), Bit#(64), Bit#(8), Bit#(64))) trace_PageBuf;   
endinterface

interface ISSP;
   interface Vector#(2, FlashCtrlClient) flashClients;
   interface ISSPProgram programIfc;
   interface PageFeeder pagefeeder;
   interface ColProcOutput isspOutput;
   interface ISSPDebug debug;
   interface ISSPDebugResp debugResp;
endinterface

(* synthesize *)
module mkDualFlashPageBuffer_synth(DualFlashPageBuffer#(TAdd#(SelectCols,1), PageBufSz));
   let pageBuf <- mkDualFlashPageBuffer;
   return pageBuf;
endmodule

(* synthesize *)
module mkRowSelector_synth(RowSelector#(SelectCols));
   let rowSelector <- mkRowSelector;
   return rowSelector;
endmodule

(* synthesize *)
module mkISSP(ISSP);
   
   FlashReadMultiplexOO#(1) flashMux <- mkFlashReadMultiplexOO;
   
   DualFlashPageBuffer#(TAdd#(SelectCols,1), PageBufSz) pageBuf <- mkDualFlashPageBuffer_synth;
   
   mkConnection(pageBuf.flashRdClient, flashMux.flashReadServers[0]);
   
   RowSelector#(SelectCols) rowSel <- mkRowSelector_synth;
   
   ColProc colProc <- mkColProc;
      
   zipWithM_(mkConnection, cons(colProc.pageBufferClient, reverse(rowSel.pageBufferClients)), pageBuf.pageBufferServers);
   
   mkConnection(rowSel.rowVecReq, colProc.rowVecReq);

   RowMaskBuff#(TAdd#(SelectCols,1)) rowMaskBuff <- mkRowMaskBuff;
   
   mkConnection(rowSel.reserveRowVecs, rowMaskBuff.reserveRowVecs);
   mkConnection(colProc.releaseRowVecs, rowMaskBuff.releaseRowVecs);
   
   zipWithM_(mkConnection, reverse(rowSel.rowMaskWrites), take(rowMaskBuff.writePorts));
   zipWithM_(mkConnection, cons(colProc.maskReadClient, reverse(rowSel.rowMaskReads)), rowMaskBuff.readPorts);
   
   // program-related parts
   let programmer_rowSel   <- mkRowSelectorProgramIfc(rowSel.programIfc);
   let programmer_inCol    <- mkInColProgramIfc(colProc.programColProcReader);
   let programmer_colXForm <- mkColXFormProgramIfc(colProc.programColXForm);
   let programmer_outCol   <- mkOutColProgramIfc(colProc.programOutputCol);
   
   
   interface flashClients = flashMux.flashClient;
   interface ISSPProgram programIfc;
      interface rowSel   = programmer_rowSel  ;
      interface inCol    = programmer_inCol   ;
      interface colXForm = programmer_colXForm;
      interface outCol   = programmer_outCol  ;
   endinterface
   
   
   interface ISSPDebug debug;
      method Action dumpTrace_PageBuf();
         pageBuf.dumpTrace;
      endmethod
   endinterface
   
   interface ISSPDebugResp debugResp;
      method ActionValue#(Tuple4#(Bit#(8), Bit#(64), Bit#(8), Bit#(64))) trace_PageBuf;
         let v <- pageBuf.traceResp;
         return v;
      endmethod
   endinterface


   
   interface PageFeeder pagefeeder;
      method Action sendPageAddr_0 (Bit#(64) pageAddr, Bool last); rowSel.pageInPipes[0].enq(tuple2(pageAddr, last)); $display("(%m) received pageAddr for col_0   pageAddr = %d", pageAddr); endmethod
      method Action sendPageAddr_1 (Bit#(64) pageAddr, Bool last); rowSel.pageInPipes[1].enq(tuple2(pageAddr, last)); $display("(%m) received pageAddr for col_1   pageAddr = %d", pageAddr); endmethod
      method Action sendPageAddr_2 (Bit#(64) pageAddr, Bool last); rowSel.pageInPipes[2].enq(tuple2(pageAddr, last)); $display("(%m) received pageAddr for col_2   pageAddr = %d", pageAddr); endmethod
      method Action sendPageAddr_3 (Bit#(64) pageAddr, Bool last); rowSel.pageInPipes[3].enq(tuple2(pageAddr, last)); $display("(%m) received pageAddr for col_3   pageAddr = %d", pageAddr); endmethod
      method Action sendPageAddr_4 (Bit#(64) pageAddr, Bool last);colProc.pageInPipes[0].enq(tuple2(pageAddr, last)); $display("(%m) received pageAddr for col_4   pageAddr = %d", pageAddr); endmethod
      method Action sendPageAddr_5 (Bit#(64) pageAddr, Bool last);colProc.pageInPipes[1].enq(tuple2(pageAddr, last)); $display("(%m) received pageAddr for col_5   pageAddr = %d", pageAddr); endmethod
      method Action sendPageAddr_6 (Bit#(64) pageAddr, Bool last);colProc.pageInPipes[2].enq(tuple2(pageAddr, last)); $display("(%m) received pageAddr for col_6   pageAddr = %d", pageAddr); endmethod
      method Action sendPageAddr_7 (Bit#(64) pageAddr, Bool last);colProc.pageInPipes[3].enq(tuple2(pageAddr, last)); $display("(%m) received pageAddr for col_7   pageAddr = %d", pageAddr); endmethod
      method Action sendPageAddr_8 (Bit#(64) pageAddr, Bool last);colProc.pageInPipes[4].enq(tuple2(pageAddr, last)); $display("(%m) received pageAddr for col_8   pageAddr = %d", pageAddr); endmethod
      method Action sendPageAddr_9 (Bit#(64) pageAddr, Bool last);colProc.pageInPipes[5].enq(tuple2(pageAddr, last)); $display("(%m) received pageAddr for col_9   pageAddr = %d", pageAddr); endmethod
      method Action sendPageAddr_10(Bit#(64) pageAddr, Bool last);colProc.pageInPipes[6].enq(tuple2(pageAddr, last)); $display("(%m) received pageAddr for col_10  pageAddr = %d", pageAddr); endmethod
      method Action sendPageAddr_11(Bit#(64) pageAddr, Bool last);colProc.pageInPipes[7].enq(tuple2(pageAddr, last)); $display("(%m) received pageAddr for col_11  pageAddr = %d", pageAddr); endmethod
   endinterface
   interface isspOutput  = colProc.colProcOutput;

endmodule
