usage() { echo "Usage: $0 -n <query number> -s <scale factors> -p <directory prefix>" 1>&2; exit 1; }

while getopts ":n:s:p:" o; do
    case "${o}" in
        n)
            n=${OPTARG}
            ;;
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

if [ -z "${n}" ] ; then
    echo "-n is required. Example: -n 14" 1>&2;
    usage
fi

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

PORT=51337

MINS=$(realpath ../../MonetDB-install)

SERVERCMD="$MINS/bin/mserver5 --set mapi_port=$PORT --daemon=yes --set gdk_nr_threads=0 --set gdk_debug=2097152 --dbpath="
# CLIENTCMD="$MINS/bin/mclient -fcsv -p $PORT "
#CLIENTCMD="$MINS/bin/mclient -p $PORT "
QUERY=`cat $QFILE | sed -e ':a;N;$!ba;s/\n/ /g'`
#CLIENTCMD="$MINS/bin/mclient -p $PORT -d $DBNAME -s \"$QUERY\""
# CLIENTCMD="$MINS/bin/mclient -p $PORT -d $DBNAME -s \"$QUERY\""
CLIENTCMD="$MINS/bin/mclient -p $PORT -d $DBNAME $QFILE"

INITFCMD="echo "
CREATEDBCMD="echo createdb"

TIMINGCMD="/usr/bin/time -o $DIR/.time -f %e "
TIMEOUTCMD="timeout -k 35m 30m "

# PROFILECMD="$MINS/bin/tomograph -p $PORT -u monetdb -P monetdb -d $DBNAME  -o perfoutput/$DBNAME-q$qn"
# PROFILECMD="$MINS/bin/tomograph -p $PORT -u monetdb -P monetdb -d $DBNAME "
# PROFILECMD="$MINS/bin/tachograph -p $PORT -u monetdb -P monetdb -d $DBNAME"
# PROFILECMD="$MINS/bin/stethoscope -p $PORT -u monetdb -P monetdb -d $DBNAME "



shutdown() {
    kill $!
    # sleep 10
    # kill -9 $!
}

#unset LD_LIBRARY_PATH
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$MINS/lib/

echo $LD_LIBRARY_PATH

echo "$SERVERCMD$DBFARM &"
eval "$SERVERCMD$DBFARM &"

PID=$!

sleep 10
    
# echo "$PROFILECMD"
# eval "$PROFILECMD &"


echo "$CLIENTCMD"
eval "time $CLIENTCMD"
#eval "$CLIENTCMD$QFILE"
#eval "$TIMEOUTCMD$TIMINGCMD$CLIENTCMD$QFILE"
# echo "$CLIENTCMD\"$(cat $QFILE)\""
# eval "$CLIENTCMD\"$(cat $QFILE)\""
#> monetdb-SF$SF-coldrun-$qn.out

kill $(pidof tomograph)
# kill $(pidof tachograph)
# kill $(pidof stethoscope)
kill $(pidof mserver5)


