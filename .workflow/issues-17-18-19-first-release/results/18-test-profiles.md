# Result: Issue 18 test profiles and pipeline coverage

Accepted:

- The default profile uses a committed one-chromosome samplesheet and runs only PLINK 2, GWASLab
  and GCTA GREML under the routine resource ceiling.
- The full-scale profile uses the committed 22-autosome fixture and exercises all four association
  methods and all five heritability estimators.
- Existing route-specific profiles remain independently runnable for REGENIE, LDAK and GREML-LDMS.
- Pipeline tests cover cohort fan-out, relatedness reuse, construction-setting conflicts, resume
  reuse, and the four live intermediate-save controls.
- Fixture resolution remains portable: tracked assets use the upstream test-datasets URL, while
  local runs substitute `GWAS_TEST_FIXTURES` at runtime.

Verification:

- Default profile: 1/1 passed in 21.548 seconds.
- Full-scale profile: 1/1 passed in 55.371 seconds during implementation and passed repeatedly
  during integration.
- Relatedness-matrix suite: 6/6 passed.
- Prepared-genotype suite: 4/4 passed twice independently after deterministic PCGC test seeding.
- Integrated sharded matrix: 119/119 passed (40 + 40 + 39); shard 1 required an isolated retry
  after one Nextflow `TaskTemplateEngine` reflection failure.
- Sequential snapshot audit: 119/119 passed in 2299.147 seconds with no obsolete snapshots.
- `nf-core pipelines lint`: 516 passed, 0 failed.

Integration decision:

- Pin LDAK PCGC's documented random seed only in test configuration because its standard-error
  calculation is stochastic. Production defaults remain unchanged.
