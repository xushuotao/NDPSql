#!/usr/bin/env bash
doQuery() {
    qnum=$1
    qfile="queries/$qnum.sql"
    echo "TPCH Query $qnum..." >&2
    cat $qfile
    echo 1 > /proc/sys/vm/drop_caches
    /usr/bin/time -f "$qnum\t%e" -o qlog -a ../sqlite3 "$db" < $qfile
}


query=$@
db="/mnt/shuotao/sqlite/TPC-H.db"

rm -f qlog

if [ -z "$query" ]
then
    for i in {1..22}
    do
        doQuery $i
    done
else
    doQuery $query
fi
