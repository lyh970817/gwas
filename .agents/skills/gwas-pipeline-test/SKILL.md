---
name: gwas-pipeline-test
description: Run or debug this nf-core/gwas pipeline's fixture-backed nf-test routes or full local suite. Use for tests under tests/, GWAS_TEST_FIXTURES, nf-test-parallel, native sharding, snapshot-staleness, or pipeline-behavior validation. Do not use for upstream component submission tests.
---

# Test the GWAS pipeline

Read the root fixture-safety boundary, `tests/AGENTS.md`, and
[`ci-and-testing.md`](../../../docs/coding-standards/ci-and-testing.md).

## Resolve fixtures

Two variables, and they are not interchangeable:

- **`GWAS_TEST_FIXTURES`** is the materialized, checksum-verified runtime root the tests read
  (`tests/lib/FIXTURES.groovy`, `conf/route_profile_resolver.config`). Every fixture-backed test needs it.
  It is not an optional override.
- **`GWAS_FIXTURE_SOURCE`** is the canonical source `tests/fixtures/materialize.sh` builds that root _from_.
  Leave it unset to let the script discover `.references/test-datasets-gwas`, including through its
  worktrees; set it to pin an unmerged source without committing a machine-specific path.

Build the root once per shell and export it:

```console
export GWAS_TEST_FIXTURES=$(tests/fixtures/materialize.sh --profile docker)
```

The script prints the root on stdout and its progress on stderr; it is content-addressed and `flock`-guarded,
so a second call on a warm cache is a sub-second no-op. Pass the profile you will test with. The dev-shell
`nf-test` and `nf-test-parallel` wrappers do this for you when the variable is unset and abort if it fails,
so the export matters most when driving the jar directly. `tests/fixtures/nf-test.sh` is the same thing
wrapped around a single focused run.

There is no working remote fallback. The published bundle at
`raw.githubusercontent.com/nf-core/test-datasets/gwas/` returns 404, and until this was made a hard error an
unset variable produced a run that started normally and then failed every fixture-backed case on schema
validation — 211 of 776 cases, three hours in. It now fails in about three seconds naming the variable and
the command. A modified fixture copy is not a drop-in either: `validateMaterializedRoot` checksums every file
against `.complete.sha256`, so regenerate that manifest or materialize from a pinned `GWAS_FIXTURE_SOURCE`.

## Invocation environment and durations

The dev shell's `nf-test` wrapper execs the jar directly with pinned Nextflow; do not export `NXF_VER` or
hard-code `/nix/store` paths. That wrapper also carries the tuning the suite's wall clock depends on — a
C1-only JIT and a capped heap through `NXF_JVM_ARGS`, `NXF_OFFLINE=true` once the Nextflow plugin cache is
warm, and fixture materialization when `GWAS_TEST_FIXTURES` is unset — so route every run through it rather
than invoking a jar directly. The `NXF_OFFLINE` probe reads `nextflow.config` from the working directory, so
it only applies when you run from the repository root; from anywhere else the wrapper says so and leaves the
variable alone. `NXF_OFFLINE` aborts a run
instead of downloading when a plugin is missing, so the wrapper probes the cache first and falls back to an
online run, announcing `Nextflow plugin cache cold, running online to warm it`. On a cold cache the first
run is that slower online one and warms the cache for the rest; treat a single unexplained slow run after a
wiped `~/.nextflow/plugins` as expected rather than a regression.

From a linked worktree, which has no direnv activation, run `nix-shell shell.nix --run '<command>'` from the
worktree root. A full sharded suite takes tens of minutes; launch shards with `run_in_background: true` and
act on completion notifications rather than sleep-waiting — Bash `timeout` caps at 10 minutes.

## Run the requested scope

Choose the smallest sufficient test type and discover the current filenames and cases before a focused run.
Record the selected paths or cases and the behavior they cover, including native command/output contracts and
positive/negative cache evidence where relevant. Add broader coverage for identified cross-package interactions.
For example:

```console
nf-test test tests/<route>.nf.test --profile +docker
```

`tests/fixtures/nf-test.sh tests/<route>.nf.test --profile +docker` is the equivalent that materializes
fixtures itself, for use outside the dev shell.

