// Prepare each distinct cohort once in the representation it was supplied in, and derive PLINK 1 only when a
// selected consumer of that cohort reads PLINK 1. Every process reports on the run-wide versions topic, so
// this subworkflow emits no versions.

// MODULE: Local to the pipeline
include { PREPARE_GENOTYPE_SOURCE       } from '../../../modules/local/prepare_genotype_source/main'
include { PREPARE_PGEN_STATE            } from '../../../modules/local/prepare_pgen_state/main'
include { PLINK2_MAKEBED                } from '../../../modules/local/plink2/makebed/main'
include { PLINK2_VCF                    } from '../../../modules/local/plink2/vcf/main'

// FUNCTION: Local to the pipeline
include { buildScientificArtifactKey    } from '../utils_nfcore_gwas_pipeline'
include { getPlink1GenotypeMethodTokens } from '../validate_gwas_input/method_registry'

workflow PREPARE_COHORT_GENOTYPES {
    take:
    ch_requests // channel: [ val(meta), [ path(genotype_file), ... ] ], one element per unary analysis and per relationship row

    main:

    //
    // The prepared-key set is a reduction of the request-key set, not a second collection compared
    // against it. Every cohort key emitted here came from a request, so the prepared set is total;
    // `unique` collapses the repeats, so it is unique. Both properties hold structurally and there is
    // nothing left to assert afterwards — which matters, because the `combine` below reports neither a
    // missing key nor a duplicate one. Building the cohort set from any other source, or asserting
    // totality after the fact, would reintroduce exactly the failure this shape removes.
    //
    // Collapsing on the cohort key alone is safe because input validation has already refused any
    // samplesheet whose rows share a `cohort_id` while naming different genotype files or declaring
    // different view identities, so every discarded repeat is known to be identical to the one kept.
    //
    def ch_cohorts = ch_requests
        .map { meta, genotype_files ->
            [meta.cohort, [id: meta.cohort, genotype_format: meta.genotype_format, genotype_view_id: meta.genotype_view_id], genotype_files]
        }
        .unique { cohort_id, _cohort_meta, _genotype_files -> cohort_id }
        .map { _cohort_id, cohort_meta, genotype_files -> [cohort_meta, genotype_files] }

    //
    // PLINK 1 demand, per cohort, derived from the registry rather than from a method list repeated here.
    // A route controller declares nothing: a method's registry entry carries the representation its own
    // executable or its matrix builder reads, and that is the only thing consulted.
    //
    def plink1_methods = getPlink1GenotypeMethodTokens()
    def ch_plink1_requests = ch_requests.filter { meta, _genotype_files ->
        getSelectedMethods(meta).any { method -> method in plink1_methods }
    }
    def ch_plink1_demand = ch_plink1_requests
        .map { meta, _genotype_files -> [meta.cohort, true] }
        .unique { cohort_id, _demanded -> cohort_id }

    //
    // MODULE: Digest a supplied bundle whose identity the researcher did not declare
    //
    // The identity is either the declared token or a content digest computed in a task. `source` carries only
    // the pair `[mode, value]`, which is what enters keys and process metadata; the per-member detail travels
    // on its own channel and never reaches a task hash, so a byte-identical bundle under different names
    // keeps every artifact key it produced. A launcher-mounted view declares its identity and is therefore
    // never opened here, which is the whole point of the declaration.
    //
    def ch_by_identity = ch_cohorts.branch { cohort_meta, _genotype_files ->
        declared: cohort_meta.genotype_view_id
        digested: true
    }

    PREPARE_GENOTYPE_SOURCE(
        ch_by_identity.digested.map { cohort_meta, genotype_files -> [cohort_meta.subMap(['id', 'genotype_format']), genotype_files] }
    )

    def ch_sources = ch_by_identity.declared
        .map { cohort_meta, genotype_files -> [cohort_meta, genotype_files, [mode: 'declared', value: cohort_meta.genotype_view_id], null] }
        .mix(
            ch_by_identity.digested
                .map { cohort_meta, genotype_files -> [cohort_meta.id, cohort_meta, genotype_files] }
                .join(PREPARE_GENOTYPE_SOURCE.out.source_identity.map { source_meta, digest -> [source_meta.id, digest] }, failOnDuplicate: true, failOnMismatch: true)
                .join(PREPARE_GENOTYPE_SOURCE.out.source_members.map { source_meta, members -> [source_meta.id, members] }, failOnDuplicate: true, failOnMismatch: true)
                .map { cohort_id, cohort_meta, genotype_files, digest, members ->
                    [cohort_meta, genotype_files, [mode: 'sha256', value: readSourceIdentity(cohort_id, digest)], readSourceMembers(cohort_id, members)]
                }
        )

    //
    // The native stream, in format-polymorphic member order: primary, variant file, sample file. A PLINK 1
    // or PLINK 2 cohort is passed through exactly as supplied — converting it would cost a round trip and
    // produce the same bundle, and for a mounted view it would materialise the very bytes the mount exists to
    // avoid copying. Nothing the pipeline did not build is published.
    //
    def ch_by_format = ch_sources.branch { cohort_meta, _genotype_files, _source, _members ->
        plink2: cohort_meta.genotype_format == 'plink2'
        plink1: cohort_meta.genotype_format == 'plink1'
        vcf: cohort_meta.genotype_format == 'vcf'
    }

    def ch_native_supplied = ch_by_format.plink2
        .map { cohort_meta, genotype_files, source, members ->
            def (pgen, psam, pvar) = genotype_files
            [buildNativeView(cohort_meta, 'plink2', 'supplied', source, [:]), pgen, pvar, psam, members]
        }
        .mix(
            ch_by_format.plink1.map { cohort_meta, genotype_files, source, members ->
                def (bed, bim, fam) = genotype_files
                [buildNativeView(cohort_meta, 'plink1', 'supplied', source, [:]), bed, bim, fam, members]
            }
        )

    //
    // MODULE: Import a VCF cohort to PGEN once
    //
    // The import policy is declared once in `getVcfImportPolicy` and travels in `meta.settings`;
    // `conf/modules/genotypes.config` renders it into the native flags, so the policy the view identity
    // records and the policy the command applies are the same map.
    //
    def ch_vcf_inputs = ch_by_format.vcf.map { cohort_meta, genotype_files, source, members ->
        [buildNativeView(cohort_meta, 'plink2', 'vcf_import', source, getVcfImportPolicy()), genotype_files.first(), members]
    }

    PLINK2_VCF(ch_vcf_inputs.map { view_meta, vcf, _members -> [view_meta, vcf] })

    def ch_native = ch_native_supplied.mix(
        PLINK2_VCF.out.pgen
            .map { view_meta, pgen, psam, pvar -> [view_meta.id, view_meta, pgen, pvar, psam] }
            .join(ch_vcf_inputs.map { view_meta, _vcf, members -> [view_meta.id, members] }, failOnDuplicate: true, failOnMismatch: true)
            .map { _cohort_id, view_meta, pgen, pvar, psam, members -> [view_meta, pgen, pvar, psam, members] }
    )

    //
    // MODULE: Probe the native state of every PGEN in the stream — supplied, declared and imported alike
    //
    // This is the bundle a PLINK 1 consumer would actually project, so probing here rather than at the source
    // makes the multiallelic refusal below total over source kinds: plink2 imports a multiallelic VCF to PGEN
    // without complaint and refuses only at `--make-bed`, with a message that names no cohort.
    //
    def ch_native_by_repr = ch_native.branch { view_meta, _primary, _variant_file, _sample_file, _members ->
        pgen: view_meta.format == 'plink2'
        bed: true
    }

    PREPARE_PGEN_STATE(ch_native_by_repr.pgen.map { view_meta, pgen, pvar, psam, _members -> [view_meta.subMap(['id']), pgen, pvar, psam] })

    def ch_native_state = ch_native_by_repr.pgen
        .map { view_meta, pgen, pvar, psam, members -> [view_meta.id, view_meta, pgen, pvar, psam, members] }
        .join(PREPARE_PGEN_STATE.out.state.map { state_meta, report -> [state_meta.id, report] }, failOnDuplicate: true, failOnMismatch: true)
        .map { cohort_id, view_meta, pgen, pvar, psam, members, report -> [view_meta, pgen, pvar, psam, members, readPgenState(cohort_id, report)] }
        .mix(ch_native_by_repr.bed.map { view_meta, bed, bim, fam, members -> [view_meta, bed, bim, fam, members, null] })

    //
    // MODULE: Derive the one shared PLINK 1 hard-call projection a PGEN cohort's consumers need
    //
    // A native PLINK 1 cohort passes straight through: it is already the representation the consumer reads,
    // and a round trip through PGEN would only lose information and add a task. A PGEN cohort is projected
    // once, whatever the number of PLINK 1 consumers, and only when it has one.
    //
    def ch_native_demanded = ch_native_state
        .map { view_meta, primary, variant_file, sample_file, _members, state -> [view_meta.id, view_meta, primary, variant_file, sample_file, state] }
        .join(ch_plink1_demand, failOnDuplicate: true)
        .map { _cohort_id, view_meta, primary, variant_file, sample_file, state, _demanded -> [view_meta, primary, variant_file, sample_file, state] }

    def ch_plink1_by_origin = ch_native_demanded.branch { view_meta, _primary, _variant_file, _sample_file, _state ->
        supplied: view_meta.format == 'plink1'
        projected: true
    }

    def ch_projection_inputs = ch_plink1_by_origin.projected.map { view_meta, pgen, pvar, psam, state ->
        assertProjectable(view_meta.id, state)
        [buildProjectionView(view_meta, getPlink1ProjectionPolicy()), pgen, psam, pvar]
    }

    PLINK2_MAKEBED(ch_projection_inputs)

    // A supplied PLINK 1 bundle is its own PLINK 1 view, so it travels under its `layer: 'view'` meta and its
    // native key; a projection travels under the derived meta the atom was invoked with. `buildViewRecord`
    // tells the two apart by `layer`, and both expose the `key` its consumers ask for.
    def ch_plink1_views = ch_plink1_by_origin.supplied
        .map { view_meta, bed, bim, fam, _state -> [view_meta.id, view_meta, bed, bim, fam] }
        .mix(PLINK2_MAKEBED.out.bed.map { projection_meta, bed, bim, fam -> [projection_meta.id, projection_meta, bed, bim, fam] })

    // Each view key is emitted from the stream that produces it rather than from the joined record below.
    // `join(remainder: true)` releases its unmatched items only once both operands have completed, so a key
    // taken from the record would hold every REGENIE Step 1 fit and every dense GCTA GRM behind an unrelated
    // cohort's whole-genome hard-call projection. `ch_plink1_views` holds an element for exactly the
    // cohorts that have a PLINK 1 view, which is exactly the set its consumers ask about, so the PLINK 1 key
    // channel is partial by design and null-free by construction.
    def ch_cohort_native_view_keys = ch_native_state.map { view_meta, _primary, _variant_file, _sample_file, _members, _state -> [view_meta.id, view_meta.native_view.key] }
    def ch_cohort_plink1_view_keys = ch_plink1_views.map { cohort_id, plink1_meta, _bed, _bim, _fam -> [cohort_id, plink1_meta.key] }

    // The joined record is provenance only. It is the one consumer of `remainder: true` and the one consumer
    // of the per-member detail, and it feeds a `collectFile` on the spine where late emission is harmless.
    def ch_cohort_views = ch_native_state
        .map { view_meta, _primary, _variant_file, _sample_file, members, state -> [view_meta.id, view_meta, members, state] }
        .join(ch_plink1_views.map { cohort_id, plink1_meta, _bed, _bim, _fam -> [cohort_id, plink1_meta] }, remainder: true)
        .map { _cohort_id, view_meta, members, state, plink1_meta -> [buildCohortMeta(view_meta), buildViewRecord(view_meta, members, state, plink1_meta)] }

    //
    // The cohort-to-request seam. `cohort_id` to request identifier is one-to-many, so this is a combining
    // operator rather than a join: `join` emits one pair per key and so silently drops every request after
    // the first on each cohort, while its `failOnDuplicate` form raises on the second. `combine(by: 0)` pairs
    // every request with its cohort's bundle, and because exactly one bundle exists per cohort key the
    // product is exactly one element per request, carrying the focal request metadata rather than the cohort
    // metadata.
    //
    def ch_native_genotypes = ch_requests
        .map { meta, _genotype_files -> [meta.cohort, meta] }
        .combine(
            ch_native_state.map { view_meta, primary, variant_file, sample_file, _members, _state -> [view_meta.id, primary, variant_file, sample_file] },
            by: 0
        )
        .map { _cohort_id, meta, primary, variant_file, sample_file -> [meta, primary, variant_file, sample_file] }

    def ch_cohort_native_genotypes = ch_native_state.map { view_meta, primary, variant_file, sample_file, _members, _state ->
        [buildCohortMeta(view_meta), primary, variant_file, sample_file]
    }

    def ch_plink1_genotypes = ch_plink1_requests
        .map { meta, _genotype_files -> [meta.cohort, meta] }
        .combine(ch_plink1_views.map { cohort_id, _plink1_meta, bed, bim, fam -> [cohort_id, bed, bim, fam] }, by: 0)
        .map { _cohort_id, meta, bed, bim, fam -> [meta, bed, bim, fam] }

    emit:
    native_genotypes        = ch_native_genotypes // channel: [ val(meta), path(primary_genotype), path(variant_file), path(sample_file) ], format-polymorphic, one per request
    cohort_native_genotypes = ch_cohort_native_genotypes // channel: [ val(cohort_meta), path(primary_genotype), path(variant_file), path(sample_file) ], one per cohort
    plink1_genotypes        = ch_plink1_genotypes // channel: [ val(meta), path(bed), path(bim), path(fam) ], only requests whose selected method reads PLINK 1
    cohort_native_view_keys = ch_cohort_native_view_keys // channel: [ val(cohort_id), val(native_view_key) ], one per cohort
    cohort_plink1_view_keys = ch_cohort_plink1_view_keys // channel: [ val(cohort_id), val(plink1_view_key) ], only cohorts with a PLINK 1 view
    cohort_views            = ch_cohort_views // channel: [ val(cohort_meta), val(view_record) ], one per cohort, provenance only
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

// A pair request carries one method; a unary request carries the two selector columns.
def getSelectedMethods(meta) {
    return meta.relationship_id
        ? [meta.method]
        : (meta.association_methods ?: []) + (meta.heritability_methods ?: [])
}

// The fixed v1 policy for the PGEN to PLINK 1 hard-call projection. It is declared once here: the derivative's
// identity, the published provenance record and `PLINK2_MAKEBED`'s rendered `ext.args` all read this map, so a
// change to the policy cannot reach the command without also moving the identity.
def getPlink1ProjectionPolicy() {
    return [
        // Bump together with modules/local/plink2/makebed/environment.yml; a function test pins the two.
        tool_contract: 'plink2_2.0.0a.6.9_make_bed_v1',
        // plink2's own default, made explicit because it changes the projected bytes whenever dosages are
        // present, which is exactly why it belongs in the derivative's identity.
        hard_call_threshold: 0.1,
        // No `--max-alleles`: a multiallelic source is refused before the task is created, and by plink2
        // natively. Filtering variants away would make the derivative a different variant set rather than a
        // different encoding of the same one.
        multiallelic: 'reject',
        missing_call_policy: 'dosage_distance_above_threshold_is_missing',
        dosage: 'dropped',
        phase: 'dropped',
        selection: [samples: 'all', variants: 'all', chromosomes: 'all', regions: 'all'],
    ]
}

// Every field here is rendered into PLINK2_VCF's `ext.args`. There is deliberately no `dosage_field`: the
// absence of a `dosage=` modifier is what such a field would have meant, and the tool contract already pins
// the version at which that default holds.
def getVcfImportPolicy() {
    return [tool_contract: 'plink2_2.0.0a.6.9_vcf_import_v1', sample_id_policy: 'double_id', half_call: 'error']
}

def buildGenotypeViewKey(format, origin, source, settings) {
    return buildScientificArtifactKey(
        [layer: 'view', type: 'genotype_view', format: format, origin: origin, source: "${source.mode}:${source.value}"],
        settings,
    )
}

def buildPlink1ProjectionKey(parent_key, policy) {
    return buildScientificArtifactKey([layer: 'derived', type: 'plink1_hard_call_projection', parent_key: parent_key], policy)
}

// `format` is the representation actually on disk; `source_format` is the manifest's own `genotype_format`,
// kept verbatim so that no consumer has to invert the VCF-import mapping to recover what was supplied.
def buildNativeView(cohort_meta, format, origin, source, settings) {
    def key = buildGenotypeViewKey(format, origin, source, settings)
    return [
        id: cohort_meta.id,
        key: key,
        layer: 'view',
        artifact_type: origin == 'vcf_import' ? 'vcf_pgen_import' : 'supplied_genotypes',
        format: format,
        source_format: cohort_meta.genotype_format,
        origin: origin,
        source: source,
        settings: settings,
        native_view: [key: key, format: format, origin: origin, settings: settings],
    ]
}

def buildProjectionView(view_meta, policy) {
    return [
        id: view_meta.id,
        key: buildPlink1ProjectionKey(view_meta.key, policy),
        layer: 'derived',
        artifact_type: 'plink1_hard_call_projection',
        parent_key: view_meta.key,
        settings: policy,
    ]
}

// The cohort-scoped metadata carries both facts: `genotype_format` keeps the manifest's meaning it has today,
// and `native_format` states the representation that is actually on disk.
def buildCohortMeta(view_meta) {
    return [id: view_meta.id, genotype_format: view_meta.source_format, native_format: view_meta.format]
}

def assertProjectable(cohort_id, state) {
    if (state == null) {
        error("[nf-core/gwas] ERROR: cohort '${cohort_id}': a PLINK 1 projection was requested but no PLINK 2 state was probed; this is a pipeline defect, PREPARE_PGEN_STATE must run for every PGEN in the native stream.")
    }
    if (state.max_alleles > 2) {
        error("[nf-core/gwas] ERROR: cohort '${cohort_id}' selects a method that reads PLINK 1 but its PLINK 2 genotypes contain multiallelic variants (maximum allele count ${state.max_alleles}); the hard-call projection accepts biallelic sources only. Split or filter the source, for example with `plink2 --max-alleles 2`, and declare the result as its own cohort, or remove the PLINK 1 consumers from its rows.")
    }
}

def readSourceIdentity(cohort_id, digest_file) {
    def value = digest_file.text.trim()
    if (!(value ==~ /^[0-9a-f]{64}$/)) {
        error("[nf-core/gwas] ERROR: cohort '${cohort_id}': PREPARE_GENOTYPE_SOURCE wrote no 64-character hexadecimal digest to ${digest_file}.")
    }
    return value
}

def readSourceMembers(cohort_id, members_file) {
    return members_file
        .readLines()
        .findAll { line -> line.trim() }
        .collect { line ->
            def fields = line.split('\t', -1)
            if (fields.size() != 4) {
                error("[nf-core/gwas] ERROR: cohort '${cohort_id}': PREPARE_GENOTYPE_SOURCE wrote a malformed member row in ${members_file}: '${line}'.")
            }
            [role: fields[0], name: fields[1], size: fields[2] as Long, sha256: fields[3]]
        }
}

// Every fact is matched into a local and then reported. plink2 states the negatives explicitly, so a missing
// statement means the log shape changed rather than that the fact is false, and the two cases must not be
// confused: exactly one statement of each family must appear, and anything else is refused by name.
//
// The dosage family has THREE mutually exclusive members on the pinned image, not two. A bundle holding
// phased dosages — the ordinary product of `plink2 --vcf … dosage=HDS` on phased imputation output — reports
// "Explicitly phased dosages present" and neither of the other two, so a two-way exclusive-or would take the
// error branch on a perfectly well-formed report and abort the run.
def readPgenState(cohort_id, report_file) {
    def text = report_file.text
    def alleles = (text =~ /Maximum allele count for a single variant: (\d+)/)
    def dosage_statements = ['No dosages present', 'Dosage present', 'Explicitly phased dosages present'].findAll { statement -> text.contains(statement) }
    def phase_statements = ['No hardcalls are explicitly phased', 'Explicitly phased hardcalls present'].findAll { statement -> text.contains(statement) }
    if (!alleles || dosage_statements.size() != 1 || phase_statements.size() != 1) {
        error("[nf-core/gwas] ERROR: cohort '${cohort_id}': plink2 --pgen-info wrote an unrecognised state report to ${report_file}; expected an allele-count line, exactly one of 'No dosages present', 'Dosage present' and 'Explicitly phased dosages present', and exactly one of 'No hardcalls are explicitly phased' and 'Explicitly phased hardcalls present'.")
    }
    return [
        max_alleles: alleles[0][1] as Integer,
        dosages: dosage_statements.first() != 'No dosages present',
        phased: phase_statements.first() == 'Explicitly phased hardcalls present',
    ]
}

// The published view record. A PLINK 1 cohort has no `state` because there is nothing to project, and a
// declared-identity cohort has no `members` because its bytes are never digested — its PLINK 2 state is
// probed all the same, since a declaration asserts an identity and says nothing about what the bundle holds.
def buildViewRecord(view_meta, members, state, plink1_meta) {
    def plink1 = null
    if (plink1_meta != null) {
        plink1 = plink1_meta.layer == 'derived'
            ? [
                key: plink1_meta.key,
                origin: 'hard_call_projection',
                parent_key: plink1_meta.parent_key,
                settings: plink1_meta.settings,
                information_loss: ['dosage', 'phase', 'multiallelic_state'],
            ]
            : [key: plink1_meta.key, origin: 'supplied', parent_key: null, settings: [:], information_loss: []]
    }
    return [
        cohort: view_meta.id,
        source: [format: view_meta.source_format, identity: view_meta.source, members: members, state: state],
        native_view: view_meta.native_view,
        plink1: plink1,
    ]
}
