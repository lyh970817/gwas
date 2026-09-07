process REGENIE_STEP2 {
    tag "${meta.id}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/7a/7a05bf71ea09adc5ebf9f0c656c9b326c0f16ba8e4966914972e58313469a466/data'
        : 'community.wave.seqera.io/library/regenie:4.1.2--5d361f9fcb2f85cf'}"

    input:
    tuple val(meta), path(plink_genotype_file), path(plink_variant_file), path(plink_sample_file)
    tuple val(meta2), path(predictions), path(loco_files)
    tuple val(meta3), path(pheno)
    tuple val(meta4), path(covar)
    val bsize

    output:
    tuple val(meta), path("*.regenie.gz"), emit: results
    tuple val(meta), path("*.log"), emit: log
    tuple val("${task.process}"), val('regenie'), eval('regenie --version 2>&1 | sed -n "1{s/^v//;s/\\.gz$//;p}"'), topic: versions, emit: versions_regenie

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def covar_arg = covar ? "--covarFile ${covar}" : ''
    def genotype_flag = plink_genotype_file.name.endsWith('.pgen') ? '--pgen' : '--bed'
    def input_prefix = plink_genotype_file.baseName
    def prefix = task.ext.prefix ?: meta.id

    """
    regenie \\
        --step 2 \\
        ${genotype_flag} ${input_prefix} \\
        --phenoFile ${pheno} \\
        --pred ${predictions} \\
        ${covar_arg} \\
        --bsize ${bsize} \\
        --gz \\
        --threads ${task.cpus} \\
        ${args} \\
        --out ${prefix}
    """

    stub:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: meta.id
    // REGENIE splits its Step 2 results one file per `--phenoColList` column, so a stub that derives a single
    // suffix from the raw capture reports one-phenotype cardinality for a multi-phenotype invocation and
    // silently voids every `-stub` assertion about it. The column list is optionally single-quoted on the
    // command line. Without the option the stub keeps its single unsuffixed result.
    def pheno_match = args =~ /--phenoColList\s+'?([^'\s]+)'?/
    def pheno_columns = pheno_match.find() ? pheno_match.group(1).tokenize(',') : []
    def result_lines = (pheno_columns ?: [''])
        .collect { column -> "echo \"\" | gzip > ${prefix}${column ? '_' + column : ''}.regenie.gz" }
        .join('\n    ')
    """
    ${result_lines}
    touch ${prefix}.log
    """
}
