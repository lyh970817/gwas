---
name: gwas-pipeline-test
description: Run or debug this nf-core/gwas pipeline's fixture-backed nf-test routes or full local suite. Use for tests under tests/, GWAS_TEST_FIXTURES, nf-test-parallel, native sharding, snapshot-staleness, or pipeline-behavior validation. Do not use for upstream component submission tests.
---

# Test the GWAS pipeline

Read the root fixture-safety boundary, `tests/AGENTS.md`, and
[`ci-and-testing.md`](../../../docs/coding-standards/ci-and-testing.md).

## Resolve fixtures

Use the repository resolver's default bundle from the primary checkout or a worktree under `.worktrees/`. Set
`GWAS_TEST_FIXTURES` only for an explicit private override such as a modified fixture copy.

## Run the requested scope

Discover the current filename before a focused run:

```console
nf-test test tests/<route>.nf.test --profile +docker
```

For broad validation, use `nf-test-parallel 3 --verbose` when the development shell provides it; select another
profile with `NFT_PROFILE`. Otherwise run all three native shards with
`nf-test test --profile=+docker --shard i/3`, distinct `NFT_WORKDIR` values, and aggregated exit statuses.

After a green sharded run, run `nf-test test --profile=+docker --verbose` sequentially to expose obsolete
snapshot entries. Confirm and remove stale entries deliberately; do not use `--wipe-snapshot` for routine
validation.

Report exact scope, profile, fixture source, commands, pass/fail counts, snapshot warnings, and environment
blockers.
