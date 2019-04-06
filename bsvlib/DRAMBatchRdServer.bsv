import ClientServer::*;
import ClientServerHelper::*;
import DRAMControllerTypes::*;
import FIFO::*;
import GetPut::*;
import Shifter::*;
import SpecialFIFOs::*;
import Vector::*;



typedef struct {
   Vector#(n, Bit#(sftWidth)) sftV;
   Vector#(n, Bit#(addrWidth)) addrV;
   } DRAMBatchRdRequest#(numeric type n, numeric type addrWidth, numeric type sftWidth) deriving (Bits, Eq, FShow);

typedef Vector#(n, Bit#(dataWidth)) DRAMBatchRdResponse#(numeric type n, numeric type dataWidth);
   
typedef Server#(DRAMBatchRdRequest#(n, addrW, sftW), DRAMBatchRdResponse#(n, dtaW)) DRAMBatchRdServer#(numeric type n, numeric type addrW, numeric type dtaW, numeric type sftW);

typedef Client#(DRAMBatchRdRequest#(n, addrW, sftW), DRAMBatchRdResponse#(n, dtaW)) DRAMBatchRdClient#(numeric type n, numeric type addrW, numeric type dtaW, numeric type sftW);


interface DRAMRdBatch#(numeric type n, numeric type addrW, numeric type dtaW, numeric type sftW);
   interface DRAMBatchRdServer#(n, addrW, dtaW, sftW) batchServer;
   interface Client#(DDRRequest, DDRResponse) ddrClient;
endinterface

Integer rdLatency = 32;

module mkDRAMBatchServer(DRAMRdBatch#(n, addrW, dtaW, sftW)) provisos(
   NumEq#(TExp#(TLog#(n)), n),
   NumAlias#(logn, TLog#(n)),
   Add#(a__, dtaW, SizeOf#(DDRResponse)),
   Add#(b__, addrW, 64),
   Add#(TMul#(TSub#(n, 1), dtaW), c__, TMul#(n, dtaW)) // isn't this is always true
   );

   FIFO#(DRAMBatchRdRequest#(n, addrW, sftW)) reqQ <- mkLFIFO;
   FIFO#(DRAMBatchRdResponse#(n, dtaW)) respQ <- mkLFIFO;
   
   Reg#(Bit#(logn)) reqSel <- mkReg(0);
   
   FIFO#(Vector#(n, Bit#(sftW))) outstandingQ <- mkSizedFIFO(rdLatency+1);
   
   FIFO#(DDRRequest) dramReqQ <- mkBypassFIFO;
   
   rule doSplitReq;
      let reqV = reqQ.first;
      reqSel <= reqSel + 1;
      
      if (reqSel == 0) begin
         outstandingQ.enq(reqV.sftV);
      end
      
      if (reqSel == -1 ) begin
         reqQ.deq;
      end
      
      dramReqQ.enq(DDRRequest{
                             writeen: 0,
                             address: extend(reqV.addrV[reqSel]),
                             datain: ? });
   endrule
   
   
   
   
   ByteShiftIfc#(DDRResponse, sftW) ddrShift <- mkPipelineRightShifter;
   
   
   Reg#(Bit#(logn)) respSel <- mkReg(0);
   // rule doSftReq;
   // endrule
   
   Reg#(Bit#(logn)) respCnt <- mkReg(0);
   
   Reg#(Bit#(TMul#(TSub#(n,1),dtaW))) tempResp <- mkRegU;
   rule doSftResp;
      let v <- ddrShift.getVal;
      
      Bit#(dtaW) newD = truncate(v);
      
      tempResp <= truncateLSB({newD,tempResp});
      
      respCnt <= respCnt + 1;
            
      if (respCnt == -1)
         respQ.enq(unpack({newD, tempResp}));
         
   endrule
      
   interface DRAMRdBatchServer batchServer = toServer(reqQ, respQ);
         
   interface Client ddrClient;
      interface Get request = toGet(dramReqQ);
      interface Put response;
         method Action put(DDRResponse dramResp);
            let sftV = outstandingQ.first;
            if (respSel == -1) outstandingQ.deq;
            respSel <= respSel + 1;
            ddrShift.rotateByteBy(dramResp, sftV[respSel]);
         endmethod
      endinterface
   endinterface
   
endmodule


   
   
   
   
   
   
