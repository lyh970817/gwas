process GWASLAB_META_ANALYZE {
    tag "${meta.id}"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/gwaslab:4.1.9--pyhdfd78af_0'
        : 'quay.io/biocontainers/gwaslab:4.1.9--pyhdfd78af_0'}"

    input:
    tuple val(meta), path(sumstats, stageAs: 'parents/*'), val(study_names), val(input_format), val(genome_build), val(chromosome)

    output:
    tuple val(meta), path("${prefix}.meta.tsv.gz"), emit: meta_analysis
    tuple val(meta), path("${prefix}.study_views.tsv.gz"), emit: study_views
    tuple val(meta), path("${prefix}.effect_matrix.txt"), emit: effect_matrix
    tuple val(meta), path("${prefix}.study_order.tsv"), emit: study_order
    tuple val(meta), path("${prefix}.qc.json"), emit: qc
    tuple val(meta), path("${prefix}.derivation.json"), emit: derivation
    tuple val(meta), path("${prefix}.meta.log"), emit: log
    path "versions.yml", emit: versions, topic: versions

    script:
    prefix = task.ext.prefix ?: meta.id
    args_literal = groovy.json.JsonOutput.toJson(task.ext.args ?: '')
    // A single staged file arrives as a Path, whose `collect` iterates name components, so the
    // "at least two parents" check must see a real one-element list rather than a split path.
    parents_literal = groovy.json.JsonOutput.toJson(
        (sumstats instanceof List ? sumstats : [sumstats]).collect { parent -> parent.toString() }
    )
    study_names_literal = groovy.json.JsonOutput.toJson(
        (study_names instanceof List ? study_names : [study_names]).collect { name -> name.toString() }
    )
    input_format_literal = groovy.json.JsonOutput.toJson(input_format.toString())
    genome_build_literal = groovy.json.JsonOutput.toJson(genome_build.toString())
    prefix_literal = groovy.json.JsonOutput.toJson(prefix.toString())
    chromosome_literal = groovy.json.JsonOutput.toJson(chromosome ? chromosome.toString() : null)
    template("meta_analyze.py")

    stub:
    prefix = task.ext.prefix ?: meta.id
    def studies = (study_names instanceof List ? study_names : [study_names]).collect { name -> name.toString() }
    def matrix_header = (1..studies.size()).collect { index -> "BETA_${index} SE_${index}" }.join(' ')
    def view_header = (1..studies.size())
        .collect { index -> "STATUS_${index}\tEAF_${index}\tBETA_${index}\tSE_${index}\tP_${index}\tN_${index}" }
        .join('\t')
    """
    printf 'SNPID\tCHR\tPOS\tEA\tNEA\tSTATUS\tEAF\tBETA\tSE\tP\tN\tN_STUDIES\tDIRECTION\tEAF_META\tEAF_MIN\tEAF_MAX\tN_TOTAL\tMAX_WEIGHT_SHARE\tZ_FIXED\tQ\tP_HET\tI2\tMETA_VARIANT_KEY\\n' \\
        | gzip -n -c > "${prefix}.meta.tsv.gz"
    printf 'META_VARIANT_KEY\tSNPID\tCHR\tPOS\tEA\tNEA\t${view_header}\\n' \\
        | gzip -n -c > "${prefix}.study_views.tsv.gz"
    printf 'META_VARIANT_KEY ${matrix_header}\\n' > "${prefix}.effect_matrix.txt"
    printf 'study_index\tstudy_name\tstaged_name\tsha256\tinput_rows\tretained_rows\\n' > "${prefix}.study_order.tsv"
    printf '{"schema_version":"1.0","stub":true}\\n' > "${prefix}.qc.json"
    printf '{"schema_version":"1.0","stub":true}\\n' > "${prefix}.derivation.json"
    printf 'stub\\n' > "${prefix}.meta.log"
    cat <<-END_VERSIONS > "versions.yml"
    "${task.process}":
        gwaslab: 4.1.9
        python: \$(python3 --version | sed 's/^Python //')
    END_VERSIONS
    """
}
