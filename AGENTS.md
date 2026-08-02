# AGENTS.md

## Coding standards

`CODING_STANDARDS.md` at the repo root is the documented coding standard, indexing the topic files under
`docs/coding-standards/`. It is the standards source for the `code-review` skill. For anything destined for
upstream `nf-core/modules`, the `nf-core-*` skills under `.agents/skills/` take precedence over it.

The LDAK, GWASLab, GCTA, PLINK and PLINK 2 modules and their subworkflows under
`modules/local/` and `subworkflows/local` are being prepared for future
upstream submission. They MUST therefore follow current nf-core module and subworkflow
standards and the applicable `nf-core-*` skills despite their local path;
pipeline-specific routing and scientific policy belong in subworkflows or
`conf/modules/`, not in atomic module metadata or command construction.

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

## Local GWAS test contract

**Fixtures.** The read-only machine-local GWAS fixture checkout is
`/home/andongni/Yandex.Disk/Projects/Research/qc_dev/test-datasets-gwas` (the `gwas` branch of
`nf-core/test-datasets`). It is local-development only: do not hard-code this path in tracked files or make CI
depend on it. CI retains the upstream fixture URL/fallback. Tests needing modified data must use a private copy.

Fixture-backed tests from a checkout below `.worktrees/` must set `GWAS_TEST_FIXTURES`, because the fixture
resolver has no sibling checkout there. For a focused route test:

```console
GWAS_TEST_FIXTURES=/home/andongni/Yandex.Disk/Projects/Research/qc_dev/test-datasets-gwas \
  nf-test test tests/association_plink2.nf.test --profile +docker
```

**Broad validation.** When `nf-test-parallel` is available in the local development shell, use it for the
fixture-backed three-shard suite:

```console
GWAS_TEST_FIXTURES=/home/andongni/Yandex.Disk/Projects/Research/qc_dev/test-datasets-gwas \
  nf-test-parallel 3 --verbose
```

`nf-test-parallel 3` is a local convenience: it runs three native `--shard i/3` workers and uses `+docker` by
default; select another profile with `NFT_PROFILE`. When it is unavailable, run native
`nf-test test --profile=+docker --shard i/3` workers for `i=1`, `2`, and `3`, each with a distinct
`NFT_WORKDIR`, and aggregate their exit statuses.

After every green sharded run, validate stale snapshots sequentially:

```console
GWAS_TEST_FIXTURES=/home/andongni/Yandex.Disk/Projects/Research/qc_dev/test-datasets-gwas \
  nf-test test --profile=+docker --verbose
```

The serial run reports obsolete snapshot entries without failing. Remove confirmed stale entries deliberately;
do not use `--wipe-snapshot` for routine validation.

## Agent skills

### Issue tracker

Issues and specs live as markdown files under `.scratch/<feature-slug>/` in this repo. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles are used as-is (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`), plus one of our own, `done`, for a ticket whose work has landed. Recorded as a `Status:` line in each issue file. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
