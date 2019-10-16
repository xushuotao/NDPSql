import Pipe::*;
import Vector::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Connectable::*;
import SpecialFIFOs::*;
import BuildVector::*;
import GetPut::*;
import Assert::*;

import Bitonic::*;
import TopHalfUnit::*;

Bool debug = False;


interface VariableStreamIn#(numeric type vSz, type iType);
   interface PipeIn#(Vector#(vSz, iType)) dataChannel;
   interface PipeIn#(UInt#(32)) lenChannel;
endinterface

interface VariableStreamOut#(numeric type vSz, type iType);
   interface PipeOut#(Vector#(vSz, iType)) dataChannel;
   interface PipeOut#(UInt#(32)) lenChannel;
endinterface

function VariableStreamIn#(vSz, iType) toVariableStreamIn(PipeIn#(Vector#(vSz, iType)) inData, PipeIn#(UInt#(32)) inLen);
   return (interface VariableStreamIn;
              interface dataChannel = inData;
              interface lenChannel = inLen;
           endinterface);
endfunction

function VariableStreamOut#(vSz, iType) toVariableStreamOut(PipeOut#(Vector#(vSz, iType)) outData, PipeOut#(UInt#(32)) outLen);
   return (interface VariableStreamOut;
              interface dataChannel = outData;
              interface lenChannel = outLen;
           endinterface);
endfunction


instance Connectable#(VariableStreamIn#(vSz, iType), 
                      VariableStreamOut#(vSz, iType));
   module mkConnection#(VariableStreamIn#(vSz, iType) in,
                        VariableStreamOut#(vSz, iType) out)(Empty);
      mkConnection(out.dataChannel,in.dataChannel);
      mkConnection(out.lenChannel, in.lenChannel);
   endmodule
endinstance

instance Connectable#(VariableStreamOut#(vSz, iType),
                      VariableStreamIn#(vSz, iType)); 
   module mkConnection#(VariableStreamOut#(vSz, iType) out, 
                        VariableStreamIn#(vSz, iType) in)(Empty);
      mkConnection(out.dataChannel,in.dataChannel);
      mkConnection(out.lenChannel, in.lenChannel);
   endmodule
endinstance


interface MergeNVar#(type iType,
                     numeric type vSz,
                     numeric type n);
   interface Vector#(n, VariableStreamIn#(vSz, iType)) inStreams;
   interface VariableStreamOut#(vSz, iType) outStream;
endinterface



typeclass RecursiveMergerVar#(type iType,
                              numeric type vSz,
                              numeric type n);
////////////////////////////////////////////////////////////////////////////////
/// module:      mkStreamingMergeNVar
/// Description: this module takes N in-streams, each has sorted elements of 
///              variable length of l_i streaming @ vSz elements per beat, and 
///              merge them  into a single sorted out-stream of sum(l_i) elements 
///              with a binary merge-tree
////////////////////////////////////////////////////////////////////////////////
   module mkStreamingMergeNVar#(Bool ascending, Integer level, Integer id)(MergeNVar#(iType,vSz,n));
endtypeclass


instance RecursiveMergerVar#(iType,vSz,2) provisos(
   Bitonic::RecursiveBitonic#(vSz, iType),
   Ord#(iType),
   Bounded#(iType),
   Add#(1, b__, vSz),
   Bits#(iType, c__),
   Mul#(vSz, c__, d__),
   TopHalfUnit::TopHalfUnitInstance#(vSz, iType)
   );
   module mkStreamingMergeNVar#(Bool ascending,  Integer level, Integer id)(MergeNVar#(iType,vSz,2));
      let merger <- mkStreamingMerge2Var(ascending, level, id);
      return merger;
   endmodule
endinstance

