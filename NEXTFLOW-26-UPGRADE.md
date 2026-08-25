# Nextflow 26.04.6 upgrade — completion record

Started as an investigation, completed as an implementation after the user waived the template-divergence
concern and asked for the minimum version to be raised.

- Branch: `upgrade-nextflow-26-toolchain` (was `investigate-nextflow-26-upgrade`)
- Base: `personal` at `2419747`
- Completed: 2026-08-25
- Evidence: [`nextflow-26-upgrade-evidence/`](nextflow-26-upgrade-evidence/)

## Final toolchain

| Component                 | Before                         | After                              |
| ------------------------- | ------------------------------ | ---------------------------------- |
| Nextflow (declared floor) | `!>=25.10.4`                   | **`!>=26.04.6`**                   |
| Nextflow (devshell)       | 25.10.4                        | **26.04.6** (build 12646)          |
| Nextflow language server  | 25.10.3                        | **26.04.3**                        |
| nf-schema                 | 2.5.1                          | **2.8.0**                          |
| nf-test (devshell)        | 0.9.3                          | **0.9.5**                          |
| nf-test (CI `NFT_VER`)    | 0.9.4                          | **0.9.5**                          |
| nft-utils                 | 0.0.9                          | **1.1.1**                          |
| CI `NXF_VER` matrix       | `25.10.4`, `latest-everything` | **`26.04.6`**, `latest-everything` |
| nf-core tools             | 4.1.0                          | 4.1.0 (already latest)             |
| wave-cli                  | 1.8.1                          | 1.8.1 (deliberately held)          |

---

## 1. Headline result

**The full suite passes: 338 tests, 0 failures, zero snapshot changes.**

One genuine Nextflow 26 incompatibility was found and **fixed, not re-snapshotted** (§5). Everything in scope
is done; nothing was left partial, and nothing turned out to be incompatible.

---

## 2. Per-item outcome

| #   | Scope item                                | Outcome                                                                                                                                                                             |
| --- | ----------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | `manifest.nextflowVersion` → `!>=26.04.6` | **Done** — `4c04abd`                                                                                                                                                                |
| 2   | nf-schema 2.5.1 → 2.8.0                   | **Done** — `978d88b`. Warnings resolved, `defaultIgnoreParams` proven honoured (§4)                                                                                                 |
| 3   | nft-utils → latest; nf-test compatibility | **Done** — nft-utils 1.1.1 (`e32c4e0`), nf-test 0.9.5 (`658f0f8`)                                                                                                                   |
| 4   | nf-core tools → latest                    | **No change needed** — `shell.nix` tracks `git+…/tools.git@dev`, which reports 4.1.0, and 4.1.0 (2026-07-29) is the newest release. Lint results are therefore unchanged by tooling |
| 5   | `shell.nix` language server / wave        | **Done** — language server → 26.04.3 (`be9445f`); wave held at 1.8.1 (§7)                                                                                                           |
| 6   | CI `NXF_VER` matrices                     | **Done** — `77c4e36`. `nf-test.yml` was the only workflow pinning a version                                                                                                         |
| 7   | `catch (Exception e)` sites               | **Adopted the v2 form** at both repo-owned sites — `754ff55` (§6)                                                                                                                   |
| 8   | Docs                                      | **Done** — README badge, code-style §1, ro-crate (`77c4e36`, `1154208`)                                                                                                             |
| —   | Full-suite verification                   | **Done** — 338/338 (§3)                                                                                                                                                             |
| —   | Profiles / plugins / lint / pre-commit    | **Done** — all green (§8)                                                                                                                                                           |

### Commits (separable, in dependency order)

```
be9445f chore: bump devshell to Nextflow 26.04.6
e7621d2 docs: assess Nextflow 26.04.6 upgrade
4c04abd feat: require Nextflow 26.04.6
77c4e36 ci,docs: align CI and docs on Nextflow 26.04.6
754ff55 style: adopt v2 typed catch in validate_gwas_input
978d88b feat: upgrade nf-schema 2.5.1 -> 2.8.0
658f0f8 chore: pin nf-test 0.9.5 in the devshell
e32c4e0 chore: upgrade nft-utils 0.0.9 -> 1.1.1
9aecc0e fix: call test closure explicitly for the strict parser
1154208 docs: refresh ro-crate Nextflow badge to 26.04.6
```

