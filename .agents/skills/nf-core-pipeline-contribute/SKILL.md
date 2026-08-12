---
name: nf-core-pipeline-contribute
description: Prepare a contribution to this existing nf-core/gwas pipeline, including component installation/wiring, schema or method configuration, public docs, pipeline lint/tests, and a PR targeting dev. Do not use for submitting a component to nf-core/modules.
---

# Contribute to the pipeline

Read
[`contribution-boundaries.md`](../../../docs/coding-standards/contribution-boundaries.md) and the applicable
pipeline topics indexed by `CODING_STANDARDS.md`. Apply `dual-track-commit` before commit or branch
synchronization in this repository.

## Procedure

1. Resolve or claim the public pipeline issue when required and create a descriptive PR branch from the
   applicable public base in the contribution standard.
2. Install components with `nf-core modules install <component>` or
   `nf-core subworkflows install <component>` so `modules.json` records provenance; do not hand-copy installed
   components.
3. Wire inputs and outputs in pipeline composition. Put per-process extension arguments, prefixes, resources,
   and publication in the relevant method-family `conf/modules/*.config`, not the installed component.
4. Surface parameters through `nextflow_schema.json` with the current schema builder and update public docs for
   user-visible behavior.
5. Add the required `CHANGELOG.md` entry under the current development/unreleased section using this pipeline's
   established format.
6. Run the changed route through the pipeline test procedure and run `nf-core pipelines lint`; add a direct
   smoke run when the change warrants it.
7. Apply `dual-track-commit`, update against the current public base using the authorized synchronization mode,
   and prepare the PR with the pipeline's live template and the canonical public reviewer boundary.
8. Request review only after the required CI and local gates are green and the user authorizes the external
   action.

Report repository, branch and target, installed/wired components, schema/config/docs/changelog changes,
fallback topics consulted, exact smoke/lint/nf-test results, CI state, and skipped tests or profiles.
