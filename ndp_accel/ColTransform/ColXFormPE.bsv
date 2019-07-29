import NDPCommon::*;
import FIFO::*;
import FIFOF::*;
import Pipe::*;
import SimdAlu256::*;
import Vector::*;
import RegFile::*;
import SimdAddSub128::*;
import SimdMul64::*;
import SimdTypeCast::*;
import GetPut::*;
import Assert::*;

interface ColXFormPE;
   interface PipeIn#(RowData) inPipe;
   interface PipeOut#(RowData) outPipe;
   interface PipeIn#(Tuple3#(Bit#(3), Bool, Bit#(32))) programPort;
endinterface

typedef enum {
   Pass = 0,
   Copy = 1, 
   Store = 2,
   AluImm = 3, 
   Alu = 4,
   Cast = 5
   } InstType deriving (Bits, Eq, FShow);

typedef struct {
   InstType iType;  // 3-bit
   AluOp aluOp;     // 2-bit
   Bool isSigned;   // 1-bit 
   ColType colType; // 3-bit
   ColType strType; // 3-bit total 12-bit
   Bit#(20) imm;    // 20-bit
   } DecodeInst deriving (Bits, Eq, FShow);  // 32-bit instr


typedef struct {
   InstType iType; // 3-bit
   AluOp aluOp;    // 2-bit
   Bit#(256) immVec;
   Bit#(256) opVector;
   ColType colType; // 3-bit
   Bool isSigned;
   } D2E deriving (Bits, Eq, FShow);

typedef struct {
   InstType iType; // 3-bit
   Bit#(256) opVector;
   } E2W deriving (Bits, Eq, FShow);

