import Vector::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Assert::*;

export XilinxIntMulSign(..);
export XilinxIntMul(..);
export mkXilinxIntMul32;
export mkXilinxIntMulUnified32;
export mkXilinxIntMul64;
export mkXilinxIntMulUnified64;

// Xilinx int multiplier IP is a rigorous pipeline with a fixed latency. There
// is no back pressure in the raw IP. We will wrap it with flow control. To do
// this, we need to know the pipeline latency from macro
// XILINX_INT_MUL_LATENCY.

typedef `XILINX_INT_MUL_LATENCY IntMulLatency;

interface IntMulImport#(numeric type width);
   method Action req(Bit#(width) a, Bit#(width) b);
   method Bit#(TAdd#(width,width)) product;
endinterface

import "BVI" int_mul_signed_32 =
module mkIntMulSigned32Import(IntMulImport#(32));
   default_clock clk(CLK, (*unused*) unused_gate);
   default_reset no_reset;

   method req(A, B) enable((*inhigh*) EN);
   method P product;

   schedule (req) C (req);
   schedule (product) CF (req, product);
endmodule

import "BVI" int_mul_unsigned_32 =
module mkIntMulUnsigned32Import(IntMulImport#(32));
   default_clock clk(CLK, (*unused*) unused_gate);
   default_reset no_reset;

   method req(A, B) enable((*inhigh*) EN);
   method P product;

   schedule (req) C (req);
   schedule (product) CF (req, product);
endmodule

import "BVI" int_mul_signed_unsigned_32 =
module mkIntMulSignedUnsigned32Import(IntMulImport#(32));
   default_clock clk(CLK, (*unused*) unused_gate);
   default_reset no_reset;

   method req(A, B) enable((*inhigh*) EN);
   method P product;

   schedule (req) C (req);
   schedule (product) CF (req, product);
endmodule

import "BVI" int_mul_signed_64 =
module mkIntMulSigned64Import(IntMulImport#(64));
   default_clock clk(CLK, (*unused*) unused_gate);
   default_reset no_reset;

   method req(A, B) enable((*inhigh*) EN);
   method P product;

   schedule (req) C (req);
   schedule (product) CF (req, product);
endmodule

import "BVI" int_mul_unsigned_64 =
module mkIntMulUnsigned64Import(IntMulImport#(64));
   default_clock clk(CLK, (*unused*) unused_gate);
   default_reset no_reset;

   method req(A, B) enable((*inhigh*) EN);
   method P product;

   schedule (req) C (req);
   schedule (product) CF (req, product);
endmodule

import "BVI" int_mul_signed_unsigned_64 =
module mkIntMulSignedUnsigned64Import(IntMulImport#(64));
   default_clock clk(CLK, (*unused*) unused_gate);
   default_reset no_reset;

   method req(A, B) enable((*inhigh*) EN);
   method P product;

   schedule (req) C (req);
   schedule (product) CF (req, product);
endmodule


// mul req type
typedef enum {
   Signed,
   Unsigned,
   SignedUnsigned
   } XilinxIntMulSign deriving(Bits, Eq, FShow);

// simulation
module mkIntMulSim#(XilinxIntMulSign sign)(IntMulImport#(w)) provisos (
   Add#(w,w,w2));
   RWire#(Bit#(w2)) newReq <- mkRWire;
   Vector#(IntMulLatency, Reg#(Maybe#(Bit#(w2)))) pipe <- replicateM(mkReg(Invalid));

   (* fire_when_enabled, no_implicit_conditions *)
   rule canon;
      for(Integer i = 1; i < valueof(IntMulLatency); i = i+1) begin
         pipe[i] <= pipe[i - 1];
      end
      pipe[0] <= newReq.wget;
   endrule

   method Action req(Bit#(w) a, Bit#(w) b);
      // $display("%m, latency = %d", valueOf(IntMulLatency));
      Int#(w2) op1 = (case(sign)
         Signed, SignedUnsigned: (unpack(signExtend(a)));
         default: (unpack(zeroExtend(a)));
         endcase);
      Int#(w2) op2 = (case(sign)
         Signed: (unpack(signExtend(b)));
         default: (unpack(zeroExtend(b)));
         endcase);
      Int#(w2) prod = op1 * op2;
      newReq.wset(pack(prod));
   endmethod

   method Bit#(w2) product = fromMaybe(?, pipe[valueof(IntMulLatency) - 1]);
endmodule

// wrap up all mul IPs to have back pressure
interface XilinxIntMul#(type tagT, numeric type width);
   method Action req(Bit#(width) a, Bit#(width) b, XilinxIntMulSign sign, tagT tag);
   method Action deqResp;
   method Bool respValid;
   method Bit#(TAdd#(width,width)) product;
   method tagT respTag;
endinterface

module mkXilinxIntMul64(XilinxIntMul#(tagT, w)) provisos(
   Bits#(tagT, tagSz),
   Add#(w, w, w2),
   Add#(w, 0, 64),
   // credit based flow control types
   NumAlias#(TAdd#(IntMulLatency, 2), maxCredit),
   // NumAlias#(IntMulLatency, maxCredit),
   Alias#(Bit#(TLog#(TAdd#(maxCredit, 1))), creditT)
   );
   // different multilpliers: WaitAutoReset is not needed, since mul is a
   // pipeline with fixed latency
   `ifdef BSIM
   IntMulImport#(w) mulSigned <- mkIntMulSim(Signed);
   IntMulImport#(w) mulUnsigned <- mkIntMulSim(Unsigned);
   IntMulImport#(w) mulSignedUnsigned <- mkIntMulSim(SignedUnsigned);
   `else
   IntMulImport#(w) mulSigned <- mkIntMulSigned64Import;
   IntMulImport#(w) mulUnsigned <- mkIntMulUnsigned64Import;
   IntMulImport#(w) mulSignedUnsigned <- mkIntMulSignedUnsigned64Import;
   `endif

   // resp FIFO (unguarded) & flow ctrl credit
   FIFOF#(Tuple2#(Bit#(w2), tagT)) respQ <- mkUGSizedFIFOF(valueof(maxCredit));
   Reg#(creditT) credit <- mkReg(fromInteger(valueof(maxCredit)));

   // shift regs for sign + tag
   Vector#(IntMulLatency, Reg#(Maybe#(Tuple2#(XilinxIntMulSign, tagT)))) pipe <- replicateM(mkReg(Invalid));

   // wire to catch input req
   RWire#(Tuple2#(XilinxIntMulSign, tagT)) newReq <- mkRWire;

   // wire to catch deq
   PulseWire deqEn <- mkPulseWire;

   (* fire_when_enabled, no_implicit_conditions *)
   rule canon;
      creditT nextCredit = credit;
      // incr credit if resp FIFO is deq
      if(deqEn) begin
         if(nextCredit >= fromInteger(valueof(maxCredit))) begin
            $fdisplay(stderr, "\n%m: ASSERT FAIL!!");
            dynamicAssert(False, "credit overflow");
         end
         nextCredit = nextCredit + 1;
      end
      // enq resp FIFO if something is outputed from mul
      if ( pipe[valueof(IntMulLatency) - 1] matches tagged Valid {.sign, .tag} ) begin
         Bit#(w2) prod = (case(sign)
                             Signed: (mulSigned.product);
                             Unsigned: (mulUnsigned.product);
                             SignedUnsigned: (mulSignedUnsigned.product);
                             default: (?);
                          endcase);
         respQ.enq(tuple2(prod, tag));
      end
      // shift pipe regs
      for(Integer i = 1; i < valueof(IntMulLatency); i = i+1) begin
         pipe[i] <= pipe[i - 1];
      end
      pipe[0] <= newReq.wget;
      // decr credit if new req is taken
      if(isValid(newReq.wget)) begin
         if(nextCredit == 0) begin
            $fdisplay(stderr, "\n%m: ASSERT FAIL!!");
            dynamicAssert(False, "credit underflow");
         end
         nextCredit = nextCredit - 1;
         $display("(%m) nextCredit = %d", nextCredit);
      end
      // update credit
      credit <= nextCredit;
   endrule

   method Action req(Bit#(w) a, Bit#(w) b,
                     XilinxIntMulSign sign, tagT tag) if(credit > 0);
      case(sign)
         Signed: mulSigned.req(a, b);
         Unsigned: mulUnsigned.req(a, b);
         SignedUnsigned: mulSignedUnsigned.req(a, b);
      endcase
      newReq.wset(tuple2(sign, tag)); // notify new req
   endmethod

   method Action deqResp if(respQ.notEmpty);
      respQ.deq;
      deqEn.send; // notify deq resp
   endmethod

   method respValid = respQ.notEmpty;

   method Bit#(w2) product if(respQ.notEmpty);
      return tpl_1(respQ.first);
   endmethod

   method tagT respTag if(respQ.notEmpty);
      return tpl_2(respQ.first);
   endmethod
