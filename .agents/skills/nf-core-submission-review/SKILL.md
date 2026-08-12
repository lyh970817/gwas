---
name: nf-core-submission-review
description: Audit a planned or implemented nf-core module or subworkflow for standards conformance. Use for component portfolios, design issues, specifications, interface proposals, worktrees, branches, PRs, metadata/test consistency, or submission readiness.
---

Read `../references/nf-core-guidance-sources.md`. This skill owns review execution and output; the routed
lifecycle skills own the rules being audited.

Use this skill when work is about to settle an nf-core component portfolio or public contract, or when the
user asks for a review of a module, subworkflow, worktree, branch, PR, or work-in-progress change intended for
upstream `nf-core/modules`. For design-only work, apply every checklist item that can be evaluated before code
exists and report the remainder as implementation gates.

## Standards cache fallback

If fallback is needed, relevant topic hints are:

- Modules: `docs/nf-core-standards/module-file-structure.md`, `module-main-nf.md`, `module-meta-yml.md`, `module-testing.md`, `module-containers.md`.
- Subworkflows: `docs/nf-core-standards/subworkflows.md`, `module-testing.md`.
- All submissions: `docs/nf-core-standards/test-datasets.md`, `contributing-prs.md`.

## Review execution

- Run the review in an Agent tool subagent (e.g. `general-purpose` or `Explore`) where available. If subagent tools are unavailable, state that and review directly.
- Ask the reviewer to prioritise bugs, standards violations, metadata/test mismatches, fixture risks, missing profiles, and PR blockers.
- Do not perform broad rewrites during a review unless the user explicitly asks for fixes.
- Check whether the target is in a focused submission worktree. Flag deviations that can affect upstream submission hygiene.

## Review routing

Build one checklist from the target and audit each owner directly:

- `nf-core-component-design` for an unresolved portfolio or interface proposal;
- `nf-core-module-create` for atomic process boundaries, `main.nf`, metadata, and module contract consistency;
- `nf-core-subworkflow-create` for reusable composition, identity flow, routing, and take/emit consistency;
- `nf-core-gwas-module-conventions` for GWAS/population-genetics tuples, selectors, identity, and versions;
- `nf-core-containers` for package and container provenance;
- `nf-core-fixtures` for fixture reuse and companion test-data work;
- `nf-core-submission-test` for tests, snapshots, lint, and runtime profiles;
- `nf-core-submission-pr` for reviewer-facing branch and PR hygiene.

For an implementation, compare `main.nf`, `meta.yml`, environment/config files, tests, and snapshots as one
contract. Report each deviation against the owning skill rather than restating that skill's rules here. For a
design, mark code-only checks as later gates instead of treating their absence as a defect.

## Output format

Lead with findings, ordered by severity. Use file and line references when possible. Then list open questions, test gaps, and a brief change summary only if useful.
