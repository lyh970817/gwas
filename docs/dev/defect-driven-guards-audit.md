# Defect-driven guards: keep or remove

Prepared 2026-09-03, against `personal` @ `725304b`, following the decision that this pipeline assumes the
output of the programmes it invokes is correct and wires them per their documentation.

*Update, 2026-09-05.* The owner has retracted the blanket rule ("you may do this when it's sensible"); the
keep-or-remove decisions below remain pending, and this document remains their record. Every defect surfaced
by the audits has since been filed as an individual issue in this repository, and the entries below now cite
them.

That decision governs new work from now on. It does not by itself retire anything already merged. This
document exists so each existing case can be decided on its own.

## How to read this

Five read-only audits covered the preparation and adapter modules, the validation and routing layer, the
user-facing documentation, the test suite, and the pinned flags and command shapes. GENIE is excluded
throughout because it is being deleted; MPH is excluded from the five audits because it had not landed.
The MPH implementer's own list arrived on 2026-09-05 and is appended as Group 8.

Each item says what happens **if it is removed**, because that is the only question that matters. The
distinction that runs through the whole document is between an item that prevents a **wrong number being
published** and one that only improves an **error message**. The second kind is cheap to remove. The first
is not.

Two findings sit outside the audit's scope but were found on the way and are flagged in Group 7. They need
your attention whatever you decide here.

---

## Group 1 — Not guards at all. Removing these breaks the pipeline.

These match the description of the retired practice but are load-bearing wiring. There is no real decision
here; they are listed so they are not swept up by a keyword search for "tool defect".

| ID | Where | Removing it |
|---|---|---|
| `ldsc-stdout-capture` | `modules/local/ldsc/h2/main.nf:30-40`, `ldsc/rg/main.nf:30-40` | LDSC writes its analysis log to stdout and leaves the file it opened at `--out` empty. That log is the **only declared output** of both processes; the h² and rg estimates exist nowhere else. Remove the redirect and the pipeline publishes an empty file on a successful run. Root cause now known: the logger opens the `--out` file and never flushes or closes it, and pandas 1.5's `lru_cache`d `find_stack_level` pins the live frame when the gzip-read warning fires, so the handle is never finalised at exit. Issue #45. |
| `ldsc-gzip-predecompress` | `modules/local/ldsc/mungesumstats/main.nf:27-34` | The pinned LDSC revision reads a gzip header as bytes and crashes — no longer inferred: reproduced on the pinned image with the exact `TypeError` at `munge_sumstats.py:125`. The fork's `main` has fixed it, but `main` has diverged from the pinned `ldsc39` branch, so a pin bump within `ldsc39` does not help. The pipeline's own harmonised output is gzipped, so the route stops working. Issue #46. |
| `ldak-kvik-column-surgery` | `modules/local/ldak/kvikstep2/main.nf:53-139` | LDAK's KVIK association table has no unambiguous effect-allele frequency and no per-variant N. The join supplies both. Without them GWASLab harmonisation of the KVIK route cannot run. The **native** `.assoc` is published untouched either way (`conf/modules/ldak.config:29`). Already documented in issue #4, where the re-measurement was recorded as a comment rather than a new issue. |
| `ldak-kvik-step1-symlink-alias` | `modules/local/ldak/kvikstep2/main.nf:37-41` | `--kvik-step2` uses one prefix for both input discovery and output naming. |
| `ldak-63-ghcr-image` | `modules/local/ldak/{sumher,sumcors}/main.nf:5-7`, `sumher/Dockerfile:19,26` | The upstream LDAK 6.3 image has an intercepting entrypoint and no Bash, so a normal Nextflow task cannot launch it. Version selection, not command pinning. Issue #7 — which now also records that the pipeline's pinned "LDAK 6" image is conda `genomedk::ldak6=6.1`, not 6.2 or 6.3, that both builds print only `Version 6`, and that 6.3 `--fast-he` fails on the upstream test dataset where 6.1 succeeds. |
| `ldsc-cbiit-fork-pin` | `modules/local/ldsc/{h2,rg,mungesumstats}/main.nf:5-7` | Upstream LDSC is Python 2. This is which build to run, not how to run it. The pinned fork's own version metadata disagree (distribution 3.0.2, `ldsc.__version__` 3.0.1; issue #47), and its `main` has diverged from `ldsc39` (issue #46). |
| `metasoft-launcher` | image at `modules/local/metasoft/re2/main.nf:5-7` | METASOFT's default P-value table is a bare relative path that fails with exit 255 in any Nextflow task directory. Issue #78; the absence of any version string is issue #80. |
| `mrmega-absolute-binary-path` | `modules/local/mrmega/main.nf:26` | A trailing `/MR-MEGA` PATH entry is not reliably preserved by Apptainer, Podman or some Kubernetes executors. Issue #89 — the executor claim is recorded there, not measured under Apptainer or Podman. |
| `gwaslab-float-formats` | `modules/local/gwaslab/harmonize/templates/harmonize.py:33-59` | See Group 2 — listed there because it is a genuine decision, but it belongs in spirit here. |
| `phenotype-input-staging` | `modules/local/prepare_phenotype_inputs/main.nf:11-19` | Guards against Nextflow's staging model, not a genetics tool: an analysis id equal to its phenotype file's stem — how the fixture bundle names things — writes the output through the staged symlink and **destroys the researcher's source file**, silently, with the run reporting success. The only irreversible data-loss path found. |

