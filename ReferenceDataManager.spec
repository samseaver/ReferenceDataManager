/*
A KBase module: ReferenceDataManager
This sample module contains one small method - filter_contigs.
*/

module ReferenceDataManager {
    /*
        A string representing a workspace name.
    */
    typedef string workspace_name;

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
        string id;
        string source;
        string version;
    } ReferenceGenomeData;
    
    /*
        Lists genomes present in selected reference databases (ensembl, phytozome, refseq)
    */
    funcdef list_reference_Genomes(ListReferenceGenomesParams params) returns (list<ReferenceGenomeData> output);
    /*authentication required;*/
};
