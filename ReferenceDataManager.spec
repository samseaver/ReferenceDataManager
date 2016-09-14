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
    funcdef list_reference_Genomes(ListReferenceGenomesParams params) returns (list<ReferenceGenomeData> output);
    /*authentication required;*/
};
