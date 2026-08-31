/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
// MODULE: Local to the pipeline
include { PREPARE_PHENOTYPE_INPUTS           } from '../modules/local/prepare_phenotype_inputs/main'

// SUBWORKFLOW: Consisting of a mix of local and nf-core/modules
include { PREPARE_COHORT_GENOTYPES           } from '../subworkflows/local/prepare_cohort_genotypes'
include { PREPARE_RELATEDNESS_MATRICES       } from '../subworkflows/local/prepare_relatedness_matrices'
include { ROUTE_ASSOCIATION_ANALYSES         } from '../subworkflows/local/route_association_analyses'
include { ROUTE_GRM_HERITABILITY             } from '../subworkflows/local/route_grm_heritability'
include { ROUTE_GCTA_BIVARIATE_RELATIONSHIPS } from '../subworkflows/local/route_gcta_bivariate_relationships'
include { ROUTE_CANONICAL_SUMMARY_STATISTICS } from '../subworkflows/local/route_canonical_summary_statistics'
include { ROUTE_LDAK_SUMMARY_ANALYSES        } from '../subworkflows/local/route_ldak_summary_analyses'
include { ROUTE_LDSC_SUMMARY_ANALYSES        } from '../subworkflows/local/route_ldsc_summary_analyses'
include { ROUTE_GWAS_REPORTING               } from '../subworkflows/local/route_gwas_reporting'
include { getGwaslabReferences               } from '../subworkflows/local/utils_nfcore_gwas_pipeline'

// SUBWORKFLOW: Consisting entirely of nf-core/modules
include { softwareVersionsToYAML             } from '../subworkflows/nf-core/utils_nfcore_pipeline'

