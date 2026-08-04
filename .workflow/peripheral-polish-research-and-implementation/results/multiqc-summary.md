# MultiQC analysis-summary table research

## Recommendation

Add one deliberately small custom-content table named **Analysis plan**. It should describe the validated analysis units that this run requested; it must not imply that an association or heritability estimate completed successfully.

The table should have one row per `analysis_id`, with these visible columns in this order:

1. Cohort
2. Trait
3. Trait type
4. Genome build
5. Ancestry
6. Association methods
7. Heritability methods

Use `analysis_id` as the MultiQC row/sample key rather than repeating it as a cell. Do not add completion status, sample/case/control counts, result counts, QQ diagnostics, estimates, or links in this first version. None of those values is currently represented by a reliable, run-level result channel at the MultiQC seam.

This is useful without becoming a scientific-results panel: it lets a reader answer which cohort/trait units and routes the report covers, and it uses only values already validated before any downstream task is submitted.

## Exact available fields and source

The canonical source is `ch_analyses`, emitted by `NFCORE_GWAS` after `validateRelationalInput(...)` has validated and joined the two manifests. Every tuple begins with the enriched `meta` map.

| Table value | Exact `meta` field | Original source | Notes |
|---|---|---|---|
| row identity | `meta.id` | analysis manifest `analysis_id` | Required, whitespace-free and unique after validation. |
| Cohort | `meta.cohort` | analysis manifest `cohort_id` | Required and verified to exist in the cohort manifest. |
| Trait | `meta.trait` | analysis manifest `trait_id` | Required. |
| Trait type | `meta.trait_type` | analysis manifest `trait_type` | Required; `quantitative` or `binary`. |
| Genome build | `meta.build` | joined cohort manifest `genome_build` | Required; `GRCh37` or `GRCh38`. |
| Ancestry | `meta.ancestry` | joined cohort manifest `ancestry` | Required provenance label; do not describe it as scientific/reference routing. |
| Association methods | `meta.association_methods` | parsed analysis selector | Validated list, possibly empty. Render as comma-separated human-readable text. |
| Heritability methods | `meta.heritability_methods` | parsed analysis selector | Validated list, possibly empty. Render as comma-separated human-readable text. |

Other currently available fields were intentionally excluded:

- `genotype_format` and `has_covariates` are implementation/input details rather than the clearest run overview.
- `case_value`, `control_value`, and `population_prevalence` are method-conditioned inputs and would produce sparse, easy-to-misread columns.
- `phenotype_column` is useful provenance but duplicates the trait concept in the simple first table; it can be added later if users need it.
- `method_options` is nested, method-specific configuration and belongs in detailed provenance, not seven broad columns.
- No sample count, case/control count, estimate, result count, or reliable per-route completion field exists in this metadata.

If an analysis has no methods in one family, render an em dash (`-`) rather than an empty array or Groovy list notation.

## Reference-pipeline pattern

The three local reference pipelines establish two relevant patterns:

- Sarek and MAG register custom tables through `custom_data` plus `sp` file matching in `assets/multiqc_config.yml`. This works well for tool-generated TSV metrics.
- The newer RNA-seq strandedness implementation keeps presentation metadata in a bundled YAML asset, builds dynamic per-run data in Nextflow, serialises the merged custom-content document as JSON, and mixes that file into MultiQC. Its helper sorts rows for deterministic output and verifies that every emitted cell has a declared header.

The RNA-seq pattern is the better fit here because this table is assembled from in-memory validated manifest metadata, not from a tool-generated metrics file. It also keeps column names, descriptions, and order reviewable in an asset instead of embedding UI text in workflow logic.

Relevant reference locations:

- `.references/rnaseq/workflows/rnaseq/assets/multiqc/strand_check_summary.yaml`
- `.references/rnaseq/subworkflows/local/multiqc_rnaseq/main.nf`, especially `strandCheckSummaryYaml(...)`
- `.references/sarek/assets/multiqc_config.yml`, `custom_data.dedup_metrics`
- `.references/mag/assets/multiqc_config.yml`, `custom_data.host_removal`

The installed pipeline module runs MultiQC 1.34 and accepts arbitrary staged `*_mqc.json` custom-content input alongside the existing workflow-summary and methods-description YAML files.

## Proposed asset and output contract

Add a static asset such as `assets/multiqc_analysis_plan.yaml`:

