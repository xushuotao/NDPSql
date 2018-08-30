#!/usr/bin/env bash

if [ -z "$@" ]
then
    base_dir=../../queries
else
    base_dir=$@
fi

for i in {1..22}
do
    ../qgen -s 10 $i > $base_dir/$i.sql
done
