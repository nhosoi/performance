# $0 <slamdhome> <duration> <interval> <threads> <size> <script>      <params> <resultdir>
#        $1          $2         $3        $4        $5     $6            $7        $8
#    /.../slamd     600         10         4       10k   modify.script 2G.1G.4 /.../slamd/results/<date>
#                                                                      entrycache.dbcache.threads
SLAMDHOME=$1
RESULTDIR=$8
# check result dir
if [ "$RESULTDIR" = "" ]; then
	echo "Usage: $0 <slamdhome> <duration> <interval> <threads> <size> <script> <params> <resultdir>"
	exit 1
fi
if [ ! -d $RESULTDIR ]; then
	mkdir -p $RESULTDIR
fi
$SLAMDHOME/tools/run-script.sh -d $2 -i $3 -t $4 -a $SLAMDHOME/scripts/$5/$6 > $RESULTDIR/$6-$7.out 2> $RESULTDIR/$6-$7.err
