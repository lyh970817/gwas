// Route nf-core/gwas individual-level relationship requests through the GCTA bivariate estimators. A
// relationship is a declared, oriented pair of analysis units over one cohort; it is a different domain from a
// summary-statistics pair request and the two are never merged here. Dense REML, REML-LDMS, dense HEreg and
// HEreg-LDMS share one controller because they share the relationship definition, the endpoint resolution
// against the prepared phenotypes and the one ordered two-trait table built from them: a relationship
// selecting several of them is prepared exactly once, and the dense or LDMS matrix a REML request already
// caused to be built is the same matrix its HEreg sibling consumes, because the matrix reuse key is derived
// only from the cohort, the genotype bundle and the declared matrix settings.
//
// This is pipeline routing, reuse identity and scientific/publication policy, not an nf-core/modules submission
// candidate. Declared left/right orientation is the execution and presentation order and is taken as given: a
// reversed duplicate is refused upstream by validation, and nothing here re-derives, reorders or de-duplicates
// an orientation. That contract is load-bearing for HEreg in particular, whose cross-product coefficient is
// fitted on the lower triangle only and therefore changes when the two traits swap sides. Every constituent
// process reports directly to the run-wide versions topic, so this subworkflow emits no versions, and it reads
// no params, no workflow and no projectDir.

// MODULES: Installed directly from nf-core/modules
include { GCTA_BIVARIATEREML       } from '../../../modules/nf-core/gcta/bivariatereml/main'
include { GCTA_BIVARIATEREMLLDMS   } from '../../../modules/nf-core/gcta/bivariateremlldms/main'

// MODULE: Local to the pipeline
include { GCTA_BIVARIATEHEREG      } from '../../../modules/local/gcta/bivariatehereg/main'
include { GCTA_BIVARIATEHEREGLDMS  } from '../../../modules/local/gcta/bivariateheregldms/main'
include { PREPARE_BIVARIATE_TRAITS } from '../../../modules/local/prepare_bivariate_traits/main'

