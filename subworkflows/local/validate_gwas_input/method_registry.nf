// The closed vocabularies every registry entry is written against. Routing and validation ask the registry
// which methods hold a capability instead of repeating a method-name list that silently goes stale when a
// method is added, so a new entry that omits or misspells a capability must fail the registry contract test
// rather than quietly fall out of a hardcoded list.
//
// `input_backend` names the representation the estimator genuinely consumes. A direct-genotype estimator is a
// distinct backend and must never be given a fabricated matrix kind to make it look like a GRM route.
// `sparse_grm` is a real sixth backend rather than a variant of `dense_grm`: fastGWA streams genotypes against
// a sparse relatedness matrix.
def getMethodCapabilityContract() {
    return [
        required_fields: [
            'domain',
            'estimator_family',
            'input_backend',
            'trait_support',
            'prevalence',
            'citation_keys',
        ],
        queryable_fields: [
            'domain',
            'option_family',
            'matrix_kind',
            'endpoint_domain',
            'reference_family',
            'estimator_family',
            'input_backend',
            'trait_support',
            'supports_covariates',
            'prevalence',
            'citation_keys',
        ],
        estimator_families: [
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
        prevalence_requirements: ['not_consumed', 'consumed', 'required'],
        trait_support_fields: ['quantitative', 'binary'],
    ]
}

// One registry owns selector domain, option family, matrix, prevalence, declared estimator capability and
// citation knowledge. Association entries also carry their GWASLab constructor mapping so the selector
// vocabulary cannot drift from it. Every capability is derived from what the wired module actually runs, not
// from the shape of the token, and `getMethodCapabilityContract()` fixes the vocabulary each one is written in.
//
// `prevalence` is the one typed scale contract. `consumed` accepts and uses a declared value, `required`
// additionally requires it at ingress, and `not_consumed` rejects it unless a downstream selected method uses
// it. `ldak_he` therefore keeps binary traits on the observed scale, while `ldak_pcgc` is binary-only and
// requires population prevalence.
def getMethodRegistry() {
    return [
        regenie: [
            domain: 'association',
            option_family: 'regenie',
            estimator_family: 'whole_genome_regression',
            input_backend: 'direct_plink_genotypes',
            trait_support: [quantitative: true, binary: true],
            prevalence: [population: 'not_consumed', sample: 'not_consumed'],
            citation_keys: ['regenie'],
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
            trait_support: [quantitative: true, binary: true],
            prevalence: [population: 'not_consumed', sample: 'not_consumed'],
            citation_keys: ['gcta_fastgwa'],
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
            trait_support: [quantitative: true, binary: true],
            prevalence: [population: 'not_consumed', sample: 'not_consumed'],
            citation_keys: ['ldak_kvik'],
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
            estimator_family: 'reml',
            input_backend: 'dense_grm',
            trait_support: [quantitative: true, binary: true],
            prevalence: [population: 'consumed', sample: 'not_consumed'],
            citation_keys: ['gcta_greml'],
        ],
        gcta_greml_ldms: [
            domain: 'heritability',
            option_family: 'gcta',
            matrix_kind: 'gcta_ldms',
            estimator_family: 'reml',
            input_backend: 'ldms_grm_family',
            trait_support: [quantitative: true, binary: true],
            prevalence: [population: 'consumed', sample: 'not_consumed'],
            citation_keys: ['gcta_greml_ldms'],
        ],
        gcta_bivariate_reml: [
            domain: 'pairwise',
            endpoint_domain: 'analysis',
            option_family: 'gcta',
            matrix_kind: 'gcta_dense',
            estimator_family: 'reml',
            input_backend: 'dense_grm',
            trait_support: [quantitative: true, binary: true],
            prevalence: [population: 'consumed', sample: 'not_consumed'],
            citation_keys: ['gcta_bivariate_reml'],
        ],
        gcta_bivariate_reml_ldms: [
            domain: 'pairwise',
            endpoint_domain: 'analysis',
            option_family: 'gcta',
            matrix_kind: 'gcta_ldms',
            estimator_family: 'reml',
            input_backend: 'ldms_grm_family',
            trait_support: [quantitative: true, binary: true],
            prevalence: [population: 'consumed', sample: 'not_consumed'],
            citation_keys: ['gcta_bivariate_reml', 'gcta_greml_ldms'],
        ],
        gcta_bivariate_he: [
            domain: 'pairwise',
            endpoint_domain: 'analysis',
            option_family: 'gcta',
            matrix_kind: 'gcta_dense',
            estimator_family: 'moment_he',
            input_backend: 'dense_grm',
            trait_support: [quantitative: true, binary: false],
            supports_covariates: false,
            prevalence: [population: 'not_consumed', sample: 'not_consumed'],
            citation_keys: ['gcta_hereg'],
        ],
        gcta_bivariate_he_ldms: [
            domain: 'pairwise',
            endpoint_domain: 'analysis',
            option_family: 'gcta',
            matrix_kind: 'gcta_ldms',
            estimator_family: 'moment_he',
            input_backend: 'ldms_grm_family',
            trait_support: [quantitative: true, binary: false],
            supports_covariates: false,
            prevalence: [population: 'not_consumed', sample: 'not_consumed'],
            citation_keys: ['gcta_hereg', 'gcta_greml_ldms'],
        ],
        ldak_sumher: [
            domain: 'summary_unary',
            endpoint_domain: 'summary_statistics',
            option_family: 'ldak',
            reference_family: 'ldak',
            estimator_family: 'summary_tagging_regression',
            input_backend: 'summary_statistics',
            trait_support: [quantitative: true, binary: true],
            prevalence: [population: 'consumed', sample: 'consumed'],
            citation_keys: ['ldak_sumstats'],
        ],
        ldak_sumcors: [
            domain: 'pairwise',
            endpoint_domain: 'summary_statistics',
            option_family: 'ldak',
            reference_family: 'ldak',
            estimator_family: 'summary_tagging_regression',
            input_backend: 'summary_statistics',
            trait_support: [quantitative: true, binary: true],
            prevalence: [population: 'consumed', sample: 'consumed'],
            citation_keys: ['ldak_sumstats'],
        ],
        ldsc_h2: [
            domain: 'summary_unary',
            endpoint_domain: 'summary_statistics',
            option_family: 'ldsc',
            reference_family: 'ldsc',
            estimator_family: 'ld_score_regression',
            input_backend: 'summary_statistics',
            trait_support: [quantitative: true, binary: true],
            prevalence: [population: 'consumed', sample: 'consumed'],
            citation_keys: ['ldsc'],
        ],
        ldsc_rg: [
            domain: 'pairwise',
            endpoint_domain: 'summary_statistics',
            option_family: 'ldsc',
            reference_family: 'ldsc',
            estimator_family: 'ld_score_regression',
            input_backend: 'summary_statistics',
            trait_support: [quantitative: true, binary: true],
            prevalence: [population: 'consumed', sample: 'consumed'],
            citation_keys: ['ldsc'],
        ],
        ldak_reml: [
            domain: 'heritability',
            option_family: 'ldak',
            matrix_kind: 'ldak_kinship',
            estimator_family: 'reml',
            input_backend: 'ldak_kinship',
            trait_support: [quantitative: true, binary: true],
            prevalence: [population: 'consumed', sample: 'not_consumed'],
            citation_keys: ['ldak'],
        ],
        ldak_he: [
            domain: 'heritability',
            option_family: 'ldak',
            matrix_kind: 'ldak_kinship',
            estimator_family: 'moment_he',
            input_backend: 'ldak_kinship',
            trait_support: [quantitative: true, binary: true],
            prevalence: [population: 'not_consumed', sample: 'not_consumed'],
            citation_keys: ['ldak'],
        ],
        ldak_pcgc: [
            domain: 'heritability',
            option_family: 'ldak',
            matrix_kind: 'ldak_kinship',
            estimator_family: 'pcgc',
            input_backend: 'ldak_kinship',
            trait_support: [quantitative: false, binary: true],
            prevalence: [population: 'required', sample: 'not_consumed'],
            citation_keys: ['ldak'],
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
    def unknown = required.keySet().findAll { field -> !(field in contract.queryable_fields) }
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
