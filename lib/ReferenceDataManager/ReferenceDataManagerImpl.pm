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

#The first thing every function should do is call this function
sub util_initialize_call {
	my ($self,$params,$ctx) = @_;
	if(defined($ctx)){
	print("Starting ".$ctx->method()." method.\n");
	$self->{_token} = $ctx->token();
	$self->{_username} = $ctx->user_id();
	$self->{_method} = $ctx->method();
	$self->{_provenance} = $ctx->provenance();
	$self->{_wsclient} = new Bio::KBase::workspace::Client($self->{workspace_url},token => $ctx->token());
	$self->util_timestamp(DateTime->now()->datetime());
	}
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
    $self->util_initialize_call();
    $params = $self->util_args($params,[],{
    	ensembl => 0,#todo
    	phytozome => 0,#todo
    	refseq => 0,
    	create_report => 0,
    	update_only => 1,#todo
    	workspace => undef
    });
    my $msg = "";
    $output = [];
    if ($params->{refseq} == 1) {
    	my $source = "refseq";#Could also be "genbank"
    	my $division = "bacteria";#Could also be "archaea" or "plant"
    	my $assembly_summary_url = "ftp://ftp.ncbi.nlm.nih.gov/genomes/".$source."/".$division."/assembly_summary.txt";
    	my $assemblies = [`wget -q -O - $assembly_summary_url`];
		foreach my $entry (@{$assemblies}) {
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
			$msg .= $current_genome->{source}."\t".$current_genome->{accession}."\t".$current_genome->{status}."\n";
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
    	$self->util_create_report({
    		message => $msg,
    		workspace => $params->{workspace}
    	});
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
    $self->util_initialize_call();
    $params = $self->util_args($params,[],{
    	ensembl => 0,
    	phytozome => 0,
    	refseq => 0,
    	create_report => 0,
    	workspace => undef
    });
    my $msg = "";
    my $output = [];
    my $sources = ["ensembl","phytozome","refseq"];
    for (my $i=0; $i < @{$sources}; $i++) {
    	if ($params->{$sources->[$i]} == 1) {
    		my $wsname = $self->util_workspace_names($sources->[$i]);
    		my $wsoutput;
    		if(defined($self->util_ws_client())){
    			$wsoutput = $self->util_ws_client()->list_objects({
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
	    			$msg .= $wsoutput->[$j]->[1]."|".$wsoutput->[$j]->[10]->{Name}."\n";
	    		}
    		}
    	}
    }
    if ($params->{create_report}) {
    	$self->util_create_report({
    		message => $msg,
    		workspace => $params->{workspace}
    	});
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
	genomes has a value which is a reference to a list where each element is a ReferenceDataManager.ReferenceGenomeData
	index_in_solr has a value which is a ReferenceDataManager.bool
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
	genomes has a value which is a reference to a list where each element is a ReferenceDataManager.ReferenceGenomeData
	index_in_solr has a value which is a ReferenceDataManager.bool
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
    $self->util_initialize_call();
    $params = $self->util_args($params,[],{
    	genomes => [],
        index_in_solr => 0,
        create_report => 0,
    	workspace => undef
    });
	my $loader = new GenomeFileUtil::GenomeFileUtilClient($ENV{ SDK_CALLBACK_URL });
	my $genomes = $params->{genomes};
	for (my $i=0; $i < @{$genomes}; $i++) {
		my $genome = $genomes->[$i];
		print "Now loading ".$genome->{source}.":".$genome->{id}." with loader url=".$ENV{ SDK_CALLBACK_URL }."\n";
		my $wsname = $self->util_workspace_names($genome->{source});
		if ($genome->{source} eq "refseq" || $genome->{source} eq "ensembl") {
			my $genutilout = $loader->genbank_to_genome({
				file => {
					ftp_url => $genome->{ftp_dir}
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
    	$self->util_create_report({
    		message => "Loaded ".@{$output}." genomes!",
    		workspace => $params->{workspace}
    	});
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

$params is a ReferenceDataManager.IndexGenomesInSolrParams
$output is a reference to a list where each element is a ReferenceDataManager.KBaseReferenceGenomeData
IndexGenomesInSolrParams is a reference to a hash where the following keys are defined:
	genomes has a value which is a reference to a list where each element is a ReferenceDataManager.KBaseReferenceGenomeData
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
    $self->util_initialize_call();
    $params = $self->util_args($params,[],[]);
    my $json = JSON->new->allow_nonref;
    my @solr_records;
    $output = [];
    print "The bin directory:" . $Bin . "\n";
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
    $self->util_initialize_call();
    $params = $self->util_args($params,[],{
    	ensembl => 0,#todo
    	phytozome => 0,#todo
    	refseq => 0,
    	create_report => 0,
    	workspace => undef
    });
    
    if ($params->{create_report}) {
    	$self->util_create_report({
    		message => "Updated ".@{$output}." genomes!",
    		workspace => $params->{workspace}
    	});
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

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
ensembl has a value which is a ReferenceDataManager.bool
refseq has a value which is a ReferenceDataManager.bool
phytozome has a value which is a ReferenceDataManager.bool
updated_only has a value which is a ReferenceDataManager.bool


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

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
ensembl has a value which is a ReferenceDataManager.bool
refseq has a value which is a ReferenceDataManager.bool
phytozome has a value which is a ReferenceDataManager.bool


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
genomes has a value which is a reference to a list where each element is a ReferenceDataManager.ReferenceGenomeData
index_in_solr has a value which is a ReferenceDataManager.bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
genomes has a value which is a reference to a list where each element is a ReferenceDataManager.ReferenceGenomeData
index_in_solr has a value which is a ReferenceDataManager.bool


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

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
genomes has a value which is a reference to a list where each element is a ReferenceDataManager.KBaseReferenceGenomeData


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

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
ensembl has a value which is a ReferenceDataManager.bool
refseq has a value which is a ReferenceDataManager.bool
phytozome has a value which is a ReferenceDataManager.bool


=end text

=back



=cut

1;
