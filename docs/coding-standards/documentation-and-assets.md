# Documentation, assets, and auxiliary scripts

Applies to `README.md`, `docs/usage.md`, `docs/output.md`, `CHANGELOG.md`, `CITATIONS.md`, `assets/`, and
`bin/`.

This is the one area where the three reference pipelines are least consistent with each other, and each
carries verifiable defects. Several rules below are therefore **stricter than any of the three actually
achieve** — they are marked `(stricter than all three)` and exist because the observed variance is drift,
not design.

---

## 1. README.md

- **[MUST]** Logo block, identical in all three but for filenames: _(all three)_

  <!-- prettier-ignore -->
  ```text
  <h1>
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="docs/images/nf-core-gwas_logo_dark.png">
      <img alt="nf-core/gwas" src="docs/images/nf-core-gwas_logo_light.png">
    </picture>
  </h1>
  ```

- **[MUST]** Three badge groups, blank-line separated, in this order: CI/status (Codespaces, CI, linting,
  AWS CI, Zenodo DOI, nf-test) → runtime/tooling (Nextflow version, template version, conda, docker,
  singularity, Seqera Platform launch) → community (Slack, Bluesky, Mastodon, YouTube). _(all three)_
  Do not append non-template badges — mag adds two and one of them is not even a link.
- **[MUST]** Section order, all as sentence-case `##` headings: Introduction → Pipeline summary → Usage →
  Pipeline output → Credits → Contributions and Support → Citations. _(all three share this core; sarek and
  mag carry the separate "Pipeline summary" section and it is the clearer of the two layouts — rnaseq folds
  a 16-item numbered list into Introduction instead)_
- **[MUST]** Spell it "Contributions and Support", not "Contributions & Support". _(2/3)_
- **[MUST]** The Usage section contains all four ingredients: a `> [!NOTE]` pointing at the nf-co.re setup
  docs, fenced cohort- and analysis-manifest CSV examples, a fenced `bash` run command using
  `--cohort_manifest` / `--analysis_manifest` / `--outdir` / `-profile`, and a `> [!WARNING]` about not
  using `-c` to set parameters. Preserve the nf-core boilerplate wording verbatim.
- **[MUST]** The Citations section ends with the nf-core framework citation (Ewels et al., Nat Biotechnol
  2020, doi:10.1038/s41587-020-0439-x) and a pointer to `CITATIONS.md`. _(all three)_
- **[MUST]** The contributing link resolves to a file that exists. Prefer `.github/CONTRIBUTING.md`.
  rnaseq's README links to contributing guidelines with no `.github/CONTRIBUTING.md` present. _(2/3)_

## 2. docs/usage.md

- **[MUST]** Opens with the nf-co.re website redirect banner and the "parameters are generated from the
  schema" note. _(all three)_
- **[MUST]** These sections are present: samplesheet input; a samplesheet format table; Running the
  pipeline; Updating; Reproducibility; core Nextflow arguments (`-profile`, `-resume`, `-c`); custom
  configuration and resource requests; nf-core/configs; running in the background; memory/CPU notes.
  _(all three)_
- **[MUST]** A Column/Description pipe table documenting the samplesheet. mag omits it and shows columns
  only as backticked lists, which is harder to scan. _(2/3)_
- **[MUST]** **Use GitHub-native alerts exclusively** — `> [!NOTE]`, `> [!WARNING]`, `> [!TIP]`,
  `> [!IMPORTANT]`. Never Docusaurus `:::note` fences, never `> **NB:**`.
  _(stricter than all three — verified mixing within a single file in every pipeline: rnaseq 7 GitHub
  alerts against 11 Docusaurus fences, sarek 5 against 2, mag 8 against 4. This is unresolved migration
  debt, not a style choice; GitHub alerts render correctly on GitHub without a Docusaurus site.)_
