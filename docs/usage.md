# nf-core/gwas: Usage

## :warning: Please read this documentation on the nf-core website: [https://nf-co.re/gwas/usage](https://nf-co.re/gwas/usage)

> _Documentation of pipeline parameters is generated automatically from the pipeline schema and can no longer be found in markdown files._

## Introduction

nf-core/gwas runs association and individual-level heritability analyses from prepared human genotypes, phenotypes and optional covariates. One samplesheet row is one analysis unit: one cohort paired with one trait. A row can fan out to several methods, while genotype preparation and relatedness matrices are reused where their inputs and construction settings agree.

> [!IMPORTANT]
> Genotypes must be prepared before you run the pipeline. In particular, sample and variant identifiers, alleles, coordinates, genome build, missingness, call quality, frequency filters and population selection must already be suitable for analysis. The pipeline converts accepted genotype encodings into the formats required by its methods, but it does not perform genotype quality control.

## Samplesheet input

Pass a comma-separated samplesheet to `--input`:

```bash
--input ./samplesheet.csv
```

The header must contain all 35 columns below. Column order is not significant, but every header is mandatory even when its cells are optional; leave an unused cell empty. File paths may be local paths or remote URLs accepted by Nextflow. When a selector contains several methods, quote the comma-delimited CSV cell.

Supply exactly one complete genotype encoding per row:

- PLINK 2: populate `pgen`, `psam` and `pvar`.
- PLINK 1: populate `bed`, `bim` and `fam`.
- VCF: populate `vcf`; `vcf_index` is optional and is currently declared for completeness but not consumed by conversion.

Do not populate fields from two genotype groups on the same row, and do not provide only part of a three-file PLINK bundle. Rows sharing a `cohort_id` must describe the same genotype source.

A quantitative-trait analysis using PLINK 2 input may look like this:

```csv title="samplesheet.csv"
analysis_id,cohort_id,trait_id,trait_type,genome_build,ancestry,pgen,psam,pvar,bed,bim,fam,vcf,vcf_index,phenotype,phenotype_column,control_value,case_value,quant_covariates,cat_covariates,association_methods,heritability_methods,population_prevalence,sample_prevalence,ldak_model,ldak_power,ldak_weights,ldak_relatedness_filter,ldak_kvik_step1_subset,ldak_kvik_step1_extract,gcta_grm_parts,gcta_sparse_cutoff,gcta_ld_score_region_kb,gcta_ld_bins,gcta_ldms_maf_edges
example_pgen_qt,example_pgen,QT,quantitative,GRCh37,EUR,https://raw.githubusercontent.com/nf-core/test-datasets/gwas/results/fixtures/genotypes/example_all.pgen,https://raw.githubusercontent.com/nf-core/test-datasets/gwas/results/fixtures/genotypes/example_all.psam,https://raw.githubusercontent.com/nf-core/test-datasets/gwas/results/fixtures/genotypes/example_all.pvar,,,,,,https://raw.githubusercontent.com/nf-core/test-datasets/gwas/results/fixtures/pheno_cov/example.pheno,QT,,,https://raw.githubusercontent.com/nf-core/test-datasets/gwas/results/fixtures/pheno_cov/example.qcovar,https://raw.githubusercontent.com/nf-core/test-datasets/gwas/results/fixtures/pheno_cov/example.catcovar,plink2,gcta_greml,,,,,,,,,1,,,,
```

