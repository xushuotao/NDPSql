ousage() { echo "Usage: $0 -n <query number> -s <scale factors> -p <directory prefix>" 1>&2; exit 1; }

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

SERVERCMD="$MINS/bin/mserver5 --set mapi_port=$PORT --daemon=yes --dbpath="
CLIENTCMD="$MINS/bin/mclient -fcsv -p $PORT "
INITFCMD="echo "
CREATEDBCMD="echo createdb"

TIMINGCMD="/usr/bin/time -o $DIR/.time -f %e "
TIMEOUTCMD="timeout -k 35m 30m "



shutdown() {
    kill $!
    sleep 10
    kill -9 $!
}

export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$(realpath ../../MonetDB-install/lib/)

echo "$SERVERCMD$DBFARM > /dev/null &"
eval "$SERVERCMD$DBFARM > /dev/null &"

sleep 5
    


eval "$TIMEOUTCMD$TIMINGCMD$CLIENTCMD$QFILE" > monetdb-SF$SF-coldrun-$qn.out

shutdown()