endmodule

module mkXilinxIntMul32(XilinxIntMul#(tagT, w)) provisos(
   Bits#(tagT, tagSz),
   Add#(w, w, w2),
   Add#(w, 0, 32),
   // credit based flow control types
   NumAlias#(TAdd#(IntMulLatency, 2), maxCredit),
   Alias#(Bit#(TLog#(TAdd#(maxCredit, 1))), creditT)
   );
   // different multilpliers: WaitAutoReset is not needed, since mul is a
   // pipeline with fixed latency
   `ifdef BSIM
   IntMulImport#(w) mulSigned <- mkIntMulSim(Signed);
   IntMulImport#(w) mulUnsigned <- mkIntMulSim(Unsigned);
   IntMulImport#(w) mulSignedUnsigned <- mkIntMulSim(SignedUnsigned);
   `else
   IntMulImport#(w) mulSigned <- mkIntMulSigned32Import;
   IntMulImport#(w) mulUnsigned <- mkIntMulUnsigned32Import;
   IntMulImport#(w) mulSignedUnsigned <- mkIntMulSignedUnsigned32Import;
   `endif

   // resp FIFO (unguarded) & flow ctrl credit
   FIFOF#(Tuple2#(Bit#(w2), tagT)) respQ <- mkUGSizedFIFOF(valueof(maxCredit));
   Reg#(creditT) credit <- mkReg(fromInteger(valueof(maxCredit)));

   // shift regs for sign + tag
   Vector#(IntMulLatency, Reg#(Maybe#(Tuple2#(XilinxIntMulSign, tagT)))) pipe <- replicateM(mkReg(Invalid));

   // wire to catch input req
   RWire#(Tuple2#(XilinxIntMulSign, tagT)) newReq <- mkRWire;

   // wire to catch deq
   PulseWire deqEn <- mkPulseWire;

   (* fire_when_enabled, no_implicit_conditions *)
   rule canon;
      creditT nextCredit = credit;
      // incr credit if resp FIFO is deq
      if(deqEn) begin
         if(nextCredit >= fromInteger(valueof(maxCredit))) begin
            $fdisplay(stderr, "\n%m: ASSERT FAIL!!");
            dynamicAssert(False, "credit overflow");
         end
         nextCredit = nextCredit + 1;
      end
      // enq resp FIFO if something is outputed from mul
      if ( pipe[valueof(IntMulLatency) - 1] matches tagged Valid {.sign, .tag} ) begin
         Bit#(w2) prod = (case(sign)
                             Signed: (mulSigned.product);
                             Unsigned: (mulUnsigned.product);
                             SignedUnsigned: (mulSignedUnsigned.product);
                             default: (?);
                          endcase);
         respQ.enq(tuple2(prod, tag));
      end
      // shift pipe regs
      for(Integer i = 1; i < valueof(IntMulLatency); i = i+1) begin
         pipe[i] <= pipe[i - 1];
      end
      pipe[0] <= newReq.wget;
      // decr credit if new req is taken
      if(isValid(newReq.wget)) begin
         if(nextCredit == 0) begin
            $fdisplay(stderr, "\n%m: ASSERT FAIL!!");
            dynamicAssert(False, "credit underflow");
         end
         nextCredit = nextCredit - 1;
      end
      // update credit
      credit <= nextCredit;
   endrule

   method Action req(Bit#(w) a, Bit#(w) b,
                     XilinxIntMulSign sign, tagT tag) if(credit > 0);
      case(sign)
         Signed: mulSigned.req(a, b);
         Unsigned: mulUnsigned.req(a, b);
         SignedUnsigned: mulSignedUnsigned.req(a, b);
      endcase
      newReq.wset(tuple2(sign, tag)); // notify new req
   endmethod

   method Action deqResp if(respQ.notEmpty);
      respQ.deq;
      deqEn.send; // notify deq resp
   endmethod

   method respValid = respQ.notEmpty;

   method Bit#(w2) product if(respQ.notEmpty);
      return tpl_1(respQ.first);
   endmethod

   method tagT respTag if(respQ.notEmpty);
      return tpl_2(respQ.first);
   endmethod
endmodule

module mkXilinxIntMulUnified32(XilinxIntMul#(tagT, w)) provisos(
   Bits#(tagT, tagSz),
   Add#(w, w, w2),
   Add#(w, 0, 32),
   // credit based flow control types
   NumAlias#(TAdd#(IntMulLatency, 2), maxCredit),
   Alias#(Bit#(TLog#(TAdd#(maxCredit, 1))), creditT)
   );
   // different multilpliers: WaitAutoReset is not needed, since mul is a
   // pipeline with fixed latency
   `ifdef BSIM
   IntMulImport#(w) mulUnsigned <- mkIntMulSim(Unsigned);
   `else
   IntMulImport#(w) mulUnsigned <- mkIntMulUnsigned32Import;
   `endif

   // resp FIFO (unguarded) & flow ctrl credit
   FIFOF#(Tuple2#(Bit#(w2), tagT)) respQ <- mkUGSizedFIFOF(valueof(maxCredit));
   Reg#(creditT) credit <- mkReg(fromInteger(valueof(maxCredit)));

   // shift regs for sign + tag
   Vector#(IntMulLatency, Reg#(Maybe#(Tuple2#(Bool, tagT)))) pipe <- replicateM(mkReg(Invalid));

   // wire to catch input req
   RWire#(Tuple2#(Bool, tagT)) newReq <- mkRWire;

   // wire to catch deq
   PulseWire deqEn <- mkPulseWire;

   (* fire_when_enabled, no_implicit_conditions *)
   rule canon;
      creditT nextCredit = credit;
      // incr credit if resp FIFO is deq
      if(deqEn) begin
         if(nextCredit >= fromInteger(valueof(maxCredit))) begin
            $fdisplay(stderr, "\n%m: ASSERT FAIL!!");
            dynamicAssert(False, "credit overflow");
         end
         nextCredit = nextCredit + 1;
      end
      // enq resp FIFO if something is outputed from mul
      if ( pipe[valueof(IntMulLatency) - 1] matches tagged Valid {.sign, .tag} ) begin
         Bit#(w2) prod = mulUnsigned.product;
         respQ.enq(tuple2(sign?-prod:prod, tag));
      end
      // shift pipe regs
      for(Integer i = 1; i < valueof(IntMulLatency); i = i+1) begin
         pipe[i] <= pipe[i - 1];
      end
      pipe[0] <= newReq.wget;
      // decr credit if new req is taken
      if(isValid(newReq.wget)) begin
         if(nextCredit == 0) begin
            $fdisplay(stderr, "\n%m: ASSERT FAIL!!");
            dynamicAssert(False, "credit underflow");
         end
         nextCredit = nextCredit - 1;
      end
      // update credit
      credit <= nextCredit;
   endrule

   method Action req(Bit#(w) a, Bit#(w) b,
                     XilinxIntMulSign sign, tagT tag) if(credit > 0);
   
      Bool aIsNeg = unpack(msb(a));
      Bool bIsNeg = unpack(msb(b));
   
      Bit#(w) aIn = ?;
      Bit#(w) bIn = ?;
      
      Bool resultIsNeg = ?;
      case(sign)
         Signed: 
         begin
            aIn = aIsNeg ? -a:a;
            bIn = bIsNeg ? -b:b;
            resultIsNeg = unpack(pack(aIsNeg) ^ pack(bIsNeg));
         end
         Unsigned: 
         begin
            aIn = a;
            bIn = b;
            resultIsNeg = False;
         end
         SignedUnsigned:
         begin
            aIn = aIsNeg ? -a:a;
            bIn = b;
            resultIsNeg = aIsNeg;
         end
      endcase
      mulUnsigned.req(aIn, bIn);
      newReq.wset(tuple2(resultIsNeg, tag)); // notify new req
   endmethod

   method Action deqResp if(respQ.notEmpty);
      respQ.deq;
      deqEn.send; // notify deq resp
   endmethod

   method respValid = respQ.notEmpty;

   method Bit#(w2) product if(respQ.notEmpty);
      return tpl_1(respQ.first);
   endmethod

   method tagT respTag if(respQ.notEmpty);
      return tpl_2(respQ.first);
   endmethod
