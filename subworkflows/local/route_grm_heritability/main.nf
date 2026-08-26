// Route nf-core/gwas unary analysis units through the individual-level GRM heritability estimators: GCTA
// GREML and GREML-LDMS, and LDAK REML, Haseman-Elston and PCGC. This is pipeline routing, method selection
// and adaptation policy, not an nf-core/modules submission candidate.
//
// Relatedness-matrix construction is deliberately NOT here. PREPARE_RELATEDNESS_MATRICES stays on the
// pipeline spine so each scientifically distinct matrix is built once and fanned out to every consumer
// across every domain — this controller and the bivariate relationship controller both consume matrices
// built there, and neither may own that construction. What this controller owns is the adaptation of those
// prepared matrix streams and the prepared headerless phenotype stream into each estimator family's native
// call shape, the per-estimator selection, and the adjustment-covariate routing that only LDAK needs.
//
// GCTA and LDAK keep separate native result contracts and are never merged into a universal heritability
// table: a `.hsq`, a `.reml`, a `.he` and a `.pcgc` are different estimands reported in different ways.
// Neither is merged with the summary-scale SumHer or LDSC H2 routes for the same reason. Every constituent
// process reports directly to the run-wide versions topic, so this subworkflow emits no versions, and it
// reads no params, no workflow and no projectDir.

// SUBWORKFLOWS: Upstream-ready estimator compositions used inside a pipeline-local route
//
// The three LDAK aliases preserve the reusable subworkflow's one-estimator contract while allowing one
// analysis unit to select all three methods without changing its identity. The alias names are also the
// pinned element of the `conf/modules/ldak.config` selectors, so they are re-declared here verbatim.
include { GRM_HERITABILITY_GCTA                               } from '../grm_heritability_gcta/main'
include { GRM_HERITABILITY_LDAK as GRM_HERITABILITY_LDAK_HE   } from '../grm_heritability_ldak/main'
include { GRM_HERITABILITY_LDAK as GRM_HERITABILITY_LDAK_PCGC } from '../grm_heritability_ldak/main'
include { GRM_HERITABILITY_LDAK as GRM_HERITABILITY_LDAK_REML } from '../grm_heritability_ldak/main'

workflow ROUTE_GRM_HERITABILITY {
    take:
    ch_dense_matrices // channel: [ val(meta), [ path(grm_file), ... ] ], the dense GCTA matrices built for unary analysis units, already fanned out one element per requesting analysis
    ch_ldms_matrices // channel: [ val(meta), path(mgrm), [ path(grm_file), ... ] ], the LD- and MAF-stratified GCTA matrix families built for unary analysis units
    ch_ldak_kinship_matrices // channel: [ val(meta), [ path(grm_file), ... ], path(keep) ], the LDAK kinship matrices, keep is [] for an unrestricted analysis
    ch_headerless_phenotypes // channel: [ val(meta), path(phenotype), path(quant_covariates), path(cat_covariates) ], headerless serialisations, optional covariates are []
    ch_adjustment_covariates // channel: [ val(meta), path(adjustment_covariates) ], the numerical design built for LDAK matrix adjustment, present only for analyses that have one

    main:

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
    def ch_greml_matrices = ch_dense_matrices
        .map { meta, grm_files -> [meta, [], grm_files, 'greml'] }
        .mix(
            ch_ldms_matrices.map { meta, mgrm, grm_files -> [meta, mgrm, grm_files, 'greml_ldms'] }
        )

    // `combine` rather than `join` at the phenotype seam: one analysis unit selecting both GCTA estimators
    // contributes two matrix records against its single phenotype record, which the strict form would
    // refuse. `gcta_estimator` is the estimator identity the composition routes on and the only thing that
    // distinguishes those two records, so it stays on the record rather than being a private scatter key.
    def ch_greml_inputs = ch_greml_matrices
        .combine(ch_headerless_phenotypes, by: 0)
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
    // SUBWORKFLOWS: LDAK REML, Haseman-Elston and PCGC heritability
    //
    // Matrix construction and the per-analysis unrelated-subset routing are owned by the spine's
    // PREPARE_RELATEDNESS_MATRICES. HE and PCGC additionally receive the numerical design built specifically
    // for LDAK matrix adjustment; the estimators themselves retain the original quantitative/categorical
    // split.
    def ch_ldak_inputs = ch_ldak_kinship_matrices
        .join(ch_headerless_phenotypes, failOnDuplicate: true)
        .join(ch_adjustment_covariates, remainder: true)
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

    emit:
    gcta_heritability   = GRM_HERITABILITY_GCTA.out.heritability // channel: [ val(meta), path(hsq) ], one per analysis per selected GCTA estimator, distinguished by meta.gcta_estimator
    ldak_reml_results   = GRM_HERITABILITY_LDAK_REML.out.reml_results // channel: [ val(meta), path(reml) ], one per analysis selecting ldak_reml
    ldak_reml_liability = GRM_HERITABILITY_LDAK_REML.out.reml_liability // channel: [ val(meta), path(reml_liab) ], only for a row declaring a population prevalence
    ldak_he_results     = GRM_HERITABILITY_LDAK_HE.out.he_results // channel: [ val(meta), path(he) ], one per analysis selecting ldak_he
    ldak_pcgc_results   = GRM_HERITABILITY_LDAK_PCGC.out.pcgc_results // channel: [ val(meta), path(pcgc) ], one per analysis selecting ldak_pcgc
    ldak_pcgc_marginal  = GRM_HERITABILITY_LDAK_PCGC.out.pcgc_marginal // channel: [ val(meta), path(pcgc_marginal) ], optional PCGC-route records
}
