package ReferenceDataManager::ReferenceDataManagerImpl;
use strict;
use Bio::KBase::Exceptions;
# Use Semantic Versioning (2.0.0-rc.1)
# http://semver.org 
our $VERSION = '0.0.1';
our $GIT_URL = 'https://github.com/kbaseapps/ReferenceDataManager.git';
our $GIT_COMMIT_HASH = '6234dbcb74d8544151748bab2e0d4b8f9c799e5f';

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
#Internal Method: to list the taxons already in SOLR and return an array of those taxons
#
sub _listTaxonsInSolr {
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
    print "The final deletion query string is: \n" . "$solrQuery \n";

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
sub _checkGenomeStatus {
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

#internal method, for possibly multiple trials due to network timeouts
#
sub getTaxon {
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
sub _indexInSolr {
        my ($self, $solrCore, $docData) = @_; 
        if( @{$docData} >= 1) {
          eval {
            if( $self -> _addXML2Solr($solrCore, $docData) == 1 ) {
                #commit the additions
                if (!$self->_commit($solrCore)) {
                        print "\n Error: " . $self->_error->{response};
                }
                #print "\nIndexed " . @{$docData} . " documents.";
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
        refseq => "RefseqGenomesWS"# "ReferenceDataManagerWS"#"KBasePublicRichGenomesV5"#"RefSeq_Genomes"
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
            my $wsinfo;
            my $wsoutput;
            if(defined($self->util_ws_client())){
                $wsinfo = $self->util_ws_client()->get_workspace_info({
                    workspace => $wsname
                });
            }
            my $maxid = $wsinfo->[4];
            my $pages = ceil($maxid/10000);

            for (my $m=0; $m < $pages; $m++) {
                $wsoutput = $self->util_ws_client()->list_objects({
                    workspaces => [$wsname],
                    #Phytozome has types of KBaseGenomes.Genome-8.2, KBaseGenomeAnnotations.Assembly-2.0, and KBaseGenomes.Genome-12.2                  
                    #Ensembl_Genomes has types of KBaseGenomeAnnotations.Assembly-4.1, KBaseGenomeAnnotations.GenomeAnnotation-3.1, and KBaseGenomes.ContigSet-3.0                      
                    #type => "KBaseGenomes.Genome-8.0",             
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




=head2 list_solr_genomes

  $output = $obj->list_solr_genomes($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a ReferenceDataManager.ListSolrDocsParams
$output is a reference to a list where each element is a ReferenceDataManager.SolrGenomeData
ListSolrDocsParams is a reference to a hash where the following keys are defined:
	solr_core has a value which is a string
	row_start has a value which is an int
	row_count has a value which is an int
	create_report has a value which is a ReferenceDataManager.bool
bool is an int
SolrGenomeData is a reference to a hash where the following keys are defined:
	genome_id has a value which is a string
	ws_ref has a value which is a string
	aliases has a value which is a string
	annotations has a value which is a string
	atomic_regulons has a value which is a string
	co_occurring_fids has a value which is a string
	co_expressed_fids has a value which is a string
	complete has a value which is a ReferenceDataManager.bool
	cs_db_version has a value which is a string
	dna_sequence_length has a value which is an int
	domain has a value which is a string
	feature_id has a value which is a string
	feature_publications has a value which is a string
	feature_source_id has a value which is a string
	feature_type has a value which is a string
	function has a value which is a string
	gc_content has a value which is a float
	gene_name has a value which is a string
	genome_dna_size has a value which is an int
	genome_publications has a value which is a string
	genome_source has a value which is a string
	genome_source_id has a value which is a string
	go_ontology_description has a value which is a string
	go_ontology_domain has a value which is a string
	has_protein_familiies has a value which is a ReferenceDataManager.bool
	has_publications has a value which is a ReferenceDataManager.bool
	location_begin has a value which is an int
	location_contig has a value which is a string
	location_end has a value which is an int
	location_strand has a value which is a string
	locations has a value which is a string
	num_cds has a value which is an int
	num_contigs has a value which is an int
	object_id has a value which is a string
	object_name has a value which is a string
	object_type has a value which is a string
	protein_families has a value which is a string
	protein_translation_length has a value which is an int
	regulon_data has a value which is a string
	roles has a value which is a string
	scientific_name has a value which is a string
	scientific_name_sort has a value which is a string
	subsystems has a value which is a string
	subsystem_data has a value which is a string
	taxonomy has a value which is a string
	workspace_name has a value which is a string

</pre>

=end html

=begin text

$params is a ReferenceDataManager.ListSolrDocsParams
$output is a reference to a list where each element is a ReferenceDataManager.SolrGenomeData
ListSolrDocsParams is a reference to a hash where the following keys are defined:
	solr_core has a value which is a string
	row_start has a value which is an int
	row_count has a value which is an int
	create_report has a value which is a ReferenceDataManager.bool
bool is an int
SolrGenomeData is a reference to a hash where the following keys are defined:
	genome_id has a value which is a string
	ws_ref has a value which is a string
	aliases has a value which is a string
	annotations has a value which is a string
	atomic_regulons has a value which is a string
	co_occurring_fids has a value which is a string
	co_expressed_fids has a value which is a string
	complete has a value which is a ReferenceDataManager.bool
	cs_db_version has a value which is a string
	dna_sequence_length has a value which is an int
	domain has a value which is a string
	feature_id has a value which is a string
	feature_publications has a value which is a string
	feature_source_id has a value which is a string
	feature_type has a value which is a string
	function has a value which is a string
	gc_content has a value which is a float
	gene_name has a value which is a string
	genome_dna_size has a value which is an int
	genome_publications has a value which is a string
	genome_source has a value which is a string
	genome_source_id has a value which is a string
	go_ontology_description has a value which is a string
	go_ontology_domain has a value which is a string
	has_protein_familiies has a value which is a ReferenceDataManager.bool
	has_publications has a value which is a ReferenceDataManager.bool
	location_begin has a value which is an int
	location_contig has a value which is a string
	location_end has a value which is an int
	location_strand has a value which is a string
	locations has a value which is a string
	num_cds has a value which is an int
	num_contigs has a value which is an int
	object_id has a value which is a string
	object_name has a value which is a string
	object_type has a value which is a string
	protein_families has a value which is a string
	protein_translation_length has a value which is an int
	regulon_data has a value which is a string
	roles has a value which is a string
	scientific_name has a value which is a string
	scientific_name_sort has a value which is a string
	subsystems has a value which is a string
	subsystem_data has a value which is a string
	taxonomy has a value which is a string
	workspace_name has a value which is a string


=end text



=item Description

Lists taxons indexed in SOLR

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




=head2 list_loaded_taxons

  $output = $obj->list_loaded_taxons($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a ReferenceDataManager.ListLoadedTaxonsParams
$output is a reference to a list where each element is a ReferenceDataManager.LoadedReferenceTaxonData
ListLoadedTaxonsParams is a reference to a hash where the following keys are defined:
	workspace_name has a value which is a string
	create_report has a value which is a ReferenceDataManager.bool
bool is an int
LoadedReferenceTaxonData is a reference to a hash where the following keys are defined:
	taxon has a value which is a reference to a list where each element is a ReferenceDataManager.KBaseReferenceTaxonData
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

$params is a ReferenceDataManager.ListLoadedTaxonsParams
$output is a reference to a list where each element is a ReferenceDataManager.LoadedReferenceTaxonData
ListLoadedTaxonsParams is a reference to a hash where the following keys are defined:
	workspace_name has a value which is a string
	create_report has a value which is a ReferenceDataManager.bool
bool is an int
LoadedReferenceTaxonData is a reference to a hash where the following keys are defined:
	taxon has a value which is a reference to a list where each element is a ReferenceDataManager.KBaseReferenceTaxonData
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

Lists taxons loaded into KBase for a given workspace

=back

=cut

sub list_loaded_taxons
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to list_loaded_taxons:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'list_loaded_taxons');
    }

    my $ctx = $ReferenceDataManager::ReferenceDataManagerServer::CallContext;
    my($output);
    #BEGIN list_loaded_taxons
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
    my $solrTaxonBatch = []; 
    if(defined($self->util_ws_client())){
    $wsinfo = $self->util_ws_client()->get_workspace_info({
            workspace => $wsname
        });
    }

    my $batch_count = 10000;
    my $maxid = $wsinfo->[4];
    my $pages = ceil($maxid/$batch_count);
    print "\nFound $maxid taxon objects.\n";
    
    try {
        for (my $m = 23; $m < 33; $m++) {
        print "\nBatch ". $m . "x$batch_count";
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
        my $wstaxonrefs = [];
        for (my $j=0; $j < @{$wsoutput}; $j++) {
            push(@{$wstaxonrefs},{
                "ref" => $wsoutput->[$j]->[6]."/".$wsoutput->[$j]->[0]."/".$wsoutput->[$j]->[4]
            });
        }

        print "\nFetch the objects at the batch size of: " . @{$wstaxonrefs};
        eval {
            $taxonout = $self->util_ws_client()->get_objects2({
                objects => $wstaxonrefs
            }); #return a reference to a hash where key 'data' is defined as a list of Workspace.ObjectData
        };
        if($@) {
            print "Cannot get object information!\n";
            print "ERROR:".$@;
            #print $@->{message}."\n";
            if(defined($@->{status_line})) {
                print $@->{status_line}."\n";
            }
        }
        $taxonout = $taxonout -> {data};
        for (my $i=0; $i < @{$taxonout}; $i++) {
            my $taxonData = $taxonout -> [$i] -> {data};#an UnspecifiedObject

            push(@{$output}, {taxon => $taxonData, ws_ref => $wstaxonrefs -> [$i] -> {ref}});
            if (@{$output} < 10) {
                    my $curr = @{$output}-1;
                    $msg .= Data::Dumper->Dump([$output->[$curr]])."\n";
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
  
    #END list_loaded_taxons
    my @_bad_returns;
    (ref($output) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to list_loaded_taxons:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'list_loaded_taxons');
    }
    return($output);
}




=head2 list_solr_taxons

  $output = $obj->list_solr_taxons($params)

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

Lists taxons indexed in SOLR

=back

=cut

sub list_solr_taxons
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to list_solr_taxons:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'list_solr_taxons');
    }

    my $ctx = $ReferenceDataManager::ReferenceDataManagerServer::CallContext;
    my($output);
    #BEGIN list_solr_taxons
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
        $solrout = $self->_listTaxonsInSolr($solrCore, $fields, $startRow, $topRows);
    };
    if($@) {
        print "Cannot list taxons in SOLR information!\n";
        print "ERROR:".$@;
        if(defined($@->{status_line})) {
            print $@->{status_line}."\n";
        }
    }
    else {
        print "\nList of taxons: \n" . Dumper($solrout) . "\n";  
        $output = $solrout->{response}->{docs}; 
        
        if (@{$output} < 10) {
            my $curr = @{$output}-1;
            $msg .= Data::Dumper->Dump([$output->[$curr]])."\n";
        } 
    }
    #END list_solr_taxons
    my @_bad_returns;
    (ref($output) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to list_solr_taxons:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'list_solr_taxons');
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
$output is a reference to a list where each element is a ReferenceDataManager.KBaseReferenceGenomeData
IndexGenomesInSolrParams is a reference to a hash where the following keys are defined:
	genomes has a value which is a reference to a list where each element is a ReferenceDataManager.KBaseReferenceGenomeData
	workspace_name has a value which is a string
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

</pre>

=end html

=begin text

$params is a ReferenceDataManager.IndexGenomesInSolrParams
$output is a reference to a list where each element is a ReferenceDataManager.KBaseReferenceGenomeData
IndexGenomesInSolrParams is a reference to a hash where the following keys are defined:
	genomes has a value which is a reference to a list where each element is a ReferenceDataManager.KBaseReferenceGenomeData
	workspace_name has a value which is a string
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
            $ws_genome_obj_metadata = $ws_genome_object_info->{metadata}; 
            $ws_genome_obj_data = $ws_genome_object_info->{data}; 
            $ws_genome_usr_metadata = $ws_genome_obj_metadata->[10];
            print "$ws_genome_obj_data:\n".Dumper($ws_genome_obj_data)."\n";
        }       

        my $ws_obj_id = $ws_genome_obj_metadata->[11];
        
        $record->{workspace_name} = $ws_name; 
        $record->{object_id} = $ws_obj_id; 
        $record->{object_name} = $ws_genome_name; # kb|g.3397
        $record->{object_type} = $ws_genome_obj_metadata->[1];#"KBaseGenomes.Genome-8.0"; 

        # Get genome info
        my $ws_genome  = $ws_genome_obj_data;
        $record->{genome_id} = $ws_genome_name; #$ws_genome->{id}; # kb|g.3397
        $record->{genome_source} = $ws_genome->{source};#$genome_source; $ws_genome->{external_source}; # KBase Central Store
        $record->{genome_source_id} = $ws_genome->{source_id};#$ws_genome->{external_source_id}; # 'NODE_220_length_6412_cov_5.05805_ID_439'
        #$record->{num_cds} = $ws_genome->{md5};#[doc=12] Error adding field \'num_cds\'=\'\'
        
        # Get assembly info
        #my $ws_assembly = $ws_genome->{assembly_ref};
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
        my $ws_taxon = $ws_genome->{taxon_ref};
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
        #$self -> _addXML2Solr($solrCore, @{solr_records});

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




=head2 index_taxons_in_solr

  $output = $obj->index_taxons_in_solr($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a ReferenceDataManager.IndexTaxonsInSolrParams
$output is a reference to a list where each element is a ReferenceDataManager.SolrTaxonData
IndexTaxonsInSolrParams is a reference to a hash where the following keys are defined:
	taxons has a value which is a reference to a list where each element is a ReferenceDataManager.LoadedReferenceTaxonData
	solr_core has a value which is a string
	create_report has a value which is a ReferenceDataManager.bool
LoadedReferenceTaxonData is a reference to a hash where the following keys are defined:
	taxon has a value which is a reference to a list where each element is a ReferenceDataManager.KBaseReferenceTaxonData
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

$params is a ReferenceDataManager.IndexTaxonsInSolrParams
$output is a reference to a list where each element is a ReferenceDataManager.SolrTaxonData
IndexTaxonsInSolrParams is a reference to a hash where the following keys are defined:
	taxons has a value which is a reference to a list where each element is a ReferenceDataManager.LoadedReferenceTaxonData
	solr_core has a value which is a string
	create_report has a value which is a ReferenceDataManager.bool
LoadedReferenceTaxonData is a reference to a hash where the following keys are defined:
	taxon has a value which is a reference to a list where each element is a ReferenceDataManager.KBaseReferenceTaxonData
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

sub index_taxons_in_solr
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to index_taxons_in_solr:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'index_taxons_in_solr');
    }

    my $ctx = $ReferenceDataManager::ReferenceDataManagerServer::CallContext;
    my($output);
    #BEGIN index_taxons_in_solr
    if (! $self->_ping()) {
        die "\nError--Solr server not responding:\n" . $self->_error->{response};
    }
    $params = $self->util_initialize_call($params,$ctx);
    $params = $self->util_args($params,[],{
        taxons => {},
        create_report => 0,
        solr_core => undef
    });
 
    my $msg = "";
    $output = [];
    my $taxons = $params->{taxons};
    my $solrCore = $params->{solr_core};
    my $solrBatch = [];
    print "\nTotal taxons to be indexed: ". @{$taxons} . "\n";

    for (my $i = 0; $i < @{$taxons}; $i++) {
        my $taxonData = $taxons -> [$i] -> {taxon};#an UnspecifiedObject
        my $wref = $taxons -> [$i] -> {ws_ref};
        my $current_taxon = $self -> getTaxon($taxonData, $wref);

        push(@{$solrBatch}, $current_taxon); 
        if( @{$solrBatch} >= 10000) { 
            eval {
                $self -> _indexInSolr($solrCore, $solrBatch );
            };
            if($@) {
                print "Failed to index the taxons!\n";
                print "ERROR:".$@;
                if(defined($@->{status_line})) {
                    print $@->{status_line}."\n";
                }
            }
            else {
                print "\nIndexed ". @{$solrBatch} . " taxons.\n";
                $solrBatch = [];
            }
        }

        push(@{$output}, $current_taxon);
        if (@{$output} < 10) {
            my $curr = @{$output}-1;
            $msg .= Data::Dumper->Dump([$output->[$curr]])."\n";
        } 
    }
    
    if ($params->{create_report}) {
        print "Indexed ". scalar @{$output}. " taxons!\n";
        $self->util_create_report({
            message => "Indexed ".@{$output}." taxons!",
            workspace => undef
        });
        $output = ["indexed taxones"];
    }
    #END index_taxons_in_solr
    my @_bad_returns;
    (ref($output) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to index_taxons_in_solr:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'index_taxons_in_solr');
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
                #$self->load_genomes( {genomes => [$genome], index_in_solr => 1} );
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



=head2 ListSolrDocsParams

=over 4



=item Description

Arguments for the list_solr_genomes and list_solr_taxons functions


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



=head2 SolrGenomeData

=over 4



=item Description

Struct containing data for a single genome element output by the list_solr_genomes function


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
genome_id has a value which is a string
ws_ref has a value which is a string
aliases has a value which is a string
annotations has a value which is a string
atomic_regulons has a value which is a string
co_occurring_fids has a value which is a string
co_expressed_fids has a value which is a string
complete has a value which is a ReferenceDataManager.bool
cs_db_version has a value which is a string
dna_sequence_length has a value which is an int
domain has a value which is a string
feature_id has a value which is a string
feature_publications has a value which is a string
feature_source_id has a value which is a string
feature_type has a value which is a string
function has a value which is a string
gc_content has a value which is a float
gene_name has a value which is a string
genome_dna_size has a value which is an int
genome_publications has a value which is a string
genome_source has a value which is a string
genome_source_id has a value which is a string
go_ontology_description has a value which is a string
go_ontology_domain has a value which is a string
has_protein_familiies has a value which is a ReferenceDataManager.bool
has_publications has a value which is a ReferenceDataManager.bool
location_begin has a value which is an int
location_contig has a value which is a string
location_end has a value which is an int
location_strand has a value which is a string
locations has a value which is a string
num_cds has a value which is an int
num_contigs has a value which is an int
object_id has a value which is a string
object_name has a value which is a string
object_type has a value which is a string
protein_families has a value which is a string
protein_translation_length has a value which is an int
regulon_data has a value which is a string
roles has a value which is a string
scientific_name has a value which is a string
scientific_name_sort has a value which is a string
subsystems has a value which is a string
subsystem_data has a value which is a string
taxonomy has a value which is a string
workspace_name has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
genome_id has a value which is a string
ws_ref has a value which is a string
aliases has a value which is a string
annotations has a value which is a string
atomic_regulons has a value which is a string
co_occurring_fids has a value which is a string
co_expressed_fids has a value which is a string
complete has a value which is a ReferenceDataManager.bool
cs_db_version has a value which is a string
dna_sequence_length has a value which is an int
domain has a value which is a string
feature_id has a value which is a string
feature_publications has a value which is a string
feature_source_id has a value which is a string
feature_type has a value which is a string
function has a value which is a string
gc_content has a value which is a float
gene_name has a value which is a string
genome_dna_size has a value which is an int
genome_publications has a value which is a string
genome_source has a value which is a string
genome_source_id has a value which is a string
go_ontology_description has a value which is a string
go_ontology_domain has a value which is a string
has_protein_familiies has a value which is a ReferenceDataManager.bool
has_publications has a value which is a ReferenceDataManager.bool
location_begin has a value which is an int
location_contig has a value which is a string
location_end has a value which is an int
location_strand has a value which is a string
locations has a value which is a string
num_cds has a value which is an int
num_contigs has a value which is an int
object_id has a value which is a string
object_name has a value which is a string
object_type has a value which is a string
protein_families has a value which is a string
protein_translation_length has a value which is an int
regulon_data has a value which is a string
roles has a value which is a string
scientific_name has a value which is a string
scientific_name_sort has a value which is a string
subsystems has a value which is a string
subsystem_data has a value which is a string
taxonomy has a value which is a string
workspace_name has a value which is a string


=end text

=back



=head2 ListLoadedTaxonsParams

=over 4



=item Description

Argument(s) for the the lists_loaded_taxons function


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

Struct containing data for a single taxon element output by the list_loaded_taxons function


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



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
taxon has a value which is a reference to a list where each element is a ReferenceDataManager.KBaseReferenceTaxonData
ws_ref has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
taxon has a value which is a reference to a list where each element is a ReferenceDataManager.KBaseReferenceTaxonData
ws_ref has a value which is a string


=end text

=back



=head2 SolrTaxonData

=over 4



=item Description

Struct containing data for a single taxon element output by the list_solr_taxons function


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
create_report has a value which is a ReferenceDataManager.bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
genomes has a value which is a reference to a list where each element is a ReferenceDataManager.KBaseReferenceGenomeData
workspace_name has a value which is a string
create_report has a value which is a ReferenceDataManager.bool


=end text

=back



=head2 IndexTaxonsInSolrParams

=over 4



=item Description

Arguments for the index_taxons_in_solr function


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
taxons has a value which is a reference to a list where each element is a ReferenceDataManager.LoadedReferenceTaxonData
solr_core has a value which is a string
create_report has a value which is a ReferenceDataManager.bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
taxons has a value which is a reference to a list where each element is a ReferenceDataManager.LoadedReferenceTaxonData
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
