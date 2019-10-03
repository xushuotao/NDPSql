import Bitonic::*;
import Vector::*;
import FIFO::*;
import GetPut::*;

Bool debug = False;

typedef enum {Init, Normal} Op deriving (Bits, FShow, Eq);

interface TopHalfUnit#(numeric type vSz, type iType);
   method Action enqData(Vector#(vSz, iType) in, Op op);
   method ActionValue#(Vector#(vSz, iType)) getCurrTop;
endinterface

typedef struct{
               Op op;
               Vector#(vSz, iType) currTop;
               Vector#(vSz, iType) sftedIn;
               UInt#(TLog#(vSz)) tailPtr;
               } StageDataT#(numeric type vSz, type iType) deriving (Bits,Eq,FShow);

typeclass TopHalfUnitInstance#(numeric type vSz, type iType);
   module mkTopHalfUnit(TopHalfUnit#(vSz, iType));
endtypeclass

(* synthesize *)
module mkTopHalfUnit_8_uint32_synth(TopHalfUnit#(8, UInt#(32)));
   let tophalfunit <- mkTopHalfUnitImpl;
   return tophalfunit;
endmodule

instance TopHalfUnitInstance#(8, UInt#(32));
   module mkTopHalfUnit(TopHalfUnit#(8, UInt#(32)));
      let m_<- mkTopHalfUnit_8_uint32_synth;
      return m_;
   endmodule
endinstance


instance TopHalfUnitInstance#(vSz, iType) provisos (
   Bits#(Vector::Vector#(vSz, iType), a__),
   Add#(1, b__, vSz),
   Ord#(iType),
   FShow#(iType));
   module mkTopHalfUnit(TopHalfUnit#(vSz, iType));
      let m_<- mkTopHalfUnitImpl;
      return m_;
   endmodule
endinstance

module mkTopHalfUnitImpl(TopHalfUnit#(vSz, iType)) provisos(
   Bits#(Vector::Vector#(vSz, iType), a__),
   Add#(1, b__, vSz),
   Ord#(iType),
   FShow#(iType));
   
   Vector#(vSz, Vector#(vSz, Reg#(iType))) prevTop <- replicateM(replicateM(mkRegU));
   Vector#(vSz, FIFO#(StageDataT#(vSz, iType))) stageQ <- replicateM(mkFIFO);
   
   Vector#(vSz, Reg#(Bit#(32))) seqId <- replicateM(mkReg(0));
   
   for (Integer i = 1; i < valueOf(vSz) ; i = i + 1) begin
      rule doGenTop;
         let d <- toGet(stageQ[i-1]).get();
         
         if ( debug ) begin
            $display("stage = %0d seqid = %0d before", i, seqId[i], fshow(d));
            $display("stage = %0d seqid = %0d prevTop", i, seqId[i], fshow(readVReg(prevTop[i])));
            $display("stage = %0d seqid = %0d prevTop tail vs sfted tail ", i, seqId[i], fshow(prevTop[i][d.tailPtr]), " ", fshow(last(d.sftedIn)) );
         end
         
         if ( d.op == Normal) begin
            d.currTop[valueOf(vSz)-1-i] = max(prevTop[i][d.tailPtr], last(d.sftedIn));
            
            if ( prevTop[i][d.tailPtr] < last(d.sftedIn) ) begin
               d.sftedIn = rotateBy(d.sftedIn, 1);
            end
            else begin
               d.tailPtr = d.tailPtr - 1;
            end
         end

         if ( debug ) begin
            $display("stage = %0d seqid = %0d ", i, seqId[i], fshow(d));
            seqId[i] <= seqId[i] + 1;
         end
         
         for (Integer j = 0; j <= i; j = j + 1 ) begin
            Integer idx = valueOf(vSz)-1-j;
            prevTop[i][idx] <= d.currTop[idx];
         end
         if ( !(i == (valueOf(vSz) - 1) && d.op == Init) )
            stageQ[i].enq(d);
      endrule
   end
   
   method Action enqData(Vector#(vSz, iType) in, Op op);
      let d = StageDataT{op: op,
                         currTop:in,
                         sftedIn: in,
                         tailPtr:fromInteger(valueOf(vSz)-1)};
      
      if (debug)
         $display("stage = 0 seqid = %0d before:", seqId[0], fshow(d));

      if ( d.op == Normal) begin
         if ( last(prevTop[0])._read < last(in) ) begin
            d.sftedIn = rotateBy(in, 1);
         end
         else begin
            d.tailPtr = d.tailPtr - 1;
         end
         d.currTop[valueOf(vSz)-1] = max(last(in), last(prevTop[0])._read);
      end

      last(prevTop[0])._write(last(d.currTop));
   
      if (debug ) begin
         $display("stage = 0 seqid = %0d ", seqId[0], fshow(d));
         seqId[0] <= seqId[0] + 1;
      end
   
      stageQ[0].enq(d);
   endmethod
   
   method ActionValue#(Vector#(vSz, iType)) getCurrTop;
      let d <- toGet(last(stageQ)).get();
      return d.currTop;
   endmethod
   
endmodule
