# Packet C: LDAK heritability route

Packet ID: C-ldak-heritability

Objective: Implement Issue 16 test-first from relatedness preparation through
LDAK REML.

Files / sources:

- `.scratch/first-release-pipeline/issues/16-ldak-relatedness-matrix-preparation-and-ldak-reml-route.md`
- Issue 04 and 13 implementations/tests
- Current pipeline-local LDAK components
- `CODING_STANDARDS.md`, relevant topic standards, ADRs, and reference pipelines

Ownership: LDAK relatedness/REML-specific workflow, config, tests, snapshots,
and docs. Shared route/dispatch/schema files may be changed only when required
and must be listed explicitly.

Do: derive every acceptance criterion; work red to green at the route seam;
verify matrix identity/order and selector behavior; run focused tests; commit
coherent changes; write a result record.

Do not: restore historical `filterrelatedness`; change association or GCTA
route behavior; revert concurrent work; hard-code local fixtures; push.

Expected output: committed implementation plus
`results/C-ldak-heritability.md` with coverage, files, commands/results,
overlaps, risks, and commit IDs.

Verification: focused Issue 16 route test with `GWAS_TEST_FIXTURES` and Docker,
plus format/diff checks. Report proven host-capacity limits separately.
