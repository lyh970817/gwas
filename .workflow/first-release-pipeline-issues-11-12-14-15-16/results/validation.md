# Validation result

Status: complete at
`7554a56728f1fa12b0e8935e9ce5183db590f194`.

## Earlier failed broad run and remediation

The first exact broad attempt at the pre-remediation integrated head completed
106/115 with nine failures and controller exit 1. Its evidence was retained
rather than overwritten:

- Two legacy sheets used non-default GCTA construction values on rows that did
  not request GREML-LDMS.
- Four software-version snapshots had not yet incorporated the new route
  components.
- The default harmonisation test still expected the former PLINK2-only route
  topology.
- A tiny GREML-LDMS fixture required a test-only unconstrained override while
  production and dedicated route behavior remained constrained.
- KVIK harmonisation exposed a real canonical-header defect: its native
  association table could not itself supply unambiguous EAF and effective N.

Commits `67fc975`, `2cd6be9`, `bfab3a2`, `cee2071`, `48d6e65`, and the final
reviewed baseline snapshot delta `7554a56` remedied those failures. Focused
tests were rerun before repeating the complete broad suite.

## Completed

- Integrated focused regression selection: 52/52 passed.
- Dedicated LDAK-KVIK route suite after canonical EAF/N remediation: 8/8
  passed.
- Exact `test_regenie` umbrella profile: passed with Docker through its
  portable registered-profile alias.
- Exact `test_ldak` umbrella profile: passed with Docker through its portable
  registered-profile alias.
- Complete integration range: `git diff --check` passed.
- Independent two-axis review: Standards PASS and Spec PASS with no unresolved
  blocking findings.
- Dynamic-workflow artifact verifier: passed structurally while preserving the
  workflow's in-progress completion state.
- Exact fixture-backed three-shard suite: 116/116 passed, controller exit 0:
  - shard 1: 39/39 in 1059.785 seconds;
  - shard 2: 39/39 in 891.065 seconds;
  - shard 3: 38/38 in 1051.647 seconds.

## Sequential stale-snapshot audit

### Attempt 1: online

- The online serial attempt stopped after 77 completed tests: 67 passed, 10
  failed before workflow launch because of TLS dependency-resolution errors,
  and 39 were not run.
- None of the 10 failures was a code assertion or snapshot assertion failure.
- Evidence:
  `/tmp/codex-gwas-serial-attempt1-online.log`.

### Attempt 2: decisive supported-offline run

- The supported offline serial run completed all 116 tests.
- Result: 116/116 passed, controller exit 0, duration 1914.496 seconds.
- The complete output contains no obsolete snapshot warnings or obsolete
  snapshot labels; no stale entry requires removal.
- Evidence:
  `/tmp/codex-gwas-serial-attempt2-offline.log`.

## Validation conclusion

All required focused, exact umbrella, broad-shard, two-axis review, and
sequential stale-snapshot gates are complete and green. The earlier broad
failure and the TLS-limited online serial attempt remain recorded as
superseded diagnostic evidence rather than being erased.