// NORMAL CASE
instance RecursiveMergerVar#(iType,vSz,n) provisos (
   Add#(2, a__, n),               // n >= 2
   NumAlias#(TExp#(TLog#(n)), n), //n is power of 2
   Bitonic::RecursiveBitonic#(vSz, iType),
   Ord#(iType),
   Bounded#(iType),
   Add#(1, c__, vSz),
   Bits#(iType, d__),
   Mul#(vSz, d__, e__),
   MergeSortVar::RecursiveMergerVar#(iType, vSz, TDiv#(n, 2)),
   Mul#(TDiv#(n, 2), 2, n),
   TopHalfUnit::TopHalfUnitInstance#(vSz, iType)
);
   module mkStreamingMergeNVar#(Bool ascending, Integer level, Integer id)(MergeNVar#(iType,vSz,n));
      Vector#(TDiv#(n,2), Merge2Var#(iType, vSz)) mergers <- zipWith3M(mkStreamingMerge2Var, replicate(ascending), replicate(level), genVector());
   
      function VariableStreamOut#(vSz, iType) getPipeOut(Merge2Var#(iType, vSz) ifc) = ifc.outStream;
      function getPipeIn(ifc) = ifc.inStreams;
   
      MergeNVar#(iType, vSz, TDiv#(n,2)) mergeN_2 <- mkStreamingMergeNVar(ascending, level+1, 0);

      zipWithM_(mkConnection, map(getPipeOut,mergers), mergeN_2.inStreams);
   
      MergeNVar#(iType,vSz,n) retifc = (interface MergeNVar;
                                           interface inStreams = concat(map(getPipeIn,mergers));
                                           interface outStream = mergeN_2.outStream;
                                        endinterface);
      return retifc;
   endmodule
endinstance

// merge two sorted streams of same size of sortedSz
typedef MergeNVar#(iType, vSz, 2) Merge2Var#(type iType,
                                             numeric type vSz); 


typedef enum {DRAIN_IN, DRAIN_SORTER, MERGE} Scenario deriving(Bits, Eq, FShow);

