include { getInternalSummaryMetadata ; getSummaryStatisticsId } from './identity_helpers'
include {
    getAnalysisSettings ;
    getGenotypeGroups ;
    getMethodRoutes ;
    getSamplesheetPositionalColumns ;
    normaliseCellValue ;
    tokenizeMethodSelector ;
    validateGenotypeGroup ;
    validateMethodConditionedColumns ;
    validateMethodSelectors ;
    validateTraitColumns
} from './manifest_contracts'
include {
    getMethodCapabilities ;
    getRelationshipMethodTokens ;
    getSummaryUnaryMethodTokens
} from './method_registry'
include {
    getMethodOptionDefaults ;
    readMethodOptionsDocument ;
    validateMethodOptions
} from './method_options'
include { readReferenceCatalog             } from './resolve_references'
include {
    getGctaBivariatePrevalence ;
    requestResourceTuple ;
    resolvePairLdmsMatrixSettings ;
    resolveRequestNamespace
} from './request_contracts'

// Validate the lists as a linked contract and construct the canonical tuple consumed by GWAS.
def validateRelationalInput(cohort_rows, analysis_rows, summary_statistics_rows, relationship_rows, cohort_manifest, analysis_manifest, summary_statistics_manifest, relationship_manifest, cohort_schema, analysis_schema, summary_statistics_schema, relationship_schema, reference_catalog, method_options = null) {
    def cohort_columns = getSamplesheetPositionalColumns(cohort_schema)
    def analysis_columns = getSamplesheetPositionalColumns(analysis_schema)
    def summary_statistics_columns = getSamplesheetPositionalColumns(summary_statistics_schema)
    def relationship_columns = getSamplesheetPositionalColumns(relationship_schema)
    def errors = []
    def cohorts_by_id = [:]
    def analyses_by_id = [:]
    def summaries_by_id = [:]
    def line_by_analysis_id = [:]
    def line_by_summary_statistics_id = [:]
    def line_by_relationship_id = [:]
    def validated_analyses = []
    def validated_external_summaries = []
    def declared_summaries = []
    def generated_summaries_by_id = [:]
    def gcta_primary_requests = []
    def summary_unary_primary_requests = []
    def summary_pair_primary_requests = []
    def options_document = readMethodOptionsDocument(method_options)
    def method_options_by_analysis = validateMethodOptions(method_options, analysis_rows, options_document)
    def reference_bundles = readReferenceCatalog(reference_catalog)
    def pair_prevalence_analysis_ids = relationship_rows.findAll { row ->
        tokenizeMethodSelector(row[0].relationship_methods).any { method ->
            def capability = getMethodCapabilities()[method]
            capability && capability.domain == 'pairwise' && capability.consumes_population_prevalence
        }
    }.collectMany { row -> [normaliseCellValue(row[0].left_analysis_id), normaliseCellValue(row[0].right_analysis_id)] }.findAll { analysis_id -> analysis_id }.collect { analysis_id -> analysis_id.toString() } as Set
    def pair_prevalence_summary_statistics_ids = relationship_rows.findAll { row ->
        tokenizeMethodSelector(row[0].relationship_methods).any { method ->
            def capability = getMethodCapabilities()[method]
            capability && capability.domain == 'pairwise' && capability.consumes_population_prevalence
        }
    }.collectMany { row -> [normaliseCellValue(row[0].left_summary_statistics_id), normaliseCellValue(row[0].right_summary_statistics_id)] }.findAll { summary_statistics_id -> summary_statistics_id }.collect { summary_statistics_id -> summary_statistics_id.toString() } as Set
    def summary_prevalence_analysis_ids = summary_statistics_rows.findAll { row ->
        def summary_statistics_id = normaliseCellValue(row[0].id)?.toString()
        normaliseCellValue(row[0].producer_analysis_id) && (tokenizeMethodSelector(row[0].heritability_methods).any { method -> getMethodCapabilities()[method]?.consumes_population_prevalence } || summary_statistics_id in pair_prevalence_summary_statistics_ids)
    }.collect { row -> normaliseCellValue(row[0].producer_analysis_id).toString() } as Set

    cohort_rows.eachWithIndex { row, index ->
        def line = index + 2
        def cohort_meta = row[0]
        def cells = [cohort_columns, row[1..-1]].transpose().collectEntries()
        def cohort_id = cohort_meta.cohort
        def reject = { field, message ->
            def named = field instanceof List ? field : [field]
            def label = named.size() > 1
                ? "fields ${named.collect { name -> "'${name}'" }.join(', ')}"
                : "field '${named.first()}'"
            errors << "  - ${cohort_manifest} row ${line} (cohort_id '${cohort_id}'), ${label}: ${message}"
        }

        def genotype_format = validateGenotypeGroup(cells, reject)
        def genotype_files = genotype_format
            ? getGenotypeGroups()[genotype_format].collect { column -> cells[column] }
            : []
        def definition = [
            genome_build: cohort_meta.build,
            ancestry: cohort_meta.ancestry,
        ] + getGenotypeGroups().values().flatten().collectEntries { field -> [(field): normaliseCellValue(cells[field])?.toString() ?: ''] }
        def known = cohorts_by_id[cohort_id]
        if (known) {
            if (known.definition == definition) {
                reject.call('cohort_id', "duplicate cohort_id '${cohort_id}', identical definition on row ${known.line}")
            }
            else {
                def differing_fields = definition.keySet().findAll { field -> known.definition[field] != definition[field] }
                reject.call('cohort_id', "duplicate cohort_id '${cohort_id}' conflicts with row ${known.line} in field${differing_fields.size() > 1 ? 's' : ''} ${differing_fields.collect { field -> "'${field}'" }.join(', ')}")
            }
        }
        else {
            cohorts_by_id[cohort_id] = [
                line: line,
                meta: cohort_meta,
                genotype_format: genotype_format,
                genotype_files: genotype_files,
                definition: definition,
            ]
        }
    }

    analysis_rows.eachWithIndex { row, index ->
        def line = index + 2
        def analysis_meta = row[0]
        def cells = [analysis_columns, row[1..-1]].transpose().collectEntries()
        def analysis_id = analysis_meta.id
        def cohort_id = analysis_meta.cohort
        def reject = { field, message ->
            def named = field instanceof List ? field : [field]
            def label = named.size() > 1
                ? "fields ${named.collect { name -> "'${name}'" }.join(', ')}"
                : "field '${named.first()}'"
            errors << "  - ${analysis_manifest} row ${line} (analysis_id '${analysis_id}'), ${label}: ${message}"
        }

        if (line_by_analysis_id.containsKey(analysis_id)) {
            reject.call('analysis_id', "duplicate analysis_id '${analysis_id}', already declared on row ${line_by_analysis_id[analysis_id]}")
        }
        else {
            line_by_analysis_id[analysis_id] = line
        }
        def cohort = cohorts_by_id[cohort_id]
        if (!cohort) {
            reject.call('cohort_id', "undefined cohort_id '${cohort_id}', not declared in cohort manifest '${cohort_manifest}'")
        }

        def association_methods = tokenizeMethodSelector(analysis_meta.association_methods)
        def heritability_methods = tokenizeMethodSelector(analysis_meta.heritability_methods)
        validateMethodSelectors(association_methods, heritability_methods, reject, relationship_rows ? true : false)
        def routes = getMethodRoutes(association_methods, heritability_methods)
        def settings = getAnalysisSettings(analysis_meta)
        def is_binary = analysis_meta.trait_type == 'binary'
        validateTraitColumns(is_binary, settings, reject)
        validateMethodConditionedColumns(
            settings,
            routes,
            reject,
            analysis_id in pair_prevalence_analysis_ids || analysis_id in summary_prevalence_analysis_ids,
        )

        if (cohort) {
            def resolved_meta = analysis_meta + [
                build: cohort.meta.build,
                ancestry: cohort.meta.ancestry,
                association_methods: association_methods,
                heritability_methods: heritability_methods,
                genotype_format: cohort.genotype_format,
                is_binary: is_binary,
                has_covariates: cells.quant_covariates || cells.cat_covariates ? true : false,
                case_value: settings.case_value == null ? null : settings.case_value.toString(),
                control_value: settings.control_value == null ? null : settings.control_value.toString(),
                population_prevalence: settings.population_prevalence,
                sample_prevalence: settings.sample_prevalence,
                method_options: method_options_by_analysis[analysis_id],
            ]
            def validated = [
                resolved_meta,
                cohort.genotype_files,
                cells.phenotype,
                cells.quant_covariates,
                cells.cat_covariates,
                method_options_by_analysis[analysis_id].ldak.predictor_extract,
                method_options_by_analysis[analysis_id].ldak.weights,
            ]
            validated_analyses << validated
            analyses_by_id[analysis_id] = validated
            association_methods.each { association_method ->
                def summary_statistics_id = getSummaryStatisticsId(analysis_id, association_method)
                generated_summaries_by_id[summary_statistics_id] = getInternalSummaryMetadata(resolved_meta, association_method)
            }
        }
    }

    summary_statistics_rows.eachWithIndex { row, index ->
        def line = index + 2
        def summary_meta = row[0]
        def cells = [summary_statistics_columns, row[1..-1]].transpose().collectEntries()
        def summary_statistics_id = summary_meta.id
        def reject = { field, message ->
            def named = field instanceof List ? field : [field]
            def label = named.size() > 1
                ? "fields ${named.collect { name -> "'${name}'" }.join(', ')}"
                : "field '${named.first()}'"
            errors << "  - ${summary_statistics_manifest} row ${line} (summary_statistics_id '${summary_statistics_id}'), ${label}: ${message}"
        }

        if (line_by_summary_statistics_id.containsKey(summary_statistics_id)) {
            reject.call('summary_statistics_id', "duplicate summary_statistics_id '${summary_statistics_id}', already declared on row ${line_by_summary_statistics_id[summary_statistics_id]}")
        }
        else {
            line_by_summary_statistics_id[summary_statistics_id] = line
        }
        def source = normaliseCellValue(cells.source)
        def source_format = normaliseCellValue(summary_meta.source_format)?.toString()
        def producer_analysis_id = normaliseCellValue(summary_meta.producer_analysis_id)?.toString()
        def producer_association_method = normaliseCellValue(summary_meta.producer_association_method)?.toString()
        def has_external_origin = source || source_format
        def has_internal_origin = producer_analysis_id || producer_association_method
        if (has_external_origin && has_internal_origin) {
            reject.call(
                ['source', 'source_format', 'producer_analysis_id', 'producer_association_method'],
                'external source fields and pipeline-generated producer fields are mutually exclusive',
            )
        }
        if (!has_external_origin && !has_internal_origin) {
            reject.call(
                ['source', 'producer_analysis_id'],
                'no summary-statistics origin is declared; supply a complete external source or producer analysis/method pair',
            )
        }
        if (has_external_origin && (!source || !source_format)) {
            reject.call(['source', 'source_format'], 'external origin requires both source fields')
        }
        if (has_internal_origin && (!producer_analysis_id || !producer_association_method)) {
            reject.call(['producer_analysis_id', 'producer_association_method'], 'pipeline-generated origin requires both producer fields')
        }
        def methods = tokenizeMethodSelector(summary_meta.heritability_methods)
        def unknown = methods.findAll { method -> !getSummaryUnaryMethodTokens().contains(method) }.unique()
        if (unknown) {
            reject.call('heritability_methods', "unknown unary summary method${unknown.size() > 1 ? 's' : ''} ${unknown.collect { method -> "'${method}'" }.join(', ')}, accepted values are ${getSummaryUnaryMethodTokens().collect { method -> "'${method}'" }.join(', ')}")
        }
        def repeated = methods.countBy { method -> method }.findAll { _method, count -> count > 1 }.keySet()
        if (repeated) {
            reject.call('heritability_methods', "method${repeated.size() > 1 ? 's' : ''} ${repeated.collect { method -> "'${method}'" }.join(', ')} listed more than once")
        }
        def resolved_meta = null
        if (has_internal_origin && producer_analysis_id && producer_association_method) {
            def producer = analyses_by_id[producer_analysis_id]
            if (!producer) {
                reject.call('producer_analysis_id', "undefined analysis_id '${producer_analysis_id}'")
            }
            else {
                if (!(producer_association_method in producer[0].association_methods)) {
                    reject.call(
                        'producer_association_method',
                        "analysis '${producer_analysis_id}' does not select association method '${producer_association_method}'",
                    )
                }
                def expected_id = getSummaryStatisticsId(producer_analysis_id, producer_association_method)
                if (summary_statistics_id != expected_id) {
                    reject.call(
                        'summary_statistics_id',
                        "pipeline-generated result must use deterministic identifier '${expected_id}'",
                    )
                }
                [
                    trait_id: normaliseCellValue(summary_meta.trait),
                    trait_type: normaliseCellValue(summary_meta.trait_type),
                    genome_build: normaliseCellValue(summary_meta.build),
                    ancestry: normaliseCellValue(summary_meta.ancestry),
                    source_method: normaliseCellValue(summary_meta.source_method),
                    source_release: normaliseCellValue(summary_meta.source_release),
                    population_prevalence: normaliseCellValue(summary_meta.population_prevalence),
                    sample_prevalence: normaliseCellValue(summary_meta.sample_prevalence),
                ].findAll { _field, value -> value != null }.each { field, _value ->
                    reject.call(field, "value is derived from producer analysis '${producer_analysis_id}'; leave this field blank")
                }
                resolved_meta = getInternalSummaryMetadata(producer[0], producer_association_method) + [
                    heritability_methods: methods,
                    access_constraints: normaliseCellValue(summary_meta.access_constraints),
                ]
            }
        }
        if (has_external_origin && source && source_format) {
            if (generated_summaries_by_id.containsKey(summary_statistics_id)) {
                reject.call(
                    'summary_statistics_id',
                    "external result collides with pipeline-generated result '${summary_statistics_id}'; choose a distinct external identity",
                )
            }
            if (source_format.startsWith('auto')) {
                reject.call('source_format', 'external input must declare an explicit GWASLab format name; automatic detection is not supported')
            }
            def is_binary = summary_meta.trait_type == 'binary'
            def population_prevalence = normaliseCellValue(summary_meta.population_prevalence)
            def sample_prevalence = normaliseCellValue(summary_meta.sample_prevalence)
            if (!is_binary && population_prevalence != null) {
                reject.call('population_prevalence', "prevalence has no meaning on a quantitative trait")
            }
            if (!is_binary && sample_prevalence != null) {
                reject.call('sample_prevalence', "sample prevalence has no meaning on a quantitative trait")
            }
            resolved_meta = [
                id: summary_statistics_id,
                summary_statistics_id: summary_statistics_id,
                trait: summary_meta.trait,
                trait_id: summary_meta.trait,
                trait_type: summary_meta.trait_type,
                is_binary: is_binary,
                population_prevalence: population_prevalence,
                sample_prevalence: sample_prevalence,
                build: summary_meta.build,
                ancestry: summary_meta.ancestry,
                source_kind: 'external',
                source_format: source_format,
                source_method: summary_meta.source_method,
                source_release: normaliseCellValue(summary_meta.source_release),
                source_name: file(source).name,
                producer_analysis_id: null,
                producer_association_method: null,
                heritability_methods: methods,
                access_constraints: normaliseCellValue(summary_meta.access_constraints),
            ]
            validated_external_summaries << [resolved_meta, source]
        }
        if (resolved_meta) {
            if (!summaries_by_id.containsKey(summary_statistics_id)) {
                summaries_by_id[summary_statistics_id] = resolved_meta
                declared_summaries << resolved_meta
            }
            methods
                .findAll { method -> getSummaryUnaryMethodTokens().contains(method) }
                .each { method ->
                    def request_id = "${method}--${summary_statistics_id}".toString()
                    summary_unary_primary_requests << [
                        request_id: request_id,
                        method: method,
                        reference_family: getMethodCapabilities()[method].reference_family,
                        meta: resolved_meta + [
                            id: request_id,
                            request_id: request_id,
                            method: method,
                            summary_statistics_id: summary_statistics_id,
                        ],
                    ]
                }
        }
    }

    def seen_bindings = [:]
    def referenced_analyses = [] as Set
    def referenced_summaries = [] as Set
    relationship_rows.eachWithIndex { row, index ->
        def line = index + 2
        def relationship_meta = row[0]
        def cells = [relationship_columns, row[1..-1]].transpose().collectEntries()
        def relationship_id = relationship_meta.id
        def left_analysis_id = normaliseCellValue(relationship_meta.left_analysis_id)?.toString()
        def right_analysis_id = normaliseCellValue(relationship_meta.right_analysis_id)?.toString()
        def left_summary_statistics_id = normaliseCellValue(relationship_meta.left_summary_statistics_id)?.toString()
        def right_summary_statistics_id = normaliseCellValue(relationship_meta.right_summary_statistics_id)?.toString()
        def reject = { field, message ->
            def named = field instanceof List ? field : [field]
            def label = named.size() > 1
                ? "fields ${named.collect { name -> "'${name}'" }.join(', ')}"
                : "field '${named.first()}'"
            errors << "  - ${relationship_manifest} row ${line} (relationship_id '${relationship_id}'), ${label}: ${message}"
        }

        if (line_by_relationship_id.containsKey(relationship_id)) {
            reject.call('relationship_id', "duplicate relationship_id '${relationship_id}', already declared on row ${line_by_relationship_id[relationship_id]}")
        }
        else {
            line_by_relationship_id[relationship_id] = line
        }
        def methods = tokenizeMethodSelector(relationship_meta.relationship_methods)
        def unknown = methods.findAll { method -> !getRelationshipMethodTokens().contains(method) }.unique()
        if (unknown) {
            reject.call('relationship_methods', "unknown method${unknown.size() > 1 ? 's' : ''} ${unknown.collect { method -> "'${method}'" }.join(', ')}, accepted values are ${getRelationshipMethodTokens().collect { method -> "'${method}'" }.join(', ')}")
        }
        def repeated = methods.countBy { method -> method }.findAll { _method, count -> count > 1 }.keySet()
        if (repeated) {
            reject.call('relationship_methods', "method${repeated.size() > 1 ? 's' : ''} ${repeated.collect { method -> "'${method}'" }.join(', ')} listed more than once")
        }
        if (!methods) {
            reject.call('relationship_methods', 'row selects no pairwise method')
        }
        def capabilities = getMethodCapabilities()
        def analysis_methods = methods.findAll { method -> capabilities[method]?.endpoint_domain == 'analysis' }
        def summary_methods = methods.findAll { method -> capabilities[method]?.endpoint_domain == 'summary_statistics' }

        if ((left_analysis_id && !right_analysis_id) || (!left_analysis_id && right_analysis_id)) {
            reject.call(['left_analysis_id', 'right_analysis_id'], 'analysis endpoint slots must be populated together')
        }
        if ((left_summary_statistics_id && !right_summary_statistics_id) || (!left_summary_statistics_id && right_summary_statistics_id)) {
            reject.call(['left_summary_statistics_id', 'right_summary_statistics_id'], 'summary-statistics endpoint slots must be populated together')
        }
        if (analysis_methods && (!left_analysis_id || !right_analysis_id)) {
            reject.call(['left_analysis_id', 'right_analysis_id'], "selected method${analysis_methods.size() > 1 ? 's' : ''} ${analysis_methods.join(', ')} require two analysis endpoints")
        }
        if (summary_methods && (!left_summary_statistics_id || !right_summary_statistics_id)) {
            reject.call(['left_summary_statistics_id', 'right_summary_statistics_id'], "selected method${summary_methods.size() > 1 ? 's' : ''} ${summary_methods.join(', ')} require two summary-statistics endpoints")
        }

        def left_analysis = left_analysis_id ? analyses_by_id[left_analysis_id] : null
        def right_analysis = right_analysis_id ? analyses_by_id[right_analysis_id] : null
        def left_summary = left_summary_statistics_id ? summaries_by_id[left_summary_statistics_id] : null
        def right_summary = right_summary_statistics_id ? summaries_by_id[right_summary_statistics_id] : null
        if (left_analysis_id && !left_analysis) {
            reject.call('left_analysis_id', "undefined analysis_id '${left_analysis_id}'")
        }
        if (right_analysis_id && !right_analysis) {
            reject.call('right_analysis_id', "undefined analysis_id '${right_analysis_id}'")
        }
        if (left_summary_statistics_id && !left_summary) {
            reject.call('left_summary_statistics_id', "undefined summary_statistics_id '${left_summary_statistics_id}'")
        }
        if (right_summary_statistics_id && !right_summary) {
            reject.call('right_summary_statistics_id', "undefined summary_statistics_id '${right_summary_statistics_id}'")
        }
        if (left_analysis_id && right_analysis_id && left_analysis_id == right_analysis_id) {
            reject.call(['left_analysis_id', 'right_analysis_id'], "the exact same analysis endpoint '${left_analysis_id}' cannot occupy both sides")
        }
        if (left_summary_statistics_id && right_summary_statistics_id && left_summary_statistics_id == right_summary_statistics_id) {
            reject.call(['left_summary_statistics_id', 'right_summary_statistics_id'], "the exact same summary-statistics endpoint '${left_summary_statistics_id}' cannot occupy both sides")
        }
        if (left_analysis && left_summary && left_summary.producer_analysis_id != left_analysis_id) {
            reject.call(['left_analysis_id', 'left_summary_statistics_id'], "same-side correspondence cannot be proven: summary '${left_summary_statistics_id}' was not produced by analysis '${left_analysis_id}'")
        }
        if (right_analysis && right_summary && right_summary.producer_analysis_id != right_analysis_id) {
            reject.call(['right_analysis_id', 'right_summary_statistics_id'], "same-side correspondence cannot be proven: summary '${right_summary_statistics_id}' was not produced by analysis '${right_analysis_id}'")
        }

        def left_meta = left_analysis ? left_analysis[0] : left_summary
        def right_meta = right_analysis ? right_analysis[0] : right_summary
        if (left_meta && right_meta && left_meta.trait.toString() == right_meta.trait.toString()) {
            reject.call(
                ['left_analysis_id', 'right_analysis_id', 'left_summary_statistics_id', 'right_summary_statistics_id'],
                "declared trait_id '${left_meta.trait}' is equal on both sides; self-pairs are invalid",
            )
        }
        if (analysis_methods && left_analysis && right_analysis && left_analysis[0].cohort.toString() != right_analysis[0].cohort.toString()) {
            reject.call(['left_analysis_id', 'right_analysis_id'], "individual-level relationship methods require one cohort, but '${left_analysis_id}' uses '${left_analysis[0].cohort}' and '${right_analysis_id}' uses '${right_analysis[0].cohort}'")
        }

        // A method whose declared trait support excludes binary endpoints must fail before execution rather
        // than return an observed-scale number nobody asked for. GCTA bivariate REML keeps the binary and
        // mixed pair domain because it is the only relationship estimator here with an explicit prevalence
        // and liability-scale contract.
        def binary_endpoint = (left_meta && left_meta.is_binary) || (right_meta && right_meta.is_binary)
        def quantitative_only_methods = binary_endpoint
            ? methods.findAll { method -> capabilities[method]?.trait_support && !capabilities[method].trait_support.binary }
            : []
        if (quantitative_only_methods) {
            reject.call(
                'relationship_methods',
                "method${quantitative_only_methods.size() > 1 ? 's' : ''} ${quantitative_only_methods.join(', ')} support two quantitative endpoints only; select 'gcta_bivariate_reml' or 'gcta_bivariate_reml_ldms' for a binary or mixed pair",
            )
        }

        // Declared pair covariates must reach the estimator or the request must fail. GCTA 1.94.1 accepts
        // `--qcovar`/`--covar` on an `--HEreg-bivar` command line and silently ignores them, so a
        // covariate-bearing HE request cannot be honoured and is refused here rather than answered wrongly.
        def covariate_incapable_methods = cells.pair_quant_covariates || cells.pair_cat_covariates
            ? methods.findAll { method -> capabilities[method]?.supports_covariates == false }
            : []
        if (covariate_incapable_methods) {
            reject.call(
                ['pair_quant_covariates', 'pair_cat_covariates'],
                "method${covariate_incapable_methods.size() > 1 ? 's' : ''} ${covariate_incapable_methods.join(', ')} have no native covariate parameter and would ignore the declared pair covariates; remove them or select a covariate-capable method",
            )
        }

        def left_side = "${left_analysis_id ?: ''}\u0001${left_summary_statistics_id ?: ''}".toString()
        def right_side = "${right_analysis_id ?: ''}\u0001${right_summary_statistics_id ?: ''}".toString()
        def binding_key = [left_side, right_side].sort().join('\u0000')
        if (seen_bindings.containsKey(binding_key)) {
            reject.call(
                ['left_analysis_id', 'right_analysis_id', 'left_summary_statistics_id', 'right_summary_statistics_id'],
                "unordered endpoint binding duplicates relationship_id '${seen_bindings[binding_key].id}' on row ${seen_bindings[binding_key].line}",
            )
        }
        else {
            seen_bindings[binding_key] = [id: relationship_id, line: line]
        }
        [left_analysis_id, right_analysis_id].findAll { endpoint -> endpoint }.each { endpoint -> referenced_analyses << endpoint }
        [left_summary_statistics_id, right_summary_statistics_id].findAll { endpoint -> endpoint }.each { endpoint -> referenced_summaries << endpoint }

        if (!unknown && !repeated && methods && left_meta && right_meta) {
            methods.each { method ->
                def request_id = "${method}--${relationship_id}".toString()
                def capability = capabilities[method]
                def common_meta = [
                    id: request_id,
                    request_id: request_id,
                    relationship_id: relationship_id,
                    method: method,
                    relationship_methods: methods,
                    left_analysis_id: left_analysis_id,
                    right_analysis_id: right_analysis_id,
                    left_summary_statistics_id: left_summary_statistics_id,
                    right_summary_statistics_id: right_summary_statistics_id,
                    left_trait_id: left_meta.trait,
                    right_trait_id: right_meta.trait,
                    left_trait_type: left_meta.trait_type,
                    right_trait_type: right_meta.trait_type,
                    left_is_binary: left_meta.is_binary,
                    right_is_binary: right_meta.is_binary,
                    left_genome_build: left_meta.build,
                    right_genome_build: right_meta.build,
                    left_ancestry: left_meta.ancestry,
                    right_ancestry: right_meta.ancestry,
                    left_population_prevalence: left_meta.population_prevalence,
                    right_population_prevalence: right_meta.population_prevalence,
                    left_sample_prevalence: left_meta.sample_prevalence,
                    right_sample_prevalence: right_meta.sample_prevalence,
                ]
                if (capability.endpoint_domain == 'analysis' && left_analysis && right_analysis) {
                    def left_analysis_meta = left_analysis[0]
                    def right_analysis_meta = right_analysis[0]
                    def matrix_settings = capability.matrix_kind == 'gcta_ldms'
                        ? resolvePairLdmsMatrixSettings(
                            [:],
                            getMethodOptionDefaults().gcta.subMap(['ld_score_region_kb', 'ld_bins', 'ldms_maf_edges']),
                        ) { option, reason -> reject.call('relationship_methods', "default ${option}: ${reason}") }
                        : [:]
                    def pair_meta = common_meta + [
                        cohort: left_analysis_meta.cohort,
                        build: left_analysis_meta.build,
                        ancestry: left_analysis_meta.ancestry,
                        genotype_format: left_analysis_meta.genotype_format,
                        matrix_kind: capability.matrix_kind,
                        matrix_settings: matrix_settings,
                        reml_bivar_prevalence: getGctaBivariatePrevalence(left_analysis_meta, right_analysis_meta),
                    ]
                    def payload = [pair_meta, left_analysis[1], cells.pair_quant_covariates, cells.pair_cat_covariates]
                    gcta_primary_requests << [
                        request_id: request_id,
                        method: method,
                        reference_family: null,
                        meta: pair_meta,
                        payload: payload,
                    ]
                }
                if (capability.endpoint_domain == 'summary_statistics' && left_summary && right_summary) {
                    summary_pair_primary_requests << [
                        request_id: request_id,
                        method: method,
                        reference_family: capability.reference_family,
                        meta: common_meta,
                    ]
                }
            }
        }
    }

    validated_analyses.each { row ->
        def meta = row[0]
        if (!meta.association_methods && !meta.heritability_methods && !(meta.id in referenced_analyses)) {
            def line = line_by_analysis_id[meta.id]
            errors << "  - ${analysis_manifest} row ${line} (analysis_id '${meta.id}'), fields 'association_methods', 'heritability_methods': row selects no unary method and is not referenced by any relationship; populate a method, reference it from a relationship or remove the row"
        }
    }
    declared_summaries.each { meta ->
        if (!meta.heritability_methods && !(meta.summary_statistics_id in referenced_summaries)) {
            def line = line_by_summary_statistics_id[meta.summary_statistics_id]
            errors << "  - ${summary_statistics_manifest} row ${line} (summary_statistics_id '${meta.summary_statistics_id}'), field 'heritability_methods': result selects no unary method and is not referenced by any relationship"
        }
    }
    if (errors) {
        error("[nf-core/gwas] ERROR: Validation of linked manifests failed!\n\n${errors.join('\n')}\n")
    }

    def resolved_unary = resolveRequestNamespace(
        method_options,
        options_document,
        'unary_requests',
        summary_unary_primary_requests,
        reference_bundles,
    )
    def resolved_pair = resolveRequestNamespace(
        method_options,
        options_document,
        'pair_requests',
        gcta_primary_requests + summary_pair_primary_requests,
        reference_bundles,
    )
    def resolved_relationships = resolved_pair
        .findAll { resolved -> !resolved.request.reference_family }
        .collect { resolved ->
            def payload = resolved.request.payload
            [resolved.meta, payload[1], payload[2], payload[3]]
        }
    def unary_requests = resolved_unary.collect { resolved -> requestResourceTuple(resolved.meta, resolved.bundle) }
    def pair_requests = resolved_pair
        .findAll { resolved -> resolved.request.reference_family }
        .collect { resolved -> requestResourceTuple(resolved.meta, resolved.bundle) }

    return [
        analyses: validated_analyses,
        summary_statistics: validated_external_summaries,
        relationships: resolved_relationships,
        unary_requests: unary_requests,
        pair_requests: pair_requests,
    ]
}
