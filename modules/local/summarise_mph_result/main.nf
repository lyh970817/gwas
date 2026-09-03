process SUMMARISE_MPH_RESULT {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/18/1841daa69f98a0b0ffcb8f545070c8350a75febb167202136eab0990131d31c0/data'
        : 'community.wave.seqera.io/library/python:3.14.5--dc8358b3c5eeb927'}"

    input:
    // Everything is staged under `input/` so the published sidecar can never be written through a staged
    // symlink onto one of the native results it is summarising.
    tuple val(meta), path(serialization, stageAs: 'input/*'), path(variance_components, stageAs: 'input/*'), path(fixed_effects, stageAs: 'input/*'), path(iterations, stageAs: 'input/*'), path(native_log, stageAs: 'input/*')

    output:
    tuple val(meta), path("${prefix}.provenance.json"), emit: provenance
    path 'versions.yml', emit: versions, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    // `prefix` must remain visible to the output declarations. Every other assignment must remain visible to
    // the template and hold a JSON string literal, which is also valid Python syntax.
    prefix = task.ext.prefix ?: "${meta.id}"
    serialization_literal = groovy.json.JsonOutput.toJson(serialization.toString())
    variance_components_literal = groovy.json.JsonOutput.toJson(variance_components.toString())
    fixed_effects_literal = groovy.json.JsonOutput.toJson(fixed_effects.toString())
    iterations_literal = groovy.json.JsonOutput.toJson(iterations.toString())
    // Deliberately not named `log`: that identifier is Nextflow's own logger inside a script block, and a
    // process input named `log` resolves to the logger rather than to the staged file.
    log_literal = groovy.json.JsonOutput.toJson(native_log.toString())
    prefix_literal = groovy.json.JsonOutput.toJson(prefix.toString())
    analysis_id_literal = groovy.json.JsonOutput.toJson(meta.id.toString())
    task_process_literal = groovy.json.JsonOutput.toJson(task.process.toString())
    template('summarise_mph_result.py')

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    printf '%s\\n' '{"schema_version": "1.1", "result": {"kind": "heritability", "analysis_id": "${meta.id}", "method": "${meta.mph_estimator}"}, "residual_covariance": null, "derivation": null, "classification": "estimable", "warnings": []}' > "${prefix}.provenance.json"
    printf '"%s":\\n    python: %s\\n' \\
        '${task.process}' \\
        "\$(python3 --version | sed 's/^Python //')" \\
        > versions.yml
    """
}
