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
use Config::Simple;
use POSIX;
use FindBin qw($Bin);
use JSON;
use Data::Dumper qw(Dumper);
use LWP::UserAgent;
use XML::Simple;


#The first thing every function should do is call this function
sub util_initialize_call {
	my ($self,$params,$ctx) = @_;
	#print("Starting ".$ctx->method()." method.\n");
	$self->{_token} = $ctx->token();
	$self->{_username} = $ctx->user_id();
	$self->{_method} = $ctx->method();
	$self->{_provenance} = $ctx->provenance();	
	
	my $config_file = $ENV{ KB_DEPLOYMENT_CONFIG };
    my $cfg = Config::IniFiles->new(-file=>$config_file);
	$self->{scratch} = $cfg->val('ReferenceDataManager','scratch');
	$self->{workspace_url} = $cfg->val('ReferenceDataManager','workspace-url');#$config->{"workspace-url"};	
	die "no workspace-url defined" unless $self->{workspace_url};	$self->util_timestamp(DateTime->now()->datetime());
	print "\nWorkspace service url: $self->{workspace_url}\n";
	$self->{_wsclient} = new Bio::KBase::workspace::Client($self->{workspace_url},token => $ctx->token());
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
#################### methods for accessing SOLR using its web interface#######################
#
# method name: _testActionsInSolr
#
sub _testActionsInSolr_passed
{
	my ($self) = @_;
	$self -> _autocommit(0);
	my $json = JSON->new->allow_nonref;
	
	#1. check if the server is reachable
	if (! $self->_ping()) {
		#print "\n Error: " . $self->_error->{response};
		#exit 1;
	}
	print "\nThe server is alive!\n";
	
	#2. list all the contents in core "QZtest", with group option specified
	my $grpOption = "genome_id";
	#my $solr_ret = $self -> _listGenomesInSolr("QZtest", "genome_id", $grpOption );
	#print "\nList of genomes in QZtest at start: \n" . Dumper($solr_ret) . "\n";
	
	#3.1 wipe out the whole QZtest content!
	my $ds = {
    	#'workspace_name' => 'KBasePublicRichGenomesV5',
		#'genome_id' => 'kb|g.0'
		'*' => '*' 
	};
	#$self->_deleteRecords("QZtest", $ds);
	
	#3.2 confirm the contents in core "QZtest" are gone, with group option specified
	#$grpOption = "genome_id";
	#$solr_ret = $self -> _listGenomesInSolr("QZtest", "genome_id", $grpOption );
	#print "\nList of genomes in QZtest after deletion: \n" . Dumper($solr_ret) . "\n";
	
	#4.1 list all the contents in core "genomes", without group option--get the first 100 rows
	$grpOption = "";
	my $solr_ret = $self -> _listGenomesInSolr( "genomes", "*", $grpOption );
	my $genome_docs = $solr_ret->{response}->{response}->{docs};
	#print "\nList of genomes in core 'genomes': \n" . Dumper($genome_docs) . "\n";
	
	#5.1 populate core QZtest with the list of document from "genomes", one by one
	my $solrCore = "QZtest";
	#$self -> _addXML2Solr($solrCore, $genome_docs);
		
	#6.1 list all the refernece genomes from the Gene Bank
	my $genebank_ret = $self->list_reference_genomes({
        refseq => 1,
        update_only => 0
    });
	print "\nGene bank genome list, the first record: \n" . Dumper($genebank_ret->[0]). "\n";
		
	#6.2 list all the refernece genomes already loaded into KBase	
	my $KBgenomes_ret = $self->list_loaded_genomes({
            refseq => 1
	});
	print "\nKBase genome list: \n" . Dumper($KBgenomes_ret). "\n";	
	
	#6.3.0 Index all the refernece genomes already in KBase
	my $solrGenomes_ret = $self->index_genomes_in_solr({
		genomes => $KBgenomes_ret
	});
	#6.3.1 Commit db changes
	print "\nSolr genome list: \n" . Dumper($solrGenomes_ret). "\n";	
		if (!$self->_commit("QZtest")) {
    	print "\n Error: " . $self->_error->{response};
    	exit 1;
	}
	# Confirm the contents in core "QZtest" after addition, without group option specified
	$grpOption = "genome_id";
	$solr_ret = $self -> _listGenomesInSolr("QZtest", "*", $grpOption );
	print "\nList of docs in QZtest after insertion 1: \n" . Dumper($solr_ret) . "\n";	
	exit 0;
	
	#6.4 load genomes from the Gene Bank to KBase	
	my $genomesLoaded_ret = $self->load_genomes({
		genomes => [$genebank_ret->[0]],
		index_in_solr => 0
	});
	print "\nLoaded genome list: \n" . Dumper($genomesLoaded_ret). "\n";	
			
	#6.5 list all the refernece genomes updated
	my $ret = $self->update_loaded_genomes_v1({
 		genomeData => [$genebank_ret->[0]],    
        refseq => 1,
		formats => "gbff"
    });
	print "\nUpdated loaded genome list: \n" . Dumper($ret). "\n";
	exit 0;		
}

sub _testListGenomes{	
	my ($self) = @_;
	
	my $token = $ENV{'KB_AUTH_TOKEN'};
	my $config_file = $ENV{ KB_DEPLOYMENT_CONFIG };
	my $cfg = Config::IniFiles->new(-file=>$config_file);
	$self->{scratch} = $cfg->val('ReferenceDataManager','scratch');
	$self->{workspace_url} = $cfg->val('ReferenceDataManager','workspace-url');#$config->{"workspace-url"};	
	die "no workspace-url defined" unless $self->{workspace_url};
	$self->util_timestamp(DateTime->now()->datetime());
	print "\nWorkspace service url: $self->{workspace_url}\n";	
	$self->{_wsclient} = new Bio::KBase::workspace::Client($self->{workspace_url},token => $token);
	
	my $output = [];
	my $sources = ["ensembl","phytozome","refseq"];
    		my $wsname = $self->util_workspace_names($sources->[2]);#only test refseq
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
	    			type => "KBaseGenomes.Genome-8.0",
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
	    				print "List of loaded genomes (<10):\n". Data::Dumper->Dump([$output->[$curr]])."\n";
	    			}
	    		}
    		}
	exit 0;	
}

