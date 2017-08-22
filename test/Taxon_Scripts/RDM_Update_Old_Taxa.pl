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
    
    open(FH, "< ${data}/Updated_Taxa.txt");
    my %Objects_to_Ignore=();
    while(<FH>){
        chomp;
        @temp=split(/\t/,$_);
        $Objects_to_Ignore{$temp[1]}=1;
    }
    close(FH);

    open(FH, "< ${data}/Loaded_Taxa.txt");
    while(<FH>){
        chomp;
        @temp=split(/\t/,$_);
        $Objects_to_Ignore{$temp[1]}=1;
    }
    close(FH);

    open(FH, "< ${data}/Unchanged_Taxa.txt");
    while(<FH>){
        chomp;
        @temp=split(/\t/,$_);
        $Objects_to_Ignore{$temp[1]}=1;
    }
    close(FH);
    print "Ignoring ".scalar(keys %Objects_to_Ignore)." previously updated Taxa\n";

    open(FH, "< ${data}/NCBI_Deleted_Taxa.txt");
    while(<FH>){
        chomp;
        @temp=split(/\t/,$_);
        $Objects_to_Ignore{$temp[1]}=1;
    }
    close(FH);
    
    my $ncbi_taxa = $impl->_extract_ncbi_taxa();
    print("Extracted ".scalar(@$ncbi_taxa)." NCBI taxa\n");

    my $Taxon_WS="ReferenceTaxons";
    my $taxon_provenance = [{"script"=>$0, "script_ver"=>"0.1", "description"=>"Taxon generated from NCBI taxonomy names and nodes files downloaded on 10/20/2016."}];

    my $Start_Id=0;
    my @Object_Ids = sort { $a <=> $b } keys %Objects_to_Ignore;
    my $End_Id = $Object_Ids[$#Object_Ids];

    my @Missing_Object_Ids=();
    foreach my $i ($Object_Ids[0]..$Object_Ids[$#Object_Ids]){
	if(!exists($Objects_to_Ignore{$i})){
	    push(@Missing_Object_Ids,$i);
	}
    }
    $Start_Id=$Missing_Object_Ids[0]-1;
    $End_Id=$Missing_Object_Ids[$#Missing_Object_Ids]+1;

    #These two lines assume you're updating the entire workspace
    #Comment these lines out if you're checking for missing taxons
    my $wsinfo = $ws_client->get_workspace_info({workspace => $Taxon_WS});
    $End_Id = $wsinfo->[4];

    my $batch_count = 5000;
    my $pages = ceil($End_Id/$batch_count);
    print "Paging through $pages of $batch_count objects\n";

    print "\nE: Workspace contains $End_Id taxon objects.\n";
    print "E: Paging through $pages of $batch_count objects from: $Start_Id\n";

    my %NCBI_Taxa_Hash = map { $_->{'taxonomy_id'} => $_ } @$ncbi_taxa;
    for (my $m = 0; $m <= $pages; $m++) {
        my ($start,$end) = ( $m * $batch_count , ( $batch_count * ($m+1) -1 ) );

        $end = $End_Id if $end > $End_Id;
	$start = $Start_Id if $start < $Start_Id;

	print "E: Fetching from $start - $end objects\n";
        next if $start > $end;
        my $listed_taxa = $impl->list_loaded_taxa({workspace_name=>$Taxon_WS,minid=>$start,maxid=>$end,batch=>$batch_count,ignore=>\%Objects_to_Ignore});
	print "E: Iterating through ".scalar(@$listed_taxa)." retrieved from workspace\n";

        my $checked_taxa={};
	my $taxa_to_load=[];
        my %taxa_to_load=();
	open(OUT, ">> ${data}/Unchanged_Taxa.txt");
	open(DEL, ">> ${data}/NCBI_Deleted_Taxa.txt");
        foreach my $ws_taxon (@$listed_taxa){
            $checked_taxa->{$ws_taxon->{'taxon'}{'taxonomy_id'}}=1;

            #If not in NCBI, means it was deleted, we can't check it, but we're keeping it
	    if(!exists($NCBI_Taxa_Hash{$ws_taxon->{'taxon'}{'taxonomy_id'}})){
		@temp=split(/\//,$ws_taxon->{'ws_ref'});
                print DEL $ws_taxon->{'taxon'}{'taxonomy_id'}."\t".$temp[1]."\n";	
		next;
	    }

            my $ncbi_taxon = $NCBI_Taxa_Hash{$ws_taxon->{'taxon'}{'taxonomy_id'}};
            my $result = $impl->_check_taxon($ncbi_taxon,$ws_taxon->{'taxon'});

            if(scalar(@$result)){
                $taxa_to_load{$ncbi_taxon->{'taxonomy_id'}}=join("|\t|",@$result);
                push(@$taxa_to_load,$ncbi_taxon);
            }else{
		@temp=split(/\//,$ws_taxon->{'ws_ref'});
                print OUT $ncbi_taxon->{'taxonomy_id'}."\t".$temp[1]."\n";	
	    }
            $checked_taxa->{$ws_taxon->{'taxon'}{'taxonomy_id'}}=1;
        }
	close(OUT);
	close(DEL);
        print"E: Checked ".scalar(keys %$checked_taxa)." taxa, will load updates for ".scalar(@$taxa_to_load)."\n\n";	

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

	open(OUT, ">> ${data}/Updated_Taxa.txt");
        foreach my $item (@$saved_objects){
            my $taxid = $item->[1];
            $taxid =~ s/_taxon//;
            print OUT $taxid."\t".$item->[0]."\t".$taxa_to_load{$taxid}."\n";
        }
	close(OUT);

        if(scalar(@$saved_objects)){
            try{
                $impl->index_taxa_in_solr({taxa=>$Taxa_To_Load_in_SOLR,solr_core=>$core,create_report=>0});
            }catch{
                print "Indexing error: $_\n";
            };
        }
        print("Updated ".scalar(@$saved_objects)." Current Taxa\n");
    }
};
print $@,"\n" if $@;
ok(!$@,"Finished checking taxa\n");

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
