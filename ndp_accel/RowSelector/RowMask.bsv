import Vector::*;
import RWBramCore::*;
import Cntrs::*;
// import ConfigCounter::*;
import ClientServer::*;
import ClientServerHelper::*;
import GetPut::*;
import FIFO::*;
import SpecialFIFOs::*;
import Assert::*;

typedef 8192 MaxRowsPerPage;

typedef 32 RowVectorSz;
typedef TMul#(128, MaxRowsPerPage) MaxNumRows;
typedef TDiv#(MaxNumRows, RowVectorSz) MaxNumRowVectors;


typedef Bit#(TLog#(MaxNumRowVectors)) RowVectorId;

typedef Bit#(RowVectorSz) RowVectorMask;

typedef TDiv#(MaxRowsPerPage, RowVectorSz) MaxRowVectorsPerPage;

typedef struct{
   RowVectorId id;
   Bit#(1) src;
   } RowMaskRead deriving (FShow, Bits, Eq);
   



typedef struct{
   Bool isMerge;
   Bit#(1) src;
   RowVectorId id;
   RowVectorMask mask;
   } RowMaskWrite deriving (FShow, Bits, Eq);
   
interface RowMaskBuff#(numeric type nSlaves);
   
   // method Action setColWidth(Bit#(5) colW);

   interface Server#(Bit#(9), void) reserveRowVecs;
   // interface Put#(void) releaseRowVecs;
   interface Put#(Bit#(9)) releaseRowVecs;
   
   interface Vector#(nSlaves, Put#(RowMaskWrite)) writePorts;
   interface Vector#(nSlaves, Server#(RowMaskRead, RowVectorMask)) readPorts;
   

endinterface


module mkRowMaskBuff(RowMaskBuff#(nSlaves));
   
   Reg#(UInt#(9)) superRowsPerPage <- mkRegU();
   Vector#(2, RWBramCore#(RowVectorId, RowVectorMask)) maskTb <- replicateM(mkRWBramCore);
   Count#(Int#(TAdd#(TLog#(MaxNumRowVectors),2))) freeRows <- mkCount(fromInteger(valueOf(MaxNumRowVectors)));

   FIFO#(void) lockAcqRespQ <- mkFIFO;
   
   Vector#(nSlaves, FIFO#(Bit#(1))) outstandingReadQ <- replicateM(mkPipelineFIFO());
   
   function Put#(RowMaskWrite) genWritePort(Integer i);
      return (interface Put#(RowMaskWrite);
                 method Action put(RowMaskWrite req);
                    maskTb[req.src].wrReq(req.id, req.mask);
                 endmethod
              endinterface);
   endfunction
   

   function Server#(RowMaskRead, RowVectorMask) genReadPort(Integer i);
      return (interface Server#(RowMaskRead, RowVectorMask);
                 interface Put request;
                    method Action put(RowMaskRead req);
                       maskTb[req.src].rdReq(req.id);
                       outstandingReadQ[i].enq(req.src);
                    endmethod
                 endinterface
                 interface Get response;
                    method ActionValue#(RowVectorMask) get();
                       let src <- toGet(outstandingReadQ[i]).get();
                       maskTb[src].deqRdResp;
                       return maskTb[src].rdResp;
                    endmethod
                 endinterface
              endinterface);
   endfunction
   
   FIFO#(Bit#(9)) reserveReqQ <- mkFIFO;
   
   rule doReservation if ( freeRows - zeroExtend(unpack(reserveReqQ.first)) >= 0 );
      let req <- toGet(reserveReqQ).get;
      freeRows.decr(zeroExtend(unpack(req)));
      lockAcqRespQ.enq(?);
   endrule
   
   interface Server reserveRowVecs = toServer(reserveReqQ, lockAcqRespQ);
   //    interface Put request;
   //    //    method Action put(Bit#(9) req);// if ( freeRows - zeroExtend(unpack(req)) >= 0 );
   //    //       when(freeRows - zeroExtend(unpack(req)) < 0, noAction);
   //    //       // dynamicAssert(freeRows - zeroExtend(unpack(req)) < 0, "freeRows cannot be less than 0");
   //    //       freeRows.decr(zeroExtend(unpack(req)));
   //    //       lockAcqRespQ.enq(?);
   //    //    endmethod
   //    // endinterface
   //    interface Get response;
   //       method ActionValue#(void) get;
   //          lockAcqRespQ.deq;
   //          return ?;
   //       endmethod
   //    endinterface
   // endinterface
   
   interface Put releaseRowVecs;
      // method Action put(void req);
      //    freeRows.incr(1);
      //    if ( freeRows + 1 > fromInteger(valueOf(MaxNumRowVectors)) )
      //       $display("Warning:: You are releasing lock which has not been acquired");
      // endmethod
      method Action put(Bit#(9) req);
         freeRows.incr(zeroExtend(unpack(req)));
         $display("freeRows = %d", freeRows + zeroExtend(unpack(req)));
         if ( freeRows + zeroExtend(unpack(req)) > fromInteger(valueOf(MaxNumRowVectors)) )
            $display("Warning:: You are releasing lock which has not been acquired");
      endmethod
   endinterface
   
   interface writePorts = genWith(genWritePort);
   interface readPorts = genWith(genReadPort);
   
endmodule
