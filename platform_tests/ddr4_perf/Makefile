BASEDIR=$(abspath ../../)
PLATFORMDIR=$(abspath ../../platform)
CONNECTALDIR?=$(PLATFORMDIR)/build_tools/connectal/

MIGDIR=$(abspath ../../platform/xilinx/ddr4_v2_2/)

BSVDIR=$(BASEDIR)/bsvlib:$(MIGDIR):$(PLATFORMDIR)/lib/dram_ctrl_sim/ddr4


S2H_INTERFACES = Ddr4PerfRequest:Ddr4Perf.request
H2S_INTERFACES = Ddr4Perf:Ddr4PerfIndication:host



CONNECTALFLAGS += -D IMPORT_HOSTIF -D XILINX_SYS_CLK

CONNECTALFLAGS += --bsvpath $(BSVDIR)


BSVFILES = Ddr4Perf.bsv
CPPFILES = testddr4.cpp

ifeq ($(BOARD), vcu108)

# below are for ddr4_v2_0
CONNECTALFLAGS += \
		--verilog $(MIGDIR)/ddr4_wrapper.v \
		--xci $(CONNECTALDIR)/out/$(BOARD)/ddr4_0/ddr4_0.xci \
		--implconstraint $(MIGDIR)/ddr4_0.xdc

DDR4_V = $(CONNECTALDIR)/out/$(BOARD)/ddr4_0/ddr4_0_stub.v

prebuild:: $(DDR4_V)

$(DDR4_V): $(PLATFORMDIR)/core-scripts/synth-ddr4.tcl
	(cd $(BOARD); vivado -mode batch -source $(PLATFORMDIR)/core-scripts/synth-ddr4.tcl)

endif


PIN_TYPE = Top_Pins
PIN_TYPE_INCLUDE = Ddr4Perf
AUTOTOP = --interface pins:Ddr4Perf.pins

include $(CONNECTALDIR)/Makefile.connectal