sub _testLoadGenomes{	
	my ($self) = @_;
	
	my $token = $ENV{'KB_AUTH_TOKEN'};
	my $config_file = $ENV{ KB_DEPLOYMENT_CONFIG };
	my $cfg = Config::IniFiles->new(-file=>$config_file);
	$self->{scratch} = $cfg->val('ReferenceDataManager','scratch');
	$self->{workspace_url} = $cfg->val('ReferenceDataManager','workspace-url');#$config->{"workspace-url"};	
	die "no workspace-url defined" unless $self->{workspace_url};
	$self->util_timestamp(DateTime->now()->datetime());
	print "\nWorkspace service url: $self->{workspace_url}\n";	
	$self->{_wsclient} = new Bio::KBase::workspace::Client($self->{workspace_url},token => $token);
	
	my $loader = new GenomeFileUtil::GenomeFileUtilClient($ENV{ SDK_CALLBACK_URL });	
	
	my $genomes = [{
          'domain' => 'bacteria',
          'ftp_dir' => 'ftp://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/010/525/GCF_000010525.1_ASM1052v1',
          'version' => '1',
          'id' => 'GCF_000010525',
          'accession' => 'GCF_000010525.1',
          'status' => 'latest',
          'source' => 'refseq',
          'file' => 'GCF_000010525.1_ASM1052v1',
          'name' => 'ASM1052v1'
	}];
	my $wsname = 'kkeller:1454440703158';	
	
	for (my $i=0; $i < @{$genomes}; $i++) {
		my $genome = $genomes->[$i];
		print "Now loading ".$genome->{source}.":".$genome->{id}." for $wsname.\n";
		
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
		print "\nLoaded genome list--test: \n" . Dumper($genutilout). "\n";
	}		
	exit 0;	
}