endmodule

module mkXilinxIntMulUnified64(XilinxIntMul#(tagT, w)) provisos(
   Bits#(tagT, tagSz),
   Add#(w, w, w2),
   Add#(w, 0, 64),
   // credit based flow control types
   NumAlias#(TAdd#(IntMulLatency, 1), maxCredit),
   Alias#(Bit#(TLog#(TAdd#(maxCredit, 1))), creditT)
   );
   // different multilpliers: WaitAutoReset is not needed, since mul is a
   // pipeline with fixed latency
   `ifdef BSIM
   IntMulImport#(w) mulUnsigned <- mkIntMulSim(Unsigned);
   `else
   IntMulImport#(w) mulUnsigned <- mkIntMulUnsigned64Import;
   `endif

   // resp FIFO (unguarded) & flow ctrl credit
   FIFOF#(Tuple2#(Bit#(w2), tagT)) respQ <- mkUGSizedFIFOF(valueof(maxCredit));
   Reg#(creditT) credit <- mkReg(fromInteger(valueof(maxCredit)));

   // shift regs for sign + tag
   Vector#(IntMulLatency, Reg#(Maybe#(Tuple2#(Bool, tagT)))) pipe <- replicateM(mkReg(Invalid));

   // wire to catch input req
   RWire#(Tuple2#(Bool, tagT)) newReq <- mkRWire;

   // wire to catch deq
   PulseWire deqEn <- mkPulseWire;

   (* fire_when_enabled, no_implicit_conditions *)
   rule canon;
      creditT nextCredit = credit;
      // incr credit if resp FIFO is deq
      if(deqEn) begin
         if(nextCredit >= fromInteger(valueof(maxCredit))) begin
            $fdisplay(stderr, "\n%m: ASSERT FAIL!!");
            dynamicAssert(False, "credit overflow");
         end
         nextCredit = nextCredit + 1;
      end
      // enq resp FIFO if something is outputed from mul
      if ( pipe[valueof(IntMulLatency) - 1] matches tagged Valid {.sign, .tag} ) begin
         Bit#(w2) prod = mulUnsigned.product;
         respQ.enq(tuple2(sign?-prod:prod, tag));
      end
      // shift pipe regs
      for(Integer i = 1; i < valueof(IntMulLatency); i = i+1) begin
         pipe[i] <= pipe[i - 1];
      end
      pipe[0] <= newReq.wget;
      // decr credit if new req is taken
      if(isValid(newReq.wget)) begin
         if(nextCredit == 0) begin
            $fdisplay(stderr, "\n%m: ASSERT FAIL!!");
            dynamicAssert(False, "credit underflow");
         end
         nextCredit = nextCredit - 1;
      end
      // update credit
      credit <= nextCredit;
   endrule
   
   FIFO#(Tuple4#(Bit#(64), Bit#(64), Bool, tagT)) reqQ <- mkPipelineFIFO;
   
   rule doReq if(credit > 0);
      let {aIn, bIn, resultIsNeg, tag} = reqQ.first;
      reqQ.deq;
      
      mulUnsigned.req(aIn, bIn);
      newReq.wset(tuple2(resultIsNeg, tag)); // notify new req
   endrule

   method Action req(Bit#(w) a, Bit#(w) b,
                     XilinxIntMulSign sign, tagT tag);
   
      Bool aIsNeg = unpack(msb(a));
      Bool bIsNeg = unpack(msb(b));
   
      Bit#(w) aIn = ?;
      Bit#(w) bIn = ?;
      
      Bool resultIsNeg = ?;
      case(sign)
         Signed: 
         begin
            aIn = aIsNeg ? -a:a;
            bIn = bIsNeg ? -b:b;
            resultIsNeg = unpack(pack(aIsNeg) ^ pack(bIsNeg));
         end
         Unsigned: 
         begin
            aIn = a;
            bIn = b;
            resultIsNeg = False;
         end
         SignedUnsigned:
         begin
            aIn = aIsNeg ? -a:a;
            bIn = b;
            resultIsNeg = aIsNeg;
         end
      endcase
      reqQ.enq(tuple4(aIn, bIn, resultIsNeg, tag));
   endmethod

   method Action deqResp if(respQ.notEmpty);
      respQ.deq;
      deqEn.send; // notify deq resp
   endmethod

   method respValid = respQ.notEmpty;

   method Bit#(w2) product if(respQ.notEmpty);
      return tpl_1(respQ.first);
   endmethod

   method tagT respTag if(respQ.notEmpty);
      return tpl_2(respQ.first);
   endmethod
endmodule
