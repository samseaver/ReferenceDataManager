
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
 * <p>Original spec-file type: ReferenceTaxonData</p>
 * <pre>
 * Struct containing data for a single taxon output by the list_loaded_taxons function
 * </pre>
 * 
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
@Generated("com.googlecode.jsonschema2pojo")
@JsonPropertyOrder({
    "ref",
    "id",
    "workspace_name",
    "source_id",
    "accession",
    "name",
    "ftp_dir",
    "version",
    "source",
    "domain"
})
public class ReferenceTaxonData {

    @JsonProperty("ref")
    private String ref;
    @JsonProperty("id")
    private String id;
    @JsonProperty("workspace_name")
    private String workspaceName;
    @JsonProperty("source_id")
    private String sourceId;
    @JsonProperty("accession")
    private String accession;
    @JsonProperty("name")
    private String name;
    @JsonProperty("ftp_dir")
    private String ftpDir;
    @JsonProperty("version")
    private String version;
    @JsonProperty("source")
    private String source;
    @JsonProperty("domain")
    private String domain;
    private Map<String, Object> additionalProperties = new HashMap<String, Object>();

    @JsonProperty("ref")
    public String getRef() {
        return ref;
    }

    @JsonProperty("ref")
    public void setRef(String ref) {
        this.ref = ref;
    }

    public ReferenceTaxonData withRef(String ref) {
        this.ref = ref;
        return this;
    }

    @JsonProperty("id")
    public String getId() {
        return id;
    }

    @JsonProperty("id")
    public void setId(String id) {
        this.id = id;
    }

    public ReferenceTaxonData withId(String id) {
        this.id = id;
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

    public ReferenceTaxonData withWorkspaceName(String workspaceName) {
        this.workspaceName = workspaceName;
        return this;
    }

    @JsonProperty("source_id")
    public String getSourceId() {
        return sourceId;
    }

    @JsonProperty("source_id")
    public void setSourceId(String sourceId) {
        this.sourceId = sourceId;
    }

    public ReferenceTaxonData withSourceId(String sourceId) {
        this.sourceId = sourceId;
        return this;
    }

    @JsonProperty("accession")
    public String getAccession() {
        return accession;
    }

    @JsonProperty("accession")
    public void setAccession(String accession) {
        this.accession = accession;
    }

    public ReferenceTaxonData withAccession(String accession) {
        this.accession = accession;
        return this;
    }

    @JsonProperty("name")
    public String getName() {
        return name;
    }

    @JsonProperty("name")
    public void setName(String name) {
        this.name = name;
    }

    public ReferenceTaxonData withName(String name) {
        this.name = name;
        return this;
    }

    @JsonProperty("ftp_dir")
    public String getFtpDir() {
        return ftpDir;
    }

    @JsonProperty("ftp_dir")
    public void setFtpDir(String ftpDir) {
        this.ftpDir = ftpDir;
    }

    public ReferenceTaxonData withFtpDir(String ftpDir) {
        this.ftpDir = ftpDir;
        return this;
    }

    @JsonProperty("version")
    public String getVersion() {
        return version;
    }

    @JsonProperty("version")
    public void setVersion(String version) {
        this.version = version;
    }

    public ReferenceTaxonData withVersion(String version) {
        this.version = version;
        return this;
    }

    @JsonProperty("source")
    public String getSource() {
        return source;
    }

    @JsonProperty("source")
    public void setSource(String source) {
        this.source = source;
    }

    public ReferenceTaxonData withSource(String source) {
        this.source = source;
        return this;
    }

    @JsonProperty("domain")
    public String getDomain() {
        return domain;
    }

    @JsonProperty("domain")
    public void setDomain(String domain) {
        this.domain = domain;
    }

    public ReferenceTaxonData withDomain(String domain) {
        this.domain = domain;
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
        return ((((((((((((((((((((((("ReferenceTaxonData"+" [ref=")+ ref)+", id=")+ id)+", workspaceName=")+ workspaceName)+", sourceId=")+ sourceId)+", accession=")+ accession)+", name=")+ name)+", ftpDir=")+ ftpDir)+", version=")+ version)+", source=")+ source)+", domain=")+ domain)+", additionalProperties=")+ additionalProperties)+"]");
    }

}
