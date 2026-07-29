# nf-core/gwas: Output

## Introduction

This document describes the output produced by the pipeline. Most of the plots are taken from the MultiQC report, which summarises results at the end of the pipeline.

The directories listed below will be created in the results directory after the pipeline has finished. All paths are relative to the top-level results directory.

<!-- TODO nf-core: Write this documentation describing your workflow's output -->

## Pipeline overview

The pipeline is built using [Nextflow](https://www.nextflow.io/) and processes data using the following steps:

- [Association](#association) - Association test results, one directory per method
- [Summary statistics](#summary-statistics) - Harmonised summary statistics, one directory per analysis
- [MultiQC](#multiqc) - Aggregate report describing results and QC from the whole pipeline
- [Pipeline information](#pipeline-information) - Report metrics generated during the workflow execution

### Association

<details markdown="1">
<summary>Output files</summary>

- `association/plink2/<analysis_id>/`
  - `<analysis_id>.plink2.glm.linear`: PLINK 2 `--glm` results for a quantitative trait.
  - `<analysis_id>.plink2.glm.logistic.hybrid`: PLINK 2 `--glm` results for a binary trait. The `.hybrid` extension indicates that Firth fallback was available, which the pipeline enables by default.

</details>

[PLINK 2](https://www.cog-genomics.org/plink/2.0/assoc) `--glm` output is published exactly as PLINK 2 wrote it; only the filename changes, because PLINK 2 always embeds the phenotype name in it and the pipeline renames the file to follow the analysis-identifier-then-method grammar used throughout the published output. Results include the `A1_FREQ` (allele frequency) and `OBS_CT` (sample count) columns.

The phenotype and covariate files the pipeline normalises for each analysis are intermediates and are not published unless `--save_normalised_phenotypes` is set, in which case they appear under `phenotypes/<analysis_id>/`.

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
