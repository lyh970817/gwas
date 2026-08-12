# Pipeline tests

`tests/**` is pipeline route, relational-input, resume, and integration coverage. Apply
[`docs/coding-standards/ci-and-testing.md`](../docs/coding-standards/ci-and-testing.md) and use
`gwas-pipeline-test` for fixture resolution and execution.

These tests may exercise local components end to end, but a green pipeline suite is not component-submission
readiness evidence. Colocated module and subworkflow tests inherit their component subtree instructions and use
`nf-core-submission-test` for upstream validation.
