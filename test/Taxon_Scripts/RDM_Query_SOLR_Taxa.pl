use strict;
use POSIX;
use Data::Dumper;
use Test::More;
use Config::Simple;
use Try::Tiny;
use Time::HiRes qw(time);
use Bio::KBase::AuthToken;
use Bio::KBase::workspace::Client;
use lib '/Users/seaver/Software/KBase_Repos/ReferenceDataManager/lib';
use ReferenceDataManager::ReferenceDataManagerImpl;

local $| = 1;
my $token = $ENV{'KB_AUTH_TOKEN'};
my $config_file = $ENV{'KB_DEPLOYMENT_CONFIG'};
my $config = new Config::Simple($config_file)->get_block('ReferenceDataManager');
my $scratch = $config->{"scratch"};
my $data = $config->{"data"};
my $ws_url = $config->{"workspace-url"};
my $ws_name = undef;
my $ws_client = new Bio::KBase::workspace::Client($ws_url,token => $token);
my $auth_token = Bio::KBase::AuthToken->new(token => $token, ignore_authrc => 1);
my $ctx = LocalCallContext->new($token, $auth_token->user_id);
$ReferenceDataManager::ReferenceDataManagerServer::CallContext = $ctx;
my $impl = new ReferenceDataManager::ReferenceDataManagerImpl();
my @temp=();

eval {
    $impl->util_initialize_call({},$ctx);

    $data.="/New_Prod_Taxa";
    my $core = "taxonomy_prod";
    my $fields="taxonomy_id,domain,kingdom,scientific_lineage";

    #Find Total Number first
    my $NumFound = $impl->_listTaxaInSolr($core,"taxonomy_id",0,0)->{response}{response}{'numFound'};
    print "Found $NumFound Taxa\n";

    my $batch_count = 5000;
    my $pages = ceil($NumFound/$batch_count);

    print "Solr contains $NumFound taxon objects.\n";
    print "Paging through $pages of $batch_count objects\n";

    open(OUT, "> ${data}/Listed_Taxa.txt");
    for (my $m = 0; $m < $pages; $m++) {
        my $start = $m * $batch_count;
	my $taxa = $impl->_listTaxaInSolr($core,$fields,$start,$batch_count);
    	print OUT join("\n", map { $_->{'taxonomy_id'}."\t".$_->{'domain'}."\t".$_->{'kingdom'}."\t".$_->{'scientific_lineage'} } @{$taxa->{response}{response}{docs}})."\n";
        sleep(1);
    } 
    close(OUT);

};
done_testing(1);

my $err = undef;
if ($@) {
    $err = $@;
}
eval {
    if (defined($ws_name)) {
        $ws_client->delete_workspace({workspace => $ws_name});
        print("Test workspace was deleted\n");
    }
};
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
        return [{'service' => 'KBaseReport', 'method' => 'please_never_use_it_in_production', 'method_params' => []}];
    }
    sub method {
	my($self) = @_;
	return $self->{method};
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
}
