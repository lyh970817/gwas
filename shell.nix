{ pkgs ? import <nixpkgs> {} }:
let
  nextflowVersion = "25.10.4";
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
    pkgs.jdk17_headless
    nextflowCli
    nfCoreCli
    nfTestCli
    condaCli
    pkgs.apptainer
    pkgs.pre-commit
    waveCli
  ];
}
