# AGENTS.md

## Collaboration constraints

Recommend designs on their merits. Do not discount a design because implementation or refactoring mistakes may
be introduced; assume testing and review can catch them later.

Ask for the user's explicit approval before deciding to patch the source of a third-party programme that this
pipeline invokes directly and that we did not write. Changes to pipeline code and programmes owned by this
repository do not require that approval.

File issues, comments, and reproducers only on lyh970817/gwas by default. Posting anything to an upstream or
third-party repository requires the user's explicit approval per item, even when a reproducer is ready.

Wire a third-party programme that this pipeline invokes according to its own documentation. Investigate its
native behavior when the wiring at hand needs it: a contract the documentation leaves ambiguous, an output the
pipeline must parse, a failure the pipeline must detect. Do not investigate as an end in itself. Report a
defect in such a programme, whether in an issue, a review, or documentation, only when it is material: the
programme returns a wrong or unusable result on input in its expected form, or the defect lies on a
conventional route that ordinary users take, such as categorical covariates in a GWAS. Behavior on malformed,
unconventional, or adversarial input, such as a missing header, a name containing a comma, an empty file, a
sentinel value, or a hostile flag combination, is not a defect here; do not guard against it, document it in
user-facing docs, or test for it. It may be recorded, but only in the programme's single consolidated issue of
non-material defects, recorded and not guarded, never as an individual issue. Record every material defect as
an individual issue in this repository, naming the pinned image or version it was measured on. Do not build
compensation for a tool defect, whether a refusal, an assertion, or a recomputation, without the owner's
explicit decision. Validating user-supplied input such as manifest rows, method options, and resource files is
unaffected.

Before calling any such behavior a defect, read the programme's own documentation for it. Behavior that the
documentation describes, or that follows from a stated input contract or design choice, is intended behavior
even when it does not align with how this pipeline uses the programme: MPH documents that covariates must be
dummy-coded numeric columns, so its mishandling of a factor covariate is the pipeline's misalignment, not an
MPH defect; a capability the documentation never claims is a gap, not a defect. Treat such intended behavior as
a pipeline-side matter, whether by validating the user's input, adapting the wiring, or documenting the
contract, and never file or keep it as a bug. Reserve the word defect, and the issue handling above, for
behavior the programme's author would not have intended: it contradicts the documentation, or the documentation
is silent and the behavior is unambiguously an error on input the documentation declares valid. State the
documentary basis of every classification: the sentence that describes the behavior, or the sections searched
that are silent on it.

Keep the pipeline's adapters minimal. An adapter is code that exists only to bridge what a wired programme
does and what the pipeline needs: input reshaping, output parsing, a guard or refusal, a restated default, a
test-side compensation. Add or keep one only when, without it, the code materially breaks, the pipeline
publishes a wrong or unusable scientific result, or the programme cannot consume the pipeline's current input
scheme as the analysis manifest defines it. A message-only guard, a warning, a recorded provenance detail, a
restatement of the programme's documented default, or a second net under a failure that already stops the run
meets none of these and is removed rather than maintained. Name the condition an adapter satisfies in a
comment beside it, and record the retirement condition when the adapter compensates for a pinned version.

Split responsibility between the pipeline and the programmes it wires. The pipeline guards its own inputs,
its own processes, and the way it feeds each programme: the manifest and the user's files as the pipeline
reads them, its own joins, merges and derived files, and the formats, flags and staging a programme's
documented interface requires. It does not handle programme-level errors: if a programme accepts an input,
let it; if a programme rejects an input loudly, let that rejection stand rather than duplicating it; and do
not write code whose purpose is to detect, prevent, compensate for, or interpret a programme's own failure,
defect, tolerance, or output pathology. Such programme-level handling enters pipeline code only with the
user's explicit approval, recorded item by item, and the issue it compensates for carries the label
`upstream bug` (a measured defect) or `upstream` (a limitation). A behaviour recorded as a documented
contract is never guarded, validated against, or compensated for, whatever its consequence. Validating user-supplied input remains
unaffected, as above.

Licensing and redistribution questions for the wired scientific tools are resolved and are the user's concern.
Never defer, descope, or block work on licence grounds; at most record licence status in the issue or image
metadata.

When any workstream, route, or capability is deferred, postponed, or descoped, file a detailed issue on
lyh970817/gwas without being asked: the decision, its rationale, the evidence, a minimal reproducer where a
defect is involved, and a checkable resumption condition. A deferral is complete only when its issue exists.

