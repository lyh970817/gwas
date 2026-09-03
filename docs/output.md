# nf-core/gwas: Output

## Introduction

This document describes the files that nf-core/gwas publishes beneath `--outdir`. Native association, heritability and declared pairwise results are retained. Every internal association result and every external summary source passes through GWASLab, whose table and log are published directly. Run-level provenance is collected in MultiQC and `pipeline_info/`; one route, `genie_g`, additionally publishes a per-result provenance sidecar beside its native output.

Intermediates are unpublished by default. The optional directories described below appear only when their corresponding save control is enabled.

### Naming and attribution

The shared result prefix grammar is:

```text
<analysis_id>.<method>[.<shard>]
```

`<analysis_id>` is copied from the analysis manifest and identifies one cohort-trait analysis unit. `<method>` is one of the method-selector tokens documented in [Usage](usage.md#relational-manifest-input). A producing tool can add a native result suffix after that prefix.

Summary results use a separate first-class identity. Pipeline-generated association summaries use `<analysis_id>--<association_method>`; external summaries use the declared `summary_statistics_id`. Both publish as `<summary_statistics_id>.gwaslab.tsv.gz` with `<summary_statistics_id>.gwaslab.log` in the same identity-addressed directory.

Use the following provenance chain for any result:

1. For an analysis result, read `<analysis_id>` and `<method>` from its parent directories and filename. Find that analysis row, follow its `cohort_id`, and inspect its method options.
2. For a summary result, read `summary_statistics_id` from its directory and filename. Resolve its declared internal producer or external source from the retained summary-statistics manifest.
3. Map the method to its producing tool using the table below.
4. Read tool versions from `pipeline_info/nf_core_gwas_software_mqc_versions.yml`. The pipeline version and complete run parameters are recorded by the `pipeline_info/` reports and `params_<timestamp>.json`.

Pairwise outputs instead use the deterministic request ID `<method>--<relationship_id>`. Find `relationship_id` in `--relationship_manifest`, follow its ordered left and right endpoint IDs, and inspect the native result and log under `requests/<method>/<request_id>/`. The pipeline does not add a normalized estimand table or a diagnostics table. It adds a per-result provenance sidecar only for `genie_g`, whose runtime reports no version of its own and whose invocation therefore has to be recorded beside its result.

| Method token                                                                                                                                      | Producing tool |
| ------------------------------------------------------------------------------------------------------------------------------------------------- | -------------- |
| `regenie`                                                                                                                                         | REGENIE        |
| `gcta_fastgwa`, `gcta_greml`, `gcta_greml_ldms`, `gcta_bivariate_reml`, `gcta_bivariate_reml_ldms`, `gcta_bivariate_he`, `gcta_bivariate_he_ldms` | GCTA           |
| `ldak_kvik`, `ldak_reml`, `ldak_he`, `ldak_pcgc`, `ldak_fast_he`, `ldak_fast_pcgc`                                                                | LDAK 6         |
| `genie_g`                                                                                                                                         | GENIE          |
| `ldak_sumher`, `ldak_sumcors`                                                                                                                     | LDAK 6.3       |
| `ldsc_h2`, `ldsc_rg`                                                                                                                              | LDSC           |

Together, the result prefix, retained cohort and analysis manifests, optional method-options document, and `pipeline_info/` artifacts identify the analysis, cohort, trait, genome build, method, scientific settings, pipeline version and producing tool version. Preserve them with an archived result.

Analysis attribution applies under `association/` and `heritability/individual/`; summary attribution applies under `summary_statistics/` and summary-level request outputs. Optional prepared genotypes and relatedness matrices are deliberately shared artifacts rather than trait-method results: `genotypes/` is attributed to `cohort_id`, while `quality_control/relatedness_matrices/` is attributed to its reuse key and may serve several analysis rows.

## Pipeline overview

The pipeline is built using [Nextflow](https://www.nextflow.io/) and publishes:

- [Association](#association)
  - [REGENIE](#regenie)
  - [GCTA fastGWA-MLM](#gcta-fastgwa-mlm)
  - [LDAK-KVIK](#ldak-kvik)
- [Summary statistics](#summary-statistics)
- [Heritability](#heritability)
  - [GCTA GREML and GREML-LDMS](#gcta-greml-and-greml-ldms)
  - [LDAK estimators](#ldak-estimators)
  - [LDAK direct-genotype estimators](#ldak-direct-genotype-estimators)
  - [GENIE](#genie)
  - [Summary-level LDSC H2 and RG](#summary-level-ldsc-h2-and-rg)
- [Pairwise GCTA bivariate REML and HEreg](#pairwise-gcta-bivariate-reml-and-hereg)
- [LDAK summary-statistics heritability and correlation](#ldak-summary-statistics-heritability-and-correlation)
- [Quality control and optional prepared data](#quality-control-and-optional-prepared-data)
- [MultiQC](#multiqc)
- [Pipeline information](#pipeline-information)

## Association

Native association output is published by method and then analysis. The native tables are not rewritten; deterministic filename tokens added by tools are removed where necessary so every published name follows the shared prefix grammar.

### REGENIE

<details markdown="1">
<summary>Output files</summary>

[REGENIE](https://rgcgithub.github.io/regenie/) fits a whole-genome prediction model in Step 1 and tests variants in Step 2. Standard Step 1 is the default because it is the simplest execution path; `--regenie_step1_mode chunked` and `--regenie_step1_jobs` use split-L0/run-L0/run-L1 when a large cohort needs work divided into smaller jobs. `--regenie_lowmem` defaults to `true` so temporary prediction blocks stay in the task work directory rather than memory.

- `association/regenie/<analysis_id>/`
  - `<analysis_id>.regenie.gz`: Native, space-delimited REGENIE Step 2 association result.

</details>

For binary traits, the per-analysis `regenie.firth`, `regenie.firth_approx` and `regenie.firth_p_threshold` method options default to approximate Firth correction below `0.01`. `regenie.min_mac` defaults to `null`, retaining REGENIE's own versioned minimum-MAC policy unless an analysis explicitly overrides it.

The published Step 2 file is native output with the fixed `_PHENO` token removed from its name. Step 1 predictions, chunk-planning files, temporary low-memory predictions and logs remain in the work directory. Resumed Step 1 reuse therefore requires preserving the Nextflow cache and work outputs.

### GCTA fastGWA-MLM

<details markdown="1">
<summary>Output files</summary>

[GCTA](https://yanglab.westlake.edu.cn/software/gcta/) runs `--fastGWA-mlm` for quantitative traits and `--fastGWA-mlm-binary` for binary traits. Plain fastGWA linear regression is not selectable. The method option `gcta.sparse_cutoff` defaults to `0.05`, following the official fastGWA example, and controls construction of its sparse relatedness matrix. The native table is passed unchanged to GWASLab.

- `association/gcta_fastgwa/<analysis_id>/`
  - `<analysis_id>.gcta_fastgwa.fastGWA`: Native GCTA fastGWA-MLM result.

</details>

### LDAK-KVIK

<details markdown="1">
<summary>Output files</summary>

[LDAK-KVIK](https://dougspeed.com/ldak-kvik/) fits a Step 1 prediction model from the PLINK 1 compatibility bundle prepared once per cohort and tests the full bundle in Step 2. `ldak.kvik_step1_subset` defaults to `all`; `thin_common` requests deterministic thinning and `provided` requires the stageable `ldak.predictor_extract` resource. One `thin_common` predictor artifact is built per compatible prepared genotype view and effective thinning contract, then shared by every phenotype-specific Step 1 fit on that view. The resolved predictor artifact contributes to prediction reuse identity; phenotype and covariate differences do not fragment thinning reuse. The native `.assoc` file is published unchanged. The internal three-file Step 1 bundle is consumed directly by Step 2; predictor lists, effects, thinning progress and logs remain in the work directory. Resumed Step 1 reuse therefore requires preserving the Nextflow cache and work outputs.

- `association/ldak_kvik/<analysis_id>/`
  - `<analysis_id>.ldak_kvik.step2.assoc`: Native LDAK-KVIK Step 2 association table.

</details>

## Summary statistics

<details markdown="1">
<summary>Output files</summary>

[GWASLab](https://cloufield.github.io/gwaslab/) standardises every pipeline-generated association result and every external source; native association results remain available under `association/`. External rows declare one explicit GWASLab input format, including `gwaslab` for a pre-harmonised GWASLab table. No source bypasses the process, and the external source itself is not republished.

- `summary_statistics/<summary_statistics_id>/`
  - `<summary_statistics_id>.gwaslab.tsv.gz`: Gzip-compressed, tab-delimited GWASLab-standard summary-statistics table.
  - `<summary_statistics_id>.gwaslab.log`: GWASLab harmonisation log for the same source.

</details>

The table uses GWASLab's standard field names, including `SNPID`, `CHR`, `POS`, `EA`, `NEA`, `STATUS`, `EAF`, `BETA`, `SE`, `P` and `N` where the declared source format supplies or derives them. `EA` and `NEA` are the effect and non-effect alleles. `STATUS` is GWASLab's [seven-digit status code](https://cloufield.github.io/gwaslab/StatusCode/). Downstream program adapters consume this GWASLab artifact directly; there is no second canonical serializer, post-GWASLab schema validator or custom checksum/provenance artifact.

All build-specific GWASLab reference parameters default to unset because no compact bundled reference is scientifically adequate. With no references, raw output is still standardised for names, columns and allele roles. Supplying `--gwaslab_reference_fasta_grch37` or `--gwaslab_reference_fasta_grch38` enables reference-allele checks and flips; the corresponding `--gwaslab_rsid_vcf_*` enables rsID assignment, and `--gwaslab_strand_vcf_*` enables palindromic-strand inference. The declared genome build chooses the resource set per summary.

GWASLab drops variants that fail its sanity checks and duplicated variants. The emitted log is published beside the table as the native record of harmonisation.

## Heritability

Individual-level heritability output is method-first and then analysis under `individual/`. These native estimator tables are not harmonised.

### GCTA GREML and GREML-LDMS

<details markdown="1">
<summary>Output files</summary>

[GCTA](https://yanglab.westlake.edu.cn/software/gcta/) `.hsq` output reports genetic and residual variance components, `V(G)/Vp` on the observed scale, its standard error, log likelihood, likelihood-ratio test, p-value and `n`, the sample count after genotype, phenotype and covariate intersection. For a binary row with `population_prevalence`, GCTA also reports the native liability-scale `V(G)/Vp_L` line.

- `heritability/individual/gcta_greml/<analysis_id>/`
  - `<analysis_id>.gcta_greml.hsq`: Native GCTA GREML variance-component estimates.
- `heritability/individual/gcta_greml_ldms/<analysis_id>/`
  - `<analysis_id>.gcta_greml_ldms.hsq`: Native GCTA GREML-LDMS variance-component estimates.

</details>

GREML uses one dense matrix. GREML-LDMS partitions variants by LD score and MAF. Its method-option defaults are a `200` kb LD-score region, `4` LD strata and MAF boundaries `[0,0.01,0.05,0.2,0.5]`; changing any of them produces a distinct reusable matrix family.

### LDAK estimators

<details markdown="1">
<summary>Output files</summary>

[LDAK](https://dougspeed.com/ldak/) REML reports fitted kinship components, likelihood statistics and sample counts. Haseman-Elston regression provides the selected trait's regression estimate. PCGC is a binary-trait route and requires `population_prevalence` for ascertainment-aware estimation.

- `heritability/individual/ldak_reml/<analysis_id>/`
  - `<analysis_id>.ldak_reml.reml`: Native LDAK REML estimates.
  - `<analysis_id>.ldak_reml.reml.liab`: Optional liability-scale REML estimates for a binary analysis with `population_prevalence`.
- `heritability/individual/ldak_he/<analysis_id>/`
  - `<analysis_id>.ldak_he.he`: Native LDAK Haseman-Elston regression estimates.
- `heritability/individual/ldak_pcgc/<analysis_id>/`
  - `<analysis_id>.ldak_pcgc.pcgc`: Native LDAK PCGC regression estimates.
  - `<analysis_id>.ldak_pcgc.pcgc.marginal`: Optional marginal PCGC estimates emitted by LDAK.

</details>

The LDAK kinship model defaults to `human_default` with `power: -0.25`. Set `model: custom` before supplying another power. `weights_policy: equal` is the default and passes `--ignore-weights YES`; `default` passes no weights flag at all, which LDAK treats identically because it applies no predictor weights unless `--weights` is given; `provided` requires the staged `weights` resource. `relatedness_filter` defaults to `false`. When HE or PCGC has covariates, the pipeline first adjusts the kinship matrix on the same analysis subset and covariates, then passes those covariates to the estimator so phenotype residualisation and matrix projection remain aligned.

### LDAK direct-genotype estimators

<details markdown="1">
<summary>Output files</summary>

[LDAK](https://dougspeed.com/ldak/) fast Haseman-Elston and fast PCGC estimate the same quantities as `ldak_he` and `ldak_pcgc` but read the cohort's PLINK 1 genotypes directly, approximating the kinship trace terms with random vectors (the randomised approach introduced by [RHE-mc](https://doi.org/10.1038/s41467-020-17576-9), which GENIE also uses). No relatedness matrix is built, requested or published for these routes, so they add nothing under `quality_control/`. Covariates are projected out natively from the complete covariate files preparation writes.

- `heritability/individual/ldak_fast_he/<analysis_id>/`
  - `<analysis_id>.ldak_fast_he.fasthe`: Native randomised Haseman-Elston estimates: a key-value header (`Num_Kinships`, `Num_Top_Predictors`, `Num_Covariates`, `Coeffsfile`, `Covar_Heritability`, `Total_Samples`, `With_Phenotypes`, `Null_Likelihood`, `Alt_Likelihood`, `LRT_Stat`, `LRT_P`) followed by a `Component Heritability SE Size Mega_Intensity SE` table with `Her_K1`, `Her_Top` and `Her_All` rows.
  - `<analysis_id>.ldak_fast_he.cats`, `.share`, `.enrich`, `.cross`: Native per-category heritability, share, enrichment and cross-product results.
  - `<analysis_id>.ldak_fast_he.coeff`: Native covariate effects (`Component Effect SE P`), one `Covariate_n` row per fitted column plus the intercept.
  - `<analysis_id>.ldak_fast_he.log`: Native log recording the complete argument list, the effective random-vector count, the jackknife block count, the seed when one was supplied, the sample and predictor counts, and any weights-coverage warning.
- `heritability/individual/ldak_fast_pcgc/<analysis_id>/`
  - `<analysis_id>.ldak_fast_pcgc.fastpcgc`: Native randomised PCGC estimates in the same layout, on the liability scale.
  - `<analysis_id>.ldak_fast_pcgc.fastpcgc.marginal`: Native marginal PCGC estimate, unconditional on the covariates and therefore different from the primary result whenever covariates were fitted.
  - `<analysis_id>.ldak_fast_pcgc.cats`, `.share`, `.enrich`, `.cross`, `.coeff`, `.log`: As above, with `.coeff` reporting `Component Log_Odds SE P`.

</details>

The per-predictor (`.ind.hers`), per-block (`.jackests`), per-random-vector (`.repetitions`), label, progress and combined-covariate files stay in the work directory: they are large or purely diagnostic. Three things about these results are worth stating plainly. `ldak.fast_num_blocks` sets the number of **predictor** jackknife blocks — LDAK partitions predictors, not samples — so it moves the standard error and not the point estimate, and a block-jackknife standard error is not comparable across block settings nor to the exact `ldak_he`/`ldak_pcgc` standard error. An unseeded run cannot be reproduced: LDAK records no seed in its log unless one was supplied, so set `ldak.fast_seed` for anything you intend to publish. And with `weights_policy: provided`, inspect the `.log` for `contains weights for only`, which means LDAK gave weight zero to every predictor the weights file omitted.

### GENIE

<details markdown="1">
<summary>Output files</summary>

[GENIE](https://github.com/sriramlab/GENIE) estimates additive heritability by the same randomised method-of-moments approach as [RHE-mc](https://doi.org/10.1038/s41467-020-17576-9), reading the cohort's PLINK 1 genotypes directly. No relatedness matrix is built, requested or published, so this route adds nothing under `quality_control/`. The pipeline fixes the additive model and the projection policy (`-m G -np 0 -i 1`) and exposes none of GENIE's gene-by-environment, noise-by-environment or trace-export surface.

- `heritability/individual/genie_g/<analysis_id>/`
  - `<analysis_id>.genie_g.out`: Native GENIE result: the echoed option block, the retained sample count, the covariate count including GENIE's own intercept, the per-component variant counts, the variance components and the heritabilities.
  - `<analysis_id>.genie_g.log`: Native standard output, carrying the tab-separated parameter block, the per-jackknife-block progress and the retained-sample line the result file does not repeat.
  - `<analysis_id>.genie_g.provenance.json`: Invocation record for this result: the effective stochastic settings and which of them are GENIE's own defaults, the sample and variant identities the fit was given as SHA-256 digests, the fitted components, and the build identity of the pinned runtime. The sample-order digest **records** the order the estimator was given; it does not verify it afterwards, because the counts GENIE echoes cannot detect a permuted or short input. Order is guaranteed instead by the adapter writing every file in genotype-file order.

</details>

Read the heritability from the block under the `Heritabilities:` header, and the whole-genome figure from `Total h2`. Do not grep the bare `h2_g[k]` label: GENIE writes it twice in one file, once there and once under a second `Heritabilities and enrichments computed based on overlapping setting` block, and with overlapping component definitions the two carry different numbers — measured 6.6-fold apart. This route requires a disjoint annotation partition precisely so the two blocks agree by construction.

Three things about these results are worth stating plainly. A seed makes the fit repeatable, not stable: at GENIE's native default of ten random vectors the estimate moved across 0.0719 to 0.1016 over seeds 1 to 8 on a 200-sample cohort, about 35% of its own size, while the reported jackknife standard error ranged 0.154 to 0.284 and contains none of that Monte-Carlo component — so set `genie.random_vectors` explicitly for anything you intend to publish, and read `stochastic_settings.monte_carlo_error` in the sidecar. The pinned runtime is a single-precision build (`Eigen::Matrix<float>`) for `linux/amd64` only, with no Conda fallback; the comparison against a double-precision build that issue #10 asks for has not been made, and is the one part of that phase still open. And `genie.memory_efficient` selects a second executable that agrees with the first on the estimate but writes a wall-clock line into its log, so two of its runs are never byte-identical even at a fixed seed.

GENIE reports no version at runtime: it has no `--version`, its `--help` exits 1, and its own banner self-reports `1.0.0` for the v1.1.1 source tag. The version in `pipeline_info/nf_core_gwas_software_mqc_versions.yml` is therefore stated by the pipeline from the pinned image label rather than extracted, and the sidecar's `software.build` block records the image digest so a published result carries an authoritative build identity.

### Summary-level LDSC H2 and RG

<details markdown="1">
<summary>Output files</summary>

[LDSC](https://github.com/CBIIT/ldsc) consumes each GWASLab summary through one content-addressed HapMap3 munging step. Unary H2 and ordered pairwise RG requests reuse that munged result when the summary identity, adapter contract and HapMap3 bytes are identical. Munged summaries are workflow intermediates and are not published.

- `requests/ldsc_h2/<request_id>/`
  - `native.observed.log`: Complete native observed-scale LDSC H2 log.
  - `native.liability.log`: Optional native liability-scale log for a binary summary declaring both sample and population prevalence.
- `requests/ldsc_rg/<request_id>/`
  - `native.observed.log`: Complete native observed-scale LDSC RG log.
  - `native.liability.log`: Optional native liability-scale log when every binary endpoint declares both prevalence values.

</details>

The pipeline presents every requested LDSC invocation without converting its log into a common heritability, covariance or correlation family. Observed-scale LDSC is always retained. Liability-scale output is added only when all binary endpoints in the request declare both prevalence values; quantitative endpoints use LDSC's native `nan` placeholder in a mixed RG invocation.

## Pairwise GCTA bivariate REML and HEreg

<details markdown="1">
<summary>Output files</summary>

The dense route uses one explicit all-variant GCTA matrix. The relationship's deterministic LDMS request owns one LD-by-MAF-stratified MGRM family. Neither route inherits matrix settings from an endpoint's unary analysis, and scientifically identical unary and pair LDMS settings reuse one matrix family regardless of which method token requested it. `gcta_bivariate_he` and `gcta_bivariate_he_ldms` run GCTA's `--HEreg-bivar` Haseman-Elston cross-product (HE-CP) estimator on that same dense matrix or MGRM family. HE-CP only makes the fitting stage cheaper than REML; it still requires the same full dense (or LDMS-stratified) matrix construction, storage and I/O, so it is published as a deterministic moment reference and sensitivity analysis, not a matrix-free or more scalable route. Each method retains its separate native result contract.

- `requests/gcta_bivariate_reml/<request_id>/`
  - `native.hsq`: Complete native GCTA bivariate REML variance-component result.
  - `native.log`: Native command, version, convergence and sample-overlap log.
- `requests/gcta_bivariate_reml_ldms/<request_id>/`
  - `native.hsq`: Complete native GCTA bivariate REML-LDMS result.
  - `native.log`: Native command, version, convergence and sample-overlap log.
- `requests/gcta_bivariate_he/<request_id>/`
  - `native.HEreg`: Complete native GCTA `--HEreg-bivar` dense result: `Intercept_tr1`, `Intercept_tr2`, `Intercept_tr12`, `V(G)/Vp_tr1`, `V(G)/Vp_tr2`, `C(G)/Vp_tr12`, `rG`, `N_tr1` and `N_tr2` rows, each with `Estimate`, `SE_OLS`, `SE_Jackknife`, `P_OLS` and `P_Jackknife` columns.
  - `native.log`: Native command and version, plus the complete jackknife sampling variance/covariance matrix of the estimates; GCTA writes that matrix only to the log, never to `.HEreg`.
- `requests/gcta_bivariate_he_ldms/<request_id>/`
  - `native.HEreg`: Native GCTA HEreg-LDMS table, including its per-component and native total rows.
  - `native.log`: Native command, version and jackknife sampling variance/covariance matrix.

</details>

The pipeline preserves GCTA's native values and does not compare methods or choose a preferred result. For binary endpoints, a declared `population_prevalence` is passed only through GCTA's endpoint-aware `--reml-bivar-prevalence` interface; ordinary unary `--prevalence` is never used on this route. `gcta_bivariate_he` and `gcta_bivariate_he_ldms` accept quantitative pairs only and do not accept pair covariates. HEreg fits the declared left-trait-by-right-trait orientation on the lower triangle of the GRM, so reversed duplicate relationships remain invalid.

## LDAK summary-statistics heritability and correlation

<details markdown="1">
<summary>Output files</summary>

SumHer and SumCors are request-addressed wrappers over native LDAK 6.3. Every native result is retained directly; the pipeline does not create normalized estimand, diagnostics or provenance views.

- `requests/ldak_sumher/<request_id>/`
  - `native.hers`, `native.cats`, `native.share`, `native.enrich`, `native.extra`, `native.cross`, `native.taus`: Native SumHer estimates and category results.
  - `native.labels`, `native.progress`, `native.overlap`, `native.log`: Native labels, progress, overlap diagnostics and captured execution log.
  - `native.hers.liab`, `native.cats.liab`, `native.factor`: Optional native liability-scale artifacts, present only when LDAK receives a complete binary-trait prevalence/ascertainment pair.
- `requests/ldak_sumcors/<request_id>/`
  - `native.cors`, `native.cors.full`, `native.labels`, `native.progress`, `native.overlap`, `native.log`: Complete native SumCors result family.
  - `native.cors.liab`: Optional native liability-scale pair result when both ordered binary endpoints have complete prevalence/ascertainment declarations.

</details>

The native files retain LDAK's own result structure, warnings and missing-value representation. They are not parsed into a pipeline-wide estimand vocabulary.

## Quality control and optional prepared data

### Relatedness matrices

<details markdown="1">
<summary>Output files</summary>

The pipeline builds each reusable [GCTA](https://yanglab.westlake.edu.cn/software/gcta/) or [LDAK](https://dougspeed.com/ldak/) base artifact once and derives each requested child artifact once. Compatible GREML and fastGWA routes share a dense GCTA base, while the fastGWA cutoff identifies only its sparse child. Filtered and unrestricted LDAK routes share a kinship base, while unrelated-sample subsetting identifies only its child. LDAK HE and PCGC likewise share a covariate-adjusted child when their selected parent, effective sample subset, covariate content and native options match.

Matrices are unpublished by default because they are large intermediates. `<key>` is a content-derived artifact identity over immutable input or parent identity and effective scientific settings. It never contains focal analysis, estimator or publication state. Key-addressing is necessary because one cohort may need several artifacts, while one artifact may serve unary, pairwise and association consumers. Each base or child is published exactly once by its own key; per-partition construction files and logs are never published.

- `quality_control/relatedness_matrices/<key>/` (with `--save_relatedness_matrices`)
  - `*.grm.bin`, `*.grm.N.bin`, `*.grm.id`: Dense GCTA matrix bundle.
  - `*.grm.sp`, `*.grm.id`: Sparse GCTA fastGWA child bundle.
  - `*.grm.bin`, `*.grm.N.bin`, `*.grm.id`: GCTA GREML-LDMS stratified matrix bundles in their declared non-empty LD-by-MAF order. Each native consumer writes its small MGRM control list inside its own task; the control list is not an independently published artifact.
  - `*.grm.bin`, `*.grm.id`, `*.grm.details`, `*.grm.adjust`: Base or unrelated-sample child LDAK kinship bundle.
  - `*.grm.bin`, `*.grm.id`, `*.grm.details`, `*.grm.adjust`, `*.grm.root`: Covariate-adjusted LDAK child bundle.

</details>

Relatedness matrices are the only current `quality_control/` publication family; validation failures are reported before execution and do not create a published validation report. LDAK fast Haseman-Elston, LDAK fast PCGC and GENIE build no matrix and therefore publish nothing here.

### Prepared genotypes

<details markdown="1">
<summary>Output files</summary>

[PLINK 2](https://www.cog-genomics.org/plink/2.0/) converts PLINK 1 or VCF inputs once per cohort into the pipeline's canonical bundle. Only bundles the pipeline actually built are published. A cohort supplied as PLINK 2 is passed through without a process invocation, so it does not appear under `genotypes/`: the researcher's original `pgen`/`psam`/`pvar` already is the canonical bundle. Consequently, a four-cohort run with one PLINK 2 input can legitimately publish three prepared bundles; this does not mean a cohort was dropped.

- `genotypes/<cohort_id>/` (with `--save_prepared_genotypes`)
  - `<cohort_id>.pgen`: PLINK 2 genotype data converted by the pipeline.
  - `<cohort_id>.psam`: PLINK 2 sample information converted by the pipeline.
  - `<cohort_id>.pvar`: PLINK 2 variant information converted by the pipeline.

</details>

### Prepared phenotypes and covariates

<details markdown="1">
<summary>Output files</summary>

- `phenotypes/<analysis_id>/` (with `--save_normalised_phenotypes`)
  - `<analysis_id>.pheno`: Headered prepared phenotype file.
  - `<analysis_id>.qcovar`: Headered quantitative covariates, when supplied.
  - `<analysis_id>.catcovar`: Headered categorical covariates, when supplied.
  - `<analysis_id>.covar`: Headered merged covariates, when either covariate input was supplied.

</details>

These files show the exact representation consumed by downstream tools. They are unpublished by default because they are derived intermediates. Headerless tool-specific serialisations and the LDAK matrix-adjustment serialisation are never published. The public save parameter remains `--save_normalised_phenotypes`.

## MultiQC

<details markdown="1">
<summary>Output files</summary>

[MultiQC](https://multiqc.info/) combines the validated Analysis plan, workflow parameters, route-aware Methods Description and collected software versions into one report. The Analysis plan has one row per `analysis_id` and records the joined cohort, trait, trait type, genome build, ancestry provenance and requested association and heritability methods; the Methods Description additionally cites selected pairwise routes. It describes requested routes, not their completion or scientific results. Custom Manhattan and QQ plots and estimator-result panels are outside the current reporting scope.

- `multiqc/`
  - `multiqc_report.html`: Standalone HTML run report.
  - `multiqc_data/`: Parsed report data and the inputs used to build the report.
  - `multiqc_plots/`: Optional exported static plots.

</details>

## Pipeline information

<details markdown="1">
<summary>Output files</summary>

[Nextflow](https://www.nextflow.io/docs/latest/reports.html) produces the execution reports, and nf-core records the launch parameters and versions used by the run. The version YAML contains the tools that actually executed; a tool absent because its route was not selected has no entry. MultiQC's own version is deliberately not fed into this upstream versions file because MultiQC consumes that file, which would create a circular channel dependency.

- `pipeline_info/`
  - `execution_report_<timestamp>.html`: Nextflow task and resource report.
  - `execution_timeline_<timestamp>.html`: Nextflow execution timeline.
  - `execution_trace_<timestamp>.txt`: Nextflow task trace.
  - `pipeline_dag_<timestamp>.html`: Nextflow workflow graph.
  - `pipeline_report.html`, `pipeline_report.txt`: Optional completion reports written when email reporting is requested.
  - `params_<timestamp>.json`: Complete run parameters.
  - `nf_core_gwas_software_mqc_versions.yml`: Software versions collected from executed processes.

</details>
