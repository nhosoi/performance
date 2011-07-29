#/bin/sh

# README
# This script needs to be located on the server machine (call hostA).
# Slamd is set up on the other machine (hostB), on which ssh is properly set up.
#    ssh-HowTo:
#      on hostA: # ssh-keygen -t dsa
#                # scp .ssh/id_dsa.pub hostB:~/.ssh/authorized_keys

# hostA
# ls -R $TESTHOME
# ldif  scripts
#
# $TESTHOME/ldif:
# init.ldif ($INITLDIF)
# example10k.ldif ($TESTLDIF)
#
# $TESTHOME/scripts:
# run_slamd_ds.sh (this script)

# hostB
# ls $SLAMDHOME
# bin/   logs/   scripts/    SLAMD-License.txt   tools/
# conf/  README  server/     temp/               webapps/
# lib/   results/  slamd-2.0.1.war@  thirdparty/ work/
#
# ls $SLAMDHOME/scripts/
# run-script-wrapper.sh* gen-rep-avgpersec.sh*  <sizedir> ...
#
# ls $SLAMDHOME/scripts/<sizedir>
# bind.script       add_delete.script    modify.script          
# search.seq.script search.random.script

# Usage
# $0 [-D <directory_manager>] [-w <passwd>]
#    [-h <ds_host>] [-p <ds_port>] [-i <ID>] [-d <dbinstname>]
#    [-s <suffix>] [-t <testhome>] [-l <testldif>] [-m <initldif>]
#    [-T <slamdhost>] [-E <slamdhome>] [-R <duration>]
#    [-I <interval>] [-P] [-S] [-A] [-M] [-U]
#
#    -S: run search
#    -A: run add and delete
#    -M: run modify
#    -U: run auth/bind"
#    Note: if -[SAMU] not specified, run all 4 tests
#
#    -P: run profiler; the results are found in $TESTHOME/results/prof/$NOW
#        opreport -l /usr/sbin/ns-slapd --session-dir=dir_path
#        where dir_path is $TESTHOME/results/prof/$NOW/oprofile.$OP.$PARAM

###############################################################################
# DEFAULT VARIABLES
# server
DIRMGR="cn=directory manager"
DIRMGRPW="Secret123"
HOST=localhost
PORT=389
ID=`hostname | awk -F'.' '{print $1}'`
DBINST=userRoot
SUFFIX="dc=example,dc=com"
TESTHOME=/home/perf
INITLDIF=init.ldif
SIZE=10k

# slamd
SLAMDHOST=kiki.usersys.redhat.com
SLAMDHOME=/export/tests/slamd/slamd
DURATION=600
INTERVAL=10
###############################################################################

OPALL=1
OPADDDEL=0
OPSRCH=0
OPMOD=0
OPAUTH=0

WITHPROF=0

SCRIPTADDDEL="add_delete.script"
SCRIPTAUTH="bind.script"
SCRIPTSRCH="search.random.script"
SCRIPTMOD="modify.script"
SCRIPTRUN="$SLAMDHOME/scripts/run-script-wrapper.sh"
SCRIPTREP="$SLAMDHOME/scripts/gen-rep-avgpersec.sh"

DEFAULT_CACHEMEMSIZE=10485760
DEFAULT_DBCACHESIZE=10000000

IS64=`uname -p | awk -F'_' '{print $2}'`
INSTDIR=/usr/lib${IS64}/dirsrv/slapd-${ID}

NOW=`date +%Y%m%d.%H%M%S`
RESULTDIR=$SLAMDHOME/results/$NOW
PROFRESULTDIR=$TESTHOME/results/prof/$NOW

TESTLDIF=example${SIZE}.ldif

ONEMEG=`expr 1024 \* 1024`
ONEGIG=`expr 1024 \* $ONEMEG`
TWOGIG=`expr 2 \* $ONEGIG`