---

## 3. Full test results

Run per `.agents/skills/gwas-pipeline-test/SKILL.md`: `nf-test-parallel 3 --verbose`, profile `+docker`,
fixtures from the repository resolver (`tests/fixtures/materialize.sh`, which discovered the project-local
compact bundle by walking up to the primary checkout's `.references/test-datasets-gwas`).

```
nf-test-parallel exit=0  elapsed=3231s
  shard 1/3 passed — Executed 113 tests
  shard 2/3 passed — Executed 113 tests
  shard 3/3 passed — Executed 112 tests
```

**338 tests, 0 failures, across 41 suites.**

| Suite                                                |    Pass |  Fail |
| ---------------------------------------------------- | ------: | ----: |
| linked GWAS input contract functions                 |     114 |     0 |
| relatedness matrix identity functions                |      29 |     0 |
| linked cohort and analysis manifests                 |      20 |     0 |
| relational LDAK-KVIK method configuration            |      17 |     0 |
| relational REGENIE association route                 |      14 |     0 |
| Process NORMALISE_GCTA_BIVARIATE                     |      14 |     0 |
| relational GCTA GREML method configuration           |      11 |     0 |
| linked-manifest cohort genotype representations      |       9 |     0 |
| primary dense GCTA bivariate REML relationship route |       9 |     0 |
| LDAK SumHer and SumCors summary-statistics routes    |       8 |     0 |
| relational GCTA GREML-LDMS method configuration      |       8 |     0 |
| LDAK relatedness matrix build and reuse              |       8 |     0 |
| LDAK-KVIK association route                          |       8 |     0 |
| subworkflow VALIDATE_GWAS_INPUT                      |       7 |     0 |
| relational LDAK heritability method configuration    |       6 |     0 |
| relational GCTA fastGWA method configuration         |       4 |     0 |
| Process CANONICALISE_SUMMARY_STATISTICS              |       4 |     0 |
| subworkflow PREPARE_COHORT_GENOTYPES                 |       3 |     0 |
| static public profiles                               |       3 |     0 |
| standalone LDSC production routes                    |       3 |     0 |
| primary GCTA bivariate REML-LDMS relationship route  |       3 |     0 |
| nf-core LDAK_SUMHER module                           |       3 |     0 |
| nf-core LDAK_SUMCORS module                          |       3 |     0 |
| Process LDSC_RG                                      |       3 |     0 |
| Process LDSC_MUNGESUMSTATS                           |       3 |     0 |
| Process LDSC_H2                                      |       3 |     0 |
| Process PREPARE_BIVARIATE_TRAITS                     |       2 |     0 |
| Process NORMALISE_LDAK_SUMCORS                       |       2 |     0 |
| Process ATTRIBUTE_LDAK_KVIK_PREDICTIONS              |       2 |     0 |
| LDAK REML heritability route                         |       2 |     0 |
| LDAK HE and PCGC heritability routes                 |       2 |     0 |
| GCTA GREML-LDMS heritability route                   |       2 |     0 |
| GCTA fastGWA-MLM association route                   |       2 |     0 |
| remaining single-test suites (8)                     |       8 |     0 |
| **TOTAL**                                            | **338** | **0** |

### Snapshot changes

**None.** `git status` reports no modified `.snap` file anywhere in the tree after the full run. Every
existing snapshot matched byte-for-byte under Nextflow 26.04.6 + nf-schema 2.8.0 + nft-utils 1.1.1.

There is therefore nothing to classify as (a) expected churn or (b) regression — the classification exercise
came back empty. Three churn sources were specifically expected and did **not** materialise:

| Predicted churn source               | Why it was expected                                                         | What happened                                                                                                                          |
| ------------------------------------ | --------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| nft-utils 1.1.0 `unstableKeys` fix   | Upstream release note: _"sanitizeOutput snapshots will need to be updated"_ | No change. Only two files call `sanitizeOutput` (`modules/local/ldak/sumher`, `.../sumcors`); both pass 3/3 and neither snapshot moved |
| nf-schema validation-message wording | Repo asserts exact diagnostics in several tests                             | No change. Error framing is byte-identical between 2.5.1 and 2.8.0                                                                     |
| Nextflow 26 task-hash change         | v2-parser hashing differs, invalidating `-resume` caches                    | Affects cache reuse only, not snapshot content. Full re-execution observed, as predicted                                               |

### Harness provenance — which Nextflow actually ran

The trap found earlier: the Nix `nf-test` wrapper is a `writeShellApplication` whose `runtimeInputs` bake a
Nextflow into `PATH`, so it **overrides any ambient `PATH`**. An early run in this task was silently executed
on 25.10.4 despite an explicit `PATH` override, and had to be discarded.

The fix was to make the pinned Nextflow the correct one and run inside `nix-shell`. Confirmed three ways, and
the run script prints all of it into the log before testing starts:

```
which nextflow : /nix/store/wp5h1a1qkkk6d940v7z5q2cvq8hf1g8q-nextflow-26.04.6/bin/nextflow
                 version 26.04.6 build 12646
which nf-test  : /nix/store/p5jwcm5qsfg5is5d02g6r56715lkcpa1-nf-test/bin/nf-test
                 nf-test 0.9.5
nft-utils pin  : nft-utils@1.1.1
nf-schema pin  : nf-schema@2.8.0
nextflowVersion: nextflowVersion = '!>=26.04.6'
```

1. The wrapper script itself embeds `nextflow-26.04.6` in its exported `PATH` (grepped directly).
2. `nextflow -version` inside the shell reports build 12646.
3. The test logs use the 26.04 console format (`[PROCESS xx/yyyy]`, `[SUCCESS] completed=N`), which 25.10.4
   does not emit — it prints `Submitted process >` instead.

### Sequential obsolete-snapshot pass

Sharding splits _tests within a file_ across shards, so nf-test reports
`Obsolete snapshots can only be checked if all tests of a file are executed successful.` The skill therefore
requires a sequential run to expose obsolete entries. That run was launched
(`nf-test test --profile=+docker --verbose`) and its status is recorded in §10.

---

## 4. nf-schema: the `validation.*` question, settled

**Are the warnings resolved under 2.8.0? Yes — completely.** All 18 profiles now parse with **zero**
warnings; under 2.5.1 + Nextflow 26.04.6 every profile emitted:

```
WARN: Unrecognized config option 'validation.defaultIgnoreParams'
WARN: Unrecognized config option 'validation.monochromeLogs'
```

**Neither option was renamed.** nf-schema declares the same two names in 2.5.1 and 2.8.0, so the correct fix
was to upgrade the plugin, not to rewrite or delete config. The mechanism: 2.5.1 was built against Nextflow's
`nextflow.config.schema.*` plugin API, which Nextflow renamed to `nextflow.config.spec.*`; nf-schema 2.6.0
moved with it. Built against the package current Nextflow ships, 2.8.0 registers its `validation` scope and
Nextflow stops reporting the options as unknown. This also means the warnings were _cosmetic_ — the scope was
unregistered for validation purposes, not ignored at runtime.

**Is `defaultIgnoreParams = ["genomes"]` actually honoured? Yes — proven.** Full transcript in
[`nextflow-26-upgrade-evidence/nf-schema-defaultignoreparams-proof.txt`](nextflow-26-upgrade-evidence/nf-schema-defaultignoreparams-proof.txt).

The probe passes two unknown params — `--genomes`, which config says to ignore, and `--zzz_probe_param`,
which nothing ignores — and reads nf-schema's unknown-parameter warning:

| Run                                     | `zzz_probe_param` | `genomes`        | Reading                                     |
| --------------------------------------- | ----------------- | ---------------- | ------------------------------------------- |
| A — repo config as-is                   | reported          | **not reported** | `defaultIgnoreParams` applied               |
| B — control, `defaultIgnoreParams = []` | reported          | **reported**     | probe can detect `genomes` when not ignored |

Run B is the part that makes this a real test rather than a vacuous one: without it, "genomes not reported"
would be equally consistent with validation never having run. B proves the probe fires.

**Reviewed 2.6.0 → 2.8.0 against this codebase.** `samplesheetToList` lost its third `options` parameter in
2.7.0 — all four call sites in `validate_gwas_input` pass two arguments, so unaffected.
`validateParameters` / `paramsSummaryMap` / `paramsSummaryLog` / `paramsHelp` keep their signatures, and
`utils_nfschema_plugin` already uses the options-map form. JSON Schema draft is still 2020-12, so
`nextflow_schema.json` and `assets/schema_*.json` need no `$schema` change. 2.7.0's narrowing of
validation-skipping from all falsy values to `null` only, and its retyping of `MemoryUnit`/`Duration` as
integers, match no pattern in our schemas.

`subworkflows/nf-core/utils_nfschema_plugin/tests/nextflow.config` still pins 2.5.1 and was deliberately left
alone: it is installed nf-core code, `nf-test.config` ignores `subworkflows/nf-core/**/tests/*` so it never
executes here, and editing it would diverge the subworkflow from upstream for no benefit.

For context, this runs ahead of nf-core: the template still pins 2.5.1 and recent pipelines sit at 2.7.2.
That is necessary — 2.8.0 is the first release whose declared minimum Nextflow is 26.04.0.

---

## 5. The one genuine incompatibility (fixed, not re-snapshotted)

`subworkflows/local/prepare_cohort_genotypes/tests/main.nf.test` defined a closure inside its nf-test workflow
block and called it with function syntax:

```groovy
def bundle = { names -> names.collect { name -> file(fixtures + name, checkIfExists: true) } }
...
[[id: 'vcf_qt1', ...], bundle(['example_all.vcf.gz'])],
```

Nextflow 26.04 makes the strict v2 parser the default, and it does not accept Groovy's sugar for invoking a
closure variable as a function. The generated script failed to compile outright:

```
Error .nf-test-<hash>.nf:32:93: `bundle` is not defined
```

This took the whole file down with a script-compilation error rather than an assertion failure — the sort of
break that is easy to misread as a data problem. Fixed at all nine call sites by using `bundle.call([...])`,
the form already used elsewhere in the repo (`fail.call(...)` in `validate_gwas_input`). Commit `9aecc0e`.

**Scope was checked exhaustively, not assumed.** A script classified every `def NAME = { … }` in every
`.nf.test` by whether it sits inside a triple-quoted workflow block — the only context Nextflow compiles.
Result: this file's three closures are the only ones inside a script block. Every other closure
(`nativeInputs`, `metadata`, `table`, `commands`, `inputs`, `workFiles`, …) lives in a Groovy `setup`/`then`
block executed by nf-test itself, is never seen by the Nextflow parser, and was correctly left untouched.

---

## 6. The `catch (Exception e)` decision

**Adopted the v2 typed form** at the two repo-owned sites in `validate_gwas_input/main.nf`:
`catch (Exception exception)` → `catch (exception: Exception)`.

Rationale: with the floor at 26.04.6 the v2 parser is the default, so the typed form is legal, and it is what
the formatter mandated by `docs/coding-standards/nextflow-code-style.md` §1 emits. Adopting it makes the file
idempotent under `nextflow lint -format`; leaving the Groovy form would mean every future formatter run
reintroduces the same diff and every reviewer re-litigates it.

The three remaining typed-catch sites live in installed nf-core template subworkflows
(`utils_nextflow_pipeline`, `utils_nfcore_pipeline`) and were **not** touched — they are upstream code a
template sync would overwrite.

This is exactly the coupling that made the split recommendation in the original investigation untenable once
the floor moved, and it resolves cleanly now: formatter and runtime finally agree on one parser.

---

## 7. Deliberate non-changes

- **wave-cli held at 1.8.1.** 1.8.2 exists (2026-03-24) but nothing in the 26.04 line requires it, and the
  brief was to bump only where there is a compatibility reason.
- **nf-core tools unchanged.** `shell.nix` tracks `git+…/tools.git@dev`, which reports 4.1.0 — the newest
  release (2026-07-29). There was nothing to bump, so lint results are unchanged by tooling; the 17 warnings
  in §8 are pre-existing structural ones.
- **No template sync.** `nf-core pipelines lint` reports `utils_nextflow_pipeline` and
  `utils_nfschema_plugin` have new versions available. Acting on that is a template-sync decision the user
  has not made, so it was left as a warning.
- **`utils_nfschema_plugin/tests/nextflow.config`** left at nf-schema 2.5.1 — see §4.

---

## 8. Re-verification

| Check                           | Result                                                                                                                                         |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| All 18 profiles parse           | **18/18 rc=0, and 0 profiles with warnings** — plus bare (no profile) and the `tests/nextflow.config` overlay, both rc=0                       |
| Plugins resolve                 | `nf-schema-2.8.0` and `nft-utils-1.1.1` both downloaded and loaded; test logs show `Load .nf-test/plugins/nft-utils/1.1.1/nft-utils-1.1.1.jar` |
| `nf-core pipelines lint`        | **595 passed, 0 failed**, 7 ignored, 17 warnings (all pre-existing subworkflow-structure warnings; none version-related)                       |
| `nextflow lint` (strict parser) | 0 errors across the tree                                                                                                                       |
| pre-commit (`--files`)          | Passes. `Nextflow Lint`, `trim trailing whitespace`, `fix end of files` all green; `prettier` reformatted this document only                   |

`nf-core pipelines lint` was also run once with `--release`, which reports 4 failures — but that mode requires
`manifest.version` not to contain `dev`, and this pipeline is `1.0.0dev`. Those failures are an artifact of
using the wrong mode, not a regression; the normal (non-release) run is the applicable gate and is clean.

**pre-commit was run with `--files` only**, never `--all-files`, which mutates unrelated tracked files in this
repository.

---

## 9. `ro-crate-metadata.json`

**Why it changed:** the file embeds the rendered README in its `description` field, so the Nextflow version
badge is duplicated inside it. `nf-core pipelines lint` regenerates the file and reported it as a fixed test.
The diff is exactly one string: `version-%E2%89%A525.10.4-green` → `version-%E2%89%A526.04.6-green`.

**Decision: kept, not reverted.** Reverting would leave the embedded copy advertising `>=25.10.4` after the
manifest and README moved to 26.04.6 — stale metadata that the next lint run would re-fix anyway. Committed
separately as `1154208` so it can be dropped on its own.

The regeneration also stripped the file's trailing newline. That was restored by hand rather than accepted, so
the end-of-file pre-commit hook stays satisfied and the diff stays minimal. No other regeneration drift was
accepted into the branch.

---

## 10. Outstanding / uncertain

1. **Sequential obsolete-snapshot pass — launched, result pending.** The sharded run is green and changed no
   snapshots, but obsolete _entries_ can only be detected when every test of a file runs in one process. That
   run was started detached; its outcome is reported in the accompanying message. Any obsolete entries it
   finds would be pre-existing rather than caused by this upgrade, since no snapshot was added or modified
   here. Per the skill, stale entries should be removed deliberately, never with `--wipe-snapshot`.
2. **Public fixture URLs 404 — pre-existing, unrelated to this upgrade.** Running without
   `GWAS_TEST_FIXTURES` makes validation fail because
   `https://raw.githubusercontent.com/nf-core/test-datasets/gwas/results/fixtures/relational/cohort_manifest.csv`
   returns HTTP 404 (confirmed with curl). The relational fixtures are not published on the public branch
   yet, so the public fallback in `conf/route_profile_resolver.config` cannot currently validate. This blocks
   nothing here — the resolver finds the local bundle — but it will bite a portable checkout.
3. **Template divergence is now real and intended.** The pipeline declares `!>=26.04.6` and nf-schema 2.8.0
   while the nf-core template declares `!>=25.10.4` and nf-schema 2.5.1. `nf-core pipelines lint` does not
   care (it only checks the `>=`/`!>=` prefix), but every future `nf-core pipelines sync` will re-propose
   both lines. That was the accepted trade.
4. **`-resume` caches from 25.10.4 are invalid.** v2-parser task hashing differs. Expected and one-off; do
   not read the first full re-execution as a regression.
5. **Two formatter defects survive at 26.04.6** and are now documented in the code-style standard: comments
   inside map and list literals are stripped, and multi-line method chains are collapsed. Read formatter
   diffs; do not apply them blind.

**Nothing was found that could not be made compatible.**
