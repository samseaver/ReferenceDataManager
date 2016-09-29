package ReferenceDataManager::ReferenceDataManagerImpl;
use strict;
use Bio::KBase::Exceptions;
# Use Semantic Versioning (2.0.0-rc.1)
# http://semver.org 
our $VERSION = "0.1.0";

=head1 NAME

ReferenceDataManager

=head1 DESCRIPTION

A KBase module: ReferenceDataManager
This sample module contains one small method - filter_contigs.

=cut

#BEGIN_HEADER
use Bio::KBase::AuthToken;
use Bio::KBase::workspace::Client;
use GenomeFileUtil::GenomeFileUtilClient;
use Config::IniFiles;
use POSIX;
use FindBin qw($Bin);
use JSON;
use Data::Dumper qw(Dumper);
use LWP::UserAgent;
use XML::Simple;


#The first thing every function should do is call this function
sub util_initialize_call {
	my ($self,$params,$ctx) = @_;
	print("Starting ".$ctx->method()." method.\n");
	$self->{_token} = $ctx->token();
	$self->{_username} = $ctx->user_id();
	$self->{_method} = $ctx->method();
	$self->{_provenance} = $ctx->provenance();
	$self->{_wsclient} = new Bio::KBase::workspace::Client($self->{workspace_url},token => $ctx->token());
	$self->util_timestamp(DateTime->now()->datetime());
	return $params;
}

#This function returns the version of the current method
sub util_version {
	my ($self) = @_;
	return "1";
}

#This function returns the token of the user running the SDK method
sub util_token {
	my ($self) = @_;
	return $self->{_token};
}

#This function returns the username of the user running the SDK method
sub util_username {
	my ($self) = @_;
	return $self->{_username};
}

#This function returns the name of the SDK method being run
sub util_method {
	my ($self) = @_;
	return $self->{_method};
}

#This function returns a timestamp recored when the functionw was first started
sub util_timestamp {
	my ($self,$input) = @_;
	if (defined($input)) {
		$self->{_timestamp} = $input;
	}
	return $self->{_timestamp};
}

#Use this function to log messages to the SDK console
sub util_log {
	my($self,$message) = @_;
	print $message."\n";
}

#Use this function to get a client for the workspace service
sub util_ws_client {
	my ($self,$input) = @_;
	return $self->{_wsclient};
}

#This function validates the arguments to a method making sure mandatory arguments are present and optional arguments are set
sub util_args {
	my($self,$args,$mandatoryArguments,$optionalArguments,$substitutions) = @_;
	if (!defined($args)) {
	    $args = {};
	}
	if (ref($args) ne "HASH") {
		die "Arguments not hash";	
	}
	if (defined($substitutions) && ref($substitutions) eq "HASH") {
		foreach my $original (keys(%{$substitutions})) {
			$args->{$original} = $args->{$substitutions->{$original}};
		}
	}
	if (defined($mandatoryArguments)) {
		for (my $i=0; $i < @{$mandatoryArguments}; $i++) {
			if (!defined($args->{$mandatoryArguments->[$i]})) {
				push(@{$args->{_error}},$mandatoryArguments->[$i]);
			}
		}
	}
	if (defined($args->{_error})) {
		die "Mandatory arguments ".join("; ",@{$args->{_error}})." missing";
	}
	foreach my $argument (keys(%{$optionalArguments})) {
		if (!defined($args->{$argument})) {
			$args->{$argument} = $optionalArguments->{$argument};
		}
	}
	return $args;
}

#This function specifies the name of the workspace where genomes are loaded for the specified source database
sub util_workspace_names {
	my($self,$source) = @_;
    if (!defined($self->{_workspace_map}->{$source})) {
    	die "No workspace specified for source: ".$source;
    }
    return $self->{_workspace_map}->{$source};
}

sub util_create_report {
	my($self,$args) = @_;
	my $reportobj = {
		text_message => $args->{"message"},
		objects_created => []
	};
	if (defined($args->{objects})) {
		for (my $i=0; $i < @{$args->{objects}}; $i++) {
			push(@{$reportobj->{objects_created}},{
				'ref' => $args->{objects}->[$i]->[0],
				description => $args->{objects}->[$i]->[1]
			});
		}
	}
	$self->util_ws_client()->save_objects({
		workspace => $args->{workspace},
		objects => [{
			provenance => $self->{_provenance},
			type => "KBaseReport.Report",
			data => $reportobj,
			hidden => 1,
			name => $self->util_method()
		}]
	});
}
#################### methods for accessing SOLR #######################
#
# Internal Method used for sending HTTP
# url : Requested url
# method : HTTP method
# dataType : Type of data posting (binary or text)
# headers : headers as key => value pair
# data : if binary it will as sequence of character
#          if text it will be key => value pair
sub _request
{
    my ($self, $url, $method, $dataType, $headers, $data) = @_;

    # Intialize the request params if not specified
    $dataType = ($dataType) ? $dataType : 'text';
    $method = ($method) ? $method : 'POST';
    $url = ($url) ? $url : $self->{_SOLR_URL};
    $headers = ($headers) ?  $headers : {};
    $data = ($data) ? $data: '';
	
    my $out = {};

    # create a HTTP request
    my $ua = LWP::UserAgent->new;
    my $request = HTTP::Request->new;
    $request->method($method);
    $request->uri($url);

    # set headers
    foreach my $header (keys %$headers) {
        $request->header($header =>  $headers->{$header});
    }

    # set data for posting
    $request->content($data);

    # Send request and receive the response
    my $response = $ua->request($request);
    $out->{responsecode} = $response->code();
    $out->{response} = $response->content;
    $out->{url} = $url;
    return $out;
}

