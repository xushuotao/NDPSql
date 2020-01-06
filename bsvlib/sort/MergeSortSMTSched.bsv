// Copyright (C) 2019

// Shuotao Xu <shuotao@csail.mit.edu>

// Permission is hereby granted, free of charge, to any person obtaining a copy of this
// software and associated documentation files (the "Software"), to deal in the Software
// without restriction, including without limitation the rights to use, copy, modify,
// merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
// permit persons to whom the Software is furnished to do so, subject to the following
// conditions:

// The above copyright notice and this permission notice shall be included in all copies
// or substantial portions of the Software.  

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
// INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
// PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
// HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
// CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE
// OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import Pipe::*;
import FIFOF::*;
import SpecialFIFOs::*;
import GetPut::*;
import Vector::*;
import BuildVector::*;
import Connectable::*;
import FIFO::*;
import Bitonic::*;
import NToOneRouter::*;

import OneToNRouter::*;

import MergerSMTSched::*;
import MemoryIfc::*;
import BRAM::*;
import RWBramCore::*;
import SorterTypes::*;
import OneToNRouter::*;
import MergerSchedulerTypes::*;
import MergerScheduler::*;

import RWUramCore::*;

import BRAMFIFOFVector::*;
import DelayPipe::*;

import Cntrs::*;

// import DRAMControllerTypes::*;
// import ClientServerHelper::*;



import Assert::*;


