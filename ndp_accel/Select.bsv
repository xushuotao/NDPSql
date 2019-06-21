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
   FIFO#(Tuple3#(Bit#(64), Bool,  rowMaskT)) beatMaskQ <- mkFIFO;
   
   FIFOF#(RowData) rowDataQ <- mkSizedFIFOF((32/rowsPerBeat_int)+1);

   FIFO#(Tuple3#(Bit#(64), Bool, rowMaskT)) outBeatMaskQ <- mkFIFO;
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
      case (rowMaskQ.first) matches
         tagged Mask .maskData: 
            begin
               Vector#(colBytes, rowMaskT) maskV = unpack(maskData.mask);
               maskSel <= maskSel + 1;
               let rowVecId = maskData.rowVecId;
               $display("(%m) rowMask2beatMask(%d) maskSel = %d, maskV = %b", valueOf(colBytes), maskSel, maskData.mask);
               if ( maskSel == maxBound ) rowMaskQ.deq;
               beatMaskQ.enq(tuple3(rowVecId, False, maskV[maskSel]));
            end
         tagged Last:
            begin
               $display("(%m) rowMask2beatMask(%d) Last, maskSel = %d", valueOf(colBytes), maskSel);
               beatMaskQ.enq(tuple3(?, True, ?));
               rowMaskQ.deq;
            end
      endcase
      

   endrule
   

   Reg#(Bit#(colWidth)) rowOffset <- mkReg(0);
   rule doSelect;
      let {rowVecId, last, mask} <- toGet(beatMaskQ).get();
      rowMaskT newMask = ?;
      if  ( !last ) begin
         let v <- toGet(rowDataQ).get();
         Vector#(rowsPerBeat, Bit#(colWidth)) data = unpack(v);
         let evalRes = evalPred(data, loBound, hiBound);
         let dataMask = map(tpl_1, evalRes);
         Vector#(rowsPerBeat, Int#(colWidth)) data_int = unpack(v);
         $display("(%m) doSelect(%d) (lo, hi)=(%d, %d), dataV = ", valueOf(colBytes), loBound, hiBound, fshow(data_int));
         // $display("(%m) doSelect(%d) dataMask = %b, notallzero = %d", valueOf(colBytes), dataMask, pack(dataMask) != 0);
         newMask = andNotOr? pack(dataMask) & mask : pack(dataMask) | mask;
      
         rowOffset <= rowOffset + fromInteger(rowsPerBeat_int);
      
         Vector#(rowsPerBeat, Bit#(colWidth)) rowIds = zipWith(add2, replicate(rowOffset), genWith(fromInteger));
         
         outRowDataQ.enq(pack(rowIds));
      end 
      outBeatMaskQ.enq(tuple3(rowVecId, last, newMask));
   endrule
   
   Reg#(Bit#(lgColBytes)) maskCnt <- mkReg(0);
   
   Reg#(Bit#(32)) outMaskBuf <- mkRegU;

   rule rowMaskTomask;
      
      let {rowVecId, last, beatMask} <- toGet(outBeatMaskQ).get();
      Bit#(32) rowMask = truncateLSB({beatMask, outMaskBuf});
      $display("(%m) rowMaskTomask(%d) maskCnt = %d, mask = %b, rowMask = %b, last = %d", valueOf(colBytes), maskCnt, rowMask, beatMask, last);      
      if ( !last ) begin
         outMaskBuf <= rowMask;
         maskCnt <= maskCnt + 1;
         if ( maskCnt == maxBound ) 
            outRowMaskQ.enq(tagged Mask MaskData{rowVecId: rowVecId,
                                                 mask: rowMask});
      end
      else begin
          outRowMaskQ.enq(tagged Last);
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
