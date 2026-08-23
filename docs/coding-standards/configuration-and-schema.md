# Configuration and parameter-schema standards

Applies to `nextflow.config`, `conf/*.config`, `nextflow_schema.json`, `assets/*.json`, and `.nf-core.yml`.

---

## 1. `nextflow.config`

- **[MUST]** Every config file — including every `conf/test*.config` — opens with the same two-tier banner.
  mag breaks this in 4 of its 9 test configs by using `========` instead, and it reads as drift:

  ```groovy
  /*
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      nf-core/gwas Nextflow config file
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      Default config options for all compute environments
  ------------------------------------------------------------------------------------------
  */
  ```

  _(all three)_

- **[MUST]** Organise `params { }` into comment-headed subgroups (`// Input options`, `// References`,
  `// QC options`, …), each header unique and used once. mag repeats two headers non-contiguously — a
  navigability defect. Align `=` within each subgroup, not globally across the whole block. _(all three)_

- **[MUST]** The params block ends with the same three boilerplate groups, in order:
  `// Boilerplate options` → `// Config options` → `// Schema validation default options`. _(all three)_

- **[MUST]** `process.shell` pinned to strict bash, with the per-flag comments retained: _(all three)_

  ```groovy
  process.shell = ["bash", "-C", "-e", "-u", "-o", "pipefail"]
  ```

- **[MUST]** `validation.defaultIgnoreParams` — the nf-schema key. Never the deprecated
  `validationSchemaIgnoreParams`, and never the `nf-validation` plugin. _(verified: all three use
  `defaultIgnoreParams`, zero occurrences of the legacy key)_

- **[MUST]** `docker.runOptions`, `cleanup`, and
  `nextflow.enable.configProcessNamesValidation = true` live inside profile blocks (`docker`, `debug`),
  never at top level. The top-level default is
  `nextflow.enable.configProcessNamesValidation = false` with the standard explanatory comment.
  _(all three)_

- **[MUST]** `includeConfig` order: `conf/base.config` first and unconditional → test-profile includes
  inside `profiles { }` → institutional custom configs behind the offline guard → igenomes ternary →
  module config last. _(all three)_

- **[MUST]** `manifest { }` carries `name`, `contributors[]` (with `github` and `orcid`), `homePage`,
  `description`, `mainScript`, `defaultBranch`, `nextflowVersion` pinned with the `!>=` strict prefix,
  `version`, `doi`. _(all three)_

- **[MUST]** Standard profile set present and in the conventional order: `debug, conda, mamba, docker,
arm64, emulate_amd64, singularity, podman, shifter, charliecloud, apptainer, wave`, then
  pipeline-specific profiles, then `test*` profiles last. _(all three)_

- **[MUST]** All four of `timeline`, `report`, `trace`, `dag` enabled, writing under
  `${params.outdir}/pipeline_info/` with `${params.trace_report_suffix}`. _(all three)_

- **[MUST]** `env { }` sets exactly `PYTHONNOUSERSITE`, `R_PROFILE_USER`, `R_ENVIRON_USER`,
  `JULIA_DEPOT_PATH`. _(all three, identical)_

- **[MUST]** All container registries default to `'quay.io'`. _(all three)_

## 2. Parameter naming and defaults

- **[MUST]** `snake_case` throughout. No camelCase params anywhere in any of the three.
- **[MUST]** Never default a string or path param to `''`. Use `null` for an optional file/path or a
  tri-state selector, `false` for a genuine binary toggle, and a real literal where a sensible default
  exists. _(verified: zero `''` defaults across all three)_
- **[MUST]** Pick one toggle polarity per feature area and hold it. mag mixes `skip_binqc` with sibling
  `run_busco` / `run_checkm` for the _same_ feature area — the clearest naming defect in the reference set.
  - `skip_*` — stage is on by default, prefix turns it off.
  - `run_*` / `use_*` — stage is off by default, prefix turns it on.
