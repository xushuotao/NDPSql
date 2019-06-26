import Vector::*;
import Pipe::*;
import Connectable::*;
import FIFOF::*;

typedef enum {Char, Short, Int, Long, BigInt} ColType deriving (Bits, FShow, Eq);



typedef Bit#(256) RowData;
// typedef struct{
//    Bit#(256) data;
//    Bool last;
// } RowData deriving (Bits, Eq, FShow); 

typedef struct{
   Bit#(64) rowVecId;
   Bit#(32) mask;
   } MaskData deriving (Bits, Eq, FShow);

// typedef union tagged{
//    MaskData Mask;
//    void Last;
//    } RowMask deriving (Bits, Eq, FShow);

typedef struct{
   Bit#(64) rowVecId;
   Bit#(32) mask;
   Bool isLast;
   Bool hasData;
   } RowMask deriving (Bits, Eq, FShow);



// typedef union tagged{
//    } RowVecReq deriving (Bits, Eq, FShow);
typedef struct{
   Bit#(64) numRowVecs;
   Bool maskZero;
   Bool last;
   } RowVecReq deriving (Bits, Eq, FShow);

typedef struct{
   Bit#(256) data;
   Bit#(6) bytes;
   Bool last;
   } CompactT deriving (Bits, Eq, FShow);


function ColType toColType(Bit#(5) colBytes);
   return case (colBytes)
             1: Char;
             2: Short;
             4: Int;
             8: Long;
             16: BigInt;
          endcase;
endfunction

function Bit#(3) toLgColBytes(Bit#(5) colBytes);
   return case (colBytes)
             1: 0;
             2: 1;
             4: 2;
             8: 3;
             16: 4;
          endcase;
endfunction   

function Bit#(9) toRowVecsPerPage(Bit#(5) colBytes);
   return case (colBytes )
             1: 256;
             2: 128;
             4: 64;
             8: 32;
             16: 16;
          endcase;
endfunction

function Bit#(64) toEndPageId(Bit#(64) numRows, Bit#(5) colBytes);
   Bit#(64) endRowId = numRows - 1;
   return case (colBytes )
             1: (endRowId >> 13);
             2: (endRowId >> 12);
             4: (endRowId >> 11);
             8: (endRowId >> 10);
             16:(endRowId >> 9); 
          endcase;
endfunction


interface NDPStreamIn;
   interface PipeIn#(RowData) rowData;
   interface PipeIn#(RowMask) rowMask;
endinterface

interface NDPStreamOut;
   interface PipeOut#(RowData) rowData;
   interface PipeOut#(RowMask) rowMask;
endinterface


// typedef Vector#(4, Bit#(128)) ParamT;
// typedef Vector#(4, Bit#(128)) ParamT;
typedef Vector#(4, Bit#(128)) ParamT;

interface NDPConfigure;
   method Action setColBytes(Bit#(5) colBytes);
   method Action setParameters(ParamT paras);
   // method Action set(Bit#(3) lgColbytes, ParamT param);
endinterface


instance Connectable#(PipeOut#(Bit#(5)), NDPConfigure);
   module mkConnection#(PipeOut#(Bit#(5)) pipeOut, NDPConfigure ifc)(Empty);
      rule doConn;
         let colBytes = pipeOut.first;
         pipeOut.deq;
         ifc.setColBytes(colBytes);
      endrule
   endmodule
endinstance

instance Connectable#(PipeOut#(ParamT), NDPConfigure);
   module mkConnection#(PipeOut#(ParamT) pipeOut, NDPConfigure ifc)(Empty);
      rule doConn;
         let v = pipeOut.first;
         pipeOut.deq;
         ifc.setParameters(v);
      endrule
   endmodule
endinstance



instance Connectable#(NDPStreamOut, NDPStreamIn);
   module mkConnection#(NDPStreamOut out, NDPStreamIn in)(Empty);
      mkConnection(out.rowData, in.rowData);
      mkConnection(out.rowMask, in.rowMask);
   endmodule
endinstance


interface NDPAccel;
   interface NDPStreamIn streamIn;
   interface NDPStreamOut streamOut;
   interface NDPConfigure configure;
endinterface


function NDPStreamIn toNDPStreamIn(FIFOF#(RowData) dataQ, FIFOF#(RowMask) maskQ);
   return (interface NDPStreamIn;
              interface rowData = toPipeIn(dataQ);
              interface rowMask = toPipeIn(maskQ);
           endinterface);
endfunction


function NDPStreamOut toNDPStreamOut(FIFOF#(RowData) dataQ, FIFOF#(RowMask) maskQ);
   return (interface NDPStreamOut;
              interface rowData = toPipeOut(dataQ);
              interface rowMask = toPipeOut(maskQ);
           endinterface);
endfunction
