---
name: nf-core-subworkflow-create
description: Design, create, wire, or upstream an nf-core subworkflow in this repo. Use when defining reusable composition, take/emit contracts, identity flow, optional resources, scatter/gather behaviour, versions, tests, or pipeline-local boundaries before or during implementation.
---

Read `../nf-core-common.md` first. Treat this skill and the applicable routed skills as authoritative; use the
standards-cache fallback only when they are unclear or incomplete, or extra upstream detail is needed.

Use this skill when planning, specifying, creating, wiring, reviewing, or upstreaming a subworkflow under
`subworkflows/nf-core/<name>`, including issue work that decides reusable module composition before code exists.

## Standards cache fallback

If fallback is needed, relevant topic hints are:

- `docs/nf-core-standards/component-creation.md`
- `docs/nf-core-standards/subworkflows.md`
- `docs/nf-core-standards/module-testing.md`
- `docs/nf-core-standards/test-datasets.md`
- `docs/nf-core-standards/contributing-prs.md`

Inspect nearby subworkflows for style only after applying the active skills. If the standards cache is
consulted, current upstream standards override stale nearby examples.

## Workflow

1. Confirm the subworkflow name, target path, and whether the subworkflow represents a logical unit of at least two modules. For format-specific data processing, begin the name with the primary input format, then use concise semantic tokens for the operation and, when useful for disambiguation, the tool or tool chain; do not require a tool suffix. Use lowercase snake case for the directory and `meta.yml` name, and the same tokens in uppercase for the workflow symbol. Generic orchestration and genuinely co-primary formats may use a semantic exception.
2. Check whether an equivalent subworkflow already exists with `nf-core subworkflows list`, repository search, open PRs, or local inspection as appropriate.
3. Ensure work happens in a dedicated submission branch/worktree under `.worktrees/modules/`.
4. Generate or maintain the standard files: `main.nf`, `meta.yml`, optional `nextflow.config`, and `tests/main.nf.test`.
5. Keep channel, parameter, function, and file names consistent with this skill and the repository mechanics. Put includes before optional pure helper functions and the workflow; alias repeated imports by semantic role. Keep the workflow body ordered `take:`, `main:`, `emit:` and document public channel/value shapes at those boundaries.
6. Define all required and optional input channels in `take`. For optional file inputs, use the current documented empty-list convention where appropriate.
7. Own scatter/gather state at the composition boundary. Pass a requested shard count only to the splitting atom
   whose native command consumes it; derive the actual cardinality and key set from native splitter outputs into
   a keyed manifest, then scatter and gather by those keys. Emit useful aggregate execution provenance separately;
   keep atomic inputs and outputs limited to native selectors, runtime dependencies, and keyed shard identity.
8. Emit stable public products by name and keep temporary orchestration channels private. Preserve focal metadata through reshaping; add collision-free temporary keys only for joins/scatter, remove them before emission, and guard expected one-to-one joins with `failOnMismatch: true` and `failOnDuplicate: true`. Use `groupKey`/`groupTuple`/`getGroupTarget` when gather completion depends on actual cardinality; use `collect()` only when the native consumer truly requires one global collection.
9. Document channel structures in code comments and `meta.yml`. In `meta.yml`, inventory the invoked module and subworkflow dependency graph under `components` (subworkflows have no `tools` section) and include no `topics` section.
10. Let current module version topics flow through the composition without manually collecting or re-emitting them. Manually mix an explicit `versions` output only as a compatibility path when a called legacy component still exposes ordinary version channels; never document a versions output that `main.nf` does not emit.
11. For workflow-wide tool/route selectors, initialise every conditionally produced public channel with `channel.empty()`, invoke the selected branch, and keep the emitted API stable. Use `branch` for per-record mutually exclusive routing and `mix` compatible products back together. Reject invalid selector/input combinations before execution.
12. Tests must use the standard `nextflow_workflow` wrapper; include `subworkflows`, `subworkflows_nfcore`, `subworkflows/<name>`, and every directly or dependently exercised component tag. Exercise every distinct real composition route and every optional-input, skip, or selector path that changes behaviour; include at least one representative end-to-end stub unless branches have materially different stub behaviour. Assert `workflow.success`, snapshot stable `workflow.out` contracts or semantic projections of unstable outputs, and assert routing, identity, or absence explicitly when a snapshot obscures it. Validate topic-carried versions through the relevant output/snapshot only when the subworkflow exposes them.
13. Add `tests/nextflow.config` only for test-specific `ext.args`, prefixes, collisions, or runtime behaviour, and load it explicitly from the test. A component-root `nextflow.config` instead documents integration selectors a caller must transplant; do not conflate the two. Use the repository test-data base path with `checkIfExists: true` for source fixtures.
14. Reuse existing `nf-core/test-datasets` fixtures where possible. Prefer setup-generated intermediates from existing modules when that is more stable than adding new fixtures.
15. Run formatting, lint, and tests using the commands in `nf-core-common.md`. Use Docker during iteration; run Docker, Singularity, and Conda before PR readiness.

## Contract consistency

Treat the directory, workflow symbol, `main.nf`, `meta.yml`, tests and snapshots as one public contract. Ensure every public `take` and named `emit` is covered once, without duplicate or missing channel documentation and in the same public order as `main.nf`; structured tuple members, optionality, patterns and scalar constraints agree; focal/output identity transformations are explicit; and `components` matches the invoked dependency graph. Prefer current channel-centric metadata over legacy flat tuple-element documentation. When the companion tree disagrees with itself, use recent unrelated examples plus the current schema and lint rather than copying migration debt.

## Completion

Report:

- subworkflow path and submission worktree;
- standards cache topics consulted, if any;
- dependent modules and required test tags;
- fixture decision;
- commands run and results;
- remaining blockers or profiles not run.
