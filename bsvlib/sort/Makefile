SHELL:=/bin/bash

connectal_dir := ../../platform/build_tools/connectal/bsv/

BASEDIR=$(abspath ../../platform)

bsvdir=$(connectal_dir):..:$(connectal_dir)/../lib/bsv/:$(BASEDIR)/xilinx/aurora_8b10b_fmc_vcu108:$(BASEDIR)/controller/src/common:$(BASEDIR)/controller/src/model_virtex:$(BASEDIR)/controller/src/hw_virtex:$(BASEDIR)/lib/

bscflags=-aggressive-conditions -show-schedule -check-assert -bdir build_dir/$@ -simdir build_dir/$@  -info-dir build_dir -p %:+:$(bsvdir)  +RTS -K1G -RTS  -Xc++ -D_GLIBCXX_USE_CXX11_ABI=0

targets := Bitonic StreamingMerge

$(targets): TestSort.bsv
	touch ConnectalProjectConfig.bsv
	mkdir -p build_dir/$@
	bsc $(bscflags) -sim -u -g mk$@Test $^
	bsc $(bscflags) -sim -u -e mk$@Test -o $@


all: $(targets)


clean:
	rm -rf build_dir $(targets) *.so *.o *.sched ConnectalProjectConfig.bsv

.PHONY: $(TARGETS)
.DEFAULT_GOAL := all

