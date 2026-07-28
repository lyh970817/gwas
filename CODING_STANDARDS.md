# Coding standards — nf-core/gwas

This is the documented coding standard for this repository. The `code-review` skill discovers this file in
its "identify the standards sources" step and hands it, plus the topic files below, to the Standards
sub-agent.

## Standards sources

| File                                                                                                     | Covers                                                                                                                                  |
| -------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| [`docs/coding-standards/nextflow-code-style.md`](docs/coding-standards/nextflow-code-style.md)           | `.nf` and Groovy style: layout, banners, includes, naming, channels, workflow anatomy, local module bodies, version reporting, comments |
| [`docs/coding-standards/configuration-and-schema.md`](docs/coding-standards/configuration-and-schema.md) | `nextflow.config`, `conf/*.config`, `nextflow_schema.json`, `assets/*.json`, `.nf-core.yml`                                             |
| [`docs/coding-standards/ci-and-testing.md`](docs/coding-standards/ci-and-testing.md)                     | nf-test layout and assertions, GitHub Actions, lint/format tooling, repo hygiene files                                                  |
| [`docs/coding-standards/documentation-and-assets.md`](docs/coding-standards/documentation-and-assets.md) | `README.md`, `docs/usage.md`, `docs/output.md`, `CHANGELOG.md`, `CITATIONS.md`, `assets/`, `bin/` scripts, prose style                  |

## How to use these in review

1. **Rule tags carry the severity.** Do not invent your own.
   - **[MUST]** — a violation is a review finding. Cite the file and the rule.
   - **[SHOULD]** — a strong default. Flag a deviation only when the change gives no reason for it.
   - **[TOOLING]** — a formatter or linter owns this. **Never raise it as a finding**; the only reportable
     failure is evidence the tool was not run.
2. **Skip anything tooling already enforces.** `nextflow lint -format -harshil-alignment`, Prettier,
   pre-commit, and `nf-core pipelines lint` between them cover most formatting. Review time spent on
   whitespace is wasted.
3. **These standards override the Fowler smell baseline** that the `code-review` skill carries. Where a
   rule here endorses something the baseline would flag, the rule wins.
4. **Rules are stated with their evidence.** Each carries an `(all three)`, `(2/3)`, or
   `(1/3 — chosen)` marker. A rule marked `(1/3 — chosen)` is a deliberate decision for this pipeline, not
   a majority observation — it is still binding, but say so when citing it.

## Precedence

When guidance conflicts, resolve in this order:

1. The user's current request.
2. Repository mechanics in `CLAUDE.md`.
3. The active `nf-core-*` lifecycle skills under `.claude/skills/`. **For anything destined for upstream
   `nf-core/modules`** — module and subworkflow interfaces, `meta.yml`, component tests, submission
   hygiene — `nf-core-gwas-module-conventions` and `nf-core-submission-review` are authoritative and this
   document defers to them.
4. This document and its topic files, for pipeline-level style.
5. The cached upstream standards under `docs/nf-core-standards/`, consulted as a fallback only.

If a rule here contradicts an active skill, surface the conflict and update the skill deliberately rather
than letting the two drift apart.

## Provenance

Derived on 2026-07-27 from three established nf-core pipelines checked out alongside this repo:
`nf-core/rnaseq` (template 3.26.0), `nf-core/sarek` (template 3.9.0), `nf-core/mag` (template 5.4.2).

Two things follow from how these were read, and both matter when applying the rules:

- **The three pipelines disagree, and the disagreements are usually migrations in progress**, not
  legitimate alternatives. Lowercase `channel.*` factories, topic-channel version reporting, the newer
  container ternary, and Wave container URIs are all mid-migration across the reference set. Where a rule
  picks the newer side of a live migration, it says so. A greenfield pipeline should start on the far side
  of a migration, not inherit the transition.
- **Each pipeline's inconsistencies were recorded as well as its conventions**, and several rules exist
  specifically to prevent a defect one of the three actually carries — mixed toggle polarity, stale
  `.nf-core.yml` exemptions, mutated `meta` maps, unanchored enum patterns, bitwise `&` for boolean logic.
  Those are cited by name so the rule is arguable rather than arbitrary.

Claims that could be counted mechanically were verified directly against the sources rather than taken from
the reading pass; those rules quote the measured counts. One reported rule ("`else` always begins a line")
did not survive verification and was demoted to **[TOOLING]**.

## Hard-rule quick reference

The full rules and their rationale live in the topic files. This is the recall list, not a substitute.

**Nextflow**

- 4-space indent, no tabs; run `nextflow lint -format -sort-declarations -spaces 4 -harshil-alignment`.
- Lowercase `channel.empty()` / `.of()` / `.fromPath()`; never `Channel.`.
- Never use the implicit `it`; name every closure parameter; prefix unused ones with `_`.
- `ch_` prefix for channel variables, and only for channel variables.
- Assign channels (`ch_x = ...`); do not use `.set { }`.
- Rebuild `meta` immutably (`def meta_new = meta + [...]`); never mutate it in a closure.
- `take:` and `emit:` entries carry aligned `// channel: [ val(meta), path(x) ]` shape comments.
- Every subworkflow emits `versions`, last in the `emit:` block.
- Version reporting uses topic channels with `eval()` — no `versions.yml` heredocs in new local modules.
- `error("[nf-core/gwas] ERROR: …")` for fatal, `log.warn("[nf-core/gwas]: …")` for non-fatal. Never
  `throw`, never `exit()`.
- `&&` / `||` for boolean logic, never bitwise `&`.
- Module directive order: `tag` → `label` → `conda` → `container` → `input:` → `output:` → `when:` →
  `script:` → `stub:`.

**Config and schema**

- Never default a string or path param to `''` — `null` if optional, `false` if a toggle.
- One toggle polarity per feature area; do not mix `skip_*` and `run_*` for the same feature.
- No `check_max()`; no `resourceLimits` in `base.config` (it belongs in test configs).
- `ext.args` built as `[...].join(' ').trim()`, never string concatenation.
- `$defs` not `definitions`; `allOf` order mirrors `$defs` order; every group has a `fa_icon`.
- Every schema `description` is a capitalised sentence ending in a period.
- `validation.defaultIgnoreParams`, never `validationSchemaIgnoreParams`.
- Samplesheet uniqueness uses `uniqueEntries`, never `uniqueItems`; `meta` is always an array.
- Keep `.nf-core.yml` exemptions in sync with the repo and justify every new one.

**Testing and CI**

- Assert success before snapshotting.
- Snapshot per labelled output area, not one unlabelled whole-tree blob; leave no superseded snapshot code
  commented out.
- `.snap` files are committed and excluded from whitespace hooks.
- Pin actions to a commit SHA with a version comment; pin the same action identically across sibling
  workflows; no `@main` / `@master`.
- Concurrency block with `cancel-in-progress: true` on every CI workflow.

**Documentation**

- See [`docs/coding-standards/documentation-and-assets.md`](docs/coding-standards/documentation-and-assets.md).
