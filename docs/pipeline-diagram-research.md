# Upstream pipeline-diagram research

Research snapshot: 2026-08-05. This note surveys diagrams present on the default branches of official
`nf-core/*` repositories at the commits linked below. The first section records what those diagrams do; the
second section proposes a design for nf-core/gwas. The recommendations are interpretations, not nf-core rules.

## Observations from current upstream repositories

### 1. nf-core/differentialabundance: the closest structural precedent

The [rendered diagram](https://github.com/nf-core/differentialabundance/blob/5cb5f9858f76cbd0a9daff09002f48b462e6707a/docs/images/nf-core-differentialabundance_metro_map.png)
and its [nf-metro source](https://github.com/nf-core/differentialabundance/blob/5cb5f9858f76cbd0a9daff09002f48b462e6707a/assets/metro_map.mmd)
show a pipeline with several real input modalities and several alternative analysis tools.

- Inputs are shown as the actual accepted scientific or control formats: GTF, TSV matrix, CSV samples,
  YAML contrasts, CEL, MaxQuant TSV, GEO identifier, GMT and network TSV. A generic `CSV` icon is not used
  as a substitute for the payload that the pipeline analyses.
- The broad labels are section titles: **Data import and preparation**, **Differential analysis**,
  **Functional enrichment**, **Plots** and **Reporting**.
- Stations within those sections are concrete programs or named procedures: `affy load`, `proteus`,
  `GEOquery`, `limma`, `DESeq2`, `dream`, `propd`, `GSEA`, `gprofiler2`, `decoupler`, `shinyngs` and
  `Quarto report`. `Validate`, `Filter matrix` and `Annotate results` are broad names, but they correspond to
  actual pipeline procedures and say what object is acted upon.
- Substitutable tools are drawn as parallel branches. `limma`, `DESeq2`, `dream` and `propd` occupy the same
  logical differential-analysis stage, then rejoin at `Annotate results`.
- Lines denote input/workflow families (RNA-seq counts, Affymetrix, MaxQuant and GEO), not every combination
  of optional method selections. The same family line can traverse a chosen tool branch and then continue
  through method-independent reporting.
- Terminal artifacts are concrete and visibly typed: HTML Shiny app, HTML report, ZIP bundle and PNG plots.
  The common reporting section follows the optional analytical branches rather than pretending that each
  report generator is another scientific method.

The project README embeds the animated form and links a static fallback in its
[pipeline summary](https://github.com/nf-core/differentialabundance/blob/5cb5f9858f76cbd0a9daff09002f48b462e6707a/README.md#pipeline-summary).

### 2. nf-core/ampliseq: group alternatives when a metro line would become unreadable

The [workflow overview](https://github.com/nf-core/ampliseq/blob/d56f90c396036a0f3850b28cf5ed8c2943b90918/docs/images/ampliseq_workflow.svg)
is a block diagram rather than a strict metro map.

- The input block distinguishes FASTQ reads or a TSV sample sheet from precomputed FASTA ASVs, while optional
  TSV metadata enters later at visualisation. The scientific objects and the files used to describe them are
  both visible, but not conflated.
- Broad boxes name aggregate stages such as **Pre-processing**, **Infer ASVs**, **Post-processing**,
  **Taxonomic classification**, **Filtering**, **Tables**, **Visualisation** and **Reporting**.
- Each stage contains the real alternatives or procedures. Taxonomic classification, for example, lists
  DADA2, QIIME2, SINTAX, Kraken2 and VSEARCH/LCA together instead of drawing a separate full-length route for
  every possible classifier.
- The legend encodes execution semantics (default, mandatory, on demand and optional), while green fill marks
  the default choices. This avoids spending colours on every program combination.
- Reporting ends in a concise family of actual output formats: HTML, TSV, FASTA, BIOM, Newick and RDS.

This is useful evidence that a large option space does not have to be represented as one metro line per method.
The official [README summary](https://github.com/nf-core/ampliseq/blob/d56f90c396036a0f3850b28cf5ed8c2943b90918/README.md#pipeline-summary)
also describes the tools behind those grouped procedures.

### 3. nf-core/atacseq: fork at a substitutable program, then rejoin

The [ATAC-seq metro map](https://github.com/nf-core/atacseq/blob/e805fffab3d2113d41768d08a71bfdda129fe396/docs/images/nf-core-atacseq_metro_map_grey.svg)
starts with FASTQ and separately introduces GFF and FASTA references.

- Grey background regions carry broad stages such as **Pre-processing**, **Genome alignment**,
  **Alignment QC**, **Peak calling & QC** and **Enrichment analysis**.
- Stations name concrete software (`FastQC`, `Cutadapt`, `Chromap`, `BWA`, `Bowtie2`, `STAR`, `Picard`,
  `preseq`, `MACS2`, `Homer`, `deepTools`, `MultiQC`) or a specific procedure whose implementation is
  clarified in the diagram (`Filtering`, with samtools/bedtools/bamtools/pysam in its footnote).
- Alternative aligners fan out into four short branches and rejoin before Picard. The rest of the pipeline is
  not duplicated for each aligner.
- The legend explains mandatory versus optional stations, file inputs, and the meaning of the two route
  colours (merged libraries and optionally merged replicates).
- BAM/BAI, bigWig, HTML, XML and tabular artifacts are placed at the points where they are produced, rather
  than represented by a generic “results” endpoint.

The same diagram is the first item in the official
[pipeline summary](https://github.com/nf-core/atacseq/blob/e805fffab3d2113d41768d08a71bfdda129fe396/README.md#pipeline-summary).

### 4. nf-core/methylseq: colours can represent complete alternative workflows

The [methylseq metro map](https://github.com/nf-core/methylseq/blob/cc11bd943e6c6edf0ee3ef6e22753b3764c63471/docs/images/4.2.0_metromap.svg)
uses three coloured paths for the TAPS, bwa-meth and Bismark workflows.

- FASTQ is the primary scientific input; GTF and FASTA enter at the reference seam.
- Numbered grey regions are aggregate stages: pre-processing, genome alignment, post-processing and final QC.
- The routes share `cat fastq`, `FastQC` and `Trim Galore`, fork into specifically labelled alignment tools,
  follow route-specific post-processing programs, and reconverge for `preseq`, `Qualimap` and `MultiQC`.
- The legend has only one entry per coherent workflow, even though each workflow contains multiple programs.
- TSV and HTML artifacts are shown where produced. Optional steps are marked in the station label rather than
  encoded as a vague stage.

The [README explanation](https://github.com/nf-core/methylseq/blob/cc11bd943e6c6edf0ee3ef6e22753b3764c63471/README.md#pipeline-summary)
explicitly maps the selectable aligners to these workflows.

### 5. nf-core/viralrecon: split diagrams when the topologies are genuinely different

Viralrecon maintains separate maps for
[Illumina](https://github.com/nf-core/viralrecon/blob/fa23078485cb75e96add952045b2b897aab61b42/docs/images/nf-core-viralrecon_metro_map_illumina.svg)
and [Nanopore](https://github.com/nf-core/viralrecon/blob/fa23078485cb75e96add952045b2b897aab61b42/docs/images/nf-core-viralrecon_metro_map_nanopore.svg),
both embedded in its [pipeline summary](https://github.com/nf-core/viralrecon/blob/fa23078485cb75e96add952045b2b897aab61b42/README.md#pipeline-summary).

- Each map begins with the relevant sequencing-read format (FASTQ or FAST5) and uses numbered stage regions.
- Nearly every station is a program (`FastQC`, `fastp`, `Kraken2`, `Bowtie2`, `iVar`, `BCFtools`, `SPAdes`,
  `Unicycler`, `Pangolin`, `Nextclade`, `MultiQC`).
- The Illumina legend assigns colours to coherent caller combinations such as “variants iVar, consensus iVar”
  or “variants BCFtools, consensus BCFtools”; assembly is a separate route. Branches rejoin when they again
  share a procedure.
- The Nanopore topology is sufficiently different that it is not squeezed into the Illumina canvas. It uses a
  smaller, independently legible map.
- Terminal TSV and HTML outputs are explicit.

### 6. nf-core/rnafusion: parallel callers can converge on a common collector

The [rnafusion metro map](https://github.com/nf-core/rnafusion/blob/1c315381be24f5afb9a55464517a6bc522bf5071/docs/images/nf-core-rnafusion_metro_map.svg)
shows FASTQ through shared `fastqc`, `fastp` and `STAR align` stations, then fans out to StringTie,
CTAT-Splicing, STAR-Fusion, Arriba and FusionCatcher.

- Alternative callers have separate tracks and concrete labels.
- The relevant caller outputs converge on `fusion-report`, after which downstream consumers such as
  FusionInspector, Arriba visualisation and VCF collection branch again.
- QC is allowed to terminate separately at Picard and MultiQC instead of being forced through the caller
  collector.
- A TXT file icon identifies the collected fusion-report artifact, while other terminal functions remain named.

The official README embeds it under the
[pipeline summary](https://github.com/nf-core/rnafusion/blob/1c315381be24f5afb9a55464517a6bc522bf5071/README.md#pipeline-summary).

### 7. nf-core/oncoanalyser: for a dependency-rich pipeline, show the process network

The [oncoanalyser process diagram](https://github.com/nf-core/oncoanalyser/blob/50c177c36b977c6f2f8b5c4375d3e6ddaf40e3d0/docs/images/oncoanalyser_pipeline.png)
is a deliberately large dependency map.

- DNA and RNA FASTQ inputs remain separate. Each follows real programs such as BWA-MEM2/REDUX or
  STAR/MarkDuplicates before entering the tool network.
- Parallel tools are not hidden under conceptual labels: AMBER, COBALT, ESVEE, SAGE, VirusBreakend, PURPLE,
  LINX, ISOFOX, CUPPA and other named components appear as stations.
- Lines show which products feed downstream consumers, including cross-links between the DNA and RNA sides.
- Reporting is a distinct lower section. Outputs from many tools are aggregated into ORANGE, while LINX has
  its own report path.
- A small inline legend marker identifies processes restricted to the whole-genome/transcriptome mode, rather
  than requiring another route colour for that condition.

The official [pipeline overview](https://github.com/nf-core/oncoanalyser/blob/50c177c36b977c6f2f8b5c4375d3e6ddaf40e3d0/README.md#pipeline-overview)
uses the diagram to introduce the several available workflows.

## Cross-pipeline patterns

The examples do not impose one visual grammar, but they converge on several practices:

1. **Show the scientific payload, not only its index.** Sample sheets and manifests can appear, but FASTQ,
   FASTA, BAM, matrices and references remain visible as the data being processed.
2. **Use broad wording for regions, not for invented stations.** “Pre-processing” and “Differential analysis”
   work as backgrounds. Stations generally name a program or a real, bounded procedure such as matrix
   filtering.
3. **Branch only for a meaningful choice.** Alternative tools fork briefly and rejoin at their common consumer,
   or colours encode a small number of coherent end-to-end workflows.
4. **Do not encode the Cartesian product.** Large option spaces are handled with grouped stage contents,
   method-family routes, annotations, or separate diagrams.
5. **Keep reporting method-independent.** MultiQC, Quarto, Shiny or a pipeline-specific report receives the
   products it actually consumes; it is not presented as another scientific method.
6. **Name terminal artifacts.** File icons and labels identify the outputs users will look for. A shared icon is
   appropriate only when the routes truly emit the same output contract.
7. **Use the legend to explain one semantic dimension.** Successful legends explain workflow families,
   optionality, or node types. They do not repeat every station label.

## Recommended nf-core/gwas design

### Design decision

Use one **stacked overview containing a shared input/preparation
area, an association panel, a heritability panel and a reporting/output area**. This combines the branching
grammar of differentialabundance/atacseq with the separate scientific regions used by ampliseq and
oncoanalyser.

Use the diagram as a future scientific product overview, not as a rendering of Nextflow channel
operations. In particular, omit `Validate and join manifests`, `Prepare association inputs`, `Association
testing`, `Prepare inputs and matrices` and `Heritability estimation` as stations. The target diagram should
communicate the intended tools, procedures and product contract without being constrained by the order in
which an intermediate implementation happens to compose them.

The future product contract has exactly two terminal products:

- all association results are harmonised into the canonical **GWASLab summary-statistics format**; native
  association files are implementation intermediates and are not presented as products;
- all heritability estimates are incorporated into the **MultiQC HTML report**, alongside run provenance and
  method summaries; estimator-native files are not presented as terminal products.

### Proposed content

#### 1. Inputs and control declarations

Show the payloads prominently:

- **PLINK 2:** PGEN + PVAR + PSAM;
- **PLINK 1:** BED + BIM + FAM;
- **VCF:** VCF/VCF.GZ;
- **phenotype table** and optional **quantitative/categorical covariate tables**.

Show **cohort manifest** and **analysis manifest** as smaller control-sheet inputs attached to the input/routing
area. They are required launch inputs and should not disappear, but their role is to point at the files and
select analyses; they are not the genotype payload. If space is tight, one annotation such as “manifests link
files, traits and methods” is more informative than two leading CSV file icons.

#### 2. Shared preparation

Use concrete stations and bypasses:

- supplied PLINK 2 proceeds directly;
- PLINK 1 and VCF pass through **PLINK 2 conversion** (`MAKEPGEN` / VCF import);
- a short optional branch derives **PLINK 1** (`MAKEBED`) only for routes that require it;
- phenotype and covariate files pass through **Phenotype and covariate normalisation**
  (`NORMALISE_PHENOTYPES`).

“Input and preparation” can be the broad background title. The stations themselves should retain the exact
program/procedure vocabulary.

#### 3. Association panel

Draw four parallel method routes after the common prepared genotype/trait seam:

- **PLINK 2 `--glm`**;
- **REGENIE Step 1 → REGENIE Step 2** (the split-L0/run-L0/run-L1 execution mode can be a small annotation,
  not another full route);
- **GCTA GRM → GCTA fastGWA-MLM**;
- **LDAK predictor selection → LDAK-KVIK Step 1 → LDAK-KVIK Step 2**.

Each route should pass independently through a shared **GWASLab harmonisation** station. Multiple lines
sharing that station communicate “the same canonicalisation procedure is applied to each result”; they must
not visually imply that method-native results are retained as final products.

Terminate the association panel only at **harmonised GWASLab summary statistics**. The file family may contain
one canonical-format file per requested method and analysis, but the public product contract is one format.

#### 4. Heritability panel

Use the matrix builders as real stations, because matrix choice is scientifically meaningful and is shared by
downstream estimators:

- **GCTA dense GRM → GCTA GREML**;
- **GCTA LDMS GRMs → GCTA GREML-LDMS**;
- **LDAK kinship** (with a visibly optional **relatedness filter/sub-GRM** seam) branching to
  **LDAK REML**, **LDAK Haseman-Elston** and **LDAK PCGC**.

Where covariate-adjusted LDAK matrices are relevant, annotate **LDAK adjust-GRM** on the HE/PCGC branch rather
than hiding it in “prepare matrices.” Route all estimator outputs onward to MultiQC rather than ending the
paths at estimator-native files.

#### 5. Reporting

Place **MultiQC** in a reporting section fed by all heritability estimators plus run metadata, method summaries
and logs. It remains visually separate from the scientific method panels, but it is the public endpoint for
heritability estimates rather than merely an ancillary QC report.

### Route colours and legend

Use one colour per **program family**, not one colour for all nine method selectors:

- PLINK 2;
- REGENIE;
- GCTA;
- LDAK;
- a neutral/shared colour for common preparation, GWASLab and MultiQC seams.

The program names at branches carry the method distinctions (fastGWA versus GREML, or REML versus HE versus
PCGC). This keeps the legend short while preserving every planned scientific alternative. Add only a
second, orthogonal legend key for the optional relatedness-filter route so that its bypass is visible rather
than merely described by a station label.

### Layout sketch

```text
scientific files + manifests
          │
          ├── PLINK 2 conversion / PLINK 1 derivative ───────────────┐
          └── phenotype + covariate normalisation ───────────────────┤
                                                                    │
  Association                                                       │
    PLINK 2 --glm ──────────────────────────────┐                    │
    REGENIE Step 1 ── Step 2 ──────────────────┤                    │
    GCTA GRM ── fastGWA-MLM ───────────────────┼─ GWASLab ── harmonised TSV.GZ
    LDAK predictors ── KVIK Step 1 ── Step 2 ──┘

  GCTA heritability
    dense GRM ── GREML ───────────────────────────────────┐
    LDMS GRMs ── GREML-LDMS ──────────────────────────────┤
                                                          ├─ MultiQC ── HTML
  LDAK heritability                                      │
    kinship ────────┬─ REML ──────────────────────────────┤
                    ├─ [adjust-GRM] ─ HE ─────────────────┤
                    └─ [adjust-GRM] ─ PCGC ───────────────┤
    kinship ── [optional relatedness filter] ─────────────┘

  Reporting: run metadata + method summaries + logs ──────┘

  Final products: harmonised GWASLab summary statistics + MultiQC HTML
```

This sketch is semantic, not a proposed final geometry. In the rendered version, the association and
GCTA and LDAK heritability regions should occupy separate lower cells so their alternatives remain readable.

### Review gates before changing the committed image

1. Agree on the station inventory and which implementation details remain annotations.
2. Make a low-fidelity render with the proposed inputs and two stacked panels.
3. Check that every line corresponds to an intended scientific path and every file icon corresponds to a
   planned public input or product.
4. Inspect the raster and SVG on both light and dark backgrounds at README scale, checking label collisions,
   crossings, unused space, terminal clarity and transparent margins.
5. Only then replace the committed source and image artifacts.
