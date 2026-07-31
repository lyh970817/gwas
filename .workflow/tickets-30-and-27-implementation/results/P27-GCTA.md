# P27-GCTA result

Status: complete

Accepted:

- Added two focused negative tests for `greml_ldms` without an MGRM manifest
  and `greml` with an MGRM manifest.
- Retained runtime code, all four strict joins, positive/stub tests, the
  existing unsupported-selector test, and snapshots unchanged.

Verification:

- Direct Docker nf-test: 7/7 passed in 118.368 seconds after the second slice.
- `nf-core subworkflows lint grm_heritability_gcta`: 27 passed, 0 warnings,
  0 failures.
- `nf-core subworkflows test grm_heritability_gcta --profile docker`: passed
  both stability runs.
- `git diff --check` and pre-commit checks: passed.

Commit:

- `66fae019f9d5d5265142fb3210ffa9202191da10`
  (`Test GCTA estimator and MGRM pairing guards`)

Worktree:

- `/home/andongni/Yandex.Disk/Projects/Research/qc_dev/modules/.worktrees/modules/grm-heritability-gcta-hygiene`
