# Orchestration: Issues 17 18 19 first release

## Execution Rules

- Keep the original objective intact.
- Ask for approval before risky, expensive, external, or destructive actions.
- Keep immediate blocking work local.
- Delegate only bounded, disjoint, materially useful packets.
- Integrate packet results before final verification.

## Branching Rules

- Gate A: issue 17 must be focused-green and committed before either parallel packet starts.
- If LDAK's live container rejects `--factors`, correct the vendored module contract within issue 17.
- After Gate A, spawn exactly two implementation workers with disjoint ownership.
- Workers report discoveries that require cross-owned changes; root performs those integration edits.
- If a focused failure reproduces at `a3ec63d`, classify it as baseline evidence before changing scope.
- Full verification begins only after both parallel packets have been integrated.
- Standards and spec reviews run in parallel against `a3ec63d...HEAD`.

## Packet Prompts

- See `packets/17-ldak-routes.md`.
- See `packets/18-test-profiles.md`.
- See `packets/19-documentation.md`.
- Final reviewers receive the fixed diff command, commit list, standards sources, and ticket/spec sources.

## Completion Audit

- Every ticket criterion is checked against code or test evidence.
- Packet results are synthesized into accepted/rejected/conflict decisions.
- All required tests and audits are recorded in `final-report.md`.
- `state.json` and workflow completeness validation agree that the run is complete.
