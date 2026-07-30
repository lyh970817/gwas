# Packet C equal/default-weight LDAK REML route

Status: committed and green; custom-weights slice remains.

Commit:

- `172e8ce7d7daa90524669059ee4e7bb9fa98032d` —
  `feat(heritability): add LDAK REML route`

Evidence:

- Utility function suite passed 19/19 offline after a transient remote-config
  failure.
- Matrix suite passed 2/2:
  - shared filter: one MAKEBED, one CALCKINS, one FILTER, one SUBGRM, two REML;
  - model/power fork: two CALCKINS, no FILTER/SUBGRM, two REML with distinct
    keys.
- Liability/publication suite passed 1/1 with non-empty `.reml` and
  `.reml.liab` outputs plus LDAK versions.
- Pre-commit, formatter/lint, and diff checks passed.
- Stream-local Standards and Spec reviews passed after adding local
  subworkflow headers, removing obsolete versions emits in favor of process
  topic reporting, and isolating the test-only matrix-save setting.

Next:

- Integrate F and add SHA-256 content-derived custom-weight identity, equal
  sentinel, same-content/different-path reuse, and
  same-basename/different-content fork coverage.
