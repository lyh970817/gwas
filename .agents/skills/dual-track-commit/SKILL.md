---
name: dual-track-commit
description: Route commits in this repository across the personal and upstream-PR branches. Use whenever committing, amending, splitting history, cherry-picking, or synchronizing changes that may mix local agent or Nix development files with public nf-core/gwas changes.
---

# Dual-track commits

Treat the branches as a **dual-track** history:

- `personal` is the complete development branch. It receives public pipeline changes and personal-development changes.
- The open upstream-PR branch contains only the reviewer-facing delta from `nf-core/gwas:dev`.

A public change is complete only when it is committed on both tracks. A personal change is complete when it is committed on `personal` and absent from the PR diff.

## 1. Resolve both tracks

Inspect the live repository, remotes, worktrees, dirty state, and branch tips. Resolve the PR branch from the user's named branch or the open PR targeting `nf-core/gwas:dev`; if several open branches match, request the intended one. Never infer that `personal` is the PR branch.

Use separate clean worktrees for the two tracks. Expect their ancestry and commit hashes to differ. Preserve all pre-existing changes and record both starting tips before moving changes.

Completion criterion: the `personal` branch, PR branch, their worktrees, and their starting commits are known, and no dirty checkout will be switched or overwritten.

## 2. Classify every changed hunk

Create an exhaustive ledger assigning every changed path or mixed-file hunk to one track class.

### Personal-only

Classify repository-local development infrastructure as personal-only, including:

- `.agents/**`, `.claude/**`, `.codex/**`, `.omp/**`, `.scratch/**`, `.workflow/**`, `.references/**`, and `.worktrees/**`;
- `AGENTS.md`, `CLAUDE.md`, `CODING_STANDARDS.md`, `docs/agents/**`, and `docs/coding-standards/**`;
- Nix development files such as `flake.nix`, `flake.lock`, `shell.nix`, other repository-local `*.nix` files, and `.envrc`;
- private trackers, local fixture discovery, agent orchestration, skills, launchers, and machine-specific configuration.

This skill is under `.agents/**`, so changes to it belong only on `personal`.

### Public

Classify changes to the portable pipeline contract as public, including:

- `main.nf`, `workflows/**`, `subworkflows/**`, and pipeline modules;
- public schemas, assets, method configuration, and canonical examples;
- tests and CI that use public or committed inputs;
- reviewer-facing `README.md`, `CHANGELOG.md`, `CITATIONS.md`, and public documentation.

Classify by purpose when a path is ambiguous. Split mixed files such as `.gitignore`, test configuration, or documentation by hunk so local conveniences stay personal while portable behavior reaches both tracks.

Completion criterion: every changed hunk is assigned exactly once as personal-only or public, with mixed files split explicitly.

## 3. Build reviewer-facing commits on the PR track

Apply only public hunks to the clean PR worktree. Base the history and wording on `upstream/dev...<PR branch>`, not on intermediate personal commits. Group commits by public behavior so each subject explains what a reviewer gains.

Before committing, scan the staged diff for personal paths, local fixture overrides, private issue references, machine paths, agent tooling, and Nix development material. Remove any such leakage from the staged public change.

Completion criterion: every public hunk is represented by a logical PR commit, and the aggregate PR diff contains no personal-only material.

## 4. Propagate public commits to `personal`

Cherry-pick the new public commits onto `personal` in the same logical order when they apply cleanly. Different commit hashes are normal because the parent histories differ. When equivalent public work already exists on `personal`, compare stable patch IDs or resulting files before skipping it; commit history alone is insufficient evidence.

Treat any cherry-pick, rebase, merge, or patch-application conflict as a pause boundary. Preserve the conflict state, report the operation and conflicted files, and wait for explicit instructions before resolving, continuing, aborting, or changing strategy.

Commit personal-only hunks on `personal` after their public dependencies are present. Keep them in separate commits with subjects describing the local development capability they add.

Completion criterion: every public patch is present on both tracks, every personal patch is present only on `personal`, and neither track contains duplicate public patches.

## 5. Verify the boundary

Verify all of the following before reporting completion:

- both worktrees are clean except for explicitly preserved pre-existing changes;
- `git diff --check` passes for each new commit and the aggregate PR diff;
- public patches on `personal` are equivalent to their PR counterparts even when their commits have different hashes;
- the PR changed-file list and text scan contain no personal-only material;
- the two branch logs show the intended logical ordering;
- relevant portable validation was run from the PR worktree, with fixture or environment blockers reported accurately.

Push only when the user has authorized publication. Use `--force-with-lease` only when history rewriting is explicitly requested, after recording the remote tip being replaced.

Completion criterion: every changed hunk is accounted for on the correct track, the public boundary is clean, and any unpushed commits or unresolved validation gates are stated precisely.
