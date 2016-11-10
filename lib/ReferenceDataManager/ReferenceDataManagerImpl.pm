package ReferenceDataManager::ReferenceDataManagerImpl;
use strict;
use Bio::KBase::Exceptions;
# Use Semantic Versioning (2.0.0-rc.1)
# http://semver.org 
our $VERSION = '0.0.1';
our $GIT_URL = 'https://github.com/kbaseapps/ReferenceDataManager.git';
our $GIT_COMMIT_HASH = 'c3bbdbc026deb29a8d22d82e74f9c1a03dfbbeaa';

=head1 NAME

ReferenceDataManager

=head1 DESCRIPTION

A KBase module: ReferenceDataManager

=cut

#BEGIN_HEADER
use Bio::KBase::AuthToken;
use Workspace::WorkspaceClient;
use GenomeFileUtil::GenomeFileUtilClient;
use Config::IniFiles;
use Config::Simple;
use POSIX;
use FindBin qw($Bin);
use JSON;
use Data::Dumper qw(Dumper);
use LWP::UserAgent;
use XML::Simple;
use Try::Tiny;


#The first thing every function should do is call this function
sub util_initialize_call {
    my ($self,$params,$ctx) = @_;
    $self->{_token} = $ctx->token();
    $self->{_username} = $ctx->user_id();
    $self->{_method} = $ctx->method();
    $self->{_provenance} = $ctx->provenance();  
    
    my $config_file = $ENV{ KB_DEPLOYMENT_CONFIG };
    my $cfg = Config::IniFiles->new(-file=>$config_file);
    $self->{scratch} = $cfg->val('ReferenceDataManager','scratch');
    $self->{workspace_url} = $cfg->val('ReferenceDataManager','workspace-url');#$config->{"workspace-url"}; 
    die "no workspace-url defined" unless $self->{workspace_url};   $self->util_timestamp(DateTime->now()->datetime());
    $self->{_wsclient} = new Workspace::WorkspaceClient($self->{workspace_url},token => $ctx->token());
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
#Internal Method: to list the genomes already in SOLR and return an array of those genomes
#
sub _listGenomesInSolr {
    my ($self, $solrCore, $fields, $rowStart, $rowCount, $grp) = @_;
    my $start = ($rowStart) ? $rowStart : 0;
    my $count = ($rowCount) ? $rowCount : 10;
    $fields = ($fields) ? $fields : "*";

    my $params = {
        fl => $fields,
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
#Internal Method: to list the taxa already in SOLR and return an array of those taxa
#
sub _listTaxaInSolr {
    my ($self, $solrCore, $fields, $rowStart, $rowCount, $grp) = @_;
    $solrCore = ($solrCore) ? $solrCore : "taxonomy_ci";
    my $start = ($rowStart) ? $rowStart : 0;
    my $count = ($rowCount) ? $rowCount : 10;
    $fields = ($fields) ? $fields : "*";

    my $params = {
        fl => $fields,
        wt => "json",
        rows => $count,
        sort => "taxonomy_id asc",
        hl => "false",
        start => $start
    };
    my $query = { q => "*" };
    
    return $self->_searchSolr($solrCore, $params, $query, "json", $grp);    
}
#
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

    if (!$self->_ping()) {
        die "\nError--Solr server not responding:\n" . $self->_error->{response};
    }
    
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
        my @solr_records = @{$solr_response->{response}->{grouped}->{$groupOption}->{groups}};
        print "\n\nFound unique genome_id groups of:" . scalar @solr_records . "\n";
        print @solr_records[0]->{doclist}->{numFound} ."\n";
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

    if (!$self->_ping()) {
        die "\nError--Solr server not responding:\n" . $self->_error->{response};
    }
    
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
    
    if (!$self->_ping()) {
        die "\nError--Solr server not responding:\n" . $self->_error->{response};
    }
    
    my $ds = $self->_rawDsToSolrDs($params);
    my $doc = $self->_toXML($ds, 'add');
    my $commit = $self->{_AUTOCOMMIT} ? 'true' : 'false';
    my $url = "$self->{_SOLR_URL}/$solrCore/update?commit=" . $commit;
    my $response = $self->_sendRequest($url, 'POST', undef, $self->{_CT_XML}, $doc);
    return 1 if ($self->_parseResponse($response));
    print "\nSolr response:\n" . Dumper($response);
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
#        attr1 => [value1, value2],
#        attr2 => [value3, value4]
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
                        my @fval_data = split(/;;/, $val);
                        foreach my $fval (@fval_data) {
                            push @$d, {name => $field, content => $fval} unless $field eq '_version_';
                        }
                    }
                } else {#only a single member in the list
                    my @fval_data = split(/;;/, $values);
                    foreach my $fval (@fval_data) {
                        push @$d, { name => $field, content => $fval} unless $field eq '_version_';
                    } 
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
                    my @fval_data = split(/;;/, $val);
                    foreach my $fval (@fval_data) {
                        push @$d, {name => $field, content => $fval} unless $field eq '_version_';
                    }
                }
            } else {#only a single member in the list
                my @fval_data = split(/;;/, $values);
                foreach my $fval (@fval_data) {
                    push @$d, { name => $field, content => $fval} unless $field eq '_version_'; 
                }
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
    
    if (!$self->_ping()) {
        die "\nError--Solr server not responding:\n" . $self->_error->{response};
    }
    
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
    
    if (!$self->_ping()) {
        die "\nError--Solr server not responding:\n" . $self->_error->{response};
    }
    
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
    my ($self, $solrCore, $solrKey, $searchId) = @_;
 
    if (!$self->_ping()) {
        die "\nError--Solr server not responding:\n" . $self->_error->{response};
    }
    
    my $url = $self->{_SOLR_URL}."/$solrCore/select?";
    $url = $url. "q=$solrKey:$searchId";
    
    my $response = $self->_sendRequest($url, 'GET');
    
    #print "\n$searchId:\n" . Dumper($response). "\n";

    my $status = $self->_parseResponse($response);
    if ($status == 1) {
        my $xs = new XML::Simple();
        my $xmlRef;
        eval {
            $xmlRef = $xs->XMLin($response->{response});
        };
        #print "\n$url result:\n" . Dumper($xmlRef->{result}) . "\n";
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
    #print "Pinging server: $self->{_SOLR_PING_URL}\n";
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
sub _checkGenomeStatus 
{
    my ($self, $current_genome, $solr_genomes) = @_;
    #print "\nChecking status for genome:\n " . Dumper($current_genome) . "\n";

    my $status = "";
    if (( ref($solr_genomes) eq 'ARRAY' && @{ $solr_genomes } == 0 ) || !defined($solr_genomes) )
    {
        $status = "New genome";
    }
    elsif ( ref($solr_genomes) eq 'ARRAY' )
    {
        for (my $i = 0; $i < @{ $solr_genomes }; $i++ ) {
            my $record = $solr_genomes->[$i];
            my $genome_id = $record->{genome_id};

            if ($genome_id eq $current_genome->{accession}){
                $status = "Existing genome: current";
                $current_genome->{genome_id} = $genome_id;
                last;
            }elsif ($genome_id =~/$current_genome->{id}/){
                $status = "Existing genome: updated ";
                $current_genome->{genome_id} = $genome_id;
                last;
            }
        }
        if( $status eq "" )
        {
            $status = "New genome";#"Existing genome: status unknown";
        }
    }

    if( $status eq "" )
    {
        $status = "Existing genome: status unknown";
    }
    #print "\nStatus:$status\n";
    return $status;
}

#Internal method, to fetch genome records for a given set of ws_ref's
#First call get_objects2() to get the genome object one at a time.
#Then plow through the genome object data to assemble the data items for a Solr genome_feature object.
#Finally send the data document to Solr for indexing.
#Input: a list of KBaseReferenceGenomeData
#Output: a list of SolrGenomeFeatureData
#
sub _indexGenomeFeatureData 
{
    my ($self, $solrCore, $gnData) = @_;
    my $wsgnrefs = [];

    foreach my $gn (@{$gnData}) {
        push @{$wsgnrefs}, {
            "ref" => $gn->{ref}
        };
    }

    my $gnout;
    my $solr_gnftData = [];
    my $gnft_batch = [];    
    my $g_count = 1;
    my $batchCount = 10000;

    #foreach my $wref (@{$wsgnrefs}) { 
    for( my $gf_i = 303; $gf_i < 500; $gf_i ++ ) {
        my $wref = $wsgnrefs->[$gf_i];
        print "\nStart to fetch the object(s) for "  . $gf_i . ". " . $wref->{ref} .  " on " . scalar localtime . "\n";
        eval {#return a reference to a list where each element is a Workspace.ObjectData with a key named 'data'
                $gnout = $self->util_ws_client()->get_objects2({
                        objects => [$wref] #$wsgnrefs #$wref
                }); #return a reference to a hash where key 'data' is defined as a list of Workspace.ObjectData
        };
        if($@) {
                print "Cannot get object information!\n";
                print "ERROR:".$@;
                if(defined($@->{status_line})) {
                    print $@->{status_line}."\n";
                }
        }
        print "Done getting the object(s) for " . $wref->{ref} . " on " . scalar localtime . "\n";
        #fetch individual data item to assemble the $solr_gnftData
        $gnout = $gnout -> {data};
        my $gn_data;
        my $gn_info; #to hold a value which is a Workspace.object_info
        my $gn_onterms ={};

        my $gn_features = {};
        my $gn_tax;           
        my $gn_aliases;    
        my $gn_nm;
        my $loc_contig;
        my $loc_begin;
        my $loc_end;
        my $loc_strand;
        my $gn_loc;
               
        my $numCDs = 0;
               
        for (my $i=0; $i < @{$gnout}; $i++) {
            $gn_data = $gnout -> [$i] -> {data};#an UnspecifiedObject
            $gn_info = $gnout -> [$i] -> {info};
            $gn_features = $gn_data->{features};
            $gn_tax = $gn_data->{taxonomy};
            $gn_tax =~s/ *; */;;/g;
                       
            $numCDs  = 0;
            foreach my $feature (@{$gn_features}) {
                $numCDs++ if $feature->{type} = 'CDS'; 
            }

            for (my $ii=0; $ii < @{$gn_features}; $ii++) {
                if( defined($gn_features->[$ii]->{aliases})) {
                    $gn_nm = $gn_features->[$ii]->{aliases}[0] unless $gn_features->[$ii]->{aliases}[0]=~/^(NP_|WP_|YP_|GI|GeneID)/i;  
                    $gn_aliases = join(";", @{$gn_features->[$ii]->{aliases}});
                    $gn_aliases =~s/ *; */;;/g;
                }
                else {
                    $gn_nm = undef;
                    $gn_aliases = undef;
                }
                my $gn_funcs = $gn_features->[$ii]->{function}; 
                $gn_funcs = join(";;", split(/\s*;\s+|\s+[\@\/]\s+/, $gn_funcs));

                $loc_contig = "";
                $loc_begin = 0;
                $loc_end = "";
                $loc_strand = "";
                $gn_loc = $gn_features->[$ii]->{location};
                my $end = 0;
                 
                foreach my $contig_loc (@{$gn_loc}) { 
                    $loc_contig = $loc_contig . ";;" unless $loc_contig eq "";
                    $loc_contig = $loc_contig . $contig_loc->[0]; 
                    
                    $loc_begin = $loc_begin . ";;" unless $loc_begin eq "";
                    $loc_begin = $loc_begin . $contig_loc->[1]; 
                             
                    if( $contig_loc->[2] eq "+") {
                        $end = $contig_loc->[1] + $contig_loc->[3];
                    } 
                    else {
                        $end = $contig_loc->[1] - $contig_loc->[3];
                    }
                    $loc_end = $loc_end . ";;" unless $loc_end eq "";
                    $loc_end = $loc_end . $end; 
                             
                    $loc_strand = $loc_strand . ";;" unless $loc_strand eq "";
                    $loc_strand = $loc_strand . $contig_loc->[2]; 
                }

                $gn_onterms = $gn_features->[$ii]->{ontology_terms};

                my $current_gnft = {
                          genome_feature_id => $gn_data->{id} . "_" . $gn_features->[$ii]->{id},
                          genome_id => $gn_data->{id},
                          ws_ref => $wref->{ref}, 
                          genome_source => $gn_data -> {source},
                          genetic_code => $gn_data -> {genetic_code},
                          domain => $gn_data -> {domain},
                          scientific_name => $gn_data -> {scientific_name},
                          genome_dna_size => $gn_data -> {dna_size},
                          num_contigs => $gn_data -> {num_contigs},
                          assembly_ref => $gn_data -> {assembly_ref},
                          gc_content => $gn_data -> {gc_content},
                          complete => $gn_data -> {complete},
                          taxonomy => $gn_tax,
                          workspace_name => $gn_info -> [7],
                          num_cds => $numCDs,
                          #feature data
                          feature_type => $gn_features->[$ii]->{type},
                          feature_id => $gn_features->[$ii]->{id},
                          functions => $gn_funcs,
                          md5 => $gn_features->[$ii]->{md5},
                          gene_name => $gn_nm, 
                          protein_translation_length => ($gn_features->[$ii]->{protein_translation_length}) != "" ? $gn_features->[$ii]->{protein_translation_length} : 0,
                          dna_sequence_length => ($gn_features->[$ii]->{dna_sequence_length}) != "" ? $gn_features->[$ii]->{dna_sequence_length} : 0,
                          aliases => $gn_aliases,
                          location_contig => $loc_contig,
                          location_strand => $loc_strand,
                          location_begin => $loc_begin,
                          location_end => $loc_end,
                          ontology_namespaces => $gn_features->[$ii]->{ontology_terms}
                };
                push @{$solr_gnftData}, $current_gnft;
                push @{$gnft_batch}, $current_gnft;
                if(@{$gnft_batch} >= $batchCount) {
                    eval {
                        $self->_indexInSolr($solrCore, $gnft_batch);
                    };
                    if($@) {
                        print "Failed to index the genome_feature(s)!\n";
                        print "ERROR:".$@;
                        if(defined($@->{status_line})) {
                            print $@->{status_line}."\n";
                        }
                    }
                    else {
                        print "\nIndexed " . @{$gnft_batch} . " genome_feature(s) on " . scalar localtime . "\n";
                        $gnft_batch = [];
                    }
                }
            }
            if(@{$gnft_batch} > 0) {
                eval {
                    $self->_indexInSolr($solrCore, $gnft_batch);
                };
                if($@) {
                    print "Failed to index the genome_feature(s)!\n";
                    print "ERROR:".$@;
                    if(defined($@->{status_line})) {
                        print $@->{status_line}."\n";
                    }
                }
                else {
                    print "\nIndexed " . @{$gnft_batch} . " genome_feature(s) on " . scalar localtime . "\n";
                    $gnft_batch = [];
                }
            }
        }
    }
    return $solr_gnftData;
}

#internal method, for fetching one taxon record to be indexed in solr
#
sub _getTaxon 
{
    my ($self, $taxonData, $wsref) = @_; 

    my $current_taxon = {
        taxonomy_id => $taxonData -> {taxonomy_id},
        scientific_name => $taxonData -> {scientific_name},
        scientific_lineage => $taxonData -> {scientific_lineage},
        rank => $taxonData -> {rank},
        kingdom => $taxonData -> {kingdom},
        domain => $taxonData -> {domain},
        ws_ref => $wsref,
        aliases => $taxonData -> {alias},
        genetic_code => ($taxonData -> {genetic_code}) ? ($taxonData -> {genetic_code}) : "0",
        parent_taxon_ref => $taxonData -> {parent_taxon_ref},
        embl_code => $taxonData -> {embl_code},
        inherited_div_flag => ($taxonData -> {inherited_div_flag}) ? $taxonData -> {inherited_div_flag} : "0",
        inherited_GC_flag => ($taxonData -> {inherited_GC_flag}) ? $taxonData -> {inherited_GC_flag} : "0",
        division_id => ($taxonData -> {division_id}) ? $taxonData -> {division_id} : "0",
        mitochondrial_genetic_code => ($taxonData -> {mitochondrial_genetic_code}) ? $taxonData -> {mitochondrial_genetic_code} : "0",
        inherited_MGC_flag => ($taxonData -> {inherited_MGC_flag}) ? ($taxonData -> {inherited_MGC_flag}) : "0",
        GenBank_hidden_flag => ($taxonData -> {GenBank_hidden_flag}) ? ($taxonData -> {GenBank_hidden_flag}) : "0",
        hidden_subtree_flag => ($taxonData -> {hidden_subtree_flag}) ? ($taxonData -> {hidden_subtree_flag}) : "0",
        comments => $taxonData -> {comments}
    };
    return $current_taxon;
}

#
#internal method, for sending doc data to SOLR 
#
sub _indexInSolr 
{
    my ($self, $solrCore, $docData) = @_; 
    if( @{$docData} >= 1) {
        eval {
            if( $self -> _addXML2Solr($solrCore, $docData) == 1 ) {
                #commit the additions
                if (!$self->_commit($solrCore)) {
                        print "\n Error: " . $self->_error->{response};
                }
            }
            else {
                print "\nIndexing failed: \n" . $self->{error}->{errmsg};
            }
        };
        if($@) {
            print "Error from SOLR indexing:\n" . $@;
            if(defined($@->{status_line})) {
                print $@->{status_line}."\n";
            }
        }
    }
}

#################### End methods for accessing SOLR #######################

sub _extract_ncbi_taxons {
    my $self=shift;
    my $ids_to_extract = shift;
    my $taxon_file_path=$self->{'scratch'}."/taxon_dump/";
    mkdir($taxon_file_path);
    chdir($taxon_file_path);
    system("curl -o taxdump.tar.gz ftp://ftp.ncbi.nlm.nih.gov/pub/taxonomy/taxdump.tar.gz");
    system("tar -zxf taxdump.tar.gz");

    open(my $fh, "< ${taxon_file_path}nodes.dmp");
    my $taxon_objects={};
    while(<$fh>){
	chomp;
	my @temp=split(/\s*\|\s*/,$_,-1);
	next if defined($ids_to_extract) && !exists($ids_to_extract->{$temp[0]});
	my $object = {'taxonomy_id'=>$temp[0]+0,
		      'parent_taxon_id'=>$temp[1]+0,
		      'rank'=>$temp[2],
		      'embl_code'=>$temp[3],
		      'division_id'=>$temp[4]+0,
		      'inherited_div_flag'=>$temp[5]+0,
		      'genetic_code'=>$temp[6]+0,
		      'inherited_GC_flag'=>$temp[7]+0,
		      'mitochondrial_genetic_code'=>$temp[8]+0,
		      'inherited_MGC_flag'=>$temp[9]+0,
		      'GenBank_hidden_flag'=>$temp[10]+0,
		      'hidden_substree_root_flag'=>$temp[11],
		      'comments'=>$temp[12],
		      'domain'=>"Unknown",
		      'scientific_name'=>"",
		      'scientific_lineage'=>"",
		      'aliases'=>[]};

	$taxon_objects->{$temp[0]}=$object;
    }
    close($fh);

    open(my $fh, "< ${taxon_file_path}names.dmp");
    while(<$fh>){
	chomp;
	my @temp=split(/\s*\|\s*/,$_,-1);
	if(exists($taxon_objects->{$temp[0]})){
	    if($temp[3] eq "scientific name"){
		$taxon_objects->{$temp[0]}{"scientific_name"}=$temp[1];
	    }else{
		push(@{$taxon_objects->{$temp[0]}{"aliases"}},$temp[1]);
	    }
	}
    }
    close($fh);

    #Iterate through to make lineage, need to determine "level" of each object so to sort properly before loading
    my %taxon_level=();
    foreach my $obj ( map { $taxon_objects->{$_} } sort { $a <=> $b } keys %$taxon_objects ){
	$obj->{"scientific_lineage"} = _make_lineage($obj->{"taxonomy_id"},$taxon_objects);

	#Determine Domain
	foreach my $domain ("Eukaryota","Bacteria","Viruses","Archaea"){
	    if($obj->{"scientific_lineage"} =~ /${domain}/){
		$obj->{"domain"}=$domain;
		last;
	    }
	}

	#Determine Kingdom
	foreach my $kingdom ("Fungi","Viridiplantae","Metazoa"){
	    if($obj->{"domain"} eq "Eukaryota" && $obj->{"scientific_lineage"} =~ /${kingdom}/){
		$obj->{"kingdom"}=$kingdom;
		last;
	    }
	}
	
	my $level = scalar( split(/;\s/,$obj->{"scientific_lineage"}) );
	$taxon_level{$level}{$obj->{"taxonomy_id"}}=1;
    }

    my $taxon_objs=[];
    foreach my $level ( sort { $a <=> $b } keys %taxon_level ){
	foreach my $obj ( map { $taxon_objects->{$_} } sort { $a <=> $b } keys %{$taxon_level{$level}} ){
	    delete $obj->{"parent_taxon_id"} if $obj->{"taxonomy_id"} == 1;
	    push(@$taxon_objs,$obj);
	}
    }
    return $taxon_objs;
}

sub _make_lineage {
    my ($taxon_id,$taxon_objects)=@_;
    return "" if $taxon_id == 1;
    my @lineages=();
    if(exists($taxon_objects->{$taxon_id}) && exists($taxon_objects->{$taxon_id}{"parent_taxon_id"})){
	my $parent_taxon_id=$taxon_objects->{$taxon_id}{"parent_taxon_id"};
	while($parent_taxon_id > 1){
	    if(exists($taxon_objects->{$parent_taxon_id}{"scientific_name"}) && $taxon_objects->{$parent_taxon_id}{"scientific_name"} ne ""){
		unshift(@lineages,$taxon_objects->{$parent_taxon_id}{"scientific_name"});
	    }
	    if(exists($taxon_objects->{$parent_taxon_id}{"parent_taxon_id"})){
		$parent_taxon_id=$taxon_objects->{$parent_taxon_id}{"parent_taxon_id"};
	    }else{
		$parent_taxon_id = 0;
	    }
	}
    }
    return join("; ",@lineages);
}

sub _check_taxon {
    my $self=shift;
    my ($taxon,$taxon_list) = @_;
    my %taxon_hash = map { $_->{'taxonomy_id'} => $_ } @$taxon_list;

    my @Mismatches=();
    if(!exists($taxon_hash{$taxon->{'taxonomy_id'}})){
	push(@Mismatches,"Taxon ".$taxon->{'taxonomy_id'}." not found");
    }else{
	my @Fields_to_Check = ('parent_taxon_ref','rank','domain','scientific_name','scientific_lineage');
	my $current_taxon = $taxon_hash{$taxon->{'taxonomy_id'}};
	foreach my $field (@Fields_to_Check){
	    if($field eq 'parent_taxon_ref'){
		my $parent_taxon = undef;
		$parent_taxon = $current_taxon->{'parent_taxon_ref'} if exists $current_taxon->{'parent_taxon_ref'};
		if(defined($parent_taxon)){
		    if(!defined($taxon->{'parent_taxon_id'})){
			push(@Mismatches,"Taxon ".$taxon->{'taxonomy_id'}." does not contain parent taxon, but current taxon does");
		    }else{
			$parent_taxon = $self->{_wsclient}->get_objects2({objects=>[{"ref" => $parent_taxon}],ignoreErrors=>1})->{data};
			if(scalar(@$parent_taxon)){
			    $parent_taxon=$parent_taxon->[0]{data};
			}else{
			    push(@Mismatches,"Taxon ".$taxon->{'taxonomy_id'}." and current taxon contain parent taxon, but cannot retrieve current parent taxon");
			}
			if($parent_taxon->{'taxonomy_id'} != $taxon->{'parent_taxon_id'}){
			    push(@Mismatches,"Taxon ".$taxon->{'taxonomy_id'}." parent taxon id does not match current parent taxon id");
			}
		    }
		}elsif(defined($taxon->{'parent_taxon_id'})){
		    push(@Mismatches,"Taxon ".$taxon->{'taxonomy_id'}." does contains parent taxon, but current taxon does not");
		}
	    }else{
		if($current_taxon->{$field} ne $taxon->{$field}){
		    push(@Mismatches,"Taxon ".$taxon->{'taxonomy_id'}." field $field does not match current value");
		}
	    }
	}
    }
    return \@Mismatches;
}

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
        refseq => "RefSeq_Genomes"
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
    my $batch_count = 1000;
    my $sources = ["ensembl","phytozome","refseq"];
    for (my $i=0; $i < @{$sources}; $i++) {
        if ($params->{$sources->[$i]} == 1) {
            my $wsname = $self->util_workspace_names($sources->[$i]);
            my $wsinfo;
            my $wsoutput;
            if(defined($self->util_ws_client())){
                $wsinfo = $self->util_ws_client()->get_workspace_info({
                    workspace => $wsname
                });
            }
            my $maxid = $wsinfo->[4];
            my $pages = ceil($maxid/$batch_count);
            print "\nMax genome object id=$maxid\n";
        
            try {
                for (my $m = 0; $m < $pages; $m++) {
                   eval {
                        $wsoutput = $self->util_ws_client()->list_objects({
                          workspaces => [$wsname],
                          type => "KBaseGenomes.Genome-8.0",
                          minObjectID => $batch_count * $m,
                          maxObjectID => $batch_count * ( $m + 1)
                        });
                    };
                    if($@) {
                        print "Cannot list objects!\n";
                        print "ERROR:" . $@;#->{message}."\n";
                        if(defined($@->{status_line})) {
                            print "ERROR:" . $@->{status_line}."\n"; 
                        }
                    }
                    print "\nTotal genome object count=" . @{$wsoutput}. "\n";
                    if( @{$wsoutput} > 0 ) {
                        for (my $j=0; $j < @{$wsoutput}; $j++) {
                            push @{$output}, {
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
                                gc => $wsoutput->[$j]->[10]->{"GC content"}
                            };
                        
                            if (@{$output} < 10) {
                                my $curr = @{$output}-1;
                                $msg .= Data::Dumper->Dump([$output->[$curr]])."\n";
                            } 
                        }
                    }
                }
            }    
            catch { 
                warn "Got an exception from calling get_objects2 or solr connection\n $_";
            }   
            finally {
                if (@_) {
                        print "The trying to call get_objects2 or solr connection died with:\n" . Dumper( @_) . "\n";
                }
            };
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




=head2 list_solr_genomes

  $output = $obj->list_solr_genomes($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a ReferenceDataManager.ListSolrDocsParams
$output is a reference to a list where each element is a ReferenceDataManager.SolrGenomeFeatureData
ListSolrDocsParams is a reference to a hash where the following keys are defined:
	solr_core has a value which is a string
	row_start has a value which is an int
	row_count has a value which is an int
	create_report has a value which is a ReferenceDataManager.bool
bool is an int
SolrGenomeFeatureData is a reference to a hash where the following keys are defined:
	genome_feature_id has a value which is a string
	genome_id has a value which is a string
	feature_id has a value which is a string
	ws_ref has a value which is a string
	feature_type has a value which is a string
	aliases has a value which is a string
	scientific_name has a value which is a string
	domain has a value which is a string
	functions has a value which is a string
	genome_source has a value which is a string
	go_ontology_description has a value which is a string
	go_ontology_domain has a value which is a string
	gene_name has a value which is a string
	object_name has a value which is a string
	location_contig has a value which is a string
	location_strand has a value which is a string
	taxonomy has a value which is a string
	workspace_name has a value which is a string
	genetic_code has a value which is a string
	md5 has a value which is a string
	tax_id has a value which is a string
	assembly_ref has a value which is a string
	taxonomy_ref has a value which is a string
	ontology_namespaces has a value which is a string
	ontology_ids has a value which is a string
	ontology_names has a value which is a string
	ontology_lineages has a value which is a string
	dna_sequence_length has a value which is an int
	genome_dna_size has a value which is an int
	location_begin has a value which is an int
	location_end has a value which is an int
	num_cds has a value which is an int
	num_contigs has a value which is an int
	protein_translation_length has a value which is an int
	gc_content has a value which is a float
	complete has a value which is a ReferenceDataManager.bool

</pre>

=end html

=begin text

$params is a ReferenceDataManager.ListSolrDocsParams
$output is a reference to a list where each element is a ReferenceDataManager.SolrGenomeFeatureData
ListSolrDocsParams is a reference to a hash where the following keys are defined:
	solr_core has a value which is a string
	row_start has a value which is an int
	row_count has a value which is an int
	create_report has a value which is a ReferenceDataManager.bool
bool is an int
SolrGenomeFeatureData is a reference to a hash where the following keys are defined:
	genome_feature_id has a value which is a string
	genome_id has a value which is a string
	feature_id has a value which is a string
	ws_ref has a value which is a string
	feature_type has a value which is a string
	aliases has a value which is a string
	scientific_name has a value which is a string
	domain has a value which is a string
	functions has a value which is a string
	genome_source has a value which is a string
	go_ontology_description has a value which is a string
	go_ontology_domain has a value which is a string
	gene_name has a value which is a string
	object_name has a value which is a string
	location_contig has a value which is a string
	location_strand has a value which is a string
	taxonomy has a value which is a string
	workspace_name has a value which is a string
	genetic_code has a value which is a string
	md5 has a value which is a string
	tax_id has a value which is a string
	assembly_ref has a value which is a string
	taxonomy_ref has a value which is a string
	ontology_namespaces has a value which is a string
	ontology_ids has a value which is a string
	ontology_names has a value which is a string
	ontology_lineages has a value which is a string
	dna_sequence_length has a value which is an int
	genome_dna_size has a value which is an int
	location_begin has a value which is an int
	location_end has a value which is an int
	num_cds has a value which is an int
	num_contigs has a value which is an int
	protein_translation_length has a value which is an int
	gc_content has a value which is a float
	complete has a value which is a ReferenceDataManager.bool


=end text



=item Description

Lists genomes indexed in SOLR

=back

=cut

sub list_solr_genomes
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to list_solr_genomes:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'list_solr_genomes');
    }

    my $ctx = $ReferenceDataManager::ReferenceDataManagerServer::CallContext;
    my($output);
    #BEGIN list_solr_genomes
    $params = $self->util_initialize_call($params,$ctx);
    $params = $self->util_args($params,[],{
        solr_core => "taxonomy_ci",
        row_start => 0,
        row_count => 10,
        create_report => 0
    });

    $output = [];
    my $msg = "";
    my $solrout;
    my $solrCore = $params -> {solr_core};
    my $fields = "*";
    my $startRow = $params -> {row_start};
    my $topRows = $params -> {row_count};
    
    eval {
        $solrout = $self->_listGenomesInSolr($solrCore, $fields, $startRow, $topRows);
    };
    if($@) {
        print "Cannot list genomes in SOLR information!\n";
        print "ERROR:".$@;
        if(defined($@->{status_line})) {
            print $@->{status_line}."\n";
        }
    }
    else {
        print "\nList of genomes: \n" . Dumper($solrout) . "\n";  
        $output = $solrout->{response}->{docs}; 
        
        if (@{$output} < 10) {
            my $curr = @{$output}-1;
            $msg .= Data::Dumper->Dump([$output->[$curr]])."\n";
        } 
    }

    #END list_solr_genomes
    my @_bad_returns;
    (ref($output) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to list_solr_genomes:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'list_solr_genomes');
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
     
        my $wsname = "";
        if(defined( $genome->{workspace_name}))
        {
            $wsname = $genome->{workspace_name};
        }
        elsif(defined($genome->{source}))
        {
            $wsname = $self->util_workspace_names($genome->{source});   
        }
        
        print "\nNow loading ".$genome->{id}." with loader url=".$ENV{ SDK_CALLBACK_URL }."\n";
     
        if ($genome->{source} eq "refseq" || $genome->{source} eq "") {
            my $genutilout;
            my $genomeout;
            try {
                $genutilout = $loader->genbank_to_genome({
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
                $genomeout = {
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
                    $self->index_genomes_in_solr({
                        genomes => [$genomeout]
                    });
                }
            }
            catch { 
                warn "Got an exception from calling genbank_to_genome:\n $_";
                $genomeout = {};
            }
            finally {
                if (@_) {
                    print "The trying to call genbank_to_genome died with: @_\n";
                }
            };
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
        print "Loaded ". scalar @{$output}. " genomes!\n";
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
$output is a reference to a list where each element is a ReferenceDataManager.SolrGenomeFeatureData
IndexGenomesInSolrParams is a reference to a hash where the following keys are defined:
	genomes has a value which is a reference to a list where each element is a ReferenceDataManager.KBaseReferenceGenomeData
	workspace_name has a value which is a string
	solr_core has a value which is a string
	create_report has a value which is a ReferenceDataManager.bool
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
SolrGenomeFeatureData is a reference to a hash where the following keys are defined:
	genome_feature_id has a value which is a string
	genome_id has a value which is a string
	feature_id has a value which is a string
	ws_ref has a value which is a string
	feature_type has a value which is a string
	aliases has a value which is a string
	scientific_name has a value which is a string
	domain has a value which is a string
	functions has a value which is a string
	genome_source has a value which is a string
	go_ontology_description has a value which is a string
	go_ontology_domain has a value which is a string
	gene_name has a value which is a string
	object_name has a value which is a string
	location_contig has a value which is a string
	location_strand has a value which is a string
	taxonomy has a value which is a string
	workspace_name has a value which is a string
	genetic_code has a value which is a string
	md5 has a value which is a string
	tax_id has a value which is a string
	assembly_ref has a value which is a string
	taxonomy_ref has a value which is a string
	ontology_namespaces has a value which is a string
	ontology_ids has a value which is a string
	ontology_names has a value which is a string
	ontology_lineages has a value which is a string
	dna_sequence_length has a value which is an int
	genome_dna_size has a value which is an int
	location_begin has a value which is an int
	location_end has a value which is an int
	num_cds has a value which is an int
	num_contigs has a value which is an int
	protein_translation_length has a value which is an int
	gc_content has a value which is a float
	complete has a value which is a ReferenceDataManager.bool

</pre>

=end html

=begin text

$params is a ReferenceDataManager.IndexGenomesInSolrParams
$output is a reference to a list where each element is a ReferenceDataManager.SolrGenomeFeatureData
IndexGenomesInSolrParams is a reference to a hash where the following keys are defined:
	genomes has a value which is a reference to a list where each element is a ReferenceDataManager.KBaseReferenceGenomeData
	workspace_name has a value which is a string
	solr_core has a value which is a string
	create_report has a value which is a ReferenceDataManager.bool
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
SolrGenomeFeatureData is a reference to a hash where the following keys are defined:
	genome_feature_id has a value which is a string
	genome_id has a value which is a string
	feature_id has a value which is a string
	ws_ref has a value which is a string
	feature_type has a value which is a string
	aliases has a value which is a string
	scientific_name has a value which is a string
	domain has a value which is a string
	functions has a value which is a string
	genome_source has a value which is a string
	go_ontology_description has a value which is a string
	go_ontology_domain has a value which is a string
	gene_name has a value which is a string
	object_name has a value which is a string
	location_contig has a value which is a string
	location_strand has a value which is a string
	taxonomy has a value which is a string
	workspace_name has a value which is a string
	genetic_code has a value which is a string
	md5 has a value which is a string
	tax_id has a value which is a string
	assembly_ref has a value which is a string
	taxonomy_ref has a value which is a string
	ontology_namespaces has a value which is a string
	ontology_ids has a value which is a string
	ontology_names has a value which is a string
	ontology_lineages has a value which is a string
	dna_sequence_length has a value which is an int
	genome_dna_size has a value which is an int
	location_begin has a value which is an int
	location_end has a value which is an int
	num_cds has a value which is an int
	num_contigs has a value which is an int
	protein_translation_length has a value which is an int
	gc_content has a value which is a float
	complete has a value which is a ReferenceDataManager.bool


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
    if (! $self->_ping()) {
        die "\nError--Solr server not responding:\n" . $self->_error->{response};
    }
    $params = $self->util_initialize_call($params,$ctx);
    $params = $self->util_args($params,[],{
        genomes => {},
        create_report => 0,
        solr_core => "QZtest"
    });
 
    my $msg = "";
    $output = [];
    my $genomes = $params->{genomes};
    my $solrCore = $params->{solr_core}; 
    print "\nTotal genomes to be indexed: ". @{$genomes} . "\n";

    my $solr_ret = $self->_indexGenomeFeatureData($solrCore, $genomes);
    push(@{$output}, $solr_ret);   
    if (@{$output} < 10) {
            my $curr = @{$output}-1;
            $msg .= Data::Dumper->Dump([$output->[$curr]])."\n";
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




=head2 list_loaded_taxa

  $output = $obj->list_loaded_taxa($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a ReferenceDataManager.ListLoadedTaxaParams
$output is a reference to a list where each element is a ReferenceDataManager.LoadedReferenceTaxonData
ListLoadedTaxaParams is a reference to a hash where the following keys are defined:
	workspace_name has a value which is a string
	create_report has a value which is a ReferenceDataManager.bool
bool is an int
LoadedReferenceTaxonData is a reference to a hash where the following keys are defined:
	taxon has a value which is a ReferenceDataManager.KBaseReferenceTaxonData
	ws_ref has a value which is a string
KBaseReferenceTaxonData is a reference to a hash where the following keys are defined:
	taxonomy_id has a value which is an int
	scientific_name has a value which is a string
	scientific_lineage has a value which is a string
	rank has a value which is a string
	kingdom has a value which is a string
	domain has a value which is a string
	aliases has a value which is a reference to a list where each element is a string
	genetic_code has a value which is an int
	parent_taxon_ref has a value which is a string
	embl_code has a value which is a string
	inherited_div_flag has a value which is an int
	inherited_GC_flag has a value which is an int
	mitochondrial_genetic_code has a value which is an int
	inherited_MGC_flag has a value which is an int
	GenBank_hidden_flag has a value which is an int
	hidden_subtree_flag has a value which is an int
	division_id has a value which is an int
	comments has a value which is a string

</pre>

=end html

=begin text

$params is a ReferenceDataManager.ListLoadedTaxaParams
$output is a reference to a list where each element is a ReferenceDataManager.LoadedReferenceTaxonData
ListLoadedTaxaParams is a reference to a hash where the following keys are defined:
	workspace_name has a value which is a string
	create_report has a value which is a ReferenceDataManager.bool
bool is an int
LoadedReferenceTaxonData is a reference to a hash where the following keys are defined:
	taxon has a value which is a ReferenceDataManager.KBaseReferenceTaxonData
	ws_ref has a value which is a string
KBaseReferenceTaxonData is a reference to a hash where the following keys are defined:
	taxonomy_id has a value which is an int
	scientific_name has a value which is a string
	scientific_lineage has a value which is a string
	rank has a value which is a string
	kingdom has a value which is a string
	domain has a value which is a string
	aliases has a value which is a reference to a list where each element is a string
	genetic_code has a value which is an int
	parent_taxon_ref has a value which is a string
	embl_code has a value which is a string
	inherited_div_flag has a value which is an int
	inherited_GC_flag has a value which is an int
	mitochondrial_genetic_code has a value which is an int
	inherited_MGC_flag has a value which is an int
	GenBank_hidden_flag has a value which is an int
	hidden_subtree_flag has a value which is an int
	division_id has a value which is an int
	comments has a value which is a string


=end text



=item Description

Lists taxa loaded into KBase for a given workspace

=back

=cut

sub list_loaded_taxa
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to list_loaded_taxa:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'list_loaded_taxa');
    }

    my $ctx = $ReferenceDataManager::ReferenceDataManagerServer::CallContext;
    my($output);
    #BEGIN list_loaded_taxa
    $params = $self->util_initialize_call($params,$ctx);    
    $params = $self->util_args($params,[],{
        create_report => 0,
        workspace_name => undef
    });
    my $msg = "";
    my $output = [];

    my $wsname = $params ->{workspace_name}; #'ReferenceTaxons';
    my $wsinfo;
    my $wsoutput;
    my $taxonout;
    if(defined($self->util_ws_client())){
        $wsinfo = $self->util_ws_client()->get_workspace_info({
            workspace => $wsname
        });
    }

    my $batch_count = 1000;
    my $maxid = $wsinfo->[4];
    my $pages = ceil($maxid/$batch_count);

    print "\nFound $maxid taxon objects.\n";
    print "\nPaging through $pages of $batch_count objects\n";
    try {
        for (my $m = 1313; $m < 1316; $m++) {
            print "\nBatch ". $m . "x$batch_count";# on " . scalar localtime;
            eval { 
                    $wsoutput = $self->util_ws_client()->list_objects({
                        workspaces => [$wsname],
                        type => "KBaseGenomeAnnotations.Taxon-1.0",
                        minObjectID => $batch_count * $m,
                        maxObjectID => $batch_count * ( $m + 1)
                    });
            };
            if($@) {
                print "Cannot list objects!\n";
                print "ERROR:" . $@;#->{message}."\n";
                if(defined($@->{status_line})) {
                        print "ERROR:" . $@->{status_line}."\n"; 
                }
            }
            if( @{$wsoutput} > 0 ) { 
                my $wstaxonrefs = [];
                for (my $j=0; $j < @{$wsoutput}; $j++) {
                        push(@{$wstaxonrefs},{
                                "ref" => $wsoutput->[$j]->[6]."/".$wsoutput->[$j]->[0]."/".$wsoutput->[$j]->[4]
                        });
                }       

                print "\nStart to fetch the objects at the batch size of: " . @{$wstaxonrefs} . " on " . scalar localtime; 
                eval {
                        $taxonout = $self->util_ws_client()->get_objects2({
                                objects => $wstaxonrefs
                        }); #return a reference to a hash where key 'data' is defined as a list of Workspace.ObjectData
                };
                if($@) {
                        print "Cannot get object information!\n";
                        print "ERROR:".$@;
                        if(defined($@->{status_line})) {
                                print $@->{status_line}."\n";
                        }
               }
               print "\nDone getting the objects at the batch size of: " . @{$wstaxonrefs} . " on " . scalar localtime . "\n";
               $taxonout = $taxonout -> {data};
               my $taxon_ret = [];
               for (my $i=0; $i < @{$taxonout}; $i++) {
                       my $taxonData = $taxonout -> [$i] -> {data};#an UnspecifiedObject
                       push(@{$output}, {taxon => $taxonData, ws_ref => $wstaxonrefs -> [$i] -> {ref}});
                       if (@{$output} < 10) {
                               my $curr = @{$output}-1;
                               $msg .= Data::Dumper->Dump([$output->[$curr]])."\n";
                       } 
              
                       push(@{$taxon_ret}, {taxon => $taxonData, ws_ref => $wstaxonrefs -> [$i] -> {ref}});
               }
               $self->index_taxa_in_solr({ 
                       taxa => $taxon_ret,
                       solr_core => "taxonomy_ci",
                       create_report => 0
               });
            }
         }  
    }    
    catch { 
        warn "Got an exception from calling get_objects2 or solr connection\n $_";
    }   
    finally {
       if (@_) {
          print "The trying to call get_objects2 or solr connection died with:\n" . Dumper( @_) . "\n";
       }
    };
  
    #END list_loaded_taxa
    my @_bad_returns;
    (ref($output) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to list_loaded_taxa:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'list_loaded_taxa');
    }
    return($output);
}




=head2 list_solr_taxa

  $output = $obj->list_solr_taxa($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a ReferenceDataManager.ListSolrDocsParams
$output is a reference to a list where each element is a ReferenceDataManager.SolrTaxonData
ListSolrDocsParams is a reference to a hash where the following keys are defined:
	solr_core has a value which is a string
	row_start has a value which is an int
	row_count has a value which is an int
	create_report has a value which is a ReferenceDataManager.bool
bool is an int
SolrTaxonData is a reference to a hash where the following keys are defined:
	taxonomy_id has a value which is an int
	scientific_name has a value which is a string
	scientific_lineage has a value which is a string
	rank has a value which is a string
	kingdom has a value which is a string
	domain has a value which is a string
	ws_ref has a value which is a string
	aliases has a value which is a reference to a list where each element is a string
	genetic_code has a value which is an int
	parent_taxon_ref has a value which is a string
	embl_code has a value which is a string
	inherited_div_flag has a value which is an int
	inherited_GC_flag has a value which is an int
	mitochondrial_genetic_code has a value which is an int
	inherited_MGC_flag has a value which is an int
	GenBank_hidden_flag has a value which is an int
	hidden_subtree_flag has a value which is an int
	division_id has a value which is an int
	comments has a value which is a string

</pre>

=end html

=begin text

$params is a ReferenceDataManager.ListSolrDocsParams
$output is a reference to a list where each element is a ReferenceDataManager.SolrTaxonData
ListSolrDocsParams is a reference to a hash where the following keys are defined:
	solr_core has a value which is a string
	row_start has a value which is an int
	row_count has a value which is an int
	create_report has a value which is a ReferenceDataManager.bool
bool is an int
SolrTaxonData is a reference to a hash where the following keys are defined:
	taxonomy_id has a value which is an int
	scientific_name has a value which is a string
	scientific_lineage has a value which is a string
	rank has a value which is a string
	kingdom has a value which is a string
	domain has a value which is a string
	ws_ref has a value which is a string
	aliases has a value which is a reference to a list where each element is a string
	genetic_code has a value which is an int
	parent_taxon_ref has a value which is a string
	embl_code has a value which is a string
	inherited_div_flag has a value which is an int
	inherited_GC_flag has a value which is an int
	mitochondrial_genetic_code has a value which is an int
	inherited_MGC_flag has a value which is an int
	GenBank_hidden_flag has a value which is an int
	hidden_subtree_flag has a value which is an int
	division_id has a value which is an int
	comments has a value which is a string


=end text



=item Description

Lists taxa indexed in SOLR

=back

=cut

sub list_solr_taxa
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to list_solr_taxa:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'list_solr_taxa');
    }

    my $ctx = $ReferenceDataManager::ReferenceDataManagerServer::CallContext;
    my($output);
    #BEGIN list_solr_taxa
    $params = $self->util_initialize_call($params,$ctx);
    $params = $self->util_args($params,[],{
        solr_core => "taxonomy_ci",
        row_start => 0,
        row_count => 10,
        create_report => 0
    });

    my $msg = "";
    $output = [];
    my $solrout;
    my $solrCore = $params -> {solr_core};
    my $fields = "*";
    my $startRow = $params -> {row_start};
    my $topRows = $params -> {row_count};
    
    eval {
        $solrout = $self->_listTaxaInSolr($solrCore, $fields, $startRow, $topRows);
    };
    if($@) {
        print "Cannot list taxa in SOLR information!\n";
        print "ERROR:".$@;
        if(defined($@->{status_line})) {
            print $@->{status_line}."\n";
        }
    }
    else {
        print "\nList of taxa: \n" . Dumper($solrout) . "\n";  
        $output = $solrout->{response}->{docs}; 
        
        if (@{$output} < 10) {
            my $curr = @{$output}-1;
            $msg .= Data::Dumper->Dump([$output->[$curr]])."\n";
        } 
    }
    #END list_solr_taxa
    my @_bad_returns;
    (ref($output) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to list_solr_taxa:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'list_solr_taxa');
    }
    return($output);
}




=head2 load_taxons

  $output = $obj->load_taxons($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a ReferenceDataManager.LoadTaxonsParams
$output is a reference to a list where each element is a ReferenceDataManager.ReferenceTaxonData
LoadTaxonsParams is a reference to a hash where the following keys are defined:
	data has a value which is a string
	taxons has a value which is a reference to a list where each element is a ReferenceDataManager.ReferenceTaxonData
	index_in_solr has a value which is a ReferenceDataManager.bool
	workspace_name has a value which is a string
	create_report has a value which is a ReferenceDataManager.bool
ReferenceTaxonData is a reference to a hash where the following keys are defined:
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

$params is a ReferenceDataManager.LoadTaxonsParams
$output is a reference to a list where each element is a ReferenceDataManager.ReferenceTaxonData
LoadTaxonsParams is a reference to a hash where the following keys are defined:
	data has a value which is a string
	taxons has a value which is a reference to a list where each element is a ReferenceDataManager.ReferenceTaxonData
	index_in_solr has a value which is a ReferenceDataManager.bool
	workspace_name has a value which is a string
	create_report has a value which is a ReferenceDataManager.bool
ReferenceTaxonData is a reference to a hash where the following keys are defined:
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

Loads specified genomes into KBase workspace and indexes in SOLR on demand

=back

=cut

sub load_taxons
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to load_taxons:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'load_taxons');
    }

    my $ctx = $ReferenceDataManager::ReferenceDataManagerServer::CallContext;
    my($output);
    #BEGIN load_taxons
    $params = $self->util_initialize_call($params,$ctx);
    $params = $self->util_args($params,[],{
    	data => undef,
    	taxons => [],
        index_in_solr => 0,
        create_report => 0,
    	workspace_name => undef
    });

    my $ncbi_taxon_objs = $self->_extract_ncbi_taxons();

    my $Taxon_WS = "Taxon_Test"; #ReferenceTaxons
    my $loaded_taxon_objs = $self->list_loaded_taxa({workspace_name=>$Taxon_WS});

    my $taxon_provenance = [{"script"=>$0, "script_ver"=>"0.1", "description"=>"Taxon generated from NCBI taxonomy names and nodes files downloaded on 10/20/2016."}];
    foreach my $obj (@$ncbi_taxon_objs){
	$self->_check_taxon($obj,$loaded_taxon_objs);

	$obj->{'parent_taxon_ref'}=$Taxon_WS."/".$obj->{'parent_taxon_id'}."_taxon";
	delete $obj->{'parent_taxon_ref'} if $obj->{'taxonomy_id'}==1;
	delete $obj->{'parent_taxon_id'};

	my $taxon_name = $obj->{"taxonomy_id"}."_taxon";
	print "Loading $taxon_name\n";
	$obj->{"taxonomy_id"}+=0;
	$self->{_wsclient}->save_objects({"workspace"=>$Taxon_WS,"objects"=>[ {"type"=>"KBaseGenomeAnnotations.Taxon",
									       "data"=>$obj, 
									       "name"=>$taxon_name,
									       "provenance"=>$taxon_provenance}] });
	push(@$output, $self->getTaxon($obj, $Taxon_WS."/".$taxon_name));
    }
    #END load_taxons
    my @_bad_returns;
    (ref($output) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to load_taxons:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'load_taxons');
    }
    return($output);
}




