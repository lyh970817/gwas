// Route every nf-core/gwas unary analysis unit through the association methods it selected, and converge the
// four native result contracts on one raw-association stream. This is pipeline routing, method selection,
// per-method call-shape adaptation and method attribution, not an nf-core/modules submission candidate.
//
// Genotype preparation, relatedness-matrix construction and phenotype normalisation are deliberately NOT here.
// They stay on the pipeline spine so each distinct cohort bundle, each scientifically distinct matrix and each
// analysis unit's normalised phenotype is built once and fanned out to every consumer across every domain. What
// this controller owns is the adaptation of those prepared streams into each association family's native call
// shape, the per-method selection, and the naming of the producing method on the way out.
//
// The two prediction-reusing routes are called as subworkflows rather than inlined: `ROUTE_REGENIE_ASSOCIATIONS`
// and `ROUTE_LDAK_KVIK_ASSOCIATIONS` own their own Step 1 reuse identity, and those keys stay private to them.
// PLINK 2 `--glm` and GCTA fastGWA-MLM are invoked directly, because a composition wrapping a single module is
// not a subworkflow and would only add a scope level. Every constituent process reports directly to the
// run-wide versions topic, so this subworkflow emits no versions, and it reads no params, no workflow and no
// projectDir — the three REGENIE execution controls arrive as explicit values.

// MODULE: Local to the pipeline
include { GCTA_FASTGWA                 } from '../../../modules/local/gcta/fastgwa/main'
include { PLINK2_GLM                   } from '../../../modules/local/plink2/glm/main'

// SUBWORKFLOWS: Pipeline-local association routes that own their own Step 1 fit reuse
include { ROUTE_LDAK_KVIK_ASSOCIATIONS } from '../route_ldak_kvik_associations'
include { ROUTE_REGENIE_ASSOCIATIONS   } from '../route_regenie_associations'

workflow ROUTE_ASSOCIATION_ANALYSES {
    take:
    ch_cohort_genotypes // channel: [ val(meta), path(pgen), path(psam), path(pvar) ], the canonical PLINK 2 bundle fanned out one element per genotype request, including the relationship-scoped rows the spine also routes to matrix construction
    ch_plink1_genotypes // channel: [ val(meta), path(bed), path(bim), path(fam) ], the lazy PLINK 1 derivative, present only for cohorts with a PLINK-1-needing consumer
    ch_phenotypes // channel: [ val(meta), path(phenotype) ], the headered canonical phenotype of every analysis unit
    ch_covariates // channel: [ val(meta), path(covariates) ], the headered merged covariate design, present only for an analysis unit that declared covariates
    ch_headerless_phenotypes // channel: [ val(meta), path(phenotype), path(quant_covariates), path(cat_covariates) ], headerless serialisations, optional covariates are already []
    ch_sparse_matrices // channel: [ val(meta), [ path(grm_file), ... ] ], the sparse GCTA relatedness matrices, already fanned out one element per requesting analysis
    ch_predictor_extracts // channel: [ val(meta), path(extract) ], the optional LDAK predictor list each analysis declared, already [] when absent
    regenie_step2_bsize // value: val(step2_bsize)
    regenie_step1_mode // value: val(step1_mode), 'standard' or 'chunked'
    regenie_step1_jobs // value: val(step1_jobs), null for standard mode

    main:

    // The genotype bundle, the normalised phenotype and the merged covariate file, one element per analysis
    // unit. This is the call shape PLINK 2 and REGENIE share, and the only two routes that consume it are in
    // this controller. `join` is correct here where `combine` was correct at the cohort seam: all three
    // channels are keyed one-to-one on the analysis meta, so a missing or duplicated key is a defect and the
    // strict form is what says so. The covariate file is optional, so it joins with `remainder: true` and
    // arrives as `null` for a row that supplied none.
    def ch_analysis_inputs = ch_cohort_genotypes
        .filter { meta, _pgen, _psam, _pvar -> !meta.relationship_id }
        .join(ch_phenotypes, failOnMismatch: true, failOnDuplicate: true)
        .join(ch_covariates, remainder: true)

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
        regenie_step2_bsize,
        regenie_step1_mode,
        regenie_step1_jobs,
    )

    //
    // PIPELINE ROUTE: LDAK-KVIK association with shared Step 1 predictions
    //
    // LDAK consumes the headerless phenotype serialisation and keeps quantitative and categorical
    // covariates separate, so it is narrowed out of the prepared headerless stream rather than the headered
    // one above. An absent optional covariate is already [] there and stages nothing.
    def ch_kvik_phenotypes = ch_headerless_phenotypes.filter { meta, _phenotype, _quant_covariates, _cat_covariates -> 'ldak_kvik' in meta.association_methods }

    // The stageable predictor resource and its validated policy come from the relational LDAK family map.
    // Both remain explicit tuple members so Nextflow stages the file, while their content identity is folded
    // into the Step 1 reuse key the route owns.
    def ch_kvik_extract_policy = ch_predictor_extracts
        .filter { meta, _kvik_extract -> 'ldak_kvik' in meta.association_methods }
        .map { meta, kvik_extract -> [meta, kvik_extract, meta.method_options.ldak.kvik_step1_subset] }

    // A relationship-scoped row reaches the PLINK 1 derivative too, and it carries no association methods at
    // all, so the selected-method test is guarded rather than assuming the key is present.
    def ch_kvik_genotypes = ch_plink1_genotypes.filter { meta, _bed, _bim, _fam -> 'ldak_kvik' in (meta.association_methods ?: []) }

    ROUTE_LDAK_KVIK_ASSOCIATIONS(
        ch_kvik_genotypes,
        ch_kvik_phenotypes,
        ch_kvik_extract_policy,
    )

    //
    // MODULE: GCTA fastGWA-MLM association
    //
    // This is deliberately inline: a composition wrapping one module is not an nf-core subworkflow.
    // The module chooses --fastGWA-mlm or --fastGWA-mlm-binary from the boolean phenotype input;
    // conf/modules/gcta.config supplies no arbitrary ext.args, so plain --fastGWA-lr is unreachable.
    def ch_fastgwa_genotypes = ch_cohort_genotypes.filter { meta, _pgen, _psam, _pvar -> 'gcta_fastgwa' in meta.association_methods }
    def ch_fastgwa_phenotypes = ch_headerless_phenotypes.filter { meta, _phenotype, _quant_covariates, _cat_covariates -> 'gcta_fastgwa' in meta.association_methods }

    // fastGWA takes its five native inputs from four separately-keyed streams, so they are rejoined on the
    // analysis identifier and split again with `multiMap` so they cannot drift out of lockstep. The key is a
    // tuple position that never survives the `multiMap`, so it never reaches any metadata.
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
            ch_sparse_matrices.map { meta, sparse_grm_files -> [meta.id, [meta, sparse_grm_files]] },
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

    // The emitted metadata is the focal analysis identity plus the producing method, derived immutably with
    // `meta + [method: ...]`. Every reuse key this controller and its two nested routes computed — the REGENIE
    // and LDAK-KVIK Step 1 prediction keys, the synthetic fit ids they address those fits by, the fastGWA
    // analysis-id join key — stayed in a tuple position or inside the nested route and is absent here. The
    // PLINK 2 result family is a channel selection, not a metadata key, and is likewise absent.

    emit:
    association_results = ch_association_results // channel: [ val(meta), path(raw_summary_statistics) ], one per analysis unit per association method actually exercised, `meta.method` naming the producing route
}
