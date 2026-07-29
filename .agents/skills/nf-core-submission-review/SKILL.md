---
name: nf-core-submission-review
description: Audit a planned or implemented nf-core module or subworkflow for standards conformance. Use for component portfolios, design issues, specifications, interface proposals, worktrees, branches, PRs, metadata/test consistency, or submission readiness.
---

Read `../nf-core-common.md` first. Treat this skill and the applicable lifecycle skills it audits as
authoritative; use the standards-cache fallback only when they are unclear or incomplete, or extra upstream
detail is needed.

Use this skill when work is about to settle an nf-core component portfolio or public contract, or when the
user asks for a review of a module, subworkflow, worktree, branch, PR, or work-in-progress change intended for
upstream `nf-core/modules`. For design-only work, apply every checklist item that can be evaluated before code
exists and report the remainder as implementation gates.

## Standards cache fallback

If fallback is needed, relevant topic hints are:

- Modules: `docs/nf-core-standards/module-file-structure.md`, `module-main-nf.md`, `module-meta-yml.md`, `module-testing.md`, `module-containers.md`.
- Subworkflows: `docs/nf-core-standards/subworkflows.md`, `module-testing.md`.
- All submissions: `docs/nf-core-standards/test-datasets.md`, `contributing-prs.md`.

## Review execution

- Run the review in an Agent tool subagent (e.g. `general-purpose` or `Explore`) where available. If subagent tools are unavailable, state that and review directly.
- Ask the reviewer to prioritise bugs, standards violations, metadata/test mismatches, fixture risks, missing profiles, and PR blockers.
- Do not perform broad rewrites during a review unless the user explicitly asks for fixes.
- Check whether the target is in a focused submission worktree. Flag deviations that can affect upstream submission hygiene.

## Review checklist

Look for:

- component name, path, and process/workflow naming conformance;
- `main.nf`, `meta.yml`, `environment.yml`, tests, snapshots, and optional config consistency;
- unnecessary `tests/nextflow.config`: flag a config that only sets a cosmetic `ext.prefix` (no `ext.args`/`module_args`, and no real input/output collision to resolve) — it should be dropped and the `config "./nextflow.config"` line removed from the `.test`;
- input/output ordering and matching metadata across implementation, docs, tests, and snapshots;
- atomic interface ownership against the `nf-core-module-create` “Keep the atomic interface native” gate;
- scatter/gather ownership against the `nf-core-subworkflow-create` “Own scatter/gather state” gate;
- for GWAS/popgen components, the `nf-core-gwas-module-conventions` genotype contracts, including preservation
  of an accepted dual-format PLINK semantic union;
- `ext.args`, `ext.prefix`, versions output, stub block, resource label, conda/container declarations, and formatting; flag any baked `task.ext.args ?: '--flag value'` default (must be `?: ''`, with tool-mandatory flags promoted to `val(...)` inputs) and — the reverse error — any _optional_ flag/scalar carried as a `val(...)` input or tuple member when it should be `ext.args`: a scalar that maps to a flag the module omits when it is absent (`x ? "--x ${x}" : ''`) belongs in `ext.args` even if it is scientifically meaningful or phenotype-specific (e.g. REGENIE `--bt`, GCTA/LDAK REML `--prevalence`), per `nf-core-gwas-module-conventions` "Scalar selectors vs. file identity"; only _required_ scalars and _mandatory mutually-exclusive mode selectors_ (distinct executables/output schemas, e.g. fastGWA `is_binary`, PCGC `prevalence`) stay as inputs. Optional _file_ inputs are the exception — they stay as `path(...)` with `[]` when absent, never `ext.args`. Also flag any leading blank line inside `script:`/`stub:` command blocks;
- metadata links, bio.tools ID, file patterns, topic output descriptions, and an `ontologies:` key on every file-type input/output entry (a real `- edam:` term or `[]`); and `meta.yml` `keywords` that spell out tool acronyms for discoverability;
- no custom `meta` map keys (only the nf-core-defined set); multiple metadata-bearing inputs use each map's own `.id`; the `meta` map is not mutated/rebound on outputs (`meta + [id: ...]`); the output prefix derives from `meta.id`/staged basename and stays overridable via `ext.prefix` (not hardcoded from an arbitrary input `baseName`);
- the optional-args variable is named `args` (not `extra_args`); the resource `label` matches the tool's real needs (not a placeholder `process_medium`); the module is agnostic to fan-out/partitioning (splitting lives in a subworkflow, and any part/nparts selector defaults to 1 when absent);
- one `emit:` per semantically distinct output file/group (not unrelated globs bundled together); a version reported for every tool invoked including secondary interpreters (R/Python), each `eval` yielding a bare version string (no leading `v`, extension, or extra lines);
- work-directory name-collision handling (two same-typed input sets, or output vs input) via `stageAs` subfolders or a distinct default `ext.prefix`, covering all companion files — distinct from the anti-`stageAs` caller-basename-contract rule;
- command construction that is simple and self-evident (no unexplained Groovy such as `findAll`, no cryptic variable names, non-trivial in-script post-processing justified as contract);
- test cases free of unnecessary conditional logic (nf-test inputs are fixed) and covering each distinct output-file extension the tool can produce;
- tests for all outputs including optional outputs, success assertions, versions assertions, stable snapshots, and stub behaviour; flag assertions the sanitised snapshot already covers (channel `.size()`, `fileName`, per-file paths, `readLines().size() > 0`) — lint already fails empty-file md5s, so non-emptiness checks are redundant;
- reuse of existing fixtures or a justified companion test-datasets submission;
- commands required before PR readiness.

## Output format

Lead with findings, ordered by severity. Use file and line references when possible. Then list open questions, test gaps, and a brief change summary only if useful.
