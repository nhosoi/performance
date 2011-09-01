# $0 <port> <DMPW> <slamdhome> <duration> <interval> <threads> 
#      $1     $2        $3         $4         $5         $6
#                  /.../slamd     600         10          4       
#    <size> <script>       <params>       <resultdir>
#      $7      $8            $9              $10
#      10k   modify.script 2G.1G.4        /.../slamd/results/<date>
#                          entrycache.dbcache.threads
PORT=$1
DIRMGRPW="$2"
SLAMDHOME="$3"
DURATION=$4
INTERVAL=$5
THREADS=$6
SIZE=$7
SCRIPT="$8"
PARAMS="$9"
RESULTDIR="${10}"
# check result dir
if [ "$RESULTDIR" = "" ]; then
    echo "Usage: $0 <port> <dirmgrpw> <slamdhome> <duration> <interval> <threads> <size> <script> <params> <resultdir>"
    exit 1
fi
if [ ! -d $RESULTDIR ]; then
    mkdir -p $RESULTDIR
fi

cat $SLAMDHOME/scripts/$SIZE/$SCRIPT.template | sed -e "s/%PORT%/$PORT/" | \
 sed -e "s/%DIRMGRPW%/$DIRMGRPW/" > $SLAMDHOME/scripts/$SIZE/$SCRIPT

# if $THREADS > 4, we run multiple run-scripts.sh with -t 4 (and remain).
if [ $THREADS -gt 4 ]; then
  PROCS=`expr $THREADS / 4`
  LASTPROC=`expr $PROCS - 1`
  TMPTH=`expr $PROCS \* 4`
  REMAIN=`expr $THREADS - $TMPTH`
  I=0
  while [ $I -lt $PROCS ]; do
    if [ $REMAIN -eq 0 -a $I -eq $LASTPROC ]; then
        # run forground
        $SLAMDHOME/tools/run-script.sh -d $DURATION -i $INTERVAL -t 4 -a $SLAMDHOME/scripts/$SIZE/$SCRIPT > $RESULTDIR/$SCRIPT-$PARAMS-$I.out 2> $RESULTDIR/$SCRIPT-$PARAMS-$I.err
    else
        # run background
        $SLAMDHOME/tools/run-script.sh -d $DURATION -i $INTERVAL -t 4 -a $SLAMDHOME/scripts/$SIZE/$SCRIPT > $RESULTDIR/$SCRIPT-$PARAMS-$I.out 2> $RESULTDIR/$SCRIPT-$PARAMS-$I.err &
    fi
    I=`expr $I + 1`
  done
  if [ $REMAIN -gt 0 ]; then
    # run forground
    $SLAMDHOME/tools/run-script.sh -d $DURATION -i $INTERVAL -t $REMAIN -a $SLAMDHOME/scripts/$SIZE/$SCRIPT > $RESULTDIR/$SCRIPT-$PARAMS-$I.out 2> $RESULTDIR/$SCRIPT-$PARAMS-$I.err
  fi

  # all done?
  FMESSAGE="Job Processing Complete"
  I=0
  while [ $I -lt $PROCS ]; do
    egrep "$FMESSAGE" $RESULTDIR/$SCRIPT-$PARAMS-$I.out
    RC=$?
    if [ $RC -ne 0 ]; then
        sleep 10
    else
        I=`expr $I + 1`
    fi
  done
else
  $SLAMDHOME/tools/run-script.sh -d $DURATION -i $INTERVAL -t $THREADS -a $SLAMDHOME/scripts/$SIZE/$SCRIPT > $RESULTDIR/$SCRIPT-$PARAMS.out 2> $RESULTDIR/$SCRIPT-$PARAMS.err
fi
