# Defect-driven guards: keep or remove

Prepared 2026-09-03, against `personal` @ `725304b`, following the decision that this pipeline assumes the
output of the programmes it invokes is correct and wires them per their documentation.

That decision governs new work from now on. It does not by itself retire anything already merged. This
document exists so each existing case can be decided on its own.

## How to read this

Five read-only audits covered the preparation and adapter modules, the validation and routing layer, the
user-facing documentation, the test suite, and the pinned flags and command shapes. GENIE is excluded
throughout because it is being deleted; MPH is excluded because it has not landed. The MPH agents were
told to report their own defect-driven work separately, and that will be appended when it arrives.

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
| `ldsc-stdout-capture` | `modules/local/ldsc/h2/main.nf:30-40`, `ldsc/rg/main.nf:30-40` | LDSC writes its analysis log to stdout and leaves the file it opened at `--out` empty. That log is the **only declared output** of both processes; the h² and rg estimates exist nowhere else. Remove the redirect and the pipeline publishes an empty file on a successful run. |
| `ldsc-gzip-predecompress` | `modules/local/ldsc/mungesumstats/main.nf:27-34` | The pinned LDSC revision reads a gzip header as bytes and crashes. The pipeline's own harmonised output is gzipped, so the route stops working. |
| `ldak-kvik-column-surgery` | `modules/local/ldak/kvikstep2/main.nf:53-139` | LDAK's KVIK association table has no unambiguous effect-allele frequency and no per-variant N. The join supplies both. Without them GWASLab harmonisation of the KVIK route cannot run. The **native** `.assoc` is published untouched either way (`conf/modules/ldak.config:29`). |
| `ldak-kvik-step1-symlink-alias` | `modules/local/ldak/kvikstep2/main.nf:37-41` | `--kvik-step2` uses one prefix for both input discovery and output naming. |
| `ldak-63-ghcr-image` | `modules/local/ldak/{sumher,sumcors}/main.nf:5-7`, `sumher/Dockerfile:19,26` | The upstream LDAK 6.3 image has an intercepting entrypoint and no Bash, so a normal Nextflow task cannot launch it. Version selection, not command pinning. Issue #7. |
| `ldsc-cbiit-fork-pin` | `modules/local/ldsc/{h2,rg,mungesumstats}/main.nf:5-7` | Upstream LDSC is Python 2. This is which build to run, not how to run it. |
| `metasoft-launcher` | image at `modules/local/metasoft/re2/main.nf:5-7` | METASOFT's default P-value table is a bare relative path that fails with exit 255 in any Nextflow task directory. |
| `mrmega-absolute-binary-path` | `modules/local/mrmega/main.nf:26` | A trailing `/MR-MEGA` PATH entry is not reliably preserved by Apptainer, Podman or some Kubernetes executors. |
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
no trace of why `--factors` is missing.

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

### 2.6 `ldak-adjustgrm-root-basename` — recommend KEEP, but verify before deleting
`subworkflows/local/route_grm_heritability/main.nf:95-102,111-124`.

Adjusted GRM artifacts are deduplicated by content. LDAK records the covariate **filename** in the artifact's
`.grm.root` contract, so every consumer of a shared artifact is invoked with the one representative file
that built it rather than with its own copy.

**This is the weakest-evidenced finding in the document.** The claim rests entirely on one inline comment;
the introducing commit is subject-only and nobody has ever run the failing case. Whether a basename
disagreement is an error or a wrong answer is untested. If you want this gone, it deserves one live check
first.

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
| `kvik-summary-join-assertions` (header and missing-file checks) | `modules/local/ldak/kvikstep2/main.nf:56-59,71-74,93-96` | **Remove these three.** **Keep the two duplicate-key checks and the unmatched-key check** at `:78-81,109-113,114-117,127-137` — a duplicated key silently attaches the *last* match's EAF and N, giving a wrong-but-finite number that propagates into meta-analysis weights and is caught nowhere else. |

---

## Group 4 — Tests

