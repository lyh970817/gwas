# Orchestration: First release pipeline issues 11 12 14 15 16

## Execution Rules

- Keep the original objective intact.
- Ask for approval before risky, expensive, external, or destructive actions.
- Keep orchestration and conflict decisions in the root agent.
- Delegate only bounded, disjoint, materially useful packets.
- Integrate packet results before final verification.
- Workers are not alone in the repository: preserve unrelated changes, never
  revert another worker's edits, and report shared-file overlap immediately.

## Branching Rules

- Pin the pre-wave fixed point before implementation.
- Start A, B, and C concurrently after a read-only ownership/status preflight.
- If the main worktree is clean, create isolated worktrees from the fixed point
  so each stream can commit without racing on the shared index.
- If pre-existing changes overlap a stream, stop that stream's edits and return
  an overlap report for an integration decision.
- Do not start broad validation until A, B, and C have focused green evidence
  and their commits have been integrated.
- Land the F schema-foundation commit into schema-dependent B and C slices
  before they implement per-row settings. A must not independently rewrite the
  public row contract.
- Do not accept snapshot changes without matching public-output or
  generated-command evidence.
- Review the combined committed diff against the pinned fixed point. Remediate
  findings, rerun affected focused tests, then repeat the relevant review axis.

## Packet Prompts

### F-schema-foundation

Expand the public row contract once from 31 to 35 columns with
`gcta_ld_score_region_kb`, `gcta_ld_bins`, `gcta_sparse_cutoff`, and optional
`ldak_weights`. Own schema, samplesheet, shared field parsing/defaults,
method-conditioned validation, and focused public input/function tests. Provide
portable path information for later content-derived weights identity, but do
not implement route-specific matrix keys.

### A-association

Implement Issues 11 and 12 as one vertical-slice stream. Read the issues,
relevant ADRs, coding standards, Issue 10 outputs, and nearby/reference route
tests. Work red-to-green at the issue-defined route seams. Own
association-specific route/config/test/doc files. Avoid unrelated GCTA
heritability and LDAK REML surfaces. Commit focused changes and write a result
with requirements, files, commands, results, shared-file overlaps, and commit
IDs.

### B-gcta-matrix

Implement Issues 14 and 15 as one coordinated matrix-family stream. Read the
issues, relevant ADRs, coding standards, Issue 10/13 contracts, and
nearby/reference route tests. Preserve matrix identity and ordering through
GREML-LDMS and fastGWA-MLM. Work red-to-green at route seams. Own GCTA-specific
route/config/test/doc files. Commit focused changes and write the standard
result record.

### C-ldak-heritability

Implement Issue 16 as the LDAK heritability stream. Read the issue, relevant
ADRs, coding standards, Issue 04/13 contracts, and authoritative current
pipeline-local LDAK components. Work red-to-green at the route seam. Own
LDAK-relatedness/REML-specific route/config/test/doc files. Treat historical
`filterrelatedness` references as suspect and distinguish code defects from
host-capacity failures. Commit focused changes and write the standard result
record.

### I-integration

Integrate A, B, and C from the pinned fixed point. Reconcile shared imports,
dispatch, config, schema, docs, and snapshots by acceptance criteria. Run all
five focused route tests. Record accepted/rejected changes, conflicts,
decisions, remaining risks, and the resulting commit graph.

### V-validation

From the integrated branch, independently run diff checks, Nextflow
format/lint, relevant pipeline lint, the fixture-backed three-shard suite, and
the required sequential obsolete-snapshot audit. Do not edit except for
deliberately confirmed stale snapshots assigned back through remediation.

### R-review

Pin the fixed point and run the code-review skill's Standards and Spec axes in
parallel. Standards uses `CODING_STANDARDS.md`, relevant topic files, and the
skill's smell baseline. Spec uses all five issue files. Return separate reports
without reranking them.

## Completion Audit

- All five issue acceptance lists mapped to implementation and test evidence.
- Stream commits integrated without unrelated changes.
- Focused and broad verification recorded.
- Standards and Spec findings resolved or explicitly accepted by the user.
- Workflow artifacts complete and verified.
- Logical commits present on the current branch; no push performed.
