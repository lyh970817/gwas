# Methods description and tool citations

## Recommendation

Keep the existing nf-core rendering seam (`methodsDescriptionText` plus a MultiQC
custom-content YAML template), but make the scientific-tool prose and bibliography
route-aware. Derive the route set from the validated analysis metadata, not from
raw parameters and not by parsing filenames or process names. Keep the collated
`versions` topic as the authoritative record of exact executables and versions;
the Methods section should describe and cite the selected scientific methods,
while directing readers to Software Versions for the complete executable inventory.

This is the closest fit to the references:

- Sarek and RNA-seq preserve the current template architecture but intentionally
  leave tool citations blank. They are useful evidence for the injection and
  wording pattern, not for completed citation selection.
- MAG implements `toolCitationText()` and `toolBibliographyText()`, interpolates
  both into the same template, and conditionally selects citations from run
  configuration. It is the only complete reference implementation among the
  three.
- GWAS differs from MAG because its method choice is per analysis row. Therefore
  a function that reads global `params` would be the wrong control seam. Use the
  already validated `meta.association_methods` and `meta.heritability_methods`
  values carried by `analyses`.

No separate website lookup was needed for the structural pattern. Two primary
publication pages clarify route-specific citations missing from `CITATIONS.md`:
fastGWA ([Jiang et al. 2019](https://www.nature.com/articles/s41588-019-0530-8))
and GREML-LDMS ([Yang et al. 2015](https://www.nature.com/articles/ng.3390)).

## Current GWAS data and control flow

1. `PIPELINE_INITIALISATION` validates and enriches both manifests and emits
   `analyses` records. Each metadata map contains normalized lists named
   `association_methods` and `heritability_methods`.
2. `NFCORE_GWAS` passes that queue channel into `GWAS`.
3. `GWAS` filters the metadata lists to dispatch every route.
4. Every executable emits either a versions YAML path or a
   `[process, tool, version]` tuple to the run-wide `versions` topic.
5. Near the end of `GWAS`, topic entries are collated and supplied to MultiQC.
6. Independently, `methodsDescriptionText()` currently receives only the YAML
   template, binds workflow metadata, and sets `tool_citations` and
   `tool_bibliography` to empty strings.
7. The rendered custom-content YAML is mixed into the MultiQC input collection.

The method-description logic therefore has no current access to route selection.
It should be given a compact, deterministic route summary.

## Proposed implementation pattern

### Route summary channel

Create a side branch from `analyses` at the start of `GWAS`, before downstream
operators consume it:

```groovy
def ch_selected_methods = analyses
    .map { meta, _genotypes, _phenotype, _qcovar, _catcovar, _kvik_extract, _ldak_weights ->
        [
            association: meta.association_methods,
            heritability: meta.heritability_methods,
        ]
    }
    .collect()
    .map { selections ->
        [
            association: selections.collectMany { it.association }.unique().sort(),
            heritability: selections.collectMany { it.heritability }.unique().sort(),
        ]
    }
```

The exact syntax should follow what passes the local Nextflow formatter and
tests, but these properties are required:

- aggregate across all analysis rows;
- deduplicate repeated methods;
- sort deterministically so manifests with reordered rows render identically;
- retain association and heritability categories until prose is built;
- never infer a route from an output file, process name, or optional emission.

Render on the dataflow channel, rather than calling the function eagerly:

```groovy
def ch_methods_description = ch_selected_methods
    .map { selected_methods -> methodsDescriptionText(multiqc_template, selected_methods) }
    .collectFile(name: 'methods_description_mqc.yaml', sort: true)
```

The validated method lists are preferable to topic-version parsing. A successful
report implies route dispatch completed far enough to build MultiQC; the versions
topic also contains implementation helpers (`coreutils`, `gawk`, `r-base`) that
belong in Software Versions but should not automatically generate scientific
Methods prose. Conversely, PLINK 2 can be used for input conversion even when
PLINK 2 association was not selected, so merely seeing `plink2` in versions is
not sufficient evidence for saying that PLINK 2 association was performed.

### Pure helper functions

Implement three small helpers in the existing utility subworkflow:

```groovy
def selectedCitationKeys(selected_methods)
def toolCitationText(selected_methods)
def toolBibliographyText(selected_methods)
```

`selectedCitationKeys` should return citation keys in a fixed display order.
Both rendering helpers consume the same keys so prose and bibliography cannot
drift. Avoid two independent collections of conditionals.

Recommended fixed order:

1. PLINK 2
2. REGENIE
3. GCTA fastGWA
4. GCTA GREML
5. GCTA GREML-LDMS
6. LDAK-KVIK
7. LDAK heritability
8. GWASLab
9. MultiQC

`GWASLab` is selected whenever at least one association method is present,
because the workflow harmonises every association result. `MultiQC` is always
selected because this text appears only in the generated MultiQC report. Do not
add PLINK 2 merely because genotype conversion may run; add it as a scientific
method citation for the `plink2` association route. Exact conversion executables
remain visible in Software Versions.

### Route-to-citation mapping

| Validated selector | In-text label | Bibliography entry |
|---|---|---|
| `plink2` | PLINK 2 (Chang et al. 2015) | Existing PLINK 2 entry in `CITATIONS.md` |
| `regenie` | REGENIE (Mbatchou et al. 2021) | Existing REGENIE entry |
| `gcta_fastgwa` | GCTA fastGWA (Jiang et al. 2019) | Add the fastGWA paper, DOI `10.1038/s41588-019-0530-8`; the route uses `--fastGWA-mlm` / `--fastGWA-mlm-binary`, not fastGWA-GLMM |
| `gcta_greml` | GCTA GREML (Yang et al. 2011) | Existing GCTA entry is the original GCTA paper |
| `gcta_greml_ldms` | GCTA GREML-LDMS (Yang et al. 2015) | Add the GREML-LDMS paper, DOI `10.1038/ng.3390` |
| `ldak_kvik` | LDAK-KVIK (Hof and Speed 2025) | Existing LDAK-KVIK entry |
| any of `ldak_reml`, `ldak_he`, `ldak_pcgc` | LDAK (Speed et al. 2012) | Existing LDAK entry; emit once even if several estimators run |
| any association selector | GWASLab | Existing GWASLab project link until a citable publication is deliberately selected |
| always | MultiQC (Ewels et al. 2016) | Existing MultiQC entry |

For `GWASLab`, do not invent an author-year token from a documentation homepage.
Use a neutral linked software label in prose and a URL bibliography item, or omit
it from author-year prose while retaining the link. If a peer-reviewed GWASLab
paper is later adopted in `CITATIONS.md`, update the centralized citation record
then.

The fastGWA and GREML-LDMS papers should also be added to `CITATIONS.md`; the
Methods bibliography and repository citation inventory should not disagree.

### Suggested prose style

Use factual, short, route-derived sentences rather than a comma-heavy generic
tool list. For example, for a run selecting PLINK 2, REGENIE, GCTA fastGWA,
GCTA GREML-LDMS, and LDAK REML:

> Association testing was performed with PLINK 2 (Chang et al. 2015), REGENIE
> (Mbatchou et al. 2021), and GCTA fastGWA (Jiang et al. 2019). Association
> summary statistics were harmonised with GWASLab. SNP-based heritability was
> estimated with GCTA GREML-LDMS (Yang et al. 2015) and LDAK (Speed et al.
> 2012). The run report was generated with MultiQC (Ewels et al. 2016).

The template-level opening should retain nf-core conventions:

- pipeline name and version;
- pipeline DOI only when real metadata supplies one;
- nf-core, Bioconda, and BioContainers citations;
- Nextflow version and citation;
- exact command line in a code block;
- route-aware scientific prose;
- full bibliography;
- note that command-line text excludes values inherited from configs/profiles;
- direction to Software Versions for exact versions and helper executables.

Replace the template TODO. For prerelease builds without a pipeline DOI, avoid
the current instruction to “update the text” as if the report author controls
pipeline release metadata. Prefer: “No version-specific pipeline DOI was declared
for this build.”

### Custom template compatibility

Preserve `--multiqc_methods_description`. The same metadata keys should be
available to custom templates:

- `${workflow...}`
- `${doi_text}` and `${nodoi_text}` (or a backward-compatible replacement)
- `${tool_citations}`
- `${tool_bibliography}`

This keeps the public parameter functional while improving the default. Do not
require custom templates to know about internal channel objects.

## Anti-overclaim constraints

- Say “selected” or “performed with” only for methods in validated manifest
  selectors. Do not claim all tools in `CITATIONS.md` ran.
- Do not interpret ancestry metadata as a reference selector or scientific
  routing decision.
- Do not claim harmonisation used a reference resource merely because GWASLab
  ran; its optional FASTA/VCF references may be absent. “Harmonised with
  GWASLab” is the safe statement.
- Do not claim GRMs or predictions were imported or reused across launches.
- Do not state a specific regression fallback or model unless it is invariant
  for the selected route and trait type. The simple citation paragraph need not
  enumerate PLINK 2 linear/logistic variants or REGENIE fallback details.
- Do not call `gcta_fastgwa` fastGWA-GLMM. The code explicitly invokes
  `--fastGWA-mlm` or `--fastGWA-mlm-binary`.
- Do not describe `ldak_reml`, `ldak_he`, and `ldak_pcgc` as interchangeable;
  grouping them under one software citation is acceptable, but prose may list
  the selected estimator names if desired.
- Do not treat the Methods text as a complete reproducibility record. Retain the
  warning about external configs/profiles and direct users to workflow parameters,
  Software Versions, retained manifests, and method options.
- HTML-escape or otherwise safely render the command line. The inherited
  `SimpleTemplateEngine` pattern injects `workflow.commandLine` into HTML; tests
  should cover `<`, `>`, `&`, and quotes before claiming safe rendering.

## Tests and verification

### Pure-function tests

Add focused tests for citation-key selection and rendering:

- one association route;
- all four association routes;
- each heritability route;
- all three LDAK estimators together produce one LDAK bibliography entry;
- GCTA GREML and GREML-LDMS produce their distinct references;
- no association methods means no GWASLab reference;
- any association method means exactly one GWASLab reference;
- duplicate methods across analysis rows are deduplicated;
- reordered analysis rows produce byte-identical rendered YAML;
- MultiQC appears exactly once;
- an unknown method should fail loudly in the helper if it somehow bypasses
  manifest validation, rather than silently omitting a citation.

### Template tests

- DOI present and DOI absent;
- multiple comma-delimited DOIs;
- custom template interpolation still receives all documented keys;
- bibliography HTML remains inside the `<ul>` and produces valid YAML;
- no empty `<p></p>` is rendered;
- command-line special characters do not break or inject HTML;
- the generated file has the stable custom-content ID
  `nf-core-gwas-methods-description`.

### Workflow integration test

Extend one small fixture-backed route test to inspect
`methods_description_mqc.yaml` or the MultiQC report data:

- select two different method families across multiple analysis rows;
- assert both selected citations are present;
- assert one unselected route citation is absent;
- assert GWASLab and MultiQC are present;
- assert the Software Versions section remains collated from the topic channel.

Then run the focused nf-test, formatting/lint appropriate to the touched files,
and the repository's standard broad sharded validation followed by the sequential
stale-snapshot check if implementation changes workflow execution.

## Files expected to change during implementation

- `subworkflows/local/utils_nfcore_gwas_pipeline/main.nf`
- `workflows/gwas.nf`
- `assets/methods_description_template.yml`
- `CITATIONS.md`
- focused utility/template tests and one route integration expectation

Do not couple this work to the proposed analysis summary table. Both are MultiQC
inputs, but the summary table is analysis-row data and this packet is publication
prose plus references; keeping separate generated YAML files makes each independently
testable and replaceable.
