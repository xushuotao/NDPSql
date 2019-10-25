// import TopHalfUnitSMT::*;
import SorterTypes::*;
import Pipe::*;
import Bitonic::*;
import FIFO::*;
import FIFOF::*;
import BRAMFIFO::*;
import SpecialFIFOs::*;
import Vector::*;
import Connectable::*;
import GetPut::*;
import BuildVector::*;
import RWBramCore::*;
import Assert::*;
import DelayPipe::*;
import OneToNRouter::*;
import NToOneRouter::*;
import BRAMFIFOFVector::*;

import ClientServer::*;
import MergerScheduler::*;
import MergerCore::*;

Bool debug = False;

interface MergerSMTInput#(numeric type numTags, numeric type vSz, type iType);
   interface Vector#(numTags, Vector#(2, PipeOut#(void))) ready;
   method Action inputResp(UInt#(TLog#(numTags)) tag, SortedPacket#(vSz, iType) d);
endinterface

interface MergerSMTOutput#(numeric type numTags, numeric type vSz, type iType);
   interface Vector#(numTags, PipeOut#(void)) ready;
   interface Server#(UInt#(TLog#(numTags)), SortedPacket#(vSz, iType)) server;
endinterface


instance Connectable#(MergerSMTOutput#(numTags, vSz, iType), MergerSMTInput#(TDiv#(numTags,2), vSz, iType));
   module mkConnection#(MergerSMTOutput#(numTags, vSz, iType) out, MergerSMTInput#(TDiv#(numTags,2), vSz, iType) in)(Empty);
      function Bool extractPipeOutReady(PipeOut#(t) ifc) = ifc.notEmpty;
   
      function Bool extractPipeInReady(PipeIn#(t) ifc) = ifc.notFull;
      
      FIFO#(UInt#(TLog#(TDiv#(numTags,2)))) tagQ <- mkFIFO;
      
      for (Integer i = 0; i < valueOf(numTags); i = i + 1 ) begin
         rule doSendReq if ( out.ready[i].notEmpty && in.ready[i/2][i%2].notEmpty );
            out.ready[i].deq;
            in.ready[i/2][i%2].deq;
            out.server.request.put(fromInteger(i));
            tagQ.enq(fromInteger(i/2));
         endrule
      end
      
      rule doResp;
         let tag <- toGet(tagQ).get;
         let d <- out.server.response.get;
         in.inputResp(tag, d);
      endrule
   endmodule
endinstance


interface MergeNSMTSched#(type iType,
                     numeric type vSz,
                     numeric type n);
   
   interface MergerSMTInput#(n, vSz, iType) in;
   interface MergerSMTOutput#(1, vSz, iType) out;
endinterface

typeclass RecursiveMergerSMTSched#(type iType,
                              numeric type vSz,
                              numeric type n);
////////////////////////////////////////////////////////////////////////////////
/// module:      mkStreamingMergeN
/// Description: this module takes N in-streams, each has sorted elements of 
///              sortedSz streaming @ vSz elements per beat, and merge them into 
///              a single sorted out-stream of N*sortedSz elements with a binary
///              merge-tree
////////////////////////////////////////////////////////////////////////////////
   module mkMergeNSMTSched#(Bool ascending, Integer level)(MergeNSMTSched#(iType,vSz,n));
endtypeclass

// typedef TAdd#(10, TAdd#(vSz, TLog#(vSz))) BufSize#(numeric type vSz);
typedef TExp#(TLog#(TAdd#(6, TAdd#(vSz, TLog#(vSz))))) BufSize#(numeric type vSz);


instance RecursiveMergerSMTSched#(iType, vSz, 1) provisos(
   NumAlias#(TExp#(TLog#(BufSize#(vSz))), BufSize#(vSz)),

   TopHalfUnitSMT::TopHalfUnitSMTInstance#(1, vSz, iType),
   Add#(1, a__, vSz),
   Bits#(Tuple3#(Vector::Vector#(vSz, iType), Bool, Bool), b__),
   Add#(1, c__, b__),
   Add#(1, d__, TLog#(vSz)),
   Bitonic::RecursiveBitonic#(vSz, iType),
   Bits#(iType, typeSz),
   FShow#(iType),
   Ord#(iType)
);
   module mkMergeNSMTSched#(Bool ascending, Integer level)(MergeNSMTSched#(iType,vSz,1));
      MergerSMTSched#(1, BufSize#(vSz), vSz, iType) merger_worker <- mkMergerSMTSched(ascending, level);
      interface in = merger_worker.in;
      interface out = merger_worker.out;
   endmodule
endinstance


