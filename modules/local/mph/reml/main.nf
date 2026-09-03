process MPH_REML {
    tag "${meta.id}_${meta2.id}"
    label 'process_high'

    // MPH is not packaged for Bioconda, so this module ships a digest-pinned image and no `environment.yml`,
    // following `metasoft/re2` and `genie/g`. The image is `linux/amd64` only, statically linked against Intel
    // oneMKL, and there is no Conda fallback, so the module cannot run on another architecture.
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'docker://ghcr.io/lyh970817/mph@sha256:561fc32443768cdaa80b1a56ed6d3f4190633d8c52d0f9fc8d0f9cc1694fad6a'
        : 'ghcr.io/lyh970817/mph@sha256:561fc32443768cdaa80b1a56ed6d3f4190633d8c52d0f9fc8d0f9cc1694fad6a'}"

    input:
    // One or more `[.grm.bin, .grm.iid]` bundles staged flat, plus the prefix order the fit must use.
    // `--grm_list` names prefixes rather than paths, and the row order of the result follows the list, so the
    // order is a contract-defining scalar rather than something to recover from the staged file names.
    tuple val(meta), path(grm_files), val(grm_prefixes)
    // `--trait_names` is mandatory natively in a way the exit code hides: omitting it prints
    // "Error: --trait is required for --reml/--minque." and returns 0 with no result file at all.
    tuple val(meta2), path(phenotype_csv), val(trait_names)
    // Absent covariates are `[]`, `[]`, which is a different fit rather than an empty one: MPH synthesises an
    // intercept only when no covariate is named, so "no covariate file" and "a covariate file naming no
    // columns" are not the same model.
    tuple val(meta3), path(covariate_csv), val(covariate_names)

    output:
    tuple val(meta), path("${prefix}.mq.vc.csv"), emit: variance_components
    tuple val(meta), path("${prefix}.mq.blue.csv"), emit: fixed_effects
    tuple val(meta), path("${prefix}.mq.iter.csv"), emit: iterations
    tuple val(meta), path("${prefix}.mq.py.csv"), emit: projected_phenotypes
    tuple val(meta), path("${prefix}.mq.cor.csv"), emit: correlations, optional: true
    tuple val(meta), path("${prefix}.log"), emit: log
    tuple val("${task.process}"), val("mph"), eval("(mph 2>&1 || true) | sed -n 's/^[*] Version \\([0-9][0-9.]*\\).*/\\1/p'"), emit: versions_mph, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    prefix = task.ext.prefix ?: "${meta.id}"
    def grm_list = "${prefix}.grm_list"
    def grm_entries = grm_prefixes.collect { grm_prefix -> "\"${grm_prefix}\"" }.join(' ')
    def covariate_arguments = covariate_csv
        ? "--covariate_file \"${covariate_csv}\" --covariate_names \"${covariate_names.join(',')}\""
        : ''
    """
    printf '%s\\n' ${grm_entries} > "${grm_list}"

    mph \\
        --reml \\
        --grm_list "${grm_list}" \\
        --phenotype_file "${phenotype_csv}" \\
        --trait_names "${trait_names.join(',')}" \\
        ${covariate_arguments} \\
        --output_file "${prefix}" \\
        --num_threads "${task.cpus}" \\
        ${args} \\
        2>&1 | tee "${prefix}.log"

    # MPH's `main()` catches most thrown errors, prints them and returns 0, so the exit status is not the
    # contract. A GRM prefix that resolves to nothing, a missing `--output_file` and a missing `--trait_names`
    # all exit 0; the first two write no `mq.*` file at all and the third writes only the log. The result file
    # and the absence of an error line are therefore what this task succeeds on.
    #
    # A `Warning:` line is deliberately not fatal here: non-convergence and a rank-deficient covariate matrix
    # are legitimate native states with a complete result written, and classifying them is the caller's job.
    test -s "${prefix}.mq.vc.csv"
    ! grep -qE '^(Error|Inconsistency)' "${prefix}.log"
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    // Branching on the trait count keeps the multi-trait output cardinality exercised in stub mode: MPH writes
    // `.mq.cor.csv` only for a fit with more than one trait.
    def stub_correlations = trait_names.size() > 1
        ? "printf 'vc_name,trait_x,trait_y,cor,se\\n' > \"${prefix}.mq.cor.csv\""
        : ''
    """
    printf 'trait_x,trait_y,vc_name,m,var,seV,pve,seP,enrichment,seE\\n' > "${prefix}.mq.vc.csv"
    printf 'trait,covar,blue,se,pval\\n' > "${prefix}.mq.blue.csv"
    printf 'iter,num_traits,sample_size,num_GRMs,logLL,dLLpred,dogleg_Newton\\n' > "${prefix}.mq.iter.csv"
    printf 'IID\\n' > "${prefix}.mq.py.csv"
    ${stub_correlations}
    printf 'stub\\n' > "${prefix}.log"
    """
}