#
# Internal Method: to parse solr server response
#
sub _parseResponse
{
    my ($self, $response, $responseType) = @_;

    # Clear the error fields
    $self->{is_error} = 0;
    $self->{error} = undef;

    $responseType = "xml" unless $responseType;

    # Check for successfull request/response
    if ($response->{responsecode} eq "200") {
           if ($responseType eq "json") {
                my $resRef = JSON::from_json($response->{response});
                if ($resRef->{responseHeader}->{status} eq 0) {
                        return 1;
                }
            } else {
                my $xs = new XML::Simple();
                my $xmlRef;
                eval {
                        $xmlRef = $xs->XMLin($response->{response});
                };
                if ($xmlRef->{lst}->{'int'}->{status}->{content} eq 0){
                        return 1;
                }
            }
    }
    $self->{is_error} = 1;
    $self->{error} = $response;
    $self->{error}->{errmsg} = $@;
    return 0;
}
#
#Internal Method: to list the genomes already in SOLR and return an array of those genomes
#
sub _list_genomes_in_solr {
	my ($self) = @_;
	my $count = 10;
	my $start = 0;
	my $rows = "&rows=100";
  	my $sort = "&sort=genome_id asc";
	my $grp = "";#"genome_id";
	my $params = {
		fl => "genome_id",
		wt => "json",
		rows => $count,
		sort => "genome_id asc",
		hl => "false",
		start => $start,
		count => $count
	};
	my $query = { q => "*" };
	my $core = "QZtest";
	return $self->_search_solr($core, $params, $query, "json", $grp);
}
#
# method name: _search_solr
# Internal Method: to execute a search in SOLR according to the passed parameters
# parameters:
# $searchParams is a hash, see the example below:
# $searchParams {
#   fl => 'object_id,gene_name,genome_source',
#   wt => 'json',
#   rows => $count,
#   sort => 'object_id asc',
#   hl => 'false',
#   start => $start,
#   count => $count
#}
#
sub _search_solr {
	my ($self, $searchCore, $searchParams, $searchQuery, $resultFormat, $groupOption, $skipEscape) = @_;
	$skipEscape = {} unless $skipEscape;
	
	# If output format is not passed set it to XML
    $resultFormat = "xml" unless $resultFormat;
    my $DEFAULT_FIELD_CONNECTOR = "AND";
	
	my $url = "$self->{_SOLR_SEARCH_URL}";
	
	# Build the queryFields string with $searchQuery and $searchParams
	my $queryFields = "";
    if (! $searchQuery) {
        $self->{is_error} = 1;
        $self->{errmsg} = "Query parameters not specified";
        return undef;
    }
	foreach my $key (keys %$searchParams) {
        $queryFields .= "$key=". URI::Escape::uri_escape($searchParams->{$key}) . "&";
    }
	
	# Add solr query to queryString
    my $qStr = "q=";
    if (defined $searchQuery->{q}) {
        $qStr .= URI::Escape::uri_escape($searchQuery->{q});
        #print "Query string passed with q: " . $qStr . "\n";
    } else {
    	foreach my $key (keys %$searchQuery) {
        	if (defined $skipEscape->{$key}) {
            	$qStr .= "+$key:" . $searchQuery->{$key} ." $DEFAULT_FIELD_CONNECTOR ";
            } else {
            	$qStr .= "+$key:" . URI::Escape::uri_escape($searchQuery->{$key}) .
                        " $DEFAULT_FIELD_CONNECTOR ";
            }
        }
        # Remove last occurance of ' AND '
        $qStr =~ s/ AND $//g;
        #print "Query string passed without q: " . $qStr . "\n";
    }
    $queryFields .= "$qStr";
    #print "The query string is: \n" . "&$queryFields \n";
	
	my $solrCore = "/$searchCore"; 
  	my $sort = "&sort=genome_id asc";
	my $solrGroup = $groupOption ? "&group=true&group.field=$groupOption" : "";
	my $solrQuery = $self->{_SOLR_URL}.$solrCore."/select?".$queryFields.$solrGroup;
	print "Query string:\n$solrQuery\n";
	
	my $solr_response = $self->_request("$solrQuery", "GET");
	#print "\nRaw response: \n" . $solr_response->{response} . "\n";
	
	my $responseCode = $self->_parseResponse($solr_response, $resultFormat);
    	if ($responseCode) {
        	if ($resultFormat eq "json") {
            	my $out = JSON::from_json($solr_response->{response});
                $solr_response->{response}= $out;
        	}
	}
	if($groupOption){
		my @solr_genome_records = @{$solr_response->{response}->{grouped}->{genome_id}->{groups}};
		print "\n\nFound unique genome_id groups of:" . scalar @solr_genome_records . "\n";
		print @solr_genome_records[0]->{doclist}->{numFound} ."\n";
	}
	return $solr_response;
}
sub _testInsert2solr
{
	my ($self) = @_;
	my $ds = [ {
        object_id => "kb|ws.2869.obj.72243",
        workspace_name => "KBasePublicRichGenomesV5",
        genome_id => "kb|g.239993",
        genome_source_id => "1331250.3"
	} ];

	if (!$self->_insert2solr($ds)) {
   		print "\n Error: " . $self->_error->{response};
   		exit 1;
	}
	else
	{
        print "Added a new doc for indexing:\n" . Dumper($ds) . "\n";
		if (!$self->_commit()) {
    		print "\n Error: " . $self->_error->{response};
    		exit 1;
		}
	}	
}
#
# method name: _insert2solr
# Internal method: to add documents to solr for indexing.
# It sends a xml http request.  First it will convert the raw datastructure to required ds then it will convert 
# this ds to xml. This xml will be posted to Apache solr for indexing.
# Depending on the flag AUTOCOMMIT the documents will be indexed immediatly or on commit is issued.
# parameters:
#     $arams: This parameter specifies set of list of document fileds and values.
# return
#    1 for successful posting of the xml document
#    0 for any failure
#
# Check error method for for getting the error details for last command
#
sub _insert2solr
{
    my ($self, $params) = @_;
    #my $ds = $self->_rawDsToSolrDs($params);
    my $doc = $self->_toXML($params, 'add');
    my $commit = $self->{_AUTOCOMMIT} ? 'true' : 'false';
    my $url = "$self->{_SOLR_POST_URL}?commit=" . $commit;
    my $response = $self->_request($url, 'POST', undef, $self->{_CT_XML}, $doc);

    return 1 if ($self->_parseResponse($response));
    return 0;
}

#
# Internal Method
# This function will convert the datastructe to XML document
#
sub _toXML
{
    my ($self, $params, $rootnode) = @_;
    my $xs = new XML::Simple();
    my $xml;
    if (! $rootnode) {
    $xml = $xs->XMLout($params);
    } else {
    $xml = $xs->XMLout($params, rootname => $rootnode);
    }
	print "\n$xml\n";
    return $xml;
}

#
# method name: _rawDs2SolrDs
#
# Convert raw DS to sorl requird DS.
# Input format :
#    [
#    {
#        attr1 => [ value1, value2],
#        attr2 => [valu3, value4]
#    },
#    ...
#    ]
# Output format:
#    [
#    { field => [ { name => attr1, content => value1 },
#             { name => attr1, content => value2 },
#             { name => attr2, content => value3 },
#             { name => attr2, content => value4 }
#            ],
#    },
#    ...
#    ]
sub _rawDsToSolrDs
{
    my ($self, $docs) = @_;
	print "\nInput data:\n". Dumper($docs);
    my $ds = [];
    for my $doc (@$docs) {
    my $d = [];
    for my $field (keys %$doc) {
        my $values = $doc->{$field};
		print "$field => " . Dumper($values);
        if (scalar @$values ){
        for my $val (@$values) {
            push @$d, {name => $field, content => $val};
        }
        } else {
        push @$d, { name => $field, content => $values};
        }
    }
    push @$ds, {field => $d};
    }
    $ds = { doc => $ds };
    print "\noutput data:\n" .Dumper($ds);
    return $ds;
}
#
# method name: _error
#     returns the errors details that was occured during last transaction action.
# params : -
# returns : response details includes the following details
#    {
#          url => 'url which is being accessed',
#       response => 'response from server',
#       code => 'response code',
#       errmsg => 'for any internal error error msg'
#     }
#
#
sub _error
{
    my ($self) = @_;
    return $self->{error};
}

#
# method name: _autocommit
#    This method is used for setting the autocommit on or off.
# params:
#     flag: 1 or 0, 1 for setting autocommit on and 0 for off.
# return
#    always returns true
#
sub _autocommit
{
    my ($self, $flag) = @_;
    $self->{_AUTOCOMMIT} = $flag | 1;
    return 1;
}

#
# method name: _commit
#    This method is used for commiting the transaction that was initiated.
#     Request XML format:
#         true
# params : -
# returns :
#    1 for success
#    0 for any failure
#
# Check error method for for getting the error details for last command
#
sub _commit
{
    my ($self) = @_;
    my $url = $self->{_SOLR_POST_URL};
    my $cmd = $self->_toXML('true', 'commit');
    my $response = $self->_request($url, 'POST', undef, $self->{_CT_XML}, $cmd);

    return 1 if ($self->_parseResponse($response));
    return 0;
}

#
# method name: _rollback
#    This method is used for issuing rollback on transaction that
# was initiated. Request XML format:
#     <rollback>
# params : -
# returns :
#    1 for success
#    0 for any failure
#
# Check error method for for getting the error details for last command
#
sub _rollback
{
    my ($self) = @_;
    my $url = $self->{_SOLR_POST_URL};
    my $cmd = $self->_toXML('', 'rollback');
    my $response = $self->_request($url, 'POST', undef, $self->{_CT_XML}, $cmd);

    return 1 if ($self->_parseResponse($response));
    return 0;
}

