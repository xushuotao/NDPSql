import Vector::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Assert::*;

typedef enum {BigInt_Long, Long_Int, Int_Short, Short_Byte} CastOp deriving (Bits, Eq, FShow);

function Maybe#(Bit#(128)) downCastFunc(Bit#(256) in, CastOp op);
   Maybe#(Bit#(128)) retval = tagged Invalid;
   case (op)
      BigInt_Long: 
      begin
         Vector#(2, Bit#(128)) inVec = unpack(in);
         Vector#(2, Bit#(64)) outVec = map(truncate, inVec);
         retval = tagged Valid pack(outVec);
      end

      Long_Int: 
      begin
         Vector#(4, Bit#(64)) inVec = unpack(in);
         Vector#(4, Bit#(32)) outVec = map(truncate, inVec);
         retval = tagged Valid pack(outVec);
      end
      /*      
      Int_Short: 
      begin
         Vector#(8, Bit#(32)) inVec = unpack(in);
         Vector#(8, Bit#(16)) outVec = map(truncate, inVec);
         retval = pack(outVec);
      end
      
      Short_Byte: 
      begin
         Vector#(16, Bit#(16)) inVec = unpack(in);
         Vector#(16, Bit#(8)) outVec = map(truncate, inVec);
         retval = pack(outVec);
      end
      */
   endcase
   
   return retval;
endfunction

interface SimdTypeDownCast;
   method Action req(Bit#(256) data, CastOp op);
   method Bit#(256) resp;
   method Action deqResp;
   method Bool respValid;
endinterface

(* synthesize *)
module mkSimdTypeDownCastPP(SimdTypeDownCast);
   Reg#(Bit#(1)) beatCnt <- mkReg(0);
   Reg#(Bit#(128)) lowData <- mkRegU;
   FIFOF#(Bit#(256)) outDataQ <- mkPipelineFIFOF;
   method Action req(Bit#(256) data, CastOp op);
      let cast_data = downCastFunc(data, op);
      dynamicAssert(isValid(cast_data), "DownCastOp is not supported");
      lowData <= fromMaybe(?, cast_data);
      if ( beatCnt == 1 ) outDataQ.enq({fromMaybe(?, cast_data), lowData});
      beatCnt <= beatCnt + 1;
   endmethod
   method Bit#(256) resp = outDataQ.first;
   method Action deqResp = outDataQ.deq;
   method Bool respValid = outDataQ.notEmpty;
endmodule
