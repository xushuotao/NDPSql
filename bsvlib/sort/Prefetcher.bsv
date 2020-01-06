import FIFOF::*;
import Pipe::*;
import RWBramCore::*;
import Cntrs::*;
import GetPut::*;

interface Prefetcher#(numeric type fDepth, type dtype, type tagT);
   method Action start(tagT tag, Bit#(32) totalBlks);
   interface PipeOut#(Tuple2#(tagT, Bit#(32))) fetchReq;
   interface PipeIn#(dtype) fetchResp;
   interface PipeOut#(dtype) dataOut;
endinterface


module mkPrefetcher(Prefetcher#(fDepth, dtype, tagT)) provisos(
   Bits#(dtype, dSz),
   Bits#(tagT, tagSz),
   Log#(fDepth, lgfDepth),
   Alias#(Bit#(TLog#(TMul#(fDepth,2))), bufLineIdT));
   
   Integer depthInt = valueOf(fDepth);
   
   // double buffering;
   RWBramCore#(bufLineIdT, dtype) buffer <- mkRWBramCore;
   Reg#(bufLineIdT) wrPtr <- mkReg(0);
   Reg#(bufLineIdT) rdPtr <- mkReg(0);
   // Reg#(bufLineIdT) rdRespPtr <- mkReg(0);

   Count#(UInt#(2)) availCnt <- mkCount(2);
   Count#(UInt#(2)) outstandingReq <- mkCount(0);
   
   FIFOF#(Tuple2#(tagT, Bit#(32))) fetchReqQ <- mkFIFOF;
   FIFOF#(dtype) fetchRespQ <- mkFIFOF;
   
   FIFOF#(dtype) dataOutQ <- mkFIFOF;
   
   FIFOF#(Tuple2#(tagT, Bit#(32))) fetchJobQ <- mkFIFOF;
   Reg#(Bit#(32)) fetchCnt <- mkReg(0);
   
   rule issueFetchReq if ( outstandingReq < 2 && availCnt > 1 );
      let {tag, totalFetch} = fetchJobQ.first;
      if ( fetchCnt + 1 == totalFetch ) begin
         fetchJobQ.deq;
         fetchCnt <= 0;
      end
      else begin
         fetchCnt <= fetchCnt + 1;
      end
      outstandingReq.incr(1);
      availCnt.decr(1);
      fetchReqQ.enq(tuple2(tag, fetchCnt << fromInteger(valueOf(lgfDepth))));
   endrule
   
   rule buffFetchResp;
      let d <- toGet(fetchRespQ).get;
      if ( wrPtr == fromInteger(depthInt-1) || wrPtr == fromInteger(depthInt*2-1) ) begin
         outstandingReq.decr(1);
      end
      wrPtr <= wrPtr + 1;
      buffer.wrReq(wrPtr, d);
   endrule
   
   
   rule doRdReq if (rdPtr != wrPtr);
      rdPtr <= rdPtr + 1;
      if ( rdPtr == fromInteger(depthInt-1) || rdPtr == fromInteger(depthInt*2-1) ) begin
         availCnt.incr(1);
      end
      buffer.rdReq(rdPtr);
   endrule
   
   rule doRdResp if ( buffer.rdRespValid);
      let d = buffer.rdResp;
      buffer.deqRdResp;
      dataOutQ.enq(d);
   endrule

   method Action start(tagT tag, Bit#(32) totalBlks);
      fetchJobQ.enq(tuple2(tag, totalBlks));
   endmethod
   
   interface PipeOut fetchReq = toPipeOut(fetchReqQ);
   interface PipeIn fetchResp = toPipeIn(fetchRespQ);
   interface PipeOut dataOut = toPipeOut(dataOutQ);
endmodule
