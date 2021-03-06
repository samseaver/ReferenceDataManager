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
    #$impl->{_workspace_map}->{refseq} = "RefSeq_Genomes";

=begin test delete solr documents
    #Wipe out the whole QZtest content!
    my $slr_core = "YourCoreName";
    my $ds = {
         #'workspace_name' => 'qzTest',
         #'genome_id' => 'kb|g.0'
         '*' => '*' 
    };
    #$impl->_deleteRecords($slr_core, $ds);
=cut

    #Testing list_loaded_taxa
    my $taxon_ret;
    eval {
        $taxon_ret = $impl->list_loaded_taxa({ 
            workspace_name => "ReferenceTaxons",
            create_report => 0
    });
    };
    ok(!$@,"list_loaded_taxa command successful");
    if ($@) {
		my $err = $@;
		print "Error type: " . ref($err) . "\n";
		print "Error message: " . $err->{message} . "\n";
		print "Error error: " . $err->{error} . "\n";
		print "Error data: " .$err->{data} . "\n";
    } else {
        print "Number of records:".@{$taxon_ret}."\n";
        print "First record:\n";
        print Data::Dumper->Dump([$taxon_ret->[0]])."\n";
    }
    ok(defined($taxon_ret->[0]),"list_loaded_taxa command returned at least one taxon");

    #Testing index_taxa_in_solr
    my $solr_ret;
    eval {
        $solr_ret = $impl->index_taxa_in_solr({ 
                taxa => $taxon_ret,
                solr_core => "taxonomy_ci",
                create_report => 0
        });
    };
    ok(!$@,"index_taxa_in_solr command successful");
    if ($@) {
		my $err = $@;
		print "Error type: " . ref($err) . "\n";
		print "Error message: " . $err->{message} . "\n";
		print "Error error: " . $err->{error} . "\n";
		print "Error data: " .$err->{data} . "\n";
    } else {
        print "Number of records:".@{$solr_ret}."\n";
        print "First record:\n";
        print Data::Dumper->Dump([$solr_ret->[0]])."\n";
    }
    ok(defined($solr_ret->[0]),"index_taxa_in_solr command returned at least one taxon");
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