`ifdef DEBUG
Bool debug = True;
`else
Bool debug = False;
`endif

interface MergeSortSMTSched#(type iType,
                             numeric type vSz,
                             numeric type totalSz);
   interface PipeIn#(Vector#(vSz, iType)) inPipe;
   interface PipeOut#(Vector#(vSz, iType)) outPipe;
endinterface


////////////////////////////////////////////////////////////////////////////////
/// module:      mkStreamingMergeSortSMT
/// Description: this module takes a in-stream of unsorted elements of totalSz,
///              which is streaming @ vSz elements per beat and sort them into a
///              sorted out-stream using merge-sort algorithm
////////////////////////////////////////////////////////////////////////////////
module mkStreamingMergeSortSMTSched#(Bool ascending)(MergeSortSMTSched#(iType, vSz, totalSz)) provisos(
   Div#(totalSz, vSz, n),
   MergerSMTSched::RecursiveMergerSMTSched#(iType, vSz, TDiv#(n,2)),
   Bitonic::RecursiveBitonic#(vSz, iType),
   Bits#(Vector::Vector#(vSz, iType), a__),
   Mul#(TDiv#(n,2), 2, n),
   Add#(TLog#(TDiv#(n, 2)), b__, TLog#(n)),
   Add#(1, c__, n),
   Add#(TLog#(TDiv#(n, 2)), g__, TLog#(TMul#(TDiv#(n, 2), 2))),
   Log#(TMul#(TDiv#(n, 2), 2), TLog#(n)),
//   Add#(1, b__, n),
//   Add#(1, c__, TMul#(TDiv#(n, 2), 2)),
//   Add#(n, d__, TMul#(TDiv#(n, 2), 2))
   // NumAlias#(TMul#(n,2), bufSz)
   // Add#(d__, 1, TLog#(TMul#(TExp#(TLog#(n)), 2))),
   Add#(f__, 2, TLog#(TMul#(TExp#(TLog#(n)), 4))),
   Add#(1, e__, vSz),
   Add#(1, d__, TDiv#(n, 2)),
   FShow#(iType)
   );

   function f_sort(d) = bitonic_sort(d, ascending);

   MergeNSMTSched#(iType, vSz, TDiv#(n,2)) merger <- mkMergeNSMTSched(ascending, 0);  
   
   StreamNode#(vSz, iType) sorter <- mkBitonicSort(ascending);
   Reg#(Bit#(TLog#(n))) fanInSel <- mkReg(0);
   
   FIFO#(UInt#(TLog#(n))) nextSpot <- mkSizedFIFO(valueOf(n)*4);
   
   Reg#(UInt#(TLog#(n))) spotCnt <- mkReg(0);
   Reg#(Bool) init <- mkReg(False);
   Reg#(Bit#(32)) iterCnt <- mkReg(0);
   rule doInit if( !init);

      nextSpot.enq(spotCnt);
      if ( spotCnt == fromInteger(valueOf(n)-1)) begin
         spotCnt <= 0;
         iterCnt <= iterCnt + 1;
         if ( iterCnt == 3) init <= True;
      end
      else begin
         spotCnt <= spotCnt + 1;
      end

   endrule
   
   // Vector#(bufSz, FIFOF#(void)) ready <- replicateM(mkFIFOF);
   
   // RWBramCore#(UInt#(TLog#(bufSz)), SortedPacket#(vSz, iType)) buffer <- mkRWBramCore;
   BRAMVector#(TLog#(n), 4, SortedPacket#(vSz, iType)) buffer <- mkUGBRAMVector;
   
   rule doEnqMerger if(init);
      let d = sorter.outPipe.first;
      sorter.outPipe.deq;
      let packet = SortedPacket{d:d, first:True, last:True};
      let slot = nextSpot.first;
      nextSpot.deq;
      // ready[slot].enq(?);
      merger.in.scheduleReq.enq(TaggedSchedReq{tag: slot, topItem:last(d), last: True});
      buffer.enq(packet, slot);
   endrule
   
   
   FIFO#(UInt#(TLog#(TDiv#(n,2)))) issuedTag <- mkFIFO;
   
   rule issueRd if (init&&merger.in.scheduleResp.notEmpty);
      let tag = merger.in.scheduleResp.first;
      merger.in.scheduleResp.deq;
      buffer.rdServer.request.put(tag);
      nextSpot.enq(tag);
      issuedTag.enq(unpack(truncateLSB(pack(tag))));
   endrule   
   
   rule doRdResp;
      let packet <- buffer.rdServer.response.get;
      let tag <- toGet(issuedTag).get;
      merger.in.dataChannel.enq(TaggedSortedPacket{tag:tag, packet:packet});
   endrule
   
   
   FIFOF#(Vector#(vSz, iType)) outQ <- mkFIFOF;
      
   DelayPipe#(1, void) delayReq <- mkDelayPipe;   
   rule doReceivScheReq;
      let d = merger.out.scheduleReq.first;
      merger.out.scheduleReq.deq;
      merger.out.server.request.put(?);
     // delayReq.enq(?);
   endrule
   
   // rule pullResult if ( delayReq.notEmpty);
   //    merger.out.server.request.put(?);
   // endrule
   Reg#(Bit#(TLog#(n))) outCnt <- mkReg(0);

   rule getResp;
      let packet <- merger.out.server.response.get;
      `ifdef DEBUG
      $display(fshow(packet));
      outCnt <= outCnt + 1;
      if (outCnt == 0) dynamicAssert(packet.packet.first, "first packet should be first");
      if (outCnt == maxBound) dynamicAssert(packet.packet.last, "last packet should be last");
      if (outCnt > 0 && outCnt < maxBound) dynamicAssert(!packet.packet.first && !packet.packet.last, "packet should be neither first or last");
      `endif
      outQ.enq(packet.packet.d);
   endrule
   
      
   interface PipeIn inPipe = sorter.inPipe;
   interface PipeOut outPipe = toPipeOut(outQ);
endmodule


interface StreamingMergerSMTSched#(type iType, numeric type vSz, numeric type sortedSz, numeric type fanIn);
   interface PipeIn#(Vector#(vSz, iType)) inPipe;
   interface PipeOut#(Vector#(vSz, iType)) outPipe;
endinterface

module mkStreamingMergeNSMTSched#(Bool ascending)(StreamingMergerSMTSched#(iType, vSz, sortedSz, n)) provisos (
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

   
   FShow#(iType)
   
   );
   
   FIFO#(Bit#(TLog#(n2))) freeBufIdQ <- mkSizedFIFO(valueOf(n2));
   
   Reg#(Bit#(TLog#(n2))) initCnt <- mkReg(0);
   Reg#(Bool) init <- mkReg(False);
   rule doInit if (!init);
      initCnt <= initCnt + 1;
      freeBufIdQ.enq(initCnt);
      if ( initCnt == fromInteger(valueOf(n2)-1) )
         init <= True;
   endrule

   // read latency = 5   
   RWUramCore#(Bit#(TLog#(bufferlines)), SortedPacket#(vSz, iType)) buffer <- mkRWUramCore(4);
   // RWBramCore#(Bit#(TLog#(bufferlines)), SortedPacket#(vSz, iType)) buffer <- mkRWBramCore;
   
   function Bit#(TLog#(bufferlines)) toAddr(blkIdT blkId, lineIdT lineId);
      return {blkId,lineId};
   endfunction
   

   MergeNSMTSched#(iType, vSz, TDiv#(n,2)) merger <- mkMergeNSMTSched(ascending, 0);  

   
   FIFOF#(Vector#(vSz, iType)) inQ <- mkFIFOF;
   FIFOF#(Vector#(vSz, iType)) outQ <- mkFIFOF;   
      
   Reg#(Bit#(TLog#(blockLines))) lineCnt_enq <- mkReg(0);
   
   Vector#(n, FIFOF#(blkIdT)) sortedBlks <- replicateM(mkUGSizedFIFOF(3));
   
   Reg#(Bit#(TLog#(n))) fanInSel <- mkReg(0);
   rule doEnqBuffer;
      let d <- toGet(inQ).get;
      let bufId = freeBufIdQ.first;
      if ( lineCnt_enq == maxBound ) begin
         freeBufIdQ.deq;
         fanInSel <= fanInSel + 1;
         sortedBlks[fanInSel].enq(bufId);
      end
      lineCnt_enq <= lineCnt_enq + 1;
      // $display("Enqeuing Buffer, bufId = %d, lineCnt_enq = %d, addr = %d, fanInSel = %d", bufId, lineCnt_enq, toAddr(bufId, lineCnt_enq), fanInSel);
      buffer.wrReq(toAddr(bufId, lineCnt_enq), SortedPacket{first:lineCnt_enq==0, last:lineCnt_enq==maxBound, d:d});
   endrule
   
   Integer bufSz = valueOf(BufSize#(vSz));
   
   Vector#(n, Count#(UInt#(TLog#(TAdd#(1,BufSize#(vSz)))))) creditV <- replicateM(mkCount(fromInteger(bufSz)));
   Vector#(n, Reg#(lineIdT)) lineCnt_deqV <- replicateM(mkReg(0));
   FIFO#(UInt#(TLog#(n))) dstFanQ <- mkSizedFIFO(8);
   
   // BRAMVector#(TLog#(n), BufSize#(vSz), SortedPacket#(vSz,iType)) dispatchBuff <- mkUGBRAMVector;//mkUGPipelinedBRAMVector;
   BRAMVector#(TLog#(n), BufSize#(vSz), SortedPacket#(vSz,iType)) dispatchBuff <- mkUGPipelinedBRAMVector;
   // FIFO#(Tuple2#(Bit#(TLog#(bufferlines)), UInt#(TLog#(n)))) readReqQ <- mkFIFO;
   Vector#(n, FIFOF#(Tuple3#(blkIdT, lineIdT, UInt#(TLog#(n))))) bufferRdReqQs <- replicateM(mkFIFOF);
   
   FunnelPipe#(1, n, Tuple3#(blkIdT, lineIdT, UInt#(TLog#(n))), 1) bufferRdReqFunnel <- mkFunnelPipesPipelined(map(toPipeOut, bufferRdReqQs));
   
   for (Integer idx = 0; idx < valueOf(n); idx = idx + 1 ) begin
      rule doPullData ( creditV[idx] > 0 && sortedBlks[idx].notEmpty);
         creditV[idx].decr(1);
         let bufId = sortedBlks[idx].first;
         if (lineCnt_deqV[idx] == maxBound) begin
            sortedBlks[idx].deq;
         end
         lineCnt_deqV[idx] <= lineCnt_deqV[idx] + 1;
         bufferRdReqQs[idx].enq(tuple3(bufId, lineCnt_deqV[idx], fromInteger(idx)));
      endrule
   end
   
   rule doIssueReq if (bufferRdReqFunnel[0].notEmpty);
      let {bufId, lineCnt, dst} = bufferRdReqFunnel[0].first;
      bufferRdReqFunnel[0].deq;
      if (lineCnt == maxBound)  freeBufIdQ.enq(bufId);
      buffer.rdReq(toAddr(bufId, lineCnt));
      dstFanQ.enq(dst);
   endrule

   rule issueSchedReq;
      let packet = buffer.rdResp;
      buffer.deqRdResp;
      let dst <- toGet(dstFanQ).get;
      dispatchBuff.enq(packet, dst);
      // $display("(%t) Enqueue Dispatch buf, tag = %d, packet = ", $time, dst, fshow(packet));
      merger.in.scheduleReq.enq(TaggedSchedReq{tag: dst, topItem:last(packet.d), last: packet.last});
   endrule
   
   FIFO#(UInt#(TLog#(TDiv#(n,2)))) issuedTag <- mkSizedFIFO(3);

   rule issueDataReq if (merger.in.scheduleResp.notEmpty);
      let tag = merger.in.scheduleResp.first;
      merger.in.scheduleResp.deq;
      creditV[tag].incr(1);
      dispatchBuff.rdServer.request.put(tag);
      // $display("Dispatch read Req, tag = %d", tag);
      issuedTag.enq(unpack(truncateLSB(pack(tag))));
   endrule   
   
   rule doDataResp;
      let packet <- dispatchBuff.rdServer.response.get;
      let tag <- toGet(issuedTag).get;
      merger.in.dataChannel.enq(TaggedSortedPacket{tag:tag, packet:packet});
   endrule

      
   DelayPipe#(1, void) delayReq <- mkDelayPipe;   
   rule doReceivScheReq;
      let d = merger.out.scheduleReq.first;
      merger.out.scheduleReq.deq;
      merger.out.server.request.put(?);
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
   interface outPipe = toPipeOut(outQ);
endmodule

// `include "DRAMMergerSMTSched.bsv"
