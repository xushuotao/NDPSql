import Pipe::*;
import Vector::*;
import FIFOF::*;
import BuildVector::*;
import RWBramCore::*;
import SpecialFIFOs::*;

interface OneToNRouter#(numeric type n, type d);
   interface PipeIn#(Tuple2#(Bit#(TLog#(n)), d)) inPort;
   interface Vector#(n, PipeOut#(d)) outPorts;
endinterface

function Vector#(n, PipeOut#(d)) takeOutPorts(OneToNRouter#(n,d) ifc) = ifc.outPorts;

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
