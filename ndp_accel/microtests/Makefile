SHELL:=/bin/bash

build_dir/bdpi.o: bdpi.cpp
	mkdir -p build_dir
	gcc -fPIC -c bdpi.cpp -o build_dir/bdpi.o

targets := SelectFilter

$(targets): %: ../%.bsv Tb_%.bsv build_dir/bdpi.o
	mkdir -p build_dir/$@
	bsc -aggressive-conditions -bdir build_dir/$@ -simdir build_dir/$@ -p %:+:.. -sim -u -g mkTb_$@ Tb_$@.bsv
	bsc -aggressive-conditions -bdir build_dir/$@ -simdir build_dir/$@ -p %:+:.. -sim -u -e mkTb_$@ -o $@ build_dir/bdpi.o

# $(eval $(call compileTest, SelectFilter))


all: $(targets)

test: all
	./test_SelectFilter

clean:
	rm -rf buildDir test_* 

.PHONY: SelectFilter
.DEFAULT_GOAL := all

