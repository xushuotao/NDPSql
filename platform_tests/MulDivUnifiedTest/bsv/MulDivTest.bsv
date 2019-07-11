`include "ConnectalProjectConfig.bsv"

import Clocks::*;
import FIFO::*;
import BRAMFIFO::*;
import MulDivTestIF::*;
import XilinxIntMul::*;
import XilinxIntDiv::*;

(* synthesize *)
module mkMul(XilinxIntMul#(UserTag, 64));
   let m <- mkXilinxIntMulUnified64;
   return m;
endmodule

(* synthesize *)
module mkDiv(XilinxIntDiv#(UserTag, 64));
   let m <- mkXilinxIntDiv64;
   return m;
endmodule

interface MulDivTest;
   method Action setTest(MulDivReq r, Bool last);
   method ActionValue#(MulDivResp) resp;
endinterface

// maximum tests
typedef `MAX_TEST_NUM MaxTestNum;

// delay certain cycles after seeing all responses for a test to create back
// pressure
typedef Bit#(`LOG_DELAY_CYCLES) DelayCnt;

(* synthesize *)
module mkMulDivTest(MulDivTest);
   
   FIFO#(Tuple2#(MulDivReq, Bool)) setTestQ <- mkFIFO();
   FIFO#(MulDivResp) respQ <- mkFIFO();
   
   // tests
   FIFO#(MulDivReq) testQ <- mkSizedBRAMFIFO(valueof(MaxTestNum));
   Reg#(Bool) started <- mkReg(False);

   // delay resp
   Reg#(DelayCnt) delay <- mkReg(0);

   // mul/div units
   XilinxIntMul#(UserTag, 64) mulUnit <- mkMul;
   XilinxIntDiv#(UserTag, 64) divUnit <- mkDiv;

   rule doSetTest(!started);
      setTestQ.deq;
      let {req, last} = setTestQ.first;
      started <= last;
      testQ.enq(req);
   endrule

   rule sendTest(started);
      testQ.deq;
      let r = testQ.first;
      XilinxIntMulSign mulSign = (case(r.mulSign)
                                     Signed: (Signed);
                                     Unsigned: (Unsigned);
                                     SignedUnsigned: (SignedUnsigned);
                                     default: (?);
                                  endcase);
      mulUnit.req(r.a, r.b, mulSign, r.tag);
      divUnit.req(r.a, r.b, r.divSigned, r.tag);
      $display("(%m) %t request = ", $time, fshow(r));
   endrule

   rule delayResp(mulUnit.respValid && divUnit.respValid && delay < maxBound);
      delay <= delay + 1;
   endrule

   rule recvResp(delay == maxBound);
      mulUnit.deqResp;
      divUnit.deqResp;

      let resp = MulDivResp {
         productHi: truncateLSB(mulUnit.product),
         productLo: truncate(mulUnit.product),
         mulTag: mulUnit.respTag,
         quotient: divUnit.quotient,
         remainder: divUnit.remainder,
         divTag: divUnit.respTag
         };
      $display("(%m) %t response = ", $time, fshow(resp));
      respQ.enq(resp);
      delay <= 0; // reset delay
   endrule

   method Action setTest(MulDivReq r, Bool last);
      setTestQ.enq(tuple2(r, last));
   endmethod

   method ActionValue#(MulDivResp) resp;
      respQ.deq;
      return respQ.first;
   endmethod
endmodule
