# Issues 17 18 19 first release

## Goal

Complete the remaining first-release implementation gate (issue 17), then complete the independent
test-profile and documentation tracks (issues 18 and 19) in parallel.

## Success Criteria

- Issue 17's five acceptance criteria pass and are committed before issues 18 and 19 start.
- Issues 18 and 19 satisfy every acceptance criterion without crossing their assigned ownership.
- The fixture-backed focused tests, three-shard suite, and sequential stale-snapshot audit are green.
- A two-axis review finds no unresolved standards or specification defects.
- The current branch contains intentional commits only; user-owned `.claude-scratch/` is untouched.

## Current Context

- Branch: `claude`; fixed review point: `a3ec63d`.
- Tracker: `.scratch/first-release-pipeline/issues/{17,18,19}-*.md`.
- Canonical spec: `.scratch/first-release-pipeline/spec.md`.
- Issue 17 blocks both later tickets. Issues 18 and 19 are independent after it lands.
- The local fixture checkout is `/home/andongni/Yandex.Disk/Projects/Research/qc_dev/test-datasets-gwas`.

## Constraints

- Use ticket/spec-declared pipeline and published-output seams for TDD.
- Keep the upstream fixture URL as the tracked default; never commit the machine-local fixture path.
- Follow `CODING_STANDARDS.md`; direct reference-pipeline evidence resolves unwritten details.
- Preserve concurrent/user-owned changes and do not touch `.claude-scratch/`.
- Commit issue 17 before delegating issues 18 and 19.

## Risks

- LDAK `--adjust-grm` may reject categorical `--factors`; verify against the actual container.
- Issue 18 can expose fixture or stale-snapshot gaps rather than implementation defects.
- Issue 19 must describe observed output contracts, not anticipated filenames or directories.
- Shared files such as ticket status files are integration-owned to prevent concurrent conflicts.

## Approval Required

None. The user explicitly authorized implementation, commits, subagents, and parallel work. No
destructive, external, publishing, or credential-bearing action is planned.

## Work Packets

- `17-ldak-routes`: root-owned blocking implementation and focused validation.
- `18-test-profiles`: delegated after issue 17; owns configuration, pipeline tests, and test fixtures.
- `19-documentation`: delegated after issue 17; owns user-facing documentation and citations.
- `review-standards` and `review-spec`: read-only parallel final review packets.

## Integration Policy

Issue 17 lands as its own commit. The issue 18 and 19 workers edit the shared checkout concurrently but
have non-overlapping file ownership and do not commit. Root reviews and integrates both result sets,
owns tracker/status edits, and commits coherent ticket-level changes. Conflicts are resolved against the
ticket, spec, documented standards, then reference pipelines in that order.

## Verification

Run narrow ticket tests first. At the end run `nf-test-parallel 3 --verbose` with
`GWAS_TEST_FIXTURES`, then the sequential `nf-test test --profile=+docker --verbose` snapshot audit.
Also run `git diff --check`, relevant lint/format checks, workflow-artifact verification, and the
two-axis review from `a3ec63d`.

## Reusable Artifacts

Retain packet prompts, integrated results, and the final report under this workflow directory; do not
store bulky command logs or fixture data.
