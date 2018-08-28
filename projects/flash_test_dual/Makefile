BASEDIR=$(abspath ../../platform)
CONNECTALDIR?=$(BASEDIR)/build_tools/connectal/


BSVDIR=$(BASEDIR)/xilinx/aurora_8b10b_fmc_vc707:$(BASEDIR)/controller/src/common:$(BASEDIR)/controller/src/model_virtex:$(BASEDIR)/controller/src/hw_virtex:$(BASEDIR)/lib/:$(BASEDIR)/../bsvlib


S2H_INTERFACES = FlashTestRequest:FlashTest.request
H2S_INTERFACES = FlashTest:FlashTestIndication:host



CONNECTALFLAGS += -D IMPORT_HOSTIF -D XILINX_SYS_CLK --mainclockperiod=8 --derivedclockperiod=9.091
#CONNECTALFLAGS += -D IMPORT_HOSTIF -D XILINX_SYS_CLK --derivedclockperiod=9.091

CONNECTALFLAGS += --bsvpath $(BSVDIR)

ifneq ($(BOARD), vc707g2)
CONNECTALFLAGS += --bscflags="-D BSIM"
endif

BSVFILES = FlashTest.bsv
CPPFILES = testflash.cpp

ifeq ($(BOARD), vc707g2)

CONNECTALFLAGS += \
		--verilog $(BASEDIR)/xilinx/aurora_8b10b_fmc_vc707/ \
		--xci $(CONNECTALDIR)/out/$(BOARD)/aurora_8b10b_fmc1/aurora_8b10b_fmc1.xci \
		--xci $(CONNECTALDIR)/out/$(BOARD)/aurora_8b10b_fmc2/aurora_8b10b_fmc2.xci \
		--implconstraint $(BASEDIR)/xilinx/aurora_8b10b_fmc_vc707/aurora_8b10b_fmc_exdes.xdc


AURORA_INTRA1 = $(CONNECTALDIR)/out/$(BOARD)/aurora_8b10b_fmc1/aurora_8b10b_fmc1_stub.v
AURORA_INTRA2 = $(CONNECTALDIR)/out/$(BOARD)/aurora_8b10b_fmc2/aurora_8b10b_fmc2_stub.v

prebuild:: $(AURORA_INTRA1) $(AURORA_INTRA2)


$(AURORA_INTRA1): $(BASEDIR)/core-scripts/synth-aurora-intra-1.tcl
	(cd $(BOARD); vivado -mode batch -source $(BASEDIR)/core-scripts/synth-aurora-intra-1.tcl)

$(AURORA_INTRA2): $(BASEDIR)/core-scripts/synth-aurora-intra-2.tcl
	(cd $(BOARD); vivado -mode batch -source $(BASEDIR)/core-scripts/synth-aurora-intra-2.tcl)

endif


PIN_TYPE = Top_Pins
PIN_TYPE_INCLUDE = FlashTest
AUTOTOP = --interface pins:FlashTest.pins

include $(CONNECTALDIR)/Makefile.connectal
