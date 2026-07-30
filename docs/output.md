# nf-core/gwas: Output

## Introduction

This document describes the files that nf-core/gwas publishes beneath `--outdir`. Native association and heritability results are retained, every association result also receives a GWASLab-standardised summary-statistics table, and run-level provenance is collected in MultiQC and `pipeline_info/`.

Intermediates are unpublished by default. The optional directories described below appear only when their corresponding save control is enabled.

### Naming and provenance

The shared result prefix grammar is:

```text
<analysis_id>.<method>[.<shard>]
```

`<analysis_id>` is copied from the samplesheet and identifies one cohort-trait analysis unit. `<method>` is one of the selector tokens documented in [Usage](usage.md#samplesheet-input). A producing tool can add a native result suffix after that prefix. Harmonised files add the tool suffix `.gwaslab` after the method, giving `<analysis_id>.<method>.gwaslab.tsv.gz`.

Use the following provenance chain for any result:

1. Read `<analysis_id>` and `<method>` from its parent directories and filename.
2. Find the unique `analysis_id` row in the samplesheet supplied to `--input`; that row records `cohort_id`, `trait_id`, `trait_type`, `genome_build`, `ancestry` and the scientific settings used by the route.
3. Map `<method>` to its producing tool using the table below.
4. Read the tool version from `pipeline_info/nf_core_gwas_software_mqc_versions.yml`. The pipeline release and complete run parameters are recorded by the `pipeline_info/` reports and `params_<timestamp>.json`.

| Method token                                     | Producing tool |
| ------------------------------------------------ | -------------- |
| `plink2`                                         | PLINK 2        |
| `regenie`                                        | REGENIE        |
| `gcta_fastgwa`, `gcta_greml`, `gcta_greml_ldms`  | GCTA           |
| `ldak_kvik`, `ldak_reml`, `ldak_he`, `ldak_pcgc` | LDAK 6         |

Together, the result prefix, retained input samplesheet and `pipeline_info/` artifacts identify the analysis, cohort, trait, genome build, method, pipeline release and producing tool version. Preserve all three with an archived result.

This attribution rule applies to analysis results under `association/`, `summary_statistics/` and `heritability/`. Optional prepared genotypes and relatedness matrices are deliberately shared artifacts rather than trait-method results: `genotypes/` is attributed to `cohort_id`, while `quality_control/relatedness_matrices/` is attributed to its reuse key and may serve several analysis rows.

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
- [Quality control and optional prepared data](#quality-control-and-optional-prepared-data)
- [MultiQC](#multiqc)
- [Pipeline information](#pipeline-information)

## Association

Native association output is published by method and then analysis. The native tables are not rewritten; deterministic filename tokens added by tools are removed where necessary so every published name follows the shared prefix grammar.

### PLINK 2

<details markdown="1">
<summary>Output files</summary>

- `association/plink2/<analysis_id>/`
  - `<analysis_id>.plink2.glm.linear`: Native PLINK 2 `--glm` result for a quantitative trait.
  - `<analysis_id>.plink2.glm.logistic.hybrid`: Native PLINK 2 `--glm` result for a binary trait with Firth fallback available.

</details>

[PLINK 2](https://www.cog-genomics.org/plink/2.0/assoc) receives the normalised phenotype, preserves its native result columns and is configured to include `A1_FREQ`, `OBS_CT`, `BETA`, `SE` and `P` for harmonisation. The pipeline removes PLINK 2's fixed `.PHENO` token from the published filename; file content is unchanged.

For binary traits, Firth fallback is enabled by default so complete or quasi-complete separation, often encountered for rare variants, can still produce an estimate; this is why the result uses the `.logistic.hybrid` extension. The common normalised binary coding is `0`/`1`/`NA`, so the pipeline passes `--1`. It also uses `--covar-variance-standardize` when covariates are present to avoid PLINK 2's numerical-stability failure for differently scaled covariates; this invertible covariate reparameterisation does not change the reported genotype effect.

### REGENIE

<details markdown="1">
<summary>Output files</summary>

- `association/regenie/<analysis_id>/`
  - `<analysis_id>.regenie.gz`: Native, space-delimited REGENIE Step 2 association result.
- `intermediates/regenie/<analysis_id>/` (with `--save_regenie_predictions`)
  - `<analysis_id>.regenie_step1_pred.list`: Prediction-list manifest from standard Step 1 or chunked Run L1.
  - `<analysis_id>.regenie_step1_<chromosome>.loco.gz`: Leave-one-chromosome-out prediction table.

</details>

[REGENIE](https://rgcgithub.github.io/regenie/) fits a whole-genome prediction model in Step 1 and tests variants in Step 2. Standard Step 1 is the default because it is the simplest execution path; `--regenie_step1_mode chunked` and `--regenie_step1_jobs` use split-L0/run-L0/run-L1 when a large cohort needs work divided into smaller jobs. `--regenie_lowmem` defaults to `true` so temporary prediction blocks stay in the task work directory rather than memory.

For binary traits, approximate Firth correction is enabled by default below `--regenie_firth_p_threshold 0.01`, reducing separation bias while avoiding the cost of applying Firth to every test. The pipeline leaves `--regenie_min_mac` unset unless you provide it, deliberately retaining REGENIE's own versioned minimum-MAC policy instead of silently imposing a pipeline-specific scientific filter.

The published Step 2 file is native output with the fixed `_PHENO` token removed from its name. Step 1 predictions are reusable intermediates and remain unpublished unless `--save_regenie_predictions` is enabled; chunk-planning files, temporary low-memory predictions and logs remain in the work directory.

### GCTA fastGWA-MLM

<details markdown="1">
<summary>Output files</summary>

- `association/gcta_fastgwa/<analysis_id>/`
  - `<analysis_id>.gcta_fastgwa.fastGWA`: Native GCTA fastGWA-MLM result.

</details>

[GCTA](https://yanglab.westlake.edu.cn/software/gcta/) runs `--fastGWA-mlm` for quantitative traits and `--fastGWA-mlm-binary` for binary traits. Plain fastGWA linear regression is not a selectable route. The model consumes a sparse GCTA relatedness matrix; `gcta_sparse_cutoff` defaults to `0.05`, following the official fastGWA example. The native table includes marker identity, alleles, allele frequency, sample count, effect, standard error and p-value and is passed unchanged to GWASLab.

### LDAK-KVIK

<details markdown="1">
<summary>Output files</summary>

- `association/ldak_kvik/<analysis_id>/`
  - `<analysis_id>.ldak_kvik.step2.assoc`: Native LDAK-KVIK Step 2 association table.

</details>

[LDAK-KVIK](https://dougspeed.com/ldak-kvik/) fits a Step 1 prediction model from the PLINK 1 compatibility bundle prepared once per cohort and tests the full bundle in Step 2. Each row explicitly chooses `all`, `thin_common` or `provided` for its Step 1 predictor subset because the choice changes the fitted model and has no safe universal default. The native `.assoc` file is published unchanged. Step 1 predictions, thinning progress, summaries, p-value side products and logs remain in the work directory.

## Summary statistics

<details markdown="1">
<summary>Output files</summary>

- `summary_statistics/<analysis_id>/`
  - `<analysis_id>.<method>.gwaslab.tsv.gz`: Gzip-compressed, tab-delimited standardised summary statistics produced from one native association result.

</details>

[GWASLab](https://cloufield.github.io/gwaslab/) standardises every association result, while the native result remains available under `association/`. Files are grouped by analysis so every selected method for one cohort-trait unit can be compared in a single directory. The method token prevents collisions and `.gwaslab` is the tool suffix marking the harmonised derivative.

The canonical columns are `SNPID`, `CHR`, `POS`, `EA`, `NEA`, `STATUS`, `EAF`, `BETA`, `SE`, `P`, `N`. `EA` and `NEA` are the effect and non-effect alleles. `STATUS` is GWASLab's [seven-digit status code](https://cloufield.github.io/gwaslab/StatusCode/): the first two digits record genome build, followed by one digit each for identifier checking, coordinate checking, allele standardisation, reference alignment, and palindromic-variant/indel handling. A `9` means the corresponding check was not performed.

All build-specific GWASLab reference parameters default to unset because no compact bundled reference is scientifically adequate. With no references, the output is still standardised for names, columns and allele roles. Supplying `--gwaslab_reference_fasta_grch37` or `--gwaslab_reference_fasta_grch38` enables reference-allele checks and flips; the corresponding `--gwaslab_rsid_vcf_*` enables rsID assignment, and `--gwaslab_strand_vcf_*` enables palindromic-strand inference. The samplesheet's `genome_build` chooses the resource set per analysis.

GWASLab drops variants that fail its sanity checks and duplicated variants. Its log is not published because timestamps and container-local paths make it non-reproducible provenance noise.

## Heritability

Heritability output is method-first and then analysis, under `individual/` because every estimator consumes individual-level genotypes. These native estimator tables are not harmonised.

### GCTA GREML and GREML-LDMS

<details markdown="1">
<summary>Output files</summary>

- `heritability/individual/gcta_greml/<analysis_id>/`
  - `<analysis_id>.gcta_greml.hsq`: Native GCTA GREML variance-component estimates.
- `heritability/individual/gcta_greml_ldms/<analysis_id>/`
  - `<analysis_id>.gcta_greml_ldms.hsq`: Native GCTA GREML-LDMS variance-component estimates.

</details>

[GCTA](https://yanglab.westlake.edu.cn/software/gcta/) `.hsq` output reports genetic and residual variance components, `V(G)/Vp` on the observed scale, its standard error, log likelihood, likelihood-ratio test, p-value and `n`, the sample count after genotype, phenotype and covariate intersection. For a binary row with `population_prevalence`, GCTA also reports the native liability-scale `V(G)/Vp_L` line.

GREML uses one dense matrix. GREML-LDMS partitions variants by LD score and MAF: the `200` kb LD-score region default follows GCTA's official LDMS example, and four LD strata default to quartiles. MAF interval edges have no default and must be declared because they are a scientific partitioning choice.

### LDAK estimators

<details markdown="1">
<summary>Output files</summary>

- `heritability/individual/ldak_reml/<analysis_id>/`
  - `<analysis_id>.ldak_reml.reml`: Native LDAK REML estimates.
  - `<analysis_id>.ldak_reml.reml.liab`: Optional liability-scale REML estimates for a binary analysis with `population_prevalence`.
- `heritability/individual/ldak_he/<analysis_id>/`
  - `<analysis_id>.ldak_he.he`: Native LDAK Haseman-Elston regression estimates.
- `heritability/individual/ldak_pcgc/<analysis_id>/`
  - `<analysis_id>.ldak_pcgc.pcgc`: Native LDAK PCGC regression estimates.
  - `<analysis_id>.ldak_pcgc.pcgc.marginal`: Optional marginal PCGC estimates emitted by LDAK.

</details>

[LDAK](https://dougspeed.com/ldak/) REML reports fitted kinship components, likelihood statistics and sample counts. Haseman-Elston regression provides the selected trait's regression estimate. PCGC is a binary-trait route and requires `population_prevalence` for ascertainment-aware estimation.

The LDAK kinship model defaults to `human_default` with power `-0.25`, the documented human-data model; `custom` makes an alternative power explicit. Empty `ldak_weights` means explicit equal predictor weights. `ldak_relatedness_filter` defaults to `false`, preserving the declared analysis population unless you request an unrelated subset. When HE or PCGC has covariates, the pipeline first adjusts the kinship matrix on the same analysis subset and covariates, then passes those covariates to the estimator so phenotype residualisation and matrix projection remain aligned.

## Quality control and optional prepared data

### Relatedness matrices

<details markdown="1">
<summary>Output files</summary>

- `quality_control/relatedness_matrices/<key>/` (with `--save_relatedness_matrices`)
  - `*.grm.bin`, `*.grm.N.bin`, `*.grm.id`: Dense GCTA matrix bundle.
  - `*.grm.sp`, `*.grm.id`: Sparse GCTA fastGWA matrix bundle.
  - `*.mgrm`, `*.grm.bin`, `*.grm.N.bin`, `*.grm.id`: GCTA GREML-LDMS manifest and stratified matrix bundles.
  - `*.grm.bin`, `*.grm.id`, `*.grm.details`, `*.grm.adjust`: LDAK matrix bundle.

</details>

The pipeline builds each distinct [GCTA](https://yanglab.westlake.edu.cn/software/gcta/) or [LDAK](https://dougspeed.com/ldak/) relatedness matrix once and reuses it across compatible analyses. Matrices are unpublished by default because they are large intermediates. `<key>` is a content-derived digest over cohort identity and every construction setting that changes a matrix. Key-addressing is necessary because one cohort may need several matrices, while one matrix may belong to several analyses. Per-partition construction files and logs are never published.

Relatedness matrices are the only current `quality_control/` publication family; validation failures are reported before execution and do not create a published validation report.

### Prepared genotypes

<details markdown="1">
<summary>Output files</summary>

- `genotypes/<cohort_id>/` (with `--save_prepared_genotypes`)
  - `<cohort_id>.pgen`: PLINK 2 genotype data converted by the pipeline.
  - `<cohort_id>.psam`: PLINK 2 sample information converted by the pipeline.
  - `<cohort_id>.pvar`: PLINK 2 variant information converted by the pipeline.

</details>

[PLINK 2](https://www.cog-genomics.org/plink/2.0/) converts PLINK 1 or VCF inputs once per cohort into the pipeline's canonical bundle. Only bundles the pipeline actually built are published. A cohort supplied as PLINK 2 is passed through without a process invocation, so it does not appear under `genotypes/`: the researcher's original `pgen`/`psam`/`pvar` already is the canonical bundle. Consequently, a four-cohort run with one PLINK 2 input can legitimately publish three prepared bundles; this does not mean a cohort was dropped.

### Normalised phenotypes and covariates

<details markdown="1">
<summary>Output files</summary>

- `phenotypes/<analysis_id>/` (with `--save_normalised_phenotypes`)
  - `<analysis_id>.pheno`: Headered normalised phenotype file.
  - `<analysis_id>.qcovar`: Headered quantitative covariates, when supplied.
  - `<analysis_id>.catcovar`: Headered categorical covariates, when supplied.
  - `<analysis_id>.covar`: Headered merged covariates, when either covariate input was supplied.

</details>

These files show the exact recoding consumed by downstream tools and are useful for auditing case/control normalisation. They are unpublished by default because they are derived intermediates. Headerless tool-specific serialisations, the LDAK matrix-adjustment serialisation and the normalisation log are never published.

## MultiQC

<details markdown="1">
<summary>Output files</summary>

- `multiqc/`
  - `multiqc_report.html`: Standalone HTML run report.
  - `multiqc_data/`: Parsed report data and the inputs used to build the report.
  - `multiqc_plots/`: Optional exported static plots.

</details>

[MultiQC](https://multiqc.info/) combines the workflow summary and collected software-version information into one report. Custom Manhattan and QQ plots and custom result-summary modules are outside this release's scope.

## Pipeline information

<details markdown="1">
<summary>Output files</summary>

- `pipeline_info/`
  - `execution_report_<timestamp>.html`: Nextflow task and resource report.
  - `execution_timeline_<timestamp>.html`: Nextflow execution timeline.
  - `execution_trace_<timestamp>.txt`: Nextflow task trace.
  - `pipeline_dag_<timestamp>.html`: Nextflow workflow graph.
  - `pipeline_report.html`, `pipeline_report.txt`: Optional completion reports written when email reporting is requested.
  - `params_<timestamp>.json`: Complete run parameters.
  - `nf_core_gwas_software_mqc_versions.yml`: Software versions collected from executed processes.

</details>

[Nextflow](https://www.nextflow.io/docs/latest/reports.html) produces the execution reports, and nf-core records the launch parameters and versions used by the run. The version YAML contains the tools that actually executed; a tool absent because its route was not selected has no entry. MultiQC's own version is deliberately not fed into this upstream versions file because MultiQC consumes that file, which would create a circular channel dependency.
