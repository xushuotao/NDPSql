package AuroraCommon;

/*
export Aurora_Pins(..);
export AuroraExtImportIfc(..);
export AuroraControllerIfc(..);

export Aurora_Clock_Pins;
export mkGtxClockImport, GtxClockImportIfc::*;

export AuroraImportIfc(..);
*/

import FIFO::*;
import Clocks :: *;
import DefaultValue :: *;
import Xilinx :: *;
import XilinxCells :: *;
import ConnectalXilinxCells::*;
import ConnectalClocks::*;

import AuroraGearbox::*;

typedef 2 AuroraExtCount;
//typedef 4 AuroraExtQuad;

(* always_enabled, always_ready *)
interface Aurora_Clock_Pins;
	//(* prefix = "", result = "" *)
	method Action gt_clk_p(Bit#(1) v);
	//(* prefix = "", result = "" *)
	method Action gt_clk_n(Bit#(1) v);
   // interface Clock gt_clk_deleteme_unused_clock;
        interface Clock gt_clk_p_deleteme_unused_clock;
        interface Clock gt_clk_n_deleteme_unused_clock;
endinterface

interface AuroraExtImportIfc#(numeric type lanes);
	interface Clock aurora_clk0;
	interface Clock aurora_clk1;
	interface Clock aurora_clk2;
	interface Clock aurora_clk3;
	interface Reset aurora_rst0;
	interface Reset aurora_rst1;
	interface Reset aurora_rst2;
	interface Reset aurora_rst3;

	(* prefix = "" *)
	interface Aurora_Pins#(1) aurora0;
	(* prefix = "" *)
	interface Aurora_Pins#(1) aurora1;
	(* prefix = "" *)
	interface Aurora_Pins#(1) aurora2;
	(* prefix = "" *)
	interface Aurora_Pins#(1) aurora3;
	(* prefix = "" *)
	interface AuroraControllerIfc#(64) user0;
	(* prefix = "" *)
	interface AuroraControllerIfc#(64) user1;
	(* prefix = "" *)
	interface AuroraControllerIfc#(64) user2;
	(* prefix = "" *)
	interface AuroraControllerIfc#(64) user3;

	`ifdef BSIM
	method Action setNodeIdx(Bit#(8) idx);
	`endif
endinterface

interface AuroraImportIfc#(numeric type lanes);
	interface Clock aurora_clk;
	interface Reset aurora_rst;
	(* prefix = "" *)
	interface Aurora_Pins#(lanes) aurora;
	(* prefix = "" *)
	interface AuroraControllerIfc#(TMul#(lanes,32)) user;
endinterface

interface AuroraControllerIfc#(numeric type width);
	interface Reset aurora_rst_n;
		
	method Bit#(1) channel_up;
	method Bit#(4) lane_up;
	method Bit#(1) hard_err;
	method Bit#(1) soft_err;
	method Bit#(8) data_err_count;

	method Action send(Bit#(width) tx);
	method ActionValue#(Bit#(width)) receive();
endinterface

(* always_enabled, always_ready *)
interface Aurora_Pins#(numeric type lanes);
	(* prefix = "", result = "RXN" *)
	method Action rxn_in(Bit#(lanes) rxn_i);
	(* prefix = "", result = "RXP" *)
	method Action rxp_in(Bit#(lanes) rxp_i);

	(* prefix = "", result = "TXN" *)
	method Bit#(lanes) txn_out();
	(* prefix = "", result = "TXP" *)
	method Bit#(lanes) txp_out();
        
endinterface

interface GtClockImportIfc;
	interface Aurora_Clock_Pins aurora_clk;
	interface Clock gt_clk_p_ifc;
	interface Clock gt_clk_n_ifc;
endinterface

(* synthesize *)
module mkGtClockImport (GtClockImportIfc);
   `ifndef BSIM
   // default_clock no_clock;
   B2C1 i_gt_clk_p <- mkB2C1();
   B2C1 i_gt_clk_n <- mkB2C1();
   

   interface Aurora_Clock_Pins aurora_clk;
      method Action gt_clk_p(Bit#(1) v);
	 i_gt_clk_p.inputclock(v);
      endmethod
      method Action gt_clk_n(Bit#(1) v);
	 i_gt_clk_n.inputclock(v);
      endmethod
      interface Clock gt_clk_p_deleteme_unused_clock = i_gt_clk_p.c; // These clocks are deleted from the netlist by the synth.tcl script
      interface Clock gt_clk_n_deleteme_unused_clock = i_gt_clk_n.c;
   endinterface
   interface Clock gt_clk_p_ifc = i_gt_clk_p.c;
   interface Clock gt_clk_n_ifc = i_gt_clk_n.c;
   `else
      Clock clk <- exposeCurrentClock;
         
      interface Aurora_Clock_Pins aurora_clk;
         interface Clock gt_clk_p_deleteme_unused_clock = clk; // These clocks are deleted from the netlist by the synth.tcl script
         interface Clock gt_clk_n_deleteme_unused_clock = clk;
      endinterface
      interface Clock gt_clk_p_ifc = clk;
      interface Clock gt_clk_n_ifc = clk;
  `endif
endmodule



interface AuroraIfc;
	method Action send(DataIfc data, PacketType ptype);
	method ActionValue#(Tuple2#(DataIfc, PacketType)) receive;
	method Tuple4#(Bit#(32), Bit#(32), Bit#(32), Bit#(32)) getDebugCnts;

	interface Clock clk;
	interface Reset rst;

	method Bit#(1) channel_up;
	method Bit#(4) lane_up;
	method Bit#(1) hard_err;
	method Bit#(1) soft_err;
	method Bit#(8) data_err_count;
	
	(* prefix = "" *)
	interface Aurora_Pins#(4) aurora;
endinterface



endpackage: AuroraCommon
