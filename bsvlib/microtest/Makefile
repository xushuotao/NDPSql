SHELL:=/bin/bash

connectal_dir := ../../platform/build_tools/connectal/bsv/

BASEDIR=$(abspath ../../platform)

bsvdir=$(connectal_dir):..:$(connectal_dir)/../lib/bsv/:$(BASEDIR)/lib/dram_ctrl_sim/ddr4:$(BASEDIR)/xilinx/ddr4_v2_2/:$(BASEDIR)/controller/src/common:$(BASEDIR)/controller/src/model_virtex:$(BASEDIR)/controller/src/hw_virtex:$(BASEDIR)/lib/

bscflags=-aggressive-conditions -show-schedule -check-assert -D MainClockPeriod=1  -D DerivedClockPeriod=1 -bdir build_dir/$@ -simdir build_dir/$@  -info-dir build_dir -p %:+:$(bsvdir)  +RTS -K1G -RTS  -Xc++ -D_GLIBCXX_USE_CXX11_ABI=0 -Xc++ -O2 -steps-max-intervals 10000000 # -show-elab-progress # -D DEBUG

targets := DRAMMux

src = $(wildcard *.bsv) $(wildcard *.cpp)

$(targets): $(src)
	touch ConnectalProjectConfig.bsv
	mkdir -p build_dir/$@
	bsc $(bscflags) -sim -u -g mk$@Test TestDRAMMux.bsv
	bsc $(bscflags) -sim -u -e mk$@Test -o $@ 


all: $(targets)

clean:
	rm -rf build_dir $(targets) *.so *.o *.sched ConnectalProjectConfig.bsv

.PHONY: $(targets)
.DEFAULT_GOAL := all

