# Local component reachability after the native-results refactor

This audit records the local-component graph at commit
`5934ef29bd141cc0ca6d8ebbd24bfc1f834da30c`, immediately after the native-results refactor. It is the deletion
decision record for issue 27: a component is retained only when the production entrypoint reaches it or when it
is an explicitly supported standalone reusable composition.

## Method

The audit enumerated every tracked `main.nf` below `modules/local/` and `subworkflows/local/`, resolved every
relative module and subworkflow include recursively from the pipeline `main.nf`, and then checked the resulting
graph against component metadata, component tests, pipeline tests, configuration selectors, `modules.json`,
documentation and repository-wide symbol references. A component's own metadata or tests do not count as a
consumer. The standalone meta-analysis composition is counted separately from the production graph because its
component contract, tests and documented API are intentionally retained while pipeline routing remains out of
scope.

The baseline contains 67 local components:

| Classification | Modules | Subworkflows | Total |
| --- | ---: | ---: | ---: |
| Production-active | 36 | 19 | 55 |
| Retained standalone reusable | 4 | 1 | 5 |
| Orphan | 5 | 0 | 5 |
| Superseded duplicate | 0 | 2 | 2 |
| Test-only or self-referential | 0 | 0 | 0 |
| **Total** | **45** | **22** | **67** |

## Module inventory

| Local module | Classification | Active consumer or decision |
| --- | --- | --- |
| `attribute_ldak_kvik_predictions` | Production-active | `route_ldak_kvik_associations` |
| `attribute_regenie_predictions` | Production-active | `route_regenie_associations` |
| `custom/gctacreatemgrmmanifest` | Production-active | `plink_prepare_grm_ldms_gcta` |
| `custom/gctamergegrmparts` | Production-active | `plink_prepare_grm_gcta` |
| `custom/gctastratifyldscores` | Production-active | `plink_prepare_grm_ldms_gcta` |
| `gcta/bivariatehereg` | Production-active | `route_gcta_bivariate_relationships` |
| `gcta/bivariateheregldms` | Production-active | `route_gcta_bivariate_relationships` |
| `gcta/calculateldscores` | Production-active | `plink_prepare_grm_ldms_gcta` |
| `gcta/fastgwa` | Production-active | `route_association_analyses` |
| `gcta/makebksparse` | Production-active | `prepare_relatedness_matrices` |
| `gcta/makegrmpart` | Production-active | `plink_prepare_grm_gcta` |
| `gcta/reml` | Production-active | `grm_heritability_gcta` |
| `gcta/remlldms` | Production-active | `grm_heritability_gcta` |
| `gwaslab/harmonize` | Production-active | `route_canonical_summary_statistics` |
| `gwaslab/meta_analyze` | Retained standalone reusable | `common_variant_meta_analysis` |
| `ldak/addgrms` | Orphan | Delete: no production or supported standalone consumer |
| `ldak/adjustgrm` | Production-active | `grm_heritability_ldak` |
| `ldak/calcgenotypeerrort2` | Orphan | Delete: no production or supported standalone consumer |
| `ldak/calcinflation` | Orphan | Delete: no production or supported standalone consumer |
| `ldak/calckins` | Production-active | `plink_prepare_grm_ldak` |
| `ldak/createthinweights` | Orphan | Delete: no production or supported standalone consumer |
| `ldak/filter` | Production-active | `plink_prepare_grm_ldak` |
| `ldak/he` | Production-active | `grm_heritability_ldak` |
| `ldak/kvikstep1` | Production-active | `route_ldak_kvik_associations` |
| `ldak/kvikstep2` | Production-active | `route_ldak_kvik_associations` |
| `ldak/pcgc` | Production-active | `grm_heritability_ldak` |
| `ldak/reml` | Production-active | `grm_heritability_ldak` |
| `ldak/subgrm` | Production-active | `plink_prepare_grm_ldak` |
| `ldak/sumcors` | Production-active | `route_ldak_summary_analyses` |
| `ldak/sumher` | Production-active | `route_ldak_summary_analyses` |
| `ldak/thincommon` | Production-active | `route_ldak_kvik_associations` |
| `ldak/thinpredictors` | Orphan | Delete: no production or supported standalone consumer |
| `ldsc/h2` | Production-active | `route_ldsc_summary_analyses` |
| `ldsc/mungesumstats` | Production-active | `route_ldsc_summary_analyses` |
| `ldsc/rg` | Production-active | `route_ldsc_summary_analyses` |
| `metasoft/re2` | Retained standalone reusable | `common_variant_meta_analysis` |
| `mrmega` | Retained standalone reusable | `common_variant_meta_analysis` |
| `plink2/glm` | Production-active | `route_association_analyses` |
| `plink2/makebed` | Production-active | `prepare_cohort_genotypes` |
| `plink2/makepgen` | Production-active | `prepare_cohort_genotypes` |
| `plink2/vcf` | Production-active | `prepare_cohort_genotypes` |
| `prepare_bivariate_traits` | Production-active | `route_gcta_bivariate_relationships` |
| `prepare_ldak_summary_statistics` | Production-active | `route_ldak_summary_analyses` |
| `prepare_mrmega_input` | Retained standalone reusable | `common_variant_meta_analysis` |
| `prepare_phenotype_inputs` | Production-active | `workflows/gwas.nf` |