module mkStreamingMerge2Var#(Bool ascending, Integer level, Integer id)(Merge2Var#(iType, vSz)) provisos (
   Bits#(Vector::Vector#(vSz, iType), a__),
   Add#(1, c__, vSz),
   Ord#(iType),
   Bounded#(iType),
   Bitonic::RecursiveBitonic#(vSz, iType),
   TopHalfUnit::TopHalfUnitInstance#(vSz, iType)
   );
   
   //Vector#(2, FIFOF#(Vector#(vSz, iType))) vInQ <- replicateM(mkSizedFIFOF(128));
   //Vector#(2, FIFOF#(UInt#(32))) vLenQ <- replicateM(mkSizedFIFOF(128));
   Vector#(2, FIFOF#(Vector#(vSz, iType))) vInQ <- replicateM(mkFIFOF);
   Vector#(2, FIFOF#(UInt#(32))) vLenQ <- replicateM(mkFIFOF);

   
   Reg#(Maybe#(iType)) prevTail <- mkReg(tagged Invalid);
   Reg#(Bit#(1)) portSel <- mkRegU;
   
   Vector#(2, Reg#(UInt#(32))) vInCnt <- replicateM(mkReg(0));
   
   //FIFOF#(UInt#(32)) lenOutQ <- mkFIFOF;//mkSizedFIFOF(128);//(valueOf(TLog#(vSz))+3));
   FIFOF#(UInt#(32)) lenOutQ <- mkSizedFIFOF(valueOf(vSz)+2);
   
   StreamNode#(vSz, iType) sort_bitonic_pipeline <- mkSortBitonic(ascending);  
   // FIFOF#(Vector#(vSz, iType)) bitonicOutQ <- mkFIFOF;
   
   
   
   function t getFirst(FIFOF#(t) x)=x.first;
   function plusOne(x)=x+1;
   function sorter(x) = sort_bitonic(x, ascending);
   function Action doDeq(FIFOF#(t) x)=x.deq;
   
   Vector#(2, Reg#(iType)) prevMaxs = ?;
   if (debug) prevMaxs <- replicateM(mkReg(ascending?minBound:maxBound));
   
   TopHalfUnit#(vSz, iType) topHalfUnit <- mkTopHalfUnit;
   FIFO#(Tuple2#(Scenario, Vector#(vSz, iType))) selectedInQ <- mkSizedFIFO(valueOf(vSz)+2);
   
   rule mergeTwoInQs (!isValid(prevTail) );
      if ( vInQ[0].notEmpty) begin
         let v <- toGet(vInQ[0]).get;
         topHalfUnit.enqData(v, Init);         
         portSel <= 1;
         prevTail <= tagged Valid last(v);
         vInCnt[0] <= vInCnt[0] + 1;
      end
      else begin
         let v <- toGet(vInQ[1]).get;
         topHalfUnit.enqData(v, Init);
         portSel <= 0;
         prevTail <= tagged Valid last(v);
         vInCnt[1] <= vInCnt[1] + 1;
      end
   endrule
   
   Reg#(Bool) lenOutSent <- mkReg(False);

   rule mergeWithBuf (isValid(prevTail) );

      let prevTail_d = fromMaybe(?, prevTail);
      
      Vector#(vSz, iType) in = ?;
      
      Bool noInput = False;
      Maybe#(Bit#(1)) nextPortSel = tagged Invalid;
      if ( fold(\|| , zipWith(\< , readVReg(vInCnt), map(getFirst, vLenQ))) )  begin
         
         if ( !lenOutSent ) begin
            lenOutQ.enq(fold(\+ , map(getFirst, vLenQ)));
            lenOutSent <= True;
         end
         
         if ( portSel == 1 ) begin
            let inVec1 = vInQ[1].first;
            vInQ[1].deq;
            in = inVec1;
            vInCnt[1] <= vInCnt[1] + 1;
            if ( vInCnt[1] + 1 == vLenQ[1].first ) nextPortSel = tagged Valid 0;
            else if (vInCnt[0] == vLenQ[0].first ) nextPortSel = tagged Valid 1;
         end
         else begin
            let inVec0 = vInQ[0].first;
            in = inVec0;
            vInQ[0].deq;
            vInCnt[0] <= vInCnt[0] + 1;
            if ( vInCnt[0] + 1 == vLenQ[0].first ) nextPortSel = tagged Valid 1;
            else if (vInCnt[1] == vLenQ[1].first ) nextPortSel = tagged Valid 0;
         end
      end
      else begin
         mapM_(doDeq, vLenQ);
         if ( !lenOutSent ) begin
            lenOutQ.enq(fold(\+ , map(getFirst, vLenQ)));
         end

         lenOutSent <= False;         
         
         noInput = True;
         if ( vInQ[0].notEmpty) begin
            let v <- toGet(vInQ[0]).get;
            topHalfUnit.enqData(v, Init);
            prevTail <= tagged Valid last(v);
            vInCnt[0] <= 1;
            vInCnt[1] <= 0;
            portSel <= 1;
         end
         else if ( vInQ[1].notEmpty) begin
            let v <- toGet(vInQ[1]).get;
            topHalfUnit.enqData(v, Init);
            prevTail <= tagged Valid last(v);
            vInCnt[0] <= 0;
            vInCnt[1] <= 1;
            portSel <= 0;
         end
         else begin
            prevTail <= tagged Invalid;
            writeVReg(vInCnt, replicate(0));
         end
      end
      
      if ( noInput) begin
         selectedInQ.enq(tuple2(DRAIN_SORTER, ?));
      end
      else begin
         prevTail <= tagged Valid getTop(vec(prevTail_d, last(in)), ascending);
         topHalfUnit.enqData(in, Normal);
         selectedInQ.enq(tuple2(MERGE, in));
         if ( nextPortSel matches tagged Valid .sel ) begin
            portSel <= sel;
         end
         else if ( isSorted(vec(prevTail_d, last(in)), ascending) ) begin
            portSel <= ~portSel;
         end
      end
      
   endrule
   
   rule combWithTopHalf;
      let {scenario, in} <- toGet(selectedInQ).get;
      // $display("combWithTopHalf ",fshow(selectedInQ.first));
      Vector#(vSz, iType) out = ?;

      case (scenario)
         DRAIN_SORTER:
         begin
            let topHalf <- topHalfUnit.getCurrTop;
            out = topHalf;
            // $display("Drain Sorter  ", fshow(out));
         end
         MERGE:
         begin
            let topHalf <- topHalfUnit.getCurrTop;
            // $display("MergeWith topHalf ", fshow(topHalf));
            let cleaned = halfClean(vec(topHalf,in), ascending);
            out = cleaned[0];
         end
      endcase
      sort_bitonic_pipeline.inPipe.enq(out);
   endrule

   // function sortOut(x) = sort_bitonic(x, ascending);
   interface inStreams = zipWith(toVariableStreamIn, map(toPipeIn,vInQ), map(toPipeIn, vLenQ));
   // interface outStream = toVariableStreamOut(mapPipe(sorter, toPipeOut(bitonicOutQ)), toPipeOut(lenOutQ));
   interface outStream = toVariableStreamOut(sort_bitonic_pipeline.outPipe, toPipeOut(lenOutQ)); 
endmodule



