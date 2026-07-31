# Validation result

Status: complete with one documented transient

Verification:

- Pipeline lint before: 516 passed / 7 ignored / 10 warnings / 0 failed.
- Pipeline lint after: 520 passed / 7 ignored / 10 warnings / 0 failed.
- Ticket #30 focused Docker tests: ADDGRMS 2/2, BIVARIATEREMLLDMS 4/4,
  GAWK 8/8.
- GCTA component: lint 27/0/0, direct Docker 7/7, two-run Docker wrapper
  passed.
- LDAK component: lint 35/0/0, direct Docker 6/6, two-run Docker wrapper
  passed; review-corrected direct Docker rerun 6/6.
- Full pipeline sharded suite: 119/119 passed, 3/3 shards.
- Full pipeline serial audit: 118/119 passed. One prepared-genotype snapshot
  mismatched transiently.
- Immediate complete focused rerun of `tests/prepared_genotypes.nf.test`: 4/4
  passed in 252.524 seconds without code or snapshot changes.
- No obsolete snapshot entries were reported across the serial run and the
  clean focused audit of the one affected file.

Remaining risk:

- The prepared-genotype snapshot exhibited one nondeterministic mismatch and
  should be tracked as a suite-stability concern if it recurs.
