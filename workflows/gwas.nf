/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
// MODULE: Local to the pipeline
include { GWASLAB_HARMONIZE            } from '../modules/local/gwaslab/harmonize/main'
include { GCTA_FASTGWA                 } from '../modules/local/gcta/fastgwa/main'
include { NORMALISE_PHENOTYPES         } from '../modules/local/normalise_phenotypes/main'
include { PLINK2_GLM                   } from '../modules/local/plink2/glm/main'

// MODULE: Installed directly from nf-core/modules
include { MULTIQC                      } from '../modules/nf-core/multiqc/main'

// SUBWORKFLOW: Consisting of a mix of local and nf-core/modules
include { GRM_HERITABILITY_GCTA        } from '../subworkflows/local/grm_heritability_gcta'
include { GRM_HERITABILITY_LDAK as GRM_HERITABILITY_LDAK_HE   } from '../subworkflows/local/grm_heritability_ldak'
include { GRM_HERITABILITY_LDAK as GRM_HERITABILITY_LDAK_PCGC } from '../subworkflows/local/grm_heritability_ldak'
include { GRM_HERITABILITY_LDAK as GRM_HERITABILITY_LDAK_REML } from '../subworkflows/local/grm_heritability_ldak'
include { PLINK_ASSOCIATION_LDAK_KVIK  } from '../subworkflows/local/plink_association_ldak_kvik'
include { PLINK_GWAS_REGENIE           } from '../subworkflows/local/plink_gwas_regenie'
include { PREPARE_COHORT_GENOTYPES     } from '../subworkflows/local/prepare_cohort_genotypes'
include { PREPARE_RELATEDNESS_MATRICES } from '../subworkflows/local/prepare_relatedness_matrices'
include { associationColumnMappingJson } from '../subworkflows/local/utils_nfcore_gwas_pipeline'
include { gwaslabReferenceLookup       } from '../subworkflows/local/utils_nfcore_gwas_pipeline'
include { methodsDescriptionText       } from '../subworkflows/local/utils_nfcore_gwas_pipeline'

// SUBWORKFLOW: Consisting entirely of nf-core/modules
include { paramsSummaryMultiqc         } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML       } from '../subworkflows/nf-core/utils_nfcore_pipeline'

