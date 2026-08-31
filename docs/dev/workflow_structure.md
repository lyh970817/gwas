# Workflow structure

`workflows/gwas.nf` holds the single named `GWAS` workflow and is the pipeline spine. Everything that is
specific to one analytic domain lives in a pipeline-owned route controller under `subworkflows/local/route_*/`.
This page describes the code structure only; the scientific overview is `assets/metro_map.mmd` (see
[`metro_map.md`](metro_map.md)) and the result layout is [`../output.md`](../output.md).

## The spine

`GWAS` owns ten responsibilities and nothing else:

1. The public `take:` contract — nine positional inputs, in a load-bearing order that `main.nf` passes
   positionally.
2. Run-level analysis and method metadata, collected across all four request domains for the report.
3. The union of genotype consumers, and `PREPARE_COHORT_GENOTYPES`, which prepares each distinct cohort once.
4. The union of relatedness-matrix consumers, and `PREPARE_RELATEDNESS_MATRICES`, which builds each
   scientifically distinct matrix once.
5. `PREPARE_PHENOTYPE_INPUTS` and the tool-neutral per-analysis seams derived from it, such as the headerless
   phenotype/covariate stream that GCTA-, LDAK- and fastGWA-shaped consumers share.
6. The route-controller calls and the visible dependencies between their semantic results.
7. The fan-out of GWASLab-standard summary statistics to the summary-scale sibling routes.
8. Run-wide `versions` topic collection and collation into `pipeline_info/`.
9. The `ROUTE_GWAS_REPORTING` call.
10. The public `emit:` block.

A shared resource is built on the spine so that it is built once and fanned out to every consumer across every
domain. A route controller never owns shared genotype or matrix preparation, global validation, or a public
emission.

## Validation and method-registry ownership

`VALIDATE_GWAS_INPUT` is the one public ingress boundary. The four JSON schemas own manifest column names,
required fields, scalar types, enumerations, file existence and rejection of additional columns. nf-schema
converts each schema-approved row once. The only pre-conversion header check detects repeated CSV names,
because conversion to a map necessarily discards that information; it does not duplicate schema-required or
optional-column policy. Quoted headers and values are accepted, and schema-optional columns may be absent.

Relational checks are decomposed by the object they resolve:

- `resolve_cohorts.nf`, `resolve_analyses.nf`, `resolve_summary_statistics.nf` and
  `resolve_relationships.nf` own entity and cross-manifest contracts;
- `method_options.nf`, `native_option_policy.nf` and `request_contracts.nf` own public request capability and
  native-argument contracts;
- `resolve_references.nf` owns reference-catalog parsing and resource resolution;
- `resolve_input.nf` only orders those resolvers, reports their accumulated relational errors and constructs
  the five canonical streams.

The method registry contains no descriptive inventory. Every stored field has a live consumer:

| Registry field       | Active consumer                                                                                                  |
| -------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `domain`             | Selector vocabularies, request namespaces and methods reporting                                                  |
| `option_family`      | Per-family method-options validation and native-argument firewalls                                               |
| `matrix_kind`        | Relatedness construction, pair request settings and dense/LDMS controller routing                               |
| `endpoint_domain`    | Analysis-versus-summary relationship endpoint validation and resolution                                         |
| `reference_family`   | Reference-bundle requirements, family compatibility and request-resource routing                                |
| `estimator_family`   | GCTA REML method-options capability selection                                                                    |
| `input_backend`      | PLINK 1 preparation, matrix-family selection and summary-native policy                                           |
| `trait_support`      | Pair endpoint trait validation                                                                                   |
| `supports_covariates`| Pair covariate capability validation                                                                             |
| `prevalence`         | Analysis, generated-summary and pair prevalence validation                                                       |
| `citation_keys`      | Run-specific methods citations                                                                                   |
| `mapping`            | Association-result GWASLab column mapping                                                                        |

After this boundary, controllers and representation adapters trust the typed metadata they receive. The GCTA
bivariate controller routes on `matrix_kind`; it does not re-derive method groups. `PREPARE_BIVARIATE_TRAITS`
trusts the three-column phenotype emitted by `PREPARE_PHENOTYPE_INPUTS` and performs only ordered union and
left/right reshaping. Relationship-owned covariate files are raw public inputs, so that adapter still validates
their native table shape while removing their headers.

