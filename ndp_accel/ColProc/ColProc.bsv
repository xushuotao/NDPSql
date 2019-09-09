import ColProcReader::*;
import ColXForm::*;

import Vector::*;
import Pipe::*;
import FIFO::*;
import FIFOF::*;
import GetPut::*;
import ClientServer::*;
import ClientServerHelper::*;
import Connectable::*;

import OneToNRouter::*;
import FlashCtrlIfc::*;
import DualFlashPageBuffer::*;

import RowMask::*;

import ISSPTypes::*;
import NDPCommon::*;
import NDPDrain::*;
import Aggregate::*;
import NDPAggregate::*;

Bool debug = True;

typedef enum {SetColNum, SetCol, SetParam, Run} ProcState deriving (Bits, Eq, FShow);

interface ProgramOutputCol;
   method Action setColNum(ColNumT colnum);
   interface PipeIn#(Tuple4#(ColIdT, ColType, NDPDest, Bool)) colInfoPort;
   interface PipeIn#(Tuple3#(ColIdT, ParamT, Bool)) colNDPParamPort;
endinterface

interface ColProcOutput;
   interface Vector#(MaxNumCol, PipeOut#(AggrResp)) aggrResultOut;
endinterface


interface ColProc;
   interface Vector#(MaxNumCol, PipeIn#(Tuple2#(Bit#(64), Bool))) pageInPipes;
   interface PageBufferClient#(PageBufSz) pageBufferClient;
   
   interface PipeIn#(RowVecReq) rowVecReq;

   interface Client#(RowMaskRead, RowVectorMask) maskReadClient;

   interface Get#(Bit#(9)) releaseRowVecs;
   
   interface ProgramColProcReader programColProcReader;
   interface ProgramColXForm#(ColXFormEngs) programColXForm;
   interface ProgramOutputCol programOutputCol;


   // TODO:: output interface
   interface ColProcOutput colProcOutput;
endinterface

