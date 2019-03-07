import AlgFuncs::*;
import BuildVector::*;
import ClientServer::*;
import Connectable::*;
import FIFO::*;
import FIFOF::*;
import GetPut::*;
import PECommon::*;
import Pipe::*;
import Vector::*;

////////////////////////////////////////////////////////////////////////////////
/// Aggregate Stage: a pipeline-stage which maps an aggegration function 
///                  pair-wise on vector of size n to reduce it to size n/2 
////////////////////////////////////////////////////////////////////////////////
typedef Bit#(65) AggrWord;

interface AggrStep#(numeric type n);
   interface PipeIn#(Vector#(n, AggrWord)) request;
   interface PipeOut#(Vector#(TDiv#(n,2), AggrWord)) response;
endinterface

module mkAggrStage#(function AggrWord aggrfunc(AggrWord a, AggrWord b))(AggrStep#(n));
   FIFOF#(Vector#(TDiv#(n,2), AggrWord)) respQ <- mkFIFOF;
   interface PipeIn request;
      method Action enq(Vector#(n, AggrWord) req);
         respQ.enq(mapPairs(aggrfunc, id, req));
      endmethod
      method Bool notFull() = respQ.notFull;
   endinterface
   
   interface PipeOut response = toPipeOut(respQ);
endmodule

////////////////////////////////////////////////////////////////////////////////
/// Aggregate Unit: a pipelined module of a specific aggregation function
///                using mkAggrStage modules
////////////////////////////////////////////////////////////////////////////////


typedef struct{
   Vector#(8, AggrWord) data;
   Bit#(8) mask;
   } AggrUnitReq deriving (Bits, Eq, FShow);

interface AggrUnit;
   interface PipeIn#(AggrUnitReq) request;
   interface PipeOut#(AggrWord) response;
endinterface

module mkAggrUnit#(
   function AggrWord aggrfunc(AggrWord a, AggrWord b), AggrWord nil)(AggrUnit);
   
   FIFOF#(Vector#(8, AggrWord)) inputQ <- mkFIFOF;
   
   AggrStep#(8) stage0 <- mkAggrStage(aggrfunc);
   AggrStep#(4) stage1 <- mkAggrStage(aggrfunc);
   AggrStep#(2) stage2 <- mkAggrStage(aggrfunc);
     
   mkConnection(toPipeOut(inputQ), stage0.request);
   mkConnection(stage0.response, stage1.request);
   mkConnection(stage1.response, stage2.request);
   
   function AggrWord genInput(AggrWord v, Bool valid);
      return valid ? v : nil;
   endfunction
   
   interface PipeIn request;
      method Action enq(AggrUnitReq req);
         inputQ.enq(zipWith(genInput, req.data, unpack(req.mask)));
      endmethod
      method Bool notFull() = inputQ.notFull;
   endinterface 
   
   interface PipeOut response = mapPipe(pack, stage2.response);
endmodule

////////////////////////////////////////////////////////////////////////////////
/// Group Aggergator: A aggregator which return all aggregates per group
///                   including, min, max, sum, count
////////////////////////////////////////////////////////////////////////////////

interface GroupAggr;
   interface Put#(AggrReq) request;
   interface PipeOut#(AggrResp) response;
endinterface
   
