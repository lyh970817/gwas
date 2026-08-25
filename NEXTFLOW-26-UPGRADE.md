# Nextflow 26.04.6 upgrade assessment

Investigation only. Nothing in this document has been applied to `nextflow.config`, the CI workflows, or any
pipeline logic. The one change committed alongside it is `shell.nix` (personal-track devshell), recorded in
[Nix devshell](#nix-devshell).

- Branch: `investigate-nextflow-26-upgrade`
- Base: `personal` at `2419747`
- Investigated: 2026-08-25
- Installed runtime: 25.10.4 build 11173 (Nix store)
- Candidate runtime: 26.04.6 build 12646 (standalone dist, downloaded to scratch, invoked by path)
- Evidence logs: [`nextflow-26-upgrade-evidence/`](nextflow-26-upgrade-evidence/)

---

## 1. Recommendation

**Adopt 26.04.6 now as the development and CI toolchain. Do not raise the declared
`manifest.nextflowVersion` floor yet — leave it at `!>=25.10.4`.**

This splits the question in two, because the evidence splits in two.

The *runtime* case for 26.04.6 is settled and one-sided. Every one of the 18 declared profiles parses, the
strict v2 parser (now the default) produces zero errors across all 151 linted files, `nf-schema@2.5.1` and
`nft-utils@0.0.9` resolve, and 17 of 17 pipeline tests pass under Docker with every snapshot intact. Nothing
broke. On top of that, 26.04.6 fixes a defect that currently makes this repository's own mandated code
formatter unusable (§6) — a concrete, present-day benefit that 25.10.4 cannot deliver. There is also no
release-line reason to wait: Nextflow has no formal LTS policy at all (§1 evidence), so "hold for the 25.10
LTS" rests on a premise that does not exist.

The *declared floor* case runs the other way, and it is not close. `manifest.nextflowVersion` is a
user-facing compatibility contract, and the `!>=` prefix makes it a hard failure rather than a warning. The
nf-core 4.1.0 template — and `dev` — declare `!>=25.10.4`, as do rnaseq, sarek, and fetchngs; methylseq is
still on `25.04.0`. The only two pipelines past 25.x (mag, ampliseq) got there incidentally, and ampliseq's
own string was silently downgraded from `26.04.6` to `26.04.0` inside an unrelated parameter-typing PR. Most
importantly: **the pipeline demonstrably runs on 25.10.4**, so raising the floor would impose a hard
constraint on downstream users to buy nothing functional, while creating a line-level divergence that every
future `nf-core pipelines sync` re-proposes — a needless liability for the upstream PR track. `nf-core
pipelines lint` would not reward the bump either; it only checks that the string starts with `>=` or `!>=`
(§2 evidence), so both values lint identically.

So: take the toolchain benefit, decline the contract change. Revisit the floor when the nf-core template
moves, which most plausibly happens around 26.10 (~October 2026, by cadence). The one thing this split
requires is a narrow discipline described in §6 and Risk R1: the 26.04.6 formatter rewrites
`catch (Exception e)` into v2-only `catch (e: Exception)`, so that specific rewrite must not be committed
while the floor still says 25.10.4. Only two repo-owned sites are affected.

**Rejected alternatives.** *26.04.6 including the floor* — buys nothing the toolchain move does not, and
pays template divergence plus a hard user constraint. *25.10.7 now, 26.10 later* — 25.10.7 is a routine patch
that leaves the formatter broken; there is no LTS to align to, so the move has no payoff. *Stay put entirely*
— leaves the mandated formatter unusable, which is the one thing actually costing work today.

---

## 2. Evidence table

| # | Question | What was run | What was observed |
|---|---|---|---|
| 1 | Release-line strategy | Primary-source review of Nextflow docs, blog, and the GitHub releases API | **The LTS premise is false.** No Nextflow/Seqera source brands any release "LTS" or gives October releases a distinct support window. Docs say only: *"A stable version of Nextflow is released in the 4th and 10th month of each year."* Both lines are ordinary stable lines and both are actively patched — 25.10.7 (2026‑07‑15) and 26.04.6 (2026‑07‑09) confirmed. No published EOL for either. 26.10 is inferred ~Oct 2026 from cadence only; **no announced date**. No official guidance preferring one stable line over another. |
| 2 | nf-core template alignment | uv-cache template inspection; `gh api` against nf-core/tools `dev` and tag `4.1.0`; six peer pipelines; local template-merge branches; read of `nextflow_config.py` lint rule | Template declares **`!>=25.10.4`** on both `dev` and `4.1.0`; no CHANGELOG entry moving toward 26.x. Peers: rnaseq / sarek / fetchngs `!>=25.10.4`, methylseq `!>=25.04.0`, mag and ampliseq `!>=26.04.0` (ad hoc, feature-driven, mutually inconsistent). Local `nf-core-template-merge-4.0.2` / `-4.0.3` are already merged into `personal` and **neither touched `nextflowVersion`**. **Lint does not care about the number** — `nextflow_config.py` only asserts the value starts with `>=` / `!>=`, so `!>=26.04.6` and `!>=25.10.4` lint identically. Its docstring does note the value *"should correspond to the `NXF_VER` version tested by GitHub Actions."* |
| 3 | Strict config parser | `nextflow config -profile <p>` for all 18 profiles + bare + `-c tests/nextflow.config`, under **both** runtimes; full diff of resolved output | **All 18 profiles parse under both, rc=0, zero parse errors.** History explains why: branch `sync-template-403` (commit `8706284`, 2026‑08‑06) already rewrote `conf/route_profile_resolver.config`, wrapping bare top-level `def` statements into a single `params.route_profile_resolution = { ... }()` closure, explicitly *"the default from 26.04 onward, `NXF_SYNTAX_PARSER=v2`"*. Diffs under 26.04.6 show: **two new warnings** — `Unrecognized config option 'validation.defaultIgnoreParams'` and `'validation.monochromeLogs'` (nf-schema 2.5.1 scope, also emitted during real runs); `publishDir` rendered as a block instead of an inline map (cosmetic output-format change); container-scope ordering reshuffled (cosmetic). No semantic difference found. |
| 4 | DSL / runtime deprecations | 26.04 migration guide, `strict-syntax.mdx`, `feature-flags.mdx`, release notes v26.04.0–.6, cross-checked against actual repo code | Breaking changes that **this codebase touches**: strict v2 parser now default (repo already clean, §3); CLI params no longer auto-coerced to bool/number (repo uses `nextflow_schema.json` typing, no reliance observed); `manifest.defaultBranch` **deprecated** — repo declares `defaultBranch = 'master'` (warning only). Changes it does **not** touch: `topic:` channels unchanged (stable since 25.04); `publishDir`/`saveAs` not deprecated; output DSL unchanged; `ext.*` unchanged (two 26.x fixes actually *improve* `ext` hashing under the strict parser); DSL1 operators long gone; Java floor still 17. **Cache impact:** "Fix different task hash with v2 parser" and 26.04.2's "include params refs in task hash" mean **`-resume` caches from 25.10.4 will not be reused**. Plugin registry became mandatory in **25.10**, not 26.04 — no new plugin break. |
| 5 | Does it run? | `tests/fixtures/nf-test.sh` under Docker, nf-test 0.9.3 driven against 26.04.6 | **17/17 passed, 0 failures, all snapshots matched.** `tests/default.nf.test` 1/1 (33.7s); `tests/association_regenie.nf.test` + `tests/heritability_ldak_reml.nf.test` 16/16 (544s). 25.10.4 baseline for the same scopes also green. The only pre-existing warning (`invalid input values ... modules_testdata_base_path`) appears **identically under both** runtimes — not a 26.x regression. **Methodology note:** the Nix `nf-test` wrapper hard-prepends `nextflow-25.10.4` to `PATH`, so a naive `PATH` override silently keeps testing 25.10.4. The first run was invalidated by exactly this and re-run through a shim invoking the nf-test jar directly. Anyone repeating this must verify the version actually used. |
| 6 | The formatter bug | Mandated command from `nextflow-code-style.md` §1 on copies of `validate_gwas_input/main.nf` plus a synthetic probe, under both runtimes | **26.04.6 fixes the blocking half.** Detail in §3 below. |
| 7 | nf-test and plugins | Real suite run; plugin cache inspection | nf-test **0.9.3 works against 26.04.6**; `nft-utils@0.0.9` loads (`Load .nf-test/plugins/nft-utils/0.0.9/nft-utils-0.0.9.jar`). Declared plugin `nf-schema@2.5.1` resolves and downloads under 26.04.6 (`nf-schema-2.5.1`, `nf-tower-1.28.2`, `nf-wave-1.21.0` present in the 26.x plugin dir). Caveat: nf-schema 2.5.1 is old (2.8.0 released 2026‑08‑10) and is the source of the two new `validation.*` warnings. |

### 3. The formatter bug in detail

The command mandated by `docs/coding-standards/nextflow-code-style.md` §1:

```bash
nextflow lint -format -sort-declarations -spaces 4 -harshil-alignment
```

Run against a copy of `subworkflows/local/validate_gwas_input/main.nf` (1918 lines):

| Formatter behaviour | 25.10.4 | 26.04.6 |
|---|---|---|
| De-parenthesises computed map keys — `[(row[0].id): x]` → `[row[0].id: x]` at 3 sites (776, 788, 1125) | **Yes — output does not parse.** Re-linting the formatted file gives `Error main.nf:776:64: Unexpected input: ':'` | **Fixed.** Parentheses preserved; re-lint returns 0 errors |
| Rewrites `catch (Exception exception)` → `catch (exception: Exception)` | Yes | Yes |
| Strips comments inside map and list literals | Yes | **Yes — still broken** |
| Collapses multi-line method chains onto one long line | Yes | Yes (readability regression, not a correctness bug) |

The `catch` rewrite is the subtle one. It is not itself a bug — it is the intentional Groovy-to-Nextflow typed
syntax conversion — but it emits syntax that only the v2 parser accepts. Verified on a synthetic probe:

- 25.10.4 runtime, **default** parser, running 26-formatted code:
  `ERROR ~ Script compilation error ... Unexpected input: 'exception:' @ line 24, column 21`
- 25.10.4 runtime with `NXF_SYNTAX_PARSER=v2`: runs fine
- 26.04.6 runtime (v2 by default): runs fine

So on 25.10.4 the mandated command is broken through **two independent mechanisms** — the map-key corruption
(a genuine defect) and the typed-`catch` output (valid, but not parseable by the default 25.10.4 runtime).
26.04.6 removes the first and makes the second harmless, because formatter and runtime finally agree on one
parser. That is the single strongest repo-specific argument for the toolchain move.

Repo-wide exposure to the `catch` rewrite is small: **5 sites**, of which 3 live in nf-core template
subworkflows (`utils_nextflow_pipeline`, `utils_nfcore_pipeline`) that should not be hand-edited, leaving
**2 repo-owned sites** in `validate_gwas_input/main.nf`.

Residual known defects on 26.04.6: comment stripping inside collection literals, and method-chain collapse.
Both are reasons to keep reviewing formatter diffs rather than applying them blind.

---

## 3. Migration plan

Phase A is the recommendation. Phase B is deferred and written down so it is ready when the template moves.

### Phase A — toolchain move (do now, after the route-controller refactor lands)

1. **Do not start until `.worktrees/route-controllers` is merged.** That refactor's acceptance baseline was
   characterised under 25.10.4; changing the toolchain underneath it makes snapshot churn indistinguishable
   from refactor regressions.
2. **`shell.nix`** — already staged on this branch (commit `be9445f`). Land it first and alone, so it can be
   reverted independently.
3. **`.github/workflows/nf-test.yml`** (lines 80–82) — add 26.04.6 to the matrix as a **second blocking leg**,
   keeping 25.10.4 blocking too, since the declared floor still promises 25.10.4 works:
   ```yaml
   NXF_VER:
     - "25.10.4"
     - "26.04.6"
     - "latest-everything"
   ```
   `.github/actions/nf-test/action.yml` (line 29) consumes `NXF_VERSION` and needs no edit. Note the
   `latest-everything` leg already exercises 26.x today, but is `continue-on-error`, so it proves nothing.
4. **Re-snapshot: nothing.** All 17 tests passed under 26.04.6 with existing snapshots unchanged. Do not run
   `--wipe-snapshot`. After the matrix change, run the full suite sequentially once
   (`nf-test test --profile=+docker --verbose`) to surface obsolete entries, per `gwas-pipeline-test`.
5. **Warm caches, expect no `-resume` reuse.** v2-parser task hashing differs from v1; the first 26.04.6 run
   of any workflow recomputes from scratch. This is expected, not a regression.
6. **Record the formatter discipline** in `docs/coding-standards/nextflow-code-style.md` §1: until the floor
   moves, revert the `catch (name: Type)` rewrite in the 2 repo-owned sites before committing formatter
   output. Note the still-unfixed comment-stripping defect in the same place.

**Explicitly not changed in Phase A:** `nextflow.config`'s `manifest.nextflowVersion`, the README badge, and
`docs/coding-standards/configuration-and-schema.md`.

### Phase B — declared floor (deferred; trigger = nf-core template moves past 25.10.4)

1. `nextflow.config` line 284 — `nextflowVersion = '!>=26.04.6'` (or whatever the template then declares).
2. `README.md` line 13 — the version badge, currently `version-%E2%89%A525.10.4-green`.
3. `.github/workflows/nf-test.yml` — drop the 25.10.4 leg once it is no longer promised.
4. `docs/coding-standards/configuration-and-schema.md` line 52 — check the wording still matches.
5. Drop the §6 formatter discipline; the typed-`catch` rewrite becomes safe to commit.
6. Re-run the full suite and `nf-core pipelines lint`.

Files carrying a Nextflow version, complete list: `nextflow.config:284`, `README.md:13`,
`.github/workflows/nf-test.yml:80-82`, `shell.nix:3-4`,
`docs/coding-standards/configuration-and-schema.md:52` (prose, no number).

---

## 4. Risk register

| ID | Risk | Severity | Evidence | Mitigation |
|---|---|---|---|---|
| R1 | 26.04.6 formatter emits typed `catch`, which the default 25.10.4 runtime cannot compile — silently breaking the `!>=25.10.4` contract the repo still declares | **High** | Reproduced: `Unexpected input: 'exception:'` on 25.10.4 default parser | Only 2 repo-owned sites. Revert that specific rewrite until Phase B; document in §1 of the code-style standard. Consider a CI grep for `catch (\w+: ` while the floor is 25.10.4 |
| R2 | `-resume` caches from 25.10.4 are invalidated by v2-parser task hashing | Medium | 26.01.0-edge "Fix different task hash with v2 parser"; 26.04.2 "include params refs in task hash" | Expected and one-off. Warn developers; do not interpret full re-execution as a regression |
| R3 | `Unrecognized config option 'validation.defaultIgnoreParams' / 'validation.monochromeLogs'` under 26.04.6 | Medium | Reproduced in `nextflow config` **and** in real runs | nf-schema 2.5.1 is old (2.8.0 available). Unclear whether the options are merely unrecognised-but-honoured or silently ignored — `defaultIgnoreParams = ["genomes"]` should be verified explicitly. Bumping nf-schema is a **separate** change, template-coupled, and must not be bundled with the toolchain move |
| R4 | Declaring `!>=26.04.6` diverges from the nf-core template and every future sync re-proposes the line | Medium | Template `dev` and `4.1.0` both `!>=25.10.4`; local template-merge branches never touched the line | Avoided entirely by the recommendation — Phase B is gated on the template moving first |
| R5 | Toolchain swap collides with the in-flight route-controller refactor | Medium | Refactor at wave 4/7, baseline characterised under 25.10.4 | Sequencing rule in Phase A step 1. This branch is a staging area only |
| R6 | `manifest.defaultBranch = 'master'` is deprecated in 26.04 | Low | 26.04 migration guide | Warning only. Address during a future template sync, not here |
| R7 | New lint warning "Emit name should be omitted when there is only one emit" (4 sites) | Low | 26.04.6 lint; 3 sites in nf-core template subworkflows, 1 in `main.nf:106` | Cosmetic. Do not hand-edit the template subworkflows |
| R8 | Formatter still strips comments inside map/list literals, and collapses method chains | Low | Reproduced on **both** runtimes | Not a regression — pre-existing. Review formatter diffs; never apply blind |
| R9 | Nix `nf-test` wrapper pins its own Nextflow via `runtimeInputs`, so `PATH` overrides are silently ignored | Low | Cost one invalidated test run during this investigation | `shell.nix` now pins 26.04.6, so the wrapper and the intent agree. Always confirm the version in test output |

---

## 5. Blocking issues

**None.** No defect was found that makes the 26.04.6 toolchain move inadvisable. Every profile parses, the
strict parser reports zero errors, all declared plugins resolve, and the tested suite is fully green with
snapshots unchanged.

Two items are gates on *sequencing and scope* rather than blockers on the upgrade itself:

1. **The route-controller refactor must land first** (R5). This is a scheduling constraint, not a technical
   defect.
2. **Raising the declared floor is blocked on nf-core** (R4) — deliberately, by the recommendation. The
   trigger is the template moving past `!>=25.10.4`, not a date.

One item needs a follow-up answer but does not block: whether nf-schema 2.5.1's `validation.*` options are
still honoured under 26.04.6 or silently dropped (R3).

---

## Nix devshell

Committed separately as `be9445f`, ahead of the investigation evidence, so it can be landed or reverted on its
own. Not merged to the primary checkout — this branch is the staging area, and the route-controller refactor
must land first.

| Pin | Old | New | Hash |
|---|---|---|---|
| `nextflowVersion` | `25.10.4` | **`26.04.6`** | `sha256` base32 `10c2jqc17rcm8b6gyvadd8pilj38mxknqflgasxwyhyppvnmb9v1` |
| `nextflowLanguageServerVersion` | `25.10.3` | **`26.04.3`** | `sha256-IM+jT24gLWuLq9jXhiAs4A4NObcMzsMpDiqz+9ArwBY=` |
| `waveVersion` | `1.8.1` | `1.8.1` (unchanged) | unchanged |

**How the hashes were obtained.** The launcher hash came from
`nix-prefetch-url --type sha256 https://github.com/nextflow-io/nextflow/releases/download/v26.04.6/nextflow`.
The language-server hash came from `nix hash file --sri --type sha256` on the downloaded jar, cross-checked
against `nix-prefetch-url`, which returned the same digest in base32
(`05n05g8gpcra1qlw7khcnwwhs3p05hh8dmyqmf5nnb90dr7s7kr0`; `sha256sum` =
`20cfa34f6e202d6b8babd8d786202ce00e0d39b70ccec3290e2ab3fbd02bc016`). Neither hash was transcribed or guessed,
and both were then proven correct by a real build — a wrong hash fails the fetch outright.

**Language server.** `nextflow-io/language-server` **v26.04.3** (2026‑08‑03) is the newest release and matches
the 26.04 line, so it bumped cleanly. No compatibility caveat.

**wave-cli — deliberately not bumped.** 1.8.2 exists (2026‑03‑24), but nothing in 26.x requires it and the
brief was to bump only for a reason. Left at 1.8.1 to keep this commit minimal.

**Version-sensitive shell logic — checked, no change needed.** The `nfTestParallel` helper greps
`nf-schema@<ver>` out of `nextflow.config` and enables `NXF_OFFLINE` only when
`$HOME/.nextflow/plugins/nf-schema-<ver>` already exists. That path and the plugin id are unchanged under
26.04.6, and `nf-schema-2.5.1` was confirmed present in the 26.x plugin directory, so the preseed still
works. `NXF_DISABLE_CHECK_LATEST_VERSION` handling is unaffected. Worth noting for the future: the plugin
registry became mandatory in **25.10**, so a cold cache under `NXF_OFFLINE` still aborts rather than
downloading — unchanged behaviour, same caveat as before.

**Verification — real output.** `nix-shell --pure` builds and runs; `nf-core` needs network so it was checked
in the impure shell.

```
$ nix-shell --pure --run 'nextflow -version && nf-test version'
      N E X T F L O W
      version 26.04.6 build 12646
      created 09-07-2026 18:49 UTC (19:49 BST)
 nf-test 0.9.3

$ nix-shell --run 'nextflow -version | grep version; nextflow config -profile test >/dev/null; echo rc=$?'
      version 26.04.6 build 12646
rc=0

$ nix-shell --run 'nf-core --version'
nf-core, version 4.1.0
```

The language-server wrapper was confirmed to start and hold the LSP stdin loop (`timeout 5` → exit 124,
i.e. running, not crashing or missing).

**Did not bump cleanly: nothing.** Every pin moved or was consciously held, and the resulting shell builds and
runs the pipeline's own `nextflow config` without error.
