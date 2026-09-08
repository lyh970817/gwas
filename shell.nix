{ pkgs ? import <nixpkgs> {} }:
let
  nextflowVersion = "26.04.6";
  nextflowLanguageServerVersion = "26.04.3";
  nfCoreSource = "git+https://github.com/nf-core/tools.git@dev";
  waveVersion = "1.8.1";
  # nixpkgs still ships 0.9.3. 0.9.4 added strict-syntax support, which Nextflow
  # 26.04 needs because the v2 parser is now the default, so pin upstream directly
  # and keep this in step with NFT_VER in .github/workflows/nf-test.yml.
  nfTestVersion = "0.9.5";
  # The nf-tower core plugin version that `nextflowVersion` resolves. Nextflow ships the core plugin
  # set inside its own distribution -- `META-INF/plugins-info.txt` in nextflow-<ver>-one.jar, echoed as
  # the `core-plugins:` line of any .nextflow.log -- so this is a property of the pinned Nextflow and
  # must be updated with it. It exists because NXF_OFFLINE aborts the run outright when a required
  # plugin is absent, and nf-tower is required: measured on a cache holding only nf-schema@2.8.0, an
  # offline run dies with `Plugin with id nf-tower not found in any repository`. Matching the exact
  # version matters -- a glob would accept a stale nf-tower-1.11.2 as proof that 1.28.2 is cached.
  # Drift is safe in one direction only: a wrong pin makes the probe answer "cold" and run online.
  nfTowerVersion = "1.28.2";

  nextflowCli = pkgs.stdenvNoCC.mkDerivation {
    pname = "nextflow";
    version = nextflowVersion;
    src = pkgs.fetchurl {
      url = "https://github.com/nextflow-io/nextflow/releases/download/v${nextflowVersion}/nextflow";
      sha256 = "10c2jqc17rcm8b6gyvadd8pilj38mxknqflgasxwyhyppvnmb9v1";
    };
    dontUnpack = true;
    installPhase = ''
      install -Dm755 "$src" "$out/bin/nextflow"
    '';
  };

  nextflowLanguageServerJar = pkgs.fetchurl {
    url = "https://github.com/nextflow-io/language-server/releases/download/v${nextflowLanguageServerVersion}/language-server-all.jar";
    hash = "sha256-IM+jT24gLWuLq9jXhiAs4A4NObcMzsMpDiqz+9ArwBY=";
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

  nfTestJar = pkgs.stdenvNoCC.mkDerivation {
    pname = "nf-test-jar";
    version = nfTestVersion;
    src = pkgs.fetchurl {
      url = "https://github.com/askimed/nf-test/releases/download/v${nfTestVersion}/nf-test-${nfTestVersion}.tar.gz";
      sha256 = "0h8nzhs7d17lwbq5xlrswnfnjvnf0bdk95lym2zl55nw1jwrwrxp";
    };
    sourceRoot = ".";
    installPhase = ''
      install -Dm644 nf-test.jar "$out/share/nf-test/nf-test.jar"
    '';
  };

  # JVM flags for the short-lived Nextflow processes nf-test launches. Every test *case* is a fresh
  # `nextflow run` that lives a handful of seconds compiling Groovy and never reaches C2, so C1-only
  # startup is the single highest-leverage setting in the suite. Nextflow's own launcher agrees in
  # principle -- it hands `-XX:TieredStopAtLevel=1` to every command except `run` and `node` -- and
  # withholding it from `run` is right for a production pipeline and pure overhead for a test case.
  # Measured 277.4s -> 216.4s (1.28x) on a 31-case containerless file; see issue #113.
  #
  # NXF_JVM_ARGS rather than NXF_OPTS: NXF_OPTS is also spliced into the launcher's `java -version`
  # probe and into the classpath-resolution command line, whereas NXF_JVM_ARGS reaches only the final
  # JVM. Verified to arrive there: a deliberately bogus flag aborts the launched JVM, and
  # `-XX:+PrintCommandLineFlags` reports TieredStopAtLevel=1 active. The launcher appends NXF_JVM_ARGS
  # after everything else, so these values also override a heap set through NXF_OPTS (the form
  # `docs/usage.md` recommends for production); only an explicit NXF_JVM_ARGS changes the test heap.
  #
  # The heap cap is scoped to the test wrapper on purpose. It is right-sized for the compact fixture --
  # the JVM's own ergonomic default here is a ~3.1 GB maximum heap -- and it is what makes six
  # concurrent shards fit in memory. It is not production guidance and must not be copied into
  # `docs/usage.md`.
  nfTestJvmArgs = "-XX:TieredStopAtLevel=1 -Xss2m -Xms256m -Xmx1024m";

  nfTestCli = pkgs.writeShellApplication {
    name = "nf-test";
    runtimeInputs = [ pkgs.jdk17_headless pkgs.coreutils pkgs.gnused nextflowCli ];
    text = ''
      # Pin any nextflow bootstrap nf-test performs; no manual NXF_VER needed.
      export NXF_VER="${nextflowVersion}"

      # Applies to every test launch, including the ones nf-test-parallel makes. An explicit
      # NXF_JVM_ARGS still wins, so a one-off can measure or override it.
      export NXF_JVM_ARGS="''${NXF_JVM_ARGS:-${nfTestJvmArgs}}"

      # Every fixture-backed test resolves its inputs from GWAS_TEST_FIXTURES, and there is no working
      # remote fallback: the published bundle 404s. An unset variable used to produce a run that looked
      # healthy and then failed every fixture-backed case on schema validation -- 211 of 776 in one
      # merge-gate run, three hours in. Materialize it here, exactly as tests/fixtures/nf-test.sh does
      # for a focused run, so the variable is never the thing that is missing. Only `nf-test test`
      # needs it, and materialization is a content-addressed no-op once the bundle is cached.
      if [[ "''${1:-}" == test && -z "''${GWAS_TEST_FIXTURES:-}" && -x tests/fixtures/materialize.sh ]]; then
        fixture_profile=docker
        fixture_args=("$@")
        for (( index = 0; index < ''${#fixture_args[@]}; index++ )); do
          case "''${fixture_args[index]}" in
            --profile=*)
              fixture_profile="''${fixture_args[index]#--profile=}"
              ;;
            --profile)
              if (( index + 1 < ''${#fixture_args[@]} )); then
                fixture_profile="''${fixture_args[index + 1]}"
              fi
              ;;
          esac
        done
        fixture_profile="''${fixture_profile#+}"
        if ! fixture_root="$(tests/fixtures/materialize.sh --profile "$fixture_profile")"; then
          echo "nf-test: fixture materialization failed; refusing to run without GWAS_TEST_FIXTURES" >&2
          exit 1
        fi
        export GWAS_TEST_FIXTURES="$fixture_root"
        echo "nf-test: GWAS_TEST_FIXTURES=$fixture_root" >&2
      fi

      # nextflow.config includes ''${custom_config_base}/nfcore_custom.config on every launch unless
      # NXF_OFFLINE is set, which costs a raw.githubusercontent.com round trip plus the Groovy parse of
      # ~80 institutional profile blocks per test case -- about 3.0s of a launch, only ~0.85s of it
      # network. Verified: with NXF_OFFLINE=true the include resolves to /dev/null, `Available config
      # profiles` drops from ~180 entries to the pipeline's own 18, and the plugin repository becomes
      # the local one. Nothing under tests/ reads that remote config.
      #
      # It does NOT degrade gracefully on a cold cache -- a missing plugin aborts the run outright
      # rather than triggering a download -- so enable it only once the plugins are present, and let an
      # online run warm the cache otherwise. Both the declared nf-schema and the nf-tower core plugin
      # Nextflow resolves alongside it have to be there. The value must be the literal string `true`:
      # Nextflow compares against 'true' while nf-core's config test uses Groovy truth, so `false`
      # would disable the include and still leave Nextflow doing all of its online work.
      #
      # Deliberately not paired with NXF_DISABLE_CHECK_LATEST_VERSION: that measured at baseline on its
      # own (62.2s vs ~61s), so it buys nothing and should not be re-added.
      if [[ -z "''${NXF_OFFLINE:-}" && -f nextflow.config ]]; then
        plugin_dir="''${NXF_PLUGINS_DIR:-$HOME/.nextflow/plugins}"
        schema="$(sed -n "s/^[[:space:]]*id[[:space:]]*'nf-schema@\([^']*\)'.*/\1/p" nextflow.config | head -1)"
        if [[ -n "$schema" && -d "$plugin_dir/nf-schema-$schema" && -d "$plugin_dir/nf-tower-${nfTowerVersion}" ]]; then
          export NXF_OFFLINE=true
        else
          echo "nf-test: Nextflow plugin cache cold, running online to warm it" >&2
        fi
      else
        if [[ ! -f nextflow.config ]]; then
          echo "nf-test: not at the repository root, so NXF_OFFLINE was left alone" >&2
        fi
      fi

      exec java -jar "${nfTestJar}/share/nf-test/nf-test.jar" "$@"
    '';
  };

  # nf-test has no in-run concurrency in 0.9.3-0.9.5; its only split is `--shard i/n`, which divides
  # test *cases* (not files) across separate processes, round-robin by default.
  #
  # The default is six, and the reason it can be six is the heap cap in nfTestJvmArgs above.
  #
  # What the suite is bound by comes from issue #113's whole-suite attribution: ~79% of wall clock is
  # Nextflow bootstrap and real tool compute is ~10%, so shards contend for memory rather than CPU.
  # An earlier note here claimed 2.955x for a 3-way split on `modules/local/ldak/`; #113 measures the
  # same 3-way split at 1.62x once the whole suite is in scope, with the degradation landing entirely
  # on the Groovy bootstrap phases while task execution is unaffected.
  #
  # Three against six was then measured here directly, on a fixed 51-case slice spanning module
  # process, subworkflow function/workflow and pipeline tests, both sides already tuned and offline,
  # run 3-6-6-3 to cancel drift: mean 696.3s at k=3 against 554.0s at k=6, so **1.257x**. Six is
  # faster, but far less than doubling, for two reasons visible in the shard logs: per-case cost rose
  # 1.544x (29.40s -> 45.40s mean) going 3 to 6, and round-robin over only 51 cases left one straggler
  # shard at 520.6s while the other five finished in 349-371s. A 51-case slice cannot show what a
  # full suite would; #113's own six-shard figure (3.89x at 1.44x per-case degradation) is against a
  # *serial* tuned run, not against three shards, and is the basis for preferring six here.
  # Both of these were measured with another suite running on the same box, which inflates the
  # per-case degradation, so treat 1.257x as a floor. Raise the count past six only after measuring;
  # the constraint is RAM, which is why the default below is derived from it rather than fixed at six.
  nfTestParallel = pkgs.writeShellApplication {
    name = "nf-test-parallel";
    runtimeInputs = [ nfTestCli pkgs.coreutils pkgs.gnused ];
    text = ''
      shards=""
      if [[ "''${1:-}" =~ ^[0-9]+$ ]]; then
        shards="$1"
        shift
      fi

      # Shards contend for memory rather than cores: each one runs an nf-test JVM plus a Nextflow head
      # JVM capped by nfTestJvmArgs, with its Docker tasks on top, and about 4 GB per shard is what that
      # costs in practice. Six shards therefore need roughly 24 GB; six of them on this 12.5 GB box
      # exhausted memory and froze the machine mid-suite, which is why the default is derived from
      # MemTotal instead of being fixed at six. An explicit first argument still wins, in either
      # direction, so a measurement can still ask for more than the derived count.
      memory_derived=""
      if [[ -z "$shards" ]]; then
        mem_kb=0
        if [[ -r /proc/meminfo ]]; then
          mem_kb="$(sed -n 's/^MemTotal:[[:space:]]*\([0-9]*\).*/\1/p' /proc/meminfo)"
        fi
        shards=$(( ''${mem_kb:-0} / 1024 / 1024 / 4 ))
        if (( shards > 6 )); then
          shards=6
        fi
        if (( shards < 1 )); then
          shards=1
        fi
        memory_derived=1
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

      # Shard work dirs and logs are large, short-lived and rewritten constantly. Inside the
      # repository folder a file-sync daemon indexes every one of them while the suite runs, which
      # costs I/O the shards are already contending for. NFT_SHARD_ROOT moves the whole shard root
      # somewhere unsynced (a scratchpad, /tmp) without changing anything else about the run; the
      # default keeps the in-repo path that .gitignore already covers.
      shard_root="''${NFT_SHARD_ROOT:-.nf-test-shards}"

      # Materialize once here rather than letting six shards each do it: the bundle is
      # content-addressed and flock-guarded so concurrent calls would be safe, just wasteful. Aborting
      # before any shard starts is the point -- a broad run that discovers a fixture problem per shard
      # wastes the whole run.
      if [[ -z "''${GWAS_TEST_FIXTURES:-}" && -x tests/fixtures/materialize.sh ]]; then
        if ! fixture_root="$(tests/fixtures/materialize.sh --profile "''${profile#+}")"; then
          echo "nf-test-parallel: fixture materialization failed; no shard was started" >&2
          exit 1
        fi
        export GWAS_TEST_FIXTURES="$fixture_root"
      fi
      echo "nf-test-parallel: GWAS_TEST_FIXTURES=''${GWAS_TEST_FIXTURES:-<unset>}"

      # The JVM tuning and the warm-cache-guarded NXF_OFFLINE now live in the nf-test wrapper this
      # calls, so every shard inherits them and a plain `nf-test` run gets them too.

      rm -rf "''${shard_root:?}"/shard-*
      mkdir -p "$shard_root"

      if [[ -n "$memory_derived" ]]; then
        echo "nf-test-parallel: $shards shards (memory-derived; pass an explicit count to override)"
      fi
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
    pkgs.python3Packages.cairosvg
    waveCli
  ];
  shellHook = ''
    export NXF_VER="${nextflowVersion}"
    # NXF_JVM_ARGS is deliberately NOT exported here. Every test launch already inherits it from the
    # nf-test wrapper above, which is the only `nf-test` on this shell's PATH, so nothing is missed;
    # exporting it shell-wide would additionally apply a C1-only JIT and a 1 GB heap to a bare
    # `nextflow run`, where both are wrong -- a long production run wants C2 and its own heap.
    if [[ $- == *i* && -z "''${DIRENV_IN_ENVRC:-}" && "''${SHELL:-}" != */bash ]]; then
      exec bash
    fi
  '';
}
