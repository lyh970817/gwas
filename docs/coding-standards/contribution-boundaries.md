# Contribution and public-boundary standards

This document owns stable repository, workspace, track-classification, and reviewer-facing publication policy.
The lifecycle skills own the procedures that apply it.

## Guidance sources and precedence

Apply the user's current request, the `AGENTS.md` chain for the target path, these canonical tracked standards,
and then the active task skill's procedure. The ignored cache under `docs/nf-core-standards/` is a fallback for
upstream detail, not an owner of repository contracts. Inspect current upstream examples only after resolving
the applicable local contract; do not use a candidate's mirrored work in `.references/modules` as its own
precedent.

If live upstream requirements conflict with a canonical standard, surface the conflict and update the canonical
owner deliberately. A skill may not silently override a stable contract.

## Repository and workspace identity

Pipeline development belongs in this `nf-core/gwas` checkout. Portable pipeline PRs normally branch from and
target `nf-core/gwas:dev`; a critical released-version hotfix may branch from and target `master` when explicitly
chosen.

An upstream module or subworkflow submission belongs in a dedicated branch and worktree of a separate writable
`nf-core/modules` checkout based on its current upstream `master`. `.references/modules` is read-only reference
material and this pipeline's `master` has no component-library ancestry.

Use one focused component submission per branch and worktree. Local candidates are source material: transfer
only the portable component contract. Pipeline routing, publication, reuse identity, private tracker context,
local fixture discovery, agent tooling, and machine-specific paths do not transfer.

When a component needs new shared fixtures, prepare them in a separately resolved writable
`nf-core/test-datasets` branch/worktree. Do not encode a personal checkout path as policy.

## Personal and public tracks in this pipeline

`personal` is the complete development track. It may contain both portable pipeline work and personal
development infrastructure. The upstream pipeline PR track contains only the reviewer-facing portable delta
from `upstream/dev`.

Classify every changed hunk exactly once:

- Personal-only: `.agents/**`, `.claude/**`, `.codex/**`, `.omp/**`, `.scratch/**`, `.workflow/**`,
  `.references/**`, `.worktrees/**`, `AGENTS.md`, `CLAUDE.md`, `CODING_STANDARDS.md`, `docs/agents/**`,
  `docs/coding-standards/**`, Nix/development-shell files, `.envrc`, local fixture discovery, private trackers,
  orchestration, and machine-specific configuration.
- Portable pipeline: pipeline code and composition, schemas, public assets/examples, method configuration,
  tests and CI using public or committed inputs, and reviewer-facing `README.md`, `CHANGELOG.md`,
  `CITATIONS.md`, and public documentation.

Classify ambiguous paths by purpose and split mixed files by hunk. A portable pipeline change is complete only
when equivalent behavior is present on both the upstream-PR and personal tracks. A personal-only change is
complete when present on `personal` and absent from the public diff. The `dual-track-commit` skill owns branch
discovery, transfer order, conflict gates, patch-equivalence evidence, and final verification.

This dual-track rule governs changes made in the pipeline repository. It does not require an upstream
`nf-core/modules` submission to be copied into the pipeline's personal history.

## Public reviewer boundary

Public titles, bodies, comments, changelog entries, and reviewer-facing documentation may rely only on the
public target repository, the submitted diff, linked public issues or PRs, and public documentation. Explain
what the change adds, why it belongs upstream, and any public dependency or review consideration.

Exclude:

- absolute or machine-local paths, checkout/worktree names, environment overrides, and device details;
- private or ignored tracker references;
- agent, Claude/Codex, Nix, editor, or orchestration details;
- unpublished branches, commits, URLs, or local-only fixture instructions;
- implementation diaries, handoffs, branch-management plans, and publication plans.

Validation claims must be portable: state an environment-independent outcome or a command meaningful in the
public target. A public dependency must resolve for the reviewer. Audit every URL and reference for public
accessibility.

Drafting reviewer text does not authorize staging, committing, pushing, opening or editing a PR, assigning a
reviewer, or changing external state. Perform only the publication actions explicitly requested by the user.
