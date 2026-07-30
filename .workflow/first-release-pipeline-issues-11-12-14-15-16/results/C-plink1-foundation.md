# Packet C shared PLINK 1 derivative

Status: committed and green.

Commits:

- `17bafd73e9d02404c2e66bdbe347154231ea53a0` —
  `Prepare PLINK 1 bundles for LDAK routes`
- `146b0cda5415bf91cfc376e2c9e83b4c36fb7e6b` —
  `Prepare PLINK 1 bundles for GCTA LDMS`

Implemented:

- Vendored the authoritative `PLINK2_MAKEBED` component byte-identically.
- Added `PREPARE_COHORT_GENOTYPES.out.plink1_genotypes` with public shape
  `[meta, bed, bim, fam]`.
- Preserved focal analysis metadata.
- Lazily converts the canonical PLINK 2 bundle once per cohort only when an
  LDAK association/heritability method or GCTA GREML-LDMS needs PLINK 1, then
  fans the result back to all requesting analyses.
- Establishes the one shared derivative consumed by Issues 12, 14, and 16.

TDD evidence:

- Red: new public-output/trace assertions failed because the output was empty
  and `PLINK2_MAKEBED` count was zero.
- Green: the focused `prepare_cohort_genotypes` Docker test passed all three
  tests in 26.205 seconds.
- Focused Nextflow lint, configured pre-commit checks, and `git diff --check`
  passed.
- After adding the GCTA LDMS selector, the same focused suite remained green at
  three of three tests and all format/pre-commit/diff checks passed.

Files:

- `modules/local/plink2/makebed/{environment.yml,main.nf,meta.yml}`
- `subworkflows/local/prepare_cohort_genotypes/{main.nf,meta.yml}`
- `subworkflows/local/prepare_cohort_genotypes/tests/main.nf.test`
