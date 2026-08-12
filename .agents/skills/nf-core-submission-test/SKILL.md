---
name: nf-core-submission-test
description: Validate or debug nf-core module and subworkflow submissions with nf-core lint/test and nf-test commands.
---

Read `../references/nf-core-guidance-sources.md` and, for upstream submission work,
`../references/nf-core-component-workspaces.md`. Treat this skill as authoritative for component validation.

Use this skill when the user asks to run, debug, update, or summarize tests for an upstream module or subworkflow submission.

## Standards cache fallback

If fallback is needed, relevant topic hints are:

- `docs/nf-core-standards/module-testing.md`
- target-specific `docs/nf-core-standards/module-main-nf.md` or `docs/nf-core-standards/subworkflows.md`
- `docs/nf-core-standards/test-datasets.md`

## Workflow

1. Identify whether the target is a module or subworkflow and run commands from its submission worktree root.
2. Inspect recent changes and existing `tests/main.nf.test`, snapshots, and `nextflow.config` before running expensive checks.
3. After a `.nf` edit, format with
   `nextflow lint -format -sort-declarations -spaces 4 -harshil-alignment`.
4. For quick debugging, run `nf-test test <test-file> --profile=docker --verbose`.
5. For standard validation, run `nf-core modules lint <tool[/subtool]>` or
   `nf-core subworkflows lint <name>`, then the matching wrapper test.
6. For PR readiness, run the target wrapper test under Docker, Singularity, and Conda, for example
   `nf-core modules test <tool[/subtool]> --profile docker` and the corresponding two profile commands.
   Use `nf-core subworkflows test <name>` for a subworkflow.
7. Update snapshots only when output changes are intentional and understood.
8. If a profile cannot run due to missing local runtime support, report the exact blocker and leave the PR
   readiness state incomplete.

## Snapshot and assertion pattern

- For module tests with stable emitted outputs, prefer `assert snapshot(sanitizeOutput(process.out)).match()` over manually snapshotting selected channels plus `versions`. This captures the complete named output contract and keeps snapshots readable.
- If only specific emitted channels are unstable, keep the full-output pattern and pass those emit names via `unstableKeys`, e.g. `sanitizeOutput(process.out, unstableKeys: ["log", "html"])`.
- Use narrower semantic snapshots only when full sanitized output is unstable or low-signal (binary files, container-dependent metadata, nondeterministic logs, large scientific results). When you project, still assert success, output/channel names, metadata identity, file presence, and versions explicitly.
- Keep targeted assertions alongside full-output snapshots when they test behavior not obvious from emitted outputs (`.command.sh` option construction, expected failures, selected stable file content). Keep tests minimal but contract-complete — missing output coverage is still a testing gap.
- Do not pad a test with assertions the sanitized snapshot already enforces. A `snapshot(sanitizeOutput(process.out)).match()` already captures output-channel presence, cardinality, metadata identity, and filenames, so drop redundant `process.out.<ch>.size() == 1`, `fileName.toString() == "..."`, and per-file path checks — reviewers flag them as unnecessary. Never assert a file is non-empty (`readLines().size() > 0`, size `> 0`): nf-core lint already fails a snapshot whose md5 is the empty-file digest (`d41d8cd98f00b204e9800998ecf8427e`), so an empty output cannot slip through. The canonical minimal shape is `then { assert process.success; assertAll({ assert snapshot(sanitizeOutput(process.out)).match() }) }`.

## Configurable optional CLI args in tests

For module nf-tests that need configurable optional CLI arguments, use the current nf-core `gcta/reml` style rather than editing the module:

- Keep one minimal module-local `tests/nextflow.config`, load it once near the top of `main.nf.test` with `config "./nextflow.config"`, define safe defaults (`params { module_args = "" }`), and map them into process extensions (`ext.args = { params.module_args ?: "" }`).
- In individual tests, set `params { module_args = "--some-option" }` only when the scenario needs extra arguments; default tests rely on the empty default.
- Keep this file narrowly scoped to real nf-test overrides (`module_args`, `ext.prefix`, profile-specific settings, test-matrix controls). Do not keep `tests/nextflow.config` solely for repository-default settings such as `params.modules_testdata_base_path`.
- Never set local `nf-core/test-datasets` paths in a committed `tests/nextflow.config`. Keep the standard portable test-data parameters intact; local path workarounds belong outside committed test configs (see `NF_MODULES_TESTDATA_BASE_PATH` in `nf-core-submission-pr`).

## Debugging rules

- Prefer fixing the module/subworkflow contract over weakening assertions.
- Do not synthesize inline fixture files when an existing module can generate the needed intermediate in `setup {}` without making tests unstable.
- Keep tests deterministic; avoid assertions that depend on timestamps, random IDs, or unordered output unless normalized.
- Keep each test case free of unnecessary conditional logic: nf-test inputs are fixed per case, so `if`/ternary branches that select or vary the input are cruft — reviewers ask to delete them and pass the fixed input directly (#11009).
- Cover each distinct output-file type/extension the tool can produce with a test, not just one representative case — a reviewer asked for an explicit test exercising a `.qassoc` output that other cases did not produce (#10947).
- For gzip stubs, create valid compressed files.
- `nf-core modules test` runs nf-test twice to check snapshot stability; use `--update` only when outputs changed intentionally. `--once` is for fast local debugging only, not final evidence — PR readiness still requires the full Docker/Singularity/Conda wrapper matrix.
- Green `pull_request` lint is not the final word: the merge queue re-lints against the current `master` tip with whatever lint version master pins, so a PR can pass its own checks and still be evicted (e.g. stricter `meta.yml` `containers:` rules). Lint locally with the CI-pinned `nf-core` version (see `nf-core-local-tool-version-lint` memory) and, before enqueuing, merge current `master` in — see the merge-queue section in `nf-core-submission-pr`.

## Completion

Report exact commands, pass/fail results, changed snapshots, unresolved profile gaps, and the next concrete blocker if tests still fail.