When the implementation an issue on lyh970817/gwas asks for is finished and verified, update or close that
issue in the same piece of work, without being asked: post a comment naming the implementing commits, files
and tests, distinguish what is implemented in the pipeline from what is only prepared for upstream, and close
the issue unless its own text still owes something. When later work makes an open issue's body or latest
status stale, post a dated status comment recording what changed. A task that finishes an issue is complete
only when the issue reflects it.

During multi-workstream programmes, maintain a numbered queue of decisions that need the user, with stable
numbers so answers can arrive by number. Surface new decisions as they arise, and print the full outstanding
queue plus what is still running on request. Never silently block a workstream on an unrecorded decision.

Standing opt-in: for multi-issue implementation programmes, use the Workflow tool and background subagents
freely without asking, respecting inter-issue dependencies.

## Repository identity and routing

This is an `nf-core/gwas` pipeline checkout. `.references/modules` is a read-only companion checkout of
`nf-core/modules`, not a submission workspace or an ancestry source for this repository's branches.

The owner's `bioconda-recipes` fork checkout lives beside this repository at `../bioconda-recipes`, with one linked
worktree per recipe branch under its `.worktrees/`. It holds the Bioconda recipes for the tools this pipeline wires
(MPH, MR-MEGA, LDAK, ldsc-rs, GWASLab) and has its own `AGENTS.md`. Consult it when a container directive,
`environment.yml`, or upstream-submission question depends on a tool's Bioconda status; never post on
bioconda/bioconda-recipes without the owner's per-item approval.

The owner's nf-core/modules submission workspace lives beside this repository at `../modules`: a clone of
nf-core/modules with one linked worktree per component branch under its `.worktrees/` (named after the module or
subworkflow, `<tool>-<subcommand>`), and its own `AGENTS.md` (the upstream nf-core/modules rules). The pinned
Nextflow and nf-test binaries its component tests use live in `../gwas-modules-ci-tools/`. Prepare every module or
subworkflow submission there, never in `.references/modules`, and open or update a PR on nf-core/modules only with
the owner's per-item approval.

[`CODING_STANDARDS.md`](CODING_STANDARDS.md) indexes the canonical tracked standards. Skills under
`.agents/skills/` own task procedures, gates, evidence, and reporting; they do not override stable contracts in
the canonical standards.

Before changing a governed subtree, read every `AGENTS.md` from this root through the closest containing
directory. A task started at the repository root must discover and apply descendant instructions before acting
in that subtree.

Repository-local agent guidance and development infrastructure are personal-only. Use `dual-track-commit` for
any commit or synchronization task that may mix those changes with the portable pipeline or a public PR.

Local `personal` is the primary branch, and the repository-root checkout normally remains on it. Use linked
worktrees for other branches.

After a temporary branch has been merged into local `personal` and its content has been verified there, remove
its worktree and delete the local branch. Use the commit on `personal` for later propagation; do not retain the
temporary branch or worktree for that purpose.

Push `personal` to `origin/personal` only after all work intended for that push has been merged into `personal`
and all merged temporary branches and worktrees have been cleaned up.

Never merge a branch that still carries files which must never be tracked, anything under `.scratch/` above
all; the merge reintroduces those blobs. Rewrite the branch first.

## Worktree-isolated agents

In a worktree-isolated agent, the isolation verifier accepts only plain, single-purpose commands with literal
paths. It refuses chained one-liners, path arguments held in shell variables, `git -C` or `cd` toward the
shared checkout or `.references/`, and complex constructs around git or docker. Write multi-step logic to a
script file inside the worktree with the Write tool and run that; spell out scratchpad and worktree paths
literally.

A linked worktree has `shell.nix` but no direnv activation. Run toolchain commands as
`nix-shell shell.nix --run '<command>'` from the worktree root (the isolation verifier accepts this form);
never hard-code `/nix/store` paths or export `NXF_VER` manually — the dev shell and its `nf-test` wrapper
already pin Nextflow.

Bash `timeout` is capped at 600000 ms; larger values are silently truncated. Never sleep-wait for a background
task or subagent — launch long runs (nf-test shards, container builds) with `run_in_background: true` and act
on the completion notification. If polling is unavoidable, sleep at most 240 s per call.

