import FIFOF::*;
import NDPCommon::*;
import RowMask::*;
import Pipe::*;
import FIFO::*;
import GetPut::*;

Bool debug = False;

interface PredicateResult;
   interface NDPStreamIn streamIn;
   interface Get#(RowMaskWrite) rowMaskWrite;
   interface PipeOut#(RowVecReq) rowVecReq;
endinterface


(* synthesize *)
module mkPredicateResult(PredicateResult);
   FIFOF#(RowData) rowDataQ <- mkFIFOF;
   FIFOF#(RowMask) rowMaskQ <- mkFIFOF;
   
      
   FIFO#(RowMaskWrite) maskWriteQ <- mkFIFO;
   
   
   Reg#(Bit#(64)) rowVecCnt <- mkReg(0);
   
   FIFOF#(RowVecReq) rowVecReqQ <- mkFIFOF;
   
   Reg#(Bool) doLast <- mkReg(False);
  
 
   // Reg#(Maybe#(RowMask)) maskRelay <- mkReg(tagged Invalid);
   
   Reg#(Bit#(64)) lastRowVecId <- mkReg(-1);
   
   rule doRowMask;// if (!doLast);
      let d <- toGet(rowMaskQ).get;
      
      rowVecReqQ.enq(RowVecReq{numRowVecs: d.rowVecId - lastRowVecId,
                               maskZero: d.mask == 0,
                               rowAggr: pack(zeroExtend(countOnes(d.mask))),
                               last: d.isLast});
      
      if ( d.isLast ) begin
         lastRowVecId <= -1;
      end
      else begin
         lastRowVecId <= d.rowVecId;
      end
      if ( debug) $display("(%m) doRowMask = ", fshow(d));
      maskWriteQ.enq(RowMaskWrite{isMerge:False,
                                  src:0,
                                  id:truncate(d.rowVecId),
                                  mask: d.mask});

   endrule
   
   rule deqRowData;
      rowDataQ.deq;
   endrule
   
   interface NDPStreamIn streamIn = toNDPStreamIn(rowDataQ, rowMaskQ);
   
   interface Get rowMaskWrite = toGet(maskWriteQ);
   
   interface PipeOut rowVecReq = toPipeOut(rowVecReqQ);   
endmodule
