# LDSC pipeline integration research

Research checked on 2026-08-01. The original LDSC repository was checked at [`bulik/ldsc@2fdeeb3`](https://github.com/bulik/ldsc/commit/2fdeeb3b44379408794154993dbd6101b8946b7e); its README now directs Python 3 users to [`CBIIT/ldsc`](https://github.com/CBIIT/ldsc). The CBIIT `ldsc39` branch was checked at [`6c67395`](https://github.com/CBIIT/ldsc/commit/6c673952cee74bd5c57aef1555a03b1c015399a0).

## Decision summary

- **Bioconda:** yes, but only as the legacy `ldsc=1.0.1` recipe from `bulik/ldsc`. Its current build `1.0.1-2` requires Python `<3` and pandas `<0.21.0`. No `ldsc39` Bioconda package exists. The modern CBIIT Python 3 branch therefore has no current Bioconda execution path.
- **Parallelism:** LDSC has no application-level worker/thread option, and genetic-correlation targets are processed in a serial Python loop. It does, however, call NumPy `dot`, `lstsq` and `solve`; those kernels can use multiple native threads when NumPy is linked to a threaded BLAS/LAPACK. The available LDSC BioContainer uses OpenBLAS. Munging remains effectively single-core, while LD-score calculation (`--l2`) has the clearest multi-core kernels. Set BLAS thread variables to `task.cpus`, benchmark representative inputs, and obtain coarse-grained concurrency by scattering traits, analyses and chromosomes in Nextflow.
- **GWASLab:** GWASLab is sufficient as the pipeline's common harmonisation layer, but the file currently emitted by `GWASLAB_HARMONIZE` is not a final LDSC `.sumstats.gz`. It has not undergone LDSC's HapMap3 selection/allele merge, and REGENIE results retain `MLOG10P` instead of `P`. Use a distinct LDSC munging step or deliberately adopt GWASLab's beta LDSC implementation; do not pass the existing `.gwaslab.tsv.gz` directly to `ldsc.py`.
- **Reference data:** regression always needs ancestry-matched reference LD scores and regression weights. Recommended standalone munging additionally needs the HapMap3 `w_hm3.snplist` allele list. GWASLab bundles a build-specific copy of that HapMap3 list, but it does not bundle ancestry-matched LD-score/weight panels.

## 1. Packaging and executable choice

### Bioconda status

The [Bioconda recipe page](https://bioconda.github.io/recipes/ldsc/README.html), [package API](https://api.anaconda.org/package/bioconda/ldsc), and [recipe source](https://github.com/bioconda/bioconda-recipes/blob/master/recipes/ldsc/meta.yaml) agree on:

- package: `bioconda::ldsc=1.0.1`;
- latest build: `1.0.1-2`;
- source: `bulik/ldsc` commit `12e2687ec9bba39da2139d14f6d1944a23d5774a`;
- runtime: Python `<3`, pandas `<0.21.0`, NumPy, SciPy, bitarray and pybedtools; and
- container availability through BioContainers.

This answers “is LDSC on Bioconda?” with **yes**, but it is not a current Python 3 package. The `ldsc39` Anaconda package/API URLs return 404. The modern [CBIIT installation instructions](https://github.com/CBIIT/ldsc/tree/ldsc39) instead clone the branch and install its Python dependencies; neither CBIIT's documented `ldsc39` branch nor its exact checked revision has a Bioconda recipe to pin.

### Integration consequence

There are three materially different implementation paths:

1. **Legacy standalone LDSC:** use `bioconda::ldsc=1.0.1` and its BioContainer. This is reproducible and follows the original documented CLI, but carries an end-of-life Python 2 stack.
2. **Modern standalone LDSC:** pin the exact CBIIT `ldsc39` revision and supply a custom container for a pipeline-local module, then use `ldsc.py` and `munge_sumstats.py` as separate atomic executables. A Bioconda recipe remains the preferred route for eventual reusable/upstream components, but its absence does not block a local module.
3. **GWASLab-owned LDSC:** use the LDSC implementation embedded in the pipeline's existing `bioconda::gwaslab=4.1.9`. This avoids Python 2 and is already packaged, but GWASLab labels the integration **beta**, changes some munging behaviour, and exposes it through Python methods rather than the standalone LDSC CLI.

Do not silently call path 1 “the current LDSC implementation”: the original maintainers explicitly redirected users to CBIIT in January 2026. Select the executable owner before module design because it determines the namespace, container and output contract.

### nf-core support for software outside Bioconda

Yes. The current [nf-core module software specification](https://nf-co.re/docs/specifications/components/modules/software-requirements#software-not-on-bioconda) explicitly says that software not available on Bioconda must provide a `Dockerfile` in the module directory; nf-core GitHub Actions can build it on GitHub Packages. At pipeline level, Bioconda or conda-forge packaging is a [recommendation](https://nf-co.re/docs/specifications/pipelines/recommendations/bioconda), not an absolute requirement. The [custom-container guidance](https://nf-co.re/docs/specifications/pipelines/recommendations/custom_containers) prefers mirroring an unavoidable custom image into the nf-core organisation on Quay for long-term reproducibility.

For this pipeline, a modern CBIIT implementation can therefore remain under `modules/local/` with:

- a Dockerfile that pins source commit `6c673952cee74bd5c57aef1555a03b1c015399a0` and verifies its source checksum;
- an immutable public image reference, ideally mirrored to `quay.io/nf-core`;
- a usable `ldsc.py`/`munge_sumstats.py` command path without runtime source downloads;
- BLAS thread limits derived from `task.cpus`; and
- Docker/Singularity tests, plus a Conda-profile test only if a reliable Conda/pip fallback is supplied.

CBIIT's checked-in Dockerfile should not be copied unchanged: it starts from an unpinned `continuumio/miniconda3`, copies whichever checkout happens to be present, activates the environment through `.bashrc`, and defaults to a Flask service rather than the LDSC CLI. A pipeline image needs a deterministic CLI-oriented build.

This local route is valid for using and evaluating the Python 3 implementation now. It is not yet the clean route for submission to the shared `nf-core/modules` library: Bioconda packaging is still the preferred durable resolution because it supplies Conda users and enables standard BioContainer/Seqera container provenance.

## 2. Parallel computation

### `munge_sumstats.py`

The standalone script reads the input with pandas in blocks controlled by `--chunksize` (default five million rows), then concatenates retained rows and performs whole-table sample-size and duplicate processing. Chunking bounds parts of the read/filter operation; it does not create workers. The CLI exposes no CPU, thread, process or job count, and its main work is parsing, filtering and element-wise transformation rather than substantial matrix algebra.

**Pipeline consequence:** run one summary-statistics file per Nextflow task with `cpus 1`. Scatter traits at workflow level. A threaded BLAS does not provide a meaningful parallel contract for this path.

### Native BLAS/LAPACK threading

LDSC does not create a Python worker pool, but this is not the same as guaranteed single-core execution. The checked source calls:

- repeated `np.dot` matrix multiplications in LD-score calculation;
- `np.linalg.lstsq` during iteratively reweighted regression;
- `np.dot` to build jackknife cross-products; and
- repeated `np.linalg.solve` operations for jackknife delete values.

[NumPy documents](https://numpy.org/doc/stable/reference/global_state.html#number-of-threads-used-for-linear-algebra) that it generally executes its own calls on one thread but delegates linear algebra to BLAS backends such as OpenBLAS or MKL, which may use multiple threads. Therefore the actual core count is a property of the resolved NumPy/BLAS runtime, not an LDSC CLI option.

The available `quay.io/biocontainers/ldsc:1.0.1--pyhdfd78af_2` image was inspected on 2026-08-01. `numpy.show_config()` reported OpenBLAS, and one representative LDSC-shaped `np.dot(A.T, B)` created four process threads when run with `OPENBLAS_NUM_THREADS=4`. A small synthetic benchmark of 100 products with `A=(500,2000)` and `B=(500,50)` took 0.232 seconds with one OpenBLAS thread and 0.127 seconds with four, a 1.83-fold speed-up on this workstation. This proves that the packaged runtime can use allocated CPUs; it is not an end-to-end LDSC scaling benchmark.

An end-to-end smoke benchmark on the local 500-sample, 4,942-variant PLINK fixture used `ldsc.py --l2 --ld-wind-snps 500`. LDSC reported 0.33 seconds with both one and four BLAS threads. The fixture is too small for the accelerated kernels to dominate startup, parsing and output, so it confirms that CPU allocation should be selected from representative production-scale benchmarks rather than from the synthetic GEMM result alone.

Set `OPENBLAS_NUM_THREADS`, `OMP_NUM_THREADS` and `MKL_NUM_THREADS` to `task.cpus` in the task environment. Leaving them unset can let the library see and use more cores than the scheduler allocated. Setting all of them to one would unnecessarily disable valid parallelism; setting them to `task.cpus` provides a bounded runtime contract across BLAS variants.

### `ldsc.py --h2` and `--rg`

The CLI exposes no parallel option. In the checked CBIIT source, `--rg a,b,c,...` loops over `b,c,...` serially. `--n-blocks` controls the statistical block-jackknife partition count; it is not a worker count. `--chunk-size` controls chunks used when calculating LD scores; it is also not a worker count.

The regression and jackknife code can enter threaded BLAS/LAPACK through `dot`, `lstsq` and `solve`, but ordinary unpartitioned LDSC has very few predictors. The matrices passed to `solve` are correspondingly small, the outer jackknife and phenotype loops remain serial, and multi-core scaling may be modest. Partitioned analyses with many annotations present larger linear-algebra kernels and are more plausible beneficiaries.

**Pipeline consequence:** do not hard-code these tasks as intrinsically single-core. Start with a small bounded allocation such as two CPUs, propagate it to the BLAS thread limits, and benchmark representative unpartitioned and partitioned jobs before selecting the final process label. Parallelise independent analysis units through Nextflow. If a requested `--rg` analysis is split into separate pairwise tasks, validate that the desired SNP-intersection and output semantics are preserved rather than assuming a grouped invocation is interchangeable.

### `ldsc.py --l2`

One `--bfile` is processed per invocation and the implementation has no Python multiprocessing layer. Its core LD-score loop repeatedly computes genotype-block products with `np.dot`, so a threaded BLAS can use multiple CPUs within each task. This is the path where multi-core acceleration is most directly supported by the source and by the container experiment.

Reference panels are conventionally chromosome-sharded, so chromosome remains the natural Nextflow scatter key. Run one task per PLINK bundle/chromosome, allocate and cap a benchmarked number of BLAS threads per task, and gather the fixed chromosome-prefixed `.l2.ldscore.gz` and `.l2.M[_5_50]` files into a reference bundle. Balance per-task BLAS threads against the number of chromosome tasks that can run concurrently; nested unbounded BLAS threads would oversubscribe the executor.

## 3. Summary-statistics input and munging

### Final LDSC `.sumstats` contract

The [official format page](https://github.com/bulik/ldsc/wiki/Summary-Statistics-File-Format) defines a whitespace-delimited table with one row per SNP and these required columns:

| Column | Meaning |
| --- | --- |
| `SNP` | unique SNP identifier, normally an rsID |
| `N` | per-variant sample size |
| `Z` | signed Z score, with sign relative to `A1` |
| `A1` | effect allele |
| `A2` | other allele |

Column order is irrelevant. LDSC removes non-SNP and strand-ambiguous variants. `ldsc.py --h2` and `--rg` consume this final format; raw `BETA`/`P` association tables are not the same contract.

### What standalone `munge_sumstats.py` does

The [official heritability/genetic-correlation tutorial](https://github.com/bulik/ldsc/wiki/Heritability-and-Genetic-Correlation) strongly recommends the bundled munging script because it:

- maps common source column names;
- requires a SNP identifier, two alleles, sample size, a valid P value and a signed statistic such as `BETA`, `OR` or `Z`;
- filters missing data, invalid P values, INFO below 0.9 when available, MAF below 0.01 when available, low sample size, non-SNP alleles, strand-ambiguous alleles and duplicate rsIDs;
- checks that the signed statistic has a sensible null median;
- derives signed `Z` from P and the direction of the signed statistic; and
- optionally restricts and aligns variants with `--merge-alleles w_hm3.snplist`.

The CBIIT Python 3 port recognises the current GWASLab names `SNPID`, `EA`, `NEA`, `EAF`, `BETA`, `P` and `N`. It does **not** recognise `MLOG10P` or `N_EFF` automatically. Nonstandard columns can be named explicitly with flags such as `--p`, `--N-col` and `--signed-sumstats`, but `MLOG10P` is not numerically a P value and cannot merely be aliased with `--p`.

### Is the current GWASLab output sufficient?

**As upstream harmonisation: yes. As a final standalone-LDSC input: no.**

The current pipeline's [`GWASLAB_HARMONIZE`](../modules/local/gwaslab/harmonize/main.nf) uses GWASLab 4.1.9, runs `harmonize()`, and exports `fmt="gwaslab"`. The published contract documents common `SNPID`, `CHR`, `POS`, `EA`, `NEA`, `EAF`, `BETA`, `SE` and `N` columns. This resolves names, builds, alleles and optional rsIDs before LDSC.

It does not perform the LDSC-specific final steps:

- the module does not request HapMap3 filtering;
- its output is not `SNP,N,Z,A1,A2` `.sumstats.gz`;
- without configured rsID reference data, its `SNPID` may remain a chromosome-position identifier that cannot join the precomputed LD-score panel's rsIDs; and
- the REGENIE route publishes `MLOG10P`, while standalone munging requires `P`.

For the standalone CLI route, keep GWASLab harmonisation and add one dedicated munging task per trait. The REGENIE adapter must materialise a valid `P` or create a rigorously equivalent signed-Z input path with tested extreme-value handling. Do not rename `MLOG10P` to `P`.

### Could GWASLab replace `munge_sumstats.py`?

GWASLab 4.1.9 contains two relevant features:

1. [`to_format(fmt="ldsc", hapmap3=True, ...)`](https://github.com/Cloufield/gwaslab/blob/main/docs/format_load_save.md#ldsc-default-format) filters against GWASLab's built-in HapMap3 data and writes a raw LDSC-oriented table. The documented output contains `Beta` and `P`, not the final required `Z`, so this export is still input to munging rather than a drop-in `.sumstats.gz` for standalone `ldsc.py`.
2. [GWASLab's integrated LDSC methods](https://github.com/Cloufield/gwaslab/blob/main/docs/LDSCinGWASLab.md) implement an internal munging workflow and run heritability/correlation directly from `Sumstats` objects. This can replace the standalone script **only if GWASLab owns the LDSC execution path**. It is marked beta and is not behaviour-identical: for example, its documented default minimum-N rule is the 90th percentile divided by 1.5, whereas standalone `munge_sumstats.py` uses the 90th percentile divided by 2.

Therefore, avoid a hybrid in which GWASLab's beta munging is assumed to produce the standalone file contract without an explicit adapter and equivalence tests.

## 4. Reference data

### Munging reference

The original tutorial recommends [`w_hm3.snplist`](https://data.broadinstitute.org/alkesgroup/LDSCORE/w_hm3.snplist.bz2), approximately 1.2 million HapMap3 SNPs with `SNP`, `A1` and `A2`. It supplies the regression-SNP set and allele orientation to `--merge-alleles`. This is separate from the pipeline's optional GWASLab FASTA, rsID VCF and strand-reference VCF.

GWASLab [ships build-indexed HapMap3 data](https://github.com/Cloufield/gwaslab/blob/main/docs/Hapmap3.md), derived from `w_hm3.snplist` with positions assigned from dbSNP v150/v151. It can match by rsID or by build-aware chromosome, position and alleles. That means a GWASLab-owned munging path does not need an external HapMap3 file, but a standalone `munge_sumstats.py --merge-alleles` module should still take the original list as an explicit, provenance-bearing input.

### Regression references

`ldsc.py --h2` and `--rg` require:

- `--ref-ld-chr`: chromosome-split reference LD scores used as regression predictors; and
- `--w-ld-chr`: chromosome-split regression-weight LD scores.

For ordinary non-partitioned LDSC, the current official tutorial recommends using the same bundle for both. Partitioned heritability requires distinct baseline/annotation reference scores and regression weights. Each chromosome bundle includes `.l2.ldscore[.gz]` and matching `.l2.M`/`.l2.M_5_50` files.

References must match the GWAS ancestry. The official repository provides European and East Asian 1000 Genomes LD scores; its tutorial says other populations need population-appropriate scores. Genome build and SNP identifiers must also join correctly. GWASLab's reference FASTA/VCFs improve summary-statistic harmonisation but do not replace these LD-score and weight files.

If precomputed ancestry-matched scores are unavailable, the LDSC route must stop with a clear missing-reference error. Calculating reference LD scores with `ldsc.py --l2` is deliberately outside the initial LDSC integration scope.

## Selected LDSC integration boundary

The selected executable is the CBIIT Python 3 LDSC revision in a pinned custom container. The initial LDSC integration is limited to summary-statistics munging, SNP-heritability estimation and pairwise genetic correlation.

### Components

1. **`LDSC_MUNGESUMSTATS`:** one task per GWASLab-harmonised association result. It consumes the method-specific summary-statistics identity plus an explicit HapMap3 allele list and emits the native `.sumstats.gz` and munging log. A small pipeline adapter must first materialise valid `P` for REGENIE's `MLOG10P`; the adapter must preserve extreme-value accuracy.
2. **`LDSC_H2`:** one `ldsc.py --h2` task per munged association result. It consumes ancestry-matched reference LD-score and regression-weight bundles and emits the native log plus a stable machine-readable summary of observed-scale SNP heritability, standard error, intercept and associated diagnostics. Binary liability-scale output is included only when both sample and population prevalence are available.
3. **`LDSC_RG`:** one `ldsc.py --rg trait1,trait2` task per explicitly requested pair. It consumes two munged summary-statistics identities and the same ancestry-matched reference/weight role, then emits the native log plus a stable machine-readable table containing the pair identity, genetic correlation, standard error and significance statistics.
4. **Pipeline-local result adapter:** CBIIT retains ordinary `--h2` and `--rg` results primarily in its log. A deterministic local adapter should expose tabular outputs rather than making downstream users parse prose. It must retain the untouched native log as provenance.

Munging, heritability and genetic-correlation invocations remain separate atomic processes. Pipeline-level composition owns routing, pairing, reference selection and result aggregation.

### Routing and identity

The current pipeline can emit several association methods for one `analysis_id`; silently choosing one would be incorrect. LDSC heritability therefore runs once for every selected, harmonised association result, retaining both `analysis_id` and association method in its result identity.

Genetic correlation is opt-in through an explicit pair declaration rather than an automatic all-by-all Cartesian product. Each pair must name both `analysis_id` and association method for each side, plus a unique pair identifier. Validation must reject self-pairs, duplicate unordered pairs, unknown analyses/methods, build mismatches and incompatible reference assignments before task submission.

All traits in one correlation task must use the same compatible ancestry-matched LD-score/weight bundle. Reference resources are supplied explicitly; the pipeline neither downloads them implicitly nor calculates replacements.

### Included outputs

- munged `.sumstats.gz` and munging log per analysis-method result;
- native LDSC heritability log and normalised heritability TSV;
- native LDSC genetic-correlation log and normalised correlation TSV;
- run-wide versions identifying CBIIT LDSC by exact commit and the Python runtime; and
- ordinary MultiQC provenance/summary integration after the tabular contract is stable.

### Explicitly out of scope

- LD-score calculation (`--l2`) from PLINK reference panels;
- partitioned or cell-type-specific heritability;
- automatic all-by-all genetic correlations;
- implicit reference downloads or ancestry inference;
- GenomicSEM, LD Hub or the GWASLab beta LDSC implementation; and
- legacy Python 2 LDSC as an alternate runtime.

### Resource policy

Munging remains a one-CPU scattered task. `--h2` and pairwise `--rg` receive a small bounded CPU allocation with `OPENBLAS_NUM_THREADS`, `OMP_NUM_THREADS` and `MKL_NUM_THREADS` set to `task.cpus`; representative production inputs determine the final process label. Parallelism across analyses and requested pairs remains scheduler-visible through Nextflow.

## Sources

- [Original LDSC repository and January 2026 redirect](https://github.com/bulik/ldsc/tree/2fdeeb3b44379408794154993dbd6101b8946b7e)
- [Current CBIIT Python 3 branch](https://github.com/CBIIT/ldsc/tree/6c673952cee74bd5c57aef1555a03b1c015399a0)
- [Bioconda LDSC recipe page](https://bioconda.github.io/recipes/ldsc/README.html), [recipe source](https://github.com/bioconda/bioconda-recipes/blob/master/recipes/ldsc/meta.yaml), and [package API](https://api.anaconda.org/package/bioconda/ldsc)
- [Official summary-statistics format](https://github.com/bulik/ldsc/wiki/Summary-Statistics-File-Format)
- [Official heritability and genetic-correlation tutorial](https://github.com/bulik/ldsc/wiki/Heritability-and-Genetic-Correlation)
- [Pinned CBIIT `munge_sumstats.py`](https://github.com/CBIIT/ldsc/blob/6c673952cee74bd5c57aef1555a03b1c015399a0/munge_sumstats.py)
- [Pinned CBIIT `ldsc.py`](https://github.com/CBIIT/ldsc/blob/6c673952cee74bd5c57aef1555a03b1c015399a0/ldsc.py) and [`ldscore/sumstats.py`](https://github.com/CBIIT/ldsc/blob/6c673952cee74bd5c57aef1555a03b1c015399a0/ldscore/sumstats.py)
- [GWASLab LDSC integration](https://github.com/Cloufield/gwaslab/blob/main/docs/LDSCinGWASLab.md), [LDSC-format export](https://github.com/Cloufield/gwaslab/blob/main/docs/format_load_save.md#ldsc-default-format), and [built-in HapMap3 data](https://github.com/Cloufield/gwaslab/blob/main/docs/Hapmap3.md)
- [Current pipeline GWASLab output contract](output.md#gwaslab)
