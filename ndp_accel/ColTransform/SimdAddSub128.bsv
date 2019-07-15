import FIFOF::*;
import SpecialFIFOs::*;
import GetPut::*;
import Vector::*;
import SimdCommon::*;

interface SimdAddSub128;
   method Action req(Bit#(128) a, Bit#(128) b, Bool isSub, SimdMode mode);
   method Action deqResp;
   method Bool respValid;
   method Bit#(128) sum;
endinterface


function Bit#(w) add2(Bit#(w) x, Bit#(w) y);
   return x+y;
endfunction

function Bit#(w) sub2(Bit#(w) x, Bit#(w) y);
   return x-y;
endfunction
   
function Bit#(128) combSimdAddSub128(Bit#(128) a, Bit#(128) b, Bool isSub, SimdMode mode);
   Bit#(128) retval = ?;
   case (mode)
      Byte: 
      begin
         Vector#(16, Bit#(8)) sumV = zipWith(isSub?sub2:add2, unpack(a), unpack(b));
         retval = pack(sumV);                
      end                                    
      Short:                                 
      begin                                  
         Vector#(8, Bit#(16)) sumV = zipWith(isSub?sub2:add2, unpack(a), unpack(b));
         retval = pack(sumV);                
      end                                    
      Int:                                   
      begin                                  
         Vector#(4, Bit#(32)) sumV = zipWith(isSub?sub2:add2, unpack(a), unpack(b));
         retval = pack(sumV);                
      end                                    
      Long:                                  
      begin                                  
         Vector#(2, Bit#(64)) sumV = zipWith(isSub?sub2:add2, unpack(a), unpack(b));
         retval = pack(sumV);
      end
      BigInt:
      begin
         retval = isSub?a-b: a + b;
      end
   endcase
   
   return retval;
endfunction


function Bit#(TAdd#(w,1)) fa(Bit#(w) a, Bit#(w) b, Bit#(1) cin);
   return zeroExtend(a) + zeroExtend(b) + zeroExtend(cin);
endfunction

function Bit#(TAdd#(w,1)) fs(Bit#(w) a, Bit#(w) b, Bit#(1) cin) provisos(Add#(a__, 1, w));
   return zeroExtend(a)- zeroExtend(b) - zeroExtend(cin);
endfunction


function Bit#(TSub#(TAdd#(w,w),1)) cascadeAdd(Bit#(w) lo, Bit#(w) hi) provisos(Add#(1, a__, w) );
   return {hi,0} + zeroExtend(lo);
endfunction

function Bit#(TSub#(TAdd#(w,w),1)) cascadeSub(Bit#(w) lo, Bit#(w) hi) provisos(Add#(1, a__, w) );
   return {hi,0} + signExtend(lo);
endfunction


function Bit#(TSub#(TAdd#(w,w),1)) concat(Bit#(w) lo, Bit#(w) hi) provisos( Add#(1, a__, w) );
   Bit#(TSub#(w,1)) loo = truncate(lo);
   return {hi,loo};
endfunction

module mkComputeStage#(FIFOF#(Tuple4#(Vector#(n, Bit#(w)), Bool, SimdMode, Bool)) inQ,
                       FIFOF#(Tuple4#(Vector#(TDiv#(n,2), Bit#(TSub#(TAdd#(w,w),1))), Bool, SimdMode, Bool)) outQ,
                       SimdMode myMode
                       )(Empty) provisos(Add#(1, a__, w));
   rule doCompute;
      let {s_in, isSub, mode, bypass} <- toGet(inQ).get;
      
      $display(fshow(s_in), " mode = ", fshow(mode), " myMode = ", fshow(myMode));
      Vector#(TDiv#(n,2), Bit#(TSub#(TAdd#(w,w),1))) s_out = mapPairs(bypass?concat: (isSub?cascadeSub: cascadeAdd), ?, s_in);
      
      outQ.enq(tuple4(s_out, isSub, mode, bypass||mode==myMode));
   endrule
endmodule

module mkSimdAddSub128(SimdAddSub128);
   FIFOF#(Tuple4#(Vector#(16, Bit#(9)),   Bool, SimdMode, Bool)) bteResult <- mkPipelineFIFOF;
   FIFOF#(Tuple4#(Vector#(8,  Bit#(17)),  Bool, SimdMode, Bool)) shtResult <- mkPipelineFIFOF;
   FIFOF#(Tuple4#(Vector#(4,  Bit#(33)),  Bool, SimdMode, Bool)) intResult <- mkPipelineFIFOF;
   FIFOF#(Tuple4#(Vector#(2,  Bit#(65)),  Bool, SimdMode, Bool)) lngResult <- mkPipelineFIFOF;
   FIFOF#(Tuple4#(Vector#(1,  Bit#(129)), Bool, SimdMode, Bool)) bigResult <- mkPipelineFIFOF;
   
   mkComputeStage(bteResult, shtResult, Short);
   mkComputeStage(shtResult, intResult, Int);
   mkComputeStage(intResult, lngResult, Long);
   mkComputeStage(lngResult, bigResult, BigInt);

   
   method Action req(Bit#(128) a, Bit#(128) b, Bool isSub, SimdMode mode);
      Vector#(16, Bit#(8)) a_bytes = unpack(a);
      Vector#(16, Bit#(8)) b_bytes = unpack(b);
      Vector#(16, Bit#(9)) s_bytes = zipWith3(isSub?fs:fa, a_bytes, b_bytes, replicate(0));
      bteResult.enq(tuple4(s_bytes, isSub, mode, mode == Byte));
   endmethod
         
         
   method Action deqResp = bigResult.deq;
   method Bool respValid = bigResult.notEmpty;
   method Bit#(128) sum = truncate(pack(tpl_1(bigResult.first)));
endmodule
