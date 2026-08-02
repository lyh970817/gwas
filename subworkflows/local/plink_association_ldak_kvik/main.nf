// Run LDAK-KVIK Step 1 once per analysis and Step 2 across its PLINK 1 genotype shards.
// Every constituent process reports directly to the run-wide versions topic, so this subworkflow emits no versions.

// MODULE: Local to the pipeline
include { LDAK_THINCOMMON } from '../../../modules/local/ldak/thincommon/main'
include { LDAK_KVIKSTEP1  } from '../../../modules/local/ldak/kvikstep1/main'
include { LDAK_KVIKSTEP2  } from '../../../modules/local/ldak/kvikstep2/main'

workflow PLINK_ASSOCIATION_LDAK_KVIK {
    take:
    ch_step1_genotypes // channel: [ val(meta), path(bed), path(bim), path(fam) ], once per analysis
    ch_genotype_shards // channel: [ val(meta), path(bed), path(bim), path(fam) ], one or more per analysis
    ch_pheno // channel: [ val(meta), path(phenotype_file), val(is_binary) ], once per analysis
    ch_qcovar // channel: [ val(meta), path(quant_covariates_file) ], use [] for the optional file
    ch_covar // channel: [ val(meta), path(cat_covariates_file) ], use [] for the optional file
    ch_step1_extract_policy // channel: [ val(meta), path(extract_file), val(subset_policy) ], extract is [] for all/thin_common
    ch_keep // channel: [ val(meta), path(keep_file) ], use [] for the optional file

    main:
    def ch_step1_genotypes_by_analysis = ch_step1_genotypes.map { meta, bed, bim, fam -> tuple(meta.id, tuple(meta, bed, bim, fam)) }
    def ch_genotype_shards_by_analysis = ch_genotype_shards
        .map { meta, bed, bim, fam -> tuple(meta.id, tuple(meta, bed, bim, fam)) }
        .groupTuple(by: 0)

    ch_step1_inputs = ch_step1_genotypes_by_analysis
        .join(
            ch_pheno.map { meta, phenotype_file, is_binary -> tuple(meta.id, tuple(meta, phenotype_file, is_binary)) },
            by: 0,
            failOnDuplicate: true,
            failOnMismatch: true,
        )
        .join(
            ch_qcovar.map { meta, quant_covariates_file -> tuple(meta.id, tuple(meta, quant_covariates_file)) },
            by: 0,
            failOnDuplicate: true,
            failOnMismatch: true,
        )
        .join(
            ch_covar.map { meta, cat_covariates_file -> tuple(meta.id, tuple(meta, cat_covariates_file)) },
            by: 0,
            failOnDuplicate: true,
            failOnMismatch: true,
        )
        .join(
            ch_step1_extract_policy.map { meta, extract_file, subset_policy -> tuple(meta.id, tuple(meta, extract_file, subset_policy)) },
            by: 0,
            failOnDuplicate: true,
            failOnMismatch: true,
        )

    // Collapse analyses with identical scientific Step 1 inputs to one prediction request. The execution
    // metadata owns the content key; focal analysis metadata is retained separately for Step 2 attribution.
    def ch_prediction_requests = ch_step1_inputs
        .map { _analysis_id, genotypes, pheno, qcovar, covar, extract_policy ->
            tuple(genotypes[0].kvik_prediction_key, genotypes, pheno, qcovar, covar, extract_policy)
        }
        .unique { prediction_key, _genotypes, _pheno, _qcovar, _covar, _extract_policy -> prediction_key }
        .map { prediction_key, genotypes, pheno, qcovar, covar, extract_policy ->
            def execution_meta = genotypes[0] + [id: "${genotypes[0].cohort}.ldak_kvik.${prediction_key}"]
            tuple(
                prediction_key,
                tuple(execution_meta, genotypes[1], genotypes[2], genotypes[3]),
                tuple(execution_meta, pheno[1], pheno[2]),
                tuple(execution_meta, qcovar[1]),
                tuple(execution_meta, covar[1]),
                tuple(execution_meta, extract_policy[1], extract_policy[2]),
            )
        }

    ch_thin_common_inputs = ch_prediction_requests.filter { _prediction_key, _genotypes, _pheno, _qcovar, _covar, extract_policy -> extract_policy[2] == 'thin_common' }
    ch_thin_common_genotypes = ch_thin_common_inputs.map { _prediction_key, genotypes, _pheno, _qcovar, _covar, _extract_policy -> genotypes }
    LDAK_THINCOMMON(ch_thin_common_genotypes)

    ch_direct_step1_inputs = ch_prediction_requests
        .filter { _prediction_key, _genotypes, _pheno, _qcovar, _covar, extract_policy -> extract_policy[2] in ['all', 'provided'] }
        .map { _prediction_key, genotypes, pheno, qcovar, covar, extract_policy ->
            tuple(genotypes, pheno, qcovar, covar, tuple(extract_policy[0], extract_policy[1]))
        }
    ch_thin_step1_inputs = ch_thin_common_inputs
        .map { prediction_key, genotypes, pheno, qcovar, covar, _extract_policy -> tuple(prediction_key, genotypes, pheno, qcovar, covar) }
        .join(
            LDAK_THINCOMMON.out.predictors.map { meta, extract_file -> tuple(meta.kvik_prediction_key, tuple(meta, extract_file)) },
            by: 0,
            failOnDuplicate: true,
            failOnMismatch: true,
        )
        .map { _prediction_key, genotypes, pheno, qcovar, covar, extract -> tuple(genotypes, pheno, qcovar, covar, extract) }
    ch_step1_invocations = ch_direct_step1_inputs
        .mix(ch_thin_step1_inputs)
        .multiMap { genotypes, pheno, qcovar, covar, extract ->
            genotypes: genotypes
            pheno: pheno
            qcovar: qcovar
            covar: covar
            extract: extract
        }

    LDAK_KVIKSTEP1(
        ch_step1_invocations.genotypes,
        ch_step1_invocations.pheno,
        ch_step1_invocations.qcovar,
        ch_step1_invocations.covar,
        ch_step1_invocations.extract,
    )

    def ch_analysis_step2_inputs = ch_step1_inputs
        .map { analysis_id, genotypes, pheno, qcovar, covar, _extract_policy ->
            tuple(analysis_id, genotypes[0].kvik_prediction_key, genotypes, pheno, qcovar, covar)
        }
        .join(
            ch_genotype_shards_by_analysis,
            by: 0,
            failOnDuplicate: true,
            failOnMismatch: true,
        )
        .join(
            ch_keep.map { meta, keep_file -> tuple(meta.id, tuple(meta, keep_file)) },
            by: 0,
            failOnDuplicate: true,
            failOnMismatch: true,
        )
        .map { _analysis_id, prediction_key, genotypes, pheno, qcovar, covar, genotype_shards, keep ->
            tuple(prediction_key, genotype_shards, genotypes, pheno, qcovar, covar, keep)
        }

    ch_step2_invocations = ch_analysis_step2_inputs
        .combine(
            LDAK_KVIKSTEP1.out.predictions.map { meta, step1_root, step1_loco_details, step1_loco_prs ->
                tuple(meta.kvik_prediction_key, tuple(meta, step1_root, step1_loco_details, step1_loco_prs))
            },
            by: 0
        )
        .flatMap { _prediction_key, genotype_shards, genotypes, pheno, qcovar, covar, keep, predictions ->
            genotype_shards.collect { genotype_shard ->
                tuple(
                    tuple(genotypes[0], genotype_shard[1], genotype_shard[2], genotype_shard[3]),
                    tuple(pheno[0], pheno[1]),
                    predictions,
                    qcovar,
                    covar,
                    keep,
                )
            }
        }
        .multiMap { genotypes, pheno, predictions, qcovar, covar, keep ->
            genotypes: genotypes
            pheno: pheno
            predictions: predictions
            qcovar: qcovar
            covar: covar
            keep: keep
        }

    LDAK_KVIKSTEP2(
        ch_step2_invocations.genotypes,
        ch_step2_invocations.pheno,
        ch_step2_invocations.predictions,
        ch_step2_invocations.qcovar,
        ch_step2_invocations.covar,
        ch_step2_invocations.keep,
    )

    ch_logs = LDAK_KVIKSTEP1.out.log.mix(LDAK_KVIKSTEP2.out.log)

    emit:
    results             = LDAK_KVIKSTEP2.out.results // channel: [ val(meta), path(assoc) ], once per Step 2 shard
    harmonisation_input = LDAK_KVIKSTEP2.out.harmonisation_input // channel: [ val(meta), path(tsv) ], once per Step 2 shard
    summaries           = LDAK_KVIKSTEP2.out.summaries // channel: [ val(meta), path(summaries) ], once per Step 2 shard
    pvalues             = LDAK_KVIKSTEP2.out.pvalues // channel: [ val(meta), path(pvalues) ], optional per shard
    predictions         = LDAK_KVIKSTEP1.out.predictions // channel: [ val(meta), path(root), path(loco_details), path(loco_prs) ]
    effects             = LDAK_KVIKSTEP1.out.effects // channel: [ val(meta), path(effects) ], optional per analysis
    progress            = LDAK_THINCOMMON.out.progress // channel: [ val(meta), path(progress) ], only for thin_common analyses
    logs                = ch_logs // channel: [ val(meta), path(log) ]
}
