process DERIVE_GCTA_BIVARIATE_TOTAL {
    tag "${meta.request_id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/18/1841daa69f98a0b0ffcb8f545070c8350a75febb167202136eab0990131d31c0/data'
        : 'community.wave.seqera.io/library/python:3.14.5--dc8358b3c5eeb927'}"

    input:
    // The two native files of one completed bivariate REML fit. They are staged under `input/` so the
    // derived files this process publishes beside them can never be written through a staged symlink onto
    // the native result they are derived from.
    tuple val(meta), path(native_result, stageAs: 'input/*'), path(native_log, stageAs: 'input/*')

    output:
    tuple val(meta), path("${prefix}.total_rg.tsv"), emit: total
    tuple val(meta), path("${prefix}.provenance.json"), emit: provenance
    path 'versions.yml', emit: versions, topic: versions

    script:
    // `prefix` must remain visible to the output declarations. Every other assignment must remain visible to
    // the template and hold a JSON string literal, which is also valid Python syntax.
    prefix = task.ext.prefix ?: "${meta.request_id}"
    // The whole request record is injected rather than a per-key list: the derived table and its provenance
    // carry fifteen of its keys, and a per-key literal list would drift against the request contract. The
    // double encoding renders a Python `str` the template decodes with `json.loads`, because a single
    // encoding would emit JSON `true`/`false`/`null`, which are not Python literals.
    meta_literal = groovy.json.JsonOutput.toJson(groovy.json.JsonOutput.toJson(meta))
    capability_literal = groovy.json.JsonOutput.toJson(groovy.json.JsonOutput.toJson(meta.gcta_capability))
    native_result_literal = groovy.json.JsonOutput.toJson(native_result.toString())
    // Deliberately not named `log`: that identifier is Nextflow's own logger inside a script block, and a
    // process input named `log` resolves to the logger rather than to the staged file.
    native_log_literal = groovy.json.JsonOutput.toJson(native_log.toString())
    prefix_literal = groovy.json.JsonOutput.toJson(prefix.toString())
    task_process_literal = groovy.json.JsonOutput.toJson(task.process.toString())
    template('derive_gcta_bivariate_total.py')

    stub:
    prefix = task.ext.prefix ?: "${meta.request_id}"
    // Rendered as the `printf` format rather than through `%s`, so the tab escapes are interpreted.
    def columns = 'request_id\\trelationship_id\\tmethod\\tcomponent\\tleft_analysis_id\\tright_analysis_id\\tleft_trait_id\\tright_trait_id\\tscale\\tleft_variance\\tleft_variance_se\\tright_variance\\tright_variance_se\\tcovariance\\tcovariance_se\\trg\\trg_se\\torigin\\tn_components'
    """
    printf '${columns}\\n' > "${prefix}.total_rg.tsv"
    printf '%s\\t%s\\t%s\\ttotal\\t%s\\t%s\\t%s\\t%s\\tobserved\\tNA\\tNA\\tNA\\tNA\\tNA\\tNA\\tNA\\tNA\\tdelta_method\\t0\\n' \\
        '${meta.request_id}' '${meta.relationship_id}' '${meta.method}' \\
        '${meta.left_analysis_id}' '${meta.right_analysis_id}' '${meta.left_trait_id}' '${meta.right_trait_id}' \\
        >> "${prefix}.total_rg.tsv"
    printf '%s\\n' '{"schema_version": "1.1", "result": {"kind": "pairwise", "request_id": "${meta.request_id}", "method": "${meta.method}"}, "derivation": null, "classification": null, "warnings": []}' > "${prefix}.provenance.json"
    printf '"%s":\\n    python: %s\\n' \\
        '${task.process}' \\
        "\$(python3 --version | sed 's/^Python //')" \\
        > versions.yml
    """
}
