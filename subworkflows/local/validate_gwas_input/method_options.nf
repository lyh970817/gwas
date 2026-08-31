include { getMethodCapabilities ; getMethodTokensWithCapabilities } from './method_registry'
include { tokenizeMethodSelector          } from './manifest_contracts'

def getMethodOptionDefaults() {
    return [
        gcta: [
            grm_maf: null,
            grm_extract: [],
            reml_no_constrain: false,
            sparse_cutoff: 0.05,
            ld_score_region_kb: 200,
            ld_bins: 4,
            ldms_maf_edges: [0, 0.01, 0.05, 0.2, 0.5],
        ],
        ldak: [
            model: 'human_default',
            power: -0.25,
            weights_policy: 'equal',
            weights: [],
            relatedness_filter: false,
            kvik_step1_subset: 'all',
            predictor_extract: [],
        ],
        regenie: [
            step1_bsize: 1000,
            firth: true,
            firth_approx: true,
            firth_p_threshold: 0.01,
            min_mac: null,
        ],
    ]
}

def validateMethodOptionKeys(analysis_id, family, options, accepted, operational, fail) {
    def unknown = options.keySet().findAll { option -> !(option in accepted) }
    if (unknown) {
        def option = unknown.first()
        def reason = option in operational
            ? 'operational tuning must be supplied through run/profile configuration'
            : "unknown option; accepted ${family.toUpperCase()} options are ${accepted.join(', ')}"
        if (family == 'gcta' && option == 'gcta_grm_parts') {
            reason = 'partition count is operational and must be supplied through run/profile configuration'
        }
        fail.call(analysis_id, "${family}.${option}", reason)
    }
}

def resolveMethodResource(analysis_id, family, option, options, fail) {
    if (!options.containsKey(option)) {
        return []
    }
    def declared = options[option]
    if (!(declared instanceof String) || !declared.trim()) {
        fail.call(analysis_id, "${family}.${option}", 'expected a non-empty resource path string')
    }
    def resolved = file(declared)
    if (!resolved.exists()) {
        fail.call(analysis_id, "${family}.${option}", "resource path '${declared}' does not exist")
    }
    return resolved
}

def resolveRegenieMethodOptions(analysis_id, options, methods, defaults, fail) {
    def regenie_association = getMethodTokensWithCapabilities([domain: 'association', option_family: 'regenie'])
    if (options && !methods.association_methods.any { method -> method in regenie_association }) {
        fail.call(analysis_id, "regenie.${options.keySet().first()}", "analysis does not select 'regenie'")
    }

    def step1_bsize = options.containsKey('step1_bsize') ? options.step1_bsize : defaults.step1_bsize
    def firth = options.containsKey('firth') ? options.firth : defaults.firth
    def firth_approx = options.containsKey('firth_approx') ? options.firth_approx : defaults.firth_approx
    def firth_p_threshold = options.containsKey('firth_p_threshold') ? options.firth_p_threshold : defaults.firth_p_threshold
    def min_mac = options.containsKey('min_mac') ? options.min_mac : defaults.min_mac
    if (!(step1_bsize instanceof Number) || step1_bsize < 1 || step1_bsize != step1_bsize.toInteger()) {
        fail.call(analysis_id, 'regenie.step1_bsize', 'expected one positive integer')
    }
    if (!(firth instanceof Boolean)) {
        fail.call(analysis_id, 'regenie.firth', 'expected a boolean')
    }
    if (!(firth_approx instanceof Boolean)) {
        fail.call(analysis_id, 'regenie.firth_approx', 'expected a boolean')
    }
    if (options.containsKey('firth_approx') && firth_approx && !firth) {
        fail.call(analysis_id, 'regenie.firth_approx', "requires 'regenie.firth' to be true")
    }
    if (!(firth_p_threshold instanceof Number) || firth_p_threshold <= 0 || firth_p_threshold > 1) {
        fail.call(analysis_id, 'regenie.firth_p_threshold', 'expected a number greater than 0 and at most 1')
    }
    if (min_mac != null && (!(min_mac instanceof Number) || min_mac < 0)) {
        fail.call(analysis_id, 'regenie.min_mac', 'expected a non-negative number or null')
    }
    ['firth', 'firth_approx', 'firth_p_threshold'].each { option ->
        if (options.containsKey(option) && !methods.is_binary) {
            fail.call(analysis_id, "regenie.${option}", 'option is consumed by binary-trait REGENIE analyses only')
        }
    }
    if (options.containsKey('firth_p_threshold') && !firth) {
        fail.call(analysis_id, 'regenie.firth_p_threshold', "requires 'regenie.firth' to be true")
    }
    return [
        step1_bsize: step1_bsize.toInteger(),
        firth: firth,
        firth_approx: firth_approx,
        firth_p_threshold: firth_p_threshold,
        min_mac: min_mac,
    ]
}

