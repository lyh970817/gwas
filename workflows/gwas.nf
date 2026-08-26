/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
// MODULE: Local to the pipeline
include { GCTA_FASTGWA                                        } from '../modules/local/gcta/fastgwa/main'
include { NORMALISE_PHENOTYPES                                } from '../modules/local/normalise_phenotypes/main'
include { PLINK2_GLM                                          } from '../modules/local/plink2/glm/main'

// SUBWORKFLOW: Consisting of a mix of local and nf-core/modules
include { GRM_HERITABILITY_GCTA                               } from '../subworkflows/local/grm_heritability_gcta'
include { GRM_HERITABILITY_LDAK as GRM_HERITABILITY_LDAK_HE   } from '../subworkflows/local/grm_heritability_ldak'
include { GRM_HERITABILITY_LDAK as GRM_HERITABILITY_LDAK_PCGC } from '../subworkflows/local/grm_heritability_ldak'
include { GRM_HERITABILITY_LDAK as GRM_HERITABILITY_LDAK_REML } from '../subworkflows/local/grm_heritability_ldak'
include { PREPARE_COHORT_GENOTYPES                            } from '../subworkflows/local/prepare_cohort_genotypes'
include { PREPARE_RELATEDNESS_MATRICES                        } from '../subworkflows/local/prepare_relatedness_matrices'
include { ROUTE_CANONICAL_SUMMARY_STATISTICS                  } from '../subworkflows/local/route_canonical_summary_statistics'
include { ROUTE_GCTA_BIVARIATE_RELATIONSHIPS                  } from '../subworkflows/local/route_gcta_bivariate_relationships'
include { ROUTE_GWAS_REPORTING                                } from '../subworkflows/local/route_gwas_reporting'
include { ROUTE_LDAK_KVIK_ASSOCIATIONS                        } from '../subworkflows/local/route_ldak_kvik_associations'
include { ROUTE_LDAK_SUMMARY_ANALYSES                         } from '../subworkflows/local/route_ldak_summary_analyses'
include { ROUTE_LDSC_SUMMARY_ANALYSES                         } from '../subworkflows/local/route_ldsc_summary_analyses'
include { ROUTE_REGENIE_ASSOCIATIONS                          } from '../subworkflows/local/route_regenie_associations'
include { getGwaslabReferences                                } from '../subworkflows/local/utils_nfcore_gwas_pipeline'

// SUBWORKFLOW: Consisting entirely of nf-core/modules
include { softwareVersionsToYAML                              } from '../subworkflows/nf-core/utils_nfcore_pipeline'

