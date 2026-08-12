# Local subworkflows

Reusable LDAK, GCTA, PLINK, PLINK 2, and REGENIE compositions here are upstream-bound candidates and must follow
the canonical subworkflow, GWAS-contract, fixture, and component-test standards indexed by
`CODING_STANDARDS.md`. Use the corresponding `nf-core-*` skills for task procedure.

`route_*`, `prepare_cohort_genotypes`, `prepare_relatedness_matrices`, and `utils_nfcore_gwas_pipeline` own
pipeline routing, reuse identity, relational-input policy, or pipeline utilities and are not component-library
submission candidates. Keep that policy out of reusable compositions.

Pipeline nf-test discovery of a local subworkflow is regression coverage, not proof of component-submission
readiness. Run component submission validation in the writable `nf-core/modules` submission worktree.
