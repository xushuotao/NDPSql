import Pipe::*;
import Vector::*;
import FIFOF::*;
import Connectable::*;
import SpecialFIFOs::*;
import BuildVector::*;
import GetPut::*;

import Bitonic::*;


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


interface MergeNVar#(type iType,
                     numeric type vSz,
                     numeric type n);
   interface Vector#(n, VariableStreamIn#(vSz, iType)) inStreams;
   interface VariableStreamOut#(vSz, iType) outStream;
endinterface



// typeclass RecursiveMergerVar#(type iType,
//                               numeric type vSz,
//                               numeric type n);
// ////////////////////////////////////////////////////////////////////////////////
// /// module:      mkStreamingMergeNVar
// /// Description: this module takes N in-streams, each has sorted elements of 
// ///              variable length of l_i streaming @ vSz elements per beat, and 
// ///              merge them  into a single sorted out-stream of sum(l_i) elements 
// ///              with a binary merge-tree
// ////////////////////////////////////////////////////////////////////////////////
//    module mkStreamingMergeNVar#(Bool descending)(MergeNVar#(iType,vSz,n));
// endtypeclass


// instance RecursiveMergerVar#(iType,vSz,2) provisos(
//    Bitonic::RecursiveBitonic#(vSz, iType),
//    Ord#(iType),
//    Add#(vSz, a__, sortedSz),
//    Add#(1, b__, vSz),
//    Bits#(iType, c__),
//    Mul#(vSz, c__, d__)
//    );
//    module mkStreamingMergeNVar#(Bool descending)(MergeNVar#(iType,vSz,sortedSz,2));
//       let merger <- mkStreamingMerge2Var(descending);
//       return merger;
//    endmodule
// endinstance

// // NORMAL CASE
// instance RecursiveMergerVar#(iType,vSz,n) provisos (
//    Add#(2, a__, n),               // n >= 2
//    NumAlias#(TExp#(TLog#(n)), n), //n is power of 2
//    Bitonic::RecursiveBitonic#(vSz, iType),
//    Ord#(iType),
//    Add#(vSz, b__, sortedSz),
//    Add#(1, c__, vSz),
//    Bits#(iType, d__),
//    Mul#(vSz, d__, e__),
//    MergeSort::RecursiveMergerVar#(iType, vSz, TDiv#(n, 2)),
//    Mul#(TDiv#(n, 2), 2, n)
// );
//    module mkStreamingMergeNVar#(Bool descending)(MergeNVar#(iType,vSz,sortedSz,n));
//       Vector#(TDiv#(n,2), Merge2#(iType, vSz, sortedSz)) mergers <- replicateM(mkStreamingMerge2(descending));
   
//       function VariableStreamOut getPipeOut(Merge2Var#(iType, vSz, sortedSz) ifc) = ifc.outStream;
//       function getPipeIn(ifc) = ifc.inStreams;
   
//       MergeNVar#(iType, vSz, TMul#(sortedSz,2), TDiv#(n,2)) mergeN_2 <- mkStreamingMergeNVar(descending);

//       zipWithM_(mkConnection, map(getPipeOut,mergers), mergeN_2.inStreams);
   
//       MergeNVar#(iType,vSz,sortedSz,n) retifc = (interface MergeNVar;
//                                                  interface inStreams = concat(map(getPipeIn,mergers));
//                                                  interface outStream = mergeN_2.outStream;
//                                              endinterface);
//       return retifc;
//    endmodule
// endinstance

// merge two sorted streams of same size of sortedSz
typedef MergeNVar#(iType, vSz, 2) Merge2Var#(type iType,
                                             numeric type vSz); 



