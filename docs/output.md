# nf-core/gwas: Output

## Introduction

This document describes the files that nf-core/gwas publishes beneath `--outdir`. Native association, heritability and declared pairwise results are retained. Every internal association result and every external summary source passes through GWASLab, whose table and log are published directly. Run-level provenance is collected in MultiQC and `pipeline_info/`.

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

Pairwise outputs instead use the deterministic request ID `<method>--<relationship_id>`. Find `relationship_id` in `--relationship_manifest`, follow its ordered left and right endpoint IDs, and inspect the native result and log under `requests/<method>/<request_id>/`. The pipeline does not add a normalized estimand table, diagnostics table or per-result provenance sidecar.

| Method token                                                                                                                                      | Producing tool |
| ------------------------------------------------------------------------------------------------------------------------------------------------- | -------------- |
| `plink2`                                                                                                                                          | PLINK 2        |
| `regenie`                                                                                                                                         | REGENIE        |
| `gcta_fastgwa`, `gcta_greml`, `gcta_greml_ldms`, `gcta_bivariate_reml`, `gcta_bivariate_reml_ldms`, `gcta_bivariate_he`, `gcta_bivariate_he_ldms` | GCTA           |
| `ldak_kvik`, `ldak_reml`, `ldak_he`, `ldak_pcgc`                                                                                                  | LDAK 6         |
| `ldak_sumher`, `ldak_sumcors`                                                                                                                     | LDAK 6.3       |
| `ldsc_h2`, `ldsc_rg`                                                                                                                              | LDSC           |

Together, the result prefix, retained cohort and analysis manifests, optional method-options document, and `pipeline_info/` artifacts identify the analysis, cohort, trait, genome build, method, scientific settings, pipeline version and producing tool version. Preserve them with an archived result.

Analysis attribution applies under `association/` and `heritability/individual/`; summary attribution applies under `summary_statistics/` and summary-level request outputs. Optional prepared genotypes and relatedness matrices are deliberately shared artifacts rather than trait-method results: `genotypes/` is attributed to `cohort_id`, while `quality_control/relatedness_matrices/` is attributed to its reuse key and may serve several analysis rows.

## Pipeline overview

