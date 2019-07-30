import Vector::*;
import BuildVector::*;
import Aggregate::*;
import NDPCommon::*;
import Pipe::*;
import FIFO::*;

import "BDPI" function Bit#(32) log2_c(Bit#(32) x);
import "BDPI" function Action rand_seed();
import "BDPI" function ActionValue#(Bit#(32)) randu32(Bit#(32) dummy);
import "BDPI" function ActionValue#(Bit#(64)) randu64(Bit#(32) dummy);

typedef 8 ColBytes;
typedef TLog#(ColBytes) LgColBytes;
Integer colBytes = valueOf(ColBytes);
Bool doRandSeq = False;
Bool isSigned = True;

function Bit#(w) minSigned(Bit#(w) a, Bit#(w) b);
   Int#(w) a_int = unpack(a);
   Int#(w) b_int = unpack(b);
   return pack(min(a_int, b_int));
endfunction
                 
function Bit#(w) maxSigned(Bit#(w) a, Bit#(w) b);
   Int#(w) a_int = unpack(a);
   Int#(w) b_int = unpack(b);
   return pack(max(a_int, b_int));
endfunction

function Bit#(w) minUnSigned(Bit#(w) a, Bit#(w) b) = min(a,b);

function Bit#(w) maxUnSigned(Bit#(w) a, Bit#(w) b) = max(a,b);

                 
(* synthesize *)
module mkTb_Aggregate();
   Bit#(32) rowVecLength = 1000;
   
   Reg#(Bit#(32)) cycle <- mkReg(0);
   
   Aggregate#(ColBytes) testEng <- mkAggregate(isSigned);
   
   Reg#(Bit#(32)) maskCnt <- mkReg(0);
   Reg#(Bit#(32)) dataCnt <- mkReg(0);
   
   FIFO#(Bit#(32)) maskQ <- mkSizedFIFO(128);
   FIFO#(Bit#(256)) dataQ <- mkSizedFIFO(128);

   rule incrCycle;
      cycle <= cycle + 1;
   endrule
   
   rule testInput_mask if ( maskCnt < rowVecLength);
      let randMask <- randu32(0);
      testEng.streamIn.rowMask.enq(RowMask{rowVecId: zeroExtend(maskCnt),
                                           mask: randMask,
                                           isLast: False,
                                           hasData: True});
      $display("testInput:: maskCnt = %d, mask = %b", maskCnt, randMask);
      maskCnt <= maskCnt + 1;
      maskQ.enq(randMask);
   endrule
   
   rule testInput (dataCnt < (rowVecLength << toLgBeatsPerRowVec(toColType(fromInteger(colBytes)))) );
      Vector#(4, Bit#(64)) vals <- mapM(randu64, genWith(fromInteger));
      dataCnt <= dataCnt + 1;
      testEng.streamIn.rowData.enq(pack(vals));
      $display("testInput:: dataCnt = %d, data = ", dataCnt, fshow(vals));
      dataQ.enq(pack(vals));
   endrule

   Reg#(Bit#(32)) respCnt <- mkReg(0);   
   
   Reg#(Bit#(LgColBytes)) maskSel <- mkReg(0);
   Reg#(Bool) done <- mkReg(False);
   rule testOutput (!done);
      Vector#(ColBytes, Bit#(TDiv#(32, ColBytes))) maskV = unpack(maskQ.first);
      if ( maskSel == maxBound) maskQ.deq;
      maskSel <= maskSel + 1;
      
      Vector#(TDiv#(32, ColBytes), Bit#(TMul#(ColBytes, 8))) dataV = unpack(dataQ.first);
      dataQ.deq;
      
      Bit#(32) cnt_tester = 0;
      Bit#(TMul#(ColBytes, 8)) min_tester = isSigned? (1<<(valueOf(TMul#(ColBytes,8))-1))-1 : maxBound;
      Bit#(TMul#(ColBytes, 8)) max_tester = isSigned? (1<<(valueOf(TMul#(ColBytes,8))-1))   : minBound;
      Bit#(129) sum_tester = 0;
      
      for (Integer i = 0; i < valueOf(TDiv#(32, ColBytes)); i = i + 1) begin
         if (maskV[maskSel][i] == 1) begin
            cnt_tester = cnt_tester + 1;
            min_tester = isSigned ? minSigned(min_tester, dataV[i]): minUnSigned(min_tester, dataV[i]);
            max_tester = isSigned ? maxSigned(max_tester, dataV[i]): maxUnSigned(max_tester, dataV[i]);
            sum_tester = sum_tester + zeroExtend(dataV[i]);
         end
      end
      
      AggrResult#(ColBytes) tester = AggrResult{cnt:cnt_tester,
                                                min:min_tester,
                                                max:max_tester,
                                                sum:sum_tester
                                                };

      let testee = testEng.aggrResp.first;
      testEng.aggrResp.deq;
      $display("testOutput(@%t):: respCnt = %d, tester = ", $time, respCnt, fshow(tester));
      $display("testOutput(@%t):: respCnt = %d, testee = ", $time, respCnt, fshow(testee));
      
      if ( tester != testee ) begin
         $display("Fail: Aggregate mismatch");
         $finish();
      end
      
      if ( respCnt == (rowVecLength << toLgBeatsPerRowVec(toColType(fromInteger(colBytes)))) - 1 ) begin
         done <= True;
      end
      
      respCnt <= respCnt + 1;
      
   endrule
   
   Reg#(Bit#(32)) gapCnt <- mkReg(0);
   Bit#(32) gap = 1000;
   rule incrgapCnt ( done && gapCnt < gap);
      gapCnt <= gapCnt + 1;
      
   endrule
   
   rule checkResult (done && gapCnt == gap);     
      if ( testEng.aggrResp.notEmpty)
         $display("Fail: Aggregate number of result not match");
      else
         $display("Pass: Aggregate ");
      $finish();
   endrule

endmodule