def resolveGctaMethodOptions(analysis_id, options, methods, defaults, fail) {
    def capabilities = getMethodCapabilities()
    def selected = (methods.association_methods + methods.heritability_methods).any { method -> capabilities[method] && capabilities[method].option_family == 'gcta' }
    if (options && !selected) {
        fail.call(analysis_id, "gcta.${options.keySet().first()}", 'analysis does not select a GCTA method')
    }
    def gcta_greml_estimators = getMethodTokensWithCapabilities([domain: 'heritability', option_family: 'gcta', estimator_family: 'reml'])
    def gcta_dense_heritability = getMethodTokensWithCapabilities([domain: 'heritability', option_family: 'gcta', input_backend: 'dense_grm'])
    def gcta_ldms_heritability = getMethodTokensWithCapabilities([domain: 'heritability', option_family: 'gcta', input_backend: 'ldms_grm_family'])
    def gcta_sparse_association = getMethodTokensWithCapabilities([domain: 'association', option_family: 'gcta', input_backend: 'sparse_grm'])
    if (options.containsKey('reml_no_constrain') && !methods.heritability_methods.any { method -> method in gcta_greml_estimators }) {
        fail.call(analysis_id, 'gcta.reml_no_constrain', "option is consumed by GCTA GREML estimators only, but this analysis selects neither 'gcta_greml' nor 'gcta_greml_ldms'")
    }
    ['grm_maf', 'grm_extract'].each { option ->
        if (options.containsKey(option) && !methods.heritability_methods.any { method -> method in gcta_dense_heritability }) {
            fail.call(analysis_id, "gcta.${option}", "option is consumed by 'gcta_greml' only, which this analysis does not select")
        }
    }
    if (options.containsKey('sparse_cutoff') && !methods.association_methods.any { method -> method in gcta_sparse_association }) {
        fail.call(analysis_id, 'gcta.sparse_cutoff', "option is consumed by 'gcta_fastgwa' only, which this analysis does not select")
    }
    ['ld_score_region_kb', 'ld_bins', 'ldms_maf_edges'].each { option ->
        if (options.containsKey(option) && !methods.heritability_methods.any { method -> method in gcta_ldms_heritability }) {
            fail.call(analysis_id, "gcta.${option}", "option is consumed by 'gcta_greml_ldms' only, which this analysis does not select")
        }
    }

    def grm_maf = options.containsKey('grm_maf') ? options.grm_maf : defaults.grm_maf
    def sparse_cutoff = options.containsKey('sparse_cutoff') ? options.sparse_cutoff : defaults.sparse_cutoff
    def ld_score_region_kb = options.containsKey('ld_score_region_kb') ? options.ld_score_region_kb : defaults.ld_score_region_kb
    def ld_bins = options.containsKey('ld_bins') ? options.ld_bins : defaults.ld_bins
    def ldms_maf_edges = options.containsKey('ldms_maf_edges') ? options.ldms_maf_edges : defaults.ldms_maf_edges
    def reml_no_constrain = options.containsKey('reml_no_constrain') ? options.reml_no_constrain : defaults.reml_no_constrain
    if (grm_maf != null && (!(grm_maf instanceof Number) || grm_maf < 0 || grm_maf > 0.5)) {
        fail.call(analysis_id, 'gcta.grm_maf', 'expected a number between 0 and 0.5 inclusive')
    }
    if (!(sparse_cutoff instanceof Number) || sparse_cutoff < 0 || sparse_cutoff > 1) {
        fail.call(analysis_id, 'gcta.sparse_cutoff', 'expected a number between 0 and 1 inclusive')
    }
    if (!(ld_score_region_kb instanceof Number) || ld_score_region_kb < 1 || ld_score_region_kb != ld_score_region_kb.toInteger()) {
        fail.call(analysis_id, 'gcta.ld_score_region_kb', 'expected one positive integer')
    }
    if (!(ld_bins instanceof Number) || ld_bins < 1 || ld_bins != ld_bins.toInteger()) {
        fail.call(analysis_id, 'gcta.ld_bins', 'expected one positive integer')
    }
    if (!(ldms_maf_edges instanceof List) || ldms_maf_edges.size() < 2 || !ldms_maf_edges.every { edge -> edge instanceof Number && edge >= 0 && edge <= 0.5 }) {
        fail.call(analysis_id, 'gcta.ldms_maf_edges', 'expected a numeric boundary list spanning 0 to 0.5')
    }
    if (ldms_maf_edges.first() != 0 || ldms_maf_edges.last() != 0.5) {
        fail.call(analysis_id, 'gcta.ldms_maf_edges', 'boundaries must start at 0 and end at 0.5')
    }
    if ((1..<ldms_maf_edges.size()).any { index -> ldms_maf_edges[index] <= ldms_maf_edges[index - 1] }) {
        fail.call(analysis_id, 'gcta.ldms_maf_edges', 'boundaries must be strictly increasing')
    }
    if (!(reml_no_constrain instanceof Boolean)) {
        fail.call(analysis_id, 'gcta.reml_no_constrain', 'expected a boolean')
    }
    return [
        grm_maf: grm_maf,
        grm_extract: resolveMethodResource(analysis_id, 'gcta', 'grm_extract', options, fail),
        reml_no_constrain: reml_no_constrain,
        sparse_cutoff: sparse_cutoff,
        ld_score_region_kb: ld_score_region_kb,
        ld_bins: ld_bins,
        ldms_maf_edges: ldms_maf_edges,
    ]
}

