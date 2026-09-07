process PREPARE_REGENIE_PHENOTYPES {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/18/1841daa69f98a0b0ffcb8f545070c8350a75febb167202136eab0990131d31c0/data'
        : 'community.wave.seqera.io/library/python:3.14.5--dc8358b3c5eeb927'}"

    input:
    // The prepared phenotypes of every batch member, in the same order as `analysis_ids`. The positional
    // pairing is the caller's contract: the file basename is never read as identity, because two analyses
    // may legitimately be prepared from files with the same name. Staging is therefore indexed rather than
    // by name -- `phenotypes/*` would abort the task with an input file name collision on exactly the
    // batch this module exists to build, two members whose prepared files happen to share a basename.
    //
    // `arity: '1..*'` is load-bearing rather than decorative. Without it a one-member batch stages a bare
    // `java.nio.file.Path`, which implements `Iterable<Path>` over its *name elements*, so any `collect`
    // over the staged value would silently iterate path segments instead of files. A batch of one is the
    // common case: an analysis with no compatible sibling. The repository guards the same hazard at
    // `subworkflows/local/plink_fit_regenie/main.nf:63,87`.
    tuple val(meta), path(phenotypes, stageAs: 'phenotypes/member*.pheno', arity: '1..*'), val(analysis_ids)

    output:
    tuple val(meta), path("${prefix}.pheno"), emit: phenotype
    // `eval()` is the house style for version capture, but Nextflow rejects an `eval` output on any
    // process whose script is not Bash -- and this one is a Python `template`. The interpreter version
    // is therefore written from inside the template.
    path "versions.yml", emit: versions, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    // `prefix` must remain visible to the output declarations. The other assignments must remain visible
    // to the template and contain JSON string literals, which are also valid Python syntax.
    prefix = task.ext.prefix ?: "${meta.id}"
    phenotype_files_literal = groovy.json.JsonOutput.toJson(phenotypes.collect { phenotype -> phenotype.toString() })
    analysis_ids_literal = groovy.json.JsonOutput.toJson(analysis_ids.collect { analysis_id -> analysis_id.toString() })
    prefix_literal = groovy.json.JsonOutput.toJson(prefix.toString())
    batch_id_literal = groovy.json.JsonOutput.toJson(meta.id.toString())
    task_process_literal = groovy.json.JsonOutput.toJson(task.process.toString())
    template('prepare_regenie_phenotypes.py')

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    def header = (['FID', 'IID'] + analysis_ids).join('\\t')
    """
    printf '${header}\\n' > "${prefix}.pheno"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | sed 's/^Python //')
    END_VERSIONS
    """
}
