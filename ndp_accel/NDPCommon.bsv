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
   Bit#(32) mask;
   Bool last;
   } RowMask deriving (Bits, Eq, FShow);

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


interface NDPStreamIn;
   interface PipeIn#(RowData) rowData;
   interface PipeIn#(RowMask) rowMask;
endinterface

interface NDPStreamOut;
   interface PipeOut#(RowData) rowData;
   interface PipeOut#(RowMask) rowMask;
endinterface


interface NDPConfigure;
   method Action setColBytes(Bit#(5) colBytes);
   method Action setParameters(Vector#(4, Bit#(128)) paras);
endinterface


// instance Connectable#(PipeOut#(Bit#(5)), NDPConfigure);
//    module mkConnection#(PipeOUt#(Bit#(5))
// endinstance


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
