# Testing, CI, and developer tooling standards

Applies to `nf-test.config`, `tests/**`, `**/tests/*.nf.test`, `.github/**`, and the repo-hygiene dotfiles.

Rule tags: **[MUST]** violation is a review finding · **[SHOULD]** strong default, deviation needs a stated
reason · **[TOOLING]** a linter owns this.

Module- and subworkflow-submission testing for upstream `nf-core/modules` is owned by
`.agents/skills/nf-core-submission-test/` and `.agents/skills/nf-core-submission-review/`; those take
precedence for component tests. This document covers pipeline-level testing and repo tooling.

---

## 1. nf-test layout

- **[MUST]** `nf-test.config` follows the shared skeleton: _(all three)_

  ```groovy
  testsDir "."
  workDir System.getenv("NFT_WORKDIR") ?: ".nf-test"
  configFile "tests/nextflow.config"
  ignore 'modules/nf-core/**/tests/*', 'subworkflows/nf-core/**/tests/*'
  triggers '.github/workflows/nf-test.yml', 'nextflow.config', 'conf/**'
  plugins { load "nft-utils@<pinned>" }
  ```

- **[MUST]** Load `nft-utils` plus whichever domain plugin matches the pipeline's output types. All three do
  this; the domain plugin differs by output (`nft-bam`, `nft-vcf`, `nft-fasta`, `nft-csv`). For a GWAS
  pipeline expect `nft-csv` for tabular summary statistics.
- **[MUST]** `tests/nextflow.config` sets the test-data base-path params and carries
  `aws.client.anonymous = true` with its explanatory comment (S3 access on self-hosted runners).
  _(all three, identical)_
- **[MUST]** A `tests/.nftignore` glob file exists and is passed to `getAllFilesFromDir(..., ignoreFile:
'tests/.nftignore')` so non-deterministic outputs are excluded from content snapshots. _(all three)_
- **[MUST]** Pipeline-level tests live flat in `tests/` and are named by scenario, never `main.nf.test`
  (`tests/default.nf.test`, `tests/test_quantitative.nf.test`). Component-level tests use `main.nf.test`
  colocated under the component's own `tests/`, with scenario variants as a dotted infix
  (`main.binary.nf.test`). _(all three)_
- **[MUST]** Each `.snap` file sits beside its `.nf.test` with the same basename. _(all three)_
- **[SHOULD]** Test local modules and local subworkflows, not only the pipeline. Only rnaseq tests local
  modules; only rnaseq and sarek test local subworkflows, and both incompletely. This is the weakest area
  across all three reference pipelines — treat their practice as a floor, not a target.

## 2. nf-test file anatomy

- **[MUST]** Header order: `name` → `script` → selector (`workflow "X"` / `process "X"`) → `config` →
  `tag`(s) → `test(...)`. _(all three)_
- **[MUST]** Every test asserts success (`workflow.success` / `process.success`) _before_ any snapshot
  assertion, so a failure does not bury the console in a snapshot diff. _(sarek states this explicitly in a
  code comment; all three order it this way)_
