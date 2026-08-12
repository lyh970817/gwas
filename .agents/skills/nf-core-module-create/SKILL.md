---
name: nf-core-module-create
description: Design, create, wire, review, or upstream an nf-core module, including upstream-bound candidates under modules/local/. Use for an atomic component's execution path, interface, metadata, outputs, versions, tests, fixtures, or containers. Do not use for pipeline-only processes with no component-library contract.
---

# Create or maintain an nf-core module

Read the canonical contracts in
[`nf-core-modules.md`](../../../docs/coding-standards/nf-core-modules.md) and
[`contribution-boundaries.md`](../../../docs/coding-standards/contribution-boundaries.md). Also read the GWAS,
container, and fixture/testing topics indexed by `CODING_STANDARDS.md` when those surfaces apply.

For unresolved upstream detail, inspect the fetch date and relevant topic under `docs/nf-core-standards/`; use
`nf-core-standards-refresh` only when staleness affects the decision. Current upstream standards beat nearby
examples, but a conflict with a canonical repository contract must be surfaced and resolved deliberately.

## Procedure

1. Confirm the component name, executable owner, operation, target path, and whether the requested work is a
   pipeline-local candidate or a real upstream submission.
2. Search the current component library, CLI listings, open PRs, and relevant upstream examples for an
   equivalent component.
3. Keep candidate work in this pipeline's isolated worktree. Put an actual submission in the separate writable
   `nf-core/modules` worktree required by the contribution-boundaries standard.
4. If transferring from `modules/local/`, copy only the portable component behavior and required files.
5. Generate or maintain the standard component surface, then reconcile `main.nf`, `meta.yml`, environment,
   tests, configuration, and snapshots against every applicable canonical contract.
6. Resolve containers with `nf-core-containers` and fixtures with `nf-core-fixtures` when applicable.
7. Run `nf-core-submission-test`; use its quick loop while iterating and its full profile gate before declaring
   PR readiness.

## Completion

Report the module path and actual worktree, canonical topics and fallback sources consulted, fixture and
container decisions, exact validation commands/results, and remaining blockers or profiles not run.