workflow ROUTE_GCTA_BIVARIATE_RELATIONSHIPS {
    take:
    ch_relationships // channel: [ val(meta), [ path(genotype_file), ... ], path(pair_quant_covariates), path(pair_cat_covariates) ], one validated row per selected method per relationship
    ch_prepared_phenotypes // channel: [ val(meta), path(phenotype) ], the headerless phenotype of every analysis unit, keyed one-to-one on the analysis meta
    ch_relationship_dense_matrices // channel: [ val(meta), [ path(grm_file), ... ] ], the dense GCTA matrices built for relationship requests, already fanned out per request
    ch_relationship_ldms_matrices // channel: [ val(meta), [ path(grm_file), ... ], val(grm_prefixes) ], ordered LDMS matrix families built for relationship requests

    main:

    // Relationships own their orientation and covariates. Collapse the per-method request fan-out to one
    // relationship definition, resolve each endpoint against the canonical unary phenotype stream, and
    // construct one ordered full-union two-trait table. `combine` is deliberate at the endpoint seams: one
    // analysis may be reused by several relationships. The prepared artifact is fanned back out by
    // relationship ID only after construction, so selecting several estimators does not duplicate it.
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
            ch_prepared_phenotypes.map { meta, phenotype -> [meta.id, phenotype] },
            by: 0
        )
        .map { _analysis_id, relationship_id, meta, pair_quant_covariates, pair_cat_covariates, phenotype ->
            [relationship_id, meta, phenotype, pair_quant_covariates, pair_cat_covariates]
        }

    def ch_right_pair_phenotypes = ch_relationship_definitions
        .map { relationship_id, meta, _genotype_files, _pair_quant_covariates, _pair_cat_covariates -> [meta.right_analysis_id, relationship_id] }
        .combine(
            ch_prepared_phenotypes.map { meta, phenotype -> [meta.id, phenotype] },
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
        .map { meta, phenotype, quant_covariates, cat_covariates ->
            [meta.relationship_id, phenotype, quant_covariates ?: [], cat_covariates ?: []]
        }

    def ch_prepared_pairs = ch_relationships
        .map { meta, _genotype_files, _pair_quant_covariates, _pair_cat_covariates -> [meta.relationship_id, meta] }
        .combine(ch_prepared_relationships, by: 0)
        .map { _relationship_id, meta, phenotype, quant_covariates, cat_covariates ->
            [meta.request_id, meta, phenotype, quant_covariates, cat_covariates]
        }

    //
    // Dense GCTA relationship requests: bivariate REML and bivariate HEreg
    //
    // The installed REML atom requires the primary metadata ID to be the staged GRM basename. Keep that
    // native basename separate from request attribution and from the content-derived matrix reuse key; all
    // three identities reach the native results. Both dense estimators are addressed from the
    // same prepared pair and the same matrix stream, so the branch below is the only place they diverge.
    def ch_bivariate_matrices = ch_relationship_dense_matrices
        .filter { meta, _grm_files -> meta.matrix_kind == 'gcta_dense' }
        .map { meta, grm_files ->
            def grm_id = grm_files.find { grm_file -> grm_file.name.endsWith('.grm.id') }
            def basename = grm_id.name.substring(0, grm_id.name.length() - '.grm.id'.length())
            [meta.request_id, meta + [matrix_basename: basename], grm_files]
        }

    def ch_dense_prepared_pairs = ch_prepared_pairs.filter { _request_id, pair_meta, _phenotype, _quant_covariates, _cat_covariates -> pair_meta.matrix_kind == 'gcta_dense' }

    def ch_dense_requests = ch_bivariate_matrices
        .join(ch_dense_prepared_pairs, failOnDuplicate: true, failOnMismatch: true)
        .map { _request_id, matrix_meta, grm_files, pair_meta, phenotype, quant_covariates, cat_covariates ->
            [resolveRouteMeta(matrix_meta, pair_meta), grm_files, phenotype, quant_covariates, cat_covariates]
        }
        .branch { route_meta, _grm_files, _phenotype, _quant_covariates, _cat_covariates ->
            reml: route_meta.method == 'gcta_bivariate_reml'
            hereg: route_meta.method == 'gcta_bivariate_he'
        }

    //
    // MODULE: primary dense GCTA bivariate REML relationship request
    //
    def ch_bivariate_invocations = ch_dense_requests.reml.multiMap { route_meta, grm_files, phenotype, quant_covariates, cat_covariates ->
        grm: [route_meta, grm_files]
        pheno: [route_meta, phenotype, 1, 2]
        qcovar: [route_meta, quant_covariates]
        covar: [route_meta, cat_covariates]
    }

    GCTA_BIVARIATEREML(
        ch_bivariate_invocations.grm,
        ch_bivariate_invocations.pheno,
        ch_bivariate_invocations.qcovar,
        ch_bivariate_invocations.covar,
    )

    //
    // MODULE: primary dense GCTA bivariate HEreg relationship request
    //
    // `gcta --HEreg-bivar` has no covariate parameter: GCTA 1.94.1 lists `--qcovar` and `--covar` among its
    // accepted options and then never reads them, so passing the prepared covariate tables would silently
    // return an unadjusted estimate. Validation refuses a covariate-bearing HE request before execution and
    // the prepared covariate tables are deliberately dropped here rather than forwarded.
    def ch_hereg_invocations = ch_dense_requests.hereg.multiMap { route_meta, grm_files, phenotype, _quant_covariates, _cat_covariates ->
        grm: [route_meta, grm_files]
        pheno: [route_meta, phenotype, 1, 2]
    }

    GCTA_BIVARIATEHEREG(
        ch_hereg_invocations.grm,
        ch_hereg_invocations.pheno,
    )

    //
    // LDMS GCTA relationship requests: bivariate REML-LDMS and bivariate HEreg-LDMS
    //
    // The request ID and matrix content key remain separate attribution fields so a unary GREML-LDMS request
    // and a pair request can share one scientifically identical ordered matrix family without sharing result
    // identity. The consuming task writes its MGRM control list from the supplied prefix order.
    def ch_bivariate_ldms_matrices = ch_relationship_ldms_matrices
        .filter { meta, _grm_files, _grm_prefixes -> meta.matrix_kind == 'gcta_ldms' }
        .map { meta, grm_files, grm_prefixes ->
            [meta.request_id, meta, grm_files, grm_prefixes]
        }

    def ch_ldms_prepared_pairs = ch_prepared_pairs.filter { _request_id, pair_meta, _phenotype, _quant_covariates, _cat_covariates -> pair_meta.matrix_kind == 'gcta_ldms' }

    def ch_ldms_requests = ch_bivariate_ldms_matrices
        .join(ch_ldms_prepared_pairs, failOnDuplicate: true, failOnMismatch: true)
        .map { _request_id, matrix_meta, grm_files, grm_prefixes, pair_meta, phenotype, quant_covariates, cat_covariates ->
            [resolveLdmsRouteMeta(matrix_meta, pair_meta), grm_files, grm_prefixes, phenotype, quant_covariates, cat_covariates]
        }
        .branch { route_meta, _grm_files, _grm_prefixes, _phenotype, _quant_covariates, _cat_covariates ->
            reml: route_meta.method == 'gcta_bivariate_reml_ldms'
            hereg: route_meta.method == 'gcta_bivariate_he_ldms'
        }

    //
    // MODULE: primary GCTA bivariate REML-LDMS relationship request
    //
    def ch_bivariate_ldms_invocations = ch_ldms_requests.reml.multiMap { route_meta, grm_files, grm_prefixes, phenotype, quant_covariates, cat_covariates ->
        mgrm: [route_meta, grm_files, grm_prefixes]
        pheno: [route_meta, phenotype, 1, 2]
        qcovar: [route_meta, quant_covariates]
        covar: [route_meta, cat_covariates]
    }

    GCTA_BIVARIATEREMLLDMS(
        ch_bivariate_ldms_invocations.mgrm,
        ch_bivariate_ldms_invocations.pheno,
        ch_bivariate_ldms_invocations.qcovar,
        ch_bivariate_ldms_invocations.covar,
    )

    //
    // MODULE: primary GCTA bivariate HEreg-LDMS relationship request
    //
    // The multi-component moment fit emits its own native component and total results.
    def ch_hereg_ldms_invocations = ch_ldms_requests.hereg.multiMap { route_meta, grm_files, grm_prefixes, phenotype, _quant_covariates, _cat_covariates ->
        mgrm: [route_meta, grm_files, grm_prefixes]
        pheno: [route_meta, phenotype, 1, 2]
    }

    GCTA_BIVARIATEHEREGLDMS(
        ch_hereg_ldms_invocations.mgrm,
        ch_hereg_ldms_invocations.pheno,
    )

    emit:
    reml_results       = GCTA_BIVARIATEREML.out.bivariate_results.map { meta, result -> [stripNativeMatrixIdentity(meta), result] } // channel: [ val(meta), path(native.hsq) ]
    reml_log           = GCTA_BIVARIATEREML.out.log_file.map { meta, log -> [stripNativeMatrixIdentity(meta), log] } // channel: [ val(meta), path(native.log) ]
    hereg_results      = GCTA_BIVARIATEHEREG.out.hereg_results.map { meta, result -> [stripNativeMatrixIdentity(meta), result] } // channel: [ val(meta), path(native.HEreg) ]
    hereg_log          = GCTA_BIVARIATEHEREG.out.log.map { meta, log -> [stripNativeMatrixIdentity(meta), log] } // channel: [ val(meta), path(native.log) ]
    reml_ldms_results  = GCTA_BIVARIATEREMLLDMS.out.bivariate_results.map { meta, result -> [stripNativeMatrixIdentity(meta), result] } // channel: [ val(meta), path(native.hsq) ]
    reml_ldms_log      = GCTA_BIVARIATEREMLLDMS.out.log_file.map { meta, log -> [stripNativeMatrixIdentity(meta), log] } // channel: [ val(meta), path(native.log) ]
    hereg_ldms_results = GCTA_BIVARIATEHEREGLDMS.out.hereg_results.map { meta, result -> [stripNativeMatrixIdentity(meta), result] } // channel: [ val(meta), path(native.HEreg) ]
    hereg_ldms_log     = GCTA_BIVARIATEHEREGLDMS.out.log.map { meta, log -> [stripNativeMatrixIdentity(meta), log] } // channel: [ val(meta), path(native.log) ]
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

// Fold the matrix record's native and reuse identities into the request record. `id` becomes the staged
// matrix basename because the installed REML atoms address their GRM or MGRM family that way; the HEreg atoms
// resolve the basename from the staged bundle themselves, but keeping one route identity across the four
// estimators lets them share preparation and publication. The matrix
// attribution is carried by the request-keyed join with the prepared phenotype.
def resolveRouteMeta(matrix_meta, pair_meta) {
    return pair_meta + [
        id: matrix_meta.matrix_basename,
        matrix_key: matrix_meta.matrix_key,
        matrix_basename: matrix_meta.matrix_basename,
    ]
}

def resolveLdmsRouteMeta(matrix_meta, pair_meta) {
    return pair_meta + [id: matrix_meta.matrix_key, matrix_key: matrix_meta.matrix_key]
}

// Drop the controller's native and reuse identities from a result record and restore the focal scientific
// identity. `matrix_basename` exists only because the installed dense atom addresses its GRM by staged
// basename, `matrix_key` is the content-derived matrix reuse key, and dense `id` was rewritten to that
// basename for the same reason. Downstream the record is the request, so `id` returns to `request_id`; the
// request, method, relationship and endpoint attribution, trait identity and prevalence declarations are
// retained untouched.
def stripNativeMatrixIdentity(meta) {
    return meta.findAll { key, _value -> !(key in ['matrix_basename', 'matrix_key']) } + [id: meta.request_id]
}
