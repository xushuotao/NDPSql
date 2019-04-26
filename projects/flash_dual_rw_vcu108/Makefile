BASEDIR=$(abspath ../../platform)
CONNECTALDIR?=$(BASEDIR)/build_tools/connectal/


BSVDIR=$(BASEDIR)/xilinx/aurora_8b10b_fmc_vcu108:$(BASEDIR)/controller/src/common:$(BASEDIR)/controller/src/model_virtex:$(BASEDIR)/controller/src/hw_virtex:$(BASEDIR)/lib/:$(BASEDIR)/../bsvlib


S2H_INTERFACES = FlashRequest:FlashTop.request
H2S_INTERFACES = FlashTop:FlashIndication:host
MEM_READ_INTERFACES = lFlashTop.dmaReadClient
MEM_WRITE_INTERFACES = lFlashTop.dmaWriteClient

CONNECTALFLAGS += -D IMPORT_HOSTIF -D XILINX_SYS_CLK --mainclockperiod=8 --derivedclockperiod=9.091 -D DataBusWidth=256 -D USE_WIDE_WIDTH
# CONNECTALFLAGS += -D IMPORT_HOSTIF -D XILINX_SYS_CLK --derivedclockperiod=9.091 -D DataBusWidth=128

CONNECTALFLAGS += --bsvpath $(BSVDIR)

ifneq ($(BOARD), vcu108)
CONNECTALFLAGS += --bscflags="-D BSIM -D SIM_DMA_WRITE_LATENCY=1"
endif

BSVFILES = FlashTop.bsv
CPPFILES = testfile.cpp flashmanage.cpp mmap_util.cpp ../../util/filemap/filemap.cpp

CONNECTALFLAGS += -l boost_system -l boost_filesystem -l boost_thread -I ../../util/filemap/ --cflags=" --std=c++11 " --nonstrict

ifeq ($(BOARD), vcu108)

CONNECTALFLAGS += \
		--implconstraint $(BASEDIR)/xilinx/constraints/pcieclock-vcu108.xdc \
		--verilog $(BASEDIR)/xilinx/aurora_8b10b_fmc_vcu108/ \
		--xci $(CONNECTALDIR)/out/$(BOARD)/aurora_8b10b_fmc1/aurora_8b10b_fmc1.xci \
		--xci $(CONNECTALDIR)/out/$(BOARD)/aurora_8b10b_fmc2/aurora_8b10b_fmc2.xci \
		--implconstraint $(BASEDIR)/xilinx/aurora_8b10b_fmc_vcu108/aurora_8b10b_fmc_exdes.xdc


AURORA_INTRA1 = $(CONNECTALDIR)/out/$(BOARD)/aurora_8b10b_fmc1/aurora_8b10b_fmc1_stub.v
AURORA_INTRA2 = $(CONNECTALDIR)/out/$(BOARD)/aurora_8b10b_fmc2/aurora_8b10b_fmc2_stub.v

prebuild:: $(AURORA_INTRA1) $(AURORA_INTRA2)


$(AURORA_INTRA1): $(BASEDIR)/core-scripts/synth-aurora-intra-vcu108-1.tcl
	(cd $(BOARD); vivado -mode batch -source $<)

$(AURORA_INTRA2): $(BASEDIR)/core-scripts/synth-aurora-intra-vcu108-2.tcl
	(cd $(BOARD); vivado -mode batch -source $<)

endif


PIN_TYPE = Top_Pins
PIN_TYPE_INCLUDE = FlashTop
AUTOTOP = --interface pins:FlashTop.pins

include $(CONNECTALDIR)/Makefile.connectal
