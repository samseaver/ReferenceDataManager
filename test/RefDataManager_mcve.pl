use strict;
use Data::Dumper;
use Config::IniFiles;
use GenomeFileUtil::GenomeFileUtilClient;

$|=1; # autoflush

_testLoadGenomes();

sub _testLoadGenomes{	
	#for information only
	my $config_file = $ENV{ KB_DEPLOYMENT_CONFIG };
	my $cfg = Config::IniFiles->new(-file=>$config_file);
	my $ws_url = $cfg->val('ReferenceDataManager','workspace-url');
	print "\nWorkspace service url: $ws_url\n";	

	my $loader = new GenomeFileUtil::GenomeFileUtilClient($ENV{ SDK_CALLBACK_URL });	
	
	my $wsname = 'qzTestWS';
	
	eval {
		print "Now loading genome into $wsname.\n";
		
		my $genutilout = $loader->genbank_to_genome({
			file => {
				ftp_url => "ftp://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/010/525/GCF_000010525.1_ASM1052v1/GCF_000010525.1_ASM1052v1_genomic.gbff.gz"
			},
			genome_name => 'GCF_000010525',
			workspace_name => $wsname,
			source => 'refseq',
			taxon_wsname => "ReferenceTaxons",
			release => '1',
			generate_ids_if_needed => 1,
			genetic_code => 11,
			type => "Reference",
			metadata => {
				refid => 'GCF_000010525',
				accession => 'GCF_000010525.1',
				refname => 'ASM1052v1',
				url => undef,
				version => '1'
			}
		});
		print "\nLoaded genome list--test: \n" . Dumper($genutilout). "\n";
	};
	
	if ($@) {
		my $err = $@;
		print "Error type: " . ref($err) . "\n";
		print "Error message: " . $err->{message} . "\n";
		print "Error error: " . $err->{error} . "\n";
		print "Error data: " .$err->{data} . "\n";
	}
}
