import FIFOF::*;
import SpecialFIFOs::*;
import GetPut::*;
import Vector::*;

typedef enum{Byte, Short, Int, Long, BigInt} SimdAddMode deriving (Bits, Eq, FShow);

interface SimdAdd128;
   method Action req(Bit#(128) a, Bit#(128) b, SimdAddMode mode);
   method Action deqResp;
   method Bool respValid;
   method Bit#(128) sum;
endinterface


function Bit#(w) add2(Bit#(w) x, Bit#(w) y);
   return x+y;
endfunction
   
function Bit#(128) combSimdAdd128(Bit#(128) a, Bit#(128) b, SimdAddMode mode);
   Bit#(128) retval = ?;
   case (mode)
      Byte: 
      begin
         Vector#(16, Bit#(8)) sumV = zipWith(add2, unpack(a), unpack(b));
         retval = pack(sumV);
      end
      Short:
      begin
         Vector#(8, Bit#(16)) sumV = zipWith(add2, unpack(a), unpack(b));
         retval = pack(sumV);
      end
      Int:
      begin
         Vector#(4, Bit#(32)) sumV = zipWith(add2, unpack(a), unpack(b));
         retval = pack(sumV);
      end
      Long:
      begin
         Vector#(2, Bit#(64)) sumV = zipWith(add2, unpack(a), unpack(b));
         retval = pack(sumV);
      end
      BigInt:
      begin
         retval = a + b;
      end
   endcase
   
   return retval;
endfunction


function Bit#(TAdd#(w,1)) fa(Bit#(w) a, Bit#(w) b, Bit#(1) cin);
   return zeroExtend(a) + zeroExtend(b) + zeroExtend(cin);
endfunction

function Bit#(TSub#(TAdd#(w,w),1)) cascade(Bit#(w) lo, Bit#(w) hi) provisos(Add#(1, a__, w) );
   return {hi,0} + {0,lo};
endfunction

function Bit#(TSub#(TAdd#(w,w),1)) concat(Bit#(w) lo, Bit#(w) hi) provisos( Add#(1, a__, w) );
   Bit#(TSub#(w,1)) loo = truncate(lo);
   return {hi,loo};
endfunction

module mkComputeStage#(FIFOF#(Tuple3#(Vector#(n, Bit#(w)), SimdAddMode, Bool)) inQ,
                       FIFOF#(Tuple3#(Vector#(TDiv#(n,2), Bit#(TSub#(TAdd#(w,w),1))), SimdAddMode, Bool)) outQ,
                       SimdAddMode myMode
                       )(Empty) provisos(Add#(1, a__, w));
   rule doCompute;
      let {s_in, mode, bypass} <- toGet(inQ).get;
      
      // $display(fshow(s_in), " mode = ", fshow(mode), " myMode = ", fshow(myMode));
      Vector#(TDiv#(n,2), Bit#(TSub#(TAdd#(w,w),1))) s_out = mapPairs(bypass?concat:cascade, ?, s_in);
      
      outQ.enq(tuple3(s_out,mode, bypass||mode==myMode));
   endrule
endmodule

module mkSimdAdd128(SimdAdd128);
   FIFOF#(Tuple3#(Vector#(16, Bit#(9)),   SimdAddMode, Bool)) bteResult <- mkPipelineFIFOF;
   FIFOF#(Tuple3#(Vector#(8,  Bit#(17)),  SimdAddMode, Bool)) shtResult <- mkPipelineFIFOF;
   FIFOF#(Tuple3#(Vector#(4,  Bit#(33)),  SimdAddMode, Bool)) intResult <- mkPipelineFIFOF;
   FIFOF#(Tuple3#(Vector#(2,  Bit#(65)),  SimdAddMode, Bool)) lngResult <- mkPipelineFIFOF;
   FIFOF#(Tuple3#(Vector#(1,  Bit#(129)), SimdAddMode, Bool)) bigResult <- mkPipelineFIFOF;
   
   mkComputeStage(bteResult, shtResult, Short);
   mkComputeStage(shtResult, intResult, Int);
   mkComputeStage(intResult, lngResult, Long);
   mkComputeStage(lngResult, bigResult, BigInt);

   
   method Action req(Bit#(128) a, Bit#(128) b, SimdAddMode mode);
      Vector#(16, Bit#(8)) a_bytes = unpack(a);
      Vector#(16, Bit#(8)) b_bytes = unpack(b);
      Vector#(16, Bit#(9)) s_bytes = zipWith3(fa, a_bytes, b_bytes, replicate(0));
      bteResult.enq(tuple3(s_bytes, mode, mode == Byte));
   endmethod
         
         
   method Action deqResp = bigResult.deq;
   method Bool respValid = bigResult.notEmpty;
   method Bit#(128) sum = truncate(pack(tpl_1(bigResult.first)));
endmodule