#
#Internal Method: to list the genomes already in SOLR and return an array of those genomes
#
sub _listGenomesInSolr {
	my ($self, $solrCore, $fields, $grp) = @_;
	my $count = 100;#2,147,483,647 is integer's maximum value
	my $start = 0;
	my $rows = "&rows=100";
  	my $sort = "&sort=genome_id asc";
	
	my $params = {
		fl => $fields, #"genome_id",
		wt => "json",
		rows => $count,
		sort => "genome_id asc",
		hl => "false",
		start => $start
	};
	my $query = { q => "*" };
	
	return $self->_searchSolr($solrCore, $params, $query, "json", $grp);
}
#
# method name: _searchSolr
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
sub _searchSolr {
	my ($self, $searchCore, $searchParams, $searchQuery, $resultFormat, $groupOption, $skipEscape) = @_;
	$skipEscape = {} unless $skipEscape;
	
	# If output format is not passed set it to XML
    $resultFormat = "xml" unless $resultFormat;
    my $DEFAULT_FIELD_CONNECTOR = "AND";

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
    }
    $queryFields .= "$qStr";
	
	my $solrCore = "/$searchCore"; 
  	my $sort = "&sort=genome_id asc";
	my $solrGroup = $groupOption ? "&group=true&group.field=$groupOption" : "";
	my $solrQuery = $self->{_SOLR_URL}.$solrCore."/select?".$queryFields.$solrGroup;
	print "Query string:\n$solrQuery\n";
	
	my $solr_response = $self->_sendRequest("$solrQuery", "GET");
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
		#print @solr_genome_records[0]->{doclist}->{numFound} ."\n";
	}
	return $solr_response;
}

#
# method name: _deleteRecords
# Internal Method: to delete record(s) in SOLR that matches the given id(s) in the query
# parameters:
# $criteria is a hash that holds the conditions for field(s) to be deleted, see the example below:
# $criteria {
#   'object_id' => 'kb|ws.2869.obj.72243',
#   'workspace_name' => 'KBasePublicRichGenomesV5'
#}
#
sub _deleteRecords
{
	my ($self, $searchCore, $criteria) = @_;
	my $solrCore = "/$searchCore";

	# Build the <query/> string that concatenates all the criteria into query tags
	my $queryCriteria = "<delete>";
    if (! $criteria) {
        $self->{is_error} = 1;
        $self->{errmsg} = "No deletion criteria specified";
        return undef;
    }
        foreach my $key (keys %$criteria) {
        $queryCriteria .= "<query>$key:". URI::Escape::uri_escape($criteria->{$key}) . "</query>";
    }

    $queryCriteria .= "</delete>&commit=true";
    #print "The deletion query string is: \n" . "$queryCriteria \n";

	my $solrQuery = $self->{_SOLR_URL}.$solrCore."/update?stream.body=".$queryCriteria;
	#print "The final deletion query string is: \n" . "$solrQuery \n";

	my $solr_response = $self->_sendRequest("$solrQuery", "GET");
	return $solr_response;
}

#
# method name: _sendRequest
# Internal Method used for sending HTTP
# url : Requested url
# method : HTTP method
# dataType : Type of data posting (binary or text)
# headers : headers as key => value pair
# data : if binary it will as sequence of character
#          if text it will be key => value pair
sub _sendRequest
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
	#print "The HTTP request: \n" . Dumper($request) . "\n";
	
    # Send request and receive the response
    my $response = $ua->request($request);
    $out->{responsecode} = $response->code();
    $out->{response} = $response->content;
    $out->{url} = $url;
    return $out;
}

#
# Internal Method: to parse solr server response
# Responses from Solr take the form shown here:
#<response>
#  <lst name="responseHeader">
#    <int name="status">0</int>
#    <int name="QTime">127</int>
#  </lst>
#</response>
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
# method name: _addXML2Solr
# Internal method: to add XML documents to solr for indexing.
# It sends a xml http request.  First it will convert the raw datastructure to required ds then it will convert
# this ds to xml. This xml will be posted to Apache solr for indexing.
# Depending on the flag AUTOCOMMIT the documents will be indexed immediatly or on commit is issued.
# parameters:
#     $params: This parameter specifies set of list of document fields and values.
# return
#    1 for successful posting of the xml document
#    0 for any failure
#
#
sub _addXML2Solr
{
    my ($self, $solrCore, $params) = @_;
    my $ds = $self->_rawDsToSolrDs($params);
    my $doc = $self->_toXML($ds, 'add');
    my $commit = $self->{_AUTOCOMMIT} ? 'true' : 'false';
    my $url = "$self->{_SOLR_URL}/$solrCore/update?commit=" . $commit;
    my $response = $self->_sendRequest($url, 'POST', undef, $self->{_CT_XML}, $doc);
    print "After request sent by _addXML2Solr:\n" . Dumper($response) ."\n";
    return 1 if ($self->_parseResponse($response));
    return 0;
}

