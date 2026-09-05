process PREPARE_MPH_INPUTS {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/18/1841daa69f98a0b0ffcb8f545070c8350a75febb167202136eab0990131d31c0/data'
        : 'community.wave.seqera.io/library/python:3.14.5--dc8358b3c5eeb927'}"

    input:
    // The analysis-owned tables are staged under `input/` for the reason `prepare_phenotype_inputs` documents:
    // an analysis named after one of its own files would otherwise have this task write back through a staged
    // symlink onto the researcher's source.
    tuple val(meta), path(phenotype_table, stageAs: 'input/*'), path(quant_covariates, stageAs: 'input/*'), path(cat_covariates, stageAs: 'input/*')
    tuple val(meta2), path(grm_iid), path(fam)

    output:
    tuple val(meta), path("${prefix}.mph.pheno.csv"), emit: phenotype
    tuple val(meta), path("${prefix}.mph.covar.csv"), emit: covariates, optional: true
    // Not published. It is the machine-readable record of what this task decided, and the input to the writer
    // that publishes the sidecar after the fit, so exactly one component computes each value.
    tuple val(meta), path("${prefix}.mph.inputs.json"), emit: serialization
    path 'versions.yml', emit: versions, topic: versions


    script:
    // `prefix` must remain visible to the output declarations. Every other assignment must remain visible to
    // the template and hold a JSON string literal, which is also valid Python syntax.
    prefix = task.ext.prefix ?: "${meta.id}"
    phenotype_table_literal = groovy.json.JsonOutput.toJson(phenotype_table.toString())
    quant_covariates_literal = groovy.json.JsonOutput.toJson(quant_covariates ? quant_covariates.toString() : '')
    cat_covariates_literal = groovy.json.JsonOutput.toJson(cat_covariates ? cat_covariates.toString() : '')
    grm_iid_literal = groovy.json.JsonOutput.toJson(grm_iid.toString())
    fam_literal = groovy.json.JsonOutput.toJson(fam.toString())
    prefix_literal = groovy.json.JsonOutput.toJson(prefix.toString())
    analysis_id_literal = groovy.json.JsonOutput.toJson(meta.id.toString())
    task_process_literal = groovy.json.JsonOutput.toJson(task.process.toString())
    // The result block the sidecar is keyed by. It is supplied by the route rather than assembled here,
    // because whether a fit is a unary heritability estimate or an oriented pair is a routing fact: the same
    // serializer writes both and must not switch on the trait count to decide which identity it is publishing.
    result_literal = groovy.json.JsonOutput.toJson(groovy.json.JsonOutput.toJson(meta.mph_result))
    // Serialised twice on purpose: the inner call renders the structure as JSON, the outer one renders that
    // JSON as a quoted string. A bare JSON object is not valid Python -- its `null`, `true` and `false` are
    // not Python literals -- so the template parses a string rather than embedding an expression.
    trait_names_literal = groovy.json.JsonOutput.toJson(groovy.json.JsonOutput.toJson(meta.mph_trait_names))
    effective_literal = groovy.json.JsonOutput.toJson(groovy.json.JsonOutput.toJson(meta.mph_effective))
    matrix_literal = groovy.json.JsonOutput.toJson(groovy.json.JsonOutput.toJson(meta.mph_matrix))
    // The staged matrix prefixes in component order. MPH copies each one verbatim into its result's
    // `vc_name`, so recording them here is what lets the post-fit writer match components by name instead of
    // by row position.
    grm_prefixes_literal = groovy.json.JsonOutput.toJson(groovy.json.JsonOutput.toJson(meta.mph_grm_prefixes))
    capability_literal = groovy.json.JsonOutput.toJson(groovy.json.JsonOutput.toJson(meta.mph_capability))
    template('prepare_mph_inputs.py')

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    def stub_traits = meta.mph_trait_names.join(',')
    def stub_trait_values = meta.mph_trait_names.collect { '0' }.join(',')
    // The covariate file is written only when the analysis supplied covariates, so a stub run exercises the
    // same optional-output cardinality the real script produces.
    def stub_covariates = quant_covariates || cat_covariates
        ? "printf 'IID,intercept,stub_covariate\\nstub,1,0\\n' > \"${prefix}.mph.covar.csv\""
        : ''
    def stub_covariate_names = quant_covariates || cat_covariates ? '["intercept", "stub_covariate"]' : '[]'
    def stub_result = groovy.json.JsonOutput.toJson(meta.mph_result)
    """
    printf 'IID,${stub_traits}\\nstub,${stub_trait_values}\\n' > "${prefix}.mph.pheno.csv"
    ${stub_covariates}
    printf '%s\\n' '{"schema_version": "1.1", "result": ${stub_result}, "covariate_names": ${stub_covariate_names}, "trait_names": ${groovy.json.JsonOutput.toJson(meta.mph_trait_names)}, "analysis_set_expected": 1, "warnings": []}' > "${prefix}.mph.inputs.json"
    printf '"%s":\\n    python: %s\\n' \\
        '${task.process}' \\
        "\$(python3 --version | sed 's/^Python //')" \\
        > versions.yml
    """
}
