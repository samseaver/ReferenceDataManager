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

    my $core = "taxonomy_prod";
    $data.="/Prod_Taxa/";

    open(FH, "< ${data}/Listed_Taxa.txt");
    my %SOLRTaxa=();
    while(<FH>){
	chomp;
	@temp=split(/\t/,$_);
	$SOLRTaxa{$temp[0]}=1;	
    }
    close(FH);
    print "Found ".scalar(keys %SOLRTaxa)." Taxa in SOLR\n";

    open(FH, "< ${data}/Loaded_Taxa.txt");
    while(<FH>){
        chomp;
	@temp=split(/\t/,$_);
        $SOLRTaxa{$temp[0]}=1;
    }
    close(FH);
	
    my $ncbi_taxa = $impl->_extract_ncbi_taxa();
    print("Extracted ".scalar(@$ncbi_taxa)." NCBI taxa\n");

    $ncbi_taxa = [ grep { !exists($SOLRTaxa{$_->{'taxonomy_id'}}) } @$ncbi_taxa  ];
    my $NumFound = scalar(@$ncbi_taxa);
    print "Loading $NumFound new Taxa!\n";
    
    my $batch_count = 10;
    my $pages = ceil($NumFound/$batch_count);
    print "Paging through $pages of $batch_count objects\n";

    my $Taxon_WS="ReferenceTaxons";
    my $taxon_provenance = [{"script"=>$0, "script_ver"=>"0.1", "description"=>"Taxon generated from NCBI taxonomy names and nodes files downloaded on 1/19/2017."}];
    open(OUT, ">> ${data}/Loaded_Taxa.txt");
    for (my $m = 0; $m < $pages; $m++) {
	my ($start,$end) = ( $m * $batch_count , ( $batch_count * ($m+1) -1 ) );
	$end = $NumFound-1 if $end >= $NumFound;
	next if $start > $end;

	my $taxa_to_load=[];
	for(my $i = $start;$i<=$end;$i++){
	    next if exists($SOLRTaxa{$ncbi_taxa->[$i]{'taxonomy_id'}});
	    push(@$taxa_to_load,$ncbi_taxa->[$i]);
	}

	my $Taxa_To_Load_in_WS=[];
	my $Taxa_To_Load_in_SOLR=[];
	foreach my $obj (@$taxa_to_load){
	    $obj->{'parent_taxon_ref'}=$Taxon_WS."/".$obj->{'parent_taxon_id'}."_taxon";
	    delete $obj->{'parent_taxon_ref'} if $obj->{'taxonomy_id'}==1;
	    delete $obj->{'parent_taxon_id'};
	
	    my $taxon_name = $obj->{"taxonomy_id"}."_taxon";
	    #print "Updating $taxon_name\n";
	    $obj->{"taxonomy_id"}+=0;
	    push(@$Taxa_To_Load_in_WS,{"type"=>"KBaseGenomeAnnotations.Taxon",
				 "data"=>$obj,
				 "name"=>$taxon_name,
				 "provenance"=>$taxon_provenance});
	    push(@$Taxa_To_Load_in_SOLR,{taxon=>$obj,ws_ref=>$Taxon_WS."/".$taxon_name});
	}

	my $saved_objects=[];
	if(scalar(@$Taxa_To_Load_in_WS)){

 	    if(!$impl->_ping()){
		die "SOLR not responding: ".$impl->_error()->{response}."\n";
	    }
	    my $try_count=5;
	    while(scalar(@$saved_objects)==0 && $try_count != 0){
		$try_count--;
		print "Load started for page ${m} at ",scalar(localtime),"\n";
		try{
		    $saved_objects=$impl->util_ws_client()->save_objects({"workspace"=>$Taxon_WS,"objects"=>$Taxa_To_Load_in_WS});
		}catch{
		    print "ERROR on iteraction $try_count for Batch $batch_count: Cannot save objects: $_ at ".scalar(localtime)."\n";
		};
		print "Load ended for page ${m} at ",scalar(localtime),"\n";
		sleep(3) if scalar(@$saved_objects)==0;
	    }
	}
	foreach my $item (@$saved_objects){
	    my $taxid = $item->[1];
	    $taxid =~ s/_taxon//;
	    print OUT $taxid."\t".$item->[0]."\n";
	}
	if(scalar(@$saved_objects)){
	    print Data::Dumper::Dumper($Taxa_To_Load_in_SOLR);
	    try{	
	        $impl->index_taxa_in_solr({taxa=>$Taxa_To_Load_in_SOLR,solr_core=>$core,create_report=>0});
	    }catch{
		print "Indexing error: $_\n";
	    };
	}
	print("Loaded ".scalar(@$saved_objects)." New NCBI Taxa\n");
    }
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
