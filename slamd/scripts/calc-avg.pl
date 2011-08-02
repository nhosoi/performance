#!/usr/bin/perl

# $0 <inputfile> <outputfile>
#
# sample inputfile:
#   10M.10M.4;2910.165
#   2G.10M.4-0;3357.780
#   2G.10M.4-1;3357.781
#   2G.1G.8-0;3371.873
#   2G.1G.8-1;3371.871
#   2G.1G.8-2;3371.872
#          ...
#
# outputfile:
#   10M.10M.4;2910.165
#   2G.10M.4;3357.7805
#   2G.1G.8;3371.871
#          ...

$srcfile = $ARGV[0];
$destfile = $ARGV[1];

open(SRCFILE, "$srcfile");
open(DESTFILE, "> $destfile");
$cnt = 0;
$ckey = "";
$sum = 0;
while ($line=<SRCFILE>) {
	if ( $line =~ /\..*\.\d*(-\d*)*;\d*\./ ) {
		($rkey, $val) = split(';', $line, 2);
		($key, $t) = split('-', $rkey, 2);
		if ( $ckey ne $key ) {
			if ( $ckey ne "" ) {
				$avg = $sum / $cnt;
				print DESTFILE "$ckey;$avg\n";
			}
			$ckey = $key;
			$sum = $val;
			$cnt = 1;
		} else {
			$sum += $val;
			$cnt++;
		}
	}
}
$avg = $sum / $cnt;
print DESTFILE "$ckey;$avg\n";

close SRCFILE;
close DESTFILE;
