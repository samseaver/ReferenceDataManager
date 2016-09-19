
package us.kbase.referencedatamanager;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import javax.annotation.Generated;
import com.fasterxml.jackson.annotation.JsonAnyGetter;
import com.fasterxml.jackson.annotation.JsonAnySetter;
import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.annotation.JsonPropertyOrder;


/**
 * <p>Original spec-file type: IndexGenomesInSolrParams</p>
 * <pre>
 * Arguments for the index_genomes_in_solr function
 * </pre>
 * 
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
@Generated("com.googlecode.jsonschema2pojo")
@JsonPropertyOrder({
    "genomes",
    "workspace",
    "creat_report"
})
public class IndexGenomesInSolrParams {

    @JsonProperty("genomes")
    private List<KBaseReferenceGenomeData> genomes;
    @JsonProperty("workspace")
    private String workspace;
    @JsonProperty("creat_report")
    private Long creatReport;
    private Map<String, Object> additionalProperties = new HashMap<String, Object>();

    @JsonProperty("genomes")
    public List<KBaseReferenceGenomeData> getGenomes() {
        return genomes;
    }

    @JsonProperty("genomes")
    public void setGenomes(List<KBaseReferenceGenomeData> genomes) {
        this.genomes = genomes;
    }

    public IndexGenomesInSolrParams withGenomes(List<KBaseReferenceGenomeData> genomes) {
        this.genomes = genomes;
        return this;
    }

    @JsonProperty("workspace")
    public String getWorkspace() {
        return workspace;
    }

    @JsonProperty("workspace")
    public void setWorkspace(String workspace) {
        this.workspace = workspace;
    }

    public IndexGenomesInSolrParams withWorkspace(String workspace) {
        this.workspace = workspace;
        return this;
    }

    @JsonProperty("creat_report")
    public Long getCreatReport() {
        return creatReport;
    }

    @JsonProperty("creat_report")
    public void setCreatReport(Long creatReport) {
        this.creatReport = creatReport;
    }

    public IndexGenomesInSolrParams withCreatReport(Long creatReport) {
        this.creatReport = creatReport;
        return this;
    }

    @JsonAnyGetter
    public Map<String, Object> getAdditionalProperties() {
        return this.additionalProperties;
    }

    @JsonAnySetter
    public void setAdditionalProperties(String name, Object value) {
        this.additionalProperties.put(name, value);
    }

    @Override
    public String toString() {
        return ((((((((("IndexGenomesInSolrParams"+" [genomes=")+ genomes)+", workspace=")+ workspace)+", creatReport=")+ creatReport)+", additionalProperties=")+ additionalProperties)+"]");
    }

}
