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
print "Workspace URL: $ws_url\n";
my $ws_name = undef;
my $ws_client = new Bio::KBase::workspace::Client($ws_url,token => $token);
my $auth_token = Bio::KBase::AuthToken->new(token => $token, ignore_authrc => 1);
my $ctx = LocalCallContext->new($token, $auth_token->user_id);
$ReferenceDataManager::ReferenceDataManagerServer::CallContext = $ctx;
my $impl = new ReferenceDataManager::ReferenceDataManagerImpl();
my @temp=();

eval {
    $impl->util_initialize_call({},$ctx);

    my $Taxon_WS = "ReferenceTaxons";
    my $wsinfo = $ws_client->get_workspace_info({workspace => $Taxon_WS});
    my $minid = 0;
    my $maxid = $wsinfo->[4];

    my $batch_count = 10000;
    my $pages = ceil($maxid/$batch_count);

    print "\nE: Workspace contains $maxid taxon objects.\n";
    print "E: Paging through $pages of $batch_count objects from MinId: $minid\n";

    open(OUT, "> ${data}/Prod_Taxa/Listed_Taxa.txt");
    my $wsoutput=[];
    for (my $m = 0; $m < $pages; $m++) {
	print ("E: Batch ". $m . "x$batch_count on " . scalar(localtime)."\n");
    
	my ($minObjID,$maxObjID)=(( $batch_count * $m ) + 1,$batch_count * ( $m + 1));

	print "E: Fetching taxa with {minid=>$minObjID,maxid=>$maxObjID,batch=>$batch_count}\n";
	$wsoutput = [];
        my $try_count=5;
        while(scalar(@$wsoutput)==0 && $try_count != 0){
            $try_count--;
            try {
  		print "\nStart to list the objects at the batch size of: " . $batch_count . " on " . scalar localtime;
                $wsoutput = $ws_client->list_objects({workspaces => [$Taxon_WS],
                                                      type => "KBaseGenomeAnnotations.Taxon-1.0",
                                                      minObjectID => $minObjID,
                                                      maxObjectID => $maxObjID});
		print "\nDone getting the objects at the batch size of: " . $batch_count . " on " . scalar localtime . "\n\n";
            }catch{
                print "ERROR on iteration $try_count for Batch $batch_count: Cannot list objects: $_ at ".scalar(localtime)."\n";
            };
            sleep(3) if scalar(@$wsoutput)==0;
        }
	foreach my $entry (@$wsoutput){
	    my @temp=split(/_/,$entry->[1]); 
	    print OUT $temp[0]."\t".$entry->[0]."\n";
	}
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
