import Pipe::*;
import Intersect::*;

import Connectable::*;

import Vector::*;
import FIFO::*;
import FIFOF::*;

import ClientServer::*;
import ClientServerHelper::*;

import Cntrs::*;
import Counter::*;
import BuildVector::*;
import GetPut::*;

import Randomizable::*;



import SorterTypes::*;
import MergerSchedulerTypes::*;
import MergerScheduler::*;
import MergerSMTSched::*;
import MergeSortSMTSched::*;

typedef struct{
   UInt#(32) value;
   Bit#(1) src;
   } MergeTokenT deriving(Bits, Eq, FShow);

instance Ord#(MergeTokenT) provisos (
   Alias#(MergeTokenT, data_t));
   function Bool \< (data_t x, data_t y) = (pack(x) < pack(y));
   function Bool \<= (data_t x, data_t y) = (pack(x) <= pack(y));
   function Bool \> (data_t x, data_t y) = (pack(x) > pack(y));
   function Bool \>= (data_t x, data_t y) = (pack(x) >= pack(y));
   function Ordering compare(data_t x, data_t y) = compare(pack(x), pack(y));
   function data_t min(data_t x, data_t y) = unpack(min(pack(x), pack(y)));
   function data_t max(data_t x, data_t y) = unpack(max(pack(x), pack(y)));
endinstance

instance Bounded#(MergeTokenT);
   minBound = unpack(minBound);
   maxBound = unpack(maxBound);
endinstance


typedef 8 VecSz;

Bool ascending = True;

module mkIntersectTest(Empty);
   
   MergeNSMTSched#(MergeTokenT, VecSz,1) merger <- mkMergeNSMTSched(ascending,0);
   
   
   Intersect#(VecSz, UInt#(32)) intersec <- mkIntersect;
   
   Counter#(3) outPending <- mkCounter(0);
   
   Integer testLen = 1;
   Vector#(2, Integer) streamLen = vec(8, 8);
   
   Vector#(2, FIFO#(SortedPacket#(VecSz, MergeTokenT))) delayQs <- replicateM(mkSizedFIFO(4)); 

   
   for (Integer i = 0; i < 2; i = i + 1) begin
      Reg#(Bit#(32)) testCnt <- mkReg(0);

      
      Reg#(Bit#(32)) gear <- mkReg(0);
      
      Bit#(32) vecSz = fromInteger(valueOf(VecSz));
      
      Reg#(UInt#(32)) base <- mkReg(0);

      

      rule doGenInput if ( testCnt < fromInteger(testLen) );//&& merger.in.ready[0][i].notEmpty);
         $display("(@%t)Merging[%d] Sequence = ", $time, i);
      
         Vector#(VecSz, UInt#(32)) incrV = ?;

         for (Integer j = 0; j < valueOf(VecSz); j = j + 1) begin
            let v <- rand32();
            v = v % 3;
            if ( i == 0 ) v=v+1;
            incrV[j] = unpack(v);
         end
      
         let inV = sscanl(\+ , base, incrV);
         
         $display("Input[%d]: ",i, fshow(inV));

         
         
         // merger.in.ready[0][i].deq;
         Vector#(VecSz, MergeTokenT) indata = ?;
         for (Integer j = 0; j < valueOf(VecSz); j = j + 1) begin
            indata[j] = MergeTokenT{value: inV[j], src: fromInteger(i)};
         end
      
         merger.in.scheduleReq.enq(TaggedSchedReq{tag: fromInteger(i), topItem:last(indata),last:gear+vecSz == fromInteger(streamLen[i])});
         delayQs[i].enq(SortedPacket{first: gear==0, 
                                     last: gear+vecSz == fromInteger(streamLen[i]),
                                     d: indata});
      
         if ( gear+vecSz == fromInteger(streamLen[i]) ) begin
            gear <= 0;
            testCnt <= testCnt + 1;
            base <= 0;
         end
         else begin
            gear <= gear + vecSz;
            base <= last(inV);
         end

      endrule
            
   end
   
   rule issueReq if ( merger.in.scheduleResp.notEmpty);
      merger.in.scheduleResp.deq;
      let tag = merger.in.scheduleResp.first;
      let d <- toGet(delayQs[tag]).get;
      merger.in.dataChannel.enq(TaggedSortedPacket{tag:?, packet:d});
   endrule



   
   rule doReceivScheReq if (outPending.value < 4);
      let d = merger.out.scheduleReq.first;
      merger.out.scheduleReq.deq;
      merger.out.server.request.put(?);
      outPending.up;     
   endrule
      
   function Tuple2#(Bool, UInt#(32)) cast(MergeTokenT v);
      return tuple2(!unpack(v.src), v.value);
   endfunction
   
   rule enqResult;
      let merged <- merger.out.server.response.get;
      outPending.down;
      
      $display("Merged Output: ", fshow(merged.packet));

      intersec.inPipe.enq(IntersectStream{isLast: merged.packet.last,
                                          payload: map(cast, merged.packet.d)});
   endrule
   
   rule checkResult;
      let out = intersec.outPipe.first; 
      intersec.outPipe.deq;
      $display(fshow(out));
   endrule
   
endmodule
