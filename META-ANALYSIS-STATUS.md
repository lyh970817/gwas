# Common-variant meta-analysis (#9) — work status

Branch: `meta-analysis-per-variant-modules`, branched from `extend-method-registry-capabilities` (`eee8f4c`).

Work on GitHub issue `lyh970817/gwas#9`. Nothing here is wired into `workflows/gwas.nf`; the route-controller
refactor owns that file and was deliberately not touched. This file is kept current so another pause is cheap.

## Component status

| Component                       | Path                                               | State                                                            |
| ------------------------------- | -------------------------------------------------- | ---------------------------------------------------------------- |
| `GWASLAB_META_ANALYZE`          | `modules/local/gwaslab/meta_analyze/`              | **Complete.** 14/14 nf-tests green.                              |
| `METASOFT_RE2`                  | `modules/local/metasoft/re2/`                      | **Complete.** 8 nf-tests.                                        |
| `NORMALISE_COMMON_VARIANT_META` | `modules/local/normalise_common_variant_meta/`     | **Complete.** 6/6 nf-tests green.                                |
| `GATHER_META_SHARDS`            | `modules/local/gather_meta_shards/`                | **Complete.** 10/10 nf-tests green.                              |
| `PREPARE_MRMEGA_INPUT`          | `modules/local/prepare_mrmega_input/`              | **Complete.** 5/5 nf-tests green.                                |
| `MRMEGA`                        | `modules/local/mrmega/`                            | **Complete.** 6/6 nf-tests green against the pinned quay digest. |
| `THIN_MRMEGA_MARKERS`           | `modules/local/thin_mrmega_markers/`               | **Complete.**                                                    |
| `EXTRACT_MRMEGA_AXES`           | `modules/local/extract_mrmega_axes/`               | **Complete.** 8/8 nf-tests green.                                |
| `NORMALISE_MRMEGA_RESULT`       | `modules/local/normalise_mrmega_result/`           | **Complete.**                                                    |
| `COMMON_VARIANT_META_ANALYSIS`  | `subworkflows/local/common_variant_meta_analysis/` | **Complete, all four models.** 4/4 nf-tests green.               |

## The MR-MEGA two-pass flow

```
thin genome-wide to <=1 marker/Mb  ->  pass 1 derives axes  ->  signs canonicalized
   ->  pass 2 scatters per chromosome with --precalculated fixed axes  ->  gather
```

Wired and tested end to end. `THIN_MRMEGA_MARKERS` collects every shard's aligned view for a request and
reduces it to at most one marker per megabase, keeping only markers every study contributes with MAF > 1% on
chromosomes 1-22 and X. That is what MR-MEGA's own axis derivation does internally, so the pre-thin loses
nothing and bounds pass-1 memory. `EXTRACT_MRMEGA_AXES` reads the `Principal components:` block out of the
pass-1 log, matching coordinates to studies **by position** rather than by the path echoed there, because the
manifest is rewritten against staged copies before MR-MEGA sees it.

Sign canonicalization happens between the passes, so every shard is born canonical rather than needing a
correction afterwards. The rule is: the largest-magnitude coordinate on each axis is made positive, ties broken
by lowest study index. It depends only on the ordered source coordinates. Negating an axis flips exactly
`beta_{j+1}` and leaves `se`, every chi-square, every `ndf`, every P value and `lnBF` bit-identical, so this is
free. Scatter contributes no numerical error; the only residual against an unscattered run is the six
significant figures MR-MEGA prints its coordinates with, which cannot be raised.

## Settled take/emit contracts

### `COMMON_VARIANT_META_ANALYSIS`

```nextflow
take:
ch_request  // [ meta, parents, study_names, input_format, genome_build, models, chromosomes ]

emit:
candidate        // [ meta, *.gathered.tsv.gz ]      exactly one per request
gather_report    // [ meta, *.gather_report.json ]
shard_derivation // [ shard_meta, *.derivation.json ]
shard_qc         // [ shard_meta, *.qc.json ]
study_order      // [ shard_meta, *.study_order.tsv ]
re2              // [ shard_meta, *.re2.tsv.gz ]     only when re2 was selected
```

`models` is a subset of `fixed`, `random`, `re2`; `fixed` is always produced. `chromosomes` is the ordered
scatter list, or `[]` for a single genome-wide shard.

### `GWASLAB_META_ANALYZE`

