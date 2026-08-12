---
name: nf-core-subworkflow-create
description: Design, create, wire, review, or upstream an nf-core subworkflow, including upstream-bound candidates under subworkflows/local/. Use for reusable composition, take/emit contracts, identity flow, scatter/gather, optional resources, versions, tests, or pipeline-local boundaries. Do not use for pipeline-only routing with no component-library contract.
---

# Create or maintain an nf-core subworkflow

Read the canonical contracts in
[`nf-core-subworkflows.md`](../../../docs/coding-standards/nf-core-subworkflows.md) and
[`contribution-boundaries.md`](../../../docs/coding-standards/contribution-boundaries.md). Also read the GWAS and
fixture/testing topics indexed by `CODING_STANDARDS.md` when those surfaces apply.

For unresolved upstream detail, inspect the fetch date and relevant topic under `docs/nf-core-standards/`; use
`nf-core-standards-refresh` only when staleness affects the decision. Current upstream standards beat nearby
examples, but a conflict with a canonical repository contract must be surfaced and resolved deliberately.

## Procedure

1. Confirm the proposed logical unit, public name, target path, dependent components, and whether it is a local
   candidate or a real upstream submission.
2. Search current component listings, open PRs, and unrelated upstream examples for an equivalent composition.
3. Keep candidate work in this pipeline's isolated worktree. Put an actual submission in the separate writable
   `nf-core/modules` worktree required by the contribution-boundaries standard.
4. Generate or maintain the standard files, then reconcile `main.nf`, `meta.yml`, configuration, tests, and
   snapshots against every applicable canonical contract.
5. Trace focal identity, optional-resource absence, scatter/gather cardinality, version flow, and every public
   take/emit across the whole dependency graph. Record unresolved interface questions as blockers.
6. Resolve fixtures with `nf-core-fixtures` and validate with `nf-core-submission-test`.

## Completion

Report the subworkflow path and actual worktree, dependency graph and test tags, canonical topics and fallback
sources consulted, fixture decision, exact validation commands/results, and remaining blockers or profiles not
run.
