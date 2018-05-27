#!/usr/bin/env bash

query=$@
db="/mnt/shuotao/sqlite/TPC-H.db"
qfile="queries/$query.sql"

echo "TPCH Query $query..." >&2
cat $qfile
time ../sqlite3 "$db" < $qfile
