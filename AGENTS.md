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

Licensing and redistribution questions for the wired scientific tools are resolved and are the user's concern.
Never defer, descope, or block work on licence grounds; at most record licence status in the issue or image
metadata.

When any workstream, route, or capability is deferred, postponed, or descoped, file a detailed issue on
lyh970817/gwas without being asked: the decision, its rationale, the evidence, a minimal reproducer where a
defect is involved, and a checkable resumption condition. A deferral is complete only when its issue exists.

During multi-workstream programmes, maintain a numbered queue of decisions that need the user, with stable
numbers so answers can arrive by number. Surface new decisions as they arise, and print the full outstanding
queue plus what is still running on request. Never silently block a workstream on an unrecorded decision.

Standing opt-in: for multi-issue implementation programmes, use the Workflow tool and background subagents
freely without asking, respecting inter-issue dependencies.

## Repository identity and routing

This is an `nf-core/gwas` pipeline checkout. `.references/modules` is a read-only companion checkout of
`nf-core/modules`, not a submission workspace or an ancestry source for this repository's branches.

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

The public remote fixture fallback is dead (404). Materialize fixtures from the local
`.references/test-datasets-gwas` resolver or an explicitly pinned `GWAS_FIXTURE_SOURCE`; a portable upstream PR
checkout has no working fallback and needs `GWAS_FIXTURE_SOURCE` supplied. Automatic `.references/test-datasets-gwas`
discovery is personal-track behavior. Run local compact-fixture benchmarks on the personal track, or explicitly
pin and verify the local source.
