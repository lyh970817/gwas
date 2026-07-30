# Final Report: Issues 17 18 19 first release

## Outcome

Implementation, integration, validation and two-axis review are complete.

## Accepted Results

- Issue 17: separate LDAK HE and PCGC routes with conditional adjustment and shared kinship reuse.
- Issue 18: routine and full-scale profiles, portable assets and cross-route pipeline coverage.
- Issue 19: live first-release usage, output, README and citation documentation.

## Rejected Results

- Raw categorical `--factors` on LDAK matrix adjustment, which the live LDAK 6 binary rejects.
- A nonexistent fifth save control and unsupported claims for `sample_prevalence`.
- Nondeterministic PCGC content snapshots without a test-only seed.

## Conflicts Resolved

- Categorical covariates are treatment-coded into the numerical matrix-adjustment design.
- PCGC uses a documented random seed only under nf-test.
- One Nextflow parallel reflection failure was isolated by a green shard retry and complete serial run.

## Verification Evidence

- Focused issue-17 routes: 2/2; existing LDAK suites: 10/10.
- Default profile: passed in 21.548 seconds.
- Full-scale all-route profile: passed in 55.371 seconds and in later integration runs.
- Sharded suite: 119/119 across the final green shard results.
- Sequential snapshot audit: 119/119 in 2299.147 seconds; no obsolete snapshots.
- Release lint: 516 passed, 0 failed.
- Standards review: four initial findings fixed; reviewer confirmed the axis is clean.
- Specification review: the REGENIE `MLOG10P` contract was corrected; reviewer confirmed tickets
  17–19 are clean.
- `git diff --check`: clean.

## Remaining Risks

- The live implementation has four save controls while the old spec says five.
- `sample_prevalence` is metadata-only.
- GWASLab component metadata carries an incorrect DOI.
- Validation failures do not publish a quality-control report.
- Release lint retains ten existing warnings for template/version maintenance.

## Reusable Follow-up

- Correct or formally resolve the four documented spec/implementation discrepancies in separate
  tickets.
- Address the remaining release-template lint warnings before the release cut.

## Integration Decisions

Accepted:

- All results recorded under `results/`.
- Test-only deterministic PCGC seeding and generated RO-Crate synchronization.
- All final review fixes.

Rejected:

- Inventing behavior for unresolved release-spec gaps.
- Treating the one-off Nextflow reflection failure as a pipeline defect after isolated and sequential
  reruns passed.

Conflicts:

- None remain within tickets 17–19.

Remaining risks:

- The two broader release-spec gaps and the known metadata/lint maintenance items listed above.

Verification still needed:

- None for tickets 17–19.
