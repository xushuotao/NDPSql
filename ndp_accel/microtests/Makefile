SHELL:=/bin/bash

connectal_dir := ../../platform/build_tools/connectal/bsv/

build_dir/bdpi_common.o: bdpi_common.cpp
	mkdir -p build_dir
	gcc -fPIC -c bdpi_common.cpp -o build_dir/bdpi_common.o

targets := Compact

$(targets): %: ../%.bsv Tb_%.bsv build_dir/bdpi_common.o bdpi_%.cpp
	mkdir -p build_dir/$@
	bsc -aggressive-conditions -show-schedule -bdir build_dir/$@ -simdir build_dir/$@ -p %:+:..:$(connectal_dir) -sim -u -g mkTb_$@ Tb_$@.bsv
	bsc -aggressive-conditions -show-schedule -bdir build_dir/$@ -simdir build_dir/$@ -p %:+:..:$(connectal_dir) -sim -u -e mkTb_$@ -o $@ build_dir/bdpi_common.o bdpi_$@.cpp



all: $(targets)

test: all
	./test_Compact

clean:
	rm -rf build_dir $(targets) *.so

.PHONY: $(TARGETS)
.DEFAULT_GOAL := all

