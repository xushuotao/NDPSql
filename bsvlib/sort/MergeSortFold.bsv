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
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import BRAMFIFO::*;
import GetPut::*;
import Vector::*;
import BuildVector::*;
import Connectable::*;

import MergeSortVar::*;
import MemoryIfc::*;
import OneToNRouter::*;

import BRAM::*;

import Assert::*;

Bool debug = False;


interface MergeNFold#(type iType,
                      numeric type vSz,
                      numeric type sortedSz,
                      numeric type n,
                      numeric type fanIn);
   interface PipeIn#(Vector#(vSz, iType)) inPipe;
   interface PipeOut#(Vector#(vSz, iType)) outPipe;
endinterface

interface MultiMergeNFold#(numeric type way,
                           type iType,
                           numeric type vSz,
                           numeric type sortedSz,
                           numeric type n,
                           numeric type fanIn);
   interface PipeIn#(Vector#(vSz, iType)) inPipe;
   interface PipeOut#(Vector#(vSz, iType)) outPipe;
endinterface


module mkMergeNFoldBRAM#(Bool ascending)(MergeNFold#(iType, vSz, sortedSz, n, fanIn)) provisos(
   Bits#(Vector::Vector#(vSz, iType), a__),
   Div#(sortedSz, vSz, blockLines),
   NumEq#(blockLines, TExp#(TLog#(blockLines))), // blockLines is power of two
   NumEq#(n, TExp#(TLog#(n))), // n is power of two
   Mul#(blockLines, n, totalLines),
   Log#(TMul#(2,totalLines), aw), // address matches twice total lines
   MergeSortVar::RecursiveMergerVar#(iType, vSz, fanIn),
   Add#(c__, TLog#(blockLines), aw),
   Add#(d__, TAdd#(TLog#(TDiv#(totalLines, blockLines)), 1), aw),
   Add#(e__, TLog#(TAdd#(TDiv#(totalLines, blockLines), 1)), 32),
   Add#(fanIn, b__, TMul#(TDiv#(fanIn, 2), 2)),
   Add#(1, f__, TMul#(TDiv#(fanIn, 2), 2)),
   Add#(1, g__, fanIn),
   Pipe::FunnelPipesPipelined#(1, fanIn, Bit#(TAdd#(TLog#(TDiv#(totalLines,blockLines)), 1)), 1),
   Pipe::FunnelPipesPipelined#(1, fanIn, Tuple2#(MemoryIfc::MemoryRequest#(Bit#(aw), Vector::Vector#(vSz, iType)), 
                                                 Bit#(TLog#(fanIn))), 1)
   );
   BRAM_Configure cfg = defaultValue;
   Integer totalLns = valueOf(totalLines);
   cfg.memorySize = totalLns + totalLns/valueOf(fanIn);
   // cfg.latency = 2;
   // cfg.outFIFODepth = 4;
   BRAM2Port#(Bit#(aw), Vector#(vSz, iType)) bram <- mkBRAM2Server(cfg);
   Vector#(2, MemoryServer#(Bit#(aw), Vector#(vSz, iType))) mems <- mapM(mkMemServer, vec(bram.portA, bram.portB));
   let merger <- mkMergeNFold(ascending, mems);
   return merger;
endmodule

module mkMultiMergeNFoldBRAM#(Bool ascending)(MultiMergeNFold#(way, iType, vSz, sortedSz, n, fanIn)) provisos(
   Bits#(Vector::Vector#(vSz, iType), a__),
   Div#(sortedSz, vSz, blockLines),
   NumEq#(blockLines, TExp#(TLog#(blockLines))), // blockLines is power of two
   NumEq#(n, TExp#(TLog#(n))), // n is power of two
   Mul#(blockLines, n, totalLines),
   Log#(TMul#(2,totalLines), aw), // address matches twice total lines
   MergeSortVar::RecursiveMergerVar#(iType, vSz, fanIn),
   Add#(c__, TLog#(blockLines), aw),
   Add#(d__, TAdd#(TLog#(TDiv#(totalLines, blockLines)), 1), aw),
   Add#(e__, TLog#(TAdd#(TDiv#(totalLines, blockLines), 1)), 32),
   Add#(fanIn, b__, TMul#(TDiv#(fanIn, 2), 2)),
   Add#(1, f__, TMul#(TDiv#(fanIn, 2), 2)),
   Add#(1, g__, fanIn),
   Pipe::FunnelPipesPipelined#(1, fanIn, Bit#(TAdd#(TLog#(TDiv#(totalLines,blockLines)), 1)), 1),
   Pipe::FunnelPipesPipelined#(1, fanIn, Tuple2#(MemoryIfc::MemoryRequest#(Bit#(aw), Vector::Vector#(vSz, iType)), 
                                                 Bit#(TLog#(fanIn))), 1)
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
   Vector#(way, MergeNFold#(iType, vSz, sortedSz, n, fanIn)) merger <- zipWithM(mkMergeNFold, replicate(ascending), mems);
   
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



