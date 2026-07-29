# nf-core/gwas: Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.0.0dev - [date]

Initial release of nf-core/gwas, created with the [nf-core](https://nf-co.re/) template.

### `Added`

- Added the `NORMALISE_PHENOTYPES` local module, which normalises each analysis unit's phenotype and covariates once into a canonical layout: the trait at a fixed third column named `PHENO`, binary traits coded `0`/`1`/`NA` (the only coding PLINK 2, REGENIE, GCTA and LDAK all accept), missing values always the literal `NA`, quantitative and categorical covariates kept in separate files, and every file emitted in both a headered and a headerless serialisation because REGENIE requires a header and GCTA forbids one. The fixed column position makes GCTA's and LDAK's `--mpheno` a constant `1`. A `--save_normalised_phenotypes` save control, default `false`, publishes the headered files under `phenotypes/<analysis_id>/`.
- Added the `PLINK2_GLM` local module and wired PLINK 2 `--glm` as the pipeline's first end-to-end association route, with Firth fallback on binary traits and allele frequency and sample count columns requested explicitly for the harmonisation that follows. Results are published unmodified under `association/plink2/<analysis_id>/` as `<analysis_id>.plink2.glm.*`.
- Added the `GWASLAB_HARMONIZE` local module and passed every association result through it, so results from different methods on the same analysis are directly comparable — one canonical column set, allele orientation and variant identifier regardless of which programme produced them. Harmonised summary statistics are published under `summary_statistics/<analysis_id>/` as `<analysis_id>.<method>.gwaslab.tsv.gz`, keyed by analysis rather than by method so a cross-method comparison is a single directory listing, with the producing method carried by the filename and the `.gwaslab` tool suffix marking the file as harmonised. Native association output is preserved unmodified alongside it. Explicit column mappings are registered for all four association methods — PLINK 2, REGENIE, GCTA fastGWA and LDAK-KVIK — in one table, and the accepted `association_methods` vocabulary is derived from that table, so a route is selectable exactly when its mapping exists and adding a further route needs no new harmonisation component. Effect sizes and standard errors are written in scientific notation, because GWASLab's default fixed four-decimal format destroys them at the magnitudes a well-powered study produces.
- Added six optional GWASLab reference parameters — `--gwaslab_reference_fasta_grch37`/`_grch38`, `--gwaslab_rsid_vcf_grch37`/`_grch38` and `--gwaslab_strand_vcf_grch37`/`_grch38` — selected by the genome build each analysis declares in its samplesheet row and by nothing else, with index sidecars resolved by convention. A build with no configured resource is still standardised, without one.
- [#95](https://github.com/nf-core/gwas/pull/95) - Add the `regenie/runl1` module, completing the REGENIE Step 1 module set (`runl0`, `splitl0`, `runl1`, `step1`, `step2`).
- [#93](https://github.com/nf-core/gwas/pull/93) - Added LDAK local modules (addgrms, adjustgrm, calcgenotypeerrort2, calcinflation, calckins, createthinweights, filterrelatedness, he, kvikstep1, kvikstep2, pcgc, reml, thinpredictors) under `modules/local/ldak/`.

### `Changed`

- PLINK 2 `--glm` now requests `cols=+a1freq,+beta`, so the binary route reports `BETA`/`SE` instead of `OR`/`LOG(OR)_SE` and one GWASLab column mapping serves both trait types — otherwise the harmonised binary file would carry an odds ratio where every other method carries a log-odds beta. Native output is still published exactly as PLINK 2 wrote it; only the columns PLINK 2 is asked for changed, and the quantitative route is unaffected.
- Replaced the monolithic `conf/modules.config` with one configuration file per method family under `conf/modules/`, included by name from `nextflow.config`, so a later route ticket adds a file rather than editing a shared one. The process-wide default publish directive — which publishes nothing — now lives in `nextflow.config` itself. `docs/coding-standards/configuration-and-schema.md` §4 and the `.nf-core.yml` lint exemptions were amended in the same change.

### `Fixed`

- [#96](https://github.com/nf-core/gwas/pull/96) - Bump the `nft-utils` nf-test plugin to `0.0.9` for nf-test 0.9.4 compatibility (fixes `sanitizeOutput()` `MissingMethodException` in module tests after the 4.0.2 template merge).

### `Dependencies`

- Updated the `plink/gwas` (`2d5c9c0`) and `plink/vcf` (`6d46786`) modules to the latest nf-core/modules version, preserving the pipeline's local patches (the `plink/vcf` `--pheno`/`--make-bed` phenotype input and the `plink/gwas` split `assoc`/`qassoc` outputs plus resource-label overrides).
- Synced the vendored `modules/local/ldak/` family to the shared component library: the twelve name-matched modules now match the library byte-for-byte, `ldak/filter`, `ldak/subgrm` and `ldak/thincommon` were added, and `ldak/filterrelatedness` was removed in favour of the library's `filter` + `subgrm` split.

### `Deprecated`
