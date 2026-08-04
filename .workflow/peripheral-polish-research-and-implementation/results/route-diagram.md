# Route diagram research

## Recommendation

Add one maintainable metro-map-style overview immediately after the Introduction in `README.md`, before
`## Pipeline summary`. Keep its editable source at `assets/metro_map.mmd`, render a static SVG and PNG into
`docs/images/`, and make the static SVG the normal README image. Do not make animation the only presentation.

The diagram should explain public pipeline routes and reuse boundaries, not reproduce the Nextflow DAG or
individual process graph. The useful level is: linked inputs -> shared preparation -> selected association or
heritability route -> user-visible result families -> run report.

Recommended artifact set:

- `assets/metro_map.mmd`: reviewed source of truth, committed.
- `docs/images/nf-core-gwas_metro_map.svg`: primary rendered documentation image, committed.
- `docs/images/nf-core-gwas_metro_map.png`: static fallback and social/presentation-friendly raster, committed.
- `docs/dev/metro_map.md`: exact pinned/minimum tool requirements and reproducible render commands.

An animated SVG can be added later, but is not needed for this pass. A light/dark pair is also optional: the
RNA-seq grey map demonstrates that a single neutral, high-contrast asset can work, whereas MAG demonstrates
the `<picture>` light/dark pattern when genuinely distinct assets exist. Prefer one accessible neutral asset
over duplicating artwork that has no meaningful theme difference.

## Local reference evidence

### nf-core/rnaseq: strongest source/render policy

- `.references/rnaseq/assets/metro_map.mmd` is editable Mermaid-like `nf-metro` source with declared route
  lines, input/output file nodes, subgraphs, and a legend.
- `.references/rnaseq/docs/dev/metro_map.md` records the generator (`nf-metro>=0.5.4`), SVG and PNG commands,
  spacing/options, logo input, and the additional animated render.
- `.references/rnaseq/README.md:26-28` embeds the animated SVG but immediately supplies a static PNG fallback.
- Rendered artifacts live under `docs/images/`; source does not live there.

Accepted practice: commit the editable source, generated documentation assets, and regeneration instructions.
The animated-first README presentation is not required here; static-first is simpler and more accessible.

### nf-core/mag: theme-aware embedding

- `.references/mag/README.md:31-37` uses a `<picture>` block with dark and light PNG sources and descriptive
  alt text (`nf-core/mag metromap diagram`).
- MAG commits both SVG and PNG variants under `docs/images/`.
- No corresponding editable diagram source or regeneration guide was found in the checkout.

Accepted practice: `<picture>` is appropriate if separate tested themes exist. Rejected practice: rendered
assets without a discoverable source and regeneration contract.

### nf-core/sarek: overview plus detailed subway map

- `.references/sarek/README.md:37-40` presents a small high-level workflow image in the Introduction.
- `.references/sarek/README.md:76-79` presents a larger animated subway map after the textual Pipeline summary.
- Static SVG/PNG and animated SVG variants are committed under `docs/images/`.
- No editable source or regeneration guide was found in the checkout.

Sarek shows that two abstraction levels can be useful for a very large pipeline. GWAS does not need both: one
compact public-route map is sufficient and avoids duplicated documentation.

### Repository standard

`docs/coding-standards/documentation-and-assets.md` fixes the README core order as Introduction -> Pipeline
summary -> Usage -> Pipeline output -> Credits -> Contributions and Support -> Citations. A diagram nested in
the Introduction (after its two explanatory paragraphs) preserves this order. The standard does not prescribe
a diagram generator or asset naming scheme, so the newer, reproducible RNA-seq pattern is the best reference.

Local evidence was sufficient; no web sources were needed.

## Current GWAS topology and truthful diagram content

The public topology below is derived from `main.nf`, `workflows/gwas.nf`, and the route subworkflows—not from
ticket descriptions.

### Inputs and initialisation

- `main.nf:32-43` supplies the cohort manifest, analysis manifest, and optional method-options document to
  pipeline initialisation.
- `subworkflows/local/utils_nfcore_gwas_pipeline/main.nf:103-124` validates both complete manifests and their
  relationship before constructing the analysis channel.
- Therefore show the two linked manifests as distinct inputs joined at **Validate linked manifests**. Show
  method options as optional configuration feeding validation, not as a third manifest.

### Shared preparation

- `workflows/gwas.nf:68` prepares each distinct cohort's input genotype representation into canonical PLINK
  bundles via `PREPARE_COHORT_GENOTYPES`.
- `workflows/gwas.nf:83` normalises phenotype and optional quantitative/categorical covariates per analysis.
- `workflows/gwas.nf:73` builds selected relatedness matrices once per compatible request and fans them back
  to analyses.
- Show genotype preparation and phenotype/covariate normalisation as shared seams. Show relatedness-matrix
  preparation feeding only the routes that consume a matrix (fastGWA and heritability), not all association
  methods.

### Association routes

Show four peer public routes selected per analysis:

1. **PLINK 2 GLM** (`workflows/gwas.nf:121`)
2. **REGENIE** with reusable Step 1 predictions (`workflows/gwas.nf:134` and
   `subworkflows/local/route_regenie_associations/main.nf`)
3. **GCTA fastGWA-MLM** using a sparse GRM (`workflows/gwas.nf:216`)
4. **LDAK-KVIK** with reusable Step 1 predictions (`workflows/gwas.nf:167` and
   `subworkflows/local/route_ldak_kvik_associations/main.nf`)

All four native result streams feed **GWASLab harmonisation** (`workflows/gwas.nf:232-278`). The diagram must
show both outputs: native association results remain user-visible, while GWASLab produces standardised summary
statistics. Do not imply GWASLab selects scientific routes or that ancestry selects references; build-keyed
reference resources are the implemented input.

