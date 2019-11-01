BASEDIR=$(abspath ../../platform)

CONNECTALDIR?=$(BASEDIR)/build_tools/connectal/


BSVDIR=$(BASEDIR)/lib:$(BASEDIR)/../bsvlib/sort:$(BASEDIR)/../bsvlib/


S2H_INTERFACES = UltraRAMPerfRequest:UltraRAMPerf.request
H2S_INTERFACES = UltraRAMPerf:UltraRAMPerfIndication


CONNECTALFLAGS += --bsvpath $(BSVDIR) --bscflags="-check-assert"
CONNECTALFLAGS += --verilog ../../verilog


BSVFILES = UltraRAMPerf.bsv
CPPFILES = testultraram.cpp

include $(CONNECTALDIR)/Makefile.connectal
