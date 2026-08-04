# nf-core/gwas: Usage

## :warning: Please read this documentation on the nf-core website: [https://nf-co.re/gwas/usage](https://nf-co.re/gwas/usage)

> _Documentation of pipeline parameters is generated automatically from the pipeline schema and can no longer be found in markdown files._

## Introduction

nf-core/gwas runs association and individual-level heritability analyses from prepared human genotypes,
phenotypes and optional covariates. A cohort manifest owns genotype facts; an analysis manifest links
each trait analysis to one cohort and selects its methods.

> [!IMPORTANT]
> Genotypes must be prepared before you run the pipeline. The pipeline converts accepted genotype
> encodings into the formats required by its methods, but it does not perform genotype quality control.

## Linked manifest input

Every run requires both linked CSV manifests:

```bash
nextflow run nf-core/gwas \
    -r <VERSION> \
    -profile docker \
    --cohort_manifest ./cohorts.csv \
    --analysis_manifest ./analyses.csv \
    --outdir ./results
```

The cohort manifest owns reusable genotype facts. The analysis manifest owns one cohort–trait analysis and joins to exactly one cohort through `cohort_id`. Each `cohort_id` has one non-conflicting definition; each `analysis_id` is unique; and every analysis references a declared cohort. Cohort preparation and compatible matrices or predictions are reused, while outputs retain `analysis_id`.

### Cohort manifest fields

| Column         | Required | Description                                                                                                                                             |
| -------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `cohort_id`    | Yes      | Unique, whitespace-free cohort identifier and analysis-manifest foreign key.                                                                            |
| `genome_build` | Yes      | `GRCh37` or `GRCh38`; selects build-specific harmonisation resources.                                                                                    |
| `ancestry`     | Yes      | Case-sensitive provenance label beginning with a letter or digit and containing only letters, digits, `_`, `.`, or `-`.                                 |
| `pgen`         | By group | PLINK 2 genotype file; supply the complete `pgen`/`psam`/`pvar` group.                                                                                    |
| `psam`         | By group | PLINK 2 sample file.                                                                                                                                     |
| `pvar`         | By group | PLINK 2 variant file ending in `.pvar` or `.pvar.zst`.                                                                                                   |
| `bed`          | By group | PLINK 1 genotype file; supply the complete `bed`/`bim`/`fam` group.                                                                                       |
| `bim`          | By group | PLINK 1 variant file.                                                                                                                                    |
| `fam`          | By group | PLINK 1 sample file.                                                                                                                                     |
| `vcf`          | By group | One `.vcf`, `.vcf.gz`, or `.vcf.bgz` file; an index is not a manifest field.                                                                             |

Populate exactly one complete genotype representation on each row. PLINK 1 and VCF cohorts are converted once to canonical PLINK 2; PLINK 2 cohorts pass through.

### Analysis manifest fields

| Column                  | Required | Description                                                                                                                                                                               |
| ----------------------- | -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `analysis_id`           | Yes      | Unique, whitespace-free result identifier.                                                                                                                                                |
| `cohort_id`             | Yes      | A `cohort_id` declared in the cohort manifest.                                                                                                                                            |
| `trait_id`              | Yes      | Whitespace-free trait identifier retained in provenance.                                                                                                                                  |
| `trait_type`            | Yes      | `quantitative` or `binary`; never inferred from values.                                                                                                                                    |
| `phenotype`             | Yes      | Existing headered phenotype file containing the selected trait.                                                                                                                            |
| `phenotype_column`      | Yes      | Header name of the selected trait column.                                                                                                                                                  |
| `control_value`         | Binary   | Source value recoded to `0`; required for binary traits, forbidden for quantitative traits, and distinct from `case_value`.                                                                |
| `case_value`            | Binary   | Source value recoded to `1`; required for binary traits and forbidden for quantitative traits.                                                                                             |
| `quant_covariates`      | No       | Existing headered quantitative-covariate file.                                                                                                                                             |
| `cat_covariates`        | No       | Existing headered categorical-covariate file.                                                                                                                                              |
| `association_methods`   | By row   | Optional comma-delimited selector: `plink2`, `regenie`, `gcta_fastgwa`, or `ldak_kvik`.                                                                                                    |
| `heritability_methods`  | By row   | Optional comma-delimited selector: `gcta_greml`, `gcta_greml_ldms`, `ldak_reml`, `ldak_he`, or `ldak_pcgc`.                                                                               |
| `population_prevalence` | By route | Number strictly between `0` and `1`; valid only for binary heritability analyses and required by `ldak_pcgc`.                                                                               |

