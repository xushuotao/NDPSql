import NDPCommon::*;
import Pipe::*;
import FIFOF::*;
import GetPut::*;
import ClientServer::*;
import ClientServerHelper::*;
import FlashCtrlIfc::*;
import RowMask::*;
import FIFO::*;
import ControllerTypes::*;
import Vector::*;

typedef struct{
   Bit#(64) firstRow;
   Bit#(64) lastRow;
   Bool last;
   } RowBatchRequest deriving (Bits, Eq, FShow);

interface FirstColReader;
   // interactions with flash and rowMasks
   interface Client#(DualFlashAddr, Bit#(256)) flashRdClient;
   
   interface Client#(Bit#(9), void) reserveRowVecs;
   
   // outPipe to next Accel
   interface NDPStreamOut streamOut;
   
   // set up parameter
   interface NDPConfigure configure;
   
   method Action start();
endinterface



(* synthesize *)
module mkFirstColReader(FirstColReader);
   
   Reg#(Bool) colBytesReady <- mkReg(False);
   Reg#(Bool) paramReady <- mkReg(False);
   
   
   Bool ready = colBytesReady && paramReady;

   

   // fifos for interactions with flash
   FIFOF#(DualFlashAddr) flashReadReqQ <- mkFIFOF;
   FIFOF#(Bit#(256)) flashRespQ <- mkFIFOF;
   
   // flash read request related
   Reg#(Bit#(64)) basePageReg <- mkRegU();
   Reg#(Bit#(64)) pageReqCnt <- mkReg(maxBound);
   
   Reg#(Bit#(64)) endPageID <- mkReg(0);
   
   
   // max = 8192 (2^13)
   Reg#(Bit#(14)) rowsPerPage <- mkRegU();
   
   // max = 13 or (2^4)
   Reg#(Bit#(4)) lgRowsPerPage <- mkRegU();
   
   // max 5 or 2^3
   Reg#(Bit#(3)) lgRowsPerBeat <- mkRegU();
   
   Reg#(Bool) passThru <- mkRegU;

   
   Reg#(Bit#(5)) colBytesReg <- mkRegU(); // max is 16 when colwidth == 16byte
   Reg#(Bit#(4)) modMask_WPRV <- mkRegU(); // max is 16 when colwidth == 16byte


   Reg#(Bit#(64)) numRowsReg <- mkRegU();
   
   FIFO#(Bit#(9)) reserveReqQ <- mkFIFO;
   FIFO#(void) reserveRespQ <- mkFIFO;
   
   
   FIFO#(DualFlashAddr) addrQ <- mkSizedFIFO(8);
   
   Reg#(Bit#(64)) rowVecCnt <- mkReg(maxBound);
   Reg#(Bit#(64)) totalrowVec <- mkReg(0);
   
   
   rule genRowVecReserve if (ready && !passThru && pageReqCnt <= endPageID);
      $display("(%m) genPageReq colBytes = %d, numRows = %d, pageReqCnt = %d, endPageID = %d, rowVecCnt = %d, totalrowVec = %d", colBytesReg, numRowsReg, pageReqCnt, endPageID, rowVecCnt, totalrowVec);
      pageReqCnt <= pageReqCnt + 1;
      addrQ.enq(toDualFlashAddr(pageReqCnt + basePageReg));
      reserveReqQ.enq(truncate(min(totalrowVec-rowVecCnt, extend(rowsPerPage>>5))));
      rowVecCnt <= rowVecCnt + extend(rowsPerPage>>5);
   endrule
   
   rule issueReq;
      reserveRespQ.deq();
      let addr <- toGet(addrQ).get();
      flashReadReqQ.enq(addr);
   endrule

   
   // generate row mask
   FIFOF#(RowMask) allRowMaskQ <- mkFIFOF;
   Reg#(Bit#(32)) lastMask <- mkRegU;

   // doFlashResp related
   Reg#(Bit#(TLog#(TDiv#(PageWords, 2)))) pageBeatCnt <- mkReg(0);
   Reg#(Bit#(64)) pageRespCnt <- mkReg(maxBound);
   Reg#(Bit#(64)) totalFlashBeat <- mkReg(0);
   Reg#(Bit#(64)) flashBeatCnt <- mkReg(maxBound);

   FIFOF#(Bit#(256)) streamOutQ <- mkFIFOF;
   
   // rule displayFlashResp (flashRespQ.notEmpty );//&& ready && !passThru );&& pageRespCnt <= endPageID);
   //    $display("data ready from flash, passThru = %d, pageRespCnt = %d, endPageID = %d, ready = %d", passThru, pageRespCnt, endPageID, ready);
   // endrule
   
   rule doFlashResp if (ready && !passThru && pageRespCnt <= endPageID);
      let flashWord <- toGet(flashRespQ).get;
      
      Vector#(8, Bit#(32)) word_int = unpack(flashWord);
      $display("(%m) flashWord ", fshow(word_int));
      
      if ( pageBeatCnt == fromInteger(pageWords/2-1) ) begin
         pageBeatCnt <= 0;
         pageRespCnt <= pageRespCnt + 1;
      end
      else begin
         pageBeatCnt <= pageBeatCnt + 1;
      end
      
      Bool isLastPage = (pageRespCnt == endPageID);
      
      $display("(%m) doFlashResp: pageCnt = %d, pageBeatCnt = %d, flashBeatCnt = %d, totalFlashbeat = %d, endPageID = %d, modMask_WPRV = %b", pageRespCnt, pageBeatCnt, flashBeatCnt, totalFlashBeat, endPageID, modMask_WPRV);
      
      if ( pageBeatCnt < fromInteger(8192/32) ) begin // useful 8k data
         
         
         flashBeatCnt <= flashBeatCnt + 1;
         
         Bool discardData = (flashBeatCnt >= totalFlashBeat);
         
         if ( (pageBeatCnt & zeroExtend(modMask_WPRV)) == 0) begin
            Bit#(32) rowMask = maxBound;
        
            Bool isLast = False;
            
            $display("(%m) doFlashResp producing mask");
            if ( flashBeatCnt + extend(colBytesReg) >= extend(totalFlashBeat) ) begin
               rowMask = lastMask;
               isLast = True;
            end
            
            if (!discardData) begin
               allRowMaskQ.enq(RowMask{mask:rowMask,
                                       last: isLast});
            end
         end
         
         if (!discardData) streamOutQ.enq(flashWord);
      end
   endrule
   
   FIFO#(Tuple2#(Bool, RowMask)) tempMaskQ <- mkSizedFIFO(8);
   
   rule doRowVecReserve if (ready && passThru && rowVecCnt < totalrowVec);
      Bool needReserve = False;
      
      rowVecCnt <= rowVecCnt + 1;
      if ( (rowVecCnt & fromInteger(8192/32 - 1)) == 0 ) begin
         reserveReqQ.enq(truncate(min(fromInteger(8192/32), totalrowVec - rowVecCnt)));
         needReserve = True;
      end
      
      if ( rowVecCnt + 1 == totalrowVec ) begin
         tempMaskQ.enq(tuple2(needReserve, RowMask{mask: lastMask,
                                                   last: True}));
      end
      else begin
         tempMaskQ.enq(tuple2(needReserve, RowMask{mask: -1,
                                                   last: False}));

      end
   endrule

   
   rule doMaskGen;// if (ready && passThru && rowVecCnt < totalRowVec);
      let {needResp, d} <- toGet(tempMaskQ).get();
      if (needResp) reserveRespQ.deq;
      allRowMaskQ.enq(d);
   endrule
   
      
   rule finishColRead if (ready &&
                          (!passThru && (pageRespCnt == endPageID + 1 && pageReqCnt == endPageID + 1) ||
                           (passThru && rowVecCnt == totalrowVec)));
      $display("(%m) finishColRead, passThru = %d, (pageReqCnt, pageRespCnt, endPageID)=(%d,%d,%d), (rowVecCnt, totalrowVec)=(%d, %d)", passThru, pageReqCnt, pageRespCnt, endPageID, rowVecCnt, totalrowVec);
      colBytesReady <= False;
      paramReady <= False;
   endrule
   
   Reg#(Bit#(3)) lgBeatsPerRowVec <- mkRegU;

   // read interactions with flash
   // inPipes
   interface Client flashRdClient = toClient(flashReadReqQ, flashRespQ);
   
   interface Client reserveRowVecs = toClient(reserveReqQ, reserveRespQ);
      
   // outPipe
   interface NDPStreamOut streamOut = toNDPStreamOut(streamOutQ, allRowMaskQ);
   interface NDPConfigure configure;
      method Action setColBytes(Bit#(5) colBytes) if (!colBytesReady);
         Bit#(4) lgRPP = case (colBytes)
                            1: 13;
                            2: 12;
                            4: 11;
                            8: 10;
                            16: 9;
                         endcase;
         rowsPerPage <= 1 << lgRPP;
         lgRowsPerPage <= lgRPP;
            
   
         // this happens to be equal 32 rows in super row.
         // if colwidth == 1-byte, words(32-byte) per RowV = 1
         colBytesReg <= colBytes;
   
         // words per row vector
         modMask_WPRV <= case (colBytes)
                            1: 'b0;  // 1
                            2: 'b1;  // 2
                            4: 'b11; // 4
                            8: 'b111; // 8
                            16:'b1111; // 16
                         endcase;

         lgRowsPerBeat <= case (colBytes)
                             1: 5;
                             2: 4;
                             4: 3;
                             8: 2;
                             16: 1;
                          endcase;
   
         lgBeatsPerRowVec <= case (colBytes)
                                1: 0;
                                2: 1;
                                4: 2;
                                8: 3;
                                16: 4;
                             endcase;
   
         colBytesReady <= True;
      endmethod

      method Action setParameters(Vector#(4, Bit#(128)) paras) if ( colBytesReady && !paramReady );
         $display("(%m) setParameters: basePage = %d, numRows = %d,  passThru = %d", paras[0], paras[1], paras[2][0]);
         basePageReg <= truncate(paras[0]);
   
         // max number of Rows
         Bit#(64) numRows = truncate(paras[1]);
         numRowsReg <= numRows;
   
         Bit#(64) endRow = numRows - 1;
      
         Bit#(64) totalRowVecs = (numRows + 31) >> 5;
         
         totalrowVec <= totalRowVecs;
         
         $display("(%m) setParameters: totalRowVecs = %d, totalFlashBeats = %d", totalRowVecs, totalRowVecs << lgBeatsPerRowVec);
         totalFlashBeat <= totalRowVecs << lgBeatsPerRowVec;
   
         // Bit#(64)
         endPageID <= endRow >> lgRowsPerPage;
         
         Bit#(5) rowVRmd_last = truncate(numRows - 1);
   
         // Bit#(32)
         lastMask <= truncate((33'b10<<rowVRmd_last) - 1);
   
         paramReady <= True;
   
         passThru <= unpack(paras[2][0]);

      endmethod
   endinterface
   
   method Action start() if (ready);
      // ready <= True;
      pageReqCnt <= 0;
      pageRespCnt <= 0;
      flashBeatCnt <= 0;
      rowVecCnt <= 0;
      // beatCnt <= 0;
   endmethod
   
endmodule
