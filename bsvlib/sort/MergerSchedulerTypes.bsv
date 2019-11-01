import Vector::*;
import Bitonic::*;
import BuildVector::*;

typedef struct {
   iType topItem;
   Bool last;
   UInt#(TLog#(numTags)) tag;
   } TaggedSchedReq#(numeric type numTags, type iType) deriving (FShow, Bits, Eq);



typedef struct {
   iType topItem;
   Bool last;
   } SchedReq#(type iType) deriving (FShow, Bits, Eq);


typedef struct{
   Bit#(1) portSel;
   Bool first;
   Bool otherDone;
   iType currMax;
   Vector#(2, UInt#(TLog#(TAdd#(sz,1)))) inflights;
   } ScheduleContext#(type iType, numeric type sz) deriving (Bits, Eq, FShow);


function UInt#(TAdd#(TLog#(numTags),1)) toTag1D(UInt#(TLog#(numTags)) tag, Bit#(1) portId);
   return unpack({pack(tag), portId});
endfunction

function ScheduleContext#(iType, sz) computeContext(ScheduleContext#(iType, sz) currCtxt, Bit#(1) port, SchedReq#(iType) req, Bool ascending) provisos (Ord#(iType));
   
   let currPort   = currCtxt.portSel;
   
   let first_all  = currCtxt.first;
   let done_other = currCtxt.otherDone;
   let done_self  = req.last;
   let vecTail    = req.topItem;
   let currMax    = currCtxt.currMax;
   
   let externallySorted = isSorted(vec(currMax, vecTail), ascending);
   

   let nextPort   = currCtxt.portSel;
   if ( first_all ) nextPort = ~port;
   else if ( done_self ) nextPort = ~currPort;
   else if ( done_other ) begin /*nothing*/ end
   else if ( externallySorted ) nextPort = ~currPort;

   currCtxt.inflights[currPort] = currCtxt.inflights[currPort] > 0 ? currCtxt.inflights[currPort]-1 : currCtxt.inflights[currPort];
   currCtxt.portSel             = nextPort;
   currCtxt.first               = done_self&&done_other;
   currCtxt.otherDone           = (!done_other&&done_self) || (done_other&&!done_self);
   currCtxt.currMax             = first_all? vecTail: getTop(vec(currMax, vecTail), ascending);

   return currCtxt;
endfunction

function Bool needDrainBuffer(ScheduleContext#(iType, sz) currCtxt);
   return currCtxt.inflights[currCtxt.portSel] > 0;
endfunction
   
   


function Bit#(1) getNextSel(Bit#(1) currPortSel, Bool first_all, Bool last_self, Bool otherDone, Bool externallySorted);
   let retVal = currPortSel;
   
   if ( first_all ) retVal = ~retVal;
   else if ( last_self ) retVal = ~retVal;
   else if ( otherDone ) begin /*nothing*/ end
   else if ( externallySorted ) retVal = ~retVal;
   
   return retVal;
endfunction
