// Copyright (C) 2019

// Shuotao Xu <shuotao@csail.mit.edu>

// Permission is hereby granted, free of charge, to any person obtaining a copy of this
// software and associated documentation files (the "Software"), to deal in the Software
// without restriction, including without limitation the rights to use, copy, modify,
// merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
// permit persons to whom the Software is furnished to do so, subject to the following
// conditions:

// The above copyright notice and this permission notice shall be included in all copies
// or substantial portions of the Software.  

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
// INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
// PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
// HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
// CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE
// OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


import Vector::*;
import BuildVector::*;
import Pipe::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Connectable::*;

interface StreamNode#(numeric type n, type itype);
   interface PipeIn#(Vector#(n, itype)) inPipe;
   interface PipeOut#(Vector#(n, itype)) outPipe;
endinterface

typeclass RecursiveBitonic#(numeric type n, type itype);
////////////////////////////////////////////////////////////////////////////////
/// function:    sort_bitonic
/// Description: this function sorts a input vector of bitonic sequence 
///              using partial bitonic sorting network
/// Arguments:   in         ==> vector of a bitonic sequence
///              ascending ==> sorting order is ascending order
///                             i.e (out[i+1] > out[i]), and vice versa
/// Return:      vector of sorted input sequence in ascending or descending order
////////////////////////////////////////////////////////////////////////////////
   function Vector#(n, itype) sort_bitonic(Vector#(n, itype) in, Bool ascending);
   
////////////////////////////////////////////////////////////////////////////////
/// function:    bitonic_merge
/// Description: this function merge-sorts a input vector of two sorted sequences
///              using bitonic sorting network
/// Arguments:   in         ==> vector of two sorted sequences
///                             in[n-1:n/2] and in[n/2-1:0]
///              ascending ==> sorting order is ascending order
///                             i.e (out[i+1] > out[i]), and vice versa
/// Return:      vector of sorted input sequence in ascending or descending order
////////////////////////////////////////////////////////////////////////////////
   function Vector#(n, itype) bitonic_merge(Vector#(n, itype) in, Bool ascending);

////////////////////////////////////////////////////////////////////////////////
/// function:    bitonic sort
/// Description: this function sort in input vector using bitonic sorting network
/// Arguments:   in         ==> unsorted vector
///              ascending ==> sorting order is ascending order
///                             i.e (out[i+1] > out[i]), and vice versa
/// Return:      vector of sorted input sequence in ascending or descending order
////////////////////////////////////////////////////////////////////////////////
   function Vector#(n, itype) bitonic_sort(Vector#(n, itype) in, Bool ascending);
   
   module mkBitonicSort#(Bool ascending)(StreamNode#(n, itype));
   module mkSortBitonic#(Bool ascending)(StreamNode#(n, itype));
   module mkUGSortBitonic#(Bool ascending)(StreamNode#(n, itype));
   module mkBitonicMerge#(Bool ascending)(StreamNode#(n, itype));
endtypeclass

// base cases
instance RecursiveBitonic#(1, itype) provisos(Ord#(itype));
   function Vector#(1, itype) sort_bitonic(Vector#(1, itype) in, Bool ascending) = in;
   function Vector#(1, itype) bitonic_merge(Vector#(1, itype) in, Bool ascending) = in;   
   function Vector#(1, itype) bitonic_sort(Vector#(1, itype) in, Bool ascending) = in;   
endinstance

// base cases
instance RecursiveBitonic#(2, itype) provisos(Ord#(itype), Bits#(Vector::Vector#(2, itype), a__));
   function Vector#(2, itype) sort_bitonic(Vector#(2, itype) in, Bool ascending) = cas(in, ascending);
   function Vector#(2, itype) bitonic_merge(Vector#(2, itype) in, Bool ascending) = cas(in, ascending);   
   function Vector#(2, itype) bitonic_sort(Vector#(2, itype) in, Bool ascending) = cas(in, ascending);
   module mkSortBitonic#(Bool ascending)(StreamNode#(2, itype));
      FIFOF#(Vector#(2, itype)) fifo <- mkFIFOF;
      function f(x) = cas(x, ascending);
      interface PipeIn inPipe = mapPipeIn(f, toPipeIn(fifo));
      interface PipeOut outPipe = toPipeOut(fifo);
   endmodule
   
   module mkUGSortBitonic#(Bool ascending)(StreamNode#(2, itype));
      FIFOF#(Vector#(2, itype)) fifo <- mkUGFIFOF1;
      function f(x) = cas(x, ascending);
      interface PipeIn inPipe = mapPipeIn(f, toPipeIn(fifo));
      interface PipeOut outPipe = toPipeOut(fifo);
   endmodule


   module mkBitonicMerge#(Bool ascending)(StreamNode#(2, itype));
      FIFOF#(Vector#(2, itype)) fifo <- mkFIFOF;
      function f(x) = cas(x, ascending);
      interface PipeIn inPipe = mapPipeIn(f, toPipeIn(fifo));
      interface PipeOut outPipe = toPipeOut(fifo);
   endmodule
      
   module mkBitonicSort#(Bool ascending)(StreamNode#(2, itype));
      FIFOF#(Vector#(2, itype)) fifo <- mkFIFOF;
      function f(x) = cas(x, ascending);
      interface PipeIn inPipe = mapPipeIn(f, toPipeIn(fifo));
      interface PipeOut outPipe = toPipeOut(fifo);
   endmodule
