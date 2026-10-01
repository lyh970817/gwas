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

      # Every fixture-backed test resolves its inputs from GWAS_TEST_FIXTURES rather than fetching the
      # published nf-core/test-datasets branch per case, so an unset variable is a hard error in the
      # tests. It used to be a silent one: a run looked healthy and then failed every fixture-backed
      # case on schema validation -- 211 of 776 in one merge-gate run, three hours in. Materialize it
      # here, exactly as tests/fixtures/nf-test.sh does for a focused run, so the variable is never the
      # thing that is missing. Only `nf-test test` needs it, and materialization is a content-addressed
      # no-op once the bundle is cached. GWAS_FIXTURE_SOURCE overrides the published source root.
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
      # content-addressed and flock-guarded so concurrent calls would be safe, just wasteful -- each
      # one fetches the 20 published fixtures again. Aborting before any shard starts is the point --
      # a broad run that discovers a fixture problem per shard wastes the whole run.
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

      # nf-test 0.9.5 installs the plugins nf-test.config loads into `.nf-test/plugins` relative to the
      # launch directory -- a fixed location, not under NFT_WORKDIR -- so every shard reads and, on a
      # cold cache, downloads into the same directory. In a fresh worktree the shards race on that
      # download and die. Install them once, before any shard starts, when a declared plugin is
      # missing; `update-plugins` re-downloads unconditionally, so a warm cache is left alone.
      plugins_missing=""
      while read -r plugin_name plugin_version; do
        if [[ -z "$(ls -A ".nf-test/plugins/$plugin_name/$plugin_version" 2>/dev/null)" ]]; then
          plugins_missing+=" $plugin_name@$plugin_version"
        fi
      done < <(sed -n 's/^[[:space:]]*load[[:space:]]*"\([^"@]*\)@\([^"]*\)".*/\1 \2/p' nf-test.config)
      if [[ -n "$plugins_missing" ]]; then
        echo "nf-test-parallel: installing nf-test plugins before the shards start:$plugins_missing"
        if ! nf-test update-plugins; then
          echo "nf-test-parallel: nf-test plugin installation failed; no shard was started" >&2
          exit 1
        fi
      fi

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

  # `ci-local` runs the checks a pipeline PR to dev gets on GitHub, before pushing. It operates on the
  # checkout in the current directory, not on the one holding this shell.nix, so a PR-branch worktree
  # (which carries no shell.nix) is checked with `nix-shell <personal>/shell.nix --run ci-local`.
  #
  # Each stage mirrors one job and reads its pins from the same file CI does: the prek hooks and their
  # revisions from .pre-commit-config.yaml, the nf-core/tools release from `.nf-core.yml`
  # `nf_core_version` (a private uvx environment, never the tools@dev `nf-core` above), and the fixture
  # source from nf-test.yml's `fixture_source` when it pins one -- unpinned, as now, the materializer's
  # default published branch applies, as in CI. What it cannot mirror, and why, is listed in the
  # gwas-pipeline-test skill. Deliberate differences: Nextflow is this shell's pinned version, where the
  # lint job takes setup-nextflow's latest-stable and nf-test also runs a non-blocking latest-everything
  # leg; prek is nixpkgs' release, where prek-action installs the latest; and shards come from
  # nf-test-parallel's memory-derived count rather than CI's seven runners.
  #
  # The lint stages run in a throwaway copy of the tree, never in the checkout: CI's checkout holds only
  # the pushed commit, while a local checkout also carries ignored content -- the `.references/modules`
  # companion checkout above all -- that `nf-core pipelines lint` walks (its plugin_includes test fails on
  # nf-validation imports there). The copy is HEAD by default, which is what CI lints; `--worktree` copies
  # the working tree's tracked and untracked-unignored files instead, i.e. what the next commit would carry;
  # `--rev` and `--staged` copy a given commit and the index, which is how the git hooks below call it.
  ciLocal = pkgs.writeShellApplication {
    name = "ci-local";
    runtimeInputs = [
      nfTestCli
      nfTestParallel
      nextflowCli
      pkgs.jdk17_headless
      pkgs.prek
      pkgs.uv
      pkgs.git
      pkgs.curl
      pkgs.jq
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnused
      pkgs.gnugrep
      pkgs.gnutar
    ];
    text = ''
      usage() {
        cat <<'EOF'
      Usage: ci-local [options] [stage...] [-- nf-test paths...]

      Run the checks GitHub runs on a pipeline PR to dev, against the checkout in the current directory.

      Stages (default: all, in this order):
        pre-commit        linting.yml pre-commit job: every prek hook except nextflow-lint
        nextflow-lint     linting.yml pre-commit job: the nextflow-lint hook on its own
        nf-core-lint      linting.yml nf-core job: `nf-core pipelines lint` at the .nf-core.yml version
        template-version  template-version-comment.yml: informational, never fails
        nf-test           nf-test.yml: sharded `nf-test test --ci --changed-since <merge-base>`
        lint              alias for the four stages before nf-test

      Options:
        --base REF        PR target the change is measured against (default: $CI_LOCAL_BASE or upstream/dev).
                          A master/main target switches on CI's release mode: `lint --release` and the
                          conda,docker,singularity nf-test matrix.
        --profile LIST    nf-test profiles, comma-separated (default: docker, or the release matrix)
        --shards N        nf-test shards per profile (default: nf-test-parallel's memory-derived count,
                          capped at CI's maximum of 7 and at the selected test count)
        --tag TAG         pass --tag TAG to nf-test, as the nf-test action's `tags` input does
        --all             run every nf-test case instead of those changed since the merge base
        --worktree        lint the working tree (tracked files as edited, plus untracked files that are not
                          ignored) instead of HEAD
        --rev REV         lint the tree of commit REV instead of HEAD (the pre-push hook's mode)
        --staged          lint the index, i.e. what `git commit` would record, and run the prek stages on
                          the staged changes only rather than --all-files (the pre-commit hook's mode)
        -h, --help        show this help

      The lint stages run in a temporary copy of the tree, so ignored local content (.references/, build
      output) is never linted and nothing in the checkout is rewritten. The copy is HEAD by default, which
      is what CI lints; --worktree, --rev and --staged choose another tree, and nf-test always runs in the
      checkout itself. Hook and lint auto-fixes land in the copy only: the summary names them as "would
      rewrite" and saves them as a patch in the logs.

      Everything after `--` is handed to nf-test as explicit test paths.
      Logs go to $CI_LOCAL_OUT (default: $XDG_CACHE_HOME/gwas-ci-local/<checkout>-<hash>).
      EOF
      }

      # CI's pinned inputs that are not read from a repository file. Keep them in step with
      # .github/workflows/linting.yml (python-version) and .github/workflows/nf-test.yml (get-shards max_shards).
      ci_python="3.14"
      ci_max_shards=7

      base="''${CI_LOCAL_BASE:-upstream/dev}"
      profiles=""
      shards=""
      tag=""
      run_all=""
      lint_source="head"
      lint_rev=""
      stages=()
      test_paths=()

      set_lint_source() {
        if [[ "$lint_source" != head && "$lint_source" != "$1" ]]; then
          echo "ci-local: --worktree, --rev and --staged each choose the lint tree; pass one" >&2
          exit 2
        fi
        lint_source="$1"
      }

      while (( $# > 0 )); do
        case "$1" in
          --base) base="''${2:?--base needs a ref}"; shift 2 ;;
          --base=*) base="''${1#--base=}"; shift ;;
          --profile) profiles="''${2:?--profile needs a value}"; shift 2 ;;
          --profile=*) profiles="''${1#--profile=}"; shift ;;
          --shards) shards="''${2:?--shards needs a count}"; shift 2 ;;
          --shards=*) shards="''${1#--shards=}"; shift ;;
          --tag) tag="''${2:?--tag needs a value}"; shift 2 ;;
          --tag=*) tag="''${1#--tag=}"; shift ;;
          --all) run_all=1; shift ;;
          --worktree) set_lint_source worktree; shift ;;
          --rev) set_lint_source rev; lint_rev="''${2:?--rev needs a commit}"; shift 2 ;;
          --rev=*) set_lint_source rev; lint_rev="''${1#--rev=}"; shift ;;
          --staged) set_lint_source staged; shift ;;
          -h|--help) usage; exit 0 ;;
          --) shift; test_paths=("$@"); break ;;
          lint) stages+=(pre-commit nextflow-lint nf-core-lint template-version); shift ;;
          pre-commit|nextflow-lint|nf-core-lint|template-version|nf-test) stages+=("$1"); shift ;;
          *) echo "ci-local: unknown argument '$1'" >&2; usage >&2; exit 2 ;;
        esac
      done

      if (( ''${#stages[@]} == 0 )); then
        stages=(pre-commit nextflow-lint nf-core-lint template-version nf-test)
      fi

      if [[ -n "$shards" && ! "$shards" =~ ^[1-9][0-9]*$ ]]; then
        echo "ci-local: --shards must be a positive integer" >&2
        exit 2
      fi

      if ! root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
        echo "ci-local: run from inside the pipeline checkout" >&2
        exit 2
      fi
      if [[ ! -f "$root/.nf-core.yml" || ! -f "$root/nf-test.config" ]]; then
        echo "ci-local: $root is not the pipeline root (.nf-core.yml or nf-test.config missing)" >&2
        exit 2
      fi
      # Run from a git hook, git exports GIT_DIR (in a linked worktree) and GIT_INDEX_FILE (pre-commit; a
      # temporary index under `commit -a` or `commit <paths>`). Every git call on the lint copy below, and
      # prek's and nf-core's own, would inherit them and act on this checkout instead of the copy. Keep the
      # index the caller named for --staged and drop the rest: from the checkout root git rediscovers the
      # same repository. A relative GIT_INDEX_FILE is relative to the hook's directory, the checkout root.
      source_index=""
      if [[ -n "''${GIT_INDEX_FILE:-}" ]]; then
        source_index="$GIT_INDEX_FILE"
        if [[ "$source_index" != /* ]]; then
          source_index="$PWD/$source_index"
        fi
      fi
      unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR
      cd "$root"

      lint_commit=""
      if [[ "$lint_source" == rev ]]; then
        if ! lint_commit="$(git rev-parse --verify --quiet "$lint_rev^{commit}")"; then
          echo "ci-local: --rev '$lint_rev' is not a commit here" >&2
          exit 2
        fi
      fi

      # Only nf-test's --changed-since needs the base to resolve; release mode is read from its name. The
      # hooks lint without it, so a clone with no upstream remote can still commit and push.
      merge_base=""
      for stage in "''${stages[@]}"; do
        if [[ "$stage" == nf-test ]]; then
          if ! git rev-parse --verify --quiet "$base^{commit}" >/dev/null; then
            echo "ci-local: base '$base' does not resolve; fetch it or pass --base" >&2
            exit 2
          fi
          merge_base="$(git merge-base "$base" HEAD)"
        fi
      done

      # CI keys release mode on the PR's base branch name, not on the remote that carries it.
      base_branch="''${base##*/}"
      release=""
      if [[ "$base_branch" == master || "$base_branch" == main ]]; then
        release=1
      fi
      if [[ -z "$profiles" ]]; then
        if [[ -n "$release" ]]; then
          profiles="conda,docker,singularity"
        else
          profiles="docker"
        fi
      fi

      # Logs and shard work dirs stay out of the synced checkout and out of every tracked ignore file.
      out="''${CI_LOCAL_OUT:-''${XDG_CACHE_HOME:-$HOME/.cache}/gwas-ci-local/$(basename "$root")-$(printf '%s' "$root" | sha1sum | cut -c1-8)}"
      mkdir -p "$out"

      stage_names=()
      stage_results=()
      stage_notes=()

      record() {
        stage_names+=("$1")
        stage_results+=("$2")
        stage_notes+=("$3")
      }

      banner() {
        printf '\n==> ci-local: %s\n' "$1"
      }

      run_logged() {
        # Tee a stage's output to its log while keeping the command's own exit status.
        local log="$1"
        shift
        "$@" 2>&1 | tee "$log"
        return "''${PIPESTATUS[0]}"
      }

      # The lint copy: a temporary directory under the ci-local cache, removed on exit. It is its own git
      # repository with the copied tree as its single commit, because prek selects files through git.
      lint_tmp=""
      lint_root=""
      lint_subject=""
      staged_files=()
      # shellcheck disable=SC2329 # invoked through the EXIT trap
      cleanup() {
        if [[ -n "$lint_tmp" ]]; then
          rm -rf -- "$lint_tmp"
        fi
      }
      trap cleanup EXIT

      prepare_lint_tree() {
        local cache="''${XDG_CACHE_HOME:-$HOME/.cache}/gwas-ci-local"
        mkdir -p "$cache"
        lint_tmp="$(mktemp -d "$cache/lint-tree.XXXXXX")"
        lint_root="$lint_tmp/$(basename "$root")"
        mkdir -p "$lint_root"
        case "$lint_source" in
          worktree)
            # What the next commit would carry: tracked files as edited, and untracked files not ignored.
            local path
            git ls-files -z --cached --others --exclude-standard | while IFS= read -r -d "" path; do
              if [[ -e "$path" || -L "$path" ]]; then
                printf '%s\0' "$path"
              fi
            done | sort -zu | tar --null -T - -cf - | tar -xf - -C "$lint_root"
            lint_subject="the working tree of $root (uncommitted edits and untracked, unignored files included)"
            ;;
          staged)
            # Exactly what `git commit` records: the index the hook names -- a temporary one under
            # `commit -a` or `commit <paths>` -- whose blobs git has already written. The prek stages then
            # check only the paths it adds or changes against HEAD.
            local index_env=()
            if [[ -n "$source_index" ]]; then
              index_env=(env GIT_INDEX_FILE="$source_index")
            fi
            "''${index_env[@]}" git checkout-index -a -f --prefix="$lint_root/"
            mapfile -d "" -t staged_files < <("''${index_env[@]}" git diff --cached --name-only -z --diff-filter=d)
            lint_subject="the index of $root (what the commit records; prek stages on ''${#staged_files[@]} staged path(s))"
            ;;
          *)
            # A commit exactly as a CI checkout materializes it, through a private index so the
            # checkout's own index and worktree list are untouched: HEAD, or --rev.
            local commit="''${lint_commit:-HEAD}"
            GIT_INDEX_FILE="$lint_tmp/index" git read-tree "$commit"
            GIT_INDEX_FILE="$lint_tmp/index" git checkout-index -a -f --prefix="$lint_root/"
            if [[ -n "$lint_commit" ]]; then
              lint_subject="commit $(git rev-parse --short "$lint_commit") of $root"
            else
              lint_subject="HEAD $(git rev-parse --short HEAD) of $root$(git diff --quiet HEAD 2>/dev/null || echo ', uncommitted edits excluded (--worktree lints them)')"
            fi
            ;;
        esac
        git -C "$lint_root" init -q
        git -C "$lint_root" add -A -f
        git -C "$lint_root" -c user.name=ci-local -c user.email=ci-local@localhost -c commit.gpgsign=false \
          commit -q --no-verify -m "ci-local lint copy"
      }

      tree_state() {
        # Content fingerprint of every file in the lint copy that differs from its commit, to name what a
        # stage rewrote.
        local path
        { git -C "$lint_root" diff --name-only HEAD; git -C "$lint_root" ls-files --others --exclude-standard; } \
          | sort -u | while IFS= read -r path; do
            printf '%s %s\n' "$path" "$(git -C "$lint_root" hash-object -- "$path" 2>/dev/null || echo deleted)"
          done | sort
      }

      rewritten_since() {
        comm -13 <(printf '%s\n' "$1") <(tree_state) | cut -d' ' -f1 | paste -sd' ' -
      }

      save_rewrites() {
        # Every auto-fix the stages made to the lint copy, as a patch against the linted tree.
        local patch="$out/lint-rewrites.patch"
        rm -f "$patch"
        if [[ -z "$lint_root" ]]; then
          return
        fi
        git -C "$lint_root" add -A -f
        if ! git -C "$lint_root" diff --cached --quiet HEAD; then
          git -C "$lint_root" diff --cached --binary HEAD >"$patch"
          echo "ci-local: auto-fixes the checkout would receive are saved in $patch"
        fi
      }

      # The files the prek stages run on: CI's --all-files, or under --staged the staged paths only. An
      # empty --files list would not mean "none" to prek, so the caller skips the stage instead.
      prek_scope=(--all-files)
      prek_label="--all-files"
      set_prek_scope() {
        if [[ "$lint_source" == staged ]]; then
          prek_scope=(--files "''${staged_files[@]}")
          prek_label="staged files"
        fi
      }

      stage_pre_commit() {
        banner "pre-commit (prek run $prek_label, nextflow-lint skipped)"
        if [[ "$lint_source" == staged && ''${#staged_files[@]} -eq 0 ]]; then
          record pre-commit SKIP "no added or changed path is staged"
          return
        fi
        local log="$out/pre-commit.log" before rewritten
        before="$(tree_state)"
        if run_logged "$log" env -C "$lint_root" SKIP=nextflow-lint prek run --show-diff-on-failure --color=always "''${prek_scope[@]}"; then
          record pre-commit PASS "$log"
        else
          rewritten="$(rewritten_since "$before")"
          record pre-commit FAIL "$log''${rewritten:+; hooks would rewrite: $rewritten}"
        fi
      }

      stage_nextflow_lint() {
        banner "nextflow-lint (prek run nextflow-lint $prek_label, $(nextflow -version 2>/dev/null | sed -n 's/.*version \([^ ]*\) build.*/Nextflow \1/p'))"
        if [[ "$lint_source" == staged && ''${#staged_files[@]} -eq 0 ]]; then
          record nextflow-lint SKIP "no added or changed path is staged"
          return
        fi
        local log="$out/nextflow-lint.log"
        if run_logged "$log" env -C "$lint_root" prek run nextflow-lint --show-diff-on-failure --color=always "''${prek_scope[@]}"; then
          record nextflow-lint PASS "$log"
        else
          record nextflow-lint FAIL "$log"
        fi
      }

      pinned_nf_core_version() {
        # linting.yml reads this key from .nf-core.yml and installs exactly that release.
        sed -n 's/^nf_core_version:[[:space:]]*//p' "''${lint_root:-$root}/.nf-core.yml" | tr -d "\"' \r" | head -1
      }

      stage_nf_core_lint() {
        local version
        version="''${CI_LOCAL_NF_CORE_VERSION:-$(pinned_nf_core_version)}"
        if [[ -z "$version" ]]; then
          record nf-core-lint FAIL "no nf_core_version in .nf-core.yml"
          return
        fi
        local mode=()
        if [[ -n "$release" ]]; then
          mode=(--release)
        fi
        banner "nf-core-lint (nf-core==$version on Python $ci_python''${release:+, --release})"
        local log="$out/nf-core-lint.log"

        # nf-core caches `nextflow config` output in $NXF_HOME/nf-core/, keyed only by a hash of the
        # pipeline's main.nf and config files. 4.0.3 stores `config -flat` keys there, 4.1 stores nested
        # `config -o json`, and each misreads the other's entry: the lint template that files_unchanged
        # renders hashes the same across releases, so a cache left by the dev shell's tools@dev nf-core
        # crashes 4.0.3 with KeyError 'manifest.name'. CI starts from an empty home, so give each nf-core
        # version its own cache and link every other entry (framework, plugins, secrets) to the real home.
        local real_home="''${NXF_HOME:-$HOME/.nextflow}"
        local lint_home="''${XDG_CACHE_HOME:-$HOME/.cache}/gwas-ci-local/nxf-home-nf-core-$version"
        mkdir -p "$real_home" "$lint_home/nf-core"
        local entry
        while IFS= read -r -d "" entry; do
          if [[ ! -e "$lint_home/''${entry##*/}" && ! -L "$lint_home/''${entry##*/}" ]]; then
            ln -s "$entry" "$lint_home/''${entry##*/}"
          fi
        done < <(find "$real_home" -mindepth 1 -maxdepth 1 ! -name nf-core -print0)

        # A private uv environment at the version CI installs, never the dev shell's nf-core. The dev
        # shell's PYTHONPATH carries its own Python's site-packages and breaks this interpreter, and the
        # GitHub variables are cleared so lint can never post a PR comment from here.
        local before rewritten status=PASS
        before="$(tree_state)"
        if ! run_logged "$log" env -u PYTHONPATH -u GITHUB_TOKEN -u GITHUB_COMMENTS_URL -u GITHUB_PR_COMMIT \
            NXF_HOME="$lint_home" \
            uvx --python "$ci_python" --from "nf-core==$version" \
            nf-core -l "$out/nf-core-lint.debug.log" pipelines lint "''${mode[@]}" \
            --dir "$lint_root" --markdown "$out/lint_results.md"; then
          status=FAIL
        fi
        # Lint applies its own auto-fixes (the RO-Crate description, for one) in place; here they land in
        # the copy, so name them rather than let them pass unseen.
        rewritten="$(rewritten_since "$before")"
        record nf-core-lint "$status" "$out/lint_results.md''${rewritten:+; lint would rewrite: $rewritten}"
      }

      stage_template_version() {
        banner "template-version"
        local pinned latest
        pinned="$(pinned_nf_core_version)"
        # CI compares against `nf-core --version` after an unpinned install, i.e. the latest PyPI release.
        latest="$(curl -fsSL --max-time 20 https://pypi.org/pypi/nf-core/json 2>/dev/null | jq -r '.info.version // empty' || true)"
        if [[ -z "$latest" ]]; then
          record template-version WARN "could not read the latest nf-core release from PyPI"
        elif [[ "$pinned" != "$latest" ]]; then
          record template-version WARN "template $pinned, latest nf-core $latest: CI posts an outdated-template comment (non-blocking)"
        else
          record template-version PASS "template $pinned is the latest nf-core"
        fi
      }

      only_ignored_changes() {
        # nf-test.yml's paths-ignore: a PR touching only these paths never starts the workflow.
        local path any=""
        while IFS= read -r path; do
          [[ -z "$path" ]] && continue
          any=1
          case "$path" in
            docs/*|*.md|*.png|*.svg|meta.yml|*/meta.yml) ;;
            *) return 1 ;;
          esac
        done < <({ git diff --name-only "$merge_base"; git ls-files --others --exclude-standard; } | sort -u)
        [[ -n "$any" ]]
      }

      stage_nf_test() {
        local selection=(--ci --verbose)
        local scope
        if [[ ''${#test_paths[@]} -gt 0 ]]; then
          scope="explicit paths: ''${test_paths[*]}"
        elif [[ -n "$run_all" ]]; then
          scope="all tests"
        else
          scope="changed since $base (merge base ''${merge_base:0:12})"
          selection+=(--changed-since "$merge_base")
          if only_ignored_changes; then
            banner "nf-test"
            record nf-test SKIP "every change matches nf-test.yml paths-ignore"
            return
          fi
        fi
        if [[ -n "$tag" ]]; then
          selection+=(--tag "$tag")
        fi

        # CI reads the fixtures from the source nf-test.yml pins, so do the same unless the caller already
        # chose a source or a materialized root. With no pin, leave GWAS_FIXTURE_SOURCE unset so the
        # materializer's default published branch applies, as it does in CI.
        if [[ -z "''${GWAS_TEST_FIXTURES:-}" && -z "''${GWAS_FIXTURE_SOURCE:-}" ]]; then
          local pinned_source
          pinned_source="$(sed -n 's/^[[:space:]]*fixture_source:[[:space:]]*\([^[:space:]#]*\).*/\1/p' .github/workflows/nf-test.yml | head -1)"
          if [[ -n "$pinned_source" ]]; then
            export GWAS_FIXTURE_SOURCE="$pinned_source"
          fi
        fi

        local profile
        local -a profile_list
        IFS=, read -r -a profile_list <<<"$profiles"
        for profile in "''${profile_list[@]}"; do
          banner "nf-test ($profile, $scope''${GWAS_FIXTURE_SOURCE:+, fixtures from $GWAS_FIXTURE_SOURCE})"
          local dry_log="$out/nf-test-$profile.dry-run.log"
          # The same discovery get-shards runs: a dry run decides whether anything is selected and how many.
          if ! run_logged "$dry_log" nf-test test --profile="+$profile" --dry-run "''${selection[@]}" "''${test_paths[@]}" >/dev/null; then
            record "nf-test:$profile" FAIL "dry-run discovery failed: $dry_log"
            continue
          fi
          if grep -q 'No tests to execute' "$dry_log"; then
            record "nf-test:$profile" PASS "no tests selected"
            continue
          fi
          local selected
          selected="$(sed -n 's/.*Executed \([0-9]*\) tests.*/\1/p' "$dry_log" | tail -1)"
          local count="$shards"
          # nf-test-parallel's own memory-derived default, computed here so it can also be capped the way
          # get-shards caps CI's matrix: at seven, and at the number of selected cases.
          if [[ -z "$count" ]]; then
            local mem_kb
            mem_kb="$(sed -n 's/^MemTotal:[[:space:]]*\([0-9]*\).*/\1/p' /proc/meminfo 2>/dev/null)"
            count=$(( ''${mem_kb:-0} / 1024 / 1024 / 4 ))
            if (( count > 6 )); then count=6; fi
            if (( count < 1 )); then count=1; fi
          fi
          if (( count > ci_max_shards )); then count=$ci_max_shards; fi
          if [[ -n "$selected" ]] && (( selected > 0 && count > selected )); then
            count=$selected
          fi
          echo "ci-local: ''${selected:-?} tests selected, $count shard(s)"
          local log="$out/nf-test-$profile.log"
          local shard_root="$out/nf-test-shards-$profile"
          if run_logged "$log" env NFT_PROFILE="+$profile" NFT_SHARD_ROOT="$shard_root" \
              nf-test-parallel "$count" "''${selection[@]}" "''${test_paths[@]}"; then
            record "nf-test:$profile" PASS "''${selected:-?} tests, $count shard(s); logs in $shard_root"
          else
            grep -h -E "SUCCESS:|FAILURE:" "$shard_root"/shard-*.log 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g; s/^/  /' || true
            record "nf-test:$profile" FAIL "shard logs in $shard_root"
          fi
        done
      }

      echo "ci-local: checkout $root at $(git rev-parse --short HEAD)$(git diff --quiet HEAD 2>/dev/null || echo ' (with uncommitted changes)')"
      echo "ci-local: base $base''${merge_base:+, merge base ''${merge_base:0:12}}''${release:+, release mode}"
      echo "ci-local: logs in $out"

      for stage in "''${stages[@]}"; do
        case "$stage" in
          pre-commit|nextflow-lint|nf-core-lint)
            prepare_lint_tree
            set_prek_scope
            echo "ci-local: linting a copy of $lint_subject"
            break
            ;;
        esac
      done

      for stage in "''${stages[@]}"; do
        case "$stage" in
          pre-commit) stage_pre_commit ;;
          nextflow-lint) stage_nextflow_lint ;;
          nf-core-lint) stage_nf_core_lint ;;
          template-version) stage_template_version ;;
          nf-test) stage_nf_test ;;
        esac
      done

      save_rewrites

      status=0
      printf '\n==> ci-local summary\n'
      for index in "''${!stage_names[@]}"; do
        printf '  %-4s  %-18s %s\n' "''${stage_results[index]}" "''${stage_names[index]}" "''${stage_notes[index]}"
        if [[ "''${stage_results[index]}" == FAIL ]]; then
          status=1
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
    ciLocal
    condaCli
    pkgs.apptainer
    pkgs.pre-commit
    pkgs.prek
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
