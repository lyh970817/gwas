// The closed vocabularies every registry entry is written against. Routing and validation ask the registry
// which methods hold a capability instead of repeating a method-name list that silently goes stale when a
// method is added, so a new entry that omits or misspells a capability must fail the registry contract test
// rather than quietly fall out of a hardcoded list.
//
// `input_backend` names the representation the estimator genuinely consumes. A direct-genotype estimator is a
// distinct backend and must never be given a fabricated matrix kind to make it look like a GRM route.
// `sparse_grm` is a real sixth backend rather than a variant of `dense_grm`: fastGWA streams genotypes against
// a sparse relatedness matrix. `reference_strictness` grades how badly a summary estimator degrades when its
// external LD reference does not match the GWAS; `strict` is declared for the reference-strict full-LD
// likelihood family that has no registered entry yet.
def getMethodCapabilityContract() {
    return [
        required_fields: [
            'domain',
            'estimator_family',
            'input_backend',
            'component_model',
            'trait_support',
            'stochastic',
            'produces_likelihood',
            'supports_partial_overlap',
            'reference_strictness',
            'requires_prevalence',
            'produces_reusable_intermediates',
            'role',
            'citation_key',
        ],
        estimator_families: [
            'generalised_linear_model',
            'whole_genome_regression',
            'mixed_linear_model',
            'reml',
            'moment_he',
            'pcgc',
            'ld_score_regression',
            'summary_tagging_regression',
        ],
        input_backends: [
            'dense_grm',
            'ldms_grm_family',
            'ldak_kinship',
            'sparse_grm',
            'direct_plink_genotypes',
            'summary_statistics',
        ],
        component_models: [
            'not_applicable',
            'single_component',
            'ldms_multi_component',
            'tagging_model_defined',
        ],
        prevalence_requirements: ['not_consumed', 'consumed', 'required'],
        reference_strictness: ['tolerant', 'model_matched', 'strict'],
        trait_support_fields: ['quantitative', 'binary', 'binary_requires'],
    ]
}

