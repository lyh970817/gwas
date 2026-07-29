# nf-core/gwas: Output

## Introduction

This document describes the output produced by the pipeline. Most of the plots are taken from the MultiQC report, which summarises results at the end of the pipeline.

The directories listed below will be created in the results directory after the pipeline has finished. All paths are relative to the top-level results directory.

<!-- TODO nf-core: Write this documentation describing your workflow's output -->

## Pipeline overview

The pipeline is built using [Nextflow](https://www.nextflow.io/) and processes data using the following steps:

- [Association](#association) - Association test results, one directory per method
- [Summary statistics](#summary-statistics) - Harmonised summary statistics, one directory per analysis
- [Heritability](#heritability) - Heritability estimates, one directory per method and analysis
- [MultiQC](#multiqc) - Aggregate report describing results and QC from the whole pipeline
- [Pipeline information](#pipeline-information) - Report metrics generated during the workflow execution

### Association

<details markdown="1">
<summary>Output files</summary>

- `association/plink2/<analysis_id>/`
  - `<analysis_id>.plink2.glm.linear`: PLINK 2 `--glm` results for a quantitative trait.
  - `<analysis_id>.plink2.glm.logistic.hybrid`: PLINK 2 `--glm` results for a binary trait. The `.hybrid` extension indicates that Firth fallback was available, which the pipeline enables by default.
- `association/regenie/<analysis_id>/`
  - `<analysis_id>.regenie.gz`: REGENIE Step 2 association results for the analysis.
- `association/ldak_kvik/<analysis_id>/`
  - `<analysis_id>.ldak_kvik.step2.assoc`: LDAK-KVIK Step 2 association results for the analysis.
- `association/gcta_fastgwa/<analysis_id>/`
  - `<analysis_id>.gcta_fastgwa.fastGWA`: [GCTA](https://yanglab.westlake.edu.cn/software/gcta/) fastGWA-MLM association results for the analysis.
- `intermediates/regenie/<analysis_id>/` (only with `--save_regenie_predictions`)
  - `<analysis_id>.regenie_step1_pred.list`: REGENIE Step 1 prediction-list manifest.
  - `<analysis_id>.regenie_step1_1.loco.gz`: Leave-one-chromosome-out predictions for the selected trait.

</details>

[PLINK 2](https://www.cog-genomics.org/plink/2.0/assoc) `--glm` output is published exactly as PLINK 2 wrote it; only the filename changes, because PLINK 2 always embeds the phenotype name in it and the pipeline renames the file to follow the analysis-identifier-then-method grammar used throughout the published output. Results include the `A1_FREQ` (allele frequency) and `OBS_CT` (sample count) columns.

[REGENIE](https://rgcgithub.github.io/regenie/) fits its whole-genome prediction model in Step 1 and tests variants in Step 2. Standard Step 1 is the default; `--regenie_step1_mode chunked` with `--regenie_step1_jobs` uses REGENIE's native split-L0/run-L0/run-L1 execution family for larger cohorts. Step 2's native space-delimited result is published unchanged apart from removing the fixed `_PHENO` filename token introduced by the canonical normalised trait name. The pipeline does not set `--minMAC` unless `--regenie_min_mac` is supplied, so REGENIE's own built-in minimum-MAC default applies.

[LDAK-KVIK](https://www.ldak-kvik.com/) fits its Step 1 prediction model from the PLINK 1 compatibility bundle prepared once per cohort and tests the full bundle in Step 2. Each analysis selects its Step 1 predictor policy in the samplesheet: `all` uses every predictor, `thin_common` runs LDAK's native common-predictor thinning, and `provided` uses the row's `ldak_kvik_step1_extract` file. The native `.assoc` table is published unchanged and then passed through the explicit LDAK-KVIK GWASLab mapping. Step 1 predictions, thinning progress, summaries, p-value side products and programme logs remain intermediates.

The phenotype and covariate files the pipeline normalises for each analysis are intermediates and are not published unless `--save_normalised_phenotypes` is set, in which case they appear under `phenotypes/<analysis_id>/`.

REGENIE's prediction list and LOCO table are also intermediates and remain unpublished by default. `--save_regenie_predictions` publishes the reusable bundle under `intermediates/regenie/<analysis_id>/`; the lower-level chunk-planning files, temporary low-memory predictions and programme logs remain in the work directory.

### Summary statistics

<details markdown="1">
<summary>Output files</summary>

- `summary_statistics/<analysis_id>/`
  - `<analysis_id>.<method>.gwaslab.tsv.gz`: Harmonised summary statistics for one analysis produced by one association method, gzip-compressed and tab-delimited.

</details>

[GWASLab](https://cloufield.github.io/gwaslab/) standardises every association result the pipeline produces, so that results from different methods on the same analysis are directly comparable. Harmonisation does not replace the native association output described above; it is written alongside it.

These files are keyed by analysis rather than by method, so every method run for one analysis lands in one directory and comparing methods is a single directory listing. The method is carried by the filename instead, following the same grammar as the rest of the published output — analysis identifier, then method — with the `.gwaslab` tool suffix marking the file as harmonised.

The columns are GWASLab's canonical names in GWASLab's canonical order rather than the producing programme's: `SNPID`, `CHR`, `POS`, `EA` (effect allele), `NEA` (non-effect allele), `STATUS`, `EAF`, `BETA`, `SE`, `P`, `N`. Effect sizes and standard errors are written in scientific notation so that they keep their precision at the small magnitudes a well-powered study produces. Variants that fail GWASLab's sanity checks, and duplicated variants, are dropped.

`STATUS` is GWASLab's [seven-digit status code](https://cloufield.github.io/gwaslab/StatusCode/), which records per variant what harmonisation was able to verify: the first two digits are the genome build, and the remaining five record in turn the variant identifier check, the coordinate check, allele standardisation, alignment against the reference sequence, and the handling of palindromic variants and indels. A `9` means that check was not performed.

Which checks can run depends on the optional reference resources you configure. Without any, the file is still standardised in name, column set and allele order, but nothing is checked against an external reference. Supplying `--gwaslab_reference_fasta_grch37` / `--gwaslab_reference_fasta_grch38` allows alleles to be checked and flipped against the reference sequence, `--gwaslab_rsid_vcf_grch37` / `--gwaslab_rsid_vcf_grch38` allows rsIDs to be assigned, and `--gwaslab_strand_vcf_grch37` / `--gwaslab_strand_vcf_grch38` allows the strand of palindromic variants to be inferred. Each is selected by the genome build the analysis declares in its samplesheet row, so a run mixing builds configures each build independently, and an analysis on a build with no configured resource is still standardised without one.

GWASLab's own harmonisation log is an intermediate and is not published: it records the run timestamp and container-local input paths, so it would differ between two otherwise identical runs.

### Heritability

<details markdown="1">
<summary>Output files</summary>

- `heritability/individual/gcta_greml/<analysis_id>/`
  - `<analysis_id>.gcta_greml.hsq`: [GCTA](https://yanglab.westlake.edu.cn/software/gcta/) GREML variance-component estimates for one analysis, as GCTA wrote them.
- `heritability/individual/gcta_greml_ldms/<analysis_id>/`
  - `<analysis_id>.gcta_greml_ldms.hsq`: [GCTA](https://yanglab.westlake.edu.cn/software/gcta/) GREML-LDMS variance-component estimates for one analysis, as GCTA wrote them.
- `heritability/individual/ldak_reml/<analysis_id>/`
  - `<analysis_id>.ldak_reml.reml`: [LDAK](https://dougspeed.com/) REML variance-component estimates for one analysis, as LDAK wrote them.
  - `<analysis_id>.ldak_reml.reml.liab`: Optional liability-scale estimates for a binary analysis that declared `population_prevalence`.

</details>

Heritability output is written per method and per analysis, under `individual/` because these estimators work from individual-level genotypes rather than from summary statistics. GCTA's native `.hsq` table contains the genetic and residual variance components, `V(G)/Vp` as the estimate of heritability on the observed scale, its standard error, the log likelihood, the likelihood-ratio test and its p-value, and `n`, the number of samples the estimator actually used after intersecting genotypes, phenotype and covariates. LDAK's native `.reml` table reports the corresponding fitted kinship components, likelihood statistics and sample counts. For a binary trait whose row declares `population_prevalence`, each programme also writes its native liability-scale estimate. Unlike association results, heritability estimates are not harmonised — there is nothing cross-method to align.

The relatedness matrix each estimate is computed from is an intermediate and is not published unless `--save_relatedness_matrices` is set, in which case the matrices appear under `quality_control/relatedness_matrices/<key>/`. `<key>` is the reuse key of the matrix, a digest of the cohort and of every setting that changes the matrix: analyses that share one are computed against one matrix, which is built once. LDAK keys include the kinship model, power and weights identity. Equal weighting records only its mode; a supplied weights file records the SHA-256 digest of its bytes, never its path or basename, so identical content can be reused across locations while different content with the same filename remains distinct. Requesting an unrelated subset does not change the key, so filtered and unfiltered analyses share one kinship build. Tool logs are not published, since they record container-local paths and the run timestamp.

### MultiQC

<details markdown="1">
<summary>Output files</summary>

- `multiqc/`
  - `multiqc_report.html`: a standalone HTML file that can be viewed in your web browser.
  - `multiqc_data/`: directory containing parsed statistics from the different tools used in the pipeline.
  - `multiqc_plots/`: directory containing static images from the report in various formats.

</details>

[MultiQC](http://multiqc.info) is a visualization tool that generates a single HTML report summarising all samples in your project. Most of the pipeline QC results are visualised in the report and further statistics are available in the report data directory.

Results generated by MultiQC collate pipeline QC from supported tools e.g. FastQC. The pipeline has special steps which also allow the software versions to be reported in the MultiQC output for future traceability. For more information about how to use MultiQC reports, see <http://multiqc.info>.

### Pipeline information

<details markdown="1">
<summary>Output files</summary>

- `pipeline_info/`
  - Reports generated by Nextflow: `execution_report.html`, `execution_timeline.html`, `execution_trace.txt` and `pipeline_dag.dot`/`pipeline_dag.svg`.
  - Reports generated by the pipeline: `pipeline_report.html`, `pipeline_report.txt` and `software_versions.yml`. The `pipeline_report*` files will only be present if the `--email` / `--email_on_fail` parameter's are used when running the pipeline.
  - Reformatted samplesheet files used as input to the pipeline: `samplesheet.valid.csv`.
  - Parameters used by the pipeline run: `params.json`.

</details>

[Nextflow](https://www.nextflow.io/docs/latest/tracing.html) provides excellent functionality for generating various reports relevant to the running and execution of the pipeline. This will allow you to troubleshoot errors with the running of the pipeline, and also provide you with other information such as launch commands, run times and resource usage.
