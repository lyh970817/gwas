// Route nf-core/gwas analysis records through REGENIE, batching compatible analyses into one native
// invocation and reusing scientifically identical Step 1 fits. This is pipeline-specific relational-input
// policy, not an nf-core/modules submission candidate.
// Every constituent process reports directly to the run-wide versions topic, so this subworkflow emits no versions.

// MODULE: Local to the pipeline
include { PREPARE_REGENIE_PHENOTYPES       } from '../../../modules/local/prepare_regenie_phenotypes/main'

// SUBWORKFLOW: Upstream-ready REGENIE composition used inside a pipeline-local route
include { PLINK_FIT_REGENIE                } from '../plink_fit_regenie/main'

// MODULE: Installed directly from nf-core/modules
include { REGENIE_STEP2                    } from '../../../modules/nf-core/regenie/step2/main'

// FUNCTION: Local to the pipeline
include { canonicaliseScientificIdentifier } from '../utils_nfcore_gwas_pipeline'
include { canonicaliseScientificValue      } from '../utils_nfcore_gwas_pipeline'
include { digestFileBytes                  } from '../utils_nfcore_gwas_pipeline'
include { digestIdentityText               } from '../utils_nfcore_gwas_pipeline'
include { buildCanonicalPredictionKey      } from '../utils_nfcore_gwas_pipeline'

