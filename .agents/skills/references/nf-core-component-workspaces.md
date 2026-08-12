# nf-core component workspaces

An upstream `nf-core/modules` submission belongs in a dedicated branch and worktree of the writable component
library checkout, based on its current upstream `master`. Do not create that submission branch from this
`nf-core/gwas` pipeline repository or assume this repository's `master` has component-library ancestry.
The reference-only `.references/modules` checkout named in `AGENTS.md` is not that writable submission
workspace; resolve or create a separate writable `nf-core/modules` clone and worktree.

Use one component submission per branch and worktree. Keep implementation, linting, testing, PR preparation,
and review follow-up in that worktree. Preserve existing worktrees. Keep `WORKTREE_PR.md`, plans, and drafts
uncommitted unless the user asks otherwise.

Local candidates under this pipeline's `modules/local/` and `subworkflows/local/` are source material. Transfer
only the portable component contract to the component-library worktree; pipeline routing, publication, reuse
identity, local fixtures, private tracker references, agent tooling, and machine-specific paths stay out of the
submission.

Use `dual-track-commit` for commits made in this pipeline repository. Do not include pipeline-local guidance or
development infrastructure in an upstream component submission.
