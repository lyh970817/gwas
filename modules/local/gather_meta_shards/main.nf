process GATHER_META_SHARDS {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/18/1841daa69f98a0b0ffcb8f545070c8350a75febb167202136eab0990131d31c0/data'
        : 'community.wave.seqera.io/library/python:3.14.5--dc8358b3c5eeb927'}"

    input:
    tuple val(meta), path(shards, stageAs: 'shards/*'), path(records, stageAs: 'records/*'), val(expected_chromosomes)

    output:
    tuple val(meta), path("${prefix}.gathered.tsv.gz"), emit: gathered
    tuple val(meta), path("${prefix}.gather_report.json"), emit: report
    path "versions.yml", emit: versions, topic: versions

    script:
    prefix = task.ext.prefix ?: meta.id
    // A single staged file arrives as a Path, and Groovy's `collect` iterates a Path's name
    // components rather than treating it as one element. Normalise before collecting.
    shards_literal = groovy.json.JsonOutput.toJson(
        (shards instanceof List ? shards : [shards]).collect { shard -> shard.toString() }
    )
    records_literal = groovy.json.JsonOutput.toJson(
        (records instanceof List ? records : [records]).collect { record -> record.toString() }
    )
    expected_literal = groovy.json.JsonOutput.toJson(
        (expected_chromosomes instanceof List ? expected_chromosomes : [expected_chromosomes])
            .collect { chromosome -> chromosome.toString() }
    )
    prefix_literal = groovy.json.JsonOutput.toJson(prefix.toString())
    template("gather_meta_shards.py")

    stub:
    prefix = task.ext.prefix ?: meta.id
    """
    printf 'SNPID\tCHR\tPOS\tEA\tNEA\tSTATUS\tEAF\tBETA\tSE\tP\tN\tMETA_VARIANT_KEY\\n' \\
        | gzip -n -c > "${prefix}.gathered.tsv.gz"
    printf '{"schema_version":"1.0","stub":true}\\n' > "${prefix}.gather_report.json"
    printf '"${task.process}":\\n    python: %s\\n' "\$(python3 --version | sed 's/^Python //')" > versions.yml
    """
}