def resolveLdakMethodOptions(analysis_id, options, methods, defaults, fail) {
    def model = options.containsKey('model') ? options.model : defaults.model
    def power = options.containsKey('power') ? options.power : defaults.power
    def weights_policy = options.containsKey('weights_policy') ? options.weights_policy : defaults.weights_policy
    def relatedness_filter = options.containsKey('relatedness_filter') ? options.relatedness_filter : defaults.relatedness_filter
    def kvik_step1_subset = options.containsKey('kvik_step1_subset') ? options.kvik_step1_subset : defaults.kvik_step1_subset
    if (!(model in ['human_default', 'custom'])) {
        fail.call(analysis_id, 'ldak.model', "expected 'human_default' or 'custom'")
    }
    if (!(power instanceof Number) || power < -2 || power > 0) {
        fail.call(analysis_id, 'ldak.power', 'expected a number between -2 and 0 inclusive')
    }
    if (model == 'human_default' && power != -0.25) {
        fail.call(analysis_id, 'ldak.power', "model 'human_default' fixes power at -0.25; set model to 'custom' to supply another power")
    }
    if (!(weights_policy in ['equal', 'default', 'provided'])) {
        fail.call(analysis_id, 'ldak.weights_policy', "expected 'equal', 'default' or 'provided'")
    }
    if (options.containsKey('weights') && weights_policy != 'provided') {
        fail.call(analysis_id, 'ldak.weights', "resource is only accepted when weights_policy is 'provided', got '${weights_policy}'")
    }
    if (weights_policy == 'provided' && !options.containsKey('weights')) {
        fail.call(analysis_id, 'ldak.weights', "weights_policy is 'provided' but no resource is supplied")
    }
    def weights = resolveMethodResource(analysis_id, 'ldak', 'weights', options, fail)
    if (!(relatedness_filter instanceof Boolean)) {
        fail.call(analysis_id, 'ldak.relatedness_filter', 'expected a boolean')
    }
    if (!(kvik_step1_subset in ['all', 'thin_common', 'provided'])) {
        fail.call(analysis_id, 'ldak.kvik_step1_subset', "expected 'all', 'thin_common' or 'provided'")
    }
    if (options.containsKey('predictor_extract') && kvik_step1_subset != 'provided') {
        fail.call(analysis_id, 'ldak.predictor_extract', "resource is only accepted when kvik_step1_subset is 'provided', got '${kvik_step1_subset}'")
    }
    if (kvik_step1_subset == 'provided' && !options.containsKey('predictor_extract')) {
        fail.call(analysis_id, 'ldak.predictor_extract', "kvik_step1_subset is 'provided' but no resource is supplied")
    }
    def predictor_extract = resolveMethodResource(analysis_id, 'ldak', 'predictor_extract', options, fail)

    def ldak_kinship_heritability = getMethodTokensWithCapabilities([domain: 'heritability', input_backend: 'ldak_kinship'])
    def ldak_association = getMethodTokensWithCapabilities([domain: 'association', option_family: 'ldak'])
    def selects_ldak_kinship = methods.heritability_methods.any { method -> method in ldak_kinship_heritability }
    def selects_ldak_kvik = methods.association_methods.any { method -> method in ldak_association }
    if (options && !selects_ldak_kinship && !selects_ldak_kvik) {
        fail.call(analysis_id, "ldak.${options.keySet().first()}", 'analysis does not select an LDAK method')
    }
    if (options.containsKey('weights') && !selects_ldak_kinship) {
        fail.call(analysis_id, 'ldak.weights', 'resource is consumed by LDAK kinship methods only, which this analysis does not select')
    }
    ['model', 'power', 'weights_policy', 'relatedness_filter'].each { option ->
        if (options.containsKey(option) && !selects_ldak_kinship) {
            fail.call(analysis_id, "ldak.${option}", 'option is consumed by LDAK kinship methods only, which this analysis does not select')
        }
    }
    ['kvik_step1_subset', 'predictor_extract'].each { option ->
        if (options.containsKey(option) && !selects_ldak_kvik) {
            fail.call(analysis_id, "ldak.${option}", "option is consumed by 'ldak_kvik' only, which this analysis does not select")
        }
    }
    return [
        model: model,
        power: power,
        weights_policy: weights_policy,
        weights: weights,
        relatedness_filter: relatedness_filter,
        kvik_step1_subset: kvik_step1_subset,
        predictor_extract: predictor_extract,
    ]
}

