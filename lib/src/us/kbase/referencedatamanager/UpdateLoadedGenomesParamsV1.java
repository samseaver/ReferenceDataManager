
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
 * <p>Original spec-file type: UpdateLoadedGenomesParams_v1</p>
 * <pre>
 * Arguments for the update_loaded_genomes_v1 function
 * </pre>
 * 
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
@Generated("com.googlecode.jsonschema2pojo")
@JsonPropertyOrder({
    "ensembl",
    "refseq",
    "phytozome",
    "genomeData",
    "workspace_name",
    "create_report",
    "fileformats"
})
public class UpdateLoadedGenomesParamsV1 {

    @JsonProperty("ensembl")
    private Long ensembl;
    @JsonProperty("refseq")
    private Long refseq;
    @JsonProperty("phytozome")
    private Long phytozome;
    @JsonProperty("genomeData")
    private List<ReferenceGenomeData> genomeData;
    @JsonProperty("workspace_name")
    private String workspaceName;
    @JsonProperty("create_report")
    private Long createReport;
    @JsonProperty("fileformats")
    private String fileformats;
    private Map<String, Object> additionalProperties = new HashMap<String, Object>();

    @JsonProperty("ensembl")
    public Long getEnsembl() {
        return ensembl;
    }

    @JsonProperty("ensembl")
    public void setEnsembl(Long ensembl) {
        this.ensembl = ensembl;
    }

    public UpdateLoadedGenomesParamsV1 withEnsembl(Long ensembl) {
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

    public UpdateLoadedGenomesParamsV1 withRefseq(Long refseq) {
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

    public UpdateLoadedGenomesParamsV1 withPhytozome(Long phytozome) {
        this.phytozome = phytozome;
        return this;
    }

    @JsonProperty("genomeData")
    public List<ReferenceGenomeData> getGenomeData() {
        return genomeData;
    }

    @JsonProperty("genomeData")
    public void setGenomeData(List<ReferenceGenomeData> genomeData) {
        this.genomeData = genomeData;
    }

    public UpdateLoadedGenomesParamsV1 withGenomeData(List<ReferenceGenomeData> genomeData) {
        this.genomeData = genomeData;
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

    public UpdateLoadedGenomesParamsV1 withWorkspaceName(String workspaceName) {
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

    public UpdateLoadedGenomesParamsV1 withCreateReport(Long createReport) {
        this.createReport = createReport;
        return this;
    }

    @JsonProperty("fileformats")
    public String getFileformats() {
        return fileformats;
    }

    @JsonProperty("fileformats")
    public void setFileformats(String fileformats) {
        this.fileformats = fileformats;
    }

    public UpdateLoadedGenomesParamsV1 withFileformats(String fileformats) {
        this.fileformats = fileformats;
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
        return ((((((((((((((((("UpdateLoadedGenomesParamsV1"+" [ensembl=")+ ensembl)+", refseq=")+ refseq)+", phytozome=")+ phytozome)+", genomeData=")+ genomeData)+", workspaceName=")+ workspaceName)+", createReport=")+ createReport)+", fileformats=")+ fileformats)+", additionalProperties=")+ additionalProperties)+"]");
    }

}