The test suite is where most of the volume is, and where most of the cheap wins are. Roughly forty findings;
the pattern is stark. Almost every high-fragility item is an exact-content or MD5 snapshot of real tool
output with **no pipeline guard behind it at all** — it documents one tool version's arithmetic. Almost
every worth-keeping item pins a string this repository authored.

### 4.1 Remove — snapshots of tool arithmetic with nothing behind them

- `tests/relational_gcta_bivariate_he.nf.test` pins the whole native `.HEreg` text including
  `rG -3.79993 7.45616 -nan`. No rG-recomputation code exists anywhere.
- `tests/summary_statistics_ldsc.nf.test` pins ~10 floats per invocation including
  `Total Observed scale h2: -1.2938e-15 (1.1092e-15)` — numerical noise near zero, not scientific content.
- MD5 snapshots of real output in `modules/local/gcta/bivariatehereg`, `gcta/bivariateheregldms`,
  `tests/association_gcta_fastgwa.nf.test`, `tests/relational_gcta_fastgwa.nf.test`,
  `tests/heritability_gcta_greml_ldms.nf.test`, `tests/relational_gcta_greml_ldms.nf.test`,
  `tests/relational_gcta_greml.nf.test`. Keep the adjacent structural checks (`V(G)` single source row,
  `/Vp_L` presence or absence) — they catch real stratum-wiring regressions and cost nothing.
- Exact P-value strings in `modules/local/mrmega/tests` (`0.0010333`, `0.00103304`) and METASOFT's
  fixed-width `0.00000` underflow format. Keep the header and column-shape assertions.
- `modules/local/ldsc/mungesumstats/tests` pins a native rejection message — and already hedges between two
  possible strings, so the test anticipates its own staleness.
- `metasoft-re2-native-log-table-path` asserts an internal container path with no pipeline dependency.
- KVIK, HE and PCGC content snapshots stabilised only by a **test-only** `--random-seed 7`.
- `sumher`/`sumcors` tests pinning LDAK's exact error wording for input the tool correctly refuses — this
  documents correct behaviour, not misbehaviour. Loosen to a generic failure check.
- `sumher-sumcors-liability-arg-order` pins exact flag **order** with no evidence LDAK's parser is
  order-sensitive. Replace with unordered presence checks.
- `ldak-fast-he-pcgc-unseeded-reproducibility-warning` asserts a hardcoded factual claim about LDAK's log
  that is never re-verified against a live run.

**The clearest single instance of the retired practice** is `fasthe-partial-weights-warning`
(`modules/local/ldak/fasthe/tests` and `tests/heritability_ldak_fast_estimators.nf.test`). It pins an exact
LDAK log phrase, and its own comment says: *"The pipeline adds no coverage guard of its own... This pins that
behaviour end to end so a future shared guard has a red test to turn green."* It is bait for a guard that
will now never be built. Remove both instances.

### 4.2 Keep

- `missing-covariate-cell-refusal` (`tests/heritability_ldak_fast_estimators.nf.test`, four scenarios) —
  every pinned string is pipeline-authored, and no other test exercises that guard. The strongest keep in
  the audit.
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
- The `ldak.fast_seed` behavioural tests, `fasthe-default-weights-equal-alias-equivalence`,
  `hereg-ldms-native-total-contract`, the LDSC stdout-redirect tests, and `ldsc-firewall-reject-samp-prev`.
- `gcta-fastgwa-binary-beta-header-pin` — keep as an **isolated** canary. GCTA reports the log-odds effect
  as `BETA` on its binary MLM route, and effect-semantic drift is a real risk; isolate it so an unrelated
  GCTA point release does not also fail the surrounding snapshot-heavy test.

### 4.3 Two test defects found on the way

- **`gwaslab-harmonize-six-digit-float-format` does not actually exercise the defence.** Its fixture uses
  BETA=0.10 and SE=0.02, which do not underflow at four decimals. The most consequential guard in the
  pipeline has a test that would pass with the guard removed. Needs a small-magnitude fixture such as
  3.12e-05.
- **`hereg-command-line-no-covariate-flags` is vacuous.** It asserts the emitted command carries no
  covariate flags, but the request under test never attaches a covariate. If covariate forwarding were
  re-added to `GCTA_BIVARIATEHEREG`, **no test in the whole GCTA-bivariate slice would catch it.**

