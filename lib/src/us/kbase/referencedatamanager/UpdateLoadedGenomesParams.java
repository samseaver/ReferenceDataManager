
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
 * <p>Original spec-file type: UpdateLoadedGenomesParams</p>
 * <pre>
 * Arguments for the update_loaded_genomes function
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
    "creat_report",
    "formats"
})
public class UpdateLoadedGenomesParams {

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
    @JsonProperty("creat_report")
    private Long creatReport;
    @JsonProperty("formats")
    private String formats;
    private Map<String, Object> additionalProperties = new HashMap<String, Object>();

    @JsonProperty("ensembl")
    public Long getEnsembl() {
        return ensembl;
    }

    @JsonProperty("ensembl")
    public void setEnsembl(Long ensembl) {
        this.ensembl = ensembl;
    }

    public UpdateLoadedGenomesParams withEnsembl(Long ensembl) {
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

    public UpdateLoadedGenomesParams withRefseq(Long refseq) {
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

    public UpdateLoadedGenomesParams withPhytozome(Long phytozome) {
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

    public UpdateLoadedGenomesParams withGenomeData(List<ReferenceGenomeData> genomeData) {
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

    public UpdateLoadedGenomesParams withWorkspaceName(String workspaceName) {
        this.workspaceName = workspaceName;
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

    public UpdateLoadedGenomesParams withCreatReport(Long creatReport) {
        this.creatReport = creatReport;
        return this;
    }

    @JsonProperty("formats")
    public String getFormats() {
        return formats;
    }

    @JsonProperty("formats")
    public void setFormats(String formats) {
        this.formats = formats;
    }

    public UpdateLoadedGenomesParams withFormats(String formats) {
        this.formats = formats;
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
        return ((((((((((((((((("UpdateLoadedGenomesParams"+" [ensembl=")+ ensembl)+", refseq=")+ refseq)+", phytozome=")+ phytozome)+", genomeData=")+ genomeData)+", workspaceName=")+ workspaceName)+", creatReport=")+ creatReport)+", formats=")+ formats)+", additionalProperties=")+ additionalProperties)+"]");
    }

}