---

## Group 2 — Defect-driven, and a published number depends on it

These are the real decisions.

### 2.1 `gwaslab-float-formats` — recommend KEEP
`modules/local/gwaslab/harmonize/templates/harmonize.py:33-59`, applied at `:122`.

GWASLab writes BETA, SE, OR, HR, Z, CHISQ, F and MLOG10P with a fixed four-decimal format — verified in the
vendored upstream at `io_to_formats.py:232-250`. A common variant at N=450,000 with BETA=3.12e-05 and
SE=9.8e-06 is written as `0.0000  0.0000`. The pipeline overrides the format to `{:.6e}`.

**If removed:** every effect size and standard error below roughly 1e-4 is destroyed in every published
summary-statistics file, and the inverse-variance weight `1/SE²` divides by zero downstream. This is the
one place where "publish what the tool said" and "publish a correct number" genuinely conflict.

This is not an assertion about the tool's output — it is choosing a serialisation option the tool exposes.
Issue #44 (verified against the 4.1.9 wheel in the image and the upstream 4.1.9 commit; the vendored copy
read for this audit is actually 4.2.0).

### 2.2 `gwaslab-remove-invalid` and `gwaslab-fixchrpos` — recommend REVERT or DOCUMENT
`modules/local/gwaslab/harmonize/templates/harmonize.py:93-94`.

`remove=True` (GWASLab's default is `False`) drops variants from the published table. `fixchrpos=True`
(default `False`) rewrites CHR and POS from the variant ID. Both change what is published.

**There is no comment and no commit body for either.** Nothing in the tree says what the tool would do
otherwise or why the departure was made. Under the new rule these are the strongest revert candidates in
the pipeline. If they stay, each needs one line of rationale.

### 2.3 `ldak-adjustgrm-no-factors` — recommend KEEP, and document at the point of use
`modules/local/ldak/adjustgrm/main.nf:28` emits only `--covar` and has no `--factors` argument at all.
The compensation is at `modules/local/prepare_phenotype_inputs/templates/prepare_phenotype_inputs.py:181-188`,
which treatment-codes every categorical covariate against its lexically first observed level.

LDAK's `--adjust-grm` rejects `--factors` (mode 164 is absent from the allow-list in `consistent.c`), so any
HE or PCGC analysis with a categorical covariate exits 1.

**This is the only place in the audited tree where the pipeline constructs a scientific input to route
around a rejected flag.** The design matrix is pipeline-authored, not LDAK's. `adjustgrm/main.nf` carries
no trace of why `--factors` is missing. Issue #50 (the rejection is present in both the 6.2 and the 6.3
`consistent.c`).

### 2.4 `ldak-covar-missing-cell` — recommend KEEP
Guard at `modules/local/prepare_phenotype_inputs/templates/prepare_phenotype_inputs.py:385-414`; declared by
`requires_complete_covariates` in `subworkflows/local/validate_gwas_input/method_registry.nf` on
`ldak_kvik`, `ldak_reml`, `ldak_he`, `ldak_pcgc`, `ldak_fast_he`, `ldak_fast_pcgc`; wired at
`workflows/gwas.nf:161-165,174`.

LDAK never parses a missing `--covar` cell. It leaves whatever value was last in its read buffer in place —
the neighbouring column, the previous row's last value, or uninitialised memory (measured 1.1762e-316).
The sample is still reported as retained and nothing appears in the log.

**If removed:** a user with one `NA` in a covariate file, which is ordinary in real cohort data, gets a
result computed against an arbitrary covariate value at exit 0. The substituted value is not even
deterministic.

Worth knowing about the evidence: the **first version of this claim was wrong**. It came from a probe that
removed only the first covariate of the first row, where the substituted value coincidentally matched zero.
Commit `e1b6717` corrected it — a mid-row cell gives an estimate that setting the same cell to zero does not
reproduce. The guard turned out to be more justified than it had been described.

