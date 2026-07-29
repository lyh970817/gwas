---
name: nextflow-nixos-shell-compat
description: OBSOLETE as of 2026-07-05 — kept only as a historical pointer. This host now runs Nextflow/nf-test directly (no shim); do not apply the bwrap recipe below.
---

# Nextflow NixOS Shell Compatibility (resolved)

This skill documented a workaround for a host that had no `/bin/bash` and no Docker daemon, which broke
every Nextflow task launch (`Cannot run program "/bin/bash"`). As of 2026-07-05 the host has
`services.envfs.enable = true;` in `/etc/nixos/configuration.nix` (confirmed: `/bin` and `/usr/bin` are
`envfs` FUSE mounts) and a running Docker daemon. Both root causes are fixed.

**Verified empirically on this host (2026-07-05):** `modules/nf-core/plink/maf` passes on `conda`,
`docker`, and `singularity` profiles, and an R-based module (`modules/nf-core/soupx`, real run + custom
args) passes on `conda`, all via plain invocation — **no bwrap shim, no `/usr/bin/which` bind**. `envfs`
resolves `/bin/bash`, `/bin/sh`, `/usr/bin/env`, and `/usr/bin/which` transparently on `exec()` even
though they don't show up under `ls`/`stat` (that's expected FUSE behavior, not a sign it's not working).

## Current policy

- Just run `nf-test`/`nextflow`/`nf-core` directly. No shim, no profile restriction.
- Tooling still comes from the repo `shell.nix`/`.envrc` (`direnv`/`nix-shell shell.nix --run '…'`), as
  before — that part hasn't changed.
- Docker, Singularity, and Conda profiles are all usable locally now; the full matrix no longer needs to
  be deferred to CI.

## If this regresses

If `Cannot run program "/bin/bash"` reappears (e.g. on a different host, or after an envfs regression),
the old bwrap recipe is preserved in git history of this file (see the version before 2026-07-05) and in
`TEST_EXECUTION_BLOCKER.md`'s git history. The permanent fix is `services.envfs.enable = true;` +
`nixos-rebuild` (root).
