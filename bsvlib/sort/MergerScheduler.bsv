import Bitonic::*;
import Pipe::*;
import Cntrs::*;
import Vector::*;
import FIFOF::*;
import SpecialFIFOs::*;
import BuildVector::*;

Bool debug = False;

function Bit#(1) getNextSel(Bit#(1) currPortSel, Bool first_all, Bool last_self, Bool otherDone, Bool externallySorted);
   let retVal = currPortSel;
   
   if ( first_all ) retVal = ~retVal;
   else if ( last_self ) retVal = ~retVal;
   else if ( otherDone ) begin /*nothing*/ end
   else if ( externallySorted ) retVal = ~retVal;
   
   return retVal;
endfunction


interface MergerSched#(numeric type numCredits, type iType);
   interface Vector#(2, PipeOut#(void)) nextReq;
   method Action update(iType vecTail, Bool last);
   method Action incrCredit;
endinterface


module mkMergerScheduler#(Bool ascending)(MergerSched#(numCredits, iType)) provisos(Bits#(iType, iSz), Ord#(iType));
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
