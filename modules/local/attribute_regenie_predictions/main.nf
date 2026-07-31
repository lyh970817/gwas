process ATTRIBUTE_REGENIE_PREDICTIONS {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/52/52ccce28d2ab928ab862e25aae26314d69c8e38bd41ca9431c67ef05221348aa/data'
        : 'community.wave.seqera.io/library/coreutils_grep_gzip_lbzip2_pruned:838ba80435a629f8'}"

    input:
    tuple val(meta), path(predictions), path(loco)

    output:
    tuple val(meta), path("${meta.id}.regenie_step1_pred.list"), path("${meta.id}.regenie_step1_1.loco.gz"), emit: bundle
    tuple val("${task.process}"), val("coreutils"), eval("cp --version | head -n 1 | cut -d ' ' -f 4"), emit: versions_coreutils, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def loco_files = loco instanceof List ? loco : [loco]
    if (loco_files.size() != 1) {
        error("[nf-core/gwas] ERROR: REGENIE prediction attribution for analysis '${meta.id}' expected one LOCO file for canonical phenotype column 'PHENO', got ${loco_files.size()}")
    }
    """
    cp ${loco_files.first()} ${meta.id}.regenie_step1_1.loco.gz
    while IFS='	 ' read -r phenotype _; do
        printf '%s %s\\n' "\${phenotype}" "${meta.id}.regenie_step1_1.loco.gz"
    done < ${predictions} > ${meta.id}.regenie_step1_pred.list
    """

    stub:
    """
    touch ${meta.id}.regenie_step1_1.loco.gz
    printf '%s %s\\n' 'PHENO' '${meta.id}.regenie_step1_1.loco.gz' > ${meta.id}.regenie_step1_pred.list
    """
}
