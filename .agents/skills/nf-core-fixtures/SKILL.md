---
name: nf-core-fixtures
description: Decide, prepare, or review nf-core/test-datasets fixtures for an upstream module or subworkflow submission. Do not use for this pipeline's private GWAS fixture resolver.
---

# Resolve component fixtures

Read
[`component-fixtures-and-testing.md`](../../../docs/coding-standards/component-fixtures-and-testing.md) and
[`contribution-boundaries.md`](../../../docs/coding-standards/contribution-boundaries.md). Use the relevant
`docs/nf-core-standards/` topics only for unresolved upstream detail.

## Fixture decision

1. Enumerate every test input and whether the output needs biological meaning or only valid tool execution.
2. Search existing `nf-core/test-datasets` data with the current CLI and repository branch.
3. Compare reuse with deterministic generation by existing components in `setup {}`.
4. If new shared data is still required, resolve the user's writable `nf-core/test-datasets` fork, create a
   dedicated branch/worktree, and coordinate it with the component worktree. Do not assume a personal path.
5. Keep local worktree handoff links uncommitted and do not push or open a fixture PR without the user's explicit
   request.

## Pre-submission gate

Before publishing fixture work, inspect the current target branch's `.github/workflows/` and reproduce every
applicable job against the complete fixture worktree:

1. Record each installed action/tool version and matrix value.
2. Run the same command over the same repository scope; whole-repository checks remain whole-repository checks.
3. Run every declared test matrix entry with the exact Nextflow version, profile, and flags.
4. Reproduce hidden action behavior from its primary documentation or a local action runner.
5. Stop while any equivalent job is red; fix it, rerun the complete gate, and record successful commands and
   versions in the private handoff.

Report the reuse/generation/new-data decision, paths proposed, discovery and gate commands/results, and whether a
companion public fixture PR is required.
