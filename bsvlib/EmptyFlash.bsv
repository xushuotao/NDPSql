import ControllerTypes::*;
import AuroraCommon::*;
import AuroraImportFmc1::*;
import FlashCtrlVirtex::*;
import FlashCtrlModel::*;
import GetPut::*;
import FIFO::*;

// (* synthesize *)
module mkEmptyFlashCtrl#(function Bit#(128) genData(Bit#(64) beatCnt))(FlashCtrlVirtexIfc);
   FIFO#(FlashCmd) flashCmdQ <- mkSizedFIFO(16); //should not have back pressure
   FIFO#(Tuple2#(Bit#(128), TagT)) wrDataQ <- mkSizedFIFO(16); //TODO size?
   FIFO#(Tuple2#(Bit#(128), TagT)) rdDataQ <- mkSizedFIFO(16); //TODO size?
   FIFO#(TagT) wrReqQ <- mkSizedFIFO(valueOf(NumTags)); //TODO size?
   FIFO#(Tuple2#(TagT, StatusT)) ackQ <- mkSizedFIFO(valueOf(NumTags)); //TODO size?
   
   
   FIFO#(TagT) readReqQ <- mkSizedFIFO(128);
   FIFO#(TagT) writeReqQ <- mkSizedFIFO(1);
   
   Reg#(Bit#(32)) readCnt <- mkReg(0);
   Reg#(Bit#(32)) writeCnt <- mkReg(0);
   Reg#(Bit#(64)) cycles <- mkReg(0);
   
   Reg#(Bit#(64)) prevCycleRd <- mkReg(-1);
   Reg#(Bit#(64)) prevCycleWr <- mkReg(-1);
   
   Reg#(Bit#(8)) outstandingWrite[2] <- mkCReg(2, 0);
   Reg#(Bit#(64)) readBeatCnt <- mkReg(0);         
   (* descending_urgency="doDummyRead, doDummyWrite, doFlashCmd" *)
   
   rule incrCycle;
      cycles <= cycles + 1;
   endrule
   
   rule doFlashCmd;
      let v <- toGet(flashCmdQ).get;
      case (v.op) 
         READ_PAGE: readReqQ.enq(v.tag);
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
      let readTag = readReqQ.first;
      if ( readCnt == fromInteger(pageWords-1) ) begin
         readCnt <= 0;
         readReqQ.deq;
      end
      else begin
         readCnt <= readCnt + 1;
      end
      
      prevCycleRd <= cycles;
      // if ( cycles - prevCycleRd > 1 ) 
      //    $display("(%d) %m gap in sending dumpy read data .. prevCycle = %d, gap = %d", cycles, prevCycleRd, cycles - prevCycleRd);
      // $display("(%d) %m sending dumpy read data ... tag = %d, readCnt = %d", cycles, readTag, readCnt);
      
      if ( readCnt == 0) begin
         $display("%m starting read for tag = %d @ cycles = %d", readTag, cycles);
      end
      rdDataQ.enq(tuple2(genData(readBeatCnt), readTag));
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
      //    $display("(%d) %m gap in receiving dumpy write data .. prevCycle = %d, gap = %d", cycles, prevCycleWr, cycles - prevCycleWr);
      // $display("(%d) %m receiving dumpy write data ... tag = %d, writeCnt = %d", cycles, writeTag, writeCnt);
      let data = wrDataQ.first;
      wrDataQ.deq;
   endrule
   
   // let currClock <- exposeCurrentClock;
   // let currReset <- exposeCurrentReset;

   // AuroraIfc auroraIntra1 <- mkAuroraIntra1(currClock, currClock,currClock, currReset);

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

   // (* always_enabled, always_ready *)
   interface Aurora_Pins aurora = ?;//auroraIntra1.aurora;
   //    // (* always_enabled, always_ready *)
   //    method Action rxn_in(Bit#(4) rxn_i);
   //       $display("To Enable");
   //    endmethod
   //    // (* always_enabled, always_ready *)
   //    method Action rxp_in(Bit#(4) rxp_i);
   //       $display("To Enable");
   //    endmethod

   //    method Bit#(4) txn_out();
   //       return 1;
   //    endmethod

   //    method Bit#(4) txp_out();
   //       return 1;
   //     endmethod
   // endinterface

   
   
   interface FCAuroraStatus auroraStatus;
      method Bit#(1) channel_up;
         return 1;
      endmethod
      method Bit#(4) lane_up;
         return -1;
      endmethod
   endinterface
endmodule
