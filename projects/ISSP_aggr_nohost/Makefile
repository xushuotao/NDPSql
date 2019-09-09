BASEDIR=$(abspath ../../platform)
CONNECTALDIR?=$(BASEDIR)/build_tools/connectal/

ISSPBASEDIR = $(abspath ../../ndp_accel)
ISSPDIR=$(ISSPBASEDIR)/RowSelector:$(ISSPBASEDIR)/ColProc:$(ISSPBASEDIR)/ColProc/ColTransform:$(ISSPBASEDIR)/ColProc/Aggregate

BSVDIR=$(BASEDIR)/xilinx/aurora_8b10b_fmc_vcu108:$(BASEDIR)/controller/src/common:$(BASEDIR)/controller/src/model_virtex:$(BASEDIR)/controller/src/hw_virtex:$(BASEDIR)/lib/:$(BASEDIR)/../bsvlib:$(ISSPDIR)

S2H_INTERFACES := FlashRequest:FlashTop.flashRequest
S2H_INTERFACES += RowSelectorProgramIfc:FlashTop.rowSelProgramIfc
S2H_INTERFACES += InColProgramIfc:FlashTop.inColProgramIfc
S2H_INTERFACES += ColXFormProgramIfc:FlashTop.colXFormProgramIfc
S2H_INTERFACES += OutColProgramIfc:FlashTop.outColProgramIfc
S2H_INTERFACES += PageFeeder:FlashTop.pagefeeder
S2H_INTERFACES += ISSPDebug:FlashTop.isspDebug

H2S_INTERFACES := FlashTop:FlashIndication,ISSPIndication:host

MEM_READ_INTERFACES = lFlashTop.dmaReadClient
MEM_WRITE_INTERFACES = lFlashTop.dmaWriteClient

CONNECTALFLAGS += -D IMPORT_HOSTIF -D XILINX_SYS_CLK --mainclockperiod=8 --derivedclockperiod=9.091 -D DataBusWidth=256 -D USE_WIDE_WIDTH


CONNECTALFLAGS += --bsvpath $(BSVDIR)

XILINX_INT_MUL_LATENCY = 16


ifneq ($(BOARD), vcu108)
CONNECTALFLAGS += --bscflags="-D XILINX_INT_MUL_LATENCY=$(XILINX_INT_MUL_LATENCY) \
							  -D CntrlUndefBSIM \
							  -D TRACE_BUF \
							  -D BSIM -D SIM_DMA_WRITE_LATENCY=1 -D SIM_DMA_READ_LATENCY=1" \
				  --cxxflags="-D CntrlUndefBSIM  -D FAKE_WRITE"
else
CONNECTALFLAGS += --bscflags="-D XILINX_INT_MUL_LATENCY=$(XILINX_INT_MUL_LATENCY) \
							  -D TRACE_BUF"
endif

BSVFILES = ../ISSP_aggr/FlashTop.bsv $(ISSPBASEDIR)/ISSPTypes.bsv
CPPFILES = ../../util/flashmanage/flashmanage.cpp ../../util/mmap_util/mmap_util.cpp ../../util/filemap/filemap.cpp  ../../util/issp_programmer/issp_programmer.cpp ../../util/issp_programmer/pageaddr_feeder.cpp testissp.cpp ../flashFileManager/colfileloader.cpp

CONNECTALFLAGS += -l boost_system -l boost_filesystem -l boost_thread -I ../../util/filemap/ -I ../../util/flashmanage/ -I ../../util/mmap_util/ -I ../../util/issp_programmer/ -I../flashFileManager --cflags=" --std=c++11 " --nonstrict

CONNECTALFLAGS += --verilog ../../verilog \
				  --bsimsource ../../cpp/bvi_emulatedflash.cpp --cxxflags=" --std=c++11 " \
				  --verilatorflags="-LDFLAGS \"-lboost_system -lboost_filesystem -lboost_thread\""

ifeq ($(BOARD), vcu108)

CONNECTALFLAGS += \
		--implconstraint $(BASEDIR)/xilinx/constraints/pcieclock-vcu108.xdc \
		--verilog $(BASEDIR)/xilinx/aurora_8b10b_fmc_vcu108/ \
		--xci $(CONNECTALDIR)/out/$(BOARD)/aurora_8b10b_fmc1/aurora_8b10b_fmc1.xci \
		--xci $(CONNECTALDIR)/out/$(BOARD)/aurora_8b10b_fmc2/aurora_8b10b_fmc2.xci \
		--implconstraint $(BASEDIR)/xilinx/aurora_8b10b_fmc_vcu108/aurora_8b10b_fmc_exdes.xdc


AURORA_INTRA1 = $(CONNECTALDIR)/out/$(BOARD)/aurora_8b10b_fmc1/aurora_8b10b_fmc1_stub.v
AURORA_INTRA2 = $(CONNECTALDIR)/out/$(BOARD)/aurora_8b10b_fmc2/aurora_8b10b_fmc2_stub.v

# int mul/div
INT_MUL_SIGNED_XCI = $(CONNECTALDIR)/out/$(BOARD)/int_mul_signed_32/int_mul_signed_32.xci
INT_MUL_UNSIGNED_XCI = $(CONNECTALDIR)/out/$(BOARD)/int_mul_unsigned_32/int_mul_unsigned_32.xci
INT_MUL_SIGNED_UNSIGNED_XCI = $(CONNECTALDIR)/out/$(BOARD)/int_mul_signed_unsigned_32/int_mul_signed_unsigned_32.xci

# also configure the latency of IP core
INT_MUL_LATENCY = $(XILINX_INT_MUL_LATENCY)

CONNECTALFLAGS += --xci $(INT_MUL_SIGNED_XCI) \
				  --xci $(INT_MUL_UNSIGNED_XCI) \
				  --xci $(INT_MUL_SIGNED_UNSIGNED_XCI)


prebuild:: $(AURORA_INTRA1) $(AURORA_INTRA2) $(INT_MUL_SIGNED_XCI)


$(AURORA_INTRA1): $(BASEDIR)/core-scripts/synth-aurora-intra-vcu108-1.tcl
	(cd $(BOARD); vivado -mode batch -source $<)

$(AURORA_INTRA2): $(BASEDIR)/core-scripts/synth-aurora-intra-vcu108-2.tcl
	(cd $(BOARD); vivado -mode batch -source $<)

$(INT_MUL_SIGNED_XCI): $(BASEDIR)/core-scripts/synth_int_mul.tcl
	(cd $(BOARD); vivado -mode batch -source $^ -tclargs $(INT_MUL_LATENCY) 32)



endif


PIN_TYPE = Top_Pins
PIN_TYPE_INCLUDE = FlashTop
AUTOTOP = --interface pins:FlashTop.pins

include $(CONNECTALDIR)/Makefile.connectal
