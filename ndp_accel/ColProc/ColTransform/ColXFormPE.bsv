import NDPCommon::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Pipe::*;
import SimdAlu256::*;
import Vector::*;
import RegFile::*;
import SimdAddSub128::*;
import SimdMul64::*;
import SimdTypeCast::*;
import GetPut::*;
import Assert::*;
import ScheduleMonitor::*;
import BuildVector::*;

interface ColXFormPE;
   interface PipeIn#(Tuple2#(Bit#(64),Bool)) rowVecIn;
   interface PipeIn#(RowData) inPipe;
   interface PipeOut#(Tuple2#(Bit#(64),Bool)) rowVecOut;
   interface PipeOut#(RowData) outPipe;
   interface PipeIn#(Tuple3#(Bit#(3), Bool, Bit#(32))) programPort;
endinterface

Bool debug = False;

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
   
   Bool first;
   Tuple2#(Bit#(64),Bool) rowVecId;
   } D2E deriving (Bits, Eq, FShow);

typedef struct {
   InstType iType; // 3-bit
   Bit#(256) opVector;
   
   Bool first;
   Tuple2#(Bit#(64),Bool) rowVecId;
   } E2W deriving (Bits, Eq, FShow);

(* synthesize *)
module mkColXFormPE(ColXFormPE);
   FIFOF#(Tuple2#(Bit#(64),Bool)) rowVecInQ <- mkPipelineFIFOF;
   FIFOF#(Tuple2#(Bit#(64),Bool)) rowVecOutQ <- mkPipelineFIFOF;
   // FIFOF#(Bit#(64)) rowVecInQ <- mkFIFOF;
   // FIFOF#(Bit#(64)) rowVecOutQ <- mkFIFOF;

   FIFOF#(RowData) inQ <- mkPipelineFIFOF;
   FIFOF#(RowData) outQ <- mkPipelineFIFOF;
   
   RegFile#(Bit#(3), DecodeInst) iMem <- mkRegFileFull;
   Reg#(Bit#(3)) pc <- mkReg(0);
   // FIFO#(D2E) d2e <- mkPipelineFIFO;
   FIFO#(D2E) d2e <- mkFIFO;
   SimdAlu256 alu <- mkSimdAlu256;
   FIFO#(E2W) e2w <- mkSizedFIFO(valueOf(TAdd#(TMax#(AddSubLatency, IntMulLatency),17)));
   FIFO#(RowData) operandQ <- mkSizedFIFO(17);
   
   Reg#(Bit#(3)) pcMax <- mkRegU;
   
   Reg#(Bit#(128)) castTemp <- mkRegU;
   Reg#(CastOp) castOp <- mkRegU;
   Reg#(Bool) isCopy <- mkRegU;
   
   Reg#(Bit#(5)) beatCnt <- mkReg(0);
   
   let monitor <- mkScheduleMonitor(stdout, vec("fetch_decode", "execute", "writeback"));
   
   rule doFetchDecode;
      let inst = iMem.sub(pc);
      if (debug) $display("%m, doFetch, pc = %d, inst =", pc, fshow(inst));

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
      
      Bit#(5) numBeats = toBeatsPerRowVec(inst.colType);
      Bool last = False;
      if ( zeroExtend(beatCnt) + 1 == numBeats ) begin
         beatCnt <= 0;
         if ( pc < pcMax ) begin
            pc <= pc + 1;
         end
         else begin
            last = True;
            pc <= 0;
         end
      end
      else begin
         beatCnt <= beatCnt + 1;
      end

      Bool first = (beatCnt == 0 && pc == 0);
      
      Tuple2#(Bit#(64),Bool) rowVecId = ?;
      if ( first ) begin
         rowVecId = rowVecInQ.first;
         rowVecInQ.deq;
         monitor.record("fetch_decode", "1");
      end
      else begin
         monitor.record("fetch_decode","F");   
      end
      

      
      d2e.enq(D2E{iType:    inst.iType,
                  aluOp:    inst.aluOp,
                  immVec:   imm,
                  opVector: opVector,
                  colType:  inst.colType,
                  isSigned: inst.isSigned,
                  first: first,
                  rowVecId: rowVecId});
   endrule
      
   rule doExecute;
      let eInst <- toGet(d2e).get;
      e2w.enq(E2W{iType: eInst.iType,
                  opVector: eInst.opVector,
                  first: eInst.first,
                  rowVecId: eInst.rowVecId});
      
      monitor.record("execute", "E");
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
      
      if (d.first) rowVecOutQ.enq(d.rowVecId);
      
      monitor.record("writeback","W");
      if (debug) $display("doLowWrite");
   endrule
   
   
   rule doUpWrite if (!doLower);
      doLower <= True;
      outQ.enq(upBeat);
      if (debug) $display("doUpWrite");
      monitor.record("writeback","U");
   endrule
      
   interface rowVecIn = toPipeIn(rowVecInQ);
   interface rowVecOut = toPipeOut(rowVecOutQ);
   interface inPipe = toPipeIn(inQ);
   interface outPipe = toPipeOut(outQ);
   interface PipeIn programPort;// = toPipeIn(progQ);
      method Action enq(Tuple3#(Bit#(3), Bool, Bit#(32)) v);
         if (debug) $display("%m programPort, setting iMem = ", fshow(v));
         let {pc, setPcMax, inst} = v;
         if ( !setPcMax )
            iMem.upd(pc, unpack(inst));
         else
            pcMax <= truncate(inst-1);
      endmethod
      method Bool notFull = True;
   endinterface
endmodule
   
