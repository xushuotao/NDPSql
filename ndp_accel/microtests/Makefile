SHELL:=/bin/bash

connectal_dir := ../../platform/build_tools/connectal/bsv/

BASEDIR=$(abspath ../../platform)

bsvdir=%:+:..:$(connectal_dir):..:$(connectal_dir)/../lib/bsv/:../../bsvlib:$(BASEDIR)/xilinx/aurora_8b10b_fmc_vcu108:$(BASEDIR)/controller/src/common:$(BASEDIR)/controller/src/model_virtex:$(BASEDIR)/controller/src/hw_virtex:$(BASEDIR)/lib/

bscflags=-aggressive-conditions -show-schedule -bdir build_dir/$@ -simdir build_dir/$@ -p $(bsvdir) +RTS -K1G -RTS  -D ClockDefaultParam

build_dir/bdpi_common.o: bdpi_common.cpp
	mkdir -p build_dir
	gcc -fPIC -c bdpi_common.cpp -o build_dir/bdpi_common.o

targets := Compact ColReader

$(targets): %: ../%.bsv Tb_%.bsv build_dir/bdpi_common.o bdpi_%.cpp
	mkdir -p build_dir/$@
	bsc $(bscflags) -sim -u -g mkTb_$@ Tb_$@.bsv
	bsc $(bscflags) -sim -u -e mkTb_$@ -o $@ build_dir/bdpi_common.o bdpi_$@.cpp



all: $(targets)



clean:
	rm -rf build_dir $(targets) *.so

.PHONY: $(TARGETS)
.DEFAULT_GOAL := all

