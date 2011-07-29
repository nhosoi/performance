# $0 <op>   <resultdir>
#     $1        $2
#    add    /.../slamd/results/<date>
#    delete     ..
#    search     ..
#    modify     ..
#    bind       ..
OP=$1
RESULTDIR=$2
# check result dir
if [ "$RESULTDIR" = "" ]; then
    echo "Usage: $0 <op> <resultdir>"
    exit 1
fi

RESULTFILE=$RESULTDIR/$OP.avgpersec.csv
echo "\"param(ecache.dbcache.threads)\";\"avg/sec\"" > $RESULTFILE
egrep -i "Successful $OP Operations -- Count:" $RESULTDIR/*$OP*.script-*.out | awk '{print $1, $10}' | sed -e "s/.out:conn /;/" | sed -e "s/.*.script.//" | sed -e "s/;$//" >> $RESULTFILE
chmod 666 $RESULTFILE
