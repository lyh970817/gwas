# First release pipeline issues 11 12 14 15 16

## Goal

Implement the next unblocked first-release wave as three coordinated streams:

- Association: Issues 11 and 12.
- GCTA/matrix family: Issues 14 and 15.
- LDAK heritability: Issue 16.

Integrate the streams into the current branch, prove their route contracts with
focused and broad tests, review the combined diff against both repository
standards and the issue specifications, fix actionable findings, and commit the
completed wave.

## Success Criteria

- Every acceptance criterion in Issues 11, 12, 14, 15, and 16 is implemented.
- The public test seams are the route-level nf-test entrypoints and their
  emitted files, metadata, version topics, and generated commands named by the
  issue contracts. Those issue-defined seams are treated as pre-agreed by the
  request to implement the tickets.
- Each stream has focused green tests or a precisely evidenced environmental
  blocker; the integrated three-shard fixture-backed suite is green.
- The required sequential stale-snapshot audit is run after the green sharded
  suite and confirmed stale entries are handled deliberately.
- `nextflow lint`/format and relevant pipeline lint checks pass for touched
  files, subject to documented local tool limitations.
- A two-axis Standards and Spec review finds no unresolved blocking issues.
- Intended changes are recorded in logical commits on the current branch.

## Current Context

- Repository: `/home/andongni/Yandex.Disk/Projects/Research/qc_dev/gwas`.
- Current branch: `claude`.
- Pinned pre-wave fixed point:
  `21b5576da6f77d23e579bf0ed7140250280a5439`.
- Issue source: `.scratch/first-release-pipeline/issues/`.
- Completed prerequisites: Issues 10 and 13; Issue 05 is superseded for Issue
  15 as stated by the user.
- The user authorized expanding the frozen 31-column public row contract. This
  wave therefore introduces a 35-column contract with per-row
  `gcta_ld_score_region_kb`, `gcta_ld_bins`, `gcta_sparse_cutoff`, and optional
  `ldak_weights`.
- Local fixtures: `/home/andongni/Yandex.Disk/Projects/Research/qc_dev/test-datasets-gwas`,
  supplied through `GWAS_TEST_FIXTURES` only and never hard-coded.
- Canonical code standards: `CODING_STANDARDS.md` plus the reference pipelines
  when the written standard is silent.

## Constraints

- The root agent orchestrates, routes, and synthesizes; subagents perform
  exploration, edits, verification, and review.
- Preserve unrelated user changes and never revert another stream's work.
- The tracked tree was clean at preflight, but `.claude-scratch/` contains 24
  unrelated untracked files and this run contributes seven untracked
  `.workflow/` files; never stage with `git add -A`.
- Use isolated worktrees for implementation streams if the current worktree or
  shared-file ownership makes direct concurrent edits unsafe.
- Keep pipeline-local integration distinct from upstream component-library
  work; do not change sibling repositories unless an issue explicitly requires
  copying an already-authoritative component.
- Use canonical domain vocabulary from the issue register and relevant ADRs.
- Do not push, publish a PR, or modify external systems in this workflow.

## Risks

- All three streams may touch route dispatch, configuration, schema, docs, or
  snapshots; integration must resolve these shared surfaces deliberately.
- Matrix identity and ordering contracts from Issue 13 are inputs to Issues 14,
  15, and 16 and must not be re-derived inconsistently.
- LDAK setup can be memory-heavy; validation failures must distinguish code
  defects from evidenced host-capacity limits.
- Snapshot updates can conceal behavior drift; review generated commands and
  stable public outputs before accepting snapshot changes.

## Approval Required

No additional approval gate. The user explicitly authorized the five local
issues, three parallel work streams, testing, review, and commits. Destructive
Git operations, external writes, pushes, and publication remain out of scope.

## Work Packets

- `F-schema-foundation`: expand and validate the public row contract once,
  before schema-dependent stream slices.
- `A-association`: discover, test-first implement, and focused-verify Issues 11
  and 12.
- `B-gcta-matrix`: discover, test-first implement, and focused-verify Issues 14
  and 15.
- `C-ldak-heritability`: discover, test-first implement, and focused-verify
  Issue 16.
- `I-integration`: integrate stream commits, reconcile shared files, and run
  integrated focused checks.
- `V-validation`: independently run formatting/lint, sharded fixture-backed
  tests, and the sequential stale-snapshot audit.
- `R-review`: run parallel Standards and Spec reviews from the pinned pre-wave
  fixed point; remediation is a separate packet if findings are actionable.

## Integration Policy

- Each implementation stream owns only files needed by its issue cluster and
  reports every shared file it changes.
- Prefer commits per coherent route cluster. Cherry-pick or otherwise integrate
  only reviewed stream commits; never overwrite shared files wholesale.
- Resolve disagreements from the issue text, then `CODING_STANDARDS.md`, then
  the three reference pipeline checkouts.
- For Issue 14, differing LD-bin counts create distinct matrix keys/builds.
  The earlier same-key conflict wording is internally impossible because bin
  count is scientific matrix identity; update the ticket accordingly.
- LDAK weights-file identity in reuse keys is content-derived, never basename-
  only or absolute-path-derived.
- Record accepted changes, rejected proposals, conflicts, decisions, and
  remaining risks in `results/integration.md` and `final-report.md`.

## Verification

- Narrow first: issue-specific nf-test files with `GWAS_TEST_FIXTURES` and
  `+docker`, plus generated-command assertions where behavior is not visible in
  outputs.
- Format/lint touched Nextflow and configuration surfaces.
- Broad: `nf-test-parallel 3 --verbose` when available, otherwise three native
  shards with distinct workdirs.
- After a green sharded run: sequential
  `nf-test test --profile=+docker --verbose` for obsolete snapshot reporting.
- Run the workflow artifact completeness checker before completion.

## Reusable Artifacts

The run directory itself is the reusable recipe for future route waves:
`.workflow/first-release-pipeline-issues-11-12-14-15-16/`.
