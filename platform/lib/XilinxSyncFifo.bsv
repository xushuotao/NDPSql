import Vector::*;
// import Clocks::*;
// import CBus::*;

// import sync fifos from Xilinx FIFO generator
interface SyncFifoImport#(numeric type w);
   method Bool full;
   method Action enq(Bit#(w) x);
   method Bool empty;
   method Bit#(w) first;
   method Action deq;
endinterface



// // generate parameterized-width fifo from fixed-with fifo
// module mkGenXilinxSyncFifo#(
//    function module#(SyncFIFOIfc#(Bit#(fifoW))) mkfifo(Clock srcClk, Reset srcRst, Clock dstClk),
//    Clock srcClk, Reset srcRst, Clock dstClk
//       )(SyncFIFOIfc#(t)) provisos(
//          Bits#(t, dataW),
//          Add#(1, a__, dataW),
//          NumAlias#(fifoNum, TDiv#(dataW, fifoW))
//          );
//                Vector#(fifoNum, SyncFIFOIfc#(Bit#(fifoW))) fifos <- replicateM(mkfifo(srcClk, srcRst, dstClk));
      
//       function Bool getNotFull(SyncFIFOIfc#(Bit#(fifoW)) ifc) = ifc.notFull;
//                Bool isNotFull = all(getNotFull, fifos);
      
//          function Bool getNotEmpty(SyncFIFOIfc#(Bit#(fifoW)) ifc) = ifc.notEmpty;
//             Bool isNotEmpty = all(getNotEmpty, fifos);
      
//             method notFull = isNotFull;
      
//             method Action enq(t x);
//                Vector#(fifoNum, Bit#(fifoW)) data = unpack(zeroExtendNP(pack(x)));
//                for(Integer i = 0; i < valueof(fifoNum); i = i+1) begin
//                   fifos[i].enq(data[i]);
//                end
//             endmethod
      
//             method notEmpty = isNotEmpty;
      
//             method t first;
//                Vector#(fifoNum, Bit#(fifoW)) data = ?;
//                for(Integer i = 0; i < valueof(fifoNum); i = i+1) begin
//                   data[i] = fifos[i].first;
//                end
//                return unpack(truncateNP(pack(data)));
//             endmethod
      
//             method Action deq;
//                for(Integer i = 0; i < valueof(fifoNum); i = i+1) begin
//                   fifos[i].deq;
//                end
//             endmethod
// endmodule

// module mkXilinxSyncFifo#(Clock srcClk, Reset srcRst, Clock dstClk)(SyncFIFOIfc#(t)) provisos(
//    Bits#(t, dataW), Add#(1, a__, dataW)
//                                                                                              );
//    SyncFIFOIfc#(t) m <- mkGenXilinxSyncFifo(mkSyncFifo_w32_d16, srcClk, srcRst, dstClk);
//    return m;
// endmodule

// module mkXilinxSyncBramFifo#(Clock srcClk, Reset srcRst, Clock dstClk)(SyncFIFOIfc#(t)) provisos(
//    Bits#(t, dataW), Add#(1, a__, dataW)
//                                                                                                  );
//    SyncFIFOIfc#(t) m <- mkGenXilinxSyncFifo(mkSyncBramFifo_w36_d512, srcClk, srcRst, dstClk);
//    return m;
// endmodule
