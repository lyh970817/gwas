# Sourced by the hooks in this directory; not a hook itself (git only runs files named after hooks).
#
# core.hooksPath names this directory in the main checkout for every worktree of the repository, so a
# hook fired in the public PR worktree (no shell.nix) or in an agent worktree on an older branch still
# finds the shell.nix beside it and runs that shell's ci-local, with that checkout's pinned tools.

hooks_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
dev_shell="$(dirname -- "$hooks_dir")/shell.nix"

# Run "$@" with the dev shell's tools. The current environment is used only when it was built from this
# very shell.nix (the shellHook exports its sha256); otherwise -- a plain shell, a stale direnv capture,
# another worktree's older shell -- the command runs through nix-shell, which costs about 3 s warm.
run_in_dev_shell() {
    if [[ ! -f "$dev_shell" ]]; then
        echo "${hook_name:-hook}: $dev_shell is missing, so the checks cannot run." >&2
        echo "${hook_name:-hook}: restore the main checkout to a branch that carries it, or run 'ci-hooks uninstall'." >&2
        return 1
    fi
    local want
    want="$(sha256sum "$dev_shell" | cut -d' ' -f1)"
    if [[ "${GWAS_DEV_SHELL_SHA256:-}" == "$want" ]] && command -v "$1" >/dev/null 2>&1; then
        "$@"
        return
    fi
    if ! command -v nix-shell >/dev/null 2>&1; then
        echo "${hook_name:-hook}: nix-shell is not on PATH, so $dev_shell cannot provide $1." >&2
        return 1
    fi
    nix-shell "$dev_shell" --run "$(printf '%q ' "$@")"
}
