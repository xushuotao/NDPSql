import ISSPTypes::*;
import NDPCommon::*;
import ColXFormPE::*;
import Pipe::*;
import OneToNRouter::*;
import Vector::*;
import Connectable::*;

typedef PipeIn#(Tuple2#(Bit#(TLog#(engs)), Tuple3#(Bit#(3), Bool, Bit#(32)))) ProgramColXForm#(numeric type engs);

interface ColXForm#(numeric type engs);
   interface PipeIn#(Tuple2#(Bit#(64), Bool)) rowVecIn;
   interface PipeOut#(Tuple2#(Bit#(64), Bool)) rowVecOut;
   interface PipeIn#(RowData) inPipe;
   interface PipeOut#(RowData) outPipe;
   interface ProgramColXForm#(engs) programIfc;
endinterface


module mkColXForm(ColXForm#(engs)) provisos(
   Add#(1, a__, TMul#(TDiv#(engs, 2), 2)),
   Add#(engs, b__, TMul#(TDiv#(engs, 2), 2)));

   Vector#(engs, ColXFormPE) vPE <- replicateM(mkColXFormPE);
   
   module connectPE#(ColXFormPE pe0, ColXFormPE pe1)(Empty);
      mkConnection(pe0.rowVecOut, pe1.rowVecIn);
      mkConnection(pe0.outPipe, pe1.inPipe);
   endmodule
   
   if ( valueOf(engs) > 1 ) begin
      Vector#(TSub#(engs, 1), Empty) emptyifcs <- zipWithM(connectPE, take(vPE), tail(vPE));
   end
   
   OneToNRouter#(engs, Tuple3#(Bit#(3), Bool, Bit#(32))) programRouter <- mkOneToNRouterPipelined;
   
   function PipeIn#(Tuple3#(Bit#(3), Bool, Bit#(32))) getProgramPort(ColXFormPE pe) = pe.programPort;
   
   zipWithM_(mkConnection, programRouter.outPorts, map(getProgramPort, vPE));

   interface rowVecIn = vPE[0].rowVecIn;
   interface rowVecOut = last(vPE).rowVecOut;
   interface inPipe = vPE[0].inPipe;
   interface outPipe = last(vPE).outPipe;
   interface programIfc = programRouter.inPort;
endmodule
