import DRAMControllerTypes::*;
import Vector::*;
import GetPut::*;
import FIFOF::*;
import ClientServer::*;
import ClientServerHelper::*;
import Pipe::*;
import FIFOG::*;

// import CompletionBuffer::*;
// import Cntrs::*;

import CmplBuf::*;


typedef 32 NTokens;
Integer nTokens_int = valueOf(NTokens);

interface DRAMMux#(numeric type nCli, numeric type nCtr);
   interface Vector#(nCli, Server#(Tuple2#(Bit#(TLog#(nCtr)), DDRRequest), DDRResponse)) dramServers;
   interface Vector#(nCtr, DDR4Client) dramControllers;
endinterface

module mkDRAMMux(DRAMMux#(nCli, nCtr)) provisos(
   Add#(1, a__, nCli),
   Add#(1, b__, nCtr),
   Alias#(Bit#(TLog#(nCli)), cliIdT),
   Alias#(Bit#(TLog#(nCtr)), ctrIdT),
   Alias#(Bit#(TLog#(NTokens)), tokenT)
    // Alias#(CBToken#(NTokens), tokenT)
   );
   
   Vector#(nCli, FIFOF#(Tuple2#(ctrIdT, DDRRequest))) cliReqQ <- replicateM(mkFIFOF);
   Vector#(nCli, FIFOF#(DDRResponse)) cliRespQ <- replicateM(mkFIFOF);
   

   Vector#(nCtr, FIFOF#(DDRRequest)) serReqQ <- replicateM(mkFIFOF);
   // Vector#(nCtr, FIFOF#(Tuple2#(cliIdT, tokenT))) serDestQ <- replicateM(mkUGSizedFIFOF(nTokens_int));
    Vector#(nCtr, FIFOG#(Tuple2#(cliIdT, tokenT))) serDestQ <- replicateM(mkSizedFIFOG(nTokens_int));
   Vector#(nCtr, FIFOF#(DDRResponse)) serRespQ <- replicateM(mkFIFOF);
   
   // Vector#(nCli, CompletionBuffer#(NTokens, DDRResponse)) cmplBuf <- replicateM(mkCompletionBuffer);
   // Vector#(nCli, Count#(UInt#(TLog#(TAdd#(NTokens,1))))) reqTokens <- replicateM(mkCount(fromInteger(nTokens_int)));
   Vector#(nCli, CmplBuf#(NTokens, DDRResponse)) cmplBuf <- replicateM(mkCmplBuf);

   
   function Bool fifoReady(FIFOF#(d) fifo) = fifo.notEmpty;
   function Bool fifogReady(FIFOG#(d) fifo) = fifo.canDeq;

   
   // (* descending_urgency = "doDistResp, doDistReq" *)
   
   rule doDistReq if ( fold(\|| , map(fifoReady, cliReqQ)) );
      Vector#(nCtr, Maybe#(Tuple3#(cliIdT, tokenT, DDRRequest))) memReqs = replicate(tagged Invalid);
      Bool hasAction = False;
      for (Integer i = 0; i < valueOf(nCli); i = i + 1) begin
         if ( cliReqQ[i].notEmpty ) begin
            let {ctrId,req} = cliReqQ[i].first;
            if ( !isValid(memReqs[ctrId])) begin
               hasAction = True;
               // if ( req.writeen == 0 && reqTokens[i] > 0 && serDestQ[ctrId].canEnq) begin
               // let cbToken <- cmplBuf[i].reserve.get;
               if ( req.writeen == 0 && cmplBuf[i].reserve.notEmpty && serDestQ[ctrId].canEnq ) begin
                  let cbToken = cmplBuf[i].reserve.first;
                  cmplBuf[i].reserve.deq;
                  memReqs[ctrId] = tagged Valid tuple3(fromInteger(i), cbToken, req);
                  cliReqQ[i].deq;
               end
               else if (req.writeen != 0 ) begin
                  memReqs[ctrId] = tagged Valid tuple3(fromInteger(i),  ?, req);
                  cliReqQ[i].deq;
               end
            end
         end
      end
      
      if (hasAction)
         $display("MuxReq:: ",fshow(memReqs));
      
      for (Integer i = 0; i < valueOf(nCtr); i = i + 1) begin
         if ( memReqs[i] matches tagged Valid {.cliId, .token, .request} ) begin
            serReqQ[i].enq(request);
            if ( request.writeen==0 ) begin
               serDestQ[i].enq(tuple2(cliId, token)); 
            end
         end
      end
   endrule
   
   rule doDistResp if ( fold(\|| , zipWith(\&& ,map(fifogReady, serDestQ), map(fifoReady, serRespQ))) );
      Vector#(nCli, Maybe#(Tuple2#(tokenT, DDRResponse))) memResp = replicate(tagged Invalid);
      Bool hasAction = False;
      for (Integer i = 0; i < valueOf(nCtr); i = i + 1) begin
         if ( serDestQ[i].canDeq && serRespQ[i].notEmpty ) begin
            hasAction = True;
            let {cliId, token} = serDestQ[i].first;
            let resp = serRespQ[i].first;
            if ( !isValid(memResp[cliId]) ) begin
               serDestQ[i].deq;
               serRespQ[i].deq;
               memResp[cliId] = tagged Valid tuple2(token, resp);
            end
         end
      end
      
      if (hasAction)
         $display("MuxResp:: ",fshow(memResp));
      
      for (Integer i = 0; i < valueOf(nCli); i = i + 1) begin
         if ( memResp[i] matches tagged Valid {.token, .data} ) begin
            cmplBuf[i].complete(token, data);
         // if ( memResp[i] matches tagged Valid .resp ) begin
         //     cmplBuf[i].complete.put(resp);
         end
      end
   endrule
   

   
   for (Integer i = 0; i < valueOf(nCli); i = i + 1)begin
      rule drainResp if (cmplBuf[i].drain.notEmpty);
         // reqTokens[i].incr(1);
         // let d <- cmplBuf[i].drain.get;
         cmplBuf[i].drain.deq;
         cliRespQ[i].enq(cmplBuf[i].drain.first);
      endrule
   end
   
   interface dramServers = zipWith(toServer, cliReqQ, cliRespQ);
   interface dramControllers = zipWith(toClient, serReqQ, serRespQ);
endmodule
