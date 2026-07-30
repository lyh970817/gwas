# Result: Final standards and specification review

Standards axis:

- Initial review found four actionable items: missing full-scale content hashes, a success assertion
  outside `assertAll`, tool-link placement in output documentation, and missing `def` declarations
  for stub-local fragments.
- All four were corrected and the reviewer confirmed no remaining finding.

Specification axis:

- Initial review found one ticket-scoped documentation error: REGENIE harmonised output was described
  as carrying `P`, while the live GWASLab mapping produces `MLOG10P`.
- The documentation now distinguishes REGENIE's `MLOG10P` from the other methods' `P`, and the
  reviewer confirmed the finding is resolved.
- The fifth save control and published validation reports remain broader release-spec gaps owned by
  issue 20 or a formal specification amendment; they are not acceptance failures for tickets 17–19.

Post-fix verification:

- Full-scale content-snapshot test: 1/1 passed.
- HE/PCGC real and stub test: 2/2 passed.
- `docs/output.md` Prettier check: passed.
- `nf-core pipelines lint`: 516 passed, 0 failed.
- Both reviewers confirmed their ticket-scoped axes are clean.
