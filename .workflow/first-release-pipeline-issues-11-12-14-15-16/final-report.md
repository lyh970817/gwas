# Final Report: First release pipeline issues 11 12 14 15 16

## Outcome

Implementation, integration, focused validation, and two-axis review are
complete at
`7554a56728f1fa12b0e8935e9ce5183db590f194`. The fixture-backed three-shard
suite and decisive supported-offline sequential audit are green. The
implementation and verification work is complete, and `claude` has been
fast-forwarded to this exact reviewed head with post-fast-forward integration
divergence `0/0`. This artifact and the issue records are captured together in
the same records-only archival commit atop that implementation head.

## Accepted Results

- All three coordinated streams are integrated on one shared 35-column input
  contract.
- REGENIE, LDAK-KVIK, GCTA GREML-LDMS, GCTA fastGWA MLM/MLM-binary, and LDAK
  relatedness/REML routes are implemented with route-level real/stub coverage.
- The integration result, conflict decisions, remediation history, and review
  disposition are recorded under `results/`.

## Rejected Results

- No 31-column compatibility shim.
- No path- or basename-derived LDAK weights identity.
- No acceptance of provisional snapshot drift without matching behavior
  evidence.
- No quantitative-only limitation for fastGWA: genuine binary Docker evidence
  now proves native and canonical `BETA`/`N`.

## Conflicts Resolved

- Shared schema, route dispatch, configuration, documentation, and snapshot
  changes were integrated as coherent commits.
- LDMS identity includes bin count; distinct counts create distinct builds.
- Test-only handling for tiny GCTA fixtures does not alter constrained
  production or dedicated route behavior.
- LDAK-KVIK native output remains unchanged; canonical EAF and effective N come
  from its explicit companion summary joined by Predictor and alleles.

## Verification Evidence

- Focused integrated selection: 52/52 passed.
- LDAK-KVIK canonical regression suite: 8/8 passed.
- Exact Docker umbrella profiles `test_regenie` and `test_ldak`: passed.
- Standards review: PASS, zero unresolved hard findings.
- Spec review: PASS, zero unresolved findings.
- Three-shard fixture-backed suite: 116/116, controller exit 0.
  - shard 1: 39/39 in 1059.785 seconds;
  - shard 2: 39/39 in 891.065 seconds;
  - shard 3: 38/38 in 1051.647 seconds.
- Sequential audit attempt 1, online: stopped after 77 completed; 67 passed,
  10 TLS prelaunch failures, 39 not run, and no code/snapshot assertion
  failures. Log: `/tmp/codex-gwas-serial-attempt1-online.log`.
- Decisive supported-offline sequential audit: 116/116, exit 0, 1914.496
  seconds, with no obsolete snapshot warnings or labels. Log:
  `/tmp/codex-gwas-serial-attempt2-offline.log`.
- Dynamic-workflow artifact structural verifier: PASS.
- Exact target-branch implementation landing: PASS; `claude` contains
  `7554a56728f1fa12b0e8935e9ce5183db590f194`, the post-fast-forward divergence
  from the reviewed integration branch was `0/0`, and the records-only archival
  commit follows it.
- Archival records: PASS; the finalized workflow artifact and issue records are
  captured in the same records-only archival commit atop the reviewed
  implementation head.

## Remaining Risks

No known implementation, Standards, Spec, focused-test, broad-test, or
snapshot-audit risk remains. No completion or archival gate is pending.
Protected unrelated `.claude-scratch/` content remains unchanged.

## Reusable Follow-up

No further local workflow action is required. No push was performed; any future
publication remains separately authorized.
