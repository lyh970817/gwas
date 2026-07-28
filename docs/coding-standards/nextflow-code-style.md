# Nextflow & Groovy code style

Applies to `main.nf`, `workflows/*.nf`, `subworkflows/local/**/*.nf`, and `modules/local/**/*.nf`.

Rule tags: **[MUST]** violation is a review finding · **[SHOULD]** strong default, deviation needs a stated
reason · **[TOOLING]** a formatter/linter owns this, do not hand-police it in review.

Evidence tags cite the three reference pipelines (`nf-core/rnaseq`, `nf-core/sarek`, `nf-core/mag`). Counts
marked "measured" were verified directly against the checked-out sources, not inferred.

---

## 1. Formatting mechanics

- **[TOOLING]** Run the repo formatter after any `.nf` edit; it owns indentation, alignment, brace and
  `else` placement:

  ```bash
  nextflow lint -format -sort-declarations -spaces 4 -harshil-alignment
  ```

  Do not raise review findings for anything this command would fix. Do raise a finding if a changed `.nf`
  file is visibly unformatted (a sign the command was never run).

- **[MUST]** 4-space indentation, spaces only, never tabs. _(all three; measured: 0 tab-indented `.nf`
  files across 132 files)_

- **[MUST]** "Harshil alignment" — column-aligned `=`, `from`, and trailing comments — applied wherever two
  or more sibling lines of the same shape appear: `include` blocks, `take:`/`emit:` blocks, `output:`
  blocks, and consecutive `ch_x = ch_x.mix(...)` reassignments. _(all three)_ The `-harshil-alignment` flag
  above produces this; the rule exists so hand-written additions are not left ragged.

- **[SHOULD]** No enforced maximum line length for `.nf` files. Prettier's `printWidth: 120` does not apply —
  Prettier has no Nextflow parser and never touches `.nf`. Break multi-argument process calls one argument
  per line and use backslash continuation in shell blocks; otherwise let a single-purpose line run long
  rather than wrapping it awkwardly. _(all three; lines over 200 chars exist in all three)_

- **[SHOULD]** Trailing commas on multi-line argument lists and list literals whose closing bracket is on its
  own line; none on single-line calls. _(mag dominant, sarek at top level; rnaseq mostly omits — chosen for
  cleaner diffs)_

- **[TOOLING]** Brace and `else` placement. `{` opens on the statement line in all three. `} else {` vs a
  line-initial `else` genuinely diverges (measured: rnaseq 44 same-line, sarek 25, mag 1) — take whatever
  the formatter emits and never flag it.

## 2. File layout and section banners

- **[MUST]** Three banner tiers, kept visually distinct. Do not invent a fourth. _(all three use tier 1 and
  tier 2; mag mixes three competing styles for tier 1 — the inconsistency to avoid)_
  1. **File/section banner** — `/* */` block, tilde rule, ALL-CAPS indented title. Used in `main.nf` and at
     the top of `workflows/*.nf` to mark `IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS`, `NAMED WORKFLOWS`,
     `RUN MAIN WORKFLOW`, `FUNCTIONS`:

     ```groovy
     /*
     ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
         IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
     ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     */
     ```

  2. **Step banner inside `main:`** — three `//` lines, label from the fixed set
     `WORKFLOW` / `SUBWORKFLOW` / `MODULE`, then a sentence-case description:

     ```groovy
     //
     // SUBWORKFLOW: Prepare reference genome files
     //
     ```

  3. **Purpose comment at the top of a local subworkflow** — one to three `//` lines, no box, stating what
     the subworkflow does. _(dominant in all three)_

- **[MUST]** `#!/usr/bin/env nextflow` on line 1 of `main.nf` only. Never write `nextflow.enable.dsl = 2` —
  absent from all three. _(all three)_

- **[MUST]** File order: shebang (entrypoint only) → banner → `include` block → helper `def` functions or
  `workflow` block → trailing `FUNCTIONS` section. Local subworkflows: purpose comment → `include`s →
  `workflow`. _(all three)_

## 3. `include` statements

- **[MUST]** One symbol per `include` line; single-quoted relative paths; never absolute or
  `${projectDir}`-based. _(all three)_
- **[MUST]** Group includes with a `//` header naming the category, and separate groups with a blank line.
  The conventional headers are:

  ```groovy
  // MODULE: Installed directly from nf-core/modules
  // MODULE: Local to the pipeline
  // SUBWORKFLOW: Consisting of a mix of local and nf-core/modules
  // SUBWORKFLOW: Consisting entirely of nf-core/modules
  ```

  _(all three)_ Put a plugin import (`from 'plugin/nf-schema'`) under its own header, not under a
  SUBWORKFLOW header — rnaseq mislabels this and it reads as a mistake.

