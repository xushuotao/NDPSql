import Pipe::*;

import FIFO::*;
import FIFOF::*;

import Vector::*;

import Connectable::*;
import GetPut::*;

import Compaction::*;


typedef struct{
   Bool isLast;
   Vector#(vSz, Tuple2#(Bool, dType)) payload;
   } IntersectStream#(numeric type vSz, type dType) deriving (Bits, Eq, FShow);


typedef struct{
   Maybe#(dType) currPri;
   IntersectStream#(vSz, dType) data;
   Bit#(vSz) mask;
   }  InterStageT#(numeric type vSz, type dType) deriving (Bits, Eq, FShow);

interface Intersect#(numeric type vSz, type dType);
   interface PipeIn#(IntersectStream#(vSz, dType)) inPipe;
   interface PipeOut#(CompactResp#(Tuple2#(Bool, dType), vSz)) outPipe;
endinterface
 
module mkIntersect(Intersect#(vSz, dType)) provisos(
   Bits#(dType, dSz),
   NumAlias#(vSz, TExp#(TLog#(vSz))),
   Add#(a__, TLog#(TAdd#(1, vSz)), TLog#(TAdd#(1, TAdd#(vSz, vSz)))),
   Add#(1, b__, vSz),
   Add#(vSz, c__, TMul#(vSz, 2)),
   Eq#(dType),
   FShow#(Intersect::InterStageT#(vSz, dType))
   );

   
   // FIFOF#(Tuple2#(Bool, Vector#(vSz, Tuple2#(Bit#(1), dType)))) inQ <- mkFIFOF;
   
   Vector#(TAdd#(vSz,1), FIFOF#(InterStageT#(vSz, dType))) pipes <- replicateM(mkFIFOF);
   
   FIFOF#(Tuple2#(Bool, Vector#(vSz, Tuple2#(Bit#(1), dType)))) outQ <- mkFIFOF;   
   
   function CompactReq#(Tuple2#(Bool, dType), vSz) toCompactReq(InterStageT#(vSz, dType) d);
      return CompactReq{data: d.data.payload,
                        mask: d.mask,
                        last: d.data.isLast};
   endfunction
   
   Compaction#(Tuple2#(Bool, dType), vSz) compactResult <- mkCompaction;
   
   mkConnection(mapPipe(toCompactReq, toPipeOut(last(pipes))), compactResult.reqPipe);
   
      
   
   for (Integer i = 0; i < valueOf(vSz); i = i + 1 ) begin
      rule doIntersect;
         let staged <- toGet(pipes[i]).get;
         $display("Intersect Stage[%d]: mask = %b ", i, staged.mask, fshow(staged));
         let currPrimary = staged.currPri;
         let mask = staged.mask;
         let payload = staged.data.payload;
         let {isPrimary, data} = payload[i];
         if ( isPrimary ) begin
            mask[i] = 0;
            currPrimary = tagged Valid data;
         end
         else if ( currPrimary matches tagged Valid .prikey) begin
            if ( prikey == data ) begin
               mask[i] = 1;
            end
            else begin
               mask[i] = 0;
            end
         end
         else begin
            mask[i] = 0;
         end
         
         staged.currPri = currPrimary;
         staged.mask = mask;

         $display("Intersect Stage[%d]: mask = %b ", i, staged.mask, fshow(staged));
         
         pipes[i+1].enq(staged);
      endrule
   end
   
   
   
   function Tuple2#(Bool, dType) findLastPrimary(Tuple2#(Bool, dType) low, Tuple2#(Bool, dType) hi);
      return tpl_1(hi) ? hi : low;
   endfunction
   
   Reg#(Tuple2#(Bool, dType)) currPriKey <- mkReg(tuple2(False,?));
   interface PipeIn inPipe;// = toPipeOut(inQ);
      method Action enq(IntersectStream#(vSz, dType) d);
         if ( d.isLast ) currPriKey <= tuple2(False,?);
         else currPriKey <= fold(findLastPrimary, cons(currPriKey, d.payload));
         pipes[0].enq(InterStageT{currPri: tpl_1(currPriKey)?tagged Valid tpl_2(currPriKey) : tagged Invalid,
                                  data: d,
                                  mask: ?});
      endmethod
      method Bool notFull = pipes[0].notFull;
   endinterface
   interface outPipe = compactResult.respPipe;
endmodule
