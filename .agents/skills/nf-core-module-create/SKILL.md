---
name: nf-core-module-create
description: Design, create, wire, review, or upstream an nf-core module, including upstream-bound candidates under modules/local/. Use when defining an atomic component's execution path, name, public interface, selectors, metadata roles, outputs, versions, tests, fixtures, or container strategy before or during implementation. Do not use for pipeline-only processes with no intended component-library contract.
---

Read `../references/nf-core-guidance-sources.md`. For an upstream submission, also read
`../references/nf-core-component-workspaces.md`. Treat this skill and the applicable routed skills as
authoritative.

## Standards cache fallback

If fallback is needed, relevant topic hints are:

- `docs/nf-core-standards/component-creation.md`
- `docs/nf-core-standards/module-file-structure.md`
- `docs/nf-core-standards/module-main-nf.md`
- `docs/nf-core-standards/module-meta-yml.md`
- `docs/nf-core-standards/module-args-params.md`
- `docs/nf-core-standards/module-meta-map.md`
- `docs/nf-core-standards/module-testing.md`
- `docs/nf-core-standards/module-containers.md`
- `docs/nf-core-standards/test-datasets.md`

Inspect nearby existing modules for style only after applying the active skills. If the standards cache is
consulted, current upstream standards override stale nearby examples.

Also apply, when relevant:

- `nf-core-containers` — for the `container` directive branching and Wave/Seqera URI verification whenever you touch the container directive or `environment.yml`.
- `nf-core-gwas-module-conventions` — for the repository-local contract shape (tuple ordering, `meta` roles, prefix identity, topic-based versions) whenever the module touches PLINK/PLINK2 or any GWAS/popgen tool.

## Workflow

1. Confirm the upstream component name and target path.
2. Check whether an equivalent module already exists with `nf-core modules list`, repository search, open PRs, or local inspection as appropriate.
3. Keep local-candidate work in a pipeline worktree; place an actual upstream submission in the component-library
   workspace described by `nf-core-component-workspaces.md`.
