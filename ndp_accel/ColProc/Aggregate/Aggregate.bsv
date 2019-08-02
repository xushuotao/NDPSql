import AlgFuncs::*;
import BuildVector::*;
import ClientServer::*;
import Connectable::*;
import FIFO::*;
import FIFOF::*;
import GetPut::*;
import NDPCommon::*;
import Pipe::*;
import Vector::*;


typedef struct {
   Bit#(129) sum;
   Bit#(64) cnt;
   Bit#(TMul#(colBytes,8)) min;
   Bit#(TMul#(colBytes,8)) max;
   } AggrResult#(numeric type colBytes) deriving (Bits, Eq, FShow);

interface Aggregate#(numeric type colBytes);
   interface NDPStreamIn streamIn;
   interface PipeOut#(AggrResult#(colBytes)) aggrResp;
endinterface

function Tuple2#(Bool, Bit#(w)) minSigned2(Tuple2#(Bool, Bit#(w)) a, Tuple2#(Bool, Bit#(w)) b);
   let {valid_a, a_val} = a;
   Int#(w) a_comp = valid_a ? unpack(a_val) : maxBound;
   
   let {valid_b, b_val} = b;
   Int#(w) b_comp = valid_b ? unpack(b_val) : maxBound;
   return tuple2(True, pack(min(a_comp, b_comp)));
endfunction

function Tuple2#(Bool, Bit#(w)) minUnSigned2(Tuple2#(Bool, Bit#(w)) a, Tuple2#(Bool, Bit#(w)) b);
   let {valid_a, a_val} = a;
   UInt#(w) a_comp = valid_a ? unpack(a_val) : maxBound;
   
   let {valid_b, b_val} = b;
   UInt#(w) b_comp = valid_b ? unpack(b_val) : maxBound;
   return tuple2(True, pack(min(a_comp, b_comp)));
endfunction

function Tuple2#(Bool, Bit#(w)) maxSigned2(Tuple2#(Bool, Bit#(w)) a, Tuple2#(Bool, Bit#(w)) b);
   let {valid_a, a_val} = a;
   Int#(w) a_comp = valid_a ? unpack(a_val) : minBound;
   
   let {valid_b, b_val} = b;
   Int#(w) b_comp = valid_b ? unpack(b_val) : minBound;
   return tuple2(True, pack(max(a_comp, b_comp)));
endfunction

function Tuple2#(Bool, Bit#(w)) maxUnSigned2(Tuple2#(Bool, Bit#(w)) a, Tuple2#(Bool, Bit#(w)) b);
   let {valid_a, a_val} = a;
   UInt#(w) a_comp = valid_a ? unpack(a_val) : minBound;
   
   let {valid_b, b_val} = b;
   UInt#(w) b_comp = valid_b ? unpack(b_val) : minBound;
   return tuple2(True, pack(max(a_comp, b_comp)));
endfunction

function Tuple2#(Bool, Bit#(w)) sum2(Tuple2#(Bool, Bit#(w)) a, Tuple2#(Bool, Bit#(w)) b);
   let {valid_a, a_val} = a;
   UInt#(w) a_comp = valid_a ? unpack(a_val) : 0;
   
   let {valid_b, b_val} = b;
   UInt#(w) b_comp = valid_b ? unpack(b_val) : 0;

   return tuple2(True, pack(a_comp+b_comp));
endfunction


module mkAggregate#(Bool isSigned)(Aggregate#(colBytes)) provisos(
   NumAlias#(TLog#(colBytes), lgColBytes),
   NumAlias#(TExp#(lgColBytes), colBytes),
   NumAlias#(TMul#(8, colBytes), colWidth),
   NumAlias#(TDiv#(32, colBytes), rowsPerBeat),
   Alias#(Bit#(rowsPerBeat), rowMaskT),
   Bits#(Vector::Vector#(colBytes, Bit#(TDiv#(32, colBytes))), 32),
   Add#(b__, TLog#(TAdd#(1, TDiv#(32, colBytes))), 64),
   Add#(1, c__, TLog#(TAdd#(1, TDiv#(32, colBytes)))),
   Add#(1, d__, TDiv#(32, colBytes)),
   Add#(e__, TAdd#(TMul#(8, colBytes), TLog#(TDiv#(32, colBytes))), 129),
   Add#(colWidth, a__, 128) );
   
   Integer rowsPerBeat_int = valueOf(rowsPerBeat);
   FIFOF#(RowMask) rowMaskQ <- mkFIFOF;
   FIFOF#(RowData) rowDataQ <- mkSizedFIFOF((32/rowsPerBeat_int)+1);
   
   Reg#(Bit#(lgColBytes)) maskSel <- mkReg(0);
   // rowVecId, isLast, hasData, mask
   FIFO#(Tuple4#(Bit#(64), Bool, Bool, rowMaskT)) beatMaskQ <- mkFIFO;
   
   FIFOF#(AggrResult#(colBytes)) aggrResultQ <- mkFIFOF;
   
   rule rowMask2beatMask;
      let maskData = rowMaskQ.first;
      let rowVecId = maskData.rowVecId;
      let isLast = maskData.isLast;
      if ( maskData.hasData ) begin
         Vector#(colBytes, rowMaskT) maskV = unpack(maskData.mask);
         maskSel <= maskSel + 1;

         $display("(%m) rowMask2beatMask(%d) maskSel = %d, maskV = %b", valueOf(colBytes), maskSel, maskData.mask);
         if ( maskSel == maxBound ) rowMaskQ.deq;
         beatMaskQ.enq(tuple4(rowVecId, isLast, True, maskV[maskSel]));
      end
      else begin
         beatMaskQ.enq(tuple4(rowVecId, isLast, False, ?));
         rowMaskQ.deq;
      end
   endrule

   rule doAggr;
      let {rowVecId, last, hasData, mask} <- toGet(beatMaskQ).get();
      
      if  ( hasData ) begin
         let v <- toGet(rowDataQ).get();
         Vector#(rowsPerBeat, Bit#(colWidth)) data = unpack(v);
         
         let {dummy0, min} = fold(isSigned?minSigned2:minUnSigned2, 
                                 zip(unpack(mask), data));
         
         let {dummy1, max} = fold(isSigned?maxSigned2:maxUnSigned2, 
                             zip(unpack(mask),data));


         Tuple2#(Bool, Bit#(TAdd#(colWidth, TLog#(rowsPerBeat)))) tpl_sum 
         = fold(sum2,zip(unpack(mask), map(zeroExtend, data)));
         
         let {dummy2, sum} = tpl_sum;
         
         let cnt = countOnes(mask);
         aggrResultQ.enq(AggrResult{sum: zeroExtend(sum),
                                    min: min,
                                    max: max,
                                    cnt: zeroExtend(pack(cnt))});
      end
   endrule
   
   interface NDPStreamIn streamIn = toNDPStreamIn(rowDataQ, rowMaskQ);
   interface PipeOut aggrResp = toPipeOut(aggrResultQ);
endmodule

