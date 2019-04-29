
// Copyright (c) 2013 Nokia, Inc.

// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use, copy,
// modify, merge, publish, distribute, sublicense, and/or sell copies
// of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
// BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
// ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.


`include "ConnectalProjectConfig.bsv"

import FIFO::*;
import FIFOF::*;
import Vector::*;
import BuildVector::*;
import Connectable::*;
import HostInterface::*;
import Assert::*;

import GetPut::*;
import ClientServer::*;
import ClientServerHelper::*;

// flash controller stuff
import ControllerTypes::*;
import AuroraCommon::*;
import AuroraImportFmc1::*;
import FlashCtrlVirtex::*;
import FlashCtrlModel::*;

//flash test bench
// import FlashBench::*;

//DMA stuff
import ConnectalConfig::*;
import ConnectalMemTypes::*;
import MemReadEngine::*;
import MemWriteEngine::*;
import Pipe::*;

import FlashTypes::*;
import RenameTable::*;
import BRAMFIFOVector::*;

import FlashCtrlIfc::*;
import FlashSwitch::*;


import BRAM::*;


import Clocks::*;
// import Randomizable::*;
import LFSR::*;

// `define EmptyFlash

`ifdef EmptyFlash
import EmptyFlash::*;
`endif


interface Top_Pins;
   `ifndef SIMULATION
   `ifndef EmptyFlash 
   interface Aurora_Pins#(4) aurora_fmc1;
   interface Aurora_Clock_Pins aurora_clk_fmc1;
   interface Aurora_Pins#(4) aurora_fmc2;
   interface Aurora_Clock_Pins aurora_clk_fmc2;
   // interface DDR4_Pins_Dual_VCU108 pins_ddr4;
   `endif
      `endif
endinterface


