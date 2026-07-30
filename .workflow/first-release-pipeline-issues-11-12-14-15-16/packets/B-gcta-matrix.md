# Packet B: GCTA matrix-family routes

Packet ID: B-gcta-matrix

Objective: Implement Issues 14 and 15 together while preserving the Issue 13
matrix-family contract.

Files / sources:

- `.scratch/first-release-pipeline/issues/14-gcta-greml-ldms-route.md`
- `.scratch/first-release-pipeline/issues/15-gcta-fastgwa-mlm-association-route-wiring.md`
- Issue 10 and 13 implementations/tests
- `CODING_STANDARDS.md`, relevant topic standards, ADRs, and reference pipelines

Ownership: GCTA-specific workflow, config, tests, snapshots, and docs. Shared
route/dispatch/schema files may be changed only when required and must be listed
explicitly.

Do: derive every acceptance criterion; work red to green at route seams;
preserve matrix identity/order; run focused tests; commit coherent changes;
write a result record.

Do not: change REGENIE/KVIK or LDAK REML behavior; revert concurrent work;
hard-code local fixture paths; push.

Expected output: committed implementation plus
`results/B-gcta-matrix.md` with coverage, files, commands/results, overlaps,
risks, and commit IDs.

Verification: focused Issue 14/15 route tests with `GWAS_TEST_FIXTURES` and
Docker, plus format/diff checks.
