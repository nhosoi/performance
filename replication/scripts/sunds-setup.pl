use Getopt::Std;

use Net::LDAP;
use Net::LDAP::Message;

my $homedir = "/opt/sunds/dsee7";
my $instdir = "/opt/sunds";
my $servid = `hostname -s`;
chomp($servid);
my $port = 389;
my $masters = 0;
my $replicas = 0;
my $rootdn = "cn=directory manager";
my $rootdnpw = "password";
my $suffix = "dc=example,dc=com";
my $fqdn = `hostname -f`;
chomp $fqdn;
my $verbose = 0;
my $initldif = "/var/tmp/sundsinit.ldif";
my $tmppwfile = "/var/tmp/sunds-pw.txt";
my $backendname = "userroot";

sub usage {
    print "Usage:\n";
    print "sunds-setup.pl [-h <serverid>] [-p <port>]\n";
    print "               [-m <master count>] [-r <replica count>]\n";
    print "               [-w <rootdn password>] [-s <suffix>]\n";
    print "               [-I <instance dir, e.g. /opt/sunds>]\n";
    print "               [-H <home dir, e.g. /opt/sunds/dsee7>]\n";
    print "               [-v]\n";
    exit 0;
}

sub LDAPerror
{
    my ($from, $mesg) = @_;
    print "Return code: ", $mesg->code, "\n";
    print "Message: ", $mesg->error_name, "\n";
    print $mesg->error_text;
    print "MessageID: ", $mesg->mesg_id, "\n";

}

sub genInitLdif
{
    my $name = shift;

    if (!open(INITLDIF, "> $initldif")) {
        print"genInitLdif: failed to open $initldif\n";
        exit 1;
    }

    print INITLDIF "dn: $suffix\n";
    print INITLDIF "objectClass: top\n";
    if ( $suffix =~ /dc=/ ) {
        print INITLDIF "objectClass: domain\n";
        print INITLDIF "dc: $name\n";
    } elsif ( $suffix =~ /o=/ ) {
        print INITLDIF "objectClass: organization\n";
        print INITLDIF "o: $name\n";
    } else {
        print"genInitLdif: failed to open $initldif\n";
        `rm $initldif`;
        exit 1;
    }
    close INITLDIF;
}

usage() if (!getopts('I:H:h:p:m:r:w:s:v'));

if ($opt_I) {
    $instdir = $opt_I;
}

if ($opt_H) {
    $homedir = $opt_H;
}

if ($opt_h) {
    $servid = $opt_h;
}

if ($opt_p) {
    $port = $opt_p;
}

if ($opt_m) {
    $masters = $opt_m;
}

if ($opt_r) {
    $replicas = $opt_r;
}

if ($opt_w) {
    $rootdnpw = $opt_w;
}

if ($opt_s) {
    $suffix = $opt_s;
}

if ($opt_v) {
    $verbose = $opt_v;
}

if ( $suffix =~ m/dc=(\w+),*/ ||
     $suffix =~ m/o=(\w+)/ ) {
    $backendname = $1;
}

if ($verbose) {
    print "parameters:\n";
    print "\tserverid: $servid, port: $port\n";
    print "\tmasters: $masters, replicas: $replicas\n";
    print "\tsuffix: $suffix, backendname: $backendname\n";
    print "\trootdnpw: $rootdnpw\n";
    print "\thomedir: $homedir, installdir: $instdir\n";
}

if ($masters == 0 && $replicas == 0) {
    print "No servers are requested to set up.\n";
    exit 0;
}

`echo $rootdnpw > $tmppwfile`;

my $bindir = $homedir . "/bin";

my %masterid_port = ();
my %replicaid_port = ();

my $output = "";

################################
# install masters "slapd-IDM#" #
################################
for (my $i = 0; $i < $masters; $i++) {
    my $myservid = $servid . "M" . $i;
    print "$i: $myservid, $port\n";
    my $servdir = $instdir . "/slapd-" . $myservid;
    if (! -d $servdir) {
        my $sslport = $port + 100;
        $output = `$bindir/dsadm create -p $port -P $sslport -w $tmppwfile $instdir/slapd-$myservid`;
        if ($verbose) {
            print $output;
        }
    }
    $output = `$bindir/dsadm start $instdir/slapd-$myservid`;
    if ($verbose) {
        print $output;
    }
    $masterid_port{"$myservid"} = $port;
    $port++;
}

