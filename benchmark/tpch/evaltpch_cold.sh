#!/bin/bash

usage() { echo "Usage: $0 -s <scale factors> -p <directory prefix>" 1>&2; exit 1; }

while getopts ":n:s:p:" o; do
    case "${o}" in
        s)
            s=${OPTARG}
            ;;
        p)
            p=${OPTARG}
            ;;
        *)
            usage
            ;;
    esac
done

if [ -z "${s}" ] ; then
    echo "-s is required. Example: -s 300" 1>&2;
    usage
fi

if [ -z "${p}" ] ; then
    echo "-p is required. Example: -p /mnt/md0/shuotao/tpch" 1>&2;
    usage
fi

DIR=$p

FARM=$DIR/.farms
DBNAME=monetdb-sf$s
DBFARM=$FARM/$DBNAME/

PORT=51337

MINS=$(realpath ../../MonetDB-install)

SERVERCMD="$MINS/bin/mserver5 --set mapi_port=$PORT --daemon=yes --set gdk_nr_threads=0 --dbpath="
# CLIENTCMD="$MINS/bin/mclient -fcsv -p $PORT "
#CLIENTCMD="$MINS/bin/mclient -p $PORT "

INITFCMD="echo "
CREATEDBCMD="echo createdb"

TIMINGCMD="/usr/bin/time -o $DIR/.time -f %e "
TIMEOUTCMD="timeout -k 35m 30m "

export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$(realpath ../../MonetDB-install/lib/)

cleanpagecache(){
    sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'
}


for n in `seq 1 22`;
do
    echo $n
    qn=$(printf "%02d" $n)
    QFILE=queries/q$qn.sql

    if [ ! -d $DBFARM ] ; then
        echo "DBFARM $DBFARM has not be initialized, run script ./script/loadtpch.sh"
        exit 1;
    fi

    if [ ! -r $QFILE ]; then
        echo "TPCH Query $qn script is not found in querys folder, recheck"
        exit 1;
    fi

    QUERY=`cat $QFILE | sed -e ':a;N;$!ba;s/\n/ /g'`
    CLIENTCMD="$MINS/bin/mclient -p $PORT -d $DBNAME -s \"$QUERY\""
    PROFILECMD="$MINS/bin/tomograph -p $PORT -u monetdb -P monetdb -d $DBNAME  -o perfoutput/$DBNAME-q$qn"



    shutdown() {
        kill $!
        # sleep 10
        # kill -9 $!
    }


    cleanpagecache;

    echo "$SERVERCMD$DBFARM &"
    eval "$SERVERCMD$DBFARM &"
    
    PID=$!

    sleep 1
    
    echo "$PROFILECMD"
    eval "$PROFILECMD &"


    echo "$CLIENTCMD"
    eval "$CLIENTCMD"

    kill $(pidof tomograph)

    kill $(pidof mserver5)
    sleep 10

done

sleep 5;

allfiles=""

for pdfname in `ls perfoutput/$DBNAME-q??_??.pdf`;
do
    if [[ ${pdfname} != *"00.pdf"* ]]; then
        allfiles=$allfiles"$pdfname "
    fi
done

echo $allfiles

pdftk $allfiles cat output $DBNAME-tpch-cold.pdf
        
       