(* synthesize *)
module mkColXForm_synth(ColXForm#(ColXFormEngs));
   let m <-  mkColXForm;
   return m;
endmodule


(* synthesize *)
module mkColProc(ColProc);
   
   let colProcReader <- mkColProcReader;
   let colXForm <- mkColXForm_synth;
   
   FIFO#(RowVecReq) rowVecReqQ <- mkFIFO;
   
   FIFOF#(RowMaskRead) maskReqQ <- mkSizedFIFOF(8);
   FIFOF#(RowVectorMask) maskRespQ <- mkFIFOF;
   
   FIFO#(Bit#(9)) releaseQ <- mkFIFO;
   
   mkConnection(colProcReader.rowVecOut, colXForm.rowVecIn);
   mkConnection(colProcReader.outPipe, colXForm.inPipe);
   
   FIFO#(Tuple2#(Bit#(64), Bool)) bypassRowVecQ <- mkSizedFIFO(8);
   
   Reg#(ProcState) state <- mkReg(SetColNum);
   
   rule issueRd;
      let {rowVecId, last} = colXForm.rowVecOut.first;
      colXForm.rowVecOut.deq;
      maskReqQ.enq(RowMaskRead{id:truncate(rowVecId),
                               src:0});
      bypassRowVecQ.enq(tuple2(rowVecId,last));
      if ( debug) $display("(%m) receive rowVecReq from ColxForm rowVecId = %d, last = %d ", rowVecId, last);
   endrule
   
   Reg#(Bit#(TLog#(MaxNumCol))) colCntMask <- mkReg(0);
   
   
   Reg#(Bit#(TLog#(TAdd#(MaxNumCol,1)))) outColNum <- mkReg(0);
   Vector#(MaxNumCol, Reg#(Bit#(5))) beatsPerRowVec_V <- replicateM(mkRegU);
   Vector#(MaxNumCol, Reg#(NDPDest)) destSel <- replicateM(mkReg(NDP_Drain));
   
   Vector#(MaxNumCol, OneToNRouter#(NDPDestCnt, RowMask)) rowMaskToNDP <- replicateM(mkOneToNRouterPipelined);
   Vector#(MaxNumCol, OneToNRouter#(NDPDestCnt, RowData)) rowDataToNDP <- replicateM(mkOneToNRouterPipelined);
   Vector#(MaxNumCol, OneToNRouter#(NDPDestCnt, Bit#(5))) setByteRouter <- replicateM(mkOneToNRouterPipelined);
   Vector#(MaxNumCol, OneToNRouter#(NDPDestCnt, ParamT)) setParamRouter <- replicateM(mkOneToNRouterPipelined);

   
   Vector#(MaxNumCol, NDPAccel) drainNDPs <- replicateM(mkNDPDrain);
   Vector#(MaxNumCol, NDPAggregate) aggrNDPs <- replicateM(mkNDPAggregate);
   Vector#(MaxNumCol, Reg#(Maybe#(AggrResp))) aggrResults <- replicateM(mkReg(tagged Invalid));
   
   
   for ( Integer i = 0; i < valueOf(MaxNumCol); i = i + 1) begin
      let ndpStreamOuts = zipWith(zipNDPStreamOut, rowMaskToNDP[i].outPorts, rowDataToNDP[i].outPorts);
      // 0 for NDPDrain
      mkConnection(ndpStreamOuts[0], drainNDPs[i].streamIn);
      mkConnection(setByteRouter[i].outPorts[0], drainNDPs[i].configure);
      mkConnection(setParamRouter[i].outPorts[0], drainNDPs[i].configure);
      // 1 for NDPAggregate
      mkConnection(ndpStreamOuts[1], aggrNDPs[i].streamIn);
      mkConnection(setByteRouter[i].outPorts[1], aggrNDPs[i].configure);
      mkConnection(setParamRouter[i].outPorts[1], aggrNDPs[i].configure);
      // TODOs
      // 2 for Group
      // 3 for Bloomfilter
      // 4 for Host
   end
   

   function Bit#(TLog#(NDPDestCnt)) toNDPId(NDPDest dest);
      return case (dest)
                NDP_Aggregate: 1;
                default: 0;
             endcase;
   endfunction
   
   
   Reg#(Bit#(64)) prevRowVecId <- mkReg(-1);
   rule collectMask if (state == Run);
      let mask = maskRespQ.first;
      let {rowVecId, last} = bypassRowVecQ.first;

      if ( zeroExtend(colCntMask) + 1 == outColNum ) begin
         maskRespQ.deq;
         bypassRowVecQ.deq;
         colCntMask <= 0;
         prevRowVecId <= rowVecId;
         releaseQ.enq(truncate(rowVecId - prevRowVecId));
      end
      else begin
         colCntMask <= colCntMask + 1;
      end
      
      if (debug) $display("(%m) @%t collect and distribute rowmask rowVecId = %d, colCntMask = %d, mask = %b, last = %d", $time, rowVecId, colCntMask, mask, last);
      rowMaskToNDP[colCntMask].inPort.enq(tuple2(toNDPId(destSel[colCntMask]),RowMask{rowVecId: rowVecId,
                                                                                      mask: mask,
                                                                                      isLast: last,
                                                                                      hasData: True}));
   endrule
   
   Reg#(Bit#(TLog#(MaxNumCol))) colCntData <- mkReg(0);

   
   Reg#(Bit#(5)) beatCnt <- mkReg(0);
   
   Reg#(Bit#(64)) beatNum <- mkReg(0);
   
   FIFO#(Tuple2#(Bit#(TLog#(MaxNumCol)), Bit#(256))) dataBuf <- mkSizedFIFO(8);
   
   rule collectData if (state == Run);
      if ( beatCnt + 1 == beatsPerRowVec_V[colCntData] ) begin
         beatCnt <= 0;
         if ( zeroExtend(colCntData) + 1 == outColNum ) begin
            colCntData <= 0;
         end
         else begin
            colCntData <= colCntData + 1;
         end
      end
      else begin
         beatCnt <= beatCnt + 1;
      end
      beatNum <= beatNum + 1;
      let d = colXForm.outPipe.first;
      colXForm.outPipe.deq;
      if (debug) $display("(%m) @%t collect Data beatCnt = %d, colCntData = %d, data = %h, beatNum = %d", $time, beatCnt, colCntData, d, beatNum);
      dataBuf.enq(tuple2(colCntData, d));
   endrule
   
   rule releaseData;
      let {colCntData, d} <- toGet(dataBuf).get();
      rowDataToNDP[colCntData].inPort.enq(tuple2(toNDPId(destSel[colCntData]),d));
   endrule
      
   
   interface pageInPipes = colProcReader.pageInPipes;
   // interface flashRdClient = colProcReader.flashRdClient;
   interface pageBufferClient = colProcReader.flashBufClient;
   
   interface rowVecReq = colProcReader.rowVecReq;
   
   interface maskReadClient = toClient(maskReqQ, maskRespQ);

   interface releaseRowVecs = toGet(releaseQ);
   
   interface programColProcReader = colProcReader.programIfc;
   
   interface programColXForm = colXForm.programIfc;
   
   interface ProgramOutputCol programOutputCol;
      method Action setColNum(ColNumT colnum) if ( state == SetColNum);
         $display("(%m) setOutColNum = %d", colnum);
         outColNum <= colnum;
         state <= SetCol;
      endmethod
      interface PipeIn colInfoPort;
         method Action enq(Tuple4#(ColIdT, ColType, NDPDest, Bool) v) if ( state == SetCol );
            let {colIdT, colType, ndpDest, isLast } = v;
            $display("%m colInfo set: ", fshow(v));
            destSel[colIdT] <= ndpDest;
            beatsPerRowVec_V[colIdT] <= toBeatsPerRowVec(colType);
            setByteRouter[colIdT].inPort.enq(tuple2(toNDPId(ndpDest), toColBytes(colType)));
            if ( isLast ) state <= SetParam;
         endmethod
         // don't rely on this method as a guard
         method Bool notFull;
            return state == SetCol;
         endmethod
      endinterface
      interface PipeIn colNDPParamPort;
         method Action enq(Tuple3#(ColIdT, ParamT, Bool) v) if ( state == SetParam );
            let {colId, param, last} = v;
            $display("%m colNDPParamPort = ", fshow(v));
            setParamRouter[colId].inPort.enq(tuple2(toNDPId(destSel[colId]), param));
            if (last ) state <= Run;
         endmethod
   
         // don't rely on this method as a guard
         method Bool notFull;
            return state == SetParam;
         endmethod
      endinterface
   endinterface
   
   
   interface ColProcOutput colProcOutput;
      interface aggrResultOut = map(takeAggrResp, aggrNDPs);
   endinterface
endmodule