// PLUGIN
include { paramsSummaryMap                   } from 'plugin/nf-schema'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow GWAS {
    take:
    ch_analyses // channel: [ val(meta), [ path(genotype_file), ... ], path(phenotype), path(quant_covariates), path(cat_covariates), path(kvik_extract), path(ldak_weights) ]
    ch_external_summary_statistics // channel: [ val(meta), path(source) ]
    ch_relationships // channel: [ val(meta), [ path(genotype_file), ... ], path(pair_quant_covariates), path(pair_cat_covariates) ]
    ch_unary_requests // channel: [ val(meta), path(hapmap3_snplist), path(reference_ld_scores), path(regression_weights), path(tagging_file) ]
    ch_pair_requests // channel: [ val(meta), path(hapmap3_snplist), path(reference_ld_scores), path(regression_weights), path(tagging_file) ]
    multiqc_config // channel: val(multiqc_config)
    multiqc_logo // channel: val(multiqc_logo)
    multiqc_methods_description // channel: val(multiqc_methods_description)
    outdir // channel: val(outdir)

    main:

    // This is the pipeline spine and owns exactly ten things: the public `take:` contract above, run-level
    // analysis and method metadata, the union of genotype consumers and their single preparation, the union
    // of relatedness-matrix consumers and their single preparation, phenotype preparation plus the
    // tool-neutral per-analysis seams derived from it, the route-controller calls and the dependencies
    // between their semantic results, the fan-out of GWASLab-standard summaries to the summary-scale routes,
    // run-wide version collection and collation, the reporting call, and the public `emit:` block below.
    //
    // Every route controller is a pipeline-owned subworkflow that receives all configuration values and
    // resources explicitly through its own `take:`. None of them reads `params`, `workflow` or `projectDir`,
    // and none of them owns a shared resource, the validation contract, or a public emission.
    //
    //   ch_analyses / ch_relationships
    //          |
    //          v
    //   PREPARE_COHORT_GENOTYPES ---> PREPARE_RELATEDNESS_MATRICES     PREPARE_PHENOTYPE_INPUTS
    //          |                                |                              |
    //          +--------------------------------+------------------------------+   shared resources,
    //          |                                |                              |   each built once
    //          v                                v                              v
    //   ROUTE_ASSOCIATION_ANALYSES     ROUTE_GRM_HERITABILITY     ROUTE_GCTA_BIVARIATE_RELATIONSHIPS
    //          |
    //          | association_results                        ch_external_summary_statistics
    //          v                                                         |
    //   ROUTE_CANONICAL_SUMMARY_STATISTICS <---------------------------- +
    //          |
    //          | summary_statistics (GWASLab convergence point)
    //          +--> ROUTE_LDAK_SUMMARY_ANALYSES
    //          +--> ROUTE_LDSC_SUMMARY_ANALYSES
    //          +--> SIBLING SEAM: a future meta-analysis route attaches here (issue #9)
    //
    //   channel.topic('versions') --> softwareVersionsToYAML --> ROUTE_GWAS_REPORTING --> multiqc_report

    //
    // Run-level analysis and method metadata for the report
    //
    // Both are materialised here rather than in the reporting controller because they describe the whole run
    // as validation admitted it, across all four request domains, and no single route can see that union.
    def ch_analysis_metadata = ch_analyses
        .map { meta, _genotype_files, _phenotype, _quant_covariates, _cat_covariates, _kvik_extract, _ldak_weights -> meta }
        .collect()
    def ch_method_metadata = ch_analyses
        .map { meta, _genotype_files, _phenotype, _quant_covariates, _cat_covariates, _kvik_extract, _ldak_weights -> [domain: 'analysis', meta: meta] }
        .mix(
            ch_relationships.map { meta, _genotype_files, _pair_quant_covariates, _pair_cat_covariates -> [domain: 'pairwise', meta: meta] }
        )
        .mix(
            ch_unary_requests.map { meta, _hapmap3_snplist, _reference_ld_scores, _regression_weights, _tagging_file -> [domain: 'summary_unary', meta: meta] }
        )
        .mix(
            ch_pair_requests.map { meta, _hapmap3_snplist, _reference_ld_scores, _regression_weights, _tagging_file -> [domain: 'pairwise', meta: meta] }
        )
        .collect()

    //
    // Union of the genotype consumers across every request domain
    //
    // One element per analysis unit carrying the genotype files it declared. A pairwise LDMS request is
    // also a consumer of the cohort's lazy PLINK 1 derivative, so it enters this request stream without
    // inheriting either endpoint's unary method settings. Cohort preparation collapses every request to
    // the distinct cohort before conversion.
    def ch_genotype_requests = ch_analyses.map { meta, genotype_files, _phenotype, _quant_covariates, _cat_covariates, _kvik_extract, _ldak_weights ->
        [meta, genotype_files]
    }
    ch_genotype_requests = ch_genotype_requests.mix(
        ch_relationships.filter { meta, _genotype_files, _pair_quant_covariates, _pair_cat_covariates -> meta.matrix_kind == 'gcta_ldms' }.map { meta, genotype_files, _pair_quant_covariates, _pair_cat_covariates -> [meta, genotype_files] }
    )

    //
    // Union of the relatedness-matrix consumers across every request domain
    //
    // Matrix preparation additionally receives the optional LDAK weights Path. It derives identity from the
    // bytes before request deduplication and keeps the Path outside matrix metadata and the published key.
    def ch_relatedness_analyses = ch_analyses.map { meta, genotype_files, _phenotype, _quant_covariates, _cat_covariates, _kvik_extract, ldak_weights ->
        [meta, genotype_files, ldak_weights ?: []]
    }
    ch_relatedness_analyses = ch_relatedness_analyses.mix(
        ch_relationships.map { meta, genotype_files, _pair_quant_covariates, _pair_cat_covariates -> [meta, genotype_files, []] }
    )

    //
    // SUBWORKFLOW: Prepare each distinct cohort's genotypes once into the canonical PLINK 2 bundle
    //
    PREPARE_COHORT_GENOTYPES(ch_genotype_requests)

    //
    // SUBWORKFLOW: Build each distinct relatedness matrix once and fan it out per analysis unit
    //
    PREPARE_RELATEDNESS_MATRICES(
        ch_relatedness_analyses,
        PREPARE_COHORT_GENOTYPES.out.cohort_genotypes,
        PREPARE_COHORT_GENOTYPES.out.plink1_genotypes,
        params.gcta_grm_parts,
    )

    //
    // MODULE: Prepare each analysis unit's phenotype and covariates in the shared tool-compatible layout
    //
    PREPARE_PHENOTYPE_INPUTS(
        ch_analyses.map { meta, _genotype_files, phenotype, quant_covariates, cat_covariates, _kvik_extract, _ldak_weights ->
            [meta, phenotype, quant_covariates, cat_covariates]
        }
    )

    // GCTA and LDAK reject a header row. LDAK-KVIK, fastGWA and every individual-level GRM heritability
    // estimator therefore consume the headerless phenotype and covariate serialisations. This one prepared
    // stream is built here because it has consumers in more than one route, and is passed to the association
    // and heritability controllers explicitly. Optional covariates are represented by [], which stages nothing.
    def ch_gcta_phenotypes = PREPARE_PHENOTYPE_INPUTS.out.phenotype_headerless
        .join(PREPARE_PHENOTYPE_INPUTS.out.quant_covariates_headerless, remainder: true)
        .join(PREPARE_PHENOTYPE_INPUTS.out.cat_covariates_headerless, remainder: true)
        .map { meta, phenotype, quant_covariates, cat_covariates ->
            [meta, phenotype, quant_covariates ?: [], cat_covariates ?: []]
        }

    //
    // SUBWORKFLOW: Pipeline route for PLINK 2, REGENIE, LDAK-KVIK and GCTA fastGWA associations
    //
    // Cohort genotype preparation, relatedness-matrix construction and phenotype preparation stay above on
    // the spine so each shared resource is built once and fanned out to every consumer across every domain.
    // The controller owns association-method selection, the adaptation of those prepared streams into each
    // family's native call shape, the two prediction-reusing routes, and the fan-in of four native result
    // contracts onto one raw-association stream naming the producing method.
    //
    // The declared optional LDAK predictor list is narrowed out of the validated relational row here, because
    // reading that row is spine knowledge; which analyses want it, and what its content identity contributes
    // to the Step 1 reuse key, is the controller's. An absent file is [] and stages nothing.
    ROUTE_ASSOCIATION_ANALYSES(
        PREPARE_COHORT_GENOTYPES.out.genotypes,
        PREPARE_COHORT_GENOTYPES.out.plink1_genotypes,
        PREPARE_PHENOTYPE_INPUTS.out.phenotype,
        PREPARE_PHENOTYPE_INPUTS.out.covariates,
        ch_gcta_phenotypes,
        PREPARE_RELATEDNESS_MATRICES.out.gcta_sparse,
        ch_analyses.map { meta, _genotype_files, _phenotype, _quant_covariates, _cat_covariates, kvik_extract, _ldak_weights ->
            [meta, kvik_extract ?: []]
        },
        params.regenie_step2_bsize,
        params.regenie_step1_mode,
        params.regenie_step1_jobs,
    )

    //
    // SUBWORKFLOW: Pipeline route for individual-level GRM heritability, GCTA GREML/GREML-LDMS and LDAK REML/HE/PCGC
    //
    // Relatedness-matrix construction stays above on the spine so each scientifically distinct matrix is built
    // once and fanned out to every consumer across every domain — this controller and the bivariate
    // relationship controller below both consume matrices built by PREPARE_RELATEDNESS_MATRICES. The
    // controller owns estimator selection, the adaptation of the prepared matrix and headerless phenotype
    // streams into each family's native call shape, and the adjustment-covariate routing only LDAK needs.
    // GCTA and LDAK keep separate native result contracts and are never merged into one heritability table.
    //
    // The two GCTA matrix streams are narrowed to the unary analysis rows here, mirroring the
    // relationship-scoped narrowing the bivariate route below does, so the controller never sees a
    // relationship matrix. An LDAK kinship matrix is only ever requested by a unary heritability method, so
    // that stream is passed as PREPARE_RELATEDNESS_MATRICES emits it.
    ROUTE_GRM_HERITABILITY(
        PREPARE_RELATEDNESS_MATRICES.out.gcta_dense.filter { meta, _grm_files -> !meta.relationship_id },
        PREPARE_RELATEDNESS_MATRICES.out.gcta_ldms.filter { meta, _grm_files, _grm_prefixes -> !meta.relationship_id },
        PREPARE_RELATEDNESS_MATRICES.out.ldak_kinship,
        ch_gcta_phenotypes,
        PREPARE_PHENOTYPE_INPUTS.out.adjustment_covariates,
    )

    //
    // SUBWORKFLOW: Pipeline route for GCTA bivariate REML and REML-LDMS relationship requests
    //
    // Individual-level relationships are their own domain, disjoint from the summary-statistics pair requests
    // routed below. Dense and LDMS share one controller because they share the relationship definition, the
    // endpoint resolution against the prepared phenotypes and the bivariate trait table built from them. The
    // spine keeps matrix and phenotype preparation; the controller owns relationship
    // de-duplication, declared orientation, preparation reuse and native identity. The matrix
    // streams are narrowed to the relationship-scoped rows here, mirroring the unary narrowing above, so the
    // controller never sees a unary analysis matrix.
    ROUTE_GCTA_BIVARIATE_RELATIONSHIPS(
        ch_relationships,
        PREPARE_PHENOTYPE_INPUTS.out.phenotype_headerless,
        PREPARE_RELATEDNESS_MATRICES.out.gcta_dense.filter { meta, _grm_files -> meta.relationship_id },
        PREPARE_RELATEDNESS_MATRICES.out.gcta_ldms.filter { meta, _grm_files, _grm_prefixes -> meta.relationship_id },
    )

    //
    // SUBWORKFLOW: Pipeline route for GWASLab-standard summary statistics from every origin
    //
    // The single convergence point of the summary-statistics half of the pipeline: it takes the raw
    // association results produced above and the externally supplied sources from the validated manifest, and
    // emits one GWASLab result per summary_statistics_id. The controller owns the internal producer metadata
    // and producer-specific GWASLab mappings. The spine keeps the seam between the association
    // controller above and the fan-out below, and resolves the build-keyed GWASLab resources here because
    // they are pipeline parameters rather than request-owned references.
    def gwaslab_references = getGwaslabReferences()

    ROUTE_CANONICAL_SUMMARY_STATISTICS(
        ROUTE_ASSOCIATION_ANALYSES.out.association_results,
        ch_external_summary_statistics,
        gwaslab_references,
    )

    //
    // SUBWORKFLOW: Pipeline route for LDAK SumHer and SumCors from GWASLab-standard summary statistics
    //
    // First sibling on the summary-statistics fan-out. Both summary-scale LDAK methods share one
    // controller because they share the GWASLab-to-LDAK preparation and the endpoint resolution that feeds
    // it. The spine selects the route; the controller owns preparation reuse, ordered pair resolution,
    // native-argument and runtime policy, and native outputs. It receives the full validated request tuple so
    // the reference-bundle convention stays request-owned rather than becoming spine knowledge.
    def ch_sumher_requests = ch_unary_requests.filter { meta, _hapmap3_snplist, _reference_ld_scores, _regression_weights, _tagging_file -> meta.method == 'ldak_sumher' }
    def ch_sumcors_requests = ch_pair_requests.filter { meta, _hapmap3_snplist, _reference_ld_scores, _regression_weights, _tagging_file -> meta.method == 'ldak_sumcors' }

    ROUTE_LDAK_SUMMARY_ANALYSES(
        ch_sumher_requests,
        ch_sumcors_requests,
        ROUTE_CANONICAL_SUMMARY_STATISTICS.out.summary_statistics,
    )

    //
    // SUBWORKFLOW: Pipeline route for standalone CBIIT Python 3 LDSC munging, H2 and RG
    //
    // Second sibling on the summary-statistics fan-out. Both summary-scale LDSC methods share one
    // controller because they share the content-addressed munging that feeds them: a GWASLab summary
    // consumed by a unary H2 request and by either side of any number of RG requests is munged exactly once.
    // The spine selects the route; the controller owns the munging reuse identity, endpoint resolution in
    // declared pair order, observed- and liability-scale selection, and native logs. It
    // receives the full validated request tuple so the reference-bundle convention stays request-owned rather
    // than becoming spine knowledge.
    def ch_ldsc_h2_requests = ch_unary_requests.filter { meta, _hapmap3_snplist, _reference_ld_scores, _regression_weights, _tagging_file -> meta.method == 'ldsc_h2' }
    def ch_ldsc_rg_requests = ch_pair_requests.filter { meta, _hapmap3_snplist, _reference_ld_scores, _regression_weights, _tagging_file -> meta.method == 'ldsc_rg' }

    ROUTE_LDSC_SUMMARY_ANALYSES(
        ch_ldsc_h2_requests,
        ch_ldsc_rg_requests,
        ROUTE_CANONICAL_SUMMARY_STATISTICS.out.summary_statistics,
    )

    // SIBLING SEAM — a future meta-analysis route (GitHub issue lyh970817/gwas#9) attaches here.
    //
    // ROUTE_LDAK_SUMMARY_ANALYSES and ROUTE_LDSC_SUMMARY_ANALYSES are siblings, not a chain: each reads
    // ROUTE_CANONICAL_SUMMARY_STATISTICS.out.summary_statistics independently and neither observes the other.
    // A meta-analysis route is the same kind of sibling and attaches at this point, after GWASLab
    // convergence and after the two existing consumers, by the same three-part pattern they both follow:
    //
    //   1. Select the route on the spine by filtering the validated request stream that carries it — for a
    //      meta-analysis request that is a pair- or set-scoped stream reaching GWAS through `take:`, filtered
    //      on `meta.method` exactly as the two blocks above filter theirs. The spine narrows; it does not
    //      interpret the request.
    //   2. Call ROUTE_META_ANALYSIS(<selected requests>, ROUTE_CANONICAL_SUMMARY_STATISTICS.out.summary_statistics,
    //      <any explicit configuration values>). Pass the GWASLab-standard stream unmodified: it is a plain queue
    //      channel and a third reader adds no barrier, no reuse change and no cardinality change to the two
    //      existing readers. Do not insert a collect()/groupTuple() here to materialise it for the new route.
    //   3. Let the controller own everything downstream of that seam — endpoint resolution, per-cohort
    //      preparation and its reuse identity, native meta-analysis invocation, and model-specific outputs.
    //
    // Nothing else on this spine changes: the union channels, the shared-resource preparations, the version
    // topic and the public `emit:` block below are all independent of how many summary consumers exist. If a
    // meta-analysed output must itself become a pipeline summary, that is a change to
    // ROUTE_CANONICAL_SUMMARY_STATISTICS's inputs rather than a second convergence point here.

    //
    // Collate and save software versions
    //
    def ch_topic_versions = channel.topic("versions")
        .distinct()
        .branch { entry ->
            versions_file: entry instanceof Path
            versions_tuple: true
        }

    def ch_topic_versions_string = ch_topic_versions.versions_tuple
        .map { process, tool, version ->
            [process[process.lastIndexOf(':') + 1..-1], "  ${tool}: ${version}"]
        }
        .groupTuple(by: 0)
        .map { process, tool_versions ->
            tool_versions.unique().sort()
            "${process}:\n${tool_versions.join('\n')}"
        }

    def ch_collated_versions = softwareVersionsToYAML(ch_topic_versions.versions_file)
        .mix(ch_topic_versions_string)
        .collectFile(
            storeDir: "${outdir}/pipeline_info",
            name: 'nf_core_' + 'gwas_software_' + 'mqc_' + 'versions.yml',
            sort: true,
            newLine: true,
        )

    //
    // SUBWORKFLOW: Render the run report from the analysis plan, workflow summary, methods description and versions
    //
    // The reporting controller owns MultiQC assembly but reads no parent scope: the run parameter summary is
    // evaluated here and every pipeline-default asset is resolved here, then passed in explicitly.
    def summary_params = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")
    ROUTE_GWAS_REPORTING(
        ch_collated_versions,
        ch_analysis_metadata,
        ch_method_metadata,
        summary_params,
        multiqc_config,
        multiqc_logo,
        multiqc_methods_description,
        file("${projectDir}/assets/multiqc_analysis_plan.yml", checkIfExists: true),
        file("${projectDir}/assets/multiqc_config.yml", checkIfExists: true),
        file("${projectDir}/assets/nf-core-gwas_logo_light.png", checkIfExists: true),
        file("${projectDir}/assets/methods_description_template.yml", checkIfExists: true),
    )

    emit:
    summary_statistics  = ROUTE_CANONICAL_SUMMARY_STATISTICS.out.summary_statistics // channel: [ val(meta), path(gwaslab_summary_statistics) ]
    multiqc_report      = ROUTE_GWAS_REPORTING.out.report.toList() // channel: [ [ path(report) ] ]
    gcta_ldms_artifacts = PREPARE_RELATEDNESS_MATRICES.out.gcta_ldms_artifacts // channel: [ val(matrix_meta), path(grm_files), val(grm_prefixes) ], one per base key
}