# set up test environment
# . check the server is up
# . check ssh is available
# . check slamd is available
# . check opscripts are available
# . check ldif files are available
# . create a result dir on the slamd host
# . check the server host has an openldap client package
setup_testenv()
{
	SCRIPTRUN="$SLAMDHOME/scripts/run-script-wrapper.sh"
	SCRIPTREP="$SLAMDHOME/scripts/gen-rep-avgpersec.sh"
	RESULTDIR=$SLAMDHOME/results/$NOW
	PROFRESULTDIR=$TESTHOME/results/prof/$NOW
	TESTLDIF=example${SIZE}.ldif

	TAG="setup_testenv"

	# is the server up?
	ps -ef | egrep ns-slapd | egrep slapd-${ID}
	RC=$?
	if [ $RC -ne 0 ]; then
		# server is down; restart it
		$INSTDIR/start-slapd
		RC=$?
		if [ $RC -ne 0 ]; then
			echo "$TAG: Starting the server failed: $RC"
			exit 1
		fi
	fi
	echo "$TAG: the server is up"

	# is ssh available? so is slamd?
	script=`ssh $SLAMDHOST ls $SLAMDHOME/tools/run-script.sh`
	RC=$?
	if [ $RC -ne 0 ]; then
		echo "$TAG: ssh is not available: $RC"
		exit 1
	fi
	echo "$TAG: ssh is available"
	if [ "$script" = "" ]; then
		echo "$TAG: slamd is not available"
		exit 1
	fi
	echo "$TAG: slamd is available"

	# are op scripts available?
	script=`ssh $SLAMDHOST ls $SLAMDHOME/scripts/$SIZE/$SCRIPTADDDEL`
	if [ "$script" = "" ]; then
		echo "$TAG: $SCRIPTADDDEL is not available"
		exit 1
	fi
	echo "$TAG: $SCRIPTADDDEL is available"
	script=`ssh $SLAMDHOST ls $SLAMDHOME/scripts/$SIZE/$SCRIPTSRCH`
	if [ "$script" = "" ]; then
		echo "$TAG: $SCRIPTSRCH is not available"
		exit 1
	fi
	echo "$TAG: $SCRIPTSRCH is available"
	script=`ssh $SLAMDHOST ls $SLAMDHOME/scripts/$SIZE/$SCRIPTMOD`
	if [ "$script" = "" ]; then
		echo "$TAG: $SCRIPTMOD is not available"
		exit 1
	fi
	echo "$TAG: $SCRIPTMOD is available"

	# check ldif files are available
	if [ ! -f $TESTHOME/ldif/$INITLDIF ]; then
		echo "$TAG: $TESTHOME/ldif/$INITLDIF is not available"
		exit 1
	fi
	echo "$TAG: $TESTHOME/ldif/$INITLDIF is available"
	if [ ! -f $TESTHOME/ldif/$TESTLDIF ]; then
		echo "$TAG: $TESTHOME/ldif/$TESTLDIF is not available"
		exit 1
	fi
	echo "$TAG: $TESTHOME/ldif/$TESTLDIF is available"

	# create a result dir on the slamd host
	ssh $SLAMDHOST mkdir -p $RESULTDIR
	RC=$?
	if [ $RC -ne 0 ]; then
		echo "$TAG: failed to mkdir $RESULTDIR: $RC"
		exit 1
	fi
	ssh $SLAMDHOST chmod 777 $RESULTDIR
	echo "$TAG: $RESULTDIR is available"

	# check the server host has an openldap client package
	rpm -q openldap-clients
	RC=$?
	if [ $RC -ne 0 ]; then
		echo "$TAG: openldap-clients is not installed: $RC"
		exit 1
	fi
	echo "$TAG: openldap-clients is installed: $RC"

	if [ $WITHPROF -eq 1 ]; then
		mkdir -p $PROFRESULTDIR
	fi
} 

