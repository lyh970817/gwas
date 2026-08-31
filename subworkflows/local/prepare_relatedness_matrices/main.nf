// Build each relatedness base artifact once, derive each requested child once, and restore focal metadata.
// Every component reports on the run-wide versions topic, so this subworkflow emits no versions.

// SUBWORKFLOW: Consisting of a mix of local and nf-core/modules
include { PLINK_PREPARE_GRM_GCTA           } from '../plink_prepare_grm_gcta/main'
include { PLINK_PREPARE_GRM_LDMS_GCTA      } from '../plink_prepare_grm_ldms_gcta/main'
include { PLINK_PREPARE_GRM_LDAK           } from '../plink_prepare_grm_ldak/main'

// MODULE: Local to the pipeline
include { GCTA_MAKEBKSPARSE                } from '../../../modules/local/gcta/makebksparse/main'

// FUNCTION: Local to the pipeline
include { buildScientificArtifactKey       } from '../utils_nfcore_gwas_pipeline'
include { canonicaliseScientificIdentifier } from '../utils_nfcore_gwas_pipeline'
include { canonicaliseScientificValue      } from '../utils_nfcore_gwas_pipeline'
include { digestFileBytes                  } from '../utils_nfcore_gwas_pipeline'
include { getMethodCapabilities            } from '../validate_gwas_input/method_registry'

