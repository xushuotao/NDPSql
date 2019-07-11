import FIFOF::*;
import FIFO::*;
import SpecialFIFOs::*;
import Vector::*;
import Assert::*;
// import WaitAutoReset::*;

export XilinxIntDiv(..);
export mkXilinxIntDiv32;
export mkXilinxIntDiv64;

typedef `XILINX_INT_DIV_LATENCY IntDivLatency;

// import Xilinx IP core for unsigned division

// axi tuser: user tag + info needed to handle divide by 0 + sign info
typedef struct {
   Bool divByZero;
   Bit#(width) divByZeroRem; // remainder in case of divide by zero
   Bool signedDiv; // signed division (so dividend/divisor has been abs)
   Bit#(1) quotientSign; // sign bit of quotient (in case of signedDiv)
   Bit#(1) remainderSign; // sign bit of remainder (in case of signedDiv)
   Bit#(8) tag;
   } IntDivUser#(numeric type width) deriving(Bits, Eq, FShow);

interface IntDivUnsignedImport#(numeric type width);
   method Action enqDividend(Bit#(width) dividend, IntDivUser#(width) user);
   method Action enqDivisor(Bit#(width) divisor);
   method Action deqResp;
   method Bool respValid;
   method Bit#(TAdd#(width, width)) quotient_remainder;
   method IntDivUser#(width) respUser;
endinterface

import "BVI" int_div_unsigned_32 =
module mkIntDivUnsigned32Import(IntDivUnsignedImport#(32));
   default_clock clk(aclk, (*unused*) unused_gate);
   default_reset no_reset;

   method enqDividend(
      s_axis_dividend_tdata, s_axis_dividend_tuser
      ) enable(s_axis_dividend_tvalid) ready(s_axis_dividend_tready);

   method enqDivisor(
      s_axis_divisor_tdata
      ) enable(s_axis_divisor_tvalid) ready(s_axis_divisor_tready);

   method deqResp() enable(m_axis_dout_tready) ready(m_axis_dout_tvalid);
   method m_axis_dout_tvalid respValid;
   method m_axis_dout_tdata quotient_remainder ready(m_axis_dout_tvalid);
   method m_axis_dout_tuser respUser ready(m_axis_dout_tvalid);

   schedule (enqDividend) C (enqDividend);
   schedule (enqDivisor) C (enqDivisor);
   schedule (deqResp) C (deqResp);
   schedule (enqDividend) CF (enqDivisor, deqResp);
   schedule (enqDivisor) CF (deqResp);
   schedule (respValid, quotient_remainder, respUser ) CF 
      (respValid, quotient_remainder, respUser, enqDividend, enqDivisor, deqResp);
endmodule

import "BVI" int_div_unsigned_64 =
module mkIntDivUnsigned64Import(IntDivUnsignedImport#(64));
   default_clock clk(aclk, (*unused*) unused_gate);
   default_reset no_reset;

   method enqDividend(
      s_axis_dividend_tdata, s_axis_dividend_tuser
      ) enable(s_axis_dividend_tvalid) ready(s_axis_dividend_tready);

   method enqDivisor(
      s_axis_divisor_tdata
      ) enable(s_axis_divisor_tvalid) ready(s_axis_divisor_tready);

   method deqResp() enable(m_axis_dout_tready) ready(m_axis_dout_tvalid);
   method m_axis_dout_tvalid respValid;
   method m_axis_dout_tdata quotient_remainder ready(m_axis_dout_tvalid);
   method m_axis_dout_tuser respUser ready(m_axis_dout_tvalid);

   schedule (enqDividend) C (enqDividend);
   schedule (enqDivisor) C (enqDivisor);
   schedule (deqResp) C (deqResp);
   schedule (enqDividend) CF (enqDivisor, deqResp);
   schedule (enqDivisor) CF (deqResp);
   schedule (respValid, quotient_remainder, respUser ) CF 
      (respValid, quotient_remainder, respUser, enqDividend, enqDivisor, deqResp);
endmodule


// simulation
module mkIntDivUnsignedSim(IntDivUnsignedImport#(w)) provisos (Add#(w,w,w2));
   FIFO#(Tuple2#(Bit#(w), IntDivUser#(w))) dividendQ <- mkBypassFIFO;
   FIFO#(Bit#(w)) divisorQ <- mkBypassFIFO;
   
   
   Vector#(IntDivLatency, FIFOF#(Tuple2#(Bit#(w2), IntDivUser#(w)))) respQs <- replicateM(mkPipelineFIFOF);

   rule compute;
      dividendQ.deq;
      divisorQ.deq;
      let {dividend, user} = dividendQ.first;
      let divisor = divisorQ.first;

      UInt#(w) a = unpack(dividend);
      UInt#(w) b = unpack(divisor);
      Bit#(w) q = pack(a / b);
      Bit#(w) r = pack(a % b);
      respQs[0].enq(tuple2({q, r}, user));
   endrule
      
   for (Integer i = 0; i < valueOf(IntDivLatency) - 1; i = i + 1 ) begin
      rule doConn;
         let v = respQs[i].first;
         respQs[i].deq;
         respQs[i+1].enq(v);
      endrule
   end

   method Action enqDividend(Bit#(w) dividend, IntDivUser#(w) user);
      dividendQ.enq(tuple2(dividend, user));
   endmethod

   method Action enqDivisor(Bit#(w) divisor);
      divisorQ.enq(divisor);
   endmethod

   method Action deqResp;
      last(respQs).deq;
   endmethod

   method respValid = last(respQs).notEmpty;

   method quotient_remainder = tpl_1(last(respQs).first);

   method respUser = tpl_2(last(respQs).first);
endmodule


// Wrapper for user (add reset guard, check overflow/divided by 0).  We cannot
// unify two dividers to one, because divider latency may not be a constant.
interface XilinxIntDiv#(type tagT, numeric type width);
   method Action req(Bit#(width) dividend, Bit#(width) divisor, Bool signedDiv, tagT tag);
   // response
   method Action deqResp;
   method Bool respValid;
   method Bit#(width) quotient;
   method Bit#(width) remainder;
   method tagT respTag;
endinterface

module mkXilinxIntDiv64(XilinxIntDiv#(tagT, w)) provisos (
   Bits#(tagT, tagSz), Add#(tagSz, a__, 8), Add#(w, w, w2),
   Add#(w, 0, 64)
   );
   `ifdef BSIM
   IntDivUnsignedImport#(w) divIfc <- mkIntDivUnsignedSim;
   `else
   IntDivUnsignedImport#(w) divIfc <- mkIntDivUnsigned64Import;
   `endif
   // WaitAutoReset#(4) init <- mkWaitAutoReset;

   method Action req(Bit#(w) dividend, Bit#(w) divisor, Bool signedDiv, tagT tag);// if(init.isReady);
      // compute the input ops to div unsigned IP
      Bit#(1) dividend_sign = msb(dividend);
      Bit#(1) divisor_sign = msb(divisor);
      Bit#(w) a = dividend;
      Bit#(w) b = divisor;
      if(signedDiv) begin
         if(dividend_sign == 1) begin
            a = 0 - dividend;
         end
         if(divisor_sign == 1) begin
            b = 0 - divisor;
         end
      end
      // get the user struct (sign/divide by 0)
      IntDivUser#(w) user = IntDivUser {
         divByZero: divisor == 0,
         divByZeroRem: dividend,
         signedDiv: signedDiv,
         // quotient negative when dividend and divisor have different signs
         quotientSign: dividend_sign ^ divisor_sign,
         // remainder sign follows that of dividend
         remainderSign: dividend_sign,
         tag: zeroExtend(pack(tag))
         };
      divIfc.enqDividend(a, user);
      divIfc.enqDivisor(b);
   endmethod

   // we also put reset guard on deq port to prevent random signals before
   // reset from dequing or corrupting axi states
   method Action deqResp;// if(init.isReady);
      divIfc.deqResp;
   endmethod

   method respValid = divIfc.respValid;// && init.isReady;
   
   method Bit#(w) quotient;// if(init.isReady);
      let user = divIfc.respUser;
      Bit#(w) q;
      if(user.divByZero) begin
         q = maxBound;
      end
      else begin
         q = truncateLSB(divIfc.quotient_remainder);
         if(user.signedDiv && user.quotientSign == 1) begin
            q = 0 - q;
         end
         // signed overflow is automatically handled
      end
      return q;
   endmethod
   
   method Bit#(w) remainder;// if(init.isReady);
      let user = divIfc.respUser;
      Bit#(w) r;
      if(user.divByZero) begin
         r = user.divByZeroRem;
      end
      else begin
         r = truncate(divIfc.quotient_remainder);
         if(user.signedDiv && user.remainderSign == 1) begin
            r = 0 - r;
         end
         // signed overflow is automatically handled
      end
      return r;
   endmethod 

   method tagT respTag;// if(init.isReady);
      return unpack(truncate(divIfc.respUser.tag));
   endmethod
