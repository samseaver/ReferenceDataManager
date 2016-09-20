
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
 * <p>Original spec-file type: LoadGenomesParams</p>
 * <pre>
 * Arguments for the load_genomes function
 * </pre>
 * 
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
@Generated("com.googlecode.jsonschema2pojo")
@JsonPropertyOrder({
    "data",
    "genomes",
    "index_in_solr",
    "workspace_name",
    "create_report"
})
public class LoadGenomesParams {

    @JsonProperty("data")
    private String data;
    @JsonProperty("genomes")
    private List<ReferenceGenomeData> genomes;
    @JsonProperty("index_in_solr")
    private Long indexInSolr;
    @JsonProperty("workspace_name")
    private String workspaceName;
    @JsonProperty("create_report")
    private Long createReport;
    private Map<String, Object> additionalProperties = new HashMap<String, Object>();

    @JsonProperty("data")
    public String getData() {
        return data;
    }

    @JsonProperty("data")
    public void setData(String data) {
        this.data = data;
    }

    public LoadGenomesParams withData(String data) {
        this.data = data;
        return this;
    }

    @JsonProperty("genomes")
    public List<ReferenceGenomeData> getGenomes() {
        return genomes;
    }

    @JsonProperty("genomes")
    public void setGenomes(List<ReferenceGenomeData> genomes) {
        this.genomes = genomes;
    }

    public LoadGenomesParams withGenomes(List<ReferenceGenomeData> genomes) {
        this.genomes = genomes;
        return this;
    }

    @JsonProperty("index_in_solr")
    public Long getIndexInSolr() {
        return indexInSolr;
    }

    @JsonProperty("index_in_solr")
    public void setIndexInSolr(Long indexInSolr) {
        this.indexInSolr = indexInSolr;
    }

    public LoadGenomesParams withIndexInSolr(Long indexInSolr) {
        this.indexInSolr = indexInSolr;
        return this;
    }

    @JsonProperty("workspace_name")
    public String getWorkspaceName() {
        return workspaceName;
    }

    @JsonProperty("workspace_name")
    public void setWorkspaceName(String workspaceName) {
        this.workspaceName = workspaceName;
    }

    public LoadGenomesParams withWorkspaceName(String workspaceName) {
        this.workspaceName = workspaceName;
        return this;
    }

    @JsonProperty("create_report")
    public Long getCreateReport() {
        return createReport;
    }

    @JsonProperty("create_report")
    public void setCreateReport(Long createReport) {
        this.createReport = createReport;
    }

    public LoadGenomesParams withCreateReport(Long createReport) {
        this.createReport = createReport;
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
        return ((((((((((((("LoadGenomesParams"+" [data=")+ data)+", genomes=")+ genomes)+", indexInSolr=")+ indexInSolr)+", workspaceName=")+ workspaceName)+", createReport=")+ createReport)+", additionalProperties=")+ additionalProperties)+"]");
    }

}
