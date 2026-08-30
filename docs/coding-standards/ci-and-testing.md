# Pipeline testing, CI, and tooling standards

Applies to pipeline-level `nf-test.config`, `tests/**`, `.github/**`, and repository tooling. Component
submission tests use
[`component-fixtures-and-testing.md`](component-fixtures-and-testing.md) and the component submission skills.

## Mechanism ownership

`nf-test.config`, `tests/nextflow.config`, `.github/workflows/**`, `.github/actions/**`, `.prettierrc.yml`,
`.prettierignore`, `.pre-commit-config.yaml`, `.gitattributes`, `.gitignore`, the devcontainer, and editor settings
own their exact commands, versions, matrices, formatting, excludes, and file contents. Inspect those live files;
do not duplicate their complete configuration in prose.

The fixture resolver implementations in pipeline configuration and the test helpers own their exact search and
validation behavior. They must select the same fixture source for one launch context; treat disagreement as a
pipeline defect rather than letting guidance or a skill invent a third resolution algorithm.

Run the configured formatter, pre-commit hooks, Nextflow lint, and pipeline lint as applicable. Report missing or
failed mechanism evidence rather than hand-policing mechanically repairable formatting.

## Pipeline nf-test layout

- **[MUST]** Pipeline tests live flat in `tests/` and are named by scenario, not `main.nf.test`. A snapshot sits
  beside its matching test and is committed.
- **[MUST]** `tests/.nftignore` excludes nondeterministic output from content snapshots. Test data and anonymous
  object-store access are configured centrally in `tests/nextflow.config`.
- **[SHOULD]** Pipeline CI may discover tests colocated with local modules/subworkflows as regression coverage;
  that result does not replace component-submission validation.

## Test anatomy and scenario configuration

- **[MUST]** Order the header as `name`, `script`, workflow/process selector, optional `config`, tags, then test
  cases. Pipeline cases carry `tag "pipeline"` plus a scenario/profile tag.
- **[MUST]** Assert success before snapshots and group independent assertions with `assertAll(...)`.
- **[MUST]** Set `outdir = "$outputDir"` in the test and keep ordinary scenario configuration in a named test
  profile. A relational-input test may override cohort/analysis manifests and method options when the invalid or
  edge-case relationship is itself the subject.
- **[SHOULD]** Centralize repeated scenario wiring in `tests/lib/*.groovy` once a declarative helper makes the
  suite clearer.

## Pipeline snapshots and stubs

- **[MUST]** Capture both output paths and stable content, excluding ignored nondeterminism. Remove the
  Nextflow/pipeline version key from version artifacts before snapshotting.
- **[MUST]** Snapshot named output areas separately. Use semantic extraction for formats with unstable bytes;
  do not leave a superseded snapshot strategy commented beside the active one.
- **[MUST]** Choose one explicit pipeline stub strategy and apply it consistently: either duplicate scenarios
  with full stub snapshots or drive stubs from scenario data with deliberately narrowed file-tree assertions.
- **[MUST]** The download-pipeline workflow independently exercises the packaged pipeline stub path with its
  configured non-stub fallback.

## Cache-boundary refactors

- **[MUST]** A refactor that changes a scientific-stage cache boundary records positive and negative two-run
  evidence. The unchanged rerun must resume the intended work and preserve output cardinality and order; a
  rerun with a changed identity input must rerun the affected work while preserving the required cardinality and
  order of its assembled result.

## CI policy

- **[MUST]** Pipeline nf-test CI shards changed tests across the supported runtime profiles and pinned/current
  Nextflow versions, then uses an explicit fan-in job to fail the workflow when a required shard fails.
- **[MUST]** CI-shaped workflows cancel superseded runs through concurrency. Repository-sensitive publishing,
  cloud, mutation, or cleanup jobs use the appropriate repository guard and least required permissions.
- **[MUST]** Pin third-party actions to immutable commit SHAs with readable version comments; use the same pin
  across sibling workflows and never a mutable `@main` or `@master` ref. An nf-core-maintained action may use
  the project's accepted release-tag policy.
- **[MUST]** Pipeline lint uses the `nf-core` version declared by the repository mechanism and adds release
  validation only for the release base.