# update entry cache size and db cache size if necessary;
# then restart the server
set_cachesizes()
{
	cachememsize=${1:-$DEFAULT_CACHEMEMSIZE}
	dbcachesize=${2:-$DEFAULT_DBCACHESIZE}

	TAG="set_cachesizes"

	echo "$TAG: cachememsize: $cachememsize"
	echo "$TAG: dbcachesize: $dbcachesize"

	currentcachememsize=`ldapsearch -LLLx -h localhost -p $PORT -D "$DIRMGR" -w "$DIRMGRPW" -b "cn=${DBINST},cn=ldbm database,cn=plugins,cn=config" -s base "(cn=*)" nsslapd-cachememsize | egrep nsslapd-cachememsize | awk '{print $2}'`
	currentdbcachesize=`ldapsearch -LLLx -h localhost -p $PORT -D "$DIRMGR" -w "$DIRMGRPW" -b "cn=config,cn=ldbm database,cn=plugins,cn=config" -s base "(cn=*)" nsslapd-dbcachesize | egrep nsslapd-dbcachesize | awk '{print $2}'`

	echo "$TAG: current cachememsize: $currentcachememsize"
	echo "$TAG: current dbcachesize: $currentdbcachesize"

	modified=0
	if [ $cachememsize -ne $currentcachememsize ]; then
		echo "$TAG: cachememsize: does not match; replace it"
		ldapmodify -x -h localhost -p $PORT -D "$DIRMGR" -w "$DIRMGRPW" <<-EOF
		dn: cn=${DBINST},cn=ldbm database,cn=plugins,cn=config
		changetype: modify
		replace: nsslapd-cachememsize
		nsslapd-cachememsize: $cachememsize
		EOF
		modified=1
	fi
	if [ $dbcachesize -ne $currentdbcachesize ]; then
		echo "$TAG: dbcachesize: does not match; replace it"
		ldapmodify -x -h localhost -p $PORT -D "$DIRMGR" -w "$DIRMGRPW" <<-EOF
		dn: cn=config,cn=ldbm database,cn=plugins,cn=config
		changetype: modify
		replace: nsslapd-dbcachesize
		nsslapd-dbcachesize: $dbcachesize
		EOF
		modified=1
	fi

	if [ $modified -eq 1 ]; then
		$INSTDIR/restart-slapd
		RC=$?
		if [ $RC -ne 0 ]; then
			echo "$TAG: Restarting the server failed: $RC"
			exit 1
		fi
	fi

	currentcachememsize=`ldapsearch -LLLx -h localhost -p $PORT -D "$DIRMGR" -w "$DIRMGRPW" -b "cn=${DBINST},cn=ldbm database,cn=plugins,cn=config" -s base "(cn=*)" nsslapd-cachememsize | egrep nsslapd-cachememsize | awk '{print $2}'`
	currentdbcachesize=`ldapsearch -LLLx -h localhost -p $PORT -D "$DIRMGR" -w "$DIRMGRPW" -b "cn=config,cn=ldbm database,cn=plugins,cn=config" -s base "(cn=*)" nsslapd-dbcachesize | egrep nsslapd-dbcachesize | awk '{print $2}'`

	echo "$TAG: updated cachememsize: $currentcachememsize"
	echo "$TAG: updated dbcachesize: $currentdbcachesize"

}

start_profiler()
{
	if [ $WITHPROF -eq 0 ]; then
		return
	fi
	opcontrol --reset
	opcontrol --start
}

stop_profiler()
{
	if [ $WITHPROF -eq 0 ]; then
		return
	fi
	OP=$1
	PARAM=$2
	opcontrol --dump
	opcontrol --shutdown
	(cd /var/lib; tar cf - oprofile) | \
	(cd $PROFRESULTDIR; tar xf - oprofile; mv oprofile oprofile.$OP.$PARAM)
}

