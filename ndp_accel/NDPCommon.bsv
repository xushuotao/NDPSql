import Vector::*;
import Pipe::*;
import Connectable::*;
import FIFOF::*;

typedef enum {Byte, Short, Int, Long, BigInt} ColType deriving (Bits, FShow, Eq);

typedef 29 PageBufSz;

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
   // Bit#(32) mask;
   Bit#(64) rowAggr;
   Bool last;
   } RowVecReq deriving (Bits, Eq, FShow);

typedef struct{
   Bit#(256) data;
   Bit#(6) bytes;
   Bool last;
   } CompactT deriving (Bits, Eq, FShow);


function ColType toColType(Bit#(5) colBytes);
   return case (colBytes)
             1: Byte;
             2: Short;
             4: Int;
             8: Long;
             16: BigInt;
          endcase;
endfunction

function Bit#(5) toColBytes(ColType colType);
   return case (colType)
             Byte:  1; 
             Short: 2; 
             Int:   4; 
             Long:  8; 
             BigInt:16; 
          endcase;
endfunction

function Bit#(3) toLgColBytes(Bit#(5) colBytes);
   return case (colBytes)
             1:  0;
             2:  1;
             4:  2;
             8:  3;
             16: 4;
          endcase;
endfunction   

function Bit#(9) toRowVecsPerPage(Bit#(5) colBytes);
   return case (colBytes )
             1:  256;
             2:  128;
             4:  64;
             8:  32;
             16: 16;
          endcase;
endfunction

function Bit#(9) toRowVecsPerPage2(ColType colType);
   return case (colType )
             Byte  : 256;
             Short : 128;
             Int   : 64;
             Long  : 32;
             BigInt: 16;
          endcase;
endfunction


function Bit#(3) toLgRowVecsPerPage(ColType colType);
   return case (colType )
             Byte  : 8;
             Short : 7;
             Int   : 6;
             Long  : 5;
             BigInt: 4;
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

function Bit#(64) toNumPages(Bit#(64) numRows, ColType colType);
   Bit#(64) endRowId = numRows - 1;
   Bit#(64) endPageId = case (colType)
                           Byte  : (endRowId >> 13);
                           Short : (endRowId >> 12);
                           Int   : (endRowId >> 11);
                           Long  : (endRowId >> 10);
                           BigInt: (endRowId >> 9);
                        endcase;
   return endPageId + 1;
endfunction

function Bit#(64) toNumRowVecs(Bit#(64) numRows);
   return (numRows + 31) >> 5;
endfunction

function Bit#(8) lastPageBeats(Bit#(64) numRows, ColType colType);
   Bit#(64) totalRowVecs = toNumRowVecs(numRows);
   return truncate(case (colType)
                      Byte  : (totalRowVecs);
                      Short : (totalRowVecs << 1);
                      Int   : (totalRowVecs << 2);
                      Long  : (totalRowVecs << 3);
                      BigInt: (totalRowVecs << 4);
                   endcase);
endfunction


function Bit#(5) toBeatsPerRowVec(ColType colType);
   return case (colType)
             Byte  : 1;
             Short : 2;
             Int   : 4;
             Long  : 8;
             BigInt: 16;
          endcase;
endfunction

function Bit#(4) toLgBeatsPerRowVec(ColType colType);
   return case (colType)
             Byte  : 0;
             Short : 1;
             Int   : 2;
             Long  : 3;
             BigInt: 4;
          endcase;
endfunction



interface NDPStreamIn;
   interface PipeIn#(RowData) rowData;
   interface PipeIn#(RowMask) rowMask;
endinterface

function NDPStreamIn zipNDPStreamIn(PipeIn#(RowMask) ifc0, PipeIn#(RowData) ifc1);
   return (interface NDPStreamIn;
              interface rowMask = ifc0;
              interface rowData = ifc1;
           endinterface);
endfunction


interface NDPStreamOut;
   interface PipeOut#(RowData) rowData;
   interface PipeOut#(RowMask) rowMask;
endinterface

function NDPStreamOut zipNDPStreamOut(PipeOut#(RowMask) ifc0, PipeOut#(RowData) ifc1);
   return (interface NDPStreamOut;
              interface rowMask = ifc0;
              interface rowData = ifc1;
           endinterface);
endfunction


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

function NDPStreamIn takeStreamIn(NDPAccel ifc) = ifc.streamIn;


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
