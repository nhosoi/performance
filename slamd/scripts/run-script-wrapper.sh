# $0 <slamdhome> <duration> <interval> <threads> <size> <script>      <params> <resultdir>
#        $1          $2         $3        $4        $5     $6            $7        $8
#    /.../slamd     600         10         4       10k   modify.script 2G.1G.4 /.../slamd/results/<date>
#                                                                      entrycache.dbcache.threads
SLAMDHOME=$1
THREADS=$4
RESULTDIR=$8
# check result dir
if [ "$RESULTDIR" = "" ]; then
	echo "Usage: $0 <slamdhome> <duration> <interval> <threads> <size> <script> <params> <resultdir>"
	exit 1
fi
if [ ! -d $RESULTDIR ]; then
	mkdir -p $RESULTDIR
fi

# if $THREADS > 4, we run multiple run-scripts.sh with -t 4 (and remain).
if [ $THREADS -gt 4 ]; then
  PROCS=`expr $THREADS / 4`
  TMPTH=`expr $PROCS \* 4`
  REMAIN=`expr $THREADS - $TMPTH`
  I=0
  while [ $I -lt $PROCS ]; do
    $SLAMDHOME/tools/run-script.sh -d $2 -i $3 -t 4 -a $SLAMDHOME/scripts/$5/$6 > $RESULTDIR/$6-$7-$I.out 2> $RESULTDIR/$6-$7-$I.err
	I=`expr $I + 1`
  done
  if [ $REMAIN -gt 0 ]; then
    $SLAMDHOME/tools/run-script.sh -d $2 -i $3 -t $REMAIN -a $SLAMDHOME/scripts/$5/$6 > $RESULTDIR/$6-$7-$I.out 2> $RESULTDIR/$6-$7-$I.err
  fi
else
  $SLAMDHOME/tools/run-script.sh -d $2 -i $3 -t $4 -a $SLAMDHOME/scripts/$5/$6 > $RESULTDIR/$6-$7.out 2> $RESULTDIR/$6-$7.err
fi
