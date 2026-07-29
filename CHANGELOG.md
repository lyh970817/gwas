# nf-core/gwas: Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.0.0dev - [date]

Initial release of nf-core/gwas, created with the [nf-core](https://nf-co.re/) template.

### `Added`

- Added the `NORMALISE_PHENOTYPES` local module, which normalises each analysis unit's phenotype and covariates once into a canonical layout: the trait at a fixed third column named `PHENO`, binary traits coded `0`/`1`/`NA` (the only coding PLINK 2, REGENIE, GCTA and LDAK all accept), missing values always the literal `NA`, quantitative and categorical covariates kept in separate files, and every file emitted in both a headered and a headerless serialisation because REGENIE requires a header and GCTA forbids one. The fixed column position makes GCTA's and LDAK's `--mpheno` a constant `1`. A `--save_normalised_phenotypes` save control, default `false`, publishes the headered files under `phenotypes/<analysis_id>/`.
- Added the `PLINK2_GLM` local module and wired PLINK 2 `--glm` as the pipeline's first end-to-end association route, with Firth fallback on binary traits and allele frequency and sample count columns requested explicitly for the harmonisation that follows. Results are published unmodified under `association/plink2/<analysis_id>/` as `<analysis_id>.plink2.glm.*`.
- [#95](https://github.com/nf-core/gwas/pull/95) - Add the `regenie/runl1` module, completing the REGENIE Step 1 module set (`runl0`, `splitl0`, `runl1`, `step1`, `step2`).
- [#93](https://github.com/nf-core/gwas/pull/93) - Added LDAK local modules (addgrms, adjustgrm, calcgenotypeerrort2, calcinflation, calckins, createthinweights, filterrelatedness, he, kvikstep1, kvikstep2, pcgc, reml, thinpredictors) under `modules/local/ldak/`.

### `Changed`

- Replaced the monolithic `conf/modules.config` with one configuration file per method family under `conf/modules/`, included by name from `nextflow.config`, so a later route ticket adds a file rather than editing a shared one. The process-wide default publish directive — which publishes nothing — now lives in `nextflow.config` itself. `docs/coding-standards/configuration-and-schema.md` §4 and the `.nf-core.yml` lint exemptions were amended in the same change.

### `Fixed`

- [#96](https://github.com/nf-core/gwas/pull/96) - Bump the `nft-utils` nf-test plugin to `0.0.9` for nf-test 0.9.4 compatibility (fixes `sanitizeOutput()` `MissingMethodException` in module tests after the 4.0.2 template merge).

### `Dependencies`

- Updated the `plink/gwas` (`2d5c9c0`) and `plink/vcf` (`6d46786`) modules to the latest nf-core/modules version, preserving the pipeline's local patches (the `plink/vcf` `--pheno`/`--make-bed` phenotype input and the `plink/gwas` split `assoc`/`qassoc` outputs plus resource-label overrides).
- Synced the vendored `modules/local/ldak/` family to the shared component library: the twelve name-matched modules now match the library byte-for-byte, `ldak/filter`, `ldak/subgrm` and `ldak/thincommon` were added, and `ldak/filterrelatedness` was removed in favour of the library's `filter` + `subgrm` split.

### `Deprecated`
