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
5. `NORMALISE_PHENOTYPES` and the tool-neutral per-analysis seams derived from it, such as the headerless
   phenotype/covariate stream that GCTA-, LDAK- and fastGWA-shaped consumers share.
6. The route-controller calls and the visible dependencies between their semantic results.
7. The fan-out of canonical summary statistics to the summary-scale sibling routes.
8. Run-wide `versions` topic collection and collation into `pipeline_info/`.
9. The `ROUTE_GWAS_REPORTING` call.
10. The public `emit:` block.

A shared resource is built on the spine so that it is built once and fanned out to every consumer across every
domain. A route controller never owns shared genotype or matrix preparation, global validation, or a public
emission.

## Route controllers

| Controller                           | Owns                                                                                                 |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------- |
| `ROUTE_ASSOCIATION_ANALYSES`         | PLINK 2, REGENIE, LDAK-KVIK and GCTA fastGWA selection, and the fan-in to one raw-association stream |
| `ROUTE_GRM_HERITABILITY`             | Individual-level GCTA GREML/GREML-LDMS and LDAK REML/HE/PCGC estimator selection                     |
| `ROUTE_GCTA_BIVARIATE_RELATIONSHIPS` | GCTA bivariate REML and REML-LDMS relationship requests                                              |
| `ROUTE_CANONICAL_SUMMARY_STATISTICS` | Internal and external origins converging on one canonical serialisation per summary ID               |
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

## Adding a route

Attach a new summary-scale route at the SIBLING SEAM comment in `workflows/gwas.nf`, after canonical
convergence. The three-part pattern is: filter the validated request stream on `meta.method` on the spine; call
the controller with that selection plus `ROUTE_CANONICAL_SUMMARY_STATISTICS.out.summary_statistics` unmodified;
let the controller own everything downstream. The canonical stream is a plain queue channel, so an additional
reader adds no barrier and changes no existing cardinality — do not introduce a `collect()` or `groupTuple()`
to materialise it.

An individual-level route attaches instead alongside `ROUTE_GRM_HERITABILITY`, consuming the prepared genotype,
matrix and phenotype streams the spine already fans out.

## Process names

A process's fully qualified `task.process` includes its controller scope, for example
`NFCORE_GWAS:GWAS:ROUTE_LDSC_SUMMARY_ANALYSES:NORMALISE_LDSC`. Several modules serialise `task.process` into a
published `provenance.json`, so that scope is visible in results. Trace, resume and version surfaces are
leaf-normalised and unaffected. `withName:` selectors in `conf/modules/` are `.*:`-prefixed and match the leaf
regardless of controller scope; do not anchor one to a full path.
