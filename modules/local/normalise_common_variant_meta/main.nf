process NORMALISE_COMMON_VARIANT_META {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/18/1841daa69f98a0b0ffcb8f545070c8350a75febb167202136eab0990131d31c0/data'
        : 'community.wave.seqera.io/library/python:3.14.5--dc8358b3c5eeb927'}"

    input:
    tuple val(meta), path(meta_analysis, stageAs: 'upstream/*'), path(study_order, stageAs: 'upstream/*'), path(qc, stageAs: 'upstream/*'), path(derivation, stageAs: 'upstream/*'), path(re2, stageAs: 're2/*'), path(mrmega, stageAs: 'mrmega/*')

    output:
    tuple val(meta), path("${prefix}.candidate.tsv.gz"), emit: candidate
    tuple val(meta), path("${prefix}.derivation.json"), emit: derivation
    path "versions.yml", emit: versions, topic: versions

    script:
    prefix = task.ext.prefix ?: meta.id
    meta_analysis_literal = groovy.json.JsonOutput.toJson(meta_analysis.toString())
    study_order_literal = groovy.json.JsonOutput.toJson(study_order.toString())
    qc_literal = groovy.json.JsonOutput.toJson(qc.toString())
    upstream_derivation_literal = groovy.json.JsonOutput.toJson(derivation.toString())
    re2_literal = re2 ? groovy.json.JsonOutput.toJson(re2.toString()) : 'None'
    mrmega_literal = mrmega ? groovy.json.JsonOutput.toJson(mrmega.toString()) : 'None'
    prefix_literal = groovy.json.JsonOutput.toJson(prefix.toString())
    template("normalise_common_variant_meta.py")

    stub:
    prefix = task.ext.prefix ?: meta.id
    def columns = [
        'SNPID',
        'CHR',
        'POS',
        'EA',
        'NEA',
        'STATUS',
        'EAF',
        'BETA',
        'SE',
        'P',
        'N',
        'N_STUDIES',
        'DIRECTION',
        'EAF_META',
        'EAF_MIN',
        'EAF_MAX',
        'N_TOTAL',
        'MAX_WEIGHT_SHARE',
        'Z_FIXED',
        'Q',
        'P_HET',
        'I2',
    ]
    if (re2) {
        columns += ['P_RE2', 'RE2_MEAN_COMPONENT', 'RE2_HET_COMPONENT', 'RE2_STATUS']
    }
    if (mrmega) {
        columns += [
            'MRMEGA_CHISQ_ASSOC',
            'MRMEGA_DF_ASSOC',
            'MRMEGA_LOG10P_ASSOC',
            'MRMEGA_P_ASSOC',
            'MRMEGA_CHISQ_ANCESTRY_HET',
            'MRMEGA_DF_ANCESTRY_HET',
            'MRMEGA_LOG10P_ANCESTRY_HET',
            'MRMEGA_P_ANCESTRY_HET',
            'MRMEGA_CHISQ_RESIDUAL_HET',
            'MRMEGA_DF_RESIDUAL_HET',
            'MRMEGA_LOG10P_RESIDUAL_HET',
            'MRMEGA_P_RESIDUAL_HET',
            'MRMEGA_LNBF',
        ]
    }
    columns += ['META_VARIANT_KEY']
    def header = columns.join('\t')
    def stub_derivation = groovy.json.JsonOutput.toJson(
        [
            schema_version: '1.0',
            operation: 'normalise_common_variant_meta',
            prefix: prefix.toString(),
            models: [
                fixed: true,
                random: false,
                re2_joined: re2 ? true : false,
                mrmega_joined: mrmega ? true : false,
            ],
            candidate_columns: columns,
            stub: true,
        ]
    )
    """
    printf '${header}\\n' | gzip -n -c > "${prefix}.candidate.tsv.gz"
    printf '%s\\n' '${stub_derivation}' > "${prefix}.derivation.json"
    printf '"${task.process}":\\n    python: %s\\n' "\$(python3 --version | sed 's/^Python //')" > "versions.yml"
    """
}
