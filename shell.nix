{ pkgs ? import <nixpkgs> {} }:
let
  nextflowVersion = "25.10.4";
  nextflowLanguageServerVersion = "25.10.3";
  nfCoreSource = "git+https://github.com/nf-core/tools.git@dev";
  waveVersion = "1.8.1";

  nextflowCli = pkgs.stdenvNoCC.mkDerivation {
    pname = "nextflow";
    version = nextflowVersion;
    src = pkgs.fetchurl {
      url = "https://github.com/nextflow-io/nextflow/releases/download/v${nextflowVersion}/nextflow";
      sha256 = "0mjl71im82pm2s5jj5fxy6nm5gph187nmm040y5cgj31yipzi2ln";
    };
    dontUnpack = true;
    installPhase = ''
      install -Dm755 "$src" "$out/bin/nextflow"
    '';
  };

  nextflowLanguageServerJar = pkgs.fetchurl {
    url = "https://github.com/nextflow-io/language-server/releases/download/v${nextflowLanguageServerVersion}/language-server-all.jar";
    hash = "sha256-aBaD4Naxand76OaIZ7WnjDkgei8T0rjwohRFRH2Z2FI=";
  };

  nextflowLanguageServer = pkgs.writeShellApplication {
    name = "nextflow-language-server";
    runtimeInputs = [ pkgs.jdk17_headless ];
    text = ''
      exec java -jar "${nextflowLanguageServerJar}" "$@"
    '';
  };

  nfCoreCli = pkgs.writeShellApplication {
    name = "nf-core";
    runtimeInputs = [ pkgs.uv ];
    text = ''
      exec uvx --from "${nfCoreSource}" python - -- "$@" <<'PY'
import inspect
import pathlib
import sys

from nf_core.__main__ import run_nf_core

# `python - -- "$@"` injects a literal `--` and sets argv[0] to `-`.
# Normalize argv so nf-core sees the expected CLI shape.
if len(sys.argv) > 1 and sys.argv[1] == "--":
    sys.argv.pop(1)
sys.argv[0] = "nf-core"

try:
    from nf_core.components.lint import LintResult
except Exception:
    LintResult = None

if LintResult is not None:
    signature = inspect.signature(LintResult.__init__)
    file_path_param = signature.parameters.get("file_path")
    needs_patch = file_path_param is not None and file_path_param.default is inspect._empty

    if needs_patch:
        original_init = LintResult.__init__

        def patched_init(self, component, parent_lint_test, lint_test, message, file_path=None):
            if file_path is None:
                component_dir = getattr(component, "component_dir", None)
                file_path = pathlib.Path(component_dir) if component_dir is not None else pathlib.Path(".")
            else:
                file_path = pathlib.Path(file_path)
            return original_init(self, component, parent_lint_test, lint_test, message, file_path)

        LintResult.__init__ = patched_init

sys.exit(run_nf_core())
PY
    '';
  };

  nfTestCli = pkgs.writeShellApplication {
    name = "nf-test";
    runtimeInputs = [ pkgs.jdk17_headless nextflowCli ];
    text = ''
      exec java -jar "${pkgs.nf-test}/share/nf-test/nf-test.jar" "$@"
    '';
  };

  # nf-test has no in-run concurrency in 0.9.3-0.9.5; its only split is
  # `--shard i/n`, which divides test files across separate processes. The suite
  # is bound by per-test wall clock -- container start plus tool runtime -- not
  # by CPU or memory, so running shards side by side scales close to linearly.
  # A 3-way split measured 2.955x (795s -> 269s) on `modules/local/ldak/`.
  nfTestParallel = pkgs.writeShellApplication {
    name = "nf-test-parallel";
    runtimeInputs = [ nfTestCli pkgs.coreutils pkgs.gnused ];
    text = ''
      shards=3
      if [[ "''${1:-}" =~ ^[0-9]+$ ]]; then
        shards="$1"
        shift
      fi

      if (( shards < 1 )); then
        echo "nf-test-parallel: shard count must be a positive integer" >&2
        exit 2
      fi

      if [[ ! -f nf-test.config ]]; then
        echo "nf-test-parallel: run from the repository root (no nf-test.config here)" >&2
        exit 2
      fi

      profile="''${NFT_PROFILE:-+docker}"
      shard_root=".nf-test-shards"

      # NXF_OFFLINE skips Nextflow's plugin-registry and version round trips and
      # is worth ~15% per run. It does NOT degrade gracefully on a cold cache --
      # a missing plugin aborts the run outright rather than triggering a
      # download -- so enable it only once the declared plugin is present, and
      # let an online run warm the cache otherwise. Deliberately not paired with
      # NXF_DISABLE_CHECK_LATEST_VERSION: that measured at baseline on its own
      # (62.2s vs ~61s), so it buys nothing and should not be re-added.
      if [[ -z "''${NXF_OFFLINE:-}" ]]; then
        plugin_dir="''${NXF_PLUGINS_DIR:-$HOME/.nextflow/plugins}"
        schema="$(sed -n "s/^[[:space:]]*id[[:space:]]*'nf-schema@\([^']*\)'.*/\1/p" nextflow.config | head -1)"
        if [[ -n "$schema" && -d "$plugin_dir/nf-schema-$schema" ]]; then
          export NXF_OFFLINE=true
        else
          echo "nf-test-parallel: plugin cache cold, running online to warm it" >&2
        fi
      fi

      rm -rf "''${shard_root:?}"/shard-*
      mkdir -p "$shard_root"

      echo "nf-test-parallel: $shards shards, profile $profile"

      pids=()
      for shard in $(seq 1 "$shards"); do
        workdir="$shard_root/shard-$shard"
        mkdir -p "$workdir"
        # nf-test caches nft-utils under its work dir, so a fresh per-shard dir
        # would re-fetch the same plugin once per shard. Seed it instead.
        if [[ -d .nf-test/plugins ]]; then
          cp -r .nf-test/plugins "$workdir/plugins"
        fi
        NFT_WORKDIR="$workdir" nf-test test \
          --profile="$profile" \
          --shard "$shard/$shards" \
          "$@" >"$shard_root/shard-$shard.log" 2>&1 &
        pids+=("$!")
      done

      status=0
      for index in "''${!pids[@]}"; do
        shard=$(( index + 1 ))
        if wait "''${pids[index]}"; then
          echo "  shard $shard/$shards passed"
        else
          status=1
          echo "  shard $shard/$shards FAILED -- $shard_root/shard-$shard.log" >&2
        fi
      done

      exit "$status"
    '';
  };

  condaCli = pkgs.writeShellApplication {
    name = "conda";
    runtimeInputs = [ pkgs.micromamba pkgs.python3 ];
    text = ''
      export MAMBA_ROOT_PREFIX="''${MAMBA_ROOT_PREFIX:-$HOME/.cache/micromamba}"
      mkdir -p "$MAMBA_ROOT_PREFIX/bin"

      cat > "$MAMBA_ROOT_PREFIX/bin/activate" <<'EOF'
#!/usr/bin/env bash
_conda_target="''${1:?missing environment prefix}"
export CONDA_PREFIX="$_conda_target"
export CONDA_DEFAULT_ENV="$_conda_target"
export CONDA_SHLVL="1"
export PATH="$_conda_target/bin:$PATH"
EOF
      chmod +x "$MAMBA_ROOT_PREFIX/bin/activate"

      if [[ "$#" -ge 2 && "$1" == "info" && "$2" == "--json" ]]; then
        micromamba info --json | python -c '
import json
import sys

payload = json.load(sys.stdin)
payload["conda_prefix"] = sys.argv[1]
json.dump(payload, sys.stdout, indent=4)
sys.stdout.write("\n")
' "$MAMBA_ROOT_PREFIX"
        exit $?
      fi

      exec micromamba --yes "$@"
    '';
  };

  waveSources = {
    x86_64-linux = {
      url = "https://github.com/seqeralabs/wave-cli/releases/download/v${waveVersion}/wave-${waveVersion}-linux-x86_64";
      sha256 = "sha256-ox1ZKfK1ftDZJinlOTKJyBP+TEGAdaBbjJmA7JdQIWo=";
    };
    aarch64-linux = {
      url = "https://github.com/seqeralabs/wave-cli/releases/download/v${waveVersion}/wave-${waveVersion}-linux-arm64";
      sha256 = "sha256-aqhaFkJ3qqGUPWXMm5DZks4yupijfzn/JYZ9wlHxE1I=";
    };
  };

  waveSource = waveSources.${pkgs.stdenv.hostPlatform.system}
    or (throw "Unsupported system for wave-cli: ${pkgs.stdenv.hostPlatform.system}");

  waveCli = pkgs.stdenvNoCC.mkDerivation {
    pname = "wave-cli";
    version = waveVersion;
    src = pkgs.fetchurl {
      inherit (waveSource) url sha256;
    };
    dontUnpack = true;
    installPhase = ''
      install -Dm755 "$src" "$out/bin/wave"
    '';
  };
in
pkgs.mkShell {
  packages = [
    pkgs.bash
    pkgs.jdk17_headless
    nextflowCli
    nextflowLanguageServer
    nfCoreCli
    nfTestCli
    nfTestParallel
    condaCli
    pkgs.apptainer
    pkgs.pre-commit
    waveCli
  ];
  shellHook = ''
    if [[ $- == *i* && -z "''${DIRENV_IN_ENVRC:-}" && "''${SHELL:-}" != */bash ]]; then
      exec bash
    fi
  '';
}