#
# method name: _exists
#    This method is used for checking if the document with ID specified
# exists in solr index database or not.
# params :
#    id: document id for searching in solr dabase for existance
# returns :
#    1 for success
#    0 for any failure
#
# Check error method for for getting the error details for last command
#
sub _exists
{
    my ($self, $id) = @_;
    my $url = "$self->{_SOLR_SEARCH_URL}?q=id:$id";
    my $response = $self->_request($url, 'GET');
    my $status = ($self->_parseResponse($response));
    if ($status) {
    my $xs = new XML::Simple();
    my $xmlRef;
    eval {
        $xmlRef = $xs->XMLin($response->{response});
    };
    if ($xmlRef->{lst}->{'int'}->{status}->{content} eq 0){
        if ($xmlRef->{result}->{numFound} gt 0) {
        return 1;
        }
    }
    }
    return 0;
}

# method name: _ping
#    This methods is check Apache solr server is reachable or not
# params : -
# returns :
#     1 for success
#     0 for failure
# Check error method for for getting the error details for last command
#
sub _ping
{
    #print "In ping server at " . $self->{_SOLR_PING_URL} . "\n";
    my ($self, $errors) = @_;
    my $response = $self->_request($self->{_SOLR_PING_URL}, 'GET');
print("Ping's response: " . $response);
    return 1 if ($self->_parseResponse($response));
    return 0;
}

sub _clear_error
{
    my ($self) = @_;
    $self->{is_error} = 0;
    $self->{error} = undef;
}



#
# Internal Method: to check if a given genome by name is present in SOLR.  Returns a string stating the status
#
sub _checkGenomeStatus {
	my ($current_genome, $solr_genomes) = @_;
	
	print "\tChecking status for assembly $current_genome->{accession}: ";
	my $status;
	if ( @{ $solr_genomes } == 0 ){
		$status = "New genome";
	}else{
		for (my $i = 0; $i < @{ $solr_genomes }; $i++ ) {
 		    my $record = $solr_genomes->[$i];
		    my $genome_id = $record->{genome_id};

		    if ($genome_id eq $current_genome->{accession}){
			$status = "Existing genome: current";
			$current_genome->{genome_id} = $genome_id;
		    }elsif ($genome_id =~/$current_genome->{id}/){
			$status = "Existing genome: updated ";
			$current_genome->{genome_id} = $genome_id;
		    }else{
			$status = "Existing genome: status unknown";
			$current_genome->{genome_id} = $genome_id;
		    }
		}
	}  

	print "$status\n";

	return $status;
}

#################### End methods for accessing SOLR #######################

#END_HEADER

sub new
{
    my($class, @args) = @_;
    my $self = {
    };
    bless $self, $class;
    #BEGIN_CONSTRUCTOR
    
    my $config_file = $ENV{ KB_DEPLOYMENT_CONFIG };
    my $cfg = Config::IniFiles->new(-file=>$config_file);
    $self->{workspace_url} = $cfg->val('ReferenceDataManager','workspace-url');
    $self->{scratch} = $cfg->val('ReferenceDataManager','scratch');
    die "no workspace-url defined" unless $self->{workspace_url};
    $self->{_workspace_map} = {
    	ensembl => "Ensembl_Genomes",
    	phytozome => "Phytozome_Genomes",
    	refseq => "RefSeq_Genomes"
    };
    if (! $self->{_SOLR_URL}) {
        $self->{_SOLR_URL} = "http://kbase.us/internal/solr-ci/search";
    }
    $self->{_SOLR_POST_URL} = "$self->{_SOLR_URL}/update";
    $self->{_AUTOCOMMIT} = 0;
    $self->{_CT_XML} = { Content_Type => 'text/xml; charset=utf-8' };
    $self->{_CT_JSON} = { Content_Type => 'text/json'};
    
    #END_CONSTRUCTOR

    if ($self->can('_init_instance'))
    {
	$self->_init_instance();
    }
    return $self;
}

=head1 METHODS



=head2 list_reference_genomes

  $output = $obj->list_reference_genomes($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a ReferenceDataManager.ListReferenceGenomesParams
$output is a reference to a list where each element is a ReferenceDataManager.ReferenceGenomeData
ListReferenceGenomesParams is a reference to a hash where the following keys are defined:
	ensembl has a value which is a ReferenceDataManager.bool
	refseq has a value which is a ReferenceDataManager.bool
	phytozome has a value which is a ReferenceDataManager.bool
	updated_only has a value which is a ReferenceDataManager.bool
	workspace_name has a value which is a string
	create_report has a value which is a ReferenceDataManager.bool
bool is an int
ReferenceGenomeData is a reference to a hash where the following keys are defined:
	accession has a value which is a string
	status has a value which is a string
	name has a value which is a string
	ftp_dir has a value which is a string
	file has a value which is a string
	id has a value which is a string
	version has a value which is a string
	source has a value which is a string
	domain has a value which is a string

</pre>

=end html

=begin text

$params is a ReferenceDataManager.ListReferenceGenomesParams
$output is a reference to a list where each element is a ReferenceDataManager.ReferenceGenomeData
ListReferenceGenomesParams is a reference to a hash where the following keys are defined:
	ensembl has a value which is a ReferenceDataManager.bool
	refseq has a value which is a ReferenceDataManager.bool
	phytozome has a value which is a ReferenceDataManager.bool
	updated_only has a value which is a ReferenceDataManager.bool
	workspace_name has a value which is a string
	create_report has a value which is a ReferenceDataManager.bool
bool is an int
ReferenceGenomeData is a reference to a hash where the following keys are defined:
	accession has a value which is a string
	status has a value which is a string
	name has a value which is a string
	ftp_dir has a value which is a string
	file has a value which is a string
	id has a value which is a string
	version has a value which is a string
	source has a value which is a string
	domain has a value which is a string


=end text



=item Description

Lists genomes present in selected reference databases (ensembl, phytozome, refseq)

=back

=cut

sub list_reference_genomes
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to list_reference_genomes:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'list_reference_genomes');
    }

    my $ctx = $ReferenceDataManager::ReferenceDataManagerServer::CallContext;
    my($output);
    #BEGIN list_reference_genomes
    #$params = $self->util_initialize_call($params,$ctx);
    $params = $self->util_args($params,[],{
    	ensembl => 0,#todo
    	phytozome => 0,#todo
    	refseq => 0,
    	create_report => 0,
    	update_only => 1,#todo
    	workspace_name => undef
    });
    my $msg = "";
    $output = [];
    if ($params->{refseq} == 1) {
    	my $source = "refseq";#Could also be "genbank"
    	my $division = "bacteria";#Could also be "archaea" or "plant"
    	my $assembly_summary_url = "ftp://ftp.ncbi.nlm.nih.gov/genomes/".$source."/".$division."/assembly_summary.txt";
    	my $assemblies = [`wget -q -O - $assembly_summary_url`];
		my $count = 0;
		foreach my $entry (@{$assemblies}) {
			$count++;
			chomp $entry;
			if ($entry=~/^#/) { #header
				next;
			}
			my @attribs = split /\t/, $entry;
			my $current_genome = {
				source => $source,
				domain => $division
			};
			$current_genome->{accession} = $attribs[0];
			$current_genome->{status} = $attribs[10];
			$current_genome->{name} = $attribs[15];
			$current_genome->{ftp_dir} = $attribs[19];
			$current_genome->{file} = $current_genome->{ftp_dir};
			$current_genome->{file}=~s/.*\///;
			($current_genome->{id}, $current_genome->{version}) = $current_genome->{accession}=~/(.*)\.(\d+)$/;
			#$current_genome->{dir} = $current_genome->{accession}."_".$current_genome->{name};#May not need this
			push(@{$output},$current_genome);
			if ($count < 10) {
				$msg .= $current_genome->{accession}.";".$current_genome->{status}.";".$current_genome->{name}.";".$current_genome->{ftp_dir}.";".$current_genome->{file}.";".$current_genome->{id}.";".$current_genome->{version}.";".$current_genome->{source}.";".$current_genome->{domain}."\n";
			}
		}
    } elsif ($params->{phytozome} == 1) {
    	my $source = "phytozome";
    	my $division = "plant";
    	#NEED SAM TO FILL THIS IN
    } elsif ($params->{ensembl} == 1) {
    	my $source = "ensembl";
    	my $division = "fungal";
    	#TODO
    }
    if ($params->{create_report}) {
    	print $msg."\n";
    	$self->util_create_report({
    		message => $msg,
    		workspace => $params->{workspace}
    	});
    	$output = [$params->{workspace}."/list_reference_genomes"];
    }
    #END list_reference_genomes
    my @_bad_returns;
    (ref($output) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to list_reference_genomes:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'list_reference_genomes');
    }
    return($output);
}




