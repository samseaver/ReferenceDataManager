use strict;
use Data::Dumper;
use Test::More;
use Config::Simple;
use Time::HiRes qw(time);
use Bio::KBase::AuthToken;
use Bio::KBase::workspace::Client;
use lib '/Users/seaver/Software/KBase_Repos/ReferenceDataManager/lib';
use ReferenceDataManager::ReferenceDataManagerImpl;

local $| = 1;
my $token = $ENV{'KB_AUTH_TOKEN'};
my $config_file = $ENV{'KB_DEPLOYMENT_CONFIG'};
my $config = new Config::Simple($config_file)->get_block('ReferenceDataManager');
my $ws_url = $config->{"workspace-url"};
my $ws_name = undef;
my $ws_client = new Bio::KBase::workspace::Client($ws_url,token => $token);
my $auth_token = Bio::KBase::AuthToken->new(token => $token, ignore_authrc => 1);
my $ctx = LocalCallContext->new($token, $auth_token->user_id);
$ReferenceDataManager::ReferenceDataManagerServer::CallContext = $ctx;
my $impl = new ReferenceDataManager::ReferenceDataManagerImpl();

eval {
    $impl->util_initialize_call({},$ctx);
    my $listed_taxons=[];
    my $ids_to_extract = {1=>1,2=>1,131567=>1,1224=>1,28211=>1,356=>1,335928=>1,6=>1};
    eval {
#        $listed_taxons = $impl->list_loaded_taxons({workspace_name=>"Taxon_Test"});
#        $listed_taxons = $impl->list_loaded_taxons({workspace_name=>"ReferenceTaxons"});
	my @refs = ();
	foreach my $id (keys %$ids_to_extract){
	    push(@refs,{ref=>"ReferenceTaxons/".$id."_taxon"});
	}

	my $results = $impl->util_ws_client()->get_objects2({objects=>\@refs,ignoreErrors=>1})->{data};
	foreach my $result (@$results){
	    push(@$listed_taxons,$result->{data}) if $result;
	}
    };
    print $@,"\n" if $@;
    ok(!$@,"Listed ".scalar(@$listed_taxons)." WS taxons");

    print Data::Dumper::Dumper($listed_taxons),"\n";

    my $ncbi_taxons=[];
    eval {
	$ncbi_taxons = $impl->_extract_ncbi_taxons($ids_to_extract);
    };
    print $@,"\n" if $@;
    ok(!$@,"Extracted ".scalar(@$ncbi_taxons)." NCBI taxons");

    my $taxons_to_load=[];
    eval {
	foreach my $obj (@$ncbi_taxons){
	    my $result = $impl->_check_taxon($obj,$listed_taxons);
	    if(scalar(@$result)){
		print "Re-loading Taxon ".$obj->{'taxonomy_id'}."\n";
		print "\t".join("\n\t",@$result)."\n";
		push(@$taxons_to_load,$obj);
	    }
	}
    };
    print $@,"\n" if $@;
    ok(!$@,"Will load ".scalar(@$taxons_to_load)." NCBI taxons");
};

eval {
    my $loaded_taxons = $impl->load_taxons({});
    print $@,"\n" if $@;
    ok(!$@,"Loaded ".scalar(@$loaded_taxons)."NCBI Taxons\n");
};

done_testing(4);

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
