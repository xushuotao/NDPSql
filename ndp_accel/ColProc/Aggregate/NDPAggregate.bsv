import Pipe::*;
import Vector::*;
import ISSPTypes::*;
import NDPCommon::*;
import NDPPassThru::*;
import Aggregate::*;
import BuildVector::*;

interface NDPAggregate;
   interface NDPStreamIn streamIn;
   interface PipeOut#(AggrResp) aggrResp;
   interface NDPConfigure configure;
endinterface

function PipeOut#(AggrResp) takeAggrResp(NDPAggregate ifc) = ifc.aggrResp;

(*synthesize*)
module mkNDPAggregate(NDPAggregate);
   
   let passThru <- mkNDPPassThru;
   Aggregate#(1) aggregate_char <- mkAggregate(False);
   Aggregate#(2) aggregate_short <- mkAggregate(False);
   Aggregate#(4) aggregate_uint <- mkAggregate(False);
   Aggregate#(8) aggregate_ulong <- mkAggregate(False);
   Aggregate#(16) aggregate_bigint <- mkAggregate(False);
   
   Aggregate#(4) aggregate_int <- mkAggregate(True);
   Aggregate#(8) aggregate_long <- mkAggregate(True);

   
   Vector#(8, NDPStreamIn) aggregate_streamIns = vec(passThru.streamIn,         // 0
                                                     aggregate_char.streamIn,   // 1
                                                     aggregate_short.streamIn,  // 2
                                                     aggregate_uint.streamIn,   // 3
                                                     aggregate_ulong.streamIn,  // 4
                                                     aggregate_bigint.streamIn, // 5
                                                     aggregate_int.streamIn,    // 6
                                                     aggregate_long.streamIn);  // 7
   rule doEmptyRule;
      if ( passThru.streamOut.rowMask.notEmpty) begin
         passThru.streamOut.rowMask.deq;
      end
      if ( passThru.streamOut.rowData.notEmpty) begin
         passThru.streamOut.rowData.deq;
      end
   endrule
   
   PipeOut#(AggrResp) emptyResult = (interface PipeOut#(AggrResp)
                                        method AggrResp first if (False);
                                           return ?;
                                        endmethod
                                        method Bool notEmpty = False;
                                        method Action deq if (False);
                                           noAction;
                                        endmethod
                                     endinterface);
      
   
   Vector#(8, PipeOut#(AggrResp)) aggregate_aggrResult = vec(emptyResult,               // 0
                                                             aggregate_char.aggrResp,   // 1
                                                             aggregate_short.aggrResp,  // 2
                                                             aggregate_uint.aggrResp,   // 3
                                                             aggregate_ulong.aggrResp,  // 4
                                                             aggregate_bigint.aggrResp, // 5
                                                             aggregate_int.aggrResp,    // 6
                                                             aggregate_long.aggrResp);  // 7
   
   
   Reg#(Bit#(3)) sel <- mkReg(0);
   
   interface NDPStreamIn streamIn = aggregate_streamIns[sel];
   interface PipeOut aggrResp = aggregate_aggrResult[sel];

   interface NDPConfigure configure;
      method Action setColBytes(Bit#(5) colBytes);
         $display("(%m) NDPAggregate setColBytes = %d", colBytes);
         sel <= (case (colBytes)
                    0: 0;
                    1: 1;
                    2: 2;
                    4: 3;
                    8: 4;
                    16: 5;
                 endcase);
         aggregate_char.reset;
         aggregate_short.reset;
         aggregate_uint.reset;
         aggregate_ulong.reset;
         aggregate_bigint.reset;
      endmethod
      method Action setParameters(ParamT paras);
         $display("(%m) NDPAggregate setParamaters isSigned = %d", paras[0][0]);
         // isSigned
         if ( paras[0][0] == 1) begin
            sel <= (case (sel)
                       3: 6;
                       4: 7;
                       default sel;
                    endcase);
         end
         aggregate_int.reset;
         aggregate_long.reset;
      endmethod
   endinterface
endmodule

