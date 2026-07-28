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
// Accepted heritability method tokens for the `heritability_methods` column.
//
def heritabilityMethodTokens() {
    return ['gcta_greml', 'gcta_greml_ldms', 'ldak_reml', 'ldak_he', 'ldak_pcgc']
}

//
// The three mutually exclusive genotype groups, each mapped to the columns that make it complete.
// `vcf_index` is deliberately absent: it is declared on the samplesheet for completeness but the
// pipeline converts the VCF itself and never reads the index, so requiring it would reject valid input.
//
def genotypeGroups() {
    return [
        plink2: ['pgen', 'pvar', 'psam'],
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
        'pvar',
        'psam',
        'bed',
        'bim',
        'fam',
        'vcf',
        'vcf_index',
        'pheno_file',
        'qcovar_file',
        'covar_file',
        'kvik_extract_file',
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
// into `[ meta, genotype_files, pheno_file, qcovar_file, covar_file, kvik_extract_file ]`.
//
// Every error names the samplesheet row it came from and the column it is about, so a large
// samplesheet can be fixed without bisecting it. All errors are collected and reported together
// rather than failing on the first one.
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
        // Method selectors. Membership in these two lists is what makes eleven further columns
        // meaningful or meaningless, so they are resolved first.
        //
        def association_methods = tokenizeMethodSelector(meta.association_methods)
        def heritability_methods = tokenizeMethodSelector(meta.heritability_methods)

        def unknown_association = association_methods.findAll { method -> !association_vocabulary.contains(method) }
        if (unknown_association) {
            reject('association_methods', "unknown method${unknown_association.size() > 1 ? 's' : ''} ${unknown_association.collect { method -> "'${method}'" }.join(', ')}, accepted values are ${association_vocabulary.collect { method -> "'${method}'" }.join(', ')}")
        }
        def unknown_heritability = heritability_methods.findAll { method -> !heritability_vocabulary.contains(method) }
        if (unknown_heritability) {
            reject('heritability_methods', "unknown method${unknown_heritability.size() > 1 ? 's' : ''} ${unknown_heritability.collect { method -> "'${method}'" }.join(', ')}, accepted values are ${heritability_vocabulary.collect { method -> "'${method}'" }.join(', ')}")
        }
        if (!association_methods && !heritability_methods) {
            reject('association_methods', "row selects no method, populate 'association_methods' or 'heritability_methods' or remove the row")
        }

        // The LDAK model and power defaults, and the KVIK subset and GCTA partition defaults, are
        // samplesheet column defaults rather than pipeline parameters. nf-schema fills them in when
        // the column is present, but a samplesheet may omit the column altogether, so they are
        // resolved here as well before anything is compared against them.
        def ldak_model = cellValue(meta.ldak_model) ?: 'ldak'
        def ldak_power = cellValue(meta.ldak_power) != null ? meta.ldak_power : -0.25
        def kvik_subset = cellValue(meta.kvik_subset) ?: 'all'
        def gcta_grm_parts = cellValue(meta.gcta_grm_parts) != null ? meta.gcta_grm_parts : 1
        def population_prevalence = cellValue(meta.population_prevalence)
        def sample_prevalence = cellValue(meta.sample_prevalence)
        def case_value = cellValue(meta.case_value)
        def control_value = cellValue(meta.control_value)
        def ldms_maf_edges = cellValue(meta.ldms_maf_edges)

        def runs_ldak_kvik = association_methods.contains('ldak_kvik')
        def runs_ldak_heritability = heritability_methods.any { method -> method in ['ldak_reml', 'ldak_he', 'ldak_pcgc'] }
        def runs_ldak = runs_ldak_kvik || runs_ldak_heritability
        def runs_gcta_grm = association_methods.contains('gcta_fastgwa') || heritability_methods.any { method -> method in ['gcta_greml', 'gcta_greml_ldms'] }
        def runs_greml_ldms = heritability_methods.contains('gcta_greml_ldms')

        //
        // Genotype groups: exactly one, populated completely.
        //
        def populated_groups = groups.findAll { _name, columns -> columns.any { column -> files[column] } }
        if (!populated_groups) {
            reject('pgen', "no genotype group populated, supply exactly one of pgen/pvar/psam, bed/bim/fam or vcf")
        }
        else if (populated_groups.size() > 1) {
            def extra_groups = populated_groups.keySet().toList().tail()
            extra_groups.each { name ->
                def populated_column = groups[name].find { column -> files[column] }
                reject(populated_column, "a second genotype group is populated on this row, supply exactly one of pgen/pvar/psam, bed/bim/fam or vcf")
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
        // Trait type drives the case/control and prevalence columns.
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

        //
        // The eleven columns whose validity depends on membership of the method selector lists.
        // `association_methods` and `heritability_methods` are checked above; the nine that follow
        // are only consumed by particular methods, so populating them without selecting the
        // consuming method is a typo rather than a harmless no-op.
        //
        if (population_prevalence && !heritability_methods) {
            reject('population_prevalence', "prevalence is only consumed by the heritability methods, none are selected on this row")
        }
        if (sample_prevalence && !heritability_methods) {
            reject('sample_prevalence', "prevalence is only consumed by the heritability methods, none are selected on this row")
        }
        if (ldak_model != 'ldak' && !runs_ldak) {
            reject('ldak_model', "the LDAK kinship model is only consumed by the LDAK methods, none are selected on this row")
        }
        if (ldak_power != -0.25 && !runs_ldak) {
            reject('ldak_power', "the LDAK kinship power is only consumed by the LDAK methods, none are selected on this row")
        }
        if (cellValue(meta.ldak_relatedness_filter) && !runs_ldak_heritability) {
            reject('ldak_relatedness_filter', "the relatedness filter is only consumed by the LDAK heritability methods, none are selected on this row")
        }
        if (kvik_subset != 'all' && !runs_ldak_kvik) {
            reject('kvik_subset', "the KVIK step 1 subset control is only consumed by 'ldak_kvik', which is not selected on this row")
        }
        if (files.kvik_extract_file && !runs_ldak_kvik) {
            reject('kvik_extract_file', "a KVIK extract file is only consumed by 'ldak_kvik', which is not selected on this row")
        }
        if (files.kvik_extract_file && kvik_subset != 'provided') {
            reject('kvik_extract_file', "a KVIK extract file is only accepted when kvik_subset is 'provided', this row declares '${kvik_subset}'")
        }
        if (kvik_subset == 'provided' && !files.kvik_extract_file) {
            reject('kvik_extract_file', "kvik_subset is 'provided' but no extract file is supplied")
        }
        if (gcta_grm_parts != 1 && !runs_gcta_grm) {
            reject('gcta_grm_parts', "the GCTA relatedness matrix part count is only consumed by the GCTA methods, none are selected on this row")
        }
        if (ldms_maf_edges && !runs_greml_ldms) {
            reject('ldms_maf_edges', "MAF bin edges are only consumed by 'gcta_greml_ldms', which is not selected on this row")
        }
        if (!ldms_maf_edges && runs_greml_ldms) {
            reject('ldms_maf_edges', "'gcta_greml_ldms' is selected but no semicolon-delimited MAF bin edges are supplied")
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
                ldak_relatedness_filter: cellValue(meta.ldak_relatedness_filter) ? true : false,
                kvik_subset: kvik_subset,
                gcta_grm_parts: gcta_grm_parts,
                ldms_maf_edges: ldms_maf_edges ? ldms_maf_edges.toString().tokenize(';').collect { edge -> edge.trim() as BigDecimal } : [],
            ],
            genotype_files,
            files.pheno_file,
            files.qcovar_file,
            files.covar_file,
            files.kvik_extract_file,
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