module mkMergeNFold#(Bool ascending, Vector#(2, MemoryServer#(Bit#(aw), Vector#(vSz, iType))) mems) (MergeNFold#(iType, vSz, sortedSz, n, fanIn)) provisos(
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
   MergeSortVar::RecursiveMergerVar#(iType, vSz, fanIn),
   Add#(g__, TLog#(TAdd#(totalBlocks, 1)), 32),
   Add#(fanIn, b__, TMul#(TDiv#(fanIn, 2), 2)),
   Add#(1, e__, TMul#(TDiv#(fanIn, 2), 2)),
   Add#(1, f__, fanIn),
   Pipe::FunnelPipesPipelined#(1, fanIn, Bit#(TAdd#(TLog#(totalBlocks), 1)),1),
   Pipe::FunnelPipesPipelined#(1, fanIn, Tuple2#(MemoryIfc::MemoryRequest#(Bit#(aw), Vector::Vector#(vSz, iType)), 
                                                 Bit#(TLog#(fanIn))), 1)
   );
   
   Reg#(blkIdT) blkId_init <- mkReg(0);
   FIFOF#(blkIdT) freeBlockQ <- mkSizedBRAMFIFOF(valueOf(totalBlocks)+valueOf(totalBlocks)/valueOf(fanIn));//mkSizedFIFO(valueOf(totalBlocks)*2);
   Reg#(Bool) init <- mkReg(False);
   rule doInit if ( !init);
      blkId_init <= blkId_init + 1;
      if (debug) $display("blkId_init, blkId = %d", blkId_init);
      freeBlockQ.enq(blkId_init);
      if ( blkId_init == fromInteger(valueOf(totalBlocks)+valueOf(totalBlocks)/valueOf(fanIn) - 1) ) 
         init <= True;
   endrule
   
   //Vector#(fanIn, FIFO#(Tuple2#(Maybe#(blkBurstT),blkIdT))) sortedBlockQs <- replicateM(mkSizedFIFO(valueOf(totalBlocks)));
   Vector#(fanIn, FIFO#(Tuple2#(Maybe#(blkBurstT),blkIdT))) sortedBlockQs <- replicateM(mkSizedBRAMFIFO(valueOf(totalBlocks)));
   
   MergeNVar#(iType, vSz, fanIn) merger <- mkStreamingMergeNVar(ascending, 0, 0);
   
   
   FIFOF#(Vector#(vSz, iType)) inQ <- mkFIFOF;
   FIFOF#(Vector#(vSz, iType)) outQ <- mkFIFOF;
   

   Integer blkLines = valueOf(blockLines);
   Integer lgBlkLines = valueOf(TLog#(blockLines));
   Integer totalBlks = valueOf(totalBlocks);
   
   Reg#(blkIdT) currBlkId <- mkRegU;
   Reg#(blkLineT) lineCnt <- mkReg(0);
   Reg#(Bit#(TLog#(fanIn))) fanSel <- mkReg(0);
   
   function Bit#(aw) toAddr(blkIdT blkId, blkLineT lineId);
      return (zeroExtend(blkId)<<fromInteger(lgBlkLines)) + zeroExtend(lineId);
   endfunction
   
   Vector#(fanIn, Reg#(blkLineT)) vLineCntRd <- replicateM(mkReg(0));
   FIFO#(Bit#(TLog#(fanIn))) destFanQ <- mkSizedFIFO(3);
   Integer bufSz = 3+valueOf(TLog#(vSz));
   Vector#(fanIn, FIFOF#(Vector#(vSz, iType))) dataInBufs <- replicateM(mkSizedFIFOF(bufSz+1));
   OneToNRouter#(fanIn,Vector#(vSz, iType)) dataInRouter <- mkOneToNRouterPipelined;
   zipWithM_(mkConnection, takeOutPorts(dataInRouter), map(toPipeIn, dataInBufs));
   Vector#(fanIn, Array#(Reg#(Bit#(8)))) elemCnts <- replicateM(mkCReg(2, 0));
   
   Vector#(fanIn, FIFOF#(blkIdT)) blockReturnQs <- replicateM(mkFIFOF);
   FunnelPipe#(1, fanIn, blkIdT, 1) blockReturnFunnel <- mkFunnelPipesPipelined(map(toPipeOut, blockReturnQs));
   mkConnection(blockReturnFunnel[0], toPipeIn(freeBlockQ));
   
   //FIFO#(MemoryRequest#(Bit#(aw), Vector#(vSz, iType))) memRdReqQ <- mkFIFO;

   Vector#(fanIn, FIFOF#(Tuple2#(MemoryRequest#(Bit#(aw), Vector#(vSz, iType)),Bit#(TLog#(fanIn))))) memRdReqQs <- replicateM(mkFIFOF);
   FunnelPipe#(1,fanIn,Tuple2#(MemoryRequest#(Bit#(aw),Vector#(vSz, iType)),Bit#(TLog#(fanIn))),1) memRdReqFunnel <- mkFunnelPipesPipelined(map(toPipeOut, memRdReqQs));
   
   for (Integer fanSelRd = 0; fanSelRd < valueOf(fanIn); fanSelRd = fanSelRd + 1) begin
      rule doMemReq if ( elemCnts[fanSelRd][1] < fromInteger(bufSz) );
         let {blkBurst, baseBlk} = sortedBlockQs[fanSelRd].first;
         elemCnts[fanSelRd][1] <= elemCnts[fanSelRd][1] + 1;
         if ( blkBurst matches tagged Valid .burst &&& vLineCntRd[fanSelRd] == 0) begin
            merger.inStreams[fanSelRd].lenChannel.enq(unpack(zeroExtend(burst) << fromInteger(lgBlkLines)));
            // if (debug) $display("doMemReq, vLineCnt[%d] = %d, baseBlk = %d, blkBurst = ", fanSelRd, vLineCntRd[fanSelRd], baseBlk, fshow(blkBurst));      
         end
         memRdReqQs[fanSelRd].enq(tuple2(MemoryRequest{addr: toAddr(baseBlk,vLineCntRd[fanSelRd]), datain: ?, write: False},fromInteger(fanSelRd)));
         vLineCntRd[fanSelRd] <= vLineCntRd[fanSelRd] + 1;
         if ( vLineCntRd[fanSelRd] == 0 ) begin
            if (debug) $display("doMemReq, vLineCnt[%d] = %d, baseBlk = %d, blkBurst = ", fanSelRd, vLineCntRd[fanSelRd], baseBlk, fshow(blkBurst));
         end
         if ( vLineCntRd[fanSelRd] == maxBound ) begin
            sortedBlockQs[fanSelRd].deq;
            // freeBlockQ.enq(baseBlk);
            blockReturnQs[fanSelRd].enq(baseBlk);
         end
      endrule
      
      
      rule doMergeInStream;//if ( elemCnts[fanSelRd][0] > 0 );
         let d <- toGet(dataInBufs[fanSelRd]).get();
         // let d = dataInRouter.outPorts[fanSelRd].first;
         // dataInRouter.outPorts[fanSelRd].deq;
         elemCnts[fanSelRd][0] <= elemCnts[fanSelRd][0] - 1;         
         merger.inStreams[fanSelRd].dataChannel.enq(d);
      endrule
   end
      
   rule memRdIssue;
      let {req, fanSel} = memRdReqFunnel[0].first;
      memRdReqFunnel[0].deq;
      mems[1].request.put(req);
      destFanQ.enq(fanSel);
   endrule


   
   rule doMemResp;
      let destFan <- toGet(destFanQ).get;
      let d <- mems[1].response.get();
      // dataInBufs[destFan].enq(d);
      dataInRouter.inPort.enq(tuple2(destFan,d));
   endrule

   
   Reg#(blkBurstT) blkCnt_mergeResp <- mkReg(0);
   FIFO#(Tuple4#(Maybe#(blkIdT), blkBurstT, Bool, Bool)) reservedBlkQ <- mkSizedFIFO(totalBlks);
   
   rule doMergeResp;
      let lineBurst = merger.outStream.lenChannel.first;
      dynamicAssert(lineBurst % fromInteger(blkLines) == 0, "burst should be sortedSz/vecSz aligned");

      blkBurstT blksNeeded = truncate(pack(lineBurst >> fromInteger(lgBlkLines)));
      if ( blkCnt_mergeResp + 1 == blksNeeded ) begin
         blkCnt_mergeResp <= 0;
         merger.outStream.lenChannel.deq;
      end
      else begin
         blkCnt_mergeResp <= blkCnt_mergeResp + 1;
      end
      
      Bool first = blkCnt_mergeResp == 0;
      Bool last = blkCnt_mergeResp + 1 == blksNeeded;
      if (debug) $display("doMergeResp, blksNeeded = %d, (first,last) = (%d, %d)", blksNeeded, first, last);
      if (lineBurst == fromInteger(valueOf(totalLines))) begin
         if (debug) $display("to output port");
         reservedBlkQ.enq(tuple4(tagged Invalid, blksNeeded,first,last));
      end
      else begin
         let blkId <- toGet(freeBlockQ).get;
         reservedBlkQ.enq(tuple4(tagged Valid blkId, blksNeeded,first,last));
      end
   endrule

   Array#(Reg#(Bool)) burstLock <- mkCReg(2, False);   
   Array#(Reg#(blkBurstT)) inflightblks <- mkCReg(2, 0);
   
   Reg#(blkLineT) lineCnt_mergeResp <- mkReg(0); 
   // Reg#(Bit#(TLog#(fanIn))) fanSel_mergeResp <- mkReg(0);

   
   (* descending_urgency="doDeqInPipe, doMergeRespData_feedback" *)
      
   rule doDeqInPipe if (init && inflightblks[1] < fromInteger(valueOf(n)));// && !burstLock[1]);
      let d <- toGet(inQ).get;
      let blkId = currBlkId;
      if (lineCnt == 0 ) begin
         blkId <- toGet(freeBlockQ).get;
         currBlkId <= blkId;
      end
      
      if (debug) $display("doDeqInPipe, lineCnt = %d, blkId = %d", lineCnt, blkId);
      if ( lineCnt == maxBound ) begin
         sortedBlockQs[fanSel].enq(tuple2(tagged Valid 1, blkId));
         fanSel <= fanSel + 1;
         inflightblks[1] <= inflightblks[1] + 1;
      end
      
      lineCnt <= lineCnt + 1;
      mems[0].request.put(MemoryRequest{addr: toAddr(blkId, lineCnt), datain: d, write: True});
   endrule

   
   rule doMergeRespData_feedback (isValid(tpl_1(reservedBlkQ.first)) && inflightblks[1] == fromInteger(valueOf(n)));
      // $display("inflightblks[1] = %d", inflightblks[1]);
      dynamicAssert(inflightblks[1]==fromInteger(valueOf(n)), "feedback is only allowed when all blocks are accumulated");
      let {currBlkId,blkBurst,first,last} = reservedBlkQ.first;
      let blkId = fromMaybe(?, currBlkId);
      let d = merger.outStream.dataChannel.first;
      merger.outStream.dataChannel.deq;
      if (lineCnt_mergeResp == 0) begin
         // if (debug) $display("doMergeRespData, lineCnt_mergeResp = %d, fanSel_mergeResp = %d, blkBurst = %d, first = %d, last = %d, currBlkId = ", lineCnt_mergeResp, fanSel_mergeResp, blkBurst, first, last, fshow(currBlkId));
         // if (first) burstLock[0] <= True;
      end
      if ( lineCnt_mergeResp == maxBound ) begin
         reservedBlkQ.deq;
         sortedBlockQs[fanSel].enq(tuple2(first?tagged Valid blkBurst:tagged Invalid, blkId));
         if ( last ) begin 
            fanSel <= fanSel + 1;
            // burstLock[0] <= False;
         end
      end
      lineCnt_mergeResp <= lineCnt_mergeResp + 1;

      mems[0].request.put(MemoryRequest{addr: toAddr(blkId, lineCnt_mergeResp), datain: d, write: True});
   endrule
   
   rule doMergeRespData_output (!isValid(tpl_1(reservedBlkQ.first)));
      // let {currBlkId,blkBurst,first,last} = reservedBlkQ.first;
      lineCnt_mergeResp <= lineCnt_mergeResp + 1;
      let d = merger.outStream.dataChannel.first;
      merger.outStream.dataChannel.deq;
      if ( lineCnt_mergeResp == maxBound ) begin
         reservedBlkQ.deq;
         inflightblks[0] <= inflightblks[0] - 1;
      end
      dynamicAssert(inflightblks[0]>0, "inflightblks should not go below 0");
      outQ.enq(d);
   endrule

   

   interface inPipe = toPipeIn(inQ);
   interface outPipe = toPipeOut(outQ);
endmodule
