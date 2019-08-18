import FIFOF::*;
import Pipe::*;
import NDPCommon::*;
import Vector::*;
import FIFO::*;
import GetPut::*;
import AlgFuncs::*;

interface Select#(numeric type colBytes);
   interface NDPStreamIn streamIn;
   interface NDPStreamOut streamOut;
   interface NDPConfigure configure;
endinterface

function Bool unsignedTest(Bit#(sz) in,  Bit#(sz) lv, Bit#(sz) hv);
   return in >= lv && in <= hv;
endfunction
   
function Bool signedTest(Bit#(sz) in,  Bit#(sz) lv, Bit#(sz) hv);
   return signedLE(lv,in) && signedLE(in,hv);
endfunction

Bool debug = False;


module mkSelect(Select#(colBytes)) provisos(
   NumAlias#(TLog#(colBytes), lgColBytes),
   NumAlias#(TExp#(lgColBytes), colBytes),
   NumAlias#(TMul#(8, colBytes), colWidth),
   NumAlias#(TDiv#(32, colBytes), rowsPerBeat),
   NumAlias#(colBytes, ratio),
   Bits#(Vector::Vector#(ratio, Bit#(TDiv#(32, ratio))), 32),
   Alias#(Bit#(rowsPerBeat), rowMaskT),
   Add#(colWidth, a__, 128) );
   Integer rowsPerBeat_int = valueOf(rowsPerBeat);

   
   Reg#(Bit#(colWidth)) loBound <- mkRegU;
   Reg#(Bit#(colWidth)) hiBound <- mkRegU;
   
   // Reg#(Bool) produceRowId <- mkReg(False);
   

   FIFOF#(RowMask) rowMaskQ <- mkFIFOF;
   
   Reg#(Bit#(lgColBytes)) maskSel <- mkReg(0);
   // rowVecId, isLast, hasData, mask
   FIFO#(Tuple4#(Bit#(64), Bool, Bool, rowMaskT)) beatMaskQ <- mkFIFO;
   
   FIFOF#(RowData) rowDataQ <- mkSizedFIFOF((32/rowsPerBeat_int)+1);

   // rowVecId, isLast, hasData, mask
   FIFO#(Tuple4#(Bit#(64), Bool, Bool, rowMaskT)) outBeatMaskQ <- mkFIFO;
   FIFOF#(RowMask) outRowMaskQ <- mkFIFOF;   
   FIFOF#(RowData) outRowDataQ <- mkFIFOF;
   
   Reg#(Bool) andNotOr <- mkReg(True);
   
   Reg#(Bool) isSigned <- mkReg(True);
   
   function Vector#(n, Tuple2#(Bool, Bit#(sz))) evalPred(Vector#(n, Bit#(sz)) inV, Bit#(sz) lv, Bit#(sz) hv);
    Vector#(n, Bit#(sz)) lvVec = replicate(lv);
    Vector#(n, Bit#(sz)) hvVec = replicate(hv);
   
    if (isSigned)
       return zipWith(tuple2, zipWith3(signedTest, inV,  lvVec, hvVec), inV);
    else
       return zipWith(tuple2, zipWith3(unsignedTest, inV,  lvVec, hvVec), inV);
   endfunction


   
   rule rowMask2beatMask;
      let maskData = rowMaskQ.first;
      let rowVecId = maskData.rowVecId;
      let isLast = maskData.isLast;
      if ( maskData.hasData ) begin
         Vector#(colBytes, rowMaskT) maskV = unpack(maskData.mask);
         maskSel <= maskSel + 1;

         if ( debug) $display("(%m) rowMask2beatMask(%d) maskSel = %d, maskV = %b, isLast = ", valueOf(colBytes), maskSel, maskData.mask, fshow(isLast));
         if ( maskSel == maxBound ) rowMaskQ.deq;
         beatMaskQ.enq(tuple4(rowVecId, isLast, True, maskV[maskSel]));
      end
      else begin
         beatMaskQ.enq(tuple4(rowVecId, isLast, False, ?));
         rowMaskQ.deq;
      end
      

   endrule
   

   Reg#(Bit#(colWidth)) rowOffset <- mkReg(0);
   rule doSelect;
      let {rowVecId, last, hasData, mask} <- toGet(beatMaskQ).get();
      rowMaskT newMask = ?;
      if  ( hasData ) begin
         let v <- toGet(rowDataQ).get();
         Vector#(rowsPerBeat, Bit#(colWidth)) data = unpack(v);
         let evalRes = evalPred(data, loBound, hiBound);
         let dataMask = map(tpl_1, evalRes);
         Vector#(rowsPerBeat, Int#(colWidth)) data_int = unpack(v);
         if (debug) $display("(%m) doSelect(%d) (lo, hi)=(%d, %d), dataV = ", valueOf(colBytes), loBound, hiBound, fshow(data_int));
         // $display("(%m) doSelect(%d) dataMask = %b, notallzero = %d", valueOf(colBytes), dataMask, pack(dataMask) != 0);
         // newMask = andNotOr? pack(dataMask) & mask : pack(dataMask) | mask;
         newMask = pack(dataMask) & mask;
      
         rowOffset <= rowOffset + fromInteger(rowsPerBeat_int);
      
         Vector#(rowsPerBeat, Bit#(colWidth)) rowIds = zipWith(add2, replicate(rowOffset), genWith(fromInteger));
         
         outRowDataQ.enq(pack(rowIds));
      end 
      outBeatMaskQ.enq(tuple4(rowVecId, last, hasData, newMask));
   endrule
   
   Reg#(Bit#(lgColBytes)) maskCnt <- mkReg(0);
   
   Reg#(Bit#(32)) outMaskBuf <- mkRegU;

   rule rowMaskTomask;
      let {rowVecId, last, hasData, beatMask} <- toGet(outBeatMaskQ).get();
      Bit#(32) rowMask = truncateLSB({beatMask, outMaskBuf});
      if (debug) $display("(%m) rowMaskTomask(%d) maskCnt = %d, mask = %b, rowMask = %b, last = %d", valueOf(colBytes), maskCnt, rowMask, beatMask, last);      
      if ( hasData ) begin
         outMaskBuf <= rowMask;
         maskCnt <= maskCnt + 1;
         if ( maskCnt == maxBound ) 
            outRowMaskQ.enq(RowMask{rowVecId: rowVecId,
                                    mask: rowMask,
                                    hasData: True,
                                    isLast: last});
      end
      else begin
         outRowMaskQ.enq(RowMask{rowVecId: rowVecId,
                                 mask: ?,
                                 hasData: False,
                                 isLast: last});
      end
   endrule

   
   interface NDPStreamIn streamIn = toNDPStreamIn(rowDataQ, rowMaskQ);
   
   interface NDPStreamOut streamOut = toNDPStreamOut(outRowDataQ, outRowMaskQ);
   
   interface NDPConfigure configure;
      method Action setColBytes(Bit#(5) colBytes);
         noAction;
      endmethod
      method Action setParameters(Vector#(4, Bit#(128)) paras);
         $display("(%m) setParameters of colBytes %d, (loB, hiB, isSigned, andNotOr) = (%d,%d,%d,%d)", valueOf(colBytes), paras[0], paras[1], paras[2][0], paras[3][0]);
         loBound <= truncate(paras[0]);
         hiBound <= truncate(paras[1]);
         isSigned <= unpack(paras[2][0]);
         andNotOr <= unpack(paras[3][0]);
         rowOffset <= 0;
      endmethod
   endinterface
   
endmodule
