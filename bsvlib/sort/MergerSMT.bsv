import TopHalfUnitSMT::*;
import Pipe::*;
import Bitonic::*;
import FIFOF::*;
import BRAMFIFO::*;
import SpecialFIFOs::*;
import Vector::*;
import Connectable::*;
import GetPut::*;
import BuildVector::*;
import RWBramCore::*;
import Assert::*;
import DelayPipe::*;

Bool debug = False;

typedef struct {
   Vector#(vSz, iType) d;
   Bool first;
   Bool last;
   } SortedPacket#(numeric type vSz, type iType) deriving (Bits,Eq,FShow);


interface MergeNSMT#(type iType,
                     numeric type vSz,
                     numeric type n);
   interface Vector#(n, PipeIn#(SortedPacket#(vSz, iType))) inPipes;
   interface PipeOut#(SortedPacket#(vSz, iType)) outPipe;
endinterface

typeclass RecursiveMergerSMT#(type iType,
                              numeric type vSz,
                              numeric type n);
////////////////////////////////////////////////////////////////////////////////
/// module:      mkStreamingMergeN
/// Description: this module takes N in-streams, each has sorted elements of 
///              sortedSz streaming @ vSz elements per beat, and merge them into 
///              a single sorted out-stream of N*sortedSz elements with a binary
///              merge-tree
////////////////////////////////////////////////////////////////////////////////
   module mkMergeNSMT#(Bool ascending, Integer level)(MergeNSMT#(iType,vSz,n));
endtypeclass

typedef TAdd#(4, TAdd#(vSz, TLog#(vSz))) BufSize#(numeric type vSz);

instance RecursiveMergerSMT#(iType, vSz, 2) provisos(
   TopHalfUnitSMT::TopHalfUnitSMTInstance#(1, vSz, iType),
   Add#(1, a__, vSz),
   Bits#(Tuple3#(Vector::Vector#(vSz, iType), Bool, Bool), b__),
   Add#(1, c__, b__),
   Add#(1, d__, TLog#(vSz)),
   Bitonic::RecursiveBitonic#(vSz, iType),
   Bits#(iType, typeSz),
   FShow#(iType),
   Ord#(iType)
);
   module mkMergeNSMT#(Bool ascending, Integer level)(MergeNSMT#(iType,vSz,2));
      MergerSMT#(1, BufSize#(vSz), vSz, iType) merger_worker <- mkMergerSMT(ascending, level);
      interface inPipes = merger_worker.inPipes[0];
      interface outPipe = merger_worker.outPipes[0];
   endmodule
endinstance


instance RecursiveMergerSMT#(iType, vSz, n) provisos(
   Mul#(TDiv#(n, 2), 2, n),
   MergerSMT::RecursiveMergerSMT#(iType, vSz, TDiv#(n, 2)),
   TopHalfUnitSMT::TopHalfUnitSMTInstance#(TDiv#(n, 2), vSz, iType),
   Add#(1, a__, vSz),
   Bits#(Tuple3#(Vector::Vector#(vSz, iType), Bool, Bool), b__),
   Add#(1, c__, b__),
   Add#(1, d__, TLog#(vSz)),
   Bitonic::RecursiveBitonic#(vSz, iType),
   FShow#(iType),
   Ord#(iType)
);
   module mkMergeNSMT#(Bool ascending, Integer level)(MergeNSMT#(iType,vSz,n));
   
      MergerSMT#(TDiv#(n,2), BufSize#(vSz), vSz, iType) merger_worker <- mkMergerSMT(ascending, level);
   
      MergeNSMT#(iType,vSz,TDiv#(n,2)) mergerN_2 <- mkMergeNSMT(ascending, level+1);
   
      zipWithM_(mkConnection, merger_worker.outPipes, mergerN_2.inPipes);
   
      interface inPipes = concat(merger_worker.inPipes);
      interface outPipe = mergerN_2.outPipe;
   endmodule
endinstance
                            

interface MergerSMT#(numeric type numTags,
                     numeric type tagBufSz,
                     numeric type vSz,
                     type iType);
   interface Vector#(numTags, Vector#(2, PipeIn#(SortedPacket#(vSz,iType)))) inPipes;
   interface Vector#(numTags, PipeOut#(SortedPacket#(vSz,iType))) outPipes;
endinterface


