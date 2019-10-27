// Copyright (c) 2017 Massachusetts Institute of Technology
//
// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use, copy,
// modify, merge, publish, distribute, sublicense, and/or sell copies
// of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
// BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
// ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import BRAMCore::*;
import RegFile::*;
import FIFOF::*;
import GetPut::*;
import SpecialFIFOs::*;
import DelayPipe::*;

interface RWBramCore#(type addrT, type dataT);
   method Action wrReq(addrT a, dataT d);
   method Action rdReq(addrT a);
   method dataT rdResp;
   method Bool rdRespValid;
   method Action deqRdResp;
endinterface

module mkRWBramCore(RWBramCore#(addrT, dataT)) provisos(
   Bits#(addrT, addrSz), Bits#(dataT, dataSz),
   Bounded#(addrT)
   );
   
   Bool useBRAM = valueOf(TExp#(addrSz)) > 8 && valueOf(dataSz) >= 256;
   
   BRAM_DUAL_PORT#(addrT, dataT) bram   = ?;
   BRAM_PORT#(addrT, dataT)      wrPort = ?;
   BRAM_PORT#(addrT, dataT)      rdPort = ?;
   
   RegFile#(addrT, dataT)        rf  = ?;

   // 1 elem pipeline fifo to add guard for read req/resp
   // must be 1 elem to make sure rdResp is not corrupted
   // BRAMCore should not change output if no req is made
   FIFOF#(void) rdReqQ <- mkPipelineFIFOF;
   Reg#(addrT) rdAddr = ?;
   FIFOF#(Tuple2#(addrT, dataT)) wrReqQ = ?;
   
   if ( useBRAM ) begin
      bram   <- mkBRAMCore2(valueOf(TExp#(addrSz)), False);
      wrPort = bram.a;
      rdPort = bram.b;
   end
   else begin
      rf <- mkRegFileFull;
      rdAddr <- mkRegU;
      wrReqQ <- mkPipelineFIFOF;
   end

   if (!useBRAM) begin
      (*fire_when_enabled*)
      rule deqWrReq;
         let {addr, data} <- toGet(wrReqQ).get;
         rf.upd(addr, data);
      endrule
   end
         
   method Action wrReq(addrT a, dataT d);
      if ( useBRAM )
         wrPort.put(True, a, d);
      else
         wrReqQ.enq(tuple2(a,d));
   endmethod
   
   method Action rdReq(addrT a);
      if ( useBRAM ) begin
         rdReqQ.enq(?);
         rdPort.put(False, a, ?);
      end
      else begin
         rdReqQ.enq(?);
         rdAddr <= a;
      end
   endmethod
   
   method dataT rdResp if(rdReqQ.notEmpty);
      let retval = ?;
      if ( useBRAM )
         retval = rdPort.read;
      else
         retval = rf.sub(rdAddr);
      return retval;
   endmethod
   
   method rdRespValid = rdReqQ.notEmpty;
   
   method Action deqRdResp;
      rdReqQ.deq;
   endmethod
endmodule

module mkUGRWBramCore(RWBramCore#(addrT, dataT)) provisos(
   Bits#(addrT, addrSz), Bits#(dataT, dataSz),
   Bounded#(addrT)
   );
   
   Bool useBRAM = valueOf(TExp#(addrSz)) > 8 && valueOf(dataSz) >= 256;
   
   BRAM_DUAL_PORT#(addrT, dataT) bram   = ?;
   BRAM_PORT#(addrT, dataT)      wrPort = ?;
   BRAM_PORT#(addrT, dataT)      rdPort = ?;
   
   RegFile#(addrT, dataT)        rf  = ?;

   // 1 elem pipeline fifo to add guard for read req/resp
   // must be 1 elem to make sure rdResp is not corrupted
   // BRAMCore should not change output if no req is made
   DelayPipe#(1, void) rdReqQ <- mkDelayPipe;
   Reg#(addrT) rdAddr = ?;
   DelayPipe#(1, Tuple2#(addrT, dataT)) wrReqQ = ?;
   
   if ( useBRAM ) begin
      bram   <- mkBRAMCore2(valueOf(TExp#(addrSz)), False);
      wrPort = bram.a;
      rdPort = bram.b;
   end
   else begin
      rf <- mkRegFileFull;
      rdAddr <- mkRegU;
      wrReqQ <- mkDelayPipe;
   end

   if (!useBRAM) begin
      (*fire_when_enabled*)
      rule deqWrReq if ( wrReqQ.notEmpty);
         let {addr, data} = wrReqQ.first;
         wrReqQ.deq;
         rf.upd(addr, data);
      endrule
   end
         
   method Action wrReq(addrT a, dataT d);
      if ( useBRAM )
         wrPort.put(True, a, d);
      else
         wrReqQ.enq(tuple2(a,d));
   endmethod
   
   method Action rdReq(addrT a);
      if ( useBRAM ) begin
         rdReqQ.enq(?);
         rdPort.put(False, a, ?);
      end
      else begin
         rdReqQ.enq(?);
         rdAddr <= a;
      end
   endmethod
   
   method dataT rdResp;// if(rdReqQ.notEmpty);
      let retval = ?;
      if ( useBRAM )
         retval = rdPort.read;
      else
         retval = rf.sub(rdAddr);
      return retval;
   endmethod
   
   method rdRespValid = rdReqQ.notEmpty;
   
   method Action deqRdResp;
      rdReqQ.deq;
   endmethod
endmodule
