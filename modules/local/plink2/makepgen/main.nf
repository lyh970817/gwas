process PLINK2_MAKEPGEN {
    tag "${meta.id}"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/22/22dd30b4bc53d1ba88fcd146a2dd562659c9aaa3f0f1712542fb2b4048b454b7/data'
        : 'community.wave.seqera.io/library/plink2:2.0.0a.6.9--e6710830a4b7f0c6'}"

    input:
    tuple val(meta), path(bed), path(bim), path(fam)

    output:
    tuple val(meta), path("*.pgen"), path("*.psam"), path("*.pvar"), emit: pgen
    tuple val(meta), path("*.log"), emit: log
    tuple val("${task.process}"), val("plink2"), eval("plink2 --version 2>&1 | sed 's/^PLINK v//; s/ 64.*\$//'"), emit: versions_plink2, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def mem_mb = task.memory.toMega()
    // plink2 resolves a PLINK 1 fileset from a single `--bfile` stem, so deriving that stem from the
    // .bed alone silently mis-resolves — or fails at runtime — for a bundle whose .bim and .fam are
    // named differently. Re-staging the trio under one stem in a scratch directory makes the
    // mismatch unrepresentable; the directory is fresh per task, so it cannot collide with an input.
    """
    mkdir -p bfile
    ln -s "\$PWD/${bed}" bfile/input.bed
    ln -s "\$PWD/${bim}" bfile/input.bim
    ln -s "\$PWD/${fam}" bfile/input.fam

    plink2 \\
        --bfile bfile/input \\
        --threads "${task.cpus}" \\
        --memory "${mem_mb}" \\
        --make-pgen \\
        --out "${prefix}" \\
        ${args}
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch "${prefix}.pgen"
    touch "${prefix}.psam"
    touch "${prefix}.pvar"
    touch "${prefix}.log"
    """
}
