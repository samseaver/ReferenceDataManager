/*
A KBase module: ReferenceDataManager
This sample module contains one small method - filter_contigs.
*/

module ReferenceDataManager {
    /*
        A boolean.
    */
    typedef int bool;
    
    /*
        Arguments for the list_reference_genomes function
        
    */
    typedef structure {
        bool ensembl;
        bool refseq;
        bool phytozome;
        bool updated_only;
	string workspace_name;
	bool create_report; 
   } ListReferenceGenomesParams;

    /*
        Struct containing data for a single genome output by the list_reference_genomes function
        
    */
    typedef structure {
        string accession;
        string status;
        string name;
        string ftp_dir;
        string file;
        string id;
        string version;
        string source;
        string domain;
    } ReferenceGenomeData;

    /*
        Lists genomes present in selected reference databases (ensembl, phytozome, refseq)
    */
    funcdef list_reference_genomes(ListReferenceGenomesParams params) returns (list<ReferenceGenomeData> output);
    
    /*
        Arguments for the list_loaded_genomes function
        
    */
    typedef structure {
        bool ensembl;
        bool refseq;
        bool phytozome;
	string workspace_name;
	bool create_report;
   } ListLoadedGenomesParams;
    
    /*
        Struct containing data for a single genome output by the list_loaded_genomes function
        
    */
    typedef structure {
        string ref;
        string id;
        string workspace_name;
        string source_id;
        string accession;
        string name;
        string ftp_dir;
        string version;
        string source;
        string domain; 
    } KBaseReferenceGenomeData;

    /*
        Lists genomes loaded into KBase from selected reference sources (ensembl, phytozome, refseq)
    */
    funcdef list_loaded_genomes(ListLoadedGenomesParams params) returns (list<KBaseReferenceGenomeData> output);
    
    /*
        Arguments for the load_genomes function
        
    */
    typedef structure {
        string data;
	list<ReferenceGenomeData> genomes;
        bool index_in_solr;
	string workspace_name;
	bool create_report;
    } LoadGenomesParams;
    
    /*
        Loads specified genomes into KBase workspace and indexes in SOLR on demand
    */
    funcdef load_genomes(LoadGenomesParams params) returns (list<KBaseReferenceGenomeData> output) authentication required;
    
    /*
        Arguments for the index_genomes_in_solr function
        
    */
    typedef structure {
        list<KBaseReferenceGenomeData> genomes;
        string workspace_name;
        bool creat_report;
    } IndexGenomesInSolrParams;
    
    /*
        Index specified genomes in SOLR from KBase workspace
    */
    funcdef index_genomes_in_solr(IndexGenomesInSolrParams params) returns (list<KBaseReferenceGenomeData> output) authentication required;
    
    /*
        Arguments for the update_loaded_genomes function
        
    */
    typedef structure {
        bool ensembl;
        bool refseq;
        bool phytozome;
        list<ReferenceGenomeData> genomeData;
	string workspace_name;
        bool create_report;
	string fileformats;
    } UpdateLoadedGenomesParams;
    
    /*
        Updates the loaded genomes in KBase for the specified source databases
    */
    funcdef update_loaded_genomes(UpdateLoadedGenomesParams params) returns (list<KBaseReferenceGenomeData> output) authentication required;
};