| Column                    | Description                                                                                                                                                                                                      |
| ------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `analysis_id`             | Required unique, whitespace-free identifier for this analysis unit. It is the focal identifier in result paths and filenames.                                                                                    |
| `cohort_id`               | Required whitespace-free cohort identifier. Several trait rows may share it, but all such rows must declare the same genotype source.                                                                            |
| `trait_id`                | Required whitespace-free trait identifier.                                                                                                                                                                       |
| `trait_type`              | Required trait type: `quantitative` or `binary`. The pipeline never infers this from phenotype values or prevalence.                                                                                             |
| `genome_build`            | Required genotype coordinate system: `GRCh37` or `GRCh38`. It selects any build-specific GWASLab reference resources.                                                                                            |
| `ancestry`                | Optional case-sensitive ancestry label containing letters, digits, underscores, dots or dashes. It is carried in analysis metadata for provenance.                                                               |
| `pgen`                    | PLINK 2 genotype file ending in `.pgen`; populate with `psam` and `pvar` only.                                                                                                                                   |
| `psam`                    | PLINK 2 sample file ending in `.psam`; populate with `pgen` and `pvar` only.                                                                                                                                     |
| `pvar`                    | PLINK 2 variant file ending in `.pvar` or `.pvar.zst`; populate with `pgen` and `psam` only.                                                                                                                     |
| `bed`                     | PLINK 1 genotype file ending in `.bed`; populate with `bim` and `fam` only.                                                                                                                                      |
| `bim`                     | PLINK 1 variant file ending in `.bim`; populate with `bed` and `fam` only.                                                                                                                                       |
| `fam`                     | PLINK 1 sample file ending in `.fam`; populate with `bed` and `bim` only.                                                                                                                                        |
| `vcf`                     | VCF genotype file ending in `.vcf`, `.vcf.gz` or `.vcf.bgz`; leave both PLINK groups empty. The pipeline converts it once per cohort.                                                                            |
| `vcf_index`               | Optional `.tbi` or `.csi` index for `vcf`. It is validated if supplied, but the current VCF converter does not consume it.                                                                                       |
| `phenotype`               | Required headered phenotype file containing the selected trait. The first two columns must identify family and individual consistently with the genotype sample file.                                            |
| `phenotype_column`        | Required name of the trait column in `phenotype`, even when that file contains only one trait.                                                                                                                   |
| `control_value`           | Source value representing controls. Required for `binary` rows and rejected for `quantitative` rows; numeric and text tokens are accepted.                                                                       |
| `case_value`              | Source value representing cases. Required for `binary` rows and rejected for `quantitative` rows; numeric and text tokens are accepted.                                                                          |
| `quant_covariates`        | Optional headered file of prepared quantitative covariates.                                                                                                                                                      |
| `cat_covariates`          | Optional headered file of prepared categorical covariates. Use non-numeric labels for categorical levels with more than two categories so downstream tools cannot interpret their codes as a quantitative scale. |
| `association_methods`     | Optional comma-delimited list drawn from `plink2`, `regenie`, `gcta_fastgwa`, `ldak_kvik`. There is no run-wide default list.                                                                                    |
| `heritability_methods`    | Optional comma-delimited list drawn from `gcta_greml`, `gcta_greml_ldms`, `ldak_reml`, `ldak_he`, `ldak_pcgc`. There is no run-wide default list.                                                                |
| `population_prevalence`   | Optional population prevalence strictly between `0` and `1` for a binary-trait liability-scale estimate. It is always required by `ldak_pcgc` and rejected on quantitative rows.                                 |
| `sample_prevalence`       | Optional analysed-sample case proportion strictly between `0` and `1`. Supply it only with `population_prevalence`. The current pipeline validates and carries it in analysis metadata but does not pass it to an estimator. |
| `ldak_model`              | LDAK kinship model: `human_default` or `custom`. It defaults to `human_default`, the documented model for human data.                                                                                            |
| `ldak_power`              | Predictor-variance power from `-2` to `0`. It defaults to `-0.25`, the documented human-model value; `human_default` requires this value, while `custom` lets you choose another.                                |
| `ldak_weights`            | Optional LDAK predictor-weights file. An empty cell uses explicit equal weights so the weighting policy is deterministic rather than an implicit programme choice.                                               |
| `ldak_relatedness_filter` | Boolean selecting an unrelated subset for this analysis's LDAK heritability estimator. It defaults to `false` so the declared analysis population is retained unless you request filtering.                      |
| `ldak_kvik_step1_subset`  | Required with `ldak_kvik`: `all`, `thin_common` or `provided`. It has no default because predictor selection is a scientific choice.                                                                             |
| `ldak_kvik_step1_extract` | Predictor list required only when `ldak_kvik_step1_subset` is `provided`.                                                                                                                                        |
| `gcta_grm_parts`          | Positive integer number of parts for a GCTA relatedness-matrix build. It is required with every GCTA route and has no default because it is an explicit memory-control choice.                                   |
| `gcta_sparse_cutoff`      | Relatedness cutoff for the sparse fastGWA-MLM matrix. It defaults to `0.05`, following the official GCTA fastGWA example.                                                                                        |
| `gcta_ld_score_region_kb` | GREML-LDMS LD-score region width in kilobases. It defaults to `200`, following the official GCTA LDMS example.                                                                                                   |
| `gcta_ld_bins`            | Number of GREML-LDMS individual-SNP LD-score strata. It defaults to `4`, which divides the scores into quartiles.                                                                                                |
| `gcta_ldms_maf_edges`     | Semicolon-delimited, strictly increasing MAF interval boundaries required for `gcta_greml_ldms`. They must start at `0` and end at `0.5`; semicolons avoid conflicting with the commas used by method lists.     |

