SHELL:=/bin/bash

connectal_dir := ../../platform/build_tools/connectal/bsv/

build_dir/bdpi.o: bdpi.cpp
	mkdir -p build_dir
	gcc -fPIC -c bdpi.cpp -o build_dir/bdpi.o

targets := SelectFilter Aggregator

$(targets): %: ../%.bsv Tb_%.bsv build_dir/bdpi.o
	mkdir -p build_dir/$@
	bsc -aggressive-conditions -show-schedule -bdir build_dir/$@ -simdir build_dir/$@ -p %:+:..:$(connectal_dir) -sim -u -g mkTb_$@ Tb_$@.bsv
	bsc -aggressive-conditions -show-schedule -bdir build_dir/$@ -simdir build_dir/$@ -p %:+:..:$(connectal_dir) -sim -u -e mkTb_$@ -o $@ build_dir/bdpi.o

# $(eval $(call compileTest, SelectFilter))


all: $(targets)

test: all
	./test_SelectFilter

clean:
	rm -rf build_dir $(targets) *.so

.PHONY: SelectFilter Aggregator
.DEFAULT_GOAL := all