endmodule

module mkXilinxIntDiv32(XilinxIntDiv#(tagT, w)) provisos (
   Bits#(tagT, tagSz), Add#(tagSz, a__, 8), Add#(w, w, w2),
   Add#(w, 0, 32)
   );
   `ifdef BSIM
   IntDivUnsignedImport#(w) divIfc <- mkIntDivUnsignedSim;
   `else
   IntDivUnsignedImport#(w) divIfc <- mkIntDivUnsigned32Import;
   `endif
   // WaitAutoReset#(4) init <- mkWaitAutoReset;

   method Action req(Bit#(w) dividend, Bit#(w) divisor, Bool signedDiv, tagT tag);// if(init.isReady);
      // compute the input ops to div unsigned IP
      Bit#(1) dividend_sign = msb(dividend);
      Bit#(1) divisor_sign = msb(divisor);
      Bit#(w) a = dividend;
      Bit#(w) b = divisor;
      if(signedDiv) begin
         if(dividend_sign == 1) begin
            a = 0 - dividend;
         end
         if(divisor_sign == 1) begin
            b = 0 - divisor;
         end
      end
      // get the user struct (sign/divide by 0)
      IntDivUser#(w) user = IntDivUser {
         divByZero: divisor == 0,
         divByZeroRem: dividend,
         signedDiv: signedDiv,
         // quotient negative when dividend and divisor have different signs
         quotientSign: dividend_sign ^ divisor_sign,
         // remainder sign follows that of dividend
         remainderSign: dividend_sign,
         tag: zeroExtend(pack(tag))
         };
      divIfc.enqDividend(a, user);
      divIfc.enqDivisor(b);
   endmethod

   // we also put reset guard on deq port to prevent random signals before
   // reset from dequing or corrupting axi states
   method Action deqResp;// if(init.isReady);
      divIfc.deqResp;
   endmethod

   method respValid = divIfc.respValid;// && init.isReady;
   
   method Bit#(w) quotient;// if(init.isReady);
      let user = divIfc.respUser;
      Bit#(w) q;
      if(user.divByZero) begin
         q = maxBound;
      end
      else begin
         q = truncateLSB(divIfc.quotient_remainder);
         if(user.signedDiv && user.quotientSign == 1) begin
            q = 0 - q;
         end
         // signed overflow is automatically handled
      end
      return q;
   endmethod
   
   method Bit#(w) remainder;// if(init.isReady);
      let user = divIfc.respUser;
      Bit#(w) r;
      if(user.divByZero) begin
         r = user.divByZeroRem;
      end
      else begin
         r = truncate(divIfc.quotient_remainder);
         if(user.signedDiv && user.remainderSign == 1) begin
            r = 0 - r;
         end
         // signed overflow is automatically handled
      end
      return r;
   endmethod 

   method tagT respTag;// if(init.isReady);
      return unpack(truncate(divIfc.respUser.tag));
   endmethod
endmodule