The pipeline is built using [Nextflow](https://www.nextflow.io/) and publishes:

- [Association](#association)
  - [PLINK 2](#plink-2)
  - [REGENIE](#regenie)
  - [GCTA fastGWA-MLM](#gcta-fastgwa-mlm)
  - [LDAK-KVIK](#ldak-kvik)
- [Summary statistics](#summary-statistics)
- [Heritability](#heritability)
  - [GCTA GREML and GREML-LDMS](#gcta-greml-and-greml-ldms)
  - [LDAK estimators](#ldak-estimators)
  - [Summary-level LDSC H2 and RG](#summary-level-ldsc-h2-and-rg)
- [Pairwise GCTA bivariate REML and HEreg](#pairwise-gcta-bivariate-reml-and-hereg)
- [LDAK summary-statistics heritability and correlation](#ldak-summary-statistics-heritability-and-correlation)
- [Quality control and optional prepared data](#quality-control-and-optional-prepared-data)
- [MultiQC](#multiqc)
- [Pipeline information](#pipeline-information)

## Association

Native association output is published by method and then analysis. The native tables are not rewritten; deterministic filename tokens added by tools are removed where necessary so every published name follows the shared prefix grammar.

### PLINK 2

<details markdown="1">
<summary>Output files</summary>

[PLINK 2](https://www.cog-genomics.org/plink/2.0/assoc) receives the prepared phenotype, preserves its native result columns and is configured to include `A1_FREQ`, `OBS_CT`, `BETA`, `SE` and `P` for harmonisation. The pipeline removes PLINK 2's fixed `.PHENO` token from the published filename; file content is unchanged.

- `association/plink2/<analysis_id>/`
  - `<analysis_id>.plink2.glm.linear`: Native PLINK 2 `--glm` result for a quantitative trait.
  - `<analysis_id>.plink2.glm.logistic.hybrid`: Native PLINK 2 `--glm` result for a binary trait with Firth fallback available.

</details>

For binary traits, Firth fallback is enabled by default so complete or quasi-complete separation, often encountered for rare variants, can still produce an estimate; this is why the result uses the `.logistic.hybrid` extension. The prepared binary coding is `0`/`1`/`NA`, so the pipeline passes `--1`. It also uses `--covar-variance-standardize` when covariates are present to avoid PLINK 2's numerical-stability failure for differently scaled covariates; this invertible covariate reparameterisation does not change the reported genotype effect.

### REGENIE

<details markdown="1">
<summary>Output files</summary>

[REGENIE](https://rgcgithub.github.io/regenie/) fits a whole-genome prediction model in Step 1 and tests variants in Step 2. Standard Step 1 is the default because it is the simplest execution path; `--regenie_step1_mode chunked` and `--regenie_step1_jobs` use split-L0/run-L0/run-L1 when a large cohort needs work divided into smaller jobs. `--regenie_lowmem` defaults to `true` so temporary prediction blocks stay in the task work directory rather than memory.

- `association/regenie/<analysis_id>/`
  - `<analysis_id>.regenie.gz`: Native, space-delimited REGENIE Step 2 association result.
- `intermediates/association_predictions/regenie/<analysis_id>/` (with `--save_association_predictions`)
  - `<analysis_id>.regenie_step1_pred.list`: Prediction-list manifest from standard Step 1 or chunked Run L1.
  - `<analysis_id>.regenie_step1_<chromosome>.loco.gz`: Leave-one-chromosome-out prediction table.

</details>

For binary traits, the per-analysis `regenie.firth`, `regenie.firth_approx` and `regenie.firth_p_threshold` method options default to approximate Firth correction below `0.01`. `regenie.min_mac` defaults to `null`, retaining REGENIE's own versioned minimum-MAC policy unless an analysis explicitly overrides it.

The published Step 2 file is native output with the fixed `_PHENO` token removed from its name. Step 1 predictions are reusable intermediates and remain unpublished unless `--save_association_predictions` is enabled; chunk-planning files, temporary low-memory predictions and logs remain in the work directory.

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

[LDAK-KVIK](https://dougspeed.com/ldak-kvik/) fits a Step 1 prediction model from the PLINK 1 compatibility bundle prepared once per cohort and tests the full bundle in Step 2. `ldak.kvik_step1_subset` defaults to `all`; `thin_common` requests deterministic thinning and `provided` requires the stageable `ldak.predictor_extract` resource. The choice changes prediction reuse identity. The native `.assoc` file is published unchanged. The reusable three-file Step 1 bundle is optional output; effects, thinning progress and logs remain in the work directory.

- `association/ldak_kvik/<analysis_id>/`
  - `<analysis_id>.ldak_kvik.step2.assoc`: Native LDAK-KVIK Step 2 association table.
- `intermediates/association_predictions/ldak_kvik/<analysis_id>/` (with `--save_association_predictions`)
  - `<analysis_id>.ldak_kvik.step1.root`: LDAK Step 1 model root file, attributed to the requesting analysis.
  - `<analysis_id>.ldak_kvik.step1.loco.details`: Leave-one-chromosome-out model details used by LDAK-KVIK Step 2.
  - `<analysis_id>.ldak_kvik.step1.loco.prs`: Leave-one-chromosome-out polygenic scores used by LDAK-KVIK Step 2.

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

The LDAK kinship model defaults to `human_default` with `power: -0.25`. Set `model: custom` before supplying another power. `weights_policy: equal` is the default and explicitly ignores weights; `default` retains LDAK's native policy; `provided` requires the staged `weights` resource. `relatedness_filter` defaults to `false`. When HE or PCGC has covariates, the pipeline first adjusts the kinship matrix on the same analysis subset and covariates, then passes those covariates to the estimator so phenotype residualisation and matrix projection remain aligned.

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
  - `*.mgrm`, `*.grm.bin`, `*.grm.N.bin`, `*.grm.id`: GCTA GREML-LDMS manifest and stratified matrix bundles.
  - `*.grm.bin`, `*.grm.id`, `*.grm.details`, `*.grm.adjust`: Base or unrelated-sample child LDAK kinship bundle.
  - `*.grm.bin`, `*.grm.id`, `*.grm.details`, `*.grm.adjust`, `*.grm.root`: Covariate-adjusted LDAK child bundle.

</details>

Relatedness matrices are the only current `quality_control/` publication family; validation failures are reported before execution and do not create a published validation report.

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
