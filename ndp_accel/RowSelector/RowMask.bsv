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
import ISSPTypes::*;
import NDPCommon::*;

Bool debug = False;

typedef 8192 MaxRowsPerPage;

typedef 32 RowVectorSz;
typedef TMul#(PageBufSz, MaxRowsPerPage) MaxNumRows;
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
   
   interface Server#(Bit#(9), void) reserveRowVecs;
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
      if (debug) $display("doReservation, freeRows = %d", freeRows);
      lockAcqRespQ.enq(?);
   endrule
   
   interface Server reserveRowVecs = toServer(reserveReqQ, lockAcqRespQ);
   
   interface Put releaseRowVecs;
      method Action put(Bit#(9) req);
         freeRows.incr(zeroExtend(unpack(req)));
         // if (debug) $display("freeRows = %d, maxRowVecs = %d", freeRows + zeroExtend(unpack(req)), fromInteger(valueOf(MaxNumRowVectors)));
         // if ( freeRows + zeroExtend(unpack(req)) > fromInteger(valueOf(MaxNumRowVectors)) )
         //    $display("Warning:: You are releasing lock which has not been acquired");
      endmethod
   endinterface
   
   interface writePorts = genWith(genWritePort);
   interface readPorts = genWith(genReadPort);
   
endmodule
