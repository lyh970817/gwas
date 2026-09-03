// Build one LD-by-MAF component plan: the LD scores of a focal PLINK 1 bundle and the ordered, disjoint SNP
// groups derived from them. The plan is the shared input of every LD- and MAF-stratified matrix family, so it
// is built here once rather than inside any one tool's matrix builder.
// Every constituent process reports directly to the run-wide versions topic, so this subworkflow emits no versions.

// MODULE: Local to the pipeline
include { GCTA_CALCULATELDSCORES      } from '../../../modules/local/gcta/calculateldscores/main'
include { CUSTOM_GCTASTRATIFYLDSCORES } from '../../../modules/local/custom/gctastratifyldscores/main'

workflow PLINK_PREPARE_LDMS_PLAN_GCTA {
    take:
    ch_genotypes // channel: [ val(meta), path(bed), path(bim), path(fam) ], focal genotypes
    ch_ld_score_region_kb // channel: [ val(meta2), val(ld_score_region_kb) ], LD-score region size
    ch_ld_bins // channel: [ val(meta3), val(ld_bins) ], LD-score bin count
    ch_maf_edges // channel: [ val(meta4), val(maf_edges) ], MAF edges

    main:
    ch_plan_inputs = ch_genotypes
        .map { meta, bed, bim, fam -> tuple(meta.id, tuple(meta, bed, bim, fam)) }
        .join(ch_ld_score_region_kb.map { meta2, ld_score_region_kb -> tuple(meta2.id, ld_score_region_kb) }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(ch_ld_bins.map { meta3, ld_bins -> tuple(meta3.id, ld_bins) }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .join(ch_maf_edges.map { meta4, maf_edges -> tuple(meta4.id, maf_edges) }, by: 0, failOnDuplicate: true, failOnMismatch: true)

    ch_ld_score_inputs = ch_plan_inputs.multiMap { _plan_id, genotypes, ld_score_region_kb, _ld_bins, _maf_edges ->
        genotypes: genotypes
        region_kb: ld_score_region_kb
    }
    GCTA_CALCULATELDSCORES(ch_ld_score_inputs.genotypes, ch_ld_score_inputs.region_kb)

    ch_stratify_inputs = GCTA_CALCULATELDSCORES.out.ld_scores
        .map { meta, ld_scores -> tuple(meta.id, meta, ld_scores) }
        .join(ch_plan_inputs.map { plan_id, _genotypes, _ld_score_region_kb, ld_bins, maf_edges -> tuple(plan_id, ld_bins, maf_edges) }, by: 0, failOnDuplicate: true, failOnMismatch: true)
        .map { _plan_id, meta, ld_scores, ld_bins, maf_edges -> tuple(meta, ld_scores, ld_bins, maf_edges) }
    CUSTOM_GCTASTRATIFYLDSCORES(ch_stratify_inputs)

    emit:
    plan      = CUSTOM_GCTASTRATIFYLDSCORES.out.strata_bundle // channel: [ val(meta), path(strata_manifest), [ path(snp_group_file), ... ] ], LD-major MAF-minor row order
    ld_scores = GCTA_CALCULATELDSCORES.out.ld_scores // channel: [ val(meta), path(ld_scores) ]
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

// Expand a completed component plan into ordered component records. The ordinal is the 1-based manifest row,
// and the manifest row order is LD-major and MAF-minor with empty strata omitted, which is the stratifier's
// contract. `count` travels with every record so a gather can size its `groupKey` without re-reading the file.
//
// The manifest is parsed by header name rather than by column position, and the retained variant set is the
// union of the group files rather than the BIM: the LD-score pass applies GCTA's own quality control, so a BIM
// row that appears in no group is expected on a real cohort rather than an error.
//
// Deliberately duplicated rather than exported: each composition that expands a plan carries its own copy, so
// no component depends on a Groovy function living inside another submission candidate. Every copy is covered
// by its own `tests/main.function.nf.test` against the one manifest contract stated above.
def readLdmsComponents(manifest, snp_group_files) {
    def rows = manifest.readLines()
    def columns = rows[0].split('\t', -1).toList()
    def groups = (snp_group_files instanceof List ? snp_group_files : [snp_group_files]).collectEntries { snp_group_file -> [snp_group_file.name, snp_group_file] }
    return rows
        .drop(1)
        .withIndex()
        .collect { row, index ->
            def provenance = [columns, row.split('\t', -1).toList()].transpose().collectEntries()
            [
                ordinal: index + 1,
                count: rows.size() - 1,
                stratum_key: provenance.stratum_key,
                predictor_count: provenance.predictor_count as int,
                group_file: groups[provenance.group_filename],
                provenance: provenance,
            ]
        }
}