```yaml
id: nf-core-gwas-analysis-plan
section_name: Analysis plan
description: >
  One row per validated analysis unit, showing the cohort, trait and methods
  requested for this run. This table describes the run plan, not per-method
  completion or scientific results.
plot_type: table
pconfig:
  id: nf-core-gwas-analysis-plan-table
  title: Analysis plan
  namespace: nf-core/gwas
headers:
  cohort:
    title: Cohort
    description: Cohort identifier joined from the linked manifests.
  trait:
    title: Trait
    description: Trait identifier declared for this analysis.
  trait_type:
    title: Trait type
    description: Declared trait type; quantitative or binary.
  genome_build:
    title: Genome build
    description: Genome build declared for the cohort genotypes.
  ancestry:
    title: Ancestry
    description: Cohort ancestry provenance label supplied by the user.
  association_methods:
    title: Association methods
    description: Association routes requested for this analysis.
  heritability_methods:
    title: Heritability methods
    description: Heritability routes requested for this analysis.
```

At runtime, merge that static map with a `data` map shaped like:

```json
{
  "data": {
    "height_bmi": {
      "cohort": "ukb",
      "trait": "bmi",
      "trait_type": "quantitative",
      "genome_build": "GRCh38",
      "ancestry": "EUR",
      "association_methods": "plink2, regenie",
      "heritability_methods": "gcta_greml"
    }
  }
}
```

The emitted file should be named `analysis_plan_mqc.json`. JSON is preferable for the generated document because it avoids manual YAML escaping and matches the recent RNA-seq implementation. Static authoring can remain YAML and be parsed with SnakeYAML, already available to Nextflow code in this repository/reference pattern.

Add `nf-core-gwas-analysis-plan` to `report_section_order`, immediately before the existing workflow summary. A sensible order is:

1. Analysis plan
2. Workflow summary
3. Software versions
4. Methods description

Follow the repository's existing negative-order convention when encoding that order; the important requirement is to verify the rendered order rather than infer the direction from the numeric values alone.

## Integration seam

1. Add a utility helper alongside `methodsDescriptionText(...)`, or another small local pipeline utility, that accepts the parsed static asset plus a list of analysis `meta` maps and returns pretty-printed JSON.
2. At the beginning of `workflow GWAS`, derive a metadata-only stream from `ch_analyses`:

   ```groovy
   def ch_analysis_plan_rows = ch_analyses.map { meta, _genotypes, _phenotype, _quant_covariates, _cat_covariates, _kvik_extract, _ldak_weights -> meta }
   ```

3. Collect all metadata once, sort by `meta.id`, map arrays to comma-separated text (or `-`), merge with the parsed asset, and `collectFile(name: 'analysis_plan_mqc.json')`.
4. Mix the resulting file into `ch_multiqc_files` before invoking `MULTIQC`.

Be careful not to use an execution-output channel as the source. If the table were driven by completed result files, analyses without one result type could disappear and the section would falsely conflate routing, process completion, and publication. The validated input channel gives stable planned coverage and the section wording states that boundary explicitly.

The helper should follow the RNA-seq guardrails:

- sort by analysis ID before `collectEntries`;
- take column order from the asset's `headers.keySet()`;
- error when code emits a cell that the asset does not declare;
- emit only declared cells in header order;
- avoid mutating the original `meta` map;
- use plain strings for method lists.

## Focused tests

1. **Pure helper test, if the repository exposes local utility-function tests:** two deliberately out-of-order meta maps produce lexicographically ordered JSON keys and the exact seven cells; empty method lists render `-`.
2. **Contract guard test:** an emitted field missing from `headers` raises a clear error, mirroring the RNA-seq implementation.
3. **Focused nf-test assertion:** use an existing small linked-manifest route (the default test is the natural candidate), open `multiqc/multiqc_data/multiqc_data.json`, and assert that the custom section contains each expected analysis ID and representative joined cohort fields (`build`, `ancestry`) plus requested method names.
4. **Rendered smoke check:** assert `multiqc_report.html` contains `Analysis plan` and the disclaimer language distinguishing plan from completion/results.
5. **Determinism:** snapshot or directly compare the custom-content data for a two-analysis fixture declared in reverse lexical order.
6. **Regression:** run the existing focused default nf-test with Docker, then the ordinary pipeline lint/format checks applicable to the touched files. Broader sharded validation is warranted before final handoff because the central workflow and MultiQC input bundle are changed.

Do not test for QQ plots, heritability estimate panels, screenshots, or completion status in this work item. Those are explicitly deferred product features.

## Decision summary

Accepted: a seven-column input-provenance table derived from validated joined manifest metadata.

Rejected for now: status and scientific-result columns, because there is no truthful aggregate result model at the current MultiQC seam.

Style choice: static YAML presentation plus dynamically generated JSON data, following the newest and closest local reference implementation.