run_add_delete()
{
	TAG="run_add_delete"
	ECACHESIZE=$1
	DBCACHESIZE=$2
	THREADCNT=$3
	PARAMS=$4

	echo "$TAG: cachememsize: $ECACHESIZE, dbcachesize: $DBCACHESIZE, $THREADCNT threads"

	# initialize the db
	$INSTDIR/stop-slapd
	RC=$?
	if [ $RC -ne 0 ]; then
		echo "$TAG: Stopping the server failed: $RC"
		exit 1
	fi
	$INSTDIR/ldif2db -n $DBINST -i $TESTHOME/ldif/$INITLDIF
	RC=$?
	if [ $RC -ne 0 ]; then
		echo "$TAG: Importing $TESTHOME/ldif/$INITLDIF failed: $RC"
		exit 1
	fi
	$INSTDIR/start-slapd
	RC=$?
	if [ $RC -ne 0 ]; then
		echo "$TAG: Starting the server failed: $RC"
		exit 1
	fi

	# set cachesizes
	set_cachesizes $ECACHESIZE $DBCACHESIZE

	start_profiler
	ssh $SLAMDHOST $SCRIPTRUN $SLAMDHOME $DURATION $INTERVAL $THREADCNT $SIZE $SCRIPTADDDEL "$PARAMS" $RESULTDIR
	stop_profiler $SCRIPTADDDEL "$PARAMS"
	RC=$?
	if [ $RC -ne 0 ]; then
		echo "$TAG: $SCRIPTRUN failed: $RC"
		echo "$TAG: params: $SLAMDHOME $DURATION $INTERVAL $THREADCNT $SIZE $SCRIPTADDDEL "$PARAMS" $RESULTDIR"
		exit 1
	fi
	echo "$TAG: params: $SLAMDHOME $DURATION $INTERVAL $THREADCNT $SIZE $SCRIPTADDDEL "$PARAMS" $RESULTDIR: PASS"
}

run_add_delete_all()
{
	TAG="run_add_delete_all"

	# cachememsize: 10M, dbcachesize: 10M, 4 threads
	run_add_delete $DEFAULT_CACHEMEMSIZE $DEFAULT_DBCACHESIZE 4 "10M.10M.4"

	# cachememsize: 2G, dbcachesize: 10M, 4 threads
	run_add_delete $TWOGIG $DEFAULT_DBCACHESIZE 4 "2G.10M.4"

	# cachememsize: 2G, dbcachesize: 1G, 4 threads
	run_add_delete $TWOGIG $ONEGIG 4 "2G.1G.4"

	# cachememsize: 2G, dbcachesize: 1G, 8 threads
	run_add_delete $TWOGIG $ONEGIG 8 "2G.1G.8"

# Uncomment when running on a large memory machine!!!
#	# cachememsize: 2G, dbcachesize: 1G, 16 threads
#	run_add_delete $TWOGIG $ONEGIG 16 "2G.1G.16"
#
#	# cachememsize: 2G, dbcachesize: 1G, 32 threads
#	run_add_delete $TWOGIG $ONEGIG 32 "2G.1G.32"
#
#	# cachememsize: 2G, dbcachesize: 1G, 64 threads
#	run_add_delete $TWOGIG $ONEGIG 64 "2G.1G.64"

	# generate add result (avg/sec) for office calc
	ssh $SLAMDHOST $SCRIPTREP add $RESULTDIR

	# generate delete result (avg/sec) for office calc
	ssh $SLAMDHOST $SCRIPTREP delete $RESULTDIR
}

run_search()
{
	TAG="run_search"

	ECACHESIZE=$1
	DBCACHESIZE=$2
	THREADCNT=$3
	PARAMS=$4

	echo "$TAG: cachememsize: $ECACHESIZE, dbcachesize: $DBCACHESIZE, $THREADCNT threads"

	# set caches
	set_cachesizes $ECACHESIZE $DBCACHESIZE

	# warm up the caches
	ldapsearch -LLLx -h $HOST -p $PORT -D "$DIRMGR" -w "$DIRMGRPW" -b "$SUFFIX" "(objectclass=*)" > /dev/null

	start_profiler
	ssh $SLAMDHOST $SCRIPTRUN $SLAMDHOME $DURATION $INTERVAL $THREADCNT $SIZE $SCRIPTSRCH "$PARAMS" $RESULTDIR
	stop_profiler $SCRIPTSRCH "$PARAMS"
	RC=$?
	if [ $RC -ne 0 ]; then
		echo "$TAG: $SCRIPTRUN failed: $RC"
		echo "$TAG: params: $SLAMDHOME $DURATION $INTERVAL $THREADCNT $SIZE $SCRIPTSRCH "$PARAMS" $RESULTDIR"
		exit 1
	fi
	echo "$TAG: params: $SLAMDHOME $DURATION $INTERVAL $THREADCNT $SIZE $SCRIPTSRCH "$PARAMS" $RESULTDIR: PASS"
}