4. If starting from `modules/local/`, transfer only the minimal portable files and behaviour needed upstream.
5. Ensure the module has `main.nf`, `meta.yml`, `environment.yml`, and `tests/main.nf.test`; add or update `tests/main.nf.test.snap` only for intentional snapshot changes.
6. Keep process names uppercase and module directories lowercase. Use four-space Nextflow indentation and two-space YAML indentation.
7. Within each metadata-bearing tuple, declare `val(metaN)` first, followed by its file/path members and then any scalar `val(...)` members that are _mandatory_ for that tuple's analysis or file role (a required value, or a mandatory mutually-exclusive mode selector — optional flags go to `task.ext.args`; see `nf-core-gwas-module-conventions` "Scalar selectors vs. file identity"). Those tuple-local scalars remain inside the tuple and are not keys in the `meta` map. Put metadata-bearing input tuples before genuinely standalone, process-global `val(...)` inputs, and keep input/output ordering consistent between `main.nf`, `meta.yml`, tests, and snapshots.
8. Keep the atomic interface native: every input must be consumed by the command or staged because a
   manifest/list references it at runtime. Keep cleanup-only files and composition-only state outside module
   inputs. Put a requested scatter count on the splitting module only when the native split command consumes it.
   Keep the module agnostic to orchestration: partition/fan-out strategy belongs in a subworkflow or pipeline,
   never hard-coded into the module, and the module must handle the unsplit case gracefully — a required
   part/nparts selector defaults to 1 when absent (`def nparts = nparts_gcta ?: 1`) rather than assuming a
   splitting composition always supplies it (#11003).
9. Route optional command arguments through `ext.args`/`${args}` rather than hardcoding pipeline-specific behaviour. `def args = task.ext.args ?: ''` must default to an empty string — never bake tool flags into the `?:` default (reviewers reject `?: '--window-prune 0.98 ...'`). A flag the tool errors without is a mandatory interface input, not a hidden default: model it as a `val(...)` input (see `nf-core-gwas-module-conventions` "Scalar selectors vs. file identity") and supply it from the test, not from a default value.
10. Emit versions using the current topic output pattern expected by nf-core.
11. Add stub behaviour that creates valid files for every output channel, including valid gzip files where applicable.
12. Reuse existing `nf-core/test-datasets` fixtures where possible. Use setup-generated intermediates from existing modules instead of synthesizing branch-local helper files when practical.
13. Apply `nf-core-submission-test`. Use Docker during iteration; run Docker, Singularity, and Conda before PR readiness.

## main.nf and environment.yml rules

- `main.nf` defines exactly one `process`; the only process directives are `tag`, `label`, `conda`, and
  `container`. Do not add or retain a process-level `when:` block in a new or upstream-bound module.
- Define `args`, `args2`, and `prefix` only when the command or an output declaration consumes them. In `stub:`,
  define only variables needed to construct stub outputs; never retain an unused `args` declaration. Follow
  `nf-core-gwas-module-conventions` for dependency order and prefix scope.
- No leading blank line inside `script:`/`stub:` command blocks. Collapse mutually exclusive CLI fragments into
  one ternary rather than pairing separate "on" and "off" variables.
- Every file-type entry in `meta.yml` (inputs and outputs) MUST carry an `ontologies:` key — a list of `- edam: <url> # label` terms when a matching EDAM format term exists, or `ontologies: []` when none applies (e.g. PLINK `.bed/.bim/.fam`). Current nf-core lint/schema expects the key on every file entry; reviewers ask for it explicitly when missing.
- `environment.yml`: pin each dependency with its channel and version but not the build number; do not add channels unless strictly necessary and never add `defaults`; if pip dependencies are used, pin the `pip` version as well.
- GPU-capable modules must follow https://nf-co.re/docs/developing/components/gpu-modules.
- Add a `tests/nextflow.config` only when a test genuinely needs it — to pass `ext.args`/`args2...`, to use the `params.module_args` → `ext.args` pattern, or to set `ext.prefix` when it resolves a _real_ input/output name collision. Do NOT add a config that only sets a cosmetic `ext.prefix`; let outputs take the default `${meta.id}` prefix. Remember the config applies only when the `.test` declares `config "./nextflow.config"`, so a stray config with no such line is dead weight.
- Name the optional-arguments variable exactly `args` (`def args = task.ext.args ?: ''`) — reviewers rewrite `extra_args` or any other custom name back to `args` (upstream review did this repeatedly, e.g. #10995, #11005, #11650).
- The `meta` map keys are constrained to the nf-core-defined set (https://nf-co.re/docs/specifications/components/modules/general#types-of-meta-map-keys); never invent custom keys such as `pheno_col`, `nparts`, or `is_binary` — nf-core lint rejects them, and reviewers enforce it explicitly (#11003, #11008). When two metadata-bearing inputs each need identity, use each map's own `.id` (`meta.id`, `meta2.id`). Route optional per-analysis scalars through `ext.args` (a closure may read `meta`, e.g. `ext.args = { meta.trait_type == 'binary' ? '--bt' : '' }`) and mandatory scalars through `val(...)` tuple members — see `nf-core-gwas-module-conventions` "Scalar selectors vs. file identity". Do not mutate or rebind the `meta` map on outputs (`meta + [id: ...]`) to reflect an output basename (#11002); leave the incoming map intact and express renamed outputs through the filenames.
- Derive the output prefix from the active identity source (`meta.id`, or the staged basename for basename-driven tools) and keep it overridable via `task.ext.prefix`; do not hardcode it from an arbitrary input file's `baseName` when `meta.id` is available (#11008, #11009).
- Choose the resource `label` that matches the tool's real CPU/memory profile; do not leave every module on a placeholder `process_medium` (reviewers ask "is `process_medium` the best setting here?", #12343).
- When two same-typed input sets, or an output and an input, could collide on the same staged name in the work directory, stage each set into its own subfolder with `stageAs` (as `samtools/merge` does) or default `ext.prefix` to a distinct value — and cover every companion file of a multi-file bundle (`.bed`/`.bim`/`.fam`), not just the primary (#12273, #12277). This is the opposite of a caller basename/prefix contract mismatch, which you must NOT paper over with `stageAs` (see `nf-core-gwas-module-conventions` "Prefix / identity: one source of truth").
- Emit one output per semantically distinct file or file-group: give `*_pred.list` and `*.loco.gz` their own `emit:` blocks rather than bundling unrelated globs into a single output (#11008). Only files that always travel together and are consumed as a unit (a GRM bundle, a `.bed/.bim/.fam` trio) belong in one collected/glob output.
- Report a version for every tool the script actually invokes, including secondary interpreters (R/`r-base`, Python) used for post-processing, not only the headline tool (#10999). Craft each version `eval`/extraction so only the bare version string reaches the output — strip a leading `v`, any file extension/suffix, and extra lines (`... --version | head -n 1`); reviewers reject `v4.1.2.gz`-style values (#11008).
- Keep the module focused on invoking its tool. Command construction should be simple and self-evident: avoid unexplained Groovy collection tricks (`findAll`) and cryptic variable names (`lb1`..`lb4`), and justify any non-trivial in-script post-processing (e.g. an R reshaping step) as part of the documented contract rather than incidental scope creep (#10997, #10999).
- `meta.yml` `keywords` should include the spelled-out forms of tool acronyms (e.g. "genome-wide complex trait analysis", "genetic relationship matrix" for GCTA/GRM) so the component is discoverable by search (#11003).

## Completion

Report:

- module path and submission worktree;
- standards cache topics consulted, if any;
- fixture decision;
- commands run and results;
- remaining blockers or profiles not run.
