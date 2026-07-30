process NORMALISE_PHENOTYPES {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/18/1841daa69f98a0b0ffcb8f545070c8350a75febb167202136eab0990131d31c0/data'
        : 'community.wave.seqera.io/library/python:3.14.5--dc8358b3c5eeb927'}"

    input:
    // Staged under `input/` rather than at the task root, which is not cosmetic. Nextflow stages an
    // input as a symlink into the task directory and places no guard on an output whose name equals
    // a staged input's, so an analysis unit named after its own phenotype file — `cohort1` beside
    // `cohort1.pheno`, which is exactly how the fixture bundle names things — would have this module
    // write `cohort1.pheno` straight through the symlink and destroy the researcher's source file,
    // silently, with the run reporting success. This module is the only one in the repo that reads
    // and writes the same extensions, so it is the only one that can collide; `input/` makes the
    // collision impossible rather than merely unlikely.
    tuple val(meta), path(phenotype, stageAs: 'input/*'), path(quant_covariates, stageAs: 'input/*'), path(cat_covariates, stageAs: 'input/*')

    output:
    tuple val(meta), path("${prefix}.pheno"), emit: phenotype
    tuple val(meta), path("${prefix}.noheader.pheno"), emit: phenotype_headerless
    tuple val(meta), path("${prefix}.qcovar"), emit: quant_covariates, optional: true
    tuple val(meta), path("${prefix}.noheader.qcovar"), emit: quant_covariates_headerless, optional: true
    tuple val(meta), path("${prefix}.catcovar"), emit: cat_covariates, optional: true
    tuple val(meta), path("${prefix}.noheader.catcovar"), emit: cat_covariates_headerless, optional: true
    tuple val(meta), path("${prefix}.covar"), emit: covariates, optional: true
    tuple val(meta), path("${prefix}.adjustcovar"), emit: adjustment_covariates, optional: true
    tuple val(meta), path("${prefix}.normalise.log"), emit: log
    // `eval()` is the house style for version capture, but Nextflow rejects an `eval` output on any
    // process whose script is not Bash — and this one is a Python `template`. So the interpreter
    // version is written from inside the template instead, exactly as the repo's other template
    // module `modules/local/ldak/calcinflation` does.
    path "versions.yml", emit: versions, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    // None of these carries `def`, and both omissions are load-bearing. `prefix` must be visible from
    // the output block, which interpolates it because a bare `*.pheno` glob would also match the
    // headerless serialisation — `modules/nf-core/plink2/glm` binds it the same way. The other five
    // must be visible to the template engine, which resolves names against the task context rather
    // than against this closure's locals, so a `def` here would render as an unknown-variable error.
    prefix = task.ext.prefix ?: "${meta.id}"
    analysis_id = meta.id
    phenotype_column = meta.phenotype_column
    case_value = meta.case_value ?: ''
    control_value = meta.control_value ?: ''
    trait_type = meta.is_binary ? 'binary' : 'quantitative'
    // Template interpolation is textual, so a value carrying a quote or a backslash would corrupt the
    // generated Python rather than being rejected by it. The samplesheet schema forbids whitespace in
    // these three columns but not those two characters, so they are refused here, where the message
    // can name the analysis unit that declared them.
    [phenotype_column, case_value, control_value].each { value ->
        if (value.toString() =~ /["\\]/) {
            error("[nf-core/gwas] ERROR: analysis '${meta.id}' declares a phenotype column or trait value containing a quote or backslash: '${value}'")
        }
    }
    template('normalise_phenotypes.py')

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    quant_covariates_stub = quant_covariates
        ? """
    touch "${prefix}.qcovar"
    touch "${prefix}.noheader.qcovar"
    """
        : ''
    cat_covariates_stub = cat_covariates
        ? """
    touch "${prefix}.catcovar"
    touch "${prefix}.noheader.catcovar"
    """
        : ''
    merged_covariates_stub = quant_covariates || cat_covariates ? """touch "${prefix}.covar"\n""" : ''
    adjustment_covariates_stub = quant_covariates || cat_covariates ? """touch "${prefix}.adjustcovar"\n""" : ''
    """
    printf 'FID\\tIID\\tPHENO\\n' > "${prefix}.pheno"
    printf '' > "${prefix}.noheader.pheno"
    ${quant_covariates_stub}
    ${cat_covariates_stub}
    ${merged_covariates_stub}
    ${adjustment_covariates_stub}
    touch "${prefix}.normalise.log"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | sed 's/^Python //')
    END_VERSIONS
    """
}
