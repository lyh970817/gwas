//
// Common-variant meta-analysis of two or more canonical summary statistics.
//
// Fixed effects, conventional random effects and Han-Eskin RE2 are all strictly per variant, so the
// whole composition scatters by chromosome with no special handling: each shard restricts every
// parent to one chromosome and runs the identical computation. The gather then refuses anything
// that is not exactly one completed shard per requested chromosome, because the failure worth
// guarding against is a result that looks whole but quietly lost a chromosome.
//
// MR-MEGA is deliberately NOT wired here. It cannot scatter naively: its ancestry axes are derived
// from genome-wide between-study allele-frequency differences, so per-chromosome axis derivation
// would be a different model on every shard. The supported design is two-pass -- thin genome-wide,
// derive axes once, canonicalize the axis signs, then scatter with `--precalculated` fixed axes --
// and it needs three components that do not exist yet. See meta.yml and META-ANALYSIS-STATUS.md.
//

include { GWASLAB_META_ANALYZE          } from '../../../modules/local/gwaslab/meta_analyze/main'
include { METASOFT_RE2                  } from '../../../modules/local/metasoft/re2/main'
include { NORMALISE_COMMON_VARIANT_META } from '../../../modules/local/normalise_common_variant_meta/main'
include { GATHER_META_SHARDS            } from '../../../modules/local/gather_meta_shards/main'

workflow COMMON_VARIANT_META_ANALYSIS {
    take:
    // [ val(meta), path(parents), val(study_names), val(input_format), val(genome_build),
    //   val(models), val(chromosomes) ]
    //   parents      ordered canonical parent tables, at least two, in exact positional study order
    //   study_names  unique labels in the same order; defines the direction string and column order
    //   models       subset of 'fixed', 'random', 're2'; 'fixed' is always produced
    //   chromosomes  ordered chromosomes to scatter over, or [] for a single genome-wide shard
    ch_request

    main:

    // One record per shard. The shard identity lives in meta.id so that every output basename is
    // distinct in the gather's staging directory; the request identity is carried alongside so the
    // shards can be regrouped without parsing it back out of a filename.
    ch_plan = ch_request.flatMap { meta, parents, study_names, input_format, genome_build, models, chromosomes ->
        def targets = chromosomes ? chromosomes.collect { chromosome -> chromosome.toString() } : ['']
        if (targets.size() != targets.unique().size()) {
            error("common_variant_meta_analysis: request ${meta.id} repeats a chromosome")
        }
        targets.collect { chromosome ->
            def shard = meta + [id: chromosome ? "${meta.id}_chr${chromosome}" : meta.id]
            [shard, meta, chromosome, parents, study_names, input_format, genome_build, models]
        }
    }

    GWASLAB_META_ANALYZE(
        ch_plan.map { shard, _request, chromosome, parents, study_names, input_format, genome_build, _models ->
            [shard, parents, study_names, input_format, genome_build, chromosome]
        }
    )

    // Rejoin the plan so each shard's outputs travel with its request identity and model selection.
    ch_context = ch_plan.map { shard, request, chromosome, _parents, _names, _format, _build, models ->
        [shard, request, chromosome, models]
    }

    ch_re2_requested = GWASLAB_META_ANALYZE.out.effect_matrix
        .join(ch_context, failOnMismatch: true, failOnDuplicate: true)
        .branch { _shard, _matrix, _request, _chromosome, models ->
            run: models.contains('re2')
            skip: true
        }

    METASOFT_RE2(
        ch_re2_requested.run.map { shard, matrix, _request, _chromosome, _models -> [shard, matrix] }
    )

    // Absent optional model output is [], never a placeholder file.
    ch_re2 = METASOFT_RE2.out.re2.mix(
        ch_re2_requested.skip.map { shard, _matrix, _request, _chromosome, _models -> [shard, []] }
    )

    ch_normalise = GWASLAB_META_ANALYZE.out.meta_analysis
        .join(GWASLAB_META_ANALYZE.out.study_order, failOnMismatch: true, failOnDuplicate: true)
        .join(GWASLAB_META_ANALYZE.out.qc, failOnMismatch: true, failOnDuplicate: true)
        .join(GWASLAB_META_ANALYZE.out.derivation, failOnMismatch: true, failOnDuplicate: true)
        .join(ch_re2, failOnMismatch: true, failOnDuplicate: true)
        .map { shard, table, study_order, qc, derivation, re2 ->
            [shard, table, study_order, qc, derivation, re2, []]
        }

    NORMALISE_COMMON_VARIANT_META(ch_normalise)

    // Group the per-shard candidates back onto their request. The GWASLab QC document is the
    // completion record: it declares the shard's chromosome and its eligible-variant count, which
    // is what lets a legitimately empty chromosome be told apart from one that never ran.
    ch_gathered_input = NORMALISE_COMMON_VARIANT_META.out.candidate
        .join(GWASLAB_META_ANALYZE.out.qc, failOnMismatch: true, failOnDuplicate: true)
        .join(ch_context, failOnMismatch: true, failOnDuplicate: true)
        .map { _shard, candidate, qc, request, chromosome, _models ->
            [request, candidate, qc, chromosome]
        }
        .groupTuple()
        .map { request, candidates, records, chromosomes ->
            [request, candidates, records, chromosomes.collect { chromosome -> chromosome ?: 'ALL' }]
        }

    // A genome-wide request is a one-shard gather rather than a special case, so the completeness
    // and duplicate-variant checks apply identically whether or not the run was scattered.
    GATHER_META_SHARDS(
        ch_gathered_input.map { request, candidates, records, chromosomes ->
            [request, candidates, records, chromosomes]
        }
    )

    emit:
    candidate    = GATHER_META_SHARDS.out.gathered            // [ meta, path(tsv.gz) ]  one per request
    gather_report = GATHER_META_SHARDS.out.report             // [ meta, path(json) ]
    shard_derivation = NORMALISE_COMMON_VARIANT_META.out.derivation // [ shard_meta, path(json) ]
    shard_qc     = GWASLAB_META_ANALYZE.out.qc                // [ shard_meta, path(json) ]
    study_order  = GWASLAB_META_ANALYZE.out.study_order       // [ shard_meta, path(tsv) ]
    re2          = METASOFT_RE2.out.re2                       // [ shard_meta, path(tsv.gz) ] when requested
}
