//
// Subworkflow with functionality specific to the nf-core/gwas pipeline
//

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT FUNCTIONS / MODULES / SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { UTILS_NFSCHEMA_PLUGIN     } from '../../nf-core/utils_nfschema_plugin'
include { paramsSummaryMap          } from 'plugin/nf-schema'
include { samplesheetToList         } from 'plugin/nf-schema'
include { paramsHelp                } from 'plugin/nf-schema'
include { completionEmail           } from '../../nf-core/utils_nfcore_pipeline'
include { completionSummary         } from '../../nf-core/utils_nfcore_pipeline'
include { UTILS_NFCORE_PIPELINE     } from '../../nf-core/utils_nfcore_pipeline'
include { UTILS_NEXTFLOW_PIPELINE   } from '../../nf-core/utils_nextflow_pipeline'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW TO INITIALISE PIPELINE
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow PIPELINE_INITIALISATION {

    take:
    version           // boolean: Display version and exit
    validate_params   // boolean: Boolean whether to validate parameters against the schema at runtime
    monochrome_logs   // boolean: Do not use coloured log outputs
    nextflow_cli_args //   array: List of positional nextflow CLI args
    outdir            //  string: The output directory where the results will be saved
    input             //  string: Path to input samplesheet
    help              // boolean: Display help message and exit
    help_full         // boolean: Show the full help message
    show_hidden       // boolean: Show hidden parameters in the help message

    main:

    ch_versions = channel.empty()

    //
    // Print version and exit if required and dump pipeline parameters to JSON file
    //
    UTILS_NEXTFLOW_PIPELINE (
        version,
        true,
        outdir,
        workflow.profile.tokenize(',').intersect(['conda', 'mamba']).size() >= 1
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
    after_text = """${workflow.manifest.doi ? "\n* The pipeline\n" : ""}${workflow.manifest.doi.tokenize(",").collect { doi -> "    https://doi.org/${doi.trim().replace('https://doi.org/','')}"}.join("\n")}${workflow.manifest.doi ? "\n" : ""}
* The nf-core framework
    https://doi.org/10.1038/s41587-020-0439-x

* Software dependencies
    https://github.com/nf-core/gwas/blob/master/CITATIONS.md
"""
    if (monochrome_logs) {
        before_text = before_text.replaceAll(/\033\[[0-9;]*m/, '')
    }

    command = "nextflow run ${workflow.manifest.name} -profile <docker/singularity/.../institute> --input samplesheet.csv --outdir <OUTDIR>"

    UTILS_NFSCHEMA_PLUGIN (
        workflow,
        validate_params,
        null,
        help,
        help_full,
        show_hidden,
        before_text,
        after_text,
        command
    )

    //
    // Check config provided to the pipeline
    //
    UTILS_NFCORE_PIPELINE (
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
    def ch_samplesheet = channel.fromList(
        validateInputSamplesheet(samplesheetToList(input, "${projectDir}/assets/schema_input.json"), input)
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
    email           //  string: email address
    email_on_fail   //  string: email address sent on pipeline failure
    plaintext_email // boolean: Send plain-text email instead of HTML
    outdir          //    path: Path to output directory where results will be published
    monochrome_logs // boolean: Disable ANSI colour codes in log output
    multiqc_report  //  string: Path to MultiQC report

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
        log.error "Pipeline failed. Please refer to troubleshooting docs for common issues: https://nf-co.re/docs/running/troubleshooting"
    }
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// Accepted association method tokens for the `association_methods` column.
//
def associationMethodTokens() {
    return ['plink2', 'regenie', 'gcta_fastgwa', 'ldak_kvik']
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
// The samplesheet columns that carry files, in the order nf-schema emits them after the meta map.
//
def samplesheetFileColumns() {
    return [
        'pgen',
        'psam',
        'pvar',
        'bed',
        'bim',
        'fam',
        'vcf',
        'vcf_index',
        'phenotype',
        'quant_covariates',
        'cat_covariates',
        'ldak_kvik_step1_extract',
    ]
}

//
// Empty samplesheet cells reach the meta map as empty strings rather than as nulls, so
// "was this column populated?" is asked through this rather than against null.
//
def cellValue(value) {
    return value != null && value.toString().trim() ? value : null
}

//
// Split a comma-delimited method selector cell into its tokens.
//
def tokenizeMethodSelector(selector) {
    return selector ? selector.toString().tokenize(',').collect { token -> token.trim() }.findAll { token -> token } : []
}

//
// Validate the samplesheet beyond what the per-row JSON Schema can express, and reshape each row
// into `[ meta, genotype_files, phenotype, quant_covariates, cat_covariates, ldak_kvik_step1_extract ]`.
//
// Every error names the samplesheet row it came from and the column it is about, so a large
// samplesheet can be fixed without bisecting it. All errors are collected and reported together
// rather than failing on the first one. Note that nf-schema numbers data rows from 1 as "Entry N"
// while this pass counts the header as row 1, so its first data row is row 2.
//
def validateInputSamplesheet(rows, samplesheet) {
    def file_columns = samplesheetFileColumns()
    def groups = genotypeGroups()
    def association_vocabulary = associationMethodTokens()
    def heritability_vocabulary = heritabilityMethodTokens()

    def errors = []
    def line_by_analysis_id = [:]
    def source_by_cohort_id = [:]
    def validated_rows = []

    rows.eachWithIndex { row, index ->
        // The header occupies line 1, so the first data row is line 2.
        def line = index + 2
        def meta = row[0]
        def files = [file_columns, row[1..-1]].transpose().collectEntries()
        def analysis_id = meta.id

        def reject = { column, message ->
            errors << "  - row ${line} (analysis_id '${analysis_id}'), column '${column}': ${message}"
        }

        //
        // Cross-row: `analysis_id` is the focal identifier of every output path, so two rows
        // sharing one would overwrite each other's results.
        //
        if (line_by_analysis_id.containsKey(analysis_id)) {
            reject('analysis_id', "duplicate analysis_id, already declared on row ${line_by_analysis_id[analysis_id]}")
        }
        else {
            line_by_analysis_id[analysis_id] = line
        }

        //
        // Method selectors. Membership of these two lists is what makes nine further columns
        // meaningful or meaningless, so they are resolved first.
        //
        def association_methods = tokenizeMethodSelector(meta.association_methods)
        def heritability_methods = tokenizeMethodSelector(meta.heritability_methods)

        [
            [column: 'association_methods', methods: association_methods, vocabulary: association_vocabulary],
            [column: 'heritability_methods', methods: heritability_methods, vocabulary: heritability_vocabulary],
        ].each { selector ->
            def unknown = selector.methods.findAll { method -> !selector.vocabulary.contains(method) }.unique()
            if (unknown) {
                reject(selector.column, "unknown method${unknown.size() > 1 ? 's' : ''} ${unknown.collect { method -> "'${method}'" }.join(', ')}, accepted values are ${selector.vocabulary.collect { method -> "'${method}'" }.join(', ')}")
            }
            def repeated = selector.methods.countBy { method -> method }.findAll { _method, count -> count > 1 }.keySet()
            if (repeated) {
                reject(selector.column, "method${repeated.size() > 1 ? 's' : ''} ${repeated.collect { method -> "'${method}'" }.join(', ')} listed more than once")
            }
        }
        if (!association_methods && !heritability_methods) {
            reject('association_methods', "row selects no method, populate 'association_methods' or 'heritability_methods' or remove the row")
        }

        // The LDAK model and power defaults are samplesheet column defaults rather than pipeline
        // parameters. nf-schema fills them in when the column is present, but a samplesheet may omit
        // the column altogether, so they are resolved here as well before anything is compared
        // against them. Every other conditional column is deliberately left without a default.
        def ldak_model = cellValue(meta.ldak_model) ?: 'human_default'
        def ldak_power = cellValue(meta.ldak_power) != null ? meta.ldak_power : -0.25
        def ldak_relatedness_filter = cellValue(meta.ldak_relatedness_filter) ? true : false
        def kvik_step1_subset = cellValue(meta.ldak_kvik_step1_subset)
        def gcta_grm_parts = cellValue(meta.gcta_grm_parts)
        def population_prevalence = cellValue(meta.population_prevalence)
        def sample_prevalence = cellValue(meta.sample_prevalence)
        def case_value = cellValue(meta.case_value)
        def control_value = cellValue(meta.control_value)
        def maf_edges = cellValue(meta.gcta_ldms_maf_edges)

        def runs_ldak_kvik = association_methods.contains('ldak_kvik')
        def runs_ldak_heritability = heritability_methods.any { method -> method in ['ldak_reml', 'ldak_he', 'ldak_pcgc'] }
        def runs_gcta = association_methods.contains('gcta_fastgwa') || heritability_methods.any { method -> method in ['gcta_greml', 'gcta_greml_ldms'] }
        def runs_greml_ldms = heritability_methods.contains('gcta_greml_ldms')

        //
        // Genotype groups: exactly one, populated completely.
        //
        def populated_groups = groups.findAll { _name, columns -> columns.any { column -> files[column] } }
        if (!populated_groups) {
            reject('pgen', "no genotype group is populated, supply exactly one of pgen/psam/pvar, bed/bim/fam or vcf")
        }
        else if (populated_groups.size() > 1) {
            populated_groups.keySet().toList().tail().each { name ->
                def populated_column = groups[name].find { column -> files[column] }
                reject(populated_column, "a second genotype group is populated on this row, supply exactly one of pgen/psam/pvar, bed/bim/fam or vcf")
            }
        }
        else {
            def group_name = populated_groups.keySet().first()
            groups[group_name].findAll { column -> !files[column] }.each { column ->
                reject(column, "genotype group '${group_name}' is only partly populated, all of ${groups[group_name].join(', ')} are required together")
            }
        }

        def genotype_format = populated_groups.size() == 1 ? populated_groups.keySet().first() : null
        def genotype_files = genotype_format ? groups[genotype_format].collect { column -> files[column] } : []

        //
        // Cross-row: every row on one cohort must describe the same genotypes, so a copy-paste
        // error in one row cannot silently apply another cohort's data.
        //
        if (genotype_format && genotype_files.every { genotype_file -> genotype_file }) {
            def cohort_source = [genotype_format, genotype_files.collect { genotype_file -> genotype_file.toString() }]
            def known_source = source_by_cohort_id[meta.cohort]
            if (known_source && known_source.source != cohort_source) {
                reject('cohort_id', "rows sharing cohort_id '${meta.cohort}' declare different genotype sources, row ${known_source.line} declares ${known_source.source[0]} '${known_source.source[1].first()}'")
            }
            else if (!known_source) {
                source_by_cohort_id[meta.cohort] = [line: line, source: cohort_source]
            }
        }

        //
        // Trait type drives the case, control and prevalence columns. It is the canonical trait
        // classification and is never inferred from the values or from prevalence.
        //
        def is_binary = meta.trait_type == 'binary'
        if (is_binary) {
            if (!case_value) {
                reject('case_value', "a binary trait must declare the value used for cases in the phenotype file")
            }
            if (!control_value) {
                reject('control_value', "a binary trait must declare the value used for controls in the phenotype file")
            }
        }
        else {
            if (case_value) {
                reject('case_value', "case_value has no meaning on a quantitative trait, remove it or set trait_type to 'binary'")
            }
            if (control_value) {
                reject('control_value', "control_value has no meaning on a quantitative trait, remove it or set trait_type to 'binary'")
            }
            if (population_prevalence) {
                reject('population_prevalence', "prevalence has no meaning on a quantitative trait, remove it or set trait_type to 'binary'")
            }
            if (sample_prevalence) {
                reject('sample_prevalence', "prevalence has no meaning on a quantitative trait, remove it or set trait_type to 'binary'")
            }
        }
        if (sample_prevalence && !population_prevalence) {
            reject('sample_prevalence', "a sample prevalence corrects ascertainment against a population prevalence, which this row does not declare")
        }

        //
        // The eleven columns whose validity depends on membership of the comma-delimited method
        // selector lists. The two selectors are checked above against their own vocabularies; the
        // nine that follow are consumed by particular methods only, so populating one without
        // selecting its consumer is a typo rather than a harmless no-op, and leaving one empty when
        // its consumer is selected is an under-specified analysis.
        //
        if (population_prevalence && !heritability_methods) {
            reject('population_prevalence', "prevalence is consumed by the heritability methods only, and none are selected on this row")
        }
        if (!population_prevalence && heritability_methods.contains('ldak_pcgc')) {
            reject('population_prevalence', "'ldak_pcgc' always estimates on the liability scale and requires a population prevalence")
        }
        if (sample_prevalence && !heritability_methods) {
            reject('sample_prevalence', "prevalence is consumed by the heritability methods only, and none are selected on this row")
        }
        if (ldak_model != 'human_default' && !runs_ldak_heritability) {
            reject('ldak_model', "the LDAK kinship model is consumed by the LDAK heritability methods only, and none are selected on this row")
        }
        if (ldak_model == 'human_default' && ldak_power != -0.25) {
            reject('ldak_power', "the documented human model fixes the power at -0.25, set ldak_model to 'custom' to supply your own")
        }
        if (ldak_power != -0.25 && !runs_ldak_heritability) {
            reject('ldak_power', "the LDAK kinship power is consumed by the LDAK heritability methods only, and none are selected on this row")
        }
        if (ldak_relatedness_filter && !runs_ldak_heritability) {
            reject('ldak_relatedness_filter', "the relatedness filter is consumed by the LDAK heritability methods only, and none are selected on this row")
        }
        if (kvik_step1_subset && !runs_ldak_kvik) {
            reject('ldak_kvik_step1_subset', "the KVIK step 1 subset control is consumed by 'ldak_kvik' only, which is not selected on this row")
        }
        if (!kvik_step1_subset && runs_ldak_kvik) {
            reject('ldak_kvik_step1_subset', "'ldak_kvik' is selected but no step 1 predictor subset is declared, there is no implicit resolution")
        }
        if (files.ldak_kvik_step1_extract && !runs_ldak_kvik) {
            reject('ldak_kvik_step1_extract', "a KVIK step 1 extract file is consumed by 'ldak_kvik' only, which is not selected on this row")
        }
        if (files.ldak_kvik_step1_extract && kvik_step1_subset != 'provided') {
            reject('ldak_kvik_step1_extract', "a KVIK step 1 extract file is only accepted when ldak_kvik_step1_subset is 'provided', this row declares '${kvik_step1_subset ?: ''}'")
        }
        if (kvik_step1_subset == 'provided' && !files.ldak_kvik_step1_extract) {
            reject('ldak_kvik_step1_extract', "ldak_kvik_step1_subset is 'provided' but no extract file is supplied")
        }
        if (gcta_grm_parts && !runs_gcta) {
            reject('gcta_grm_parts', "the GCTA relatedness matrix part count is consumed by the GCTA methods only, and none are selected on this row")
        }
        if (!gcta_grm_parts && runs_gcta) {
            reject('gcta_grm_parts', "a GCTA method is selected but no relatedness matrix part count is declared")
        }
        if (maf_edges && !runs_greml_ldms) {
            reject('gcta_ldms_maf_edges', "MAF bin edges are consumed by 'gcta_greml_ldms' only, which is not selected on this row")
        }
        if (!maf_edges && runs_greml_ldms) {
            reject('gcta_ldms_maf_edges', "'gcta_greml_ldms' is selected but no semicolon-delimited MAF bin edges are supplied")
        }

        def parsed_maf_edges = maf_edges ? maf_edges.toString().tokenize(';').collect { edge -> edge.trim() as BigDecimal } : []
        if (parsed_maf_edges != parsed_maf_edges.toSorted() || parsed_maf_edges.unique(false).size() != parsed_maf_edges.size()) {
            reject('gcta_ldms_maf_edges', "MAF bin edges must be strictly increasing, got '${maf_edges}'")
        }

        validated_rows << [
            meta + [
                association_methods: association_methods,
                heritability_methods: heritability_methods,
                genotype_format: genotype_format,
                is_binary: is_binary,
                // Case and control source values are carried as strings throughout: real phenotype
                // files use numeric and textual conventions alike, and nothing downstream compares
                // them numerically.
                case_value: case_value?.toString(),
                control_value: control_value?.toString(),
                population_prevalence: population_prevalence,
                sample_prevalence: sample_prevalence,
                ldak_model: ldak_model,
                ldak_power: ldak_power,
                ldak_relatedness_filter: ldak_relatedness_filter,
                ldak_kvik_step1_subset: kvik_step1_subset,
                gcta_grm_parts: gcta_grm_parts,
                gcta_ldms_maf_edges: parsed_maf_edges,
            ],
            genotype_files,
            files.phenotype,
            files.quant_covariates,
            files.cat_covariates,
            files.ldak_kvik_step1_extract,
        ]
    }

    if (errors) {
        error("Validation of samplesheet failed!\n\nThe following errors have been detected in ${samplesheet}:\n\n${errors.join('\n')}\n")
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
    def citation_text = [
            "Tools used in the workflow included:",
            "MultiQC (Ewels et al. 2016)",
            "."
        ].join(' ').trim()

    return citation_text
}

def toolBibliographyText() {
    // TODO nf-core: Optionally add bibliographic entries to this list.
    // Can use ternary operators to dynamically construct based conditions, e.g. params["run_xyz"] ? "<li>Author (2023) Pub name, Journal, DOI</li>" : "",
    // Uncomment function in methodsDescriptionText to render in MultiQC report
    def reference_text = [
            "<li>Ewels, P., Magnusson, M., Lundin, S., & Käller, M. (2016). MultiQC: summarize analysis results for multiple tools and samples in a single report. Bioinformatics , 32(19), 3047–3048. doi: /10.1093/bioinformatics/btw354</li>"
        ].join(' ').trim()

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
    } else meta["doi_text"] = ""
    meta["nodoi_text"] = meta.manifest_map.doi ? "" : "<li>If available, make sure to update the text to include the Zenodo DOI of version of the pipeline used. </li>"

    // Tool references
    meta["tool_citations"] = ""
    meta["tool_bibliography"] = ""

    // TODO nf-core: Only uncomment below if logic in toolCitationText/toolBibliographyText has been filled!
    // meta["tool_citations"] = toolCitationText().replaceAll(", \\.", ".").replaceAll("\\. \\.", ".").replaceAll(", \\.", ".")
    // meta["tool_bibliography"] = toolBibliographyText()


    def methods_text = mqc_methods_yaml.text

    def engine =  new groovy.text.SimpleTemplateEngine()
    def description_html = engine.createTemplate(methods_text).make(meta)

    return description_html.toString()
}