def readMethodOptionsDocument(method_options) {
    if (!method_options) {
        return [:]
    }
    def document_path = method_options.toString()
    def fail = { reason ->
        error("[nf-core/gwas] ERROR: Method-options document '${document_path}', analysis_id '<document>', option '<root>': ${reason}")
    }
    def document_file = file(method_options)
    if (!document_file.exists()) {
        fail.call('file does not exist')
    }

    def document = null
    try {
        document = new groovy.json.JsonSlurper().parseText(document_file.text)
    }
    catch (exception: Exception) {
        fail.call("malformed JSON (${exception.message})")
    }
    if (!(document instanceof Map)) {
        fail.call('expected an object keyed by analysis_id or by a supported request namespace')
    }
    return document
}

def getAnalysisOptionsDocument(method_options, document) {
    def namespaces = ['analyses', 'unary_requests', 'pair_requests']
    def uses_namespaces = document.keySet().any { key -> key in namespaces }
    if (!uses_namespaces) {
        return document
    }
    def unknown = document.keySet().findAll { key -> !(key in namespaces) }
    if (unknown) {
        error("[nf-core/gwas] ERROR: Method-options document '${method_options}' has unknown top-level namespace '${unknown.first()}'; accepted namespaces are ${namespaces.join(', ')}")
    }
    namespaces.each { namespace ->
        if (document.containsKey(namespace) && !(document[namespace] instanceof Map)) {
            error("[nf-core/gwas] ERROR: Method-options document '${method_options}', namespace '${namespace}': expected an object")
        }
    }
    return document.analyses ?: [:]
}

