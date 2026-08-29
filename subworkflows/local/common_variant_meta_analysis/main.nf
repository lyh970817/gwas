//
// Common-variant meta-analysis of two or more canonical summary statistics.
//
// Fixed effects, conventional random effects and Han-Eskin RE2 are strictly per variant, so they
// scatter by chromosome with no special handling: each shard restricts every parent to one
// chromosome and runs the identical computation.
//
// MR-MEGA cannot scatter that way. Its ancestry axes come from genome-wide between-study
// allele-frequency differences, so deriving them per chromosome would fit a different model on
// every shard. It therefore runs in two passes:
//
//   thin genome-wide  ->  pass 1 derives axes  ->  signs canonicalized
//                     ->  pass 2 scatters with --precalculated fixed axes  ->  gather
//
// Canonicalizing the axis signs between the passes means every shard is born canonical. Negating an
// axis flips exactly the coefficient beta_{j+1} and leaves se, every chi-square, every ndf, every P
// value and lnBF bit-identical, so it is a free transform there and would be a correction pass
// afterwards. Scatter itself contributes no numerical error; the only residual against an
// unscattered run is the six significant figures MR-MEGA prints its coordinates with.
//
// The gather then refuses anything that is not exactly one completed shard per requested
// chromosome, because the failure worth guarding against is a result that looks whole but quietly
// lost a chromosome.
//

include { GWASLAB_META_ANALYZE                             } from '../../../modules/local/gwaslab/meta_analyze/main'
include { METASOFT_RE2                                     } from '../../../modules/local/metasoft/re2/main'
include { THIN_MRMEGA_MARKERS                              } from '../../../modules/local/thin_mrmega_markers/main'
include { PREPARE_MRMEGA_INPUT as PREPARE_MRMEGA_AXIS_INPUT } from '../../../modules/local/prepare_mrmega_input/main'
include { MRMEGA as MRMEGA_DERIVE_AXES                     } from '../../../modules/local/mrmega/main'
include { EXTRACT_MRMEGA_AXES                              } from '../../../modules/local/extract_mrmega_axes/main'
include { PREPARE_MRMEGA_INPUT as PREPARE_MRMEGA_SHARD_INPUT } from '../../../modules/local/prepare_mrmega_input/main'
include { MRMEGA as MRMEGA_SCATTER                         } from '../../../modules/local/mrmega/main'
include { NORMALISE_MRMEGA_RESULT                          } from '../../../modules/local/normalise_mrmega_result/main'
include { NORMALISE_COMMON_VARIANT_META                    } from '../../../modules/local/normalise_common_variant_meta/main'
include { GATHER_META_SHARDS                               } from '../../../modules/local/gather_meta_shards/main'

