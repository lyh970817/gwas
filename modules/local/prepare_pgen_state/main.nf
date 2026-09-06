process PREPARE_PGEN_STATE {
    tag "${meta.id}"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/22/22dd30b4bc53d1ba88fcd146a2dd562659c9aaa3f0f1712542fb2b4048b454b7/data'
        : 'community.wave.seqera.io/library/plink2:2.0.0a.6.9--e6710830a4b7f0c6'}"

    input:
    // Format-polymorphic native member order: primary, variant file, sample file. `--pgen-info` reads the
    // headers only, so this is a sub-second call whatever the bundle's size.
    tuple val(meta), path(pgen), path(pvar), path(psam)

    output:
    tuple val(meta), path("${prefix}.pgen_info.log"), emit: state
    tuple val("${task.process}"), val("plink2"), eval("plink2 --version 2>&1 | sed 's/^PLINK v//; s/ 64.*\$//'"), emit: versions_plink2, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    // `prefix` must remain visible to the output declaration above.
    prefix = task.ext.prefix ?: "${meta.id}"
    def input_prefix = pgen.baseName
    def mem_mb = task.memory.toMega()
    """
    plink2 \\
        --pfile "${input_prefix}" \\
        --pgen-info \\
        --threads "${task.cpus}" \\
        --memory "${mem_mb}" \\
        --out "${prefix}.pgen_info"
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    printf '  Maximum allele count for a single variant: 2\\n  No hardcalls are explicitly phased\\n  No dosages present\\n' > "${prefix}.pgen_info.log"
    """
}
