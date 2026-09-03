process PREPARE_GENIE_INPUTS {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/18/1841daa69f98a0b0ffcb8f545070c8350a75febb167202136eab0990131d31c0/data'
        : 'community.wave.seqera.io/library/python:3.14.5--dc8358b3c5eeb927'}"

    input:
    // The bundle is staged under `genotypes/` and the analysis-owned files under `input/` so that an analysis
    // named after its own cohort cannot have this task write through a staged symlink onto its own source.
    tuple val(meta), path(bed, stageAs: 'genotypes/*'), path(bim, stageAs: 'genotypes/*'), path(fam, stageAs: 'genotypes/*')
    tuple val(meta2), path(phenotype, stageAs: 'input/*'), path(adjustment_covariates, stageAs: 'input/*')
    tuple val(meta3), path(annotation, stageAs: 'input/*')

    output:
    // GENIE reads these three through three different flags and they have independent identity, so they are
    // three channels rather than one bundle. The covariate file is separately optional because a tuple member
    // cannot be.
    tuple val(meta), path("${prefix}.genie.pheno"), emit: phenotype
    tuple val(meta), path("${prefix}.genie.annot"), emit: annotation
    tuple val(meta), path("${prefix}.genie.covar"), emit: covariates, optional: true
    tuple val(meta), path("${prefix}.genie_expected.tsv"), emit: expected_counts
    tuple val(meta), path("${prefix}.genie_effective.json"), emit: effective_settings
    tuple val(meta), path("${prefix}.provenance.json"), emit: provenance
    path 'versions.yml', emit: versions, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    // `prefix` must remain visible to the output declarations. Every other assignment must remain visible to
    // the template and hold a JSON string literal, which is also valid Python syntax.
    prefix = task.ext.prefix ?: "${meta.id}"
    bed_literal = groovy.json.JsonOutput.toJson(bed.toString())
    bim_literal = groovy.json.JsonOutput.toJson(bim.toString())
    fam_literal = groovy.json.JsonOutput.toJson(fam.toString())
    phenotype_literal = groovy.json.JsonOutput.toJson(phenotype.toString())
    adjustment_covariates_literal = groovy.json.JsonOutput.toJson(adjustment_covariates ? adjustment_covariates.toString() : '')
    annotation_literal = groovy.json.JsonOutput.toJson(annotation ? annotation.toString() : '')
    prefix_literal = groovy.json.JsonOutput.toJson(prefix.toString())
    analysis_id_literal = groovy.json.JsonOutput.toJson(meta.id.toString())
    method_literal = groovy.json.JsonOutput.toJson(meta.genie_method.toString())
    // Serialised twice on purpose: the inner call renders the map as JSON, the outer one renders that
    // JSON as a quoted string. A bare JSON object is not valid Python -- its `null`, `true` and `false`
    // are not Python literals -- so the template parses a string rather than embedding an expression.
    // The staged annotation Path is dropped: it is an input to this task, not a setting to record.
    requested_settings_literal = groovy.json.JsonOutput.toJson(groovy.json.JsonOutput.toJson(meta.method_options.genie.findAll { name, _value -> name != 'annotation' }))
    capability_literal = groovy.json.JsonOutput.toJson(groovy.json.JsonOutput.toJson(meta.genie_capability))
    task_process_literal = groovy.json.JsonOutput.toJson(task.process.toString())
    template('prepare_genie_inputs.py')

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    // The effective-settings JSON is written parsable rather than empty because the calling route reads it on
    // the head node to render the native argument list.
    def covariates_stub = adjustment_covariates ? "printf 'FID IID cov_1\\nF1 S1 0\\n' > \"${prefix}.genie.covar\"" : ''
    """
    printf 'FID IID PHENO\\nF1 S1 0\\n' > "${prefix}.genie.pheno"
    printf '1\\n' > "${prefix}.genie.annot"
    ${covariates_stub}
    printf 'individuals\\t1\\nbin_0\\t1\\n' > "${prefix}.genie_expected.tsv"
    printf '%s\\n' '{"random_vectors": 10, "jackknife_blocks": 1, "seed": null, "memory_efficient": false, "native_args": ["-jn", "1"], "native_defaults_apply": ["random_vectors"], "n_variants": 1, "n_samples_fam": 1, "n_samples_retained": 1, "annotation_columns": 1, "annotation_column_sums": [1], "covariate_columns": 0}' > "${prefix}.genie_effective.json"
    printf '%s\\n' '{"schema_version": "1.1", "result": {"kind": "heritability", "analysis_id": "${meta.id}", "method": "${meta.genie_method}"}, "residual_covariance": null, "derivation": null, "classification": null, "warnings": []}' > "${prefix}.provenance.json"
    printf '"%s":\\n    python: %s\\n' \\
        '${task.process}' \\
        "\$(python3 --version | sed 's/^Python //')" \\
        > versions.yml
    """
}
