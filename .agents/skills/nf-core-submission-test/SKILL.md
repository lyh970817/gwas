---
name: nf-core-submission-test
description: Validate or debug an upstream nf-core module or subworkflow submission with current lint, nf-test, and wrapper commands. Do not use a green pipeline suite as component-submission readiness evidence.
---

# Validate a component submission

Read
[`component-fixtures-and-testing.md`](../../../docs/coding-standards/component-fixtures-and-testing.md), the
applicable module or subworkflow contract, and
[`contribution-boundaries.md`](../../../docs/coding-standards/contribution-boundaries.md). Use current cache
topics only for unresolved upstream detail.

## Procedure

1. Identify module versus subworkflow and run from its actual writable `nf-core/modules` submission worktree.
2. Inspect the diff, `main.nf`, `meta.yml`, environment/config files, tests, and snapshots before expensive runs.
3. After a Nextflow edit, run
   `nextflow lint -format -sort-declarations -spaces 4 -harshil-alignment`.
4. Debug narrowly with `nf-test test <test-file> --profile=docker --verbose`.
5. Run `nf-core modules lint <component>` or `nf-core subworkflows lint <component>`, then the matching wrapper.
6. Before PR readiness, run the wrapper under Docker, Singularity, and Conda. Do not use `--once` as final
   evidence; report a missing local runtime as an incomplete readiness gate.
7. Update snapshots only when the output change is intentional and understood. Prefer fixing the contract over
   weakening assertions.
8. Validate with the version of `nf-core` pinned by the target CI and current upstream state. If a merge queue or
   base update changes the lint surface, route branch synchronization and queue diagnosis to
   `nf-core-submission-pr`.

Report exact commands and versions, pass/fail results, intentional snapshot changes, unresolved profile gaps,
and the next concrete blocker.
