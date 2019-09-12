import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;
import BuildVector::*;

import Randomizable::*;

function Bool isSorted(Vector#(n, itype) in, Bool descending)
   provisos(Ord#(itype));
   Bool unSorted = False;
   for (Integer i = 1; i < valueOf(n); i = i + 1) begin
      if ( descending ) begin
         unSorted = in[i-1] > in[i] || unSorted;
      end
      else begin
         unSorted = in[i-1] < in[i] || unSorted;
      end
   end
   return !unSorted;
endfunction

////////////////////////////////////////////////////////////////////////////////
/// function compare and swap
////////////////////////////////////////////////////////////////////////////////
function Vector#(2,itype) cas(Vector#(2,itype) in, Bool descending)
   provisos(Ord#(itype));
   let a = in[1];
   let b = in[0];
   return (pack(a>b)^pack(!descending))==1? vec(b,a): vec(a,b);
endfunction

////////////////////////////////////////////////////////////////////////////////
/// function:    halfCleaner
/// Description: this function takes two sorted vectors and return two
///              bitonic vectors, in which top vector values are bigger than
///              the bottom
/// Arguments:   in         ==> two sorted vectors {top, bot}
///              descending ==> input vectors are sorted in descending order
///                             i.e (top[i+1] > top[i])
/// 
////////////////////////////////////////////////////////////////////////////////
function Vector#(2, Vector#(vcnt, itype)) halfClean(Vector#(2, Vector#(vcnt, itype)) in, Bool descending) 
   provisos(Ord#(itype));
   let top_rev = reverse(in[1]);
   let bot_ret = zipWith(descending?min:max, top_rev, in[0]);
   let top_ret = zipWith(descending?max:min, top_rev, in[0]);
   return vec(bot_ret, reverse(top_ret));
endfunction

function Vector#(2, Vector#(TDiv#(cnt,2), itype)) splitHalf(Vector#(cnt, itype) in)
   provisos(Add#(TDiv#(cnt, 2), a__, cnt));
   Vector#(TDiv#(cnt,2), itype) bot = take(in);
   Vector#(TDiv#(cnt,2), itype) top = drop(in);
   return vec(bot,top);
endfunction

typeclass RecursiveBitonic#(numeric type n, type itype);
   function Vector#(n, itype) sort_bitonic(Vector#(n, itype) in, Bool descending);
   function Vector#(n, itype) bitonic_merge(Vector#(n, itype) in, Bool descending);
   function Vector#(n, itype) bitonic_sort(Vector#(n, itype) in, Bool descending);
endtypeclass

// base cases
instance RecursiveBitonic#(1, itype) provisos(Ord#(itype));
   function Vector#(1, itype) sort_bitonic(Vector#(1, itype) in, Bool descending) = in;
   function Vector#(1, itype) bitonic_merge(Vector#(1, itype) in, Bool descending) = in;   
   function Vector#(1, itype) bitonic_sort(Vector#(1, itype) in, Bool descending) = in;   
endinstance


instance RecursiveBitonic#(n, itype) 
   provisos(Ord#(itype),
            Add#(TDiv#(n, 2), a__, n),
            Mul#(2, TDiv#(n, 2), n),
            RecursiveBitonic#(n, itype),
            RecursiveBitonic#(TDiv#(n, 2), itype)
      );
   
   function Vector#(n, itype) sort_bitonic(Vector#(n, itype) in, Bool descending);
      if ( valueOf(n) == 1 ) begin
         return sort_bitonic(in, descending);
      end
      else begin
         let halves = splitHalf(in);
   
         let bot_bitonic_seq = zipWith(descending?min:max, halves[1], halves[0]);
         let top_bitonic_seq = zipWith(descending?max:min, halves[1], halves[0]);
         
         let bot_sorted_seq = sort_bitonic(bot_bitonic_seq, descending);
         let top_sorted_seq = sort_bitonic(top_bitonic_seq, descending);
   
         return concat(vec(bot_sorted_seq, top_sorted_seq)); //:( a trick for bsc to use Mul#
      end
   endfunction
   
   function Vector#(n, itype) bitonic_merge(Vector#(n, itype) in, Bool descending);
      let sorted_halves = splitHalf(in);
      let bitonic_seq_V = halfClean(sorted_halves, descending);
   
      let bot_sorted_seq = sort_bitonic(bitonic_seq_V[0], descending);
      let top_sorted_seq = sort_bitonic(bitonic_seq_V[1], descending);
      
      return concat(vec(bot_sorted_seq, top_sorted_seq)); //:( a trick for bsc to use Mul#
   endfunction


   function Vector#(n, itype) bitonic_sort(Vector#(n, itype) in, Bool descending);
      if ( valueOf(n) == 1 ) begin
         return bitonic_sort(in, descending);
      end
      else begin
         let halves = splitHalf(in);
         let sorted_bot = bitonic_sort(halves[0], descending);
         let sorted_top = bitonic_sort(halves[1], descending);
         return bitonic_merge(concat(vec(sorted_bot, sorted_top)), descending);
      end
   endfunction
endinstance

typedef 16 ElemCnt;

module mkBitonicTest(Empty);
   Reg#(Bit#(32)) testCnt <- mkReg(0);
   Integer testLen = 10000;
   Bool descending = True;
   rule doTest;
      testCnt <= testCnt + 1;
      Vector#(ElemCnt, UInt#(32)) inV;
      for (Integer i = 0; i < valueOf(ElemCnt); i = i + 1) begin
         let v <- rand32();
         inV[i] = unpack(v);
      end
      
      let outV = bitonic_sort(inV, descending);
      
      $display("Seq[%d] Input  = ", testCnt, fshow(inV));
      $display("Seq[%d] Output = ", testCnt, fshow(outV));
      
      if ( !isSorted(outV, descending) ) begin
         $display("FAILED: BitonicSort");
         $finish;
      end
      
      if (testCnt + 1 == fromInteger(testLen)) begin
         $display("PASSED: BitonicSort");
         $finish;
      end
   endrule
endmodule

