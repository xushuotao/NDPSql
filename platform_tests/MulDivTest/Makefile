
# Copyright (c) 2017 Massachusetts Institute of Technology
# 
# Permission is hereby granted, free of charge, to any person
# obtaining a copy of this software and associated documentation
# files (the "Software"), to deal in the Software without
# restriction, including without limitation the rights to use, copy,
# modify, merge, publish, distribute, sublicense, and/or sell copies
# of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
# BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
# ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

CONNECTALDIR = ../../platform/build_tools/connectal

PROJ_DIR = $(abspath .)
FPGA_LIB_DIR = $(PROJ_DIR)/../../platform/lib
XILINX_IP_DIR = $(PROJ_DIR)/../../platform/xilinx
CORE_SCRIPT_DIR = $(PROJ_DIR)/../../platform/core-scripts

BUILD_DIR = $(PROJ_DIR)/build
PROJECTDIR = $(BUILD_DIR)/$(BOARD)

S2H_INTERFACES = MulDivTestRequest:MulDivTestWrapper.request
H2S_INTERFACES = MulDivTestWrapper:MulDivTestIndication

BSVFILES = $(PROJ_DIR)/bsv/MulDivTestIF.bsv 

CPPFILES = $(PROJ_DIR)/cpp/main.cpp 

CONNECTALFLAGS += --nocache -v \
				  --bsvpath $(PROJ_DIR)/bsv \
				  --bsvpath $(FPGA_LIB_DIR) \
				  --cflags " -std=c++0x " \
				  --bscflags " -check-assert "


# test specific params
CONNECTALFLAGS += -D USER_TAG_SIZE=4 \
				  -D MAX_TEST_NUM=1024 \
				  -D LOG_DELAY_CYCLES=7

# xilinx multiplier latency
XILINX_INT_MUL_LATENCY = 16
XILINX_INT_DIV_LATENCY = 64
CONNECTALFLAGS += --bscflags " -D XILINX_INT_MUL_LATENCY=$(XILINX_INT_MUL_LATENCY) \
							   -D XILINX_INT_DIV_LATENCY=$(XILINX_INT_DIV_LATENCY) "

ifeq ($(BOARD),$(filter $(BOARD),vc707 vcu108))
# synthesize for VC707 or vcu108

# VC707 needs some more clocking constraints
ifeq ($(BOARD),vc707)
CONNECTALFLAGS += -C $(XILINX_IP_DIR)/vc707/constraints/clocks.xdc
endif

# int mul/div
INT_MUL_SIGNED_XCI = $(CONNECTALDIR)/out/$(BOARD)/int_mul_signed_64/int_mul_signed_64.xci
INT_MUL_UNSIGNED_XCI = $(CONNECTALDIR)/out/$(BOARD)/int_mul_unsigned_64/int_mul_unsigned_64.xci
INT_MUL_SIGNED_UNSIGNED_XCI = $(CONNECTALDIR)/out/$(BOARD)/int_mul_signed_unsigned_64/int_mul_signed_unsigned_64.xci
INT_DIV_UNSIGNED_XCI = $(CONNECTALDIR)/out/$(BOARD)/int_div_unsigned_64/int_div_unsigned_64.xci

# also configure the latency of IP core
INT_MUL_LATENCY = $(XILINX_INT_MUL_LATENCY)
INT_DIV_LATENCY = $(XILINX_INT_DIV_LATENCY)

CONNECTALFLAGS += --xci $(INT_MUL_SIGNED_XCI) \
				  --xci $(INT_MUL_UNSIGNED_XCI) \
				  --xci $(INT_MUL_SIGNED_UNSIGNED_XCI) \
				  --xci $(INT_DIV_UNSIGNED_XCI)

prebuild:: $(INT_MUL_SIGNED_XCI) $(INT_DIV_UNSIGNED_XCI)

$(INT_MUL_SIGNED_XCI): $(CORE_SCRIPT_DIR)/synth_int_mul.tcl
	(cd $(PROJECTDIR); vivado -mode batch -source $^ -tclargs $(INT_MUL_LATENCY) 64)

$(INT_DIV_UNSIGNED_XCI): $(CORE_SCRIPT_DIR)/synth_int_div.tcl
	(cd $(PROJECTDIR); vivado -mode batch -source $^ -tclargs $(INT_DIV_LATENCY) 64)

# Force to generate IP core, because we pass args to synth tcl
.PHONY: $(INT_MUL_SIGNED_XCI) $(INT_DIV_UNSIGNED_XCI)


else
# simulation

CONNECTALFLAGS += --bscflags " -D BSIM " \
				  --cflags " -D BSIM "

endif


include $(CONNECTALDIR)/Makefile.connectal

clean.%:
	rm -rf $(BUILD_DIR)/$*

