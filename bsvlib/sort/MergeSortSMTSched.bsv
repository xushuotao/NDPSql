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

import BRAMFIFOFVector::*;
import DelayPipe::*;

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

interface MultiMergeNFoldSMT#(numeric type way,
                              type iType,
                              numeric type vSz,
                              numeric type sortedSz,
                              numeric type n,
                              numeric type fanIn);
   interface PipeIn#(Vector#(vSz, iType)) inPipe;
   interface PipeOut#(Vector#(vSz, iType)) outPipe;
endinterface


interface MergeNFoldSMT#(type iType,
                      numeric type vSz,
                      numeric type sortedSz,
                      numeric type n,
                      numeric type fanIn);
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
   


   
      
   // rule issueRd if (init);
   //    function Bool fready(FIFOF#(t) x) = x.notEmpty;
   //    function Bool pready(PipeOut#(t) x) = x.notEmpty;
   //    function vpready(x) = map(pready, x);
      
   //    Vector#(n, Bool) senderReady = map(fready, ready);
   //    Vector#(n, Bool) receiverReady = concat(map(vpready, merger.in.ready));
      
   //    Vector#(n, Bool) allReady = zipWith(\&& , senderReady, receiverReady);
      
   //    Vector#(n, Tuple2#(Bool, Bit#(TLog#(n)))) indexArray = zipWith(tuple2, allReady, genWith(fromInteger));
      
   //    let port = fold(elemFind, indexArray);

      
   //    // let port = findElem(True, allReady);
      
   //    if ( port matches {True, .tag} ) begin
   //       buffer.rdReq(unpack(tag));
   //       ready[tag].deq;
   //       merger.in.ready[tag>>1][tag[0]].deq;
   //       nextSpot.enq(unpack(tag));
   //       issuedTag.enq(unpack(truncateLSB(tag)));
   //    end
   // endrule
   
   
   // rule doRdResp;
   //    let packet = buffer.rdResp;
   //    buffer.deqRdResp;
   //    let tag <- toGet(issuedTag).get;
   //    merger.in.inputResp(tag, packet);
   // endrule
   
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