module mkStreamingMerge2Var#(Bool descending)(Merge2Var#(iType, vSz)) provisos (
   Bits#(Vector::Vector#(vSz, iType), a__),
   Add#(1, c__, vSz),
   Ord#(iType),
   Eq#(iType),
   Bitonic::RecursiveBitonic#(vSz, iType)
   );
   
   Vector#(2, FIFOF#(Vector#(vSz, iType))) vInQ <- replicateM(mkPipelineFIFOF);
   Vector#(2, FIFOF#(UInt#(32))) vLenQ <- replicateM(mkPipelineFIFOF);
   
   Reg#(Maybe#(Vector#(vSz, iType))) prevTopBuf <- mkReg(tagged Invalid);
   
   Vector#(2, Reg#(UInt#(32))) vInCnt <- replicateM(mkReg(0));
   
   FIFOF#(Vector#(vSz, iType)) bitonicOutQ <- mkFIFOF;
   FIFOF#(UInt#(32)) lenOutQ <- mkFIFOF;
   
   
   function t getFirst(FIFOF#(t) x)=x.first;
   function plusOne(x)=x+1;
   rule mergeTwoInQs (!isValid(prevTopBuf) && 
                      vInCnt[0] < vLenQ[0].first &&
                      vInCnt[1] < vLenQ[1].first );
      

      if ( zipWith(\== ,readVReg(vInCnt), replicate(0)) == replicate(True) )
         lenOutQ.enq(fold(\+ , map(getFirst, vLenQ)));
      
      function doGet(x) = x.get;
      let inVec <- mapM(doGet, map(toGet, vInQ));

      writeVReg(vInCnt, map(plusOne, readVReg(vInCnt)));
         
      let cleaned = halfClean(inVec, descending);
      bitonicOutQ.enq(cleaned[0]);
      prevTopBuf <= tagged Valid sort_bitonic(cleaned[1], descending);
   endrule
   
   function Action doDeq(FIFOF#(t) x)=x.deq;
   
   rule mergeWithBuf (isValid(prevTopBuf));
      let prevTop = fromMaybe(?, prevTopBuf);
      Vector#(vSz, iType) in = ?;
      
      // $display("vInCnts = ",fshow(readVReg(vInCnt)));
      // $display("VLenQ.first = ",fshow(map(getFirst, vLenQ)));
      
      Bool noInput = False;
      if (vInCnt[0] < vLenQ[0].first && vInCnt[1] < vLenQ[1].first ) begin
         let inVec0 = vInQ[0].first;
         let inVec1 = vInQ[1].first;
         in = inVec0;
         // $display("head(inVec0) = %d, head(inVec1) = %d, last(prev) = %d", head(inVec0), head(inVec1), last(prevTop));
         if ( isSorted(vec(head(inVec1), last(prevTop)), descending) ) begin
            in = inVec1;
            vInCnt[1] <= vInCnt[1] + 1;
            vInQ[1].deq;
         end
         else begin
            vInCnt[0] <= vInCnt[0] + 1;
            vInQ[0].deq;
         end
         
      end
      else if ( vInCnt[0] < vLenQ[0].first ) begin
         in <- toGet(vInQ[0]).get;
         vInCnt[0] <= vInCnt[0] + 1;
      end
      else if (  vInCnt[1] < vLenQ[1].first ) begin
         in <- toGet(vInQ[1]).get;
         vInCnt[1] <= vInCnt[1] + 1;
      end
      else begin
         writeVReg(vInCnt, replicate(0));
         mapM_(doDeq, vLenQ);         
         noInput = True;
      end
      
      if ( noInput) begin
         prevTopBuf <= tagged Invalid;
         bitonicOutQ.enq(prevTop);
      end
      else begin
         let cleaned = halfClean(vec(prevTop,in), descending);
         bitonicOutQ.enq(cleaned[0]);
         prevTopBuf <= tagged Valid sort_bitonic(cleaned[1], descending);
      end
   endrule
   
   // rule dumpQ0 (!isValid(prevTopBuf) && 
   //              vInCnt[0] < vLenQ[0].first &&
   //              vInCnt[1] == vLenQ[1].first );
 
   //    let in <- toGet(vInQ[0]).get;

   //    if ( vInCnt[0] + 1 == vLenQ[0].first ) begin
   //       mapM_(doDeq, vLenQ);
   //       writeVReg(vInCnt, replicate(0));         
   //    end

   //    bitonicOutQ.enq(in);
   // endrule


   // rule dumpQ1 (!isValid(prevTopBuf) && 
   //              vInCnt[1] < vLenQ[1].first &&
   //              vInCnt[0] == vLenQ[0].first );
 
   //    let in <- toGet(vInQ[1]).get;

   //    if ( vInCnt[1] + 1 == vLenQ[1].first ) begin
   //       mapM_(doDeq, vLenQ);
   //       writeVReg(vInCnt, replicate(0));         
   //    end
   //    bitonicOutQ.enq(in);
   // endrule
   
   function sortOut(x) = sort_bitonic(x, descending);
   interface inStreams = zipWith(toVariableStreamIn, map(toPipeIn,vInQ), map(toPipeIn, vLenQ));
   interface outStream = toVariableStreamOut(mapPipe(sortOut, toPipeOut(bitonicOutQ)), toPipeOut(lenOutQ));
endmodule



