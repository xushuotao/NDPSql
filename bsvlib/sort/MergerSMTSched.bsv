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
import MergerSchedulerTypes::*;
import MergerScheduler::*;
import MergerCore::*;



`ifdef DEBUG
Bool debug = False;
`else 
Bool debug = True;
`endif

typedef struct{
   UInt#(TLog#(numTags)) tag;
   SortedPacket#(vSz, iType) packet;
} TaggedSortedPacket#(numeric type numTags, numeric type vSz, type iType) deriving (FShow, Bits, Eq);

interface MergerSMTInput#(numeric type numTags, numeric type vSz, type iType);
   // interface Vector#(numTags, Vector#(2, PipeIn#(SchedReq#(iType)))) scheduleReq;
   // interface Vector#(numTags, PipeOut#(Bit#(1))) scheduleResp;
   interface PipeIn#(TaggedSchedReq#(TMul#(numTags,2), iType)) scheduleReq;
   interface PipeOut#(UInt#(TLog#(TMul#(numTags,2)))) scheduleResp;
   
   interface PipeIn#(TaggedSortedPacket#(numTags,vSz, iType)) dataChannel;
endinterface

interface MergerSMTOutput#(numeric type numTags, numeric type vSz, type iType);
   // interface Vector#(numTags, PipeOut#(SchedReq#(iType))) scheduleReq;
   interface PipeOut#(TaggedSchedReq#(numTags, iType)) scheduleReq;
   
   interface Server#(UInt#(TLog#(numTags)), TaggedSortedPacket#(numTags, vSz, iType)) server; 
   // interface PipeIn#(UInt#(TLog#(numTag))) dataReq;
   // interface PipeOut#(TaggedSortedPacket#(numTags, vSz, iType)) dataResp;
endinterface


instance Connectable#(MergerSMTOutput#(numTags, vSz, iType), MergerSMTInput#(TDiv#(numTags,2), vSz, iType)) provisos(
   //Add#(TLog#(numTags), a__, TLog#(TMul#(numTags, 2)))
   NumAlias#(numTags, TMul#(TDiv#(numTags, 2),2)),
   Log#(TMul#(TDiv#(numTags, 2), 2), TLog#(numTags)),
   Add#(TLog#(TDiv#(numTags, 2)), a__, TLog#(numTags))
   );
   module mkConnection#(MergerSMTOutput#(numTags, vSz, iType) out, MergerSMTInput#(TDiv#(numTags,2), vSz, iType) in)(Empty);
      rule mkConnect;
         let req = out.scheduleReq.first;
         out.scheduleReq.deq;
         in.scheduleReq.enq(req);
      endrule
   
      // for (Integer i = 0; i < valueOf(numTags)/2; i = i + 1 ) begin
      rule issueRdReq if ( in.scheduleResp.notEmpty );
         let tag = in.scheduleResp.first;
         in.scheduleResp.deq;
         // Bit#(TLog#(TDiv#(numTags,2))) tag = fromInteger(i);
         out.server.request.put(tag);
         `ifdef DEBUG
         $display("issueRdReq back to tag = %d", tag);
         `endif
      endrule
      // end
   
      rule doResp;// if (out.dataResp.notEmpty);
         let d <- out.server.response.get;
         in.dataChannel.enq(TaggedSortedPacket{packet:d.packet, tag:unpack(truncateLSB(pack(d.tag)))});
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
   module mkMergeNSMTSched#(Bool ascending , Integer level)(MergeNSMTSched#(iType,vSz,n));
endtypeclass


instance RecursiveMergerSMTSched#(iType, vSz, 1) provisos(
   Bits#(iType, typeSz),
   FShow#(iType),
   Ord#(iType),
   TopHalfUnitSMT::TopHalfUnitSMTInstance#(1, vSz, iType),
   Bitonic::RecursiveBitonic#(vSz, iType),
   Add#(1, a__, vSz),
   Add#(b__, TLog#(BufSize#(vSz)), TLog#(TMul#(1, BufSize#(vSz)))),
   MergerSMTSched::MergerSMTSchedInstance#(1, BufSize#(vSz), vSz, iType)

);
   module mkMergeNSMTSched#(Bool ascending, Integer level)(MergeNSMTSched#(iType,vSz,1));
      MergerSMTSched#(1, BufSize#(vSz), vSz, iType) merger_worker <- mkMergerSMTSched(ascending
                                                                                      `ifdef DEBUG
                                                                                      ,level
                                                                                      `endif
                                                                                      );
      interface in = merger_worker.in;
      interface out = merger_worker.out;
   endmodule
endinstance


instance RecursiveMergerSMTSched#(iType, vSz, n) provisos(
   Bits#(iType, typeSz),
   FShow#(iType),
   Ord#(iType),
   TopHalfUnitSMT::TopHalfUnitSMTInstance#(n, vSz, iType),
   Bitonic::RecursiveBitonic#(vSz, iType),
   Connectable::Connectable#(MergerSMTSched::MergerSMTOutput#(n, vSz, iType),
                             MergerSMTSched::MergerSMTInput#(TDiv#(n, 2), vSz, iType)),
   MergerSMTSched::RecursiveMergerSMTSched#(iType, vSz, TDiv#(n, 2)),
   Add#(1, a__, vSz),
   Add#(b__, TLog#(BufSize#(vSz)), TLog#(TMul#(TExp#(TLog#(n)), BufSize#(vSz)))),
   MergerSMTSched::MergerSMTSchedInstance#(n, BufSize#(vSz), vSz, iType)
   );
   module mkMergeNSMTSched#(Bool ascending, Integer level)(MergeNSMTSched#(iType,vSz,n));
   
      MergerSMTSched#(n, BufSize#(vSz), vSz, iType) merger_worker <- mkMergerSMTSched(ascending
                                                                                      `ifdef DEBUG
                                                                                      , level
                                                                                      `endif
                                                                                      );
   
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


module mkMergerSMTSched_Impl#(Bool ascending
                              `ifdef DEBUG
                              , Integer level
                              `endif
                              )(MergerSMTSched#(numTags, tagBufSz, vSz, iType)) 
   provisos(
      Bits#(iType, typeSz),
      FShow#(iType),
      Ord#(iType),
      Bitonic::RecursiveBitonic#(vSz, iType),
      TopHalfUnitSMT::TopHalfUnitSMTInstance#(numTags, vSz, iType),
      MergerScheduler::MergerSchedInstance#(tagBufSz, iType),
      Add#(1, a__, vSz),
      Add#(1, b__, numTags),

   
      // NumAlias#(TExp#(TLog#(tagBufSz)), tagBufSz),
      Add#(e__, TLog#(tagBufSz), TLog#(TMul#(TExp#(TLog#(numTags)), tagBufSz))),
   
      NumAlias#(TExp#(TLog#(numTags)), numTags),
      Alias#(UInt#(TLog#(numTags)), tagT)
      );
   String tab = "";
   `ifdef DEBUG
   for ( Integer l = 0; l < level; l = l + 1 ) tab = tab + "\t";
   `endif
   
   MergerSchedVector#(numTags, tagBufSz, iType) scheduler <- mkMergerSchedVector(ascending
                                                                                 `ifdef DEBUG
                                                                                 , level
                                                                                 `endif
                                                                                 );
   
   MergerCore#(numTags, vSz, iType) mergerCore <- mkUGMergeCore(ascending
                                                                `ifdef DEBUG
                                                                , level
                                                                `endif
                                                                );
   
   BRAMVector#(TLog#(numTags), tagBufSz, SortedPacket#(vSz, iType)) buffer <- mkUGPipelinedBRAMVector;
   // BRAMVector#(TLog#(numTags), tagBufSz, SortedPacket#(vSz, iType)) buffer <- mkUGBRAMVector;
   
   // Vector#(numTags, FIFOF#(SchedReq#(iType))) schedReqQ <- replicateM(mkSizedFIFOF(valueOf(tagBufSz)+1));
   FIFOF#(TaggedSchedReq#(numTags, iType)) schedReqQ <- mkSizedFIFOF(3);

   `ifdef DEBUG
   Vector#(numTags, Reg#(Maybe#(iType))) prevMax <- replicateM(mkReg(tagged Invalid));
   `endif
   
   //DelayPipe#(2, Tuple2#(SortedPacket#(vSz, iType), tagT)) bufferEnqDelay <- mkDelayPipe;
   (* fire_when_enabled *)//, no_implicit_conditions *)
   rule doEnqBuf (mergerCore.outPipe.notEmpty);//(sorter.outPipe.notEmpty);
      let {packet, tag} = mergerCore.outPipe.first;
      mergerCore.outPipe.deq;
      
      schedReqQ.enq(TaggedSchedReq{tag: tag, topItem: last(packet.d), last: packet.last});
      
      // bufferEnqDelay.enq(tuple2(packet, tag));
      buffer.enq(packet, tag);
      // Below are debuggers
      `ifdef DEBUG
      $display("(%t) %s[%0d-%0d]Out:: first = %d, last = %d, (prevMax, currHead) = ", $time, tab, level, tag, packet.first, packet.last, fshow(prevMax[tag]), " ", fshow(packet.d[0]));
      dynamicAssert(isSorted(packet.d, ascending), "beat should be sorted internally");
      // if ( debug ) begin
      prevMax[tag] <= packet.last ? tagged Invalid : tagged Valid packet.d[valueOf(vSz)-1];
      if ( prevMax[tag] matches tagged Valid .v) begin
         dynamicAssert(isSorted(vec(v, packet.d[0]), ascending), "beats should be sorted externally");         
      end
      `endif
      // end
   endrule
   
   // rule doIssueEnq if (bufferEnqDelay.notEmpty);
   //    let {packet, tag} = bufferEnqDelay.first;
   //    bufferEnqDelay.deq;
   //    buffer.enq(packet,tag);
   // endrule
   
   Vector#(numTags, Reg#(Bool)) isFirst <- replicateM(mkReg(True));
   Vector#(numTags, Reg#(Bool)) doneOne <- replicateM(mkReg(False));
   
   FIFOF#(tagT) rdTagQ <- mkUGSizedFIFOF(3);
   // Reg#(tagT) rdTag <- mkRegU;

   // function getSchedReq(x) = x.schedReq;
   // function getSchedResp(x) = x.schedResp;
   
   interface MergerSMTInput in;
      interface scheduleReq = scheduler.schedReq;
      interface scheduleResp = scheduler.schedResp;
   
      interface PipeIn dataChannel;
         method Action enq(TaggedSortedPacket#(numTags, vSz,iType) v);
            let tag = v.tag;
            let packet = v.packet;
            // if (debug) $display("(%t) %s[%0d-%0d]In:: first = %d, last = %d, (prevMax, currHead) = ", $time, tab, level, tag, packet.first, packet.last, fshow(prevMax[tag]), " ", fshow(packet.d[0]));
            mergerCore.enq(packet.d, tag, isFirst[tag], !isFirst[tag]&&packet.first, doneOne[tag]&&packet.last);
            if ( !doneOne[tag] && packet.last ) doneOne[tag] <= True;
            if ( doneOne[tag] && packet.last) begin doneOne[tag] <= False; isFirst[tag] <= True; end
            else if ( isFirst[tag] ) isFirst[tag] <= False;
         endmethod
         method Bool notFull = True;
      endinterface
   endinterface

   interface MergerSMTOutput out;
      interface scheduleReq = toPipeOut(schedReqQ);

      interface Server server;
         interface Put request;
            method Action put(tagT tag);
               `ifdef DEBUG
               $display("(%t) %s[%0d-%0d]server:: readReq ", $time, tab, level, tag);
               `endif
               scheduler.incrCredit(tag);
               buffer.rdServer.request.put(tag);
               // rdTag <= tag;
               rdTagQ.enq(tag);
            endmethod
         endinterface
         interface Get response;
            method ActionValue#(TaggedSortedPacket#(numTags, vSz,iType)) get;
               let tag <- toGet(rdTagQ).get;
               // let tag = rdTag._read;
               // scheduler.incrCredit(tag);
               let d <- buffer.rdServer.response.get;
               return TaggedSortedPacket{packet: d, tag: tag};
            endmethod
         endinterface
      endinterface
   endinterface
endmodule


typeclass MergerSMTSchedInstance#(numeric type numTags, numeric type tagBufSz, numeric type vSz, type iType);
   module mkMergerSMTSched#(Bool ascending
      `ifdef DEBUG
      , Integer level
      `endif
      )(MergerSMTSched#(numTags, tagBufSz, vSz, iType));
endtypeclass

instance MergerSMTSchedInstance#(numTags, tagBufSz, vSz, iType) provisos(
   Bits#(iType, typeSz),
   FShow#(iType),
   Ord#(iType),
   Bitonic::RecursiveBitonic#(vSz, iType),
   TopHalfUnitSMT::TopHalfUnitSMTInstance#(numTags, vSz, iType),
   MergerScheduler::MergerSchedInstance#(tagBufSz, iType),
   Add#(1, a__, vSz),
   Add#(1, b__, numTags),
   // NumAlias#(TExp#(TLog#(tagBufSz)), tagBufSz),
   Add#(e__, TLog#(tagBufSz), TLog#(TMul#(TExp#(TLog#(numTags)), tagBufSz))),

   NumAlias#(TExp#(TLog#(numTags)), numTags),
   Alias#(UInt#(TLog#(numTags)), tagT)
);
   module mkMergerSMTSched#(Bool ascending
      `ifdef DEBUG
      , Integer level
      `endif
      )(MergerSMTSched#(numTags, tagBufSz, vSz, iType));
      let merger <- mkMergerSMTSched_Impl(ascending
                                          `ifdef DEBUG
                                          , level
                                          `endif
                                          );
      return merger;
   endmodule
endinstance

// `include "SynthMerger_UInt_32_8.bsv"
`include "SynthMerger_UInt_32_16.bsv"