// One registry owns selector domain, option family, matrix, prevalence, declared estimator capability and
// citation knowledge. Association entries also carry their GWASLab constructor mapping so the selector
// vocabulary cannot drift from it. Every capability is derived from what the wired module actually runs, not
// from the shape of the token, and `getMethodCapabilityContract()` fixes the vocabulary each one is written in.
//
// Four readings need stating, because the declared value is not obvious from the token:
//   - `ldak_sumher` declares `tagging_model_defined` because the staged tagging bundle, not the pipeline,
//     fixes the category count; the reference catalog admits both one-category and annotation-rich SumHer
//     models. `ldak_sumcors` is `single_component` because every accepted SumCors bundle model is
//     one-category.
//   - `ldak_he` consumes no prevalence at all, so a binary trait keeps the observed scale.
//   - `ldak_he`, `ldak_pcgc` and `ldak_kvik` are `stochastic` because their standard errors or model
//     components come from a randomised step; `tests/nextflow.config` and the LDAK test profiles pin
//     `--random-seed` for exactly those three and for nothing else.
//   - `ldak_pcgc` is binary-only in `trait_support` because a quantitative row may not declare a prevalence
//     and this estimator may not run without one; the two established rules already make it so.
def getMethodRegistry() {
    return [
        plink2: [
            domain: 'association',
            estimator_family: 'generalised_linear_model',
            input_backend: 'direct_plink_genotypes',
            component_model: 'not_applicable',
            trait_support: [quantitative: true, binary: true, binary_requires: []],
            stochastic: false,
            produces_likelihood: false,
            supports_partial_overlap: null,
            reference_strictness: null,
            requires_prevalence: [population: 'not_consumed', sample: 'not_consumed'],
            produces_reusable_intermediates: false,
            role: 'unrelated-sample generalised linear association baseline',
            citation_key: 'plink2',
            mapping: [common: [
                snpid: 'ID',
                chrom: '#CHROM',
                pos: 'POS',
                ea: 'A1',
                nea: 'REF',
                eaf: 'A1_FREQ',
                n: 'OBS_CT',
                beta: 'BETA',
                se: 'SE',
                p: 'P',
            ]],
        ],
        regenie: [
            domain: 'association',
            option_family: 'regenie',
            estimator_family: 'whole_genome_regression',
            input_backend: 'direct_plink_genotypes',
            component_model: 'not_applicable',
            trait_support: [quantitative: true, binary: true, binary_requires: []],
            stochastic: false,
            produces_likelihood: false,
            supports_partial_overlap: null,
            reference_strictness: null,
            requires_prevalence: [population: 'not_consumed', sample: 'not_consumed'],
            produces_reusable_intermediates: false,
            role: 'whole-genome-regression association for related or structured samples',
            citation_key: 'regenie',
            mapping: [common: [
                snpid: 'ID',
                chrom: 'CHROM',
                pos: 'GENPOS',
                ea: 'ALLELE1',
                nea: 'ALLELE0',
                eaf: 'A1FREQ',
                n: 'N',
                beta: 'BETA',
                se: 'SE',
                mlog10p: 'LOG10P',
                readargs: [sep: ' '],
            ]],
        ],
        gcta_fastgwa: [
            domain: 'association',
            option_family: 'gcta',
            matrix_kind: 'gcta_sparse',
            estimator_family: 'mixed_linear_model',
            input_backend: 'sparse_grm',
            component_model: 'single_component',
            trait_support: [quantitative: true, binary: true, binary_requires: []],
            stochastic: false,
            produces_likelihood: false,
            supports_partial_overlap: null,
            reference_strictness: null,
            requires_prevalence: [population: 'not_consumed', sample: 'not_consumed'],
            produces_reusable_intermediates: true,
            role: 'sparse-GRM mixed-linear-model association for related samples',
            citation_key: 'gcta_fastgwa',
            mapping: [common: [
                snpid: 'SNP',
                chrom: 'CHR',
                pos: 'POS',
                ea: 'A1',
                nea: 'A2',
                eaf: 'AF1',
                n: 'N',
                beta: 'BETA',
                se: 'SE',
                p: 'P',
            ]],
        ],
        ldak_kvik: [
            domain: 'association',
            option_family: 'ldak',
            estimator_family: 'mixed_linear_model',
            input_backend: 'direct_plink_genotypes',
            component_model: 'single_component',
            trait_support: [quantitative: true, binary: true, binary_requires: []],
            stochastic: true,
            produces_likelihood: false,
            supports_partial_overlap: null,
            reference_strictness: null,
            requires_prevalence: [population: 'not_consumed', sample: 'not_consumed'],
            produces_reusable_intermediates: false,
            role: 'LDAK mixed-model association fitted under the LDAK heritability model',
            citation_key: 'ldak_kvik',
            mapping: [
                common: [
                    snpid: 'Predictor',
                    chrom: 'Chromosome',
                    pos: 'Basepair',
                    ea: 'A1',
                    nea: 'A2',
                    eaf: 'EAF',
                    neff: 'N',
                    p: 'Wald_P',
                ],
                quantitative: [beta: 'Effect', se: 'SE'],
                binary: [beta: 'Approx_Log_OR', se: 'Approx_SE'],
            ],
        ],
        gcta_greml: [
            domain: 'heritability',
            option_family: 'gcta',
            matrix_kind: 'gcta_dense',
            consumes_population_prevalence: true,
            estimator_family: 'reml',
            input_backend: 'dense_grm',
            component_model: 'single_component',
            trait_support: [quantitative: true, binary: true, binary_requires: []],
            stochastic: false,
            produces_likelihood: true,
            supports_partial_overlap: null,
            reference_strictness: null,
            requires_prevalence: [population: 'consumed', sample: 'not_consumed'],
            produces_reusable_intermediates: true,
            role: 'established exact/reference REML',
            citation_key: 'gcta_greml',
        ],
        gcta_greml_ldms: [
            domain: 'heritability',
            option_family: 'gcta',
            matrix_kind: 'gcta_ldms',
            consumes_population_prevalence: true,
            estimator_family: 'reml',
            input_backend: 'ldms_grm_family',
            component_model: 'ldms_multi_component',
            trait_support: [quantitative: true, binary: true, binary_requires: []],
            stochastic: false,
            produces_likelihood: true,
            supports_partial_overlap: null,
            reference_strictness: null,
            requires_prevalence: [population: 'consumed', sample: 'not_consumed'],
            produces_reusable_intermediates: true,
            role: 'established exact/reference REML',
            citation_key: 'gcta_greml_ldms',
        ],
        gcta_bivariate_reml: [
            domain: 'pairwise',
            endpoint_domain: 'analysis',
            option_family: 'gcta',
            matrix_kind: 'gcta_dense',
            consumes_population_prevalence: true,
            estimator_family: 'reml',
            input_backend: 'dense_grm',
            component_model: 'single_component',
            trait_support: [quantitative: true, binary: true, binary_requires: []],
            stochastic: false,
            produces_likelihood: true,
            supports_partial_overlap: true,
            reference_strictness: null,
            requires_prevalence: [population: 'consumed', sample: 'not_consumed'],
            produces_reusable_intermediates: true,
            role: 'canonical likelihood reference and the supported binary or mixed-trait pair route',
            citation_key: 'gcta_bivariate_reml',
        ],
        gcta_bivariate_reml_ldms: [
            domain: 'pairwise',
            endpoint_domain: 'analysis',
            option_family: 'gcta',
            matrix_kind: 'gcta_ldms',
            consumes_population_prevalence: true,
            estimator_family: 'reml',
            input_backend: 'ldms_grm_family',
            component_model: 'ldms_multi_component',
            trait_support: [quantitative: true, binary: true, binary_requires: []],
            stochastic: false,
            produces_likelihood: true,
            supports_partial_overlap: true,
            reference_strictness: null,
            requires_prevalence: [population: 'consumed', sample: 'not_consumed'],
            produces_reusable_intermediates: true,
            role: 'canonical likelihood reference and the supported binary or mixed-trait pair route',
            citation_key: 'gcta_bivariate_reml',
            citation_keys: ['gcta_bivariate_reml', 'gcta_greml_ldms'],
        ],
        gcta_bivariate_he: [
            domain: 'pairwise',
            endpoint_domain: 'analysis',
            option_family: 'gcta',
            matrix_kind: 'gcta_dense',
            estimator_family: 'moment_he',
            input_backend: 'dense_grm',
            component_model: 'single_component',
            trait_support: [quantitative: true, binary: false, binary_requires: []],
            supports_covariates: false,
            stochastic: false,
            produces_likelihood: false,
            supports_partial_overlap: true,
            reference_strictness: null,
            requires_prevalence: [population: 'not_consumed', sample: 'not_consumed'],
            produces_reusable_intermediates: true,
            role: 'deterministic moment reference or sensitivity over an existing dense GRM',
            citation_key: 'gcta_hereg',
        ],
        gcta_bivariate_he_ldms: [
            domain: 'pairwise',
            endpoint_domain: 'analysis',
            option_family: 'gcta',
            matrix_kind: 'gcta_ldms',
            estimator_family: 'moment_he',
            input_backend: 'ldms_grm_family',
            component_model: 'ldms_multi_component',
            trait_support: [quantitative: true, binary: false, binary_requires: []],
            supports_covariates: false,
            stochastic: false,
            produces_likelihood: false,
            supports_partial_overlap: true,
            reference_strictness: null,
            requires_prevalence: [population: 'not_consumed', sample: 'not_consumed'],
            produces_reusable_intermediates: true,
            role: 'deterministic moment reference or sensitivity over an existing LDMS GRM family',
            citation_key: 'gcta_hereg',
            citation_keys: ['gcta_hereg', 'gcta_greml_ldms'],
        ],
        ldak_sumher: [
            domain: 'summary_unary',
            endpoint_domain: 'summary_statistics',
            option_family: 'ldak',
            reference_family: 'ldak',
            consumes_population_prevalence: true,
            consumes_sample_prevalence: true,
            estimator_family: 'summary_tagging_regression',
            input_backend: 'summary_statistics',
            component_model: 'tagging_model_defined',
            trait_support: [quantitative: true, binary: true, binary_requires: []],
            stochastic: false,
            produces_likelihood: false,
            supports_partial_overlap: null,
            reference_strictness: 'model_matched',
            requires_prevalence: [population: 'consumed', sample: 'consumed'],
            produces_reusable_intermediates: false,
            role: 'heritability-model sensitivity',
            citation_key: 'ldak_sumstats',
        ],
        ldak_sumcors: [
            domain: 'pairwise',
            endpoint_domain: 'summary_statistics',
            option_family: 'ldak',
            reference_family: 'ldak',
            consumes_population_prevalence: true,
            consumes_sample_prevalence: true,
            estimator_family: 'summary_tagging_regression',
            input_backend: 'summary_statistics',
            component_model: 'single_component',
            trait_support: [quantitative: true, binary: true, binary_requires: []],
            stochastic: false,
            produces_likelihood: false,
            supports_partial_overlap: true,
            reference_strictness: 'model_matched',
            requires_prevalence: [population: 'consumed', sample: 'consumed'],
            produces_reusable_intermediates: false,
            role: 'heritability-model sensitivity',
            citation_key: 'ldak_sumstats',
        ],
        ldsc_h2: [
            domain: 'summary_unary',
            endpoint_domain: 'summary_statistics',
            option_family: 'ldsc',
            reference_family: 'ldsc',
            consumes_population_prevalence: true,
            consumes_sample_prevalence: true,
            estimator_family: 'ld_score_regression',
            input_backend: 'summary_statistics',
            component_model: 'single_component',
            trait_support: [quantitative: true, binary: true, binary_requires: []],
            stochastic: false,
            produces_likelihood: false,
            supports_partial_overlap: null,
            reference_strictness: 'tolerant',
            requires_prevalence: [population: 'consumed', sample: 'consumed'],
            produces_reusable_intermediates: false,
            role: 'recommended robust baseline',
            citation_key: 'ldsc',
        ],
        ldsc_rg: [
            domain: 'pairwise',
            endpoint_domain: 'summary_statistics',
            option_family: 'ldsc',
            reference_family: 'ldsc',
            consumes_population_prevalence: true,
            consumes_sample_prevalence: true,
            estimator_family: 'ld_score_regression',
            input_backend: 'summary_statistics',
            component_model: 'single_component',
            trait_support: [quantitative: true, binary: true, binary_requires: []],
            stochastic: false,
            produces_likelihood: false,
            supports_partial_overlap: true,
            reference_strictness: 'tolerant',
            requires_prevalence: [population: 'consumed', sample: 'consumed'],
            produces_reusable_intermediates: false,
            role: 'recommended robust baseline',
            citation_key: 'ldsc',
        ],
        ldak_reml: [
            domain: 'heritability',
            option_family: 'ldak',
            matrix_kind: 'ldak_kinship',
            consumes_population_prevalence: true,
            estimator_family: 'reml',
            input_backend: 'ldak_kinship',
            component_model: 'single_component',
            trait_support: [quantitative: true, binary: true, binary_requires: []],
            stochastic: false,
            produces_likelihood: true,
            supports_partial_overlap: null,
            reference_strictness: null,
            requires_prevalence: [population: 'consumed', sample: 'not_consumed'],
            produces_reusable_intermediates: true,
            role: 'model-specific exact/reference REML',
            citation_key: 'ldak',
        ],
        ldak_he: [
            domain: 'heritability',
            option_family: 'ldak',
            matrix_kind: 'ldak_kinship',
            estimator_family: 'moment_he',
            input_backend: 'ldak_kinship',
            component_model: 'single_component',
            trait_support: [quantitative: true, binary: true, binary_requires: []],
            stochastic: true,
            produces_likelihood: false,
            supports_partial_overlap: null,
            reference_strictness: null,
            requires_prevalence: [population: 'not_consumed', sample: 'not_consumed'],
            produces_reusable_intermediates: true,
            role: 'exact/reference moment estimator',
            citation_key: 'ldak',
        ],
        ldak_pcgc: [
            domain: 'heritability',
            option_family: 'ldak',
            matrix_kind: 'ldak_kinship',
            consumes_population_prevalence: true,
            requires_population_prevalence: true,
            estimator_family: 'pcgc',
            input_backend: 'ldak_kinship',
            component_model: 'single_component',
            trait_support: [quantitative: false, binary: true, binary_requires: ['population_prevalence']],
            stochastic: true,
            produces_likelihood: false,
            supports_partial_overlap: null,
            reference_strictness: null,
            requires_prevalence: [population: 'required', sample: 'not_consumed'],
            produces_reusable_intermediates: true,
            role: 'exact/reference moment estimator',
            citation_key: 'ldak',
        ],
    ]
}

