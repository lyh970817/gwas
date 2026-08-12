# AGENTS.md

## Collaboration constraints

Recommend designs on their merits. Do not discount a design because implementation or refactoring mistakes may
be introduced; assume testing and review can catch them later.

Ask for the user's explicit approval before deciding to patch an existing programme's source code.

Choose the model family and reasoning effort for each subagent task according to its difficulty.

## Repository identity

This is an `nf-core/gwas` pipeline checkout. `.references/modules` is a reference-only companion checkout of
`nf-core/modules`, not an upstream submission workspace; do not treat this repository or its `master` branch as
a component-library fork.

Pipeline coding standards are routed by `CODING_STANDARDS.md`. For modules and subworkflows intended for
upstream `nf-core/modules`, the applicable `nf-core-*` skills under `.agents/skills/` are authoritative.

The LDAK, GWASLab, GCTA, PLINK, and PLINK 2 modules and subworkflows under `modules/local/` and
`subworkflows/local/` are upstream-bound candidates despite their local paths. Keep atomic components free of
pipeline routing and scientific policy; those belong in composition or the relevant `conf/modules/*.config`.

## Local fixture boundary

`.references/test-datasets-gwas` is a read-only, machine-local fixture checkout. Never hard-code it in pipeline
code or make CI depend on it. Use a private copy for modified fixtures. The `gwas-pipeline-test` skill owns the
local fixture resolver and nf-test procedure.
