# Orchestration: Tickets 30 and 27 implementation

## Execution Rules

- Keep the original objective intact.
- Ask for approval before risky, expensive, external, or destructive actions.
- Keep immediate blocking work local.
- Delegate only bounded, disjoint, materially useful packets.
- Integrate packet results before final verification.

## Branching Rules

1. Capture pre-change pipeline lint and focused-test behavior.
2. Create GCTA and LDAK branches/worktrees from committed
   `../modules:gwas/integration` HEAD, never from the dirty working tree.
3. Run P30, P27-GCTA, and P27-LDAK concurrently because ownership is disjoint.
4. Each packet uses a vertical red-green slice where a behavioral test changes:
   demonstrate the missing/broken behavior, make the minimum scoped change,
   then rerun the focused test.
5. Do not merge the component branches. Integrate by checking each packet
   against its ticket contract and preserving independent commits.
6. After implementation, run independent spec and standards review. Correct
   accepted findings in the owning worktree and reverify.

## Packet Prompts

### P30

- Objective: remove retired PLINK 1 association/VCF component artifacts and
  repair both stale `GCTA_MAKEGRMPART` setup paths.
- Ownership: pipeline paths for the two retired components and the two named
  nf-test files only, plus ticket status/report artifacts after success.
- Do not: alter PLINK2 behavior, current routes, or unrelated vendored modules.
- Output: scoped diff, baseline comparison, focused test evidence, commit hash.

### P27-GCTA

- Objective: add focused negative tests for GREML-LDMS without MGRM and GREML
  with MGRM.
- Ownership: `subworkflows/nf-core/grm_heritability_gcta/tests/` only.
- Do not: change joins, runtime code, positive/stub assertions, or other
  components.
- Output: scoped diff, lint/test evidence, focused commit hash.

### P27-LDAK

- Objective: add the unsupported-estimator negative test and make `meta.yml`
  document the exact executable output tuples.
- Ownership: `subworkflows/nf-core/grm_heritability_ldak/meta.yml` and
  `tests/`.
- Do not: change joins, runtime output shapes, estimator routing, or other
  components.
- Output: scoped diff, lint/test evidence, focused commit hash.

### REVIEW

- Objective: review each diff against its ticket and applicable repository or
  nf-core standards.
- Ownership: read-only review; report findings with file/line evidence.
- Output: accepted/rejected findings and required corrections.

## Completion Audit

- Confirm all acceptance criteria directly from tree/diffs and command results.
- Confirm no packet contains unrelated user changes.
- Confirm three independent commits exist on the intended branches.
- Record skipped or environment-blocked broad checks explicitly.
- Run `collect_results.py` and `verify_workflow.py`.
