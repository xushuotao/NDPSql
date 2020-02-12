import FIFO::*;
import FIFOF::*;
import Pipe::*;
import RWBramCore::*;
import Cntrs::*;
import GetPut::*;
import SorterTypes::*;
import BRAMFIFOFVector::*;
import GetPut::*;
import ClientServer::*;
import Vector::*;
import RegFile::*;
import BuildVector::*;
import DelayPipe::*;
import Connectable::*;

import KeyValue::*;

interface Prefetcher#(numeric type fDepth, type dtype, type tagT);
   method Action start(tagT tag, Bit#(32) totalBlks);
   interface PipeOut#(Tuple2#(tagT, Bit#(32))) fetchReq;
   interface PipeIn#(dtype) fetchResp;
   interface PipeOut#(dtype) dataOut;
endinterface

typeclass PrefetcherInstance#(numeric type fDepth, type dtype, type tagT);
   module mkPrefetcher(Prefetcher#(fDepth, dtype, tagT)); 
endtypeclass


instance PrefetcherInstance#(fDepth, dtype, tagT) provisos(
   Bits#(dtype, dSz),
   Bits#(tagT, tagSz),
   Log#(fDepth, lgfDepth),
   Alias#(Bit#(TLog#(TMul#(fDepth,2))), bufLineIdT),
   Add#(a__, TLog#(TMul#(fDepth, 2)), TLog#(TMul#(fDepth, 4)))
   );
   module mkPrefetcher(Prefetcher#(fDepth, dtype, tagT));
      let m_ <- mkPrefetcherImpl;
      return m_;
   endmodule
endinstance

module mkPrefetcherImpl(Prefetcher#(fDepth, dtype, tagT)) provisos(
   Bits#(dtype, dSz),
   Bits#(tagT, tagSz),
   Log#(fDepth, lgfDepth),
   Alias#(Bit#(TLog#(TMul#(fDepth,2))), bufLineIdT),
   Add#(a__, TLog#(TMul#(fDepth, 2)), TLog#(TMul#(fDepth, 4)))
   );
   Integer depthInt = valueOf(fDepth);

   // double buffering;
   RWBramCore#(bufLineIdT, dtype) buffer <- mkRWBramCore;
   Reg#(Bit#(TLog#(TMul#(fDepth,4)))) wrPtr <- mkReg(0);
   Reg#(Bit#(TLog#(TMul#(fDepth,4)))) rdPtr <- mkReg(0);
   // Reg#(bufLineIdT) rdRespPtr <- mkReg(0);

   Count#(UInt#(2)) availCnt <- mkCount(2);
   Count#(UInt#(2)) outstandingReq <- mkCount(0);

   FIFOF#(Tuple2#(tagT, Bit#(32))) fetchReqQ <- mkFIFOF;
   FIFOF#(dtype) fetchRespQ <- mkFIFOF;

   FIFOF#(dtype) dataOutQ <- mkFIFOF;

   FIFOF#(Tuple2#(tagT, Bit#(32))) fetchJobQ <- mkFIFOF;
   Reg#(Bit#(32)) fetchCnt <- mkReg(0);

   rule issueFetchReq if ( availCnt > 0 );
      let {tag, totalFetch} = fetchJobQ.first;
      if ( fetchCnt + 1 == totalFetch ) begin
         fetchJobQ.deq;
         fetchCnt <= 0;
      end
      else begin
         fetchCnt <= fetchCnt + 1;
      end
      // outstandingReq.incr(1);
      availCnt.decr(1);
      fetchReqQ.enq(tuple2(tag, fetchCnt << fromInteger(valueOf(lgfDepth))));
   endrule
   
   // rule buffFetchResp;
   //    let d <- toGet(fetchRespQ).get;
   //    // if ( wrPtr == fromInteger(depthInt-1) || wrPtr == fromInteger(depthInt*2-1) ) begin
   //    //    outstandingReq.decr(1);
   //    // end
   //    wrPtr <= wrPtr + 1;
   //    buffer.wrReq(truncate(wrPtr), d);
   // endrule


   rule doRdReq if (rdPtr != wrPtr);
      rdPtr <= rdPtr + 1;
      if (rdPtr == fromInteger(depthInt-1) || rdPtr == fromInteger(2*depthInt-1) ||
          rdPtr == fromInteger(3*depthInt-1) || rdPtr == fromInteger(4*depthInt-1) ) 
         begin
            availCnt.incr(1);
         end
      buffer.rdReq(truncate(rdPtr));
   endrule

   // rule doRdResp if ( buffer.rdRespValid);
   //    let d = buffer.rdResp;
   //    buffer.deqRdResp;
   //    dataOutQ.enq(d);
   // endrule
 
   method Action start(tagT tag, Bit#(32) totalBlks);
      fetchJobQ.enq(tuple2(tag, totalBlks));
   endmethod

   interface PipeOut fetchReq = toPipeOut(fetchReqQ);
   interface PipeIn fetchResp;// = toPipeIn(fetchRespQ);
      method Action enq(dtype d);
         wrPtr <= wrPtr + 1;
         buffer.wrReq(truncate(wrPtr), d);
      endmethod
      method Bool notFull;
         return True;
      endmethod
   endinterface
   interface PipeOut dataOut;// = toPipeOut(dataOutQ);
      method Bool notEmpty;
         return buffer.rdRespValid;
      endmethod
      method dtype first;
         return buffer.rdResp;
      endmethod
      method Action deq;
         buffer.deqRdResp;
      endmethod
   endinterface
endmodule
   

//2KB
(*synthesize*)
module mkPrefetcher_32_16_uint_32_synth(Prefetcher#(32, SortedPacket#(16, UInt#(32)), Bit#(1)));
   let m_ <- mkPrefetcherImpl;
   return m_;
endmodule
instance PrefetcherInstance#(32, SortedPacket#(16, UInt#(32)), Bit#(1));
   module mkPrefetcher(Prefetcher#(32, SortedPacket#(16, UInt#(32)), Bit#(1)));
      let m_ <- mkPrefetcher_32_16_uint_32_synth;
      return m_;
   endmodule
endinstance

//1KB
(*synthesize*)
module mkPrefetcher_16_16_uint_32_synth(Prefetcher#(16, SortedPacket#(16, UInt#(32)), Bit#(1)));
   let m_ <- mkPrefetcherImpl;
   return m_;
endmodule
instance PrefetcherInstance#(16, SortedPacket#(16, UInt#(32)), Bit#(1));
   module mkPrefetcher(Prefetcher#(16, SortedPacket#(16, UInt#(32)), Bit#(1)));
      let m_ <- mkPrefetcher_16_16_uint_32_synth;
      return m_;
   endmodule
endinstance

////////////////////////////////////////////////////////////////////////////////
/// Vector Prefetcher
////////////////////////////////////////////////////////////////////////////////


typeclass VectorPrefetcherInstance#(numeric type vSz, numeric type fDepth, numeric type numFetches, type dtype, type tagT);
   module mkVectorPrefetcher(VectorPrefetcher#(vSz, fDepth, numFetches, dtype, tagT)); 
endtypeclass


instance VectorPrefetcherInstance#(vSz, fDepth, numFetches, dtype, tagT) provisos(
   Bits#(dtype, dSz),
   Bits#(tagT, tagSz),
   Mul#(fDepth, 2, bufDepth),
   Alias#(Bit#(TLog#(TMul#(fDepth,2))), bufLineIdT),
   
   Add#(1, a__, vSz),
   Add#(b__, TLog#(bufDepth), TLog#(TMul#(TExp#(TLog#(vSz)), bufDepth))),
   
   Pipe::FunnelPipesPipelined#(1, vSz, Tuple3#(Bit#(TLog#(vSz)), tagT, Bit#(TLog#(numFetches))), 1)
   
   );
   module mkVectorPrefetcher(VectorPrefetcher#(vSz, fDepth, numFetches, dtype, tagT));
      let m_ <- mkVectorPrefetcherImpl;
      return m_;
   endmodule
endinstance

interface VectorPrefetcher#(numeric type vSz, numeric type fDepth, numeric type numFetches, type dtype, type tagT);
   method Action start(tagT tag);
   interface PipeOut#(Tuple3#(Bit#(TLog#(vSz)), tagT, Bit#(TLog#(numFetches)))) fetchReq;
   interface PipeIn#(Tuple2#(Bit#(TLog#(vSz)), dtype)) fetchResp;
   interface Vector#(vSz, PipeOut#(void)) dataReady;
   // method Vector#(vSz, Bool) dataReady;
   interface Server#(UInt#(TLog#(vSz)), dtype) rdServer;
endinterface

module mkVectorPrefetcherImpl(VectorPrefetcher#(vSz, fDepth, numFetches, dtype, tagT)) provisos(
   // NumAlias#(TExp#(TLog#(vSz)), vSz),
   Bits#(dtype, dSz),
   Bits#(tagT, tagSz),
   Mul#(fDepth, 2, bufDepth),
   Alias#(Bit#(TLog#(TMul#(fDepth,2))), bufLineIdT),
   
   Add#(1, a__, vSz),
   Add#(b__, TLog#(bufDepth), TLog#(TMul#(TExp#(TLog#(vSz)), bufDepth))),
                                                                                                
   Pipe::FunnelPipesPipelined#(1, vSz, Tuple3#(Bit#(TLog#(vSz)), tagT, Bit#(TLog#(numFetches))), 1)

   );
   Integer depthInt = valueOf(fDepth);
   

   // double buffering;
   // BRAMVector#(TLog#(vSz), bufDepth, dtype) buffer <- mkUGBRAMVector;
   BRAMVector#(TLog#(vSz), bufDepth, dtype) buffer <- mkUGPipelinedBRAMVector;
   // BRAMVector#(TLog#(vSz), bufDepth, dtype) buffer <- mkUGURAMVector;
   // BRAMVector#(TLog#(vSz), bufDepth, dtype) buffer <- mkUGPipelinedURAMVector;


   Vector#(vSz, Count#(UInt#(TLog#(TAdd#(bufDepth,1))))) elemCnt <- replicateM(mkCount(0));
   Vector#(vSz, FIFOF#(void)) dataReadyQs <- replicateM(mkFIFOF);

   Vector#(vSz, Count#(UInt#(2))) availCnt <- replicateM(mkCount(2));
   
   Vector#(vSz, Reg#(Bool)) doneReg <- replicateM(mkReg(True));
   
   
   Vector#(vSz, FIFOF#(Tuple3#(Bit#(TLog#(vSz)), tagT, Bit#(TLog#(numFetches))))) fetchReqQ <- replicateM(mkFIFOF);
   
   FunnelPipe#(1, vSz, Tuple3#(Bit#(TLog#(vSz)), tagT, Bit#(TLog#(numFetches))), 1) fetchReqFunnel <- mkFunnelPipesPipelined(map(toPipeOut, fetchReqQ));

   
   FIFOF#(Tuple3#(Bit#(TLog#(vSz)), tagT, Bit#(TLog#(numFetches)))) issueQ <- mkFIFOF;
   Vector#(vSz, Reg#(Bit#(TLog#(numFetches)))) fetchCnt <- replicateM(mkReg(0));
   
   Reg#(tagT) currTag <- mkRegU;
   
   
   for (Integer i = 0; i < valueOf(vSz); i = i + 1) begin
      rule genFetchReq if ( availCnt[i] > 0 && !doneReg[i] );
         if ( fetchCnt[i] == fromInteger(valueOf(numFetches)-1) ) begin
            doneReg[i] <= True;
            fetchCnt[i] <= 0;
         end
         else begin
            fetchCnt[i] <= fetchCnt[i] + 1;
         end
         availCnt[i].decr(1);
         fetchReqQ[i].enq(tuple3(fromInteger(i), currTag, fetchCnt[i]));
         // $display("genFetchReq i = %d, availCnt = %d, fetchCnt = %d, numFetches = %d", i, availCnt[i], fetchCnt[i], valueOf(numFetches));
      endrule
      
      rule genDataReady if ( elemCnt[i] > 0 );
         elemCnt[i].decr(1);
         dataReadyQs[i].enq(?);
      endrule
   end
   

   RegFile#(UInt#(TLog#(vSz)), Bit#(TLog#(fDepth))) rdCnt <- mkRegFileFull;
   Reg#(UInt#(TLog#(vSz))) initCnt <- mkReg(0);
   Reg#(Bool) initReg <- mkReg(False);
   rule initrdCnt if ( !initReg );
      initCnt <= initCnt + 1;
      if (initCnt == maxBound) initReg <= True;
      rdCnt.upd(initCnt, 0);
   endrule
   
   FIFO#(dtype) delayPipe <- mkDelayPipeG(1);
   
   mkConnection(buffer.rdServer.response, toPut(delayPipe));
   
   // rule delayBuffer;
   //     let v <- buffer.rdServer.response.get;
   // endrule



   method Action start(tagT tag) if ( fold(\&& , readVReg(doneReg)) );
      writeVReg(doneReg, replicate(False));
      currTag <= tag;
   endmethod

   interface PipeOut fetchReq = fetchReqFunnel[0];
   
   interface PipeIn fetchResp;
      method Action enq(Tuple2#(Bit#(TLog#(vSz)), dtype) d);
         let {tag, data} = d;
         // $display("fetchResp segId = %d", tag);
         buffer.enq(data, unpack(tag));
         elemCnt[tag].incr(1);
      endmethod
      method Bool notFull;
         return True;
      endmethod
   endinterface

   // method Vector#(vSz, Bool) dataReady;
   //    function d getValue(Count#(d) cntifc) = cntifc._read;
   //    return zipWith(\> , map(getValue, elemCnt), replicate(0));
   // endmethod
   
   interface dataReady = map(toPipeOut, dataReadyQs);
   interface Server rdServer;
      interface Put request;
         method Action put(UInt#(TLog#(vSz)) tag) if (initReg);
            buffer.rdServer.request.put(tag);
            // elemCnt[tag].decr(1);
            // $display("prefetcher rdServer, elemCnt[%d] = %d", tag, elemCnt[tag]);
            let rdCntVal = rdCnt.sub(tag);
            if (rdCntVal == fromInteger(depthInt-1) ) begin
               // $display("prefetcher rdServer incr availCnt");
               availCnt[tag].incr(1);
               rdCnt.upd(tag,0);
            end
            else begin
               rdCnt.upd(tag,rdCntVal+1);
               // rdCnt[tag] <= rdCnt[tag] + 1;
            end
         endmethod
      endinterface
      interface Get response = toGet(delayPipe);
      //    method ActionValue#(dtype) get();
      //       let v <- buffer.rdServer.response.get;
      //       return v;
      //    endmethod
      // endinterface
   endinterface
   
endmodule

module mkVectorPrefetcherImplSplit(VectorPrefetcher#(vSz, fDepth, numFetches, dtype, tagT)) provisos(
   // NumAlias#(TExp#(TLog#(vSz)), vSz),
   Bits#(dtype, dSz),
   Bits#(tagT, tagSz),
   Mul#(fDepth, 2, bufDepth),
   Alias#(Bit#(TLog#(TMul#(fDepth,2))), bufLineIdT),
   
   Add#(1, a__, vSz),
   Add#(1, b__, TDiv#(vSz, 2)),
   Add#(TDiv#(vSz, 2), c__, vSz),
   Add#(1, TLog#(TDiv#(vSz, 2)), TLog#(vSz)),

   Add#(d__, TLog#(bufDepth), TLog#(TMul#(TExp#(TLog#(vSz)), bufDepth)))


   );
   Integer depthInt = valueOf(fDepth);
   

   // double buffering;
   // BRAMVector#(TLog#(vSz), bufDepth, dtype) buffer <- mkUGBRAMVector;
   BRAMVector#(TLog#(vSz), bufDepth, dtype) buffer <- mkUGPipelinedBRAMVector;
   // BRAMVector#(TLog#(vSz), bufDepth, dtype) buffer <- mkUGURAMVector;
   // BRAMVector#(TLog#(vSz), bufDepth, dtype) buffer <- mkUGPipelinedURAMVector;

   Vector#(vSz, Count#(UInt#(TLog#(TAdd#(bufDepth,1))))) elemCnt <- replicateM(mkCount(0));
   Vector#(vSz, FIFOF#(void)) dataReadyQs <- replicateM(mkFIFOF);

   Vector#(vSz, Count#(UInt#(2))) availCnt <- replicateM(mkCount(2));
   
   Vector#(vSz, Reg#(Bool)) doneReg <- replicateM(mkReg(True));
   
   
   Vector#(vSz, FIFOF#(Tuple2#(tagT, Bit#(TLog#(numFetches))))) fetchReqQ <- replicateM(mkFIFOF);
   
   FIFOF#(Tuple3#(Bit#(TLog#(vSz)), tagT, Bit#(TLog#(numFetches)))) issueQ <- mkFIFOF;
   Vector#(vSz, Reg#(Bit#(TLog#(numFetches)))) fetchCnt <- replicateM(mkReg(0));
   
   Reg#(tagT) currTag <- mkRegU;
   
   
   for (Integer i = 0; i < valueOf(vSz); i = i + 1) begin
      rule genFetchReq if ( availCnt[i] > 0 && !doneReg[i] );
         if ( fetchCnt[i] == fromInteger(valueOf(numFetches)-1) ) begin
            doneReg[i] <= True;
            fetchCnt[i] <= 0;
         end
         else begin
            fetchCnt[i] <= fetchCnt[i] + 1;
         end
         availCnt[i].decr(1);
         fetchReqQ[i].enq(tuple2(currTag, fetchCnt[i]));
         // $display("genFetchReq i = %d, availCnt = %d, fetchCnt = %d, numFetches = %d", i, availCnt[i], fetchCnt[i], valueOf(numFetches));
      endrule
      
      rule genDataReady if ( elemCnt[i] > 0 );
         elemCnt[i].decr(1);
         dataReadyQs[i].enq(?);
      endrule
   end


   function Bool fReqReady(FIFOF#(t) x) = x.notEmpty;
   
   Vector#(2, Vector#(TDiv#(vSz,2), FIFOF#(Tuple2#(tagT, Bit#(TLog#(numFetches)))))) fetchReqQsSplit = vec(take(fetchReqQ), drop(fetchReqQ));
   Vector#(2, FIFOF#(Tuple3#(Bit#(TLog#(TDiv#(vSz,2))), tagT, Bit#(TLog#(numFetches))))) issueQs <- replicateM(mkFIFOF);

   for (Integer i = 0; i < 2; i = i + 1) begin
      Vector#(TDiv#(vSz,2), Bool) canGo = map(fReqReady, fetchReqQsSplit[i]);
      Vector#(TDiv#(vSz,2), Tuple2#(Bool, Bit#(TLog#(TDiv#(vSz,2))))) indexArray = zipWith(tuple2, canGo, genWith(fromInteger));
      let port = fold(elemFind, indexArray);
      rule issueFetchReq if ( pack(canGo) != 0);
         let idx = tpl_2(port);
         fetchReqQsSplit[i][idx].deq;
         let {tag, cnt} = fetchReqQsSplit[i][idx].first;
         issueQs[i].enq(tuple3(idx, tag, cnt));
      endrule
   end   
   
   rule doIssue;
      if ( issueQs[0].notEmpty) begin
         let {idx, tag, cnt} = issueQs[0].first;
         issueQs[0].deq;
         issueQ.enq(tuple3({1'b0, idx}, tag, cnt));
      end
      else begin
         let {idx, tag, cnt} = issueQs[1].first;
         issueQs[1].deq;
         issueQ.enq(tuple3({1'b1, idx}, tag, cnt));
      end
   endrule

   // Vector#(vSz, Reg#(Bit#(TLog#(fDepth)))) rdCnt <- replicateM(mkReg(0));
   RegFile#(UInt#(TLog#(vSz)), Bit#(TLog#(fDepth))) rdCnt <- mkRegFileFull;
   Reg#(UInt#(TLog#(vSz))) initCnt <- mkReg(0);
   Reg#(Bool) initReg <- mkReg(False);
   rule initrdCnt if ( !initReg );
      initCnt <= initCnt + 1;
      if (initCnt == maxBound) initReg <= True;
      rdCnt.upd(initCnt, 0);
   endrule


   method Action start(tagT tag) if ( fold(\&& , readVReg(doneReg)) );
      writeVReg(doneReg, replicate(False));
      currTag <= tag;
   endmethod

   interface PipeOut fetchReq = toPipeOut(issueQ);
   
   interface PipeIn fetchResp;
      method Action enq(Tuple2#(Bit#(TLog#(vSz)), dtype) d);
         let {tag, data} = d;
         // $display("fetchResp segId = %d", tag);
         buffer.enq(data, unpack(tag));
         elemCnt[tag].incr(1);
      endmethod
      method Bool notFull;
         return True;
      endmethod
   endinterface

   // method Vector#(vSz, Bool) dataReady;
   //    function d getValue(Count#(d) cntifc) = cntifc._read;
   //    return zipWith(\> , map(getValue, elemCnt), replicate(0));
   // endmethod
   
   interface dataReady = map(toPipeOut, dataReadyQs);
   interface Server rdServer;
      interface Put request;
         method Action put(UInt#(TLog#(vSz)) tag) if (initReg);
            buffer.rdServer.request.put(tag);
            // elemCnt[tag].decr(1);
            // $display("prefetcher rdServer, elemCnt[%d] = %d", tag, elemCnt[tag]);
            let rdCntVal = rdCnt.sub(tag);
            if (rdCntVal == fromInteger(depthInt-1) ) begin
               // $display("prefetcher rdServer incr availCnt");
               availCnt[tag].incr(1);
               rdCnt.upd(tag,0);
            end
            else begin
               rdCnt.upd(tag,rdCntVal+1);
               // rdCnt[tag] <= rdCnt[tag] + 1;
            end
         endmethod
      endinterface
      interface Get response;
         method ActionValue#(dtype) get();
            let v <- buffer.rdServer.response.get;
            return v;
         endmethod
      endinterface
   endinterface
   
endmodule



// //4KB burst of 4MB-block
// (*synthesize*)
// module mkVectorPrefetcher_64_16_uint_32_synth(VectorPrefetcher#(256, 64, 1024, SortedPacket#(16, UInt#(32)), Bit#(1)));
//    let m_ <- mkVectorPrefetcherImpl;
//    return m_;
// endmodule
// instance VectorPrefetcherInstance#(256, 64, 1024, SortedPacket#(16, UInt#(32)), Bit#(1));
//    module mkVectorPrefetcher(VectorPrefetcher#(256, 64, 1024, SortedPacket#(16, UInt#(32)), Bit#(1)));
//       let m_ <- mkVectorPrefetcher_64_16_uint_32_synth;
//       return m_;
//    endmodule
// endinstance

//2KB burst of 4MB-block
(*synthesize*)
module mkVectorPrefetcher_32_16_uint_32_synth(VectorPrefetcher#(256, 32, 2048, SortedPacket#(16, UInt#(32)), Bit#(1)));
   let m_ <- mkVectorPrefetcherImpl;
   return m_;
endmodule
instance VectorPrefetcherInstance#(256, 32, 2048, SortedPacket#(16, UInt#(32)), Bit#(1));
   module mkVectorPrefetcher(VectorPrefetcher#(256, 32, 2048, SortedPacket#(16, UInt#(32)), Bit#(1)));
      let m_ <- mkVectorPrefetcher_32_16_uint_32_synth;
      return m_;
   endmodule
endinstance

// //1KB burst of 4MB-block
// (*synthesize*)
// module mkVectorPrefetcher_16_16_uint_32_synth(VectorPrefetcher#(256, 16, 4096, SortedPacket#(16, UInt#(32)), Bit#(1)));
//    let m_ <- mkVectorPrefetcherImpl;
//    return m_;
// endmodule
// instance VectorPrefetcherInstance#(256, 16, 4096, SortedPacket#(16, UInt#(32)), Bit#(1));
//    module mkVectorPrefetcher(VectorPrefetcher#(256, 16, 4096, SortedPacket#(16, UInt#(32)), Bit#(1)));
//       let m_ <- mkVectorPrefetcher_16_16_uint_32_synth;
//       return m_;
//    endmodule
// endinstance



//2KB burst of 4MB-block for uint64
(*synthesize*)
module mkVectorPrefetcher_32_8_uint_64_synth(VectorPrefetcher#(256, 32, 2048, SortedPacket#(8, UInt#(64)), Bit#(1)));
   let m_ <- mkVectorPrefetcherImpl;
   return m_;
endmodule
instance VectorPrefetcherInstance#(256, 32, 2048, SortedPacket#(8, UInt#(64)), Bit#(1));
   module mkVectorPrefetcher(VectorPrefetcher#(256, 32, 2048, SortedPacket#(8, UInt#(64)), Bit#(1)));
      let m_ <- mkVectorPrefetcher_32_8_uint_64_synth;
      return m_;
   endmodule
endinstance


//2KB burst of 4MB-block for kv32
(*synthesize*)
module mkVectorPrefetcher_32_8_kv32_synth(VectorPrefetcher#(256, 32, 2048, SortedPacket#(8, KVPair#(UInt#(32), UInt#(32))), Bit#(1)));
   let m_ <- mkVectorPrefetcherImpl;
   return m_;
endmodule
instance VectorPrefetcherInstance#(256, 32, 2048, SortedPacket#(8, KVPair#(UInt#(32), UInt#(32))), Bit#(1));
   module mkVectorPrefetcher(VectorPrefetcher#(256, 32, 2048, SortedPacket#(8, KVPair#(UInt#(32), UInt#(32))), Bit#(1)));
      let m_ <- mkVectorPrefetcher_32_8_kv32_synth;
      return m_;
   endmodule
endinstance


(*synthesize*)
module mkVectorPrefetcher_32_4_kv64_synth(VectorPrefetcher#(256, 32, 2048, SortedPacket#(4, KVPair#(UInt#(64), UInt#(64))), Bit#(1)));
   let m_ <- mkVectorPrefetcherImpl;
   return m_;
endmodule
instance VectorPrefetcherInstance#(256, 32, 2048, SortedPacket#(4, KVPair#(UInt#(64), UInt#(64))), Bit#(1));
   module mkVectorPrefetcher(VectorPrefetcher#(256, 32, 2048, SortedPacket#(4, KVPair#(UInt#(64), UInt#(64))), Bit#(1)));
      let m_ <- mkVectorPrefetcher_32_4_kv64_synth;
      return m_;
   endmodule
endinstance