- **[MUST]** Every code fence carries a language tag, and manifest/params examples carry a title:
  ` ```bash `, ` ```csv title="cohort_manifest.csv" `, ` ```csv title="analysis_manifest.csv" `,
  ` ```yaml title="params.yaml" `. _(all three use titled data examples; filenames follow this pipeline's contract)_
- **[MUST]** Reference params in prose as backticked double-dash flags, for example
  `` `--cohort_manifest` ``. _(all three)_
- **[MUST]** No duplicated sections. sarek repeats its custom-configuration and nf-core/configs content
  under two different headings.
- **[SHOULD]** Ship complete, valid cohort- and analysis-manifest examples inline.

## 3. docs/output.md

- **[MUST]** Every tool section wraps its file list in this exact skeleton — the single most consistent
  convention found anywhere in the reference set _(verified: 43 / 64 / 55 occurrences)_:

  <!-- prettier-ignore -->
  ```text
  <details markdown="1">
  <summary>Output files</summary>

  - `plink/`
    - `*.bed`: Binary genotype table produced by PLINK.

  </details>
  ```

  The blank lines after `<summary>` and before `</details>` are required for the bullet list to render,
  and the tags sit at column 0 rather than being indented. Check for stray or duplicated closing tags, and
  for `<details markdown = "1">` with stray spaces (sarek has one).

- **[MUST]** Output-file bullets follow ``- `filename`: Description.`` _(all three)_
- **[MUST]** Link each tool inline on first mention, immediately after opening its `<details>` block.
  _(all three)_
- **[MUST]** Intro paragraph, then a "Pipeline overview" list of stages, then per-tool sections, then
  MultiQC, then Pipeline information listing the standard `pipeline_info/` artifacts
  (`execution_report.html`, `execution_timeline.html`, `execution_trace.txt`, `pipeline_dag.svg`,
  `pipeline_report.html`, `software_versions.yml`, `params*.json`). _(all three)_
- **[SHOULD]** Render "Pipeline overview" as a nested TOC of anchor links rather than a flat stage list —
  it doubles as navigation once the file passes a few hundred lines. _(2/3: rnaseq and sarek)_

## 4. CHANGELOG.md

- **[MUST]** Header states the format the file actually follows, **and the body matches that claim**.
  rnaseq's preamble claims Keep a Changelog and then never uses its vocabulary — the exact
  documented-versus-actual mismatch to avoid.
- **[MUST]** Use the Keep a Changelog section headings: `### Added`, `### Changed`, `### Fixed`,
  `### Removed`, `### Deprecated`. Do not backtick-wrap them as mag does (`` ### `Added` ``).
  _(2/3 use the vocabulary; rnaseq substitutes eleven pipeline-specific headings instead)_
- **[MUST]** One version-heading format, fixed for the life of the file. **None of the three is worth
  copying** — rnaseq uses bracket+date with no codename, sarek a codename with no date, and mag's own
  format drifts release to release (`v`-prefix, hyphen placement, and brackets all vary). Pick one and hold
  it; `## [1.1.0](url) - 2026-07-27` is the least ambiguous.
- **[MUST]** PR links as `[#NNNN](https://github.com/nf-core/gwas/pull/NNNN) - Description`. _(all three)_
- **[MUST]** Include a dependency-version table whenever tool versions change, with the columns
  `| Dependency | Old version | New version |`. _(all three, minor column-name drift)_
- **[SHOULD]** No persistent "Unreleased" heading is required — all three land entries directly under the
  next release heading (grep-confirmed absent everywhere). Whichever convention is chosen, document it in
  the preamble accurately.

## 5. CITATIONS.md

- **[MUST]** Structure: `# nf-core/gwas: Citations` → pipeline / nf-core / Nextflow citation blockquotes →
  `## Pipeline tools` → optional `## R packages` → `## Software packaging/containerisation tools`.
  _(all three)_
- **[MUST]** The final section heading is exactly `## Software packaging/containerisation tools` — British
  spelling — listing Anaconda, Bioconda, BioContainers, Docker, Singularity. This is the single most
  consistent string across all three repos. _(all three)_
- **[MUST]** Per-tool entry format: _(all three)_

  ```markdown
  - [PLINK](https://doi.org/10.1086/519795)

    > Purcell S, Neale B, Todd-Brown K, et al. PLINK: a tool set for whole-genome association and
    > population-based linkage analyses. Am J Hum Genet. 2007;81(3):559-575. doi: 10.1086/519795.
    > PubMed PMID: 17701901; PubMed Central PMCID: PMC1950838.
  ```

  A link-only entry with no citation blockquote is acceptable for tools without a paper. _(all three)_

- **[MUST]** `## Pipeline tools` entries are strictly alphabetical. All three intend this and all three have
  stragglers appended out of order — check the tail of the section specifically.

## 6. assets/

- **[MUST]** `schema_cohort_manifest.json` and `schema_analysis_manifest.json` are present, with `meta`
  arrays and a per-property `errorMessage`. See
  [`configuration-and-schema.md`](configuration-and-schema.md) for their full rules.
- **[MUST]** Ship example cohort and analysis manifests that validate against those schemas.
- **[MUST]** If `assets/multiqc_config.yml` exists _(present in sarek and mag; rnaseq has none — verified)_:
  - `report_section_order` pins the three standard keys with negative orders:
    `gwas-methods-description: -1000`, `software_versions: -1001`, `gwas-summary: -1002`;
  - `export_plots: true` and `disable_version_detection: true`;
  - `custom_logo` names a file that actually exists in `assets/` — mag's points at
    `mag_logo_mascot_light.png` while the real asset is `nf-core-mag_logo_light.png`;
  - `report_comment` **templates the pipeline version rather than hardcoding it**. Both sarek and mag
    hardcode the release string, and both go stale. _(stricter than both)_
- **[MUST]** `methods_description_template.yml`, if present, uses the standard key set (`id`, `description`,
  `section_name`, `section_href`, `plot_type: "html"`) and `${...}` Groovy placeholders. _(2/3)_
- **[SHOULD]** Email and sendmail templates keep the standard Groovy conditional
  (`<% if (!success){ ... } %>`), CID-embedded logo in the HTML variant, and base64 76-column embedding in
  the text variant. _(all three)_
- Note: `multiqc_config.yml`, `methods_description_template.yml`, and Slack/Teams notification payloads
  (`adaptivecard.json`, `slackreport.json`) are **optional**. Their absence alone is not a review finding.

## 7. bin/ scripts

- **[MUST]** Prefer an nf-core module over a new `bin/` script. Only add a script when the logic genuinely
  cannot live in a module — rnaseq's `bin/` has shrunk to three files precisely because helpers migrated
  into modules. Script count is not a target: the three repos hold 3, 1, and 12.
- **[MUST]** `#!/usr/bin/env python3`, never bare `#!/usr/bin/env python`.
  _(stricter than all three — rnaseq and mag are each internally inconsistent about this)_
- **[MUST]** A license header line: `# Written by <Name> and released under the MIT license.` _(2/3)_
- **[MUST]** `argparse` for the CLI, with `def main(): ...` and
  `if __name__ == "__main__": sys.exit(main())`. _(dominant in all three but violated by individual scripts
  in each — treat as hard here)_
- **[MUST]** Pick `print()` or `logging` and hold it across the whole `bin/` directory. `print()` dominates
  the reference set; `logging` appears in exactly one script across all three repos.
  _(stricter than all three)_
- **[MUST]** R scripts: `#!/usr/bin/env Rscript`, `optparse` for arguments, explicit
  `stop("...", call. = FALSE)` checks for required arguments, and **one** naming case throughout — rnaseq's
  R script mixes dot.case, camelCase, and PascalCase in a single file. _(2/3 have R at all)_
- **[SHOULD]** Double-quoted strings; guard index access on positional arguments (mag's `split_fasta.py`
  has none).
- Notes on absences, none of which are review findings: no script in any of the three carries type hints;
  docstrings are sparse everywhere; only one script of roughly sixteen implements `--version`; and there
  are **no shell scripts in `bin/` in any of the three** (verified).

## 8. Prose style

- **[TOOLING]** Line wrapping. Markdown is left unwrapped, one paragraph per source line — measured lines of
  618, 566, and 501 characters in the three repos. Prettier runs with `proseWrap: preserve` and will not
  rewrap. Never raise a finding about markdown line length. _(all three)_
- **[MUST]** Inline links only — `[text](url)`. Reference-style `[text][ref]` links appear zero times
  across README, usage, output, and CITATIONS in all three repos. This is the cleanest rule in the set.
  _(all three)_
- **[MUST]** Sentence case for all headings. _(1/3 — mag is the only one that holds it; rnaseq and sarek
  both drift into Title Case within a single file. Chosen deliberately.)_
- **[MUST]** Backtick every CLI flag, file path, and samplesheet column name. _(all three)_
- **[SHOULD]** Second person for user-facing instructions ("You will need to create a samplesheet…").
  _(all three)_
- **[SHOULD]** Be consistent about whether a tool is written as a backticked name or an inline link within
  a given document. All three mix the two for the same tool in different places.
- **[SHOULD]** British spelling, matching the mandated `containerisation` heading in `CITATIONS.md`. Be
  aware this is unenforced and unenforceable without tooling: British and American forms coexist
  mid-paragraph in all three repos ("analyse"/"normalizes", "customise"/"customized",
  "summarises"/"summarizing"). Do not spend review time on it — if consistency matters, add a spellcheck
  config, which none of the three has.
