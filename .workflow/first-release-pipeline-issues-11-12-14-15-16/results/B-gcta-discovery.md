# Packet B discovery

Status: blocked on public-contract resolution.

Accepted:

- Issue 14 needs the established GCTA LDMS composition plus its two custom
  helpers, deterministic stratum order, MGRM order, matrix-key fan-out, native
  `.hsq` publication, and a real independent Docker profile.
- Issue 15 installs `gcta/fastgwa`, invokes it inline, keeps focal analysis
  metadata separate from sparse-matrix identity, runs MLM only, preserves
  native `.fastGWA`, and feeds the result into GWASLab with populated `N`.
- Preserve matrix kinds `gcta_dense`, `gcta_ldms`, and `gcta_sparse`;
  construction settings belong in their respective keys.
- Preserve one-to-many routing with `combine(by: 0)`.

Contract blockers:

- The frozen 31-column samplesheet has no per-row
  `gcta_ld_score_region_kb`, `gcta_ld_bins`, or `gcta_sparse_cutoff`, although
  Issues 14 and 15 require same-run rows with different values to fork matrix
  builds.
- Issue 14 says `gcta_ld_bins` belongs in the reuse key, but also asks
  conflicting bin counts on an otherwise-identical key to fail. Those
  conditions cannot both be true. Scientifically distinct bin counts must
  create distinct keys/builds.

Recommended resolution:

- Expand the public row contract with the three GCTA settings and replace the
  contradictory conflict criterion with a distinct-build criterion.

Focused tests:

- `tests/heritability_gcta_greml_ldms.nf.test`
- `tests/association_gcta_fastgwa.nf.test`
- `tests/relatedness_matrix.nf.test`
- utility function tests
