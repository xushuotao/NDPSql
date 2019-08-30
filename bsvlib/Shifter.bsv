package Shifter;

import GetPut::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Pipe::*;
import Vector::*;

function Bit#(tDataWidth) rotateRByte (Bit#(tDataWidth) inData, Bit#(tShiftWidth) shift);
   return inData >> {shift, 3'b0};
endfunction

function Bit#(tDataWidth) rotateLByte (Bit#(tDataWidth) inData, Bit#(tShiftWidth) shift);
   return inData << {shift, 3'b0};
endfunction   


interface ShiftIfc#(type dataT, numeric type lgStepSz, numeric type sftSz);
   method Action shiftBy(dataT v, Bit#(sftSz) shift);
   method PipeOut#(dataT) outPipe;
endinterface

typedef ShiftIfc#(dataT, 3, sftSz) ByteShiftIfc#(type dataT, numeric type sftSz);
typedef ShiftIfc#(dataT, 5, sftSz) WordShiftIfc#(type dataT, numeric type sftSz);


module mkCombinationalLeftShifter(ShiftIfc#(dataT, lgStepSz, sftSz))
   provisos(Bits#(dataT, dataSz),
            Bitwise#(dataT),
            Add#(1, a__, dataSz));
   FIFOF#(Tuple2#(datatT, Bit#(sftSz))) inputFifo <- mkFIFOF;
   
   function dataT doShift(Tuple2#(dataT, Bit#(sftSz)) args);
      let { data, sft } = args;
      Bit#(lgStepSz) pad = 0;
      return data << {shft, pad};
   endfunction
   
   method Action shiftBy(datatT v, Bit#(sftSz) shift);
      //$display("inputVal = %h, shift = %d", v, shift);
      inputFifo.enq(tuple2(v,shift));
   endmethod
   
   interface PipeOut outPipe = mapPipe(doShift, toPipeOut(inputFifo));
endmodule

module mkCombinationalRightShifter(ShiftIfc#(dataT, lgStepSz, sftSz))
   provisos(Bits#(dataT, dataSz),
            Bitwise#(dataT),
            Add#(1, a__, dataSz));
   
   FIFOF#(Tuple2#(datatT, Bit#(sftSz))) inputFifo <- mkFIFOF;
   
   function dataT doShift(Tuple2#(dataT, Bit#(sftSz)) args);
      let { data, sft } = args;
      Bit#(lgStepSz) pad = 0;
      return data >> {shft, pad};
   endfunction
   
   method Action shiftBy(datatT v, Bit#(sftSz) shift);
      //$display("inputVal = %h, shift = %d", v, shift);
      inputFifo.enq(tuple2(v,shift));
   endmethod
   
   interface PipeOut outPipe = mapPipe(doShift, toPipeOut(inputFifo));
endmodule


module mkPipelineLeftShifter(ShiftIfc#(dataT, lgStepSz, sftSz))
   provisos(Bits#(dataT, dataSz),
            Bitwise#(dataT)));
   
   function Tuple2#(dataT, Bit#(shftSz)) doSftStep (Tuple2#(dataT, Bit#(shftSz)) in, Integer step);
      return shift[i] == 1 ? val << (2**(i+valueOf(lgStepSz))) : val;
   endfunction
   
   Vector#(sftSz, FIFOF#(Tuple2#(dataT, Bit#(sftSz)))) stageFifos <- replicateM(mkPipelineFIFOF);
   
   for (Integer i = 1; i < valueOf(sftSz); i = i + 1) begin
      rule doStage;
         let args <- toGet(stageFifos[i-1]).get();
         stageFifos[i].enq(args, i);
      endrule
   end
      
   method Action shiftBy(dataT v, Bit#(sftSz) shift);
      //$display("inputVal = %h, shift = %d", v, shift);
      stageFifos[0].enq(doSftStep(tuple2(v,shift), 0));
   endmethod
   
   interface outPipe = mapPipe(tpl_1, toPipeOut(last(stagaFifos)));
endmodule



module mkPipelineRightShifter(ShiftIfc#(dataT, lgStepSz, sftSz))
   provisos(Bits#(dataT, dataSz),
            Bitwise#(dataT)));
   
   function Tuple2#(dataT, Bit#(shftSz)) doSftStep (Tuple2#(dataT, Bit#(shftSz)) in, Integer step);
      return shift[i] == 1 ? val >> (2**(i+valueOf(lgStepSz))) : val;
   endfunction
   
   Vector#(sftSz, FIFOF#(Tuple2#(dataT, Bit#(sftSz)))) stageFifos <- replicateM(mkPipelineFIFOF);
   
   for (Integer i = 1; i < valueOf(sftSz); i = i + 1) begin
      rule doStage;
         let args <- toGet(stageFifos[i-1]).get();
         stageFifos[i].enq(args, i);
      endrule
   end
      
   method Action shiftBy(dataT v, Bit#(sftSz) shift);
      //$display("inputVal = %h, shift = %d", v, shift);
      stageFifos[0].enq(doSftStep(tuple2(v,shift), 0));
   endmethod
   
   interface outPipe = mapPipe(tpl_1, toPipeOut(last(stagaFifos)));
endmodule