```nextflow
input:
tuple val(meta), path(sumstats, stageAs: 'parents/*'), val(study_names), val(input_format), val(genome_build), val(chromosome)

output:
tuple val(meta), path("${prefix}.meta.tsv.gz"),        emit: meta_analysis
tuple val(meta), path("${prefix}.study_views.tsv.gz"), emit: study_views
tuple val(meta), path("${prefix}.effect_matrix.txt"),  emit: effect_matrix
tuple val(meta), path("${prefix}.study_order.tsv"),    emit: study_order
tuple val(meta), path("${prefix}.qc.json"),            emit: qc
tuple val(meta), path("${prefix}.derivation.json"),    emit: derivation
tuple val(meta), path("${prefix}.meta.log"),           emit: log
path "versions.yml", emit: versions, topic: versions
```

`task.ext.args` is a closed whitelist of `--random-effects` and `--min-studies <INT>`; everything else is
rejected. There is no native GWASLab argument pass-through.

Published candidate columns:

```
SNPID CHR POS EA NEA STATUS EAF BETA SE P N
N_STUDIES DIRECTION EAF_META EAF_MIN EAF_MAX N_TOTAL MAX_WEIGHT_SHARE Z_FIXED Q P_HET I2
[BETA_RANDOM SE_RANDOM Z_RANDOM P_RANDOM TAU2_RANDOM]
META_VARIANT_KEY
```

### `METASOFT_RE2`

```nextflow
input:
tuple val(meta), path(effect_matrix)

output:
tuple val(meta), path("${prefix}.metasoft.txt"), emit: native_result
tuple val(meta), path("${prefix}.re2.tsv.gz"),   emit: re2
tuple val(meta), path("${prefix}.metasoft.log"), emit: log
path "versions.yml", emit: versions, topic: versions
```

`emit: native` is impossible — `native` is a Groovy keyword and `nextflow lint` rejects it. K is derived from
the matrix width, so it is not an input. No `conda` directive and no `environment.yml`: METASOFT is not in
Bioconda.

### `GATHER_META_SHARDS`

```nextflow
input:
tuple val(meta), path(shards, stageAs: 'shards/*'), path(records, stageAs: 'records/*'), val(expected_chromosomes)

output:
tuple val(meta), path("${prefix}.gathered.tsv.gz"),    emit: gathered
tuple val(meta), path("${prefix}.gather_report.json"), emit: report
path "versions.yml", emit: versions, topic: versions
```

Shards and completion records are paired by **basename stem**, a documented caller contract, not by position.
The completion record is `GWASLAB_META_ANALYZE`'s `qc.json`: it declares `chromosome` and
`fixed_eligible_variants`. An unscattered run is gathered too, as a one-shard gather under the sentinel
chromosome `ALL`, so the completeness checks apply identically either way.

### `COMMON_VARIANT_META_ANALYSIS` take channel

```
[ meta, parents, study_names, input_format, genome_build, trait_type, models, axes, chromosomes ]
```

`models` is a subset of `fixed`, `random`, `re2`, `mrmega`; `fixed` is always produced. `axes` is required when
`mrmega` is selected. Emits `candidate`, `gather_report`, `shard_derivation`, `shard_qc`, `study_order`, `re2`,
`ancestry_axes` and `axes_qc`.

### `EXTRACT_MRMEGA_AXES`

```nextflow
input:
tuple val(meta), path(mrmega_log), path(filelist), val(axes)

output:
tuple val(meta), path("${prefix}.precalculated_axes.txt"), emit: precalculated_axes
tuple val(meta), path("${prefix}.ancestry_axes.tsv"),      emit: coordinates
tuple val(meta), path("${prefix}.axes_qc.json"),           emit: qc
```

### `NORMALISE_COMMON_VARIANT_META`, `PREPARE_MRMEGA_INPUT`, `MRMEGA`, `THIN_MRMEGA_MARKERS`, `NORMALISE_MRMEGA_RESULT`

Built by parallel agents; see their `main.nf` and `meta.yml`. `NORMALISE_COMMON_VARIANT_META` added `stageAs`
on its upstream inputs because its `derivation` input and `derivation` output would otherwise collide on the
same filename and it would write through the staged symlink, corrupting the upstream task's output.

## Verified by execution

- **Analytical inverse-variance results** reproduce hand calculations exactly. Three studies at SE
  0.02/0.03/0.04 with BETA 0.10/0.14/0.08 give `BETA` 0.1075410, `SE` 0.01536443, `Z` 6.999349. Two studies
  where the merge mold itself is absent give `BETA` 0.054, `SE` 0.008944272, `Q` 0.8, `P_HET` 0.3710934.
