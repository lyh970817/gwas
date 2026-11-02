---
name: nf-core-pipeline-contribute
description: Implement or prepare a contribution to this existing nf-core/gwas pipeline. Use for component installation or wiring, schema or method configuration, public pipeline docs, relevant lint/tests, or a PR targeting dev. Apply only the procedure steps relevant to the requested delta. Do not use for submitting a component to nf-core/modules.
---

# Contribute to the pipeline

Read
[`contribution-boundaries.md`](../../../docs/coding-standards/contribution-boundaries.md) and the applicable
pipeline topics indexed by `CODING_STANDARDS.md`. Apply `dual-track-commit` before commit or branch
synchronization in this repository.

## Procedure

1. Classify the requested delta and its public target. Resolve or claim a public issue and create a public PR
   branch only when the task actually includes that external contribution stage.
2. When installing or updating a shared component, use `nf-core modules install <component>` or
   `nf-core subworkflows install <component>` so `modules.json` records provenance; do not hand-copy installed
   components. Skip this step for changes that do not install or update a component.
3. When composition changes, wire the affected inputs and outputs. Put per-process extension arguments,
   prefixes, resources, and publication in the relevant method-family `conf/modules/*.config`, not an installed
   component.
4. When user-visible parameters change, update `nextflow_schema.json` with the current schema builder and revise
   the affected public documentation. Do not manufacture schema or documentation churn for an unrelated delta.
5. Add a `CHANGELOG.md` entry only when the requested contribution and the pipeline's live release convention
   require one; use the current development or unreleased section.
6. Select validation from the changed surface: use the pipeline test procedure for affected routes, run the
   relevant configured lint gates, and add a direct smoke run only when the change warrants it. Record skipped
   gates rather than implying that every contribution has the same test surface.
7. For commits or branch synchronization, apply `dual-track-commit`. Prepare a public PR only when requested,
   using the live template, current authorized base-update mode, and canonical reviewer boundary.
8. Before closing the linked issue, when practical, delete issue-specific generated audit and evidence documents
   without an ongoing named consumer.
9. Request review only after the applicable CI and local gates are green and the user authorizes the external
   action. Before every push to the PR branch, apply [Push a PR branch](#push-a-pr-branch).
10. Close the linked origin issue after the contribution is integrated into every intended track and its required
    verification is complete.

## Push a PR branch

Apply this before every push that creates or updates a pull request to `nf-core/gwas`. The push itself, and any
PR comment, still needs the owner's explicit approval per item (root `AGENTS.md`). The PR branch carries no
`shell.nix`, so run each command from the PR worktree as
`nix-shell <personal checkout>/shell.nix --run '<command>'`; `ci-local` is described in `gwas-pipeline-test`.

1. Fetch `upstream`, then build the PR branch with `dual-track-commit`: only the portable delta from
   `upstream/dev`, committed, in a clean worktree. `ci-local` lints commits, not uncommitted edits.
2. `ci-local lint`: every stage passes; `template-version` may warn. The pre-push hook lints the exact pushed
   commit again and refuses a failing push, so this step only brings the feedback forward. It replaces neither
   step 3 nor step 4.
3. `ci-local --base upstream/dev nf-test` runs the cases nf-test selects as changed since the merge base, as
   `nf-test.yml` does. Compare the printed selection count with the change before reading a pass as evidence.
   A change to any `triggers` path in `nf-test.config`, such as `conf/**` or `nextflow.config`, selects the
   whole suite on its own.
4. Run `ci-local --base upstream/dev --all nf-test` instead of step 3 when the update is large: it touches
   `main.nf`, `workflows/`, `subworkflows/`, `conf/`, `nextflow.config`, `nextflow_schema.json` or
   `modules.json`; changes more than three directories under `modules/`; or rebases the branch onto a newer
   `upstream/dev`. Run it before a release PR as well, with `--base upstream/master` for CI's release mode.
   The full suite is 810 cases, about an hour on three shards.
5. Steps 3 and 4 are the one heavy job on the machine: start nothing else heavy alongside, keep the
   memory-derived shard count (three here) as the ceiling, and launch with `run_in_background`. For a run
   expected to exceed ten minutes, stop Yandex.Disk first with `sudo -n systemctl stop yandex-disk.service`,
   and start it again with `sudo -n systemctl start yandex-disk.service` when the run ends, pass or fail.
6. Push without `--no-verify`. When the hook refuses the push, fix the finding in a new commit. Report each
   stage's result, the nf-test selection and pass counts, and the pushed SHA.
7. Launch `ci-watch -R nf-core/gwas <pr>` with `run_in_background` as soon as the push lands, and act on its
   report before reporting the push done, requesting review, or ticking the PR checklist. `gh pr checks` is not
   evidence: it misses the `workflow_run`, `pull_request_target` and `issue_comment` runs the push sets off. Fix
   any failed, cancelled or timed-out run, or report it when it is an indirect run that is not ours. The report
   of a push names every workflow run and its conclusion, not an nf-test count alone.

Report repository, branch and target; which procedure steps applied or were inapplicable; actual installed,
wired, schema, config, documentation, or changelog changes; fallback topics consulted; exact validation results;
CI state; generated documents retained or deleted; linked origin issue and closure state; and skipped tests or
profiles.