workflow PREPARE_RELATEDNESS_MATRICES {
    take:
    ch_analyses // channel: [ val(meta), [ path(genotype_file), ... ], path(ldak_weights) ], [] when absent
    ch_cohort_genotypes // channel: [ val(cohort_meta), path(pgen), path(psam), path(pvar) ]
    ch_plink1_genotypes // channel: [ val(meta), path(bed), path(bim), path(fam) ], analyses needing PLINK 1
    gcta_grm_parts // channel: val(gcta_grm_parts), run/profile GCTA GRM partition count

    main:

    // Final consumer requests preserve focal metadata beside an explicit base/derived artifact graph. The
    // temporary view-compatibility key is the single replacement seam for issue #8; no base or derivative
    // identity independently reads staged genotype names.
    def ch_requests = ch_analyses.flatMap { meta, genotype_files, ldak_weights ->
        getRelatednessMatrixKinds(meta).collect { kind ->
            def weights_policy = kind == 'ldak_kinship' ? meta.method_options.ldak.weights_policy : 'equal'
            def weights_identity = kind == 'ldak_kinship' ? getLdakWeightsIdentity(ldak_weights, weights_policy) : [mode: 'equal']
            def gcta_extract = kind in ['gcta_dense', 'gcta_sparse'] && !meta.relationship_id ? meta.method_options.gcta.grm_extract : []
            def extract_identity = kind in ['gcta_dense', 'gcta_sparse'] ? getMethodResourceIdentity(gcta_extract) : [mode: 'all']
            def request = buildRelatednessArtifactRequest(meta, genotype_files, kind, weights_identity, extract_identity, gcta_extract)
            def weights_file = kind == 'ldak_kinship' ? ldak_weights ?: [] : []
            [request.selected_key, meta, request, weights_file]
        }
    }

    // Base construction is reduced independently of final requested form. Sparse cutoffs and LDAK filtering
    // cannot fragment these records because they occur only on child requests.
    def ch_base_requests = ch_requests
        .map { _selected_key, _meta, request, weights_file -> [request.base.key, request.base, weights_file] }
        .unique { key, _base, _weights_file -> key }
        .map { key, base, weights_file ->
            def matrix_meta = buildRelatednessArtifactMeta(base)
            [key, matrix_meta, base, weights_file, gcta_grm_parts]
        }

    // One PLINK 1 bundle exists per cohort even when several consumers requested it.
    def ch_plink1_cohorts = ch_plink1_genotypes
        .map { meta, bed, bim, fam -> [meta.cohort, bed, bim, fam] }
        .unique { cohort, _bed, _bim, _fam -> cohort }

    // Pair GCTA base requests with their prepared PGEN bundle. The compatibility key currently retains the
    // pre-#8 cohort partition, so every base has one cohort routing record while the identity seam remains
    // explicit and replaceable.
    def ch_gcta_base_genotypes = ch_base_requests
        .filter { _key, _matrix_meta, base, _weights_file, _parts -> base.type in ['gcta_dense', 'gcta_ldms'] }
        .map { _key, matrix_meta, base, _weights_file, parts -> [base.cohort, matrix_meta, base, parts] }
        .combine(
            ch_cohort_genotypes.map { cohort_meta, pgen, psam, pvar -> [cohort_meta.id, pgen, psam, pvar] },
            by: 0
        )
        .map { _cohort_id, matrix_meta, base, parts, pgen, psam, pvar -> [matrix_meta, base, parts, pgen, psam, pvar] }

    def ch_gcta_base_types = ch_gcta_base_genotypes.branch { _matrix_meta, base, _parts, _pgen, _psam, _pvar ->
        gcta_dense: base.type == 'gcta_dense'
        gcta_ldms: base.type == 'gcta_ldms'
    }

    // GCTA resolves one manifest entry from the staged PGEN prefix. Matching companion basenames remain a
    // native caller contract; the staged basename is not part of the scientific base key.
    def ch_dense_manifests = ch_gcta_base_types.gcta_dense
        .map { matrix_meta, _base, _parts, pgen, _psam, _pvar -> [matrix_meta, pgen.baseName] }
        .collectFile { matrix_meta, stem -> ["${matrix_meta.id}.mpfile", "${stem}\n"] }
        .map { manifest -> [manifest.baseName, manifest] }

    def ch_dense_inputs = ch_gcta_base_types.gcta_dense
        .map { matrix_meta, base, parts, pgen, psam, pvar -> [matrix_meta.id, matrix_meta, base, parts, pgen, psam, pvar] }
        .join(ch_dense_manifests, failOnDuplicate: true, failOnMismatch: true)
        .multiMap { _matrix_id, matrix_meta, base, parts, pgen, psam, pvar, manifest ->
            genotypes: [matrix_meta, manifest, pgen, pvar, psam]
            snp_group: [matrix_meta, base.gcta_extract ?: []]
            n_parts: [matrix_meta, parts]
        }

    PLINK_PREPARE_GRM_GCTA(
        ch_dense_inputs.genotypes,
        ch_dense_inputs.snp_group,
        ch_dense_inputs.n_parts,
    )

    // Each sparse child is keyed by its dense parent plus cutoff. Several cutoffs combine with the same
    // completed parent without creating another dense construction.
    def ch_sparse_derivatives = ch_requests
        .filter { _selected_key, _meta, request, _weights_file -> request.derived && request.derived.type == 'gcta_sparse' }
        .map { _selected_key, _meta, request, _weights_file -> [request.derived.key, request.derived] }
        .unique { key, _derived -> key }

    def ch_sparse_inputs = ch_sparse_derivatives
        .map { _key, derived -> [derived.parent_key, derived] }
        .combine(
            PLINK_PREPARE_GRM_GCTA.out.grm_files.map { matrix_meta, grm_files -> [matrix_meta.key, grm_files] },
            by: 0
        )
        .multiMap { _parent_key, derived, grm_files ->
            def matrix_meta = buildRelatednessArtifactMeta(derived)
            grm: [matrix_meta, grm_files]
            cutoff: derived.settings.cutoff
        }

    GCTA_MAKEBKSPARSE(
        ch_sparse_inputs.grm,
        ch_sparse_inputs.cutoff,
    )

    // LDMS remains one base-family artifact. Its ordered gather/manifest implementation is unchanged here and
    // remains the explicit scope of issue #31.
    def ch_ldms_builds = ch_gcta_base_types.gcta_ldms
        .map { matrix_meta, base, parts, _pgen, _psam, _pvar -> [base.cohort, matrix_meta, parts] }
        .combine(ch_plink1_cohorts, by: 0)
        .map { _cohort, matrix_meta, parts, bed, bim, fam -> [matrix_meta, parts, bed, bim, fam] }

    def ch_ldms_manifests = ch_ldms_builds
        .map { matrix_meta, _parts, bed, _bim, _fam -> [matrix_meta, bed.baseName] }
        .collectFile { matrix_meta, stem -> ["${matrix_meta.id}.mbfile", "${stem}\n"] }
        .map { manifest -> [manifest.baseName, manifest] }

    def ch_ldms_inputs = ch_ldms_builds
        .map { matrix_meta, parts, bed, bim, fam -> [matrix_meta.id, matrix_meta, parts, bed, bim, fam] }
        .join(ch_ldms_manifests, failOnDuplicate: true, failOnMismatch: true)
        .multiMap { _matrix_id, matrix_meta, parts, bed, bim, fam, manifest ->
            genotypes: [matrix_meta, manifest, bed, bim, fam]
            ld_score_region_kb: [matrix_meta, matrix_meta.settings.ld_score_region_kb]
            ld_bins: [matrix_meta, matrix_meta.settings.ld_bins]
            maf_edges: [matrix_meta, matrix_meta.settings.maf_edges]
            n_parts: [matrix_meta, parts]
        }

    PLINK_PREPARE_GRM_LDMS_GCTA(
        ch_ldms_inputs.genotypes,
        ch_ldms_inputs.ld_score_region_kb,
        ch_ldms_inputs.ld_bins,
        ch_ldms_inputs.maf_edges,
        ch_ldms_inputs.n_parts,
    )

    // CALCKINS sees only LDAK base requests. Optional filtering/subsetting is supplied as a child request whose
    // parent key selects the completed base, so unrestricted and filtered consumers share construction.
    def ch_ldak_inputs = ch_base_requests
        .filter { _key, _matrix_meta, base, _weights_file, _parts -> base.type == 'ldak_kinship' }
        .map { key, matrix_meta, base, weights_file, _parts -> [base.cohort, key, matrix_meta, base, weights_file] }
        .combine(ch_plink1_cohorts, by: 0)
        .map { _cohort, key, matrix_meta, base, weights_file, bed, bim, fam -> [key, matrix_meta, base, weights_file, bed, bim, fam] }
        .multiMap { _key, matrix_meta, base, weights_file, bed, bim, fam ->
            genotypes: [matrix_meta, bed, bim, fam, base.settings.power]
            weights: [matrix_meta, weights_file]
        }

    def ch_ldak_subset_requests = ch_requests
        .filter { _selected_key, _meta, request, _weights_file -> request.derived && request.derived.type == 'ldak_subset' }
        .map { _selected_key, _meta, request, _weights_file -> [request.derived.parent_key, buildRelatednessArtifactMeta(request.derived)] }
        .unique { _parent_key, derived_meta -> derived_meta.key }

    PLINK_PREPARE_GRM_LDAK(
        ch_ldak_inputs.genotypes,
        ch_ldak_inputs.weights,
        ch_ldak_subset_requests,
    )

    // Fan every selected final artifact back to its unchanged focal analysis/request metadata.
    def ch_gcta_dense = ch_requests
        .filter { _selected_key, _meta, request, _weights_file -> request.kind == 'gcta_dense' }
        .map { selected_key, meta, _request, _weights_file -> [selected_key, meta.relationship_id ? meta + [matrix_key: selected_key] : meta] }
        .combine(
            PLINK_PREPARE_GRM_GCTA.out.grm_files.map { matrix_meta, grm_files -> [matrix_meta.key, grm_files] },
            by: 0
        )
        .map { _selected_key, meta, grm_files -> [meta, grm_files] }

    def ch_gcta_sparse = ch_requests
        .filter { _selected_key, _meta, request, _weights_file -> request.kind == 'gcta_sparse' }
        .map { selected_key, meta, _request, _weights_file -> [selected_key, meta] }
        .combine(
            GCTA_MAKEBKSPARSE.out.sparse_grm_files.map { matrix_meta, sparse_grm_files -> [matrix_meta.key, sparse_grm_files] },
            by: 0
        )
        .map { _selected_key, meta, sparse_grm_files -> [meta, sparse_grm_files] }

    def ch_gcta_ldms = ch_requests
        .filter { _selected_key, _meta, request, _weights_file -> request.kind == 'gcta_ldms' }
        .map { selected_key, meta, _request, _weights_file -> [selected_key, meta.relationship_id ? meta + [matrix_key: selected_key] : meta] }
        .combine(
            PLINK_PREPARE_GRM_LDMS_GCTA.out.mgrm_bundle.map { matrix_meta, mgrm, grm_files -> [matrix_meta.key, mgrm, grm_files] },
            by: 0
        )
        .map { _selected_key, meta, mgrm, grm_files -> [meta, mgrm, grm_files] }

    def ch_ldak_unfiltered = ch_requests
        .filter { _selected_key, _meta, request, _weights_file -> request.kind == 'ldak_kinship' && !request.derived }
        .map { selected_key, meta, _request, _weights_file -> [selected_key, meta] }
        .combine(
            PLINK_PREPARE_GRM_LDAK.out.base_grm.map { matrix_meta, grm_files -> [matrix_meta.key, grm_files] },
            by: 0
        )
        .map { selected_key, meta, grm_files -> [meta, selected_key, grm_files, []] }

    def ch_ldak_filtered = ch_requests
        .filter { _selected_key, _meta, request, _weights_file -> request.kind == 'ldak_kinship' && request.derived }
        .map { selected_key, meta, _request, _weights_file -> [selected_key, meta] }
        .combine(
            PLINK_PREPARE_GRM_LDAK.out.subset_grm.map { matrix_meta, grm_files -> [matrix_meta.key, grm_files] },
            by: 0
        )
        .combine(
            PLINK_PREPARE_GRM_LDAK.out.filtered_list.map { matrix_meta, keep, _lose -> [matrix_meta.key, keep] },
            by: 0
        )
        .map { selected_key, meta, grm_files, keep -> [meta, selected_key, grm_files, keep] }

    def ch_ldak_kinship = ch_ldak_unfiltered.mix(ch_ldak_filtered)

    emit:
    gcta_dense   = ch_gcta_dense // channel: [ val(meta), path(grm_files) ]
    gcta_sparse  = ch_gcta_sparse // channel: [ val(meta), path(sparse_grm_files) ]
    gcta_ldms    = ch_gcta_ldms // channel: [ val(meta), path(mgrm), path(grm_files) ]
    ldak_kinship = ch_ldak_kinship // channel: [ val(meta), val(artifact_key), path(grm_files), path(keep) ]
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

def canonicaliseDeclaredValue(value) {
    return canonicaliseScientificValue(value)
}

def canonicaliseIdentifier(value) {
    return canonicaliseScientificIdentifier(value)
}

def buildRelatednessMatrixKey(identity, settings) {
    return buildScientificArtifactKey(identity, settings)
}

def buildPreparedViewCompatibilityKey(meta, genotype_files) {
    def compatibility_identity = [
        contract: 'pending_issue_8',
        cohort: meta.cohort,
        genotype_format: meta.genotype_format,
        genotypes: genotype_files.collect { genotype_file -> genotype_file.name }.sort(),
    ]
    return buildScientificArtifactKey(
        [layer: 'compatibility', type: 'prepared_genotype_view'],
        compatibility_identity,
    )
}

def buildRelatednessArtifactMeta(artifact) {
    def meta = [
        id: "${artifact.type}.${artifact.key}",
        key: artifact.key,
        layer: artifact.layer,
        artifact_type: artifact.type,
        settings: artifact.settings,
    ]
    return artifact.layer == 'base'
        ? meta + [view_compatibility_key: artifact.view_compatibility_key]
        : meta + [parent_key: artifact.parent_key]
}

def getRelatednessMatrixKinds(meta) {
    def capabilities = getMethodCapabilities()
    def selected = meta.relationship_id
        ? [meta.method] as Set
        : ((meta.association_methods ?: []) + (meta.heritability_methods ?: [])) as Set
    return ['gcta_dense', 'gcta_ldms', 'gcta_sparse', 'ldak_kinship'].findAll { kind ->
        selected.any { method -> capabilities[method] && capabilities[method].matrix_kind == kind }
    }
}

def getLdakWeightsIdentity(weights_file, weights_policy = 'equal') {
    if (!weights_file) {
        return [mode: weights_policy]
    }
    return [mode: 'provided', sha256: digestFileBytes(weights_file)]
}

def getMethodResourceIdentity(resource) {
    if (!resource) {
        return [mode: 'all']
    }
    return [mode: 'file', sha256: digestFileBytes(resource)]
}

def getRelatednessBaseSettings(meta, requested_kind, weights_identity = [mode: 'equal'], gcta_extract_identity = [mode: 'all']) {
    if (requested_kind in ['gcta_dense', 'gcta_sparse']) {
        if (meta.relationship_id) {
            return meta.matrix_settings
        }
        def settings = [:]
        if (meta.method_options.gcta.grm_maf != null) {
            settings.maf = meta.method_options.gcta.grm_maf
        }
        if (gcta_extract_identity.mode == 'file') {
            settings.extract = gcta_extract_identity
        }
        return settings
    }
    if (requested_kind == 'gcta_ldms') {
        return meta.relationship_id
            ? meta.matrix_settings
            : [
                ld_score_region_kb: meta.method_options.gcta.ld_score_region_kb,
                ld_bins: meta.method_options.gcta.ld_bins,
                maf_edges: meta.method_options.gcta.ldms_maf_edges,
            ]
    }
    if (requested_kind == 'ldak_kinship') {
        return [
            model: meta.method_options.ldak.model,
            power: meta.method_options.ldak.power,
            weights: weights_identity,
        ]
    }
}

def getRelatednessDerivedSettings(meta, requested_kind) {
    if (requested_kind == 'gcta_sparse') {
        return [cutoff: meta.method_options.gcta.sparse_cutoff]
    }
    if (requested_kind == 'ldak_kinship' && meta.method_options.ldak.relatedness_filter) {
        return [relatedness_filter: true]
    }
    return [:]
}

def buildRelatednessArtifactRequest(meta, genotype_files, kind, weights_identity = [mode: 'equal'], gcta_extract_identity = [mode: 'all'], gcta_extract = []) {
    def view_compatibility_key = buildPreparedViewCompatibilityKey(meta, genotype_files)
    def base_type = kind == 'gcta_sparse' ? 'gcta_dense' : kind
    def base_settings = getRelatednessBaseSettings(meta, kind, weights_identity, gcta_extract_identity)
    def base_key = buildScientificArtifactKey(
        [layer: 'base', type: base_type, view_compatibility_key: view_compatibility_key],
        base_settings,
    )
    def base = [
        layer: 'base',
        type: base_type,
        key: base_key,
        view_compatibility_key: view_compatibility_key,
        settings: base_settings,
        cohort: meta.cohort,
    ]
    if (base_type == 'gcta_dense') {
        base.gcta_extract = gcta_extract
    }

    def derived = [:]
    if (kind == 'gcta_sparse') {
        def settings = getRelatednessDerivedSettings(meta, kind)
        derived = [
            layer: 'derived',
            type: 'gcta_sparse',
            parent_key: base.key,
            settings: settings,
            key: buildScientificArtifactKey([layer: 'derived', type: 'gcta_sparse', parent_key: base.key], settings),
        ]
    }
    if (kind == 'ldak_kinship' && meta.method_options.ldak.relatedness_filter) {
        def settings = getRelatednessDerivedSettings(meta, kind)
        derived = [
            layer: 'derived',
            type: 'ldak_subset',
            parent_key: base.key,
            settings: settings,
            key: buildScientificArtifactKey([layer: 'derived', type: 'ldak_subset', parent_key: base.key], settings),
        ]
    }

    return [
        kind: kind,
        base: base,
        derived: derived,
        selected_key: derived ? derived.key : base.key,
    ]
}