workflow ROUTE_REGENIE_ASSOCIATIONS {
    take:
    ch_analyses // channel: [ val(meta), path(primary_genotype), path(variant_file), path(sample_file), path(phenotype), path(covariates), val(view_key) ], format-polymorphic member order, covariates is [] when absent
    step2_bsize // value: val(step2_bsize)
    step1_mode // value: val(step1_mode), 'standard' or 'chunked'
    step1_jobs // value: val(step1_jobs), use null for standard mode
    batch_size // value: val(batch_size), maximum analyses fitted and tested in one REGENIE invocation

    main:

    // One request per analysis, carrying the identity that decides which analyses may share a native
    // invocation. The keys are private routing values rather than custom meta fields; the original
    // analysis metadata stays beside every consumer and is restored at the emit.
    def ch_requests = ch_analyses.map { meta, primary, variant_file, sample_file, phenotype, covariates, view_key ->
        def step1_bsize = meta.method_options.regenie.step1_bsize
        def identity = readPhenotypeIdentity(phenotype)
        [
            compatibility: buildRegenieFitCompatibilityKey(view_key, meta.is_binary, covariates ?: [], identity.sample_set, step1_bsize),
            meta: meta,
            primary: primary,
            variant_file: variant_file,
            sample_file: sample_file,
            phenotype: phenotype,
            phenotype_digest: identity.content,
            covariates: covariates ?: [],
            step1_bsize: step1_bsize,
        ]
    }

    // Fit batches. Members are ordered by analysis id and cut into consecutive chunks of at most
    // `batch_size`, so the same manifest always yields the same batches, the same keys and the same task
    // names. A group is never closed on first arrival: every member of a compatibility class is collected
    // before any batch is formed, which is what makes membership independent of scheduling order.
    def ch_fit_batches = ch_requests
        .map { request -> [request.compatibility, request] }
        .groupTuple()
        .flatMap { compatibility_key, requests ->
            requests
                .sort { left, right -> left.meta.id <=> right.meta.id }
                .collate(batch_size)
                .collect { members -> [buildRegenieFitBatchKey(compatibility_key, members), members] }
        }
        .map { fit_batch_key, members ->
            def fit_meta = [
                id: "regenie.${fit_batch_key}",
                is_binary: members.first().meta.is_binary,
                phenotype_columns: members.collect { member -> member.meta.id },
            ]
            [fit_batch_key, fit_meta, members]
        }

    // The one multi-column phenotype file the batch shares. Its columns are named by `analysis_id`, which
    // is what REGENIE names its per-column Step 2 output files after, and therefore what makes the native
    // outputs attributable. The module re-asserts inside the task that the members really do share one
    // sample set, so a mistaken grouping fails by name instead of changing a member's science.
    PREPARE_REGENIE_PHENOTYPES(
        ch_fit_batches.map { _fit_batch_key, fit_meta, members ->
            [fit_meta, members.collect { member -> member.phenotype }, members.collect { member -> member.meta.id }]
        }
    )

    def ch_batch_phenotypes = PREPARE_REGENIE_PHENOTYPES.out.phenotype.map { fit_meta, phenotype -> [fit_meta.id, phenotype] }

    // Every member of a fit batch agrees on the genotype view, the covariate bytes and the Step 1 block
    // size, so the batch is fitted from the deterministic survivor's staged files. Two cohorts holding
    // byte-identical genotypes share one view key and therefore one fit, exactly as they did per analysis.
    def ch_fit = ch_fit_batches
        .map { _fit_batch_key, fit_meta, members -> [fit_meta.id, fit_meta, members] }
        .join(ch_batch_phenotypes, failOnDuplicate: true, failOnMismatch: true)
        .multiMap { _fit_id, fit_meta, members, batch_phenotype ->
            genotypes: [fit_meta, members.first().primary, members.first().variant_file, members.first().sample_file]
            pheno: [fit_meta, batch_phenotype]
            covar: [fit_meta, members.first().covariates]
            bsize: [fit_meta, members.first().step1_bsize]
            mode: [fit_meta, step1_mode]
            jobs: [fit_meta, step1_mode == 'chunked' ? step1_jobs : []]
        }

    PLINK_FIT_REGENIE(ch_fit.genotypes, ch_fit.pheno, ch_fit.covar, ch_fit.bsize, ch_fit.mode, ch_fit.jobs)

    // PLINK_FIT_REGENIE returns only opaque fit metadata. Reattach the private key through the fit id side
    // channel, then combine one fitted bundle with every Step 2 sub-batch that consumes it. The batch
    // phenotype travels with the bundle because Step 2 reads the same multi-column file and selects its
    // own subset of columns from it.
    def ch_fit_keys = ch_fit_batches.map { fit_batch_key, fit_meta, _members -> [fit_meta.id, fit_batch_key] }

    def ch_fit_bundles = PLINK_FIT_REGENIE.out.predictions
        .map { fit_meta, predictions ->
            validateRegenieFitPredictionCoverage(fit_meta, predictions)
            [fit_meta.id, predictions]
        }
        .join(
            PLINK_FIT_REGENIE.out.loco.map { fit_meta, loco -> [fit_meta.id, loco] },
            failOnDuplicate: true,
            failOnMismatch: true,
        )
        .join(ch_batch_phenotypes, failOnDuplicate: true, failOnMismatch: true)
        .join(ch_fit_keys, failOnDuplicate: true, failOnMismatch: true)
        .map { _fit_id, predictions, loco, batch_phenotype, fit_batch_key -> [fit_batch_key, predictions, loco, batch_phenotype] }

    // Step 2 sub-batches. REGENIE accepts a `--phenoColList` subset of the phenotypes in `--pred` and
    // returns byte-identical results for it, so the test identity can be narrower than the fit identity:
    // two analyses that differ only in an invocation-global Step 2 option (`--minMAC`, Firth) share one
    // Step 1 fit and are tested separately, instead of silently re-fitting Step 1 for a Step 2 change.
    def ch_test_batches = ch_fit_batches.flatMap { fit_batch_key, fit_meta, members ->
        members
            .groupBy { member -> canonicaliseScientificValue(getRegenieStep2Policy(member.meta)) }
            .collect { _policy, policy_members ->
                def policy = getRegenieStep2Policy(policy_members.first().meta)
                def member_ids = policy_members.collect { member -> member.meta.id }
                // `method_options` carries the effective Step 2 settings rather than one member's raw
                // option map: they are what `conf/modules/regenie.config` renders, and they are identical
                // across the sub-batch by construction, so the invocation metadata says exactly what the
                // rendered command will contain.
                def test_meta = [
                    id: "regenie.${buildRegenieTestBatchKey(fit_batch_key, policy, member_ids)}",
                    is_binary: fit_meta.is_binary,
                    phenotype_columns: member_ids,
                    method_options: [regenie: policy],
                ]
                [fit_batch_key, test_meta, policy_members]
            }
    }

    def ch_step2 = ch_test_batches
        .combine(ch_fit_bundles, by: 0)
        .multiMap { _fit_batch_key, test_meta, members, predictions, loco, batch_phenotype ->
            genotypes: [test_meta, members.first().primary, members.first().variant_file, members.first().sample_file]
            predictions: [test_meta, predictions, loco]
            pheno: [test_meta, batch_phenotype]
            covar: [test_meta, members.first().covariates]
            bsize: step2_bsize
        }

    REGENIE_STEP2(ch_step2.genotypes, ch_step2.predictions, ch_step2.pheno, ch_step2.covar, ch_step2.bsize)

    // Attribution. One invocation emits one native result per phenotype column, so each is routed back to
    // the analysis whose id named that column before anything downstream sees it.
    def ch_attributed = REGENIE_STEP2.out.results.flatMap { test_meta, results ->
        def attributed = normaliseFileList(results).collect { result -> [attributeRegenieResult(test_meta, result), result] }
        validateRegenieStep2Attribution(test_meta, attributed.collect { analysis_id, _result -> analysis_id })
        attributed
    }

    // The strict join is what guarantees exactly one result per requesting analysis and restores the
    // original analysis metadata, so no batch key or private invocation identity survives the emit.
    def ch_results = ch_analyses
        .map { meta, _primary, _variant_file, _sample_file, _phenotype, _covariates, _view_key -> [meta.id, meta] }
        .join(ch_attributed, failOnDuplicate: true, failOnMismatch: true)
        .map { _analysis_id, meta, results -> [meta, results] }

    emit:
    results = ch_results // channel: [ val(meta), path(regenie_results) ]
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

// Two identities are read out of one prepared phenotype. The content digest distinguishes batch members
// from each other and is what makes a changed trait re-fit its batch. The non-missing sample-set digest
// decides whether two analyses may share a fit at all: REGENIE mean-imputes missing observations across a
// whole invocation, so members whose missingness differs would each be fitted against a sample set they
// would not have alone. This is a grouping decision, not the guarantee -- `PREPARE_REGENIE_PHENOTYPES`
// re-checks the property inside the task and fails the batch by name if the grouping was ever wrong.
def readPhenotypeIdentity(phenotype) {
    def observed = file(phenotype)
        .readLines()
        .drop(1)
        .collect { line -> line.split('\t') }
        .findAll { fields -> fields.size() > 2 && fields[2].trim() != 'NA' }
        .collect { fields -> "${fields[0]}\t${fields[1]}" }
        .sort()
    return [
        content: digestFileBytes(phenotype),
        sample_set: digestIdentityText(observed.join('\n')),
    ]
}

// The compatibility key holds every setting that changes native execution or sample semantics and is
// shared by every member of a fit batch. The genotype view key arrives from preparation as a tuple
// member: it is the cohort's immutable native view identity, so two cohorts holding byte-identical
// genotypes share one fit and a changed bundle gets its own. `--bt` is invocation-global and REGENIE
// refuses a binary column as a quantitative trait, so trait type separates batches. Focal and downstream
// metadata stay out. Per-member content is deliberately absent: it belongs to the batch key below.
def buildRegenieFitCompatibilityKey(view_key, is_binary, covariates, sample_set_digest, step1_bsize) {
    def identity = [
        genotype_view: view_key,
        is_binary: is_binary,
        covariates: covariates ? digestFileBytes(covariates) : 'absent',
        phenotype_samples: sample_set_digest,
        step1_bsize: step1_bsize,
        adapter_contract: 'regenie_4.1.2_step1_batch_v1',
    ]
    return buildCanonicalPredictionKey(identity)
}

// The fit batch key names one Step 1 task: its compatibility class plus exactly which members it fits,
// with their content. Membership is in the key because the task's `--phenoColList` and its outputs are
// derived from it, so two different member sets must never collide on one identity.
def buildRegenieFitBatchKey(compatibility_key, members) {
    def identity = [
        compatibility: compatibility_key,
        members: canonicaliseScientificIdentifier(members.collect { member -> [id: member.meta.id, phenotype: member.phenotype_digest] }),
    ]
    return buildCanonicalPredictionKey(identity)
}

// The effective Step 2 policy, exactly as `conf/modules/regenie.config` renders it. Every one of these
// options is invocation-global, so analyses that disagree on any of them cannot share one Step 2 command.
def getRegenieStep2Policy(meta) {
    def options = meta.method_options.regenie
    return [
        is_binary: meta.is_binary,
        firth: meta.is_binary && options.firth,
        firth_approx: meta.is_binary && options.firth && options.firth_approx,
        firth_p_threshold: meta.is_binary && options.firth ? options.firth_p_threshold : null,
        min_mac: options.min_mac,
    ]
}

def buildRegenieTestBatchKey(fit_batch_key, policy, member_ids) {
    def identity = [
        fit_batch: fit_batch_key,
        policy: canonicaliseScientificValue(policy),
        members: canonicaliseScientificIdentifier(member_ids),
        adapter_contract: 'regenie_4.1.2_step2_v1',
    ]
    return buildCanonicalPredictionKey(identity)
}

// REGENIE Step 1 removes a binary phenotype with fewer than ten cases and exits successfully, listing only
// the survivors in `_pred.list`. Unbatched that cost one analysis; batched it would silently drop one
// member of a batch whose other members succeed, and the run would end with a result missing rather than
// failed. Comparing the delivered prediction set against the requested one catches that and any other
// drop path, because it compares sets rather than matching a warning string.
def validateRegenieFitPredictionCoverage(fit_meta, predictions) {
    def delivered = file(predictions)
        .readLines()
        .findAll { line -> line.trim() }
        .collect { line -> line.trim().split('\\s+').first() }
    def missing = fit_meta.phenotype_columns.findAll { column -> !(column in delivered) }
    if (missing) {
        error(
            "[nf-core/gwas] ERROR: REGENIE Step 1 batch '${fit_meta.id}' produced no prediction for analysis(es) ${missing.collect { analysis_id -> "'${analysis_id}'" }.join(', ')}. REGENIE removes a binary phenotype with fewer than 10 cases from a fit and still exits successfully; check the case counts of those analyses, or set regenie_batch_size to 1 to fit them on their own."
        )
    }
}

// REGENIE writes one Step 2 result per phenotype column, named `<prefix>_<column>.regenie.gz`, and
// `conf/modules/regenie.config` sets that prefix to the invocation id. The expected names are therefore
// constructed rather than parsed, so an unrecognised file is a loud failure instead of a plausible
// mis-attribution.
def attributeRegenieResult(test_meta, result) {
    def analysis_id = test_meta.phenotype_columns.find { column -> result.name == "${test_meta.id}_${column}.regenie.gz" }
    if (!analysis_id) {
        error(
            "[nf-core/gwas] ERROR: REGENIE Step 2 invocation '${test_meta.id}' produced '${result.name}', which names none of its phenotype columns ${test_meta.phenotype_columns.collect { column -> "'${column}'" }.join(', ')}. Expected one file per column named '${test_meta.id}_<analysis_id>.regenie.gz'."
        )
    }
    return analysis_id
}

// REGENIE Step 2 ignores a `--phenoColList` column that has no Step 1 prediction and warns rather than
// failing, so a column can disappear between the request and the results. Defence in depth behind the
// Step 1 coverage check: without it the missing analysis would simply never reach the emit.
def validateRegenieStep2Attribution(test_meta, attributed) {
    def missing = test_meta.phenotype_columns.findAll { column -> !(column in attributed) }
    if (missing) {
        error(
            "[nf-core/gwas] ERROR: REGENIE Step 2 invocation '${test_meta.id}' produced no result for analysis(es) ${missing.collect { analysis_id -> "'${analysis_id}'" }.join(', ')}. REGENIE ignores a --phenoColList column that has no Step 1 prediction instead of failing."
        )
    }
}

// A process output that resolves to a single file arrives as a bare `java.nio.file.Path`, which
// implements `Iterable<Path>` over its own name elements, so iterating it would silently walk path
// segments instead of files. A single-member batch is the common case, which is exactly when that
// happens. The repository guards the same hazard at `subworkflows/local/plink_fit_regenie/main.nf:63,87`.
def normaliseFileList(value) {
    return [value].flatten().findAll { entry -> entry }
}
