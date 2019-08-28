import Vector::*;
import FIFO::*;
import SpecialFIFOs::*;
import Pipe::*;
import ISSPTypes::*;
import NDPCommon::*;
import FIFOF::*;
import GetPut::*;
import Compaction::*;


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
   Add#(b__, TLog#(TAdd#(1, TDiv#(32, colBytes))), 
        TLog#(TAdd#(1,TAdd#(TDiv#(32, colBytes), TDiv#(32, colBytes))))),
   Add#(1, c__, TDiv#(32, colBytes)),
   Add#(TDiv#(32, colBytes), d__, TMul#(TDiv#(32, colBytes), 2))
 );
   
   
   Integer rowsPerBeat_int = valueOf(rowsPerBeat);                  

   FIFOF#(RowData) rowDataQ <- mkSizedFIFOF((32/rowsPerBeat_int)+1);
   FIFOF#(RowMask) maskDataQ <- mkFIFOF;
   
   Reg#(Bit#(lgColBytes)) maskSel <- mkReg(0);
   FIFO#(Tuple2#(rowMaskT, Bool)) beatMaskQ <- mkFIFO;
   
   Compaction#(Bit#(colWidth), rowsPerBeat) compaction <- mkCompaction;
   
   rule maskToRowMask;
      Vector#(colBytes, rowMaskT) maskV = unpack(maskDataQ.first.mask);
      beatMaskQ.enq(tuple2(maskV[maskSel], valueOf(colBytes)== 1||maskSel==-1?maskDataQ.first.last:False));
      maskSel <= maskSel + 1;
      if (valueOf(colBytes) == 1 )
         maskDataQ.deq;
      else 
         if ( maskSel == -1 ) 
            maskDataQ.deq;

   endrule
   
   rule doInput;
      let {m, last} <- toGet(beatMaskQ).get;
      let d <- toGet(rowDataQ).get;
      
      compaction.reqPipe.enq(CompactReq{data: unpack(d),
                                        mask: m,
                                        last: last});
   endrule

   
   function CompactT toCompactT(CompactResp#(Bit#(colWidth), rowsPerBeat) v);
      return CompactT{data: pack(v.data),
                      bytes: zeroExtend(v.itemCnt) << valueOf(lgColBytes),
                      last: v.last};
   endfunction
                                                                          
   
   interface streamIn = toNDPStreamIn(rowDataQ, maskDataQ);
   interface outPipe = mapPipe(toCompactT, compaction.respPipe);
endmodule