- **Random effects under real heterogeneity.** Betas +0.5/-0.1/+0.2 at SE 0.05: `Q` 72 on 2 df,
  `P_HET` 2.319523e-16, `I2` 0.9722222, `TAU2_RANDOM` 0.0875, `BETA_RANDOM` 0.2, `SE_RANDOM` 0.1732051,
  `P_RANDOM` 0.2482131. Every value asserted.
- **GWASLab and METASOFT agree to every digit METASOFT emits**, on the same fixture, for **both** fixed and
  random effects: `BETA_FE` 0.200000, `STD_FE` 0.0288675, `PVALUE_FE` 4.26219E-12; `BETA_RE` 0.200000,
  `STD_RE` 0.173205, `PVALUE_RE` 0.248213, `TAU_SQUARE` 0.0875000, `Q` 72.0000, `I_SQUARE` 97.2222.
  This supersedes the earlier note that METASOFT's tau-squared uses a non-textbook denominator: at **equal**
  weights it matches textbook DerSimonian-Laird exactly. Whether it diverges at unequal weights is untested.
- **Precision protection end to end.** `BETA` 3.12e-05 / `SE` 9.8e-06 survives parent loading, alignment, the
  effect matrix, the published table and METASOFT (3.086618e-05 / 6.067884e-06 vs 3.08662E-05 / 6.06788E-06).
- **Scatter changes no answer.** The two-chromosome scattered run and the unscattered run produce identical
  per-variant values through the subworkflow.
- `chi2_logsf` vs SciPy: max absolute error in log10 **5.68e-14** over 309 points where SciPy is finite; vs
  mpmath at 60 dps, **1.82e-12** over the 123 points where SciPy itself underflows to `-inf`. Golden value
  chi-square 7459 at 3 df gives log10 P -1617.8629316806.
- MR-MEGA `--precalculated` works on the pinned quay binary; per-chromosome scatter reproduced unscattered.
- **The full two-pass MR-MEGA flow runs end to end** on a five-study, two-chromosome fixture with a real
  allele-frequency gradient: axes derived once, signs canonicalized, both shards fitted against them, gathered
  into one result. `MRMEGA_DF_ASSOC` is `axes + 1` and `MRMEGA_DF_ANCESTRY_HET` is `axes` on every row, the
  log-scale-first block reaches the published table, and no `MRMEGA_NATIVE_P_*` column is published.

## Whole-suite evidence

One sweep over all nine modules plus the subworkflow:
`nf-test test <9 module tests> <subworkflow test> --profile +docker`
-> **SUCCESS: Executed 76 tests in 1835s**, 0 failed.
`nf-core pipelines lint` -> 621 passed, 7 ignored, 24 warnings, 0 failed.

## Not verified

- `nf-core pipelines lint` has **not** been run on this branch.
- No end-to-end pipeline route exists, because `workflows/gwas.nf` is deliberately untouched.
- METASOFT tau-squared at **unequal** study weights.
- Nothing at realistic scale. No benchmark on 5-15M variants or 10-50 studies; #9 asks for that and it has not
  been done. The wide aligned table is fully materialised in memory, which is the thing #9 warns about.

## Design decisions that are not obvious from the code

1. **The effect matrix is headerless.** METASOFT's parser treats any non-numeric token that is not `NA` as
   fatal, so a header row makes the file unusable. Found by running it.
2. **Contribution masking happens before GWASLab sees the data.** GWASLab's fixed-effect loop silently requires
   non-null `N` _and_ `EAF` as well as `BETA`/`SE > 0`, so a row with a good effect estimate but no `EAF`
   contributes nothing, with no warning. The template applies the same mask up front and reports the loss
   source-attributed in `qc.json`. This also guarantees the effect matrix holds exactly the estimates that
   contributed, so the GWASLab/METASOFT cross-check compares like with like.
3. **Reverse-complement disagreements are excluded, not resolved.** GWASLab matches only exact and swapped
   allele pairs, so a reverse-complement representation silently becomes a _second union row_ holding a subset
   of the studies — one variant reported twice. Verified experimentally. Such sites are dropped from every
   parent and counted. Palindromic sites are their own reverse complement, self-match, and merge normally.
4. **Duplicate normalised keys are dropped per parent, all copies, and counted.** `meta_analyze_multi` does a
   silent `drop_duplicates(keep="first")`; keeping an arbitrary row is not defensible.
