import Vector::*;
import FIFO::*;
import SpecialFIFOs::*;
import Pipe::*;
import FIFOF::*;
import GetPut::*;
import Connectable::*;

typedef struct{
   Vector#(vSz, dataT) data;
   Bit#(vSz) mask;
   Bool last;
   } CompactReq#(type dataT, numeric type vSz) deriving (FShow, Bits, Eq);
   
typedef struct{
   Vector#(vSz, dataT) data;
   Bit#(TLog#(TAdd#(1,vSz))) itemCnt;
   Bool last;
   } CompactResp#(type dataT, numeric type vSz) deriving (FShow, Bits, Eq);

typedef struct{
   Vector#(vSz, Tuple2#(Bool, Bit#(dSz))) data;
   Bool last;
   } PipeT#(numeric type dSz, numeric type vSz) deriving (Bits, Eq, FShow);

interface Compaction#(type dataT, numeric type vSize);
   interface PipeIn#(CompactReq#(dataT, vSize)) reqPipe;
   interface PipeOut#(CompactResp#(dataT, vSize)) respPipe;
endinterface


module connectStage#(PipeOut#(PipeT#(dSz, vSz)) outPort, PipeIn#(PipeT#(dSz,vSz)) inPort, Integer i)(Empty);
   
   function PipeT#(dSz, vSz) evenCompact(PipeT#(dSz, vSz) d);
      Vector#(vSz, Tuple2#(Bool, Bit#(dSz))) inV = d.data;
      for ( Integer i = 0; i < valueOf(vSz); i = i + 2) begin
         if ( tpl_1(inV[i]) == False) begin
            inV[i] = inV[i+1];
            inV[i+1] = tuple2(False, ?);
         end
      end
      return PipeT{data:inV, last:d.last};
   endfunction

   function PipeT#(dSz, vSz) oddCompact(PipeT#(dSz, vSz) d);
      Vector#(vSz, Tuple2#(Bool, Bit#(dSz))) inV = d.data;
      for ( Integer i = 1; i < valueOf(vSz) - 1; i = i + 2) begin
         if ( tpl_1(inV[i]) == False) begin
            inV[i] = inV[i+1];
            inV[i+1] = tuple2(False, ?);
         end
      end
      return PipeT{data:inV, last:d.last};
   endfunction

   mkConnection(mapPipe(i%2==0?evenCompact:oddCompact, outPort), inPort);
endmodule



module mkCompaction(Compaction#(dataT, vSz)) provisos(
   Bits#(dataT, dSz),
   NumAlias#(vSz, TExp#(TLog#(vSz))),
   Add#(a__, TLog#(TAdd#(1, vSz)), TLog#(TAdd#(1, TAdd#(vSz, vSz)))),
   Add#(1, b__, vSz),
   Add#(vSz, c__, TMul#(vSz, 2))
 );
   
   
   Integer vSz_int = valueOf(vSz);
   
   FIFOF#(CompactReq#(dataT, vSz)) reqQ <- mkFIFOF;
   FIFOF#(CompactResp#(dataT, vSz)) respQ <- mkFIFOF;

   function PipeT#(dSz, vSz) toPipeT(CompactReq#(dataT, vSz) req) provisos (Bits#(dataT, dSz));
      return PipeT{data: zipWith(tuple2, unpack(req.mask), map(pack, req.data)), last: req.last};
   endfunction

   
   Vector#(vSz, FIFOF#(PipeT#(dSz, vSz))) stageQs <- replicateM(mkLFIFOF);

   Vector#(vSz, PipeOut#(PipeT#(dSz, vSz))) outPorts = cons(mapPipe(toPipeT, toPipeOut(reqQ)),
                                                            take(map(toPipeOut,stageQs)));
   Vector#(vSz, PipeIn#(PipeT#(dSz, vSz))) inPorts = map(toPipeIn, stageQs);
      
   
   zipWith3M(connectStage, outPorts, inPorts, genVector());
      
      
   
   Reg#(UInt#(TLog#(TAdd#(1, vSz)))) oldCnt <- mkReg(0);
         
   
   Reg#(Vector#(vSz, Tuple2#(Bool, Bit#(dSz)))) outBuf <- mkRegU;
   Reg#(Bool) flush <- mkReg(False);
         
   FIFO#(PipeT#(dSz, vSz)) compactedQ <- mkLFIFO;
   
   rule doBatch (!flush);
      PipeT#(dSz,vSz) v <- toGet(stageQs[valueOf(vSz)-1]).get;
      $display("%m, condensed beat = ", fshow(v));
      let newCnt = countElem(True, map(tpl_1, v.data));
      Vector#(TAdd#(vSz,vSz), Tuple2#(Bool, Bit#(dSz))) concataV = append(outBuf, v.data);
      
      // let rotatedV = reverse(rotateBy(reverse(concataV), newCnt));
      UInt#(TLog#(TAdd#(1, TAdd#(vSz, vSz)))) shiftSz = extend(newCnt);
      let rotatedV = shiftOutFrom0(?, concataV, shiftSz);
      
      if ( newCnt > 0 ) begin
         $display("newCnt=%d, oldCnt=%d", newCnt, oldCnt);
         $display("concatedV = ", fshow(concataV));
         $display("rotatedV = ", fshow(rotatedV));
      end
      
      outBuf <= take(rotatedV);

      
      flush <= v.last && (oldCnt + newCnt > fromInteger(vSz_int));
      
      Bool last = v.last && (oldCnt + newCnt <= fromInteger(vSz_int));
      
      oldCnt <= last? 0 : (oldCnt + newCnt)%fromInteger(vSz_int);
      
      // let outdata = reverse(rotateBy(reverse(concataV), 8-oldCnt));
      UInt#(TLog#(TAdd#(1, TAdd#(vSz, vSz)))) shiftSz2 = extend(fromInteger(vSz_int) - oldCnt);
      let outdata = shiftOutFrom0(?, concataV, shiftSz2);

      $display("v.last = %d, islast = %d", v.last, last);
      
      
      if ( oldCnt + newCnt >= fromInteger(vSz_int) || v.last ) begin
         compactedQ.enq(PipeT{data: take(outdata),
                              last: last});
      end
   endrule
   
   rule doFlush (flush);
      $display("do flush oldCnt = %d", oldCnt);
      flush <= False;
      // let outdata = reverse(rotateBy(reverse(outBuf), truncate(8-oldCnt)));
      let outdata = shiftOutFrom0(?,outBuf, fromInteger(vSz_int)-oldCnt);
      compactedQ.enq(PipeT{data: take(outdata),
                           last: True});
   endrule
   
   // FIFOF#(CompactT) outPipeQ <- mkFIFOF;
   
   rule produceCompacT;
      let v <- toGet(compactedQ).get();
      Vector#(vSz, dataT) dataV = map(unpack, map(tpl_2, v.data));
      Vector#(vSz, Bool) maskV = map(tpl_1, v.data);
      let cnt = countElem(True, maskV);
      respQ.enq(CompactResp{data: dataV,
                            itemCnt: pack(cnt),
                            last: v.last});
      
   endrule

   
   interface reqPipe = toPipeIn(reqQ);
   interface respPipe = toPipeOut(respQ);
endmodule