run_search_all()
{
	TAG="run_search_all"

	# initialize the db
	$INSTDIR/stop-slapd
	RC=$?
	if [ $RC -ne 0 ]; then
		echo "$TAG: Stopping the server failed: $RC"
		exit 1
	fi
	$INSTDIR/ldif2db -n $DBINST -i $TESTHOME/ldif/$TESTLDIF
	RC=$?
	if [ $RC -ne 0 ]; then
		echo "$TAG: Importing $TESTHOME/ldif/$TESTLDIF failed: $RC"
		exit 1
	fi
	# initialize the db
	$INSTDIR/start-slapd
	RC=$?
	if [ $RC -ne 0 ]; then
		echo "$TAG: Stopping the server failed: $RC"
		exit 1
	fi

	# cachememsize: 10M, dbcachesize: 10M, 4 threads
	run_search $DEFAULT_CACHEMEMSIZE $DEFAULT_DBCACHESIZE 4 "10M.10M.4"

	# cachememsize: 2G, dbcachesize: 10M, 4 threads
	run_search $TWOGIG $DEFAULT_DBCACHESIZE 4 "2G.10M.4"

	# cachememsize: 2G, dbcachesize: 1G, 4 threads
	run_search $TWOGIG $ONEGIG 4 "2G.1G.4"

	# cachememsize: 2G, dbcachesize: 1G, 8 threads
	run_search $TWOGIG $ONEGIG 8 "2G.1G.8"

# Uncomment when running on a large memory machine!!!
#	# cachememsize: 2G, dbcachesize: 1G, 16 threads
#	run_search $TWOGIG $ONEGIG 16 "2G.1G.16"
#
#	# cachememsize: 2G, dbcachesize: 1G, 32 threads
#	run_search $TWOGIG $ONEGIG 32 "2G.1G.32"
#
#	# cachememsize: 2G, dbcachesize: 1G, 64 threads
#	run_search $TWOGIG $ONEGIG 64 "2G.1G.64"

	# generate search result (avg/sec) for office calc
	ssh $SLAMDHOST $SCRIPTREP search $RESULTDIR
}

run_modify()
{
	TAG="run_modify"

	ECACHESIZE=$1
	DBCACHESIZE=$2
	THREADCNT=$3
	PARAMS=$4

	echo "$TAG: cachememsize: $ECACHESIZE, dbcachesize: $DBCACHESIZE, $THREADCNT threads"

	# set caches
	set_cachesizes $ECACHESIZE $DBCACHESIZE

	# warm up the caches
	ldapsearch -LLLx -h $HOST -p $PORT -D "$DIRMGR" -w "$DIRMGRPW" -b "$SUFFIX" "(objectclass=*)" > /dev/null

	start_profiler
	ssh $SLAMDHOST $SCRIPTRUN $SLAMDHOME $DURATION $INTERVAL $THREADCNT $SIZE $SCRIPTMOD "$PARAMS" $RESULTDIR
	stop_profiler $SCRIPTMOD "$PARAMS"
	RC=$?
	if [ $RC -ne 0 ]; then
		echo "$TAG: $SCRIPTRUN failed: $RC"
		echo "$TAG: params: $SLAMDHOME $DURATION $INTERVAL $THREADCNT $SIZE $SCRIPTMOD "$PARAMS" $RESULTDIR"
		exit 1
	fi
	echo "$TAG: params: $SLAMDHOME $DURATION $INTERVAL $THREADCNT $SIZE $SCRIPTMOD "$PARAMS" $RESULTDIR: PASS"
}

