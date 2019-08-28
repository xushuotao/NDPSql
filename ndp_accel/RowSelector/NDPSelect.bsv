import ISSPTypes::*;
import NDPCommon::*;
import Vector::*;
import FIFO::*;
import FIFOF::*;
import GetPut::*;
import AlgFuncs::*;
import Select::*;
import NDPPassThru::*;
import BuildVector::*;

import OneToNRouter::*;

import Pipe::*;
import Connectable::*;

function Bool unsignedTest(Bit#(sz) in,  Bit#(sz) lv, Bit#(sz) hv);
   return in >= lv && in <= hv;
endfunction
   
function Bool signedTest(Bit#(sz) in,  Bit#(sz) lv, Bit#(sz) hv);
   return signedLE(lv,in) && signedLE(in,hv);
endfunction


function Vector#(n, Tuple2#(Bool, Bit#(sz))) evalPred(Vector#(n, Bit#(sz)) inV, Bit#(sz) lv, Bit#(sz) hv, Bool isSigned);
    Vector#(n, Bit#(sz)) lvVec = replicate(lv);
    Vector#(n, Bit#(sz)) hvVec = replicate(hv);
   
    if (isSigned)
       return zipWith(tuple2, zipWith3(signedTest, inV,  lvVec, hvVec), inV);
    else
       return zipWith(tuple2, zipWith3(unsignedTest, inV,  lvVec, hvVec), inV);
endfunction



(*synthesize*)
module mkNDPSelect(NDPAccel);
   
   let passThru <- mkNDPPassThru;
   
   Select#(1) select_char <- mkSelect;
   Select#(2) select_short <- mkSelect;
   Select#(4) select_int <- mkSelect;
   Select#(8) select_long <- mkSelect;
   Select#(16) select_bigint <- mkSelect;
   
   Vector#(6, NDPStreamIn) select_streamIns = vec(passThru.streamIn,
                                                  select_char.streamIn,
                                                  select_short.streamIn,
                                                  select_int.streamIn,
                                                  select_long.streamIn,
                                                  select_bigint.streamIn);
   
   Vector#(6, NDPStreamOut) select_streamOuts = vec(passThru.streamOut,
                                                   select_char.streamOut,
                                                   select_short.streamOut,
                                                   select_int.streamOut,
                                                   select_long.streamOut,
                                                   select_bigint.streamOut);
   
   
   Reg#(Bit#(3)) sel <- mkReg(1);
   /*
   function Tuple2#(Bit#(3), d) toRouter(d) = tuple2(sel, d);
   
   OneToNRouter#(6, RowMask) rowMaskRouter <- mkOneToNRouterPipelined;
   OneToNRouter#(6, RowData) rowDataRouter <- mkOneToNRouterPipelined;
   
   
   function NDPStreamOut combineIfc(PipeOut#(RowData) a, PipeOut#(RowMask) b);
      return (interface NDPStreamOut;
                 interface rowData = a;
                 interface rowMask = b;
              endinterface);
   endfunction
   
   
   function PipeOut#(RowMask) extractRowMask(NDPStreamOut a) = a.rowMask;
   function PipeOut#(RowData) extractRowData(NDPStreamOut a) = a.rowData;
   
   Vector#(6, NDPStreamOut) outs = zipWith(combineIfc, rowDataRouter.outPorts, rowMaskRouter.outPorts);
   zipWithM_(mkConnection, outs, select_streamIns);
      
   FunnelPipe#(1, 6, RowMask, 1) out_mask <- mkFunnelPipesPipelined(map(extractRowMask, select_streamOuts));
   FunnelPipe#(1, 6, RowData, 1) out_data <- mkFunnelPipesPipelined(map(extractRowData, select_streamOuts));

   interface NDPStreamIn streamIn;// = select_streamIns[sel];
      interface PipeIn rowData = mapPipeIn(toRouter, rowDataRouter.inPort);
      interface PipeIn rowMask = mapPipeIn(toRouter, rowMaskRouter.inPort);
   endinterface

   interface NDPStreamOut streamOut = combineIfc(out_data[0], out_mask[0]);// = select_streamOuts[sel];
  */
   
   interface NDPStreamIn streamIn = select_streamIns[sel];
   interface NDPStreamOut streamOut = select_streamOuts[sel];

   interface NDPConfigure configure;
      method Action setColBytes(Bit#(5) colBytes);
         $display("(%m) setColBytes = %d", colBytes);
         sel <= (case (colBytes)
                    0: 0;
                    1: 1;
                    2: 2;
                    4: 3;
                    8: 4;
                    16: 5;
                 endcase);

      endmethod
      method Action setParameters(ParamT paras);
         select_char.configure.setParameters(paras);
         select_short.configure.setParameters(paras);
         select_int.configure.setParameters(paras);
         select_long.configure.setParameters(paras);
         select_bigint.configure.setParameters(paras);
      endmethod
   endinterface

endmodule
