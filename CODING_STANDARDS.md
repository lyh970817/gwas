# Coding standards — nf-core/gwas

This file indexes the canonical tracked standards. The `AGENTS.md` chain selects the applicable scope; skills
own task procedure, gates, evidence, and reporting rather than stable contracts.

## Topics

| File                                                                                                     | Covers                                                                                 |
| -------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| [`docs/coding-standards/nextflow-code-style.md`](docs/coding-standards/nextflow-code-style.md)           | Pipeline `.nf` and Groovy layout, naming, channels, workflows, diagnostics, and style |
| [`docs/coding-standards/configuration-and-schema.md`](docs/coding-standards/configuration-and-schema.md) | Configuration, parameters, schema, assets, and `.nf-core.yml`                         |
| [`docs/coding-standards/ci-and-testing.md`](docs/coding-standards/ci-and-testing.md)                     | Pipeline nf-test, CI, lint/format tooling, and repository hygiene                     |
| [`docs/coding-standards/documentation-and-assets.md`](docs/coding-standards/documentation-and-assets.md) | Public documentation, assets, citations, changelog, and scripts                       |
| [`docs/coding-standards/contribution-boundaries.md`](docs/coding-standards/contribution-boundaries.md) | Repository/workspace identity, personal/public tracks, and reviewer-facing boundaries |
| [`docs/coding-standards/nf-core-modules.md`](docs/coding-standards/nf-core-modules.md) | Atomic upstream-bound module contracts |
| [`docs/coding-standards/nf-core-subworkflows.md`](docs/coding-standards/nf-core-subworkflows.md) | Reusable upstream-bound composition contracts |
| [`docs/coding-standards/gwas-component-contracts.md`](docs/coding-standards/gwas-component-contracts.md) | GWAS/population-genetics tuple, identity, selector, and bundle contracts |
| [`docs/coding-standards/component-containers.md`](docs/coding-standards/component-containers.md) | Component packages, runtime directives, and container metadata |
| [`docs/coding-standards/component-fixtures-and-testing.md`](docs/coding-standards/component-fixtures-and-testing.md) | Component fixture, assertion, snapshot, and readiness contracts |

## Severity

- **[MUST]** — a violation is a review finding.
- **[SHOULD]** — a strong default; flag an unexplained deviation.
- **[TOOLING]** — a formatter or linter owns the rule. Report evidence that the tool was not run, not each
  mechanically repairable instance.

Topic evidence markers record the reference-pipeline basis: `(all three)`, `(2/3)`, or `(1/3 — chosen)`. A
chosen rule is a deliberate pipeline decision and remains binding.

## Precedence and provenance

Apply the user's current request, the `AGENTS.md` chain for the target, these canonical topics, and the active
skill's task procedure. Consult the ignored cache under `docs/nf-core-standards/` only through the fallback in
the active skill. If current upstream requirements conflict with a canonical contract, update the owning topic
deliberately rather than allowing skill prose or an example to override it.

These topics were derived on 2026-07-27 from `.references/rnaseq` (template 3.26.0), `.references/sarek`
(template 3.9.0), and `.references/mag` (template 5.4.2). Where the references disagree because a convention is
migrating, the topic records the selected newer form. Where a topic already decides a point, it takes precedence
over a contrary example in a reference checkout.