At least one of `association_methods` or `heritability_methods` must be non-empty. A method-specific field is accepted only when its corresponding method is selected.

An [example samplesheet](../assets/samplesheet.csv) containing all three genotype encodings is provided with the pipeline.

### Phenotype normalisation

The pipeline normalises each selected phenotype to a common two-identifier-plus-trait layout. Binary source values matching `control_value` and `case_value` become `0` and `1`; missing values and unmatched binary values become `NA`. Quantitative values must be numeric. Quantitative and categorical covariates remain distinct for tools with separate native interfaces, and a merged covariate file is also prepared where required.

> [!WARNING]
> The two validation passes number samplesheet rows differently. nf-schema reports `Entry N`, counting data rows from 1; the pipeline preflight reports `row N`, counting the header as row 1. The same bad CSV line can therefore be reported as `Entry 3` and `row 4`. These messages point to the same data row.

### Run-level defaults

The samplesheet table records all row-level defaults and their rationales. The remaining scientific or storage-affecting run defaults are:

| Parameter or behaviour                                                     | Default and rationale                                                                                                                                                                                                                                                                      |
| -------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| PLINK 2 binary association                                                 | Firth fallback is enabled so separated or sparse binary-trait tests can still produce estimates. Binary phenotypes are passed with `--1` because the common normalised coding is `0`/`1`/`NA`; covariates are variance-standardised to prevent numerical failure when their scales differ. |
| `--regenie_step1_mode`                                                     | `standard`, the simplest one-task Step 1. Use `chunked` with `--regenie_step1_jobs` when a large cohort needs REGENIE's split-L0/run-L0/run-L1 execution family.                                                                                                                           |
| `--regenie_lowmem`                                                         | `true`, keeping Step 1's temporary prediction blocks in the task work directory to reduce memory use.                                                                                                                                                                                      |
| `--regenie_firth`, `--regenie_firth_approx`, `--regenie_firth_p_threshold` | `true`, `true`, and `0.01`. Binary Step 2 uses the faster approximate Firth correction for tests crossing the configured significance threshold, reducing separation bias without applying the cost to every variant.                                                                      |
| `--regenie_min_mac`                                                        | Unset, so REGENIE's own versioned minimum-minor-allele-count policy applies instead of the pipeline silently imposing a scientific filter.                                                                                                                                                 |
| GWASLab reference parameters                                               | Unset. Every association output is still standardised; reference-dependent allele checks, rsID assignment and strand inference run only when you provide the corresponding build-specific FASTA or VCF resource.                                                                           |
| Save controls                                                              | Off. Intermediates stay out of the results directory unless explicitly requested, avoiding unexpectedly large published output.                                                                                                                                                            |

The four opt-in save controls are:

- `--save_prepared_genotypes`: publish PLINK 2 bundles that the pipeline converted under `genotypes/<cohort_id>/`.
- `--save_normalised_phenotypes`: publish headered normalised phenotype and covariate files under `phenotypes/<analysis_id>/`.
- `--save_relatedness_matrices`: publish merged GCTA or LDAK matrix bundles under `quality_control/relatedness_matrices/<key>/`.
- `--save_regenie_predictions`: publish the reusable REGENIE Step 1 prediction bundle under `intermediates/regenie/<analysis_id>/`.

See the [output documentation](output.md) for the exact files and publication exceptions.

## Running the pipeline

The typical command for running the pipeline is:

```bash
nextflow run nf-core/gwas \
    -r <VERSION> \
    -profile docker \
    --input ./samplesheet.csv \
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
input: "./samplesheet.csv"
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

Pin the release with `-r`, retain the exact samplesheet and parameter file, and archive `pipeline_info/` with your results. Reusing the same release, inputs and parameters also lets `-resume` recover cached tasks.

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
