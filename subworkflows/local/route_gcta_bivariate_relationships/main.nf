// Route nf-core/gwas individual-level relationship requests through GCTA bivariate REML. A relationship is a
// declared, oriented pair of analysis units over one cohort; it is a different domain from a summary-statistics
// pair request and the two are never merged here. Dense REML and REML-LDMS share one controller because they
// share the relationship definition, the endpoint resolution against the normalised phenotypes and the one
// ordered two-trait table built from them: a relationship selecting both methods is prepared exactly once.
//
// This is pipeline routing, reuse identity and scientific/publication policy, not an nf-core/modules submission
// candidate. Declared left/right orientation is the execution and presentation order and is taken as given: a
// reversed duplicate is refused upstream by validation, and nothing here re-derives, reorders or de-duplicates
// an orientation. Every constituent process reports directly to the run-wide versions topic, so this
// subworkflow emits no versions, and it reads no params, no workflow and no projectDir.

// MODULES: Installed directly from nf-core/modules
include { GCTA_BIVARIATEREML       } from '../../../modules/nf-core/gcta/bivariatereml/main'
include { GCTA_BIVARIATEREMLLDMS   } from '../../../modules/nf-core/gcta/bivariateremlldms/main'

// MODULE: Local to the pipeline
include { NORMALISE_GCTA_BIVARIATE } from '../../../modules/local/normalise_gcta_bivariate/main'
include { PREPARE_BIVARIATE_TRAITS } from '../../../modules/local/prepare_bivariate_traits/main'

