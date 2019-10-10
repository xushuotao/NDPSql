import Bitonic::*;
import Vector::*;
import FIFO::*;
import GetPut::*;
import SpecialFIFOs::*;

Bool debug = False;

typedef enum {Init, Normal} Op deriving (Bits, FShow, Eq);

interface TopHalfUnit#(numeric type vSz, type iType);
   method Action enqData(Vector#(vSz, iType) in, Op op);
   method ActionValue#(Vector#(vSz, iType)) getCurrTop;
endinterface

typedef struct{
               Op op;
               // Vector#(vSz, iType) currTop;
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
   Bounded#(iType),
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
   Bounded#(iType),
   FShow#(iType));
   
   Vector#(vSz, Vector#(vSz, Reg#(iType))) prevTop = ?;//<- replicateM(replicateM(mkRegU));
   for (Integer i = 0; i < valueOf(vSz); i = i + 1 ) begin
      for ( Integer j = 0; j < i + 1; j = j + 1) begin
         prevTop[i][valueOf(vSz)-1-j] <- mkReg(minBound);
      end
   end
   
   
   Vector#(vSz, FIFO#(StageDataT#(vSz, iType))) stageQ <- replicateM(mkPipelineFIFO);
   FIFO#(Vector#(vSz, iType)) resultQ <- mkPipelineFIFO;
   
   Vector#(vSz, Reg#(Bit#(32))) seqId <- replicateM(mkReg(0));
   
   for (Integer i = 1; i < valueOf(vSz) ; i = i + 1) begin
      rule doGenTop;
         let d <- toGet(stageQ[i-1]).get();
         
         if ( debug ) begin
            $display("stage = %0d seqid = %0d before", i, seqId[i], fshow(d));
            $display("stage = %0d seqid = %0d prevTop", i, seqId[i], fshow(readVReg(prevTop[i])));
            $display("stage = %0d seqid = %0d prevTop tail vs sfted tail ", i, seqId[i], fshow(prevTop[i][d.tailPtr]), " ", fshow(last(d.sftedIn)) );
         end
 
         Vector#(vSz, iType) currTop = readVReg(prevTop[i-1]);
         iType currItem = max(prevTop[i][d.tailPtr], last(d.sftedIn));
         if ( d.op == Normal) begin
            // d.currTop[valueOf(vSz)-1-i] = max(prevTop[i][d.tailPtr], last(d.sftedIn));
            currTop[valueOf(vSz)-1-i] = max(prevTop[i][d.tailPtr], last(d.sftedIn));
                         
            if ( prevTop[i][d.tailPtr] < last(d.sftedIn) ) begin
               d.sftedIn = rotateBy(d.sftedIn, 1);
            end
            else begin
               d.tailPtr = d.tailPtr - 1;
            end
         end
         else begin
            currTop[valueOf(vSz)-1-i] = last(d.sftedIn);
            // currTop[
            // currItem = last(d.sftedIn);
            d.sftedIn = rotateBy(d.sftedIn, 1);
         end
         

         if ( debug ) begin
            $display("stage = %0d seqid = %0d ", i, seqId[i], fshow(d));
            seqId[i] <= seqId[i] + 1;
         end
         
         for (Integer j = 0; j < i+1; j = j + 1 ) begin
            Integer idx = valueOf(vSz)-1-j;
            // prevTop[i][idx] <=  d.currTop[idx];
            prevTop[i][idx] <= currTop[idx];
            // prevTop[i][idx] <=  prevTop[i-1][idx];
         end
         // prevTop[i][valueOf(vSz)-1-i] <= currItem;
         
         // if ( !(i == (valueOf(vSz) - 1) && d.op == Init) )
         stageQ[i].enq(d);
         // else if ( i == (valueOf(vSz) - 1) && d.op!=Init) begin
         //    d.currTop = currTop;
         //    stageQ[i].enq(d);
         // end
      endrule
   end
   
   Reg#(Bit#(32)) id <- mkReg(0);
   rule doGetResult;
      let v <- toGet(last(stageQ)).get();
      id <= id + 1;
      if ( debug )
         $display("seqid = %0d result = ", id, fshow(v.op), " ", fshow(readVReg(last(prevTop))));
      //if ( v.op != Init) begin
         resultQ.enq(readVReg(last(prevTop)));
      //end
   endrule
   
   method Action enqData(Vector#(vSz, iType) in, Op op);
      let d = StageDataT{op: op,
                         // currTop:in,
                         sftedIn: in,
                         tailPtr:fromInteger(valueOf(vSz)-1)};
      
      if (debug) begin
         $display("stage = 0 seqid = %0d before:", seqId[0], fshow(d));
         $display("stage = 0 seqid = %0d prevTop:", seqId[0], fshow(readVReg(prevTop[0])));
      end
   
      Vector#(vSz, iType) currTop = in;

      if ( d.op == Normal) begin
         if ( last(prevTop[0])._read < last(in) ) begin
            d.sftedIn = rotateBy(in, 1);
         end
         else begin
            d.tailPtr = d.tailPtr - 1;
         end
         currTop[valueOf(vSz)-1] = max(last(in), last(prevTop[0])._read);
         // d.currTop[valueOf(vSz)-1] = max(last(in), last(prevTop[0])._read);
      end
      else begin
         d.sftedIn = rotateBy(in, 1);
      end

      last(prevTop[0])._write(last(currTop));
   
      if (debug ) begin
         $display("stage = 0 seqid = %0d ", seqId[0], fshow(d));
         seqId[0] <= seqId[0] + 1;
      end
   
      stageQ[0].enq(d);
   endmethod
   
   method ActionValue#(Vector#(vSz, iType)) getCurrTop = toGet(resultQ).get;
      // let d <- toGet(last(stageQ)).get();
      // return readVReg(last(prevTop));
      // let d <- 
   // endmethod
   
endmodule
