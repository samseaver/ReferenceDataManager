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
use Config::IniFiles;
use Data::Dumper;

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
	die "Mandatory arguments ".join("; ",@{$args->{_error}})." missing";
	foreach my $argument (keys(%{$optionalArguments})) {
		if (!defined($args->{$argument})) {
			$args->{$argument} = $optionalArguments->{$argument};
		}
	}
	return $args;
}

sub func_load_genome {
	#Part of load genome function
	#getMD5Checksums($assembly);
	#my $assembly_status = checkAssemblyStatus($assembly);
	#if ($assembly_status eq $status || $status eq "all"){
	#	my $dir = "$reference_genome_staging_dir/$assembly->{accession}";
	#	`mkdir $reference_genome_staging_dir/$assembly->{accession}` unless (-d "$reference_genome_staging_dir/$assembly->{accession}");
	#	getGenBankFile($assembly) if grep $_ eq "gbf", @formats;
	#	getGffFile($assembly) if grep $_ eq "gff", @formats;
	#	getFnaFile($assembly) if grep $_ eq "fna", @formats;
	#	getFaaFile($assembly) if grep $_ eq "faa", @formats;
	#	getFeatureTableFile($assembly) if grep $_ eq "ftb", @formats;
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
    my $wsInstance = $cfg->val('ReferenceDataManager','workspace-url');
    die "no workspace-url defined" unless $wsInstance;
    
    $self->{'workspace-url'} = $wsInstance;
    
    #END_CONSTRUCTOR

    if ($self->can('_init_instance'))
    {
	$self->_init_instance();
    }
    return $self;
}

=head1 METHODS



=head2 list_reference_Genomes

  $output = $obj->list_reference_Genomes($params)

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
	id has a value which is a string
	source has a value which is a string
	version has a value which is a string

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
	id has a value which is a string
	source has a value which is a string
	version has a value which is a string


=end text



=item Description

Lists genomes present in selected reference databases (ensembl, phytozome, refseq)

=back

=cut

sub list_reference_Genomes
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to list_reference_Genomes:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'list_reference_Genomes');
    }

    my $ctx = $ReferenceDataManager::ReferenceDataManagerServer::CallContext;
    my($output);
    #BEGIN list_reference_Genomes
    $params = $self->util_args($params,[],{
    	ensembl => 0,#todo
    	phytozome => 0,#todo
    	refseq => 0,
    	update_only => 1#todo
    });
    $output = [];
    if ($params->{refseq} == 1) {
    	["division=s", "Division: bacteria | archaea | plant, multivalued, comma-seperated"],
		["source=s", "Source: genbank | refseq", {default => "refseq"}],
    	my $source = "refseq";#Could also be "genbank"
    	my $division = "bacteria";#Could also be "archaea" or "plant"
    	my $assembly_summary_url = "ftp://ftp.ncbi.nlm.nih.gov/genomes/".$source."/".$division."/assembly_summary.txt";
    	my $assemblies = [`wget -q -O - $assembly_summary_url`];
		my $current_genome;
		foreach my $entry (@{$assemblies}) {
			chomp $entry;
			if ($entry=~/^#/) { #header
				if (defined($current_genome)) {
					#Note: we might need special behavior here if $current_genome->{status} eq "replaced" 
					push(@{$output},$current_genome);
				}
				$current_genome = {
					source => $source,
					domain => $division
				};
				$current_genome->{header} = $entry;
				$current_genome->{header} =~s/^#/status\tdivision\t/;
				next;
			}
			my @attribs = split /\t/, $entry;
			$current_genome->{accession} = $attribs[0];
			$current_genome->{status} = $attribs[10];
			$current_genome->{name} = $attribs[15];
			$current_genome->{ftp_dir} = $attribs[19];
			$current_genome->{file} = $current_genome->{ftp_dir};
			$current_genome->{file}=~s/.*\///;
			($current_genome->{id}, $current_genome->{version}) = $current_genome->{accession}=~/(.*)\.(\d+)$/;
			#$current_genome->{dir} = $current_genome->{accession}."_".$current_genome->{name};#May not need this
		}
		if (defined($current_genome)) {
			push(@{$output},$current_genome);
		}
    }
    #END list_reference_Genomes
    my @_bad_returns;
    (ref($output) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to list_reference_Genomes:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'list_reference_Genomes');
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
id has a value which is a string
source has a value which is a string
version has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
id has a value which is a string
source has a value which is a string
version has a value which is a string


=end text

=back



=cut

1;
