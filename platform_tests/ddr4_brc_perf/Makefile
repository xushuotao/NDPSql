BASEDIR=$(abspath ../../platform)
CONNECTALDIR?=$(BASEDIR)/build_tools/connectal/


COREDIR=$(BASEDIR)/core-scripts/
MIGDIR=$(BASEDIR)/xilinx/ddr4_v2_2/

BSVDIR=$(BASEDIR)/dram_ctrl/ddr4/:$(MIGDIR):$(BASEDIR)/../bsvlib


S2H_INTERFACES = Ddr4PerfRequest:Ddr4Perf.request
H2S_INTERFACES = Ddr4Perf:Ddr4PerfIndication:host



CONNECTALFLAGS += -D IMPORT_HOSTIF -D XILINX_SYS_CLK

CONNECTALFLAGS += --bsvpath $(BSVDIR)
CONNECTALFLAGS += --bscflags " -D BRC "


BSVFILES = Ddr4Perf.bsv
CPPFILES = testddr4.cpp

ifeq ($(BOARD), vcu108)

# below are for ddr4_v2_0
CONNECTALFLAGS += \
		--verilog $(MIGDIR)/ddr4_brc_wrapper.v \
		--xci $(CONNECTALDIR)/out/$(BOARD)/ddr4_brc/ddr4_brc.xci \
		--implconstraint $(MIGDIR)/ddr4_0.xdc

DDR4_V = $(CONNECTALDIR)/out/$(BOARD)/ddr4_brc/ddr4_brc_stub.v

prebuild:: $(DDR4_V)

$(DDR4_V): $(COREDIR)/synth-ddr4-brc.tcl
	(cd $(BOARD); vivado -mode batch -source $(COREDIR)/synth-ddr4-brc.tcl)

endif


PIN_TYPE = Top_Pins
PIN_TYPE_INCLUDE = Ddr4Perf
AUTOTOP = --interface pins:Ddr4Perf.pins

include $(CONNECTALDIR)/Makefile.connectal
