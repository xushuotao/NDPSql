SHELL:=/bin/bash

connectal_dir := ../../../platform/build_tools/connectal/bsv/

bsc_flags:= -aggressive-conditions -show-schedule -bdir build_dir/$@ -simdir build_dir/$@ -info-dir build_dir -p %:+:..:$(connectal_dir):../../

build_dir/bdpi.o: bdpi.cpp
	mkdir -p build_dir
	gcc -fPIC -c bdpi.cpp -o build_dir/bdpi.o

targets := Aggregate

$(targets): %: ../%.bsv Tb_%.bsv build_dir/bdpi.o
	mkdir -p build_dir/$@
	bsc $(bsc_flags) -sim -u -g mkTb_$@ Tb_$@.bsv
	bsc $(bsc_flags) -sim -u -e mkTb_$@ -o $@ build_dir/bdpi.o


all: $(targets)

clean:
	rm -rf build_dir $(targets) *.so

.PHONY: SelectFilter Aggregator
.DEFAULT_GOAL := all

