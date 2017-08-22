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
    $data.="/Prod_Taxa";
    my $core = "taxonomy_prod";
    
    open(FH, "< ${data}/NCBI_Deleted_Taxa.txt");
    my %Deleted_Taxa=();
    while(<FH>){
        chomp;
        @temp=split(/\t/,$_);
        $Deleted_Taxa{$temp[0]}=1;
    }
    close(FH);
    
    my $Taxon_WS="ReferenceTaxons";
    my $Taxa_To_Fetch=[];
    foreach my $taxon (keys %Deleted_Taxa){
        my $taxon_ref=$Taxon_WS."/".$taxon."_taxon";
        push(@$Taxa_To_Fetch,{ref=>$taxon_ref});
    }
    my $Fetched_Taxa = [map { $_ } @{$impl->util_ws_client()->get_objects2({objects=>$Taxa_To_Fetch,ignoreErrors=>1})->{data}}]; 
    #print Data::Dumper::Dumper($Fetched_Taxa->[0]),"\n";

    my $Taxa_To_Load_in_SOLR=[];
    foreach my $taxon (@$Fetched_Taxa){
	my $taxon_ref = $taxon->{info}[6]."/".$taxon->{info}[0]."/".$taxon->{info}[4];
	my $taxon_name = $taxon->{info}[1];

	#update deleted flag
	$taxon->{data}{deleted}=1;

	push(@$Taxa_To_Load_in_SOLR,{taxon=>$taxon->{data},ws_ref=>$taxon_ref});
   }

   print Data::Dumper::Dumper($Taxa_To_Load_in_SOLR->[0]),"\n";

   try{
	$impl->index_taxa_in_solr({taxa=>$Taxa_To_Load_in_SOLR,solr_core=>$core,create_report=>0});
    }catch{
	print "Indexing error: $_\n";
    };
    print("Updated ".scalar(@$Taxa_To_Load_in_SOLR)." deleted Taxa\n");

};
print $@,"\n" if $@;
ok(!$@,"Finished updating taxa\n");

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
