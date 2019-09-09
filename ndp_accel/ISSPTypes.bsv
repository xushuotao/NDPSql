typedef enum {Byte=0, Short=1, Int=2, Long=3, BigInt=4} ColType deriving (Bits, FShow, Eq);

typedef 5 NDPDestCnt;
typedef enum {NDP_Drain, NDP_Group, NDP_Aggregate, NDP_Bloom, NDP_Host} NDPDest deriving (Bits, Eq, FShow);


typedef enum {
   Pass = 0,
   Copy = 1, 
   Store = 2,
   AluImm = 3, 
   Alu = 4,
   Cast = 5
   } InstType deriving (Bits, Eq, FShow);


typedef enum{Add=0, Sub=1, Mul=2, Mullo=3} AluOp deriving (Bits, Eq, FShow);

typedef struct {
   InstType iType;  // 3-bit
   ColType inType; // 3-bit
   ColType outType; // 3-bit total 12-bit
   AluOp aluOp;     // 2-bit
   Bool isSigned;   // 1-bit 
   Bit#(20) imm;    // 20-bit
   } DecodeInst deriving (Bits, Eq, FShow);  // 32-bit instr

typedef struct{
   ColType colType;
   Bit#(64) numRows;
   Bit#(64) baseAddr;
   Bool forward;
   Bool allRows;
   Bit#(1) rdPort;
   Bit#(64) lowTh;
   Bit#(64) hiTh;
   Bool isSigned;
   Bool andNotOr; 
   } RowSelectorParamT deriving (Bits, Eq, FShow);


typedef struct{
   ColType colType;
   Bit#(64) baseAddr;
   } InColParamT deriving (Bits, Eq, FShow);


typedef struct{
   ColType colType;
   NDPDest dest;
   Bool isSigned;
   } OutColParamT deriving (Bits, Eq, FShow);


interface RowSelectorProgramIfc;
   method Action setParam(Bit#(8) colId, RowSelectorParamT param);
endinterface


interface InColProgramIfc;
   method Action setDim(Bit#(64) numRows, Bit#(8) numCols);
   method Action setParam(Bit#(8) colId, InColParamT param);
endinterface

interface ColXFormProgramIfc;
   method Action setProgramLength(Bit#(8) colId, Bit#(8) progLength);
   method Action setInstruction(Bit#(32) inst);
endinterface

interface OutColProgramIfc;
   method Action setColNum(Bit#(8) numCols);
   method Action setParam(Bit#(8) colId, OutColParamT param);
endinterface

interface PageFeeder;
   method Action sendPageAddr_11(Bit#(64) pageAddr, Bool last);
   method Action sendPageAddr_10(Bit#(64) pageAddr, Bool last);
   method Action sendPageAddr_9 (Bit#(64) pageAddr, Bool last);
   method Action sendPageAddr_8 (Bit#(64) pageAddr, Bool last);
   method Action sendPageAddr_7 (Bit#(64) pageAddr, Bool last);
   method Action sendPageAddr_6 (Bit#(64) pageAddr, Bool last);   
   method Action sendPageAddr_5 (Bit#(64) pageAddr, Bool last);
   method Action sendPageAddr_4 (Bit#(64) pageAddr, Bool last);
   method Action sendPageAddr_3 (Bit#(64) pageAddr, Bool last);
   method Action sendPageAddr_2 (Bit#(64) pageAddr, Bool last);
   method Action sendPageAddr_1 (Bit#(64) pageAddr, Bool last);
   method Action sendPageAddr_0 (Bit#(64) pageAddr, Bool last);
endinterface

interface ISSPDebug;
   method Action dumpTrace_PageBuf();
endinterface

typedef struct{
   Bit#(64) sum_lo;
   Bit#(64) sum_hi;
   Bit#(64) min_lo;
   Bit#(64) min_hi;
   Bit#(64) max_lo;
   Bit#(64) max_hi;
   Bit#(64) cnt   ;
   } AggrRespTransport deriving (Bits, Eq, FShow);

interface ISSPIndication;
   method Action aggrResp(Bit#(8) colId, AggrRespTransport v);
   method Action trace_PageBuf(Bit#(8) resTag, Bit#(64) resCycle, Bit#(8) relTag, Bit#(64) relCycle);
endinterface
