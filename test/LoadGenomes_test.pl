use strict;
use Data::Dumper;
use Test::More;
use Config::Simple;
use Time::HiRes qw(time);
use Bio::KBase::AuthToken;
use Bio::KBase::workspace::Client;
use ReferenceDataManager::ReferenceDataManagerImpl;

use Config::IniFiles;


local $| = 1;
my $token = $ENV{'KB_AUTH_TOKEN'};
my $config_file = $ENV{ KB_DEPLOYMENT_CONFIG };
my $cfg = Config::IniFiles->new(-file=>$config_file);
my $wsInstance = $cfg->val('ReferenceDataManager','workspace-url');
die "no workspace-url defined" unless $wsInstance;


#my $config = new Config::Simple($config_file)->get_block('ReferenceDataManager');
#my $ws_url = $config->{"workspace-url"};
#my $ws_name = undef;
#my $ws_client = new Bio::KBase::workspace::Client($ws_url,token => $token);
my $auth_token = Bio::KBase::AuthToken->new(token => $token, ignore_authrc => 1);
my $ctx = LocalCallContext->new($token, $auth_token->user_id);
$ReferenceDataManager::ReferenceDataManagerServer::CallContext = $ctx;
my $impl = new ReferenceDataManager::ReferenceDataManagerImpl();

eval {
    #Altering workspace map
    $impl->{_workspace_map}->{refseq} = "ReferenceDataManagerWS";

    #Testing the list_reference_genomes function
    my $refret;
    eval {
        $refret = $impl->list_reference_genomes({
            refseq => 1,
            update_only => 0
        });
    };
    ok(!$@,"list_reference_Genomes command successful");
    if ($@) {
        print "ERROR:".$@;
    } else {
        print "Number of records:".@{$refret}."\n";
        print "First record:\n";
        print Data::Dumper->Dump([$refret->[0]])."\n";
    }
    ok(defined($refret->[0]),"list_reference_Genomes command returned at least one genome");

    #Testing load_genomes function
    my $ret;
    eval {
        $ret = $impl->load_genomes({
            genomes => $refret,
            index_in_solr => 0
        });
    };
    ok(!$@,"load_genomes command successful");
    if ($@) {
        print "ERROR:".$@;
        #my $err = $@;
        #print "Error type: " . ref($err) . "\n";
        #print "Error message: " . $err->{message} . "\n";
        #print "Error error: " . $err->{error} . "\n";
        #print "Error data: " .$err->{data} . "\n";
    } else {
        print "Loaded @{$ret} genomes:\n";
        print Data::Dumper->Dump([$ret->[0]])."\n";
    }
    ok(defined($ret->[0]),"load_genomes command returned at least one genome");
    done_testing(2);
};

my $err = undef;
if ($@) {
    $err = $@;
}
if (defined($err)) {
    if(ref($err) eq "Bio::KBase::Exceptions::KBaseException") {
        die("Error while running tests: " . $err->trace->as_string);
    } else {
        die $err;
    }
}

{
    package LocalCallContext;
    use strict;
    sub new {
        my($class,$token,$user) = @_;
        my $self = {
            token => $token,
            user_id => $user
        };
        return bless $self, $class;
    }
    sub user_id {
        my($self) = @_;
        return $self->{user_id};
    }
    sub token {
        my($self) = @_;
        return $self->{token};
    }
    sub provenance {
        my($self) = @_;
        return [{'service' => 'ReferenceDataManager', 'method' => 'please_never_use_it_in_production', 'method_params' => []}];
    }
    sub authenticated {
        return 1;
    }
    sub log_debug {
        my($self,$msg) = @_;
        print STDERR $msg."\n";
    }
    sub log_info {
        my($self,$msg) = @_;
        print STDERR $msg."\n";
    }
    sub method {
        my($self) = @_;
        return "TEST_METHOD";
    }
}
