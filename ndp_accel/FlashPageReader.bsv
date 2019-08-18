import FlashCtrlIfc::*;
import ControllerTypes::*;
import DualFlashPageBuffer::*;
import ClientServer::*;
import ClientServerHelper::*;
import FIFO::*;
import DualFlashPageBuffer::*;
import GetPut::*;
import NDPCommon::*;

typedef Bit#(TLog#(PageBufSz)) BufTagT;

interface FlashPageReaderIO;
   interface Server#(DualFlashAddr, Bit#(256)) readServer;
   interface PageBufferClient#(PageBufSz) pageBufferClient;
endinterface

(* synthesize *)
module mkFlashPageReaderIO(FlashPageReaderIO);
   FIFO#(DualFlashAddr) addrQ <- mkFIFO;
   FIFO#(BufTagT) tagRespQ <- mkSizedFIFO(valueOf(PageBufSz));
   FIFO#(Bit#(256)) dataRespQ <- mkFIFO;
   FIFO#(BufTagT) tagDoneQ <- mkFIFO;
   // 256 beats per Page
   Reg#(Bit#(8)) beatCnt <- mkReg(0);
   interface Server readServer = toServer(addrQ, dataRespQ);
   interface PageBufferClient pageBufferClient;
      interface bufReserve = toClient(addrQ, tagRespQ);
   
      interface Client circularRead;
         interface Get request;
            method ActionValue#(BufTagT) get();
               let tag = tagRespQ.first;
               $display("(%m) circularRead get, tag = %d, beatCnt = %d", tag, beatCnt);
               if ( beatCnt == maxBound) begin
                  tagRespQ.deq;
                  tagDoneQ.enq(tag);
               end
               beatCnt <= beatCnt + 1;
               return tag;
            endmethod
         endinterface
         interface Put response = toPut(dataRespQ);
      endinterface
      interface Get doneBuf = toGet(tagDoneQ);
   endinterface
endmodule
