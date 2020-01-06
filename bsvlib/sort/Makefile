SHELL:=/bin/bash

connectal_dir := ../../platform/build_tools/connectal/bsv/

BASEDIR=$(abspath ../../platform)

bsvdir=$(connectal_dir):..:$(connectal_dir)/../lib/bsv/:$(BASEDIR)/xilinx/aurora_8b10b_fmc_vcu108:$(BASEDIR)/controller/src/common:$(BASEDIR)/controller/src/model_virtex:$(BASEDIR)/controller/src/hw_virtex:$(BASEDIR)/lib/:$(BASEDIR)/lib/dram_ctrl_sim/ddr4:$(BASEDIR)/xilinx/ddr4_v2_2/

bscflags=-aggressive-conditions -show-schedule -check-assert -bdir build_dir/$@ -simdir build_dir/$@  -info-dir build_dir -p %:+:$(bsvdir)  +RTS -K1G -RTS  -Xc++ -D_GLIBCXX_USE_CXX11_ABI=0  -D MainClockPeriod=1  -D DerivedClockPeriod=1 -Xc++ -O2 -steps-max-intervals 10000000 # -show-elab-progress # -D DEBUG

targets := Bitonic BitonicPipelined StreamingMerge2 StreamingMergeSort StreamingMerge2Var MergeNFoldBRAM

targets_smt := MergeSMT2 StreamingMergeSortSMT MergeNFoldSMTBRAM

targets_sched := MergeSMT2Sched StreamingMergeSortSMTSched StreamingMergeNSMTSched StreamingDRAMMergeNSMTSched

src = $(wildcard *.bsv) $(wildcard *.cpp)

$(targets): $(src)
	touch ConnectalProjectConfig.bsv
	mkdir -p build_dir/$@
	bsc $(bscflags) -sim -u -g mk$@Test TestSort.bsv
	bsc $(bscflags) -sim -u -e mk$@Test -o $@ bdpi_sort.cpp

$(targets_smt): $(src)
	touch ConnectalProjectConfig.bsv
	mkdir -p build_dir/$@
	bsc $(bscflags) -sim -u -g mk$@Test TestSortSMT.bsv
	bsc $(bscflags) -sim -u -e mk$@Test -o $@ bdpi_sort.cpp

$(targets_sched): $(src)
	touch ConnectalProjectConfig.bsv
	mkdir -p build_dir/$@
	bsc $(bscflags) -sim -u -g mk$@Test TestSortSMTSched.bsv
	bsc $(bscflags) -sim -u -e mk$@Test -o $@ bdpi_sort.cpp


all: $(targets) $(targets_smt) $(targets_sched)

clean:
	rm -rf build_dir $(targets) $(targets_smt) $(targets_sched) *.so *.o *.sched ConnectalProjectConfig.bsv

.PHONY: $(targets) $(targets_smt) $(targets_sched)
.DEFAULT_GOAL := all

