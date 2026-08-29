process EXTRACT_MRMEGA_AXES {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/18/1841daa69f98a0b0ffcb8f545070c8350a75febb167202136eab0990131d31c0/data'
        : 'community.wave.seqera.io/library/python:3.14.5--dc8358b3c5eeb927'}"

    input:
    tuple val(meta), path(mrmega_log), path(filelist), val(axes)

    output:
    tuple val(meta), path("${prefix}.precalculated_axes.txt"), emit: precalculated_axes
    tuple val(meta), path("${prefix}.ancestry_axes.tsv"), emit: coordinates
    tuple val(meta), path("${prefix}.axes_qc.json"), emit: qc
    path "versions.yml", emit: versions, topic: versions

    script:
    prefix = task.ext.prefix ?: meta.id
    log_literal = groovy.json.JsonOutput.toJson(mrmega_log.toString())
    filelist_literal = groovy.json.JsonOutput.toJson(filelist.toString())
    axes_literal = groovy.json.JsonOutput.toJson(axes.toString())
    prefix_literal = groovy.json.JsonOutput.toJson(prefix.toString())
    template("extract_mrmega_axes.py")

    stub:
    prefix = task.ext.prefix ?: meta.id
    """
    printf 'study_a.txt.gz 0.1\\nstudy_b.txt.gz -0.1\\nstudy_c.txt.gz 0.0\\n' > "${prefix}.precalculated_axes.txt"
    printf 'study_index\tstudy_name\tAXIS_1\\n1\tstudy_a.txt.gz\t0.1\\n' > "${prefix}.ancestry_axes.tsv"
    printf '{"schema_version":"1.0","stub":true}\\n' > "${prefix}.axes_qc.json"
    printf '"${task.process}":\\n    python: %s\\n' "\$(python3 --version | sed 's/^Python //')" > versions.yml
    """
}
