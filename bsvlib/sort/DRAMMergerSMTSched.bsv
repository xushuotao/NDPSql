import SorterTypes::*;
import MergerSchedulerTypes::*;
import MergerSMTSched::*;

import Pipe::*;
import Vector::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;

import DRAMControllerTypes::*;
import ClientServer::*;
import ClientServerHelper::*;
import Assert::*;

import DRAMMux::*;
import Prefetcher::*;
import Cntrs::*;
import Counter::*;

import DelayPipe::*;
import BRAMFIFOFVector::*;

import Connectable::*;
import GetPut::*;

interface DRAMPrefDebugIfc;
   method Vector#(2, Tuple3#(Bit#(64), Bit#(64), Bit#(64))) dumpStatus;
endinterface


interface DRAMStreamingMergerSMTSched#(type iType, numeric type vSz, numeric type sortedSz, numeric type fanIn, numeric type fDepth);
   interface PipeIn#(Vector#(vSz, iType)) inPipe;
   interface PipeOut#(Vector#(vSz, iType)) outPipe;
   // interface Vector#(2, DDR4Client) dramClients;
   interface Vector#(2, Client#(Tuple2#(Bit#(1), DDRRequest), DDRResponse)) dramMuxClients;
   `ifdef Debug
   interface DRAMPrefDebugIfc debug;
   `endif
endinterface

// typedef TMul#(1024,8) PrefSz;

module mkDRAMStreamingMergeNSMTSched#(Bool ascending)(DRAMStreamingMergerSMTSched#(iType, vSz, sortedSz, n, fDepth)) provisos (
   Bits#(iType, typeSz),
   Add#(1, d__, n),
   Log#(TMul#(TDiv#(n, 2), 2), TLog#(n)),
   Add#(TLog#(TDiv#(n, 2)), a__, TLog#(TMul#(TDiv#(n, 2), 2))),
   Add#(1, b__, vSz),
   MergerSMTSched::RecursiveMergerSMTSched#(iType, vSz, TDiv#(n,2)),
   
   // Add#(c__, 4, TLog#(TMul#(TExp#(TLog#(n)), 16))),
   // Add#(c__, 5, TLog#(TMul#(TExp#(TLog#(n)), 32))),
   Add#(c__, TLog#(BufSize#(vSz)),   TLog#(TMul#(TExp#(TLog#(n)), BufSize#(vSz)))),

   Div#(sortedSz, vSz, blockLines),
   NumAlias#(blockLines, TExp#(TLog#(blockLines))), //blockLines is power of 2
   Mul#(blockLines, n, totalLines),
   Mul#(n, 2, n2),
   Mul#(blockLines, n2, bufferlines),
   Alias#(Bit#(TLog#(n2)), blkIdT),
   Alias#(Bit#(TLog#(blockLines)), lineIdT),
   
   Add#(TLog#(n2), TLog#(blockLines), TLog#(bufferlines)),
   Pipe::FunnelPipesPipelined#(1, n, Tuple3#(blkIdT,  lineIdT, UInt#(TLog#(n))), 1),
   
   Add#(e__, TAdd#(TLog#(n), TAdd#(TLog#(blockLines), 3)), 64),
   Add#(f__, TAdd#(TMul#(vSz, typeSz), 2), 640),
   // Pipe::FunnelPipesPipelined#(1, n, Tuple3#(Bit#(1), Bit#(32), Bit#(TLog#(n))), 1),
   
   // Prefetcher::PrefetcherInstance#(fDepth_beats,SorterTypes::SortedPacket#(vSz, iType), Bit#(1)),
   // Pipe::FunnelPipesPipelined#(1, n, Tuple2#(SorterTypes::SortedPacket#(vSz, iType), UInt#(TLog#(n))), 1),
   
   Div#(fDepth,vSz, fDepth_beats),
   // Add#(g__, TLog#(TMul#(fDepth_beats, 2)), TLog#(TMul#(fDepth_beats, 4))),
   Add#(h__, TLog#(TMul#(fDepth_beats, 2)), TLog#(TMul#(TExp#(TLog#(n)), TMul#(fDepth_beats, 2)))),
   Add#(g__, TLog#(TDiv#(blockLines, fDepth_beats)), 32),
   Add#(i__, TLog#(n), 32),
   Prefetcher::VectorPrefetcherInstance#(n, fDepth_beats, TDiv#(blockLines,fDepth_beats), SorterTypes::SortedPacket#(vSz, iType), Bit#(1)),
   
   FShow#(iType)
   
   );
   
   

   
   // FIFO#(Bit#(TLog#(n2))) freeBufIdQ <- mkSizedFIFO(valueOf(n2));
   
   // Reg#(Bit#(TLog#(n2))) initCnt <- mkReg(0);
   // Reg#(Bool) init <- mkReg(False);
   // rule doInit if (!init);
   //    initCnt <= initCnt + 1;
   //    freeBufIdQ.enq(initCnt);
   //    if ( initCnt == fromInteger(valueOf(n2)-1) )
   //       init <= True;
   // endrule

   // read latency = 5   

   // RWBramCore#(Bit#(TLog#(bufferlines)), SortedPacket#(vSz, iType)) buffer <- mkRWBramCore;
   
   function Bit#(TLog#(bufferlines)) toAddr(blkIdT blkId, lineIdT lineId);
      return {blkId,lineId};
   endfunction
   

   MergeNSMTSched#(iType, vSz, TDiv#(n,2)) merger <- mkMergeNSMTSched(ascending, 0);  

   
   FIFOF#(Vector#(vSz, iType)) inQ <- mkFIFOF;
   FIFOF#(Vector#(vSz, iType)) outQ <- mkSizedFIFOF(4);   
      
   Reg#(Bit#(TLog#(blockLines))) lineCnt_enq <- mkReg(0);
    
   // Vector#(n, FIFOF#(blkIdT)) sortedBlks <- replicateM(mkUGSizedFIFOF(3));
   
   Reg#(Bit#(TLog#(n))) fanInSel <- mkReg(0);
   