endinstance

// normal cases
instance RecursiveBitonic#(n, itype) 
   provisos(Ord#(itype),
            Add#(TDiv#(n, 2), a__, n),
            Mul#(2, TDiv#(n, 2), n),
            RecursiveBitonic#(n, itype),
            RecursiveBitonic#(TDiv#(n, 2), itype),
            Bits#(Vector::Vector#(TDiv#(n, 2), itype), b__),
            Add#(1, c__, TLog#(n))
      );
   
   function Vector#(n, itype) sort_bitonic(Vector#(n, itype) in, Bool ascending);
   
      Vector#(TAdd#(TLog#(n),1), Vector#(n, itype)) sortData = ?;
      sortData[0] = in;
      
      for (Integer i = 0; i < valueOf(TLog#(n)); i = i + 1 )begin
         Integer stride = valueOf(n)/(2**(i+1));
         for ( Integer j = 0; j < 2**i; j = j + 1 ) begin
            for ( Integer k = 0; k < valueOf(n)/(2**(i+1)); k = k + 1) begin
               Integer idx = (j*valueOf(n)/(2**i))+k;
               let {a, b} = cas_tpl(tuple2(sortData[i][idx],sortData[i][idx+stride]), ascending);
               sortData[i+1][idx] = a;
               sortData[i+1][idx+stride] = b;
            end
         end
      end 
   
      return last(sortData);

////////////////////////////////////////////////////////////////////////////////
/// recursive version gives out funny circuit
////////////////////////////////////////////////////////////////////////////////
      // let halves = splitHalf(in);
      // function cas_f(x) = cas(x,ascending);
      // let bitonic_seqV = transpose(map(cas_f, transpose(vec(halves[0], halves[1]))));
      // let bot_sorted_seq = sort_bitonic(bitonic_seqV[0], ascending);
      // let top_sorted_seq = sort_bitonic(bitonic_seqV[1], ascending);
      // return append(bot_sorted_seq, top_sorted_seq);
      // return concat(vec(bot_sorted_seq, top_sorted_seq)); //:( a trick for bsc to use Mul#
   endfunction
   
   function Vector#(n, itype) bitonic_merge(Vector#(n, itype) in, Bool ascending);
      let sorted_halves = splitHalf(in);
      let bitonic_seq_V = halfClean(sorted_halves, ascending);
   
      let bot_sorted_seq = sort_bitonic(bitonic_seq_V[0], ascending);
      let top_sorted_seq = sort_bitonic(bitonic_seq_V[1], ascending);
      
      return append(bot_sorted_seq, top_sorted_seq); //:( a trick for bsc to use Mul#
      // return concat(vec(bot_sorted_seq, top_sorted_seq)); //:( a trick for bsc to use Mul#
   endfunction


   function Vector#(n, itype) bitonic_sort(Vector#(n, itype) in, Bool ascending);
      let halves = splitHalf(in);
      let sorted_bot = bitonic_sort(halves[0], ascending);
      let sorted_top = bitonic_sort(halves[1], ascending);
      return bitonic_merge(append(sorted_bot, sorted_top), ascending);
   
      // return bitonic_merge(concat(vec(sorted_bot, sorted_top)), ascending);
   endfunction
   
   module mkSortBitonic#(Bool ascending)(StreamNode#(n, itype));
      //Vector#(TAdd#(TLog#(n),1), FIFOF#(Vector#(n, itype))) dataPipe <- replicateM(mkPipelineFIFOF);
      Vector#(TAdd#(TLog#(n),1), FIFOF#(Vector#(n, itype))) dataPipe <- replicateM(mkFIFOF);
      for (Integer i = 0; i < valueOf(TLog#(n)) ; i = i + 1 )begin
         rule doStage;   
            Integer stride = valueOf(n)/(2**(i+1));
            Vector#(n, itype) data = dataPipe[i].first;
            dataPipe[i].deq;
            for ( Integer j = 0; j < 2**i; j = j + 1 ) begin
               for ( Integer k = 0; k < valueOf(n)/(2**(i+1)); k = k + 1) begin
                  Integer idx = (j*valueOf(n)/(2**i))+k;
                  let {a, b} = cas_tpl(tuple2(data[idx],data[idx+stride]), ascending);
                  data[idx] = a;
                  data[idx+stride] = b;
               end
            end
            dataPipe[i+1].enq(data);
         endrule
      end

   
      interface PipeIn inPipe = toPipeIn(dataPipe[0]);
         // method Action enq(Vector#(n, itype) in);
         //    Integer stride = valueOf(n)/2;
         //    Vector#(n, itype) data = ?;
         //    for ( Integer k = 0; k < valueOf(n)/2; k = k + 1) begin
         //       let idx = k;
         //       let {a, b} = cas_tpl(tuple2(in[idx],in[idx+stride]), ascending);
         //       data[idx] = a;
         //       data[idx+stride] = b;
         //    end
         //    dataPipe[0].enq(data);
         // endmethod
         // method Bool notFull = dataPipe[0].notEmpty;
      // endinterface
      interface PipeOut outPipe = toPipeOut(last(dataPipe));
      //    method Vector#(n, itype) first;
      //       // let bot_sorted = sort_bitonic[0].outPipe.first;
      //       // let top_sorted = sort_bitonic[1].outPipe.first;

      //       Integer stride = 1;
      //       Vector#(n, itype) data = last(dataPipe).first;
      //       for ( Integer j = 0; j < valueOf(n)/2; j = j + 1 ) begin
      //          Integer idx = (j*2);
      //          let {a, b} = cas_tpl(tuple2(data[idx],data[idx+stride]), ascending);
      //          data[idx] = a;
      //          data[idx+stride] = b;
      //       end
      //       return data;
      //    endmethod
      //    method Action deq = last(dataPipe).deq;
      //    method Bool notEmpty = last(dataPipe).notEmpty;
      // endinterface
   endmodule
   
   

module mkUGSortBitonic#(Bool ascending)(StreamNode#(n, itype));
   Vector#(TLog#(n), Reg#(Vector#(n, itype))) stageData <- replicateM(mkRegU);
   Vector#(TLog#(n), Reg#(Bool)) valid <- replicateM(mkReg(False));
   // Vector#(TLog#(n), FIFOF#(Vector#(n, itype))) stageData <- replicateM(mkUGFIFOF);
   for (Integer i = 1; i < valueOf(TLog#(n)); i = i + 1 )begin
      (* fire_when_enabled, no_implicit_conditions *)
      rule doStage;//if (stageData[i-1].notEmpty);
         Integer stride = valueOf(n)/(2**(i+1));
         Vector#(n, itype) data = stageData[i-1];

         for ( Integer j = 0; j < 2**i; j = j + 1 ) begin
            for ( Integer k = 0; k < valueOf(n)/(2**(i+1)); k = k + 1) begin
               Integer idx = (j*valueOf(n)/(2**i))+k;
               let {a, b} = cas_tpl(tuple2(data[idx],data[idx+stride]), ascending);
               data[idx] = a;
               data[idx+stride] = b;
            end
         end
         stageData[i]._write(data);
         
         valid[i] <= valid[i-1];
      endrule
   end
   
   RWire#(Vector#(n, itype)) inWire <- mkRWire;
   
   rule doFirstStage;
      let in = fromMaybe(?, inWire.wget());
      Integer stride = valueOf(n)/2;
      Vector#(n, itype) data = ?;
      for ( Integer k = 0; k < valueOf(n)/2; k = k + 1) begin
         let idx = k;
         let {a, b} = cas_tpl(tuple2(in[idx],in[idx+stride]), ascending);
         data[idx] = a;
         data[idx+stride] = b;
      end
      stageData[0]._write(data);
      
      valid[0] <= isValid(inWire.wget());
   endrule

   
   interface PipeIn inPipe;
      method Action enq(Vector#(n, itype) in);
         inWire.wset(in);
      endmethod
      method Bool notFull = True;
   endinterface
   interface PipeOut outPipe;
      method Bool notEmpty = last(valid)._read();
      method Vector#(n, itype) first = last(stageData)._read();
      method Action deq=noAction;
   endinterface
endmodule

   
   module mkBitonicMerge#(Bool ascending)(StreamNode#(n, itype));
      //Vector#(2, FIFOF#(Vector#(TDiv#(n,2), itype))) inFifos <- replicateM(mkFIFOF);
      Vector#(2, FIFOF#(Vector#(TDiv#(n,2), itype))) inFifos <- replicateM(mkPipelineFIFOF);
      Vector#(2, StreamNode#(TDiv#(n,2), itype)) sort_bitonic <- replicateM(mkSortBitonic(ascending));
      zipWithM_(mkConnection, map(toPipeOut, inFifos), vec(sort_bitonic[0].inPipe, sort_bitonic[1].inPipe));
      interface PipeIn inPipe;
         method Action enq(Vector#(n, itype) in);
            let sorted_halves = splitHalf(in);
            let bitonic_seq_V = halfClean(sorted_halves, ascending);
            inFifos[0].enq(bitonic_seq_V[0]);
            inFifos[1].enq(bitonic_seq_V[1]);
         endmethod
         method Bool notFull = inFifos[0].notFull && inFifos[1].notFull; 
      endinterface
      interface PipeOut outPipe;
         method Vector#(n, itype) first;
            let bot_sorted = sort_bitonic[0].outPipe.first;
            let top_sorted = sort_bitonic[1].outPipe.first;
            return append(bot_sorted,top_sorted);
         endmethod
         method Action deq;
            sort_bitonic[0].outPipe.deq;
            sort_bitonic[1].outPipe.deq;
         endmethod
         method Bool notEmpty = sort_bitonic[0].outPipe.notEmpty && sort_bitonic[1].outPipe.notEmpty;
      endinterface
   endmodule
      
   module mkBitonicSort#(Bool ascending)(StreamNode#(n, itype));
      Vector#(2, StreamNode#(TDiv#(n,2), itype)) bitonic_sorter <- replicateM(mkBitonicSort(ascending));
      StreamNode#(n, itype) bitonic_merger <- mkBitonicMerge(ascending);
      rule doMerger;
         let bot_sorted = bitonic_sorter[0].outPipe.first;
         let top_sorted = bitonic_sorter[1].outPipe.first;
         bitonic_sorter[0].outPipe.deq;
         bitonic_sorter[1].outPipe.deq;
         bitonic_merger.inPipe.enq(concat(vec(bot_sorted,top_sorted)));
      endrule
      interface PipeIn inPipe;
         method Action enq(Vector#(n, itype) in);
            let halves = splitHalf(in);
            bitonic_sorter[0].inPipe.enq(halves[0]);
            bitonic_sorter[1].inPipe.enq(halves[1]);
         endmethod
         method Bool notFull = bitonic_sorter[0].inPipe.notFull && bitonic_sorter[1].inPipe.notFull;
      endinterface
      interface PipeOut outPipe = bitonic_merger.outPipe;
   endmodule
endinstance


////////////////////////////////////////////////////////////////////////////////
/// helper functions
////////////////////////////////////////////////////////////////////////////////


function Bool isSorted(Vector#(n, itype) in, Bool ascending)
   provisos(Ord#(itype));
   Bool unSorted = False;
   for (Integer i = 1; i < valueOf(n); i = i + 1) begin
      if ( ascending ) begin
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
function Vector#(2,itype) cas(Vector#(2,itype) in, Bool ascending)
   provisos(Ord#(itype));
   let a = in[1];
   let b = in[0];
   return (pack(a>b)^pack(!ascending))==1? vec(b,a): vec(a,b);
endfunction

function Tuple2#(itype,itype) cas_tpl(Tuple2#(itype,itype) in, Bool ascending)
   provisos(Ord#(itype));
   let {b, a} = in;
   // let b = in[0];
   return (pack(a>b)^pack(!ascending))==1? tuple2(b,a): tuple2(a,b);
endfunction


////////////////////////////////////////////////////////////////////////////////
/// function compare and swap
////////////////////////////////////////////////////////////////////////////////
function itype getTop(Vector#(2,itype) in, Bool ascending)
   provisos(Ord#(itype));
   let a = in[1];
   let b = in[0];
   return ascending?max(a,b):min(a,b);
endfunction


////////////////////////////////////////////////////////////////////////////////
/// function:    halfCleaner
/// Description: this function takes two sorted vectors and return two
///              bitonic vectors, in which top vector values are bigger than
///              the bottom
/// Arguments:   in         ==> two sorted vectors {top, bot}
///              ascending ==> sorting order is ascending order
///                             i.e (out[i+1] > out[i]), and vice versa
/// Return:      two non-overlapping bitonic sequences where 
///              any(out[0]) <(>) any(out[1])
////////////////////////////////////////////////////////////////////////////////
function Vector#(2, Vector#(vcnt, itype)) halfClean(Vector#(2, Vector#(vcnt, itype)) in, Bool ascending) 
   provisos(Ord#(itype));
   let top_rev = reverse(in[1]);
   let bot_ret = zipWith(ascending?min:max, top_rev, in[0]);
   let top_ret = zipWith(ascending?max:min, top_rev, in[0]);
   return vec(bot_ret, reverse(top_ret));
endfunction

function Vector#(2, Vector#(TDiv#(cnt,2), itype)) splitHalf(Vector#(cnt, itype) in)
   provisos(Add#(TDiv#(cnt, 2), a__, cnt));
   Vector#(TDiv#(cnt,2), itype) bot = take(in);
   Vector#(TDiv#(cnt,2), itype) top = drop(in);
   return vec(bot,top);
endfunction


