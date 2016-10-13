use strict;
use Data::Dumper;
use Config::IniFiles;
use GenomeFileUtil::GenomeFileUtilClient;

_testLoadGenomes();

sub _testLoadGenomes{	
	#for information only
	my $config_file = $ENV{ KB_DEPLOYMENT_CONFIG };
	my $cfg = Config::IniFiles->new(-file=>$config_file);
	my $ws_url = $cfg->val('ReferenceDataManager','workspace-url');
	print "\nWorkspace service url: $ws_url\n";	

	my $loader = new GenomeFileUtil::GenomeFileUtilClient($ENV{ SDK_CALLBACK_URL });	
	
	#data, should be an array although here I only put one item for test
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

	my $wsname = 'qzTestWS';	
	
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
}