=head2 index_taxa_in_solr

  $output = $obj->index_taxa_in_solr($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a ReferenceDataManager.IndexTaxaInSolrParams
$output is a reference to a list where each element is a ReferenceDataManager.SolrTaxonData
IndexTaxaInSolrParams is a reference to a hash where the following keys are defined:
	taxa has a value which is a reference to a list where each element is a ReferenceDataManager.LoadedReferenceTaxonData
	solr_core has a value which is a string
	create_report has a value which is a ReferenceDataManager.bool
LoadedReferenceTaxonData is a reference to a hash where the following keys are defined:
	taxon has a value which is a ReferenceDataManager.KBaseReferenceTaxonData
	ws_ref has a value which is a string
KBaseReferenceTaxonData is a reference to a hash where the following keys are defined:
	taxonomy_id has a value which is an int
	scientific_name has a value which is a string
	scientific_lineage has a value which is a string
	rank has a value which is a string
	kingdom has a value which is a string
	domain has a value which is a string
	aliases has a value which is a reference to a list where each element is a string
	genetic_code has a value which is an int
	parent_taxon_ref has a value which is a string
	embl_code has a value which is a string
	inherited_div_flag has a value which is an int
	inherited_GC_flag has a value which is an int
	mitochondrial_genetic_code has a value which is an int
	inherited_MGC_flag has a value which is an int
	GenBank_hidden_flag has a value which is an int
	hidden_subtree_flag has a value which is an int
	division_id has a value which is an int
	comments has a value which is a string
bool is an int
SolrTaxonData is a reference to a hash where the following keys are defined:
	taxonomy_id has a value which is an int
	scientific_name has a value which is a string
	scientific_lineage has a value which is a string
	rank has a value which is a string
	kingdom has a value which is a string
	domain has a value which is a string
	ws_ref has a value which is a string
	aliases has a value which is a reference to a list where each element is a string
	genetic_code has a value which is an int
	parent_taxon_ref has a value which is a string
	embl_code has a value which is a string
	inherited_div_flag has a value which is an int
	inherited_GC_flag has a value which is an int
	mitochondrial_genetic_code has a value which is an int
	inherited_MGC_flag has a value which is an int
	GenBank_hidden_flag has a value which is an int
	hidden_subtree_flag has a value which is an int
	division_id has a value which is an int
	comments has a value which is a string

</pre>

=end html

=begin text

$params is a ReferenceDataManager.IndexTaxaInSolrParams
$output is a reference to a list where each element is a ReferenceDataManager.SolrTaxonData
IndexTaxaInSolrParams is a reference to a hash where the following keys are defined:
	taxa has a value which is a reference to a list where each element is a ReferenceDataManager.LoadedReferenceTaxonData
	solr_core has a value which is a string
	create_report has a value which is a ReferenceDataManager.bool
LoadedReferenceTaxonData is a reference to a hash where the following keys are defined:
	taxon has a value which is a ReferenceDataManager.KBaseReferenceTaxonData
	ws_ref has a value which is a string
KBaseReferenceTaxonData is a reference to a hash where the following keys are defined:
	taxonomy_id has a value which is an int
	scientific_name has a value which is a string
	scientific_lineage has a value which is a string
	rank has a value which is a string
	kingdom has a value which is a string
	domain has a value which is a string
	aliases has a value which is a reference to a list where each element is a string
	genetic_code has a value which is an int
	parent_taxon_ref has a value which is a string
	embl_code has a value which is a string
	inherited_div_flag has a value which is an int
	inherited_GC_flag has a value which is an int
	mitochondrial_genetic_code has a value which is an int
	inherited_MGC_flag has a value which is an int
	GenBank_hidden_flag has a value which is an int
	hidden_subtree_flag has a value which is an int
	division_id has a value which is an int
	comments has a value which is a string
bool is an int
SolrTaxonData is a reference to a hash where the following keys are defined:
	taxonomy_id has a value which is an int
	scientific_name has a value which is a string
	scientific_lineage has a value which is a string
	rank has a value which is a string
	kingdom has a value which is a string
	domain has a value which is a string
	ws_ref has a value which is a string
	aliases has a value which is a reference to a list where each element is a string
	genetic_code has a value which is an int
	parent_taxon_ref has a value which is a string
	embl_code has a value which is a string
	inherited_div_flag has a value which is an int
	inherited_GC_flag has a value which is an int
	mitochondrial_genetic_code has a value which is an int
	inherited_MGC_flag has a value which is an int
	GenBank_hidden_flag has a value which is an int
	hidden_subtree_flag has a value which is an int
	division_id has a value which is an int
	comments has a value which is a string


=end text



=item Description

Index specified genomes in SOLR from KBase workspace

=back

=cut

sub index_taxa_in_solr
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to index_taxa_in_solr:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'index_taxa_in_solr');
    }

    my $ctx = $ReferenceDataManager::ReferenceDataManagerServer::CallContext;
    my($output);
    #BEGIN index_taxa_in_solr
    if (! $self->_ping()) {
        die "\nError--Solr server not responding:\n" . $self->_error->{response};
    }
    $params = $self->util_initialize_call($params,$ctx);
    $params = $self->util_args($params,[],{
        taxa => {},
        create_report => 0,
        solr_core => undef
    });
 
    my $msg = "";
    $output = [];
    my $taxa = $params->{taxa};
    my $solrCore = $params->{solr_core};
    my $solrBatch = [];
    my $solrBatchCount = 10000;
    print "\nTotal taxa to be indexed: ". @{$taxa} . "\n";

    for (my $i = 0; $i < @{$taxa}; $i++) {
        my $taxonData = $taxa -> [$i] -> {taxon};#an UnspecifiedObject
        my $wref = $taxa -> [$i] -> {ws_ref};
        my $current_taxon = $self -> _getTaxon($taxonData, $wref);

        push(@{$solrBatch}, $current_taxon); 
        if(@{$solrBatch} >= $solrBatchCount) { 
            eval {
                $self -> _indexInSolr($solrCore, $solrBatch );
            };
            if($@) {
                print "Failed to index the taxa!\n";
                print "ERROR:".$@;
                if(defined($@->{status_line})) {
                    print $@->{status_line}."\n";
                }
            }
            else {
                print "\nIndexed ". @{$solrBatch} . " taxa.\n";
                $solrBatch = [];
            }
        }

        push(@{$output}, $current_taxon);
        if (@{$output} < 10) {
            my $curr = @{$output}-1;
            $msg .= Data::Dumper->Dump([$output->[$curr]])."\n";
        } 
    }
    if(@{$solrBatch} > 0) {
            eval {
                $self -> _indexInSolr($solrCore, $solrBatch );
            };
            if($@) {
                print "Failed to index the taxa!\n";
                print "ERROR:".$@;
                if(defined($@->{status_line})) {
                    print $@->{status_line}."\n";
                }
            }
            else {
                print "\nIndexed ". @{$solrBatch} . " taxa.\n";
            }
    }
    if ($params->{create_report}) {
        print "Indexed ". scalar @{$output}. " taxa!\n";
        $self->util_create_report({
            message => "Indexed ".@{$output}." taxa!",
            workspace => undef
        });
        $output = ["indexed taxa"];
    }
    #END index_taxa_in_solr
    my @_bad_returns;
    (ref($output) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to index_taxa_in_solr:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'index_taxa_in_solr');
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
    if (! $self->_ping()) {                                                                                                   
        die "\nError--Solr server not responding:\n" . $self->_error->{response};
    }
    $params = $self->util_initialize_call($params,$ctx);
    $params = $self->util_args($params,[],{
        refseq => 1,
        update_only => 0,
        create_report => 0,
        workspace_name => undef
    });
    
    my $msg = "";
    $output = [];
    
    my $count = 0;
    my $genomes_in_solr;
    my $ref_genomes;
    my $loaded_genomes;
    
        $genomes_in_solr = $self->_listGenomesInSolr("QZtest", "*");    
        $ref_genomes = $self->list_reference_genomes({refseq => $params->{refseq}, update_only => $params->{update_only}}); 
        $loaded_genomes = $self->list_loaded_genomes({refseq => $params->{refseq}});    
   
        $genomes_in_solr = $genomes_in_solr->{response}->{response}->{docs};  
    
        for (my $i=0; $i < @{ $ref_genomes } && $i < 2; $i++) {
            my $genome = $ref_genomes->[$i];
    
            #check if the genome is already present in the database by querying SOLR
            my $gnstatus = $self->_checkGenomeStatus( $genome, $genomes_in_solr);

            if ($gnstatus=~/(new|updated)/i){
                $count ++;
                push(@{$output},$genome);
            
                if ($count < 10) {
                    $msg .= $genome->{accession}.";".$genome->{status}.";".$genome->{name}.";".$genome->{ftp_dir}.";".$genome->{file}.";".$genome->{id}.";".$genome->{version}.";".$genome->{source}.";".$genome->{domain}."\n";
                }
            }else{
                # Current version already in KBase, check for annotation update
            }
        }
        $self->load_genomes( {genomes => $output, index_in_solr => 1} );
    
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




