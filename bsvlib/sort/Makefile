SHELL:=/bin/bash

connectal_dir := ../../../platform/build_tools/connectal/bsv/

BASEDIR=$(abspath ../../../platform)

# bsvdir=%:+:..:$(connectal_dir):..:$(connectal_dir)/../lib/bsv/:../../:../../../bsvlib:$(BASEDIR)/xilinx/aurora_8b10b_fmc_vcu108:$(BASEDIR)/controller/src/common:$(BASEDIR)/controller/src/model_virtex:$(BASEDIR)/controller/src/hw_virtex:$(BASEDIR)/lib/

bscflags=-aggressive-conditions -show-schedule -check-assert -bdir build_dir/$@ -simdir build_dir/$@  -info-dir build_dir -p %:+  +RTS -K1G -RTS  -Xc++ -D_GLIBCXX_USE_CXX11_ABI=0

targets := Bitonic

cpp_targets := common

cpp_objects = $(addprefix build_dir/bdpi_, $(addsuffix .o, $(cpp_targets)))

$(cpp_objects): build_dir/%.o: %.cpp
	mkdir -p build_dir
	g++ -fPIC -std=c++11 -c $^ -o $@


$(targets): %: %.bsv
	mkdir -p build_dir/$@
	bsc $(bscflags) -sim -u -g mk$@Test $^
	bsc $(bscflags) -sim -u -e mk$@Test -o $@



all: $(targets)


clean:
	rm -rf build_dir $(targets) *.so *.o *.sched

.PHONY: $(TARGETS)
.DEFAULT_GOAL := all

