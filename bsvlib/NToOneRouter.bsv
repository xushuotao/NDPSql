import Vector::*;
import Pipe::*;
import Reg6375::*;

interface NToOneRouter#(numeric type n, type d);
   interface Vector#(n, PipeIn#(d)) inPorts;
   interface PipeOut#(Tuple2#(Bit#(TLog#(n)), d)) outPort;
endinterface


module mkUGNToOneRouter(NToOneRouter#(n,d)) provisos(Bits#(d, dSz));

   Vector#(n, RWire#(d)) dWires <- replicateM(mkRWire);
   Vector#(n, Reg#(d)) regV <- replicateM(mkRegU);
   
   Reg#(Bit#(TLog#(n))) sel <- mkRegU;
   Reg#(Bool) valid <- mkReg(False);
   
   function fMaybe(x) = fromMaybe(?, x);
   rule doRoute;
      function Maybe#(d) readWire(RWire#(d) x) = x.wget();
      Vector#(n, Maybe#(d)) dWireReads = map(readWire, dWires);
      
      Vector#(n, Bool) enables = map(isValid, dWireReads);
      Vector#(n, d) payloads = map(fMaybe, dWireReads);
      
      valid <= pack(enables) == 0 ? False: True;
      writeVReg(regV, payloads);
   endrule

   
   function PipeIn#(d) genPipeIn(Integer i);
      return (interface PipeIn#(d);
                 method Action enq(d v);
                    dWires[i].wset(v);
                    sel <= fromInteger(i);
                 endmethod
                 method Bool notFull = True;
              endinterface);
   endfunction
         
   interface inPorts = genWith(genPipeIn);
   
   interface PipeOut outPort;
      method Tuple2#(Bit#(TLog#(n)), d) first;
         return tuple2(sel, regV[sel]);
      endmethod
      method Action deq;
         noAction;
      endmethod
      method Bool notEmpty;
         return valid;
      endmethod
   endinterface
endmodule


// module mkNToOneRouterDelay2(NToOneRouter#(n,d)) provisos(Bits#(d, dSz));
   
//    // function PipeIn#(d) genPipeIn(Integer i);
//    //    return (interface PipeIn#(d);
//    //               method Action enq(d v);
//    //                  dWires[i].wset(v);
//    //                  sel <= fromInteger(i);
//    //               endmethod
//    //               method Bool notFull = True;
//    //            endinterface);
//    // endfunction
   
//    Vector#(n, FIFOF#(d)) inQs <- replicateM(mkFIFOF);
         
//    interface inPorts = map(toPipeIn, inQs);//= genWith(genPipeIn);
   
//    interface PipeOut outPort;
//       method Tuple2#(Bit#(TLog#(n)), d) first;
//          return tuple2(sel, regV[sel]);
//       endmethod
//       method Action deq;
//          noAction;
//       endmethod
//       method Bool notEmpty;
//          return valid;
//       endmethod
//    endinterface
// endmodule

// endmodule
