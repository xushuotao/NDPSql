import Pipe::*;
import Vector::*;
import FIFOF::*;
import BuildVector::*;

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