## Subworkflow inventory

| Local subworkflow | Classification | Active consumer or decision |
| --- | --- | --- |
| `common_variant_meta_analysis` | Retained standalone reusable | Tested and documented public composition; not routed by the pipeline |
| `grm_heritability_gcta` | Production-active | `route_grm_heritability` |
| `grm_heritability_ldak` | Production-active | `route_grm_heritability` |
| `plink_association_ldak_kvik` | Superseded duplicate | Delete: prediction reuse moved to `route_ldak_kvik_associations` |
| `plink_fit_regenie` | Production-active | `route_regenie_associations` |
| `plink_gwas_regenie` | Superseded duplicate | Delete: prediction reuse moved to `route_regenie_associations` |
| `plink_prepare_grm_gcta` | Production-active | `prepare_relatedness_matrices` and `plink_prepare_grm_ldms_gcta` |
| `plink_prepare_grm_ldak` | Production-active | `prepare_relatedness_matrices` |
| `plink_prepare_grm_ldms_gcta` | Production-active | `prepare_relatedness_matrices` |
| `prepare_cohort_genotypes` | Production-active | `workflows/gwas.nf` |
| `prepare_relatedness_matrices` | Production-active | `workflows/gwas.nf` |
| `route_association_analyses` | Production-active | `workflows/gwas.nf` |
| `route_canonical_summary_statistics` | Production-active | `workflows/gwas.nf` |
| `route_gcta_bivariate_relationships` | Production-active | `workflows/gwas.nf` |
| `route_grm_heritability` | Production-active | `workflows/gwas.nf` |
| `route_gwas_reporting` | Production-active | `workflows/gwas.nf` |
| `route_ldak_kvik_associations` | Production-active | `route_association_analyses` |
| `route_ldak_summary_analyses` | Production-active | `workflows/gwas.nf` |
| `route_ldsc_summary_analyses` | Production-active | `workflows/gwas.nf` |
| `route_regenie_associations` | Production-active | `route_association_analyses` |
| `utils_nfcore_gwas_pipeline` | Production-active | Pipeline entrypoint and `workflows/gwas.nf`; also owns imported reporting helpers |
| `validate_gwas_input` | Production-active | `utils_nfcore_gwas_pipeline` plus imported route and preparation helpers |

## Dead surface in retained components

The same reference scan found five dead public or implementation surfaces in retained components:

- `PLINK_PREPARE_GRM_GCTA.effective_parts` is calculated only to be emitted and has no caller, publication rule
  or documented consumer. The gather still derives its group size internally; only the dead re-export is removed.
- `PREPARE_PHENOTYPE_INPUTS.log` and its `.prepare.log` diagnostic are not consumed or published. The phenotype
  and covariate outputs, explicit ingress errors and scientific normalization behavior remain unchanged.
- `PREPARE_BIVARIATE_TRAITS.log` and its `.pair.log` diagnostic are not consumed or published. The ordered trait
  union and relationship-covariate outputs remain unchanged.
- `ROUTE_CANONICAL_SUMMARY_STATISTICS.harmonization_log` duplicates an unconsumed route-level channel. The
  atomic `GWASLAB_HARMONIZE.log` output remains part of that module's contract and continues to publish beside
  each canonical summary-statistics table.
- `digestScientificInput` has no caller. The active identity helpers call `digestFileBytes` directly, so the
  unused compatibility wrapper is removed.

The scan also established boundaries that are deliberately unchanged here. LDAK `maxrel` state belongs to the
relatedness identity work, LDMS `strata` metadata must remain aligned with MGRM order, ThinCommon reuse is a
separate route change, validation is an ingress-contract change, LDSC preparation is a separate scaling change,
and prediction attribution and publication remain part of the prediction-cache work. None is changed by this
pruning pass.

## Expected post-deletion graph

Removing the five orphan modules and two superseded subworkflows leaves 60 local components: 55 production-active
and five retained standalone reusable components. Re-running reachability on that simulated graph produces no
new orphan, test-only or self-referential component. The implementation must reproduce that graph exactly and
must leave no reference to any deleted component in code, metadata, configuration, tests, snapshots,
`modules.json`, documentation or comments.