// PLUGIN
include { paramsSummaryMap                                    } from 'plugin/nf-schema'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow GWAS {
    take:
    ch_analyses // channel: [ val(meta), [ path(genotype_file), ... ], path(phenotype), path(quant_covariates), path(cat_covariates), path(kvik_extract), path(ldak_weights) ]
    ch_external_summary_statistics // channel: [ val(meta), path(source) ]
    ch_relationships // channel: [ val(meta), [ path(genotype_file), ... ], path(pair_quant_covariates), path(pair_cat_covariates) ]
    ch_unary_requests // channel: [ val(meta), path(hapmap3_snplist), path(reference_ld_scores), path(regression_weights), path(tagging_file) ]
    ch_pair_requests // channel: [ val(meta), path(hapmap3_snplist), path(reference_ld_scores), path(regression_weights), path(tagging_file) ]
    multiqc_config // channel: val(multiqc_config)
    multiqc_logo // channel: val(multiqc_logo)
    multiqc_methods_description // channel: val(multiqc_methods_description)
    outdir // channel: val(outdir)

    main:

    def ch_analysis_metadata = ch_analyses
        .map { meta, _genotype_files, _phenotype, _quant_covariates, _cat_covariates, _kvik_extract, _ldak_weights -> meta }
        .collect()
    def ch_method_metadata = ch_analyses
        .map { meta, _genotype_files, _phenotype, _quant_covariates, _cat_covariates, _kvik_extract, _ldak_weights -> [domain: 'analysis', meta: meta] }
        .mix(
            ch_relationships.map { meta, _genotype_files, _pair_quant_covariates, _pair_cat_covariates -> [domain: 'pairwise', meta: meta] }
        )
        .mix(
            ch_unary_requests.map { meta, _hapmap3_snplist, _reference_ld_scores, _regression_weights, _tagging_file -> [domain: 'summary_unary', meta: meta] }
        )
        .mix(
            ch_pair_requests.map { meta, _hapmap3_snplist, _reference_ld_scores, _regression_weights, _tagging_file -> [domain: 'pairwise', meta: meta] }
        )
        .collect()

    // One element per analysis unit carrying the genotype files it declared. A pairwise LDMS request is
    // also a consumer of the cohort's lazy PLINK 1 derivative, so it enters this request stream without
    // inheriting either endpoint's unary method settings. Cohort preparation collapses every request to
    // the distinct cohort before conversion.
    def ch_genotype_requests = ch_analyses.map { meta, genotype_files, _phenotype, _quant_covariates, _cat_covariates, _kvik_extract, _ldak_weights ->
        [meta, genotype_files]
    }
    ch_genotype_requests = ch_genotype_requests.mix(
        ch_relationships.filter { meta, _genotype_files, _pair_quant_covariates, _pair_cat_covariates -> meta.matrix_kind == 'gcta_ldms' }.map { meta, genotype_files, _pair_quant_covariates, _pair_cat_covariates -> [meta, genotype_files] }
    )

    // Matrix preparation additionally receives the optional LDAK weights Path. It derives identity from the
    // bytes before request deduplication and keeps the Path outside matrix metadata and the published key.
    def ch_relatedness_analyses = ch_analyses.map { meta, genotype_files, _phenotype, _quant_covariates, _cat_covariates, _kvik_extract, ldak_weights ->
        [meta, genotype_files, ldak_weights ?: []]
    }
    ch_relatedness_analyses = ch_relatedness_analyses.mix(
        ch_relationships.map { meta, genotype_files, _pair_quant_covariates, _pair_cat_covariates -> [meta, genotype_files, []] }
    )

    //
    // SUBWORKFLOW: Prepare each distinct cohort's genotypes once into the canonical PLINK 2 bundle
    //
    PREPARE_COHORT_GENOTYPES(ch_genotype_requests)

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
        .filter { meta, _pgen, _psam, _pvar -> !meta.relationship_id }
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
    // PIPELINE ROUTE: REGENIE association with shared Step 1 predictions
    //
    // The local route owns nf-core/gwas scientific identity, cross-analysis fit reuse and output
    // attribution. Upstream-ready REGENIE components remain unaware of the relational input contract.
    def ch_regenie_analyses = ch_analysis_inputs.filter { meta, _pgen, _psam, _pvar, _phenotype, _covariates -> 'regenie' in meta.association_methods }

    ROUTE_REGENIE_ASSOCIATIONS(
        ch_regenie_analyses,
        params.regenie_step2_bsize,
        params.regenie_step1_mode,
        params.regenie_step1_jobs,
    )

    //
    // PIPELINE ROUTE: LDAK-KVIK association with shared Step 1 predictions
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

    def ch_kvik_genotypes = PREPARE_COHORT_GENOTYPES.out.plink1_genotypes.filter { meta, _bed, _bim, _fam -> 'ldak_kvik' in (meta.association_methods ?: []) }

    ROUTE_LDAK_KVIK_ASSOCIATIONS(
        ch_kvik_genotypes,
        ch_kvik_phenotypes.map { _analysis_id, meta, phenotype, quant_covariates, cat_covariates -> [meta, phenotype, quant_covariates, cat_covariates] },
        ch_kvik_extract_policy.map { _analysis_id, meta, kvik_extract, subset_policy -> [meta, kvik_extract, subset_policy] },
    )

    //
    // MODULE: GCTA fastGWA-MLM association
    //
    // This is deliberately inline: a composition wrapping one module is not an nf-core subworkflow.
    // The module chooses --fastGWA-mlm or --fastGWA-mlm-binary from the boolean phenotype input;
    // conf/modules/gcta.config supplies no arbitrary ext.args, so plain --fastGWA-lr is unreachable.
    def ch_fastgwa_genotypes = PREPARE_COHORT_GENOTYPES.out.genotypes.filter { meta, _pgen, _psam, _pvar -> 'gcta_fastgwa' in meta.association_methods }
    def ch_fastgwa_phenotypes = ch_gcta_phenotypes.filter { meta, _phenotype, _quant_covariates, _cat_covariates -> 'gcta_fastgwa' in meta.association_methods }

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
    // Association result fan-in ahead of canonical serialisation
    //
    // One record per analysis per association method actually exercised. Each route contributes an
    // adapter that names its method on the meta map and normalises whatever emissions the programme
    // splits its results across; everything downstream is method-agnostic. `meta.id` stays the analysis
    // identifier — the method is a separate key, because the analysis is what the published summary
    // statistics directory is keyed by and the method is what distinguishes the files inside it.
    //
    // The pipeline's PLINK 2 policy emits linear results for quantitative traits and logistic-hybrid results
    // for binary traits. Select those two supported forms explicitly so a generic module stub that materialises
    // every optional output preserves the same one-result-per-analysis contract as a real configured run.
    def ch_association_results = channel.empty()

    def ch_plink2_results = PLINK2_GLM.out.linear.filter { meta, _sumstats -> !meta.is_binary }
    ch_plink2_results = ch_plink2_results.mix(
        PLINK2_GLM.out.logistic_hybrid.filter { meta, _sumstats -> meta.is_binary }
    )

    ch_association_results = ch_association_results.mix(
        ch_plink2_results.map { meta, sumstats -> [meta + [method: 'plink2'], sumstats] }
    )
    ch_association_results = ch_association_results.mix(
        ROUTE_REGENIE_ASSOCIATIONS.out.results.map { meta, sumstats -> [meta + [method: 'regenie'], sumstats] }
    )
    ch_association_results = ch_association_results.mix(
        ROUTE_LDAK_KVIK_ASSOCIATIONS.out.harmonisation_input.map { meta, sumstats -> [meta + [method: 'ldak_kvik'], sumstats] }
    )
    ch_association_results = ch_association_results.mix(
        GCTA_FASTGWA.out.results.map { meta, sumstats -> [meta + [method: 'gcta_fastgwa'], sumstats] }
    )

    //
    // PIPELINE ROUTE: canonical summary statistics from every internal and external origin
    //
    // The controller owns the internal producer metadata, the producer-specific GWASLab mappings, the
    // raw/canonical convergence, the strict source reattribution and the canonical serialisation. The spine
    // keeps the fan-in of the association routes above and the fan-out of the canonical stream to the LDAK and
    // LDSC summary routes below, and resolves the build-keyed GWASLab resources here because they are pipeline
    // parameters rather than request-owned references.
    def gwaslab_references = getGwaslabReferences()

    ROUTE_CANONICAL_SUMMARY_STATISTICS(
        ch_association_results,
        ch_external_summary_statistics,
        gwaslab_references,
    )

    //
    // PIPELINE ROUTE: LDAK SumHer and SumCors from canonical summary statistics
    //
    // Both summary-scale LDAK methods share one controller because they share the canonical-to-LDAK
    // preparation and the endpoint resolution that feeds it. The spine selects the route; the controller
    // owns preparation reuse, ordered pair resolution, native-argument and runtime policy, and
    // normalization. It receives the full validated request tuple so the reference-bundle convention stays
    // request-owned rather than becoming spine knowledge.
    def ch_sumher_requests = ch_unary_requests.filter { meta, _hapmap3_snplist, _reference_ld_scores, _regression_weights, _tagging_file -> meta.method == 'ldak_sumher' }
    def ch_sumcors_requests = ch_pair_requests.filter { meta, _hapmap3_snplist, _reference_ld_scores, _regression_weights, _tagging_file -> meta.method == 'ldak_sumcors' }

    ROUTE_LDAK_SUMMARY_ANALYSES(
        ch_sumher_requests,
        ch_sumcors_requests,
        ROUTE_CANONICAL_SUMMARY_STATISTICS.out.summary_statistics,
    )

    //
    // PIPELINE ROUTE: standalone CBIIT Python 3 LDSC munging, H2 and RG
    //
    // Both summary-scale LDSC methods share one controller because they share the content-addressed munging
    // that feeds them: a canonical summary consumed by a unary H2 request and by either side of any number of
    // RG requests is munged exactly once. The spine selects the route; the controller owns the munging reuse
    // identity, endpoint resolution in declared pair order, observed- and liability-scale selection, native
    // log gathering and normalization. It receives the full validated request tuple so the reference-bundle
    // convention stays request-owned rather than becoming spine knowledge.
    def ch_ldsc_h2_requests = ch_unary_requests.filter { meta, _hapmap3_snplist, _reference_ld_scores, _regression_weights, _tagging_file -> meta.method == 'ldsc_h2' }
    def ch_ldsc_rg_requests = ch_pair_requests.filter { meta, _hapmap3_snplist, _reference_ld_scores, _regression_weights, _tagging_file -> meta.method == 'ldsc_rg' }

    ROUTE_LDSC_SUMMARY_ANALYSES(
        ch_ldsc_h2_requests,
        ch_ldsc_rg_requests,
        ROUTE_CANONICAL_SUMMARY_STATISTICS.out.summary_statistics,
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
        .filter { meta, _grm_files -> !meta.relationship_id }
        .map { meta, grm_files -> [meta, [], grm_files, 'greml'] }
        .mix(
            PREPARE_RELATEDNESS_MATRICES.out.gcta_ldms.filter { meta, _mgrm, _grm_files -> !meta.relationship_id }.map { meta, mgrm, grm_files -> [meta, mgrm, grm_files, 'greml_ldms'] }
        )

    def ch_greml_inputs = ch_greml_matrices
        .combine(ch_gcta_phenotypes, by: 0)
        .multiMap { meta, mgrm, grm_files, estimator, phenotype, quant_covariates, cat_covariates ->
            def route_meta = meta + [gcta_estimator: estimator]
            grm: [route_meta, mgrm, grm_files]
            pheno: [route_meta, phenotype]
            qcovar: [route_meta, quant_covariates]
            covar: [route_meta, cat_covariates]
            estimator: [route_meta, estimator]
        }

    GRM_HERITABILITY_GCTA(
        ch_greml_inputs.grm,
        ch_greml_inputs.pheno,
        ch_greml_inputs.qcovar,
        ch_greml_inputs.covar,
        ch_greml_inputs.estimator,
    )

    //
    // PIPELINE ROUTE: GCTA bivariate REML and REML-LDMS relationship requests
    //
    // Individual-level relationships are their own domain, disjoint from the summary-statistics pair requests
    // routed above. Dense and LDMS share one controller because they share the relationship definition, the
    // endpoint resolution against the normalised phenotypes and the bivariate trait table built from them. The
    // spine keeps matrix construction and phenotype normalisation; the controller owns relationship
    // de-duplication, declared orientation, preparation reuse, native identity and normalization. The matrix
    // streams are narrowed to the relationship-scoped rows here, mirroring the unary narrowing above, so the
    // controller never sees a unary analysis matrix.
    ROUTE_GCTA_BIVARIATE_RELATIONSHIPS(
        ch_relationships,
        NORMALISE_PHENOTYPES.out.phenotype_headerless,
        PREPARE_RELATEDNESS_MATRICES.out.gcta_dense.filter { meta, _grm_files -> meta.relationship_id },
        PREPARE_RELATEDNESS_MATRICES.out.gcta_ldms.filter { meta, _mgrm, _grm_files -> meta.relationship_id },
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
    def ch_topic_versions = channel.topic("versions")
        .distinct()
        .branch { entry ->
            versions_file: entry instanceof Path
            versions_tuple: true
        }

    def ch_topic_versions_string = ch_topic_versions.versions_tuple
        .map { process, tool, version ->
            [process[process.lastIndexOf(':') + 1..-1], "  ${tool}: ${version}"]
        }
        .groupTuple(by: 0)
        .map { process, tool_versions ->
            tool_versions.unique().sort()
            "${process}:\n${tool_versions.join('\n')}"
        }

    def ch_collated_versions = softwareVersionsToYAML(ch_topic_versions.versions_file)
        .mix(ch_topic_versions_string)
        .collectFile(
            storeDir: "${outdir}/pipeline_info",
            name: 'nf_core_' + 'gwas_software_' + 'mqc_' + 'versions.yml',
            sort: true,
            newLine: true,
        )

    //
    // SUBWORKFLOW: Render the run report from the analysis plan, workflow summary, methods description and versions
    //
    // The reporting controller owns MultiQC assembly but reads no parent scope: the run parameter summary is
    // evaluated here and every pipeline-default asset is resolved here, then passed in explicitly.
    def summary_params = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")
    ROUTE_GWAS_REPORTING(
        ch_collated_versions,
        ch_analysis_metadata,
        ch_method_metadata,
        summary_params,
        multiqc_config,
        multiqc_logo,
        multiqc_methods_description,
        file("${projectDir}/assets/multiqc_analysis_plan.yml", checkIfExists: true),
        file("${projectDir}/assets/multiqc_config.yml", checkIfExists: true),
        file("${projectDir}/assets/nf-core-gwas_logo_light.png", checkIfExists: true),
        file("${projectDir}/assets/methods_description_template.yml", checkIfExists: true),
    )

    emit:
    canonical_summary_statistics  = ROUTE_CANONICAL_SUMMARY_STATISTICS.out.summary_statistics // channel: [ val(meta), path(canonical_summary_statistics) ]
    summary_statistics_provenance = ROUTE_CANONICAL_SUMMARY_STATISTICS.out.provenance // channel: [ val(meta), path(provenance) ]
    multiqc_report                = ROUTE_GWAS_REPORTING.out.report.toList() // channel: [ [ path(report) ] ]
}