/*
module mkMultiMergeNFoldBRAM#(Bool ascending)(MultiMergeNFoldSMT#(way, iType, vSz, sortedSz, n, fanIn)) provisos(
   Bits#(Vector::Vector#(vSz, iType), a__),
   Div#(sortedSz, vSz, blockLines),
   NumEq#(blockLines, TExp#(TLog#(blockLines))), // blockLines is power of two
   NumEq#(n, TExp#(TLog#(n))), // n is power of two
   Mul#(blockLines, n, totalLines),
   Log#(TMul#(2,totalLines), aw), // address matches twice total lines
   MergerSMT::RecursiveMergerSMT#(iType, vSz, fanIn),
   Add#(c__, TLog#(blockLines), aw),
   Add#(d__, TAdd#(TLog#(TDiv#(totalLines, blockLines)), 1), aw),
   Add#(e__, TLog#(TAdd#(TDiv#(totalLines, blockLines), 1)), 32),
   Add#(fanIn, b__, TMul#(TDiv#(fanIn, 2), 2)),
   Add#(1, f__, TMul#(TDiv#(fanIn, 2), 2)),
   Add#(1, g__, fanIn),
   Pipe::FunnelPipesPipelined#(1, fanIn, Bit#(TAdd#(TLog#(TDiv#(totalLines,blockLines)), 1)), 1),
   Pipe::FunnelPipesPipelined#(1, fanIn, Tuple4#(MemoryIfc::MemoryRequest#(Bit#(aw), Vector::Vector#(vSz, iType)),
                                                 Bool,Bool,Bit#(TLog#(fanIn))), 1)
   );
   
   function Vector#(2, Server#(BRAMRequest#(addrT, dataT), dataT)) toVec(BRAM2Port#(addrT, dataT) bram);
      return vec(bram.portA, bram.portB);
   endfunction
   
   BRAM_Configure cfg = defaultValue;
   Integer totalLns = valueOf(totalLines);
   cfg.memorySize = totalLns + totalLns/valueOf(fanIn);
   Vector#(way, BRAM2Port#(Bit#(aw), Vector#(vSz, iType))) bram <- replicateM(mkBRAM2Server(cfg));
   Vector#(way, Vector#(2, MemoryServer#(Bit#(aw), Vector#(vSz, iType)))) mems = ?;//<- mapM(mkMemServer, toVec(bram[i]));
   for (Integer i = 0; i < valueOf(way); i = i + 1) mems[i] <- mapM(mkMemServer, toVec(bram[i]));
   Vector#(way, MergeNFoldSMT#(iType, vSz, sortedSz, n, fanIn)) merger <- zipWithM(mkMergeNFoldSMT, replicate(ascending), mems);
   
   Reg#(Bit#(TLog#(TMul#(TDiv#(sortedSz,vSz), n)))) beatCnt_in <- mkReg(0);
   Reg#(Bit#(TLog#(way))) waySel_in <- mkReg(0);
   Reg#(Bit#(TLog#(TMul#(TDiv#(sortedSz,vSz), n)))) beatCnt_out <- mkReg(0);
   Reg#(Bit#(TLog#(way))) waySel_out <- mkReg(0);

   interface PipeIn inPipe;
      method Action enq(Vector#(vSz, iType) d);
         if ( beatCnt_in == fromInteger(valueOf(TMul#(TDiv#(sortedSz,vSz),n))-1) )begin
            beatCnt_in <= 0;
            if ( waySel_in == fromInteger(valueOf(way)-1)) begin
               waySel_in <= 0;
            end
            else begin
               waySel_in <= waySel_in + 1;
            end
         end
         else begin
            beatCnt_in <= beatCnt_in + 1;
         end
   
         merger[waySel_in].inPipe.enq(d);
      endmethod
      method Bool notFull = merger[waySel_in].inPipe.notFull;
   endinterface
   
   interface PipeOut outPipe;
      method Vector#(vSz, iType) first = merger[waySel_out].outPipe.first;
      method Action deq;
         merger[waySel_out].outPipe.deq;
         if ( beatCnt_out == fromInteger(valueOf(TMul#(TDiv#(sortedSz,vSz),n))-1) )begin
            beatCnt_out <= 0;
            if ( waySel_out == fromInteger(valueOf(way)-1)) begin
               waySel_out <= 0;
            end
            else begin
               waySel_out <= waySel_out + 1;
            end
         end
         else begin
            beatCnt_out <= beatCnt_out + 1;
         end
      endmethod
      method Bool notEmpty = merger[waySel_out].outPipe.notEmpty;
   endinterface
endmodule





module mkMergeNFoldBRAM#(Bool ascending)(MergeNFoldSMT#(iType, vSz, sortedSz, n, fanIn)) provisos(
   Bits#(Vector::Vector#(vSz, iType), a__),
   Div#(sortedSz, vSz, blockLines),
   NumEq#(blockLines, TExp#(TLog#(blockLines))), // blockLines is power of two
   NumEq#(n, TExp#(TLog#(n))), // n is power of two
   Mul#(blockLines, n, totalLines),
   Log#(TMul#(2,totalLines), aw), // address matches twice total lines
   MergerSMT::RecursiveMergerSMT#(iType, vSz, fanIn),
   Add#(c__, TLog#(blockLines), aw),
   Add#(d__, TAdd#(TLog#(TDiv#(totalLines, blockLines)), 1), aw),
   Add#(e__, TLog#(TAdd#(TDiv#(totalLines, blockLines), 1)), 32),
   Add#(fanIn, b__, TMul#(TDiv#(fanIn, 2), 2)),
   Add#(1, f__, TMul#(TDiv#(fanIn, 2), 2)),
   Add#(1, g__, fanIn),
   Pipe::FunnelPipesPipelined#(1, fanIn, Bit#(TAdd#(TLog#(TDiv#(totalLines,blockLines)), 1)), 1),
   Pipe::FunnelPipesPipelined#(1, fanIn, Tuple4#(MemoryIfc::MemoryRequest#(Bit#(aw), Vector::Vector#(vSz, iType)),
                                                 Bool,Bool,Bit#(TLog#(fanIn))), 1)
   );
   BRAM_Configure cfg = defaultValue;
   Integer totalLns = valueOf(totalLines);
   cfg.memorySize = totalLns + totalLns/valueOf(fanIn);
   // cfg.latency = 2;
   // cfg.outFIFODepth = 4;
   BRAM2Port#(Bit#(aw), Vector#(vSz, iType)) bram <- mkBRAM2Server(cfg);
   Vector#(2, MemoryServer#(Bit#(aw), Vector#(vSz, iType))) mems <- mapM(mkMemServer, vec(bram.portA, bram.portB));
   let merger <- mkMergeNFoldSMT(ascending, mems);
   return merger;
endmodule


module mkMergeNFoldSMT#(Bool ascending, Vector#(2, MemoryServer#(Bit#(aw), Vector#(vSz, iType))) mems) (MergeNFoldSMT#(iType, vSz, sortedSz, n, fanIn)) provisos(
   Bits#(Vector::Vector#(vSz, iType), a__),
   Div#(sortedSz, vSz, blockLines),
   NumEq#(blockLines, TExp#(TLog#(blockLines))), // blockLines is power of two
   NumEq#(n, TExp#(TLog#(n))), // n is power of two
   Mul#(blockLines, n, totalLines),
   NumEq#(TExp#(aw), TMul#(2,totalLines)), // address matches twice total lines
   Div#(totalLines, blockLines, totalBlocks),
   Alias#(Bit#(TAdd#(TLog#(totalBlocks),1)), blkIdT),
   Alias#(Bit#(TLog#(TAdd#(totalBlocks,1))), blkBurstT),
   Alias#(Bit#(TLog#(blockLines)), blkLineT), 
   Add#(c__, TAdd#(TLog#(totalBlocks), 1), aw),
   Add#(d__, TLog#(blockLines), aw),
   MergerSMT::RecursiveMergerSMT#(iType, vSz, fanIn),
   Add#(g__, TLog#(TAdd#(totalBlocks, 1)), 32),
   Add#(fanIn, b__, TMul#(TDiv#(fanIn, 2), 2)),
   Add#(1, e__, TMul#(TDiv#(fanIn, 2), 2)),
   Add#(1, f__, fanIn),
   Pipe::FunnelPipesPipelined#(1, fanIn, Bit#(TAdd#(TLog#(totalBlocks), 1)),1),
   Pipe::FunnelPipesPipelined#(1, fanIn, Tuple4#(MemoryIfc::MemoryRequest#(Bit#(aw), Vector::Vector#(vSz, iType)),
                                                 Bool,Bool,Bit#(TLog#(fanIn))), 1)
   );
   
   Integer folds = valueOf(TDiv#(TLog#(n),TLog#(fanIn))) - 1;
   
   Reg#(blkIdT) blkId_init <- mkReg(0);
   FIFOF#(blkIdT) freeBlockQ <- mkSizedFIFOF(valueOf(totalBlocks)*2);//mkSizedBRAMFIFOF(valueOf(totalBlocks)+valueOf(totalBlocks)/valueOf(fanIn));
   Reg#(Bool) init <- mkReg(False);
   rule doInit if ( !init);
      blkId_init <= blkId_init + 1;
      if (debug) $display("blkId_init, blkId = %d", blkId_init);
      freeBlockQ.enq(blkId_init);
      if ( blkId_init == fromInteger(valueOf(totalBlocks)+valueOf(totalBlocks)/valueOf(fanIn) - 1) ) 
         init <= True;
   endrule
   
   
   Vector#(fanIn, FIFO#(Tuple3#(blkIdT, Bool, Bool))) sortedBlockQs <- replicateM(mkSizedFIFO(valueOf(totalBlocks)));
   
   MergeNSMT#(iType, vSz, fanIn) merger <- mkMergeNSMT(ascending, 0);         
   
   
   FIFOF#(Vector#(vSz, iType)) inQ <- mkFIFOF;
   FIFOF#(Vector#(vSz, iType)) outQ <- mkFIFOF;
   

   Integer blkLines = valueOf(blockLines);
   Integer lgBlkLines = valueOf(TLog#(blockLines));
   Integer totalBlks = valueOf(totalBlocks);
   
   
   function Bit#(aw) toAddr(blkIdT blkId, blkLineT lineId);
      return (zeroExtend(blkId)<<fromInteger(lgBlkLines)) + zeroExtend(lineId);
   endfunction
   
   Vector#(fanIn, Reg#(blkLineT)) vLineCntRd <- replicateM(mkReg(0));
   FIFO#(Tuple3#(Bool, Bool, Bit#(TLog#(fanIn)))) destFanQ <- mkSizedFIFO(3);
   Integer bufSz = 3+valueOf(TLog#(vSz));
   Vector#(fanIn, FIFOF#(SortedPacket#(vSz, iType))) dataInBufs <- replicateM(mkSizedFIFOF(bufSz+1));
   // OneToNRouter#(fanIn,SortedPacket#(vSz, iType)) dataInRouter <- mkOneToNRouterBRAM;
   OneToNRouter#(fanIn,SortedPacket#(vSz, iType)) dataInRouter <- mkOneToNRouterPipelined;
   zipWithM_(mkConnection, takeOutPorts(dataInRouter), map(toPipeIn, dataInBufs));
   Vector#(fanIn, Array#(Reg#(Bit#(8)))) elemCnts <- replicateM(mkCReg(2, 0));
   
   Vector#(fanIn, FIFOF#(blkIdT)) blockReturnQs <- replicateM(mkFIFOF);
   FunnelPipe#(1, fanIn, blkIdT, 1) blockReturnFunnel <- mkFunnelPipesPipelined(map(toPipeOut, blockReturnQs));
   mkConnection(blockReturnFunnel[0], toPipeIn(freeBlockQ));
   
   //FIFO#(MemoryRequest#(Bit#(aw), Vector#(vSz, iType))) memRdReqQ <- mkFIFO;

   Vector#(fanIn, FIFOF#(Tuple4#(MemoryRequest#(Bit#(aw), Vector#(vSz, iType)),Bool, Bool, Bit#(TLog#(fanIn))))) memRdReqQs <- replicateM(mkFIFOF);
   FunnelPipe#(1,fanIn,Tuple4#(MemoryRequest#(Bit#(aw),Vector#(vSz, iType)),Bool, Bool, Bit#(TLog#(fanIn))),1) memRdReqFunnel <- mkFunnelPipesPipelined(map(toPipeOut, memRdReqQs));
   
   for (Integer fanSelRd = 0; fanSelRd < valueOf(fanIn); fanSelRd = fanSelRd + 1) begin
      rule doMemReq if ( elemCnts[fanSelRd][1] < fromInteger(bufSz) );
         let {blkId, first, last} = sortedBlockQs[fanSelRd].first;
         elemCnts[fanSelRd][1] <= elemCnts[fanSelRd][1] + 1;
         let firstBeat = (vLineCntRd[fanSelRd] == 0 && first);
         let lastBeat = (vLineCntRd[fanSelRd] == maxBound && last);
         
         memRdReqQs[fanSelRd].enq(tuple4(MemoryRequest{addr: toAddr(blkId,vLineCntRd[fanSelRd]), datain: ?, write: False},
                                         firstBeat,
                                         lastBeat,
                                         fromInteger(fanSelRd)));
         vLineCntRd[fanSelRd] <= vLineCntRd[fanSelRd] + 1;
         if ( vLineCntRd[fanSelRd] == 0 ) begin
            if (first)
               if (debug) $display("doMemReq, vLineCnt[%d] = %d, blkId = %d, first = %d, last = %d", fanSelRd, vLineCntRd[fanSelRd], blkId, first, last);
            //if (debug) $display("doMemReq, vLineCnt[%d] = %d, blkId = %d, first = %d, last = %d", fanSelRd, vLineCntRd[fanSelRd], blkId, first, last);
         end
         if ( vLineCntRd[fanSelRd] == maxBound ) begin
            sortedBlockQs[fanSelRd].deq;
            blockReturnQs[fanSelRd].enq(blkId);
         end
      endrule
      
      
      rule doMergeInStream;//if ( elemCnts[fanSelRd][0] > 0 );
         let packet <- toGet(dataInBufs[fanSelRd]).get();
         elemCnts[fanSelRd][0] <= elemCnts[fanSelRd][0] - 1;         
         merger.inPipes[fanSelRd].enq(packet);
      endrule
   end
      
   rule memRdIssue;
      let {req, first, last, fanSel} = memRdReqFunnel[0].first;
      memRdReqFunnel[0].deq;
      mems[1].request.put(req);
      destFanQ.enq(tuple3(first, last, fanSel));
   endrule


   
   rule doMemResp;
      let {first, last, destFan} <- toGet(destFanQ).get;
      let d <- mems[1].response.get();
      dataInRouter.inPort.enq(tuple2(destFan,SortedPacket{d:d, first:first, last:last}));
   endrule

   Array#(Reg#(Bool)) burstLock <- mkCReg(2, False);   
   Array#(Reg#(blkBurstT)) inflightblks <- mkCReg(2, 0);
   
   Reg#(blkLineT) lineCnt_mergeResp <- mkReg(0); 

   Reg#(blkLineT) lineCnt <- mkReg(0);
   Reg#(Bit#(TLog#(fanIn))) fanSel <- mkReg(0);
   
      
   rule doDeqInPipe if (init && inflightblks[1] < fromInteger(valueOf(n)));
      let d <- toGet(inQ).get;
      let blkId = freeBlockQ.first;
      
      if (debug) $display("doDeqInPipe, lineCnt = %d, blkId = %d", lineCnt, blkId);
      if ( lineCnt == maxBound ) begin
         freeBlockQ.deq;
         sortedBlockQs[fanSel].enq(tuple3(blkId,True,True));
         fanSel <= fanSel + 1;
         inflightblks[1] <= inflightblks[1] + 1;
      end
      
      lineCnt <= lineCnt + 1;
      mems[0].request.put(MemoryRequest{addr: toAddr(blkId, lineCnt), datain: d, write: True});
   endrule

   Reg#(Bit#(TAdd#(TDiv#(TLog#(n),TLog#(fanIn)),1))) iterCnt <- mkReg(0);
   Reg#(Bit#(TLog#(totalBlocks))) blkCnt_feedback <- mkReg(0);
   rule doMergeRespData_feedback ( iterCnt < fromInteger(folds) &&  inflightblks[1] == fromInteger(valueOf(n)) );//(isValid(tpl_1(reservedBlkQ.first)) && inflightblks[1] == fromInteger(valueOf(n)));
      // $display("inflightblks[1] = %d", inflightblks[1]);
      dynamicAssert(inflightblks[1]==fromInteger(valueOf(n)), "feedback is only allowed when all blocks are accumulated");
      let blkId = freeBlockQ.first;
      
      let packet = merger.outPipe.first;
      merger.outPipe.deq;
      
      let firstBeat = lineCnt_mergeResp == 0 && packet.first;
      let lastBeat = lineCnt_mergeResp == maxBound && packet.last;
      
      if ( packet.last ) dynamicAssert(lineCnt_mergeResp == maxBound, "last packet should always be at the last beat of block");
      
      if (lineCnt_mergeResp == 0) begin
         // if (debug) $display("doMergeRespData, lineCnt_mergeResp = %d, fanSel_mergeResp = %d, blkBurst = %d, first = %d, last = %d, currBlkId = ", lineCnt_mergeResp, fanSel_mergeResp, blkBurst, first, last, fshow(currBlkId));
         // if (first) burstLock[0] <= True;
      end
      if ( lineCnt_mergeResp == maxBound ) begin
         blkCnt_feedback <= blkCnt_feedback + 1;
         if ( blkCnt_feedback == maxBound ) iterCnt <= iterCnt + 1;
         freeBlockQ.deq;
         sortedBlockQs[fanSel].enq(tuple3(blkId, packet.first, packet.last));
         if ( packet.last ) begin 
            fanSel <= fanSel + 1;
         end
      end
      lineCnt_mergeResp <= lineCnt_mergeResp + 1;

      mems[0].request.put(MemoryRequest{addr: toAddr(blkId, lineCnt_mergeResp), datain: packet.d, write: True});
   endrule
   
   Reg#(Bit#(TLog#(totalBlocks))) blkCnt_output <- mkReg(0);   
   rule doMergeRespData_output (iterCnt == fromInteger(folds));
      // let {currBlkId,blkBurst,first,last} = reservedBlkQ.first;
      lineCnt_mergeResp <= lineCnt_mergeResp + 1;
      let packet = merger.outPipe.first;
      merger.outPipe.deq;
      
      if ( packet.first ) dynamicAssert(blkCnt_output == 0 && lineCnt_mergeResp == 0, "checking first aligns");
      if ( packet.last )  dynamicAssert(blkCnt_output == maxBound && lineCnt_mergeResp == maxBound, "checking last aligns");
      
      if ( lineCnt_mergeResp == maxBound ) begin
         blkCnt_output <= blkCnt_output + 1;
         if ( blkCnt_output == maxBound) iterCnt <= 0;
         inflightblks[0] <= inflightblks[0] - 1;
      end
      dynamicAssert(inflightblks[0]>0, "inflightblks should not go below 0");
      outQ.enq(packet.d);
   endrule

   

   interface inPipe = toPipeIn(inQ);
   interface outPipe = toPipeOut(outQ);
endmodule
*/