The defect is specific to the pinned build. The pipeline's "LDAK 6" image
(`community.wave.seqera.io/library/ldak6_r-base:452828f72b3c9129`) is conda `genomedk::ldak6=6.1`, not 6.2 or
6.3. The defect reproduces there exactly — a mid-row `NA` takes the neighbouring column's value, a wholly
missing first row takes 1.1761e-316, exit 0 — while the LDAK 6.3 image mean-imputes a missing cell as
documented, and both the 6.2 and the 6.3 sources carry that imputation branch. Both builds print only
`Version 6`, so the modules' version output cannot tell them apart. The guard's justification therefore
disappears on migration to 6.3 (issue #7), which is itself gated by a 6.3 `--fast-he` failure ("Kinship
Matrix 1 has trace zero") on the upstream test dataset where 6.1 succeeds. Issue #49.

Note the honest framing: a missing cell is legal, well-formed user input. It becomes invalid only because of
how LDAK reads it. This is a defect-driven refusal wearing input-validation clothes.

**Cost of keeping** is the widest in the document: a registry capability on six method entries, ~30 lines of
Python, a `docs/usage.md` paragraph, a troubleshooting row, two nf-test cases, and a permanent widening of
the `PREPARE_PHENOTYPE_INPUTS` cache key. Removing the refusal makes `requires_complete_covariates` dead
weight across the whole registry, so this is a costly one to half-remove.

### 2.5 `gcta-hereg-covariates-ignored` — recommend KEEP the ingress refusal
`subworkflows/local/validate_gwas_input/resolve_relationships.nf:121-132`;
`subworkflows/local/route_gcta_bivariate_relationships/main.nf:137-144,196-199`;
`method_registry.nf:240,255`.

GCTA 1.94.1 lists `--qcovar` and `--covar` under the accepted options for `--HEreg-bivar` and never reads
them. Issue #34 traced it to `option.cpp`: the HEreg dispatch passes only the GRM, phenotype, keep/remove
list and trait indices, and `HE_reg`/`HE_reg_bivar` have no covariate parameter or code path at all. 1.95.3
is byte-identical with and without covariates.

**If removed:** the run succeeds and publishes an **unadjusted** genetic correlation labelled as a
covariate-adjusted one. If you do drop it, stop advertising HE as a covariate-comparable sensitivity beside
REML — the two would then differ for a reason nothing records.

### 2.6 `ldak-adjustgrm-root-basename` — recommend KEEP, as a clear-failure guard
`subworkflows/local/route_grm_heritability/main.nf:95-102,111-124`.

Adjusted GRM artifacts are deduplicated by content. LDAK records the covariate **filename** in the artifact's
`.grm.root` contract, so every consumer of a shared artifact is invoked with the one representative file
that built it rather than with its own copy.

This was the weakest-evidenced finding in the document when it was written; it no longer is. The failing
case has now been run on both LDAK images (issue #54): a byte-identical covariate file under another name,
or the same basename in a subdirectory, makes LDAK exit 1 with an explicit message that names `--check-root
NO` as the bypass. It is a loud error, not an undefined or wrong answer. The recommendation stands, but the
reason changes: the guard prevents a clear late failure on every consumer of a shared artifact, not a wrong
number. In kind it belongs with Group 3, and it should be weighed at that price.

---

## Group 3 — Defect-driven, but only improves an error message. Cheap removals.

Nothing here can cause a wrong number. Each converts an obscure late failure into a clear early one.

| ID | Where | Recommendation |
|---|---|---|
| `gctastratify-required-columns` | `modules/local/custom/gctastratifyldscores/main.nf:49-54` | **Remove.** Without it R errors obscurely on a missing column. Wrong numbers are impossible. Fires only if GCTA changes its output format. Undocumented, untested. |
| `gctastratify-finite-check` | `modules/local/custom/gctastratifyldscores/main.nf:56-60` | **Remove.** The next guard fires anyway, with a worse message. R will not silently place a variant in a stratum on `NA` comparisons. |
| `harmonize-neff-validity` (finite/positive half) | `modules/local/gwaslab/harmonize/templates/harmonize.py:97-110` | **Remove the finite/positive test**, keep the `N`-already-exists refusal — that one is pipeline logic, not tool defence. Reachable today only through a duplicate key in the KVIK join, so it is a second net under the first. |
| `harmonize-pinned-defaults` | `modules/local/gwaslab/harmonize/templates/harmonize.py:95` | **Remove.** `sweep_mode=False` is already GWASLab's default, is uncommented, and contradicts the adjacent comment saying the remaining defaults are left alone. |
| `ldak-sumher-sumcors-pipefail` | `modules/local/ldak/sumher/main.nf:35`, `sumcors/main.nf:29` | **Remove.** Redundant — `nextflow.config:249` already sets `process.shell` with pipefail — and an archived issue closed **wontfix** on exactly this point. Nine of the eleven other tee-capturing LDAK modules omit it. The cleanest removal in the audit. |
| `ldak-fast-num-blocks-floor` | `subworkflows/local/validate_gwas_input/method_options.nf:260-263` | **Your call, stylistic.** LDAK refuses cleanly with a better message than the pipeline's own. Not defect-driven — the tool behaves correctly — but it has the shape you asked about. |
| `kvik-summary-join-assertions` (header and missing-file checks) | `modules/local/ldak/kvikstep2/main.nf:56-59,71-74,93-96` | **Remove these three.** **Keep the two duplicate-key checks and the unmatched-key check** at `:78-81,109-113,114-117,127-137` — a duplicated key silently attaches the *last* match's EAF and N, giving a wrong-but-finite number that propagates into meta-analysis weights and is caught nowhere else. The join's motive is issue #4. |

---

## Group 4 — Tests

The test suite is where most of the volume is, and where most of the cheap wins are. Roughly forty findings;
the pattern is stark. Almost every high-fragility item is an exact-content or MD5 snapshot of real tool
output with **no pipeline guard behind it at all** — it documents one tool version's arithmetic. Almost
every worth-keeping item pins a string this repository authored.

### 4.1 Remove — snapshots of tool arithmetic with nothing behind them

- `tests/relational_gcta_bivariate_he.nf.test` pins the whole native `.HEreg` text including
  `rG -3.79993 7.45616 -nan`. No rG-recomputation code exists anywhere. The `-nan` SE, and the jackknife
  var/cov matrix that reaches only the `.log`, are issue #40.
- `tests/summary_statistics_ldsc.nf.test` pins ~10 floats per invocation including
  `Total Observed scale h2: -1.2938e-15 (1.1092e-15)` — numerical noise near zero, not scientific content.
- MD5 snapshots of real output in `modules/local/gcta/bivariatehereg`, `gcta/bivariateheregldms`,
  `tests/association_gcta_fastgwa.nf.test`, `tests/relational_gcta_fastgwa.nf.test`,
  `tests/heritability_gcta_greml_ldms.nf.test`, `tests/relational_gcta_greml_ldms.nf.test`,
  `tests/relational_gcta_greml.nf.test`. Keep the adjacent structural checks (`V(G)` single source row,
  `/Vp_L` presence or absence) — they catch real stratum-wiring regressions and cost nothing.
- Exact P-value strings in `modules/local/mrmega/tests` (`0.0010333`, `0.00103304`; the pins at `:70,96` are
  noted in issue #18's new comment) and METASOFT's fixed-width `0.00000` underflow format (issue #84). Keep
  the header and column-shape assertions.
- `modules/local/ldsc/mungesumstats/tests` pins a native rejection message — and already hedges between two
  possible strings, so the test anticipates its own staleness.
- `metasoft-re2-native-log-table-path` asserts an internal container path with no pipeline dependency.
- KVIK, HE and PCGC content snapshots stabilised only by a **test-only** `--random-seed 7`. The unseeded
  jackknife SE spread on the pinned 6.1 build is issue #53.
- `sumher`/`sumcors` tests pinning LDAK's exact error wording for input the tool correctly refuses — this
  documents correct behaviour, not misbehaviour. Loosen to a generic failure check.
- `sumher-sumcors-liability-arg-order` pins exact flag **order** with no evidence LDAK's parser is
  order-sensitive. Replace with unordered presence checks.
- `ldak-fast-he-pcgc-unseeded-reproducibility-warning` asserts a hardcoded factual claim about LDAK's log
  that is never re-verified against a live run. The claim itself is now measured: issue #52.

**The clearest single instance of the retired practice** is `fasthe-partial-weights-warning`
(`modules/local/ldak/fasthe/tests` and `tests/heritability_ldak_fast_estimators.nf.test`). It pins an exact
LDAK log phrase, and its own comment says: *"The pipeline adds no coverage guard of its own... This pins that
behaviour end to end so a future shared guard has a red test to turn green."* It is bait for a guard that
will now never be built. Remove both instances.

### 4.2 Keep

- `missing-covariate-cell-refusal` (`tests/heritability_ldak_fast_estimators.nf.test`, four scenarios) —
  every pinned string is pipeline-authored, and no other test exercises that guard. The strongest keep in
  the audit. Issue #49; note the build-specific caveat in 2.4.
- `hereg-covariate-message` and `hereg-binary-endpoint-message` — pipeline-authored diagnostics proven to
  block task submission. Exactly the shape the new rule preserves.
- `gcta-ldak-native-column-mapping` (`method_registry.function.nf.test`) — the load-bearing interface
  contract GWASLab harmonisation depends on. A wrong mapping mis-harmonises silently.
- The three GRM part- and stratum-ordering function tests — they guard Nextflow's `groupTuple()`
  completion-order nondeterminism against GCTA's byte-sequential GRM format. Synthetic, cheap, not about
  GCTA misbehaving.
- `hereg-manual-regression-reproduction` — independently recomputes the HE-CP regression in Groovy and
  compares to GCTA within tolerance. The most scientifically valuable test found, though note it verifies
  GCTA's mathematics rather than defending against it.
- The `ldak.fast_seed` behavioural tests (issue #52), `fasthe-default-weights-equal-alias-equivalence`,
  `hereg-ldms-native-total-contract`, the LDSC stdout-redirect tests (issue #45), and
  `ldsc-firewall-reject-samp-prev`.
- `gcta-fastgwa-binary-beta-header-pin` — keep as an **isolated** canary. GCTA reports the log-odds effect
  as `BETA` on its binary MLM route, and effect-semantic drift is a real risk; isolate it so an unrelated
  GCTA point release does not also fail the surrounding snapshot-heavy test. Issue #39.

### 4.3 Two test defects found on the way

- **`gwaslab-harmonize-six-digit-float-format` does not actually exercise the defence.** Its fixture uses
  BETA=0.10 and SE=0.02, which do not underflow at four decimals. The most consequential guard in the
  pipeline has a test that would pass with the guard removed. Needs a small-magnitude fixture such as
  3.12e-05. Recorded in issue #44.
- **`hereg-command-line-no-covariate-flags` is vacuous.** It asserts the emitted command carries no
  covariate flags, but the request under test never attaches a covariate. If covariate forwarding were
  re-added to `GCTA_BIVARIATEHEREG`, **no test in the whole GCTA-bivariate slice would catch it.**

---

## Group 5 — Documentation

Prose describing tool misbehaviour, in `docs/usage.md`, `docs/output.md` and `CHANGELOG.md`. Three passages
are the written rationale for guards that are still enforced, and must move only if their guard moves:

1. The GCTA HE-CP covariate rejection — `docs/usage.md:122`, `docs/output.md:248`, `CHANGELOG.md:33`.
2. The LDAK missing-covariate-cell rejection — `docs/usage.md:364`, `CHANGELOG.md:43`. Issue #49; if it
   stays, it should name the 6.1 build it applies to.
3. The LDAK unseeded-fast-route warning — `docs/usage.md:172,335`, `docs/output.md:186`. Issue #52.

Recommend keeping, trimmed:

- The LDAK zero-weight note (`docs/usage.md:331`) — **nothing in code catches this**, so the prose is the
  only safety net. Issue #51.
- The predictor-jackknife-block caveat (`docs/usage.md:334`) — prevents a user comparing incomparable
  standard errors.
- `CHANGELOG.md:43` — a "Breaking" entry with no stated cause is worse documentation than one with a cause.
  This is the single place where removal looks actively harmful to the record.

Recommend trimming to one line: the "stochastic in standard errors only" note (`docs/usage.md:172`; issue
#53, which also records that five unseeded runs on the 6.3 image gave identical SEs — suggestive, not
proven), and the duplicate seed warning that appears in both `usage.md` and `output.md`.

Recommend removing: the `#21` clause at `CHANGELOG.md:33` — it reads as a defect note but is ordinary
capability documentation.

`README.md` has no findings. `docs/gwas-tool-documentation/` is vendored upstream material only, and
`docs/adr/` has no tracked files.

---

## Group 6 — Looks defect-driven, is not. Separate decisions if you want them.

None of these exists because a tool misbehaves, and none is retired by the new rule. They are listed
because they are indistinguishable from Group 2 at a glance.

- **`ldak_fast_he` quantitative-only** (`method_registry.nf:362`) — not because LDAK refuses a binary trait,
  which it runs, but because this route never passes `--prevalence`. See Group 7.1.
- **`gcta_bivariate_he` quantitative-only** (`method_registry.nf:239,254`) — same shape, same reasoning.
- **PCGC binary-only** (`method_registry.nf:350,374`) — LDAK genuinely refuses a quantitative trait. This is
  user-input validation restating a native contract, and it is **not separable** from the item above
  without splitting a rule the code deliberately keeps whole.
- **REGENIE Firth defaults** (`method_options.nf:49-53`) — `firth`, `firth_approx`, `firth_p_threshold`, all
  deliberately away from REGENIE's own defaults. Scientific policy, and it changes published numbers.
- **LDAK `--cutoff 0.01`** (`route_ldak_summary_analyses/main.nf:125-127`) — the tree calls this "the
  pipeline's default rare-variant cutoff" and never states LDAK's own. Worth confirming before anyone
  assumes it is a no-op.
- **`ldsc-dual-scale-invocation`**, **`gwaslab-auto-format-refusal`**, **`ldak-reference-model-whitelists`**,
  **`gcta-fastgwa-lr-unreachable`**, **`plink2-double-id`**, **`ldsc-signed-sumstats`**,
  **`gcta-mpheno-1`**, **`ldak-power`**, **`gcta-sparse-cutoff`**, **`ldak-weights-equal`** — all policy,
  packaging or data-model convergence. Details in the source audits.
- **`gctastratify-assignment-invariant`** (`custom/gctastratifyldscores/main.nf:106`) — an invariant on **our
  own** binning arithmetic, three lines away from two Group 3 removals. Do not sweep it up: it is precisely
  the check that catches a bug in code this repository owns.
- **`prepare_cohort_genotypes/main.nf:18-32,78-85`** — argues *against* adding a post-hoc totality
  assertion. If defences are being removed, this comment is what stops someone re-adding the check it
  rejects.

---

## Group 7 — Not about the ruling, but found on the way

### 7.1 A scientific inconsistency in the pipeline's own position
`ldak_fast_he` refuses a binary trait because the route passes no `--prevalence` and would otherwise report
an observed-scale figure as a heritability. But `ldak_he` **accepts** binary traits with
`prevalence: not_consumed` and publishes exactly that observed-scale figure — the registry comment at
`method_registry.nf:97-98` says so outright. The same number is refused for one estimator and published for
another. This predates all of the above and survives whatever you decide here.

### 7.2 MR-MEGA's native P-value is demonstrably wrong
Measured on both binaries: exact at df=2; at df=3 accurate to ~1e-14, first **negative at χ²=86.96**, floors
near 9.5e-18, returns **0.352 at χ²=1980**, **0.99933 at χ²=2214**, and **exactly 1.0 from χ²=2367.68
onward**. The most significant variants get P=1. MR-MEGA's own authors ship `fixP.r` for this, and issue #18
requires unconditional recomputation in log space.

The pipeline currently publishes the native `.result` verbatim and does not recompute. The saving grace is
that `COMMON_VARIANT_META_ANALYSIS` is **not wired into `workflows/gwas.nf`** — verified — so nothing is
published today. It cannot be wired without settling this. This is the one place where "assume the output
is correct" has a documented counterexample, and it needs your explicit call rather than mine. The
re-measurement is recorded as a comment on issue #18: the df=3 profile is refined, the df=2 branch is exact,
and `fixP.r` is necessary but **not sufficient** — it still returns P=0 at χ²=7459, where the true log10 P is
−1617.87, and the six-significant-figure χ² bounds any recomputation to about 0.002 in log10 P.

### 7.3 A precision regression that was never a decision
`modules/local/prepare_ldak_summary_statistics/templates/prepare_ldak_summary_statistics.py:26` computes
`float(row["BETA"]) / float(row["SE"])`. LDAK requires a Z, so the derivation itself cannot be reverted —
but commit `a851f1e` originally wrote `format(beta / se, ".17g")` with per-row validation and a provenance
sidecar recording the conversion. Commit `ba6d8fa`, **with an empty body**, stripped all three. Because the
input is the six-significant-digit harmonised file, the Z LDAK regresses on is now re-derived from rounded
text. Recommend restoring the precision.

### 7.4 Two claimed defences that do not exist
The METASOFT K=50 cliff and MR-MEGA's `pc ≤ K-3` constraint are **not enforced anywhere**. The whole
meta-analysis stack was grepped; no code implements either and no test goes near 50 studies. Nothing to
remove — but nothing protecting against either, either. Both are now filed: the METASOFT K=50 method switch
is issue #82 and the MR-MEGA `pc ≤ K-3` constraint is issue #88, each recording that the pipeline enforces
nothing. On the direction of the K=50 switch, for the record: the tabulated table covers K=2..50, and the
ratio of tabulated to asymptotic value is 0.607 at K=50 and 1.000 at K=51, so the K≥51 values are 1.65×
**larger** — any earlier "anti-conservative" label is directionally wrong if the table is the reference.

### 7.5 The LDAK HE/PCGC seed is test-only
`--random-seed 7` for `LDAK_HE` and `LDAK_PCGC` lives in `tests/nextflow.config` alone, with an explicit
comment that production remains unseeded. The production reproducibility feature is the separate
`ldak.fast_seed` option on different modules on a different route. Any reasoning that treated the HE/PCGC
seed as a production control was wrong. Issues #52 and #53.

### 7.6 Lost rationale, and thin evidence generally
Seven load-bearing commits have **empty bodies** — `ba6d8fa`, `f6405fae`, `a851f1e`, `bf531c00`, `3d3e2000`,
`96b19c69`, `c095df0`. Between them they own the LDSC log workaround, the stripped LDAK Z precision, the
`--adjust-grm`/`--factors` design, and the deletion of the round-trip-representation rationale at
`modules/local/gwaslab/meta_analyze/templates/meta_analyze.py:20-23` — which now reads as arbitrary and is
the likeliest thing a future refactor removes. For several items in this document an inline comment is the
**only** surviving rationale, so deleting the comment destroys the record with nothing to fall back on.

### 7.7 Housekeeping found on the way
- The six `conf/containers_*.config` files are **orphaned** — none is `includeConfig`'d anywhere, and they
  reference `modules/nf-core/` paths for modules that live under `modules/local/`. Nothing is broken; they
  are dead template artifacts. `modules/nf-core/gawk` is installed and never invoked.
- `modules/local/metasoft/re2/main.nf:21` sets `JAVA_TOOL_OPTIONS`, which the image's own comment
  deliberately refuses to do because setting it at all makes the JVM print to stderr on every invocation.
  Issue #81.
- `modules/local/custom/gctamergegrmparts/main.nf:32` still reports a coreutils version via `sort --version`
  although `sort` is no longer invoked.
- `modules/local/plink2/vcf/main.nf:26-32` places `${args}` early while `makebed` and `makepgen` place it
  last. This repository has measured a real PLINK 2 positional quirk before. Worth confirming it was
  deliberate. Noted inside issue #42.
- `subworkflows/local/route_grm_heritability/main.nf:60` filters on an uncommented magic tuple arity and
  will silently drop every record if the tuple width changes.
- `resolve_references.nf:47-49` validates a declared reference checksum as 64 hex characters and **never
  hashes the file**. It has no consumer beyond display.
- `subworkflows/local/prepare_relatedness_matrices/meta.yml:10-13` documents an `nf-core subworkflows lint`
  bug and is the only explanation for a lowercase-function-name convention seven other files follow
  silently. Worth checking whether current `nf-core/tools` still has it.

---

## Group 8 — MPH

These items are on branch `add-mph-heritability` (at `a6dda90`), not yet merged. They were listed by the
implementer on 2026-09-05 as the branch's own defect-driven work, and nothing on the list has been removed.
The owner rules on them exactly as on Groups 1–7: for each, the question is what happens if it is removed,
and whether that is a wrong number or only a worse message. The implementer gave no recommendations, and
the review of the branch is still running; recommendations will follow the review. Each MPH behaviour was
filed as an issue against MPH 0.55.1 (banner "Version 0.55.1 (December 9, 2025)", release commit
`13ffe63`) on 2026-09-05; the numbers are given per item, and an item with no number defends against
something that is not an MPH defect.

### 8.1 Atom script post-conditions

| # | Where | Defends against |
|---|---|---|
| 1 | `mph/makegrm/main.nf`: `test -s *.grm.bin, *.grm.iid` | MPH prints an error and returns 0 having written nothing. Issue #55. |
| 2 | `mph/makegrm/main.nf`: `! grep -qE '^(Error\|Inconsistency)'` | Same, for errors that leave a partial file. Issue #55. |
| 3 | `mph/reml/main.nf`: `test -s *.mq.vc.csv` | A failed fit exits 0 writing only a header-only trace. Issue #55. |
| 4 | `mph/reml/main.nf`: `! grep -qE '^(Error\|Inconsistency)'` | Same. Issue #55. |
| 5 | both atoms: `eval("(mph 2>&1 \|\| true) \| sed ...")` | MPH exits 1 on its banner and has no `--version`. Issue #56. |

Issue #55 is one mechanism — `main()` catches, prints, and returns 0 — behind all four post-conditions.
Issue #72 (an unwritable `--output_file`: full fit, nothing written, no message, exit 0) is a different
mechanism that items 3 and 4 also happen to catch.

### 8.2 `custom/mphsnpinfo` (`main.nf`)

| # | Where | Defends against |
|---|---|---|
| 6 | weight-name comma/whitespace refusal (l.59) | MPH splits its name lists on commas only. Issue #57. |
| 7 | autosome universe (`in_universe`, `autosome_count`) plus weight-0 rows | GCTA restricts GRMs to autosomes; MPH applies no chromosome rule, so a shared bundle would give the two engines different predictor sets. Documented GCTA behaviour, not filed. |
| 8 | SNP in more than one group file (l.107) | Plan/BIM consistency. Pipeline-side. |
| 9 | group SNP absent from the BIM (l.102) | The plan and the bundle are not the same view. MPH's silent `--snp_info_file` subsetting of the BIM is documented behaviour, not filed. |
| 10 | group SNP outside the autosome universe (l.112) | The plan and the BIM disagree on the universe. Pipeline-side. |

### 8.3 `prepare_mph_inputs` (`templates/prepare_mph_inputs.py`)

| # | Where | Defends against |
|---|---|---|
| 11 | `read_sample_order`: `.grm.iid` must equal the FAM IID column in FAM order (l.177) | MPH indexes the matrix by that file's order with no check; a reversed file gives a complete, stable, **wrong** result at exit 0 (pve 0.115563 → −0.299462, 5/5 runs). Issue #58. |
| 12 | `read_sample_order`: duplicate IID in the FAM (l.164) | MPH keys samples by IID alone; a duplicate IID segfaults with no message. Issue #59. |
| 13 | `read_traits`: FID/IID pairing must match the FAM (l.219) | MPH would include a sample GCTA would drop. Issue #59. |
| 14 | `MISSING_TOKENS` rewritten to empty fields | A literal `NA` aborts MPH (uncaught `std::invalid_argument`, exit 139); `-9` is read as the number −9. Issue #60. |
| 15 | `numeric_or_fail` non-finite refusal (l.196) | A `nan` phenotype makes the solver loop without bound; a `nan` covariate gives a header-only trace at exit 0. Issue #61. |
| 16 | explicit all-ones intercept column, named first | MPH synthesises no intercept once a covariate is named. Issue #62. |
| 17 | `encode_covariates` dummy encoding | MPH never expands a categorical covariate. Issue #64. |
| 18 | `check_mph_names` on emitted covariate names (l.145/151) | MPH splits `--covariate_names` on commas. Issue #57. |
| 19 | zero-analysis-set refusal (l.314) | An empty analysis set is not a fittable model. Pipeline-side. |
| 20 | `complete_case_attrition` warning (l.357) | Records samples MPH will drop for an empty covariate cell. Documented MPH behaviour, not filed. |
| 21 | `dropped_not_in_grm` warning (l.362) | Records phenotype rows outside the matrix. Pipeline-side. |
| 22 | `split_row` / per-row column-count check (l.106/115) | Our own reader. The implementer classes this as ordinary input validation, not a guard. |

### 8.4 `summarise_mph_result` (`templates/summarise_mph_result.py`)

| # | Where | Defends against |
|---|---|---|
| 23 | analysis-set cross-check, fatal (l.189) | MPH's reported N against the count the prepared inputs predict. Pipeline-side. |
| 24 | pruned-intercept refusal (l.158) | MPH prunes a rank-deficient design silently; the pruned column is unnamed and can be the intercept, which changes the model. Issue #65. |
| 25 | other pruned covariate → warning (l.165) | Records columns MPH dropped and never names. Issue #65. |
| 26 | `WARNING_PATTERNS` → `not_converged`, `covariate_matrix_rank_deficient`, verbatim others | Both are exit-0 log lines beside a complete result (non-convergence: pve 0.142655 against 0.0873109). Issues #66 and #65. |
| 27 | `native_predictor_count` matched by `vc_name`; a plan component with no result row is fatal (l.135) | Never match by position. Pipeline-side. |
| 28 | `num_threads` read from the log's `OPTION` echo | The thread count is an input to the estimate. Issue #68. |

### 8.5 Registry, options, route, config

| # | Where | Defends against |
|---|---|---|
| 29 | `method_registry.nf`: `mph_grm`/`mph_grm_family` separation, with a comment citing the `gcta --pca` eigenvalue evidence | Neither engine may be handed the other's bytes: the GRM formats differ in header, triangle order, scaling and companion files, and relabelling fails silently both ways. Issue #69. |
| 30 | `method_registry.nf`: `requires_complete_covariates: false`, with a measured comment | MPH drops a blank-cell sample and reports it. Documented behaviour, not filed. |
| 31 | `method_options.nf`: `gcta.grm_maf`/`gcta.grm_extract` refused beside an MPH selector | The implementer classes this as **pipeline policy**, not a defect. |
| 32 | `method_options.nf`: `resolveMphMethodOptions` comments (seed moves point estimates; tolerance floor recorded) | Prose only. Issues #67 and #76. |
| 33 | `route_mph_heritability/main.nf`: `buildMphEffectiveSettings` emits `reproducibility`, no `deterministic` | A determinism claim would be false across thread counts and memory modes. Issues #67 and #68. |
| 34 | `conf/modules/mph.config`: `.mq.py.csv` excluded from publication | Individual-level data, scaling with the cohort. Pipeline-side. |
| 35 | `tests/nextflow.config`: `MPH_MAKEGRM\|MPH_REML` container override, cpus/memory not pinned, with a comment | Prose only. |

On seeds, for the record: `tests/nextflow.config` does **not** pin an MPH seed; the route test does
(`tests/heritability_mph_reml.nf.test:45,110`). Issue #67.

### 8.6 Two corrections recorded during filing

- **The 0.085 → 0.191 figure is confounded** (issue #65). It compares the `C-cov_with_intercept` and
  `C-cov_all` fits, and the `all` fit also carries `Q1`, `Q2`, `Q3` and `SEX`; no run isolates the intercept.
  `docs/usage.md:382` and `summarise_mph_result.py:26-30` on the branch overstate it, and item 24's
  justification rests on the mechanism, not on that number.
- **The enrichment row was mislabelled** (issue #68). `MPH-NATIVE-CONTRACT.md` C11's
  4.19322/4.19319/4.19325 is the enrichment-**covariance** column; the enrichment itself is
  1.70283/1.70282/1.70283 across thread counts. The conclusion that the thread count moves the sixth to
  seventh figure survives the relabelling.

### 8.7 Tests and prose on the branch that pin defect behaviour

Expected-failure cases for items 6, 8–13, 15, 18, 23, 24 and 27 in
`modules/local/{custom/mphsnpinfo,mph/reml,prepare_mph_inputs,summarise_mph_result}/tests/main.nf.test`;
warning-vocabulary, cross-check and covariate-reconciliation assertions in `tests/heritability_mph_reml.nf.test`;
a `--num_iterations 1` non-convergence case in `modules/local/mph/reml/tests/main.nf.test` (issue #66).

Prose describing MPH misbehaviour: the `docs/usage.md` reproducibility paragraph (seed-to-seed spread at
three random-vector settings; issue #67), rank-deficiency paragraph (intercept pruning and the confounded
0.085 → 0.191 figure; issue #65), missing-value paragraph (`NA` / `-9` / `nan`; issues #60, #61), and the
iterations and tolerance table cells (issue #76); in `docs/output.md`, "sidecar is written after the fit" and
the GCTA/MPH bundle non-interchangeability (issue #69); in `CHANGELOG.md`, the `--pca` eigenvalue sentence
(issue #69), the `.grm.iid`-order sentence (issue #58) and the cross-check sentence; and the `meta.yml` of
`mph/makegrm`, `mph/reml`, `prepare_mph_inputs` and `summarise_mph_result`. These are decided with their
guards, as in Group 5.

Also reported by the implementer, not a guard: a helper hit `gcta --ld-score-region` exiting 139 with no
message when the bundle's base-pair span is narrower than one region width. Nextflow fails the task on the
exit code, so it is not silent, and no compensation was built. Issue #38.

---

## What this audit could not establish

It was read-only by design. Nothing was executed, so every claim about what a tool does comes from the
tree, from vendored upstream source, or from a previously recorded measurement — not from a fresh run.
Three items rested on inference rather than record when this was written. Two have since been measured
during issue filing: the LDAK `.grm.root` basename coupling (2.6, issue #54) and the LDSC gzip crash
mechanism (Group 1, issue #46). Only the MR-MEGA ordinal filename motive remains inferred.

Two scopes were not covered by the five audits and would need the same treatment for a complete inventory:
the `subworkflows/local/common_variant_meta_analysis/` stack, and the GENIE and MPH routes — the first
because it is being deleted, the second because it had not landed. The METASOFT and MR-MEGA tools behind
the first are now covered by issues #78–#104, though the stack itself has still not been audited. Group 8
lists the MPH items as reported by their implementer; it is not an independent audit of that route.

---

## Structural observations worth keeping

**The tree already states the new policy.** `subworkflows/local/validate_gwas_input/method_options.nf:8-10`:
*"A `null` default always means 'pass nothing and let the native default stand', never 'zero' or 'off' …
which is what makes an unset option reproduce the tool's own documented behaviour rather than a pipeline
opinion."* Everything in this document is an exception to a rule the codebase already holds.

**The concentration is narrow.** Across all 32 GCTA and LDAK module files there is not one comment inside a
`script:` or `stub:` block, no flag pinned to a documented default, and no order claim. The retired pattern
lives in exactly three places: GWASLab formatting (issue #44), LDSC's broken logger and gzip reader (issues
#45, #46), and GENIE — which was by far the densest case and is already leaving.
