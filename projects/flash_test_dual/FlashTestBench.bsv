import TagAlloc::*;
import FlashTestTypes::*;
import RegFile::*;
import ControllerTypes::*;
import FIFO::*;
import FIFOF::*;
import Vector::*;
import GetPut::*;
import ClientServer::*;

typedef struct{
   Bit#(64) cycles; 
   Bit#(32) erased_blocks;
   Bit#(32) bad_blocks;
} EraseRetT deriving(Bits, Eq);


typedef struct{
   Bit#(64) cycles; 
   Bit#(32) written_pages;
} WriteRetT deriving(Bits, Eq);

typedef struct{
   Bit#(64) cycles;
   Bit#(32) read_pages;
   Bit#(32) wrong_words;
   Bit#(32) wrong_pages;
} ReadRetT deriving(Bits, Eq);


interface FlashTestBenchIfc;
   method Action start(Bit#(64) randSeed);
   method ActionValue#(EraseRetT) eraseDone;
   method ActionValue#(WriteRetT) writeDone;
   method ActionValue#(ReadRetT) readDone;
   // method Action eraseDone(Bit#(64) cycles, Bit#(32) erased_blocks, Bit#(32) bad_blocks);
   // method Action writeDone(Bit#(64) cycles, Bit#(32) writen_pages);
   // method Action readDone(Bit#(64) cycles, Bit#(32) read_pages, Bit#(32) wrong_words, Bit#(32) wrong_pages);
endinterface


module mkFlashTestBench#(FlashCtrlUser flash)(FlashTestBenchIfc);
   TagServer tagAlloc <- mkTagAlloc();

   
   Reg#(Bool) started <- mkReg(False);
   Reg#(Bit#(64)) cycles <- mkReg(0);
   
   // (* descending_urgency = "eraseBlockReq" *)
   
      
   rule increCycle;// (started);
      cycles <= cycles + 1;
   endrule
   
   FIFOF#(Bit#(TLog#(NumBlocks))) eraseReqQ <- mkFIFOF();
   Reg#(Bit#(TLog#(TestNumBlocks))) blockCnt <- mkReg(0);
   
   RegFile#(TagT, Bit#(TLog#(TestNumBlocks))) lut <- mkRegFileFull();
   
   rule eraseBlocksReq;
      let blockBase = eraseReqQ.first;
      if ( blockCnt + 1 == 0) begin
         eraseReqQ.deq();
      end
      
      blockCnt <= blockCnt + 1;         
      
      let tag <- tagAlloc.reqTag.response.get();
      Bit#(TLog#(NumBlocks)) blockAddr = blockBase + extend(blockCnt);
         
      Bit#(TLog#(NUM_BUSES)) busid = truncate(blockAddr);
      Bit#(TLog#(ChipsPerBus)) chipid = truncate(blockAddr>>fromInteger(lgBusOffset));
      Bit#(TLog#(BlocksPerCE)) blockid = truncateLSB(blockAddr);
      $display("Erase Flash tag  = %d, blockCnt = %d", tag, blockCnt);

      flash.sendCmd(FlashCmd{tag: tag, op: ERASE_BLOCK, bus: busid, chip: chipid, 
                             block: extend(blockid), page: 0});
      lut.upd(tag, truncate(blockCnt));
   endrule
   
   FIFOF#(Bit#(TLog#(NumBlocks))) eraseRespQ <- mkFIFOF();
   Reg#(Bit#(TLog#(TestNumBlocks))) eraseActCnt <- mkReg(0);
   
   Reg#(Bit#(TAdd#(TLog#(TestNumBlocks),1))) numBadBlocks <- mkReg(0);
   
   RegFile#(Bit#(TLog#(TestNumBlocks)), Bool) badBlockMap <- mkRegFileFull();   
   // BRAM2Port#(Bit#(, BlockT) blockMap <- mkBRAM2Server(cfg);
   
   FIFOF#(Tuple2#(Bit#(TLog#(NumBlocks)), Bit#(TAdd#(TLog#(TestNumPages),1)))) writeReqQ <- mkFIFOF();
   FIFO#(Bit#(TAdd#(TLog#(TestNumPages),1))) writeDataReqQ <- mkFIFO();
   FIFO#(Bit#(TAdd#(TLog#(TestNumPages),1))) writeAckReqQ <- mkFIFO();
   
   FIFO#(EraseRetT) eraseDoneQ <- mkFIFO();
   
   Reg#(Bit#(64)) startCycle_wr <- mkRegU();
   
   rule eraseBlocksResp if (eraseRespQ.notEmpty);
      let blockBase = eraseRespQ.first();
      
      eraseActCnt <= eraseActCnt + 1;

      let v <- flash.ackStatus;
      let tag = tpl_1(v);
      let status = tpl_2(v);
      
      let tempBadBlocks = numBadBlocks;
      
      $display("Got Erase Acknowledge tag = %d, status = %d, eraceActCnt = %d", tag, status, eraseActCnt);
      
      let addr = lut.sub(tag);
      if ( status == ERASE_DONE )begin
         badBlockMap.upd(addr, True);
      end
      else if (status == ERASE_ERROR )begin
         tempBadBlocks = numBadBlocks + 1;
         badBlockMap.upd(addr, False);
      end
      
      tagAlloc.retTag.put(tag);
      if ( eraseActCnt == -1 ) begin
         eraseRespQ.deq();
         // going to next step: Write Pages
         // tempBadBlocks = 0;
         Bit#(32) testPages = fromInteger(testNumPages) - extend(tempBadBlocks)<<fromInteger(valueOf(TLog#(PagesPerBlock)));
         
         $display("testPages == %d", testPages);
         writeReqQ.enq(tuple2(blockBase, truncate(testPages)));
         writeDataReqQ.enq(truncate(testPages));
         writeAckReqQ.enq(truncate(testPages));
         startCycle_wr <= cycles;
         eraseDoneQ.enq(EraseRetT{cycles: cycles, erased_blocks:fromInteger(testNumBlocks), bad_blocks:extend(tempBadBlocks)});
         tagAlloc.reqTag.request.put(testPages);
         // tagAlloc.reqTag.request.put(fromInteger(testNumPages));
      end
      
      numBadBlocks <= tempBadBlocks;

   endrule
   
   // Reg#(Bit#(TLog#(TestNumBlocks))) blockWrCnt <- mkReg(0);
   // Reg#(Bit#(TLog#(PagesPerBlock))) pageWrCnt <- mkReg(0);
   
   Reg#(Bit#(TLog#(TestNumPages)))pageWrCnt <- mkReg(0);
   
   FIFO#(Tuple2#(Bit#(TLog#(NumBlocks)), Bit#(TAdd#(TLog#(TestNumPages),1)))) readReqQ_pre <- mkFIFO();
   FIFOF#(Tuple2#(Bit#(TLog#(NumBlocks)), Bit#(TAdd#(TLog#(TestNumPages),1)))) readReqQ <- mkFIFOF();
   
   RegFile#(TagT, Bit#(TLog#(TestNumPages))) lut_wr <- mkRegFileFull();
   
   Reg#(Bit#(TLog#(NUM_BUSES))) busid_cnt <- mkReg(0);
   Reg#(Bit#(TLog#(ChipsPerBus))) chipid_cnt <- mkReg(0);
   Reg#(Bit#(TLog#(BlocksPerCE))) blockid_cnt <- mkReg(0);
   Reg#(Bit#(TLog#(PagesPerBlock))) pageid_cnt <- mkReg(0);

   
   rule writePagesReq if (writeReqQ.notEmpty());
      let v = writeReqQ.first();
      let blockBase = tpl_1(v);
      // let testPages = tpl_2(v);
      
      if ( pageWrCnt == -1 ) begin
         writeReqQ.deq();
            readReqQ_pre.enq(v);
      end
      pageWrCnt <= pageWrCnt + 1;
      
      // Bit#(TLog#(NumBlocks)) blockAddr = blockBase + extend(blockWrCnt);
      
      Bit#(TLog#(NUM_BUSES)) busid_base = truncate(blockBase);
      Bit#(TLog#(ChipsPerBus)) chipid_base = truncate(blockBase>>fromInteger(lgBusOffset));
      Bit#(TLog#(BlocksPerCE)) blockid_base = truncateLSB(blockBase);
      
      let busid = busid_base + busid_cnt;
      let chipid = chipid_base + chipid_cnt;
      let blockid = blockid_base + blockid_cnt;
      //$display("write Pages Requests blockWrCnt = %d, pageWrCnt = %d, blockBase = %d", blockWrCnt, pageWrCnt, blockBase);
      
      busid_cnt <= busid_cnt + 1;
      if ( busid_cnt == -1 ) begin
         chipid_cnt <= chipid_cnt + 1;
         if ( chipid_cnt == -1 ) begin
            pageid_cnt <= pageid_cnt + 1;
            if ( pageid_cnt == -1 ) begin
               blockid_cnt <= blockid_cnt + 1;
            end
         end
      end
      
      // if (badBlockMap.sub(blockWrCnt)) begin
      let concat1 = {chipid_cnt,busid_cnt};
      let concat2 = {blockid_cnt,concat1};
      if (badBlockMap.sub(truncate(concat2))) begin
         let tag <- tagAlloc.reqTag.response.get();
         flash.sendCmd(FlashCmd{tag: tag, op: WRITE_PAGE, bus: busid, chip: chipid, 
                                block: extend(blockid), page: extend(pageid_cnt)});
         // lut_wr.upd(tag, {pageWrCnt, blockWrCnt});
         lut_wr.upd(tag, pageWrCnt);
      end
      
   endrule
   

   FIFO#(Tuple2#(TagT, Bit#(TLog#(TestNumPages)))) writeDataTagQ <- mkSizedFIFO(128);
   rule writePageDataPre;
      let tag <- flash.writeDataReq();
      let addr = lut_wr.sub(tag);
      writeDataTagQ.enq(tuple2(tag, addr));
   endrule

   
   Reg#(Bit#(TLog#(PageWords))) wordWrCnt <- mkReg(0);
   
   function Bit#(128) composeWord(Bit#(TLog#(TestNumPages)) pageId, Bit#(TLog#(PageWords)) wordId);
      return extend({pageId, wordId});
   endfunction
   
   Reg#(Bit#(TLog#(TestNumPages))) pageWrittenCnt <- mkReg(0);
   
   // Reg#(Bit#(TLog#
   
   Reg#(Bit#(64)) preCycle <- mkRegU();
   Reg#(TagT) prevTag <- mkRegU();
   // Reg#(Bit#(TLog#(PageWords))) prevwordWrCnt <- mkReg(0);
   
   rule writePageData;
      let v = writeDataTagQ.first();
      let testPages = writeDataReqQ.first();
      if ( wordWrCnt + 1 == fromInteger(pageWords) ) begin
         writeDataTagQ.deq();
         wordWrCnt <= 0;
      

         if ( pageWrittenCnt + 1 == truncate(testPages) ) begin
            writeDataReqQ.deq();
            pageWrittenCnt <= 0;
         end
         else begin
            pageWrittenCnt <= pageWrittenCnt + 1;
         end
      end
      else begin
         wordWrCnt <= wordWrCnt + 1;
      end
      prevTag <= tpl_1(v);
      preCycle <= cycles;
      if (preCycle + 1 != cycles) begin
         $display ("Writing Word: cycle_diff = %d, pageWrittenCnt = %d, wordWrCnt = %d, prevTag = %d, currTag = %d", cycles - preCycle, pageWrittenCnt, wordWrCnt, prevTag, tpl_1(v));
      end
      flash.writeWord(tuple2(composeWord(tpl_2(v), wordWrCnt), tpl_1(v)));
   endrule
   
   Reg#(Bit#(TLog#(TestNumPages))) pageAcks <- mkReg(0);
   
   FIFOF#(Bit#(TAdd#(TLog#(FlashTestTypes::TestNumPages), 1))) testPages_preRdData <- mkFIFOF();
   
   FIFO#(WriteRetT) writeDoneQ <- mkFIFO();
   
   Reg#(Bit#(64)) startCycle_rd <- mkRegU();
   rule writePageAck;
      let testPages = writeAckReqQ.first();
      let v <- flash.ackStatus();
      let tag = tpl_1(v);
      let status = tpl_2(v);
      // staticAssert( status == WRITE_DONE, "Wrong writePage Ack");
      tagAlloc.retTag.put(tag);
      if ( pageAcks + 1 == truncate(testPages) ) begin
         writeAckReqQ.deq();
         tagAlloc.reqTag.request.put(extend(testPages));
         writeDoneQ.enq(WriteRetT{cycles: cycles - startCycle_wr, written_pages: extend(pageAcks) + 1});
         startCycle_rd <= cycles;
         let v_ <- toGet(readReqQ_pre).get();
         readReqQ.enq(v_);
         testPages_preRdData.enq(testPages);
         pageAcks <= 0;
      end
      else begin
         pageAcks <= pageAcks + 1;
      end
   endrule
   
   Reg#(Bit#(TLog#(TestNumBlocks))) blockRdCnt <- mkReg(0);
   // Reg#(Bit#(TLog#(PagesPerBlock))) pageRdCnt <- mkReg(0);
   Reg#(Bit#(TLog#(TestNumPages))) pageRdCnt <- mkReg(0);
   
   Reg#(Bit#(TLog#(NUM_BUSES))) busid_cnt_Rd <- mkReg(0);
   Reg#(Bit#(TLog#(ChipsPerBus))) chipid_cnt_Rd <- mkReg(0);
   Reg#(Bit#(TLog#(BlocksPerCE))) blockid_cnt_Rd <- mkReg(0);
   Reg#(Bit#(TLog#(PagesPerBlock))) pageid_cnt_Rd <- mkReg(0);


   
   RegFile#(TagT, Bit#(TLog#(TestNumPages))) lut_rd <- mkRegFileFull();
   
   rule readPageReq if (readReqQ.notEmpty);
      let v = readReqQ.first();
      let blockBase = tpl_1(v);
      let testPages = tpl_2(v);
      
      if ( pageRdCnt == -1 ) begin
         readReqQ.deq();
      end
      pageRdCnt <= pageRdCnt + 1;
      
      
      Bit#(TLog#(NUM_BUSES)) busid_base = truncate(blockBase);
      Bit#(TLog#(ChipsPerBus)) chipid_base = truncate(blockBase>>fromInteger(lgBusOffset));
      Bit#(TLog#(BlocksPerCE)) blockid_base = truncateLSB(blockBase);
      
      let busid = busid_base + busid_cnt_Rd;
      let chipid = chipid_base + chipid_cnt_Rd;
      let blockid = blockid_base + blockid_cnt_Rd;
      //$display("write Pages Requests blockWrCnt = %d, pageWrCnt = %d, blockBase = %d", blockWrCnt, pageWrCnt, blockBase);
      
      busid_cnt_Rd <= busid_cnt_Rd + 1;
      if ( busid_cnt_Rd == -1 ) begin
         chipid_cnt_Rd <= chipid_cnt_Rd + 1;
         if ( chipid_cnt_Rd == -1 ) begin
            pageid_cnt_Rd <= pageid_cnt_Rd + 1;
            if ( pageid_cnt_Rd == -1 ) begin
               blockid_cnt_Rd <= blockid_cnt_Rd + 1;
            end
         end
      end
      
      
      // if (badBlockMap.sub(blockRdCnt)) begin
      let concat1 = {chipid_cnt_Rd,busid_cnt_Rd};
      let concat2 = {blockid_cnt_Rd,concat1};
      if (badBlockMap.sub(truncate(concat2))) begin
         let tag <- tagAlloc.reqTag.response.get();
         flash.sendCmd(FlashCmd{tag: tag, op: READ_PAGE, bus: busid, chip: chipid, 
                                block: extend(blockid), page: extend(pageid_cnt_Rd)});
         // lut_rd.upd(tag, {pageRdCnt, blockRdCnt});
         lut_rd.upd(tag, pageRdCnt);
      end
   endrule
   
   
   Reg#(Bit#(TLog#(TestNumPages))) wrongPageCnt <- mkReg(0);
   
   Vector#(128, FIFO#(Tuple3#(Bit#(128), Bit#(TLog#(TestNumPages)), Bool))) readDataQs <- replicateM(mkFIFO());
   Vector#(128, Reg#(Bit#(TestNumPages))) wrongPageCnts <- replicateM(mkReg(0));
   
   Reg#(Bit#(TLog#(PageWords))) rdCnts_pre <- mkReg(0);   
   Reg#(Bit#(TLog#(TestNumBlocks))) blkCnt_pre <- mkReg(0);
   
   Vector#(128, Reg#(Bit#(TLog#(PageWords)))) pageWordCnts <- replicateM(mkReg(0));
   Reg#(Bit#(TLog#(PageWords))) wordCnt <- mkReg(0);
   Reg#(Bit#(TLog#(TestNumPages))) totalPageCnt <- mkReg(0);
   
   FIFO#(Tuple4#(Bit#(128), TagT, Bit#(TLog#(TestNumPages)), Bool)) checkRdDataQ <- mkFIFO();
   rule preRdData;
      let testPages = testPages_preRdData.first();
      let v <- flash.readWord();
      let data = tpl_1(v);
      let tag = tpl_2(v);
      // Bool lastPageWord = False;
      Bool lastTestWord = False;
      
      if ( wordCnt + 1 == fromInteger(pageWords)) begin
         wordCnt <= 0;
         if ( totalPageCnt + 1 == truncate(testPages)) begin
            lastTestWord = True;
            $display("preRdData totalPageCnt = %d, wordCnt = %d, lastTestWord = %d", totalPageCnt, wordCnt, lastTestWord);
            totalPageCnt <= 0;
            testPages_preRdData.deq();
         end
         else begin
            totalPageCnt <= totalPageCnt + 1;
         end
      end
      else begin
         wordCnt <= wordCnt + 1;
      end
            
      
      if ( pageWordCnts[tag] + 1 == fromInteger(pageWords)) begin
         pageWordCnts[tag] <= 0;
         tagAlloc.retTag.put(tag);
         // lastPageWord = True;
      end
      else begin
         pageWordCnts[tag] <= pageWordCnts[tag] + 1;
      end
      
      let pageId = lut_rd.sub(tag);
      checkRdDataQ.enq(tuple4(data, tag, pageId, lastTestWord));
   endrule


   Vector#(128, Reg#(Bit#(TLog#(PageWords)))) pageWordCkCnts <- replicateM(mkReg(0));   
   
   Vector#(128, Reg#(Bool)) wrongPage <- replicateM(mkReg(False));
   Reg#(Bit#(TLog#(TMul#(PageWords, TestNumPages)))) totalWrongWords <- mkReg(0);
   
   Reg#(Bit#(TAdd#(TLog#(TestNumPages),1))) totalWrongPages <- mkReg(0);
   
   FIFOF#(Bit#(0)) rdDoneQ <- mkFIFOF();
   rule checkRdData;
      let v <- toGet(checkRdDataQ).get();
      let data = tpl_1(v);
      let tag = tpl_2(v);
      let pageId = tpl_3(v);
      let lastTestWord = tpl_4(v);
      
      let temp_wrongPg = wrongPage[tag];
      
      let temp_wrongwords = totalWrongWords;
      
      if ( data != composeWord(pageId, pageWordCkCnts[tag])) begin
         temp_wrongPg = True;
         totalWrongWords <= totalWrongWords + 1;
         $display("!!!!Wrong Word");
         $display("Check Read Data pageId = %h, pageWordCkCnts[%d] = %h, data = %h", pageId, tag, pageWordCkCnts[tag], data);         
      end
      

      
      if ( pageWordCkCnts[tag] + 1 == fromInteger(pageWords)) begin
         pageWordCkCnts[tag] <= 0;
         wrongPage[tag] <= False;
         if ( temp_wrongPg ) begin
            totalWrongPages <= totalWrongPages + 1;
         end
      end
      else begin
         pageWordCkCnts[tag] <= pageWordCkCnts[tag] + 1;
         wrongPage[tag] <= temp_wrongPg;
      end
      
      if (lastTestWord) begin
         $display("checkRdData lastTestWord");
         rdDoneQ.enq(?);
      end
   endrule
   
   FIFO#(ReadRetT) readDoneQ <- mkFIFO();
   rule sendRdDone if (rdDoneQ.notEmpty);
      rdDoneQ.deq();
      //(Bit#(64) cycles, Bit#(32) read_pages, Bit#(32) wrong_words, Bit#(32) wrong_pages);
      $display("!!!!sendRdDone");
      readDoneQ.enq(ReadRetT{cycles: cycles - startCycle_rd, read_pages: fromInteger(testNumPages), 
                             wrong_words:extend(totalWrongWords), wrong_pages:extend(totalWrongPages)});
      totalWrongWords<=0;
      totalWrongPages<=0;
      // cycles <= 0;
   endrule
   
   method Action start(Bit#(64) randSeed);
      tagAlloc.reqTag.request.put(fromInteger(testNumBlocks));
      eraseReqQ.enq(truncate(randSeed));
      eraseRespQ.enq(truncate(randSeed));
      cycles <= 0;
      numBadBlocks<= 0;      
   endmethod
   method ActionValue#(EraseRetT) eraseDone;
      let v <- toGet(eraseDoneQ).get();
      return v;
   endmethod
   method ActionValue#(WriteRetT) writeDone;
      let v <- toGet(writeDoneQ).get();
      return v;
   endmethod
   method ActionValue#(ReadRetT) readDone;
      let v <- toGet(readDoneQ).get();
      return v;
   endmethod
endmodule      