=head2 list_loaded_genomes

  $output = $obj->list_loaded_genomes($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a ReferenceDataManager.ListLoadedGenomesParams
$output is a reference to a list where each element is a ReferenceDataManager.KBaseReferenceGenomeData
ListLoadedGenomesParams is a reference to a hash where the following keys are defined:
	ensembl has a value which is a ReferenceDataManager.bool
	refseq has a value which is a ReferenceDataManager.bool
	phytozome has a value which is a ReferenceDataManager.bool
	workspace_name has a value which is a string
	create_report has a value which is a ReferenceDataManager.bool
bool is an int
KBaseReferenceGenomeData is a reference to a hash where the following keys are defined:
	ref has a value which is a string
	id has a value which is a string
	workspace_name has a value which is a string
	source_id has a value which is a string
	accession has a value which is a string
	name has a value which is a string
	ftp_dir has a value which is a string
	version has a value which is a string
	source has a value which is a string
	domain has a value which is a string

</pre>

=end html

=begin text

$params is a ReferenceDataManager.ListLoadedGenomesParams
$output is a reference to a list where each element is a ReferenceDataManager.KBaseReferenceGenomeData
ListLoadedGenomesParams is a reference to a hash where the following keys are defined:
	ensembl has a value which is a ReferenceDataManager.bool
	refseq has a value which is a ReferenceDataManager.bool
	phytozome has a value which is a ReferenceDataManager.bool
	workspace_name has a value which is a string
	create_report has a value which is a ReferenceDataManager.bool
bool is an int
KBaseReferenceGenomeData is a reference to a hash where the following keys are defined:
	ref has a value which is a string
	id has a value which is a string
	workspace_name has a value which is a string
	source_id has a value which is a string
	accession has a value which is a string
	name has a value which is a string
	ftp_dir has a value which is a string
	version has a value which is a string
	source has a value which is a string
	domain has a value which is a string


=end text



=item Description

Lists genomes loaded into KBase from selected reference sources (ensembl, phytozome, refseq)

=back

=cut

sub list_loaded_genomes
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to list_loaded_genomes:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'list_loaded_genomes');
    }

    my $ctx = $ReferenceDataManager::ReferenceDataManagerServer::CallContext;
    my($output);
    #BEGIN list_loaded_genomes
    #$params = $self->util_initialize_call($params,$ctx);
    $params = $self->util_args($params,[],{
    	ensembl => 0,
    	phytozome => 0,
    	refseq => 0,
    	create_report => 0,
    	workspace_name => undef
    });
    my $msg = "";
    my $output = [];
    my $sources = ["ensembl","phytozome","refseq"];
    for (my $i=0; $i < @{$sources}; $i++) {
    	if ($params->{$sources->[$i]} == 1) {
    		my $wsname = $self->util_workspace_names($sources->[$i]);
    		my $wsoutput;
    		if(defined($self->util_ws_client())){
    			$wsoutput = $self->util_ws_client()->get_workspace_info({
    				workspace => $wsname
    			});
    		}
    		my $maxid = $wsoutput->[4];
    		my $pages = ceil($maxid/10000);
    		for (my $m=0; $m < $pages; $m++) {
    			$wsoutput = $self->util_ws_client()->list_objects({
	    			workspaces => [$wsname],
	    			type => "KBaseGenomes.Genome",
	    			minObjectID => 10000*$m,
	    			maxObjectID => 10000*($m+1)
	    		});
	    		for (my $j=0; $j < @{$wsoutput}; $j++) {
	    			push(@{$output},{
	    				"ref" => $wsoutput->[$j]->[6]."/".$wsoutput->[$j]->[0]."/".$wsoutput->[$j]->[4],
				        id => $wsoutput->[$j]->[1],
						workspace_name => $wsoutput->[$j]->[7],
						source_id => $wsoutput->[$j]->[10]->{"Source ID"},
						accession => $wsoutput->[$j]->[10]->{"Source ID"},
						name => $wsoutput->[$j]->[10]->{Name},
						version => $wsoutput->[$j]->[4],
						source => $wsoutput->[$j]->[10]->{Source},
						domain => $wsoutput->[$j]->[10]->{Domain},
						save_date => $wsoutput->[$j]->[3],
						contigs => $wsoutput->[$j]->[10]->{"Number contigs"},
						features => $wsoutput->[$j]->[10]->{"Number features"},
						dna_size => $wsoutput->[$j]->[10]->{"Size"},
						gc => $wsoutput->[$j]->[10]->{"GC content"},
	    			});
	    			if (@{$output} < 10) {
	    				my $curr = @{$output}-1;
	    				$msg .= Data::Dumper->Dump([$output->[$curr]])."\n";
	    			}
	    		}
    		}
    	}
    }
    if ($params->{create_report}) {
    	print $msg."\n";
    	$self->util_create_report({
    		message => $msg,
    		workspace => $params->{workspace}
    	});
    	$output = [$params->{workspace}."/list_loaded_genomes"];
    }
    #END list_loaded_genomes
    my @_bad_returns;
    (ref($output) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to list_loaded_genomes:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'list_loaded_genomes');
    }
    return($output);
}