At least one method selector must be populated. Tokens are comma-delimited without spaces and may appear only once. Association-only and heritability-only rows are both valid.

### Runnable examples

[`assets/examples/relational/cohort_manifest.csv`](../assets/examples/relational/cohort_manifest.csv) is shared by the [minimal quantitative](../assets/examples/relational/analysis_manifest_quantitative.csv), [minimal binary](../assets/examples/relational/analysis_manifest_binary.csv), [association-only](../assets/examples/relational/analysis_manifest_association_only.csv), and [heritability-only](../assets/examples/relational/analysis_manifest_heritability_only.csv) examples. They use standard defaults and do not need `--method_options`.

```bash
nextflow run nf-core/gwas \
    -r <VERSION> \
    -profile docker \
    --cohort_manifest assets/examples/relational/cohort_manifest.csv \
    --analysis_manifest assets/examples/relational/analysis_manifest_quantitative.csv \
    --outdir results
```

The [heterogeneous multi-method manifest](../assets/examples/relational/analysis_manifest_heterogeneous.csv) pairs with [per-analysis GCTA and LDAK overrides](../assets/examples/relational/method_options_heterogeneous.json), including stageable resources:

```bash
nextflow run nf-core/gwas \
    -r <VERSION> \
    -profile docker \
    --cohort_manifest assets/examples/relational/cohort_manifest.csv \
    --analysis_manifest assets/examples/relational/analysis_manifest_heterogeneous.csv \
    --method_options assets/examples/relational/method_options_heterogeneous.json \
    --outdir results
```

### Advanced method options

`--method_options` is optional. Its JSON root is keyed by `analysis_id`; each value may contain `gcta`, `ldak` and/or `regenie`. Unlisted analyses receive every default. Unknown analyses, families or options, invalid values, missing resources, and options whose consuming method is not selected are rejected before task submission.

| GCTA option          | Type and default                       | Consumer and constraints                                                                                 |
| -------------------- | -------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `grm_maf`            | Number or `null`; `null`                | Dense `gcta_greml` matrix filter; `0` to `0.5` inclusive when set.                                       |
| `grm_extract`        | Resource path or absent; absent         | Predictor list staged for dense `gcta_greml` matrix construction.                                        |
| `reml_no_constrain`  | Boolean; `false`                        | `gcta_greml` and `gcta_greml_ldms`; disables variance-component constraints.                             |
| `sparse_cutoff`      | Number; `0.05`                          | `gcta_fastgwa` only; `0` to `1` inclusive.                                                               |
| `ld_score_region_kb` | Positive integer; `200`                 | `gcta_greml_ldms` only; LD-score window in kilobases.                                                    |
| `ld_bins`            | Positive integer; `4`                   | `gcta_greml_ldms` only; number of LD-score strata.                                                       |
| `ldms_maf_edges`     | Number array; `[0,0.01,0.05,0.2,0.5]` | `gcta_greml_ldms` only; strictly increasing, at least two values, beginning at `0` and ending at `0.5`. |

| LDAK option          | Type and default                    | Consumer and constraints                                                                                                                                      |
| -------------------- | ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `model`              | String; `human_default`             | Kinship routes; `human_default` or `custom`.                                                                                                                   |
| `power`              | Number; `-0.25`                     | Kinship routes; `-2` to `0`. `human_default` fixes `-0.25`; select `custom` for another value.                                                                  |
| `weights_policy`     | String; `equal`                     | Kinship routes; `equal` passes `--ignore-weights YES`, `default` retains native weighting, and `provided` requires `weights`.                                  |
| `weights`            | Resource path or absent; absent     | Kinship routes (`ldak_reml`, `ldak_he`, `ldak_pcgc`); accepted exactly with `weights_policy: provided`.                                                        |
| `relatedness_filter` | Boolean; `false`                    | Kinship routes; optionally derives an unrelated subset.                                                                                                       |
| `kvik_step1_subset`  | String; `all`                       | `ldak_kvik` only; `all`, `thin_common`, or `provided`.                                                                                                         |
| `predictor_extract`  | Resource path or absent; absent     | `ldak_kvik` only; required exactly with `kvik_step1_subset: provided`.                                                                                          |