(* synthesize *)
module mkGroupAggr(GroupAggr);
   Int#(65) minn = 1<<64;//minBound;
   Int#(65) maxx= (1<<64)-1;//maxBound;
   let minAggr <- mkAggrUnit(minSigned2, pack(maxx));
   let maxAggr <- mkAggrUnit(maxSigned2, pack(minn));
   let sumAggr <- mkAggrUnit(add, 0);
   
   FIFOF#(UInt#(4)) cntAggrQ <- mkSizedFIFOF(5); // 4-stage pipeline; +1 allow concurrent enq/deq
   
   Vector#(4, PipeOut#(AggrWord)) outpipes = vec(minAggr.response,
                                                 maxAggr.response,
                                                 sumAggr.response,
                                                 mapPipe(compose(zeroExtend, pack), toPipeOut(cntAggrQ)));
   
   PipeOut#(Vector#(4, AggrWord)) joinoutpipe <- mkJoinVector(id, outpipes);
   
   // for ( Integer i = 0; i < 4; i = i + 1 ) begin
   //    rule displaynotempty (outpipes[i].notEmpty);
   //       $display("%m, aggr_unit[%d] outpipe is not empty,  first = %h", i, outpipes[i].first);
   //    endrule
   // end
      
   
   function AggrResp toAggrResp(Vector#(4, AggrWord) v);
      return AggrResp{min: truncate(v[0]),
                      max: truncate(v[1]),
                      sum: truncate(v[2]),
                      cnt: unpack(truncate(v[3])),
                      valid: v[3][3:0] != 0
                      };
   endfunction
   
   interface Put request;
      method Action put(AggrReq req);
         let ext_data = req.isSigned? map(signExtend, req.data): map(zeroExtend, req.data);
         AggrUnitReq uReq = AggrUnitReq{data:ext_data, mask:req.mask};
         minAggr.request.enq(uReq);
         maxAggr.request.enq(uReq);
         sumAggr.request.enq(uReq);
         cntAggrQ.enq(countOnes(req.mask));
         $display("%m, put aggrReq = ", fshow(req));
         // $display("%m, put aggrunitReq = ", fshow(uReq));
      endmethod
   endinterface
      
   interface PipeOut response = mapPipe(toAggrResp, joinoutpipe);
endmodule

(* synthesize *)
module mkAggregator(AggrStreamIfc);
   Vector#(MaxGroups, GroupAggr) groupAggrs <- replicateM(mkGroupAggr);
   
   function Bool genMaskBit(GroupIdT groupid, Bool maskbit, Integer i);
      return (groupid == fromInteger(i)) && maskbit;
   endfunction
   
   function Bit#(8) genMask(Vector#(8, GroupIdT) groupIds, Bit#(8) mask, Integer i);
      return pack(zipWith3(genMaskBit, groupIds, unpack(mask), replicate(i)));
   endfunction
   
   Reg#(Vector#(MaxGroups, AggrResp)) aggrs <- mkReg(replicate(AggrResp{min:?,
                                                                        max:?,
                                                                        sum:?,
                                                                        cnt:?,
                                                                        valid:False}));
   
   function PipeOut#(AggrResp) getResponseIfc(GroupAggr ifc) = ifc.response;
   
   PipeOut#(Vector#(MaxGroups, AggrResp)) joinOutPipe <- mkJoinVector(id, map(getResponseIfc, groupAggrs));
   
   Reg#(Bool) isSignedReg <- mkRegU;
   FIFO#(Bool) isLastQ <- mkSizedFIFO(6);
   
   FIFO#(Vector#(MaxGroups, AggrResp)) resultQ <- mkFIFO;
   
   
   // for ( Integer i = 0; i < valueOf(MaxGroups); i = i + 1 ) begin
   //    rule displaynotempty (groupAggrs[i].response.notEmpty);
   //       $display("%m, groupAggr[%d] outpipe is not empty", i);
   //    endrule
   // end
   
   //// TODO:: The following conditional compared can be rid of if we store Bit#(65)
   //// Let's wait for synthesis result
   
   function Bit#(64) getMin(Bit#(64) a, Bit#(64) b);
      return isSignedReg ? minSigned2(a,b) : min(a,b);
   endfunction
   function Bit#(64) getMax(Bit#(64) a, Bit#(64) b);
      return isSignedReg ? maxSigned2(a,b) : max(a,b);
   endfunction

   
   rule updateResults;
      
      joinOutPipe.deq;
      
      function AggrResp updateAggrs(AggrResp old, AggrResp update);
         return update.valid ? (old.valid ? AggrResp{min: getMin(old.min, update.min),
                                                     max: getMax(old.max, update.max),
                                                    sum: (old.sum + update.sum),
                                                    cnt: (old.cnt + update.cnt),
                                                    valid: True} : update): old;
      endfunction

      let newAggrs = zipWith(updateAggrs, aggrs, joinOutPipe.first);
      aggrs <= newAggrs;
      
      $display("%m Get results update: ", fshow(joinOutPipe.first));
      
      let isLast <- toGet(isLastQ).get;
      if ( isLast )
         resultQ.enq(newAggrs);
   endrule
   
   method Action configure(Bool isSigned);
      aggrs <= replicate(AggrResp{min:?,
                                  max:?,
                                  sum:?,
                                  cnt:?,
                                  valid:False});

      isSignedReg <= isSigned;
      $display("%m configure");
   endmethod
   
   method Action put(FlitT v);
      Vector#(MaxGroups, Bit#(8)) masks = zipWith3(genMask, replicate(v.groupIds), replicate(v.mask), genVector());
      for (Integer i = 0; i < valueOf(MaxGroups); i = i + 1) begin
         groupAggrs[i].request.put(AggrReq{data:v.data, mask:masks[i], isSigned: isSignedReg});
      end
      isLastQ.enq(v.last);
      $display("%m put Flit = ", fshow(v));
   endmethod
   
   method ActionValue#(Vector#(MaxGroups, AggrResp)) get();
      let v <- toGet(resultQ).get;
     return v;
   endmethod
endmodule