#
# method name: _toXML
# Internal Method
# This function will convert the datastructe to XML document
# For XML Formatted Index Updates
#
# The XML schema recognized by the update handler for adding documents is very straightforward:
# The <add> element introduces one or more documents to be added.
# The <doc> element introduces the fields making up a document.
# The <field> element presents the content for a specific field.
# For example:
# <add>
#  <doc>
#    <field name="authors">Patrick Eagar</field>
#    <field name="subject">Sports</field>
#    <field name="dd">796.35</field>
#    <field name="numpages">128</field>
#    <field name="desc"></field>
#    <field name="price">12.40</field>
#    <field name="title" boost="2.0">Summer of the all-rounder: Test and championship cricket in England 1982</field>
#    <field name="isbn">0002166313</field>
#    <field name="yearpub">1982</field>
#    <field name="publisher">Collins</field>
#  </doc>
#  <doc boost="2.5">
#  ...
#  </doc>
#</add>
# Index update commands can be sent as XML message to the update handler using Content-type: application/xml or Content-type: text/xml.
# For adding Documents
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
	#print "\n$xml\n";
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
#
sub _rawDsToSolrDs
{
    my ($self, $docs) = @_;
	#print "\nInput data:\n". Dumper($docs);
    my $ds = [];
	if( ref($docs) eq 'ARRAY' && scalar (@$docs) ) {
    	for my $doc (@$docs) {
    		my $d = [];		
    		for my $field (keys %$doc) {
        		my $values = $doc->{$field};
        		if (ref($values) eq 'ARRAY' && scalar (@$values) ){
        			for my $val (@$values) {
            			push @$d, {name => $field, content => $val} unless $field eq '_version_';
        			}
        		} else {#only a single member in the list
        			push @$d, { name => $field, content => $values} unless $field eq '_version_'; 
        		}
    		}
    		push @$ds, {field => $d};
    	}
	}
	else {#only a single member in the list
		my $d = [];	
    	for my $field (keys %$docs) {
        	my $values = $docs->{$field};
			#print "$field => " . Dumper($values);
        	if (ref($values) eq 'ARRAY' && scalar (@$values) ){
        		for my $val (@$values) {
            		push @$d, {name => $field, content => $val} unless $field eq '_version_';
        		}
        	} else {#only a single member in the list
        		push @$d, { name => $field, content => $values} unless $field eq '_version_'; 
        	}
    	}
    	push @$ds, {field => $d};
    }
	
    $ds = { doc => $ds };
    #print "\noutput data:\n" .Dumper($ds);
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
#
sub _commit
{
    my ($self, $solrCore) = @_;
    my $url = $self->{_SOLR_POST_URL} . "/$solrCore/update";
    my $cmd = $self->_toXML('true', 'commit');
    my $response = $self->_sendRequest($url, 'POST', undef, $self->{_CT_XML}, $cmd);

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
#
sub _rollback
{
    my ($self, $solrCore) = @_;
    my $url = $self->{_SOLR_POST_URL} . "/$solrCore/update";
    my $cmd = $self->_toXML('', 'rollback');
    my $response = $self->_sendRequest($url, 'POST', undef, $self->{_CT_XML}, $cmd);

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
#
sub _exists
{
    my ($self, $id) = @_;
    my $url = "$self->{_SOLR_SEARCH_URL}?q=id:$id";
    my $response = $self->_sendRequest($url, 'GET');
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
    my ($self, $errors) = @_;
	print "Pinging server: $self->{_SOLR_PING_URL}\n";
    my $response = $self->_sendRequest($self->{_SOLR_PING_URL}, 'GET');
	#print "Ping's response:\n" . Dumper($response) . "\n";
	
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
# method name: _error
# returns the errors details that was occured during last transaction action.
# params : -
# returns : response details includes the following details
#    {
#       url => 'url which is being accessed',
#       response => 'response from server',
#       code => 'response code',
#       errmsg => 'for any internal error error msg'
#     }
#
# Check error method for for getting the error details for last command
#
sub _error
{
    my ($self) = @_;
    return $self->{error};
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

    $self->{_workspace_map} = {
    	ensembl => "Ensembl_Genomes",
    	phytozome => "Phytozome_Genomes",
    	refseq => "kkeller:1454440703158"#"ReferenceTaxons"#"KBaseExampleData"#"KBasePublicRichGenomesV5"#"RefSeq_Genomes"
    };  
		
	#SOLR specific parameters
    if (! $self->{_SOLR_URL}) {
        $self->{_SOLR_URL} = "http://kbase.us/internal/solr-ci/search";
    }
    $self->{_SOLR_POST_URL} = $self->{_SOLR_URL};
    $self->{_SOLR_PING_URL} = "$self->{_SOLR_URL}/select";
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
    $params = $self->util_initialize_call($params,$ctx);
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
    $params = $self->util_initialize_call($params,$ctx);	
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
	    			type => "KBaseGenomes.Genome-8.0",
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
    $params = $self->util_initialize_call($params,$ctx);
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

	 my $wsname = $self->util_workspace_names($genome->{source});	
	 print "Now loading ".$genome->{source}.":".$genome->{id}." with loader url=".$ENV{ SDK_CALLBACK_URL }."\n";
	 
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
    $params = $self->util_initialize_call($params,$ctx);
    $params = $self->util_args($params,[],{
    	genomes => {},
        create_report => 0,
    	workspace_name => undef
    });
    my $json = JSON->new->allow_nonref;
    my @solr_records;
    $output = [];
	my $genomes = $params->{genomes};
	for (my $i=0; $i < @{$genomes}; $i++) {
		my $record;
		my $kbase_genome_data = $genomes->[$i];
		my $ws_name = $kbase_genome_data->{workspace_name};
		my $ws_genome_name = $kbase_genome_data->{id}; 
		my $genome_source = $kbase_genome_data->{source};
		
		my $ws_genome_obj_metadata = {};
		my $ws_genome_obj_data = {};
		my $ws_genome_usr_metadata = {};
		my $ws_genome_object_info = {};
		if(defined($self->util_ws_client())){
    		$ws_genome_object_info = $self->util_ws_client()->get_object({
				id => $ws_genome_name,
				workspace => $ws_name});
			$ws_genome_obj_metadata = $ws_genome_object_info->{metadata}; #`ws-get -w $ws_name $ws_genome_name -m`;	
			$ws_genome_obj_data = $ws_genome_object_info->{data}; #`ws-get -w $ws_name $ws_genome_name`;	
			$ws_genome_usr_metadata = $ws_genome_obj_metadata->[10];
			#print "$ws_genome_obj_data:\n".Dumper($ws_genome_obj_data)."\n";
		}		

		my $ws_obj_id = $ws_genome_obj_metadata->[11];
		
		$record->{workspace_name} = $ws_name; 
		$record->{object_id} = $ws_obj_id; #"kb|ws.".$ws_id.".obj."."$ws_genome_id"; # kb|ws.2869.obj.9837
		$record->{object_name} = $ws_genome_name; # kb|g.3397
		$record->{object_type} = $ws_genome_obj_metadata->[1];#"KBaseGenomes.Genome-8.0"; 

		# Get genome info
		my $ws_genome  = $ws_genome_obj_data;#$json->decode(`ws-get -w $ws_name $ws_genome_name`);
		$record->{genome_id} = $ws_genome_name; #$ws_genome->{id}; # kb|g.3397
		$record->{genome_source} = $ws_genome->{source};#$genome_source; $ws_genome->{external_source}; # KBase Central Store
		$record->{genome_source_id} = $ws_genome->{source_id};#$ws_genome->{external_source_id}; # 'NODE_220_length_6412_cov_5.05805_ID_439'
		#$record->{num_cds} = $ws_genome->{md5};#[doc=12] Error adding field \'num_cds\'=\'\'
		
		# Get assembly info
		#my $ws_assembly = $ws_genome->{assembly_ref};#json->decode(`ws-get $ws_genome->{assembly_ref}`);
		$record->{genome_dna_size} = $ws_genome->{dna_size};#3867594
		$record->{num_contigs} = $ws_genome->{num_contigs};#304
		$record->{scientific_name} = $ws_genome->{scientific_name};
		$record->{domain} = $ws_genome->{domain};
		$record->{gc_content} = $ws_genome->{gc_content};
		$record->{complete} = $ws_genome->{complete}; # 1	
		
		#ERROR: [doc=12] unknown field--meaning the Solr schema does not include these fields, we could modify the schema if needed
		#$record->{contigset_ref} = $ws_genome->{contigset_ref};#"6/11/1"#ERROR: [doc=12] unknown field \'contigset_ref\'							
		#$record->{genetic_code} = $ws_genome->{genetic_code};#ERROR: [doc=12] unknown field \'genetic_code\'		
 		#$record->{md5} = $ws_genome->{md5};#'9afd25f3e46a18b3b3d176a7e33a4c48':ERROR: [doc=12] unknown field \'md5\'
		
		# Get taxon info
		my $ws_taxon = $ws_genome->{taxon_ref};#$ws_genome_usr_metadata;#$json->decode(`ws-get $ws_genome->{taxon_ref}`);
		$record->{taxonomy} = $ws_genome->{taxonomy};#Bacteria; Rhodobacter CACIA 14H1'
		#$record->{tax_id} = $ws_genome->{tax_id};#-1#ERROR: [doc=12] unknown field \'tax_id\'		
		
		# Get feature info#These data fields exist in the current genomes Solr schema, 
		# but not available from this workspace's objects, not even in the 'features' array
		my $ws_features = $ws_genome->{features};
		#print "$ws_features:\n".Dumper($ws_features->[0])."\n";
		#$record->{feature_source_id} = $ws_features->{feature_source_id}; #fig|83333.1.peg.3182
		#$record->{feature_id} = $ws_features->{id}; #kb|g.0.peg.3026
		#$record->{feature_type} = $ws_features->{type};#CDS
		#$record->{feature_publications} = $ws_features->{feature_publications};#8576051 Characterization of degQ and degS, Escherichia coli genes encoding homologs of the DegP protease. http://www.ncbi.nlm.nih.gov/pubmed/8576051 Waller,P R; Sauer,R T Journal of bacteriology

		#$genome->{genome_publications}=$ws_genome->{};
		#$genome->{has_publications}=$ws_genome->{};

		push (@{solr_records}, $record);
		
		# Test adding the docs in @{solr_records} to a given Solr core
		my $solrCore = "QZtest";
		$self -> _addXML2Solr($solrCore, @{solr_records});

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
    $params = $self->util_initialize_call($params,$ctx);
    
    my $msg = "";
    $output = [];
	print "\nTesting within update_loaded_genomes\n";
    my $count = 0;
    my $ref_genomes = $self->list_reference_genomes({refseq => 1, update_only => 0});
    my $loaded_genomes = $self->list_loaded_genomes({refseq => 1});
    my @genomes_in_solr = ($self->_listGenomesInSolr("QZtest", "*"))->{response}->{response}->{docs};    

    for (my $i=0; $i <@{ $ref_genomes }; $i++) {
		my $genome = $ref_genomes->[$i];
	
		#check if the genome is already present in the database by querying SOLR
    	my $gnstatus = $self->checkGenomeStatus( $genome, \@genomes_in_solr);

		if ($gnstatus=~/(new|updated)/i){
	   		$count ++;
	   		#$self->load_genomes( genomes => $genome, index_in_solr => 1 );
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
    	$output = [$params->{workspace}."/update_loaded_genomes"];
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


