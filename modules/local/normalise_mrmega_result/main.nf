// Map the native MR-MEGA `.result` into the keyed schema NORMALISE_COMMON_VARIANT_META accepts.
// This is pure column mapping: `MarkerName` already IS the `META_VARIANT_KEY`, because
// PREPARE_MRMEGA_INPUT wrote the allele-aware key there rather than an rsID, so nothing is
// re-derived and nothing is joined on a name.
//
// The three native `P-value_*` columns are carried through only as `MRMEGA_NATIVE_P_*`, for debug
// provenance. They are numerically invalid whenever the corresponding `ndf` is not 2, and which of
// the three is sound flips with `--pc` and the study count, so the downstream normalizer discards
// all three unconditionally and recomputes the tail in log space. Nothing here recomputes them and
// nothing here publishes them as a result.
process NORMALISE_MRMEGA_RESULT {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/18/1841daa69f98a0b0ffcb8f545070c8350a75febb167202136eab0990131d31c0/data'
        : 'community.wave.seqera.io/library/python:3.14.5--dc8358b3c5eeb927'}"

    input:
    tuple val(meta), path(mrmega_result), val(axes)

    output:
    tuple val(meta), path("${prefix}.mrmega_fields.tsv.gz"), emit: fields
    tuple val(meta), path("${prefix}.mrmega_qc.json"), emit: qc
    path "versions.yml", emit: versions, topic: versions

    script:
    prefix = task.ext.prefix ?: meta.id
    result_literal = groovy.json.JsonOutput.toJson(mrmega_result.toString())
    axes_literal = groovy.json.JsonOutput.toJson(axes.toString())
    prefix_literal = groovy.json.JsonOutput.toJson(prefix.toString())
    template("normalise_mrmega_result.py")

    stub:
    prefix = task.ext.prefix ?: meta.id
    def header = [
        'META_VARIANT_KEY',
        'MRMEGA_CHISQ_ASSOC',
        'MRMEGA_CHISQ_ANCESTRY_HET',
        'MRMEGA_CHISQ_RESIDUAL_HET',
        'MRMEGA_DF_ASSOC',
        'MRMEGA_DF_ANCESTRY_HET',
        'MRMEGA_DF_RESIDUAL_HET',
        'MRMEGA_NATIVE_P_ASSOC',
        'MRMEGA_NATIVE_P_ANCESTRY_HET',
        'MRMEGA_NATIVE_P_RESIDUAL_HET',
        'MRMEGA_LNBF',
    ].join('\t')
    """
    printf '${header}\\n' | gzip -n -c > "${prefix}.mrmega_fields.tsv.gz"
    printf '{"schema_version":"1.0","stub":true}\\n' > "${prefix}.mrmega_qc.json"
    printf '"${task.process}":\\n    python: %s\\n' "\$(python3 --version | sed 's/^Python //')" > versions.yml
    """
}