=head2 status 

  $return = $obj->status()

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

Return the module status. This is a structure including Semantic Versioning number, state and git info.

=back

=cut

sub status {
    my($return);
    #BEGIN_STATUS
    $return = {"state" => "OK", "message" => "", "version" => $VERSION,
               "git_url" => $GIT_URL, "git_commit_hash" => $GIT_COMMIT_HASH};
    #END_STATUS
    return($return);
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



=head2 SolrGenomeFeatureData

=over 4



=item Description

Struct containing data for a single genome element output by the list_solr_genomes and index_genomes_in_solr functions


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
genome_feature_id has a value which is a string
genome_id has a value which is a string
feature_id has a value which is a string
ws_ref has a value which is a string
feature_type has a value which is a string
aliases has a value which is a string
scientific_name has a value which is a string
domain has a value which is a string
functions has a value which is a string
genome_source has a value which is a string
go_ontology_description has a value which is a string
go_ontology_domain has a value which is a string
gene_name has a value which is a string
object_name has a value which is a string
location_contig has a value which is a string
location_strand has a value which is a string
taxonomy has a value which is a string
workspace_name has a value which is a string
genetic_code has a value which is a string
md5 has a value which is a string
tax_id has a value which is a string
assembly_ref has a value which is a string
taxonomy_ref has a value which is a string
ontology_namespaces has a value which is a string
ontology_ids has a value which is a string
ontology_names has a value which is a string
ontology_lineages has a value which is a string
dna_sequence_length has a value which is an int
genome_dna_size has a value which is an int
location_begin has a value which is an int
location_end has a value which is an int
num_cds has a value which is an int
num_contigs has a value which is an int
protein_translation_length has a value which is an int
gc_content has a value which is a float
complete has a value which is a ReferenceDataManager.bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
genome_feature_id has a value which is a string
genome_id has a value which is a string
feature_id has a value which is a string
ws_ref has a value which is a string
feature_type has a value which is a string
aliases has a value which is a string
scientific_name has a value which is a string
domain has a value which is a string
functions has a value which is a string
genome_source has a value which is a string
go_ontology_description has a value which is a string
go_ontology_domain has a value which is a string
gene_name has a value which is a string
object_name has a value which is a string
location_contig has a value which is a string
location_strand has a value which is a string
taxonomy has a value which is a string
workspace_name has a value which is a string
genetic_code has a value which is a string
md5 has a value which is a string
tax_id has a value which is a string
assembly_ref has a value which is a string
taxonomy_ref has a value which is a string
ontology_namespaces has a value which is a string
ontology_ids has a value which is a string
ontology_names has a value which is a string
ontology_lineages has a value which is a string
dna_sequence_length has a value which is an int
genome_dna_size has a value which is an int
location_begin has a value which is an int
location_end has a value which is an int
num_cds has a value which is an int
num_contigs has a value which is an int
protein_translation_length has a value which is an int
gc_content has a value which is a float
complete has a value which is a ReferenceDataManager.bool


=end text

=back



=head2 ListSolrDocsParams

=over 4



=item Description

Arguments for the list_solr_genomes and list_solr_taxa functions


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
solr_core has a value which is a string
row_start has a value which is an int
row_count has a value which is an int
create_report has a value which is a ReferenceDataManager.bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
solr_core has a value which is a string
row_start has a value which is an int
row_count has a value which is an int
create_report has a value which is a ReferenceDataManager.bool


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
solr_core has a value which is a string
create_report has a value which is a ReferenceDataManager.bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
genomes has a value which is a reference to a list where each element is a ReferenceDataManager.KBaseReferenceGenomeData
workspace_name has a value which is a string
solr_core has a value which is a string
create_report has a value which is a ReferenceDataManager.bool


=end text

=back



=head2 ListLoadedTaxaParams

=over 4



=item Description

Argument(s) for the the lists_loaded_taxa function


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
workspace_name has a value which is a string
create_report has a value which is a ReferenceDataManager.bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
workspace_name has a value which is a string
create_report has a value which is a ReferenceDataManager.bool


=end text

=back



=head2 KBaseReferenceTaxonData

=over 4



=item Description

Struct containing data for a single taxon element output by the list_loaded_taxa function


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
taxonomy_id has a value which is an int
scientific_name has a value which is a string
scientific_lineage has a value which is a string
rank has a value which is a string
kingdom has a value which is a string
domain has a value which is a string
aliases has a value which is a reference to a list where each element is a string
genetic_code has a value which is an int
parent_taxon_ref has a value which is a string
embl_code has a value which is a string
inherited_div_flag has a value which is an int
inherited_GC_flag has a value which is an int
mitochondrial_genetic_code has a value which is an int
inherited_MGC_flag has a value which is an int
GenBank_hidden_flag has a value which is an int
hidden_subtree_flag has a value which is an int
division_id has a value which is an int
comments has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
taxonomy_id has a value which is an int
scientific_name has a value which is a string
scientific_lineage has a value which is a string
rank has a value which is a string
kingdom has a value which is a string
domain has a value which is a string
aliases has a value which is a reference to a list where each element is a string
genetic_code has a value which is an int
parent_taxon_ref has a value which is a string
embl_code has a value which is a string
inherited_div_flag has a value which is an int
inherited_GC_flag has a value which is an int
mitochondrial_genetic_code has a value which is an int
inherited_MGC_flag has a value which is an int
GenBank_hidden_flag has a value which is an int
hidden_subtree_flag has a value which is an int
division_id has a value which is an int
comments has a value which is a string


=end text

=back



=head2 LoadedReferenceTaxonData

=over 4



=item Description

Struct containing data for a single output by the list_loaded_taxa function


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
taxon has a value which is a ReferenceDataManager.KBaseReferenceTaxonData
ws_ref has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
taxon has a value which is a ReferenceDataManager.KBaseReferenceTaxonData
ws_ref has a value which is a string


=end text

=back



=head2 SolrTaxonData

=over 4



=item Description

Struct containing data for a single taxon element output by the list_solr_taxa function


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
taxonomy_id has a value which is an int
scientific_name has a value which is a string
scientific_lineage has a value which is a string
rank has a value which is a string
kingdom has a value which is a string
domain has a value which is a string
ws_ref has a value which is a string
aliases has a value which is a reference to a list where each element is a string
genetic_code has a value which is an int
parent_taxon_ref has a value which is a string
embl_code has a value which is a string
inherited_div_flag has a value which is an int
inherited_GC_flag has a value which is an int
mitochondrial_genetic_code has a value which is an int
inherited_MGC_flag has a value which is an int
GenBank_hidden_flag has a value which is an int
hidden_subtree_flag has a value which is an int
division_id has a value which is an int
comments has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
taxonomy_id has a value which is an int
scientific_name has a value which is a string
scientific_lineage has a value which is a string
rank has a value which is a string
kingdom has a value which is a string
domain has a value which is a string
ws_ref has a value which is a string
aliases has a value which is a reference to a list where each element is a string
genetic_code has a value which is an int
parent_taxon_ref has a value which is a string
embl_code has a value which is a string
inherited_div_flag has a value which is an int
inherited_GC_flag has a value which is an int
mitochondrial_genetic_code has a value which is an int
inherited_MGC_flag has a value which is an int
GenBank_hidden_flag has a value which is an int
hidden_subtree_flag has a value which is an int
division_id has a value which is an int
comments has a value which is a string


=end text

=back



=head2 ReferenceTaxonData

=over 4



=item Description

Struct containing data for a single taxon output by the list_loaded_taxa function


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



=head2 LoadTaxonsParams

=over 4



=item Description

Arguments for the load_taxons function


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
data has a value which is a string
taxons has a value which is a reference to a list where each element is a ReferenceDataManager.ReferenceTaxonData
index_in_solr has a value which is a ReferenceDataManager.bool
workspace_name has a value which is a string
create_report has a value which is a ReferenceDataManager.bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
data has a value which is a string
taxons has a value which is a reference to a list where each element is a ReferenceDataManager.ReferenceTaxonData
index_in_solr has a value which is a ReferenceDataManager.bool
workspace_name has a value which is a string
create_report has a value which is a ReferenceDataManager.bool


=end text

=back



=head2 IndexTaxaInSolrParams

=over 4



=item Description

Arguments for the index_taxa_in_solr function


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
taxa has a value which is a reference to a list where each element is a ReferenceDataManager.LoadedReferenceTaxonData
solr_core has a value which is a string
create_report has a value which is a ReferenceDataManager.bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
taxa has a value which is a reference to a list where each element is a ReferenceDataManager.LoadedReferenceTaxonData
solr_core has a value which is a string
create_report has a value which is a ReferenceDataManager.bool


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



=cut

1;