- **[SHOULD]** Order within a group follows pipeline execution order, not alphabetical. None of the three
  sort alphabetically; do not raise findings for unsorted includes. _(all three)_
- **[MUST]** Be internally consistent about the trailing `/main` in module paths within a file. rnaseq and
  mag both mix `'.../kraken2/kraken2/main'` and `'.../stringtie/stringtie'` in one file — a real defect to
  avoid. Prefer the explicit `/main` form throughout. _(inconsistent in 2/3 — chosen)_
- **[MUST]** Alias with `as` whenever the same component is invoked in more than one role, and make the
  alias more specific than the base name while keeping the base name as a substring:
  `include { GUNZIP as GUNZIP_GENOTYPES }`. _(all three)_

## 4. Naming

| Category                 | Rule                                                                                                      | Evidence                                                                                                |
| ------------------------ | --------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| Processes                | `SCREAMING_SNAKE_CASE`, matching the module directory uppercased                                          | all three                                                                                               |
| Workflows / subworkflows | `SCREAMING_SNAKE_CASE`, matching the directory name                                                       | all three                                                                                               |
| Subworkflow directories  | `snake_case`, prefixed by the primary `take:` input type where one dominates (`bam_`, `vcf_`, `prepare_`) | sarek convention, worth adopting                                                                        |
| Channel variables        | `ch_` prefix + `snake_case`                                                                               | rnaseq/mag (measured: 237 and 476 `ch_` assignments); sarek is the outlier at 92 — **[MUST]** use `ch_` |
| Local Groovy variables   | `snake_case`, declared with `def`                                                                         | all three                                                                                               |
| Helper functions         | `camelCase`, verb-first (`getGenomeAttribute`, `checkSamplesAfterGrouping`)                               | all three                                                                                               |
| `params.*`               | `snake_case`, always                                                                                      | all three                                                                                               |
| `take:` / `emit:` names  | `snake_case`, no `ch_` prefix on the label itself                                                         | all three                                                                                               |
| Meta keys                | lowercase single words (`meta.id`, `meta.group`)                                                          | all three                                                                                               |

- **[MUST]** A `ch_`-prefixed name holds a channel. Do not prefix a process handle or a plain value — rnaseq
  misapplies this at `align_star/main.nf:42` and it misleads readers.

## 5. Channels and operators

- **[MUST]** Lowercase channel factories: `channel.empty()`, `channel.of()`, `channel.fromPath()`,
  `channel.value()`, `channel.fromList()`, `channel.topic()`. Never capitalised `Channel.`.
  _(measured: rnaseq 57 lowercase / 0 capitalised; mag 87 / 0; sarek 110 / 201 — sarek is mid-migration and
  is the one to not copy)_
- **[MUST]** Never rely on the implicit `it` closure parameter. Name every closure parameter explicitly,
  even single-argument ones: `.map { fai -> checkContigSize(fai) }`.
  _(measured: rnaseq 0 bare-`it` closures, mag 0, sarek 48 — the two fully-migrated pipelines are at
  literally zero)_
- **[MUST]** Prefix a destructured-but-unused parameter with an underscore: `.map { _meta, bam -> bam }`.
  _(all three; measured 22 / 87 / 48 occurrences)_
- **[MUST]** Bind channels by assignment (`ch_x = ...`), not `.set { ch_x }`.
  _(measured: `.set {` appears 2 / 4 / 1 times across the three against hundreds of assignments)_
- **[MUST]** Accumulate with explicit self-reassignment, one `.mix()` per line when chaining:

  ```groovy
  ch_multiqc_files = ch_multiqc_files
      .mix(ALIGN_PLINK.out.stats)
      .mix(ALIGN_PLINK.out.log)
  ```

  _(all three)_ Do not nest `.mix()` calls inside one another — rnaseq does this once and it is the harder
  line to read in that file.

- **[SHOULD]** Multi-line `.map {}` puts `->` on its own line with the body indented one further level;
  each chained `.operator()` starts its own line indented one level from the assignment. _(all three)_
- **[MUST]** Derive a modified meta map immutably — `def meta_new = meta + [key: value]`, or
  `meta - meta.subMap('key')`. Never mutate `meta` in place inside a closure; mag does this in its utils
  subworkflow and it is a latent aliasing bug. _(mag dominant idiom, 18 occurrences)_
