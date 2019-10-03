import Pipe::*;
import Vector::*;
import FIFO::*;
import FIFOF::*;
import Connectable::*;
import SpecialFIFOs::*;
import BuildVector::*;
import GetPut::*;
import Assert::*;

import Bitonic::*;

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
   module mkStreamingMergeNVar#(Bool descending, Integer level, Integer id)(MergeNVar#(iType,vSz,n));
endtypeclass


instance RecursiveMergerVar#(iType,vSz,2) provisos(
   Bitonic::RecursiveBitonic#(vSz, iType),
   Ord#(iType),
   Bounded#(iType),
   Add#(1, b__, vSz),
   Bits#(iType, c__),
   Mul#(vSz, c__, d__)
   );
   module mkStreamingMergeNVar#(Bool descending,  Integer level, Integer id)(MergeNVar#(iType,vSz,2));
      let merger <- mkStreamingMerge2Var(descending, level, id);
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
   Mul#(TDiv#(n, 2), 2, n)
);
   module mkStreamingMergeNVar#(Bool descending, Integer level, Integer id)(MergeNVar#(iType,vSz,n));
      Vector#(TDiv#(n,2), Merge2Var#(iType, vSz)) mergers <- zipWith3M(mkStreamingMerge2Var, replicate(descending), replicate(level), genVector());
   
      function VariableStreamOut#(vSz, iType) getPipeOut(Merge2Var#(iType, vSz) ifc) = ifc.outStream;
      function getPipeIn(ifc) = ifc.inStreams;
   
      MergeNVar#(iType, vSz, TDiv#(n,2)) mergeN_2 <- mkStreamingMergeNVar(descending, level+1, 0);

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

