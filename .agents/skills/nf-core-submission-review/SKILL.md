---
name: nf-core-submission-review
description: Audit a planned or implemented nf-core module or subworkflow for standards conformance. Use for component portfolios, designs, interfaces, worktrees, branches, PRs, metadata/test consistency, or submission readiness.
---

# Review a component submission

Canonical component topics indexed by `CODING_STANDARDS.md` own stable rules. The lifecycle skills own the
procedures, gates, and evidence being audited.

## Review execution

1. Build a checklist from the target: component boundary, module or subworkflow contract, GWAS conventions,
   packages/containers, fixtures/tests, contribution boundary, and public PR procedure.
2. Run an independent review subagent when available. Ask it to prioritize bugs, standard violations,
   cross-file contract mismatches, fixture risks, missing profiles, and public blockers.
3. For an implementation, compare `main.nf`, `meta.yml`, environment/config files, tests, and snapshots as one
   contract. For a design, mark code-only checks as later gates rather than defects.
4. Confirm that actual submission work is in a focused writable component-library worktree.
5. Do not perform broad rewrites during a review unless the user asked for fixes.

For unresolved upstream detail, consult the relevant `docs/nf-core-standards/` topic. Lead the report with
findings ordered by severity and cite files/lines. Then list open questions, test gaps, and blockers; add a brief
change summary only when useful.
