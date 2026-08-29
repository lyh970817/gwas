// Genome-wide marker set for MR-MEGA pass 1, which derives the axes of genetic variation and
// nothing else. MR-MEGA's own axis derivation already keeps at most one marker per megabase on
// chromosomes 1-23 with EAF strictly inside (0.01, 0.99) in every study, so thinning to the same
// resolution here loses no axis information while bounding the memory of a pass that otherwise
// materialises every shared marker to build the between-study distance matrix.
//
// The emitted table carries the identical column schema as its input, so it is a drop-in
// replacement for the gathered study views wherever PREPARE_MRMEGA_INPUT is fed.
process THIN_MRMEGA_MARKERS {
    tag "${meta.id}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/18/1841daa69f98a0b0ffcb8f545070c8350a75febb167202136eab0990131d31c0/data'
        : 'community.wave.seqera.io/library/python:3.14.5--dc8358b3c5eeb927'}"

    input:
    tuple val(meta), path(study_views, stageAs: 'views/*'), val(study_count)

    output:
    tuple val(meta), path("${prefix}.thinned_views.tsv.gz"), emit: thinned
    tuple val(meta), path("${prefix}.thin_qc.json"), emit: qc
    path "versions.yml", emit: versions, topic: versions

    script:
    prefix = task.ext.prefix ?: meta.id
    // A single staged file arrives as a Path, and Groovy's `collect` iterates a Path's name
    // components rather than treating it as one element. Normalise before collecting.
    views_literal = groovy.json.JsonOutput.toJson(
        (study_views instanceof List ? study_views : [study_views]).collect { view -> view.toString() }
    )
    study_count_literal = groovy.json.JsonOutput.toJson(study_count.toString())
    prefix_literal = groovy.json.JsonOutput.toJson(prefix.toString())
    template("thin_mrmega_markers.py")

    stub:
    prefix = task.ext.prefix ?: meta.id
    def studies = Math.max(1, study_count as int)
    def header = (
        ['META_VARIANT_KEY', 'SNPID', 'CHR', 'POS', 'EA', 'NEA'] + (1..studies).collectMany { index ->
            ["STATUS_${index}", "EAF_${index}", "BETA_${index}", "SE_${index}", "P_${index}", "N_${index}"]
        }
    ).join('\t')
    """
    printf '${header}\\n' | gzip -n -c > "${prefix}.thinned_views.tsv.gz"
    printf '{"schema_version":"1.0","stub":true}\\n' > "${prefix}.thin_qc.json"
    printf '"${task.process}":\\n    python: %s\\n' "\$(python3 --version | sed 's/^Python //')" > versions.yml
    """
}
