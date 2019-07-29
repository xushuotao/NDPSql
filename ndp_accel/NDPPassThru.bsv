import NDPCommon::*;
import Pipe::*;
import FIFOF::*;

(* synthesize *)
module mkNDPPassThru(NDPAccel);
   FIFOF#(RowData) inData <- mkFIFOF;
   FIFOF#(RowMask) inMask <- mkFIFOF;
   
   
   interface NDPStreamIn streamIn = toNDPStreamIn(inData, inMask);
   
   interface NDPStreamOut streamOut = toNDPStreamOut(inData, inMask);

   interface NDPConfigure configure;
      method Action setColBytes(Bit#(5) colBytes);
         noAction;
      endmethod
      method Action setParameters(ParamT paras);
            noAction;
      endmethod
   endinterface
endmodule// mkNDPPassThru
