import ISSPTypes::*;
import NDPCommon::*;
import Pipe::*;
import FIFOF::*;

(* synthesize *)
module mkNDPDrain(NDPAccel);
   FIFOF#(RowData) inData <- mkFIFOF;
   FIFOF#(RowMask) inMask <- mkFIFOF;
   
   rule doDeqData;
      inData.deq;
   endrule
   
   rule doDeqMask;
      inMask.deq;
   endrule

   interface NDPStreamOut streamIn = toNDPStreamIn(inData, inMask);
   
   interface NDPStreamOut streamOut;
      interface PipeOut rowMask;
         method RowMask first if (False);
            return ?;
         endmethod
         method Action deq if (False);
            noAction;
         endmethod
         method Bool notEmpty = False;
      endinterface
   
      interface PipeOut rowData;
         method RowData first if (False);
            return ?;
         endmethod
         method Action deq if (False);
            noAction;
         endmethod
         method Bool notEmpty = False;
      endinterface

   endinterface

   interface NDPConfigure configure;
      method Action setColBytes(Bit#(5) colBytes);
         noAction;
      endmethod
      method Action setParameters(ParamT paras);
         noAction;
      endmethod
   endinterface
endmodule// mkNDPPassThru
