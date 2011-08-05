# $0 <op>   <resultdir>
#     $1        $2
#    add    /.../slamd/results/<date>
#    delete     ..
#    search     ..
#    modify     ..
#    bind       ..
OP=$1
RESULTDIR=$2
DIRNAME=`dirname $0`
CALCSUM="perl $DIRNAME/calc-sum.pl"
# check result dir
if [ "$RESULTDIR" = "" ]; then
    echo "Usage: $0 <op> <resultdir>"
    exit 1
fi

TMPRESULTFILE=$RESULTDIR/$OP.avgpersec.tmp
RESULTFILE=$RESULTDIR/$OP.avgpersec.csv
echo "\"param(ecache.dbcache.threads)\";\"avg/sec\"" > $RESULTFILE
FILES=`/bin/ls $RESULTDIR/*$OP*.script-*-[0-9]*.out | wc -l`
if [ $FILES -eq 0 ]; then
    echo "Empty result" >> $RESULTFILE
else
    egrep -i "Successful $OP Operations -- Count:" $RESULTDIR/*$OP*.script-*.out | awk '{print $1, $10}' | sed -e "s/.out:conn /;/" | sed -e "s/.*.script.//" | sed -e "s/;$//" >> ${TMPRESULTFILE}.0
    awk -F/ '{print $NF}' $TMPRESULTFILE.0 | sort -n -t \. -k 3 > ${TMPRESULTFILE}.1
    $CALCSUM ${TMPRESULTFILE}.1 ${TMPRESULTFILE}.2
    cat ${TMPRESULTFILE}.2 >> $RESULTFILE
    rm ${TMPRESULTFILE}.*
fi
chmod 666 $RESULTFILE
