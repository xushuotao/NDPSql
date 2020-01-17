import RWBramCore::*;
import Vector::*;
import Pipe::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import GetPut::*;
import ClientServer::*;
import RegFile::*;
import DelayPipe::*;

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
   // Vector#(vSz, Reg#(UInt#(dlog))) enqPtr <- replicateM(mkReg(0)); 
   // Vector#(vSz, Reg#(UInt#(dlog))) deqPtr <- replicateM(mkReg(0));
   
   RegFile#(UInt#(vlog), UInt#(dlog)) enqPtr <- mkRegFileFull;//replicateM(mkReg(0)); 
   RegFile#(UInt#(vlog), UInt#(dlog)) deqPtr <- mkRegFileFull;//replicateM(mkReg(0)); 

   RWBramCore#(UInt#(TLog#(TMul#(vSz, fifodepth))), fifotype) buffer <- mkUGRWBramCore;
   
   Integer depth = valueOf(fifodepth);
   
   Vector#(vSz, Integer) offsets = zipWith(\* , genVector(), replicate(depth));
   
   function UInt#(TLog#(TMul#(vSz, fifodepth))) toAddr(UInt#(vlog) idx, UInt#(dlog) ptr) = fromInteger(offsets[idx])+extend(ptr);

   `ifdef DEBUG   
   Vector#(vSz, FIFOF#(void)) validQs <- replicateM(mkUGSizedFIFOF(valueOf(fifodepth)));
   `endif
   
   Reg#(Bool) init <- mkReg(False);
   Reg#(UInt#(vlog)) tagCnt <- mkReg(0);
   
   rule doInit if (!init);
      enqPtr.upd(tagCnt,0);
      deqPtr.upd(tagCnt,0);
      tagCnt <= tagCnt + 1;
      
      if ( tagCnt == fromInteger(valueOf(vSz)-1))
         init <= True;
   endrule

   method Action enq(fifotype data, UInt#(vlog) tag) if (init);
      let ptr = enqPtr.sub(tag);
      if ( ptr == fromInteger(depth-1)) begin
         enqPtr.upd(tag, 0);
      end
      else begin
         enqPtr.upd(tag, ptr+1);
      end
      `ifdef DEBUG   
      validQs[tag].enq(?);
      `endif
      // $display("%m,(%t) buffer wrReq tag = %d, enqPtr = %d, addr = %d", $time, tag, enqPtr[tag], toAddr(tag, enqPtr[tag]));
      buffer.wrReq(toAddr(tag, ptr), data);
   endmethod

   
   interface Server rdServer;
      interface Put request;
         method Action put(UInt#(vlog) tag) if ( init);
            let ptr = deqPtr.sub(tag);
            if ( ptr == fromInteger(depth-1)) begin
               deqPtr.upd(tag, 0);
            end
            else begin
               deqPtr.upd(tag, ptr+1);
            end
            `ifdef DEBUG   
            validQs[tag].deq;

            `endif
            buffer.rdReq(toAddr(tag, ptr));
            // $display("%m,(%t) buffer rdReq tag = %d, deqPtr = %d, addr = %d", $time, tag, deqPtr[tag], toAddr(tag, deqPtr[tag]));
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


module mkUGPipelinedBRAMVector(BRAMVector#(vlog, fifodepth, fifotype))
   provisos (
      NumAlias#(TExp#(vlog), vSz),
      Log#(fifodepth, dlog),
      // NumAlias#(TExp#(TLog#(fifodepth)), fifodepth), // fifodepth is power of 2
      Bits#(fifotype, fifotypesz),
      Add#(a__, dlog, TLog#(TMul#(TExp#(vlog), fifodepth))),
      Alias#(UInt#(vlog), tagT)
      );
   // Vector#(vSz, Reg#(UInt#(dlog))) enqPtr <- replicateM(mkReg(0)); 
   // Vector#(vSz, Reg#(UInt#(dlog))) deqPtr <- replicateM(mkReg(0));
   
   RWBramCore#(UInt#(vlog), UInt#(dlog)) enqPtrBuff <- mkUGRWBramCore;
   RWBramCore#(UInt#(vlog), UInt#(dlog)) deqPtrBuff <- mkUGRWBramCore;

   RWBramCore#(UInt#(TLog#(TMul#(vSz, fifodepth))), fifotype) buffer <- mkUGRWBramCore;
   
   Integer depth = valueOf(fifodepth);
   
   Vector#(vSz, Integer) offsets = zipWith(\* , genVector(), replicate(depth));
   
   function UInt#(TLog#(TMul#(vSz, fifodepth))) toAddr(UInt#(vlog) idx, UInt#(dlog) ptr) = fromInteger(offsets[idx])+extend(ptr);

   `ifdef DEBUG   
   Vector#(vSz, FIFOF#(void)) validQs <- replicateM(mkUGSizedFIFOF(valueOf(fifodepth)));
   `endif
   
   Reg#(Bool) init <- mkReg(False);
   Reg#(UInt#(vlog)) tagCnt <- mkReg(0);
   rule doInit if (!init);
      enqPtrBuff.wrReq(tagCnt,0);
      deqPtrBuff.wrReq(tagCnt,0);
      tagCnt <= tagCnt + 1;
      
      if ( tagCnt == fromInteger(valueOf(vSz)-1))
         init <= True;
   endrule
   
   DelayPipe#(1, Tuple2#(UInt#(vlog), fifotype)) enqReqQ <- mkDelayPipe;
   // FIFOF#(Tuple2#(UInt#(vlog), fifotype)) enqReqQ <- mkUGFIFOF;
   
   Reg#(tagT) tag_enq <- mkReg(0);
   Reg#(UInt#(dlog)) enq_ptr <- mkReg(0);
   rule doEnq if ( enqPtrBuff.rdRespValid && init);
      let {tag, data} = enqReqQ.first;
      enqReqQ.deq;

      let ptr = enq_ptr;
      if ( tag != tag_enq ) 
         ptr = enqPtrBuff.rdResp;
      enqPtrBuff.deqRdResp;
      buffer.wrReq(toAddr(tag, ptr), data);
      //$display("%m,(%t) buffer doEnq tag = %d, enqPtr = %d, addr = %d", $time, tag, ptr, toAddr(tag, ptr));      
      
      if ( ptr == fromInteger(depth-1)) begin
         ptr = 0;
      end
      else begin
         ptr = ptr + 1;
      end
      
      tag_enq <= tag;
      enqPtrBuff.wrReq(tag, ptr);
      enq_ptr <= ptr;
   endrule
   
   DelayPipe#(1, UInt#(vlog)) deqReqQ <- mkDelayPipe;
   // FIFOF#(UInt#(vlog)) deqReqQ <- mkUGFIFOF;
   
   Reg#(tagT) tag_deq <- mkReg(0);
   Reg#(UInt#(dlog)) deq_ptr <- mkReg(0);
   rule doDeq if (deqPtrBuff.rdRespValid && init);
      let tag = deqReqQ.first;
      deqReqQ.deq;

      let ptr = deq_ptr;
      if ( tag != tag_deq ) 
         ptr = deqPtrBuff.rdResp;

      deqPtrBuff.deqRdResp;
      buffer.rdReq(toAddr(tag, ptr));      
      // $display("%m,(%t) buffer doDeq tag = %d, deqPtr = %d, addr = %d", $time, tag, ptr, toAddr(tag, ptr));      
      
      if ( ptr == fromInteger(depth-1)) begin
         ptr = 0;
      end
      else begin
         ptr = ptr + 1;
      end
      
      tag_deq <= tag;
      deqPtrBuff.wrReq(tag, ptr);
      deq_ptr <= ptr;
   endrule
   


   method Action enq(fifotype data, UInt#(vlog) tag) if (init);
      //$display("%m,(%t) buffer enqPtr Buff read req tag = %d ", $time, tag);
      enqPtrBuff.rdReq(tag);
      enqReqQ.enq(tuple2(tag, data));
   endmethod

   
   interface Server rdServer;
      interface Put request;
         method Action put(UInt#(vlog) tag) if ( init);
            //$display("%m,(%t) buffer deqPtr Buff read req tag = %d ", $time, tag);      
            deqPtrBuff.rdReq(tag);
            deqReqQ.enq(tag);
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


module mkUGPipelinedURAMVector(BRAMVector#(vlog, fifodepth, fifotype))
   provisos (
      NumAlias#(TExp#(vlog), vSz),
      Log#(fifodepth, dlog),
      // NumAlias#(TExp#(TLog#(fifodepth)), fifodepth), // fifodepth is power of 2
      Bits#(fifotype, fifotypesz),
      Add#(a__, dlog, TLog#(TMul#(TExp#(vlog), fifodepth))),
      Alias#(UInt#(vlog), tagT)
      );
   // Vector#(vSz, Reg#(UInt#(dlog))) enqPtr <- replicateM(mkReg(0)); 
   // Vector#(vSz, Reg#(UInt#(dlog))) deqPtr <- replicateM(mkReg(0));
   
   RWBramCore#(UInt#(vlog), UInt#(dlog)) enqPtrBuff <- mkUGRWBramCore;
   RWBramCore#(UInt#(vlog), UInt#(dlog)) deqPtrBuff <- mkUGRWBramCore;

   RWBramCore#(UInt#(TLog#(TMul#(vSz, fifodepth))), fifotype) buffer <- mkUGRWBramCore;
   
   Integer depth = valueOf(fifodepth);
   
   Vector#(vSz, Integer) offsets = zipWith(\* , genVector(), replicate(depth));
   
   function UInt#(TLog#(TMul#(vSz, fifodepth))) toAddr(UInt#(vlog) idx, UInt#(dlog) ptr) = fromInteger(offsets[idx])+extend(ptr);

   `ifdef DEBUG   
   Vector#(vSz, FIFOF#(void)) validQs <- replicateM(mkUGSizedFIFOF(valueOf(fifodepth)));
   `endif
   
   Reg#(Bool) init <- mkReg(False);
   Reg#(UInt#(vlog)) tagCnt <- mkReg(0);
   rule doInit if (!init);
      enqPtrBuff.wrReq(tagCnt,0);
      deqPtrBuff.wrReq(tagCnt,0);
      tagCnt <= tagCnt + 1;
      
      if ( tagCnt == fromInteger(valueOf(vSz)-1))
         init <= True;
   endrule
   
   DelayPipe#(1, Tuple2#(UInt#(vlog), fifotype)) enqReqQ <- mkDelayPipe;
   // FIFOF#(Tuple2#(UInt#(vlog), fifotype)) enqReqQ <- mkUGFIFOF;
   
   Reg#(tagT) tag_enq <- mkReg(0);
   Reg#(UInt#(dlog)) enq_ptr <- mkReg(0);
   rule doEnq if ( enqPtrBuff.rdRespValid && init);
      let {tag, data} = enqReqQ.first;
      enqReqQ.deq;

      let ptr = enq_ptr;
      if ( tag != tag_enq ) 
         ptr = enqPtrBuff.rdResp;
      enqPtrBuff.deqRdResp;
      buffer.wrReq(toAddr(tag, ptr), data);
      //$display("%m,(%t) buffer doEnq tag = %d, enqPtr = %d, addr = %d", $time, tag, ptr, toAddr(tag, ptr));      
      
      if ( ptr == fromInteger(depth-1)) begin
         ptr = 0;
      end
      else begin
         ptr = ptr + 1;
      end
      
      tag_enq <= tag;
      enqPtrBuff.wrReq(tag, ptr);
      enq_ptr <= ptr;
   endrule
   
   DelayPipe#(1, UInt#(vlog)) deqReqQ <- mkDelayPipe;
   // FIFOF#(UInt#(vlog)) deqReqQ <- mkUGFIFOF;
   
   Reg#(tagT) tag_deq <- mkReg(0);
   Reg#(UInt#(dlog)) deq_ptr <- mkReg(0);
   rule doDeq if (deqPtrBuff.rdRespValid && init);
      let tag = deqReqQ.first;
      deqReqQ.deq;

      let ptr = deq_ptr;
      if ( tag != tag_deq ) 
         ptr = deqPtrBuff.rdResp;

      deqPtrBuff.deqRdResp;
      buffer.rdReq(toAddr(tag, ptr));      
      // $display("%m,(%t) buffer doDeq tag = %d, deqPtr = %d, addr = %d", $time, tag, ptr, toAddr(tag, ptr));      
      
      if ( ptr == fromInteger(depth-1)) begin
         ptr = 0;
      end
      else begin
         ptr = ptr + 1;
      end
      
      tag_deq <= tag;
      deqPtrBuff.wrReq(tag, ptr);
      deq_ptr <= ptr;
   endrule
   


   method Action enq(fifotype data, UInt#(vlog) tag) if (init);
      //$display("%m,(%t) buffer enqPtr Buff read req tag = %d ", $time, tag);
      enqPtrBuff.rdReq(tag);
      enqReqQ.enq(tuple2(tag, data));
   endmethod

   
   interface Server rdServer;
      interface Put request;
         method Action put(UInt#(vlog) tag) if ( init);
            //$display("%m,(%t) buffer deqPtr Buff read req tag = %d ", $time, tag);      
            deqPtrBuff.rdReq(tag);
            deqReqQ.enq(tag);
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