5. **Output `STATUS` is a per-digit consensus of the _contributing_ parents**, falling back to GWASLab's
   unknown digit `9`. The merge copies the mold's `STATUS` onto rows a parent never supplied, so the mask
   matters.
6. **Two float formats.** The published candidate uses `{:.6e}`; intermediate adapter inputs use Python
   `repr()`, the shortest representation that round-trips to the identical float64.
7. **`TAU2_RANDOM` is recomputed in the template.** GWASLab drops its internal `_R2` before returning.
8. **Output is re-sorted explicitly** by `(CHR, POS, EA, NEA)` with `kind="mergesort"`. GWASLab sorts by
   `(CHR, POS)` only, with pandas' non-stable quicksort — a real determinism hazard at multi-allelic sites.
9. **`Q`/`P_HET`/`I2` are `NA` when fewer than two studies contribute**, and `Q` is clamped at 0.
10. **QC counts are shard-composable** — additive integers or min/max ranges. Nothing is genome-wide-only.
11. **`study_names` is an explicit tuple scalar**, because positional study order is the determinism contract.
12. **The chromosome selector is channel-borne, not `ext.args`.** It varies per task under scatter and is
    neither a metadata key nor a process-global value. The model settings stay in `ext.args` because they are
    per-request configuration.
13. **Shard identity lives in `meta.id`** as `<request>_chr<N>`. Underscore, not a dot, because the gather
    pairs shards to records on the basename stem before the first dot.
14. **Union and intersection are counted on the allele set**, not the ordered `EA:NEA` key. A parent carrying
    the swapped representation is the same variant, and the merge collapses it. Counting the orderings
    separately overstated the union and understated the intersection; a test caught this.
15. **A single staged file arrives as a `Path`, and Groovy's `collect` iterates a `Path`'s name components.**
    `path(x, stageAs: 'dir/*')` with one file therefore yields `["dir", "name.ext"]` from `x.collect{}`, not
    one element. Both `GATHER_META_SHARDS` and `GWASLAB_META_ANALYZE` normalise with
    `(x instanceof List ? x : [x])`. Three gather tests failed on this before the fix; any single-chromosome
    request would have hit it.

## Container notes

- METASOFT: `ghcr.io/lyh970817/metasoft@sha256:29dfc8a85266582cf5a05039c41b90d3003b3e06920fa010ed3a20268027c2f3`.
  **The image must contain `bash`.** Nextflow launches every containerised task as `/bin/bash -ue .command.run`,
  and the first Alpine build had busybox only, so every task died at exit 127 before the script ran. This was
  invisible to `docker run --entrypoint metasoft` verification, which never invokes a shell. Trace metrics were
  checked too: Nextflow 25.10.4 calls only `ps -e -o pid= -o ppid=` and reads the rest from `/proc`, which
  busybox `ps` supports, so no `procps`/`coreutils` is needed. There is a test that runs a real task through
  the container and asserts on the log and versions, specifically so a base-image regression is caught here
  rather than at integration.
  Licensing: the upstream `LICENSE` forbids redistribution on its own terms; the author's later grant is at
  `/usr/share/doc/metasoft/REDISTRIBUTION-PERMISSION.md` in the image. Cite both together, never the LICENSE
  alone.
- MR-MEGA: `quay.io/loukas_moutsianas/mrmega@sha256:1143b7f016f00f0f32cbc6ad72b4a571e2f824e440a0b7fecf4ec4c8334ae1e8`.
  Invoke as `/MR-MEGA/MR-MEGA`, absolute — `/MR-MEGA` is on the image `PATH` so the bare name works under
  Docker, but Apptainer and Podman do not reliably preserve a non-standard image `PATH`. The behavioural matrix
  was re-run against this exact binary and is byte-identical to the previously characterized build. The image
  carries **no licence material at all** and cannot be tied to upstream v0.2 beyond a hard-coded banner; say so
  in metadata rather than implying otherwise.

## Native contract briefings — do not lose these

### METASOFT

- **RE2 needs no flag.** FE, RE and RE2 are always computed; only binary effects and m-values are opt-in.
  `metasoft -input X -output Y -log Z`; the image launcher injects `-pvalue_table`.
- `metasoft --version` prints 2.0.1; the jar itself has no version output.
- Output columns 9/10/11 are `PVALUE_RE2`, `STAT1_RE2`, `STAT2_RE2`. Columns 10 and 11 are _statistics_ whose
  sum is the Han-Eskin statistic, not p-values.
