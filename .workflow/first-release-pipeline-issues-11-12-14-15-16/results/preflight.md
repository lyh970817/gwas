# Preflight result

Accepted:

- Target branch: `claude`.
- Review/integration fixed point:
  `21b5576da6f77d23e579bf0ed7140250280a5439`.
- The tracked tree was clean at that point.
- Three isolated stream worktrees are required because every stream is expected
  to touch `workflows/gwas.nf`; Issues 14, 15, and 16 also overlap shared
  matrix/config/test surfaces.

Protected unrelated state:

- 24 untracked files under `.claude-scratch/`.
- The run's seven initial untracked files under `.workflow/`.
- Neither directory is ignored, so staging must always use explicit pathspecs.

Branch context:

- `claude` was 28 commits ahead of local `upstream/dev` at preflight.
- No upstream tracking branch was configured for `claude`.
- No fetch, rebase, push, or external mutation is part of this wave.

Decision:

- Implement A, B, and C in isolated external worktrees created at the exact
  fixed point, then integrate their commits deliberately into `claude`.

Created worktrees:

- A: `/tmp/codex-gwas-wave-hNCsm1xZ/association-11-12` on
  `codex/wave-association-11-12`.
- B: `/tmp/codex-gwas-wave-hNCsm1xZ/gcta-14-15` on
  `codex/wave-gcta-14-15`.
- C: `/tmp/codex-gwas-wave-hNCsm1xZ/ldak-16` on
  `codex/wave-ldak-16`.

All three were clean and pinned to the exact fixed point. The ignored issue
files are absent from those worktrees, so workers must read them through their
absolute paths in the main checkout.
