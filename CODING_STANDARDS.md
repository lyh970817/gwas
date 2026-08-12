# Coding standards — nf-core/gwas

This file routes pipeline-level review to the normative topic files. Component-contract scope and precedence are
defined in `AGENTS.md`; the applicable `nf-core-*` skills own those rules.

## Topics

| File                                                                                                     | Covers                                                                                 |
| -------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| [`docs/coding-standards/nextflow-code-style.md`](docs/coding-standards/nextflow-code-style.md)           | Pipeline `.nf` and Groovy layout, naming, channels, workflows, diagnostics, and style |
| [`docs/coding-standards/configuration-and-schema.md`](docs/coding-standards/configuration-and-schema.md) | Configuration, parameters, schema, assets, and `.nf-core.yml`                         |
| [`docs/coding-standards/ci-and-testing.md`](docs/coding-standards/ci-and-testing.md)                     | Pipeline nf-test, CI, lint/format tooling, and repository hygiene                     |
| [`docs/coding-standards/documentation-and-assets.md`](docs/coding-standards/documentation-and-assets.md) | Public documentation, assets, citations, changelog, and scripts                       |

## Severity

- **[MUST]** — a violation is a review finding.
- **[SHOULD]** — a strong default; flag an unexplained deviation.
- **[TOOLING]** — a formatter or linter owns the rule. Report evidence that the tool was not run, not each
  mechanically repairable instance.

Topic evidence markers record the reference-pipeline basis: `(all three)`, `(2/3)`, or `(1/3 — chosen)`. A
chosen rule is a deliberate pipeline decision and remains binding.

## Precedence and provenance

Apply the user's current request, then `AGENTS.md`, active `nf-core-*` skills for upstream-bound components,
and these pipeline topic files. Consult the ignored cache under `docs/nf-core-standards/` only through the
fallback described by the active skill.

These topics were derived on 2026-07-27 from `.references/rnaseq` (template 3.26.0), `.references/sarek`
(template 3.9.0), and `.references/mag` (template 5.4.2). Where the references disagree because a convention is
migrating, the topic records the selected newer form. Where a topic already decides a point, it takes precedence
over a contrary example in a reference checkout.
