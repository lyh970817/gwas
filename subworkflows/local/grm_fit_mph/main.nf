// Prepare IID-keyed trait/design CSVs, then fit one or more ordered native MPH GRMs.
// Callers with native-ready CSVs invoke MPH_REML directly.

include { CUSTOM_PREPAREMPHINPUTS } from '../../../modules/local/custom/preparemphinputs/main'
include { MPH_REML                } from '../../../modules/local/mph/reml/main'

workflow GRM_FIT_MPH {
    take:
    ch_inputs // channel: [ val(meta), path(grm_files), path(phenotypes), path(quant_covariates), path(cat_covariates), path(fam), val(trait_names), val(missing_tokens) ]

    main:
    def ch_preparation = ch_inputs.multiMap { meta, grm_files, phenotypes, quant_covariates, cat_covariates, fam, trait_names, missing_tokens ->
        tables: [meta, phenotypes, quant_covariates, cat_covariates, trait_names, missing_tokens]
        samples: [meta, grm_files.find { grm_file -> grm_file.name.endsWith('.grm.iid') }, fam]
    }
    CUSTOM_PREPAREMPHINPUTS(ch_preparation.tables, ch_preparation.samples)

    def ch_fit = ch_inputs
        .map { meta, grm_files, _phenotypes, _quant_covariates, _cat_covariates, _fam, trait_names, _missing_tokens -> [meta, grm_files, trait_names] }
        .join(CUSTOM_PREPAREMPHINPUTS.out.phenotype, failOnDuplicate: true, failOnMismatch: true)
        .join(CUSTOM_PREPAREMPHINPUTS.out.covariates, failOnDuplicate: true, remainder: true)
        .multiMap { meta, grm_files, trait_names, phenotype_csv, covariate_csv ->
            grm: [meta, grm_files]
            phenotype: [meta, phenotype_csv, trait_names]
            covariates: [meta, covariate_csv ?: [], covariate_csv ? covariate_csv.readLines().first().split(',').drop(1).toList() : []]
        }
    MPH_REML(ch_fit.grm, ch_fit.phenotype, ch_fit.covariates)

    emit:
    phenotype            = CUSTOM_PREPAREMPHINPUTS.out.phenotype // channel: [ val(meta), path(phenotype_csv) ]
    covariates           = CUSTOM_PREPAREMPHINPUTS.out.covariates // channel: [ val(meta), path(covariate_csv) ], absent when none supplied
    variance_components  = MPH_REML.out.variance_components // channel: [ val(meta), path(variance_components) ]
    fixed_effects        = MPH_REML.out.fixed_effects // channel: [ val(meta), path(fixed_effects) ]
    iterations           = MPH_REML.out.iterations // channel: [ val(meta), path(iterations) ]
    projected_phenotypes = MPH_REML.out.projected_phenotypes // channel: [ val(meta), path(projected_phenotypes) ]
    correlations         = MPH_REML.out.correlations // channel: [ val(meta), path(correlations) ], multi-trait fits only
    native_log           = MPH_REML.out.log // channel: [ val(meta), path(log) ]
}
