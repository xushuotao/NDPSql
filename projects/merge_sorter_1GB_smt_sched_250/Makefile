BASEDIR=$(abspath ../../platform)
CONNECTALDIR?=$(BASEDIR)/build_tools/connectal/

MIGDIR=$(abspath ../../platform/xilinx/ddr4_v2_2/)

BSVDIR=$(BASEDIR)/lib/dram_ctrl_sim/ddr4/:$(BASEDIR)/lib:$(BASEDIR)/../bsvlib/sort:$(BASEDIR)/../bsvlib/:$(MIGDIR)


S2H_INTERFACES = SorterRequest:Sorter.request
H2S_INTERFACES = Sorter:SorterIndication:host



CONNECTALFLAGS += -D IMPORT_HOSTIF -D XILINX_SYS_CLK

CONNECTALFLAGS += --bsvpath $(BSVDIR)

CONNECTALFLAGS += -D SORT_SZ_L0=16384 -D SORT_SZ_L1=4194304 -D SORT_SZ_L2=1073741824 --bscflags=" -steps-max-intervals 10000000 +RTS -K1G -RTS"

CONNECTALFLAGS += --verilog $(abspath ../../verilog)


BSVFILES = Sorter.bsv
CPPFILES = testsorter.cpp

ifeq ($(BOARD),vcu108)
CONNECTALFLAGS += \
			--implconstraint ../../platform/xilinx/constraints/pcieclock-vcu108.xdc
else
ifeq ($(BOARD),vcu118)
CONNECTALFLAGS += \
			--implconstraint ../../platform/xilinx/constraints/pcieclock-vcu118.xdc
endif
endif



ifeq ($(BOARD), $(filter $(BOARD), vcu108 vcu118))
# below are for ddr4_v2_0
CONNECTALFLAGS += \
		--verilog $(MIGDIR)/ddr4_wrapper.v \
		--xci $(CONNECTALDIR)/out/$(BOARD)/ddr4_0/ddr4_0.xci

ifeq ($(BOARD), vcu108)
CONNECTALFLAGS += --implconstraint $(MIGDIR)/ddr4_vcu108.xdc
else
CONNECTALFLAGS += --implconstraint $(MIGDIR)/ddr4_vcu118.xdc
endif

DDR4_V = $(CONNECTALDIR)/out/$(BOARD)/ddr4_0/ddr4_0_stub.v

prebuild:: $(DDR4_V)

$(DDR4_V): $(BASEDIR)/core-scripts/synth-ddr4.tcl
	(cd $(BOARD); vivado -mode batch -source $(BASEDIR)/core-scripts/synth-ddr4.tcl)

endif



PIN_TYPE = Top_Pins
PIN_TYPE_INCLUDE = Sorter
AUTOTOP = --interface pins:Sorter.pins

include $(CONNECTALDIR)/Makefile.connectal