- 18 header names, but data rows are 16 fixed columns plus two K-wide blocks **plus a trailing tab**, so a
  tab-separated read sees `17 + 2K` fields on data rows and 18 on the header. Drop the trailing empty field
  before checking width. This was a real bug caught by running it.
- Row order is preserved but duplicate keys are permitted; **join by key on a de-duplicated input**.
- `awk`'s `exit` runs the `END` block, so a rule-level failure must set a flag that `END` checks, or the END
  diagnostics print on top of the real error. Also a real bug caught by running it.

Silent-failure modes the module defends against:

1. **Partial pairs are silently swallowed** — `BETA` with `SE=NA` drops that study at exit 0 and produces a row
   _bit-identical_ to a correct `NA NA` row, so it cannot be caught downstream.
2. **Undocumented K=50 cliff.** The table covers K = 2..50; at K = 51 the correction ratio jumps from ~0.61 to
   exactly 1.000, shifting RE2 p-values ~1.6x anti-conservative with no warning.
3. **Small tails underflow to the literal `0.00000`** near 1e-307 at exit 0, reachable through heterogeneity
   alone. Never read it as a probability.
4. Degenerate-but-positive SEs give `NAN` at exit 0.
5. **Exit codes are inconsistent** — truncated output at 255, a good output at 255 when only the log is
   unwritable, exit 1 on leading whitespace. Assert on output completeness, never the exit code.

`I_SQUARE` is a percentage, not a fraction.

### MR-MEGA

1. **All three native P values must be discarded unconditionally and recomputed in log space.** Upstream's own
   `fixP.r` recomputes in _linear_ space and returns `P = 0` for a real chi-square 7459 top hit. P saturates to
   exactly 1.0 from chi-square ~2367.68, is 0.352 at 1980 and 0.99933 at 2214, and the first negative value
   appears at **86.96**. The defect is confined to `df != 2`, but which column is sound flips with `--pc` and
   K, which is exactly why the discard must be unconditional.
2. **The axis bound is `pc <= K-3`, not `K-2` as #9 states.** The binary's gate is `K-2 > pc` strictly.
   Violating it yields 300/300 `SmallCohortCount` at exit 0 with no message. `--pc` defaults to 3 in the binary
   and 4 in the docs; always pass it explicitly.
3. Silent wrong answers: `NA` in EAF parses as **0.0** and is accepted; `--no_alleles` negates beta for every
   study after the first; within-file duplicate markers overwrite silently; the marker key is the name string
   only, so chromosome/position mismatches are counted but ignored; errors 1-5 are never printed; a missing
   manifest or zero shared markers **segfaults** at exit 139; `-t`, `-m` and `--name_strand` are inert.
4. **Sign canonicalization is a pure post-hoc transform** — negating an axis flips exactly `beta_{j+1}` and
   leaves everything else bit-identical.
5. **New, found while building:** a `--precalculated` manifest whose coordinate block is **narrower than
   `--pc`** exits 0 with a complete `.result` in which every `beta_j`/`se_j` for j >= 1 is exactly 0,
   `chisq_ancestry_het` is 0 and `P-value_ancestry_het` is `nan`. Nothing on any stream. `MRMEGA` rejects it.
6. **The binary route is lossy, and this is accepted deliberately.** MR-MEGA's native inverse is
   `se = (ln(OR) - ln(OR_95L)) / 1.96` with a hard-coded 1.96 rather than the exact quantile, so writing true
   95% bounds makes it reconstruct an SE smaller than canonical by `z/1.96 - 1 = -1.8375e-05`, inflating every
   chi-square by about 3.7e-05 relative. It is recorded in `adapter_qc.json` rather than compensated.
   Routing binary traits through `--qt` with `BETA`/`SE` would avoid it entirely and is numerically better,
   **but that is not a documented binary route for MR-MEGA**, and the standing policy is to follow a tool's
   documented usage rather than substitute our own judgement. Binary traits therefore keep `-bt` with
   `OR`/`OR_95L`/`OR_95U` exactly as #9 specifies. The cost is filed as a GitHub issue so it is on record.
7. Result header df columns are `ndf_association`, `ndf_ancestry_het`, `ndf_residual_het`, not bare `ndf`.
   Column count is `20 + 2(T+1)`.

## Next steps

1. Benchmark at realistic dimensions before believing the memory profile. Nothing has been run at scale.
2. Route wiring belongs to the route-controller refactor, not this branch.
