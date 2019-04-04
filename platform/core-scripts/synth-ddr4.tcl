source "board.tcl"
source "$connectaldir/scripts/connectal-synth-ip.tcl"

connectal_synth_ip ddr4 2.2 ddr4_0 [list CONFIG.C0_CLOCK_BOARD_INTERFACE {Custom} CONFIG.C0.DDR4_InputClockPeriod {3332} CONFIG.C0.DDR4_MemoryPart {EDY4016AABG-DR-F} CONFIG.C0.DDR4_DataWidth {80} CONFIG.C0.BANK_GROUP_WIDTH {1} CONFIG.System_Clock {No_Buffer} CONFIG.Debug_Signal {Disable}]

# [list CONFIG.C0_CLOCK_BOARD_INTERFACE {Custom} CONFIG.Example_TG {SIMPLE_TG} CONFIG.C0.DDR4_InputClockPeriod {3332} CONFIG.C0.DDR4_MemoryPart {EDY4016AABG-DR-F} CONFIG.C0.DDR4_DataWidth {80} CONFIG.Debug_Signal {Disable} CONFIG.C0.BANK_GROUP_WIDTH {1} CONFIG.SystemClock {Differential}]
