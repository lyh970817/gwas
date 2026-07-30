# Packet A discovery

Status: ready after the shared PLINK 1 derivative seam is owned by Packet C.

Accepted:

- Vendor the established `plink_fit_regenie`, `plink_gwas_regenie`, and
  `plink_association_ldak_kvik` compositions from the named sibling component
  revision; keep atomic module interfaces unchanged.
- Add route-level seams in `tests/association_regenie.nf.test` and
  `tests/association_ldak_kvik.nf.test`.
- Prove native and GWASLab-harmonised results, method-specific publication,
  selector/default behavior through generated commands, and genuinely
  independent `test_regenie`/`test_ldak` profiles.
- Treat the live 22-autosome fixture as authoritative over Issue 11's stale
  three-autosome wording.
- Packet C owns the single lazy PLINK 1 derivative used by both LDAK-KVIK and
  LDAK heritability.

Open implementation decision:

- Start KVIK with the composition's single merged PLINK 1 bundle and use the
  real route test to establish native result cardinality. Do not manufacture
  chromosome-specific conversions unless the public contract or observed tool
  behavior requires them.

Highest shared surfaces:

- `workflows/gwas.nf`, `nextflow.config`, `nextflow_schema.json`,
  `conf/modules/ldak.config`, `docs/output.md`, `CHANGELOG.md`, and broad
  snapshots.

Focused tests:

- `tests/association_regenie.nf.test`
- `tests/association_ldak_kvik.nf.test`
- `tests/input_validation.nf.test`
- `tests/summary_statistics.nf.test`
