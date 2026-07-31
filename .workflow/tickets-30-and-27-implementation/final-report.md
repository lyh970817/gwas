# Final Report: Tickets 30 and 27 implementation

## Outcome

Ticket #30 is implemented on the pipeline `claude` branch. Ticket #27 is
implemented as independent GCTA and LDAK component-library branches/worktrees.
Both local tracker records are reconciled to `done`.

## Accepted

- Removed the retired pipeline-local PLINK 1 association and VCF components.
- Preserved PLINK1 input conversion and current PLINK2 VCF conversion.
- Repaired the four stale GCTA MakeGRMPart test setup paths.
- Installed the missing pinned upstream GAWK setup dependency after an
  execution-first failure proved it was required by the existing bivariate
  test.
- Added both missing GCTA estimator/MGRM negative tests.
- Added the missing LDAK unsupported-selector negative test, strengthened after
  review to assert the exact guard message.
- Corrected all LDAK output metadata one-for-one against executable emissions.
- Preserved all twelve strict joins and runtime tuple contracts unchanged.

## Rejected

- No shared join helper: the repeated strict flags protect different local
  identity transitions and the components must remain independently
  submit-able.
- No GCTA test helper for two explicit invalid-contract cases: readability and
  scenario independence outweigh a small amount of fixture repetition.
- No pipeline-local edits to the pinned GAWK component merely to satisfy a
  non-gating current component-lint diagnostic; its Docker suite and required
  pipeline lint are green.

## Commits

Pipeline:

- `a29114ac73f126ef1ea77e846a7913df88187483` — remove retired PLINK
  components and repair GCTA setup paths.
- `be6508e11bc6f8122b61adc8b055de2e2a83d728` — install the GAWK test
  dependency and record the changelog/provenance.

Component library:

- GCTA `66fae019f9d5d5265142fb3210ffa9202191da10` — add estimator/MGRM
  guard tests.
- LDAK `bfc1a88f1dc13edb06d4bcb00e0d301b11f34165` — correct output
  metadata and add unsupported-selector coverage.
- LDAK `ab385b5227be6bbd2a450c34eaeb5bb7675f298b` — require the exact
  selector guard failure after review.

## Verification

- Pipeline lint: 516 passed / 7 ignored / 10 warnings / 0 failed before;
  520 / 7 / 10 / 0 after.
- GCTA installed-component tests: ADDGRMS 2/2 and BIVARIATEREMLLDMS 4/4.
- GAWK installed-component tests: 8/8.
- GCTA subworkflow: lint 27/0/0; direct Docker 7/7; two-run Docker wrapper
  passed.
- LDAK subworkflow: lint 35/0/0; direct Docker 6/6; two-run Docker wrapper
  passed; post-review direct Docker 6/6.
- Full pipeline three-shard suite: all 119 tests passed, 3/3 shards.
- Full sequential stale-snapshot audit: 118/119 passed in 2288.185 seconds.
  `--save_prepared_genotypes publishes one bundle per prepared cohort` had one
  transient snapshot mismatch despite its semantic assertions and pipeline run
  succeeding. The same case had passed in the sharded suite, and an immediate
  complete focused rerun of `tests/prepared_genotypes.nf.test` passed 4/4 in
  252.524 seconds with no code or snapshot change. No obsolete snapshots were
  reported across the sequential run plus the clean focused file audit.

## Remaining risks

- `nf-core modules lint gawk` reports one warning and one failure against the
  exact pinned upstream component (`containers` metadata and `ext.suffix`).
  This is non-gating for ticket #30: the installed component's Docker tests
  pass 8/8 and the required pipeline lint has zero failures.
- The component branches intentionally retain their existing dependency
  ancestry from `gwas/integration`; making either upstream-PR-ready beyond
  these focused changes remains out of scope.
- One nondeterministic prepared-genotype snapshot mismatch occurred during the
  119-test serial audit. It is unrelated to the touched files, passed in the
  sharded run and on immediate full-file rerun, and should remain visible as a
  test-stability caveat rather than being silently described as a clean first
  serial pass.

## Outcome

## Accepted Results

## Rejected Results

## Conflicts Resolved

## Verification Evidence

## Remaining Risks

## Reusable Follow-up