instance RecursiveMergerSMTSched#(iType, vSz, n) provisos(
   NumAlias#(TExp#(TLog#(BufSize#(vSz))), BufSize#(vSz)),

   // Add#(1, e__, TDiv#(n, 2)),
   // Add#(1, f__, TMul#(TDiv#(TDiv#(n, 2), 2), 2)),
   // Add#(TDiv#(n, 2), g__, TMul#(TDiv#(TDiv#(n, 2), 2), 2)),

   Mul#(TDiv#(n, 2), 2, n),
   MergerSMTSched::RecursiveMergerSMTSched#(iType, vSz, TDiv#(n, 2)),
   TopHalfUnitSMT::TopHalfUnitSMTInstance#(n, vSz, iType),
   Add#(1, a__, vSz),
   Bits#(Tuple3#(Vector::Vector#(vSz, iType), Bool, Bool), b__),
   Add#(1, c__, b__),
   Add#(1, d__, TLog#(vSz)),
   Bitonic::RecursiveBitonic#(vSz, iType),
   FShow#(iType),
   Ord#(iType)
);
   module mkMergeNSMTSched#(Bool ascending, Integer level)(MergeNSMTSched#(iType,vSz,n));
   
      MergerSMTSched#(n, BufSize#(vSz), vSz, iType) merger_worker <- mkMergerSMTSched(ascending, level);
   
      MergeNSMTSched#(iType,vSz,TDiv#(n,2)) mergerN_2 <- mkMergeNSMTSched(ascending, level+1);
   
      mkConnection(merger_worker.out, mergerN_2.in);
   
      interface in = merger_worker.in;
      interface out = mergerN_2.out;
   endmodule
endinstance


interface MergerSMTSched#(numeric type numTags,
                     numeric type tagBufSz,
                     numeric type vSz,
                     type iType);
   interface MergerSMTInput#(numTags, vSz, iType) in;
   interface MergerSMTOutput#(numTags, vSz, iType) out;
endinterface


module mkMergerSMTSched#(Bool ascending, Integer level)(MergerSMTSched#(numTags, tagBufSz, vSz, iType)) provisos(
   NumAlias#(TExp#(TLog#(numTags)), numTags),
   NumAlias#(TExp#(TLog#(tagBufSz)), tagBufSz),
   Alias#(UInt#(TLog#(numTags)), tagT),
   Add#(1, a__, vSz),
   Bits#(Tuple3#(Vector::Vector#(vSz, iType), Bool, Bool), b__),
   Add#(1, c__, b__),
   Bitonic::RecursiveBitonic#(vSz, iType),
   TopHalfUnitSMT::TopHalfUnitSMTInstance#(numTags, vSz, iType),
   Add#(1, d__, TLog#(vSz)),
   FShow#(iType),
   Ord#(iType)
   );
   String tab = "";
   for ( Integer l = 0; l < level; l = l + 1 ) tab = tab + "\t";

   
   Vector#(numTags, MergerSched#(tagBufSz, iType)) schedulers <- replicateM(mkMergerScheduler(True));
   
   MergerCore#(numTags, vSz, iType) mergerCore <- mkUGMergeCore(ascending, level);
   
   BRAMFIFOFAsyncVector#(TLog#(numTags), tagBufSz, SortedPacket#(vSz, iType)) buffer <- mkUGBRAMFIFOFAsyncVector;

   
   Vector#(numTags, Reg#(Maybe#(iType))) prevMax <- replicateM(mkReg(tagged Invalid));
   (* fire_when_enabled *)//, no_implicit_conditions *)
   rule doEnqBuf (mergerCore.outPipe.notEmpty);//(sorter.outPipe.notEmpty);
                    
      let {packet, tag} = mergerCore.outPipe.first;
      mergerCore.outPipe.deq;
      
      buffer.enq(packet, tag);
      
      // Below are debuggers
      if (debug) $display("(%t) %s[%0d-%0d]Out:: first = %d, last = %d, (prevMax, currHead) = ", $time, tab, level, tag, packet.first, packet.last, fshow(prevMax[tag]), " ", fshow(packet.d[0]));
      dynamicAssert(isSorted(packet.d, ascending), "beat should be sorted internally");
      if ( debug ) begin
         prevMax[tag] <= packet.last ? tagged Invalid : tagged Valid packet.d[valueOf(vSz)-1];
         if ( prevMax[tag] matches tagged Valid .v) begin
            dynamicAssert(isSorted(vec(v, packet.d[0]), ascending), "beats should be sorted externally");         
         end
      end
   endrule
   
   
   Vector#(numTags, Reg#(Bool)) isFirst <- replicateM(mkReg(True));
   Vector#(numTags, Reg#(Bool)) doneOne <- replicateM(mkReg(False));
   
   function Vector#(2, PipeOut#(void)) takeReadys(MergerSched#(tagBufSz, iType) ifc);
      return ifc.nextReq;
   endfunction
   
   Reg#(tagT) rdTag <- mkRegU;
   
   interface MergerSMTInput in;
      interface ready = map(takeReadys, schedulers);
      method Action inputResp(UInt#(TLog#(numTags)) tag, SortedPacket#(vSz, iType) packet);
         schedulers[tag].update(last(packet.d), packet.last);
         mergerCore.enq(packet.d, tag, isFirst[tag], !isFirst[tag]&&packet.first, doneOne[tag]&&packet.last);
         if ( !doneOne[tag] && packet.last ) doneOne[tag] <= True;
         if ( doneOne[tag] && packet.last) begin doneOne[tag] <= False; isFirst[tag] <= True; end
         else if ( isFirst[tag] ) isFirst[tag] <= False;
      endmethod
   endinterface

   interface MergerSMTOutput out;
      interface ready = buffer.rdReady;
      interface Server server;
         interface Put request;
            method Action put(tagT tag);
               buffer.rdServer.request.put(tag);
               rdTag <= tag;
            endmethod
         endinterface
         interface Get response;
            method ActionValue#(SortedPacket#(vSz,iType)) get;
               let d <- buffer.rdServer.response.get;
               schedulers[rdTag].incrCredit;
               return d;
            endmethod
         endinterface
      endinterface
   endinterface
endmodule
