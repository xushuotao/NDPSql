source board.tcl
source $connectaldir/scripts/connectal-synth-ip.tcl

connectal_synth_ip aurora_8b10b 11.1 aurora_8b10b_fmc2 [list CONFIG.C_AURORA_LANES {4} CONFIG.C_LANE_WIDTH {4} CONFIG.C_LINE_RATE {4.4} CONFIG.C_REFCLK_FREQUENCY {275.000} CONFIG.Interface_Mode {Streaming} CONFIG.C_GT_LOC_16 {4} CONFIG.C_GT_LOC_15 {3} CONFIG.C_GT_LOC_14 {2} CONFIG.C_GT_LOC_13 {1} CONFIG.C_GT_LOC_1 {X}]
#[list CONFIG.C_AURORA_LANES {4} CONFIG.C_LANE_WIDTH {4} CONFIG.C_LINE_RATE {4.4} CONFIG.C_REFCLK_FREQUENCY {275} CONFIG.C_INIT_CLK {110.0} CONFIG.Interface_Mode {Streaming} CONFIG.C_GT_LOC_4 {4} CONFIG.C_GT_LOC_3 {3} CONFIG.C_GT_LOC_2 {2} CONFIG.C_START_QUAD {Quad_X0Y3} CONFIG.C_START_LANE {X0Y12} CONFIG.C_REFCLK_SOURCE {MGTREFCLK1 of Quad X0Y3} CONFIG.CHANNEL_ENABLE {X0Y12 X0Y13 X0Y14 X0Y15}]
