---
name: nf-core-submission-pr
description: Prepare reviewer-facing upstream PRs for an nf-core/modules module or subworkflow and any companion nf-core/test-datasets fixtures. Do not use for a pipeline PR; use nf-core-pipeline-contribute.
---

# Prepare a component submission PR

Read
[`contribution-boundaries.md`](../../../docs/coding-standards/contribution-boundaries.md). Use
`nf-core-submission-test` for readiness evidence and `nf-core-fixtures` for companion data.

## Readiness

Before treating a submission as ready:

1. Confirm one focused component submission in the correct writable component-library worktree.
2. Confirm local plans, handoffs, caches, pipeline guidance, and unrelated tooling are not staged.
3. Verify successful target lint and required Docker, Singularity, and Conda wrapper tests.
4. Inspect the current target repository/base branch for the live PR template in supported GitHub locations,
   including an organization default when applicable. Select the contribution-specific template; do not invent
   a checklist when none exists.
5. Tick only checks proven in the current branch state. Keep the body concise and apply the canonical public
   reviewer boundary. Before marking the PR ready or requesting review, every item of the template checklist,
   including the Docker, Singularity and Conda test runs, must have been performed by us and ticked; an unticked
   item is a blocker, not a note.
6. Do not push, open, edit, label, assign, or merge a PR without the user's explicit request. Review/CI merge
   requirements remain external gates.

## Branch currency and merge queue

Before queueing, update the branch against current upstream `master` using the authorized synchronization mode,
then re-run the current lint and tests. The `nf-core/modules` merge queue validates the merge result with current
master, so newer lint rules or an unreachable shallow merge base can evict a PR after its own checks pass.

Diagnose an eviction from the `merge_group` workflow run, not only the green `pull_request` checks. Bring the
component to the current standard and restore branch currency before requeueing.

Before ticking checklist boxes or reporting the PR ready, and after every push or requeue, watch all of its
workflow runs, `labeler`, GPU and `merge_group` runs included, with `ci-watch -R nf-core/modules <pr>` from the
gwas dev shell (`nix-shell <gwas checkout>/shell.nix --run 'ci-watch -R nf-core/modules <pr>'`), launched with
`run_in_background`; `gh pr checks` lists only the head commit's check runs. `ci-watch` counts only runs tied to
the PR by branch, PR number or log evidence, so strangers' comment-triggered runs stay in its uncounted summary
line; open a reported failure by its URL and confirm it is the PR's before treating it as ours. A non-blocking leg
(`continue-on-error`) concludes success and reports its failure only through annotations and bot comments, which
`ci-watch` lists as warnings: read and explain every warning in the report, never ignore it.

## Commit and public-text procedure

- Inspect the effective Git identity before committing and use the user's real configured identity. Commit
  subjects describe the concrete component behavior or contract; omit reviewer names, PR numbers, vague review
  language, and `[skip ci]` on the final review-ready commit.
- Split follow-up by concept. Before pushing, inspect branch status, upstream diff/stat, and recent log; confirm
  the branch is actually ahead.
- Describe the tool/workflow capability, what is upstreamed, the public issue or dependency when relevant, and
  reviewer-relevant risk. Do not narrate local migration history or unchanged behavior.

## Coordinated fixture and stacked submissions

When new public fixtures are required, open the test-datasets PR first and the component PR second, linking the
accessible dependency once. Local wrapper testing may use `NF_MODULES_TESTDATA_BASE_PATH`; the public body names
only the accessible companion PR, never the local override or checkout.

For split component PRs, a downstream branch may remain stacked on an unmerged prerequisite so setup tests run,
but each public PR still targets upstream `master`. Open the prerequisite first, cite its public URL once, and
expect the downstream diff to include it temporarily.

After an explicitly authorized PR opening, record the number and URL in uncommitted `WORKTREE_PR.md`; cross-link
the component and fixture handoffs when both exist.

Report the worktree/branch, live template used, verified checklist and wrapper evidence, public dependencies,
queue/currency state, external actions performed, and blockers.
