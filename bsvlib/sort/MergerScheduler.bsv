import Bitonic::*;
import Pipe::*;
import Cntrs::*;
import Vector::*;
import FIFOF::*;
import SpecialFIFOs::*;
import BuildVector::*;
import GetPut::*;
import Connectable::*;
import SorterTypes::*;
import Assert::*;
import SorterTypes::*;

import MergerSchedulerTypes::*;

`ifdef DEBUG
Bool debug = True;
`else
Bool debug = False;
`endif

interface MergerSchedVector#(numeric type numTags, numeric type numCredits, type iType);
   interface PipeIn#(TaggedSchedReq#(TMul#(numTags,2), iType)) schedReq;
   interface PipeOut#(UInt#(TLog#(TMul#(numTags,2)))) schedResp;   
   method Action incrCredit(UInt#(TLog#(numTags)) tag);
endinterface

typeclass MergerSchedVectorInstance#(numeric type numTags, numeric type numCredits, type iType);
   module mkMergerSchedVector#(Bool ascending
                               `ifdef DEBUG
                               , Integer level
                               `endif
                               )(MergerSchedVector#(numTags, numCredits, iType)); 
endtypeclass

instance MergerSchedVectorInstance#(1, numCredits, iType) 
   provisos (
      Bits#(iType, typeSz),
      MergerScheduler::MergerSchedInstance#(numCredits, iType),
      FShow#(iType)
   );
   
      module mkMergerSchedVector#(Bool ascending
      `ifdef DEBUG
      , Integer level
      `endif
      )(MergerSchedVector#(1, numCredits, iType));
      
      `ifdef DEBUG
      function scheM(x) = mkMergerScheduler(ascending, level, x);
      `endif
      Vector#(1, MergerSched#(numCredits, iType)) schedulers <- 
         `ifdef DEBUG
         genWithM(scheM);
         `else
         replicateM(mkMergerScheduler(ascending));
         `endif
      
      Vector#(TMul#(1,2), FIFOF#(SchedReq#(iType))) schedReqQ <- replicateM(mkUGSizedFIFOF(valueOf(numCredits)+1));
      
      function Vector#(2, PipeIn#(SchedReq#(b))) getPipeIn(MergerSched#(a, b) ifc) = ifc.schedReq;
      function PipeOut#(Bit#(1)) getPipeOut(MergerSched#(a, b) ifc) = ifc.schedResp;
      
      zipWithM_(mkConnection, map(toPipeOut, schedReqQ), concat(map(getPipeIn,schedulers)));
      
      FIFOF#(UInt#(TLog#(TMul#(1,2)))) willGoQ <- mkFIFOF;//BypassFIFOF;
      
      function Bool pready(PipeOut#(t) x) = x.notEmpty;
      
      rule issueWillGo;

         Vector#(1, Bool) canGo = map(pready, map(getPipeOut, schedulers));
         
         Vector#(1, Tuple2#(Bool, Bit#(TLog#(1)))) indexArray = zipWith(tuple2, canGo, genWith(fromInteger));
         
         let port = fold(elemFind, indexArray);
         
         if ( pack(canGo) != 0 ) begin
            let tag = tpl_2(port);
            let portsel = schedulers[tag].schedResp.first;
            schedulers[tag].schedResp.deq;
            if ( debug) $display("Will Go tag = %d, portSel = %d", tag, portsel);
            willGoQ.enq(unpack({tag,portsel}));
         end
      endrule


      interface PipeIn schedReq;
         method Action enq(TaggedSchedReq#(TMul#(1,2), iType) req);
            if (debug) $display(fshow(req));
            schedReqQ[req.tag].enq(SchedReq{topItem:req.topItem, last: req.last});
         endmethod
         method Bool notFull = True;
      endinterface
         
      interface PipeOut schedResp = toPipeOut(willGoQ);
      
      method Action incrCredit(UInt#(TLog#(1)) tag);
         schedulers[tag].incrCredit;
      endmethod
   endmodule


endinstance

instance MergerSchedVectorInstance#(numTags, numCredits, iType) 
   provisos (
      Add#(1, a__, numTags),
      Bits#(iType, typeSz),
      MergerScheduler::MergerSchedInstance#(numCredits, iType),
      Add#(1, b__, TDiv#(numTags, 2)),
      Add#(TLog#(TDiv#(numTags, 2)), 1, TLog#(numTags)),
      Add#(TDiv#(numTags, 2), c__, numTags),
      // Add#(1, b__, TDiv#(numTags, 2)),
      // Add#(TLog#(TDiv#(numTags, 2)), 1, TLog#(numTags)),
      // Add#(TDiv#(numTags, 2), c__, numTags),
      FShow#(iType)
   );

   module mkMergerSchedVector#(Bool ascending
      `ifdef DEBUG
      , Integer level
      `endif
      )(MergerSchedVector#(numTags, numCredits, iType));
      
      `ifdef DEBUG
      function scheM(x) = mkMergerScheduler(ascending, level, x);
      `endif
      Vector#(numTags, MergerSched#(numCredits, iType)) schedulers <- 
         `ifdef DEBUG
         genWithM(scheM);
         `else
         replicateM(mkMergerScheduler(ascending));
         `endif
      
      Vector#(TMul#(numTags,2), FIFOF#(SchedReq#(iType))) schedReqQ <- replicateM(mkUGSizedFIFOF(valueOf(numCredits)+1));
      
      function Vector#(2, PipeIn#(SchedReq#(b))) getPipeIn(MergerSched#(a, b) ifc) = ifc.schedReq;
      function PipeOut#(Bit#(1)) getPipeOut(MergerSched#(a, b) ifc) = ifc.schedResp;
      
      zipWithM_(mkConnection, map(toPipeOut, schedReqQ), concat(map(getPipeIn,schedulers)));
      
      Vector#(2, FIFOF#(UInt#(TLog#(numTags)))) willGoQ <- replicateM(mkFIFOF);//BypassFIFOF;
      
      function Bool pready(PipeOut#(t) x) = x.notEmpty;
   
      Vector#(2, Vector#(TDiv#(numTags,2), MergerSched#(numCredits, iType))) schedulersSplit = vec(take(schedulers), drop(schedulers));   
      
      for (Integer i = 0; i < 2; i = i + 1) begin
         rule issueWillGo_0;

            Vector#(TDiv#(numTags,2), Bool) canGo = map(pready, map(getPipeOut, schedulersSplit[i]));
         
            Vector#(TDiv#(numTags,2), Tuple2#(Bool, Bit#(TLog#(TDiv#(numTags,2))))) indexArray = zipWith(tuple2, canGo, genWith(fromInteger));
         
            let port = fold(elemFind, indexArray);
            
            if ( pack(canGo) != 0 ) begin
               let tag = tpl_2(port);
               let portsel = schedulersSplit[i][tag].schedResp.first;
               schedulersSplit[i][tag].schedResp.deq;
               if ( debug) $display("Will Go split = %d, tag = %d, portSel = %d", i, tag, portsel);
               willGoQ[i].enq(unpack({tag,portsel}));
            end
         endrule
      end
         
      
      FIFOF#(UInt#(TLog#(TMul#(numTags,2)))) schedRespQ <- mkBypassFIFOF;
      
      rule doIssue;
         if ( willGoQ[0].notEmpty) begin
            let tag = willGoQ[0].first;
            willGoQ[0].deq;
            schedRespQ.enq(unpack({1'b0, pack(tag)}));
         end
         else begin
            let tag = willGoQ[1].first;
            willGoQ[1].deq;
            schedRespQ.enq(unpack({1'b1, pack(tag)}));
         end
      endrule


      interface PipeIn schedReq;
         method Action enq(TaggedSchedReq#(TMul#(numTags,2), iType) req);
            if (debug) $display(fshow(req));
            schedReqQ[req.tag].enq(SchedReq{topItem:req.topItem, last: req.last});
         endmethod
         method Bool notFull = True;
      endinterface
         
      interface PipeOut schedResp = toPipeOut(schedRespQ);
      
      method Action incrCredit(UInt#(TLog#(numTags)) tag);
         schedulers[tag].incrCredit;
      endmethod
   endmodule
endinstance


interface MergerSched#(numeric type numCredits, type iType);
   interface Vector#(2, PipeIn#(SchedReq#(iType))) schedReq;
   // interface Vector#(2, PipeOut#(void)) schedResp;
   interface PipeOut#(Bit#(1)) schedResp;   
   method Action incrCredit;
endinterface

typeclass MergerSchedInstance#(numeric type numCredits, type iType);
   module mkMergerScheduler#(Bool ascending 
                             `ifdef DEBUG
                             , Integer level, Integer tag 
                             `endif
                             )(MergerSched#(numCredits, iType));

endtypeclass

instance MergerSchedInstance#(numCredits, iType) provisos(Bits#(iType, iSz), Ord#(iType));
   module mkMergerScheduler#(Bool ascending 
                             `ifdef DEBUG
                             , Integer level, Integer tag 
                             `endif
                             )(MergerSched#(numCredits, iType));
      let scheduler <- mkMergerSchedulerImpl(ascending
                                             `ifdef DEBUG
                                             , level, tag 
                                             `endif
                                             );
   
      return scheduler;
   endmodule
endinstance



module mkMergerSchedulerImpl#(Bool ascending 
                              `ifdef DEBUG
                              , Integer level, Integer tag 
                              `endif
                              )(MergerSched#(numCredits, iType)) provisos(Bits#(iType, iSz), Ord#(iType));
   String tab = "";
   `ifdef DEBUG
   for ( Integer l = 0; l < level; l = l + 1 ) tab = tab + "\t";
   `endif

   Reg#(Bit#(1)) portSel <- mkReg(0);
   Reg#(Bool) isFirst <- mkReg(True);
   Vector#(2, Reg#(Bool)) done <- replicateM(mkReg(False));
   Reg#(iType) prevTail <- mkRegU;
   
   Vector#(2, FIFOF#(SchedReq#(iType))) inQ <- replicateM(mkBypassFIFOF);
   
   // Vector#(2, FIFOF#(void)) canGoQ <- replicateM(mkFIFOF);
   FIFOF#(Bit#(1)) canGoQ <- mkFIFOF;
   
   Count#(UInt#(TLog#(TAdd#(numCredits,1)))) credit <- mkCount(fromInteger(valueOf(numCredits)));
   
   `ifdef DEBUG
   Reg#(Bit#(128)) numDecr <- mkReg(0);
   Reg#(Bit#(128)) numIncr <- mkReg(0);
   `endif
   
   rule doSchedule if (credit >0);
      credit.decr(1);
      let req = ?;
      
      let selectedPort = portSel;
      
      if ( portSel == 0 || (isFirst && inQ[0].notEmpty) ) begin
         req <- toGet(inQ[0]).get; 
         selectedPort = 0;
      end
      else begin
         req <- toGet(inQ[1]).get;
         selectedPort = 1;
      end
      
      
      let vecTail = req.topItem;
      let last = req.last;
         
      Bool lastPacket = False;      
      if ( last) begin
         if ( done[~portSel] ) begin
            done[0] <= False;
            done[1] <= False;
            isFirst <= True;
            lastPacket = True;
         end
         else begin
            done[portSel] <= True;
            isFirst <= False;
         end
      end
      else begin
         isFirst <= False;
      end

      Bit#(1) nextSel = getNextSel(selectedPort, isFirst, last, done[~portSel], isSorted(vec(prevTail, vecTail), ascending));
      `ifdef DEBUG 
      $display("(%t) %s[%0d-%0d]::scheduler update, credit = %d, portSel = %d, last = %d, nextSel = %d", $time, tab, level, tag, credit, portSel, last, nextSel); 
      numDecr <= numDecr + 1;
      $display("numIncr = %d, numDecr = %d", numIncr, numDecr);
      dynamicAssert(numIncr <= numDecr, "num of incrCredit should alway be smaller than num of decrCredit");
      `endif
      portSel <= nextSel;
      canGoQ.enq(selectedPort);
      prevTail <= isFirst? vecTail : getTop(vec(prevTail, vecTail), ascending);
         
   endrule

   interface schedReq = map(toPipeIn, inQ);
   interface schedResp = toPipeOut(canGoQ);
   
   method Action incrCredit;
      `ifdef DEBUG
      numIncr <= numIncr + 1;
      `endif
      credit.incr(1);
   endmethod
endmodule


interface MergerSchedComb#(numeric type numCredits, type iType);
   interface Vector#(2, PipeOut#(void)) nextReq;
   method Action update(iType vecTail, Bool last);
   method Action incrCredit;
endinterface


module mkMergerSchedulerComb#(Bool ascending)(MergerSchedComb#(numCredits, iType)) provisos(Bits#(iType, iSz), Ord#(iType));
   Vector#(2, FIFOF#(void)) bypassQ <- replicateM(mkBypassFIFOF);
   Reg#(Bit#(1)) portSel <- mkReg(0);
   Reg#(Bool) isFirst <- mkReg(True);
   Vector#(2, Reg#(Bool)) done <- replicateM(mkReg(False));
   Reg#(iType) prevTail <- mkRegU;
   // Reg#(UInt#(TLog#(TAdd#(numCredits,1)))) credit[2] <- mkCReg(2, 0);
   Count#(UInt#(TLog#(TAdd#(numCredits,1)))) credit <- mkCount(fromInteger(valueOf(numCredits)));
   


   
   Reg#(Bool) init <- mkReg(False);
   
   rule doInit if (!init);
      bypassQ[0].enq(?);
      init <= True;
   endrule
      

   function PipeOut#(void) genNextReq(Integer i);   
      return (interface PipeOut#(void);
                 method void first = bypassQ[i].first;
                 method Bool notEmpty = bypassQ[i].notEmpty && credit > 0;
                 method Action deq if (credit > 0);
                    bypassQ[i].deq;
                    credit.decr(1);
                 endmethod
              endinterface);
   endfunction
   
   interface nextReq = genWith(genNextReq);
   
   method Action update(iType vecTail, Bool last) if (init);
      // let packet = mem.rdResp;
      // mem.deqRdResp;
      Bool lastPacket = False;
      if ( last) begin
         if ( done[~portSel] ) begin
            done[0] <= False;
            done[1] <= False;
            isFirst <= True;
            lastPacket = True;
         end
         else begin
            done[portSel] <= True;
            isFirst <= False;
         end
      end
      else begin
         isFirst <= False;
      end

      Bit#(1) nextSel = getNextSel(portSel, isFirst, last, done[~portSel], isSorted(vec(prevTail, vecTail), ascending));
      if (debug) $display("%m, scheduler update, portSel = %d, last = %d, nextSel = %d", portSel, last, nextSel);
      portSel <= nextSel;
      bypassQ[nextSel].enq(?);
      prevTail <= isFirst? vecTail : getTop(vec(prevTail, vecTail), ascending);
   endmethod
   
   method Action incrCredit;
      credit.incr(1);
   endmethod
endmodule


/*
typedef enum {Schedule, Append} SchedOp deriving (Bits, Eq, FShow);

typedef struct{
   UInt#(TLog#(numTags)) tag;
   Bit#(1) port;
   SchedReq schedReq;
   Bool newCntx;
   } ScheduleF2P#(type iType, numeric type numTags) deriving (Bits, Eq, FShow);


typedef struct{
   SceduleContext#(iType, numCredits) cntx;
   UInt#(TLog#(numTags)) tag;
   } DrainFrame#(numeric type numTags,
                 numeric type numCredits,
                 type iType) deriving (FShow, Bits, Eq);


module mkMergerSchedVector#(Bool ascending
                            `ifdef DEBUG
                            , Integer level
                            `endif
                            )(MergerSchedVector#(numTags, numCredits, iType));
   
   ScheduleContext#(iType, numCredits) initValue = ScheduleContext{currList:0,
                                                                   currMax:?,
                                                                   first:True,
                                                                   otherDone: False};
                                                                   
                                                                   
   // Reg#(Bool) busy <- mkCReg(2, False);
   // Reg#(TLog#(numTags)) currTag[2] <- mkCReg(2, 0);
   Reg#(ScheduleContext#(iType, numCredits)) currContextReg <- mkRegU;
   
   RWBramCore#(UInt#(numTags), ScheduleContext#(iType, numCredits)) contextArray <- mkRWBramCore;
   
   BRAMVector#(TLog#(numTags), valueOf(numCredits), SchedReq) reqBuffer <- mkBypassBRAMVector;
   
   Reg#(Bit#(1)) portIdReg <- mkRegU;
   
   FIFOF#(ScheduleF2P#(iType, numTags)) f2p <- mkFIFOF;
   
   FIFOF#(DrainFrame#(numTags, numCredits, iType)) drainReqQ <- mkBypassFIFOF;
   FIFOF#(DrainFrame#(numTags, numCredits, iType)) drainRespQ <- mkFIFO;
   Fifo#(2, UInt#(TLog#(numTags)), UInt#(TLog#(numTags))) sb <- mkCFSFifo( \== );
   
   rule doProcessSchedule;
      let currTag = ?;
      let currContext = ?;
      let portId = ?;
      let schedReq = ?;
      
      let processReq = True;;
      
      if (drainResp.first.tag == f2p.first.tag ) begin
         drainRespQ.deq;
         f2p.deq;
         if ( f2p.first.newCntx ) begin
            // drop stale context
            contextArray.deqRdResp;            
         end
         currTag     = f2p.first.tag;
         currContext = drainResp.first.cntx;
         portId      = f2p.first.portId;
         schedReq    = f2p.first.schedReq;
      end
      else if ( drainResp.first.tag != f2p.first.tag) begin
         drainRespQ.deq;
         currTag     = drainResp.first.tag;
         currContext = drainResp.first.cntx;
         processReq = False;
         // stall f2p and write context to context Array
      end
      else if ( drainResp.notEmpty && !f2p.notEmpty ) begin
         drainRespQ.deq;
         currTag     = drainResp.first.tag;
         currContext = drainResp.first.cntx;
         processReq = False;
      end
      else begin
         f2p.deq;
         currTag     = f2p.first.tag;
         portId      = f2p.first.portId;
         schedReq    = f2p.first.schedReq;
         if ( f2p.first.newCntx ) begin
            currContext = contextArray.rdResp;
            contextArray.deqRdResp;            
         end
         else begin
            currContext = currContextReg;
         end
      end
         
         
      if ( processReq ) begin
         // found out the currTag is currently being drained
         if ( sb.search(currTag) ) begin
            // doing append only
            reqBuffer.wrReq(toTag1D(tag, portId), schedReq);
            bypassAppendInfo.enq(portId);
         end
         else begin
            let nextContext = computeNextContext(currContext, portId, schedReq, ascending);
            // if the current schedule req can go
            if ( currContext.portSel == portId || currContext.first ) begin
               canGo.enq(toTag1D(tag, portId));
               if (nextContext.inflights[nextContext.portSel] > 0) begin
                  // evoke drain ScheduleReq if the nextPortSel has buffered requests;
                  drainReqQ.enq(nextContext);
                  sb.enq(tag);
               end
            end
            else begin
               // append to schedule request buffer
               nextContext = currContext;
               nextContext.inflights[portId] = nextContext.inflights[portId] + 1;
               reqBuffer.wrReq(toTag1D(tag, portId), schedReq);
            end
            
            contextArray.wrReq(currTag, nextContext);
            currContextReg <= nextContext;
         end
      end
      else begin
         // flush the drained context to context Array
         contextArray.wrReq(currTag, currContext);
         currContextReg <= currContext;
      end
   endrule
   
   Reg#(Bool) firstIter <- mkReg(False);
   
   Reg#(ScheduleContext#(iType, numCredits)) drainContextReg <- mkRegU;
   Reg#(Bit#(1)) portIdReg <- mkRegU;
   Reg#(UInt#(TLog#(numTags))) tagReg <- mkRegU;
   
   rule doDrainScheduleReq;
      let currContext = drainContextReg;
      let portId = portIdReg;
      let tagS = tagReg;
      let nextContext = ?;

      if ( !firstIter ) begin
         let schedReq = reqBuffer.rdResp;
         reqBuffer.deqRdResp;
         
         nextContext = computeNextContext(currContext, portId, schedReq, ascending);
         
         if (bypassAppendInfo.notEmpty) begin
            let appendedPort = bypassAppendInfo;
            nextContext.listSz[appendedPort] = nextContext.listSz[appendedPort] + 1;
         end
         
         canGo2.enq(toTag1D(tagS, portId));
         drainContextReg <= nextContext;
         
         if ( needDrainBuffer(nextContext )) begin
            firstIter <= False;
            reqBuffer.rdReq(toTagId(tagS, nextContext.portSel));
            portIdReg <= nextContext.portSel;
         end
         else begin
            drainRespQ.enq(DrainFrame{cntx:nextContext, tag:tagS});
            sb.deq;
            if ( drainReqQ.notEmpty ) begin
               let req = drainReqQ.first;
               drainScheduleReqQ.deq;
               reqBuffer.rdReq(toTagId(req.tag, req.cntx.portSel));
               tagReg <= req.tag;
               portIdReg <= req.cntx.portSel;
            end
            else begin
               firstIter <= True;
            end
         end
      end
      else begin
         let req = drainReqQ.first;
         drainReqQ.deq;
         tagReg <= req.tag;
         portIdReg <= nextContext.portSel;
         reqBuffer.rdReq(toTagId(req.tag, req.cntx.portSel));
      end
   endrule
   
   
   rule doDistributeCanGo;
      if ( canGo2.notEmpty) begin
         let tagSrc = canGo2.first;
         canGo2.deq;
      end
      else begin
         let tagSrc = canGo.first;
         canGo.deq;
      end

      let portId = toPortId(tagSrc);      
      let tagDst = toTagDst(tagSrc);
      

      bufferdCanGoQs[tagDst].enq(portId);
   endrule
   
   for ( Integer i = 0; i < valueOf(numTags); i = i + 1 ) begin
      rule doIssue;
      endrule
   end
   
   
  
   Reg#(TLog#(numTags)) fetchedTag <- mkReg(0);
      
   interface PipeIn schedReq;
      method Action enq(TaggedSchedReq#(TMul#(numTags,2), iType) req);
         UInt#(numTags) tagSched = unpack(truncateLSB(pack(req.tag)));
         fetchedTag <= tagSched;
         if ( fetchedTag == tagSched ) begin
            f2d.enq(ScheduleF2D{tag: tagSched, topItem: req.topItem; last: req.last, op: Schedule, newCntx: False});
         end
         else begin
            contextArray.rdReq(tagSched);
            f2d.enq(ScheduleF2D{tag: tagSched, topItem: req.topItem; last: req.last, op: Schedule, newCntx: True});
         end
      endmethod
      method Bool notEmpty;
         return f2d.notEmpty;
      endmethod
   endinterface

   interface schedResp = toPipeOut(issueQ);
   method Action incrCredit(UInt#(TLog#(numTags)) tag);
      credit[tag].incr(1);
   endmethod
endmodule
*/



// `include "SynthMergerScheduler_UInt_32_8.bsv"
`include "SynthMergerScheduler_UInt_32_16.bsv"
