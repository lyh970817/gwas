/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
// MODULE: Local to the pipeline
include { NORMALISE_PHENOTYPES     } from '../modules/local/normalise_phenotypes/main'
include { PLINK2_GLM               } from '../modules/local/plink2/glm/main'

// MODULE: Installed directly from nf-core/modules
include { MULTIQC                  } from '../modules/nf-core/multiqc/main'

// SUBWORKFLOW: Consisting of a mix of local and nf-core/modules
include { PREPARE_COHORT_GENOTYPES } from '../subworkflows/local/prepare_cohort_genotypes'
include { methodsDescriptionText   } from '../subworkflows/local/utils_nfcore_gwas_pipeline'

// SUBWORKFLOW: Consisting entirely of nf-core/modules
include { paramsSummaryMultiqc     } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML   } from '../subworkflows/nf-core/utils_nfcore_pipeline'

// PLUGIN
include { paramsSummaryMap         } from 'plugin/nf-schema'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow GWAS {
    take:
    ch_samplesheet // channel: samplesheet read in from --input
    multiqc_config
    multiqc_logo
    multiqc_methods_description
    outdir

    main:

    def ch_versions = channel.empty()
    def ch_multiqc_files = channel.empty()

    //
    // SUBWORKFLOW: Prepare each distinct cohort's genotypes once into the canonical PLINK 2 bundle
    //
    PREPARE_COHORT_GENOTYPES(
        ch_samplesheet.map { meta, genotype_files, _phenotype, _quant_covariates, _cat_covariates, _kvik_extract ->
            [meta, genotype_files]
        }
    )

    //
    // MODULE: Normalise each analysis unit's phenotype and covariates into the canonical layout
    //
    NORMALISE_PHENOTYPES(
        ch_samplesheet.map { meta, _genotype_files, phenotype, quant_covariates, cat_covariates, _kvik_extract ->
            [meta, phenotype, quant_covariates, cat_covariates]
        }
    )

    // The genotype bundle, the normalised phenotype and the merged covariate file, one element per
    // analysis unit. `join` is correct here where `combine` was correct at the cohort seam: all three
    // channels are keyed one-to-one on the analysis meta, so a missing or duplicated key is a defect
    // and the strict form is what says so. The covariate file is optional, so it joins with
    // `remainder: true` and arrives as `null` for a row that supplied none.
    def ch_analysis_inputs = PREPARE_COHORT_GENOTYPES.out.genotypes
        .join(NORMALISE_PHENOTYPES.out.phenotype, failOnMismatch: true, failOnDuplicate: true)
        .join(NORMALISE_PHENOTYPES.out.covariates, remainder: true)

    //
    // MODULE: PLINK 2 --glm association
    //
    // `multiMap` rather than three `map`s of the same channel, so the three inputs cannot drift out
    // of lockstep. A row that supplied no covariates passes `[]`, which stages nothing: the module's
    // covariate argument is a ternary on a `path` inside a tuple, and no placeholder file is written.
    def ch_glm_input = ch_analysis_inputs
        .filter { meta, _pgen, _psam, _pvar, _phenotype, _covariates -> 'plink2' in meta.association_methods }
        .multiMap { meta, pgen, psam, pvar, phenotype, covariates ->
            genotypes: [meta, pgen, psam, pvar]
            phenotype: [meta, phenotype]
            covariates: [meta, covariates ?: []]
        }

    PLINK2_GLM(
        ch_glm_input.genotypes,
        ch_glm_input.phenotype,
        ch_glm_input.covariates,
    )

    //
    // Collate and save software versions
    //
    def topic_versions = channel.topic("versions")
        .distinct()
        .branch { entry ->
            versions_file: entry instanceof Path
            versions_tuple: true
        }

    def topic_versions_string = topic_versions.versions_tuple
        .map { process, tool, version ->
            [process[process.lastIndexOf(':') + 1..-1], "  ${tool}: ${version}"]
        }
        .groupTuple(by: 0)
        .map { process, tool_versions ->
            tool_versions.unique().sort()
            "${process}:\n${tool_versions.join('\n')}"
        }

    def ch_collated_versions = softwareVersionsToYAML(ch_versions.mix(topic_versions.versions_file))
        .mix(topic_versions_string)
        .collectFile(
            storeDir: "${outdir}/pipeline_info",
            name: 'nf_core_' + 'gwas_software_' + 'mqc_' + 'versions.yml',
            sort: true,
            newLine: true,
        )

    //
    // MODULE: MultiQC
    //
    ch_multiqc_files = ch_multiqc_files.mix(ch_collated_versions)
    def ch_summary_params = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")
    def ch_workflow_summary = channel.value(paramsSummaryMultiqc(ch_summary_params))
    ch_multiqc_files = ch_multiqc_files.mix(ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    def ch_multiqc_custom_methods_description = multiqc_methods_description
        ? file(multiqc_methods_description, checkIfExists: true)
        : file("${projectDir}/assets/methods_description_template.yml", checkIfExists: true)
    def ch_methods_description = channel.value(methodsDescriptionText(ch_multiqc_custom_methods_description))
    ch_multiqc_files = ch_multiqc_files.mix(ch_methods_description.collectFile(name: 'methods_description_mqc.yaml', sort: true))
    MULTIQC(
        ch_multiqc_files.flatten().collect().map { files ->
            [
                [id: 'gwas'],
                files,
                multiqc_config
                    ? file(multiqc_config, checkIfExists: true)
                    : file("${projectDir}/assets/multiqc_config.yml", checkIfExists: true),
                multiqc_logo ? file(multiqc_logo, checkIfExists: true) : [],
                [],
                [],
            ]
        }
    )

    emit:
    multiqc_report = MULTIQC.out.report.map { _meta, report -> [report] }.toList() // channel: /path/to/multiqc_report.html
    versions       = ch_versions // channel: [ path(versions.yml) ]
}
