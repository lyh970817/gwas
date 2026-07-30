# Packet A: Association routes

Packet ID: A-association

Objective: Implement Issues 11 and 12 together with test-first vertical slices.

Files / sources:

- `.scratch/first-release-pipeline/issues/11-regenie-association-route.md`
- `.scratch/first-release-pipeline/issues/12-ldak-kvik-association-route.md`
- Issue 10 implementation and tests
- `CODING_STANDARDS.md`, relevant topic standards, ADRs, and reference pipelines

Ownership: Association-specific workflow, config, tests, snapshots, and docs.
Shared route/dispatch/schema files may be changed only when required and must be
listed explicitly.

Do: derive every acceptance criterion; confirm issue-defined route seams; work
red to green; run focused tests; commit coherent changes; write a result record.

Do not: change GCTA heritability or LDAK REML behavior; revert concurrent work;
hard-code local fixture paths; push.

Expected output: committed implementation plus
`results/A-association.md` containing requirements coverage, files changed,
commands/results, overlap notes, risks, and commit IDs.

Verification: focused Issue 11/12 route tests with `GWAS_TEST_FIXTURES` and
Docker, plus format/diff checks.