run_modify_all()
{
	TAG="run_modify_all"

	# initialize the db
	$INSTDIR/stop-slapd
	RC=$?
	if [ $RC -ne 0 ]; then
		echo "$TAG: Stopping the server failed: $RC"
		exit 1
	fi
	$INSTDIR/ldif2db -n $DBINST -i $TESTHOME/ldif/$TESTLDIF
	RC=$?
	if [ $RC -ne 0 ]; then
		echo "$TAG: Importing $TESTHOME/ldif/$TESTLDIF failed: $RC"
		exit 1
	fi
	# initialize the db
	$INSTDIR/start-slapd
	RC=$?
	if [ $RC -ne 0 ]; then
		echo "$TAG: Stopping the server failed: $RC"
		exit 1
	fi

	# cachememsize: 10M, dbcachesize: 10M, 4 threads
	run_modify $DEFAULT_CACHEMEMSIZE $DEFAULT_DBCACHESIZE 4 "10M.10M.4"

	# cachememsize: 2G, dbcachesize: 10M, 4 threads
	run_modify $TWOGIG $DEFAULT_DBCACHESIZE 4 "2G.10M.4"

	# cachememsize: 2G, dbcachesize: 1G, 4 threads
	run_modify $TWOGIG $ONEGIG 4 "2G.1G.4"

	# cachememsize: 2G, dbcachesize: 1G, 8 threads
	run_modify $TWOGIG $ONEGIG 8 "2G.1G.8"

# Uncomment when running on a large memory machine!!!
#	# cachememsize: 2G, dbcachesize: 1G, 16 threads
#	run_modify $TWOGIG $ONEGIG 16 "2G.1G.16"
#
#	# cachememsize: 2G, dbcachesize: 1G, 32 threads
#	run_modify $TWOGIG $ONEGIG 32 "2G.1G.32"
#
#	# cachememsize: 2G, dbcachesize: 1G, 64 threads
#	run_modify $TWOGIG $ONEGIG 64 "2G.1G.64"

	# generate modify result (avg/sec) for office calc
	ssh $SLAMDHOST $SCRIPTREP modify $RESULTDIR
}

run_auth()
{
	TAG="run_auth"

	ECACHESIZE=$1
	DBCACHESIZE=$2
	THREADCNT=$3
	PARAMS=$4

	echo "$TAG: cachememsize: $ECACHESIZE, dbcachesize: $DBCACHESIZE, $THREADCNT threads"

	# set caches
	set_cachesizes $ECACHESIZE $DBCACHESIZE

	# warm up the caches
	ldapsearch -LLLx -h $HOST -p $PORT -D "$DIRMGR" -w "$DIRMGRPW" -b "$SUFFIX" "(objectclass=*)" > /dev/null

	start_profiler
	ssh $SLAMDHOST $SCRIPTRUN $SLAMDHOME $DURATION $INTERVAL $THREADCNT $SIZE $SCRIPTAUTH "$PARAMS" $RESULTDIR
	stop_profiler $SCRIPTAUTH "$PARAMS"
	RC=$?
	if [ $RC -ne 0 ]; then
		echo "$TAG: $SCRIPTRUN failed: $RC"
		echo "$TAG: params: $SLAMDHOME $DURATION $INTERVAL $THREADCNT $SIZE $SCRIPTAUTH "$PARAMS" $RESULTDIR"
		exit 1
	fi
	echo "$TAG: params: $SLAMDHOME $DURATION $INTERVAL $THREADCNT $SIZE $SCRIPTAUTH "$PARAMS" $RESULTDIR: PASS"
}