### Heritability routes

Show five peer estimators selected per analysis, grouped by implementation family:

- **GCTA GREML** (dense GRM)
- **GCTA GREML-LDMS** (LDMS/MGRM family)
- **LDAK REML**
- **LDAK Haseman-Elston**
- **LDAK PCGC**

`workflows/gwas.nf:280-402` confirms these routes. All produce individual-level heritability outputs. The map
should not show Manhattan, QQ, or heritability report panels: those products do not exist in this release.

### Reporting

`workflows/gwas.nf:405-454` collates versions, workflow parameters, methods description, and MultiQC. Draw a
dashed reporting line or separate neutral line from the whole run to **MultiQC + software/run provenance**;
do not suggest that scientific result files pass through MultiQC or that MultiQC transforms them.

## Proposed diagram model

Use a left-to-right map with three visual route families:

```text
Cohort manifest -----\
                      > Validate + join -> Shared cohort genotype preparation -----------+
Analysis manifest ---/                         |                                         |
        |                                      +-> Relatedness-matrix preparation         |
        +-----------------> Phenotype/covariate normalisation                            |
                                                                                         |
 Association routes: PLINK 2 | REGENIE | fastGWA | LDAK-KVIK -> Native results ----------+
                                                       \-> GWASLab -> Standardised stats  |
                                                                                         |
 Heritability routes: GCTA GREML | GCTA GREML-LDMS | LDAK REML | LDAK HE | LDAK PCGC
                                                       \-> Heritability estimates         |
                                                                                         |
 Whole run -------------------------------------------------------> MultiQC + provenance  |
```

For an `nf-metro` source, use route lines rather than nine disconnected boxes where possible:

- four association lines, with shared stations for manifest validation, cohort preparation, phenotype
  normalisation, native result publication, and GWASLab harmonisation;
- five heritability lines, sharing validation, preparation, phenotype normalisation, matrix-family stations,
  and heritability output;
- one neutral reporting line or visually separate annotation for MultiQC/provenance.

Route labels should use user-facing names exactly as the docs do. Keep internal process names, tuple shapes,
channel operators, cache keys, and module implementation details out of the graphic.

## Placement and README markup

Place the image after the Introduction's input-QC warning and before `## Pipeline summary`. That allows the
existing numbered summary to remain the text equivalent and preserves the documented section order.

Static-first markup:

```markdown
![Overview of the nf-core/gwas analysis routes](docs/images/nf-core-gwas_metro_map.svg)
```

If theme testing demonstrates a real need for separate images, use MAG's pattern:

```html
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/nf-core-gwas_metro_map_dark.svg">
  <img alt="Overview of the nf-core/gwas analysis routes" src="docs/images/nf-core-gwas_metro_map_light.svg">
</picture>
```

Do not use only a title attribute; use meaningful `alt`. Do not encode the whole workflow in the alt text—the
adjacent numbered Pipeline summary is the detailed text alternative.

## Accessibility and presentation constraints

- Use redundant identity: line labels and station/tool names in addition to colour. Colour alone must not
  distinguish methods.
- Maintain high contrast on both GitHub themes and the nf-core website.
- Avoid red/green-only distinctions and very pale grey labels.
- Use a static artifact as the baseline. Any animation must respect the same information hierarchy and have a
  static fallback; it must not be necessary to understand the map.
- Preserve readable text at typical README width. If nine method lines become visually dense, group the five
  heritability estimators into GCTA and LDAK branches while retaining every estimator label.
- Keep labels concise and expand uncommon abbreviations in the adjacent Pipeline summary.
- The diagram must not claim genotype QC, cross-run artifact import, ancestry-driven scientific routing,
  Manhattan/QQ plots, or a heritability dashboard.

## Anti-patterns

- Do not use Nextflow's generated DAG as the user overview; it exposes implementation complexity and changes
  too frequently.
- Do not commit only PNG. SVG is the primary scalable documentation format; PNG is a fallback.
- Do not commit generated SVG/PNG without the `.mmd` source and regeneration instructions.
- Do not hand-edit generated SVG after rendering; fix source or generator settings.
- Do not show all internal processes or every optional resource.
- Do not represent all matrices as a single interchangeable GRM: sparse, dense, LDMS, and LDAK kinship have
  different consumers.
- Do not imply that published intermediate artifacts are imported as caches in another launch.
- Do not add screenshots or nonexistent scientific report panels to make the diagram look more complete.

## Verification

1. Render from a clean checkout using the commands documented in `docs/dev/metro_map.md`.
2. Re-render a second time and confirm `git diff --exit-code` for deterministic output.
3. Confirm the SVG is well formed (for example `xmllint --noout`) and the PNG is readable (`file` plus an image
   inspection).
4. Open the README in both light and dark GitHub-style themes and at a narrow viewport; verify label contrast,
   no clipping, and reasonable scaling.
5. Disable animation if one is ever introduced and confirm no information is lost.
6. Compare every public route label against `docs/usage.md` selectors and `workflows/gwas.nf` invocations.
7. Confirm the diagram contains exactly four association routes and five heritability routes currently
   implemented.
8. Confirm native association output and GWASLab-standardised output are visually distinct.
9. Run Markdown/prettier checks and link/image-path checks used by repository CI.
10. Review the adjacent Pipeline summary as the diagram's textual equivalent and keep both synchronized when
    routes change.

## Integration decision

Accept a single reproducible static metro map now. Prefer the RNA-seq source/render documentation practice,
use MAG's theme-aware markup only if theme-specific assets prove necessary, and omit Sarek-style duplication
between a high-level workflow image and a detailed subway map. This is enough polish without making the
documentation asset harder to maintain than the pipeline contract it explains.
