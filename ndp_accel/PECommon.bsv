import Vector::*;

typedef 256 BusWidth;
typedef Bit#(BusWidth) BusDta;

typedef 8 NumContexts;
typedef Bit#(TLog#(NumContexts)) ContextT;



interface NDPInterface;
   method Action configure(Vector#(8, Bit#(64)) para);
   method Action put(BusDta inBeat);
   method ActionValue#(BusDta) get();
endinterface


typedef struct{
   Vector#(8, Bit#(64)) data;
   Bit#(8) mask;
   Bool last;
   } FlitT deriving (Bits, Eq, FShow);

interface SingleStreamIfc;
   method Action configure(Vector#(8, Bit#(64)) para);
   method Action put(FlitT v);
   method ActionValue#(FlitT) get();
endinterface


interface DoubleStreamIfc;
   method Action put(Vector#(8, Bit#(64)) v, ContextT cxt, Bit#(1) operand);
   method ActionValue#(Tuple2#(Vector#(8, Bit#(64)),ContextT)) get();
endinterface
                                
   
                           
                             

