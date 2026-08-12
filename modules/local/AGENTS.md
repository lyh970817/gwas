# Local modules

LDAK, GWASLab, GCTA, PLINK, and PLINK 2 families here are upstream-bound atomic candidates and must follow the
canonical module, GWAS-contract, container, fixture, and component-test standards indexed by
`CODING_STANDARDS.md`. Use the corresponding `nf-core-*` skills for task procedure.

Attribute adapters, `normalise_phenotypes`, and `custom/` helpers are pipeline-owned unless an approved design
establishes a portable component contract. Pipeline-owned modules may implement pipeline semantics; do not
transfer those semantics into an upstream-bound atom.

Pipeline nf-test discovery of a local module is regression coverage, not proof of component-submission
readiness. Run component submission validation in the writable `nf-core/modules` submission worktree.
