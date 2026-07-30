# Packet C discovery

Status: default/equal-weight route ready; complete ticket blocked on weights
contract.

Accepted:

- Vendor `plink2/makebed`, `plink_prepare_grm_ldak`, and
  `grm_heritability_ldak` from the authoritative live component sources and
  repoint only local include paths.
- Packet C owns the one lazy PLINK 1 derivative consumed by both Issues 12 and
  16.
- Use matrix kind `ldak_kinship`, construction settings model/power/weights,
  and keep relatedness filtering outside the base key.
- Build one full-cohort kinship, derive filtered `filter` + `subgrm` output only
  when requested, and fan filtered/unfiltered bundles back to focal analyses.
- Never restore historical `filterrelatedness`; live `filter` and `subgrm` are
  authoritative.
- Prove native REML, liability output, filtered/unfiltered reuse, model/power
  forks, method-specific publication, and preflight prevalence behavior.

Contract blocker:

- The frozen 31-column samplesheet has no LDAK weights field, while Issue 16
  requires weights in the key and a same-run changed-weights route test.
- Equal/default weights can be represented honestly with a canonical sentinel,
  but custom weights require an explicit public field and a portable identity
  rule.

Recommended resolution:

- Either expand the row contract with a weights-file field whose key identity
  is content-derived, or amend Issue 16 to equal/default weights only for the
  first release. Do not use basename-only or absolute-path identity.

Focused tests:

- `tests/heritability_ldak_reml.nf.test`
- `tests/relatedness_matrix.nf.test`
- `tests/input_validation.nf.test`
- utility function tests
