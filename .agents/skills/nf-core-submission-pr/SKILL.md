---
name: nf-core-submission-pr
description: Prepare an upstream nf-core/modules PR for a module or subworkflow submission from this fork.
---

Read `../nf-core-common.md` first. Treat this skill as authoritative; use the standards-cache fallback only
when this guidance is unclear or incomplete, or extra upstream detail is needed.

Use this skill when preparing, opening, updating, or summarizing an upstream `nf-core/modules` PR for a module or subworkflow submission.

## Standards cache fallback

If fallback is needed, relevant topic hints are:

- `docs/nf-core-standards/contributing-prs.md`
- target-specific module or subworkflow standards files;
- `docs/nf-core-standards/test-datasets.md` if fixtures are involved.

## PR readiness

Before treating a PR as ready:

- Confirm the branch is focused on one upstream component submission.
- Confirm the work is in the appropriate submission worktree.
- Confirm local planning files, `WORKTREE_PR.md`, ignored caches, and unrelated tooling files are not staged for the upstream PR.
- Run or verify successful linting and Docker, Singularity, and Conda wrapper tests for the target.
- Ensure the PR body is reviewer-facing and high-level.
- Mention `nf-core/test-datasets` only when a companion fixture PR is actually required.
- Do not add a standalone `Validation` section; put command evidence in checklist items or the minimal reviewer-relevant note.
- Do not push, open, edit, or label a PR unless the user explicitly asks.
- Each PR needs one approving review before it can merge (a second is advisable for exceptionally complex PRs); a review can be requested from a human on Slack. All CI checks must pass before merge.

## Merge queue and branch currency

`nf-core/modules` merges through a GitHub **merge queue**, which lints and tests the PR _merged with the current `master` tip_ — not the state the PR's own checks ran against. Two failure modes follow, both of which pass PR-level CI yet get the PR silently **evicted from the queue**:

- **Newer lint rules on master.** If `master` adopted a stricter lint (e.g. the `meta.yml` `containers:` format — see `nf-core-containers`) after the PR's checks last ran, the queue re-lints with the new rules and fails. Bring the module up to the current standard, do not just re-queue.
- **Branch far behind master.** The lint workflow's changes-detection (`dorny/paths-filter`, shallow `--depth=2` fetch) cannot reach a distant merge-base, so it sees only the last commit. If that commit touched no `main.nf`/`.nf.test.snap`, the module-lint matrix comes up empty, `nf-core-lint-modules` fails, and `confirm-pass-lint` fails with no obvious per-module error.

Before (re-)enqueuing, **merge current `origin/master` into the branch** and push, so the merge-base is reachable and the queued lint matches what you verified locally. To diagnose an eviction, read the `merge_group` workflow runs (`gh api "repos/nf-core/modules/actions/runs?event=merge_group"`, filter `head_branch` for `gh-readonly-queue/master/pr-<N>-`), not just the green `pull_request` checks.

## PR body style

For new component submissions:

- Briefly describe the underlying tool or workflow capability.
- Explain what is being upstreamed.
- Link the relevant issue with `Closes #...` when available.
- Mention reviewer-relevant dependency or risk only when it matters.
- Avoid module-specific interface minutiae, local migration history, and unchanged-behavior sections.

## PR template sourcing

- Before drafting, fetch the current upstream PR template from the target checkout (`.github/PULL_REQUEST_TEMPLATE.md`) rather than paraphrasing a checklist from memory. Save a local reusable copy under this skill (e.g. `references/nf-core-modules-pull-request-template.md`) and draft from it.
- Tick a checklist box only when the associated item has actually been verified in the current branch state. Do not pre-check boxes based on intention, expectation, or partial evidence. Do not present a PR as ready with the Docker/Singularity/Conda wrapper-test boxes left unchecked — check them only from successful wrapper runs with recorded command evidence.
- If the repo has no PR template, do not fabricate a "default checklist".

## Git identity and commit hygiene

- Before committing upstream PR work, set the user's real git identity (not a GitHub noreply address):

  ```bash
  git config user.name "lyh970817"
  git config user.email "lyh970817@yandex.com"
  ```

- For modules upstreamed from this fork, set `meta.yml` `authors` and `maintainers` to `@lyh970817` unless the user says otherwise.
- Make each commit subject describe the concrete change it contains (a specific output contract, test, or metadata item). Avoid process subjects like `address review suggestions`, `Fix reviewer suggestions`, or `Apply feedback`.
- Do not include PR numbers, reviewer names, or `(#12345)` references in commit subjects — PR linkage belongs in GitHub metadata.
- Split review follow-up into conceptual commits rather than one catch-all commit. Before pushing, inspect `git status --short --branch`, `git diff --stat @{u}...HEAD`, and `git log --oneline --decorate -5`, and confirm the branch is actually ahead (do not trust an `Everything up-to-date` message blindly).
- Add `[skip ci]` to a commit subject only for intermediate or known-incomplete pushes; omit it on final, review-ready commits.

## Two-repo (test-datasets + modules) submissions

When a module's tests need shared fixtures in `nf-core/test-datasets`, this is a coordinated two-repo contribution. Open PRs in this order:

1. `nf-core/test-datasets` first — the module PR depends on files not yet on the public dataset branch.
2. `nf-core/modules` second, referencing the dataset PR.
3. Optionally a short downstream tracking issue in `nf-core/gwas` after both PRs exist — one request sentence plus flat bullets linking the two PRs.

- Cross-link a companion PR once, using a single full GitHub URL (not URL plus a shorthand `#123` in the same sentence).
- If the final setup needs no new dataset PR, say so explicitly and do not draft a fake companion dataset PR.
- When a module PR depends on unmerged dataset changes, point `NF_MODULES_TESTDATA_BASE_PATH` at the local `nf-core/test-datasets` checkout for wrapper tests and state that dependency explicitly in the modules PR body.

### Stacked / split PRs

- When a split PR depends on another unmerged split PR for test `setup {}`, keep the downstream branch stacked on the prerequisite branch so tests remain runnable without branch-local helpers, but still open each PR against `nf-core/modules:master` (not against another fork branch).
- Open the prerequisite PR first so the downstream PR body and `WORKTREE_PR.md` can cite the real dependency URL. Expect the stacked downstream PR to temporarily include the prerequisite module in its diff against `master` until the prerequisite merges — this is acceptable.
- Name the merge dependency once with a full URL in the reviewer-facing body. After all replacement PRs are open, comment on any superseded umbrella PR with a flat list of replacement URLs and close it.

## Tracking

After an upstream PR is opened, record the PR number and URL in `WORKTREE_PR.md` at the root of that submission worktree. Keep it uncommitted unless the user explicitly asks otherwise.

If a companion `nf-core/test-datasets` PR is required, link the module/subworkflow PR and fixture PR in both worktrees' `WORKTREE_PR.md` files.
