import URAMCore::*;
import Cntrs::*;
import DelayPipe::*;
import FIFOF::*;
import SpecialFIFOs::*;

interface RWUramCore#(type addrT, type dataT);
   method Action wrReq(addrT a, dataT d);
   method Action rdReq(addrT a);
   method dataT rdResp;
   method Bool rdRespValid;
   method Action deqRdResp;
endinterface


module mkRWUramCore#(Integer depth)(RWUramCore#(addrT, dataT)) provisos(
   Bits#(addrT, addrSz), Bits#(dataT, dataSz),
   Bounded#(addrT)
   );
   
   URAM_DUAL_PORT#(addrT, dataT) uram   <- mkURAMCore2(depth);
   URAM_PORT#(addrT, dataT)      wrPort = uram.a;
   URAM_PORT#(addrT, dataT)      rdPort = uram.b;
   
   DelayReg#(void) rdReqQ <- mkDelayReg(depth+1);
   
   FIFOF#(dataT) rdRespQ <- mkUGSizedFIFOF(depth+3);
   
   Count#(UInt#(8)) credit <- mkCount(fromInteger(depth+3));
   
   rule doEnq if ( isValid(rdReqQ) );
      let rdVal = rdPort.read;
      rdRespQ.enq(rdVal);
   endrule
      
         
   method Action wrReq(addrT a, dataT d);
      wrPort.put(True, a, d);
   endmethod
   
   method Action rdReq(addrT a) if (credit>0);
      credit.decr(1);
      rdReqQ <= ?;
      rdPort.put(False, a, ?);
   endmethod
   
   method dataT rdResp if (rdRespQ.notEmpty);
      return rdRespQ.first;
   endmethod
   
   method rdRespValid = rdRespQ.notEmpty;
   
   method Action deqRdResp;
      credit.incr(1);
      rdRespQ.deq;
   endmethod
endmodule

