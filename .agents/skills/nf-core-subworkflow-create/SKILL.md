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

1. Confirm the subworkflow name, target path, and whether the subworkflow represents a logical unit of at least two modules.
2. Check whether an equivalent subworkflow already exists with `nf-core subworkflows list`, repository search, open PRs, or local inspection as appropriate.
3. Ensure work happens in a dedicated submission branch/worktree under `.worktrees/modules/`.
4. Generate or maintain the standard files: `main.nf`, `meta.yml`, optional `nextflow.config`, and `tests/main.nf.test`.
5. Keep channel, parameter, function, and file names consistent with this skill and the repository mechanics;
   use cached subworkflow naming detail only if the fallback is needed.
6. Define all required and optional input channels in `take`. For optional file inputs, use the current documented empty-list convention where appropriate.
7. Own scatter/gather state at the composition boundary. Pass a requested shard count only to the splitting atom
   whose native command consumes it; derive the actual cardinality and key set from native splitter outputs into
   a keyed manifest, then scatter and gather by those keys. Emit useful aggregate execution provenance separately;
   keep atomic inputs and outputs limited to native selectors, runtime dependencies, and keyed shard identity.
8. Emit all file outputs with named extensions and collect module `versions` channels into the subworkflow `versions` output.
9. Document channel structures in code comments and `meta.yml`. In `meta.yml`, list the called modules under a `components` section (subworkflows have no `tools` section) and include no `topics` section.
10. Tests must include required tags for dependent modules/subworkflows, exercise meaningful input/output shapes, include success and versions assertions, and at minimum support CI stub execution.
11. Reuse existing `nf-core/test-datasets` fixtures where possible. Prefer setup-generated intermediates from existing modules when that is more stable than adding new fixtures.
12. Run formatting, lint, and tests using the commands in `nf-core-common.md`. Use Docker during iteration; run Docker, Singularity, and Conda before PR readiness.

## Completion

Report:

- subworkflow path and submission worktree;
- standards cache topics consulted, if any;
- dependent modules and required test tags;
- fixture decision;
- commands run and results;
- remaining blockers or profiles not run.