interface FlashRequest;
   method Action readPage(Bit#(32) card, Bit#(32) bus, Bit#(32) chip, Bit#(32) block, Bit#(32) page, Bit#(32) tag);
   method Action writePage(Bit#(32) card, Bit#(32) bus, Bit#(32) chip, Bit#(32) block, Bit#(32) page, Bit#(32) tag);
   method Action eraseBlock(Bit#(32) card, Bit#(32) bus, Bit#(32) chip, Bit#(32) block, Bit#(32) tag);
   method Action setDmaReadRef(Bit#(32) sgId);
   method Action setDmaWriteRef(Bit#(32) sgId);
   method Action start(Bit#(32) dummy);
   method Action debugDumpReq(Bit#(32) card);
   method Action setDebugVals (Bit#(32) flag, Bit#(32) debugDelay);
endinterface



interface FlashIndication;
   method Action readDone(Bit#(32) tag, Bit#(64) cycles);
   method Action writeDone(Bit#(32) tag, Bit#(64) cycles);
   method Action eraseDone(Bit#(32) tag, Bit#(32) status, Bit#(64) cycles);
   method Action debugDumpResp(Bit#(32) card, Bit#(32) debug0, Bit#(32) debug1, Bit#(32) debug2, Bit#(32) debug3, Bit#(32) debug4, Bit#(32) debug5);
endinterface

interface FlashTop;
   interface FlashRequest request;
   interface Vector#(1, MemReadClient#(DataBusWidth)) dmaReadClient;
   interface Vector#(1, MemWriteClient#(DataBusWidth)) dmaWriteClient;
   interface Top_Pins pins;
endinterface

typedef 16 CmdQDepth;

// typedef TMul#(CmdQDepth, 8) FIFODepth;


// NumDmaChannels each for flash i/o and emualted i/o
//typedef TAdd#(NumDmaChannels, NumDmaChannels) NumObjectClients;
//typedef NumDmaChannels NumObjectClients;
typedef 128 DmaBurstBytes;
// typedef 8224 DmaBurstBytes; 

typedef TMul#(WordSz,2) BeatSz;
Integer beatBytes = valueOf(BeatSz)/8;
Integer dmaBurstBytes        = valueOf(DmaBurstBytes);
Integer dmaBurstFlashWords   = dmaBurstBytes/wordBytes; //128/16 = 8
Integer dmaBurstBeats        = dmaBurstBytes/beatBytes; //128/32 = 4
Integer dmaBurstsPerPage     = (pageSizeUser+dmaBurstBytes-1)/dmaBurstBytes; //ceiling, 65
// Integer dmaBurstFlashWordsLast    = (pageSizeUser%dmaBurstBytes)/wordBytes; //num bursts in last dma; 2 bursts
Integer dmaBurstBeatsLast    = (pageSizeUser%dmaBurstBytes)/beatBytes; //num bursts in last dma; 2 bursts
// Integer pagePadCnt           = dmaBurstFlashWords - dmaBurstFlashWordsLast; //6
Integer pageBeatPadCnt           = dmaBurstBeats - dmaBurstBeatsLast; //6
Integer dmaAllocPageSizeLog  = 14; //typically portal alloc page size is 16KB; MUST MATCH SW

Integer pageBeats            = pageWords/2;

typedef TAdd#(TDiv#(DmaBurstBytes,32),4) FIFODepth;
// typedef TDiv#(PageSizeUser, 32) FIFODepth;



(*synthesize*)
module mkBRAMFIFOVectorSynth(BRAMFIFOVectorIfc#(TLog#(TAGS_PER_PORT), FIFODepth, Tuple2#(Bit#(BeatSz), TagT)));
  BRAMFIFOVectorIfc#(TLog#(TAGS_PER_PORT), FIFODepth, Tuple2#(Bit#(BeatSz), TagT)) bramFifoVec <- mkBRAMFIFOVector(dmaBurstBeats, pageBeats, pageBeatPadCnt);
   
   // BRAMFIFOVectorIfc#(TLog#(TAGS_PER_PORT), FIFODepth, Tuple2#(Bit#(BeatSz), TagT)) bramFifoVec <- mkBRAMFIFOVector(dmaBurstBeats, pageBeats, 0);
   return bramFifoVec;
endmodule


module mkFlashTop#(HostInterface host, FlashIndication indication)(FlashTop);
   
   Clock clk110 = host.derivedClock;
   Reset rst110 = host.derivedReset;
   ////////////////////////////////////////////////////////////////////////////////
   /// Flash Controllers Instantiation 
   ////////////////////////////////////////////////////////////////////////////////
   Vector#(2,FlashCtrlVirtexIfc) flashCtrls;
   Vector#(2,GtClockImportIfc) gtx_clk_fmcs <- replicateM(mkGtClockImport);
   
   
   // ClockDividerIfc clk_div <- mkClockDivider(2);
   
   // Clock half_clk = clk_div.slowClock;
   // Reset half_rst <- mkSyncReset(5, user_reset_n, derivedClock);
   
   
   
   `ifdef EmptyFlash
   flashCtrls <- replicateM(mkEmptyFlashCtrl);
   `else
   `ifdef BSIM
   flashCtrls[0] <- mkFlashCtrlModel(gtx_clk_fmcs[0].gt_clk_p_ifc, gtx_clk_fmcs[0].gt_clk_n_ifc, clk110, rst110);
   flashCtrls[1] <- mkFlashCtrlModel(gtx_clk_fmcs[1].gt_clk_p_ifc, gtx_clk_fmcs[1].gt_clk_n_ifc, clk110, rst110);
   `else
   flashCtrls[0] <- mkFlashCtrlVirtex1(gtx_clk_fmcs[0].gt_clk_p_ifc, gtx_clk_fmcs[0].gt_clk_n_ifc, clk110, rst110);
   flashCtrls[1] <- mkFlashCtrlVirtex2(gtx_clk_fmcs[1].gt_clk_p_ifc, gtx_clk_fmcs[1].gt_clk_n_ifc, clk110, rst110);
   `endif
   `endif
   
   Vector#(2, FlashSwitch#(2)) flashSwitches <- replicateM(mkFlashSwitch);
   

   zipWithM_(mkConnection, map(extractFlashCtrlClient, flashSwitches), map(extractFlashCtrlUser, flashCtrls));
   
   Vector#(2, FlashCtrlUser) dmaFlashUsers = zipWith(select, map(extractFlashCtrlUsers, flashSwitches), replicate(0));
   
   Reg#(Bool) started <- mkReg(False);
   
   
   FIFO#(MultiFlashCmd) flashCmdQ <- mkFIFO;
   
   MemReadEngine#(DataBusWidth, DataBusWidth, CmdQDepth, NUM_ENG_PORTS) re <- mkMemReadEngine;
   // MemWriteEngine#(DataBusWidth, DataBusWidth, CmdQDepth, NUM_ENG_PORTS) we <- mkMemWriteEngineBuff(valueOf(CmdQDepth)*128);
   MemWriteEngine#(DataBusWidth, DataBusWidth, CmdQDepth, NUM_ENG_PORTS) we <- mkMemWriteEngine;
   
   Reg#(NodeT) myNodeId <- mkReg(0);
   
   

	Reg#(Bit#(32)) delayRegSet <- mkReg(0);
	Reg#(Bit#(8)) delayReg <- mkReg(0);
	Reg#(Bit#(1)) debugFlag <- mkReg(0);
	Reg#(Bit#(32)) debugReadCnt <- mkReg(0);
	Reg#(Bit#(32)) debugWriteCnt <- mkReg(0);

   
   // tuple2: original tag, bus number
   Vector#(2, RenameTable#(128, Tuple2#(TagT, Bit#(3)))) reqTb <- replicateM(mkRenameTable);
   

   BRAM2Port#(Bit#(7), Bit#(64)) cycleStore <- mkBRAM2Server(defaultValue); 
   
   Reg#(Bit#(64)) cycles <- mkReg(0);
   
   rule incrCycle;
      cycles <= cycles + 1;
   endrule
   
   ////////////////////////////////////////////////////////////////////////////////
   /// Drive Flash Commands
   ////////////////////////////////////////////////////////////////////////////////
      

   rule driveFlashCmd (started);
      flashCmdQ.deq;
      let v = flashCmdQ.first;
      cycleStore.portA.request.put(BRAMRequest{write:True, responseOnWrite:False, address:v.cmd.tag, datain:cycles});
      let dst = v.dstNode;
      let cardId = v.cardId;
      let newTag <- reqTb[cardId].writeEntry(tuple2(v.cmd.tag, v.cmd.bus));
      $display(fshow(v.cmd.op));
      $display("Flash Cmd to (%d, %d, %d, %d, %d), orTag = %d, newTag = %d", v.cardId, v.cmd.bus, v.cmd.chip, v.cmd.block, v.cmd.page, v.cmd.tag, newTag);
      v.cmd.tag = newTag;
      dmaFlashUsers[cardId].sendCmd(v.cmd);
   endrule
   
   
   ////////////////////////////////////////////////////////////////////////////////
   /// Read from Flash
   ////////////////////////////////////////////////////////////////////////////////
   
   Vector#(2, FIFO#(Tuple2#(Bit#(WordSz), TagT))) readWordQs <- replicateM(mkFIFO);
   
   Vector#(2, FIFOF#(Tuple4#(Bit#(BeatSz), TagT, TagT, Bit#(1)))) readBeatsQs <- replicateM(mkFIFOF);
   
   FIFO#(Tuple4#(Bit#(BeatSz), TagT, TagT, Bit#(1))) readRespQ <- mkFIFO;
   for (Integer i = 0; i < 2; i = i + 1) begin
      
      Vector#(8, Reg#(Bit#(1))) pageWordCnts <- replicateM(mkReg(0));
      // TagGen#(8) busTagGen <- mkTagGen;
      
      rule flashReadResp;
         let v <- dmaFlashUsers[i].readWord;

         let {data, reTag} = v;
         // $display("FlashCtrl[%d] return {data, tag} = {%h, %d}", i, data, reTag);
         reqTb[i].readEntry(reTag);
         readWordQs[i].enq(v);
      endrule
      
      Vector#(8, Reg#(Bit#(WordSz))) readBufs <- replicateM(mkRegU);
      rule getOriginalTag;
         let {data, reTag} <- toGet(readWordQs[i]).get;
         let {orTag, busId} <- reqTb[i].readResp;
         pageWordCnts[busId] <= pageWordCnts[busId] + 1;
         readBufs[busId] <= data;
         // $display("FlashCard = %d BusId = %d, pageWordCnts[busId] = %d, readBuf[busId] = %h", i, busId, pageWordCnts[busId], readBufs[busId]);
         if ( pageWordCnts[busId] == 1)
            readBeatsQs[i].enq(tuple4({data,readBufs[busId]},orTag,reTag,fromInteger(i)));
            // readRespQ.enq(tuple4({data,readBufs[busId]},orTag,reTag,fromInteger(i)));
      endrule
      
      // rule doMerge;
      //    let d <- toGet(readBeatsQs[i]).get;
      //    readRespQ.enq(d);
      // endrule
   end
   
   // FunnelPipe#(1,2,Tuple4#(Bit#(BeatSz), TagT, TagT, Bit#(1)),2) readRespFunnel <- mkFunnelPipesPipelinedRR(map(toPipeOut, readBeatsQs), 1);
   FunnelPipe#(1,2,Tuple4#(Bit#(BeatSz), TagT, TagT, Bit#(1)),2) readRespFunnel <- mkFunnelPipesPipelined(map(toPipeOut, readBeatsQs));
   

   
   
   ////////////////////////////////////////////////////////////////////////////////
   /// DMA Write the Read Resp
   ////////////////////////////////////////////////////////////////////////////////


   Reg#(Bit#(32)) dmaWriteSgid <- mkReg(0);   
   Vector#(NUM_ENG_PORTS, BRAMFIFOVectorIfc#(TLog#(TAGS_PER_PORT), FIFODepth, Tuple2#(Bit#(BeatSz), TagT))) bramFifoVec <- replicateM(mkBRAMFIFOVectorSynth());
   Vector#(NUM_ENG_PORTS, FIFO#(Tuple2#(TagT, Bit#(32)))) dmaReq2RespQ <- replicateM(mkSizedFIFO(valueOf(CmdQDepth))); //TODO sz?
   Vector#(NUM_ENG_PORTS, FIFO#(MemengineCmd)) dmaWriteReqQ <- replicateM(mkSizedFIFO(16));
   Vector#(NUM_ENG_PORTS, FIFOF#(TagT)) dmaWriteDoneQs <- replicateM(mkFIFOF);
   
   function Tuple2#(Bit#(TLog#(TAGS_PER_PORT)), Bit#(TLog#(NUM_ENG_PORTS))) decTag(TagT tag);
      Bit#(TLog#(NUM_ENG_PORTS)) engPortSel  = truncate(tag);
      Bit#(TLog#(TAGS_PER_PORT)) idx         = truncate(tag>>log2(num_eng_ports));
      return tuple2(idx, engPortSel);
   endfunction

   function TagT encTag(Bit#(TLog#(TAGS_PER_PORT)) idx, Bit#(TLog#(NUM_ENG_PORTS)) engPort);
      TagT tmpIdx  = zeroExtend(idx);
      TagT tmpEp   = zeroExtend(engPort);
      TagT tag     = (tmpIdx<<log2(num_eng_ports)) | tmpEp;
      return tag;
   endfunction

   function Bit#(32) calcDmaPageOffset(TagT tag);
      Bit#(32) off = zeroExtend(tag);
      return (off<< dmaAllocPageSizeLog);
   endfunction
   
   // Vector#(NumTags, Reg#(Tuple2#(Bit#(1), TagT))) tagTable <- replicateM(mkRegU);
   BRAM2Port#(Bit#(7), Tuple2#(Bit#(1), TagT)) tagTable <- mkBRAM2Server(defaultValue);    
   
   
   Reg#(Bit#(64)) prevCycleRd <- mkReg(-1);
   
   rule doDistrReadFromFlash;
	  // let {data, orTag, reTag, card} <- toGet(readRespQ).get;
	  let {data, orTag, reTag, card} <- toGet(readRespFunnel[0]).get;
	  let taggedRdata = tuple2(data, orTag);
	  //let taggedRdata = dataFlash2FifoVecQ.first;
	  //dataFlash2FifoVecQ.deq;
	  //match{.data, .tag} = taggedRdata;
	  match{.idx, .sel} = decTag(orTag);
	  bramFifoVec[sel].enq(taggedRdata, idx);
	  // $display("[%d] @%d FlashTop.bsv: flash read sel=%d, idx=%d, orTag=%d, data=%x", myNodeId, 
	  // 				cycles, sel, idx, orTag, data);
      prevCycleRd <= cycles;
      if ( cycles - prevCycleRd > 1) $display("WARNING:: Bubble on Flash Top, cycles = %d, prevCycleRd = %d", cycles, prevCycleRd);
      // tagTable[orTag] <= tuple2(card, reTag);
      tagTable.portA.request.put(BRAMRequest{write:True, responseOnWrite:False, address:orTag, datain:tuple2(card, reTag)});
   endrule




   //connect output of bramfifovecs with WE port
   for (Integer p=0; p<num_eng_ports; p=p+1) begin
      rule createDmaWriteReq;
	     let {rdyIdx, rdyCnt} <- bramFifoVec[p].getReadyIdx();
	     //req DMA
	     TagT tag              = encTag(rdyIdx, fromInteger(p));
	     Bit#(32) pageOffset   = calcDmaPageOffset(tag);
	     Bit#(32) burstOffset  = (rdyCnt<<log2(dmaBurstBytes)) + pageOffset;
	     let dmaCmd            = MemengineCmd {
	                                           sglId: dmaWriteSgid, 
	                                           base: zeroExtend(burstOffset),
	                                           len:fromInteger(dmaBurstBytes), 
	                                           burstLen:128
	                                           };
	     // bramFifoVec[p].reqDeq(rdyIdx);
	  
	     dmaReq2RespQ[p].enq(tuple2(tag, rdyCnt));
	     $display("[%d] FlashTop.bsv: init dma write rdyIdx=%d, rdyCnt=%d, engId=%d, tag=%d, addr=0x%x 0x%x", myNodeId, 
	              rdyIdx, rdyCnt, p, tag, dmaWriteSgid, burstOffset);
         
         $display("time == %t, we [%d] request put", $time, p);
	     we.writeServers[p].request.put(dmaCmd);
         
      endrule
      
      
      Reg#(Bit#(64)) lastCycleBeat <- mkReg(0);
      
      rule displayDMAbp if (!we.writeServers[p].data.notFull);
         $display("BackPressure:: dmaWriteChannel %d @ %d", p, cycles);
      endrule
         
      rule sendDmaWrites;
	     let data <- bramFifoVec[p].respDeq();
         we.writeServers[p].data.enq(tpl_1(data));
	     $display("[%d] @%d FlashTop.bsv: DmaWritesData ENGID=%d,tag=%d data=%x ", myNodeId, 
	              cycles, p, tpl_2(data), tpl_1(data));
         lastCycleBeat <= cycles;
         if ( cycles - lastCycleBeat > 1 ) begin
            $display("WARNING:: dmaWrite data bubble, cycles = %d, lastCycleRd = %d", cycles, lastCycleBeat);
         end
         
      endrule


      //dma response.get done; when enough has accumulated, send ack to sw
      rule dmaWriterGetResponse;
	     let dummy <- we.writeServers[p].done.get;
	     let {tag, idxCnt} = dmaReq2RespQ[p].first;
	     dmaReq2RespQ[p].deq;
	     $display("[%d] @%d FlashTop.bsv: dma resp of ENG[%d] %d out of dmaBurstsPerPage = %d, tag=%d", myNodeId, cycles, p, idxCnt, dmaBurstsPerPage, tag);
	     if ( idxCnt==fromInteger(dmaBurstsPerPage-1)) begin
	        dmaWriteDoneQs[p].enq(tag);
	     end
      endrule

   end
   
   
   FunnelPipe#(1,NUM_ENG_PORTS,TagT,2) dmaWriteDoneFunnel <- mkFunnelPipesPipelined(map(toPipeOut, dmaWriteDoneQs));
   FIFO#(TagT) donePipe <- mkFIFO;
   rule rl_writeDoneArb;
      let tag <- toGet(dmaWriteDoneFunnel[0]).get;
      cycleStore.portB.request.put(BRAMRequest{write:False, responseOnWrite:False, address:tag, datain:?});
      tagTable.portB.request.put(BRAMRequest{write:False, responseOnWrite:False, address:tag, datain:?});
      donePipe.enq(tag);
   endrule
	  
   rule rl_writeDoneInd;
      let tag <- toGet(donePipe).get;
      // let {card, reTag} = tagTable[tag];
      let {card, reTag} <- tagTable.portB.response.get;
      reqTb[card].invalidEntry(reTag);
      let startCycle <- cycleStore.portB.response.get;
      
      // indication is gonna be slow
	  //indication.readDone(zeroExtend(tag), cycles - startCycle);
   endrule

      

   
   
   //--------------------------------------------
   // Writes to Flash (DMA Reads)
   //--------------------------------------------
   Reg#(Bit#(32)) dmaReadSgid <- mkReg(0);
   Vector#(NUM_ENG_PORTS, FIFO#(Tuple2#(TagT, Bit#(1)))) dmaRdReq2RespQ <- replicateM(mkSizedFIFO(4)); //TODO sz
   Vector#(NUM_ENG_PORTS, Reg#(Bit#(32))) dmaReadBurstCount <- replicateM(mkReg(0));
   Vector#(NUM_ENG_PORTS, FIFO#(TagT)) dmaReadReqQ <- replicateM(mkSizedFIFO(4));
   Vector#(NUM_ENG_PORTS, Reg#(Bit#(32))) dmaRdReqCnts <- replicateM(mkReg(0));
   Reg#(Bit#(TLog#(NUM_ENG_PORTS))) reSel <- mkReg(0);
   // flash controller, original tag, renamed tag
   Vector#(2,FIFO#(Tuple3#(Bit#(1), TagT, TagT))) flashWrReqQs <- replicateM(mkFIFO);
   FIFO#(Tuple3#(Bit#(1), TagT, TagT)) writeDataReq <- mkFIFO;
   
   for ( Integer i = 0; i < 2; i = i + 1) begin
	  rule flashWriteReq;
		 TagT tag <- dmaFlashUsers[i].writeDataReq();
         reqTb[i].readEntry(tag);
         flashWrReqQs[i].enq(tuple3(fromInteger(i), ?, tag));
         $display("[%d] FlashTop.bsv: writeDataReq received from controller card=%d, tag=%d", myNodeId,i,tag);
		 // WdReqT req = WdReqT{origTag: ?, reTag: tag, src: ?, dst: ?};
		 // flashSplit.locFlashCli.writeDataReq.put(req);
	  endrule
      
      rule getOriginalTag_Write;
         let {card, original_tag, renamed_tag} <- toGet(flashWrReqQs[i]).get;
         let {tag, busId} <- reqTb[i].readResp;
         original_tag = tag;
         $display("getOriginalTag_Write : {card, orTag, reTag} = {%d, %d, %d}", card, original_tag, renamed_tag);
         writeDataReq.enq(tuple3(card,original_tag,renamed_tag));
      endrule
   
   end

   //Handle write data requests
   rule handleWriteDataRequestFromFlash;
	  let {card, orginal_tag, renamed_tag} <- toGet(writeDataReq).get;

	  dmaReadReqQ[reSel].enq(orginal_tag); //use original tag to get DMA data
	  // //use renamed tag when forwarding bursts; req src is dst of bursts
	  dmaRdReq2RespQ[reSel].enq(tuple2(renamed_tag, card)); 
	  //round robin through the REs
	  if (reSel == fromInteger(num_eng_ports-1)) begin
		 reSel <= 0;
	  end
	  else begin
		 reSel <= reSel + 1;
	  end
   endrule

   for (Integer p=0; p<num_eng_ports; p=p+1) begin

	  rule issueDmaRead; 
		 //for each req in dmaReadReqQ, read the entire page
		 let tag = dmaReadReqQ[p].first;
		 Bit#(32) pageOffset = calcDmaPageOffset(tag);
		 Bit#(32) burstOffset = (dmaRdReqCnts[p]<<log2(dmaBurstBytes)) + pageOffset;
		 let dmaCmd = MemengineCmd {
		                            sglId: dmaReadSgid, 
		                            base: zeroExtend(burstOffset),
		                            len:fromInteger(dmaBurstBytes), 
		                            burstLen:128
		                            };
		 re.readServers[p].request.put(dmaCmd);
		 $display("[%d] FlashTop.bsv: dma read cmd issued: tag=%d base=%x, burstOffset=%d", myNodeId, tag, dmaReadSgid, burstOffset);
		 if (dmaRdReqCnts[p] == fromInteger(dmaBurstsPerPage-1)) begin
			dmaRdReqCnts[p] <= 0;
			dmaReadReqQ[p].deq; //done with this req
		 end
		 else begin
			dmaRdReqCnts[p] <= dmaRdReqCnts[p] + 1;
		 end
	  endrule

	  // rule dmaReaderGetResponse;
	  //    let dummy <- re.readServers[p].done.get;
	  // endrule

	  //forward data
	  FIFO#(Tuple3#(Bit#(128), TagT, Bit#(1))) writeWordPipe <- mkFIFO();
      
      Reg#(Bit#(1)) beatCntDmaRd <- mkReg(0);
      Reg#(Bit#(WordSz)) upperWord <- mkRegU;
	  rule pipeDmaRdData;
         beatCntDmaRd <= beatCntDmaRd + 1;
         
         let outData = upperWord;
         
         if ( beatCntDmaRd == 0 ) begin
		    let v <- toGet(re.readServers[p].data).get;
            upperWord <= truncateLSB(v.data);
            outData = truncate(v.data);
         end
         
		 let {retag, dst} = dmaRdReq2RespQ[p].first;
		 if (dmaReadBurstCount[p] < fromInteger(pageWords)) begin
			writeWordPipe.enq(tuple3(outData, retag, dst));
			$display("[%d] FlashTop.bsv: forwarded dma read data [%d]: retag=%d, dst=%d, data=%x", 
			         myNodeId, dmaReadBurstCount[p], retag, dst, outData);
		 end
		 else begin 
			//drop the data because it's just 0 padded
			$display("[%d] FlashTop.bsv: dropped dma read data[%d]", myNodeId, dmaReadBurstCount[p]);
		 end

		 if (dmaReadBurstCount[p] == fromInteger(dmaBurstsPerPage*dmaBurstFlashWords-1)) begin
			dmaRdReq2RespQ[p].deq;
			dmaReadBurstCount[p] <= 0;
		 end
		 else begin
			dmaReadBurstCount[p] <= dmaReadBurstCount[p] + 1;
		 end
	  endrule

	  rule forwardDmaRdData;
		 writeWordPipe.deq;
		 debugWriteCnt <= debugWriteCnt + 1;
         let {data, retag, dst} = writeWordPipe.first;
		 // flashSplit.locFlashServ.writeWord.put(writeWordPipe.first);
		 dmaFlashUsers[dst].writeWord(tuple2(data, retag));
	  endrule
	  
   end //for each engine port

   // //local write data
   // rule locWriteData;
   //    let d <- flashSplit.locFlashCli.writeWord.get();
   //    flashCtrl.writeWord(tuple2(tpl_1(d), tpl_2(d)));
   // endrule


	//--------------------------------------------
	// Writes/Erase Acks
	//--------------------------------------------
   FIFO#(Tuple2#(TagT, StatusT)) ackQ <- mkFIFO;
   
   let rand_error <- mkLFSR_32;
   for (Integer i = 0; i < 2; i = i + 1) begin
      FIFO#(Tuple2#(TagT, StatusT)) ackTempQ <- mkFIFO;
	  rule locAck;
		 let ackStatus <- dmaFlashUsers[i].ackStatus();
		 let {tag, status} = ackStatus;
         reqTb[i].readEntry(tag);
         ackTempQ.enq(ackStatus);
		 // flashSplit.locFlashCli.ackStatus.put(tuple3(tag, status, ?));
         cycleStore.portB.request.put(BRAMRequest{write:False, responseOnWrite:False, address:tag, datain:?});
	  endrule
		
	  //Handle acks from controller

	  rule handleControllerAck;
         let {orTag, busId} <- reqTb[i].readResp;
         let {reTag, status} <- toGet(ackTempQ).get;
       
         reqTb[i].invalidEntry(reTag);
         let startCycle <- cycleStore.portB.response.get;
         case (status)
		    WRITE_DONE: indication.writeDone(zeroExtend(orTag), cycles - startCycle);
		    ERASE_DONE: begin
                           `ifdef SIMULATION
                           let randv = rand_error.value;
                           rand_error.next;
                           indication.eraseDone(zeroExtend(orTag), zeroExtend(pack(randv%100==0)), cycles - startCycle);
                           `else
                           indication.eraseDone(zeroExtend(orTag), 0, cycles - startCycle);
                           `endif
                        end
		    ERASE_ERROR: indication.eraseDone(zeroExtend(orTag), 1, cycles - startCycle);
	     endcase
	  endrule
   end


	//--------------------------------------------
	// Debug
	//--------------------------------------------

   FIFO#(Bit#(1)) debugReqQ <- mkFIFO();
	// rule doDebugDump;
	// 	$display("[%d] FlashTop.bsv: debug dump request received", myNodeId);
	// 	debugReqQ.deq;
	// 	let debugCnts = dmaFlashUsers[0].debug.getDebugCnts(); 
	// 	let gearboxSendCnt = tpl_1(debugCnts);         
	// 	let gearboxRecCnt = tpl_2(debugCnts);   
	// 	let auroraSendCntCC = tpl_3(debugCnts);     
	// 	let auroraRecCntCC = tpl_4(debugCnts);  
	// 	indication.debugDumpResp(gearboxSendCnt, gearboxRecCnt, auroraSendCntCC, auroraRecCntCC, debugReadCnt, debugWriteCnt);
	// endrule


   Reg#(Bit#(32)) flashReqCnt <- mkReg(0);
   Reg#(Bit#(32)) totalReqs <- mkReg(0);

   
   interface FlashRequest request;   
      method Action readPage(Bit#(32) card, Bit#(32) bus, Bit#(32) chip, Bit#(32) block, Bit#(32) page, Bit#(32) tag) if (started);
         FlashCmd fcmd = FlashCmd{tag: truncate(tag),
                                  op: READ_PAGE,
                                  bus: truncate(bus),
                                  chip: truncate(chip),
                                  block: truncate(block),
                                  page: truncate(page)
                                  };
         flashCmdQ.enq(MultiFlashCmd{srcNode: myNodeId, dstNode: truncate(card>>1), cardId: card[0], cmd: fcmd});
         // flashReqCnt <= flashReqCnt + 1;
         // $display("flashReqCnt = %d", flashReqCnt);
         // if ( flashReqCnt + 1 == totalReqs )
         //    indication.readDone(tag, 0);
      endmethod
      method Action writePage(Bit#(32) card, Bit#(32) bus, Bit#(32) chip, Bit#(32) block, Bit#(32) page, Bit#(32) tag);
         FlashCmd fcmd = FlashCmd{tag: truncate(tag),
            op: WRITE_PAGE,
            bus: truncate(bus),
            chip: truncate(chip),
            block: truncate(block),
            page: truncate(page)
            };
         flashCmdQ.enq(MultiFlashCmd{srcNode: myNodeId, dstNode: truncate(card>>1), cardId: card[0], cmd: fcmd});
//         indication.writeDone(tag, 0);
      endmethod
      method Action eraseBlock(Bit#(32) card, Bit#(32) bus, Bit#(32) chip, Bit#(32) block, Bit#(32) tag);

         FlashCmd fcmd = FlashCmd{tag: truncate(tag),
            op: ERASE_BLOCK,
            bus: truncate(bus),
            chip: truncate(chip),
            block: truncate(block),
            page: 0
            };
         flashCmdQ.enq(MultiFlashCmd{srcNode: myNodeId, dstNode: truncate(card>>1), cardId: card[0], cmd: fcmd});
         $display("eraseBlock method ", fshow(fcmd));
         // indication.eraseDone(tag, 0,0);
      endmethod
   
      method Action setDmaReadRef(Bit#(32) sgId);
         $display("setDmaReadRef = %d", sgId);
         dmaReadSgid <= sgId;
      endmethod
      method Action setDmaWriteRef(Bit#(32) sgId);
         $display("setDmaWriteRef = %d", sgId);
         dmaWriteSgid <= sgId;
      endmethod
      
      
      method Action start(Bit#(32) dummy);
         started <= True;
         totalReqs <= dummy;
         rand_error.seed(dummy);
      endmethod
      method Action debugDumpReq(Bit#(32) card);
      
      endmethod
      method Action setDebugVals (Bit#(32) flag, Bit#(32) debugDelay);
      
      endmethod


      // method Action auroraStatus();
      // `ifndef SIMULATION
      //    indication.auroraStatus1(extend(flashCtrls[0].auroraStatus.channel_up), extend(flashCtrls[0].auroraStatus.lane_up));
      //    indication.auroraStatus2(extend(flashCtrls[1].auroraStatus.channel_up), extend(flashCtrls[1].auroraStatus.lane_up));
      //  `else
      //    indication.auroraStatus1(1, 3);
      //    indication.auroraStatus2(1, 3);
      //  `endif
      // endmethod
      // method Action start(Bit#(64) randSeed);
      //    flashTests[0].start(randSeed);
      //    flashTests[1].start(randSeed);
      // endmethod
   endinterface
   
   interface dmaReadClient = vec(re.dmaClient);
   interface dmaWriteClient = vec(we.dmaClient);


      interface Top_Pins pins;      

         `ifndef SIMULATION
         `ifndef EmptyFlash
         interface Aurora_Pins aurora_fmc1 = flashCtrls[0].aurora;
         interface Aurora_Clock_Pins aurora_clk_fmc1 = gtx_clk_fmcs[0].aurora_clk;
         interface Aurora_Pins aurora_fmc2 = flashCtrls[1].aurora;
         interface Aurora_Clock_Pins aurora_clk_fmc2 = gtx_clk_fmcs[1].aurora_clk;
         `endif
      // interface ddr4_clock = ddr4_clocks.ddr4_sys_clk;
      // interface DDR4_Pins_Dual_VCU108 pins_ddr4;
      //    interface pins_c0 = ddr4_ctrl_0.ddr4;
      //    interface pins_c1 = ddr4_ctrl_1.ddr4;
      // endinterface      
         `endif
      endinterface
      
endmodule
