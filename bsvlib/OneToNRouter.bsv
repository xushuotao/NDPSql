import Pipe::*;
import Vector::*;
import GetPut::*;
import FIFOF::*;
import BuildVector::*;
import RWBramCore::*;
import SpecialFIFOs::*;

interface OneToNRouter#(numeric type n, type d);
   interface PipeIn#(Tuple2#(Bit#(TLog#(n)), d)) inPort;
   interface Vector#(n, PipeOut#(d)) outPorts;
endinterface

function Vector#(n, PipeOut#(d)) takeOutPorts(OneToNRouter#(n,d) ifc);
   return ifc.outPorts;
endfunction

module mkOneToNRouterPipelined(OneToNRouter#(n,d)) provisos(
   Bits#(d, a__),
   Add#(1, b__, n),
   Add#(1, c__, TMul#(TDiv#(n, 2), 2)),
   Add#(n, d__, TMul#(TDiv#(n, 2), 2))
   );


   FIFOF#(Tuple2#(Bit#(TLog#(n)), d)) req <- mkFIFOF;
   UnFunnelPipe#(1, n, d, 1) unfunnel <- mkUnFunnelPipesPipelinedInternal(vec(toPipeOut(req)));
   if ( valueOf(n) == 1 ) begin
      unfunnel = cons(mapPipe(tpl_2, toPipeOut(req)), ?);
   end
   interface PipeIn inPort = toPipeIn(req);
   // interface PipeIn inPort;
   //    method Action enq(Tuple2#(Bit#(TLog#(n)), d) v);
   //    if ( tpl_1(v) < fromInteger(valueOf(n)) ) 
   //       req.enq(v);
   //    else
   //       $display("out of bound %d", tpl_1(v));
   //    endmethod
   //    method Bool notFull();
   //       return req.notFull;
   //    endmethod
   // endinterface

   interface outPorts = unfunnel;
endmodule

module mkOneToNRouterBRAM(OneToNRouter#(n,d)) provisos(
   Bits#(d, a__),
   Add#(1, b__, n),
   Add#(1, c__, TMul#(TDiv#(n, 2), 2)),
   Add#(n, d__, TMul#(TDiv#(n, 2), 2))
   );

   RWBramCore#(Bit#(TLog#(n)), d) distributorBuff <- mkRWBramCore;
   
   Vector#(n, Array#(Reg#(Bit#(1)))) credit <- replicateM(mkCReg(2,1));
   Vector#(n, FIFOF#(d)) outQs <- replicateM(mkFIFOF);
   
   Reg#(Bit#(TLog#(n))) dstQ <- mkRegU;
   for (Integer i = 0; i < valueOf(n); i = i + 1 ) begin
      rule doDistrReq if ( credit[i][0] == 0 );
         distributorBuff.rdReq(fromInteger(i));
         credit[i][0] <= 1;
         // dstQ.enq(i);
         dstQ <= fromInteger(i);//.enq(i);
      endrule
      
      rule doDistrResp if ( dstQ == fromInteger(i) );
         // dstQ.deq;
         let data = distributorBuff.rdResp;
         distributorBuff.deqRdResp;
         outQs[i].enq(data);
      endrule
      
   end
   
   FIFOF#(Tuple2#(Bit#(TLog#(n)),d)) inQ <- mkFIFOF;
   rule doDistrWr if ( inQ.first matches {.dst, .data} &&& credit[dst][1] > 0) ;
      inQ.deq;
      distributorBuff.wrReq(dst, data);
      credit[dst][1] <= 0;
   endrule
   
   interface PipeIn inPort = toPipeIn(inQ);
   //    method Action enq(Tuple2#(Bit#(TLog#(n)), d) v);//
   //       when( credit[tpl_1(v)][1] == 0, noAction );
   //       let {dst, data} = v;
   //       distributorBuff.wrReq(dst, data);
   //       credit[dst][1] <= 0;
   //    endmethod
   
   //    method Bool notFull;// = (credit[tpl_1(v)][1] > 0);
   //       return True;
   //    endmethod
   // endinterface

   interface outPorts = map(toPipeOut, outQs);
   
endmodule
   
   
typeclass OneToNRouterInstance#(numeric type n, type d);
   module mkOneToNRouterDelay2(OneToNRouter#(n,d));
endtypeclass

instance OneToNRouterInstance#(2, d) provisos(
   Bits#(d, dSz)
   );
   module mkOneToNRouterDelay2(OneToNRouter#(2,d));
   
      Vector#(2, FIFOF#(d)) distr_L0 <- replicateM(mkFIFOF);
   
      interface PipeIn inPort;// = toPipeIn(inQ);
         method Action enq(Tuple2#(Bit#(TLog#(2)), d) v);//
            let {dst, payload} = v;
            distr_L0[dst].enq(payload);
         endmethod
   
         method Bool notFull;
            return True;
         endmethod
      endinterface

      interface outPorts = map(toPipeOut, distr_L0);
   
   endmodule
endinstance

instance OneToNRouterInstance#(n, d) provisos(
   Bits#(d, dSz),
   Log#(n, logn),
   NumAlias#(TDiv#(logn,2), logL0),
   NumAlias#(TSub#(logn, logL0), logL1),
   Add#(b__, logL0, logn),
   Add#(c__, logL1, logn),
   Mul#(TExp#(logL0), TExp#(logL1), n)
   );
   module mkOneToNRouterDelay2(OneToNRouter#(n,d));
   
      Vector#(TExp#(logL0), FIFOF#(Tuple2#(Bit#(logL1), d))) distr_L0 <- replicateM(mkFIFOF);
      Vector#(TExp#(logL0), Vector#(TExp#(logL1), FIFOF#(d))) distr_L1 <- replicateM(replicateM(mkFIFOF));
   
      function Bit#(logL0) toL0Addr(Bit#(logn) tag);
         return truncateLSB(tag);
      endfunction

      function Bit#(logL1) toL1Addr(Bit#(logn) tag);
         return truncate(tag);
      endfunction
   
      for (Integer i = 0; i < valueOf(TExp#(logL0)); i = i + 1 ) begin
         rule doL2Distr;
            let {dst_L1, payload} <- toGet(distr_L0[i]).get;
            distr_L1[i][dst_L1].enq(payload);
         endrule
      end

   
      interface PipeIn inPort;// = toPipeIn(inQ);
         method Action enq(Tuple2#(Bit#(TLog#(n)), d) v);//
            let {dst, payload} = v;
            let dst_L0 = toL0Addr(dst);
            let dst_L1 = toL1Addr(dst);
            distr_L0[dst_L0].enq(tuple2(dst_L1, payload));
         endmethod
   
         method Bool notFull;
            return True;
         endmethod
      endinterface

      interface outPorts = map(toPipeOut, concat(distr_L1));
   
   endmodule
endinstance


   
