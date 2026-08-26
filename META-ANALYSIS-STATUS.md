# Common-variant meta-analysis (#9) — paused work status

Branch: `meta-analysis-per-variant-modules`, branched from `extend-method-registry-capabilities` (`eee8f4c`).

Work on GitHub issue `lyh970817/gwas#9` was **paused by user decision** partway through building the three
per-variant components. This file records exactly where the work stopped so it can be resumed rather than
restarted. Nothing here is wired into `workflows/gwas.nf`; a concurrent route-controller refactor owns that file
and was deliberately not touched.

## Component status

| Component                       | Path                                  | State                                                                                                                                                                                                        |
| ------------------------------- | ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `GWASLAB_META_ANALYZE`          | `modules/local/gwaslab/meta_analyze/` | **Partial but functional.** `main.nf` + `environment.yml` + `templates/meta_analyze.py` are complete and were executed successfully end to end against the pinned container. **No `meta.yml`, no `tests/`.** |
| `METASOFT_RE2`                  | _not created_                         | **Not started.** Contract designed (below), nothing written.                                                                                                                                                 |
| `NORMALISE_COMMON_VARIANT_META` | _not created_                         | **Not started.** Contract designed (below), nothing written.                                                                                                                                                 |

`modules/local/gwaslab/meta_analyze/main.nf` passes `nextflow lint` with no errors. The only warning is a false
positive (`prefix_literal` declared but not used — it _is_ used, inside the Python template, which the linter
does not parse). `normalise_ldsc` has the same pattern.

## Settled take/emit contracts

### `GWASLAB_META_ANALYZE` (implemented)

```nextflow
input:
tuple val(meta), path(sumstats, stageAs: 'parents/*'), val(study_names), val(input_format), val(genome_build)

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

`task.ext.args` is a **closed whitelist**, validated in the template, and rejects everything else:

- `--random-effects` — adds the DerSimonian–Laird columns
- `--min-studies <INT>` — default 2, must be ≥ 2 and ≤ number of parents
- `--chromosome <VALUE>` — optional shard selector, default genome-wide

There is no native GWASLab argument pass-through.

Published candidate columns (`.meta.tsv.gz`):

```
SNPID CHR POS EA NEA STATUS EAF BETA SE P N
N_STUDIES DIRECTION EAF_META EAF_MIN EAF_MAX N_TOTAL MAX_WEIGHT_SHARE Z_FIXED Q P_HET I2
[BETA_RANDOM SE_RANDOM Z_RANDOM P_RANDOM TAU2_RANDOM]
META_VARIANT_KEY
```

### `METASOFT_RE2` (designed, not written)

```nextflow
input:
tuple val(meta), path(effect_matrix)