Reuse an owned warm `NFT_WORKDIR` and the materialized fixture root across serial commands when they use the
same checkout and fixture source. Keep concurrent runs isolated; do not share a live work directory. Coordinate
one heavy test or build job at a time on this host; a sharded invocation is one coordinated job.

For independently warranted broad validation, confirm `GWAS_TEST_FIXTURES` is exported (above), then
use `nf-test-parallel --verbose` when the development shell provides it; it prints the fixture root it is
using as its first line, so check that line rather than assuming. Select another
profile with `NFT_PROFILE`, and `NFT_SHARD_ROOT` to put the shard work dirs and logs outside the synced
repository folder (default `.nf-test-shards`). The shard count defaults to `min(6, max(1, floor(MemTotal_GB / 4)))` read from
`/proc/meminfo`, because the ceiling is the box's memory rather than its cores: each shard runs a heap-capped
nf-test JVM, a Nextflow head JVM and their Docker tasks. Six shards therefore need at least 24 GB, and this
machine (12.5 GB) derives 3 — running six here exhausted memory and froze the box mid-suite. The wrapper
announces a derived count as `nf-test-parallel: N shards (memory-derived; pass an explicit count to
override)`; an explicit first argument wins in either direction. Otherwise run the native shards with
`nf-test test --profile=+docker --shard i/N`, distinct `NFT_WORKDIR` values, and aggregated exit statuses.

## Select a broader tier when needed

A declared-type tier can cover interactions spanning several packages without selecting every pipeline case:

```console
export GWAS_TEST_FIXTURES=$(tests/fixtures/materialize.sh --profile docker)
nf-test-parallel --filter=process,workflow,function --verbose
```

`--filter` selects on the test type each file declares, so the same command selects the same cases on any
checkout and a mistake shows up as a changed count rather than as silence. Counted by `--dry-run` discovery,
which is the authoritative figure, the suite is 776 cases: 672 selected by `process,workflow,function`
(function 420, process 155, workflow 97) and 104 by `pipeline`, summing exactly. Do not confuse that with
the `test(` blocks in the sources — many are generated in `.each` loops, so one block yields several cases
— nor with counts measured on older commits: the suite was 828 cases before the validation-rejection and
stub-twin collapse, and 777 when issue #113 first measured it. Re-measure with `--dry-run` rather than
quoting any of them. `--related-tests` and `--changed-since` narrow further but choose from a diff, so a wrong
base quietly selects nothing and still reports success. If using them, inspect `--dry-run` discovery and verify
the selected cases against the intended scope before treating the result as evidence.

The type filter omits route-level and `-resume` coverage supplied by pipeline tests. Select those cases
explicitly when they cover the changed behavior; a tier pass alone does not establish that coverage. Follow
the canonical local-suite policy for intermediate merges and keep the final gate visibly pending.

## Close the final integration and snapshot gate

For an explicit final-integration gate, freeze the combined implementation and run the complete suite
unsharded through the dev-shell wrapper:

```console
nf-test test --profile=+docker --verbose
```

This gate covers the combined changes and deliberately deferred snapshot owners; it does not depend on first
running a duplicate complete sharded suite. Snapshot generation and updates work during focused runs, including
shards, and do not require a complete sequential run. Sharding skips tests and can suppress obsolete-snapshot
detection: for bounded removal/rename checks, run every affected file unsharded with all its tests passing and
no skips. That covers the affected owners without an extra global run. Inspect generated or changed snapshots
and reconcile recorded mechanical drift. Investigate unexpected output changes before accepting snapshots.

Use `--clean-snapshot` only when actual obsolete entries need removal, scoped to the affected files where
possible; do not use `--wipe-snapshot` for routine validation. Rerun affected failures or changes and inspect
the resulting diff. Apply the canonical repeat-run criteria rather than automatically repeating a green
complete suite after cleanup. Reuse evidence for the same candidate and scope rather than duplicating
validation; do not bracket purely snapshot maintenance with complete suites. Ordinary bounded changes need
only the focused scope unless a canonical complete-suite trigger applies.

Report exact scope, profile, fixture source, commands, pass/fail counts, snapshot warnings, environment
blockers, and whether the final gate is pending or complete. List any mechanical snapshot drift awaiting the
final gate separately from successful behavioral evidence.
