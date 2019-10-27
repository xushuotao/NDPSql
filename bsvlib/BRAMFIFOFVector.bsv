import RWBramCore::*;
import Vector::*;
import Pipe::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import GetPut::*;
import ClientServer::*;

Bool debug = False;

interface BRAMFIFOFVector#(numeric type vlog, numeric type fifodepth, type fifotype);
   method Action enq(fifotype data, UInt#(vlog) idx);
   interface Vector#(TExp#(vlog), PipeOut#(fifotype)) outPipes;
endinterface


module mkUGBRAMFIFOFVector(BRAMFIFOFVector#(vlog, fifodepth, fifotype))
   provisos (
      NumAlias#(TExp#(vlog), vSz),
      Log#(fifodepth, dlog),
      NumAlias#(TExp#(TLog#(fifodepth)), fifodepth), // fifodepth is power of 2
      Bits#(fifotype, fifotypesz)
      );
   Vector#(vSz, Reg#(UInt#(dlog))) enqPtr <- replicateM(mkReg(0)); 
   Vector#(vSz, Reg#(UInt#(dlog))) deqPtr <- replicateM(mkReg(0)); 
   Vector#(vSz, Array#(Reg#(UInt#(TAdd#(fifodepth,1))))) elemCnt <- replicateM(mkCReg(2, 0)); 
   
   RWBramCore#(UInt#(TAdd#(vlog, dlog)), fifotype) buffer <- mkRWBramCore;
   Vector#(vSz, Array#(Reg#(fifotype))) readCache <- replicateM(mkCRegU(2));
   Vector#(vSz, Array#(Reg#(Bool))) valid <- replicateM(mkCReg(2, False));
   Reg#(UInt#(vlog)) idxReg <- mkRegU;
   
   function UInt#(TAdd#(vlog, dlog)) toAddr(UInt#(vlog) idx, UInt#(dlog) ptr) = unpack({pack(idx), pack(ptr)});

   function PipeOut#(fifotype) genPipeOut(Integer i);
      return (interface PipeOut;
                 method Bool notEmpty = valid[i][0];//(elemCnt[i][0] > 0);
                 method fifotype first = readCache[i][1];
                 method Action deq if (valid[i][0]);//if (elemCnt[i][0] > 0);
                    if (debug) $display("deq, tag = %d, elemCnt = %d, deqPtr = %d", i, elemCnt[i][0], deqPtr[i]);
                    elemCnt[i][0] <= elemCnt[i][0] - 1;
                    if ( elemCnt[i][0] > 1 ) begin
                       deqPtr[i] <= deqPtr[i] + 1;
                       buffer.rdReq(toAddr(fromInteger(i), deqPtr[i]));
                    end
                    valid[i][0] <= elemCnt[i][0]>1 ? True:False;
                    idxReg <= fromInteger(i);
                 endmethod
              endinterface);
   endfunction
   

   
   (* fire_when_enabled *)
   rule fillRdCache if ( buffer.rdRespValid);
      readCache[idxReg][0] <= buffer.rdResp;
      buffer.deqRdResp;
   endrule
      
   method Action enq(fifotype data, UInt#(vlog) tag);
      if (debug) $display("enq, tag = %d, elemCnt = %d, enqPtr = %d", tag, elemCnt[tag][1], enqPtr[tag]);
      valid[tag][1] <= True;
      if ( elemCnt[tag][1] == 0 ) begin
         readCache[tag][1] <= data;
      end
      else begin
         enqPtr[tag] <= enqPtr[tag] + 1;
         buffer.wrReq(toAddr(tag, enqPtr[tag]), data);
      end
      elemCnt[tag][1] <= elemCnt[tag][1] + 1;
   endmethod

   interface outPipes = genWith(genPipeOut);   
endmodule

interface BRAMFIFOFAsyncVector#(numeric type vlog, numeric type fifodepth, type fifotype);
   method Action enq(fifotype data, UInt#(vlog) idx);
   interface Vector#(TExp#(vlog), PipeOut#(void)) rdReady;
   interface Server#(UInt#(vlog), fifotype) rdServer;
endinterface

module mkUGBRAMFIFOFAsyncVector(BRAMFIFOFAsyncVector#(vlog, fifodepth, fifotype))
   provisos (
      NumAlias#(TExp#(vlog), vSz),
      Log#(fifodepth, dlog),
      NumAlias#(TExp#(TLog#(fifodepth)), fifodepth), // fifodepth is power of 2
      Bits#(fifotype, fifotypesz)
      );
   Vector#(vSz, Reg#(UInt#(dlog))) enqPtr <- replicateM(mkReg(0)); 
   Vector#(vSz, Reg#(UInt#(dlog))) deqPtr <- replicateM(mkReg(0)); 
   RWBramCore#(UInt#(TAdd#(vlog, dlog)), fifotype) buffer <- mkUGRWBramCore;
   
   Vector#(vSz, FIFOF#(void)) validQs <- replicateM(mkUGSizedFIFOF(valueOf(fifodepth)));
   
   function UInt#(TAdd#(vlog, dlog)) toAddr(UInt#(vlog) idx, UInt#(dlog) ptr) = unpack({pack(idx), pack(ptr)});

   method Action enq(fifotype data, UInt#(vlog) tag);
      validQs[tag].enq(?);
      enqPtr[tag] <= enqPtr[tag] + 1;
      buffer.wrReq(toAddr(tag, enqPtr[tag]), data);
   endmethod

   interface rdReady = map(toPipeOut, validQs);
   
   interface Server rdServer;
      interface Put request;
         method Action put(UInt#(vlog) tag);
            deqPtr[tag] <= deqPtr[tag] + 1;
            buffer.rdReq(toAddr(tag, deqPtr[tag]));
         endmethod
      endinterface
      interface Get response;
         method ActionValue#(fifotype) get if ( buffer.rdRespValid);
            buffer.deqRdResp;
            return buffer.rdResp;
         endmethod
      endinterface
   endinterface
endmodule


interface BRAMVector#(numeric type vlog, numeric type fifodepth, type fifotype);
   method Action enq(fifotype data, UInt#(vlog) idx);
   interface Server#(UInt#(vlog), fifotype) rdServer;
endinterface

module mkUGBRAMVector(BRAMVector#(vlog, fifodepth, fifotype))
   provisos (
      NumAlias#(TExp#(vlog), vSz),
      Log#(fifodepth, dlog),
      // NumAlias#(TExp#(TLog#(fifodepth)), fifodepth), // fifodepth is power of 2
      Bits#(fifotype, fifotypesz),
      Add#(a__, dlog, TLog#(TMul#(TExp#(vlog), fifodepth)))
      );
   Vector#(vSz, Reg#(UInt#(dlog))) enqPtr <- replicateM(mkReg(0)); 
   Vector#(vSz, Reg#(UInt#(dlog))) deqPtr <- replicateM(mkReg(0)); 
   RWBramCore#(UInt#(TLog#(TMul#(vSz, fifodepth))), fifotype) buffer <- mkUGRWBramCore;
   
   Integer depth = valueOf(fifodepth);
   
   Vector#(vSz, Integer) offsets = zipWith(\* , genVector(), replicate(depth));
   
   function UInt#(TLog#(TMul#(vSz, fifodepth))) toAddr(UInt#(vlog) idx, UInt#(dlog) ptr) = fromInteger(offsets[idx])+extend(ptr);
   
   Vector#(vSz, FIFOF#(void)) validQs <- replicateM(mkSizedFIFOF(valueOf(fifodepth)));

   method Action enq(fifotype data, UInt#(vlog) tag);
      if ( enqPtr[tag] == fromInteger(depth-1)) begin
         enqPtr[tag] <= 0;
      end
      else begin
         enqPtr[tag] <= enqPtr[tag] + 1;
      end
      // validQs[tag].enq(?);
      buffer.wrReq(toAddr(tag, enqPtr[tag]), data);
   endmethod

   
   interface Server rdServer;
      interface Put request;
         method Action put(UInt#(vlog) tag);
            if ( deqPtr[tag] == fromInteger(depth-1) ) begin
               deqPtr[tag] <= 0;
            end
            else begin
               deqPtr[tag] <= deqPtr[tag] + 1;
            end
            // validQs[tag].deq;
            buffer.rdReq(toAddr(tag, deqPtr[tag]));
         endmethod
      endinterface
      interface Get response;
         method ActionValue#(fifotype) get if ( buffer.rdRespValid); 
            buffer.deqRdResp;
            return buffer.rdResp;
         endmethod
      endinterface
   endinterface
endmodule


