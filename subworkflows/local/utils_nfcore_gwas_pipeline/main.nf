//
// Subworkflow with functionality specific to the nf-core/gwas pipeline
//

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT FUNCTIONS / MODULES / SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { UTILS_NFSCHEMA_PLUGIN   } from '../../nf-core/utils_nfschema_plugin'
include { paramsSummaryMap        } from 'plugin/nf-schema'
include { samplesheetToList       } from 'plugin/nf-schema'
include { paramsHelp              } from 'plugin/nf-schema'
include { completionEmail         } from '../../nf-core/utils_nfcore_pipeline'
include { completionSummary       } from '../../nf-core/utils_nfcore_pipeline'
include { UTILS_NFCORE_PIPELINE   } from '../../nf-core/utils_nfcore_pipeline'
include { UTILS_NEXTFLOW_PIPELINE } from '../../nf-core/utils_nextflow_pipeline'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW TO INITIALISE PIPELINE
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow PIPELINE_INITIALISATION {
    take:
    version // boolean: Display version and exit
    validate_params // boolean: Boolean whether to validate parameters against the schema at runtime
    monochrome_logs // boolean: Do not use coloured log outputs
    nextflow_cli_args //   array: List of positional nextflow CLI args
    outdir //  string: The output directory where the results will be saved
    input //  string: Path to input samplesheet
    help // boolean: Display help message and exit
    help_full // boolean: Show the full help message
    show_hidden // boolean: Show hidden parameters in the help message

    main:

    ch_versions = channel.empty()

    //
    // Print version and exit if required and dump pipeline parameters to JSON file
    //
    UTILS_NEXTFLOW_PIPELINE(
        version,
        true,
        outdir,
        workflow.profile.tokenize(',').intersect(['conda', 'mamba']).size() >= 1,
    )

    //
    // Validate parameters and generate parameter summary to stdout
    //

    def before_text = ""
    def after_text = ""
    before_text = """
-\033[2m----------------------------------------------------\033[0m-
                                        \033[0;32m,--.\033[0;30m/\033[0;32m,-.\033[0m
\033[0;34m        ___     __   __   __   ___     \033[0;32m/,-._.--~\'\033[0m
\033[0;34m  |\\ | |__  __ /  ` /  \\ |__) |__         \033[0;33m}  {\033[0m
\033[0;34m  | \\| |       \\__, \\__/ |  \\ |___     \033[0;32m\\`-._,-`-,\033[0m
                                        \033[0;32m`._,._,\'\033[0m
\033[0;35m  nf-core/gwas ${workflow.manifest.version}\033[0m
-\033[2m----------------------------------------------------\033[0m-
"""
    after_text = """${workflow.manifest.doi ? "\n* The pipeline\n" : ""}${workflow.manifest.doi.tokenize(",").collect { doi -> "    https://doi.org/${doi.trim().replace('https://doi.org/', '')}" }.join("\n")}${workflow.manifest.doi ? "\n" : ""}
* The nf-core framework
    https://doi.org/10.1038/s41587-020-0439-x

* Software dependencies
    https://github.com/nf-core/gwas/blob/master/CITATIONS.md
"""
    if (monochrome_logs) {
        before_text = before_text.replaceAll(/\033\[[0-9;]*m/, '')
    }

    command = "nextflow run ${workflow.manifest.name} -profile <docker/singularity/.../institute> --input samplesheet.csv --outdir <OUTDIR>"

    UTILS_NFSCHEMA_PLUGIN(
        workflow,
        validate_params,
        null,
        help,
        help_full,
        show_hidden,
        before_text,
        after_text,
        command,
    )

    //
    // Check config provided to the pipeline
    //
    UTILS_NFCORE_PIPELINE(
        nextflow_cli_args
    )

    //
    // Create channel from input file provided through params.input
    //
    // The samplesheet is validated in two passes. nf-schema covers everything a per-row JSON
    // Schema can express; validateInputSamplesheet covers the rest — the fields whose validity
    // depends on which methods a row selects, and the cross-field and cross-row rules no per-row
    // schema can reach. Validation runs over the whole list rather than per channel element,
    // because the cross-row rules need every row in hand before any of them can be decided.
    //
    def input_schema = "${projectDir}/assets/schema_input.json"
    def ch_samplesheet = channel.fromList(
        validateInputSamplesheet(samplesheetToList(input, input_schema), input, input_schema)
    )

    emit:
    samplesheet = ch_samplesheet
    versions    = ch_versions
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW FOR PIPELINE COMPLETION
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow PIPELINE_COMPLETION {
    take:
    email //  string: email address
    email_on_fail //  string: email address sent on pipeline failure
    plaintext_email // boolean: Send plain-text email instead of HTML
    outdir //    path: Path to output directory where results will be published
    monochrome_logs // boolean: Disable ANSI colour codes in log output
    multiqc_report //  string: Path to MultiQC report

    main:
    summary_params = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")
    def multiqc_reports = multiqc_report.toList()

    //
    // Completion email and summary
    //
    workflow.onComplete {
        if (email || email_on_fail) {
            completionEmail(
                summary_params,
                email,
                email_on_fail,
                plaintext_email,
                outdir,
                monochrome_logs,
                multiqc_reports.getVal(),
            )
        }

        completionSummary(monochrome_logs)
    }

    workflow.onError {
        log.error("Pipeline failed. Please refer to troubleshooting docs for common issues: https://nf-co.re/docs/running/troubleshooting")
    }
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// The GWASLab constructor column mapping for each association method.
//
// Explicit mappings rather than GWASLab format names, for every method and not only the ones with no
// format-book entry: LDAK-KVIK has no entry at all, the pinned GWASLab version differs from the version
// whose format book was inspected, and PLINK 2's own entry declares a `#` comment character, which would
// make pandas read the `#CHROM` header line as a comment. Four short maps cost less than four unverified
// assumptions.
//
// The keys are `gwaslab.Sumstats` constructor arguments and the values are the source column headers the
// programme actually writes; the component splats the serialised map straight into that constructor. A key
// that is not a constructor argument is forwarded to `pandas.read_table` instead, which is how `readargs`
// carries a non-tab separator.
//
// `common` applies to every analysis. `quantitative` and `binary` are merged over it where the programme
// renames its effect columns by trait type; a method that does not need them omits both.
//
// Registering a new association route is exactly this: add an entry. The accepted `association_methods`
// vocabulary is derived from these keys, so a route cannot be selectable without a mapping and a mapping
// cannot be orphaned.
//
def associationColumnMappings() {
    return [
        plink2: [
            common: [
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
            ]
        ],
        regenie: [
            common: [
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
            ]
        ],
        gcta_fastgwa: [
            common: [
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
            ]
        ],
        ldak_kvik: [
            common: [
                snpid: 'Predictor',
                chrom: 'Chromosome',
                pos: 'Basepair',
                ea: 'A1',
                nea: 'A2',
                maf: 'MAF',
                z: 'Wald_Stat',
                p: 'Wald_P',
            ],
            quantitative: [beta: 'Effect', se: 'SE'],
            binary: [beta: 'Approx_Log_OR', se: 'Approx_SE'],
        ],
    ]
}

//
// The column mapping for one analysis, serialised as the JSON object the component takes as its
// `input_format`. Serialised here rather than written out by hand so that quoting is the JSON library's
// problem rather than a reviewer's.
//
def associationColumnMappingJson(method, is_binary) {
    def entry = associationColumnMappings()[method]
    if (!entry) {
        error("[nf-core/gwas] ERROR: no GWASLab column mapping is registered for association method '${method}'")
    }
    return groovy.json.JsonOutput.toJson(entry.common + (entry[is_binary ? 'binary' : 'quantitative'] ?: [:]))
}

//
// The optional GWASLab reference resources, keyed on genome build and on nothing else. The samplesheet's
// `genome_build` column is the only real heterogeneity in this set — an rsID VCF is a property of the
// coordinate system, not of a cohort or an ancestry — so the reference selection reduces to this.
//
// A build with no configured resource yields empty lists, which stage nothing and reach the component as
// an absent reference; harmonisation then standardises without one rather than failing. Index sidecars are
// read by convention rather than exposed as six further parameters, and a missing one is a hard error
// naming the file, because a silently absent index would fail later inside GWASLab.
//
def gwaslabReferenceLookup() {
    def sidecar = { resource, suffixes ->
        if (!resource) {
            return []
        }
        def resolved = suffixes.collect { suffix -> file("${resource}${suffix}") }.find { candidate -> candidate.exists() }
        if (!resolved) {
            error("[nf-core/gwas] ERROR: no index found for GWASLab reference '${resource}', expected one of ${suffixes.collect { suffix -> "'${resource}${suffix}'" }.join(', ')}")
        }
        return resolved
    }
    def resources = { fasta, rsid_vcf, strand_vcf ->
        [
            fasta: fasta ? file(fasta, checkIfExists: true) : [],
            fasta_index: sidecar.call(fasta, ['.fai']),
            rsid_vcf: rsid_vcf ? file(rsid_vcf, checkIfExists: true) : [],
            rsid_vcf_index: sidecar.call(rsid_vcf, ['.tbi', '.csi']),
            strand_vcf: strand_vcf ? file(strand_vcf, checkIfExists: true) : [],
            strand_vcf_index: sidecar.call(strand_vcf, ['.tbi', '.csi']),
        ]
    }
    return [
        GRCh37: resources.call(params.gwaslab_reference_fasta_grch37, params.gwaslab_rsid_vcf_grch37, params.gwaslab_strand_vcf_grch37),
        GRCh38: resources.call(params.gwaslab_reference_fasta_grch38, params.gwaslab_rsid_vcf_grch38, params.gwaslab_strand_vcf_grch38),
    ]
}

//
// Accepted association method tokens for the `association_methods` column. Derived from the column-mapping
// registry: every association result is harmonised, so a route that is selectable without a registered
// mapping is a route that fails at harmonisation time. The literal order of that map is preserved, so the
// vocabulary this reports in a validation error is unchanged.
//
def associationMethodTokens() {
    return associationColumnMappings().keySet().toList()
}

//
// Accepted heritability method tokens for the `heritability_methods` column. The three LDAK
// estimators are separate tokens rather than one `ldak` token behind a sub-selector, so a single
// analysis can request all three.
//
def heritabilityMethodTokens() {
    return ['gcta_greml', 'gcta_greml_ldms', 'ldak_reml', 'ldak_he', 'ldak_pcgc']
}

//
// The three mutually exclusive genotype groups, each mapped to the columns that make it complete.
// `vcf_index` is deliberately absent: it is declared on the samplesheet for completeness but the
// VCF converter does not consume it, so requiring it would reject valid input.
//
def genotypeGroups() {
    return [
        plink2: ['pgen', 'psam', 'pvar'],
        plink1: ['bed', 'bim', 'fam'],
        vcf: ['vcf'],
    ]
}

//
// The samplesheet columns nf-schema emits positionally after the meta map, in the order it emits
// them. Derived from the schema rather than restated here: a column added there shifts every later
// slot, and a hand-maintained copy would silently start reading cells from the wrong column. A
// column is positional exactly when it declares no `meta` key, which today makes the list identical
// to the columns carrying files.
//
def samplesheetPositionalColumns(schema) {
    def properties = new groovy.json.JsonSlurper().parseText(file(schema).text).items.properties
    return properties.findAll { _column, definition -> !definition.containsKey('meta') }.keySet().toList()
}

//
// An empty samplesheet cell never reaches the meta map as null: nf-schema drops the key and its
// converter substitutes an empty list in its place. A populated cell, meanwhile, may arrive as a
// number whose Groovy truth is false — `0` is both a legal PLINK control code and a legal MAF bin
// edge. So "was this column populated?" is asked through this, and its answer compared against
// null rather than taken as a truth value.
//
def cellValue(value) {
    if (value == null || (value instanceof Collection && value.isEmpty())) {
        return null
    }
    return value.toString().trim() ? value : null
}

//
// Split a comma-delimited method selector cell into its tokens.
//
def tokenizeMethodSelector(selector) {
    return selector ? selector.toString().tokenize(',').collect { token -> token.trim() }.findAll { token -> token } : []
}

//
// The method routes a row selects, as the membership tests the conditional columns are gated on.
// Each is membership of a named token set rather than "the selector list is non-empty", so a row
// naming only an unrecognised method is still treated as selecting nothing.
//
def methodRoutes(association_methods, heritability_methods) {
    return [
        runs_heritability: heritability_methods.any { method -> method in heritabilityMethodTokens() },
        runs_ldak_kvik: association_methods.contains('ldak_kvik'),
        runs_ldak_heritability: heritability_methods.any { method -> method in ['ldak_reml', 'ldak_he', 'ldak_pcgc'] },
        runs_ldak_pcgc: heritability_methods.contains('ldak_pcgc'),
        runs_gcta: association_methods.contains('gcta_fastgwa') || heritability_methods.any { method -> method in ['gcta_greml', 'gcta_greml_ldms'] },
        runs_greml_ldms: heritability_methods.contains('gcta_greml_ldms'),
    ]
}

//
// The conditional columns of one row, resolved once. The LDAK model and power defaults are
// samplesheet column defaults rather than pipeline parameters: nf-schema fills them in when the
// column is present, but a samplesheet may omit the column altogether, so they are resolved here as
// well before anything is compared against them. Every other conditional column is deliberately
// left without a default.
//
def rowSettings(meta) {
    def ldak_power = cellValue(meta.ldak_power)
    return [
        ldak_model: cellValue(meta.ldak_model) ?: 'human_default',
        ldak_power: ldak_power != null ? ldak_power : -0.25,
        ldak_relatedness_filter: cellValue(meta.ldak_relatedness_filter) ? true : false,
        ldak_kvik_step1_subset: cellValue(meta.ldak_kvik_step1_subset),
        gcta_grm_parts: cellValue(meta.gcta_grm_parts),
        population_prevalence: cellValue(meta.population_prevalence),
        sample_prevalence: cellValue(meta.sample_prevalence),
        case_value: cellValue(meta.case_value),
        control_value: cellValue(meta.control_value),
        gcta_ldms_maf_edges: cellValue(meta.gcta_ldms_maf_edges),
    ]
}

//
// Method selectors: every token must belong to its column's vocabulary and may appear only once.
// These are resolved before anything else because membership of them is what makes nine further
// columns meaningful or meaningless.
//
def validateMethodSelectors(association_methods, heritability_methods, reject) {
    [
        [column: 'association_methods', methods: association_methods, vocabulary: associationMethodTokens()],
        [column: 'heritability_methods', methods: heritability_methods, vocabulary: heritabilityMethodTokens()],
    ].each { selector ->
        def unknown = selector.methods.findAll { method -> !selector.vocabulary.contains(method) }.unique()
        if (unknown) {
            reject.call(selector.column, "unknown method${unknown.size() > 1 ? 's' : ''} ${unknown.collect { method -> "'${method}'" }.join(', ')}, accepted values are ${selector.vocabulary.collect { method -> "'${method}'" }.join(', ')}")
        }
        def repeated = selector.methods.countBy { method -> method }.findAll { _method, count -> count > 1 }.keySet()
        if (repeated) {
            reject.call(selector.column, "method${repeated.size() > 1 ? 's' : ''} ${repeated.collect { method -> "'${method}'" }.join(', ')} listed more than once")
        }
    }
    // Neither selector alone is required, so an empty row is only detectable from both together and
    // is attributed to both.
    if (!association_methods && !heritability_methods) {
        reject.call(['association_methods', 'heritability_methods'], "row selects no method, populate one of them or remove the row")
    }
}

//
// Genotype groups: exactly one, populated completely. Returns the name of the one complete group,
// or null when the row does not have one.
//
def validateGenotypeGroup(cells, reject) {
    def groups = genotypeGroups()
    def populated_groups = groups.findAll { _name, columns -> columns.any { column -> cells[column] } }
    if (!populated_groups) {
        // Nothing on the row points at a genotype column, so every genotype column is equally
        // implicated and naming one of them would be arbitrary.
        reject.call(groups.values().flatten(), "no genotype group is populated, supply exactly one of pgen/psam/pvar, bed/bim/fam or vcf")
    }
    else if (populated_groups.size() > 1) {
        populated_groups
            .keySet()
            .toList()
            .tail()
            .each { name ->
                def populated_column = groups[name].find { column -> cells[column] }
                reject.call(populated_column, "a second genotype group is populated on this row, supply exactly one of pgen/psam/pvar, bed/bim/fam or vcf")
            }
    }
    else {
        def group_name = populated_groups.keySet().first()
        groups[group_name]
            .findAll { column -> !cells[column] }
            .each { column ->
                reject.call(column, "genotype group '${group_name}' is only partly populated, all of ${groups[group_name].join(', ')} are required together")
            }
    }
    return populated_groups.size() == 1 ? populated_groups.keySet().first() : null
}

//
// Cross-row: every row on one cohort must describe the same genotypes, so a copy-paste error in one
// row cannot silently apply another cohort's data. The genotype columns of this row are the ones
// that disagree with the source the cohort already established, so they are what the error names.
//
def checkCohortGenotypesAgree(cohort_id, line, genotype_format, genotype_files, source_by_cohort_id, reject) {
    if (!genotype_format || !genotype_files.every { genotype_file -> genotype_file }) {
        return null
    }
    def cohort_source = [genotype_format, genotype_files.collect { genotype_file -> genotype_file.toString() }]
    def known_source = source_by_cohort_id[cohort_id]
    if (!known_source) {
        source_by_cohort_id[cohort_id] = [line: line, source: cohort_source]
    }
    else if (known_source.source != cohort_source) {
        reject.call(genotypeGroups()[genotype_format], "rows sharing cohort_id '${cohort_id}' declare different genotype sources, row ${known_source.line} declares ${known_source.source[0]} '${known_source.source[1].first()}'")
    }
}

//
// Trait type drives the case, control and prevalence columns. It is the canonical trait
// classification and is never inferred from the values or from prevalence.
//
def validateTraitColumns(is_binary, settings, reject) {
    if (is_binary) {
        if (settings.case_value == null) {
            reject.call('case_value', "a binary trait must declare the value used for cases in the phenotype file")
        }
        if (settings.control_value == null) {
            reject.call('control_value', "a binary trait must declare the value used for controls in the phenotype file")
        }
    }
    else {
        if (settings.case_value != null) {
            reject.call('case_value', "case_value has no meaning on a quantitative trait, remove it or set trait_type to 'binary'")
        }
        if (settings.control_value != null) {
            reject.call('control_value', "control_value has no meaning on a quantitative trait, remove it or set trait_type to 'binary'")
        }
        if (settings.population_prevalence != null) {
            reject.call('population_prevalence', "prevalence has no meaning on a quantitative trait, remove it or set trait_type to 'binary'")
        }
        if (settings.sample_prevalence != null) {
            reject.call('sample_prevalence', "prevalence has no meaning on a quantitative trait, remove it or set trait_type to 'binary'")
        }
    }
    if (settings.sample_prevalence != null && settings.population_prevalence == null) {
        reject.call('sample_prevalence', "a sample prevalence corrects ascertainment against a population prevalence, which this row does not declare")
    }
}

//
// The nine columns whose validity depends on which methods the row selects. Each is consumed by
// particular methods only, so populating one without selecting its consumer is a typo rather than a
// harmless no-op, and leaving one empty when its consumer is selected is an under-specified
// analysis.
//
def validateMethodConditionedColumns(settings, cells, routes, reject) {
    if (settings.population_prevalence != null && !routes.runs_heritability) {
        reject.call('population_prevalence', "prevalence is consumed by the heritability methods only, and none are selected on this row")
    }
    if (settings.population_prevalence == null && routes.runs_ldak_pcgc) {
        reject.call('population_prevalence', "'ldak_pcgc' always estimates on the liability scale and requires a population prevalence")
    }
    if (settings.sample_prevalence != null && !routes.runs_heritability) {
        reject.call('sample_prevalence', "prevalence is consumed by the heritability methods only, and none are selected on this row")
    }
    if (settings.ldak_model != 'human_default' && !routes.runs_ldak_heritability) {
        reject.call('ldak_model', "the LDAK kinship model is consumed by the LDAK heritability methods only, and none are selected on this row")
    }
    if (settings.ldak_model == 'human_default' && settings.ldak_power != -0.25) {
        reject.call('ldak_power', "the documented human model fixes the power at -0.25, set ldak_model to 'custom' to supply your own")
    }
    if (settings.ldak_power != -0.25 && !routes.runs_ldak_heritability) {
        reject.call('ldak_power', "the LDAK kinship power is consumed by the LDAK heritability methods only, and none are selected on this row")
    }
    if (settings.ldak_relatedness_filter && !routes.runs_ldak_heritability) {
        reject.call('ldak_relatedness_filter', "the relatedness filter is consumed by the LDAK heritability methods only, and none are selected on this row")
    }
    if (settings.ldak_kvik_step1_subset != null && !routes.runs_ldak_kvik) {
        reject.call('ldak_kvik_step1_subset', "the KVIK step 1 subset control is consumed by 'ldak_kvik' only, which is not selected on this row")
    }
    if (settings.ldak_kvik_step1_subset == null && routes.runs_ldak_kvik) {
        reject.call('ldak_kvik_step1_subset', "'ldak_kvik' is selected but no step 1 predictor subset is declared, there is no implicit resolution")
    }
    if (cells.ldak_kvik_step1_extract && !routes.runs_ldak_kvik) {
        reject.call('ldak_kvik_step1_extract', "a KVIK step 1 extract file is consumed by 'ldak_kvik' only, which is not selected on this row")
    }
    if (cells.ldak_kvik_step1_extract && settings.ldak_kvik_step1_subset != 'provided') {
        reject.call('ldak_kvik_step1_extract', "a KVIK step 1 extract file is only accepted when ldak_kvik_step1_subset is 'provided', this row declares '${settings.ldak_kvik_step1_subset ?: ''}'")
    }
    if (settings.ldak_kvik_step1_subset == 'provided' && !cells.ldak_kvik_step1_extract) {
        reject.call('ldak_kvik_step1_extract', "ldak_kvik_step1_subset is 'provided' but no extract file is supplied")
    }
    if (settings.gcta_grm_parts != null && !routes.runs_gcta) {
        reject.call('gcta_grm_parts', "the GCTA relatedness matrix part count is consumed by the GCTA methods only, and none are selected on this row")
    }
    if (settings.gcta_grm_parts == null && routes.runs_gcta) {
        reject.call('gcta_grm_parts', "a GCTA method is selected but no relatedness matrix part count is declared")
    }
    if (settings.gcta_ldms_maf_edges != null && !routes.runs_greml_ldms) {
        reject.call('gcta_ldms_maf_edges', "MAF bin edges are consumed by 'gcta_greml_ldms' only, which is not selected on this row")
    }
    if (settings.gcta_ldms_maf_edges == null && routes.runs_greml_ldms) {
        reject.call('gcta_ldms_maf_edges', "'gcta_greml_ldms' is selected but no semicolon-delimited MAF bin edges are supplied")
    }
}

//
// MAF bin edges reach here either as the raw semicolon-delimited text or, when a single edge is
// declared, as the number nf-schema inferred from that lone cell.
//
def parseMafEdges(maf_edges, reject) {
    def parsed_maf_edges = maf_edges != null ? maf_edges.toString().tokenize(';').collect { edge -> edge.trim() as BigDecimal } : []
    if (parsed_maf_edges != parsed_maf_edges.toSorted() || parsed_maf_edges.unique(false).size() != parsed_maf_edges.size()) {
        reject.call('gcta_ldms_maf_edges', "MAF bin edges must be strictly increasing, got '${maf_edges}'")
    }
    return parsed_maf_edges
}

//
// Validate the samplesheet beyond what the per-row JSON Schema can express, and reshape each row
// into `[ meta, genotype_files, phenotype, quant_covariates, cat_covariates, ldak_kvik_step1_extract ]`.
//
// Every error names the samplesheet row it came from and the column, or set of columns, it is
// about, so a large samplesheet can be fixed without bisecting it. All errors are collected and
// reported together rather than failing on the first one. Note that nf-schema numbers data rows
// from 1 as "Entry N" while this pass counts the header as row 1, so its first data row is row 2.
//
// The rules themselves live in the helpers above, one job each; this reads the row, hands each
// helper what it needs, and reshapes what survives.
//
def validateInputSamplesheet(rows, samplesheet, schema) {
    def positional_columns = samplesheetPositionalColumns(schema)
    def groups = genotypeGroups()

    def errors = []
    def line_by_analysis_id = [:]
    def source_by_cohort_id = [:]
    def validated_rows = []

    rows.eachWithIndex { row, index ->
        // The header occupies line 1, so the first data row is line 2.
        def line = index + 2
        def meta = row[0]
        def cells = [positional_columns, row[1..-1]].transpose().collectEntries()

        // A rule that no single column owns names every column it implicates, rather than picking
        // one of them and leaving the reader to guess why. The helpers below invoke this as
        // `reject.call(...)`: `nextflow lint` does not model a closure passed as an argument and
        // reports bare call syntax as an undefined function.
        def reject = { column, message ->
            def named = column instanceof List ? column : [column]
            def label = named.size() > 1
                ? "columns ${named.collect { name -> "'${name}'" }.join(', ')}"
                : "column '${named.first()}'"
            errors << "  - row ${line} (analysis_id '${meta.id}'), ${label}: ${message}"
        }

        //
        // Cross-row: `analysis_id` is the focal identifier of every output path, so two rows
        // sharing one would overwrite each other's results.
        //
        if (line_by_analysis_id.containsKey(meta.id)) {
            reject.call('analysis_id', "duplicate analysis_id, already declared on row ${line_by_analysis_id[meta.id]}")
        }
        else {
            line_by_analysis_id[meta.id] = line
        }

        def association_methods = tokenizeMethodSelector(meta.association_methods)
        def heritability_methods = tokenizeMethodSelector(meta.heritability_methods)
        validateMethodSelectors(association_methods, heritability_methods, reject)

        def routes = methodRoutes(association_methods, heritability_methods)
        def settings = rowSettings(meta)

        def genotype_format = validateGenotypeGroup(cells, reject)
        def genotype_files = genotype_format ? groups[genotype_format].collect { column -> cells[column] } : []
        checkCohortGenotypesAgree(meta.cohort, line, genotype_format, genotype_files, source_by_cohort_id, reject)

        def is_binary = meta.trait_type == 'binary'
        validateTraitColumns(is_binary, settings, reject)
        validateMethodConditionedColumns(settings, cells, routes, reject)
        def parsed_maf_edges = parseMafEdges(settings.gcta_ldms_maf_edges, reject)

        validated_rows << [
            meta + [
                association_methods: association_methods,
                heritability_methods: heritability_methods,
                genotype_format: genotype_format,
                is_binary: is_binary,
                has_covariates: cells.quant_covariates || cells.cat_covariates ? true : false,
                case_value: settings.case_value == null ? null : settings.case_value.toString(),
                control_value: settings.control_value == null ? null : settings.control_value.toString(),
                population_prevalence: settings.population_prevalence,
                sample_prevalence: settings.sample_prevalence,
                ldak_model: settings.ldak_model,
                ldak_power: settings.ldak_power,
                ldak_relatedness_filter: settings.ldak_relatedness_filter,
                ldak_kvik_step1_subset: settings.ldak_kvik_step1_subset,
                gcta_grm_parts: settings.gcta_grm_parts,
                gcta_ldms_maf_edges: parsed_maf_edges,
            ],
            genotype_files,
            cells.phenotype,
            cells.quant_covariates,
            cells.cat_covariates,
            cells.ldak_kvik_step1_extract,
        ]
    }

    if (errors) {
        error("[nf-core/gwas] ERROR: Validation of samplesheet failed!\n\nThe following problems have been detected in ${samplesheet}:\n\n${errors.join('\n')}\n")
    }

    return validated_rows
}

//
// Generate methods description for MultiQC
//
def toolCitationText() {
    // TODO nf-core: Optionally add in-text citation tools to this list.
    // Can use ternary operators to dynamically construct based conditions, e.g. params["run_xyz"] ? "Tool (Foo et al. 2023)" : "",
    // Uncomment function in methodsDescriptionText to render in MultiQC report
    def citation_text = ["Tools used in the workflow included:", "MultiQC (Ewels et al. 2016)", "."].join(' ').trim()

    return citation_text
}

def toolBibliographyText() {
    // TODO nf-core: Optionally add bibliographic entries to this list.
    // Can use ternary operators to dynamically construct based conditions, e.g. params["run_xyz"] ? "<li>Author (2023) Pub name, Journal, DOI</li>" : "",
    // Uncomment function in methodsDescriptionText to render in MultiQC report
    def reference_text = ["<li>Ewels, P., Magnusson, M., Lundin, S., & Käller, M. (2016). MultiQC: summarize analysis results for multiple tools and samples in a single report. Bioinformatics , 32(19), 3047–3048. doi: /10.1093/bioinformatics/btw354</li>"].join(' ').trim()

    return reference_text
}

def methodsDescriptionText(mqc_methods_yaml) {
    // Convert  to a named map so can be used as with familiar NXF ${workflow} variable syntax in the MultiQC YML file
    def meta = [:]
    meta.workflow = workflow.toMap()
    meta["manifest_map"] = workflow.manifest.toMap()

    // Pipeline DOI
    if (meta.manifest_map.doi) {
        // Using a loop to handle multiple DOIs
        // Removing `https://doi.org/` to handle pipelines using DOIs vs DOI resolvers
        // Removing ` ` since the manifest.doi is a string and not a proper list
        def temp_doi_ref = ""
        def manifest_doi = meta.manifest_map.doi.tokenize(",")
        manifest_doi.each { doi_ref ->
            temp_doi_ref += "(doi: <a href=\'https://doi.org/${doi_ref.replace("https://doi.org/", "").replace(" ", "")}\'>${doi_ref.replace("https://doi.org/", "").replace(" ", "")}</a>), "
        }
        meta["doi_text"] = temp_doi_ref.substring(0, temp_doi_ref.length() - 2)
    }
    else {
        meta["doi_text"] = ""
    }
    meta["nodoi_text"] = meta.manifest_map.doi ? "" : "<li>If available, make sure to update the text to include the Zenodo DOI of version of the pipeline used. </li>"

    // Tool references
    meta["tool_citations"] = ""
    meta["tool_bibliography"] = ""

    // TODO nf-core: Only uncomment below if logic in toolCitationText/toolBibliographyText has been filled!
    // meta["tool_citations"] = toolCitationText().replaceAll(", \\.", ".").replaceAll("\\. \\.", ".").replaceAll(", \\.", ".")
    // meta["tool_bibliography"] = toolBibliographyText()


    def methods_text = mqc_methods_yaml.text

    def engine = new groovy.text.SimpleTemplateEngine()
    def description_html = engine.createTemplate(methods_text).make(meta)

    return description_html.toString()
}