module mkMergerSMT#(Bool ascending, Integer level)(MergerSMT#(numTags, tagBufSz, vSz, iType)) provisos(
   Alias#(UInt#(TLog#(numTags)), tagT),
   Add#(1, a__, vSz),
   Bits#(Tuple3#(Vector::Vector#(vSz, iType), Bool, Bool), b__),
   Add#(1, c__, b__),
   Bitonic::RecursiveBitonic#(vSz, iType),
   TopHalfUnitSMT::TopHalfUnitSMTInstance#(numTags, vSz, iType),
   Add#(1, d__, TLog#(vSz)),
   FShow#(iType),
   Ord#(iType)

   // NumAlias#(TExp#(TLog#(tagBufSz)), tagBufSz) // tagBufSz is power of 2
   );
   
   Vector#(numTags, Vector#(2, FIFOF#(SortedPacket#(vSz, iType)))) inQs <- replicateM(replicateM(mkPipelineFIFOF));
   
   Vector#(numTags, Vector#(2, Reg#(Bool))) firstReg <- replicateM(replicateM(mkReg(False)));
   Vector#(numTags, Vector#(2, Reg#(Bool))) lastReg <- replicateM(replicateM(mkReg(False)));

   
   TopHalfUnitSMT#(numTags, vSz,iType) topHalfUnit <- mkUGTopHalfUnitSMT(ascending);
   
   StreamNode#(vSz, iType) sorter <- mkUGSortBitonic(ascending);
   
   Vector#(numTags, Reg#(Bit#(1))) portSel <- replicateM(mkReg(0));
   Vector#(numTags, Reg#(iType)) prevTail <- replicateM(mkRegU);
   Vector#(numTags, Array#(Reg#(Bit#( TLog#(TAdd#(tagBufSz,1)) ) )) ) credit <- replicateM(mkCReg(2, fromInteger(valueOf(tagBufSz))));
   Vector#(numTags, FIFOF#(SortedPacket#(vSz, iType))) buffer <- replicateM(mkSizedBRAMFIFOF(valueOf(tagBufSz)));
   // FIFOF#(Tuple5#(Vector#(vSz, iType), Bool, Bool, Bool, tagT)) selectedInQ <- mkUGSizedFIFOF(valueOf(vSz));
   DelayPipe#(vSz, Tuple4#(Vector#(vSz, iType), Bool, Bool, Bool)) selectedInQ <- mkDelayPipe;
   
   String tab = "";
   for ( Integer l = 0; l < level; l = l + 1 ) tab = tab + "\t";
   
   for (Integer i = 0; i < valueOf(numTags); i = i + 1 ) begin
      Vector#(2, Reg#(Bool)) done <- replicateM(mkReg(False));
      Reg#(Bool) isFirst <- mkReg(True);
      
      rule doDeqInQ if (credit[i][0] > 0);
         credit[i][0] <= credit[i][0] - 1;
         SortedPacket#(vSz, iType) packet = ?;
         Bool lastPacket = False;
         if ( portSel[i] == 0) begin
            packet <- toGet(inQs[i][0]).get;
            if ( packet.last) begin
               if ( done[1] ) begin
                  done[0] <= False;
                  done[1] <= False;
                  isFirst <= True;
                  lastPacket = True;
               end
               else begin
                  done[0] <= True;
                  isFirst <= False;
               end
            end
            else begin
               isFirst <= False;
            end
         end
         else begin
            packet <- toGet(inQs[i][1]).get;
            if ( packet.last) begin
               if ( done[0] ) begin
                  done[0] <= False;
                  done[1] <= False;
                  isFirst <= True;
                  lastPacket = True;
               end
               else begin
                  done[1] <= True;
                  isFirst <= False;
               end
            end
            else begin
               isFirst <= False;
            end
         end
         
         if ( isFirst ) portSel[i] <= ~portSel[i];
         else if ( packet.last ) portSel[i] <= ~portSel[i];
         else if ( done[~portSel[i]] ) portSel[i] <= portSel[i];
         else if ( isSorted(vec(prevTail[i], last(packet.d)), ascending) ) portSel[i] <= ~portSel[i];
         prevTail[i] <= isFirst? last(packet.d) : getTop(vec(prevTail[i], last(packet.d)), ascending);
         
         if (debug) $display("(%t) %s[%0d-%0d]In:: isFirst = %d, firstOut = %d, lastPacket = %d, portSel = %d", $time, tab, level, i, isFirst, !isFirst&&packet.first, lastPacket, portSel[i]);
         topHalfUnit.enqData(packet.d, isFirst?Init:Normal, fromInteger(i));
         selectedInQ.enq(tuple4(packet.d, isFirst, !isFirst&&packet.first, lastPacket));//, fromInteger(i)));
      endrule
   end
   
   // FIFOF#(Tuple3#(tagT, Bool, Bool)) outTagQ <- mkUGSizedFIFOF(valueOf(TLog#(vSz))+1);
   DelayPipe#(TLog#(vSz), Tuple3#(tagT, Bool, Bool)) outTagQ <- mkDelayPipe;
   
   RWBramCore#(tagT, Vector#(vSz, iType)) prevTopCtxt <- mkRWBramCore;
   
   Vector#(numTags, Reg#(Bool)) needDrain <- replicateM(mkReg(False));
   
   // tag, in, drop, drain
   Reg#(Tuple5#(tagT, Vector#(vSz,iType), Bool, Bool, Bool)) halfCleanTask <- mkRegU;
   
   (* fire_when_enabled *)//, no_implicit_conditions *)
   rule doPreHalfClean if ( selectedInQ.notEmpty );
      let {currTop, tag} = topHalfUnit.currTop.first;      
      let {in, firstPacket, firstOut, lastPacket} = selectedInQ.first;
      selectedInQ.deq;
      topHalfUnit.currTop.deq;
      
      prevTopCtxt.wrReq(tag, currTop);
      
      if (debug) $display("(%t) %s[%0d-%0d]prehalfclean:: ", $time, tab, level, tag,  fshow(selectedInQ.first));      
      // dynamicAssert(tag == tagIn, "tag must match");
      dynamicAssert(!(firstPacket&&firstOut), "firstPacket and firstOut cannot be both true");
      
      Bool dropIn = firstPacket && !needDrain[tag]; //!nextDrainTag.notEmpty;// !isValid(nextDrain);
      Bool drain = False;
      let nextTag = tag;
      // if ( firstPacket && nextDrainTag.notEmpty() ) begin// matches tagged Valid .drainTag
      if ( firstPacket && needDrain[tag] ) begin// matches tagged Valid .drainTag
         // nextTag = drainTag;
         // nextTag <- toGet(nextDrainTag).get;
         needDrain[tag] <= False;
         drain = True;
         // nextDrain <= tagged Invalid;
      end
      else if ( lastPacket ) begin
         // nextDrain <= tagged Valid tag;
         // nextDrainTag.enq(tag);
         needDrain[tag] <= True;
      end
      
      prevTopCtxt.rdReq(nextTag);
      // halfCleanTask.enq(tuple5(nextTag, in, dropIn, drain, firstOut));
      halfCleanTask <= tuple5(nextTag, in, dropIn, drain, firstOut);
   endrule
   
   // rule doPrevHalfCleanDrain ( nextDrainTag.notEmpty && !(topHalfUnit.currTop.notEmpty && selectedInQ.notEmpty) ); //& nextDrain matches tagged Valid .tag);
   (* fire_when_enabled *)
   rule doPrevHalfCleanDrain ( !selectedInQ.notEmpty &&& findElem(True, readVReg(needDrain)) matches tagged Valid .tag  ); //& nextDrain matches tagged Valid .tag);
      needDrain[tag] <= False;
      prevTopCtxt.rdReq(tag);
      halfCleanTask <= tuple5(tag, ?, False, True, False);
   endrule
      
   (* fire_when_enabled *)
   rule doHalfClean if ( prevTopCtxt.rdRespValid ) ;
      let {tag, in, dropIn, drain, firstOut} = halfCleanTask;
      
      let prevTop = prevTopCtxt.rdResp;
      prevTopCtxt.deqRdResp;
      if (debug) $display("(%t) %s[%0d-%0d]halfclean:: ", $time, tab, level, tag,  fshow(halfCleanTask));
      if (dropIn ) begin
         // noAction;
      end
      else if ( drain )begin
         sorter.inPipe.enq(prevTop);
         outTagQ.enq(tuple3(tag,False,True));
      end
      else begin
         sorter.inPipe.enq(halfClean(vec(in, prevTop), ascending)[0]);
         outTagQ.enq(tuple3(tag,firstOut,False));
      end
   endrule
   
   Vector#(numTags, Reg#(Maybe#(iType))) prevMax <- replicateM(mkReg(tagged Invalid));
   (* fire_when_enabled *)//, no_implicit_conditions *)
   rule doEnqBuf if(sorter.outPipe.notEmpty);
      let {tag, first, last} = outTagQ.first;
      outTagQ.deq;
      
      let d = sorter.outPipe.first;
      sorter.outPipe.deq;
      if (debug) $display("(%t) %s[%0d-%0d]Out:: first = %d, last = %d, (prevMax, currHead) = ", $time, tab, level, tag, first, last, fshow(prevMax[tag]), " ", fshow(d[0]));
      dynamicAssert(isSorted(d, ascending), "beat should be sorted internally");
      prevMax[tag] <= last ? tagged Invalid : tagged Valid d[valueOf(vSz)-1];
      if ( prevMax[tag] matches tagged Valid .v) begin
         dynamicAssert(isSorted(vec(v, d[0]), ascending), "beats should be sorted externally");         
      end
      buffer[tag].enq(SortedPacket{d: d, first: first, last: last});
   endrule
   
   
   function PipeOut#(SortedPacket#(vSz, iType)) genPipeOut(Integer tag);
      return (interface PipeOut;
                 method SortedPacket#(vSz, iType) first;
                    return buffer[tag].first;
                 endmethod
                 method Action deq;
                    buffer[tag].deq;
                    credit[tag][1] <= credit[tag][1] + 1;
                 endmethod
                 method Bool notEmpty;
                    return buffer[tag].notEmpty;
                 endmethod
              endinterface);
   endfunction
   

   function mapToPipeIn(fifos) = map(toPipeIn, fifos);
   
   interface inPipes = map(mapToPipeIn,inQs);
   interface outPipes = genWith(genPipeOut);
      
endmodule
