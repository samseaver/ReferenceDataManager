
package us.kbase.referencedatamanager;

import java.util.HashMap;
import java.util.Map;
import javax.annotation.Generated;
import com.fasterxml.jackson.annotation.JsonAnyGetter;
import com.fasterxml.jackson.annotation.JsonAnySetter;
import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.annotation.JsonPropertyOrder;


/**
 * <p>Original spec-file type: ListLoadedGenomesParams</p>
 * <pre>
 * Arguments for the list_loaded_genomes function
 * </pre>
 * 
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
@Generated("com.googlecode.jsonschema2pojo")
@JsonPropertyOrder({
    "ensembl",
    "refseq",
    "phytozome",
    "workspace",
    "create_report"
})
public class ListLoadedGenomesParams {

    @JsonProperty("ensembl")
    private Long ensembl;
    @JsonProperty("refseq")
    private Long refseq;
    @JsonProperty("phytozome")
    private Long phytozome;
    @JsonProperty("workspace")
    private String workspace;
    @JsonProperty("create_report")
    private Long createReport;
    private Map<String, Object> additionalProperties = new HashMap<String, Object>();

    @JsonProperty("ensembl")
    public Long getEnsembl() {
        return ensembl;
    }

    @JsonProperty("ensembl")
    public void setEnsembl(Long ensembl) {
        this.ensembl = ensembl;
    }

    public ListLoadedGenomesParams withEnsembl(Long ensembl) {
        this.ensembl = ensembl;
        return this;
    }

    @JsonProperty("refseq")
    public Long getRefseq() {
        return refseq;
    }

    @JsonProperty("refseq")
    public void setRefseq(Long refseq) {
        this.refseq = refseq;
    }

    public ListLoadedGenomesParams withRefseq(Long refseq) {
        this.refseq = refseq;
        return this;
    }

    @JsonProperty("phytozome")
    public Long getPhytozome() {
        return phytozome;
    }

    @JsonProperty("phytozome")
    public void setPhytozome(Long phytozome) {
        this.phytozome = phytozome;
    }

    public ListLoadedGenomesParams withPhytozome(Long phytozome) {
        this.phytozome = phytozome;
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

    public ListLoadedGenomesParams withWorkspace(String workspace) {
        this.workspace = workspace;
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

    public ListLoadedGenomesParams withCreateReport(Long createReport) {
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
        return ((((((((((((("ListLoadedGenomesParams"+" [ensembl=")+ ensembl)+", refseq=")+ refseq)+", phytozome=")+ phytozome)+", workspace=")+ workspace)+", createReport=")+ createReport)+", additionalProperties=")+ additionalProperties)+"]");
    }

}