- **[SHOULD]** Name `.branch {}` and `.multiMap {}` labels in lowercase `snake_case` and align the trailing
  `:` across labels. _(all three)_
- **[SHOULD]** Prefer named destructuring (`{ meta, fai -> }`) over positional indexing (`{ t -> t[1] }`).
  rnaseq and sarek mix both within one file; pick destructuring.

## 6. `workflow` block anatomy

- **[MUST]** `take:` / `main:` / `emit:` in that order, each on its own line. _(all three)_
- **[MUST]** Every `take:` and `emit:` entry carries an aligned trailing shape comment in the shared
  `val(...)` / `path(...)` vocabulary:

  ```groovy
  take:
  ch_genotypes  // channel: [ val(meta), path(bed), path(bim), path(fam) ]
  ch_phenotypes // channel: [ val(meta), path(pheno) ]
  ```

  _(rnaseq and sarek: 323 and 369 `// channel:` comments measured; mag only 22 — follow rnaseq/sarek)_

- **[MUST]** `emit:` entries align their `=` signs, and `versions` is the last entry when present.
  _(all three; 5 sarek subworkflows put it first — the minority to avoid)_
- **[MUST]** Version reporting is a _process_ obligation, not a subworkflow one. Every local process declares
  its tools on the `versions` topic (§9), and the pipeline collects them centrally from
  `channel.topic("versions")` in `workflows/gwas.nf` — so a subworkflow composed only of topic-reporting
  local modules has no version channel in scope, and must not invent one. Emitting `versions =
  channel.empty()`, or accumulating a `ch_versions` variable purely to satisfy the letter of an emit
  contract, is exactly the `.mix()` threading §9 forbids. A subworkflow emits `versions` only when it
  genuinely composes something that produces a version channel — an installed nf-core module still on the
  file-based `versions.yml` pattern, or a nested subworkflow that emits one — and then it is last in the
  `emit:` block. A subworkflow that deliberately emits no `versions` says so in its header comment, as
  `subworkflows/local/prepare_cohort_genotypes/main.nf` does.
  _(1/3 — chosen. This amends an earlier rule that required every subworkflow to emit `versions`; that rule
  contradicted §9 and its cited counts did not reproduce. Measured against the checked-out sources: rnaseq —
  which §9 already names as the migration target — emits `versions` from 0 of its 5 local subworkflows; mag
  emits from 23 of 23 and sarek from 54 of 65, but both are still on the classic per-module `versions.yml`
  pattern, which is what makes those emits carry anything. This pipeline is fully on topic channels, so it
  follows rnaseq. A deliberate decision for this pipeline, not a majority observation.)_
- **[SHOULD]** One blank line before each step banner inside `main:`. Whether a blank line follows `main:`
  is split roughly 50/50 in all three — do not flag it.

## 7. Groovy idioms

- **[MUST]** `error("...")` is the only fatal-abort mechanism. Never `throw new ...` (measured: 0
  occurrences across all three) and never `exit(...)` (measured: 1 legacy occurrence in mag only).
- **[MUST]** Prefix pipeline diagnostics consistently. Adopt mag's scheme, which is the only fully
  consistent one of the three:
  - fatal: `error("[nf-core/gwas] ERROR: ...")`
  - non-fatal: `log.warn("[nf-core/gwas]: ...")`

  Do not duplicate the severity word inside the message body — mag does this once
  (`log.warn('[nf-core/mag]: WARNING: ...')`) and it reads as a bug.

- **[MUST]** `def` for every local variable and helper function; no explicit Java types. _(all three)_
- **[MUST]** Elvis for defaults (`task.ext.args ?: ''`), ternary for binary choices, `if / else if / else`
  for three or more branches. _(all three)_
- **[MUST]** Use `&&` / `||` for boolean logic. rnaseq uses bitwise `&` in three places
  (`workflows/rnaseq/main.nf:429,459,782`); that is a latent bug, not a style, and should be flagged
  wherever it appears.
- **[MUST]** Null-guard before splitting a CSV-string param:
  `if (params.tools && params.tools.split(',').contains('x'))`. sarek omits the guard in two places and
  those are NPE risks. _(sarek idiom, corrected)_
- **[SHOULD]** Double-quoted GStrings for anything interpolated, single quotes for literals. Use `${var}`
  braces by default; bare `$var` only where it reads unambiguously. _(all three, inconsistently — chosen)_
- **[SHOULD]** Prefer `.contains()` / `.endsWith()` / `in [...]` over regex matching for simple string
  checks. _(mag dominant)_
