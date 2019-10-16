import Bitonic::*;
import Vector::*;
import FIFO::*;
import FIFOF::*;
import GetPut::*;
import SpecialFIFOs::*;
import RegFile::*;
import BuildVector::*;

Bool debug = False;

typedef enum {Init, Normal} Op deriving (Bits, FShow, Eq);

interface TopHalfUnitSMT#(numeric type numTags, numeric type vSz, type iType);
   method Action enqData(Vector#(vSz, iType) in, Op op, UInt#(TLog#(numTags)) tag);
   method ActionValue#(Tuple2#(Vector#(vSz, iType), UInt#(TLog#(numTags)))) getCurrTop;
endinterface


typeclass TopHalfUnitSMTInstance#(numeric type numTags, numeric type vSz, type iType);
   module mkTopHalfUnitSMT(TopHalfUnitSMT#(numTags, vSz, iType));
endtypeclass

instance TopHalfUnitSMTInstance#(numTags, vSz, iType) provisos (
   Bits#(Vector::Vector#(vSz, iType), a__),
   Add#(1, b__, vSz),
   TopHalfStageInstance#(numTags,vSz, vSz, iType),
   Ord#(iType),
   Bounded#(iType),
   FShow#(iType));
   module mkTopHalfUnitSMT(TopHalfUnitSMT#(numTags, vSz, iType));
      let m_<- mkTopHalfUnitSMTImpl;
      return m_;
   endmodule
endinstance

interface TopHalfStage#(numeric type numTags,
                        numeric type vSz,
                        numeric type vSzMax,
                        type iType);
   method Vector#(TDiv#(vSz,1), iType) read(UInt#(TLog#(numTags)) tag);
   method Tuple5#(UInt#(TLog#(numTags)), Vector#(vSzMax, iType), UInt#(TLog#(TAdd#(vSz, 1))), Op, Bool) nextReq;
   method Action currReq(UInt#(TLog#(numTags)) tag, Vector#(vSzMax, iType) in, UInt#(TLog#(vSz)) tailPtr, Op op, Bool valid);
endinterface


typeclass TopHalfStageInstance#(numeric type numTags,
                                numeric type vSz,
                                numeric type vSzMax,
                                type iType);
   module mkTopHalfStage(TopHalfStage#(numTags, vSz, vSzMax, iType));
endtypeclass

instance TopHalfStageInstance#(numTags,1,vSzMax,iType) provisos(
   Bits#(Vector::Vector#(1, iType), a__),
   Add#(1, b__, vSzMax),
   Ord#(iType));
   module mkTopHalfStage(TopHalfStage#(numTags, 1, vSzMax, iType));
   
      RegFile#(UInt#(TLog#(numTags)),Vector#(1,iType)) currTopCtxt <- mkRegFileFull;
   
      Reg#(Bool) nextValid <- mkReg(False);
      Reg#(Op) nextOp <- mkRegU;
      Reg#(UInt#(1)) nextTailPtr <- mkRegU;
      Reg#(Vector#(vSzMax, iType)) nextIn <- mkRegU;
      Reg#(UInt#(TLog#(numTags))) nextTag <- mkRegU;
   
      method Vector#(1, iType) read(UInt#(TLog#(numTags)) tag);
         return currTopCtxt.sub(tag);
      endmethod
   
      method Tuple5#(UInt#(TLog#(numTags)), Vector#(vSzMax, iType), UInt#(1), Op, Bool) nextReq;
         return tuple5(nextTag, nextIn, nextTailPtr, nextOp, nextValid);
      endmethod
   
      method Action currReq(UInt#(TLog#(numTags)) tag, Vector#(vSzMax, iType) in, UInt#(0) tailPtr, Op op, Bool valid);
         let currTop = currTopCtxt.sub(tag);
         if ( valid ) begin
            if ( op == Normal ) begin
               iType tailItem = max(currTop[0], last(in));
               if ( currTop[0] < last(in) ) begin
                  nextIn <= rotateBy(in, 1);
                  nextTailPtr <= 1;
               end
               else begin
                  nextIn <= in;
                  nextTailPtr <= 0;
               end
               currTopCtxt.upd(tag, vec(tailItem));
            end
            else begin
               currTopCtxt.upd(tag, drop(in));
               nextIn <= in;
            end
         end
         
         nextTag <= tag;
         nextOp <= op;
         nextValid <= valid;
      endmethod
   endmodule
endinstance

instance TopHalfStageInstance#(numTags,vSz,vSzMax,iType) provisos(
   Add#(a__, TLog#(TAdd#(TSub#(vSz, 1), 1)), TLog#(TAdd#(vSz, 1))),
   Add#(b__, TLog#(TSub#(vSz, 1)), TLog#(vSz)),
   Add#(1, c__, vSzMax),
   Bits#(Vector::Vector#(vSz, iType), d__),
   Add#(1, TDiv#(TSub#(vSz, 1), 1), vSz),
   Add#(vSz, e__, vSzMax),
   Ord#(iType),
   TopHalfUnitSMT::TopHalfStageInstance#(numTags, TSub#(vSz, 1), vSzMax, iType)

   );
   module mkTopHalfStage(TopHalfStage#(numTags, vSz, vSzMax, iType));
      TopHalfStage#(numTags, TSub#(vSz,1), vSzMax, iType) prevStage <- mkTopHalfStage;
      RegFile#(UInt#(TLog#(numTags)), Vector#(vSz, iType)) currTopCtxt <- mkRegFileFull;
   
      Reg#(Bool) nextValid <- mkReg(False);
      Reg#(Op) nextOp <- mkRegU;
      Reg#(UInt#(TLog#(TAdd#(vSz,1)))) nextTailPtr <- mkRegU;
      Reg#(Vector#(vSzMax, iType)) nextIn <- mkRegU;
      Reg#(UInt#(TLog#(numTags))) nextTag <- mkRegU;
   
      (* fire_when_enabled, no_implicit_conditions*)
      rule doStage;
         let {tag, in, tailPtr, op, valid} = prevStage.nextReq;
         let prevTop = prevStage.read(tag);
         
         let currTop = currTopCtxt.sub(tag);
         if ( op == Normal ) begin
            iType tailItem = max(currTop[tailPtr], last(in));
            if ( currTop[tailPtr] < last(in) ) begin
               nextIn <= rotateBy(in, 1);
               nextTailPtr <= zeroExtend(tailPtr) + 1;
            end
            else begin
               nextIn <= in;
               nextTailPtr <= zeroExtend(tailPtr);
            end
            currTopCtxt.upd(tag, cons(tailItem, prevTop));
         end
         else begin
            currTopCtxt.upd(tag, drop(in));
            nextIn <= in;
         end
         
         nextTag <= tag;
         nextOp <= op;
         nextValid <= valid;
      endrule
   
      method Vector#(vSz, iType) read(UInt#(TLog#(numTags)) tag);
         return currTopCtxt.sub(tag);
      endmethod
   
      method Tuple5#(UInt#(TLog#(numTags)), Vector#(vSzMax, iType), UInt#(TLog#(TAdd#(vSz, 1))), Op, Bool) nextReq;
         return tuple5(nextTag, nextIn, nextTailPtr, nextOp, nextValid);
      endmethod
   
      method Action currReq(UInt#(TLog#(numTags)) tag, Vector#(vSzMax, iType) in, UInt#(TLog#(vSz)) tailPtr, Op op, Bool valid);
         prevStage.currReq(tag, in, truncate(tailPtr), op, valid);
      endmethod
   endmodule
endinstance


module mkTopHalfUnitSMTImpl(TopHalfUnitSMT#(numTags, vSz, iType)) provisos(
   Alias#(UInt#(TLog#(numTags)), tagT),
   Bits#(Vector::Vector#(vSz, iType), a__),
   Add#(1, b__, vSz),
   Ord#(iType),
   Bounded#(iType),
   FShow#(iType),
   TopHalfUnitSMT::TopHalfStageInstance#(numTags, vSz, vSz, iType));

   Reg#(UInt#(TLog#(TAdd#(vSz,2)))) credit[2] <- mkCReg(2, fromInteger(valueOf(vSz)+1));   
   FIFOF#(Tuple2#(Vector#(vSz, iType), tagT)) resultQ <- mkUGSizedFIFOF(valueOf(vSz)+1);
   
   TopHalfStage#(numTags, vSz, vSz, iType) topHalfUnitPipeline <- mkTopHalfStage;
   
   RWire#(Tuple3#(Vector#(vSz, iType), Op, tagT)) inWire <- mkRWire;
   
   (* fire_when_enabled, no_implicit_conditions*)
   rule firstStage;
      if ( inWire.wget matches tagged Valid {.in, .op, .tag} ) begin
         topHalfUnitPipeline.currReq(tag, in, ?, op, True);
         credit[1] <= credit[1] - 1;
      end
      else begin
         topHalfUnitPipeline.currReq(?, ?, ?, ?, False);
      end
   endrule
   
      
   rule doGetResult;
      let {tag, in, tail, op, valid} = topHalfUnitPipeline.nextReq;
      if ( valid ) begin
         let d = topHalfUnitPipeline.read(tag);
         resultQ.enq(tuple2(d, tag));
      end
   endrule
   
   method Action enqData(Vector#(vSz, iType) in, Op op, tagT tag) if (credit[1] > 0 );
      inWire.wset(tuple3(in, op, tag));
   endmethod
   
   method ActionValue#(Tuple2#(Vector#(vSz, iType), tagT)) getCurrTop if ( resultQ.notEmpty);
      credit[0] <= credit[0] + 1;
      let v <- toGet(resultQ).get;
      return v;
   endmethod
   
endmodule

////////////////////////////////////////////////////////////////////////////////
/// Synthesis Boundaries
////////////////////////////////////////////////////////////////////////////////
(* synthesize *)
module mkTopHalfUnitSMT_16_uint32_synth(TopHalfUnitSMT#(16, 8, UInt#(32)));
   let tophalfunit <- mkTopHalfUnitSMTImpl;
   return tophalfunit;
endmodule
instance TopHalfUnitSMTInstance#(16, 8, UInt#(32));
   module mkTopHalfUnitSMT(TopHalfUnitSMT#(16, 8, UInt#(32)));
      let m_ <- mkTopHalfUnitSMT_16_uint32_synth;
      return m_;
   endmodule
endinstance

(* synthesize *)
module mkTopHalfUnitSMT_8_uint32_synth(TopHalfUnitSMT#(8, 8, UInt#(32)));
   let tophalfunit <- mkTopHalfUnitSMTImpl;
   return tophalfunit;
endmodule
instance TopHalfUnitSMTInstance#(8, 8, UInt#(32));
   module mkTopHalfUnitSMT(TopHalfUnitSMT#(8, 8, UInt#(32)));
      let m_ <- mkTopHalfUnitSMT_8_uint32_synth;
      return m_;
   endmodule
endinstance

(* synthesize *)
module mkTopHalfUnitSMT_4_uint32_synth(TopHalfUnitSMT#(4, 8, UInt#(32)));
   let tophalfunit <- mkTopHalfUnitSMTImpl;
   return tophalfunit;
endmodule
instance TopHalfUnitSMTInstance#(4, 8, UInt#(32));
   module mkTopHalfUnitSMT(TopHalfUnitSMT#(4, 8, UInt#(32)));
      let m_ <- mkTopHalfUnitSMT_4_uint32_synth;
      return m_;
   endmodule
endinstance

(* synthesize *)
module mkTopHalfUnitSMT_2_uint32_synth(TopHalfUnitSMT#(2, 8, UInt#(32)));
   let tophalfunit <- mkTopHalfUnitSMTImpl;
   return tophalfunit;
endmodule
instance TopHalfUnitSMTInstance#(2, 8, UInt#(32));
   module mkTopHalfUnitSMT(TopHalfUnitSMT#(2, 8, UInt#(32)));
      let m_ <- mkTopHalfUnitSMT_2_uint32_synth;
      return m_;
   endmodule
endinstance

(* synthesize *)
module mkTopHalfUnitSMT_1_uint32_synth(TopHalfUnitSMT#(1, 8, UInt#(32)));
   let tophalfunit <- mkTopHalfUnitSMTImpl;
   return tophalfunit;
endmodule
instance TopHalfUnitSMTInstance#(1, 8, UInt#(32));
   module mkTopHalfUnitSMT(TopHalfUnitSMT#(1, 8, UInt#(32)));
      let m_ <- mkTopHalfUnitSMT_1_uint32_synth;
      return m_;
   endmodule
endinstance