module mkStreamingMerge2Var#(Bool descending, Integer level, Integer id)(Merge2Var#(iType, vSz)) provisos (
   Bits#(Vector::Vector#(vSz, iType), a__),
   Add#(1, c__, vSz),
   Ord#(iType),
   Bounded#(iType),
   Bitonic::RecursiveBitonic#(vSz, iType)
   );
   
   Vector#(2, FIFOF#(Vector#(vSz, iType))) vInQ <- replicateM(mkFIFOF());
   Vector#(2, FIFOF#(UInt#(32))) vLenQ <- replicateM(mkFIFOF());
   
   Reg#(Maybe#(iType)) prevTail <- mkReg(tagged Invalid);
   Reg#(Bit#(1)) portSel <- mkRegU;
   
   Vector#(2, Reg#(UInt#(32))) vInCnt <- replicateM(mkReg(0));
   
   FIFOF#(UInt#(32)) lenOutQ <- mkFIFOF;//mkSizedFIFOF(128);//(valueOf(TLog#(vSz))+3));
   
   StreamNode#(vSz, iType) sort_bitonic_pipeline <- mkSortBitonic(descending);  
   // FIFOF#(Vector#(vSz, iType)) bitonicOutQ <- mkFIFOF;
   
   
   
   function t getFirst(FIFOF#(t) x)=x.first;
   function plusOne(x)=x+1;
   function sorter(x) = sort_bitonic(x, descending);
   function Action doDeq(FIFOF#(t) x)=x.deq;
   
   Vector#(2, Reg#(iType)) prevMaxs = ?;
   if (debug) prevMaxs <- replicateM(mkReg(descending?minBound:maxBound));
   
   
   FIFO#(Tuple2#(Scenario, Vector#(vSz, iType))) selectedInQ <- mkPipelineFIFO;
   Reg#(Vector#(vSz, iType)) rightOperand <- mkRegU;
   Vector#(2, Reg#(UInt#(32))) vLen <- replicateM(mkRegU);
   rule mergeTwoInQs (!isValid(prevTail));
      
      // if ( zipWith(\== ,readVReg(vInCnt), replicate(0)) == replicate(True) ) begin
      dynamicAssert( zipWith(\== ,readVReg(vInCnt), replicate(0)) == replicate(True), "only activated in the first cycle");
      if (debug) $display("(%m) merger %0d_%0d, vLens = ", level, id, fshow(map(getFirst, vLenQ)));
      lenOutQ.enq(fold(\+ , map(getFirst, vLenQ)));
      mapM_(doDeq, vLenQ);
      writeVReg(vLen, map(getFirst, vLenQ));
      // end
      
      function doGet(x) = x.get;
      let inVec <- mapM(doGet, map(toGet, vInQ));

      if (debug) begin
         writeVReg(prevMaxs, map(last, inVec));
         for (Integer i = 0; i < 2; i = i + 1) begin
            String msg="merger "+integerToString(level)+"_"+integerToString(id)+", stream_"+integerToString(i);
            dynamicAssert(isSorted(inVec[i], descending), msg+" is not sorted internally");
            dynamicAssert(isSorted(vec(prevMaxs[i], head(inVec[i])), descending), msg+" is not sorted externally");
         end
      end
      

      writeVReg(vInCnt, map(plusOne, readVReg(vInCnt)));
               
      let cleaned = halfClean(inVec, descending);
      selectedInQ.enq(tuple2(DRAIN_IN, cleaned[0]));
      rightOperand <= cleaned[1];
      
      // selectedInQ.enq(tuple2(DRAIN_IN, inVec[0]));
      // rightOperand <= inVec[1];
      prevTail <= tagged Valid getTop(vec(last(inVec[0]), last(inVec[1])),descending);
      portSel <= ~pack(isSorted(vec(last(inVec[0]), last(inVec[1])), descending));

      // bitonicOutQ.enq(cleaned[0]);
      // prevTopBuf <= tagged Valid sort_bitonic(cleaned[1], descending);
   endrule
   

   
   rule mergeWithBuf (isValid(prevTail));
      let prevTail_d = fromMaybe(?, prevTail);
      Vector#(vSz, iType) in = ?;
      
      // $display("vInCnts = ",fshow(readVReg(vInCnt)));
      // $display("VLenQ.first = ",fshow(map(getFirst, vLenQ)));
      
      Bool noInput = False;
      if (vInCnt[0] < vLen[0] && vInCnt[1] < vLen[1] ) begin
         let inVec0 = vInQ[0].first;
         let inVec1 = vInQ[1].first;
         in = inVec0;
         // $display("head(inVec0) = %d, head(inVec1) = %d, last(prev) = %d", head(inVec0), head(inVec1), last(prevTop));
         if ( portSel == 1 ) begin
         // if ( isSorted(vec(head(inVec1), last(prevTop)), descending) ) begin
            in = inVec1;
            vInCnt[1] <= vInCnt[1] + 1;
            vInQ[1].deq;
            if (debug) prevMaxs[1] <= last(in);
         end
         else begin
            vInCnt[0] <= vInCnt[0] + 1;
            vInQ[0].deq;
            if (debug) prevMaxs[0] <= last(in);
         end
         
         if (debug) begin
            Vector#(2, Vector#(vSz, iType)) inVec = vec(inVec0, inVec1);
            for (Integer i = 0; i < 2; i = i + 1) begin
               String msg="merger "+integerToString(level)+"_"+integerToString(id)+", stream_"+integerToString(i);
               dynamicAssert(isSorted(inVec[i], descending), msg+" is not sorted internally");
               dynamicAssert(isSorted(vec(prevMaxs[i], head(inVec[i])), descending), msg+" is not sorted externally");
            end
         end

      end
      else if ( vInCnt[0] < vLen[0] ) begin
         in <- toGet(vInQ[0]).get;
         vInCnt[0] <= vInCnt[0] + 1;
         if (debug) begin
            prevMaxs[0] <= last(in);
            String msg="merger "+integerToString(level)+"_"+integerToString(id)+", stream_"+integerToString(0);
            dynamicAssert(isSorted(in, descending), msg+" is not sorted internally");
            dynamicAssert(isSorted(vec(prevMaxs[0], head(in)), descending), msg+" is not sorted externally");
         end
      end
      else if (  vInCnt[1] < vLen[1] ) begin
         in <- toGet(vInQ[1]).get;
         vInCnt[1] <= vInCnt[1] + 1;
         if (debug) begin
            prevMaxs[1] <= last(in);
            String msg="merger "+integerToString(level)+"_"+integerToString(id)+", stream_"+integerToString(1);
            dynamicAssert(isSorted(in, descending), msg+" is not sorted internally");
            dynamicAssert(isSorted(vec(prevMaxs[1], head(in)), descending), msg+" is not sorted externally");
         end
      end
      else begin
         writeVReg(vInCnt, replicate(0));
         noInput = True;
         if ( debug ) writeVReg(prevMaxs, replicate(descending?minBound:maxBound));
      end
      
      if ( noInput) begin
         prevTail <= tagged Invalid;
         selectedInQ.enq(tuple2(DRAIN_SORTER, ?));
      end
      else begin
         prevTail <= tagged Valid getTop(vec(prevTail_d, last(in)), descending);
         selectedInQ.enq(tuple2(MERGE, in));
      end
      
      if ( isSorted(vec(prevTail_d, last(in)), descending)) begin
         portSel <= ~portSel;
      end
   endrule
   
   Reg#(Vector#(vSz, iType)) feedbackBuf <- mkRegU();
   rule doOutput;
      let {scenario, in} <- toGet(selectedInQ).get;
      // $display(fshow(scenario));
      Vector#(vSz, iType) feedback = ?;
      Vector#(vSz, iType) out = ?;
      case (scenario)
         DRAIN_IN: 
         begin
            feedback = rightOperand;
            out = in;
         end
         DRAIN_SORTER:
         begin
            out = feedbackBuf;
         end
         MERGE:
         begin
            let cleaned = halfClean(vec(feedbackBuf,in), descending);
            out = cleaned[0];
            feedback = cleaned[1];
         end
      endcase
      sort_bitonic_pipeline.inPipe.enq(out);
      // bitonicOutQ.enq(out);
      feedbackBuf <= sorter(feedback);
   endrule
   
   // function sortOut(x) = sort_bitonic(x, descending);
   interface inStreams = zipWith(toVariableStreamIn, map(toPipeIn,vInQ), map(toPipeIn, vLenQ));
   // interface outStream = toVariableStreamOut(mapPipe(sorter, toPipeOut(bitonicOutQ)), toPipeOut(lenOutQ));
   interface outStream = toVariableStreamOut(sort_bitonic_pipeline.outPipe, toPipeOut(lenOutQ)); 
endmodule



