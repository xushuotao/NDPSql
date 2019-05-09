import Vector::*;
import FIFO::*;
import SpecialFIFOs::*;
import Pipe::*;
import NDPCommon::*;
import FIFOF::*;
import GetPut::*;
import Compaction::*;

typedef struct{
   Vector#(n, Tuple2#(Bool, Bit#(w))) data;
   Bool last;
   } StageT#(numeric type n, numeric type w) deriving (Bits, Eq, FShow);


typedef struct{
   Bit#(256) data;
   Bit#(6) bytes;
   Bool last;
   } CompactT deriving (Bits, Eq, FShow);



function Vector#(n, Tuple2#(Bool, Bit#(w))) evenCompact(Vector#(n, Tuple2#(Bool, Bit#(w))) inV);
   for ( Integer i = 0; i < valueOf(n); i = i + 2) begin
      if ( tpl_1(inV[i]) == False) begin
         inV[i] = inV[i+1];
         inV[i+1] = tuple2(False, ?);
      end
   end
   return inV;
endfunction

function Vector#(n, Tuple2#(Bool, Bit#(w))) oddCompact(Vector#(n, Tuple2#(Bool, Bit#(w))) inV);
   for ( Integer i = 1; i < valueOf(n) - 1; i = i + 2) begin
      if ( tpl_1(inV[i]) == False) begin
         inV[i] = inV[i+1];
         inV[i+1] = tuple2(False, ?);
      end
   end
   return inV;
endfunction


interface Compact#(numeric type colBytes);
   interface NDPStreamIn streamIn;
   interface PipeOut#(CompactT) outPipe;
endinterface


module mkCompact(Compact#(colBytes)) provisos(
   NumAlias#(TLog#(colBytes), lgColBytes),
   NumAlias#(TExp#(lgColBytes), colBytes),
   NumAlias#(TDiv#(32, colBytes), rowsPerBeat),
   Alias#(Bit#(rowsPerBeat), rowMaskT),
   NumAlias#(TMul#(8, colBytes), colWidth),
   Add#(a__, TLog#(TAdd#(1, TDiv#(32, colBytes))), 6),
   Bits#(Vector::Vector#(colBytes, Bit#(TDiv#(32, colBytes))), 32),
   Add#(b__, TLog#(TAdd#(1, TDiv#(32, colBytes))), TAdd#(TLog#(TDiv#(32,
      colBytes)), 2)),
   Add#(1, c__, TDiv#(32, colBytes)),
   Add#(TDiv#(32, colBytes), d__, TMul#(TDiv#(32, colBytes), 2))
 );
   
   
   Integer rowsPerBeat_int = valueOf(rowsPerBeat);                  

   FIFOF#(RowData) rowDataQ <- mkSizedFIFOF((32/rowsPerBeat_int)+1);
   FIFOF#(Bit#(32)) maskDataQ <- mkFIFOF;
   
   Reg#(Bit#(lgColBytes)) maskSel <- mkReg(0);
   FIFO#(rowMaskT) beatMaskQ <- mkFIFO;
   
   Compaction#(Bit#(colWidth), rowsPerBeat) compaction <- mkCompaction;
   
   rule maskToRowMask;
      Vector#(colBytes, rowMaskT) maskV = unpack(maskDataQ.first);
      beatMaskQ.enq(maskV[maskSel]);
      maskSel <= maskSel + 1;
      if (valueOf(colBytes) == 1 )
         maskDataQ.deq;
      else 
         if ( maskSel == -1 ) 
            maskDataQ.deq;

   endrule
   
   rule doInput;
      let m <- toGet(beatMaskQ).get;
      let d <- toGet(rowDataQ).get;
      
      compaction.reqPipe.enq(CompactReq{data: unpack(d.data),
                                        mask: m,
                                        last: d.last});
   endrule

   
   function CompactT toCompactT(CompactResp#(Bit#(colWidth), rowsPerBeat) v);
      return CompactT{data: pack(v.data),
                      bytes: zeroExtend(v.itemCnt) << valueOf(lgColBytes),
                      last: v.last};
   endfunction
                                                                          
   
   interface streamIn = toNDPStreamIn(rowDataQ, maskDataQ);
   interface outPipe = mapPipe(toCompactT, compaction.respPipe);
endmodule
