import SimdCommon::*;
import SimdAddSub128::*;
import SimdMul64::*;
import Vector::*;
import FIFO::*;
import GetPut::*;

import Assert::*;


typedef enum{Add, Sub, Mul, Mullo} AluOp deriving (Bits, Eq, FShow);

interface SimdAlu256;
   method Action start(Bit#(256) a, Bit#(256) b, AluOp op, SimdMode mode, Bool isSigned);
   method ActionValue#(Tuple2#(Vector#(2, Bit#(256)), Bool)) result;
endinterface

(* synthesize *)
module mkSimdAlu256(SimdAlu256);
   
   Vector#(2, SimdAddSub128) addsub <- replicateM(mkSimdAddSub128);
   Vector#(4, SimdMul64) mul <- replicateM(mkSimdMul64);
   
   FIFO#(AluOp) outstandingQ <- mkSizedFIFO(valueOf(TAdd#(TMax#(AddSubLatency, IntMulLatency),1)));

   method Action start(Bit#(256) a, Bit#(256) b, AluOp op, SimdMode mode, Bool isSigned);
      case (op)
         Add, Sub:
         begin
            Vector#(2, Bit#(128)) aVec = unpack(a);
            Vector#(2, Bit#(128)) bVec = unpack(b);
            addsub[0].req(aVec[0], bVec[0], op == Sub, mode);
            addsub[1].req(aVec[1], bVec[1], op == Sub, mode);
         end
         Mul, Mullo:
         begin
            Vector#(4, Bit#(64)) aVec = unpack(a);
            Vector#(4, Bit#(64)) bVec = unpack(b);
            mul[0].req(aVec[0], bVec[0], pack(mode == Long), op == Mullo, isSigned);
            mul[1].req(aVec[1], bVec[1], pack(mode == Long), op == Mullo, isSigned);
            mul[2].req(aVec[2], bVec[2], pack(mode == Long), op == Mullo, isSigned);
            mul[3].req(aVec[3], bVec[3], pack(mode == Long), op == Mullo, isSigned);
            // dynamicAssert(mode == Long || mode == Int, "Mul only support 32-bit and 64-bit");
         end
      endcase
   
      outstandingQ.enq(op);
   endmethod
   
   method ActionValue#(Tuple2#(Vector#(2, Bit#(256)), Bool)) result;
      let op <- toGet(outstandingQ).get;
      Vector#(2, Bit#(256)) retval = ?;
      Bool half = True;
      case (op)
         Add, Sub:
         begin
            let d0 = addsub[0].sum;
            let d1 = addsub[1].sum;
            addsub[0].deqResp;
            addsub[1].deqResp;
            retval[0] = {d1, d0};
         end
         Mul, Mullo:
         begin
            let d0 = mul[0].product;
            let d1 = mul[1].product;
            let d2 = mul[2].product;
            let d3 = mul[3].product;
            mul[0].deqResp;
            mul[1].deqResp;
            mul[2].deqResp;
            mul[3].deqResp;
            
            if ( op == Mullo ) begin
               retval[0] = {d3[63:0], d2[63:0], d1[63:0], d0[63:0]};
            end
            else begin
               retval[0] = {d1, d0};
               retval[1] = {d3, d2};
            end
            half = (op == Mullo);
         end
      endcase
   
      return tuple2(retval, half);
   endmethod
endmodule
