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
#   2G.10M.4;6715.561
#   2G.1G.8;10115.616
#          ...

$srcfile = $ARGV[0];
$destfile = $ARGV[1];

open(SRCFILE, "$srcfile");
open(DESTFILE, "> $destfile");
$cnt = 0;
$ckey = "";
$sum = 0;
while ($line=<SRCFILE>) {
	chop $line;	
	if ( $line =~ /\..*\.\d*(-\d*)*;\d*\./ ) {
		($rkey, $val) = split(';', $line, 2);
		($key, $t) = split('-', $rkey, 2);
		if ( $ckey ne $key ) {
			if ( $ckey ne "" ) {
				print DESTFILE "$ckey;$sum\n";
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
print DESTFILE "$ckey;$sum\n";

close SRCFILE;
close DESTFILE;
