---
name: dual-track-commit
description: Route commits in this repository across the personal and upstream-pipeline-PR branches. Use for commit, amend, split, cherry-pick, merge, rebase, or synchronization work that may mix personal development infrastructure with portable nf-core/gwas changes.
---

# Route dual-track commits

Read the track classification and public boundary in
[`contribution-boundaries.md`](../../../docs/coding-standards/contribution-boundaries.md).

## Resolve the tracks

1. Inspect live remotes, branches, worktrees, dirty state, and branch tips. Resolve the upstream pipeline PR
   branch from the user's request or live PR state; never infer that `personal` is the PR branch.
2. Use separate clean worktrees. Record starting tips and preserve pre-existing changes.
3. Create an exhaustive hunk ledger using the canonical personal/portable classification. Split mixed files by
   hunk and assign each hunk exactly once.

## Build and propagate

1. Apply only portable hunks to the clean PR worktree. Base commit grouping and reviewer wording on
   `upstream/dev...<PR branch>`.
2. Before each public commit, scan the staged diff for personal paths, local overrides, private issues,
   machine paths, agent tooling, and Nix/development material.
3. Propagate the portable commits to `personal` in logical order. Compare stable patch IDs or resulting files
   when equivalent work may already exist; history alone is insufficient.
4. Treat a cherry-pick, merge, rebase, or patch-application conflict as a pause boundary. Preserve the conflict
   state and wait for explicit instructions before resolving, continuing, aborting, or changing strategy.
5. Commit personal-only hunks separately after their public dependencies are present.

## Verify and report

Verify clean worktrees, per-commit and aggregate `git diff --check`, public patch equivalence, the public
changed-file/text boundary, logical branch ordering, and relevant portable validation. Push only when authorized;
use `--force-with-lease` only for explicitly authorized history rewriting after recording the remote tip.

Report starting/final tips, commit mapping, hunk classification, equivalence evidence, validation scope, clean
state, unpushed commits, and every unresolved gate.