// Preserve the established public mapping shape while projecting it from the unified registry.
def getAssociationColumnMappings() {
    return getMethodRegistry()
        .findAll { _token, entry -> entry.domain == 'association' }
        .collectEntries { token, entry -> [(token): entry.mapping] }
}

def getAssociationColumnMappingJson(method, is_binary) {
    def entry = getAssociationColumnMappings()[method]
    if (!entry) {
        error("[nf-core/gwas] ERROR: no GWASLab column mapping is registered for association method '${method}'")
    }
    return groovy.json.JsonOutput.toJson(entry.common + (entry[is_binary ? 'binary' : 'quantitative'] ?: [:]))
}

// Project the stable capability interface without exposing the association mapping implementation.
def getMethodCapabilities() {
    return getMethodRegistry().collectEntries { token, entry ->
        [(token): entry.findAll { name, _value -> name != 'mapping' }]
    }
}

// Ask the registry which methods hold a capability. Every caller that used to carry its own method-name list
// goes through here, so adding an entry extends the answer instead of leaving one list quietly behind.
def getMethodTokensWithCapabilities(required) {
    def contract = getMethodCapabilityContract()
    def unknown = required.keySet().findAll { field -> !(field in contract.required_fields) && !(field in ['option_family', 'reference_family', 'endpoint_domain', 'matrix_kind', 'requires_population_prevalence', 'consumes_population_prevalence', 'consumes_sample_prevalence', 'citation_keys']) }
    if (unknown) {
        error("[nf-core/gwas] ERROR: method capability selection uses unregistered field '${unknown.first()}'")
    }
    return getMethodCapabilities()
        .findAll { _token, details -> required.every { field, value -> details[field] == value } }
        .keySet()
        .toList()
}