(* synthesize *)
module mkColXFormPE(ColXFormPE);
   FIFOF#(RowData) inQ <- mkFIFOF;
   FIFOF#(RowData) outQ <- mkFIFOF;
   
   RegFile#(Bit#(3), DecodeInst) iMem <- mkRegFileFull;
   Reg#(Bit#(3)) pc <- mkReg(0);
   FIFO#(DecodeInst) f2e <- mkFIFO;
   FIFO#(D2E) d2e <- mkFIFO;
   SimdAlu256 alu <- mkSimdAlu256;
   FIFO#(E2W) e2w <- mkSizedFIFO(valueOf(TAdd#(TMax#(AddSubLatency, IntMulLatency),1)));
   FIFO#(RowData) operandQ <- mkSizedFIFO(valueOf(TAdd#(TMax#(AddSubLatency, IntMulLatency),17)));
   
   Reg#(Bit#(3)) pcMax <- mkRegU;
   
   // Reg#(Bit#(1)) beatCnt <- mkReg(0);
   Reg#(Bit#(128)) castTemp <- mkRegU;
   Reg#(CastOp) castOp <- mkRegU;
   Reg#(Bool) isCopy <- mkRegU;
   
   Reg#(Bit#(5)) beatCnt <- mkReg(0);
   
   // Reg#(Bit#(4)) beatCnt 
   
   rule doFetchDecode;// if ( beatCnt == 0);
      let inst = iMem.sub(pc);
      $display("%m, doFetch, pc = %d, inst =", pc, fshow(inst));

      let opVector <- toGet(inQ).get;
      
      
      Bit#(256) imm = ?;
      case (inst.colType)
         Byte:
         begin
            Vector#(32, Bit#(8)) immV = replicate(truncate(inst.imm));
            imm = pack(immV);
         end
         Short:
         begin
            Vector#(16, Bit#(16)) immV = replicate(truncate(inst.imm));
            imm = pack(immV);
         end
         Int:
         begin
            Vector#(8, Bit#(32)) immV = replicate(inst.isSigned?signExtend(inst.imm): zeroExtend(inst.imm));
            imm = pack(immV);
         end
         Long:
         begin
            Vector#(4, Bit#(64)) immV = replicate(inst.isSigned?signExtend(inst.imm): zeroExtend(inst.imm));
            imm = pack(immV);
         end
         Long:
         begin
            Vector#(2, Bit#(128)) immV = replicate(inst.isSigned?signExtend(inst.imm): zeroExtend(inst.imm));
            imm = pack(immV);
         end
      endcase
      
      d2e.enq(D2E{iType:    inst.iType,
                  aluOp:    inst.aluOp,
                  immVec:   imm,
                  opVector: opVector,
                  colType:  inst.colType,
                  isSigned: inst.isSigned});

      
      if ( inst.iType == Copy || inst.iType == Store ) begin
         if ( inst.strType == inst.colType) begin
            operandQ.enq(opVector);
         end
         else if ( inst.strType == Long && inst.colType == BigInt ) begin
            let d = downCastFunc(opVector, BigInt_Long);
            castTemp <= fromMaybe(?, d);
            if ( beatCnt[0] == 1) begin
               dynamicAssert(isValid(d), "DownCastOp is not supported");
               operandQ.enq({fromMaybe(?, d), castTemp});
            end
         end
         else if ( inst.strType == Int && inst.colType == Long ) begin
            let d = downCastFunc(opVector, Long_Int);
            castTemp <= fromMaybe(?, d);
            if ( beatCnt[0] == 1) begin
               dynamicAssert(isValid(d), "DownCastOp is not supported");
               operandQ.enq({fromMaybe(?, d), castTemp});
            end
         end
      end
      
      Bit#(6) numBeats = toBeatsPerRowVec(inst.colType);
      if ( zeroExtend(beatCnt) + 1 == numBeats ) begin
         beatCnt <= 0;
         if ( pc < pcMax )
            pc <= pc + 1;
         else
            pc <= 0;
      end
      else begin
         beatCnt <= beatCnt + 1;
      end

   endrule
   
   
   // rule doFetchSecondBeat if (beatCnt == 1);
   //    beatCnt <= 0;
      
   //    let opVector <- toGet(inQ).get;
   //    let d = downCastFunc(opVector, castOp);
   //    $display("doFetchSecondBeat downcasting");
   //    dynamicAssert(isValid(d), "DownCastOp is not supported");
   //    operandQ.enq({fromMaybe(?, d), castTemp});
      
            
   //    d2e.enq(D2E{iType:    isCopy? Copy: Store,
   //                aluOp:    ?,
   //                immVec:   ?,
   //                opVector: opVector,
   //                colType:  ?,
   //                isSigned: ?});

      
   // endrule
      
   rule doExecute;
      let eInst <- toGet(d2e).get;
      e2w.enq(E2W{iType: eInst.iType,
                  opVector: eInst.opVector});
      
      if ( eInst.iType == Alu ) begin
         let vec2 <- toGet(operandQ).get;
         alu.start(vec2, eInst.opVector, eInst.aluOp, unpack(pack(eInst.colType)), eInst.isSigned);
      end
      else if ( eInst.iType == AluImm ) begin
         alu.start(eInst.immVec, eInst.opVector, eInst.aluOp, unpack(pack(eInst.colType)), eInst.isSigned);
      end
   endrule
   
   Reg#(Bool) doLower <- mkReg(True);
   Reg#(Bit#(256)) upBeat <- mkRegU;
   rule doWrite if ( doLower);
      let d <- toGet(e2w).get;
      
      Bool doLower_wire = doLower;
      Bit#(256) outBeat = d.opVector;
      
      if ( d.iType == Alu || d.iType == AluImm ) begin
         let {result, half} <- alu.result;
         doLower_wire = half;
         outBeat = result[0];
         upBeat <= result[1];
      end
      
      doLower <= doLower_wire;
      if ( d.iType != Store ) begin
         outQ.enq(outBeat);
      end
      
      $display("doLowWrite");
   endrule
   
   
   rule doUpWrite if (!doLower);
      doLower <= True;
      outQ.enq(upBeat);
      $display("doUpWrite");
   endrule
      
   interface inPipe = toPipeIn(inQ);
   interface outPipe = toPipeOut(outQ);
   interface PipeIn programPort;// = toPipeIn(progQ);
      method Action enq(Tuple3#(Bit#(3), Bool, Bit#(32)) v);
         $display("%m programPort, setting iMem = ", fshow(v));
         let {pc, setPcMax, inst} = v;
         if ( !setPcMax )
            iMem.upd(pc, unpack(inst));
         else
            pcMax <= truncate(inst-1);
      endmethod
      method Bool notFull = True;
   endinterface
endmodule
   