---
name: gwas-pipeline-test
description: Run or debug this nf-core/gwas pipeline's fixture-backed nf-test routes or full local suite. Use for tests under tests/, GWAS_TEST_FIXTURES resolution, nf-test-parallel, native sharding, snapshot-staleness checks, or a request to validate pipeline behavior. Do not use for colocated upstream module/subworkflow submission tests; use nf-core-submission-test for those.
---

# Test the GWAS pipeline

## Resolve fixtures

Follow the fixture boundary in `AGENTS.md`. The resolver discovers its default bundle from either the primary
checkout or a worktree under `.worktrees/`. Set `GWAS_TEST_FIXTURES` only for an explicit override such as a
private modified copy.

## Run the requested scope

For a focused route, discover the current test filename and run:

```console
nf-test test tests/<route>.nf.test --profile +docker
```

For broad validation, use `nf-test-parallel 3 --verbose` when the local development shell provides it. Select a
different profile with `NFT_PROFILE`.

Otherwise run the three native shards with `nf-test test --profile=+docker --shard i/3`, using distinct
`NFT_WORKDIR` values for `i=1`, `2`, and `3`, and aggregate every exit status.

After a green sharded run, run the suite sequentially to expose obsolete snapshot entries:

```console
nf-test test --profile=+docker --verbose
```

The serial run may report stale snapshot entries without failing. Confirm and remove stale entries deliberately;
do not use `--wipe-snapshot` for routine validation.

Report the exact test scope, profile, fixture source, commands, pass/fail counts, snapshot warnings, and any
environment blocker.
