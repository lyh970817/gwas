# GenomicSEM LDSC integration research

Research checked on 2026-08-01 against GenomicSEM `master` commit [`0a63ac0`](https://github.com/GenomicSEM/GenomicSEM/commit/0a63ac0ea01b61d28bd17e4a204e0fa561ce5040), dated 2026-06-02. GenomicSEM describes itself as alpha software; pin an exact source revision rather than installing a moving branch.

## Decision summary

- **Bioconda:** GenomicSEM is not currently available from Bioconda. Both `conda search --override-channels -c bioconda r-genomicsem` and a wildcard search for `*genomic*sem*` returned no entries on 2026-08-01; the corresponding Anaconda package API endpoint returns 404. Upstream documents installation from GitHub.
- **Parallelism:** `munge()` can process multiple files concurrently with a local PSOCK worker cluster. `ldsc()` itself has no `parallel` or `cores` argument and its implementation processes trait pairs and jackknife blocks serially. Large multivariate LDSC jobs therefore do not scale across `task.cpus` through GenomicSEM itself.
- **GWASLab:** The pipeline's GWASLab output is a good canonical input layer, but it is not a replacement for LDSC munging. GenomicSEM still needs HapMap3 allele-reference filtering and produces its own `SNP`, `N`, `Z`, `A1`, `A2` `.sumstats.gz` contract. The current GWASLab output is directly recognisable for routes that retain `P`; the REGENIE route requires an explicit `MLOG10P`-to-`P` adaptation because GenomicSEM `munge()` does not recognise `MLOG10P`.
- **Reference data:** At minimum, the workflow needs an uncompressed HapMap3 `w_hm3.snplist` for munging and ancestry-matched LDSC regression/weight files for `ldsc()`. These are separate from GWASLab's optional FASTA, rsID VCF and strand VCF resources.

## 1. Packaging and installation

The [upstream README](https://github.com/GenomicSEM/GenomicSEM/blob/0a63ac0ea01b61d28bd17e4a204e0fa561ce5040/README.md) installs the package with `devtools::install_github("GenomicSEM/GenomicSEM")`. The upstream [`DESCRIPTION`](https://github.com/GenomicSEM/GenomicSEM/blob/0a63ac0ea01b61d28bd17e4a204e0fa561ce5040/DESCRIPTION) reports package version `0.0.5`, while the README calls the code `0.0.5c`; neither identifier uniquely captures the current 2026 source state.

The package is absent from the current Bioconda `linux-64` and `noarch` indexes. The previously indexed-looking URL `https://anaconda.org/bioconda/r-genomicsem` now resolves to a package-not-found page, and [`api.anaconda.org/package/bioconda/r-genomicsem`](https://api.anaconda.org/package/bioconda/r-genomicsem) returns 404.

**Integration consequence:** there is no current Bioconda package that can be declared as `bioconda::r-genomicsem=<version>` in an nf-core module `environment.yml`. A reproducible implementation needs either:

1. a new Bioconda recipe, which is the clean upstream-compatible route; or
2. a pipeline-local container that installs a fixed GenomicSEM commit and records that commit as its version.

Installing unpinned `master` at runtime is not reproducible and should not be used.

## 2. Parallel computation and scale

### Munging

The current [`munge()` implementation](https://github.com/GenomicSEM/GenomicSEM/blob/0a63ac0ea01b61d28bd17e4a204e0fa561ce5040/R/munge.R) has `parallel = FALSE` and `cores = NULL` defaults. When enabled, it:

- creates a local PSOCK cluster with `doParallel` and `foreach`;
- parallelises **across input files**, not within one summary-statistics file;
- caps the worker count at the number of input files;
- disables parallelism for a single file; and
- uses `detectCores() - 1` when `cores` is omitted.

The checked-in [`munge.Rd` manual](https://github.com/GenomicSEM/GenomicSEM/blob/0a63ac0ea01b61d28bd17e4a204e0fa561ce5040/man/munge.Rd) incorrectly says the parallel default is `TRUE`; the executable function signature is the reliable value.

The [official patch notes](https://github.com/GenomicSEM/GenomicSEM/blob/0a63ac0ea01b61d28bd17e4a204e0fa561ce5040/PATCHNOTES.md#parallel-munge-test) report munging files of approximately four million variants and 17 columns each. On the documented Linux server, 12 files took 772 seconds serially, 273 seconds with four workers, 209 seconds with eight workers and 147 seconds with 12 workers. This is useful concurrency, but not linear scaling; 12 workers delivered about a 5.3-fold speed-up. Each PSOCK worker reads and holds a separate large input table, so memory and I/O pressure increase with concurrency.

For Nextflow, the safer scaling model is to scatter one summary-statistics file per task with one CPU and let the executor run files concurrently. This gives process-level memory isolation and scheduler-visible resource use. A grouped `munge()` task is only justified if preserving GenomicSEM's multi-file invocation is more important than those workflow controls; in that case, pass `cores = task.cpus` explicitly.

### LDSC

The current [`ldsc()` function](https://github.com/GenomicSEM/GenomicSEM/blob/0a63ac0ea01b61d28bd17e4a204e0fa561ce5040/R/ldsc.R) exposes no parallel controls. It reads chromosome reference files with serial `lapply`, reads each trait serially, then evaluates heritabilities and genetic covariances in nested trait loops. With $T$ traits it fits $T(T+1)/2$ univariate/bivariate regressions. For more than 18 traits, it automatically increases the jackknife block count to one more than the number of non-redundant elements in the enlarged covariance matrix; the patch notes warn that very high block counts can themselves become problematic.

No upstream LDSC benchmark was found. The package's published scaling tables cover `munge()` and per-variant `userGWAS()`/`commonfactorGWAS()`, not `ldsc()`. Consequently, there is no evidence for calling GenomicSEM `ldsc()` a strongly parallel or proven high-throughput LDSC implementation. It is reasonable for ordinary trait sets, but large trait panels scale at least quadratically in the number of trait pairs and run primarily in one R process.

The [upstream Linux guidance](https://github.com/GenomicSEM/GenomicSEM/blob/0a63ac0ea01b61d28bd17e4a204e0fa561ce5040/README.md#parallel-performance-on-linux) also warns about nested BLAS/OpenMP oversubscription. It recommends setting `OPENBLAS_NUM_THREADS`, `OMP_NUM_THREADS`, `MKL_NUM_THREADS`, `NUMEXPR_NUM_THREADS` and `VECLIB_MAXIMUM_THREADS` to `1`, then controlling parallelism only through GenomicSEM's `cores` argument. Without this, the authors observed `cores × machine cores` R threads and severe slowdown. This matters for `munge()` and later GenomicSEM GWAS functions; it does not add parallelism to `ldsc()`.

**Pipeline recommendation:** keep `ldsc()` as a grouped trait-set process with one CPU unless a benchmark on the intended BLAS proves otherwise. Parallelise independent trait sets or analyses at the Nextflow level. Do not advertise `task.cpus > 1` as LDSC acceleration.

## 3. Input format, munging and references

### What GenomicSEM `munge()` consumes

The executable [`munge()`](https://github.com/GenomicSEM/GenomicSEM/blob/0a63ac0ea01b61d28bd17e4a204e0fa561ce5040/R/munge.R) accepts one or more tabular GWAS files plus:

- `hm3`: an allele reference with `SNP`, `A1` and `A2` columns;
- `trait.names`: output identities;
- `N`: optional per-trait sample sizes, used to override a file's sample-size column;
- optional INFO and MAF thresholds, defaulting to 0.9 and 0.01; and
- optional explicit column-name mappings.

The [manual](https://github.com/GenomicSEM/GenomicSEM/blob/0a63ac0ea01b61d28bd17e4a204e0fa561ce5040/man/munge.Rd) recommends the original LDSC developers' uncompressed [`w_hm3.snplist`](https://data.broadinstitute.org/alkesgroup/LDSCORE/w_hm3.snplist.bz2). The implementation merges on rsID, aligns effect direction to the HapMap3 alleles, removes variants not present in that reference, applies INFO/MAF filters when those columns exist, derives $Z = \operatorname{sign}(\text{effect})\sqrt{\chi^2_1(P)}$, and writes `SNP`, `N`, `Z`, `A1`, `A2` as `<trait>.sumstats.gz`.

The current alias table recognises the pipeline's GWASLab names:

| GenomicSEM role | Recognised GWASLab column |
| --- | --- |
| Variant identifier | `SNPID` |
| Effect allele | `EA` |
| Other allele | `NEA` |
| Effect | `BETA` or `OR` |
| Sample size | `N` or `N_EFF` |
| Allele frequency / MAF input | `EAF` |
| P value | `P` |
| Z statistic | `Z` |

GWASLab `STATUS`, `CHR`, `POS` and `SE` are not used by GenomicSEM `munge()`. Although `Z` is recognised generally, the current munging implementation calculates its output Z from `P` and the sign of the effect. Therefore a valid effect and `P` are required in practice.

### Is the current GWASLab output sufficient?

**As a standardisation layer: mostly. As the complete LDSC munging step: no.**

The pipeline already emits `SNPID`, `EA`, `NEA`, `BETA`, `N` and `EAF`, all of which GenomicSEM recognises. PLINK 2, GCTA and LDAK-KVIK harmonised outputs also retain `P`, so they can be passed to `munge()` without renaming. This still performs an additional, scientifically distinct HapMap3 selection and allele-alignment step.

The documented REGENIE route retains native `LOG10P` as GWASLab `MLOG10P` rather than `P`. GenomicSEM does not recognise `MLOG10P`, and its current `munge()` cannot derive Z from `BETA` and `SE`. REGENIE input therefore needs a deliberate adapter that materialises `P` (with defined handling for extreme values), or a dedicated LDSC formatter that derives signed Z directly and performs the same HapMap3 checks. This must be tested numerically; silently treating `MLOG10P` as `P` would be wrong.

GWASLab reference harmonisation remains useful before GenomicSEM:

- If valid rsIDs are already present, GenomicSEM can merge them to `w_hm3.snplist` directly.
- If rsIDs are absent, the pipeline's GWASLab rsID reference VCF should be supplied. GWASLab-generated chromosome-position identifiers will not match GenomicSEM's rsID merge.
- FASTA and strand-reference VCF inputs can improve allele and palindromic-strand checks, but they do not replace the HapMap3 allele list or LDSC LD-score bundle.

### Additional LDSC inputs

After munging, [`ldsc()`](https://github.com/GenomicSEM/GenomicSEM/blob/0a63ac0ea01b61d28bd17e4a204e0fa561ce5040/man/ldsc.Rd) requires:

1. a vector of GenomicSEM `.sumstats.gz` files;
2. `sample.prev` for binary traits and `NA` for continuous traits;
3. `population.prev` for binary traits and `NA` for continuous traits;
4. an `ld` directory with original-LDSC-format chromosome files such as `<chr>.l2.ldscore.gz` and `<chr>.l2.M_5_50`; and
5. a `wld` directory containing regression weights, unless the selected reference bundle deliberately serves both roles.

The [official summary-data guidance](https://github.com/GenomicSEM/GenomicSEM/wiki/2.-Important-resources-and-key-information) requires ancestrally homogeneous GWAS inputs and ancestry-matched LD scores. The European HapMap3/1000 Genomes resources used in examples must not be applied by default to other ancestry groups.

Sample size also needs explicit scientific policy. GenomicSEM warns when effective sample-size columns are detected, and its patch notes recommend the sum of effective sample sizes with sample prevalence 0.5 for the documented binary-trait liability conversion. GWASLab standardisation does not determine the correct sample size or population prevalence. Those values need to come from the analysis metadata and must stay aligned with trait order.

## Proposed integration boundary

A clean pipeline design is:

1. retain GWASLab harmonisation as the common association-output standardisation step;
2. add a small GenomicSEM-input adapter only where canonical fields are missing, especially REGENIE `MLOG10P`;
3. run HapMap3 munging once per trait, scattered by Nextflow;
4. group the munged traits by the intended multivariate analysis identity;
5. run one GenomicSEM `ldsc()` task per group with ancestry-matched `ld`/`wld` resources and ordered prevalence metadata; and
6. record the exact GenomicSEM source commit and reference bundle provenance in outputs.

This preserves one canonical summary-statistics representation while keeping the LDSC-specific scientific filters and reference data explicit.

## Sources

- [GenomicSEM repository and installation README](https://github.com/GenomicSEM/GenomicSEM/tree/0a63ac0ea01b61d28bd17e4a204e0fa561ce5040)
- [GenomicSEM package metadata](https://github.com/GenomicSEM/GenomicSEM/blob/0a63ac0ea01b61d28bd17e4a204e0fa561ce5040/DESCRIPTION)
- [`munge()` source](https://github.com/GenomicSEM/GenomicSEM/blob/0a63ac0ea01b61d28bd17e4a204e0fa561ce5040/R/munge.R) and [worker implementation](https://github.com/GenomicSEM/GenomicSEM/blob/0a63ac0ea01b61d28bd17e4a204e0fa561ce5040/R/munge_main.R)
- [`munge()` reference manual](https://github.com/GenomicSEM/GenomicSEM/blob/0a63ac0ea01b61d28bd17e4a204e0fa561ce5040/man/munge.Rd)
- [`ldsc()` source](https://github.com/GenomicSEM/GenomicSEM/blob/0a63ac0ea01b61d28bd17e4a204e0fa561ce5040/R/ldsc.R) and [reference manual](https://github.com/GenomicSEM/GenomicSEM/blob/0a63ac0ea01b61d28bd17e4a204e0fa561ce5040/man/ldsc.Rd)
- [GenomicSEM patch notes and official performance tables](https://github.com/GenomicSEM/GenomicSEM/blob/0a63ac0ea01b61d28bd17e4a204e0fa561ce5040/PATCHNOTES.md)
- [GenomicSEM guidance on GWAS inputs and ancestry-matched LD scores](https://github.com/GenomicSEM/GenomicSEM/wiki/2.-Important-resources-and-key-information)
- [Original LDSC HapMap3 allele reference](https://data.broadinstitute.org/alkesgroup/LDSCORE/w_hm3.snplist.bz2)
- [Current pipeline GWASLab output contract](output.md#gwaslab)
