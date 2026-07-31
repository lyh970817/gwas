# Tickets 30 and 27 implementation

## Goal

Implement and commit pipeline ticket #30 in the `gwas` checkout, and implement
component-library ticket #27 as two independently submit-able GCTA and LDAK
changes in dedicated sibling-repository worktrees.

## Success Criteria

- Retired pipeline-local `PLINK_GWAS` and `PLINK_VCF` component artifacts are
  removed without disturbing PLINK 1 input conversion or `PLINK2_VCF`.
- The GCTA add-GRMs and bivariate REML-LDMS nf-test setups resolve the existing
  pipeline-local `GCTA_MAKEGRMPART`, and both focused tests pass.
- The GCTA heritability subworkflow gains both missing estimator/MGRM negative
  tests while retaining all existing behavior.
- The LDAK heritability subworkflow gains its unsupported-estimator negative
  test and its metadata matches every emitted `[meta, path]` and versions tuple.
- All twelve strict joins remain inline and unchanged.
- Pipeline lint has no new failure relative to baseline; each component passes
  focused lint and Docker-backed nf-tests.
- Each logical change is reviewed and committed without including unrelated
  user-owned changes.

## Current Context

- Pipeline checkout: `/home/andongni/Yandex.Disk/Projects/Research/qc_dev/gwas`,
  branch `claude`, initially clean except untracked `.claude-scratch/`.
- Component-library checkout: sibling `../modules`, branch `gwas/integration`,
  with unrelated user-owned modifications that must remain untouched.
- Component source baseline: committed `gwas/integration` HEAD `d5704cac8`.
- Ticket contracts:
  `.scratch/first-release-pipeline/issues/30-orphaned-vendored-modules-and-dangling-test-references.md`
  and
  `.scratch/first-release-pipeline/issues/27-residual-hygiene-on-new-subworkflows.md`.

## Constraints

- Preserve all unrelated dirty files and active worktrees.
- Put each upstream component on one branch and one worktree below
  `../modules/.worktrees/modules/`.
- Do not introduce a shared join helper or alter runtime tuple shapes.
- Do not hard-code local fixture paths in tracked files.
- Do not push, publish, or open PRs.

## Risks

- The sibling integration checkout is dirty; all component edits must occur in
  new worktrees from its committed HEAD.
- Negative nf-tests may expose nf-test failure-matching behavior that needs
  careful assertion design.
- Broad pipeline validation is container-backed and may be time-consuming.

## Approval Required

No additional approval gate. The user explicitly requested parallel worktrees,
implementation, tests, review, and commits. No destructive or external action is
planned.

## Work Packets

- `P30`: pipeline residue removal and broken GCTA setup repair in the current
  checkout.
- `P27-GCTA`: focused GCTA guard-test additions in its own component worktree.
- `P27-LDAK`: focused LDAK guard test and output metadata repair in its own
  component worktree.
- `REVIEW`: independent standards/spec review of all three committed-intent
  diffs, followed by any necessary corrections.

## Integration Policy

Keep the three histories independent. #30 stays on the pipeline `claude`
branch. GCTA and LDAK each receive a focused component-library branch and
commit. Do not merge component-library branches into the pipeline or into each
other. Accept only changes within each packet's declared ownership.

## Verification

Run narrow nf-tests first, then ticket-required lint. For component worktrees,
run `nf-core subworkflows lint` and Docker-backed focused nf-tests. For the
pipeline, compare `nf-core pipelines lint` against a captured pre-change
baseline and run the two affected tests. Run broader pipeline validation if
the focused and lint gates are green and the environment permits it. Validate
workflow artifact completeness at the end.

## Reusable Artifacts

The workflow plan, packet reports, integration decisions, review findings, and
final report remain under `.workflow/tickets-30-and-27-implementation/`.
