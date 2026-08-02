// Run REGENIE Step 1 fitting and Step 2 association across PLINK-format genotype shards.
// Every constituent process reports directly to the run-wide versions topic, so this subworkflow emits no versions.

// SUBWORKFLOW: Consisting entirely of nf-core/modules
include { PLINK_FIT_REGENIE             } from '../plink_fit_regenie/main'

// MODULE: Local to the pipeline
include { ATTRIBUTE_REGENIE_PREDICTIONS } from '../../../modules/local/attribute_regenie_predictions/main'

// MODULE: Installed directly from nf-core/modules
include { REGENIE_STEP2                 } from '../../../modules/nf-core/regenie/step2/main'

workflow PLINK_GWAS_REGENIE {
    take:
    ch_step1_genotypes // channel: [ val(meta), path(plink_genotype_file), path(plink_variant_file), path(plink_sample_file) ], one analysis request carrying meta.regenie_prediction_key
    ch_step2_genotypes // channel: [ val(meta2), path(plink_genotype_file), path(plink_variant_file), path(plink_sample_file) ], Step 2 shards
    ch_pheno // channel: [ val(meta3), path(pheno) ]
    ch_covar // channel: [ val(meta4), path(covar) ], use [] when absent
    ch_step1_bsize // channel: [ val(meta5), val(step1_bsize) ]
    ch_step2_bsize // channel: [ val(meta6), val(step2_bsize) ]
    ch_step1_mode // channel: [ val(meta7), val(step1_mode) ], 'standard' or 'chunked'
    ch_n_l0_jobs // channel: [ val(meta8), val(n_l0_jobs) ], use [] for standard mode

    main:

    // Reconcile every Step 1 input by analysis identity before deduplicating by the route-computed
    // scientific identity. The synthetic fit metadata never escapes this build seam; Step 2 and every
    // public emission are fanned back out with the consuming analysis metadata below.
    def ch_fit_requests = ch_step1_genotypes
        .map { meta, plink_genotype_file, plink_variant_file, plink_sample_file ->
            [meta.id, [meta, plink_genotype_file, plink_variant_file, plink_sample_file]]
        }
        .join(ch_pheno.map { meta, pheno -> [meta.id, [meta, pheno]] }, failOnDuplicate: true, failOnMismatch: true)
        .join(ch_covar.map { meta, covar -> [meta.id, [meta, covar]] }, failOnDuplicate: true, failOnMismatch: true)
        .join(ch_step1_bsize.map { meta, step1_bsize -> [meta.id, step1_bsize] }, failOnDuplicate: true, failOnMismatch: true)
        .join(ch_step1_mode.map { meta, step1_mode -> [meta.id, step1_mode] }, failOnDuplicate: true, failOnMismatch: true)
        .join(ch_n_l0_jobs.map { meta, n_l0_jobs -> [meta.id, n_l0_jobs] }, failOnDuplicate: true, failOnMismatch: true)
        .map { _analysis_id, genotypes, pheno, covar, step1_bsize, step1_mode, n_l0_jobs ->
            def analysis_meta = genotypes[0]
            def prediction_key = analysis_meta.regenie_prediction_key
            if (!prediction_key) {
                error("[nf-core/gwas] ERROR: REGENIE analysis '${analysis_meta.id}' has no canonical prediction-bundle identity")
            }
            def fit_meta = analysis_meta + [
                id: "${analysis_meta.cohort}.regenie.${prediction_key}",
                prediction_key: prediction_key,
            ]
            [prediction_key, fit_meta, genotypes[1], genotypes[2], genotypes[3], pheno[1], covar[1], step1_bsize, step1_mode, n_l0_jobs]
        }
        .unique { prediction_key, _fit_meta, _plink_genotype_file, _plink_variant_file, _plink_sample_file, _pheno, _covar, _step1_bsize, _step1_mode, _n_l0_jobs -> prediction_key }

    def ch_fit = ch_fit_requests.multiMap { _prediction_key, fit_meta, plink_genotype_file, plink_variant_file, plink_sample_file, pheno, covar, step1_bsize, step1_mode, n_l0_jobs ->
        genotypes: [fit_meta, plink_genotype_file, plink_variant_file, plink_sample_file]
        pheno: [fit_meta, pheno]
        covar: [fit_meta, covar]
        bsize: [fit_meta, step1_bsize]
        mode: [fit_meta, step1_mode]
        jobs: [fit_meta, n_l0_jobs]
    }

    PLINK_FIT_REGENIE(ch_fit.genotypes, ch_fit.pheno, ch_fit.covar, ch_fit.bsize, ch_fit.mode, ch_fit.jobs)

    def ch_prediction_bundles = PLINK_FIT_REGENIE.out.predictions
        .map { fit_meta, predictions -> [fit_meta.prediction_key, predictions] }
        .join(
            PLINK_FIT_REGENIE.out.loco.map { fit_meta, loco -> [fit_meta.prediction_key, loco] },
            failOnDuplicate: true,
            failOnMismatch: true,
        )

    // One request per consuming analysis, even when several requests share one fitted bundle. Combining
    // by prediction key is intentionally one-to-many; every output regains the focal analysis metadata.
    def ch_consumers = ch_step2_genotypes
        .map { meta, _plink_genotype_file, _plink_variant_file, _plink_sample_file -> [meta.regenie_prediction_key, meta.id, meta] }
        .unique { _prediction_key, analysis_id, _meta -> analysis_id }

    def ch_attributed_predictions = ch_consumers
        .combine(ch_prediction_bundles, by: 0)
        .map { _prediction_key, _analysis_id, meta, predictions, loco -> [meta, predictions, loco] }

    ATTRIBUTE_REGENIE_PREDICTIONS(ch_attributed_predictions)

    def ch_step2 = ch_step2_genotypes
        .map { meta, plink_genotype_file, plink_variant_file, plink_sample_file ->
            [meta.regenie_prediction_key, meta.id, [meta, plink_genotype_file, plink_variant_file, plink_sample_file]]
        }
        .groupTuple(by: [0, 1])
        .combine(ch_prediction_bundles, by: 0)
        .map { _prediction_key, analysis_id, genotype_shards, predictions, loco -> [analysis_id, genotype_shards, predictions, loco] }
        .join(ch_pheno.map { meta, pheno -> [meta.id, [meta, pheno]] }, failOnDuplicate: true, failOnMismatch: true)
        .join(ch_covar.map { meta, covar -> [meta.id, [meta, covar]] }, failOnDuplicate: true, failOnMismatch: true)
        .join(ch_step2_bsize.map { meta, step2_bsize -> [meta.id, step2_bsize] }, failOnDuplicate: true, failOnMismatch: true)
        .flatMap { _analysis_id, genotype_shards, predictions, loco, pheno, covar, step2_bsize ->
            genotype_shards.collect { genotype_shard ->
                [genotype_shard, [genotype_shard[0], predictions, loco], pheno, covar, step2_bsize]
            }
        }
        .multiMap { genotypes, predictions, pheno, covar, step2_bsize ->
            genotypes: genotypes
            predictions: predictions
            pheno: pheno
            covar: covar
            bsize: step2_bsize
        }

    REGENIE_STEP2(ch_step2.genotypes, ch_step2.predictions, ch_step2.pheno, ch_step2.covar, ch_step2.bsize)

    emit:
    results     = REGENIE_STEP2.out.results // channel: [ val(meta), path(regenie_results) ]
    logs        = PLINK_FIT_REGENIE.out.logs.mix(REGENIE_STEP2.out.log) // channel: [ val(meta), path(log) ]
    predictions = ch_attributed_predictions.map { meta, predictions, _loco -> [meta, predictions] } // channel: [ val(meta), path(predictions) ]
    loco        = ch_attributed_predictions.map { meta, _predictions, loco -> [meta, loco] } // channel: [ val(meta), path(loco) ]
}
