# Result: Issue 17 LDAK HE and PCGC routes

Accepted:

- Separate pipeline aliases preserve the reusable subworkflow's one-estimator contract and allow one
  analysis to request REML, HE and PCGC together.
- Shared relatedness preparation runs once per matrix key and fans out to all selected estimators.
- Covariate-bearing HE/PCGC routes run matrix adjustment; a no-covariate HE route bypasses it.
- Categorical factors are treatment-coded into a numerical adjustment design because live LDAK 6
  rejects `--factors` in `--adjust-grm` mode.
- HE, PCGC and REML publish complete native outputs in separate method-token directories.

Rejected:

- Passing the raw categorical file to `LDAK_ADJUSTGRM`: rejected by the shipped LDAK binary.
- Suppressing `--factors` without representing categorical effects: statistically incomplete.
- Changing the reusable subworkflow to accept a multi-estimator list: unnecessary interface expansion;
  aliases keep each invocation single-purpose.

Verification:

- New public route test: 2/2 real and stub scenarios passed.
- Existing LDAK REML/reuse tests: 10/10 passed across two shards.
- PLINK/normalisation suite: all functional scenarios passed across three shards; the one expected
  versions snapshot was refreshed and its shard then passed.
- `git diff --check`: clean.

Remaining risk:

- Full sharded and sequential snapshot validation is deferred to the final integrated issue-18/19 gate.