output:
tuple val(meta), path("${prefix}.metasoft.txt"),  emit: native
tuple val(meta), path("${prefix}.re2.tsv.gz"),    emit: re2
tuple val(meta), path("${prefix}.metasoft.log"),  emit: log
path "versions.yml", emit: versions, topic: versions
```

Study count `K` is derived from the matrix width, so it is not a separate input. Container
`ghcr.io/lyh970817/metasoft:2.0.1` with a TODO for the digest pin (see below). No `environment.yml` is possible
— METASOFT is not in Bioconda; follow the `modules/local/ldak/*` precedent of a container directive with no
`conda` directive.

### `NORMALISE_COMMON_VARIANT_META` (designed, not written)

```nextflow
input:
tuple val(meta), path(meta_analysis), path(study_order), path(qc), path(derivation), path(re2), path(mrmega)

output:
tuple val(meta), path("${prefix}.candidate.tsv.gz"), emit: candidate
tuple val(meta), path("${prefix}.derivation.json"),  emit: derivation
path "versions.yml", emit: versions, topic: versions
```

`re2` and `mrmega` are optional path members; callers pass `[]`. Container is the plain-Python Seqera image
already used by `normalise_ldsc` / `canonicalise_summary_statistics` — deliberately **not** a SciPy image, see
the log-space note below.

## Verified vs untested

### Verified by execution

- `SumstatsMulti.run_meta_analysis()` **is present in the pinned `bioconda::gwaslab=4.1.9`** and works. No
  version bump is needed. Confirmed inside `quay.io/biocontainers/gwaslab:4.1.9--pyhdfd78af_0`.
- The whole template runs to exit 0 on a three-study fixture and produces every declared output.
- **Analytical two- and three-study inverse-variance results** reproduce the hand calculation exactly:
  - three studies, SE 0.02/0.03/0.04, BETA 0.10/0.14/0.08 → `w` = 2500 / 1111.11 / 625, `BETA` = 0.1075410,
    `SE` = 0.01536443, `Z` = 6.999349. Module emitted `1.075410e-01`, `1.536443e-02`, `6.999349e+00`.
  - two studies (parent 1 absent), SE 0.01/0.02, BETA 0.05/0.07 → `BETA` = 0.054, `SE` = 0.008944272,
    `Q` = 0.8, `P_HET` = chi2.sf(0.8, 1) = 0.3710934, `I2` clipped to 0. All matched.
  - `MAX_WEIGHT_SHARE` verified: 2500/4236.11 = 0.5901639 and 10000/12500 = 0.8.
- **GWASLab FE vs METASOFT FE agree to all six significant figures METASOFT emits**, on the module's own
  emitted effect matrix, run offline (`--network none`):

  | key          | GWASLab BETA / SE / P                      | METASOFT BETA_FE / STD_FE / PVALUE_FE   |
  | ------------ | ------------------------------------------ | --------------------------------------- |
  | `1:1000:A:G` | 1.075410e-01 / 1.536443e-02 / 2.571538e-12 | 0.107541 / 0.0153644 / 2.57154E-12      |
  | `1:4000:G:C` | 5.400000e-02 / 8.944272e-03 / 1.566331e-09 | 0.0540000 / 0.00894427 / 1.56633E-09    |
  | `2:5000:G:A` | 3.086618e-05 / 6.067884e-06 / 3.641343e-07 | 3.08662E-05 / 6.06788E-06 / 3.64134E-07 |

  `RE` equalled `FE` on this fixture because τ² was 0 everywhere; a genuinely heterogeneous fixture is still
  needed to exercise the RE path.

- **Precision protection works end to end.** The `2:5000:G:A` row is the pathological case (`BETA` 3.12e-05,
  `SE` 9.8e-06) that four-decimal formatting destroys. It survives parent loading, alignment, the effect
  matrix, the published table, and METASOFT.
- **Allele alignment**: a parent carrying the swapped representation (`EA`/`NEA` exchanged, `BETA` negated,
  `EAF` complemented) is realigned correctly by GWASLab, and the direction string reads `+++`.
- **Outer union**: a variant absent from parent 1 (the merge mold) is still present in the result with
  direction `?++` — `keep_all_variants=True` genuinely produces an outer union, not a mold-restricted join.
- Empirically characterised GWASLab merge behaviour on indels, multi-allelic sites, duplicate keys, missing
  EAF, and reverse-complement representations (see design decisions).

### Not tested at all

- Everything through nf-test. There is no `tests/main.nf.test` and the stub has never been executed.
- The `--chromosome` shard selector code path.
- The `--random-effects` path against a fixture with real between-study heterogeneity (τ² > 0).
- Any failure/rejection path (bad `input_format`, `auto`, fewer than two parents, duplicate study names,
  `min_studies` out of range, a parent retaining no usable variant).
- `nf-core pipelines lint` and the repo pre-commit hooks were **never run** on this branch.

## Design decisions that are not obvious from the code

1. **The effect matrix is headerless.** #9 describes the layout as `META_VARIANT_KEY BETA_1 SE_1 …`; that is a
   column layout, not a literal header row. METASOFT's parser rejects any non-numeric token that is not `NA`
   and aborts on the first offending line, so a header row makes the file unusable. This was found by running
   it — the first version had a header and METASOFT produced an empty output file.
2. **Contribution masking happens before GWASLab sees the data.** GWASLab's fixed-effect loop silently requires
   non-null `N` _and_ `EAF` in addition to `BETA`/`SE > 0`. A parent row with a perfectly good effect estimate
   but a missing `EAF` therefore contributes nothing, with no warning. The template applies exactly that same
   mask itself, up front, and reports the loss source-attributed in `qc.json` as
   `contributions_lost_to_missing_n_eaf` / `excluded_missing_n` / `excluded_missing_eaf`. This also guarantees
   the emitted effect matrix contains precisely the estimates that contributed, so the GWASLab/METASOFT
   cross-check compares like with like.
3. **Reverse-complement disagreements are excluded, not resolved.** GWASLab's `_align_with_mold` matches only
   exact and swapped allele pairs. A parent carrying the reverse-complement representation (`A/G` vs `T/C` at
   the same position) does **not** merge — it silently becomes a _second union row_ holding a subset of the
   studies, so one variant is reported twice with disjoint study sets. Verified experimentally. The template
   detects such sites across parents up front, drops all involved rows from every parent, and counts them
   (`strand_conflict_sites`, `strand_conflict_rows_excluded`). #9 forbids a new frequency-based strand guess at
   the meta stage, so exclusion is the only honest option. Palindromic sites (`A/T`, `C/G`) are their own
   reverse complement, self-match, and merge normally; that inherits the parents' declared harmonisation.
4. **Duplicate normalised keys are dropped per parent, all copies, and counted.** `meta_analyze_multi` does a
   silent `drop_duplicates(subset=["CHR","POS","EA","NEA"], keep="first")`. Keeping an arbitrary first row is
   not defensible, so both copies go and `excluded_duplicate_key` records it.
5. **Output `STATUS` is a per-digit consensus of the _contributing_ parents, falling back to GWASLab's unknown
   digit `9`.** The merge copies the mold's `STATUS` onto rows a parent never supplied, so the mask matters.
   This is the conservative reading of #9's "must never claim that a reference or strand check occurred when it
   did not".
6. **Two float formats.** The published candidate uses `{:.6e}` (matching `gwaslab/harmonize`). The
   intermediate adapter inputs (`study_views`, `effect_matrix`) use Python `repr()` — the shortest
   representation that round-trips to the identical float64 — because they feed native tools and must lose
   nothing at all.
7. **`TAU2_RANDOM` is computed in the template, not read from GWASLab.** `meta_analyze_multi` drops its
   internal `_R2` column before returning, so between-study variance is recomputed as
   `max(0, (Q − df) / (W − W2/W))` from the module's own weight sums.
8. **Output is re-sorted explicitly** by `(CHR, POS, EA, NEA)` with `kind="mergesort"`. GWASLab sorts by
   `(CHR, POS)` only, with pandas' default non-stable quicksort, which is a real determinism hazard at
   multi-allelic sites.
9. **`Q`/`P_HET`/`I2` are withheld (`NA`) when fewer than two studies contribute**, and `Q` is clamped at 0.
   GWASLab emits `I2 = 1.0` and floating-point noise like `Q = 3.55e-15` for single-contribution rows.
10. **QC counts are deliberately shard-composable** — additive integers, or min/max ranges — so the module can
    be scattered per chromosome later and the QC documents summed. Nothing in `qc.json` is a genome-wide-only
    statistic.
11. **`study_names` is an explicit tuple scalar** rather than derived from staged basenames, because positional
    study order is the determinism contract for the direction string, the effect matrix column order, and the
    study-order table.

## Contract briefings received during this work — do not lose these

These were established empirically by other agents this session and were expensive to produce. They supersede
what #9 says where they conflict.

### METASOFT `ghcr.io/lyh970817/metasoft:2.0.1`

Image digest `sha256:2d06009b822ca983f10067e63161f69247bce49e6cdf7ee3baab98d98fa70a3b`. **Do not pin it yet** —
a licence-permission file inside the image still has unfilled placeholders and filling them forces a rebuild
and a new digest. Reference the tag with a clearly marked TODO.

- **RE2 requires no flag.** FE, RE and RE2 are always computed. Only binary-effects and M-values are opt-in.
  Full invocation is `metasoft -input X -output Y -log Z`; the image's launcher injects `-pvalue_table`
  automatically (METASOFT's own default is a bare relative path that fails with exit 255 in any task
  directory).
- **No version output exists in the jar.** Use `metasoft --version` or `/opt/metasoft/VERSION`.
- One-JAR fat jar, class versions 46–50, byte-identical output on Temurin 8/11/17/21/25. Offline execution
  proven with `--network none` and `--user 1000:1000`.
- Output columns 9/10/11 are `PVALUE_RE2`, `STAT1_RE2`, `STAT2_RE2`. Columns 10 and 11 are _statistics_, not
  p-values — their sum is the Han–Eskin statistic. #9's "mean-effect and heterogeneity components" map to
  STAT1/STAT2.
- 18-name header, 16 fixed columns plus two K-wide blocks. **Header and data rows are not tabular-parser
  compatible** — data rows carry a trailing tab, so `awk -F'\t'` sees 18 vs 17+2K fields. Parse deliberately.
- Row order is preserved, but comment/blank/one-token lines vanish and duplicate keys are permitted. **Join by
  key on a de-duplicated input**; never rely on positional correspondence.

Silent-failure modes the module must defend against:

1. **Partial pairs are not rejected, they are silently swallowed.** `BETA` present with `SE=NA` drops that
   entire study, exit 0, no warning — and the output row is _bit-identical_ to a properly paired `NA NA` row,
   so the corruption is undetectable downstream. #9's pairing rule must be enforced entirely upstream in the
   matrix generator. `GWASLAB_META_ANALYZE` already guarantees this by masking `BETA` and `SE` together;
   `METASOFT_RE2` must still assert it on its own input, with a test.
2. **Undocumented K=50 discontinuity.** The p-value table covers K = 2..50. At **K = 51 the correction ratio
   jumps from ~0.61 to exactly 1.000**, shifting RE2 p-values roughly 1.6× anti-conservative, with no warning.
   The module must reject or loudly warn above K = 50. #9's own benchmark scenarios include 50 studies, so
   this is reachable in normal use.
3. **Small tails underflow to the literal string `0.00000`** at roughly 1e-307 (χ² ≈ 1400 → 2.1E-306;
   χ² ≈ 1450 → `0.00000`), exit 0. IEEE double underflow, not policy truncation, and reachable through
   heterogeneity alone — betas +5/−5/0 gave FE p = 1.0 but RE2 p = `0.00000`. Never read `0.00000` as a real
   probability.
4. **Degenerate-but-positive SEs give `NAN` at exit 0.**
5. **Exit codes are inconsistent.** Truncated output _is_ left behind on mid-file failure (exit 255, last line
   cut mid-field); an unwritable log gives 255 with a _good_ output; leading whitespace throws an uncaught Java
   exception with exit **1**, not 255. Assert on output completeness and content, never on exit code alone.

For the GWASLab cross-check: `I_SQUARE` is a **percentage**, not a fraction, and METASOFT's τ² uses a
non-textbook `U` denominator, so textbook DerSimonian–Laird does **not** match. Do not treat that as a bug.

Confirmed as #9 assumed: no allele columns, enforced at the parser level — any non-numeric token that is not
`NA`/`N/A` is a hard error, so harmonisation genuinely happens entirely upstream.

### MR-MEGA `ghcr.io/lyh970817/mrmega:0.2`

Image ID `sha256:a001bc7857b90c3c469e96a50d2e59b0ce95acb16cd1564e2d46ca467f300803`. Built but **not pushed**
pending the authors' reply. Reference by tag with a TODO.

1. **Unconditional P-value discard is necessary but not sufficient — the recomputation must happen in log
   space.** Upstream ships its own fix (`fixP.r`, bundled at `/usr/share/doc/mrmega/`) which recomputes in
   _linear_ space and returns `P = 0` for a real χ² = 7459 top hit. Linear-space recomputation underflows
   exactly where it matters most. A stdlib-only `chi2_logsf` was verified against R to 4e-11 absolute in
   log10, giving `log10P = −1617.87` where both the native value (1.0) and `fixP.r` (0.0) fail completely.
   **Emit log-scale P values as the stable published contract** and derive linear P only where representable.
   This is why `NORMALISE_COMMON_VARIANT_META` should stay on the plain-Python container and implement
   `chi2_logsf` with `math.lgamma` rather than reach for SciPy.

   The MR-MEGA column set must therefore be **log-scale-first**, not linear with a log afterthought — that is
   the part that would be expensive to retrofit:

   ```
   MRMEGA_CHISQ_ASSOC MRMEGA_DF_ASSOC MRMEGA_LOG10P_ASSOC MRMEGA_P_ASSOC
   MRMEGA_CHISQ_ANCESTRY_HET MRMEGA_DF_ANCESTRY_HET MRMEGA_LOG10P_ANCESTRY_HET MRMEGA_P_ANCESTRY_HET
   MRMEGA_CHISQ_RESIDUAL_HET MRMEGA_DF_RESIDUAL_HET MRMEGA_LOG10P_RESIDUAL_HET MRMEGA_P_RESIDUAL_HET
   MRMEGA_LNBF
   ```

   Related detail: the native defect is confined to `df ≠ 2`. `df == 2` takes an `exp(-x/2)` shortcut and is
   exact everywhere. But _which_ P column is sound flips with `--pc` and K, which is precisely why the discard
   must be unconditional rather than clever. `P = 1.0` begins at χ² ≈ 2600, not 2000 (at 2000 it returns
   0.466); the cause is `KM()` summing a fixed 1000 terms while the series peaks at n ≈ χ²/2.

2. **#9's axis bound is wrong: `pc ≤ K−3`, not `K−2`.** The binary's gate is `K-2 > pc`, strictly. With K = 5,
   `--pc 3` produces 300/300 `SmallCohortCount` and **exit 0 with no message** — silent garbage. Upstream's web
   page agrees with the binary; the 2017 paper's `T ≤ K−2` does not, and #9 copied the paper. Validation must
   enforce `1 ≤ axes ≤ K−3`. `--pc` defaults to 3 in the binary but 4 in the docs — always pass it explicitly.

3. Silent wrong answers to guard against: `NA` in EAF is parsed as **0.0** and accepted, so the adapter must
   reject missing/invalid EAF before invocation; `--no_alleles` **negates β for every study after the first**
   (a real bug — `_ea` left empty, comparison against `"N"` always fails), which is why #9 forbids it;
   within-file duplicate markers overwrite silently (the de-duplication map is dead code, never written to);
   the marker key is the **name string only** — chromosome/position mismatches are counted but ignored, so the
   allele-aware key must be constructed upstream; errors numbered 1–5 are never printed at all, which is the
   mechanism behind most of the above; a missing manifest or zero shared markers **segfaults** (exit 139), so
   assert inputs before invoking; `-t`, `-m` and `--name_strand` are entirely inert — MR-MEGA does no strand
   handling whatsoever.

4. **Sign canonicalization is a pure post-hoc transform.** Negating an axis flips exactly `beta_{j+1}` and
   leaves `se`, every χ², every ndf, every P and `lnBF` bit-identical. #9's sign-canonicalization requirement
   is therefore clean post-processing with no numerical consequences.

## Exact next steps to resume

1. `modules/local/gwaslab/meta_analyze/meta.yml` — write it against the real contract above. Every file entry
   needs `ontologies:` (EDAM term or empty list); inputs and outputs must stay in `main.nf` order.
2. `modules/local/gwaslab/meta_analyze/tests/main.nf.test` (+ `tests/nextflow.config`). Reuse the fixtures in
   this file's "Verified" section — they are small, hand-checkable and already produce known answers. Cover:
   the three-study analytical case, the two-study case, the flipped-allele parent, the outer-union variant, the
   precision variant, `--chromosome` sharding, `--min-studies` exclusion, `--random-effects`, the rejection
   paths, and the stub. The prototype fixture generator and the Nextflow-template renderer used during this
   work are in the session scratchpad under `proto/` (`mk.py`, `run.py`, `probe2.py`, `render.py`) — the
   renderer is genuinely useful for iterating on a template without paying nf-test startup cost.
3. Build `METASOFT_RE2` to the contract above. Note the image has **no Python** — only BusyBox `awk`, `sed`,
   `sort`, `gzip`, `sha256sum`. The preflight (partial-pair rejection, K bounds, field-count check) and the
   output normalisation both have to be BusyBox awk.
4. Build `NORMALISE_COMMON_VARIANT_META` to the contract above, with the log-space `chi2_logsf` and the
   MR-MEGA column set reserved but unpopulated.
5. Then run, in this order: `pre-commit run --files <changed files>` (**never** `--all-files`; it mutates
   unrelated tracked files in this repo), `nf-core pipelines lint`, and the new module tests. Read
   `.agents/skills/gwas-pipeline-test/SKILL.md` first for procedure and evidence requirements.
6. Route wiring is explicitly out of scope for this branch and belongs to the route-controller refactor.
