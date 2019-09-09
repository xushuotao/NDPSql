import ControllerTypes::*;
import AuroraCommon::*;
import AuroraImportFmc1::*;
import FlashCtrlVirtex::*;
import FlashCtrlModel::*;
import GetPut::*;
import FIFO::*;

`include "ConnectalProjectConfig.bsv"

// std::string db_path = "/mnt/nvme0/shuotao/tpch/.farms/monetdb-sf300/bat/";
// std::string shipdate = "10/1051";
// std::string l_returnflag = "10/1047";
// std::string l_linestatus = "10/1050";
// std::string l_quantity = "10/1043";
// std::string l_extendedprice = "10/1044";
// std::string l_discount = "10/1045";
// std::string l_tax = "10/1046";
// size_t nRows = 1799989091;

Bool debug = False;

`ifdef SVDPI
interface XSimFlashIfc;
   method Bit#(128) getData(Bit#(64) pageaddr, Bit#(32) wordOffset);
endinterface
import "BVI" XSimFlash =
module mkXSimFlashBVI(XSimFlashIfc);
   method beat getData(pgaddr, wordOffset) ready (RDY_getData);
   schedule (getData) CF (getData);
endmodule 
`else
import "BDPI" function Bit#(64) getBaseAddr(String fname);
import "BDPI" function Bit#(128) getData(Bit#(64) pageaddr, Bit#(32) wordOffset);
import "BDPI" function Bit#(64) getNumRows(String fname);
`endif

function Bit#(64) toPageAddr(FlashCmd cmd, Bit#(1) card);
   Bit#(TLog#(BlocksPerCE)) blockAddr = truncate(cmd.block);
   Bit#(TLog#(PagesPerBlock)) pageAddr = truncate(cmd.page);
   // Bit#(1) card = fromInteger(i);
   return extend({blockAddr, pageAddr, cmd.chip, cmd.bus, card});
endfunction


(* synthesize *)
module mkEmulatedFlashCtrl#(Bit#(1) i)(FlashCtrlVirtexIfc);
   FIFO#(FlashCmd) flashCmdQ <- mkSizedFIFO(16); //should not have back pressure
   FIFO#(Tuple2#(Bit#(128), TagT)) wrDataQ <- mkSizedFIFO(16); //TODO size?
   FIFO#(Tuple2#(Bit#(128), TagT)) rdDataQ <- mkSizedFIFO(16); //TODO size?
   FIFO#(TagT) wrReqQ <- mkSizedFIFO(valueOf(NumTags)); //TODO size?
   FIFO#(Tuple2#(TagT, StatusT)) ackQ <- mkSizedFIFO(valueOf(NumTags)); //TODO size?
   
   
   FIFO#(Tuple2#(Bit#(64), TagT)) readReqQ <- mkSizedFIFO(128);
   FIFO#(TagT) writeReqQ <- mkSizedFIFO(1);
   
   Reg#(Bit#(32)) readCnt <- mkReg(0);
   Reg#(Bit#(32)) writeCnt <- mkReg(0);
   Reg#(Bit#(64)) cycles <- mkReg(0);
   
   Reg#(Bit#(64)) prevCycleRd <- mkReg(-1);
   Reg#(Bit#(64)) prevCycleWr <- mkReg(-1);
   
   Reg#(Bit#(8)) outstandingWrite[2] <- mkCReg(2, 0);
   Reg#(Bit#(64)) readBeatCnt <- mkReg(0);         
   
   `ifdef SVDPI
   let xsimFlash <- mkXSimFlashBVI;
   `endif
   (* descending_urgency="doDummyRead, doDummyWrite, doFlashCmd" *)
   
   rule incrCycle;
      cycles <= cycles + 1;
   endrule
   
   rule doFlashCmd;
      let v <- toGet(flashCmdQ).get;
      case (v.op) 
         READ_PAGE: readReqQ.enq(tuple2(toPageAddr(v, i),v.tag));
         WRITE_PAGE: begin
                        writeReqQ.enq(v.tag);
                        wrReqQ.enq(v.tag);
                        outstandingWrite[0] <= outstandingWrite[0] + 1;
                     end
         ERASE_BLOCK: ackQ.enq(tuple2(v.tag, ERASE_DONE));
         
         default: noAction;
      endcase
   endrule
   

   
   rule doDummyRead;// if (cycles - prevCycleRd>=2);
      let {pageAddr, readTag} = readReqQ.first;
      if ( readCnt == fromInteger(pageWords-1) ) begin
         readCnt <= 0;
         readReqQ.deq;
      end
      else begin
         readCnt <= readCnt + 1;
      end
      
      prevCycleRd <= cycles;
      // if ( cycles - prevCycleRd > 1 ) 
      //    if (debug) $display("(%d) %m gap in sending dumpy read data .. prevCycle = %d, gap = %d", cycles, prevCycleRd, cycles - prevCycleRd);
      // if (debug) $display("(%d) %m sending dumpy read data ... tag = %d, readCnt = %d", cycles, readTag, readCnt);
      
      if ( readCnt == 0) begin
         if (debug) $display("%m starting read for tag = %d @ cycles = %d", readTag, cycles);
      end
      Bit#(128) data = 
      `ifdef SVDPI
      xsimFlash.getData(pageAddr, readCnt);
      `else
      getData(pageAddr, readCnt);
      `endif
      if (debug) $display("(%m) EmulatedFlash ReadWord pageAddr = %d, readCnt = %d, got data = %h", pageAddr, readCnt, data);
      rdDataQ.enq(tuple2(data, readTag));
      readBeatCnt <= readBeatCnt + 1;
   endrule
   
   rule doDummyWrite;
      let writeTag = writeReqQ.first;
      if ( writeCnt == fromInteger(pageWords-1) ) begin
         writeCnt <= 0;
         writeReqQ.deq;
         ackQ.enq(tuple2(writeTag, WRITE_DONE));
         outstandingWrite[1] <= outstandingWrite[1] - 1;
      end
      else begin
         writeCnt <= writeCnt + 1;
      end
      prevCycleWr <= cycles;
      // if ( cycles - prevCycleWr > 1 ) 
      //    if (debug) $display("(%d) %m gap in receiving dumpy write data .. prevCycle = %d, gap = %d", cycles, prevCycleWr, cycles - prevCycleWr);
      // if (debug) $display("(%d) %m receiving dumpy write data ... tag = %d, writeCnt = %d", cycles, writeTag, writeCnt);
      let data = wrDataQ.first;
      wrDataQ.deq;
   endrule
   

   interface FlashCtrlUser user;
      method Action sendCmd (FlashCmd cmd); 
		 flashCmdQ.enq(cmd);
	  endmethod

      method Action writeWord (Tuple2#(Bit#(128), TagT) taggedData) if (outstandingWrite[0] > 0);
		 wrDataQ.enq(taggedData);
	  endmethod
			
      method ActionValue#(Tuple2#(Bit#(128), TagT)) readWord ();
		 rdDataQ.deq();
		 return rdDataQ.first();
	  endmethod

      method ActionValue#(TagT) writeDataReq();
		 wrReqQ.deq();
		 return wrReqQ.first();
	  endmethod

      method ActionValue#(Tuple2#(TagT, StatusT)) ackStatus ();
		 ackQ.deq();
		 return ackQ.first();
	  endmethod
   endinterface

   interface FCVirtexDebug debug = ?;

   interface Aurora_Pins aurora = ?;
   
   interface FCAuroraStatus auroraStatus;
      method Bit#(1) channel_up;
         return 1;
      endmethod
      method Bit#(4) lane_up;
         return -1;
      endmethod
   endinterface
endmodule