def getMethodCapability(method, field) {
    def details = getMethodCapabilities()[method]
    if (!details) {
        error("[nf-core/gwas] ERROR: no capability is registered for method '${method}'")
    }
    if (!details.containsKey(field)) {
        error("[nf-core/gwas] ERROR: method '${method}' declares no capability '${field}'")
    }
    return details[field]
}

// The PLINK 1 compatibility bundle is a genotype-representation requirement, not a scientific one: every LDAK
// executable reads BED/BIM/FAM, and the GCTA LDMS component plan is built by an LD-score pass that reads the
// same encoding. Summary estimators consume no genotypes at all.
def getPlink1GenotypeMethodTokens() {
    return getMethodCapabilities()
        .findAll { _token, details ->
            details.input_backend != 'summary_statistics' && (details.option_family == 'ldak' || details.input_backend == 'ldms_grm_family')
        }
        .keySet()
        .toList()
}

def getAssociationMethodTokens() {
    return getAssociationColumnMappings().keySet().toList()
}

def getHeritabilityMethodTokens() {
    return getMethodCapabilities()
        .findAll { _token, details -> details.domain == 'heritability' }
        .keySet()
        .toList()
}

def getSummaryUnaryMethodTokens() {
    return getMethodCapabilities()
        .findAll { _token, details -> details.domain == 'summary_unary' }
        .keySet()
        .toList()
}

def getRelationshipMethodTokens() {
    return getMethodCapabilities()
        .findAll { _token, details -> details.domain == 'pairwise' }
        .keySet()
        .toList()
}
