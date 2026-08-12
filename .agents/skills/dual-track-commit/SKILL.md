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
4. On a propagation conflict, preserve the conflict state while inspecting the index stages, worktree result,
   relevant history, and hunk ledger. Derive the intended `personal` result from the canonical invariant:
   portable PR behavior plus already-classified personal-only additions. Do not decide from path names or
   `ours`/`theirs` labels alone.
5. Resolve and continue without asking only when classification and intent are unambiguous and the resolution
   is mechanically implied by that invariant: keep the PR version of portable, generated, or reviewer-facing
   content; or combine the portable behavior with an established personal-only extension, retaining that
   extension only on `personal` without changing its scope or precedence. Before continuing, inspect the staged
   resolution and verify equivalence to the PR's portable behavior and the unchanged personal-only boundary.
6. Keep the conflict state intact and request explicit instructions when classification is ambiguous, product
   behavior is incompatible, personal-only semantics would be lost or expanded, the public boundary is
   uncertain, the strategy is destructive or history-changing, or the intended result is not mechanically
   implied by the track invariant. Never feed personal-only resolution content back into the public diff.
7. Commit personal-only hunks separately after their public dependencies are present.

## Verify and report

Verify clean worktrees, per-commit and aggregate `git diff --check`, public patch equivalence, the public
changed-file/text boundary, logical branch ordering, and relevant portable validation. Push only when authorized;
use `--force-with-lease` only for explicitly authorized history rewriting after recording the remote tip.

Report starting/final tips, commit mapping, hunk classification, equivalence evidence, validation scope, clean
state, unpushed commits, and every unresolved gate.