////////////////////////////////////////////////////////////////////////////////
/// DRAM Related Connection
/// Components: DRAMController 0 <->|               |<- DataPreloading
///                                 |<=> DRAMMux <=>|
///             DRAMController 1 <->|               |<-> Prefetchers
/// Note:: Assumes Two DRAM Controllers
////////////////////////////////////////////////////////////////////////////////
   Vector#(2, FIFOF#(Tuple2#(Bit#(1), DDRRequest))) dramReqQ <- replicateM(mkFIFOF); 
   Vector#(2, FIFOF#(DDRResponse)) dramRespQ <- replicateM(mkFIFOF); 

   // DRAMMux#(2, 2) dramMux <- mkDRAMMux;
   // DRAMMux#(2, 2) dramMux <- mkRwDualDRAMMux;

   // Vector#(2, Client#(Tuple2#(Bit#(1), DDRRequest), DDRResponse)) dramClis = zipWith(toClient, dramReqQ, dramRespQ);
   // zipWithM_(mkConnection, dramClis, dramMux.dramServers);
   
////////////////////////////////////////////////////////////////////////////////
/// DRAM writes: 
/// dataPreloading
////////////////////////////////////////////////////////////////////////////////
   FIFO#(Bit#(1)) freeDRAM <- mkFIFO;
   FIFO#(Bit#(1)) dramReadyQ <- mkFIFO;
   Reg#(Bit#(TLog#(n))) segCnt_load <- mkReg(0);
   Reg#(lineIdT) segLineCnt_load <- mkReg(0);
   
   Reg#(Bit#(2)) initCnt <- mkReg(0);
   
   `ifdef Debug
   Vector#(2, Reg#(Bit#(64))) totalDRAMReadReq  <- replicateM(mkReg(0));
   Vector#(2, Reg#(Bit#(64))) totalDRAMReadResp <- replicateM(mkReg(0));
   Vector#(2, Reg#(Bit#(64))) totalDRAMWrite    <- replicateM(mkReg(0));
   `endif
   (* fire_when_enabled *)
   rule doInit if ( initCnt < 2);
      freeDRAM.enq(truncate(initCnt));
      initCnt <= initCnt + 1;
   endrule
   rule dataPreloading;
      let dramId = freeDRAM.first;

      if ( segLineCnt_load == maxBound ) begin
         $display("DataPreloading: seg finished segid = %d", segCnt_load);

         if ( segCnt_load == fromInteger(valueOf(n)-1) ) begin
            freeDRAM.deq;
            dramReadyQ.enq(dramId);
            segCnt_load <= 0;
         end
         else begin
            segCnt_load <= segCnt_load + 1;
         end
         segLineCnt_load <= 0;
      end
      else begin
         segLineCnt_load <= segLineCnt_load + 1;
      end
      
      let d <- toGet(inQ).get;
      
      let sortedPacket = SortedPacket{d: d, first: segLineCnt_load == 0, last: segLineCnt_load == maxBound};
      
      // $display("DataPreloading: segCnt_load = %d, segLineCnt_load = %d ", segCnt_load, segLineCnt_load, fshow(sortedPacket));
      
      dramReqQ[0].enq(tuple2(dramId, DDRRequest{address: extend({segCnt_load,segLineCnt_load, 3'b0}), 
                                                writeen: -1, 
                                                datain:extend(pack(sortedPacket))}));
      `ifdef Debug
      totalDRAMWrite[dramId] <= totalDRAMWrite[dramId] + 1;
      `endif
   endrule
   
////////////////////////////////////////////////////////////////////////////////
/// DRAM Reads: 
/// Prefetchers
////////////////////////////////////////////////////////////////////////////////
   VectorPrefetcher#(n, fDepth_beats, TDiv#(blockLines, fDepth_beats), SortedPacket#(vSz, iType), Bit#(1)) prefetchVec <- mkVectorPrefetcher;
   rule startPrefetch;
      let dramId = dramReadyQ.first;
      dramReadyQ.deq;
      prefetchVec.start(dramId);
   endrule

   
   Reg#(Bit#(32)) fetchCnt <- mkReg(0);
   FIFOF#(Tuple2#(Bit#(1), Bit#(TLog#(n)))) outstandingBurst <- mkSizedFIFOF(64);
   // issue bursts of DRAM requests
   rule issueDramBurst;
      let {segId, dramId, baseCnt} = prefetchVec.fetchReq.first;

      if ( fetchCnt == fromInteger(valueOf(fDepth_beats)-1) ) begin
         fetchCnt <= 0;
         prefetchVec.fetchReq.deq;
      end
      else begin
         fetchCnt <= fetchCnt + 1;
      end

      if ( fetchCnt == 0) begin
         outstandingBurst.enq(tuple2(dramId, segId));
      end
      
      Bit#(32) base = (zeroExtend(segId) << fromInteger(valueOf(TLog#(blockLines)))) + 
      (zeroExtend(baseCnt) << fromInteger(valueOf(TLog#(fDepth_beats))));
      // $display("bursting dram id = %d, segId = %0d,  fetchCnt = %0d, baseCnt = %0d, base = %0d", dramId, segId, fetchCnt, baseCnt, base);
      dramReqQ[1].enq(tuple2(dramId, DDRRequest{address: extend({base+fetchCnt,3'b0}), writeen: 0, datain:?}));
      `ifdef Debug
      totalDRAMReadReq[dramId] <= totalDRAMReadReq[dramId] + 1;
      `endif
   endrule

   Reg#(Bit#(32)) fetchCnt_resp <- mkReg(0);
   Vector#(2, Reg#(Bit#(32))) totalLineCnt <- replicateM(mkReg(0));
   // handle DRAM responses
   rule doDramResp;
      let v = dramRespQ[1].first;
      dramRespQ[1].deq;

      let {dramId, segId} = outstandingBurst.first;
      
      `ifdef Debug
      totalDRAMReadResp[dramId] <= totalDRAMReadResp[dramId] + 1;
      `endif

      
      // $display("bursting response dram id = %d, segId = %0d,  fetchCnt = %0d", dramId, segId, fetchCnt_resp);
      
      if ( fetchCnt_resp == fromInteger(valueOf(fDepth_beats)-1)) begin
         fetchCnt_resp <= 0;
         outstandingBurst.deq;
      end
      else begin
         fetchCnt_resp <= fetchCnt_resp + 1;
      end
      
      if ( totalLineCnt[dramId] == fromInteger(valueOf(totalLines)-1)) begin
         totalLineCnt[dramId] <= 0;
         freeDRAM.enq(dramId);
      end
      else begin
         totalLineCnt[dramId] <= totalLineCnt[dramId] + 1;
      end
      prefetchVec.fetchResp.enq(tuple2(segId, unpack(truncate(v))));
   endrule
       
   Integer bufSz = valueOf(BufSize#(vSz));
   
   Vector#(n, Count#(UInt#(TLog#(TAdd#(1,BufSize#(vSz)))))) creditV <- replicateM(mkCount(fromInteger(bufSz)));
   // BRAMVector#(TLog#(n), BufSize#(vSz), SortedPacket#(vSz,iType)) dispatchBuff <- mkUGBRAMVector;//mkUGPipelinedBRAMVector;
   BRAMVector#(TLog#(n), BufSize#(vSz), SortedPacket#(vSz,iType)) dispatchBuff <- mkUGPipelinedBRAMVector;
   
   FIFOF#(UInt#(TLog#(n))) dstQ <- mkSizedFIFOF(8);
   
   Vector#(n, FIFOF#(void)) rdReqQs <- replicateM(mkFIFOF);
   
   for (Integer i = 0; i < valueOf(n); i = i + 1 ) begin
      rule doPullData if ( creditV[i] > 0 && prefetchVec.dataReady[i].notEmpty);
         prefetchVec.dataReady[i].deq;
         creditV[i].decr(1);
         rdReqQs[i].enq(?);
         // let idx = tpl_2(port);
         // prefetchVec.rdServer.request.put(unpack(idx));
         // creditV[idx].decr(1);
         // dstQ.enq(unpack(idx));
      endrule
   end
   
   function Bool canGoFunc(Integer i);
      return rdReqQs[i].notEmpty;
   endfunction
      
   Vector#(n, Bool) canGo = genWith(canGoFunc);
   Vector#(n, Tuple2#(Bool, UInt#(TLog#(n)))) indexArray = zipWith(tuple2, canGo, genWith(fromInteger));
   let port = fold(elemFind, indexArray);
   
   rule issueRdReq if (pack(canGo) != 0);
      let idx= tpl_2(port);
      rdReqQs[idx].deq;
      prefetchVec.rdServer.request.put(idx);
      dstQ.enq(idx);
   endrule
   
      
   rule doPushData;
      let dst <- toGet(dstQ).get;
      let packet <- prefetchVec.rdServer.response.get;
      dispatchBuff.enq(packet, dst);
      merger.in.scheduleReq.enq(TaggedSchedReq{tag: dst, topItem:last(packet.d), last: packet.last});
   endrule
   
   FIFO#(UInt#(TLog#(TDiv#(n,2)))) issuedTag <- mkSizedFIFO(4);

   rule issueDataReq if (merger.in.scheduleResp.notEmpty);
      let tag = merger.in.scheduleResp.first;
      merger.in.scheduleResp.deq;
      creditV[tag].incr(1);
      dispatchBuff.rdServer.request.put(tag);
      // $display("Dispatch read Req, tag = %d", tag);
      issuedTag.enq(unpack(truncateLSB(pack(tag))));
   endrule   
   
   
   FIFO#(SortedPacket#(vSz,iType)) dispatchDelayQ <- mkDelayPipeG(2);
   
   rule doDataResp;
      let packet <- dispatchBuff.rdServer.response.get;
      dispatchDelayQ.enq(packet);
   endrule
   
   rule doConn;
      let packet <- toGet(dispatchDelayQ).get;
      let tag <- toGet(issuedTag).get;
      merger.in.dataChannel.enq(TaggedSortedPacket{tag:tag, packet:packet});
   endrule

      
   // DelayPipe#(1, void) delayReq <- mkDelayPipe;
   
   Counter#(TLog#(TAdd#(1, 4))) outPending  <- mkCounter(0);

   rule doReceivScheReq if ( outPending.value < 4);
      let d = merger.out.scheduleReq.first;
      merger.out.scheduleReq.deq;
      merger.out.server.request.put(?);
      outPending.up;
   endrule
   
   Reg#(Bit#(TLog#(TMul#(blockLines, n)))) outCnt <- mkReg(0);

   rule getResp;
      let packet <- merger.out.server.response.get;
      // `ifdef DEBUG
      // $display(fshow(packet));
      outCnt <= outCnt + 1;
      if (outCnt == 0) dynamicAssert(packet.packet.first, "first packet should be first");
      if (outCnt == maxBound) dynamicAssert(packet.packet.last, "last packet should be last");
      if (outCnt > 0 && outCnt < maxBound) dynamicAssert(!packet.packet.first && !packet.packet.last, "packet should be neither first or last");
      // `endif
      outQ.enq(packet.packet.d);
   endrule
   
   interface inPipe = toPipeIn(inQ);
   interface PipeOut outPipe;// = toPipeOut(outQ);
      method Vector#(vSz, iType) first = outQ.first;
      method Action deq;
         outQ.deq;
         outPending.down;
      endmethod
      method Bool notEmpty = outQ.notEmpty;
   endinterface
   // interface dramClients = dramMux.dramControllers;
   interface dramMuxClients = zipWith(toClient, dramReqQ, dramRespQ);
   
   `ifdef Debug
   interface DRAMPrefDebugIfc debug;
      method Vector#(2, Tuple3#(Bit#(64), Bit#(64), Bit#(64))) dumpStatus;
         return zipWith3(tuple3, 
                         readVReg(totalDRAMWrite),
                         readVReg(totalDRAMReadReq),
                         readVReg(totalDRAMReadResp)
                         );
      endmethod
   endinterface
   `endif

endmodule

