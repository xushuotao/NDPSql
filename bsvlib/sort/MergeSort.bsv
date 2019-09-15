import Pipe::*;
import FIFOF::*;
import SpecialFIFOs::*;
import GetPut::*;
import Vector::*;
import BuildVector::*;

import Bitonic::*;

Bool debug = False;

// merge two sorted streams of same size of totalcnt
interface Merge#(type iType,
                 numeric type incnt,
                 numeric type totalcnt);
   interface Vector#(2, PipeIn#(Vector#(incnt, iType))) inPipes;
   interface PipeOut#(Vector#(incnt, iType)) outPipe;
endinterface

module mkStreamingMerge#(Bool descending)(Merge#(iType, incnt, totalcnt))
   provisos(Bits#(Vector::Vector#(incnt, iType), a__),
            Add#(1, c__, incnt),
            Div#(totalcnt, incnt, totalbeats),
            Add#(incnt, e__, totalcnt),
            Ord#(iType),
            RecursiveBitonic#(incnt, iType),
            FShow#(Vector::Vector#(incnt, iType)));
   Vector#(2, FIFOF#(Vector#(incnt, iType))) vInQ <- replicateM(mkPipelineFIFOF);

   Reg#(Maybe#(Vector#(incnt, iType))) prevTopBuf <- mkReg(tagged Invalid);
   
   Integer initCnt = valueOf(totalbeats);
   
   Vector#(2, Reg#(Bit#(TLog#(TAdd#(totalbeats,1))))) vInCnt <- replicateM(mkReg(fromInteger(initCnt)));
   
   FIFOF#(Vector#(incnt, iType)) bitonicOutQ <- mkFIFOF;
   
   function gtZero(cnt)=(cnt > 0);
   function minusOne(x)=x-1;
   
   rule mergeTwoInQs (!isValid(prevTopBuf) && all(gtZero, readVReg(vInCnt)));
      let inVec0 <- toGet(vInQ[0]).get;
      let inVec1 <- toGet(vInQ[1]).get;
      writeVReg(vInCnt, map(minusOne, readVReg(vInCnt)));
      
      let cleaned = halfClean(vec(inVec0,inVec1), descending);
      if (debug) $display("(%m @%t) mergeTwoInQs inVec0, inVec1 = ", $time, fshow(inVec0), fshow(inVec1));
      bitonicOutQ.enq(cleaned[0]);
      prevTopBuf <= tagged Valid sort_bitonic(cleaned[1], descending);
   endrule

   rule mergeWithBuf (isValid(prevTopBuf));
      let prevTop = fromMaybe(?, prevTopBuf);
      
      Vector#(incnt, iType) in = ?;
      
      Bool noInput = False;
      if (debug) $display("(%m @%t) mergeWithBuf vInCnt = ", $time, fshow(readVReg(vInCnt)));
      if ( all(gtZero, readVReg(vInCnt)) ) begin
         let inVec0 = vInQ[0].first;
         let inVec1 = vInQ[1].first;
         in = inVec0;
         if ( isSorted(vec(last(prevTop), head(inVec0)), descending) ) begin
            in = inVec1;
            vInCnt[1] <= vInCnt[1] - 1;
            vInQ[1].deq;
         end
         else begin
            vInCnt[0] <= vInCnt[0] - 1;
            vInQ[0].deq;
         end
      end
      else if ( vInCnt[0] > 0 ) begin
         in <- toGet(vInQ[0]).get;
         vInCnt[0] <= vInCnt[0] - 1;
      end
      else if ( vInCnt[1] > 0 // && vInCnt[0] == 0 && vInQ[1].notEmpty 
         ) begin
         in <- toGet(vInQ[1]).get;
         vInCnt[1] <= vInCnt[1] - 1;
      end
      else
         begin
         writeVReg(vInCnt, map(fromInteger, replicate(initCnt)));
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
   
   function sortOut(x) = sort_bitonic(x, descending);
   interface inPipes = map(toPipeIn, vInQ);
   interface PipeOut outPipe = mapPipe(sortOut, toPipeOut(bitonicOutQ));
endmodule
