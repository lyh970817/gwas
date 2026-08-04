# Final Report: Peripheral polish research and implementation

## Outcome

Implemented the approved nf-core peripheral polish on the independent
`codex/peripheral-polish-20260804` branch without touching the dirty primary
checkout. The pipeline now publishes a truthful Tower report target, a branded
and route-aware MultiQC report, a compact analysis-plan table, tailored methods
and citations, a maintained route map, stronger troubleshooting guidance, and
the supplied contributor identity.

## Accepted Results

- Tower advertises only the report the pipeline actually publishes:
  `multiqc/multiqc_report.html`.
- The bundled nf-core/gwas logo is the MultiQC default while an explicit user
  logo remains authoritative.
- MultiQC includes an "Analysis plan" table with one deterministically ordered
  row per validated `analysis_id`. It describes requested routes, not task
  completion or scientific findings.
- Methods prose and bibliography entries are derived from the union of validated
  association and heritability selectors. Shared LDAK citations are deduplicated.
- The route map source, SVG, PNG, and regeneration guide are versioned together.
- Usage documentation includes phase-oriented troubleshooting and escalation
  artifacts; output documentation explains the new report sections.
- `lyh970817 <lyh970817@yandex.com>` is recorded as a contributor.
- Four local issues capture the deliberately deferred reporting, screenshot, and
  release-metadata work.

## Rejected Results

- No QQ plots, heritability-result panels, screenshots, public full-result
  narrative, or final release identity were fabricated without source artifacts.
- No CODEOWNERS file was added: contributor identity is not evidence of review
  responsibility or path ownership.
- Tower entries for trace, timeline, DAG, and report files were removed because
  the pipeline does not currently publish stable paths for them.

## Conflicts Resolved

- MultiQC reserves the custom-table row key as its sample column. The displayed
  heading is renamed to "Analysis ID" with `pconfig.col1_header`; the exported
  data file retains MultiQC's canonical `Sample` field.
- The first route-map draft implied a false serial dependency between genotype,
  matrix, and phenotype preparation. The accepted map instead uses parallel
  association and heritability preparation bundles.
- A reporting branch initially appeared before analysis in the numbered diagram.
  Reporting is now documented alongside the map rather than represented with a
  misleading execution-order edge.

## Verification Evidence

- `nf-test-parallel 3 --verbose`: 47 + 46 + 46 tests passed; zero failures.
- `nf-test test --profile=+docker --verbose`: all 139 tests passed in 2540.956
  seconds; no obsolete snapshots were reported.
- Focused `tests/default.nf.test` and heterogeneous `tests/full_scale.nf.test`
  both passed against the final report assertions.
- `nextflow lint ...`: 50 files had no errors; only the existing unused-variable
  warnings in `modules/local/normalise_phenotypes/main.nf` remain.
- `nf-core pipelines lint`: passed and refreshed RO-Crate metadata.
- Prettier checks, `git diff --check`, YAML parsing, strict metro-map rendering,
  and visual image inspection passed.
- An independent implementation review was repeated after correcting its table,
  diagram, branding-test, and methods-coverage findings.

## Remaining Risks

- `workflow.commandLine` is HTML-escaped before insertion into the methods
  section, but the test harness does not expose a clean way to launch a pipeline
  test with HTML-significant raw command-line text. The function is therefore
  reviewed and exercised with ordinary command lines, not an adversarial launch.
- The route map is maintained source, not derived automatically from the DAG; its
  regeneration guide and strict renderer validation are the drift controls.
- Deferred local tracker files are intentionally ignored and exist only in this
  worktree until the user chooses to promote or implement them.

## Reusable Follow-up

- Research packets under `results/` record the reference-pipeline evidence,
  official fallbacks, accepted patterns, anti-patterns, and verification advice.
- Deferred issues live under `.scratch/reporting-and-release-polish/issues/`:
  association diagnostics, heritability reporting, visual/public results, and
  first-release identity/metadata.
- The metro-map maintenance contract is documented in `docs/dev/metro_map.md`.
