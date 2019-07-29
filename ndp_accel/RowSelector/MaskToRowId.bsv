import Compaction::*;

interface MaskToRowId;
   interface PipeIn#(Tuple2#(Bit#(32), Bool)) rowMask;
   interface PipeOut#(CompactT) rowIds;
endinterface

(* synthesize *)
module mkMaskToRowId(MaskToRowId);
   
   FIFOF#(Tuple2#(Bit#(32), Bool)) rowMaskQ <- mkFIFOF;
   
   Reg#(Bit#(64)) rowOffset <- mkReg(0);

   Compaction#(Bit#(64), 32)) idCompaction <- mkCompaction;


   
   rule doRowMask;
      let {mask, last}  = rowMaskQ.enq();
      rowMaskQ.deq();
      
      rowOffset <= rowOffset + 32;
      
      Vector#(32, Bit#(64)) offsets = zipWith(add2, replicate(rowOffset), genWith(fromInteger));
      
      idCompaction.reqPipe.enq(CompactReq{data: offsets,
                                          mask: mask,
                                          last: last});
   endrule
   
   Reg#(Bit#(6)) itemCnt <- mkReg(0);
   
   FIFOF#(CompactT) outQ <- mkFIFOF;
   
   rule doRowIdOut;
      
      let d = idCompaction.respPipe.first();
      let totalItems = d.itemCnt;
      let last = d.last;
      Vector#(4, Bit#(256)) dataV =  unpack(pack(d.data));
      
      if ( itemCnt + 4 >= totalItems) begin
         idCompaction.respPipe.deq();
         itemCnt <= 0;
      end
      else begin
         itemCnt <= itemCnt + 4;
         last = False;
      end
      
      Bit#(2) sel = truncate(itemCnt >> 2);
      
      outQ.enq(Compact{data: dataV[sel],
                       bytes: itemCnt + 4 >= totalItems ? (totalItems - itemCnt)<<3: 32,
                       last: last});
      
   endrule
   
   
   
   interface PipeIn#(Tuple2#(Bit#(32), Bool)) rowMask = toPipeIn(rowMaskQ);
   interface PipeIn#(CompactT) rowIds = toPipeOut(outQ);

endmodule
