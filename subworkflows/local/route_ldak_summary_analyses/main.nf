// Route nf-core/gwas summary-scale LDAK requests — SumHer heritability and SumCors genetic correlation —
// from canonical summary statistics through to the normalized result families. SumHer and SumCors are one
// controller because they share the canonical-to-LDAK preparation and the endpoint resolution that feeds it.
// This is pipeline routing, reuse identity and scientific/publication policy, not an nf-core/modules
// submission candidate. Every constituent process reports directly to the run-wide versions topic, so this
// subworkflow emits no versions, and it reads no params, no workflow and no projectDir.

// MODULES: Upstream-ready components used inside a pipeline-local route
include { LDAK_SUMCORS                    } from '../../../modules/local/ldak/sumcors/main'
include { LDAK_SUMHER                     } from '../../../modules/local/ldak/sumher/main'

// MODULES: Local to the pipeline
include { NORMALISE_LDAK_SUMCORS          } from '../../../modules/local/normalise_ldak_sumcors/main'
include { NORMALISE_LDAK_SUMHER           } from '../../../modules/local/normalise_ldak_sumher/main'
include { PREPARE_LDAK_SUMMARY_STATISTICS } from '../../../modules/local/prepare_ldak_summary_statistics/main'

workflow ROUTE_LDAK_SUMMARY_ANALYSES {
    take:
    ch_sumher_requests // channel: [ val(meta), path(hapmap3_snplist), path(reference_ld_scores), path(regression_weights), path(tagging_file) ], the ldak_sumher unary requests; LDAK-family bundles supply [] for elements 2-4
    ch_sumcors_requests // channel: [ val(meta), path(hapmap3_snplist), path(reference_ld_scores), path(regression_weights), path(tagging_file) ], the ldak_sumcors pair requests, same convention
    ch_canonical_summary_statistics // channel: [ val(meta), path(canonical_summary_statistics) ], one element per distinct summary_statistics_id

    main:

    // Adapt each distinct summary once, regardless of how many unary, pairwise or named sensitivity
    // requests consume it. The adapter owns only the deterministic canonical-to-LDAK column transform;
    // each request retains its own tagging reference, effective native arguments and publication identity.
    def ch_ldak_requested_summary_ids = ch_sumher_requests
        .map { meta, _hapmap3_snplist, _reference_ld_scores, _regression_weights, _tagging_file -> [meta.summary_statistics_id] }
        .mix(
            ch_sumcors_requests.flatMap { meta, _hapmap3_snplist, _reference_ld_scores, _regression_weights, _tagging_file ->
                [[meta.left_summary_statistics_id], [meta.right_summary_statistics_id]]
            }
        )
        .unique()

    def ch_ldak_canonical_summaries = ch_ldak_requested_summary_ids
        .combine(
            ch_canonical_summary_statistics.map { meta, summary_statistics -> [meta.summary_statistics_id, meta, summary_statistics] },
            by: 0
        )
        .map { _summary_statistics_id, meta, summary_statistics -> [meta, summary_statistics] }

    PREPARE_LDAK_SUMMARY_STATISTICS(ch_ldak_canonical_summaries)

    def ch_prepared_ldak_summaries = PREPARE_LDAK_SUMMARY_STATISTICS.out.summary_statistics
        .map { meta, summary_statistics -> [meta.summary_statistics_id, meta, summary_statistics] }
        .join(
            PREPARE_LDAK_SUMMARY_STATISTICS.out.preparation.map { meta, preparation -> [meta.summary_statistics_id, preparation] },
            failOnDuplicate: true,
            failOnMismatch: true,
        )

    def ch_sumher_invocations = ch_sumher_requests
        .map { meta, _hapmap3_snplist, _reference_ld_scores, _regression_weights, tagging_file -> [meta.summary_statistics_id, meta, tagging_file] }
        .combine(ch_prepared_ldak_summaries, by: 0)
        .multiMap { summary_statistics_id, request_meta, tagging_file, _summary_meta, summary_statistics, preparation ->
            def route_meta = request_meta + [
                id: summary_statistics_id,
                effective_native_args: getLdakSummaryArguments(request_meta),
                native_runtime: getLdakSummaryRuntime(),
            ]
            summary: [route_meta, summary_statistics]
            tagging: [[id: request_meta.reference_bundle_id], tagging_file]
            preparation: [request_meta.request_id, preparation]
        }

    LDAK_SUMHER(
        ch_sumher_invocations.summary,
        ch_sumher_invocations.tagging,
    )

    def ch_sumher_native_results = LDAK_SUMHER.out.hers
        .map { meta, hers -> [meta.request_id, meta, hers] }
        .join(LDAK_SUMHER.out.extra.map { meta, extra -> [meta.request_id, extra] }, failOnDuplicate: true, failOnMismatch: true)
        .join(LDAK_SUMHER.out.overlap.map { meta, overlap -> [meta.request_id, overlap] }, failOnDuplicate: true, failOnMismatch: true)
        .join(LDAK_SUMHER.out.log.map { meta, ldak_log -> [meta.request_id, ldak_log] }, failOnDuplicate: true, failOnMismatch: true)
        .join(ch_sumher_invocations.preparation, failOnDuplicate: true, failOnMismatch: true)
        .join(
            LDAK_SUMHER.out.hers_liability.map { meta, hers_liability -> [meta.request_id, hers_liability] },
            remainder: true,
            failOnDuplicate: true,
        )
        .map { _request_id, meta, hers, extra, overlap, ldak_log, preparation, hers_liability ->
            [meta, hers, extra, overlap, ldak_log, preparation, hers_liability ?: []]
        }

    NORMALISE_LDAK_SUMHER(ch_sumher_native_results)

    def ch_sumcors_left = ch_sumcors_requests
        .map { meta, _hapmap3_snplist, _reference_ld_scores, _regression_weights, tagging_file -> [meta.left_summary_statistics_id, meta, tagging_file] }
        .combine(ch_prepared_ldak_summaries, by: 0)
        .map { _left_summary_statistics_id, request_meta, tagging_file, _left_meta, left_summary_statistics, left_preparation ->
            [request_meta.right_summary_statistics_id, request_meta, tagging_file, left_summary_statistics, left_preparation]
        }

    def ch_sumcors_invocations = ch_sumcors_left
        .combine(ch_prepared_ldak_summaries, by: 0)
        .multiMap { _right_summary_statistics_id, request_meta, tagging_file, left_summary_statistics, left_preparation, right_meta, right_summary_statistics, right_preparation ->
            def route_meta = request_meta + [
                id: request_meta.left_summary_statistics_id,
                effective_native_args: getLdakSummaryArguments(request_meta),
                native_runtime: getLdakSummaryRuntime(),
            ]
            left: [route_meta, left_summary_statistics]
            right: [right_meta, right_summary_statistics]
            tagging: [[id: request_meta.reference_bundle_id], tagging_file]
            preparation: [request_meta.request_id, left_preparation, right_preparation]
        }

    LDAK_SUMCORS(
        ch_sumcors_invocations.left,
        ch_sumcors_invocations.right,
        ch_sumcors_invocations.tagging,
    )

    def ch_sumcors_native_results = LDAK_SUMCORS.out.correlations
        .map { meta, _meta2, correlations -> [meta.request_id, meta, correlations] }
        .join(LDAK_SUMCORS.out.correlations_full.map { meta, _meta2, correlations_full -> [meta.request_id, correlations_full] }, failOnDuplicate: true, failOnMismatch: true)
        .join(LDAK_SUMCORS.out.overlap.map { meta, _meta2, overlap -> [meta.request_id, overlap] }, failOnDuplicate: true, failOnMismatch: true)
        .join(LDAK_SUMCORS.out.log.map { meta, _meta2, ldak_log -> [meta.request_id, ldak_log] }, failOnDuplicate: true, failOnMismatch: true)
        .join(ch_sumcors_invocations.preparation, failOnDuplicate: true, failOnMismatch: true)
        .join(
            LDAK_SUMCORS.out.correlations_liability.map { meta, _meta2, correlations_liability -> [meta.request_id, correlations_liability] },
            remainder: true,
            failOnDuplicate: true,
        )
        .map { _request_id, meta, correlations, correlations_full, overlap, ldak_log, left_preparation, right_preparation, correlations_liability ->
            [meta, correlations, correlations_full, overlap, ldak_log, left_preparation, right_preparation, correlations_liability ?: []]
        }

    NORMALISE_LDAK_SUMCORS(ch_sumcors_native_results)

    emit:
    sumher_heritability          = NORMALISE_LDAK_SUMHER.out.heritability // channel: [ val(meta), path(heritability.tsv) ], one per ldak_sumher request
    sumher_diagnostics           = NORMALISE_LDAK_SUMHER.out.diagnostics // channel: [ val(meta), path(diagnostics.tsv) ]
    sumher_provenance            = NORMALISE_LDAK_SUMHER.out.provenance // channel: [ val(meta), path(provenance.json) ]
    sumcors_heritability         = NORMALISE_LDAK_SUMCORS.out.heritability // channel: [ val(meta), path(heritability.tsv) ], both endpoints of one ldak_sumcors request
    sumcors_genetic_correlation  = NORMALISE_LDAK_SUMCORS.out.genetic_correlation // channel: [ val(meta), path(genetic_correlation.tsv) ]
    sumcors_genetic_covariance   = NORMALISE_LDAK_SUMCORS.out.genetic_covariance // channel: [ val(meta), path(genetic_covariance.tsv) ]
    sumcors_diagnostics          = NORMALISE_LDAK_SUMCORS.out.diagnostics // channel: [ val(meta), path(diagnostics.tsv) ]
    sumcors_provenance           = NORMALISE_LDAK_SUMCORS.out.provenance // channel: [ val(meta), path(provenance.json) ]
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

// The effective native argument list for one summary-scale LDAK request. A request's own `--cutoff` or
// `--truncate` is honoured; otherwise the pipeline's default rare-variant cutoff applies. Liability-scale
// conversion is requested only when the declaring endpoints supply a complete prevalence pair, and SumCors
// emits the declared left-then-right order.
def getLdakSummaryArguments(meta) {
    def args = new ArrayList(meta.native_args ?: [])
    def option_names = args.findAll { token -> token instanceof String && token.startsWith('--') }.collect { token -> token.split('=', 2)[0] }
    if (!option_names.contains('--cutoff') && !option_names.contains('--truncate')) {
        args.addAll(['--cutoff', '0.01'])
    }
    if (meta.method == 'ldak_sumher' && meta.is_binary && meta.population_prevalence != null && meta.sample_prevalence != null) {
        args.addAll(['--prevalence', meta.population_prevalence.toString(), '--ascertainment', meta.sample_prevalence.toString()])
    }
    if (meta.method == 'ldak_sumcors' && meta.left_is_binary && meta.right_is_binary && meta.left_population_prevalence != null && meta.left_sample_prevalence != null && meta.right_population_prevalence != null && meta.right_sample_prevalence != null) {
        args.addAll(
            [
                '--prevalence',
                meta.left_population_prevalence.toString(),
                '--ascertainment',
                meta.left_sample_prevalence.toString(),
                '--prevalence2',
                meta.right_population_prevalence.toString(),
                '--ascertainment2',
                meta.right_sample_prevalence.toString(),
            ]
        )
    }
    return args
}

// The runtime the normalized provenance declares for the native SumHer/SumCors invocation. It is the pinned
// LDAK image the two modules run, recorded so a result states which binary produced it.
def getLdakSummaryRuntime() {
    return 'ghcr.io/lyh970817/gwas/ldak:6.3-b755ab7@sha256:f2b2157559e4346cab5e9f478ab70fc76359743ef06522fed9ad23769d735a6e'
}