=head2 load_genomes

  $output = $obj->load_genomes($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a ReferenceDataManager.LoadGenomesParams
$output is a reference to a list where each element is a ReferenceDataManager.KBaseReferenceGenomeData
LoadGenomesParams is a reference to a hash where the following keys are defined:
	data has a value which is a string
	genomes has a value which is a reference to a list where each element is a ReferenceDataManager.ReferenceGenomeData
	index_in_solr has a value which is a ReferenceDataManager.bool
	workspace_name has a value which is a string
	create_report has a value which is a ReferenceDataManager.bool
ReferenceGenomeData is a reference to a hash where the following keys are defined:
	accession has a value which is a string
	status has a value which is a string
	name has a value which is a string
	ftp_dir has a value which is a string
	file has a value which is a string
	id has a value which is a string
	version has a value which is a string
	source has a value which is a string
	domain has a value which is a string
bool is an int
KBaseReferenceGenomeData is a reference to a hash where the following keys are defined:
	ref has a value which is a string
	id has a value which is a string
	workspace_name has a value which is a string
	source_id has a value which is a string
	accession has a value which is a string
	name has a value which is a string
	ftp_dir has a value which is a string
	version has a value which is a string
	source has a value which is a string
	domain has a value which is a string

</pre>

=end html

=begin text

$params is a ReferenceDataManager.LoadGenomesParams
$output is a reference to a list where each element is a ReferenceDataManager.KBaseReferenceGenomeData
LoadGenomesParams is a reference to a hash where the following keys are defined:
	data has a value which is a string
	genomes has a value which is a reference to a list where each element is a ReferenceDataManager.ReferenceGenomeData
	index_in_solr has a value which is a ReferenceDataManager.bool
	workspace_name has a value which is a string
	create_report has a value which is a ReferenceDataManager.bool
ReferenceGenomeData is a reference to a hash where the following keys are defined:
	accession has a value which is a string
	status has a value which is a string
	name has a value which is a string
	ftp_dir has a value which is a string
	file has a value which is a string
	id has a value which is a string
	version has a value which is a string
	source has a value which is a string
	domain has a value which is a string
bool is an int
KBaseReferenceGenomeData is a reference to a hash where the following keys are defined:
	ref has a value which is a string
	id has a value which is a string
	workspace_name has a value which is a string
	source_id has a value which is a string
	accession has a value which is a string
	name has a value which is a string
	ftp_dir has a value which is a string
	version has a value which is a string
	source has a value which is a string
	domain has a value which is a string


=end text



=item Description

Loads specified genomes into KBase workspace and indexes in SOLR on demand

=back

=cut

sub load_genomes
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to load_genomes:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'load_genomes');
    }

    my $ctx = $ReferenceDataManager::ReferenceDataManagerServer::CallContext;
    my($output);
    #BEGIN load_genomes
    #$params = $self->util_initialize_call($params,$ctx);
    $params = $self->util_args($params,[],{
    	data => undef,
    	genomes => [],
        index_in_solr => 0,
        create_report => 0,
    	workspace_name => undef
    });
    my $loader = new GenomeFileUtil::GenomeFileUtilClient($ENV{ SDK_CALLBACK_URL });
    my $genomes;
    $output = [];
    if (defined($params->{data})) {
	my $array = [split(/;/,$params->{data})];
	$genomes = [{
		accession => $array->[0],
	        status => $array->[1],
	        name => $array->[2],
	        ftp_dir => $array->[3],
	        file => $array->[4],
	        id => $array->[5],
	        version => $array->[6],
	        source => $array->[7],
	        domain => $array->[8]
		}];
   } else {
	$genomes = $params->{genomes};
   }
   for (my $i=0; $i < @{$genomes}; $i++) {
	my $genome = $genomes->[$i];
	print "Now loading ".$genome->{source}.":".$genome->{id}." with loader url=".$ENV{ SDK_CALLBACK_URL }."\n";
	my $wsname = $self->util_workspace_names($genome->{source});
	if ($genome->{source} eq "refseq" || $genome->{source} eq "ensembl") {
		my $genutilout = $loader->genbank_to_genome({
			file => {
				ftp_url => $genome->{ftp_dir}."/".$genome->{file}."_genomic.gbff.gz"
			},
			genome_name => $genome->{id},
			workspace_name => $wsname,
			source => $genome->{source},
			taxon_wsname => "ReferenceTaxons",
			release => $genome->{version},
			generate_ids_if_needed => 1,
			genetic_code => 11,
			type => "Reference",
			metadata => {
				refid => $genome->{id},
				accession => $genome->{accession},
				refname => $genome->{name},
				url => $genome->{url},
				version => $genome->{version}
			}
		});
		my $genomeout = {
			"ref" => $genutilout->{genome_ref},
			id => $genome->{id},
			workspace_name => $wsname,
			source_id => $genome->{id},
		        accession => $genome->{accession},
			name => $genome->{name},
    			ftp_dir => $genome->{ftp_dir},
    			version => $genome->{version},
			source => $genome->{source},
			domain => $genome->{domain}
		};
		push(@{$output},$genomeout);
			
		if ($params->{index_in_solr} == 1) {
			$self->func_index_in_solr({
				genomes => [$genomeout]
			});
		}
	} elsif ($genome->{source} eq "phytozome") {
		#NEED SAM TO PUT CODE FOR HIS LOADER HERE
		my $genomeout = {
			"ref" => $wsname."/".$genome->{id},
			id => $genome->{id},
			workspace_name => $wsname,
			source_id => $genome->{id},
		        accession => $genome->{accession},
			name => $genome->{name},
    			ftp_dir => $genome->{ftp_dir},
    			version => $genome->{version},
			source => $genome->{source},
			domain => $genome->{domain}
		};
		push(@{$output},$genomeout);
	}
   }
   if ($params->{create_report}) {
      print "Loaded ".@{$output}." genomes!"."\n";
      $self->util_create_report({
    	message => "Loaded ".@{$output}." genomes!",
    	workspace => $params->{workspace}
      });
      $output = [$params->{workspace}."/load_genomes"];
   }
    #END load_genomes
    my @_bad_returns;
    (ref($output) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to load_genomes:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'load_genomes');
    }
    return($output);
}