run_auth_all()
{
	TAG="run_auth_all"

	# initialize the db
	$INSTDIR/stop-slapd
	RC=$?
	if [ $RC -ne 0 ]; then
		echo "$TAG: Stopping the server failed: $RC"
		exit 1
	fi
	$INSTDIR/ldif2db -n $DBINST -i $TESTHOME/ldif/$TESTLDIF
	RC=$?
	if [ $RC -ne 0 ]; then
		echo "$TAG: Importing $TESTHOME/ldif/$TESTLDIF failed: $RC"
		exit 1
	fi
	# initialize the db
	$INSTDIR/start-slapd
	RC=$?
	if [ $RC -ne 0 ]; then
		echo "$TAG: Stopping the server failed: $RC"
		exit 1
	fi

	# cachememsize: 10M, dbcachesize: 10M, 4 threads
	run_auth $DEFAULT_CACHEMEMSIZE $DEFAULT_DBCACHESIZE 4 "10M.10M.4"

	# cachememsize: 2G, dbcachesize: 10M, 4 threads
	run_auth $TWOGIG $DEFAULT_DBCACHESIZE 4 "2G.10M.4"

	# cachememsize: 2G, dbcachesize: 1G, 4 threads
	run_auth $TWOGIG $ONEGIG 4 "2G.1G.4"

	# cachememsize: 2G, dbcachesize: 1G, 8 threads
	run_auth $TWOGIG $ONEGIG 8 "2G.1G.8"

# Uncomment when running on a large memory machine!!!
#	# cachememsize: 2G, dbcachesize: 1G, 16 threads
#	run_auth $TWOGIG $ONEGIG 16 "2G.1G.16"
#
#	# cachememsize: 2G, dbcachesize: 1G, 32 threads
#	run_auth $TWOGIG $ONEGIG 32 "2G.1G.32"
#
#	# cachememsize: 2G, dbcachesize: 1G, 64 threads
#	run_auth $TWOGIG $ONEGIG 64 "2G.1G.64"

	# generate auth result (avg/sec) for office calc
	ssh $SLAMDHOST $SCRIPTREP bind $RESULTDIR
}

print_usage()
{
	echo "Usage:"
	echo "$0 [-D <directory_manager>] [-w <passwd>]"
	echo "		[-h <ds_host>] [-p <ds_port>] [-i <ID>] [-d <dbinstname>]"
	echo "		[-s <suffix>] [-t <testhome>] [-z <size>, e.g., 10k]"
	echo "		[-l <testldif>] [-m <initldif>]"
	echo "		[-T <slamdhost>] [-E <slamdhome>] [-R <duration>]"
	echo "		[-I <interval>] [-P] [-S] [-A] [-M] [-U]"
	echo "	-P: run profiler"
	echo "	-S: run search"
	echo "	-A: run add and delete"
	echo "	-M: run modify"
	echo "	-U: run auth/bind"
	echo "	Note: if -[SAMU] not specified, run all 4 tests"
}

OPTIND=1
while getopts D:w:h:p:i:d:s:t:z:l:m:T:E:R:I:SAMUP C
do
	case $C in
	D)
		DIRMGR="$OPTARG"
		;;
	w)
		DIRMGRPW="$OPTARG"
		;;
	h)
		HOST="$OPTARG"
		;;
	p)
		PORT="$OPTARG"
		;;
	i)
		ID="$OPTARG"
		;;
	d)
		DBINST="$OPTARG"
		;;
	s)
		SUFFIX="$OPTARG"
		;;
	t)
		TESTHOME="$OPTARG"
		;;
	z)
		SIZE="$OPTARG"
		;;
	l)
		TESTLDIF="$OPTARG"
		;;
	m)
		INITLDIF="$OPTARG"
		;;
	T)
		SLAMDHOST="$OPTARG"
		;;
	E)
		SLAMDHOME="$OPTARG"
		;;
	R)
		DURATION="$OPTARG"
		;;
	I)
		INTERVAL="$OPTARG"
		;;
	S)
		OPSRCH=1
		OPALL=0
		;;
	A)
		OPADDDEL=1
		OPALL=0
		;;
	M)
		OPMOD=1
		OPALL=0
		;;
	U)
		OPAUTH=1
		OPALL=0
		;;
	P)
		WITHPROF=1
		;;
	\?)
		print_usage
		exit 1
		;;
	esac
done

setup_testenv

if [ $OPALL -eq 1 -o $OPADDDEL -eq 1 ]; then
	run_add_delete_all
fi

if [ $OPALL -eq 1 -o $OPSRCH -eq 1 ]; then
	run_search_all
fi

if [ $OPALL -eq 1 -o $OPMOD -eq 1 ]; then
	run_modify_all
fi

if [ $OPALL -eq 1 -o $OPAUTH -eq 1 ]; then
	run_auth_all
fi