- Constructs absent from all three, and which should stay absent: `switch`, classes, `@CompileStatic`, type
  annotations, safe navigation `?.`, semicolon terminators, and `lib/*.groovy` static-utility classes.

## 8. Local module bodies

Module-submission standards are owned by `.claude/skills/nf-core-gwas-module-conventions/` and
`.claude/skills/nf-core-submission-review/`; those take precedence. What follows is the stylistic subset the
reference pipelines agree on.

- **[MUST]** Directive order, with a blank line between each group:
  `tag` → `label` → `conda` → `container` → `input:` → `output:` → `when:` → `script:` → `stub:`.
  _(all three, zero deviations)_
- **[MUST]** `tag "${meta.id}"` with braces, or a `-`-joined compound of meta fields. Never bare
  `tag "$meta.id"`. _(mag dominant; the bare form only survives in unrefreshed legacy modules)_
- **[MUST]** `when: task.ext.when == null || task.ext.when`, verbatim. _(sarek universal; mag omits it in
  most local modules — follow sarek)_
- **[MUST]** Declare `def args = task.ext.args ?: ''` and `def prefix = task.ext.prefix ?: "${meta.id}"` at
  the top of both `script:` and `stub:`, in that order, and actually use them. sarek has a module that
  assigns `args` and never references it. _(all three where the idiom is used at all)_
- **[MUST]** Align the `output:` block (comma before `emit:` column-aligned). Applied inconsistently in
  mag (3 of 10 modules ragged) and sarek — treat as a hard rule here.
- **[MUST]** Every command block starts on the line after `"""` — no leading blank line inside `script:`
  or `stub:`.
- **[MUST]** Quote interpolated shell arguments: `"${task.cpus}"`, `"${prefix}.log"`. Newer modules in all
  three do this; older ones interpolate bare.
- **[SHOULD]** Backslash continuation with one flag per line for any invocation with more than about three
  flags. _(all three)_
- **[SHOULD]** Format the container ternary with leading `?` and `:` on their continuation lines and no
  space inside `${...}` — the newer of the two live styles in mag and rnaseq. Match whatever
  `nf-core modules create` emits at the pinned tools version if the two disagree.

## 9. Version reporting

The three pipelines are split across a live migration, so this is a deliberate choice rather than a
majority vote:

- **[MUST]** Use Nextflow **topic channels** with `eval()` for version capture in local modules:

  ```groovy
  tuple val("${task.process}"), val('plink2'), eval('plink2 --version | sed "s/^PLINK v//"'), topic: versions
  ```

  Do not write `cat <<-END_VERSIONS > versions.yml` heredocs in new local modules, and do not thread
  `ch_versions = ch_versions.mix(...)` through subworkflows for tools already reporting on the topic
  channel.

  _(rnaseq has fully migrated — measured 4 topic declarations, 0 heredocs, 0 `.mix()` accumulations. sarek
  and mag are still on the classic pattern: 6/216 and 29/128. This repo's existing
  `nf-core-submission-review` skill already assumes `eval`-based versions, so rnaseq is the consistent
  target.)_

- **[MUST]** Each `eval` yields a bare version string — no leading `v`, no tool name, no trailing newline
  noise. Report a version for every tool invoked, including secondary interpreters (R, Python).
- **[MUST]** Keep `emit:` and `topic:` key order consistent across modules; rnaseq varies it between its own
  three local modules.

## 10. Comments

- **[MUST]** `//` for all ordinary comments. `/* */` is reserved for banners and short file-purpose
  docstrings. _(all three)_
- **[MUST]** Comments explain _why_, not _what_. The best examples in the reference set state a constraint
  or a hazard — "must remove the additional metadata because the DEPTHS channel combination is sensitive to
  any additional fields", "SortMeRNA rejects gzipped input". Restating the code is not worth a line.
- **[MUST]** No `TODO nf-core:` template scaffolding left in hand-written code. All three carry leftovers in
  generated utils files; do not add more, and clear them from files you author.
- **[SHOULD]** Sentence case, capitalised first word. Trailing periods are inconsistent everywhere — do not
  flag punctuation.
- **[SHOULD]** To leave code disabled in place, use a dated justification comment —
  `// 2026-07-27: disabled pending upstream fix for <reason>` — rather than a bare commented-out block.
  _(mag idiom)_
- **[SHOULD]** Document non-obvious channel reshaping with an inline tuple-shape comment:
  `// [ id, [ meta1, meta2 ], [ file1, file2 ] ]`. _(sarek idiom, the clearest of the three)_