#################################
# install replicas "slapd-IDR#" #
#################################
for (my $i = 0; $i < $replicas; $i++) {
    my $myservid = $servid . "R" . $i;
    print "$i: $myservid, $port\n";
    my $servdir = $instdir . "/slapd-" . $myservid;
    if (! -d $servdir) {
        my $sslport = $port + 100;
        $output = `$bindir/dsadm create -p $port -P $sslport -w $tmppwfile $instdir/slapd-$myservid`;
        if ($verbose) {
            print $output;
        }
    }
    $output = `$bindir/dsadm start $instdir/slapd-$myservid`;
    if ($verbose) {
        print $output;
    }
    $replicaid_port{"$myservid"} = $port;
    $port++;
}

###################
# initialize ldap #
###################
my %masterid_ldap = ();
my %replicaid_ldap = ();
#my @security = ( 'nsslapd-security', "off" );
#my $configdn = "cn=config";
# masters
while (my ($myservid, $myport) = each %masterid_port) {
    if ($verbose) {
        print "Initialiazing " . $myservid . "; port " . $myport . "\n";
    }
    my $myldap = Net::LDAP->new ( $fqdn, port => $myport ) or die "$@";
    my $mesg = $myldap->bind($rootdn, password => "$rootdnpw", version => 3);
    if ($mesg->code) {
        print "bind to $fqdn:$myservid:$myport failed: ";
        LDAPerror("bind", $mesg);
        exit 1;
    }
#    my $mesg = $myldap->modify($configdn, changes => [
#                                replace => [ @security ]
#                            ]);
#    if ( $mesg->code ) {
#        print "$myservid: Disabling nsslapd-security failed: ";
#        LDAPerror("modify", $mesg);
#        exit 1;
#    }

    $masterid_ldap{"$myservid"} = $myldap;
}

# replicas
while (my ($myservid, $myport) = each %replicaid_port) {
    if ($verbose) {
        print "Initialiazing " . $myservid . "; port " . $myport . "\n";
    }
    my $myldap = Net::LDAP->new ( $fqdn, port => $myport ) or die "$@";
    my $mesg = $myldap->bind($rootdn, password => "$rootdnpw", version => 3);
    if ($mesg->code) {
        print "bind to $fqdn:$myservid:$myport failed: ";
        LDAPerror("bind", $mesg);
        exit 1;
    }
#    my $mesg = $myldap->modify($configdn, changes => [
#                                replace => [ @security ]
#                            ]);
#    if ( $mesg->code ) {
#        print "$myservid: Disabling nsslapd-security failed: ";
#        LDAPerror("modify", $mesg);
#        exit 1;
#    }

    $replicaid_ldap{"$myservid"} = $myldap;
}

##################
# adding backend #
##################
my $mappingtreedn = "cn=\"$suffix\",cn=mapping tree,cn=config";
my $mappingtree = [
    "objectClass" => [ "top", "nsMappingTree", "extensibleObject" ], 
    "nsslapd-state" => "backend",
    "nsslapd-backend" => $backendname
];
my $backenddn = "cn=$backendname,cn=ldbm database,cn=plugins,cn=config";
my $backend = [
    "objectClass" => [ "top", "nsBackendInstance", "extensibleObject" ], 
    "nsslapd-suffix" => $suffix,
];
my $suffixentry;
if ( $suffix =~ /dc=/ ) {
    $suffixentry = [
        "objectClass" => [ "top", "domain" ],
        "dc" => $backendname
    ];
} elsif ( $suffix =~ /o=/ ) {
    $suffixentry = [
        "objectClass" => [ "top", "organization" ],
        "o" => $backendname
    ];
} else {
    print "Cannot determine the type of suffix $suffix\n";
    print "Use domain (dc) or organization (o)\n";
    exit 1;
}
# masters
while (my ($myservid, $myldap) = each %masterid_ldap) {
    if ($verbose) {
        print "$myservid: Adding mappingtree: $mappingtreedn\n";
    }
    my $mesg = $myldap->add( $mappingtreedn, attrs => [ @$mappingtree ] );
    if ( 68 == $mesg->code ) {
        print "$myservid: mappingtree $mappingtreedn is already configured.\n";
    } elsif ( $mesg->code ) {
        print "$myservid: adding mappingtree $mappingtreedn failed: ";
        LDAPerror("add", $mesg);
        exit 1;
    }
    if ($verbose) {
        print "$myservid: Adding backend: $backenddn\n";
    }
    my $mesg = $myldap->add( $backenddn, attrs => [ @$backend ] );
    if ( 68 == $mesg->code ) {
        print "$myservid: backend $backenddn is already configured.\n";
    } elsif ( $mesg->code ) {
        print "$myservid: adding backend $backenddn failed: ";
        LDAPerror("add", $mesg);
        exit 1;
    }
    if ($verbose) {
        print "$myservid: Adding suffix: $suffix\n";
    }
    my $mesg = $myldap->add( $suffix, attrs => [ @$suffixentry ] );
    if ( 68 == $mesg->code ) {
        print "$myservid: suffix $suffix is already configured.\n";
    } elsif ( $mesg->code ) {
        print "$myservid: adding suffix $suffix failed: ";
        LDAPerror("add", $mesg);
        exit 1;
    }
}

