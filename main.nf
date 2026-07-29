#!/usr/bin/env nextflow
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    nf-core/gwas
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Github : https://github.com/nf-core/gwas
    Website: https://nf-co.re/gwas
    Slack  : https://nfcore.slack.com/channels/gwas
----------------------------------------------------------------------------------------
*/

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT FUNCTIONS / MODULES / SUBWORKFLOWS / WORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { GWAS  } from './workflows/gwas'
include { PIPELINE_INITIALISATION } from './subworkflows/local/utils_nfcore_gwas_pipeline'
include { PIPELINE_COMPLETION     } from './subworkflows/local/utils_nfcore_gwas_pipeline'
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    NAMED WORKFLOWS FOR PIPELINE
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// WORKFLOW: Run main analysis pipeline depending on type of input
//
workflow NFCORE_GWAS {

    take:
    samplesheet // channel: samplesheet read in from --input

    main:

    //
    // WORKFLOW: Run pipeline
    //
    GWAS (
        samplesheet,
        params.multiqc_config,
        params.multiqc_logo,
        params.multiqc_methods_description,
        params.outdir,
    )
    emit:
    multiqc_report = GWAS.out.multiqc_report // channel: /path/to/multiqc_report.html
}
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow {

    main:

    //
    // WORKFLOW: Validate a local GCTA test-fixture override
    //
    def local_gwas_fixture_root = System.getenv('GWAS_TEST_FIXTURES')
    def local_gwas_fixture_profiles = [
        'test_gcta_fastgwa',
        'test_gcta_greml_ldms',
        'test_regenie_standard',
        'test_regenie_chunked',
        'test_regenie_binary',
        'test_ldak_kvik_all',
        'test_ldak_kvik_thin_common',
        'test_ldak_kvik_provided',
        'test_ldak_kvik_binary',
        'test_ldak_reml',
        'test_ldak_relatedness_shared',
        'test_ldak_relatedness_distinct',
        'test_ldak_relatedness_same_weights',
        'test_ldak_relatedness_different_weights',
    ]
    def local_gwas_fixture_config_names = [
        'REGENIE standard Step 1 test profile',
        'REGENIE chunked Step 1 test profile',
        'REGENIE binary-trait test profile',
        'LDAK-KVIK all-predictors test profile',
        'LDAK-KVIK thin-common test profile',
        'LDAK-KVIK provided-predictors test profile',
        'LDAK-KVIK binary-trait test profile',
        'LDAK REML heritability test profile',
        'LDAK shared relatedness matrix test profile',
        'LDAK distinct relatedness matrix test profile',
        'LDAK same-weight-content test profile',
        'LDAK different-weight-content test profile',
    ]
    def local_gwas_fixture_profile_selected = workflow.profile.tokenize(',').intersect(local_gwas_fixture_profiles)
    def local_gwas_fixture_config_selected = params.config_profile_name in local_gwas_fixture_config_names
    if (local_gwas_fixture_root && (local_gwas_fixture_profile_selected || local_gwas_fixture_config_selected)) {
        def local_gwas_fixture_marker = new File(local_gwas_fixture_root, 'results/fixtures/genotypes/example_all.pgen').absoluteFile
        if (!local_gwas_fixture_marker.exists()) {
            error("[nf-core/gwas] ERROR: GWAS_TEST_FIXTURES is set to '${local_gwas_fixture_root}' but ${local_gwas_fixture_marker} does not exist")
        }
    }

    //
    // SUBWORKFLOW: Run initialisation tasks
    //
    PIPELINE_INITIALISATION (
        params.version,
        params.validate_params,
        params.monochrome_logs,
        args,
        params.outdir,
        params.input,
        params.help,
        params.help_full,
        params.show_hidden
    )

    //
    // WORKFLOW: Run main workflow
    //
    NFCORE_GWAS (
        PIPELINE_INITIALISATION.out.samplesheet
    )
    //
    // SUBWORKFLOW: Run completion tasks
    //
    PIPELINE_COMPLETION (
        params.email,
        params.email_on_fail,
        params.plaintext_email,
        params.outdir,
        params.monochrome_logs,
        NFCORE_GWAS.out.multiqc_report
    )
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
