# Local subworkflows

Reusable LDAK, GCTA, PLINK, PLINK 2, and REGENIE compositions here are upstream-bound candidates and must follow
the canonical subworkflow, GWAS-contract, fixture, and component-test standards indexed by
`CODING_STANDARDS.md`. Use the corresponding `nf-core-*` skills for task procedure.

An upstream-bound subworkflow must provide meaningful multi-step composition. Do not create one whose only
computation is a single module invocation. Every computational dependency it composes must be an
upstream-prepared module or reusable subworkflow that satisfies the applicable component standards. Those
dependencies may still be prepared local candidates rather than already merged upstream, but submission
readiness covers the complete dependency graph.

`route_*`, `fit_mph_reml`, `prepare_cohort_genotypes`, `prepare_relatedness_matrices`,
`prepare_relationship_traits`, and `utils_nfcore_gwas_pipeline` own pipeline routing, reuse identity,
relational-input policy, or pipeline utilities. They are not component-library submission candidates and must not appear in the dependency graph of
an upstream-bound subworkflow. Keep their policy out of reusable compositions.
`prepare_relationship_traits` in particular owns relationship de-duplication and endpoint resolution against
the prepared phenotypes, so it is measured against pipeline architecture rather than the reusable-composition
contract.

Pipeline nf-test discovery of a local subworkflow is regression coverage, not proof of component-submission
readiness. Run component submission validation in the writable `nf-core/modules` submission worktree.
