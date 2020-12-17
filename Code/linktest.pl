#!/usr/bin/perl -w

use strict;
use English;
use Getopt::Std;
use Data::Dumper;

my $HOSTS = "/etc/hosts";

my $doint = 0;

sub usage {
    print STDERR "Usage: $ARGV[0] [-hi] [node-to-skip node-to-skip ...]\n";
    print STDERR " -h\tPrint this help.\n";
    print STDERR " -i\tPing interfaces directly.\n";
    exit(-1);
}

my $optlist = "hi";
my %options = ();
if (!getopts($optlist,\%options)) {
    usage();
}
if (defined($options{'h'})) {
    usage();
}
if (defined($options{'i'})) {
    $doint = 1;
}
my @skipnodes = @ARGV;

my %hostmap = ();
open(FD,$HOSTS)
    or die "open($HOSTS): $!\n";
while (my $line = <FD>) {
    chomp($line);
    if ($line =~ /^([0-9a-z:]+)\s+node-([0-9a-z]+)-([0-9a-z]+)$/) {
        if (!exists($hostmap{$2})) {
            $hostmap{$2} = {};
        }
        $hostmap{$2}{$3} = $1;
        #print "$line\n";
    }
    elsif ($line =~ /^([0-9a-z:]+)\s+node-([0-9a-z]+)-([-0-9a-z]+)$/) {
        if (!exists($hostmap{$2})) {
            $hostmap{$2} = {};
        }
        $hostmap{$2}{$3} = $1;
        #print "$line\n";
    }
}
close(FD);

#print Dumper(%hostmap)."\n";

my ($f,$s) = (0,0);
for my $dn (sort(keys(%hostmap))) {
    for my $sn (sort(keys(%{$hostmap{$dn}}))) {
        my $daddr = $hostmap{$dn}{$sn};
        my $dest = "node-$dn-$sn";
        my ($srcnode,$dstnode);
        if ($sn =~ /^([0-9a-z]+)-(\d+)$/) {
            $srcnode = "node-$1";
            $dstnode = "node-$dn";
        }
        else {
            $srcnode = "node-$sn";
            $dstnode = "node-$dn";
        }
        if ($doint) {
            $dest = "node-$dn-$sn";
            $srcnode = "node-$dn";
            $dstnode = $srcnode;
        }
        my $cmd = "ssh $srcnode ping6 -n -c 4 -i 0.25 -t 2 $dest";
        print "$srcnode\t-> $dstnode\t$dest ($daddr):\t";
        if (grep {$_ eq $srcnode} @skipnodes) {
            print "SKIPPED ($srcnode)\n";
            next;
        }
        if (grep {$_ eq $dstnode} @skipnodes) {
            print "SKIPPED ($dstnode)\n";
            next;
        }
        my @lines = `$cmd 2>&1`;
        if ($?) {
            print "FAILURE\n";
            print STDERR "    ($cmd)\n";
            $f++;
        }
        else {
            print "SUCCESS\n";
            $s++;
        }
        if (@lines > 0) {
            for (my $i = @lines - 1; $i >= 0; $i--) {
                chomp($lines[$i]);
                if ($lines[$i] ne "") {
                    print "  " . $lines[$i] . "\n";
                    last;
                }
            }
        }
    }
}

print "\nSUMMARY: $s succeeded, $f failed.\n";

exit($f);
