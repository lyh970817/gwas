# Result: Integrated issues 17, 18 and 19

Accepted:

- All three ticket implementations and their tracker updates.
- Test-only deterministic PCGC seeding after broad validation exposed stochastic content snapshots.
- Lint-generated RO-Crate synchronization after the README rewrite.

Rejected:

- Treating PCGC's varying standard-error bytes as a product regression.
- Inventing a fifth save control or claiming that `sample_prevalence` is already consumed.
- Propagating the incorrect GWASLab DOI from component metadata into user documentation.

Conflict resolution:

- A parallel broad run intermittently failed while Nextflow reflected over `TaskTemplateEngine`.
  The same 28-test file had already passed, the isolated 40-test shard retry passed, and the complete
  119-test sequential run passed. This is recorded as a parallel-engine flake, not a pipeline defect.

Final changes:

- LDAK HE and PCGC routes with covariate-aware matrix adjustment and shared kinship reuse.
- Fast routine and complete full-scale test profiles with portable fixtures and cross-route tests.
- First-release README, usage, output and citation documentation.
- Reproducible PCGC snapshots, versions provenance snapshots and synchronized RO-Crate metadata.

Remaining risks:

- Four documented implementation/spec discrepancies require separate scope decisions.
- Release lint retains ten pre-existing warnings for template/release maintenance.
