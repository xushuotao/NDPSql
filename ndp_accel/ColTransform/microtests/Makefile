SHELL:=/bin/bash

connectal_dir := ../../../platform/build_tools/connectal/bsv/

BASEDIR=$(abspath ../../../platform)

bsvdir=%:+:..:$(connectal_dir):..:../../:$(connectal_dir)/../lib/bsv/:../../../bsvlib:$(BASEDIR)/xilinx/aurora_8b10b_fmc_vcu108:$(BASEDIR)/controller/src/common:$(BASEDIR)/controller/src/model_virtex:$(BASEDIR)/controller/src/hw_virtex:$(BASEDIR)/lib/:$(BASEDIR)/xilinx/lib

bscflags=-aggressive-conditions -show-schedule -check-assert -bdir build_dir/$@ -simdir build_dir/$@ -info-dir build_dir/ -p $(bsvdir) +RTS -K1G -RTS  -D ClockDefaultParam -D CntrlUndefBSIM -D BSIM -D XILINX_INT_MUL_LATENCY=16 -Xc++ -D_GLIBCXX_USE_CXX11_ABI=0 -l boost_system

targets := Multiplier SimdMul64 SimdAdd128 SimdAddSub128 SimdAlu256 ColXFormPE ColProcReader ColXForm

cpp_targets := common

cpp_objects = $(addprefix build_dir/bdpi_, $(addsuffix .o, $(cpp_targets)))



build_dir/bdpi_emulatedflash.o: ../../../cpp/bdpi_emulatedflash.cpp 
	mkdir -p build_dir
	gcc -fPIC -std=c++11 -c $^ -o $@

$(cpp_objects): build_dir/%.o: %.cpp
	mkdir -p build_dir
	g++ -fPIC -std=c++11 -c $^ -o $@


$(targets): %: Tb_%.bsv $(cpp_objects) bdpi_%.cpp build_dir/bdpi_emulatedflash.o
	mkdir -p build_dir/$@
	bsc $(bscflags) -sim -u -g mkTb_$@ Tb_$@.bsv
	bsc $(bscflags) -sim -u -e mkTb_$@ -o $@ $(cpp_objects) bdpi_$@.cpp build_dir/bdpi_emulatedflash.o 



all: $(targets)



clean:
	rm -rf build_dir $(targets) *.so *.sched *.o

.PHONY: $(TARGETS)
.DEFAULT_GOAL := all

