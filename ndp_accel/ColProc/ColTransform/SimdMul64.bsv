import XilinxIntMul::*;
import Vector::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;

typedef `XILINX_INT_MUL_LATENCY XilinxIntMulLatency;

typedef TAdd#(XilinxIntMulLatency,1) IntMulLatency;

interface SimdMul64;
   method Action req(Bit#(64) a, Bit#(64) b, Bit#(1) mode, Bool mullo, Bool isSigned);
   method Action deqResp;
   method Bool respValid;
   method Bit#(128) product;
   
endinterface
                 
function Bit#(TAdd#(n,n)) multiply_unsigned( Bit#(n) a, Bit#(n) b );
    UInt#(n) a_uint = unpack(a);
    UInt#(n) b_uint = unpack(b);
    UInt#(TAdd#(n,n)) product_uint = zeroExtend(a_uint) * zeroExtend(b_uint);
    return pack( product_uint );
endfunction
                 
function Bit#(TAdd#(n,n)) multiply_signed( Bit#(n) a, Bit#(n) b );
    Int#(n) a_int = unpack(a);
    Int#(n) b_int = unpack(b);
    Int#(TAdd#(n,n)) product_int = signExtend(a_int) * signExtend(b_int);
    return pack( product_int );
endfunction


function Bit#(128) combSimdMul64(Bit#(64) a, Bit#(64) b, Bit#(1) mode, Bool mullo, Bool isSigned);
   Bit#(128) retval = ?;
   case (mode)
      0:
      begin
         Vector#(2, Bit#(32)) aVec = unpack(a);
         Vector#(2, Bit#(32)) bVec = unpack(b);
         retval = pack(zipWith(isSigned?multiply_signed:multiply_unsigned, aVec, bVec));
      end
      1:
      begin
         retval = isSigned ? multiply_signed(a,b):multiply_unsigned(a,b);
      end
   endcase
   
   if ( mode == 0 && mullo) begin
      Vector#(2,Bit#(64)) retvalV = unpack(retval);
      Vector#(2,Bit#(32)) retvalV_truc = map(truncate, retvalV);
      retval = zeroExtend(pack(retvalV_truc));
   end
   return retval;
endfunction

(* synthesize *)
module mkSimdMul64(SimdMul64);
   Vector#(4, XilinxIntMul#(void, 32)) muls <- replicateM(mkXilinxIntMulUnified32);
   
   FIFO#(Tuple3#(Bit#(1),Bool,Bool)) modeQ <- mkSizedFIFO(valueOf(IntMulLatency)+1);
   
   function Bool mulIsReady(XilinxIntMul#(t, w) mul) = mul.respValid;
   
   FIFOF#(Bit#(128)) respQ <- mkPipelineFIFOF;
   
   rule constructResult if ( all(mulIsReady, muls) );
      muls[0].deqResp;
      muls[1].deqResp;
      muls[2].deqResp;
      muls[3].deqResp;
      
      modeQ.deq;
      
      Bit#(64) pp00 = muls[0].product;
      Bit#(64) pp01 = muls[1].product;
      Bit#(64) pp10 = muls[2].product;
      Bit#(64) pp11 = muls[3].product;
      
      // $display("pp00 = %b", pp00);
      // $display("pp01 = %b", pp01);
      // $display("pp10 = %b", pp10);
      // $display("pp11 = %b", pp11);
      
      let {mode, isSigned, mullo} = modeQ.first;
      
      Bit#(128) resp = {pp11,pp00};
      
      if ( mode == 1 ) begin
         if ( isSigned )
            resp = resp + (signExtend(pp10)<<32) + (signExtend(pp01)<<32);
         else
            resp = resp + (zeroExtend(pp10)<<32) + (zeroExtend(pp01)<<32);
      end
      
      if ( mullo && mode == 0 ) begin
         respQ.enq({?, pp11[31:0], pp00[31:0]});
      end
      else begin
         respQ.enq(resp);
      end
   endrule
   
   method Action req(Bit#(64) a, Bit#(64) b, Bit#(1) mode, Bool mullo, Bool isSigned);
      Bit#(32) a0 = truncate(a);
      Bit#(32) a1 = truncateLSB(a);
   
      Bit#(32) b0 = truncate(b);
      Bit#(32) b1 = truncateLSB(b);

      muls[0].req(a0,b0,mode==0&&isSigned? Signed: Unsigned ,?);
      muls[1].req(b1,a0,isSigned? SignedUnsigned: Unsigned,?);
      muls[2].req(a1,b0,isSigned? SignedUnsigned: Unsigned,?);
      muls[3].req(a1,b1,isSigned? Signed: Unsigned,?);
      
      modeQ.enq(tuple3(mode,isSigned, mullo));
   endmethod
   
   method Action deqResp = respQ.deq;
   method Bool respValid = respQ.notEmpty;
   method Bit#(128) product = respQ.first;
   
endmodule
