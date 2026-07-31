# Integration Checklist: tickets-30-and-27-implementation

## P27 Gcta

# P27-GCTA result
Accepted:
- Added two focused negative tests for `greml_ldms` without an MGRM manifest
- Retained runtime code, all four strict joins, positive/stub tests, the
Verification:
- Direct Docker nf-test: 7/7 passed in 118.368 seconds after the second slice.
- `nf-core subworkflows lint grm_heritability_gcta`: 27 passed, 0 warnings,
- `nf-core subworkflows test grm_heritability_gcta --profile docker`: passed
- `git diff --check` and pre-commit checks: passed.
- `66fae019f9d5d5265142fb3210ffa9202191da10`
- `/home/andongni/Yandex.Disk/Projects/Research/qc_dev/modules/.worktrees/modules/grm-heritability-gcta-hygiene`

## P27 Ldak

# P27-LDAK result
Accepted:
- Added one focused negative test for the unsupported `ldak_reml` estimator.
- Removed the fictitious standalone `meta` output from `meta.yml`.
- Documented exactly 12 emitted channels: 11 metadata-bearing result tuples and
- Retained runtime code, all eight strict joins, positive/stub tests, and
Verification:
- Red seam: the new test using valid `reml` executed successfully and failed
- Direct Docker nf-test after switching to `ldak_reml`: 6/6 passed in 141.186
- `nf-core subworkflows lint grm_heritability_ldak --passed`: 35 passed,
- Docker wrapper: passed both stability runs after retrying one transient
- Targeted pre-commit checks: passed.
- `bfc1a88f1dc13edb06d4bcb00e0d301b11f34165`
- `ab385b5227be6bbd2a450c34eaeb5bb7675f298b`
- `/home/andongni/Yandex.Disk/Projects/Research/qc_dev/modules/.worktrees/modules/grm-heritability-ldak-hygiene`

## P30

# P30 result
Accepted:
- Removed the retired `modules/local/plink/gwas` and
- Preserved PLINK1 input conversion through `PLINK2_MAKEPGEN` and VCF
- Repaired all four `GCTA_MAKEGRMPART` setup paths.
- Execution exposed a second missing setup dependency; installed the pinned
- Added the required unreleased changelog entry after standards review.
Verification:
- `GCTA_ADDGRMS`: 2/2 Docker tests passed.
- `GCTA_BIVARIATEREMLLDMS`: 4/4 Docker tests passed.
- Installed GAWK component: 8/8 Docker tests passed.
- Pipeline lint baseline: 516 passed, 7 ignored, 10 warnings, 0 failed.
- Pipeline lint after: 520 passed, 7 ignored, 10 warnings, 0 failed.
- Exact-name/path searches and `git diff --check`: passed.
- Non-gating current component lint reports one warning and one failure in the
- `a29114ac73f126ef1ea77e846a7913df88187483`
- `be6508e11bc6f8122b61adc8b055de2e2a83d728`

## Review

# Review integration
## Standards
Accepted:
- P30 needed an unreleased `CHANGELOG.md` entry. Corrected before commit.
- P27-LDAK's initial negative test asserted only generic failure. Corrected in
Rejected:
- Possible duplication between the two new GCTA negative test setups. The
## Spec
found after corrections. Runtime verification supplies the lint/test evidence

## Validation

# Validation result
Verification:
- Pipeline lint before: 516 passed / 7 ignored / 10 warnings / 0 failed.
- Pipeline lint after: 520 passed / 7 ignored / 10 warnings / 0 failed.
- Ticket #30 focused Docker tests: ADDGRMS 2/2, BIVARIATEREMLLDMS 4/4,
- GCTA component: lint 27/0/0, direct Docker 7/7, two-run Docker wrapper
- LDAK component: lint 35/0/0, direct Docker 6/6, two-run Docker wrapper
- Full pipeline sharded suite: 119/119 passed, 3/3 shards.
- Full pipeline serial audit: 118/119 passed. One prepared-genotype snapshot
- Immediate complete focused rerun of `tests/prepared_genotypes.nf.test`: 4/4
- No obsolete snapshot entries were reported across the serial run and the
Remaining risk:
- The prepared-genotype snapshot exhibited one nondeterministic mismatch and

## Integration Decisions

Accepted:

Rejected:

Conflicts:

Remaining risks:

Verification still needed:
