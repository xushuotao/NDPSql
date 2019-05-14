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

interface ColReader;
   // interactions with flash and rowMasks
   interface Client#(DualFlashAddr, Bit#(256)) flashRdClient;
   interface Client#(SuperRowId, SuperRowMask) rowMaskReadPort;
   
      
   // inPipe from previous Accel
   interface PipeIn#(RowBatchRequest) rowReq;
   
   // outPipe to next Accel
   interface NDPStreamOut streamOut;
   
   // set up parameter
   interface NDPConfigure configure;
   // method Action setup(Bit#(64) basePage, Bit#(5) colBytes, Bit#(32) rowNum);
endinterface



(* synthesize *)
module mkColReader(ColReader);
   
   Reg#(Bool) ready <- mkReg(False);
   Reg#(Bool) isMasked <- mkReg(False);
   
   FIFOF#(RowBatchRequest) rowReqQ <- mkFIFOF;


   // fifos for interactions with flash
   FIFO#(DualFlashAddr) flashReadReqQ <- mkFIFO;
   FIFO#(Bit#(256)) flashRespQ <- mkFIFO;
   

   
   Reg#(Bit#(64)) rowCnt <- mkReg(0);
   
   Reg#(Bit#(64)) basePageReg <- mkRegU();
   Reg#(Bit#(64)) pageCnt <- mkReg(0);
   
   
   // max = 8192 (2^13)
   Reg#(Bit#(14)) rowsPerPage <- mkRegU();
   
   // max = 13 or (2^4)
   Reg#(Bit#(4)) lgRowsPerPage <- mkRegU();
   
   // max 5 or 2^3
   Reg#(Bit#(3)) lgRowsPerBeat <- mkRegU();
   

   
   Reg#(Bit#(5)) colBytesReg <- mkRegU(); // max is 16 when colwidth == 16byte
   Reg#(Bit#(4)) modMask_WPSR <- mkRegU(); // max is 16 when colwidth == 16byte


   Reg#(Bit#(64)) numRowsReg <- mkRegU();
   

   // this might be problematic for synthesizing
   
   // firstBeat; firstMask; lastBeat; lastMask; totalPage
   FIFO#(Tuple6#(Bit#(8), Bit#(32), Bit#(8), Bit#(32), Bit#(64), Bool)) maskInfoQ <- mkSizedFIFO(128);
   
   rule genPageReq if (ready);
      let req = rowReqQ.first();
      let startRow = req.firstRow;
      let endRow = req.lastRow;
      
      endRow = (endRow > numRowsReg-1)? numRowsReg-1 : endRow;

      Bit#(64) startPage = startRow >> lgRowsPerPage;
      Bit#(64) endPage = endRow >> lgRowsPerPage;

      $display("(%m) genPageReq startRow = %d, endRow = %d", startRow, endRow);
      $display("(%m) genPageReq basePage = %d, pageCnt = %d, startPage = %d, endPage = %d", basePageReg, pageCnt, startPage, endPage);
      
      if ( pageCnt == 0 ) begin
         Bit#(8) firstBeat = truncate(startRow >> lgRowsPerBeat); // 256 beats per page;
         
         Bit#(5) superRowRmd_first = truncate(startRow);
         Bit#(32) firstMask = reverseBits(reverseBits(truncateLSB(33'b1<<superRowRmd_first))-1);
         
         Bit#(8) lastBeat = truncate(endRow >> lgRowsPerBeat); // 256 beats per page;
         
         Bit#(5) superRowRmd_last = truncate(endRow);         
         Bit#(32) lastMask = truncate((33'b10<<superRowRmd_last) - 1);
         maskInfoQ.enq(tuple6(firstBeat, firstMask, lastBeat, lastMask, endPage - startPage + 1, req.last));
         
         $display("(%m) enqueuing maskInfo: firstBeat, firstMas, lastBeat, lastMask, totalPages (%d, %b, %d, %b, %d)", firstBeat, firstMask, lastBeat, lastMask, endPage - startPage + 1);
         
      end
      
      
      if ( startPage + pageCnt == endPage ) begin
         rowReqQ.deq;
         pageCnt <= 0;
      end
      else begin
         pageCnt <= pageCnt + 1;
      end
      

      
      flashReadReqQ.enq(toDualFlashAddr(pageCnt + basePageReg+ startPage));
      // rowBaseQ.enq(pageCnt << lgRowsPerPage);
   endrule


   Reg#(SuperRowId) superRowId <- mkReg(0);
   Reg#(Bit#(TLog#(TDiv#(PageWords, 2)))) pageBeatCnt <- mkReg(0);
   
   // fifos for interactions with row mask array
   FIFOF#(SuperRowId) rowMaskReadQ <- mkFIFOF;
   FIFOF#(SuperRowMask) rowMaskRespQ <- mkFIFOF;
   
   // artificially generate row mask
   FIFOF#(SuperRowMask) allRowMaskQ <- mkFIFOF;

   Reg#(Bit#(32)) lastRowMask <- mkRegU();
   
   FIFOF#(RowMask) rowMaskOutQ <- mkFIFOF;
   
   // fifos for data output,
   // 8 cycles to hide the latency of contending read port
   FIFOF#(Bit#(256)) outWordQ <- mkSizedFIFOF(8);
   
   
   Reg#(Bit#(64)) pageCnt_resp <- mkReg(0);
   
   FIFO#(Bool) isLastMaskQ <- mkSizedFIFO(32);
   
   rule sendMaskReq;
      // let baseRow = rowBaseQ;
      
      let {firstBeat, firstMask, lastBeat, lastMask, totalPages, last} = maskInfoQ.first();
      
      if ( pageBeatCnt == fromInteger(pageWords/2-1) ) begin
         pageBeatCnt <= 0;
         
         if ( pageCnt + 1 == totalPages ) begin
            maskInfoQ.deq;
            pageCnt_resp <= 0;
         end
         else begin
            pageCnt_resp <= pageCnt_resp + 1;
         end
         
      end
      else begin
         pageBeatCnt <= pageBeatCnt + 1;
      end
      
      
      let flashWord <- toGet(flashRespQ).get;
      
      $display("(%m) flashWordResp: pageCnt = %d, first_beat = %d, last_beat = %d, total_pages = %d", pageCnt_resp, firstBeat, lastBeat, totalPages);
      
      if ( pageBeatCnt < fromInteger(8192/32) ) begin // useful 8k data
         
         if ( (pageBeatCnt & zeroExtend(modMask_WPSR)) == 0) begin
            
            Bool isLast = last && (pageCnt_resp == totalPages - 1 && pageBeatCnt + zeroExtend(colBytesReg) >= fromInteger(8192/32));
            
            isLastMaskQ.enq(isLast);
               
            // if masked also send mask read request
            if ( isMasked ) begin
               superRowId <= superRowId + 1;
               rowMaskReadQ.enq(superRowId);
            end
            else begin
               if ( pageCnt_resp == 0 ) begin
                  if ( pageBeatCnt > zeroExtend(firstBeat) ) begin 
                     allRowMaskQ.enq(-1);
                  end
                  else if ( pageBeatCnt == zeroExtend(firstBeat)) begin
                     allRowMaskQ.enq(firstMask);
                  end
                  else begin
                     allRowMaskQ.enq(0);
                  end
               end
               else if ( pageCnt_resp < totalPages -1 ) begin
                  allRowMaskQ.enq(-1);
               end
               else begin
                  if ( pageBeatCnt < zeroExtend(lastBeat) ) begin
                     allRowMaskQ.enq(-1);
                  end
                  else if ( pageBeatCnt == zeroExtend(lastBeat)) begin
                     allRowMaskQ.enq(lastMask);
                  end
                  else begin
                     allRowMaskQ.enq(0);
                  end
               end
            end
         end
        
         
         outWordQ.enq(flashWord);
      end
   endrule
   
   
   rule switchMaskResp;
      let last <- toGet(isLastMaskQ).get();
      SuperRowMask mask = ?;
      if ( isMasked ) begin
         mask <- toGet(rowMaskRespQ).get();
      end
      else begin
         mask <- toGet(allRowMaskQ).get();
      end
      
      rowMaskOutQ.enq(RowMask{mask:mask,
                              last:last});
   endrule
   
   


   // start and end rows to Read
   interface PipeIn rowReq = toPipeIn(rowReqQ);
   
   // read interactions with flash
   // inPipes
   interface Client flashRdClient = toClient(flashReadReqQ, flashRespQ);
   interface Client rowMaskReadPort = toClient(rowMaskReadQ, rowMaskRespQ);
      
   // outPipe
   interface NDPStreamOut streamOut = toNDPStreamOut(outWordQ, rowMaskOutQ);
   interface NDPConfigure configure;
      method Action setColBytes(Bit#(5) colBytes);
         Bit#(4) lgRPP = case (colBytes)
                            1: 13;
                            2: 12;
                            4: 10;
                            8: 9;
                            16: 8;
                         endcase;
         rowsPerPage <= 1 << lgRPP;
         lgRowsPerPage <= lgRPP;
            
            
            
   
         // this happens to be equal 32 rows in super row.
         // if colwidth == 1-byte, words(32-byte) per superrow = 1
         colBytesReg <= colBytes;
   
         modMask_WPSR <= case (colBytes)
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

      endmethod

      method Action setParameters(Vector#(4, Bit#(128)) paras);
         basePageReg <= truncate(paras[0]);
   
         // max number of Rows
         Bit#(64) numRows = truncate(paras[1]);
         numRowsReg <= numRows;
   
         Bit#(5) superRowRemainder = truncate(numRows);
   
         Bit#(32) lastRowMask = (1 << superRowRemainder) - 1 ;

         isMasked <= unpack(truncate(paras[2]));
         ready <= True;
      endmethod
   endinterface

endmodule