workflow COMMON_VARIANT_META_ANALYSIS {
    take:
    // [ val(meta), path(parents), val(study_names), val(input_format), val(genome_build),
    //   val(trait_type), val(models), val(axes), val(chromosomes) ]
    //   parents      ordered canonical parent tables, at least two, in exact positional study order
    //   study_names  unique labels in the same order; defines the direction string and column order
    //   trait_type   'quantitative' or 'binary'; selects the MR-MEGA effect parameterisation
    //   models       subset of 'fixed', 'random', 're2', 'mrmega'; 'fixed' is always produced
    //   axes         MR-MEGA axis count, required when 'mrmega' is selected, else null
    //   chromosomes  ordered chromosomes to scatter over, or [] for a single genome-wide shard
    ch_request

    main:

    // One record per shard. Shard identity lives in meta.id so every output basename is distinct in
    // the gather's staging directory; the request identity is carried alongside so shards regroup
    // without parsing it back out of a filename. The separator is an underscore because the gather
    // pairs shards to completion records on the basename stem before the first dot.
    ch_plan = ch_request.flatMap { meta, parents, study_names, input_format, genome_build, trait_type, models, axes, chromosomes ->
        def targets = chromosomes ? chromosomes.collect { chromosome -> chromosome.toString() } : ['']
        if (targets.size() != targets.unique().size()) {
            error("common_variant_meta_analysis: request ${meta.id} repeats a chromosome")
        }
        if (models.contains('mrmega') && !axes) {
            error("common_variant_meta_analysis: request ${meta.id} selects mrmega without an axis count")
        }
        targets.collect { chromosome ->
            def shard = meta + [id: chromosome ? "${meta.id}_chr${chromosome}" : meta.id]
            [shard, meta, chromosome, parents, study_names, input_format, genome_build, trait_type, models, axes]
        }
    }

    GWASLAB_META_ANALYZE(
        ch_plan.map { shard, _request, chromosome, parents, study_names, input_format, genome_build, _trait, _models, _axes ->
            [shard, parents, study_names, input_format, genome_build, chromosome]
        }
    )

    // Rejoin the plan so each shard's outputs travel with its request identity and selections.
    ch_context = ch_plan.map { shard, request, chromosome, _parents, study_names, _format, _build, trait_type, models, axes ->
        [shard, request, chromosome, study_names, trait_type, models, axes]
    }

    //
    // Han-Eskin RE2. Per variant, so it simply follows the shard.
    //
    ch_re2_branch = GWASLAB_META_ANALYZE.out.effect_matrix
        .join(ch_context, failOnMismatch: true, failOnDuplicate: true)
        .branch { _shard, _matrix, _request, _chromosome, _names, _trait, models, _axes ->
            run: models.contains('re2')
            skip: true
        }

    METASOFT_RE2(ch_re2_branch.run.map { shard, matrix, _r, _c, _n, _t, _m, _a -> [shard, matrix] })

    // Absent optional model output is [], never a placeholder file.
    ch_re2 = METASOFT_RE2.out.re2.mix(
        ch_re2_branch.skip.map { shard, _matrix, _r, _c, _n, _t, _m, _a -> [shard, []] }
    )

    //
    // MR-MEGA pass 1: thin genome-wide, derive axes once, canonicalize their signs.
    //
    ch_views = GWASLAB_META_ANALYZE.out.study_views
        .join(ch_context, failOnMismatch: true, failOnDuplicate: true)

    ch_mrmega_views = ch_views.branch { _shard, _views, _request, _chromosome, _names, _trait, models, _axes ->
        run: models.contains('mrmega')
        skip: true
    }

    // Every shard of one request contributes its aligned view to the single axis-derivation set.
    ch_axis_source = ch_mrmega_views.run
        .map { _shard, views, request, _chromosome, names, trait_type, _models, axes ->
            [request, views, names, trait_type, axes]
        }
        .groupTuple()
        .map { request, views, names, trait_types, axes ->
            [request + [id: "${request.id}_axes"], request, views, names.first(), trait_types.first(), axes.first()]
        }

    THIN_MRMEGA_MARKERS(
        ch_axis_source.map { axis_meta, _request, views, names, _trait, _axes ->
            [axis_meta, views, names.size()]
        }
    )

    ch_axis_context = ch_axis_source.map { axis_meta, request, _views, names, trait_type, axes ->
        [axis_meta, request, names, trait_type, axes]
    }

    PREPARE_MRMEGA_AXIS_INPUT(
        THIN_MRMEGA_MARKERS.out.thinned
            .join(ch_axis_context, failOnMismatch: true, failOnDuplicate: true)
            .map { axis_meta, thinned, _request, names, trait_type, _axes -> [axis_meta, thinned, names, trait_type] }
    )

    // Pass 1 derives the axes, so it takes no precalculated manifest.
    MRMEGA_DERIVE_AXES(
        PREPARE_MRMEGA_AXIS_INPUT.out.study_files
            .join(PREPARE_MRMEGA_AXIS_INPUT.out.filelist, failOnMismatch: true, failOnDuplicate: true)
            .join(ch_axis_context, failOnMismatch: true, failOnDuplicate: true)
            .map { axis_meta, study_files, filelist, _request, _names, _trait, axes ->
                [axis_meta, study_files, filelist, axes, []]
            }
    )

    EXTRACT_MRMEGA_AXES(
        MRMEGA_DERIVE_AXES.out.log
            .join(PREPARE_MRMEGA_AXIS_INPUT.out.filelist, failOnMismatch: true, failOnDuplicate: true)
            .join(ch_axis_context, failOnMismatch: true, failOnDuplicate: true)
            .map { axis_meta, mrmega_log, filelist, _request, _names, _trait, axes ->
                [axis_meta, mrmega_log, filelist, axes]
            }
    )

    // Key the canonical axes by the request so they can be broadcast onto that request's shards.
    ch_axes_by_request = EXTRACT_MRMEGA_AXES.out.precalculated_axes
        .join(ch_axis_context, failOnMismatch: true, failOnDuplicate: true)
        .map { _axis_meta, precalculated, request, _names, _trait, _axes -> [request, precalculated] }

    //
    // MR-MEGA pass 2: one run per shard, every one fitting the same canonical axes.
    //
    PREPARE_MRMEGA_SHARD_INPUT(
        ch_mrmega_views.run.map { shard, views, _request, _chromosome, names, trait_type, _models, _axes ->
            [shard, views, names, trait_type]
        }
    )

    ch_shard_axes = ch_mrmega_views.run
        .map { shard, _views, request, _chromosome, _names, _trait, _models, axes -> [request, shard, axes] }
        .combine(ch_axes_by_request, by: 0)
        .map { _request, shard, axes, precalculated -> [shard, axes, precalculated] }

    MRMEGA_SCATTER(
        PREPARE_MRMEGA_SHARD_INPUT.out.study_files
            .join(PREPARE_MRMEGA_SHARD_INPUT.out.filelist, failOnMismatch: true, failOnDuplicate: true)
            .join(ch_shard_axes, failOnMismatch: true, failOnDuplicate: true)
            .map { shard, study_files, filelist, axes, precalculated ->
                [shard, study_files, filelist, axes, precalculated]
            }
    )

    NORMALISE_MRMEGA_RESULT(
        MRMEGA_SCATTER.out.result
            .join(ch_shard_axes, failOnMismatch: true, failOnDuplicate: true)
            .map { shard, result, axes, _precalculated -> [shard, result, axes] }
    )

    ch_mrmega = NORMALISE_MRMEGA_RESULT.out.fields.mix(
        ch_mrmega_views.skip.map { shard, _views, _r, _c, _n, _t, _m, _a -> [shard, []] }
    )

    //
    // Normalise every shard, then gather.
    //
    ch_normalise = GWASLAB_META_ANALYZE.out.meta_analysis
        .join(GWASLAB_META_ANALYZE.out.study_order, failOnMismatch: true, failOnDuplicate: true)
        .join(GWASLAB_META_ANALYZE.out.qc, failOnMismatch: true, failOnDuplicate: true)
        .join(GWASLAB_META_ANALYZE.out.derivation, failOnMismatch: true, failOnDuplicate: true)
        .join(ch_re2, failOnMismatch: true, failOnDuplicate: true)
        .join(ch_mrmega, failOnMismatch: true, failOnDuplicate: true)

    NORMALISE_COMMON_VARIANT_META(ch_normalise)

    // The GWASLab QC document is the completion record: it declares the shard's chromosome and its
    // eligible-variant count, which is what lets a legitimately empty chromosome be told apart from
    // one that never ran.
    ch_gathered_input = NORMALISE_COMMON_VARIANT_META.out.candidate
        .join(GWASLAB_META_ANALYZE.out.qc, failOnMismatch: true, failOnDuplicate: true)
        .join(ch_context, failOnMismatch: true, failOnDuplicate: true)
        .map { _shard, candidate, qc, request, chromosome, _names, _trait, _models, _axes ->
            [request, candidate, qc, chromosome]
        }
        .groupTuple()
        .map { request, candidates, records, chromosomes ->
            [request, candidates, records, chromosomes.collect { chromosome -> chromosome ?: 'ALL' }]
        }

    // A genome-wide request is a one-shard gather rather than a special case, so the completeness
    // and duplicate-variant checks apply identically whether or not the run was scattered.
    GATHER_META_SHARDS(ch_gathered_input)

    emit:
    candidate        = GATHER_META_SHARDS.out.gathered                // [ meta, path(tsv.gz) ] one per request
    gather_report    = GATHER_META_SHARDS.out.report                  // [ meta, path(json) ]
    shard_derivation = NORMALISE_COMMON_VARIANT_META.out.derivation   // [ shard_meta, path(json) ]
    shard_qc         = GWASLAB_META_ANALYZE.out.qc                    // [ shard_meta, path(json) ]
    study_order      = GWASLAB_META_ANALYZE.out.study_order           // [ shard_meta, path(tsv) ]
    re2              = METASOFT_RE2.out.re2                           // [ shard_meta, path(tsv.gz) ]
    ancestry_axes    = EXTRACT_MRMEGA_AXES.out.coordinates            // [ axis_meta, path(tsv) ]
    axes_qc          = EXTRACT_MRMEGA_AXES.out.qc                     // [ axis_meta, path(json) ]
}