=head2 index_genomes_in_solr

  $output = $obj->index_genomes_in_solr($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a ReferenceDataManager.IndexGenomesInSolrParams
$output is a reference to a list where each element is a ReferenceDataManager.KBaseReferenceGenomeData
IndexGenomesInSolrParams is a reference to a hash where the following keys are defined:
	genomes has a value which is a reference to a list where each element is a ReferenceDataManager.KBaseReferenceGenomeData
	workspace_name has a value which is a string
	creat_report has a value which is a ReferenceDataManager.bool
KBaseReferenceGenomeData is a reference to a hash where the following keys are defined:
	ref has a value which is a string
	id has a value which is a string
	workspace_name has a value which is a string
	source_id has a value which is a string
	accession has a value which is a string
	name has a value which is a string
	ftp_dir has a value which is a string
	version has a value which is a string
	source has a value which is a string
	domain has a value which is a string
bool is an int

</pre>

=end html

=begin text

$params is a ReferenceDataManager.IndexGenomesInSolrParams
$output is a reference to a list where each element is a ReferenceDataManager.KBaseReferenceGenomeData
IndexGenomesInSolrParams is a reference to a hash where the following keys are defined:
	genomes has a value which is a reference to a list where each element is a ReferenceDataManager.KBaseReferenceGenomeData
	workspace_name has a value which is a string
	creat_report has a value which is a ReferenceDataManager.bool
KBaseReferenceGenomeData is a reference to a hash where the following keys are defined:
	ref has a value which is a string
	id has a value which is a string
	workspace_name has a value which is a string
	source_id has a value which is a string
	accession has a value which is a string
	name has a value which is a string
	ftp_dir has a value which is a string
	version has a value which is a string
	source has a value which is a string
	domain has a value which is a string
bool is an int


=end text



=item Description

Index specified genomes in SOLR from KBase workspace

=back

=cut

sub index_genomes_in_solr
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to index_genomes_in_solr:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'index_genomes_in_solr');
    }

    my $ctx = $ReferenceDataManager::ReferenceDataManagerServer::CallContext;
    my($output);
    #BEGIN index_genomes_in_solr
    #$params = $self->util_initialize_call($params,$ctx);
    $params = $self->util_args($params,[],{
    	genomes => [],
        create_report => 0,
    	workspace_name => undef
    });
    my $json = JSON->new->allow_nonref;
    my @solr_records;
    $output = [];

    foreach my $kbase_genome_data (@$params)
    {
	my $record;
	my $ws_name = $kbase_genome_data->{workspace_name};
	my $ws_genome_name = $kbase_genome_data->{name}; 
	my $genome_source = $kbase_genome_data->{source};
	my $ws_genome_metadata  = `ws-get -w $ws_name $ws_genome_name -m`;
	my @genome_metadata = split(/\n/, $ws_genome_metadata);

	foreach my $metadata (@genome_metadata){
	  my ($ws_genome_id) = $metadata=~/Object ID:(\d+)/ if $metadata=~/Object ID:(\d+)/;
	}

	$record->{workspace_name} = $ws_name; # KBasePublicRichGenomesV5
	$record->{object_id} = $ws_genome_name; #"kb|ws.".$ws_id.".obj."."$ws_genome_id"; # kb|ws.2869.obj.9837
	$record->{object_name} = $ws_genome_name; # kb|g.3397
	$record->{object_type} = "KBaseGenomes.Genome-8.0"; # KBaseSearch.Genome-5.0 / KBaseGenomes.Genome-8.0

	# Get genome info
	my $ws_genome  = $json->decode(`ws-get -w $ws_name $ws_genome_name`);
	$record->{genome_id} = $ws_genome_name; #$ws_genome->{id}; # kb|g.3397
	$record->{genome_source} = $genome_source; # $ws_genome->{external_source}; # KBase Central Store
	$record->{genome_source_id} = $ws_genome->{external_source_id}; # 83332.12
	$record->{num_cds} = $ws_genome->{counts_map}->{CDS};

	# Get assembly info
	my $ws_assembly = $json->decode(`ws-get $ws_genome->{assembly_ref}`);
	$record->{genome_dna_size} = $ws_assembly->{dna_size};
	$record->{num_contigs} = $ws_assembly->{num_contigs};
	$record->{complete} = ""; #$ws_genome->{complete}; # type?? 
	$record->{gc_content} = $ws_genome->{gc_content};

	# Get taxon info
	my $ws_taxon = $json->decode(`ws-get $ws_genome->{taxon_ref}`);
	$record->{scientific_name} = $ws_taxon->{scientific_name};
	$record->{taxonomy} = $ws_taxon->{scientific_lineage};
	$record->{taxonomy} =~s/ *; */;/g;
	#$record->{tax_id} = $ws_taxon->{taxonomy_id};
	$record->{domain} = $ws_taxon->{domain};

	#$genome->{genome_publications}=$ws_genome->{};
	#$genome->{has_publications}=$ws_genome->{};

	push (@{solr_records}, $record);

	#print Dumper(\@{solr_records});

	# Prepare feature records for solr

	foreach my $feature_type (keys %{$ws_genome->{feature_container_references}})
	{
 	    my $container_ref = $ws_genome->{feature_container_references}->{$feature_type};
 	    my $ws_features = $json->decode(`ws-get $container_ref`);

 	    #print Dumper ($ws_features);

 	    foreach my $key (keys %{$ws_features->{features}})
	    {
		my $feature = $ws_features->{features}->{$key};
		my $record;

		$record->{workspace_name} = $ws_name; # KBasePublicRichGenomesV5
		$record->{object_id} = $feature->{feature_id}; # kb|ws.2869.obj.9836/features/kb|g.3397.peg.3821
		$record->{object_name} = $feature->{feature_id}; # kb|g.3397.featureset/features/kb|g.3397.peg.3821
		$record->{object_type} = "KBaseSearch.Feature"; # KBaseSearch.Feature

		$record->{genome_id} = $ws_genome_name; #$ws_genome->{id}; # kb|g.3397
		$record->{genome_source} = $genome_source; # $ws_genome->{external_source}; # KBase Central Store
		$record->{genome_source_id} = $ws_genome->{external_source_id}; # 83332.12

		$record->{scientific_name} = $ws_taxon->{scientific_name};
		$record->{taxonomy} = $ws_taxon->{scientific_lineage};
		$record->{taxonomy} =~s/ *; */;/g;
		#$record->{tax_id} = $ws_taxon->{taxonomy_id};
		$record->{domain} = $ws_taxon->{domain};

		$record->{feature_type} = $feature->{type}; 
		$record->{feature_id} = $feature->{feature_id}; 
		$record->{feature_source_id} = $feature->{feature_id}; 
		$record->{function} = $feature->{function}; 
	
		# aliases
		my @aliases;
		foreach my $key (keys %{$feature->{aliases}}){
			push @aliases, "$feature->{aliases}->{$key}[0]:$key";
			$record->{gene_name} = $key if $feature->{aliases}->{$key}[0]=~/Genbank Gene/i;	 
		}
		$record->{aliases} = join(" :: ", @aliases);
	
		my $last_location = scalar @{$feature->{locations}};
		$record->{location_contig} = $feature->{locations}[0][0]; 
		$record->{location_begin} = $feature->{locations}[0][1]; 
		$record->{location_end} = $feature->{locations}[$last_location][1]+$feature->{location}[$last_location][3]; 
		$record->{location_strand} = $feature->{locations}[0][2]; 
		$record->{locations} = $json->pretty->encode($feature->{locations});
		$record->{locations} =~s/\s*//g; 
		$record->{locations} =~s/,\[\]//g; 

		$record->{protein_translation_length} = $feature->{protein_translation_length}; 
		$record->{dna_sequence_length} = $feature->{dna_sequence_length}; 

=for comment	
	$record->{roles} = $feature->{}; 
	$record->{subsystems} = $feature->{}; 
	$record->{subsystem_data} = $feature->{}; 
	$record->{protein_families} = $feature->{}; 
	$record->{annotations} = $feature->{annotations}; 
	$record->{regulon_data} = $feature->{}; 
	$record->{atomic_regulons} = $feature->{}; 
	$record->{coexpressed_fids} = $feature->{}; 
	$record->{co_occurring_fids} = $feature->{}; 
	$record->{has_protein_families} = $feature->{};	
	$record->{feature_publications} = $feature->{}; 
=cut

		push @solr_records, $record;
	    }
	}
	#print Dumper (\@solr_records);

	my $genome_json = $json->pretty->encode(\@solr_records);

	my $genome_file = $self->{scratch}."$ws_genome_name.json";

	open FH, ">$genome_file" or die "Cannot write to genome.json: $!";
	print FH "$genome_json";
	close FH;

	`$Bin/post_solr_update.sh genomes $genome_file`;#By default we assume all to be indexed--if $opt->index=~/y|yes|true|1/i;
	push (@{$output}, $kbase_genome_data);
    }
        
    if ($params->{create_report}) {
    	$self->util_create_report({
    		message => "Loaded and indexed to SOLR ".@{$output}." genomes!",
    		workspace => $params->{workspace}
    	});
    }
    #END index_genomes_in_solr
    my @_bad_returns;
    (ref($output) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to index_genomes_in_solr:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'index_genomes_in_solr');
    }
    return($output);
}