// PLUGIN
include { paramsSummaryMap             } from 'plugin/nf-schema'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow GWAS {
    take:
    ch_analyses // channel: canonical relational analysis tuples
    multiqc_config
    multiqc_logo
    multiqc_methods_description
    outdir

    main:

    def ch_versions = channel.empty()
    def ch_multiqc_files = channel.empty()

    // One element per analysis unit carrying the genotype files it declared. Cohort preparation collapses
    // this to the distinct cohorts.
    def ch_analysis_genotypes = ch_analyses.map { meta, genotype_files, _phenotype, _quant_covariates, _cat_covariates, _kvik_extract, _ldak_weights ->
        [meta, genotype_files]
    }

    // Matrix preparation additionally receives the optional LDAK weights Path. It derives identity from the
    // bytes before request deduplication and keeps the Path outside matrix metadata and the published key.
    def ch_relatedness_analyses = ch_analyses.map { meta, genotype_files, _phenotype, _quant_covariates, _cat_covariates, _kvik_extract, ldak_weights ->
        [meta, genotype_files, ldak_weights ?: []]
    }

    //
    // SUBWORKFLOW: Prepare each distinct cohort's genotypes once into the canonical PLINK 2 bundle
    //
    PREPARE_COHORT_GENOTYPES(ch_analysis_genotypes)

    //
    // SUBWORKFLOW: Build each distinct relatedness matrix once and fan it out per analysis unit
    //
    PREPARE_RELATEDNESS_MATRICES(
        ch_relatedness_analyses,
        PREPARE_COHORT_GENOTYPES.out.cohort_genotypes,
        PREPARE_COHORT_GENOTYPES.out.plink1_genotypes,
        params.gcta_grm_parts,
    )

    //
    // MODULE: Normalise each analysis unit's phenotype and covariates into the canonical layout
    //
    NORMALISE_PHENOTYPES(
        ch_analyses.map { meta, _genotype_files, phenotype, quant_covariates, cat_covariates, _kvik_extract, _ldak_weights ->
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

    // GCTA and LDAK reject a header row. fastGWA, GREML and LDAK REML therefore consume the headerless
    // phenotype and covariate serialisations. Optional covariates are represented by [], which stages nothing.
    def ch_gcta_phenotypes = NORMALISE_PHENOTYPES.out.phenotype_headerless
        .join(NORMALISE_PHENOTYPES.out.quant_covariates_headerless, remainder: true)
        .join(NORMALISE_PHENOTYPES.out.cat_covariates_headerless, remainder: true)
        .map { meta, phenotype, quant_covariates, cat_covariates ->
            [meta, phenotype, quant_covariates ?: [], cat_covariates ?: []]
        }

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
    // SUBWORKFLOW: REGENIE Step 1 fitting and Step 2 association
    //
    // The prepared PGEN bundle is valid at both sides of the reusable subworkflow's PLINK semantic
    // union. The adapter spells out the prepared PGEN/PSAM/PVAR to component PGEN/PVAR/PSAM
    // reordering and derives one content identity for every Step 1 scientific input. Distinct analysis
    // identities carrying the same cohort, trait, normalised phenotype, covariates and block size
    // therefore fit once while retaining separate Step 2 and output attribution.
    def ch_regenie_input = ch_analysis_inputs
        .filter { meta, _pgen, _psam, _pvar, _phenotype, _covariates -> 'regenie' in meta.association_methods }
        .multiMap { meta, pgen, psam, pvar, phenotype, covariates ->
            if (params.regenie_step1_mode == 'chunked' && params.regenie_step1_jobs == null) {
                error("[nf-core/gwas] ERROR: --regenie_step1_jobs is required when --regenie_step1_mode is 'chunked'")
            }
            def regenie_meta = meta + [
                regenie_prediction_key: regeniePredictionKey(
                    meta,
                    phenotype,
                    covariates ?: [],
                    params.regenie_step1_bsize,
                ),
            ]
            genotypes: [regenie_meta, pgen, pvar, psam]
            phenotype: [regenie_meta, phenotype]
            covariates: [regenie_meta, covariates ?: []]
            step1_bsize: [regenie_meta, params.regenie_step1_bsize]
            step2_bsize: [regenie_meta, params.regenie_step2_bsize]
            step1_mode: [regenie_meta, params.regenie_step1_mode]
            step1_jobs: [regenie_meta, params.regenie_step1_mode == 'chunked' ? params.regenie_step1_jobs : []]
        }

    PLINK_GWAS_REGENIE(
        ch_regenie_input.genotypes,
        ch_regenie_input.genotypes,
        ch_regenie_input.phenotype,
        ch_regenie_input.covariates,
        ch_regenie_input.step1_bsize,
        ch_regenie_input.step2_bsize,
        ch_regenie_input.step1_mode,
        ch_regenie_input.step1_jobs,
    )

    //
    // SUBWORKFLOW: LDAK-KVIK Step 1 fitting and Step 2 association
    //
    // LDAK consumes the headerless phenotype serialisation and keeps quantitative and categorical
    // covariates separate. Fold both optional covariate streams onto the total phenotype stream so
    // that an absent file is represented by `[]` and stages nothing.
    def ch_kvik_phenotypes = NORMALISE_PHENOTYPES.out.phenotype_headerless
        .join(NORMALISE_PHENOTYPES.out.quant_covariates_headerless, remainder: true)
        .join(NORMALISE_PHENOTYPES.out.cat_covariates_headerless, remainder: true)
        .filter { meta, _phenotype, _quant_covariates, _cat_covariates -> 'ldak_kvik' in meta.association_methods }
        .map { meta, phenotype, quant_covariates, cat_covariates ->
            [meta.id, meta, phenotype, quant_covariates ?: [], cat_covariates ?: []]
        }

    // The stageable predictor resource and its validated policy come from the relational LDAK family map.
    // Both remain explicit tuple members so Nextflow stages the file, while their content identity is folded
    // into the Step 1 reuse key below.
    def ch_kvik_extract_policy = ch_analyses
        .filter { meta, _genotype_files, _phenotype, _quant_covariates, _cat_covariates, _kvik_extract, _ldak_weights -> 'ldak_kvik' in meta.association_methods }
        .map { meta, _genotype_files, _phenotype, _quant_covariates, _cat_covariates, kvik_extract, _ldak_weights ->
            [meta.id, meta, kvik_extract ?: [], meta.method_options.ldak.kvik_step1_subset]
        }

    def ch_kvik_input = PREPARE_COHORT_GENOTYPES.out.plink1_genotypes
        .filter { meta, _bed, _bim, _fam -> 'ldak_kvik' in meta.association_methods }
        .map { meta, bed, bim, fam -> [meta.id, meta, bed, bim, fam] }
        .join(ch_kvik_phenotypes, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(ch_kvik_extract_policy, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .multiMap { _analysis_id, meta, bed, bim, fam, _phenotype_meta, phenotype, quant_covariates, cat_covariates, _extract_meta, kvik_extract, subset_policy ->
            def kvik_meta = meta + [
                kvik_prediction_key: kvikPredictionKey(
                    meta,
                    phenotype,
                    quant_covariates,
                    cat_covariates,
                    subset_policy,
                    kvik_extract,
                ),
            ]
            genotypes: [kvik_meta, bed, bim, fam]
            phenotype: [kvik_meta, phenotype, meta.is_binary]
            qcovariates: [kvik_meta, quant_covariates]
            covariates: [kvik_meta, cat_covariates]
            extract_policy: [kvik_meta, kvik_extract, subset_policy]
            keep: [kvik_meta, []]
        }

    PLINK_ASSOCIATION_LDAK_KVIK(
        ch_kvik_input.genotypes,
        ch_kvik_input.genotypes,
        ch_kvik_input.phenotype,
        ch_kvik_input.qcovariates,
        ch_kvik_input.covariates,
        ch_kvik_input.extract_policy,
        ch_kvik_input.keep,
    )

    //
    // MODULE: GCTA fastGWA-MLM association
    //
    // This is deliberately inline: a composition wrapping one module is not an nf-core subworkflow.
    // The module chooses --fastGWA-mlm or --fastGWA-mlm-binary from the boolean phenotype input;
    // conf/modules/gcta.config supplies no arbitrary ext.args, so plain --fastGWA-lr is unreachable.
    def ch_fastgwa_genotypes = PREPARE_COHORT_GENOTYPES.out.genotypes
        .filter { meta, _pgen, _psam, _pvar -> 'gcta_fastgwa' in meta.association_methods }
    def ch_fastgwa_phenotypes = ch_gcta_phenotypes
        .filter { meta, _phenotype, _quant_covariates, _cat_covariates -> 'gcta_fastgwa' in meta.association_methods }

    def ch_fastgwa_invocations = ch_fastgwa_genotypes
        .map { meta, pgen, psam, pvar -> [meta.id, [meta, pgen, pvar, psam]] }
        .join(
            ch_fastgwa_phenotypes.map { meta, phenotype, _quant_covariates, _cat_covariates -> [meta.id, [meta, phenotype, meta.is_binary]] },
            by: 0,
            failOnDuplicate: true,
            failOnMismatch: true,
        )
        .join(
            ch_fastgwa_phenotypes.map { meta, _phenotype, quant_covariates, _cat_covariates -> [meta.id, [meta, quant_covariates]] },
            by: 0,
            failOnDuplicate: true,
            failOnMismatch: true,
        )
        .join(
            ch_fastgwa_phenotypes.map { meta, _phenotype, _quant_covariates, cat_covariates -> [meta.id, [meta, cat_covariates]] },
            by: 0,
            failOnDuplicate: true,
            failOnMismatch: true,
        )
        .join(
            PREPARE_RELATEDNESS_MATRICES.out.gcta_sparse.map { meta, sparse_grm_files -> [meta.id, [meta, sparse_grm_files]] },
            by: 0,
            failOnDuplicate: true,
            failOnMismatch: true,
        )
        .multiMap { _analysis_id, genotypes, pheno, qcovar, covar, sparse_grm ->
            genotypes: genotypes
            pheno: pheno
            qcovar: qcovar
            covar: covar
            sparse_grm: sparse_grm
        }

    GCTA_FASTGWA(
        ch_fastgwa_invocations.genotypes,
        ch_fastgwa_invocations.pheno,
        ch_fastgwa_invocations.qcovar,
        ch_fastgwa_invocations.covar,
        ch_fastgwa_invocations.sparse_grm,
    )

    //
    // MODULE: GWASLab harmonisation of every association result
    //
    // One record per analysis per association method actually exercised. Each route contributes an
    // adapter that names its method on the meta map and normalises whatever emissions the programme
    // splits its results across; everything downstream is method-agnostic. `meta.id` stays the analysis
    // identifier — the method is a separate key, because the analysis is what the published summary
    // statistics directory is keyed by and the method is what distinguishes the files inside it.
    //
    // PLINK 2 splits its result across four optional emissions, one per regression it may have fitted,
    // and exactly one of them is populated for a given analysis, so the four are mixed back into one.
    def ch_association_results = channel.empty()

    def ch_plink2_results = PLINK2_GLM.out.linear.mix(
        PLINK2_GLM.out.logistic,
        PLINK2_GLM.out.logistic_hybrid,
        PLINK2_GLM.out.firth,
    )

    ch_association_results = ch_association_results.mix(
        ch_plink2_results.map { meta, sumstats -> [meta + [method: 'plink2'], sumstats] }
    )
    ch_association_results = ch_association_results.mix(
        PLINK_GWAS_REGENIE.out.results.map { meta, sumstats -> [meta + [method: 'regenie'], sumstats] }
    )
    ch_association_results = ch_association_results.mix(
        PLINK_ASSOCIATION_LDAK_KVIK.out.harmonisation_input.map { meta, sumstats -> [meta + [method: 'ldak_kvik'], sumstats] }
    )
    ch_association_results = ch_association_results.mix(
        GCTA_FASTGWA.out.results.map { meta, sumstats -> [meta + [method: 'gcta_fastgwa'], sumstats] }
    )

    // The optional reference resources are resolved once for the run rather than per record: they are
    // parameter-derived and build-keyed, and the cohort manifest's build enum makes the lookup total.
    def gwaslab_references = gwaslabReferenceLookup()

    // `multiMap` rather than four `map`s of the same channel, so the reference tuples cannot drift out of
    // lockstep with the summary statistics they belong to. A build with no configured resource yields
    // `[]`, which stages nothing and reaches the component as an absent reference.
    def ch_harmonise_input = ch_association_results.multiMap { meta, sumstats ->
        def references = gwaslab_references[meta.build]
        sumstats: [meta, sumstats, associationColumnMappingJson(meta.method, meta.is_binary), meta.build]
        reference_fasta: [[id: meta.build], references.fasta, references.fasta_index]
        rsid_reference: [[id: meta.build], references.rsid_vcf, references.rsid_vcf_index]
        strand_reference: [[id: meta.build], references.strand_vcf, references.strand_vcf_index]
    }

    GWASLAB_HARMONIZE(
        ch_harmonise_input.sumstats,
        ch_harmonise_input.reference_fasta,
        ch_harmonise_input.rsid_reference,
        ch_harmonise_input.strand_reference,
    )

    //
    // SUBWORKFLOW: GCTA GREML heritability
    //
    // GCTA rejects a header row, so this route takes the headerless serialisations rather than the headered
    // ones the association routes use, and the trait sits at a fixed third column, which makes `--mpheno`
    // the constant 1 (set in conf/modules/gcta.config).
    //
    // The dense and LDMS matrix families retain distinct reuse keys and are adapted into the one public
    // GCTA heritability contract here. The middle GRM element is absent for GREML and is the MGRM manifest
    // for GREML-LDMS; the estimator selector makes the subworkflow enforce that distinction.
    def ch_greml_matrices = PREPARE_RELATEDNESS_MATRICES.out.gcta_dense
        .map { meta, grm_files -> [meta, [], grm_files, 'greml'] }
        .mix(
            PREPARE_RELATEDNESS_MATRICES.out.gcta_ldms
                .map { meta, mgrm, grm_files -> [meta, mgrm, grm_files, 'greml_ldms'] }
        )

    def ch_greml_inputs = ch_greml_matrices
        .join(ch_gcta_phenotypes, failOnDuplicate: true)
        .multiMap { meta, mgrm, grm_files, estimator, phenotype, quant_covariates, cat_covariates ->
            grm: [meta, mgrm, grm_files]
            pheno: [meta, phenotype]
            qcovar: [meta, quant_covariates]
            covar: [meta, cat_covariates]
            estimator: [meta, estimator]
        }

    // `GRM_HERITABILITY_GCTA.out.versions` is deliberately unconsumed: `gcta/reml` already publishes to the
    // `versions` topic, so accumulating the subworkflow's own emit as well would report GCTA twice.
    GRM_HERITABILITY_GCTA(
        ch_greml_inputs.grm,
        ch_greml_inputs.pheno,
        ch_greml_inputs.qcovar,
        ch_greml_inputs.covar,
        ch_greml_inputs.estimator,
    )

    //
    // SUBWORKFLOWS: LDAK REML, Haseman-Elston and PCGC heritability
    //
    // Matrix construction and the per-analysis unrelated-subset routing are owned above by
    // PREPARE_RELATEDNESS_MATRICES. The three aliases preserve the reusable subworkflow's one-estimator
    // contract while allowing one analysis unit to select all three methods without changing its identity.
    // HE and PCGC additionally receive the numerical design built specifically for LDAK matrix adjustment;
    // the estimators themselves retain the original quantitative/categorical split.
    def ch_ldak_inputs = PREPARE_RELATEDNESS_MATRICES.out.ldak_kinship
        .join(ch_gcta_phenotypes, failOnDuplicate: true)
        .join(NORMALISE_PHENOTYPES.out.adjustment_covariates, remainder: true)
        // `remainder` also emits adjustment-only rows for analyses that selected no LDAK
        // heritability method. Keep only the left-side matrix records before unpacking the tuple.
        .filter { record -> record.size() == 7 && record[1] != null }
        .map { meta, grm_files, keep, phenotype, quant_covariates, cat_covariates, adjustment_covariates ->
            [meta, grm_files, keep, phenotype, quant_covariates, cat_covariates, adjustment_covariates ?: []]
        }

    def ch_ldak_reml_inputs = ch_ldak_inputs
        .filter { meta, _grm_files, _keep, _phenotype, _quant_covariates, _cat_covariates, _adjustment_covariates ->
            'ldak_reml' in meta.heritability_methods
        }
        .multiMap { meta, grm_files, keep, phenotype, quant_covariates, cat_covariates, adjustment_covariates ->
            grm: [meta, grm_files]
            pheno: [meta, phenotype, meta.population_prevalence != null ? meta.population_prevalence : []]
            qcovar: [meta, quant_covariates]
            covar: [meta, cat_covariates]
            keep: [meta, keep ?: []]
            estimator: [meta, 'reml']
            adjustment_covar: [meta, adjustment_covariates]
        }

    GRM_HERITABILITY_LDAK_REML(
        ch_ldak_reml_inputs.grm,
        ch_ldak_reml_inputs.pheno,
        ch_ldak_reml_inputs.qcovar,
        ch_ldak_reml_inputs.covar,
        ch_ldak_reml_inputs.keep,
        ch_ldak_reml_inputs.estimator,
        ch_ldak_reml_inputs.adjustment_covar,
    )

    def ch_ldak_he_inputs = ch_ldak_inputs
        .filter { meta, _grm_files, _keep, _phenotype, _quant_covariates, _cat_covariates, _adjustment_covariates ->
            'ldak_he' in meta.heritability_methods
        }
        .multiMap { meta, grm_files, keep, phenotype, quant_covariates, cat_covariates, adjustment_covariates ->
            grm: [meta, grm_files]
            pheno: [meta, phenotype, []]
            qcovar: [meta, quant_covariates]
            covar: [meta, cat_covariates]
            keep: [meta, keep ?: []]
            estimator: [meta, 'he']
            adjustment_covar: [meta, adjustment_covariates]
        }

    GRM_HERITABILITY_LDAK_HE(
        ch_ldak_he_inputs.grm,
        ch_ldak_he_inputs.pheno,
        ch_ldak_he_inputs.qcovar,
        ch_ldak_he_inputs.covar,
        ch_ldak_he_inputs.keep,
        ch_ldak_he_inputs.estimator,
        ch_ldak_he_inputs.adjustment_covar,
    )

    def ch_ldak_pcgc_inputs = ch_ldak_inputs
        .filter { meta, _grm_files, _keep, _phenotype, _quant_covariates, _cat_covariates, _adjustment_covariates ->
            'ldak_pcgc' in meta.heritability_methods
        }
        .multiMap { meta, grm_files, keep, phenotype, quant_covariates, cat_covariates, adjustment_covariates ->
            grm: [meta, grm_files]
            pheno: [meta, phenotype, meta.population_prevalence]
            qcovar: [meta, quant_covariates]
            covar: [meta, cat_covariates]
            keep: [meta, keep ?: []]
            estimator: [meta, 'pcgc']
            adjustment_covar: [meta, adjustment_covariates]
        }

    // All constituent local modules report directly to the run-wide `versions` topic.
    GRM_HERITABILITY_LDAK_PCGC(
        ch_ldak_pcgc_inputs.grm,
        ch_ldak_pcgc_inputs.pheno,
        ch_ldak_pcgc_inputs.qcovar,
        ch_ldak_pcgc_inputs.covar,
        ch_ldak_pcgc_inputs.keep,
        ch_ldak_pcgc_inputs.estimator,
        ch_ldak_pcgc_inputs.adjustment_covar,
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
// A portable digest of one staged scientific input. Paths themselves are deliberately excluded: two
// byte-identical normalised files materialised for different analysis IDs are valid reuse candidates,
// while identically named files with different content are not.
def scientificInputDigest(input_file) {
    if (!input_file) {
        return 'absent'
    }
    def input_path = input_file instanceof java.nio.file.Path ? input_file : input_file.toPath()
    def digest = java.security.MessageDigest.getInstance('SHA-256')
    java.nio.file.Files
        .newInputStream(input_path)
        .withCloseable { input ->
            input.eachByte(8192) { buffer, count ->
                digest.update(buffer, 0, count)
            }
        }
    return digest.digest().encodeHex().toString()
}

// Prediction reuse keys share one deterministic map serialisation and the same 12-character
// SHA-256 prefix. Keeping that pipeline here prevents either route from drifting independently.
def canonicalPredictionKey(identity) {
    def canonical = identity
        .sort { entry -> entry.key }
        .collect { name, value -> "${name}=${value}" }
        .join('\n')
    return java.security.MessageDigest
        .getInstance('SHA-256')
        .digest(canonical.getBytes('UTF-8'))
        .encodeHex()
        .toString()
        .substring(0, 12)
}

// Step 1 reuse requires both cohort identity and every scientific input to agree. Execution-only
// controls (standard versus chunked and chunk count) are intentionally absent because they materialise
// the same prediction model; the Step 1 block size remains because it changes the fitted model.
def regeniePredictionKey(meta, phenotype, covariates, step1_bsize) {
    def identity = [
        cohort: meta.cohort,
        trait: meta.trait,
        is_binary: meta.is_binary,
        phenotype: scientificInputDigest(phenotype),
        covariates: scientificInputDigest(covariates),
        step1_bsize: step1_bsize,
    ]
    return canonicalPredictionKey(identity)
}

// LDAK-KVIK Step 1 reuse is content-defined. The predictor policy and optional predictor-list bytes
// change the fitted prediction model; run/profile tuning and LDAK kinship/estimator options do not.
def kvikPredictionKey(meta, phenotype, quant_covariates, cat_covariates, subset_policy, predictor_extract) {
    def identity = [
        cohort: meta.cohort,
        trait: meta.trait,
        is_binary: meta.is_binary,
        phenotype: scientificInputDigest(phenotype),
        quant_covariates: scientificInputDigest(quant_covariates),
        cat_covariates: scientificInputDigest(cat_covariates),
        subset_policy: subset_policy,
        predictor_extract: scientificInputDigest(predictor_extract),
    ]
    return canonicalPredictionKey(identity)
}
