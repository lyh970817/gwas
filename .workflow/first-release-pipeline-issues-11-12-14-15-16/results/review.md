# Combined Standards and Spec review

Status: PASS on both independent axes.

Review fixed point:
`21b5576da6f77d23e579bf0ed7140250280a5439`.

Current integrated head:
`7554a56728f1fa12b0e8935e9ce5183db590f194`.

## Standards

Result: PASS.

- The decisive standards review found zero unresolved hard findings.
- Route tests use registered configuration profiles, immutable 35-column input
  sheets, grouped assertions, uniform real/stub pairing, and labelled
  path/content snapshots.
- Configuration banners are normalized, method-specific controls stay on their
  intended surfaces, and the shared workflow preserves focal and matrix
  identity.
- A standalone `nextflow lint` invocation cannot parse two executable GCTA
  configuration fragments outside their pipeline configuration context. This
  was adjudicated as a command-mode limitation rather than a documented
  standards violation; the fragments are exercised through the pipeline and
  route tests.

## Specification

Result: PASS.

- Issues 11 and 12 cover the REGENIE and LDAK-KVIK association routes,
  selectors, native/canonical outputs, deterministic configuration, and
  publication contracts.
- Issues 14 and 15 cover GCTA LDMS matrix construction/reuse, ordered strata
  and MGRM input, GREML-LDMS, fastGWA MLM and MLM-binary, and canonical
  `BETA`/`N` mapping.
- Issue 16 covers LDAK kinship construction, content-derived supplied weights,
  equal weights, filtering, reuse/fork behavior, REML, and liability output.
- The authorized 35-column input expansion supplies the route settings that
  could not be represented by the former 31-column contract.

## Findings disposition

All actionable findings from earlier passes were remediated and retested.
There are no accepted exceptions and no unresolved blocking Standards or Spec
findings. The final reviewed head includes the baseline KVIK summary snapshot
delta required by the exact broad run.