=head2 update_loaded_genomes

  $output = $obj->update_loaded_genomes($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a ReferenceDataManager.UpdateLoadedGenomesParams
$output is a reference to a list where each element is a ReferenceDataManager.KBaseReferenceGenomeData
UpdateLoadedGenomesParams is a reference to a hash where the following keys are defined:
	ensembl has a value which is a ReferenceDataManager.bool
	refseq has a value which is a ReferenceDataManager.bool
	phytozome has a value which is a ReferenceDataManager.bool
	workspace_name has a value which is a string
	create_report has a value which is a ReferenceDataManager.bool
bool is an int
KBaseReferenceGenomeData is a reference to a hash where the following keys are defined:
	ref has a value which is a string
	id has a value which is a string
	workspace_name has a value which is a string
	source_id has a value which is a string
	accession has a value which is a string
	name has a value which is a string
	ftp_dir has a value which is a string
	version has a value which is a string
	source has a value which is a string
	domain has a value which is a string

</pre>

=end html

=begin text

$params is a ReferenceDataManager.UpdateLoadedGenomesParams
$output is a reference to a list where each element is a ReferenceDataManager.KBaseReferenceGenomeData
UpdateLoadedGenomesParams is a reference to a hash where the following keys are defined:
	ensembl has a value which is a ReferenceDataManager.bool
	refseq has a value which is a ReferenceDataManager.bool
	phytozome has a value which is a ReferenceDataManager.bool
	workspace_name has a value which is a string
	create_report has a value which is a ReferenceDataManager.bool
bool is an int
KBaseReferenceGenomeData is a reference to a hash where the following keys are defined:
	ref has a value which is a string
	id has a value which is a string
	workspace_name has a value which is a string
	source_id has a value which is a string
	accession has a value which is a string
	name has a value which is a string
	ftp_dir has a value which is a string
	version has a value which is a string
	source has a value which is a string
	domain has a value which is a string


=end text



=item Description

Updates the loaded genomes in KBase for the specified source databases

=back

=cut

sub update_loaded_genomes
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to update_loaded_genomes:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'update_loaded_genomes');
    }

    my $ctx = $ReferenceDataManager::ReferenceDataManagerServer::CallContext;
    my($output);
    #BEGIN update_loaded_genomes
    #$params = $self->util_initialize_call($params,$ctx);
    
    my $msg = "";
    $output = [];
    my $loader = new GenomeFileUtil::GenomeFileUtilClient($ENV{ SDK_CALLBACK_URL });

    my $count = 0;
    my $updated_genomes = list_reference_genomes(refseq => 1, update_only => 0);
    my $loaded_genomes = list_loaded_genomes(refseq => 1);
    my @genomes_in_solr = list_genomes_in_solr();    

    for (my $i=0; $i <@{ $updated_genomes }; $i++) {
	my $genome = $updated_genomes->[$i];
	
	#check if the genome is already present in the database by querying SOLR
    	my $gnstatus = checkGenomeStatus( $genome, \@genomes_in_solr);

	if ($gnstatus=~/(new|updated)/i){
	   $count ++;
	   load_genomes( genomes => $genome, index_in_solr => 0 );
	   push(@{$output},$genome);
	   if ($count < 10) {
		   $msg .= $genome->{accession}.";".$genome->{status}.";".$genome->{name}.";".$genome->{ftp_dir}.";".$genome->{file}.";".$genome->{id}.";".$genome->{version}.";".$genome->{source}.";".$genome->{domain}."\n";
		}
	}else{
		# Current version already in KBase, check for annotation updates
	}
    }
    
    if ($params->{create_report}) {
    	$self->util_create_report({
    		message => "Updated ".@{$output}." genomes!",
    		workspace => $params->{workspace}
    	});
    	$output = [$params->{workspace}."/list_reference_genomes"];
    }
    #END update_loaded_genomes
    my @_bad_returns;
    (ref($output) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to update_loaded_genomes:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'update_loaded_genomes');
    }
    return($output);
}




=head2 update_loaded_genomes_v1

  $output = $obj->update_loaded_genomes_v1($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a ReferenceDataManager.UpdateLoadedGenomesParams_v1
$output is a reference to a list where each element is a ReferenceDataManager.KBaseReferenceGenomeData
UpdateLoadedGenomesParams_v1 is a reference to a hash where the following keys are defined:
	ensembl has a value which is a ReferenceDataManager.bool
	refseq has a value which is a ReferenceDataManager.bool
	phytozome has a value which is a ReferenceDataManager.bool
	genomeData has a value which is a reference to a list where each element is a ReferenceDataManager.ReferenceGenomeData
	workspace_name has a value which is a string
	create_report has a value which is a ReferenceDataManager.bool
	fileformats has a value which is a string
bool is an int
ReferenceGenomeData is a reference to a hash where the following keys are defined:
	accession has a value which is a string
	status has a value which is a string
	name has a value which is a string
	ftp_dir has a value which is a string
	file has a value which is a string
	id has a value which is a string
	version has a value which is a string
	source has a value which is a string
	domain has a value which is a string
KBaseReferenceGenomeData is a reference to a hash where the following keys are defined:
	ref has a value which is a string
	id has a value which is a string
	workspace_name has a value which is a string
	source_id has a value which is a string
	accession has a value which is a string
	name has a value which is a string
	ftp_dir has a value which is a string
	version has a value which is a string
	source has a value which is a string
	domain has a value which is a string

</pre>

=end html

=begin text

$params is a ReferenceDataManager.UpdateLoadedGenomesParams_v1
$output is a reference to a list where each element is a ReferenceDataManager.KBaseReferenceGenomeData
UpdateLoadedGenomesParams_v1 is a reference to a hash where the following keys are defined:
	ensembl has a value which is a ReferenceDataManager.bool
	refseq has a value which is a ReferenceDataManager.bool
	phytozome has a value which is a ReferenceDataManager.bool
	genomeData has a value which is a reference to a list where each element is a ReferenceDataManager.ReferenceGenomeData
	workspace_name has a value which is a string
	create_report has a value which is a ReferenceDataManager.bool
	fileformats has a value which is a string
bool is an int
ReferenceGenomeData is a reference to a hash where the following keys are defined:
	accession has a value which is a string
	status has a value which is a string
	name has a value which is a string
	ftp_dir has a value which is a string
	file has a value which is a string
	id has a value which is a string
	version has a value which is a string
	source has a value which is a string
	domain has a value which is a string
KBaseReferenceGenomeData is a reference to a hash where the following keys are defined:
	ref has a value which is a string
	id has a value which is a string
	workspace_name has a value which is a string
	source_id has a value which is a string
	accession has a value which is a string
	name has a value which is a string
	ftp_dir has a value which is a string
	version has a value which is a string
	source has a value which is a string
	domain has a value which is a string


=end text



=item Description

Updates the loaded genomes in KBase for the specified source databases

=back

=cut

sub update_loaded_genomes_v1
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to update_loaded_genomes_v1:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'update_loaded_genomes_v1');
    }

    my $ctx = $ReferenceDataManager::ReferenceDataManagerServer::CallContext;
    my($output);
    #BEGIN update_loaded_genomes_v1
    #$params = $self->util_initialize_call($params,$ctx);
    $params = $self->util_args($params,[],{
    	ensembl => 0,#todo
    	phytozome => 0,#todo
    	refseq => 1,
    	create_report => 0,
    	workspace_name => "RefSeq_Genomes",
    	genomeData => [],
    	formats => "gbf"
    });
    
    my $msg = "";
    $output = [];
    my $solrServer = $self->{_SOLR_URL};#$ENV{KBASE_SOLR};
    my $solrFormat="&wt=csv&csv.separator=%09&csv.mv.separator=;";
    my $loader = new GenomeFileUtil::GenomeFileUtilClient($ENV{ SDK_CALLBACK_URL });
    my $genome_data = $params->{genomeData};
    my $count = 0;
    for (my $i=0; $i < @{$genome_data}; $i++) {
	my $genome = $genome_data->[$i];
	
	#check if the genome is already present in the database by querying SOLR
    	my $gnstatus;
  	my $core = "/genomes";
  	my $query = "/select?q=genome_id:".$genome->{id}."*"; 
  	my $fields = "&fl=genome_source,genome_id,genome_name";
  	my $rows = "&rows=100";
  	my $sort = "";
  	my $solrQuery = $solrServer.$core.$query.$fields.$rows.$sort.$solrFormat;
	print "\n$solrQuery\n";
	my @records = `wget -q -O - "$solrQuery" | grep -v genome_name`;

	if (scalar @records == 0 ){
	   $gnstatus = "New genome";
	}else{
	   my ($genome_source, $genome_id, $genome_name) = split /\t/, @records[0];

	   if ($genome_id eq $genome->{accession}){
		$gnstatus = "Existing genome: current";
		$genome->{genome_id} = $genome_id;
	   }elsif ($genome_id =~/$genome->{id}/){
		$gnstatus = "Existing genome: updated ";
		$genome->{genome_id} = $genome_id;
	   }else{
		$gnstatus = "Existing genome: status unknown";
		$$genome->{genome_id} = $genome_id;
	   }
	}
	if ($gnstatus=~/(new|updated)/i){
		$count ++;
		push(@{$output},$genome);
		if ($count < 10) {
		   $msg .= $genome->{accession}.";".$genome->{status}.";".$genome->{name}.";".$genome->{ftp_dir}.";".$genome->{file}.";".$genome->{id}.";".$genome->{version}.";".$genome->{source}.";".$genome->{domain}."\n";
		}
	}else{
		# Current version already in KBase, check for annotation updates
	}
    }
    
    if ($params->{create_report}) {
    	$self->util_create_report({
    		message => "Updated ".@{$output}." genomes!",
    		workspace => $params->{workspace}
    	});
    	$output = [$params->{workspace}."/list_reference_genomes"];
    }
    #END update_loaded_genomes_v1
    my @_bad_returns;
    (ref($output) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to update_loaded_genomes_v1:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'update_loaded_genomes_v1');
    }
    return($output);
}




