import Vector::*;
import FIFO::*;
import SpecialFIFOs::*;
import Pipe::*;
import NDPCommon::*;
import FIFOF::*;
import GetPut::*;

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
   Mul#(colBytes, TDiv#(32, colBytes), 32),
   NumAlias#(TMul#(8, colBytes), colWidth),
   Alias#(Bit#(rowsPerBeat), rowMaskT),
   Add#(a__, TLog#(TAdd#(1, TDiv#(32, colBytes))), TAdd#(TLog#(TDiv#(32, colBytes)), 2)),
   Add#(TLog#(TDiv#(32, colBytes)), 1, TLog#(TAdd#(1, TDiv#(32, colBytes)))),
   Add#(TDiv#(32, colBytes), b__, TMul#(TDiv#(32, colBytes), 2)),
   Add#(c__, TLog#(TAdd#(1, TDiv#(32, colBytes))), 6)
 );
   
   Integer rowsPerBeat_int = valueOf(rowsPerBeat);                  

   FIFOF#(RowData) rowDataQ <- mkSizedFIFOF((32/rowsPerBeat_int)+1);
   FIFOF#(Bit#(32)) maskDataQ <- mkFIFOF;
   

   Reg#(Bit#(lgColBytes)) maskSel <- mkReg(0);
   FIFO#(rowMaskT) rowMaskQ <- mkFIFO;
   
   rule maskToRowMask;
      Vector#(colBytes, rowMaskT) maskV = unpack(maskDataQ.first);
      rowMaskQ.enq(maskV[maskSel]);
      maskSel <= maskSel + 1;
      if (valueOf(colBytes) == 1 )
         maskDataQ.deq;
      else 
         if ( maskSel == -1 ) 
            maskDataQ.deq;

   endrule
   
   
   Vector#(rowsPerBeat, FIFO#(StageT#(rowsPerBeat, colWidth))) stageQs <- replicateM(mkLFIFO);
   
   
   rule doCompactL0;
      let v <- toGet(rowDataQ).get();
      let mask <- toGet(rowMaskQ).get();
      Vector#(rowsPerBeat, Bit#(colWidth)) data = unpack(v.data);
      $display("%m rowData = ", fshow(data));
      $display("%m rowsPerBeat = %d, mask = %b", rowsPerBeat_int, mask);
      stageQs[0].enq(StageT{data:evenCompact(zipWith(tuple2, unpack(mask), unpack(v.data))),last:v.last});
   endrule
   
   for (Integer i = 1 ; i < valueOf(rowsPerBeat) ; i = i + 1) begin
      rule connectL;
         let in <- toGet(stageQs[i-1]).get;
         if ( i % 2 == 0)
            stageQs[i].enq(StageT{data:evenCompact(in.data),last:in.last});
         else
            stageQs[i].enq(StageT{data:oddCompact(in.data),last:in.last});
      endrule
   end
   
   Reg#(UInt#(TAdd#(TLog#(rowsPerBeat),1))) oldCnt <- mkReg(0);
         

         
   
   Reg#(Vector#(rowsPerBeat, Tuple2#(Bool, Bit#(colWidth)))) outBuf <- mkRegU;
   Reg#(Bool) flush <- mkReg(False);
         
   FIFO#(StageT#(rowsPerBeat, colWidth)) compactedQ <- mkLFIFO;
   
   rule doBatch (!flush);
      let v <- toGet(stageQs[valueOf(rowsPerBeat)-1]).get;
      $display("%m, condensed beat = ", fshow(v));
      let newCnt = countElem(True, map(tpl_1, v.data));

      Vector#(TMul#(rowsPerBeat,2), Tuple2#(Bool, Bit#(colWidth))) concataV = append(outBuf, v.data);
      
      // let rotatedV = reverse(rotateBy(reverse(concataV), newCnt));
      UInt#(TAdd#(TLog#(rowsPerBeat),2)) shiftSz = extend(newCnt);
      let rotatedV = shiftOutFrom0(?, concataV, shiftSz);
      
      if ( newCnt > 0 ) begin
         $display("newCnt=%d, oldCnt=%d", newCnt, oldCnt);
         $display("concatedV = ", fshow(concataV));
         $display("rotatedV = ", fshow(rotatedV));
      end
      
      outBuf <= take(rotatedV);

      
      flush <= v.last && (oldCnt + newCnt > fromInteger(rowsPerBeat_int));
      
      Bool last = v.last && (oldCnt + newCnt <= fromInteger(rowsPerBeat_int));
      
      oldCnt <= last? 0 : (oldCnt + newCnt)%fromInteger(rowsPerBeat_int);
      
      // let outdata = reverse(rotateBy(reverse(concataV), 8-oldCnt));
      UInt#(TAdd#(TLog#(rowsPerBeat),2)) shiftSz2 = extend(fromInteger(rowsPerBeat_int) - oldCnt);
      let outdata = shiftOutFrom0(?, concataV, shiftSz2);
      
      $display("v.last = %d, islast = %d", v.last, last);
      
      
      if ( oldCnt + newCnt >= fromInteger(rowsPerBeat_int) || v.last ) begin
         compactedQ.enq(StageT{data: take(outdata),
                               last: last});
      end
   endrule
   
   rule doFlush (flush);
      $display("do flush oldCnt = %d", oldCnt);
      flush <= False;
      // let outdata = reverse(rotateBy(reverse(outBuf), truncate(8-oldCnt)));
      let outdata = shiftOutFrom0(?,outBuf, fromInteger(rowsPerBeat_int)-oldCnt);
      compactedQ.enq(StageT{data: take(outdata),
                            last: True});
   endrule
   
   FIFOF#(CompactT) outPipeQ <- mkFIFOF;
   
   rule produceCompacT;
      let v <- toGet(compactedQ).get();
      Vector#(rowsPerBeat, Bit#(colWidth)) dataV = map(tpl_2, v.data);
      Vector#(rowsPerBeat, Bool) maskV = map(tpl_1, v.data);
      Bit#(6) bytes = pack(extend(countElem(True, maskV))) << valueOf(lgColBytes);
      outPipeQ.enq(CompactT{data: pack(dataV),
                            bytes: bytes,
                            last: v.last});
      
   endrule

   
   interface streamIn = toNDPStreamIn(rowDataQ, maskDataQ);
   interface outPipe = toPipeOut(outPipeQ);
endmodule
