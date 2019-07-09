import FIFOF::*;
import FIFO::*;
import SpecialFIFOs::*;
import Vector::*;
import GetPut::*;

function Bit#(TAdd#(n,n)) multiply_unsigned( Bit#(n) a, Bit#(n) b );
    UInt#(n) a_uint = unpack(a);
    UInt#(n) b_uint = unpack(b);
    UInt#(TAdd#(n,n)) product_uint = zeroExtend(a_uint) * zeroExtend(b_uint);
    return pack( product_uint );
endfunction
                 
function Bit#(TAdd#(n,n)) multiply_signed( Bit#(n) a, Bit#(n) b );
    Int#(n) a_int = unpack(a);
    Int#(n) b_int = unpack(b);
    Int#(TAdd#(n,n)) product_int = signExtend(a_int) * signExtend(b_int);
    return pack( product_int );
endfunction


// Multiplier Interface
interface Multiplier#( numeric type n );
    method Action start( Bit#(n) a, Bit#(n) b );
    method ActionValue#(Bit#(TAdd#(n,n))) result();
endinterface

// Folded multiplier by repeated addition
module mkFoldedMultiplier( Multiplier#(n) )
	provisos(Add#(1, a__, n)); // make sure n >= 1
    
    // You can use these registers or create your own if you want
    Reg#(Bit#(n)) a <- mkRegU();
    Reg#(Bit#(n)) b <- mkRegU();
    Reg#(Bit#(n)) prod <- mkRegU();
    Reg#(Bit#(n)) tp <- mkRegU();
    Reg#(Bit#(TAdd#(TLog#(n),1))) i <- mkReg( fromInteger(valueOf(n)+1) );
    Reg#(Bool) busy <- mkReg(False);

    rule mulStep(i < fromInteger(valueOf(n)));
        Bit#(n) m = (a[0] == 0) ? 0 : b;
        a <= a >> 1; // equivalent to a[i]==0 on the previous line, and no shifting.
        Bit#(TAdd#(n,1)) sum = zeroExtend(m) + zeroExtend(tp);
        prod <= {sum[0], prod[fromInteger(valueOf(n)-1):1]};
        tp <= sum[fromInteger(valueOf(n)):1];
        i <= i + 1;
    endrule
   
    method Action start(Bit#(n) aIn, Bit#(n) bIn) if (!busy);
        a <= aIn;
        b <= bIn;
        i <= 0;
        busy <= True;
        prod <= 0;
        tp <= 0;
    endmethod

    method ActionValue#(Bit#(TAdd#(n,n))) result() if (i == fromInteger(valueOf(n)) && busy);
        busy <= False;
        return {tp, prod};
    endmethod
endmodule

typedef struct{
   Bit#(n) a;
   Bit#(n) b;
   Bit#(n) prod;
   Bit#(n) tp;
   } MultiStage#(numeric type n) deriving (Bits, Eq, FShow);

// Pipelined multiplier by repeated addition
module mkPipelinedMultiplier( Multiplier#(n) )
   provisos(Add#(1, a__, n)); // make sure n >= 1
   
   Vector#(n, FIFO#(MultiStage#(n))) fifos <- replicateM(mkPipelineFIFO);
   
   function MultiStage#(n) multiStep(MultiStage#(n) v);
      let a = v.a;
      let b = v.b;
      let prod = v.prod;
      let tp = v.tp;
         
      Bit#(n) m = (a[0] == 0) ? 0 : b;
      a = a >> 1; // equivalent to a[i]==0 on the previous line, and no shifting.
         
      Bit#(TAdd#(n,1)) sum = zeroExtend(m) + zeroExtend(tp);
      prod = {sum[0], prod[fromInteger(valueOf(n)-1):1]};
      tp = sum[fromInteger(valueOf(n)):1];
         
      return MultiStage{a: a,
                        b: b,
                        prod: prod,
                        tp: tp};
   endfunction
   
   for (Integer i = 0; i < valueOf(n) - 1; i = i + 1) begin
      rule doMulStep;
         let v = fifos[i].first;
         fifos[i].deq;
         fifos[i+1].enq(multiStep(v));
      endrule
   end

   method Action start(Bit#(n) aIn, Bit#(n) bIn);
      let a = aIn;
      let b = bIn;
      Bit#(n) prod = 0;
      Bit#(n) tp = 0;
   
      fifos[0].enq(multiStep(MultiStage{a: a,
                                        b: b,
                                        prod: prod,
                                        tp: tp}));
   endmethod

   method ActionValue#(Bit#(TAdd#(n,n))) result();
      let v <- toGet(fifos[valueOf(n)-1]).get;
      return {v.tp, v.prod};
   endmethod
endmodule

typedef struct{
   Bit#(TAdd#(n,2)) multiplicand_X_1;// = {0, multiplicand};
   Bit#(TAdd#(n,2)) multiplicand_X_2;// = {multiplicand, 0};
   Bit#(TAdd#(n,2)) multiplicand_X_3;// = multiplicand_X_1 + multiplicand_X_2;
   Bit#(TAdd#(TAdd#(n, n), 1)) prod;
   } Radix4Unsigned#(numeric type n) deriving (Bits, Eq, FShow);

module mkRadix4UnsignedMultiplier(Multiplier#(n))
   provisos(Log#(n, logn), 
            Add#(a__,1, logn), // n >= 2
            NumAlias#(n, TExp#(TLog#(n))), // n is power of 2
            Add#(2, b__, n)
            ); // make sure n >= 2
   
   Vector#(TDiv#(n,2), FIFO#(Radix4Unsigned#(n))) fifos <- replicateM(mkPipelineFIFO);
   
   function Radix4Unsigned#(n) multiStep(Radix4Unsigned#(n) v);
      let prod = v.prod;
   
      let multiplicand_X_1 = v.multiplicand_X_1;
      let multiplicand_X_2 = v.multiplicand_X_2;
      let multiplicand_X_3 = v.multiplicand_X_3;
   
      Bit#(TAdd#(n,2)) pp = {2'b0, prod[2*valueOf(n)-1:valueOf(n)]};
   
      case (prod[1:0])
         0: pp = pp + 0;
         1: pp = pp + multiplicand_X_1;
         2: pp = pp + multiplicand_X_2;
         3: pp = pp + multiplicand_X_3;
      endcase
      
      v.prod = {1'b0, pp, prod[valueOf(n)-1:2]};
         
      return v;
   endfunction
   
   for (Integer i = 0; i < valueOf(n)/2 - 1; i = i + 1) begin
      rule doMulStep;
         let v = fifos[i].first;
         fifos[i].deq;
         fifos[i+1].enq(multiStep(v));
         // $display( "Step %d: prod = %b, pp = %b\t", i, v.prod, v.pp, fshow(v));
      endrule
   end

   method Action start(Bit#(n) aIn, Bit#(n) bIn);
      let multiplicand = aIn;
      let multiplier = bIn;
   
      Bit#(TAdd#(n,2)) multiplicand_X_1 = {0, multiplicand};
      Bit#(TAdd#(n,2)) multiplicand_X_2 = zeroExtend({multiplicand, 1'b0});
      Bit#(TAdd#(n,2)) multiplicand_X_3 = multiplicand_X_1 + multiplicand_X_2;

      // $display( "start : mc = %b, mp = %b \t", aIn, bIn);
      fifos[0].enq(multiStep(Radix4Unsigned{multiplicand_X_1: multiplicand_X_1,
                                            multiplicand_X_2: multiplicand_X_2,
                                            multiplicand_X_3: multiplicand_X_3,
                                            prod: {0, multiplier}
                                            }));
   endmethod

   method ActionValue#(Bit#(TAdd#(n,n))) result();
      let v <- toGet(fifos[valueOf(n)/2-1]).get;
      // $display( "Out \t prod = %b\t", v.prod, fshow(v));
      return truncate(v.prod);
   endmethod
endmodule

typedef struct{
   Bit#(n) mc;
   Bit#(1) lostbit;
   Bit#(TAdd#(TAdd#(n, n), 1)) prod;
   } Radix4Signed#(numeric type n) deriving (Bits, Eq, FShow);

module mkRadix4SignedMultiplier(Multiplier#(n))
   provisos(Log#(n, logn), 
            Add#(a__,1, logn), // n >= 2
            NumAlias#(n, TExp#(TLog#(n))), // n is power of 2
            Add#(2, b__, n),
            Add#(1, c__, TAdd#(n, n)),
            Add#(TAdd#(n, 1), d__, c__)
            ); // make sure n >= 2
   
   Vector#(TDiv#(n,2), FIFO#(Radix4Signed#(n))) fifos <- replicateM(mkPipelineFIFO);
   
   function Radix4Signed#(n) multiStep(Radix4Signed#(n) v);
      let prod = v.prod;
   
      Bit#(TAdd#(n,1)) mult_sx = signExtend(v.mc);
      Bit#(TAdd#(n,1)) mult_x_2 = {v.mc,1'b0};
   
      Bit#(TAdd#(n,1)) pp = prod[2*valueOf(n):valueOf(n)];
   
      case ( {prod[1:0],v.lostbit} )
         3'b001: pp = pp + mult_sx;
         3'b010: pp = pp + mult_sx;
         3'b011: pp = pp + mult_x_2;
         3'b100: pp = pp - mult_x_2;
         3'b101: pp = pp - mult_sx;
         3'b110: pp = pp - mult_sx;
      endcase
   
      v.lostbit = (v.prod)[1];      
      v.prod = {msb(pp), msb(pp),pp,prod[valueOf(n)-1:2]};
         
      return v;
   endfunction
   
   for (Integer i = 0; i < valueOf(n)/2 - 1; i = i + 1) begin
      rule doMulStep;
         let v = fifos[i].first;
         fifos[i].deq;
         fifos[i+1].enq(multiStep(v));
         // $display( "Step %d: prod = %b, pp = %b\t", i, v.prod, v.pp, fshow(v));
      endrule
   end

   method Action start(Bit#(n) aIn, Bit#(n) bIn);
      let mc = aIn;
      let mp = bIn;
   
      // $display( "start : mc = %b, mp = %b \t", aIn, bIn);
      fifos[0].enq(multiStep(Radix4Signed{mc: mc,
                                          lostbit: 0,
                                          prod: {0, mp}
                                          }));
   endmethod

   method ActionValue#(Bit#(TAdd#(n,n))) result();
      let v <- toGet(fifos[valueOf(n)/2-1]).get;
      // $display( "Out \t prod = %b\t", v.prod, fshow(v));
      return truncate(v.prod);
   endmethod
endmodule