// Parse and validate the analysis-owned part of the advanced method-options document.
def validateMethodOptions(method_options, analysis_rows, document = null) {
    def defaults = getMethodOptionDefaults()
    if (!method_options) {
        return analysis_rows.collectEntries { row -> [(row[0].id): defaults] }
    }

    document = document == null ? readMethodOptionsDocument(method_options) : document
    def document_path = method_options.toString()
    def fail = { analysis_id, option, reason ->
        error("[nf-core/gwas] ERROR: Method-options document '${document_path}', analysis_id '${analysis_id}', option '${option}': ${reason}")
    }
    def analysis_document = getAnalysisOptionsDocument(method_options, document)

    def analyses = analysis_rows.collectEntries { row ->
        def meta = row[0]
        [(meta.id): [
            association_methods: tokenizeMethodSelector(meta.association_methods),
            heritability_methods: tokenizeMethodSelector(meta.heritability_methods),
            is_binary: meta.trait_type == 'binary',
        ]]
    }
    def resolved = analyses.collectEntries { analysis_id, _methods -> [(analysis_id): defaults] }

    analysis_document.each { analysis_id, families ->
        if (!analyses.containsKey(analysis_id)) {
            fail.call(analysis_id, '<analysis>', 'analysis identifier is not declared in the analysis manifest')
        }
        if (!(families instanceof Map)) {
            fail.call(analysis_id, '<analysis>', 'expected a method-family object')
        }
        def unknown_families = families.keySet().findAll { family -> !defaults.containsKey(family) }
        if (unknown_families) {
            fail.call(analysis_id, unknown_families.first().toString(), 'unknown method family; accepted families are gcta, ldak and regenie')
        }

        def gcta = families.containsKey('gcta') ? families.gcta : [:]
        def ldak = families.containsKey('ldak') ? families.ldak : [:]
        def regenie = families.containsKey('regenie') ? families.regenie : [:]
        [[name: 'gcta', options: gcta], [name: 'ldak', options: ldak], [name: 'regenie', options: regenie]].each { family ->
            if (!(family.options instanceof Map)) {
                fail.call(analysis_id, family.name, 'expected an option object')
            }
        }

        validateMethodOptionKeys(analysis_id, 'regenie', regenie, defaults.regenie.keySet().toList(), ['step2_bsize', 'step1_mode', 'step1_jobs', 'lowmem'], fail)
        validateMethodOptionKeys(analysis_id, 'ldak', ldak, defaults.ldak.keySet().toList(), ['threads', 'jobs', 'partitions'], fail)
        validateMethodOptionKeys(analysis_id, 'gcta', gcta, defaults.gcta.keySet().toList(), ['gcta_grm_parts'], fail)

        def methods = analyses[analysis_id]
        def resolved_regenie = resolveRegenieMethodOptions(analysis_id, regenie, methods, defaults.regenie, fail)
        def resolved_gcta = resolveGctaMethodOptions(analysis_id, gcta, methods, defaults.gcta, fail)
        def resolved_ldak = resolveLdakMethodOptions(analysis_id, ldak, methods, defaults.ldak, fail)
        resolved[analysis_id] = [
            gcta: resolved_gcta,
            ldak: resolved_ldak,
            regenie: resolved_regenie,
        ]
    }
    return resolved
}
