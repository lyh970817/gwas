process REGENIE_STEP1 {
    tag "${meta.id}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/7a/7a05bf71ea09adc5ebf9f0c656c9b326c0f16ba8e4966914972e58313469a466/data'
        : 'community.wave.seqera.io/library/regenie:4.1.2--5d361f9fcb2f85cf'}"

    input:
    tuple val(meta), path(plink_genotype_file), path(plink_variant_file), path(plink_sample_file)
    tuple val(meta2), path(pheno)
    tuple val(meta3), path(covar)
    val bsize

    output:
    tuple val(meta), path("*_pred.list"), emit: predictions
    tuple val(meta), path("*.loco.gz"), emit: loco
    tuple val(meta), path("*.log"), emit: log
    tuple val("${task.process}"), val('regenie'), eval('regenie --version 2>&1 | sed -n "1{s/^v//;s/\\.gz$//;p}"'), topic: versions, emit: versions_regenie

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def input_prefix = plink_genotype_file.baseName
    def prefix = task.ext.prefix ?: input_prefix
    def genotype_flag = plink_genotype_file.name.endsWith('.pgen') ? '--pgen' : '--bed'
    def covar_arg = covar ? "--covarFile ${covar}" : ''
    def bsize_arg = bsize ?: 1000
    """
    regenie \\
        --step 1 \\
        ${genotype_flag} ${input_prefix} \\
        --phenoFile ${pheno} \\
        ${covar_arg} \\
        --bsize ${bsize_arg} \\
        --gz \\
        --threads ${task.cpus} \\
        ${args} \\
        --out ${prefix}
    """

    stub:
    def args = task.ext.args ?: ''
    def input_prefix = plink_genotype_file.baseName
    def prefix = task.ext.prefix ?: input_prefix
    // A multi-phenotype Step 1 fits every column named by `--phenoColList` and emits one LOCO per column
    // together with a `_pred.list` line naming that column, so a stub reporting one prediction would void
    // every `-stub` assertion about a multi-phenotype fit. The column list is optionally single-quoted on
    // the command line. Without the option the stub keeps its single-prediction shape.
    def pheno_match = args =~ /--phenoColList\s+'?([^'\s]+)'?/
    def pheno_columns = pheno_match.find() ? pheno_match.group(1).tokenize(',') : []
    def loco_files = (1..(pheno_columns.size() ?: 1)).collect { index -> "${prefix}_${index}.loco.gz" }
    def loco_lines = loco_files.collect { loco -> "echo \"\" | gzip > ${loco}" }.join('\n    ')
    def pred_list_line = pheno_columns
        ? "printf '${[pheno_columns, loco_files].transpose().collect { column, loco -> "${column} ${loco}" }.join('\\n')}\\n' > ${prefix}_pred.list"
        : "touch ${prefix}_pred.list"
    """
    ${pred_list_line}
    ${loco_lines}
    touch ${prefix}.log
    """
}
