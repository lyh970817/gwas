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

## Invocation environment and durations

The dev shell's `nf-test` wrapper execs the jar directly with pinned Nextflow; do not export `NXF_VER` or
hard-code `/nix/store` paths. From a linked worktree, which has no direnv activation, run
`nix-shell shell.nix --run '<command>'` from the worktree root. A full three-shard suite takes tens of
minutes; launch shards with `run_in_background: true` and act on completion notifications rather than
sleep-waiting — Bash `timeout` caps at 10 minutes.

## Run the requested scope

Discover the current filename before a focused run:

```console
nf-test test tests/<route>.nf.test --profile +docker
```

For broad validation, use `nf-test-parallel 3 --verbose` when the development shell provides it; select another
profile with `NFT_PROFILE`. Otherwise run all three native shards with
`nf-test test --profile=+docker --shard i/3`, distinct `NFT_WORKDIR` values, and aggregated exit statuses.

After broad shard validation, apply the canonical unsharded-suite trigger. When it requires an unsharded run,
confirm and remove obsolete snapshot entries deliberately; do not use `--wipe-snapshot` for routine validation.

Report exact scope, profile, fixture source, commands, pass/fail counts, snapshot warnings, and environment
blockers.