## Git hooks and pull requests

Entering the dev shell points `core.hooksPath` at the main checkout's tracked `.githooks/` (`ci-hooks status`
reports it), so the hooks fire in every worktree of this repository, including the public PR worktree. They lint
throwaway copies under `~/.cache` and never rewrite the checkout. `pre-commit` runs the repository's
pre-commit hooks on the staged changes (`ci-local --staged`); `pre-push` runs the `pre-commit`, `nextflow-lint`
and `nf-core-lint` stages of `ci-local` on each pushed commit (`--rev`), about a minute per tree. Outside the
matching dev shell each hook first enters the main checkout's `shell.nix`, a few seconds more.

Fix a finding rather than bypass it. Use `git commit --no-verify` only when the hook cannot run for an
environmental reason, such as nix or the network being unavailable, and report that; the pre-push hook still
lints the result. Use `git push --no-verify` only with the owner's explicit approval for that push.

Before pushing a branch that creates or updates an `nf-core/gwas` PR, follow "Push a PR branch" in
[`nf-core-pipeline-contribute`](.agents/skills/nf-core-pipeline-contribute/SKILL.md): it owns the nf-test
gates the hooks leave out.

After every push that creates or updates a pull request on `nf-core/gwas` or `nf-core/modules`, and before
reporting the push done, requesting review, or ticking a PR checklist, watch the whole of the PR's GitHub Actions
with `ci-watch -R <repo> <pr>` launched with `run_in_background`, and act on its report. `gh pr checks` alone is
not evidence: it lists only the check runs attached to the head commit and misses the workflows the push sets
off indirectly (`workflow_run`, `pull_request_target`, `merge_group`, `issue_comment`). Any run that failed, was
cancelled or timed out is a finding to fix, or, for an indirect run that is not ours, to report, before the PR is
declared green. A non-blocking leg (`continue-on-error`, such as the latest-everything Nextflow matrix) fails
while its job still concludes success, and reports the failure only through annotations and bot comments;
`ci-watch` lists those as warnings. Read and explain every warning in the push report; never ignore one. When the
owner points at a failed action, identify the run by its URL and say whether a later run on the same PR
superseded it.

## Generated development documents

Commit issue-specific generated audit and evidence documents while they are needed for review or historical
record. After verification, delete them; retain only documents with an ongoing named consumer.

## Upstream-bound local components

The LDAK, GWASLab, GCTA, PLINK, and PLINK 2 modules and reusable subworkflows under `modules/local/` and
`subworkflows/local/` are upstream-bound candidates despite their local paths. Keep portable atomic components
free of pipeline routing, scientific policy, publication, and reuse identity; the descendant instructions route
the exact boundary.

## Local fixture safety

`.references/test-datasets-gwas` is read-only machine-local state. Never hard-code it in tracked code or make CI
depend on it. Use a private copy for modified fixtures. The live resolver mechanisms own exact source
resolution; `gwas-pipeline-test` owns test selection, execution, evidence, and reporting.

The public `nf-core/test-datasets` `gwas` branch under `params.pipelines_testdata_base_path` is the canonical
fixture source. `-profile test` resolves its manifests straight from that branch, so
`nextflow run . -profile test,docker --outdir out` works from a clean clone with no environment variable and no
side script. The nf-test suite does not read the branch per case: every nf-test invocation runs with
`GWAS_TEST_FIXTURES` set from `tests/fixtures/materialize.sh`, which fetches the branch once into a
checksum-verified cache entry, and the dev-shell `nf-test` and `nf-test-parallel` wrappers materialize it
automatically when it is unset, aborting rather than starting a run without it. `GWAS_FIXTURE_SOURCE` pins
another source root — a URL or a local checkout — which is how an unmerged fixture branch is tested without
committing a machine-specific path. There is no auto-discovery of `.references/test-datasets-gwas`; point
`GWAS_FIXTURE_SOURCE` at it explicitly. Run local compact-fixture benchmarks on the personal track, or
explicitly pin and verify the local source.

`nf-test-parallel` derives its default shard count from `MemTotal` as `min(6, max(1, floor(GB / 4)))`, because
shards contend for memory rather than cores: six shards need at least 24 GB, and this machine derives 3. Pass
an explicit count as the first argument to override it in either direction, and do not raise it past the
derived value while anything else heavy is running on the box.