=head2 version 

  $return = $obj->version()

=over 4

=item Parameter and return types

=begin html

<pre>
$return is a string
</pre>

=end html

=begin text

$return is a string

=end text

=item Description

Return the module version. This is a Semantic Versioning number.

=back

=cut

sub version {
    return $VERSION;
}

=head1 TYPES



=head2 bool

=over 4



=item Description

A boolean.


=item Definition

=begin html

<pre>
an int
</pre>

=end html

=begin text

an int

=end text

=back



=head2 ListReferenceGenomesParams

=over 4



=item Description

Arguments for the list_reference_genomes function


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
ensembl has a value which is a ReferenceDataManager.bool
refseq has a value which is a ReferenceDataManager.bool
phytozome has a value which is a ReferenceDataManager.bool
updated_only has a value which is a ReferenceDataManager.bool
workspace_name has a value which is a string
create_report has a value which is a ReferenceDataManager.bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
ensembl has a value which is a ReferenceDataManager.bool
refseq has a value which is a ReferenceDataManager.bool
phytozome has a value which is a ReferenceDataManager.bool
updated_only has a value which is a ReferenceDataManager.bool
workspace_name has a value which is a string
create_report has a value which is a ReferenceDataManager.bool


=end text

=back



=head2 ReferenceGenomeData

=over 4



=item Description

Struct containing data for a single genome output by the list_reference_genomes function


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
accession has a value which is a string
status has a value which is a string
name has a value which is a string
ftp_dir has a value which is a string
file has a value which is a string
id has a value which is a string
version has a value which is a string
source has a value which is a string
domain has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
accession has a value which is a string
status has a value which is a string
name has a value which is a string
ftp_dir has a value which is a string
file has a value which is a string
id has a value which is a string
version has a value which is a string
source has a value which is a string
domain has a value which is a string


=end text

=back



=head2 ListLoadedGenomesParams

=over 4



=item Description

Arguments for the list_loaded_genomes function


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
ensembl has a value which is a ReferenceDataManager.bool
refseq has a value which is a ReferenceDataManager.bool
phytozome has a value which is a ReferenceDataManager.bool
workspace_name has a value which is a string
create_report has a value which is a ReferenceDataManager.bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
ensembl has a value which is a ReferenceDataManager.bool
refseq has a value which is a ReferenceDataManager.bool
phytozome has a value which is a ReferenceDataManager.bool
workspace_name has a value which is a string
create_report has a value which is a ReferenceDataManager.bool


=end text

=back



=head2 KBaseReferenceGenomeData

=over 4



=item Description

Struct containing data for a single genome output by the list_loaded_genomes function


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
ref has a value which is a string
id has a value which is a string
workspace_name has a value which is a string
source_id has a value which is a string
accession has a value which is a string
name has a value which is a string
ftp_dir has a value which is a string
version has a value which is a string
source has a value which is a string
domain has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
ref has a value which is a string
id has a value which is a string
workspace_name has a value which is a string
source_id has a value which is a string
accession has a value which is a string
name has a value which is a string
ftp_dir has a value which is a string
version has a value which is a string
source has a value which is a string
domain has a value which is a string


=end text

=back



=head2 LoadGenomesParams

=over 4



=item Description

Arguments for the load_genomes function


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
data has a value which is a string
genomes has a value which is a reference to a list where each element is a ReferenceDataManager.ReferenceGenomeData
index_in_solr has a value which is a ReferenceDataManager.bool
workspace_name has a value which is a string
create_report has a value which is a ReferenceDataManager.bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
data has a value which is a string
genomes has a value which is a reference to a list where each element is a ReferenceDataManager.ReferenceGenomeData
index_in_solr has a value which is a ReferenceDataManager.bool
workspace_name has a value which is a string
create_report has a value which is a ReferenceDataManager.bool


=end text

=back



=head2 IndexGenomesInSolrParams

=over 4



=item Description

Arguments for the index_genomes_in_solr function


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
genomes has a value which is a reference to a list where each element is a ReferenceDataManager.KBaseReferenceGenomeData
workspace_name has a value which is a string
creat_report has a value which is a ReferenceDataManager.bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
genomes has a value which is a reference to a list where each element is a ReferenceDataManager.KBaseReferenceGenomeData
workspace_name has a value which is a string
creat_report has a value which is a ReferenceDataManager.bool


=end text

=back



=head2 UpdateLoadedGenomesParams

=over 4



=item Description

Arguments for the update_loaded_genomes function


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
ensembl has a value which is a ReferenceDataManager.bool
refseq has a value which is a ReferenceDataManager.bool
phytozome has a value which is a ReferenceDataManager.bool
workspace_name has a value which is a string
create_report has a value which is a ReferenceDataManager.bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
ensembl has a value which is a ReferenceDataManager.bool
refseq has a value which is a ReferenceDataManager.bool
phytozome has a value which is a ReferenceDataManager.bool
workspace_name has a value which is a string
create_report has a value which is a ReferenceDataManager.bool


=end text

=back



=head2 UpdateLoadedGenomesParams_v1

=over 4



=item Description

Arguments for the update_loaded_genomes_v1 function


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
ensembl has a value which is a ReferenceDataManager.bool
refseq has a value which is a ReferenceDataManager.bool
phytozome has a value which is a ReferenceDataManager.bool
genomeData has a value which is a reference to a list where each element is a ReferenceDataManager.ReferenceGenomeData
workspace_name has a value which is a string
create_report has a value which is a ReferenceDataManager.bool
fileformats has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
ensembl has a value which is a ReferenceDataManager.bool
refseq has a value which is a ReferenceDataManager.bool
phytozome has a value which is a ReferenceDataManager.bool
genomeData has a value which is a reference to a list where each element is a ReferenceDataManager.ReferenceGenomeData
workspace_name has a value which is a string
create_report has a value which is a ReferenceDataManager.bool
fileformats has a value which is a string


=end text

=back



=cut

1;