- **[MUST]** `when { params { ... } }` sets `outdir = "$outputDir"` and little else. Scenario configuration
  belongs in `-profile` / `conf/test*.config`, not scattered across per-test param overrides. _(1/3 — chosen.
  mag is the strictest and the cleanest here: 0 of its 8 pipeline-level test files set anything but `outdir`.
  rnaseq sets `input` in 3 of 19, and sarek sets it in 53 of 60 through the shared scenario maps in
  `tests/lib/UTILS.groovy` — so this is a deliberate choice of mag's discipline, not a consensus.)_
  - **Exception — `params.input`.** A pipeline-level test whose subject _is_ the input contract may override
    `params.input`. A samplesheet-driven pipeline cannot exercise input validation without pointing the run
    at a deliberately malformed or edge-case samplesheet, and minting a `-profile` per bad samplesheet is
    worse than the override it would avoid. rnaseq does exactly this (`tests/bam_input.nf.test`,
    `tests/prokaryotic.nf.test`). Override `input` when the samplesheet is the thing under test; keep every
    other scenario knob in a profile.
- **[MUST]** Wrap assertions in `assertAll(...)`. _(all three)_
- **[MUST]** Tag every pipeline-level test `tag "pipeline"`, plus one tag naming the scenario or profile.
  _(all three; the three diverge on how much hierarchy to add beyond that)_
- **[SHOULD]** Once the suite passes roughly a dozen files, centralise tag/`when`/`then`/stub wiring in a
  shared `tests/lib/*.groovy` helper driven by declarative scenario maps, as sarek does. Retrofitting this
  later is expensive; rnaseq and mag both write every block longhand and repeat themselves heavily.

## 3. Snapshots and assertions

- **[MUST]** Capture the output tree in two paired forms, using the conventional variable names:
  a paths-only list (`getAllFilesFromDir(dir, relative: true, includeDir: true)` → `stable_name`) and a
  content-hash list (same call with `ignoreFile:` → `stable_path`). _(all three)_
- **[MUST]** Strip the Nextflow/pipeline version key from the versions YAML before snapshotting it. The
  helper name is plugin-version dependent (`removeFromYamlMap(path, "Workflow")` in rnaseq/sarek,
  `removeNextflowVersion(path)` in mag) — confirm which the pinned `nft-utils` version exposes rather than
  copying a snippet across pipelines.
- **[MUST]** Snapshot per output area under a labelled `.match('<area>')` rather than dumping the whole tree
  into one unlabelled snapshot:

  ```groovy
  { assert snapshot(stable_name_qc, stable_path_qc).match('qc') },
  { assert snapshot(stable_name_assoc, stable_path_assoc).match('association') },
  ```

  _(mag's approach; rnaseq and sarek use a single whole-tree snapshot. Labelled per-area snapshots produce
  readable diffs as the pipeline grows, which is the whole point of committing them.)_

- **[MUST]** Do not leave the superseded approach commented out alongside the new one. mag leaves dead
  whole-tree snapshot code in every test file and it is a lint-worthy smell.
- **[MUST]** Use domain-aware content extraction rather than raw file hashes where a format has unstable
  bytes — plugin accessors like `path(f).csv(sep:'\t').rowCount`, or explicit line-slicing to skip an
  unstable header (`file.readLines()[2..-1].join('\n').md5()`). _(all three, per their output types)_
- **[MUST]** `.snap` files are committed to git, and are excluded from whitespace-fixing pre-commit hooks
  via `.*\.snap$`. _(all three, identical)_
- **[SHOULD]** Assert on a log tail with a regex (`.readLines().last() ==~ /.../`) instead of snapshotting
  logs wholesale. _(mag)_

## 4. Stub tests

- **[MUST]** Decide the stub policy explicitly and apply it uniformly. Two coherent models exist:
  - duplicate each scenario with a `" - stub"` name suffix and `options "-stub"`, keeping full snapshot
    assertions (rnaseq); or
  - drive stubs from a scenario flag and deliberately narrow assertions to the file tree plus success,
    skipping content checks (sarek).

  mag has no nf-test stub coverage at all — do not take its silence as permission to skip.

- **[MUST]** Independently of nf-test stubs, `download_pipeline.yml` stub-runs the freshly downloaded
  pipeline with a non-stub fallback. This is present in all three and is a separate concern.

## 5. CI workflows

- **[MUST]** The standard workflow set is present: `linting.yml`, `linting_comment.yml`, `branch.yml`,
  `download_pipeline.yml`, `clean-up.yml`, `fix_linting.yml`, `release-announcements.yml`,
  `template-version-comment.yml`, plus AWS/cloud full-test workflows. _(all three)_
- **[MUST]** `fix-linting.yml` is named with an underscore: `fix_linting.yml`. _(all three renamed it)_
- **[MUST]** Replace the template `ci.yml` with a sharded `nf-test.yml`. All three do this, with the same
  structure: a first job computing shard count via a local `./.github/actions/get-shards` composite action
  (`nf-test --dry-run --ci --changed-since HEAD^`, capped at N), then a fan-out job with
  `matrix: { shard, profile: [conda, docker, singularity], NXF_VER: [<pinned>, latest-everything] }`,
  `exclude` rules dropping conda/singularity off the default branch, `continue-on-error: true` only for
  `latest-everything`, and a `confirm-pass` fan-in job aggregating `needs.*.result`.
- **[MUST]** Concurrency block on every CI-shaped workflow, verbatim: _(all three)_

  ```yaml
  concurrency:
    group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
    cancel-in-progress: true
  ```

- **[MUST]** `linting.yml` runs exactly
  `nf-core -l lint_log.txt pipelines lint --dir ${GITHUB_WORKSPACE} --markdown lint_results.md`, adding
  `--release` when the base ref is the default branch, with the `nf-core` version read dynamically from
  `.nf-core.yml`'s `nf_core_version` key rather than hardcoded. _(all three, exact match)_
- **[MUST]** `if: github.repository == '<org>/<repo>'` guards on `branch.yml`, the AWS/cloud test workflows,
  and `fix_linting.yml`. Not on `nf-test.yml`, `linting.yml`, or `download_pipeline.yml`. _(all three)_
- **[MUST]** Pin `actions/*` and third-party actions to a full commit SHA with a trailing version comment
  (`actions/checkout@93cb6ef… # v5`). nf-core's own reusable actions are pinned by tag
  (`nf-core/setup-nextflow@v2`), which is the accepted exception. _(all three)_
- **[MUST]** Pin the same action to the same version across sibling workflows. rnaseq pins
  `actions/checkout` to three different versions across `nf-test.yml`, `nf-test-arm.yml`, and
  `nf-test-gpu.yml` — a concrete, checkable defect to avoid.
- **[MUST]** No branch-pinned actions (`@main`, `@master`). Both sarek and mag carry
  `eWaterCycle/setup-apptainer@main` and `rzr/fediverse-action@master`; these are known repeat offenders,
  not a convention to copy.
- **[SHOULD]** `permissions:` declared only where needed — `clean-up.yml` gets
  `issues: write, pull-requests: write`; other workflows rely on defaults. _(all three)_
- **[SHOULD]** Lowercase-hyphenated job ids, sentence-case step names, and a matrix-templated job display
  name (`"${{ matrix.profile }} | ${{ matrix.NXF_VER }} | ${{ matrix.shard }}/…"`). _(all three)_

## 6. Lint and format tooling

- **[MUST]** `.prettierrc.yml` is byte-identical to the reference set: _(verified identical in all three)_

  ```yaml
  printWidth: 120
  tabWidth: 4
  overrides:
    - files: "*.{md,yml,yaml,html,css,scss,js,cff}"
      options:
        tabWidth: 2
  ```

- **[MUST]** `.prettierignore` covers `email_template.html`, `.nextflow*`, `work/`, `data/`, `results/`,
  `.DS_Store`, `testing/`, `testing*`, `*.pyc`, `bin/`, `.nf-test/`, `ro-crate-metadata.json`,
  `modules/nf-core/`, `subworkflows/nf-core/`, plus any JSON notification templates the pipeline ships.
  _(all three)_
- **[MUST]** `.pre-commit-config.yaml` runs `pre-commit/mirrors-prettier` and `pre-commit/pre-commit-hooks`
  (`trailing-whitespace` with `--markdown-linebreak-ext=md`, `end-of-file-fixer`), both excluding
  `ro-crate-metadata.json`, `modules/nf-core/.*`, `subworkflows/nf-core/.*`, and `.*\.snap$`. _(all three)_
- **[SHOULD]** Add the `seqeralabs/nf-lint-pre-commit` hook and a matching CI step running
  `nextflow lint`. Only rnaseq pairs a local hook with a CI workflow this way, and it is the practice that
  makes the formatting rules in `nextflow-code-style.md` self-enforcing rather than review-enforced.
- Note: **`.editorconfig` is absent from all three** (verified), and **no Python lint config
  (`ruff.toml`, `pyproject.toml`) exists in any of them** despite all three shipping `bin/` Python scripts.
  Adding either is a deliberate improvement, not a gap being filled — do not raise a review finding for
  their absence, and do not assume nf-core tooling enforces Python style.

## 7. Repo hygiene files

- **[MUST]** `.gitattributes` byte-identical to: _(verified identical in all three)_

  ```gitattributes
  *.config linguist-language=nextflow
  *.nf.test linguist-language=nextflow
  modules/nf-core/** linguist-generated
  subworkflows/nf-core/** linguist-generated
  ```

- **[MUST]** `.gitignore` covers at minimum `.nextflow*`, `work/`, `data/`, `results/`, `.DS_Store`,
  `testing/`, `testing*`, `*.pyc`, `null/`, `.nf-test*`. It must **not** ignore `.snap` files.
  _(all three)_
- **[MUST]** `.devcontainer/devcontainer.json` uses `nfcore/devcontainer:latest`, `remoteUser: root`,
  `privileged: true`, and an `onCreateCommand` running `.devcontainer/setup.sh`. _(all three, identical)_
- **[SHOULD]** `.vscode/settings.json` stays minimal — the reference set contains only
  `{"markdown.styles": ["public/vscode_markdown.css"]}` and no editor formatting settings. _(all three)_
- **[SHOULD]** Add a `CODEOWNERS` with path-specific rules rather than a single blanket owner — sarek routes
  `*.nf.test*` and `.github/workflows/` to dedicated teams, which is the only model of the three that
  scales. (rnaseq has no CODEOWNERS at all; mag has one blanket rule.)
