import PECommon::*;
import Vector::*;
import FIFO::*;
import GetPut::*;

function Bool unsignedTest(Bit#(64) in,  Bit#(64) lv, Bit#(64) hv);
   return in >= lv && in <= hv;
endfunction
   
function Bool signedTest(Bit#(64) in,  Bit#(64) lv, Bit#(64) hv);
   return signedLE(lv,in) && signedLE(in,hv);
endfunction


function Bit#(w) add2(Bit#(w) a, Bit#(w) b);
   return a + b;
endfunction

function Bit#(w) and2(Bit#(w) a, Bit#(w) b);
   return a&b;
endfunction

function Bool booland2(Bool a, Bool b);
   return a&&b;
endfunction


function Vector#(8, Tuple2#(Bool, Bit#(64))) evalPred(Vector#(8, Bit#(64)) inV, Bit#(8) mask, Bit#(64) lv, Bit#(64) hv, Bool isSigned, Bit#(64) offset);
   Vector#(8, Bit#(64)) lvVec = replicate(lv);
   Vector#(8, Bit#(64)) hvVec = replicate(hv);
   Vector#(8, Bit#(64)) ptrs = zipWith(add2, replicate(offset), genWith(fromInteger));
   
   if (isSigned)
      return zipWith(tuple2, zipWith(booland2, unpack(mask), zipWith3(signedTest, inV,  lvVec, hvVec)), ptrs);
   else
      return zipWith(tuple2, zipWith(booland2, unpack(mask), zipWith3(unsignedTest, inV,  lvVec, hvVec)), ptrs);
endfunction

function Vector#(8, Tuple2#(Bool, Bit#(w))) evenCompact(Vector#(8, Tuple2#(Bool, Bit#(w))) inV);
   for ( Integer i = 0; i < 8; i = i + 2) begin
      if ( tpl_1(inV[i]) == False) begin
         inV[i] = inV[i+1];
         inV[i+1] = tuple2(False, ?);
      end
   end
   return inV;
endfunction

function Vector#(8, Tuple2#(Bool, Bit#(w))) oddCompact(Vector#(8, Tuple2#(Bool, Bit#(w))) inV);
   for ( Integer i = 1; i < 7; i = i + 2) begin
      if ( tpl_1(inV[i]) == False) begin
         inV[i] = inV[i+1];
         inV[i+1] = tuple2(False, ?);
      end
   end
   return inV;
endfunction

// FIFO#(Vector#(8, Bit#(64))) inQ <- mkFIFO;
// rule doSer32; //32*8 = 256
//    let v <- ser32.get;
//    inQ.enq(v);
// endrule

// rule doSer64;
//    let v <- ser64.get;
//    inQ.enq(v);
// endrule

typedef struct{
   Vector#(8, Tuple2#(Bool, Bit#(64))) data;
   Bool last;
   } PipeT deriving (Bits, Eq, FShow);


module mkSelectFilter(SingleStreamIfc);
   
   Reg#(Bit#(64)) ptrOffset <- mkReg(0);
   Reg#(Bit#(64)) loBound <- mkRegU;
   Reg#(Bit#(64)) hiBound <- mkRegU;
   Reg#(Bool) isSigned <- mkRegU;
   
   // FIFO#(Vector#(8, Tuple2#(Bool, Bit#(64)))) evalResultQ <- mkFIFO;
   // Vector#(8, FIFO#(Vector#(8, Tuple2#(Bool, Bit#(64))))) stageQs <- replicateM(mkFIFO);
   FIFO#(PipeT) evalResultQ <- mkFIFO;
   Vector#(8, FIFO#(PipeT)) stageQs <- replicateM(mkFIFO);

   FIFO#(FlitT) outQ <- mkFIFO;
   
   rule doCompactL0;
      let v <- toGet(evalResultQ).get;
      stageQs[0].enq(PipeT{data:evenCompact(v.data),last:v.last});
   endrule
   
   for (Integer i = 1 ; i < 8 ; i = i + 1) begin
      rule connectL;
         let in <- toGet(stageQs[i-1]).get;
         if ( i % 2 == 0)
            stageQs[i].enq(PipeT{data:evenCompact(in.data),last:in.last});
         else
            stageQs[i].enq(PipeT{data:oddCompact(in.data),last:in.last});
      endrule
   end
   
   Reg#(UInt#(4)) oldCnt <- mkReg(0);
   
   Reg#(Vector#(8, Tuple2#(Bool, Bit#(64)))) outBuf <- mkRegU;
   Reg#(Bool) flush <- mkReg(False);
   rule doBatch (!flush);
      let v <- toGet(stageQs[7]).get;
      // $display(fshow(v));
      let newCnt = countElem(True, map(tpl_1, v.data));

      Vector#(16, Tuple2#(Bool, Bit#(64))) concataV = append(outBuf, v.data);
      
      // let rotatedV = reverse(rotateBy(reverse(concataV), newCnt));
      UInt#(5) shiftSz = extend(newCnt);
      let rotatedV = shiftOutFrom0(?, concataV, shiftSz);
      
      if ( newCnt > 0 ) begin
         $display("newCnt=%d, oldCnt=%d", newCnt, oldCnt);
         $display("concatedV = ", fshow(concataV));
         $display("rotatedV = ", fshow(rotatedV));
      end
      
      outBuf <= take(rotatedV);

      
      flush <= v.last && (oldCnt + newCnt > 8);
      
      Bool last = v.last && (oldCnt + newCnt <= 8);
      
      oldCnt <= last? 0 : (oldCnt + newCnt)%8;
      
      // let outdata = reverse(rotateBy(reverse(concataV), 8-oldCnt));
      UInt#(5) shiftSz2 = extend(8-oldCnt);
      let outdata = shiftOutFrom0(?, concataV, shiftSz2);
      
      $display("v.last = %d, islast = %d", v.last, last);
      
      if ( oldCnt + newCnt >= 8 || v.last ) begin
         outQ.enq(FlitT{data:take(map(tpl_2, outdata)),
                        mask: pack(take(map(tpl_1, outdata))),
                        last: last});
      end
   endrule
   
   rule doFlush (flush);
      
      $display("do flush oldCnt = %d", oldCnt);
      flush <= False;
      // let outdata = reverse(rotateBy(reverse(outBuf), truncate(8-oldCnt)));
      let outdata = shiftOutFrom0(?,outBuf, 8-oldCnt);
      outQ.enq(FlitT{data:take(map(tpl_2, outdata)),
                     mask: pack(take(map(tpl_1, outdata))),
                     last: True});
   endrule
   
   method Action configure(Vector#(8, Bit#(64)) para);
      loBound <= para[0];
      hiBound <= para[1];
      isSigned <= unpack(para[2][0]);
   endmethod
   
   method Action put(FlitT v);
      ptrOffset <= ptrOffset + 8;
      evalResultQ.enq(PipeT{data:evalPred(v.data, v.mask, loBound, hiBound, isSigned, ptrOffset),
                            last:v.last}
                      );
   endmethod

   
   method ActionValue#(FlitT) get();
      let v <- toGet(outQ).get;
      return v;
   endmethod

endmodule