---

## Group 5 — Documentation

Prose describing tool misbehaviour, in `docs/usage.md`, `docs/output.md` and `CHANGELOG.md`. Three passages
are the written rationale for guards that are still enforced, and must move only if their guard moves:

1. The GCTA HE-CP covariate rejection — `docs/usage.md:122`, `docs/output.md:248`, `CHANGELOG.md:33`.
2. The LDAK missing-covariate-cell rejection — `docs/usage.md:364`, `CHANGELOG.md:43`.
3. The LDAK unseeded-fast-route warning — `docs/usage.md:172,335`, `docs/output.md:186`.

Recommend keeping, trimmed:

- The LDAK zero-weight note (`docs/usage.md:331`) — **nothing in code catches this**, so the prose is the
  only safety net.
- The predictor-jackknife-block caveat (`docs/usage.md:334`) — prevents a user comparing incomparable
  standard errors.
- `CHANGELOG.md:43` — a "Breaking" entry with no stated cause is worse documentation than one with a cause.
  This is the single place where removal looks actively harmful to the record.

Recommend trimming to one line: the "stochastic in standard errors only" note (`docs/usage.md:172`), and the
duplicate seed warning that appears in both `usage.md` and `output.md`.

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
is correct" has a documented counterexample, and it needs your explicit call rather than mine.

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
remove — but nothing protecting against either, either.

### 7.5 The LDAK HE/PCGC seed is test-only
`--random-seed 7` for `LDAK_HE` and `LDAK_PCGC` lives in `tests/nextflow.config` alone, with an explicit
comment that production remains unseeded. The production reproducibility feature is the separate
`ldak.fast_seed` option on different modules on a different route. Any reasoning that treated the HE/PCGC
seed as a production control was wrong.

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
- `modules/local/custom/gctamergegrmparts/main.nf:32` still reports a coreutils version via `sort --version`
  although `sort` is no longer invoked.
- `modules/local/plink2/vcf/main.nf:26-32` places `${args}` early while `makebed` and `makepgen` place it
  last. This repository has measured a real PLINK 2 positional quirk before. Worth confirming it was
  deliberate.
- `subworkflows/local/route_grm_heritability/main.nf:60` filters on an uncommented magic tuple arity and
  will silently drop every record if the tuple width changes.
- `resolve_references.nf:47-49` validates a declared reference checksum as 64 hex characters and **never
  hashes the file**. It has no consumer beyond display.
- `subworkflows/local/prepare_relatedness_matrices/meta.yml:10-13` documents an `nf-core subworkflows lint`
  bug and is the only explanation for a lowercase-function-name convention seven other files follow
  silently. Worth checking whether current `nf-core/tools` still has it.

---

## What this audit could not establish

It was read-only by design. Nothing was executed, so every claim about what a tool does comes from the
tree, from vendored upstream source, or from a previously recorded measurement — not from a fresh run.
Three items rest on inference rather than record and are marked as such above: the LDAK `.grm.root`
basename coupling (2.6), the LDSC gzip crash mechanism (Group 1), and the MR-MEGA ordinal filename motive.

Two scopes were not covered and would need the same treatment for a complete inventory: the
`subworkflows/local/common_variant_meta_analysis/` stack, and the GENIE and MPH routes — the first because
it is being deleted, the second because it has not landed.

---

## Structural observations worth keeping

**The tree already states the new policy.** `subworkflows/local/validate_gwas_input/method_options.nf:8-10`:
*"A `null` default always means 'pass nothing and let the native default stand', never 'zero' or 'off' …
which is what makes an unset option reproduce the tool's own documented behaviour rather than a pipeline
opinion."* Everything in this document is an exception to a rule the codebase already holds.

**The concentration is narrow.** Across all 32 GCTA and LDAK module files there is not one comment inside a
`script:` or `stub:` block, no flag pinned to a documented default, and no order claim. The retired pattern
lives in exactly three places: GWASLab formatting, LDSC's broken logger and gzip reader, and GENIE — which
was by far the densest case and is already leaving.
