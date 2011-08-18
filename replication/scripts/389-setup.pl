use Getopt::Std;

use Net::LDAP;
use Net::LDAP::Message;

sub usage {
    print "Usage:\n";
    print "389-setup.pl [-h <serverid>] [-p <port>]\n";
    print "             [-m <master count>] [-r <replica count>]\n";
    print "             [-w <rootdn password>] [-s <suffix>]\n";
    print "             [-v]\n";
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

usage() if (!getopts('h:p:m:r:w:s:v'));

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

if ($verbose) {
    print "parameters:\n";
    print "\tserverid: $servid, port: $port\n";
    print "\tmasters: $masters, replicas: $replicas\n";
    print "\trootdnpw: $rootdnpw\n";
}

if ($masters == 0 && $replicas == 0) {
    print "No servers are requested to set up.\n";
    exit 0;
}

sub geninffile
{
    my $servid = shift;
    my $port = shift;
    my $tmpinffile = "/var/tmp/389-" . $servid . ".inf";
    my $is64 = (`uname -r` =~ /x86_64/);
    my $str64 = "";

    if ($is64) {
        $str64 = "64";
    }
    if (!open(INF, "> $tmpinffile")) {
        print"geninffile: failed to open $tmpinffile\n";
        exit 1;
    }
    print INF "[General]\n";
    print INF "FullMachineName = " . `hostname -f`;
    print INF "ServerRoot = /usr/lib" . $str64 . "/dirsrv\n";
    print INF "SuiteSpotGroup = nobody\n";
    print INF "SuiteSpotUserID = nobody\n";
    print INF "[slapd]\n";
    print INF "AddOrgEntries = Yes\n";
    print INF "AddSampleEntries = No\n";
    print INF "InstallLdifFile = suggest\n";
    print INF "RootDN = cn=Directory Manager\n";
    print INF "RootDNPwd = " . $rootdnpw . "\n";
    print INF "ServerIdentifier = " . $servid . "\n";
    print INF "ServerPort = " . $port . "\n";
    print INF "Suffix = " . $suffix . "\n";
    print INF "bak_dir = /var/lib/dirsrv/slapd-" . $servid . "/bak\n";
    print INF "bindir = /usr/bin\n";
    print INF "cert_dir = /etc/dirsrv/slapd-" . $servid . "\n";
    print INF "config_dir = /etc/dirsrv/slapd-". $servid . "\n";
    print INF "datadir = /usr/share\n";
    print INF "db_dir = /var/lib/dirsrv/slapd-" . $servid . "/db\n";
    print INF "ds_bename = userRoot\n";
    print INF "inst_dir = /usr/lib64/dirsrv/slapd-" . $servid . "\n";
    print INF "ldif_dir = /var/lib/dirsrv/slapd-" . $servid . "/ldif\n";
    print INF "localstatedir = /var\n";
    print INF "lock_dir = /var/lock/dirsrv/slapd-" . $servid . "\n";
    print INF "log_dir = /var/log/dirsrv/slapd-" . $servid . "\n";
    print INF "naming_value = example\n";
    print INF "run_dir = /var/run/dirsrv\n";
    print INF "sbindir = /usr/sbin\n";
    print INF "schema_dir = /etc/dirsrv/slapd-" . $servid . "/schema\n";
    print INF "sysconfdir = /etc\n";
    print INF "tmp_dir = /tmp\n";
    close(INF);
}
 
my %masterid_port = ();
my %replicaid_port = ();

################################
# install masters "slapd-IDM#" #
################################
for (my $i = 0; $i < $masters; $i++) {
    my $myservid = $servid . "M" . $i;
    #print "$i: $myservid, $port\n";
    my $sysdir = "/etc/dirsrv/slapd-" . $myservid;
    if (! -d $sysdir) {
        my $tmpinffile = "/var/tmp/389-" . $myservid . ".inf";
        geninffile($myservid, $port);
        my $output = `setup-ds.pl --silent --file=$tmpinffile`;
        if ($verbose) {
            print $output;
        }
    }
    $masterid_port{"$myservid"} = $port;
    $port++;
}

#################################
# install replicas "slapd-IDR#" #
#################################
for (my $i = 0; $i < $replicas; $i++) {
    my $myservid = $servid . "R" . $i;
    #print "$i: $myservid, $port\n";
    my $sysdir = "/etc/dirsrv/slapd-" . $myservid;
    if (! -d $sysdir) {
        my $tmpinffile = "/var/tmp/389-" . $myservid . ".inf";
        geninffile($myservid, $port);
        my $output = `setup-ds.pl --silent --file=$tmpinffile`;
        if ($verbose) {
            print $output;
        }
    }
    $replicaid_port{"$myservid"} = $port;
    $port++;
}

###################
# initialize ldap #
###################
my %masterid_ldap = ();
my %replicaid_ldap = ();
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

    $replicaid_ldap{"$myservid"} = $myldap;
}

####################
# adding changelog #
####################
my $changelog = [
    objectClass => [ "top", "extensibleObject" ],
    cn => "changelog5"
];
my $changelogdn = "cn=changelog5,cn=config";
while (my ($myservid, $myldap) = each %masterid_ldap) {
    if ($verbose) {
        print "Adding changelog to " . $myservid . "\n";
    }
    my $cldir = "/var/lib/dirsrv/slapd-" . $myservid .  "/changelogdb";
    push @$changelog, ("nsslapd-changelogdir", $cldir);
    my $mesg = $myldap->add( $changelogdn, attrs => [ @$changelog ] );
    if ( 68 == $mesg->code ) {
        print "$myservid: changelog is already configured.\n";
    } elsif ( $mesg->code ) {
        print "$myservid: adding changelog config entry failed: ";
        LDAPerror("add", $mesg);
        exit 1;
    }
    pop @$changelog;
    pop @$changelog;
}

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
                nsds5replicaupdateschedule => "0000-2359 0123456"
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
            nsds5replicaupdateschedule => "0000-2359 0123456"
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