| REGENIE option       | Type and default              | Consumer and constraints                                                                                  |
| -------------------- | ----------------------------- | --------------------------------------------------------------------------------------------------------- |
| `step1_bsize`        | Positive integer; `1000`      | Step 1 fitted-model block size; participates in prediction-reuse identity.                               |
| `firth`              | Boolean; `true`               | Binary traits only; enable Firth fallback in Step 2.                                                      |
| `firth_approx`       | Boolean; `true`               | Binary traits only; requires `firth` when explicitly enabled.                                            |
| `firth_p_threshold`  | Number; `0.01`                | Binary traits only; greater than `0` and at most `1`, and requires `firth` when explicitly supplied.      |
| `min_mac`            | Number or `null`; `null`      | Optional Step 2 minimum minor allele count; `null` leaves REGENIE's built-in behavior in effect.          |

For example, this changes the fitted-model block size and Step 2 policy for one binary REGENIE analysis while every unlisted analysis retains the defaults:

```json
{
  "disease": {
    "regenie": {
      "step1_bsize": 2000,
      "firth": false,
      "min_mac": 10
    }
  }
}
```

Resource paths are staged and their contents participate in matrix or prediction reuse identity. `gcta_grm_parts` is operational partitioning and remains configuration/profile-only, never a method option.

The authoritative structural contracts are [`schema_cohort_manifest.json`](../assets/schema_cohort_manifest.json) and [`schema_analysis_manifest.json`](../assets/schema_analysis_manifest.json); relationship-, method-, trait- and resource-aware diagnostics come from the central preflight validator.

### Validation diagnostics

Structural failures name the manifest and invalid column. Cross-row preflight failures additionally name the CSV row and `cohort_id` or `analysis_id`: examples include an incomplete or second genotype group, conflicting duplicate cohorts, duplicate analyses, orphan `cohort_id` references, unknown or repeated method tokens, invalid binary coding, and route-inapplicable prevalence. Method-options failures name the JSON document, `analysis_id` and fully qualified option such as `gcta.sparse_cutoff` or `ldak.weights`; malformed JSON, unknown keys, invalid types/ranges and missing stageable resources all fail before task submission.

### Phenotype normalisation

The pipeline normalises each selected phenotype to a common two-identifier-plus-trait layout. Binary
source values matching `control_value` and `case_value` become `0` and `1`; missing values and unmatched
binary values become `NA`. Quantitative values must be numeric. Quantitative and categorical covariates
remain distinct for tools with separate native interfaces.

### Run-level defaults

| Parameter or behaviour                                                     | Default and rationale                                                                                                                                                                                                                                                                      |
| -------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| PLINK 2 binary association                                                 | Firth fallback is enabled so separated or sparse binary-trait tests can still produce estimates. Binary phenotypes are passed with `--1` because the common normalised coding is `0`/`1`/`NA`; covariates are variance-standardised to prevent numerical failure when their scales differ. |
| `--regenie_step1_mode`                                                     | `standard`, the simplest one-task Step 1. Use `chunked` with `--regenie_step1_jobs` when a large cohort needs REGENIE's split-L0/run-L0/run-L1 execution family.                                                                                                                           |
| `--regenie_lowmem`                                                         | `true`, keeping Step 1's temporary prediction blocks in the task work directory to reduce memory use.                                                                                                                                                                                      |
| REGENIE scientific method options                                          | Per-analysis `regenie.*` defaults enable approximate Firth fallback below `0.01` for binary traits and leave `min_mac` unset so REGENIE's own versioned policy applies.                                                                                                                     |
| GWASLab reference parameters                                               | Unset. Every association output is still standardised; reference-dependent allele checks, rsID assignment and strand inference run only when you provide the corresponding build-specific FASTA or VCF resource.                                                                           |
| Save controls                                                              | Off. Intermediates stay out of the results directory unless explicitly requested, avoiding unexpectedly large published output.                                                                                                                                                            |

The four opt-in save controls are:

- `--save_prepared_genotypes`: publish PLINK 2 bundles that the pipeline converted under `genotypes/<cohort_id>/`.
- `--save_normalised_phenotypes`: publish headered normalised phenotype and covariate files under `phenotypes/<analysis_id>/`.
- `--save_relatedness_matrices`: publish merged GCTA or LDAK matrix bundles under `quality_control/relatedness_matrices/<key>/`.
- `--save_association_predictions`: publish reusable REGENIE and LDAK-KVIK Step 1 bundles under `intermediates/association_predictions/<method>/<analysis_id>/`.

See the [output documentation](output.md) for the exact files and publication exceptions.

## Running the pipeline

