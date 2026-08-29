# Nextflow & Groovy code style

Applies to `main.nf`, `workflows/*.nf`, and pipeline-owned local composition selected by the descendant
instructions. Upstream-bound module and reusable-subworkflow bodies use their canonical component topics.

Evidence tags cite the three reference pipelines (`nf-core/rnaseq`, `nf-core/sarek`, `nf-core/mag`). Counts
marked "measured" were verified directly against the checked-out sources, not inferred.

---

## 1. Formatting mechanics

- **[TOOLING]** Run the repo formatter after any `.nf` edit; it owns indentation, alignment, commas, brace, and
  `else` placement:

  ```bash
  nextflow lint -format -sort-declarations -spaces 4 -harshil-alignment
  ```

  Review the evidence that this command ran, not each mechanically repairable instance.

  Requires Nextflow 26.04.6, which the pipeline now declares as its floor. On 25.10.4 this command emitted
  code Nextflow itself could not parse: it dropped the parentheses from computed map keys, turning
  `[(row[0].id): x]` into `[row[0].id: x]`, and it rewrote `catch (Exception e)` into the v2-only
  `catch (e: Exception)` while 25.10.4 still defaulted to the v1 parser. Both hazards are resolved at
  26.04.6 — the map-key rewrite is fixed, and the typed-`catch` form is valid because the v2 parser is now
  the default.

  Two formatter defects remain at 26.04.6, so read the diff rather than committing it blind: comments
  inside map and list literals are **stripped**, and multi-line method chains are collapsed onto a single
  long line. Restore anything the formatter destroys that the surrounding code depends on.

- **[SHOULD]** No enforced maximum line length for `.nf` files. Prettier's `printWidth: 120` does not apply —
  Prettier has no Nextflow parser and never touches `.nf`. Break multi-argument process calls one argument
  per line and use backslash continuation in shell blocks; otherwise let a single-purpose line run long
  rather than wrapping it awkwardly. _(all three; lines over 200 chars exist in all three)_

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

- **[MUST]** `versions` is the last `emit:` entry when present. Alignment is formatter-owned.
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

## 8. Component boundary

[`nf-core-modules.md`](nf-core-modules.md) and [`nf-core-subworkflows.md`](nf-core-subworkflows.md) own stable
component contracts. This file governs only surrounding pipeline composition. The applicable `nf-core-*`
skills provide task procedure.

## 9. Pipeline version collection

- **[MUST]** Collect component version topics centrally from `channel.topic("versions")`. Do not manually mix
  version channels through pipeline composition for components already reporting on the topic.

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
