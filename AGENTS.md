# AGENTS.md

## Collaboration constraints

Recommend designs on their merits. Do not discount a design because implementation or refactoring mistakes may
be introduced; assume testing and review can catch them later.

Ask for the user's explicit approval before deciding to patch an existing programme's source code.

Choose the model family and reasoning effort for each subagent task according to its difficulty.

## Repository identity and routing

This is an `nf-core/gwas` pipeline checkout. `.references/modules` is a read-only companion checkout of
`nf-core/modules`, not a submission workspace or an ancestry source for this repository's branches.

[`CODING_STANDARDS.md`](CODING_STANDARDS.md) indexes the canonical tracked standards. Skills under
`.agents/skills/` own task procedures, gates, evidence, and reporting; they do not override stable contracts in
the canonical standards.

Before changing a governed subtree, read every `AGENTS.md` from this root through the closest containing
directory. A task started at the repository root must discover and apply descendant instructions before acting
in that subtree.

Repository-local agent guidance and development infrastructure are personal-only. Use `dual-track-commit` for
any commit or synchronization task that may mix those changes with the portable pipeline or a public PR.

## Upstream-bound local components

The LDAK, GWASLab, GCTA, PLINK, and PLINK 2 modules and reusable subworkflows under `modules/local/` and
`subworkflows/local/` are upstream-bound candidates despite their local paths. Keep portable atomic components
free of pipeline routing, scientific policy, publication, and reuse identity; the descendant instructions route
the exact boundary.

## Local fixture safety

`.references/test-datasets-gwas` is read-only machine-local state. Never hard-code it in tracked code or make CI
depend on it. Use a private copy for modified fixtures. The live resolver mechanisms own exact source
resolution; `gwas-pipeline-test` owns test selection, execution, evidence, and reporting.

Automatic `.references/test-datasets-gwas` discovery is personal-track behavior. A portable upstream PR
checkout uses the public remote fallback unless `GWAS_FIXTURE_SOURCE` is explicitly supplied. Run local
compact-fixture benchmarks on the personal track, or explicitly pin and verify the local source.
