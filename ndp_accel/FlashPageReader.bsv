import FlashCtrlIfc::*;
import ControllerTypes::*;
import DualFlashPageBuffer::*;
import ClientServer::*;
import ClientServerHelper::*;
import FIFO::*;
import FIFOF::*;
import BRAMFIFO::*;
import DualFlashPageBuffer::*;
import GetPut::*;
import ISSPTypes::*;
import NDPCommon::*;

typedef Bit#(TLog#(PageBufSz)) BufTagT;

Bool debug = False;

interface FlashPageReaderIO;
   interface Server#(DualFlashAddr, Bit#(256)) readServer;
   interface PageBufferClient#(PageBufSz) pageBufferClient;
endinterface

(* synthesize *)
module mkFlashPageReaderIO(FlashPageReaderIO);
   FIFO#(DualFlashAddr) addrQ <- mkSizedBRAMFIFO(valueOf(PageBufSz));
   FIFO#(BufTagT) tagRespQ <- mkFIFO;//SizedFIFO(valueOf(PageBufSz));
   FIFOF#(Bit#(256)) dataRespQ <- mkFIFOF;
   FIFO#(BufTagT) tagReleaseQ <- mkFIFO;
   FIFO#(BufTagT) tagDoneQ <- mkFIFO;//SizedFIFO(valueOf(PageBufSz));
   // 256 beats per Page
   Reg#(Bit#(8)) beatCnt <- mkReg(0);
   Reg#(Bit#(8)) beatCnt_resp <- mkReg(0);
   
   // rule displayBackPressure if (! dataRespQ.notFull);
   //    $display("(%m) warning :: dataResqQ is full...");
   // endrule
                               
   
   interface Server readServer;// = toServer(addrQ, dataRespQ);
      interface request = toPut(addrQ);
      interface response = toGet(dataRespQ);
   endinterface
   interface PageBufferClient pageBufferClient;
      interface bufReserve = toClient(addrQ, tagRespQ);
   
      interface Client circularRead;
         interface Get request;
            method ActionValue#(BufTagT) get();
               let tag = tagRespQ.first;
               if (debug) $display("(%m) @%t circularRead get, tag = %d, beatCnt = %d", $time, tag, beatCnt);
               if ( beatCnt == maxBound) begin
                  tagRespQ.deq;
                  tagReleaseQ.enq(tag);
                  // tagDoneQ.enq(tag);
               end
               beatCnt <= beatCnt + 1;
               return tag;
            endmethod
         endinterface
         interface Put response;// = toPut(dataRespQ);
            method Action put(Bit#(256) data);
               dataRespQ.enq(data);
               beatCnt_resp <= beatCnt_resp + 1;
               if (debug) $display("(%m) @%t circularRead response, beatCnt = %d", $time, beatCnt_resp);
               if ( beatCnt_resp == maxBound ) begin
                  let tag <- toGet(tagReleaseQ).get;
                  tagDoneQ.enq(tag);
               end
            endmethod
         endinterface
      endinterface
      interface Get doneBuf = toGet(tagDoneQ);
   endinterface
endmodule