GWASLab 4.1.9 has no LDAK/SumHer/SumCors exporter. `PREPARE_LDAK_SUMMARY_STATISTICS` is therefore the one
minimal representation converter between the GWASLab-standard producer table and LDAK's native `Predictor`,
`A1`, `A2`, `n`, `Z` input. It neither revalidates the whole GWASLab table nor writes policy or provenance
sidecars.

## Route controllers

| Controller                           | Owns                                                                                                 |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------- |
| `ROUTE_ASSOCIATION_ANALYSES`         | PLINK 2, REGENIE, LDAK-KVIK and GCTA fastGWA selection, and the fan-in to one raw-association stream |
| `ROUTE_GRM_HERITABILITY`             | Individual-level GCTA GREML/GREML-LDMS and LDAK REML/HE/PCGC estimator selection                     |
| `ROUTE_GCTA_BIVARIATE_RELATIONSHIPS` | GCTA bivariate REML, HEreg and their LDMS relationship requests                                      |
| `ROUTE_CANONICAL_SUMMARY_STATISTICS` | Every internal and external origin crossing GWASLab once per summary ID                              |
| `ROUTE_LDAK_SUMMARY_ANALYSES`        | LDAK SumHer and SumCors                                                                              |
| `ROUTE_LDSC_SUMMARY_ANALYSES`        | LDSC munging reuse, H2 and RG                                                                        |
| `ROUTE_GWAS_REPORTING`               | MultiQC assembly                                                                                     |

`ROUTE_REGENIE_ASSOCIATIONS` and `ROUTE_LDAK_KVIK_ASSOCIATIONS` are nested inside
`ROUTE_ASSOCIATION_ANALYSES` and own their families' Step 1 prediction reuse.

Every controller receives all configuration values and resources explicitly through `take:`. A controller reads
no `params`, no `workflow` and no `projectDir` asset; the spine resolves those and passes them in. This is
checkable:

```bash
grep -rn 'params\.\|projectDir\|workflow\.' subworkflows/local/route_*/main.nf | grep -v '^\S*:[0-9]*: *//'
```

must return nothing; the only matches are the purpose comments asserting the property.

Route controllers are pipeline-routing components, not component-library submission candidates — see
[`../../subworkflows/local/AGENTS.md`](../../subworkflows/local/AGENTS.md). The reusable LDAK, GCTA, PLINK,
PLINK 2 and REGENIE compositions they call remain free of route selection, relational-manifest interpretation,
reuse identity and publication policy.

## Common meta-analysis composition

`COMMON_VARIANT_META_ANALYSIS` is implemented but is not yet wired into `GWAS`, the method registry, a manifest
contract or publication configuration. Its contract is deliberately model-specific:

- `GWASLAB_META_ANALYZE` emits `*.fixed.tsv.gz`, an optional `*.random.tsv.gz`, the native adapter inputs
  required by METASOFT and MR-MEGA, and its GWASLab log.
- `METASOFT_RE2` is a thin native invocation and emits `*.metasoft.txt` with `*.metasoft.log`.
- `PREPARE_MRMEGA_INPUT` adapts the aligned parents once in declared study order, using the request's explicit
  quantitative or binary trait type.
- `MRMEGA` runs once genome-wide without precalculated axes and emits its native `.result` and `.log`.

The composition does not scatter by chromosome, derive axes in a first pass, gather shards, normalize any
program's result, recompute native values or assemble columns from different models into one table.

## Adding a route

Attach a new summary-scale route at the SIBLING SEAM comment in `workflows/gwas.nf`, after GWASLab
convergence. The three-part pattern is: filter the validated request stream on `meta.method` on the spine; call
the controller with that selection plus `ROUTE_CANONICAL_SUMMARY_STATISTICS.out.summary_statistics` unmodified;
let the controller own everything downstream. The GWASLab-standard stream is a plain queue channel, so an
additional reader adds no barrier and changes no existing cardinality — do not introduce a `collect()` or
`groupTuple()` to materialise it.

An individual-level route attaches instead alongside `ROUTE_GRM_HERITABILITY`, consuming the prepared genotype,
matrix and phenotype streams the spine already fans out.

## Process names

A process's fully qualified `task.process` includes its controller scope, for example
`NFCORE_GWAS:GWAS:ROUTE_LDSC_SUMMARY_ANALYSES:LDSC_H2_OBSERVED`. Trace, resume and version surfaces retain that
scope. `withName:` selectors in `conf/modules/` are `.*:`-prefixed where the same leaf can be nested and match
the leaf regardless of controller scope; do not anchor one to a full path.