- **[MUST]** `save_*` for "persist an intermediate that is normally discarded", always boolean, default
  `false`. _(all three)_
- **[SHOULD]** Suffix every tool-choice enum param with `_tool` (`assoc_tool`, `ld_tool`). mag does this
  consistently; rnaseq mixes `ribo_removal_tool` with bare `aligner` / `trimmer` and it is harder to scan.
- **[SHOULD]** For a pipeline with more than about ten combinable optional tools, a single CSV-string param
  validated by an anchored regex (sarek's `tools`) is an accepted alternative to per-tool booleans. Below
  that threshold prefer per-tool params, because each one can then carry its own schema `description` and
  `help_text` — a CSV token cannot.
- **[SHOULD]** Name file/path params consistently by role: `<tool>_db` for databases, `*_reference` for
  reference genomes/panels. None of the three is fully internally consistent; sarek's `<tool>_<artifact>`
  scheme is the cleanest model.
- Note: none of the three demonstrates a deprecated-param shim. There is no convention to inherit here —
  if one is needed, take it from the current `nf-core/tools` template rather than from these pipelines.

## 3. `conf/base.config`

- **[MUST]** No `check_max()` function. It is fully retired — verified absent from all three.
- **[MUST]** No `resourceLimits` in `base.config`. Resource _capping_ belongs in `conf/test*.config`;
  `base.config` defines label-based _scaling_ only. _(all three, once terminology is normalised)_
- **[MUST]** Default (unlabelled) process resources set as `task.attempt`-scaled closures, before any
  label block. _(all three)_
- **[MUST]** All six standard labels present with strictly increasing cpu/memory/time:
  `process_single` < `process_low` < `process_medium` < `process_high`; plus `process_long` (time only) and
  `process_high_memory` (memory only). _(all three)_
- **[MUST]** `errorStrategy` retries on the standard transient exit statuses
  (`task.exitStatus in ((130..145) + 104 + 175)`) and finishes otherwise, with `maxErrors = '-1'`.
  _(all three)_
- **[MUST]** `withLabel:` blocks precede `withName:` blocks, and selectors in `base.config` are bare process
  names or bare regex alternations — never fully-qualified `WORKFLOW:SUBWORKFLOW:PROCESS` paths.
  _(all three)_
- **[MUST]** Remove the template's `// TODO nf-core: Check the defaults for all processes` comment once
  defaults are actually reviewed. Both rnaseq and sarek still carry it, unresolved.
- **[SHOULD]** A `process_gpu` label is a legitimate non-template extension where GPU-capable tools exist —
  all three independently converged on the same name and shape.

## 4. Module configs (`conf/modules/*.config`)

- **[MUST]** One config file per method family under `conf/modules/`, loaded by `includeConfig` from
  `nextflow.config`. There is no `conf/modules.config`.

  This reverses the rule this section originally carried, which required the single file and called the
  split "a scaling pattern for very large pipelines … do not reach for it before the single file is
  genuinely unmanageable". It was reversed on 2026-07-28 by the ticket that added the first association
  route, for a reason the size argument does not cover: this pipeline has seven method families
  (PLINK 2, REGENIE, two GCTA routes, three LDAK routes, GWASLab harmonisation), each arriving in its own
  ticket, and the property being bought is that a route ships as a **new file** rather than as an edit to
  a file every other route also edits. That is a merge-conflict and review-scope property, not a
  line-count one. The split is 2 of 3 in the reference set (rnaseq 32 files, sarek 39) so it is not
  exotic; mag's monolith is 41,970 bytes, which is what the single file becomes.

  Two obligations come with it, both verified against `nf-core pipelines lint` 4.1.0.dev0:
  - `.nf-core.yml` needs **both** `lint.files_exist: - conf/modules.config` (the `files_exist` check lists
    it as a required file) and `lint.modules_config: false` (the `modules_config` check reads the file to
    match `withName:` selectors against the workflow scripts). rnaseq and sarek both carry exactly this
    pair. One without the other still fails.
  - The process-wide default `publishDir` moves to `nextflow.config`, because it belongs to no method
    family. It is set `enabled: false` there: the published layout is organised by scientific stage, which
    no process-name-derived path can produce, and each per-family file opts its own processes in. sarek
    declines to have a default at all; mag keeps one and disables it. Do **not** leave a
    process-name-derived default enabled — it silently publishes every new module's intermediates under
    `outdir/<first-word-of-process-name>/`.

- **[MUST]** Order the `includeConfig` lines by pipeline stage and say so in a comment: a later file's
  `withName` selector wins where two match the same process. _(rnaseq's wording, worth copying verbatim)_
- **[MUST]** Each file uses the config banner defined in §1, followed by a `// STAGE NAME` comment.
- **[MUST]** Build multi-flag `ext.args` as a list joined and trimmed, never by string concatenation:

  ```groovy
  ext.args = [
      "--maf ${params.maf_threshold}",
      "--geno ${params.geno_threshold}",
      params.keep_allele_order ? "--keep-allele-order" : '',
  ].join(' ').trim()
  ```

  _(all three; verified 12 / 6 / 16 occurrences of the `.join(' ').trim()` idiom)_

- **[MUST]** Suppress publishing of `versions.yml` with the verbatim idiom: _(all three; 8 / 31 / 30
  occurrences)_

  ```groovy
  saveAs: { filename -> filename.equals('versions.yml') ? null : filename }
  ```

- **[MUST]** Order `withName:` blocks by pipeline stage within a file, and load `conf/modules/multiqc.config`
  last. _(all three)_
- **[MUST]** Use bare quoted process-name selectors by default (`withName: 'PLINK2_QC'`). Escalate to a
  fully-qualified `.*:SUBWORKFLOW:PROCESS` selector only where the same process runs from more than one
  subworkflow context and needs different settings per call site. Always quote the selector — sarek has one
  unquoted bare symbol and it is inconsistent with every other line in the repo.
- **[SHOULD]** Prefer ternaries inside `ext.args` / `ext.prefix` / `publishDir.enabled` closures over
  top-level `if (params.x) { }` blocks wrapping a `withName:` block. mag has zero such `if` blocks.
- **[SHOULD]** `ext.prefix` as a static string for simple cases; as a closure interpolating the meta fields
  that actually distinguish the output when a process fans out across several axes.
- **[SHOULD]** A further `// STAGE NAME` banner comment per stage inside a file that covers more than one.
  Superseded for the one-stage-per-file case by the banner rule above.

## 5. `conf/test*.config`

- **[MUST]** Set `process.resourceLimits` near the top of every non-`_full` test config
  (`[cpus: 4, memory: '15.GB', time: '1.h']` or similar). _(all three)_
- **[MUST]** Keep `params { }` minimal: `config_profile_name`, `config_profile_description`, test-data
  paths, and only the feature flags that specific scenario needs. Never redefine unrelated defaults.
  _(all three)_
- **[MUST]** 1:1 naming between profile name and config filename (`test_gwas_binary` ↔
  `conf/test_gwas_binary.config`). _(all three)_
- **[SHOULD]** Pin test-data paths to a specific `nf-core/test-datasets` commit rather than a branch, so CI
  is reproducible. _(rnaseq)_
- **[SHOULD]** A small `process { withName: X { ext.args = ... } }` block inside a test config is acceptable
  and expected for CI determinism (fixed seeds, disabled timestamps). _(all three)_

## 6. `nextflow_schema.json`

- **[MUST]** `"$schema": "https://json-schema.org/draft/2020-12/schema"` and `"$defs"` — never the legacy
  `"definitions"` key. _(verified: all three)_
- **[MUST]** Top-level key order: `$schema`, `$id`, `title`, `description`, `type`, `$defs`, `allOf`.
  _(all three)_
- **[MUST]** `allOf` references groups in exactly the same order they are declared in `$defs`.
  _(all three, no exceptions)_
- **[MUST]** Every `$defs` group has a `fa_icon`, including pipeline-authored groups. mag gives icons only
  to the four template groups and none to its ten own groups; sarek is the model here.
- **[MUST]** Every `description` is a capitalised sentence ending in a period. mag violates this in 45 of
  173 descriptions — treat it as a checkable rule, not a suggestion.
- **[MUST]** Only `input_output_options` declares a group-level `required` array, and it requires only
  `["outdir"]`. The top-level schema describes individually optional input paths; the linked input-family
  rules below are cross-parameter runtime validation and must not be misrepresented as unconditional JSON-Schema
  requirements.
- **[MUST]** `hidden: true` is reserved for `institutional_config_options` and `generic_options`
  boilerplate, plus at most one or two genuinely internal knobs. Never on a user-facing scientific or
  tool parameter, and never on `help`, `help_full`, `show_hidden`, `multiqc_title`, or
  `multiqc_methods_description`. _(all three)_
- **[MUST]** `outdir` is `type: string`, `format: directory-path`, listed in `required`, never `hidden`,
  never given a `default`. _(all three)_
- **[SHOULD]** Keep the standard group names and put them in the conventional position:
  `input_output_options` first, `reference_genome_options` early, `institutional_config_options` and
  `generic_options` last, pipeline-stage groups in between.
- Note: none of the three encodes cross-parameter conditional logic (`if`/`then`, `dependentRequired`) in
  `nextflow_schema.json` — that lives in runtime validation. Input-manifest schemas use it only for
  relationships local to one row.

## 7. `assets/schema_*_manifest.json`

### Pipeline relational-input contract

- **[MUST]** A run supplies either the linked `cohort_manifest` plus `analysis_manifest` family, a
  `summary_statistics_manifest`, or both. `cohort_manifest` and `analysis_manifest` are an inseparable pair.
  `relationship_manifest`, `reference_catalog`, and `method_options` are optional at the parameter layer and
  become necessary only when selected requests need them. Enforce these relationships in the linked-manifest
  validation pass so summary-only runs remain valid.
- **[MUST]** `summary_statistics_manifest` is the single declaration surface for both external and
  pipeline-generated summary results. Every row has one `summary_statistics_id` and exactly one origin family:
  either complete external `source` / `source_mode` / `source_format` fields plus declared trait, build,
  ancestry, and source-method metadata, or a complete `producer_analysis_id` /
  `producer_association_method` pair. The two origin families are mutually exclusive.
- **[MUST]** An internal summary ID is exactly
  `<producer_analysis_id>--<producer_association_method>`. The producer analysis must exist and must select that
  association method. An external ID may be researcher-defined but may not collide with an internal deterministic
  ID.
- **[MUST]** An internal-summary row leaves `trait_id`, `trait_type`, `genome_build`, `ancestry`,
  `source_method`, `source_release`, `population_prevalence`, and `sample_prevalence` blank. The validator
  inherits trait/build/ancestry and both prevalence values from the producer analysis, derives `source_method`
  from the producer association method, and records no invented release. External rows declare their own values.
- **[MUST]** Summary-level unary selectors live in the unified row's `heritability_methods` field for both
  origins. The analysis manifest's `heritability_methods` remains the selector for individual-level unary
  estimators; it does not implicitly select SumHer or LDSC H2 for every association result an analysis produces.
- **[MUST]** `sample_prevalence` means the binary-trait sample case fraction and is distinct from
  `population_prevalence`. Quantitative analyses and summaries leave both blank. An internal summary inherits
  both values from its producer; an external binary summary declares whichever values are known. Method-specific
  routing decides whether either value is consumed and must not fabricate the missing one.
- **[MUST]** Relationship examples use readable `left--right` IDs, for example
  `giant_height_2025--consortium_t2d_2026`, while treating `relationship_id` as an opaque user identity. The
  endpoint columns—not parsing the ID—define the pair. Pair request IDs remain
  `<method>--<relationship_id>`, for example
  `ldsc_rg--giant_height_2025--consortium_t2d_2026`.

- **[MUST]** `meta` is always an **array**, even for a single field: `"meta": ["id"]`. rnaseq has one
  bare-string `"meta": "percent_mapped"` and it is a copy-paste defect. _(all three otherwise)_
- **[MUST]** Row-uniqueness uses the nf-schema keyword `uniqueEntries: ["col1", "col2"]`, **not** the
  generic JSON-Schema `uniqueItems`. _(verified: `uniqueEntries` used in sarek and mag, `uniqueItems`
  appears zero times in all three — `uniqueItems` only expresses whole-row uniqueness and is the wrong tool)_
  - **Exception — when an error message must name the row and column.** `uniqueEntries` is only honoured at
    the top level of the schema, as a sibling of `items`; sarek places it _inside_ `items`, where nf-schema
    discards it silently with no error and no warning, so that usage is a no-op rather than a precedent.
    Placed correctly it does fire, but its message names neither a column nor a file row and renders the
    offending pair as a Groovy map — measured against nf-schema 2.5.1:
    `-> Entry 2: Detected duplicate entries: [analysis_id:dup_id]`. It also runs _before_ the Groovy
    validation pass, so it preempts any repo-side duplicate check rather than complementing it. Where a
    spec requires every validation error to name the offending row and field — as this pipeline's input
    contract does — keep the duplicate check in the Groovy pass and do not add `uniqueEntries`. The spec
    requirement wins over this rule; `uniqueItems` remains wrong in every case.
- **[MUST]** Every property carries a specific, human-readable `errorMessage` quoting the allowed values or
  extensions. mag omits it on two columns and those are the ones that produce unhelpful failures.
- **[MUST]** Every file-referencing column has `"format": "file-path"` and `"exists": true`. _(all three)_
- **[MUST]** Each manifest schema's `$id` and `title` match its own filename and entity role. mag's
  `schema_assembly_input.json` copies both verbatim from another schema — check this explicitly whenever
  more than one `assets/*.json` schema exists.
- **[MUST]** Use `enum` for a closed vocabulary, not an unanchored `pattern`. mag's `assembler` column uses
  a bare alternation regex with no `^`/`$` anchors where an `enum` was correct.
- **[SHOULD]** `dependentRequired` for "column A requires column B"; `anyOf` for "at least one input family
  per row". _(sarek and mag)_
- **[SHOULD]** ID patterns as `"^\\S+$"`; file patterns anchored and extension-specific, allowing an
  optional directory prefix but forbidding spaces.

## 8. `.nf-core.yml`

- **[MUST]** Keep `files_exist` and `files_unchanged` in sync with the actual repository. Both rnaseq and
  sarek list files they no longer contain (`awstest.yml` after replacement, `ci.yml` after renaming) —
  stale exemptions that mask real lint signal. The one deliberate exception is `conf/modules.config`: the
  `files_exist` check requires it, this pipeline does not have it, and §4 explains why. An exemption for a
  file the repository intends never to have is not stale; an exemption for one it merely used to have is.
- **[SHOULD]** Treat the count of lint exemptions as a proxy for template-deviation risk. mag needs two
  keys, sarek four, rnaseq five — and that ordering tracks how far each has drifted from the template.
  Every new exemption should be justified in the review that introduces it.
- **[SHOULD]** `nextflow_config.config_defaults` is the right exemption when a param's schema default
  genuinely cannot match the live value (a `${projectDir}`-interpolated default, or a deliberately-nulled
  default whose real value is documented in a comment above it). _(rnaseq and mag)_
