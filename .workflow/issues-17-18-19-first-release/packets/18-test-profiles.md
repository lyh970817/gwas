# Packet 18: Test profiles and pipeline coverage

Objective: Complete every acceptance criterion in issue 18 after issue 17 lands.

Context: Consolidate the fast default, expensive-route profiles, full-scale multi-chromosome profile,
and cross-route pipeline assertions. The upstream test-data URL remains the committed default, with
`GWAS_TEST_FIXTURES` supplying local development data.

Files / sources: issue 18, first-release spec testing decisions, `conf/test*.config`,
`nextflow.config`, pipeline-level `tests/`, fixture resolver/config, relevant schemas/assets.

Ownership: The worker owns configuration and pipeline-test files only. Root owns tracker files,
workflow artifacts, docs, commits, and cross-packet integration edits.

Do: Inspect before editing; work in ticket-declared public seams; run focused profile/tests regularly;
report exact verification and any fixture gaps. Adapt to concurrent issue-19 changes.

Do not: Edit `docs/`, `README.md`, `CITATIONS.md`, `.scratch/`, `.workflow/`, `.claude-scratch/`,
or run `git commit`. Do not revert any concurrent edits.

Expected output: Direct edits in owned files plus a concise result report with tests and remaining risks.

Verification: Individually runnable profiles under Docker, pipeline assertions, no tracked local path,
focused nf-test runs, `git diff --check` on owned files.
