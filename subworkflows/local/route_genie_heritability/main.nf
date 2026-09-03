// Route unary analysis units through GENIE's additive randomised Haseman-Elston estimator. No relatedness
// matrix is requested or built: the estimator reads the cohort's PLINK 1 derivative directly. This controller
// owns estimator selection, the FAM-order adapter that turns the pipeline's prepared phenotype and covariate
// seams into the files GENIE actually consumes, and the effective stochastic settings the native call renders.
// Emits no versions; reads no params.

// MODULE: Local to the pipeline
include { PREPARE_GENIE_INPUTS            } from '../../../modules/local/prepare_genie_inputs/main'
include { GENIE_G                         } from '../../../modules/local/genie/g/main'

// FUNCTION: Local to the pipeline
include { getMethodCapabilities           } from '../validate_gwas_input/method_registry'
include { getMethodTokensWithCapabilities } from '../validate_gwas_input/method_registry'

workflow ROUTE_GENIE_HERITABILITY {
    take:
    ch_plink1_genotypes // channel: [ val(meta), path(bed), path(bim), path(fam) ], unary analyses whose selectors need PLINK 1
    ch_phenotypes // channel: [ val(meta), path(phenotype) ], headerless FID/IID/value
    ch_adjustment_covariates // channel: [ val(meta), path(adjustment_covariates) ], only analyses that declared covariates
    ch_annotations // channel: [ val(meta), path(annotation) ], [] unless the analysis declared genie.annotation

    main:

    // A capability query, not a token list: every heritability estimator of the GENIE option family is routed
    // here, and the selected token travels as route metadata rather than appearing as a literal in this file.
    def genie_methods = getMethodTokensWithCapabilities([domain: 'heritability', option_family: 'genie'])
    def capabilities = getMethodCapabilities()
    def selects_genie = { meta -> meta.heritability_methods.any { method -> method in genie_methods } }

    // Every stream is narrowed by the same predicate before the guarded joins and keyed by the analysis
    // identifier, never by the meta map, so a record belonging to an analysis this route does not serve is not
    // a mismatch. The adjustment design is the one stream that is legitimately absent, and joins with
    // `remainder: true` plus the null guard ROUTE_GRM_HERITABILITY uses.
    def ch_genie_inputs = ch_plink1_genotypes
        .filter { meta, _bed, _bim, _fam -> selects_genie.call(meta) }
        .map { meta, bed, bim, fam -> [meta.id, meta, bed, bim, fam] }
        .join(
            ch_phenotypes.filter { meta, _phenotype -> selects_genie.call(meta) }.map { meta, phenotype -> [meta.id, phenotype] },
            failOnDuplicate: true,
            failOnMismatch: true,
        )
        .join(
            ch_adjustment_covariates.filter { meta, _adjustment_covariates -> selects_genie.call(meta) }.map { meta, adjustment_covariates -> [meta.id, adjustment_covariates] },
            failOnDuplicate: true,
            remainder: true,
        )
        .filter { record -> record[1] != null }
        .join(
            ch_annotations.filter { meta, _annotation -> selects_genie.call(meta) }.map { meta, annotation -> [meta.id, annotation] },
            failOnDuplicate: true,
            failOnMismatch: true,
        )
        .flatMap { _analysis_id, meta, bed, bim, fam, phenotype, adjustment_covariates, annotation ->
            meta.heritability_methods
                .findAll { method -> method in genie_methods }
                .collect { method ->
                    def route_meta = meta + [
                        genie_method: method,
                        genie_capability: capabilities[method].subMap(['option_family', 'estimator_family', 'input_backend', 'component_model', 'stochastic']),
                    ]
                    [route_meta, bed, bim, fam, phenotype, adjustment_covariates ?: [], annotation ?: []]
                }
        }
        .multiMap { route_meta, bed, bim, fam, phenotype, adjustment_covariates, annotation ->
            genotypes: [route_meta, bed, bim, fam]
            phenotype: [route_meta, phenotype, adjustment_covariates]
            annotation: [route_meta, annotation]
        }

    //
    // MODULE: Align the analysis unit's phenotype, covariates and component annotation to the cohort's FAM
    //
    PREPARE_GENIE_INPUTS(ch_genie_inputs.genotypes, ch_genie_inputs.phenotype, ch_genie_inputs.annotation)

    // The adapter owns the effective settings, because the clamped jackknife default and the rejection of a
    // curated count above the variant count both need the cohort's real BIM. The controller folds the result
    // into route metadata so the configured argument closure renders exactly what the sidecar recorded. The
    // join key is the analysis identifier paired with the selected token, which is the fan-out axis here.
    def routeKey = { meta -> [meta.id, meta.genie_method] }
    def ch_genie_invocations = PREPARE_GENIE_INPUTS.out.phenotype
        .map { meta, phenotype -> [routeKey.call(meta), meta, phenotype] }
        .join(PREPARE_GENIE_INPUTS.out.annotation.map { meta, annotation -> [routeKey.call(meta), annotation] }, failOnDuplicate: true, failOnMismatch: true)
        .join(PREPARE_GENIE_INPUTS.out.expected_counts.map { meta, expected_counts -> [routeKey.call(meta), expected_counts] }, failOnDuplicate: true, failOnMismatch: true)
        .join(PREPARE_GENIE_INPUTS.out.covariates.map { meta, covariates -> [routeKey.call(meta), covariates] }, failOnDuplicate: true, remainder: true)
        .filter { record -> record[1] != null }
        .join(PREPARE_GENIE_INPUTS.out.effective_settings.map { meta, effective -> [routeKey.call(meta), effective] }, failOnDuplicate: true, failOnMismatch: true)
        .join(ch_genie_inputs.genotypes.map { meta, bed, bim, fam -> [routeKey.call(meta), bed, bim, fam] }, failOnDuplicate: true, failOnMismatch: true)
        .multiMap { _key, meta, phenotype, annotation, expected_counts, covariates, effective_settings, bed, bim, fam ->
            // One small JSON per analysis, read on the head node exactly as the LD- and MAF-stratified strata
            // manifest is; the alternative is counting a million-line BIM here to derive the same numbers.
            def effective = new groovy.json.JsonSlurper().parse(effective_settings)
            def route_meta = meta + [genie_effective: effective]
            genotypes: [route_meta, bed, bim, fam]
            settings: [route_meta, phenotype, covariates ?: [], annotation, expected_counts, effective.memory_efficient]
        }

    //
    // MODULE: Estimate additive heritability from the raw genotypes
    //
    GENIE_G(ch_genie_invocations.genotypes, ch_genie_invocations.settings)

    emit:
    genie_results    = GENIE_G.out.results.map { meta, results -> [restoreFocalMeta(meta), results] } // channel: [ val(meta), path(out) ], one per analysis and selected GENIE method
    genie_log        = GENIE_G.out.log.map { meta, log -> [restoreFocalMeta(meta), log] } // channel: [ val(meta), path(log) ]
    genie_provenance = PREPARE_GENIE_INPUTS.out.provenance.map { meta, provenance -> [restoreFocalMeta(meta), provenance] } // channel: [ val(meta), path(provenance_json) ]
}

// The three route-local keys exist so the atom, the adapter and the configured publication closures can see the
// selected token and its resolved settings. They are stripped before emission so a consumer receives the same
// focal analysis identity it supplied, and so the route cannot leak its own bookkeeping into a published key.
def restoreFocalMeta(meta) {
    return meta.findAll { name, _value -> !(name in ['genie_method', 'genie_capability', 'genie_effective']) }
}
