BASEDIR=$(abspath ../../)
PLATFORMDIR=$(abspath ../../platform)
CONNECTALDIR?=$(PLATFORMDIR)/build_tools/connectal/

MIGDIR=$(abspath ../../platform/xilinx/ddr4_v2_2/)

BSVDIR=$(BASEDIR)/bsvlib:$(MIGDIR):$(PLATFORMDIR)/lib/dram_ctrl_sim/ddr4:$(PLATFORMDIR)/lib/


S2H_INTERFACES = Ddr4PerfRequest:Ddr4Perf.request
H2S_INTERFACES = Ddr4Perf:Ddr4PerfIndication:host



CONNECTALFLAGS += -D IMPORT_HOSTIF -D XILINX_SYS_CLK

CONNECTALFLAGS += --bsvpath $(BSVDIR)


BSVFILES = Ddr4Perf.bsv
CPPFILES = testddr4.cpp

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

SYNCFIFO_784_32 = $(CONNECTALDIR)/out/$(BOARD)/sync_bram_fifo_w784_d32/sync_bram_fifo_w784_d32.xci
SYNCFIFO_640_32 = $(CONNECTALDIR)/out/$(BOARD)/sync_bram_fifo_w640_d32/sync_bram_fifo_w640_d32.xci

CONNECTALFLAGS += \
		--xci $(SYNCFIFO_784_32) \
		--xci $(SYNCFIFO_640_32)



prebuild:: $(DDR4_V) $(SYNCFIFO_784_32) $(SYNCFIFO_640_32)

$(DDR4_V): $(PLATFORMDIR)/core-scripts/synth-ddr4.tcl
	(cd $(BOARD); vivado -mode batch -source $(PLATFORMDIR)/core-scripts/synth-ddr4.tcl)

$(SYNCFIFO_784_32): $(PLATFORMDIR)/core-scripts/synth_sync_bram_fifo.tcl
	(cd $(PROJECTDIR); vivado -mode batch -source $^ -tclargs 784 32)

$(SYNCFIFO_640_32): $(PLATFORMDIR)/core-scripts/synth_sync_bram_fifo.tcl
	(cd $(PROJECTDIR); vivado -mode batch -source $^ -tclargs 640 32)

endif


PIN_TYPE = Top_Pins
PIN_TYPE_INCLUDE = Ddr4Perf
AUTOTOP = --interface pins:Ddr4Perf.pins

include $(CONNECTALDIR)/Makefile.connectal