workflow ROUTE_GCTA_BIVARIATE_RELATIONSHIPS {
    take:
    ch_relationships // channel: [ val(meta), [ path(genotype_file), ... ], path(pair_quant_covariates), path(pair_cat_covariates) ], one validated row per selected method per relationship
    ch_normalised_phenotypes // channel: [ val(meta), path(phenotype) ], the headerless canonical phenotype of every analysis unit, keyed one-to-one on the analysis meta
    ch_relationship_dense_matrices // channel: [ val(meta), [ path(grm_file), ... ] ], the dense GCTA matrices built for relationship requests, already fanned out per request
    ch_relationship_ldms_matrices // channel: [ val(meta), path(mgrm), [ path(grm_file), ... ] ], the LD- and MAF-stratified GCTA matrix families built for relationship requests

    main:

    // Relationships own their orientation and covariates. Collapse the per-method request fan-out to one
    // relationship definition, resolve each endpoint against the canonical unary phenotype stream, and
    // construct one ordered full-union two-trait table. `combine` is deliberate at the endpoint seams: one
    // analysis may be reused by several relationships. The prepared artifact is fanned back out by
    // relationship ID only after construction, so selecting dense and LDMS does not duplicate it.
    def ch_relationship_definitions = ch_relationships
        .map { meta, genotype_files, pair_quant_covariates, pair_cat_covariates ->
            def relationship_meta = meta + [
                id: meta.relationship_id,
                request_id: meta.relationship_id,
            ]
            [meta.relationship_id, relationship_meta, genotype_files, pair_quant_covariates, pair_cat_covariates]
        }
        .unique { relationship_id, _meta, _genotype_files, _pair_quant_covariates, _pair_cat_covariates -> relationship_id }

    def ch_left_pair_phenotypes = ch_relationship_definitions
        .map { relationship_id, meta, _genotype_files, pair_quant_covariates, pair_cat_covariates ->
            [meta.left_analysis_id, relationship_id, meta, pair_quant_covariates ?: [], pair_cat_covariates ?: []]
        }
        .combine(
            ch_normalised_phenotypes.map { meta, phenotype -> [meta.id, phenotype] },
            by: 0
        )
        .map { _analysis_id, relationship_id, meta, pair_quant_covariates, pair_cat_covariates, phenotype ->
            [relationship_id, meta, phenotype, pair_quant_covariates, pair_cat_covariates]
        }

    def ch_right_pair_phenotypes = ch_relationship_definitions
        .map { relationship_id, meta, _genotype_files, _pair_quant_covariates, _pair_cat_covariates -> [meta.right_analysis_id, relationship_id] }
        .combine(
            ch_normalised_phenotypes.map { meta, phenotype -> [meta.id, phenotype] },
            by: 0
        )
        .map { _analysis_id, relationship_id, phenotype -> [relationship_id, phenotype] }

    def ch_pair_trait_inputs = ch_left_pair_phenotypes
        .join(ch_right_pair_phenotypes, failOnDuplicate: true, failOnMismatch: true)
        .map { _relationship_id, meta, left_phenotype, pair_quant_covariates, pair_cat_covariates, right_phenotype ->
            [meta, left_phenotype, right_phenotype, pair_quant_covariates, pair_cat_covariates]
        }

    PREPARE_BIVARIATE_TRAITS(ch_pair_trait_inputs)

    def ch_prepared_relationships = PREPARE_BIVARIATE_TRAITS.out.phenotype
        .join(PREPARE_BIVARIATE_TRAITS.out.quant_covariates, remainder: true)
        .join(PREPARE_BIVARIATE_TRAITS.out.cat_covariates, remainder: true)
        .join(PREPARE_BIVARIATE_TRAITS.out.log, failOnDuplicate: true, failOnMismatch: true)
        .map { meta, phenotype, quant_covariates, cat_covariates, pair_log ->
            [meta.relationship_id, phenotype, quant_covariates ?: [], cat_covariates ?: [], pair_log]
        }

    def ch_prepared_pairs = ch_relationships
        .map { meta, _genotype_files, _pair_quant_covariates, _pair_cat_covariates -> [meta.relationship_id, meta] }
        .combine(ch_prepared_relationships, by: 0)
        .map { _relationship_id, meta, phenotype, quant_covariates, cat_covariates, pair_log ->
            [meta.request_id, meta, phenotype, quant_covariates, cat_covariates, pair_log]
        }

    //
    // MODULE: primary dense GCTA bivariate REML relationship request
    //
    // The installed atomic component correctly requires the primary metadata ID to be the staged GRM
    // basename. Keep that native basename separate from request attribution and from the content-derived
    // matrix reuse key; all three identities reach the normalized provenance adapter.
    def ch_bivariate_matrices = ch_relationship_dense_matrices
        .filter { meta, _grm_files -> meta.method == 'gcta_bivariate_reml' }
        .map { meta, grm_files ->
            def grm_id = grm_files.find { grm_file -> grm_file.name.endsWith('.grm.id') }
            if (!grm_id) {
                error("[nf-core/gwas] ERROR: pair request '${meta.request_id}' received a dense GCTA matrix without a .grm.id member")
            }
            def basename = grm_id.name.substring(0, grm_id.name.length() - '.grm.id'.length())
            [meta.request_id, meta + [matrix_basename: basename], grm_files]
        }

    def ch_dense_prepared_pairs = ch_prepared_pairs.filter { _request_id, pair_meta, _phenotype, _quant_covariates, _cat_covariates, _pair_log -> pair_meta.method == 'gcta_bivariate_reml' }

    def ch_bivariate_invocations = ch_bivariate_matrices
        .join(ch_dense_prepared_pairs, failOnDuplicate: true, failOnMismatch: true)
        .multiMap { _request_id, matrix_meta, grm_files, pair_meta, phenotype, quant_covariates, cat_covariates, pair_log ->
            if (matrix_meta.relationship_id != pair_meta.relationship_id) {
                error("[nf-core/gwas] ERROR: pair request '${pair_meta.request_id}' matrix attribution disagrees with the prepared phenotype")
            }
            def route_meta = pair_meta + [
                id: matrix_meta.matrix_basename,
                matrix_key: matrix_meta.matrix_key,
                matrix_basename: matrix_meta.matrix_basename,
            ]
            grm: [route_meta, grm_files]
            pheno: [route_meta, phenotype, 1, 2]
            qcovar: [route_meta, quant_covariates]
            covar: [route_meta, cat_covariates]
            pair_log: [pair_meta.request_id, pair_log]
        }

    GCTA_BIVARIATEREML(
        ch_bivariate_invocations.grm,
        ch_bivariate_invocations.pheno,
        ch_bivariate_invocations.qcovar,
        ch_bivariate_invocations.covar,
    )

    def ch_dense_bivariate_native_results = GCTA_BIVARIATEREML.out.bivariate_results
        .map { meta, hsq -> [meta.request_id, meta, hsq] }
        .join(
            GCTA_BIVARIATEREML.out.log_file.map { meta, gcta_log -> [meta.request_id, gcta_log] },
            failOnDuplicate: true,
            failOnMismatch: true,
        )
        .join(ch_bivariate_invocations.pair_log, failOnDuplicate: true, failOnMismatch: true)
        .map { _request_id, meta, hsq, gcta_log, pair_log -> [meta, hsq, gcta_log, pair_log] }

    //
    // MODULE: primary GCTA bivariate REML-LDMS relationship request
    //
    // The MGRM manifest basename is the installed atom's native identity. The request ID and the
    // matrix content key remain separate attribution fields so a unary GREML-LDMS request and a pair
    // request can share one scientifically identical matrix family without sharing result identity.
    def ch_bivariate_ldms_matrices = ch_relationship_ldms_matrices
        .filter { meta, _mgrm, _grm_files -> 'gcta_bivariate_reml_ldms' == meta.method }
        .map { meta, mgrm, grm_files ->
            [meta.request_id, meta + [matrix_basename: mgrm.baseName], mgrm, grm_files]
        }

    def ch_ldms_prepared_pairs = ch_prepared_pairs.filter { _request_id, pair_meta, _phenotype, _quant_covariates, _cat_covariates, _pair_log -> pair_meta.method == 'gcta_bivariate_reml_ldms' }

    def ch_bivariate_ldms_invocations = ch_bivariate_ldms_matrices
        .join(ch_ldms_prepared_pairs, failOnDuplicate: true, failOnMismatch: true)
        .multiMap { _request_id, matrix_meta, mgrm, grm_files, pair_meta, phenotype, quant_covariates, cat_covariates, pair_log ->
            if (matrix_meta.relationship_id != pair_meta.relationship_id) {
                error("[nf-core/gwas] ERROR: pair request '${pair_meta.request_id}' LDMS matrix attribution disagrees with the prepared phenotype")
            }
            def route_meta = pair_meta + [
                id: matrix_meta.matrix_basename,
                matrix_key: matrix_meta.matrix_key,
                matrix_basename: matrix_meta.matrix_basename,
            ]
            mgrm: [route_meta, mgrm, grm_files]
            pheno: [route_meta, phenotype, 1, 2]
            qcovar: [route_meta, quant_covariates]
            covar: [route_meta, cat_covariates]
            pair_log: [pair_meta.request_id, pair_log]
        }

    GCTA_BIVARIATEREMLLDMS(
        ch_bivariate_ldms_invocations.mgrm,
        ch_bivariate_ldms_invocations.pheno,
        ch_bivariate_ldms_invocations.qcovar,
        ch_bivariate_ldms_invocations.covar,
    )

    def ch_ldms_bivariate_native_results = GCTA_BIVARIATEREMLLDMS.out.bivariate_results
        .map { meta, hsq -> [meta.request_id, meta, hsq] }
        .join(
            GCTA_BIVARIATEREMLLDMS.out.log_file.map { meta, gcta_log -> [meta.request_id, gcta_log] },
            failOnDuplicate: true,
            failOnMismatch: true,
        )
        .join(ch_bivariate_ldms_invocations.pair_log, failOnDuplicate: true, failOnMismatch: true)
        .map { _request_id, meta, hsq, gcta_log, pair_log -> [meta, hsq, gcta_log, pair_log] }

    def ch_bivariate_native_results = ch_dense_bivariate_native_results.mix(ch_ldms_bivariate_native_results)

    NORMALISE_GCTA_BIVARIATE(ch_bivariate_native_results)

    // The normalizer records the native basename and the matrix reuse key inside the request's published
    // provenance, and neither is part of the result contract, so both are dropped from every emitted record
    // together with the native rewrite of `id`. The `request_id` scatter keys used by the joins above never
    // leave a tuple position either.
    def ch_heritability = NORMALISE_GCTA_BIVARIATE.out.heritability.map { meta, heritability -> [stripNativeMatrixIdentity(meta), heritability] }
    def ch_genetic_correlation = NORMALISE_GCTA_BIVARIATE.out.genetic_correlation.map { meta, genetic_correlation -> [stripNativeMatrixIdentity(meta), genetic_correlation] }
    def ch_genetic_covariance = NORMALISE_GCTA_BIVARIATE.out.genetic_covariance.map { meta, genetic_covariance -> [stripNativeMatrixIdentity(meta), genetic_covariance] }
    def ch_diagnostics = NORMALISE_GCTA_BIVARIATE.out.diagnostics.map { meta, diagnostics -> [stripNativeMatrixIdentity(meta), diagnostics] }
    def ch_provenance = NORMALISE_GCTA_BIVARIATE.out.provenance.map { meta, provenance -> [stripNativeMatrixIdentity(meta), provenance] }

    emit:
    heritability        = ch_heritability // channel: [ val(meta), path(heritability.tsv) ], both endpoints of one relationship request, in declared left/right order
    genetic_correlation = ch_genetic_correlation // channel: [ val(meta), path(genetic_correlation.tsv) ], one per relationship request
    genetic_covariance  = ch_genetic_covariance // channel: [ val(meta), path(genetic_covariance.tsv) ], one per relationship request
    diagnostics         = ch_diagnostics // channel: [ val(meta), path(diagnostics.tsv) ]
    provenance          = ch_provenance // channel: [ val(meta), path(provenance.json) ]
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

// Drop the controller's native and reuse identities from a result record and restore the focal scientific
// identity. `matrix_basename` exists only because the installed atom addresses its GRM or MGRM family by
// staged basename, `matrix_key` is the content-derived matrix reuse key, and `id` was rewritten to that
// basename for the same reason. Downstream the record is the request, so `id` returns to `request_id`; the
// request, method, relationship and endpoint attribution, trait identity and prevalence declarations are
// retained untouched.
def stripNativeMatrixIdentity(meta) {
    return meta.findAll { key, _value -> !(key in ['matrix_basename', 'matrix_key']) } + [id: meta.request_id]
}