# replicas
while (my ($myservid, $myldap) = each %replicaid_ldap) {
    if ($verbose) {
        print "$myservid: Adding mappingtree: $mappingtreedn\n";
    }
    my $mesg = $myldap->add( $mappingtreedn, attrs => [ @$mappingtree ] );
    if ( 68 == $mesg->code ) {
        print "$myservid: mappingtree $mappingtreedn is already configured.\n";
    } elsif ( $mesg->code ) {
        print "$myservid: adding mappingtree $mappingtreedn failed: ";
        LDAPerror("add", $mesg);
        exit 1;
    }
    if ($verbose) {
        print "$myservid: Adding backend: $backenddn\n";
    }
    my $mesg = $myldap->add( $backenddn, attrs => [ @$backend ] );
    if ( 68 == $mesg->code ) {
        print "$myservid: backend $backenddn is already configured.\n";
    } elsif ( $mesg->code ) {
        print "$myservid: adding backend $backenddn failed: ";
        LDAPerror("add", $mesg);
        exit 1;
    }
    if ($verbose) {
        print "$myservid: Adding suffix: $suffix\n";
    }
    my $mesg = $myldap->add( $suffix, attrs => [ @$suffixentry ] );
    if ( 68 == $mesg->code ) {
        print "$myservid: suffix $suffix is already configured.\n";
    } elsif ( $mesg->code ) {
        print "$myservid: adding suffix $suffix failed: ";
        LDAPerror("add", $mesg);
        exit 1;
    }
}

## import init.ldif
#genInitLdif $backendname;
#while (my ($myservid, $myport) = each %masterid_port) {
#    if ($verbose) {
#        print "$myservid: Importing $initldif\n";
#        print "$bindir/dsconf import -a -w $tmppwfile -p $myport $initldif $suffix\n";
#    }
#    $output = `echo 'y' | $bindir/dsconf import -a -w $tmppwfile -p $myport $initldif $suffix`;
#    if ($verbose) {
#        print $output;
#    }
#}
#while (my ($myservid, $myport) = each %replicaid_port) {
#    if ($verbose) {
#        print "$myservid: Importing $initldif\n";
#    }
#    $output = `echo 'y' | $bindir/dsconf import -a -w $tmppwfile -p $myport $initldif $suffix`;
#    if ($verbose) {
#        print $output;
#    }
#}
#`rm $tmppwfile`;

#####################
# adding cn=replica #
#####################
# replica type: 2 -- readonly; 3 -- updateable
# replica flags: 1 -- log changes; 0 -- no log changes
my $replica = [
    objectClass => [ "top", "nsds5replica", "extensibleObject" ], 
    cn => "replica",
    nsds5replicaroot => $suffix,
    nsds5replicatype => 3,
    nsds5flags => 1,
    nsds5replicabinddn => $rootdn
];
# masters
my $replid = 1;
my $replicadn = "cn=replica,cn=\"$suffix\",cn=mapping tree,cn=config";
while (my ($myservid, $myldap) = each %masterid_ldap) {
    if ($verbose) {
        print "Adding cn=replica to " . $myservid . "\n";
    }
    push @$replica, ("nsds5replicaid", $replid);
    my $mesg = $myldap->add( $replicadn, attrs => [ @$replica ] );
    if ( 68 == $mesg->code ) {
        print "$myservid: cn=replica is already configured.\n";
    } elsif ( $mesg->code ) {
        print "$myservid: adding replica entry failed: ";
        LDAPerror("add", $mesg);
        exit 1;
    }
    pop @$replica;
    pop @$replica;
    $replid++;
}

# replicas
my $replica = [
    objectClass => [ "top", "nsds5replica", "extensibleObject" ], 
    cn => "replica",
    nsds5replicaroot => $suffix,
    nsds5replicatype => 2,
    nsds5flags => 0,
    nsds5replicabinddn => $rootdn
];
$replicadn = "cn=replica,cn=\"$suffix\",cn=mapping tree,cn=config";
while (my ($myservid, $myldap) = each %replicaid_ldap) {
    if ($verbose) {
        print "Adding cn=replica to " . $myservid . "\n";
    }
    push @$replica, ("nsds5replicaid", $replid);
    my $mesg = $myldap->add( $replicadn, attrs => [ @$replica ] );
    if ( 68 == $mesg->code ) {
        print "$myservid: cn=replica is already configured.\n";
    } elsif ( $mesg->code ) {
        print "$myservid: adding replica entry failed: ";
        LDAPerror("add", $mesg);
        exit 1;
    }
    pop @$replica;
    pop @$replica;
    $replid++;
}

