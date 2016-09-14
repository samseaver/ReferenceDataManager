
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
 * <p>Original spec-file type: ReferenceGenomeData</p>
 * <pre>
 * Struct containing data for a single genome output by the list_reference_genomes function
 * </pre>
 * 
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
@Generated("com.googlecode.jsonschema2pojo")
@JsonPropertyOrder({
    "accession",
    "status",
    "name",
    "ftp_dir",
    "file",
    "id",
    "version",
    "source",
    "domain"
})
public class ReferenceGenomeData {

    @JsonProperty("accession")
    private String accession;
    @JsonProperty("status")
    private String status;
    @JsonProperty("name")
    private String name;
    @JsonProperty("ftp_dir")
    private String ftpDir;
    @JsonProperty("file")
    private String file;
    @JsonProperty("id")
    private String id;
    @JsonProperty("version")
    private String version;
    @JsonProperty("source")
    private String source;
    @JsonProperty("domain")
    private String domain;
    private Map<String, Object> additionalProperties = new HashMap<String, Object>();

    @JsonProperty("accession")
    public String getAccession() {
        return accession;
    }

    @JsonProperty("accession")
    public void setAccession(String accession) {
        this.accession = accession;
    }

    public ReferenceGenomeData withAccession(String accession) {
        this.accession = accession;
        return this;
    }

    @JsonProperty("status")
    public String getStatus() {
        return status;
    }

    @JsonProperty("status")
    public void setStatus(String status) {
        this.status = status;
    }

    public ReferenceGenomeData withStatus(String status) {
        this.status = status;
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

    public ReferenceGenomeData withName(String name) {
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

    public ReferenceGenomeData withFtpDir(String ftpDir) {
        this.ftpDir = ftpDir;
        return this;
    }

    @JsonProperty("file")
    public String getFile() {
        return file;
    }

    @JsonProperty("file")
    public void setFile(String file) {
        this.file = file;
    }

    public ReferenceGenomeData withFile(String file) {
        this.file = file;
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

    public ReferenceGenomeData withId(String id) {
        this.id = id;
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

    public ReferenceGenomeData withVersion(String version) {
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

    public ReferenceGenomeData withSource(String source) {
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

    public ReferenceGenomeData withDomain(String domain) {
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
        return ((((((((((((((((((((("ReferenceGenomeData"+" [accession=")+ accession)+", status=")+ status)+", name=")+ name)+", ftpDir=")+ ftpDir)+", file=")+ file)+", id=")+ id)+", version=")+ version)+", source=")+ source)+", domain=")+ domain)+", additionalProperties=")+ additionalProperties)+"]");
    }

}
