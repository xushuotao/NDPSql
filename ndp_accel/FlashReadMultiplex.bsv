import Vector::*;
import FIFO::*;
import FIFOF::*;
import BRAMFIFO::*;
import ClientServer::*;
import ClientServerHelper::*;
import GetPut::*;

import FlashCtrlIfc::*;
import ControllerTypes::*;
import RegFile::*;


interface FlashReadMultiplexIO#(numeric type nSlaves);
   // in-order request/response per channel
   interface Vector#(nSlaves, Server#(DualFlashAddr, Bit#(256))) flashReadServers;
   
   // flash client flash controllers
   interface Vector#(2, FlashCtrlClient) flashClient;
endinterface

typedef TMul#(128, 1024) MaxInflightRows;

Bool verbose = False;

module mkFlashReadMultiplexIO(FlashReadMultiplexIO#(nSlaves));

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
      if (verbose) $display("(@%t) flashReadMux deqResp beatCnt = %d, card = %d, bus = %d, channel = %d", $time, beatCnt, card, bus, channel);
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
                                                         page: extend(req.page)});
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
                    if (verbose) $display("flashreadmux got readWord from card %d ", i, fshow(taggedData));
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


interface FlashReadMultiplexOO#(numeric type nSlaves);
   // in-order request/response per channel
   interface Vector#(nSlaves, Server#(Tuple2#(TagT, DualFlashAddr), Tuple2#(TagT, Bit#(256)))) flashReadServers;
   
   // flash client flash controllers
   interface Vector#(2, FlashCtrlClient) flashClient;
endinterface
 

module mkFlashReadMultiplexOO(FlashReadMultiplexOO#(nSlaves)) provisos (Alias#(Bit#(TLog#(nSlaves)), slaveIdT));

   Vector#(2, FIFO#(FlashCmd)) flashReqQs <- replicateM(mkFIFO);
   Vector#(2, RegFile#(TagT,Tuple2#(BusT,slaveIdT))) busTables <- replicateM(mkRegFileFull);
   
   
   Vector#(nSlaves, FIFO#((Tuple2#(TagT, Bit#(256))))) pageRespQs <- replicateM(mkFIFO);
   Vector#(2, FIFOF#(Tuple3#(slaveIdT, TagT, Bit#(256)))) cardRespQs <- replicateM(mkFIFOF);
   
   Reg#(Bit#(1)) cardPrefer <- mkReg(0);
   rule doDistribute if (cardRespQs[0].notEmpty || cardRespQs[1].notEmpty );
      let cardSel = cardPrefer;
      
      if ( cardRespQs[0].notEmpty && cardRespQs[1].notEmpty ) begin
         cardPrefer <= cardPrefer + 1;
      end
      else if ( cardRespQs[0].notEmpty) begin
         cardPrefer <= 1;
         cardSel = 0;
      end
      else begin
         cardPrefer <= 0;
         cardSel = 1;
      end
      
      let {slaveId, tag, data} <- toGet(cardRespQs[cardSel]).get;
      
      pageRespQs[slaveId].enq(tuple2(tag, data));
   endrule
         

   function Server#(Tuple2#(TagT, DualFlashAddr), Tuple2#(TagT, Bit#(256))) genFlashReadServers(Integer slaveId);
      return (interface Server#(Tuple2#(TagT, DualFlashAddr), Bit#(256));
                 interface Put request;
                    method Action put(Tuple2#(TagT, DualFlashAddr) v);
                       let {tag, req} = v;
                       flashReqQs[req.card].enq(FlashCmd{tag: tag,//zeroExtend(req.bus),
                                                         op: READ_PAGE,
                                                         bus: req.bus,
                                                         chip: req.chip,
                                                         block: extend(req.block),
                                                         page: extend(req.page)});
                       // outstandingReqQ.enq(tuple3(req.card, req.bus, fromInteger(i)));
                       busTables[req.card].upd(tag, tuple2(req.bus, fromInteger(slaveId)));
                    endmethod
                 endinterface
         
                 interface Get response = toGet(pageRespQs[slaveId]);
              endinterface);
   endfunction
   
   
   Vector#(2, Vector#(8, Reg#(Bit#(1)))) gearSelector <- replicateM(replicateM(mkReg(0)));
   Vector#(2, Vector#(8, Reg#(Bit#(128)))) wordBufs <- replicateM(replicateM(mkReg(0)));
   
   function FlashCtrlClient genFlashCtrlClient(Integer cardId);
      return (interface FlashCtrlClient;
                 method ActionValue#(FlashCmd) sendCmd;
                    let v <- toGet(flashReqQs[cardId]).get;
                    return v;
                 endmethod
                 // will never fire
                 method ActionValue#(Tuple2#(Bit#(128), TagT)) writeWord if ( False);
                    $display("Error:: (%m) writeWord flash port of %d should not be used!", cardId);
                    $finish;
                    return ?;
                 endmethod
                 method Action readWord (Tuple2#(Bit#(128), TagT) taggedData); 
                    if (verbose) $display("flashreadmux got readWord from card %d ", cardId, fshow(taggedData));
                    let {data, tag} = taggedData;
                    let {busSelect, slaveId} = busTables[cardId].sub(tag);//truncate(tag);
                    wordBufs[cardId][busSelect] <= data;
                    gearSelector[cardId][busSelect] <= gearSelector[cardId][busSelect] + 1;
                    if (gearSelector[cardId][busSelect] == 1) 
                       cardRespQs[cardId].enq(tuple3(slaveId, tag, {data, wordBufs[cardId][busSelect]}));
                 endmethod
                 method Action writeDataReq(TagT tag);
                    $display("Error:: (%m) writeDataReq flash port of %d should not be used!", cardId);
                    $finish;
                 endmethod
                 method Action ackStatus (Tuple2#(TagT, StatusT) taggedStatus);
                    $display("Error:: (%m) ackStatus flash port of %d should not be used!", cardId);
                    $finish;
                 endmethod
         
              endinterface);
   endfunction
   

   interface flashReadServers = genWith(genFlashReadServers);
   
   interface flashClient = genWith(genFlashCtrlClient);

endmodule