#####################
# adding agreements #
#####################
# among masters
my %masterid_ldap2 = %masterid_ldap;
my @agreementset = ();
my $primservid = "";
while (my ($fromservid, $myldap) = each %masterid_ldap) {
    while (my ($toservid, $unused) = each %masterid_ldap2) {
        if ( $fromservid ne $toservid ) {
            if ($primservid eq "") {
                $primservid = $fromservid;
            }
            my $agreement = [
                objectClass => 
                    [ "top", "nsds5replicationagreement", "extensibleObject" ], 
                nsds5replicahost => $fqdn,
                nsds5replicaport => $masterid_port{"$toservid"},
                nsds5replicabinddn => $rootdn,
                nsds5replicacredentials => $rootdnpw,
                nsds5replicabindmethod => "SIMPLE",
                nsds5replicaroot => $suffix,
                description => "$fromservid to $toservid",
                nsds5replicaupdateschedule => "*",
                ds5AgreementEnable => "on",
                nsDS5ReplicaTransportInfo => "LDAP"
            ];
            my $agreementname = $fromservid . "_to_" . $toservid;
            my $agreementdn = "cn=$agreementname,cn=replica,cn=\"$suffix\",cn=mapping tree,cn=config";
            if ($fromservid eq $primservid) {
                push @agreementset, $agreementdn;
            }
            if ($verbose) {
                print "Adding agreement $agreementdn to $fromservid \n";
            }
            my $mesg = $myldap->add( $agreementdn, attrs => [ @$agreement ] );
            if ( 68 == $mesg->code ) {
                print "$fromservid: agreement $agreementname is already configured.\n";
            } elsif ( $mesg->code ) {
                print "$myservid: adding agreement entry $agreementdn failed: ";
                LDAPerror("add", $mesg);
                exit 1;
            }
        }
    }
}

# masters to replicas
while (my ($fromservid, $myldap) = each %masterid_ldap) {
    while (my ($toservid, $unused) = each %replicaid_ldap) {
        if ($primservid eq "") {
            $primservid = $fromservid;
        }
        my $agreement = [
            objectClass => 
                    [ "top", "nsds5replicationagreement", "extensibleObject" ], 
            nsds5replicahost => $fqdn,
            nsds5replicaport => $replicaid_port{"$toservid"},
            nsds5replicabinddn => $rootdn,
            nsds5replicacredentials => $rootdnpw,
            nsds5replicabindmethod => "SIMPLE",
            nsds5replicaroot => $suffix,
            description => "$fromservid to $toservid",
            nsds5replicaupdateschedule => "*",
            ds5AgreementEnable => "on",
            nsDS5ReplicaTransportInfo => "LDAP"
        ];
        my $agreementname = $fromservid . "_to_" . $toservid;
        my $agreementdn = "cn=$agreementname,cn=replica,cn=\"$suffix\",cn=mapping tree,cn=config";
        if ($fromservid eq $primservid) {
            push @agreementset, $agreementdn;
        }
        if ($verbose) {
            print "Adding agreement $agreementdn to $fromservid \n";
        }
        my $mesg = $myldap->add( $agreementdn, attrs => [ @$agreement ] );
        if ( 68 == $mesg->code ) {
            print "$fromservid: agreement $agreementname is already configured.\n";
        } elsif ( $mesg->code ) {
            print "$myservid: adding agreement entry $agreementdn failed: ";
            LDAPerror("add", $mesg);
            exit 1;
        }
    }
}

########################
# initialize consumers #
########################
my $ldap = $masterid_ldap{"$primservid"};
my @initconsumer = ( 'nsds5beginreplicarefresh', "start" );
while(my $agreementdn = pop(@agreementset)) {
    if ($verbose) {
        print "Initializing consumer with $agreementdn.\n";
    }
    my $mesg = $ldap->modify($agreementdn, changes => [
                    replace => [ @initconsumer ]
                    ]);
    if ( $mesg->code ) {
        print "$primservid: initialize consumer with $agreementdn failed: ";
        LDAPerror("modify", $mesg);
        exit 1;
    }
}

while (my ($myservid, $myldap) = each %masterid_ldap) {
    $myldap->unbind;
}

while (my ($myservid, $myldap) = each %replicaid_ldap) {
    $myldap->unbind;
}
