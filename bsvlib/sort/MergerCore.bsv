import SorterTypes::*;
import TopHalfUnitSMT::*;
import Vector::*;
import Pipe::*;
import DelayPipe::*;
import Bitonic::*;
import RWBramCore::*;
import Assert::*;
import BuildVector::*;

interface MergerCore#(numeric type numTags, numeric type vSz, type iType);
   method Action enq(Vector#(vSz, iType) d, UInt#(TLog#(numTags)) tag, Bool firstAll, Bool first2, Bool lastPacket);
   interface PipeOut#(Tuple2#(SortedPacket#(vSz, iType), UInt#(TLog#(numTags)))) outPipe;
endinterface


module mkUGMergeCore#(Bool ascending, Integer level)(MergerCore#(numTags, vSz, iType)) provisos(
   Bits#(iType, iSz),
   Add#(1, a__, vSz),
   FShow#(iType),
   Bitonic::RecursiveBitonic#(vSz, iType),
   TopHalfUnitSMT::TopHalfUnitSMTInstance#(numTags, vSz, iType),
   Ord#(iType),
   Alias#(UInt#(TLog#(numTags)), tagT));
   
   String tab = "";
   for ( Integer l = 0; l < level; l = l + 1 ) tab = tab + "\t";
   
   // stage 0
   TopHalfUnitSMT#(numTags, vSz,iType) topHalfUnit <- mkUGTopHalfUnitSMT(ascending);
   DelayPipe#(vSz, Tuple4#(Vector#(vSz, iType), Bool, Bool, Bool)) selectedInQ <- mkDelayPipe;
   
   // Stage 1
   DelayPipe#(1, Vector#(vSz,iType)) sorterDelayBy1 <- mkDelayPipe;
   StreamNode#(vSz, iType) sorter <- mkUGSortBitonic(ascending);
   DelayPipe#(TAdd#(TLog#(vSz),1), Tuple3#(tagT, Bool, Bool)) outTagQ <- mkDelayPipe;
   
   RWBramCore#(tagT, Vector#(vSz, iType)) prevTopCtxt <- mkUGRWBramCore;
   Vector#(numTags, Reg#(Bool)) needDrain <- replicateM(mkReg(False));
   // tag, in, drop, drain
   Reg#(Tuple5#(tagT, Vector#(vSz,iType), Bool, Bool, Bool)) halfCleanTask <- mkRegU;

   
   (* fire_when_enabled,  no_implicit_conditions *)
   rule doPreHalfClean if ( selectedInQ.notEmpty );
      let {currTop, tag} = topHalfUnit.currTop.first;      
      let {in, firstPacket, firstOut, lastPacket} = selectedInQ.first;
      selectedInQ.deq;
      topHalfUnit.currTop.deq;
      
      prevTopCtxt.wrReq(tag, currTop);
      
      if (debug) $display("(%t) %s[%0d-%0d]prehalfclean:: ", $time, tab, level, tag,  fshow(selectedInQ.first));      
      dynamicAssert(!(firstPacket&&firstOut), "firstPacket and firstOut cannot be both true");
      
      Bool dropIn = firstPacket && !needDrain[tag];
      Bool drain = False;
      let nextTag = tag;
      if ( firstPacket && needDrain[tag] ) begin
         needDrain[tag] <= False;
         drain = True;
      end
      else if ( lastPacket ) begin
         needDrain[tag] <= True;
      end
      
      prevTopCtxt.rdReq(nextTag);
      halfCleanTask <= tuple5(nextTag, in, dropIn, drain, firstOut);
   endrule
   
   (* fire_when_enabled, no_implicit_conditions *)
   rule doPrevHalfCleanDrain ( !selectedInQ.notEmpty &&& findElem(True, readVReg(needDrain)) matches tagged Valid .tag  );
      needDrain[tag] <= False;
      prevTopCtxt.rdReq(tag);
      halfCleanTask <= tuple5(tag, ?, False, True, False);
   endrule
   
      
   (* fire_when_enabled, no_implicit_conditions *)
   rule doHalfClean if ( prevTopCtxt.rdRespValid ) ;
      let {tag, in, dropIn, drain, firstOut} = halfCleanTask;
      
      let prevTop = prevTopCtxt.rdResp;
      prevTopCtxt.deqRdResp;
      if (debug) $display("(%t) %s[%0d-%0d]halfclean:: ", $time, tab, level, tag,  fshow(halfCleanTask));
      if (dropIn ) begin
         // noAction;
      end
      else if ( drain )begin
          sorterDelayBy1.enq(prevTop);
         outTagQ.enq(tuple3(tag,False,True));
      end
      else begin
          sorterDelayBy1.enq(halfClean(vec(in, prevTop), ascending)[0]);
         outTagQ.enq(tuple3(tag,firstOut,False));
      end
   endrule
   
   (* fire_when_enabled , no_implicit_conditions *)
   rule doSortIssue if(sorterDelayBy1.notEmpty);
      let v = sorterDelayBy1.first;
      sorter.inPipe.enq(v);
   endrule

   method Action enq(Vector#(vSz, iType) d, UInt#(TLog#(numTags)) tag, Bool firstAll, Bool first2, Bool lastPacket);
      topHalfUnit.enqData(d, firstAll?Init:Normal, tag);
      selectedInQ.enq(tuple4(d, firstAll, first2, lastPacket));
   endmethod
   
   interface PipeOut outPipe;
      method Tuple2#(SortedPacket#(vSz, iType), UInt#(TLog#(numTags))) first;
         let {tag, f, l} = outTagQ.first;
         let d = sorter.outPipe.first;
         return tuple2(SortedPacket{d: d, first: f, last: l}, tag);
      endmethod
   
      method Bool notEmpty;
         return sorter.outPipe.notEmpty;
      endmethod
   
      method Action deq = noAction;
   endinterface
endmodule
   
