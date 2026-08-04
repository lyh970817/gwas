# Peripheral polish research and implementation

## Goal

Research, design, implement, and verify the approved nf-core/gwas peripheral-polish work in this independent worktree.

## Success Criteria

- Every implementation area has a focused comparison against Sarek, MAG, and RNA-seq, with official-source fallback only where local references are insufficient.
- Accepted practices are distilled under `results/` before implementation begins.
- Correct stale Tower report metadata, enable default MultiQC branding, tailor the Methods Description and executed-tool citations, add a route diagram, add troubleshooting guidance, and add a compact run-level MultiQC summary table.
- Add `lyh970817` as a contributor using the supplied email where contributor metadata supports it.
- Add a useful path-specific CODEOWNERS file only if repository ownership evidence supports exact entries.
- Create local Markdown issues for deferred QQ/heritability reporting, screenshots/public result presentation, and release metadata.
- Preserve the dirty primary checkout and make all changes only on `codex/peripheral-polish-20260804`.
- Run targeted formatting/config/tests, broad validation in proportion to the changed runtime surface, and an independent review.

## Current Context

- Worktree: `.worktrees/peripheral-polish-20260804`
- Base: committed `HEAD` `a6bea17`; primary checkout contains unrelated user changes.
- Pipeline already has standard email, completion, docs, MultiQC, schema, and report machinery; this is enhancement and cleanup, not template reconstruction.

## Constraints

- Do not implement QQ plots, heritability report panels, screenshots, public benchmark narratives, or final release/DOI metadata in this run.
- Do not invent ownership, publication identifiers, screenshots, or scientific summaries unsupported by emitted data.
- Research precedes implementation. Subagents write research results only; the root agent integrates and edits production files.
- Pipeline-specific policy stays outside atomic upstream-candidate module command construction.
- Do not commit, push, publish, or modify external systems.

## Risks

- MultiQC custom-content syntax and data shape may be version-sensitive.
- A summary table can accidentally imply scientific interpretation or rely on unavailable fields.
- Tool citation generation must reflect executed routes and remain deterministic.
- Diagram and documentation can drift from actual route wiring.
- Tracker files are ignored and require careful local-only handling.

## Approval Required

No additional approval is required for scoped edits and verification in this clean worktree. Commit, push, PR creation, deletion, publication, or external tracker changes remain outside authorization.

## Work Packets

1. Tower report metadata practice.
2. MultiQC branding practice.
3. Methods Description and executed-tool citation practice.
4. Workflow/metromap diagram practice.
5. Troubleshooting/user-guide practice.
6. MultiQC run-summary table design and data-source audit.
7. Contributor metadata and CODEOWNERS practice.
8. Local issue format and deferred-work decomposition.
9. Integration implementation after packets 1-8 are accepted.
10. Independent standards/spec review and verification.

## Integration Policy

Accept practices supported by at least one relevant reference and compatible with current repository standards. Where references disagree, prefer the newer pattern documented by `CODING_STANDARDS.md`; verify version-sensitive MultiQC behavior against official documentation. Reject decorative parity that has no truthful GWAS data source or user benefit.

## Verification

- Validate YAML, JSON, Markdown links/assets, and Nextflow configuration.
- Exercise the focused MultiQC-producing test surface and inspect the rendered custom content where feasible.
- Run `nf-core pipelines lint .` and the repository's relevant nf-test gates; broaden to the documented sharded suite if runtime changes warrant it.
- Run workflow-artifact completeness verification and an independent review subagent.

## Reusable Artifacts

The accepted research distillations under this workflow's `results/` and a compact final report; no transcripts or secrets.
