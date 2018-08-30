
#!/bin/bash
#set -x

# command line parameter parsing fun
usage() { echo "Usage: $0 -s <scale factors> -p <directory prefix>" 1>&2; exit 1; }

while getopts ":s:d:p:" o; do
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
shift $((OPTIND-1))

if [ -z "${p}" ] ; then
    echo "-p is required. Example: -p /tmp/ehannes/" 1>&2;
    usage
fi

mkdir -p $p
if [ ! -d "${p}" ] ; then
    echo "Directory $p does not exist and cannot be created." 1>&2;
    usage
fi

if [ -z "${s}" ] ; then
    echo "-s is required. Example: -s \"1 3 10\"" 1>&2;
    usage
fi
for SF in $s
do
    if [ $SF -lt 1 ] ; then
        echo "Invalid value for scale factor: $SF" 1>&2;
        exit 1
    fi
done


echo "TPC-H MonetDB load script, <shuotao@mit.edu> 2018"
echo
echo "Testing scale factors $s"
echo "Using prefix directory $p"



ln -sf .monetdb ~/.monetdb

DIR=$p
IDIR=$DIR/.install
SDIR=$DIR/.sources

MSRC=$(realpath ../MonetDB)
MINS=$(realpath ../MonetDB-install/)


mkdir -p $SDIR

# clean up source dir first
rm -rf $SDIR/*

DDIR=$DIR/.data
SCDIR=$(realpath ./db_create_script)
# QYDIR=$DIR/queries
# QRDIR=$DIR/.querylogs

RESFL=$DIR/results.tsv

touch $RESFL;

FARM=$DIR/.farms

PORT=51337
mkdir -p $DDIRp
mkdir -p $FARM
BMARK="tpch"

RESFL=$(realpath ./results.tsv)

touch $RESFL;

DB=monetdb
TIMINGCMD="/usr/bin/time -o $DIR/.time -f %e "

for SF in $s
do
    # check if we have data
    SFDDIR=$DDIR/sf-$SF/
    # if not, generate
    if [ ! -f $SFDDIR/lineitem.tbl ] ; then
        # TPC-H dbgen installer
        if [ ! -f $IDIR/dbgen/dbgen ] ; then
            rm -rf $IDIR/dbgen/
            wget https://github.com/electrum/tpch-dbgen/archive/master.zip -O $SDIR/tpch_gh.zip
            unzip $SDIR/tpch_*.zip -d $SDIR
            cd $SDIR/tpch-dbgen-master
            sed -e 's/DATABASE\s*=/DATABASE=DB2/' -e 's/MACHINE\s*=/MACHINE=LINUX/' -e 's/WORKLOAD\s*=/WORKLOAD=TPCH/' -e 's/CC\s*=/CC=gcc/' makefile.suite > Makefile
            make
            mkdir -p $IDIR/dbgen/
            cp dbgen dists.dss $IDIR/dbgen/
            rm -rf $SDIR/tpch_*
        fi
        if [ ! -f $IDIR/dbgen/dbgen ] ; then
            echo "Failed to install TPCH dbgen"
            exit -1
        fi

	cd $IDIR/dbgen/
	./dbgen -vf -s $SF
        chmod +rw *.tbl
	mkdir -p $SFDDIR
	# clean up stupid line endings
	for i in *.tbl; do
            # sed -i 's/.$//' $i ;
            # doing sed in parallel
            parallel -a $i -k --block 30M --pipe-part 'sed -r "s/.$//"' > $i.new
            mv $i.new $i
        done

        
	mv *.tbl $SFDDIR
    fi

    if [ ! -f $MINS/bin/mserver5 ] ; then
        cd $MSRC
        ./bootstrap
        mkdir build
        cd build
        ../configure --prefix=$MINS --enable-rubygem=no --enable-python3=no --enable-python2=no --enable-perl=no --enable-geos=no --enable-python=no --enable-geom=no --enable-fits=no --enable-jaql=no --enable-gsl=no --enable-odbc=no --enable-jdbc=no --enable-merocontrol=no
        make -j install
        cd $DIR
    fi

    if [ ! -f $MINS/bin/mserver5 ] ; then
        echo "Failed to install MonetDB"
        exit -1
    fi
    
    SERVERCMD="$MINS/bin/mserver5 --set mapi_port=$PORT --daemon=yes --dbpath="
    CLIENTCMD="$MINS/bin/mclient -fcsv -p $PORT "
    INITFCMD="echo "
    CREATEDBCMD="echo createdb"

    DBNAME=$DB-sf$SF
    DBFARM=$FARM/$DBNAME/
    shutdown() {
	kill $PID
    }


    if [ ! -d $DBFARM ] ; then
        # clear caches (fair loading)
        mkdir -p $DBFARM

        # initialize db directory
        eval "$INITFCMD$DBFARM"

        # start db server
        eval "$SERVERCMD$DBFARM > /dev/null &"
        PID=$!
        
        sleep 5
        
        # create db (if applicable)
        eval "$CREATEDBCMD"
        
        # create schema
        sed -e "s|DIR|$DBFARM|" $SCDIR/$DB.schema.sql > $DIR/.$DB.schema.sql.local
        eval "$CLIENTCMD$DIR/.$DB.schema.sql.local" > /dev/null

        # load data
        sed -e "s|DIR|$SFDDIR|" $SCDIR/$DB.load.sql > $DIR/.$DB.load.sql.local
        eval "$TIMINGCMD$CLIENTCMD$DIR/.$DB.load.sql.local" > /dev/null
        LDTIME=`cat $DIR/.time`
        echo -e "$LOGPREFIX\tload\t\t\t$LDTIME" | tee -a $RESFL 

        # constraints
        eval "$TIMINGCMD$CLIENTCMD$SCDIR/$DB.constraints.sql" > /dev/null
        CTTIME=`cat $DIR/.time`
        echo -e "$LOGPREFIX\tconstraints\t\t\t$CTTIME" | tee -a $RESFL 

        # analyze/vacuum
        eval "$TIMINGCMD$CLIENTCMD$SCDIR/$DB.analyze.sql" > /dev/null
        AZTIME=`cat $DIR/.time`
        echo -e "$LOGPREFIX\tanalyze\t\t\t$AZTIME" | tee -a $RESFL 
        
        shutdown
    fi
done

