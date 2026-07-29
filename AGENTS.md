# AGENTS.md

## Coding standards

`CODING_STANDARDS.md` at the repo root is the documented coding standard, indexing the topic files under
`docs/coding-standards/`. It is the standards source for the `code-review` skill. For anything destined for
upstream `nf-core/modules`, the `nf-core-*` skills under `.agents/skills/` take precedence over it.

### Reference pipelines

`../sarek`, `../mag` and `../rnaseq` are checkouts of established official nf-core pipelines and are the
style reference for this repository. `CODING_STANDARDS.md` was derived from them, so consult the checkouts
directly whenever a question is not settled by the written standard — how a `.nf` file is laid out, how
`conf/modules.config` selectors are written, how `nextflow_schema.json` is structured, how nf-test files and
snapshots are organised, how `docs/usage.md` and `docs/output.md` read. Prefer what these three actually do
over what looks reasonable in the abstract.

Two caveats when reading them. Where the three disagree, the disagreement is usually a migration in
progress rather than a genuine choice — take the newer side (lowercase `channel.*` factories, topic-channel
version reporting, the newer container ternary, Wave container URIs). And they are not uniformly clean;
`CODING_STANDARDS.md` records their inconsistencies as well as their conventions, so where it has already
ruled on a point, it wins over a contrary example found in a checkout.

## Local test fixtures

The verified machine-local GWAS fixture checkout is
`/home/andongni/Yandex.Disk/Projects/Research/qc_dev/test-datasets-gwas` (the `gwas` branch of
`nf-core/test-datasets`). It is recognised by
`results/fixtures/genotypes/example_all.pgen`; the generic sibling `test-datasets` checkout is not a
substitute for these pipeline fixtures.

Tests that call `SAMPLESHEET.fixtures` need real genotype data. In an independent worktree, set the
fixture root explicitly, then run the focused test, for example:

```console
GWAS_TEST_FIXTURES=/home/andongni/Yandex.Disk/Projects/Research/qc_dev/test-datasets-gwas \
  nf-test test tests/association_plink2.nf.test --profile +docker
```

`tests/lib/FIXTURES.groovy` resolves fixtures in this order: a non-empty `GWAS_TEST_FIXTURES` (which must
contain the marker above, or the test fails clearly), then a marker-bearing `../test-datasets` or
`../test-datasets-gwas` sibling of the pipeline checkout, then the committed upstream raw-GitHub URL. A
worktree below `.worktrees/` has no such sibling, so it requires the environment variable. The variable only
serves the nf-test samplesheet builder; it is not a general Nextflow configuration override.

For a fixture-backed full local suite, use the available `nf-test-parallel` launcher from the repository root.
Three shards is its documented measured setting:

```console
GWAS_TEST_FIXTURES=/home/andongni/Yandex.Disk/Projects/Research/qc_dev/test-datasets-gwas \
  nf-test-parallel 3 --verbose
```

When `NFT_PROFILE` is unset, the launcher selects `+docker`; it then runs native `--shard i/3` workers in
separate `.nf-test-shards/shard-*` work directories, retains a log per shard, waits for all workers, and fails
when any shard fails. Select a non-default profile through `NFT_PROFILE`, rather than adding a second
`--profile` argument. The portable fallback, only when this local launcher is unavailable, is to run the three
native `nf-test test --profile=+docker --shard i/3` commands with distinct `NFT_WORKDIR` values and aggregate
their exit statuses. CI uses that portable sharding mechanism and its own profile matrix; do not make it depend
on this local launcher.

nf-test marks tests outside each shard as skipped, so parallel workers cannot reliably report obsolete snapshot
entries. After a green sharded run, complete snapshot-integrity validation sequentially:

```console
GWAS_TEST_FIXTURES=/home/andongni/Yandex.Disk/Projects/Research/qc_dev/test-datasets-gwas \
  nf-test test --profile=+docker --verbose
```

Review the serial run's obsolete-snapshot warning or summary: it reports stale entries but does not make the
command fail. Remove intended obsolete entries deliberately; do not use `--wipe-snapshot` as a routine
validation command because it rewrites tracked snapshot files.

This is a local-development convenience only: do not hard-code this machine path in tracked source or test
snapshots, and do not configure CI to depend on it. CI must retain the upstream fixture URL/fallback. Treat
the shared checkout as read-only; tests that need modified data must create a private copy beside their
generated samplesheet.

## Agent skills

### Issue tracker

Issues and specs live as markdown files under `.scratch/<feature-slug>/` in this repo. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles are used as-is (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`), recorded as a `Status:` line in each issue file. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
