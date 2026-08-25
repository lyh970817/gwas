// Converge every summary-statistics origin on the one canonical contract. Internal association results carry
// producer metadata and a producer-specific GWASLab column mapping; an external raw row supplies its own named
// GWASLab format; an already-canonical external row bypasses harmonisation and enters only the canonical
// contract validator. Whatever the origin, the canonical table and its provenance sidecar are serialised by one
// component, so a scientific table is never published twice under two identities.
//
// This is pipeline routing, producer identity and publication policy, not an nf-core/modules submission
// candidate. This controller owns canonical serialisation only: it holds no meta-analysis eligibility rule and
// no harmonisation policy beyond the mappings the validated relational contract already registers. Every
// constituent process reports directly to the run-wide versions topic, so this subworkflow emits no versions,
// and it reads no params, no workflow and no projectDir — the build-keyed GWASLab resources arrive resolved.

// MODULE: Local to the pipeline
include { CANONICALISE_SUMMARY_STATISTICS } from '../../../modules/local/canonicalise_summary_statistics/main'
include { GWASLAB_HARMONIZE               } from '../../../modules/local/gwaslab/harmonize/main'

// FUNCTION: Local to the pipeline
include { getAssociationColumnMappingJson } from '../validate_gwas_input'
include { getInternalSummaryMetadata      } from '../validate_gwas_input'

workflow ROUTE_CANONICAL_SUMMARY_STATISTICS {
    take:
    ch_association_results // channel: [ val(meta), path(sumstats) ], one per analysis per association method actually exercised, `meta.method` named by the producing route
    ch_external_summary_statistics // channel: [ val(meta), path(source) ], every declared external summary row, both `raw` and `canonical` source modes
    gwaslab_references // value: map of genome build to the resolved GWASLab reference resources [fasta, fasta_index, rsid_vcf, rsid_vcf_index, strand_vcf, strand_vcf_index], each `[]` when unconfigured

    main:

    // Internal association results and external raw inputs converge before GWASLab. The producer-specific
    // internal mappings remain explicit and unchanged; an external row supplies a named GWASLab format.
    // Already-canonical external inputs bypass GWASLab and enter only the canonical contract validator.
    def ch_harmonise_records = ch_association_results
        .map { meta, source ->
            def summary_meta = getInternalSummaryMetadata(meta, meta.method) + [
                method: meta.method,
                source_name: source.name,
                gwaslab_input_format: getAssociationColumnMappingJson(meta.method, meta.is_binary),
            ]
            [summary_meta, source]
        }
        .mix(
            ch_external_summary_statistics.filter { meta, _source -> meta.source_mode == 'raw' }.map { meta, source -> [meta + [method: 'external', gwaslab_input_format: meta.source_format], source] }
        )

    // The optional GWASLab resources remain build-keyed pipeline parameters, resolved once by the spine and
    // passed in whole. This is independent from the request-owned LDSC/LDAK reference catalog and does not
    // infer a scientific analysis reference.
    def ch_harmonise_input = ch_harmonise_records.multiMap { meta, source ->
        def references = gwaslab_references[meta.build]
        sumstats: [meta, source, meta.gwaslab_input_format, meta.build]
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

    // Strict source reattribution: the canonicalisation adapter records a `source_sha256` over the bytes the
    // canonical table was derived from, so each harmonised candidate must be rejoined to its own source rather
    // than to any other. Validation forbids a duplicate `summary_statistics_id`, and the strict flags are what
    // say so if that ever stops holding. The scatter key never leaves a tuple position.
    def ch_harmonise_sources = ch_harmonise_records.map { meta, source -> [meta.summary_statistics_id, source] }
    def ch_canonical_candidates = GWASLAB_HARMONIZE.out.sumstats
        .map { meta, candidate -> [meta.summary_statistics_id, meta, candidate] }
        .join(ch_harmonise_sources, failOnDuplicate: true, failOnMismatch: true)
        .map { _summary_statistics_id, meta, candidate, source -> [meta, candidate, source] }
        .mix(
            ch_external_summary_statistics.filter { meta, _source -> meta.source_mode == 'canonical' }.map { meta, source -> [meta, source, source] }
        )

    CANONICALISE_SUMMARY_STATISTICS(ch_canonical_candidates)

    // The emitted metadata is the focal summary-statistics identity itself and is passed through unchanged:
    // the canonicalisation adapter serialises it whole into the published provenance sidecar, and the LDAK and
    // LDSC summary routes resolve their endpoints against `summary_statistics_id`. Nothing here is a private
    // reuse key, so nothing is stripped.

    emit:
    summary_statistics = CANONICALISE_SUMMARY_STATISTICS.out.summary_statistics // channel: [ val(meta), path(canonical_summary_statistics) ], exactly one per summary_statistics_id
    provenance         = CANONICALISE_SUMMARY_STATISTICS.out.provenance // channel: [ val(meta), path(provenance) ], one-to-one with summary_statistics on the same task
}