The typical command for running the pipeline is:

```bash
nextflow run nf-core/gwas \
    -r <VERSION> \
    -profile docker \
    --cohort_manifest ./cohorts.csv \
    --analysis_manifest ./analyses.csv \
    --outdir ./results
```

`-r <VERSION>` is strongly recommended for reproducibility. Choose the software profile appropriate for your system; see [`-profile`](#-profile).

The pipeline creates the following in your launch directory:

```bash
work                # Nextflow task work directories
<OUTDIR>            # Published results selected by --outdir
.nextflow_log       # Nextflow execution log
```

For repeated runs, place pipeline parameters in a YAML or JSON file and supply it with `-params-file`:

```bash
nextflow run nf-core/gwas -r <VERSION> -profile docker -params-file params.yaml
```

```yaml title="params.yaml"
cohort_manifest: "./cohorts.csv"
analysis_manifest: "./analyses.csv"
outdir: "./results/"
```

You can also generate parameter files with [nf-core/launch](https://nf-co.re/launch).

> [!WARNING]
> Do not use `-c <file>` to specify pipeline parameters. Custom configuration files loaded with `-c` are for process resources, infrastructure settings and module arguments; use CLI flags or `-params-file` for parameters.

## Updating

Nextflow caches pipeline code after the first run. Update the cached copy with:

```bash
nextflow pull nf-core/gwas
```

## Reproducibility

Pin the release with `-r`, retain the exact cohort and analysis manifests, optional method-options document and parameter file, and archive `pipeline_info/` with your results. Reusing the same release, inputs and parameters also lets `-resume` recover cached tasks.

Find release numbers on the [nf-core/gwas releases page](https://github.com/nf-core/gwas/releases). The run's pipeline and tool versions are recorded in the published reports described in [Pipeline information](output.md#pipeline-information).

## Core Nextflow arguments

> [!NOTE]
> Nextflow options use one hyphen; pipeline parameters use two.

### `-profile`

Use `-profile` to select configuration for your software or compute environment. Multiple profiles are comma-separated and applied from left to right, for example `-profile test,docker`.

The generic software profiles include `docker`, `singularity`, `apptainer`, `podman`, `shifter`, `charliecloud`, `conda`, `mamba` and `wave`. Docker or Singularity/Apptainer is recommended for reproducibility. If no profile is supplied, every tool must already be available on `PATH`.

The pipeline also loads institutional profiles from [nf-core/configs](https://github.com/nf-core/configs#documentation).

### `-resume`

Add `-resume` when restarting a run. Nextflow reuses cached tasks whose inputs, code and configuration have not changed. You can resume a named run with `-resume <run-name>`; use `nextflow log` to list run names.

### `-c`

Use `-c <file>` to load a Nextflow configuration file for infrastructure, executors and process resources. See the [nf-core configuration documentation](https://nf-co.re/docs/running/configuration).

## Custom configuration

### Resource requests

The pipeline assigns default CPU, memory and time requests by process label and retries selected resource-related failures with larger requests. Use [`--max_cpus`, `--max_memory` and `--max_time`](https://nf-co.re/docs/running/configuration/nextflow-for-your-system#set-max-resources) to cap requests, or use a custom configuration file to [customise individual processes](https://nf-co.re/docs/running/configuration/nextflow-for-your-system#customize-process-resources).

### Custom containers

To override a tool container or Conda environment, follow the nf-core guidance for [updating tool versions](https://nf-co.re/docs/running/configuration/nextflow-for-your-system#update-tool-versions). Record overrides because they change the software provenance of your run.

### Custom tool arguments

Use a custom configuration file to add supported process-specific arguments as described in [customising tool arguments](https://nf-co.re/docs/running/configuration/nextflow-for-your-system#modifying-tool-arguments). Do not use this mechanism to reach methods outside the documented selector lists.

### nf-core/configs

If a configuration is useful across your institution, test it locally and consider contributing it to [nf-core/configs](https://github.com/nf-core/configs). Include the corresponding documentation and profile registration in that repository.

## Running in the background

Nextflow must keep running to submit and supervise jobs. Use `-bg`, a detached `screen` or `tmux` session, or a cluster job appropriate to your infrastructure. With `-bg`, Nextflow writes its console output to a log file.

## Nextflow memory requirements

The Nextflow Java process can require substantial memory when coordinating a large run. Limit its heap with `NXF_OPTS`, for example:

```bash
export NXF_OPTS='-Xms1g -Xmx4g'
```
