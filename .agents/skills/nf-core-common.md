# nf-core submission skill common rules

Use this file before any `nf-core-*` skill in this repository.

## Scope

These skills are for upstream `nf-core/modules` module and subworkflow submissions from this fork. They do not optimise for local-only component prototypes. If work starts from `modules/local/`, treat that directory as source material to be wired into a focused upstream submission under `modules/nf-core/` or `subworkflows/nf-core/`.

## Design-time preflight

Treat nf-core standards as design inputs, not a final implementation review. Before external programme
research, invoke `nf-core-component-design` if it is not already active when the task will decide a component
portfolio, executable ownership, public interface, metadata or selector contract, output identity, container,
fixture, validation, or reusable-versus-pipeline-local boundary. Complete its applicable standards audit before
publishing or closing the design decision.

## Standards cache

The distilled standards cache lives at `docs/nf-core-standards/` and is intentionally ignored by git. The cache is populated by the `nf-core-standards-refresh` skill (`.agents/skills/nf-core-standards-refresh/SKILL.md`).

For all skills except `nf-core-standards-refresh`:

- Treat the active lifecycle skills as the authoritative working guidance. Do not open the standards cache merely because a skill links to a topic.
- Consult the cache only when the active skills are unclear or incomplete for the decision at hand, or when extra upstream standards detail is genuinely needed.
- When that fallback is needed, check `docs/nf-core-standards/index.md` and its fetch date first. Invoke `nf-core-standards-refresh` only if the cache is missing or stale enough to make the needed detail unreliable.
- Read only the cache topics needed to resolve the specific uncertainty. Topic lists in skills are conditional routing hints, not required-reading lists.
- If consulted cache guidance conflicts with explicit skill text, surface the conflict and deliberately update the relevant skill before proceeding; do not silently let the cache override the skill.

This fallback policy applies only to the nf-core standards cache. It does not alter the separate rule for
programme documentation: check the relevant programme cache or index under `docs/` before online programme
research.

## Companion component library

For anything intended for upstream `nf-core/modules`, resolve the decision from the active `nf-core-*` skills
first. When they do not settle a current convention, inspect the companion checkout at `.references/modules`
before inventing a repository-local rule. Use its `modules/nf-core/` and `subworkflows/nf-core/` trees as the
implementation reference for component layout, naming, interfaces, metadata and tests. Format-specific
data-processing subworkflows normally begin with the primary input file format, followed by concise semantic
tokens for the operation and, when useful, the tool or tool chain (for example, `fastq_align_bowtie2` or
`plink_association_ldak_kvik`). Generic orchestration and genuinely co-primary or multi-format workflows may
use a semantic name. When reviewing a proposed component already mirrored in the companion checkout,
do not use that component's own work-in-progress name as its precedent; compare established unrelated
subworkflows instead.

## Instruction priority

When instructions differ, prioritise:

1. The user's current request.
2. Required repository mechanics in `AGENTS.md` (with `CLAUDE.md` retained as a compatibility link), including branch/worktree placement, PR tracking, fixture handling, and files that must stay out of submissions.
3. The active lifecycle skills.
4. Cached nf-core standards under `docs/nf-core-standards/`, when deliberately consulted as a fallback.
5. Existing nearby modules and subworkflows for style conventions.

Once consulted, current upstream standards override stale nearby examples. A cache-versus-skill conflict must
be resolved by deliberately updating the skill rather than silently overriding it.

## Submission branches and worktrees

- Treat `master` in this fork as the reference branch for new upstream submission branches.
- Use one upstream component submission per branch and per worktree.
- Create submission worktrees under `.worktrees/modules/`.
- Preserve existing active worktrees unless the user explicitly asks to remove or replace them.
- Do implementation, linting, testing, PR preparation, and PR follow-up from the relevant submission worktree.
- Keep `WORKTREE_PR.md`, plans, drafts, and similar tracking files uncommitted unless the user explicitly asks.
- Do not include `.agents/skills/` changes in upstream component submission PR branches unless the task is specifically to change repo skill tooling.

## Command recipes

Run commands from the relevant repository or submission worktree root.

- Format/lint Nextflow after `.nf` edits:

  ```bash
  nextflow lint -format -sort-declarations -spaces 4 -harshil-alignment
  ```

- Module lint:

  ```bash
  nf-core modules lint <tool[/subtool]>
  ```

- Subworkflow lint:

  ```bash
  nf-core subworkflows lint <name>
  ```

- Module tests:

  ```bash
  nf-core modules test <tool[/subtool]> --profile docker
  nf-core modules test <tool[/subtool]> --profile singularity
  nf-core modules test <tool[/subtool]> --profile conda
  ```

- Subworkflow tests:

  ```bash
  nf-core subworkflows test <name> --profile docker
  nf-core subworkflows test <name> --profile singularity
  nf-core subworkflows test <name> --profile conda
  ```

- Focused nf-test debugging:

  ```bash
  nf-test test modules/nf-core/<tool>/tests/main.nf.test --profile=docker --verbose
  nf-test test subworkflows/nf-core/<name>/tests/main.nf.test --profile=docker --verbose
  ```

Use the smallest useful command while implementing or debugging. Before treating a submission PR as ready, require the Docker, Singularity, and Conda wrapper test matrix to pass and report exact commands run.

## Git discipline

- Check `git status --short --untracked-files=all` before and after meaningful edits.
- Do not revert changes you did not make.
- Do not run `git commit`, push branches, open PRs, close issues, or modify external repositories unless the user explicitly asks.
- If the user asks for a commit, stage only intended files and keep skill/tooling changes separate from component submission changes.

## Subagents

- Use the Agent tool (e.g. the `Explore` or `general-purpose` subagent type) for separable research and review work when it is available and warranted by task size.
- Keep edits and external actions in the main agent unless the user explicitly asks for parallel implementation.
- Reviews should run in a review subagent where available; the main agent synthesizes findings.
