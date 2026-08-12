---
name: nf-core-pipeline-contribute
description: Open a PR against an existing nf-core pipeline — install and wire modules/subworkflows, update nextflow_schema.json and pipeline module configuration, run pipeline lint and nf-test, and get the PR review-ready. Use when contributing to a pipeline repo (targeting its dev branch), as opposed to submitting a component to the nf-core/modules library.
---

Read `../references/nf-core-guidance-sources.md`. In this repository, also apply `dual-track-commit` before any
commit or branch synchronization. Treat this skill as authoritative for pipeline contribution mechanics.

Use this skill when the work is a change to an **existing pipeline repo** (adding a feature, wiring in a module or subworkflow, adjusting parameters), not authoring a component for the shared library. Component authoring itself stays in `nf-core-module-create` / `nf-core-subworkflow-create`; this skill is the pipeline-side integration and PR flow.

## Repository context

Follow the repository identity in `AGENTS.md`. Portable pipeline work can be developed here on the personal and
upstream-PR tracks described by `dual-track-commit`; upstream component submissions use a separate
component-library workspace.

For pipeline work:

- Resolve the live remotes, branch from **`upstream/dev`** (never `master`/`main`), and target `dev`.
- Exception: a critical bug in a released version branches from `upstream/master` and targets `master` (hotfix path).
- `git pull --rebase upstream dev` before opening the PR.

## Standards cache fallback

If fallback is needed, relevant topic hints are:

- `docs/nf-core-standards/pipeline-contributing.md` — branch model, commit strategy, reviewer requests, review gating.
- `docs/nf-core-standards/pipeline-adding-components.md` — installing and wiring modules/subworkflows into a pipeline.
- `docs/nf-core-standards/pipeline-schema-config.md` — `nextflow_schema.json`, parameters, and module configuration.
- `docs/nf-core-standards/pipeline-testing.md` — pipeline nf-test and `nf-core pipelines lint`.

## Workflow

1. Open (or claim) a pipeline issue describing the change before writing code; branch off `dev` with a descriptive name.
2. Install components with `nf-core modules install <tool>` / `nf-core subworkflows install <name>`; let the tool update `modules.json`. Do not hand-copy component files.
3. Wire the component into a `workflows/` or `subworkflows/local/` file: `include` it, feed its `take` channels, and route its `emit` outputs and `versions`.
4. Surface new parameters through `nextflow_schema.json` (`nf-core pipelines schema build`), with types,
   defaults, and help text. In this repository, put per-process `ext.args`, `ext.prefix`, and `publishDir` in the
   relevant method-family file under `conf/modules/` via `withName` selectors, never inside the installed module.
5. Add a `CHANGELOG.md` entry — this is required for every nf-core pipeline PR (it is on the PR checklist). Put it under the current unreleased/`dev` version heading in the matching `### ` section (`Added`/`Fixed`/`Dependencies`/`Deprecated`), in nf-core style: `- [#<PR>](<pr-url>) - <summary>`. Also update pipeline docs (`docs/`, `README`, param docs) for any user-facing change.
6. Run the local gate before requesting review: `nextflow run . -profile debug,test,docker --outdir <dir>`, then `nf-core pipelines lint .`; extend or update pipeline nf-test cases and snapshots for the changed path.
7. Commit with descriptive messages; `git pull --rebase upstream dev`; open the PR against `dev` using the pipeline's PR template and reference the issue.
8. Request review in nf-core Slack `#request-review` once CI (lint + pipeline tests) is green.

## Completion

Report:

- pipeline repo, branch, and PR target branch;
- components installed and where they were wired;
- schema, params, and method-family config changes;
- the `CHANGELOG.md` entry added;
- standards cache topics consulted, if any;
- local commands run (smoke run, lint, nf-test) and their results;
- CI status and any profiles/tests not run.
