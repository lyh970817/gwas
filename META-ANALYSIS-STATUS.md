# Common-variant meta-analysis (#9) — work status

Branch: `meta-analysis-per-variant-modules`, branched from `extend-method-registry-capabilities` (`eee8f4c`).

Work on GitHub issue `lyh970817/gwas#9`. Nothing here is wired into `workflows/gwas.nf`; the route-controller
refactor owns that file and was deliberately not touched. This file is kept current so another pause is cheap.

## Component status

| Component                       | Path                                               | State                                                              |
| ------------------------------- | -------------------------------------------------- | ------------------------------------------------------------------ |
| `GWASLAB_META_ANALYZE`          | `modules/local/gwaslab/meta_analyze/`              | **Complete.** 14/14 nf-tests green.                                |
| `METASOFT_RE2`                  | `modules/local/metasoft/re2/`                      | **Complete.** 8 nf-tests.                                          |
| `NORMALISE_COMMON_VARIANT_META` | `modules/local/normalise_common_variant_meta/`     | **Complete.** 6/6 nf-tests green.                                  |
| `GATHER_META_SHARDS`            | `modules/local/gather_meta_shards/`                | **Complete.** 10/10 nf-tests green.                                |
| `PREPARE_MRMEGA_INPUT`          | `modules/local/prepare_mrmega_input/`              | **Complete.** 5/5 nf-tests green.                                  |
| `MRMEGA`                        | `modules/local/mrmega/`                            | **Complete.** 6/6 nf-tests green against the pinned quay digest.   |
| `COMMON_VARIANT_META_ANALYSIS`  | `subworkflows/local/common_variant_meta_analysis/` | **Complete for fixed/random/re2.** MR-MEGA deliberately not wired. |

## What is NOT built

Three components stand between the finished `MRMEGA` module and a wired multi-ancestry route. They are the
entire remaining gap:

1. **`THIN_MRMEGA_MARKERS`** — thin the gathered genome-wide aligned representation to at most one marker per
   Mb for pass 1. MR-MEGA's own axis derivation already uses at most one marker per Mb bin on chromosomes 1-23
   with MAF > 1% in every study, so pre-thinning loses nothing and bounds pass-1 memory.
2. **`EXTRACT_MRMEGA_AXES`** — parse the `Principal components:` block out of the pass-1 `.log`, canonicalize
   each axis sign by a deterministic rule over the ordered source coordinates, and emit the `--precalculated`
   manifest. Sign canonicalization is a pure post-hoc transform: negating an axis flips exactly `beta_{j+1}`
   and leaves `se`, every chi-square, every ndf, every P and `lnBF` bit-identical, so doing it between the two
   passes means the shards are born canonical.
3. **`NORMALISE_MRMEGA_RESULT`** — convert the native `.result` into the keyed schema
   `NORMALISE_COMMON_VARIANT_META` already accepts (`META_VARIANT_KEY`, the three chi-square/df pairs,
   `MRMEGA_LNBF`, and the three native P values for debug provenance only). This is the smallest of the three
   and is pure column mapping; the normalizer's log-space recomputation is already built and tested.

The two-pass design, which is proven feasible:

```
thin genome-wide to <=1 marker/Mb  ->  pass 1: derive axes  ->  canonicalize axis signs
   ->  scatter per chromosome with --precalculated fixed axes  ->  gather
```

Scatter contributes **zero** error: per-chromosome scatter against unscattered gave 300/300 identical rows on
the pinned binary. A separately measured 2.46e-06 max relative difference in `chisq_association` comes entirely
from the 6-significant-figure precision of the axis coordinates echoed in the log, not from sharding.

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

### `NORMALISE_COMMON_VARIANT_META`, `PREPARE_MRMEGA_INPUT`, `MRMEGA`

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
6. **The binary route is lossy twice over.** MR-MEGA's native inverse is
   `se = (ln(OR) - ln(OR_95L)) / 1.96` with a hard-coded 1.96, not the exact quantile, so writing true 95%
   bounds makes it reconstruct an SE smaller than canonical by `z/1.96 - 1 = -1.8375e-05`, inflating every
   chi-square by ~3.7e-05 relative. Recorded in `adapter_qc.json` rather than compensated. Since the canonical
   representation is already log-OR with SE, **routing binary traits through `--qt` with `BETA`/`SE` avoids
   this entirely and is numerically strictly better** — that is a route-level decision worth taking.
7. Result header df columns are `ndf_association`, `ndf_ancestry_het`, `ndf_residual_het`, not bare `ndf`.
   Column count is `20 + 2(T+1)`.

## Next steps

1. Build the three MR-MEGA glue components listed under "What is NOT built" and extend the subworkflow with the
   two-pass scatter. The seam is already there: `GWASLAB_META_ANALYZE.out.study_views` feeds
   `PREPARE_MRMEGA_INPUT`, and `NORMALISE_COMMON_VARIANT_META` already accepts a keyed MR-MEGA file and
   recomputes its P values.
2. Run `nf-core pipelines lint`.
3. Benchmark at realistic dimensions before believing the memory profile.
4. Route wiring belongs to the route-controller refactor, not this branch.
