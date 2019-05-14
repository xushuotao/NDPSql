import Vector::*;
import FIFO::*;
import FIFOF::*;
import BRAMFIFO::*;
import ClientServer::*;
import ClientServerHelper::*;
import GetPut::*;

import FlashCtrlIfc::*;
import ControllerTypes::*;


interface FlashReadMultiplex#(numeric type nSlaves);
   // in-order request/response per channel
   interface Vector#(nSlaves, Server#(DualFlashAddr, Bit#(256))) flashReadServers;
   
   // flash client flash controllers
   interface Vector#(2, FlashCtrlClient) flashClient;
endinterface


typedef TMul#(128, 1024) MaxInflightRows;

module mkFlashReadMultiplex(FlashReadMultiplex#(nSlaves));

   Vector#(2, FIFO#(FlashCmd)) flashReqQs <- replicateM(mkFIFO);
   
   // bus Inorder buffers
   Vector#(2, Vector#(8, FIFOF#(Bit#(256)))) busPageBufs <- replicateM(replicateM(mkSizedBRAMFIFOF(pageWords/2)));

   
   Vector#(nSlaves, FIFO#(Bit#(256))) pageRespQs <- replicateM(mkFIFO);
   
   
   FIFO#(Tuple3#(Bit#(1), Bit#(3), Bit#(TLog#(nSlaves)))) outstandingReqQ <- mkSizedFIFO(128);
      
      
   Reg#(Bit#(TLog#(TDiv#(PageWords,2)))) beatCnt <- mkReg(0);   
   Reg#(Tuple3#(Bit#(1), Bit#(3), Bit#(TLog#(nSlaves)))) readMetaReg <- mkRegU();
   rule deqResp;
      let {card, bus, channel} = readMetaReg;
      if (beatCnt == 0 ) begin
         let v <- toGet(outstandingReqQ).get;
         {card, bus, channel} = v;
         readMetaReg <= v;
      end
      let d <- toGet(busPageBufs[card][bus]).get;
      if ( beatCnt < fromInteger(pageWords/2 -1) )
         beatCnt <= beatCnt + 1;
      else 
         beatCnt <= 0;
      pageRespQs[channel].enq(d);
      $display("flashReadMux deqResp beatCnt = %d, card = %d, bus = %d, channel = %d", beatCnt, card, bus, channel);
   endrule
      
      

   function Server#(DualFlashAddr, Bit#(256)) genFlashReadServers(Integer i);
      return (interface Server#(DualFlashAddr, Bit#(256));
                 interface Put request;
                    method Action put(DualFlashAddr req);
                       flashReqQs[req.card].enq(FlashCmd{tag: zeroExtend(req.bus),
                                                         op: READ_PAGE,
                                                         bus: req.bus,
                                                         chip: req.chip,
                                                         block: extend(req.block),
                                                         page: req.page});
                       outstandingReqQ.enq(tuple3(req.card, req.bus, fromInteger(i)));
                    endmethod
                 endinterface
         
                 interface Get response = toGet(pageRespQs[i]);
              endinterface);
   endfunction
   
   
   Vector#(2, Vector#(8, Reg#(Bit#(1)))) gearSelector <- replicateM(replicateM(mkReg(0)));
   Vector#(2, Vector#(8, Reg#(Bit#(128)))) wordBufs <- replicateM(replicateM(mkReg(0)));
   
   function FlashCtrlClient genFlashCtrlClient(Integer i);
      return (interface FlashCtrlClient;
                 method ActionValue#(FlashCmd) sendCmd;
                    let v <- toGet(flashReqQs[i]).get;
                    return v;
                 endmethod
                 // will never fire
                 method ActionValue#(Tuple2#(Bit#(128), TagT)) writeWord if ( False);
                    $display("Error:: (%m) writeWord flash port of %d should not be used!", i);
                    $finish;
                    return ?;
                 endmethod
                 method Action readWord (Tuple2#(Bit#(128), TagT) taggedData); 
                    $display("flashreadmux got readWord from card %d ", i, fshow(taggedData));
                    let {data, tag} = taggedData;
                    Bit#(3) busSelect = truncate(tag);
                    wordBufs[i][busSelect] <= data;
                    gearSelector[i][busSelect] <= gearSelector[i][busSelect] + 1;
                    if (gearSelector[i][busSelect] == 1) 
                       busPageBufs[i][busSelect].enq({data, wordBufs[i][busSelect]});
                 endmethod
                 method Action writeDataReq(TagT tag) if (False); 
                    $display("Error:: (%m) writeDataReq flash port of %d should not be used!", i);
                    $finish;
                 endmethod
                 method Action ackStatus (Tuple2#(TagT, StatusT) taggedStatus) if (False); 
                    $display("Error:: (%m) ackStatus flash port of %d should not be used!", i);
                    $finish;
                 endmethod
         
              endinterface);
   endfunction
   

   interface flashReadServers = genWith(genFlashReadServers);
   
   interface flashClient = genWith(genFlashCtrlClient);

endmodule
 
