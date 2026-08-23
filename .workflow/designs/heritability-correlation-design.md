# Heritability and genetic-correlation design

> [!IMPORTANT]
> **Design status:** the scientific and component-boundary design was accepted for first-release implementation
> on 2026-08-23; implementation readiness remains subject to the contract-completion gates below. This document
> describes the intended contract and does not claim that every route is implemented. Q47 remains provisional,
> Q27 and Q52 were withdrawn, and Q44 plus post-release argument curation are deferred to linked issues.

> [!NOTE]
> This is a tracked personal-workflow specification, not reviewer-facing pipeline documentation. Public
> documentation should describe only behavior that has been implemented on the portable pipeline track.

This specification consolidates the accepted SumHer, SumCors, LDSC, GCTA, and LDAK design decisions from the
heritability and genetic-correlation grilling session. It replaces the ignored HTML review artifact as the
durable implementation reference while preserving that artifact's approved organization of user inputs,
identities, requests, and outputs.

The implementation is a collection of explicit estimator routes, not an attempt to define a single best
heritability or genetic-correlation method. Every requested estimator result is retained and presented
independently.

## Status vocabulary

| Status      | Meaning                                                                                   |
| ----------- | ----------------------------------------------------------------------------------------- |
| Accepted    | Approved for the first-release implementation.                                            |
| Provisional | Usable as the current implementation assumption, but deliberately open to later revision. |
| Superseded  | Replaced by a later accepted decision in this specification.                              |
| Withdrawn   | Not a valid remaining design question and must not drive implementation.                  |
| Deferred    | Recorded outside the first-release implementation scope.                                  |

## First-release scientific surface

The first release forms one coherent heritability and genetic-correlation layer across individual-level and
summary-statistics estimators.

| Basis              | Unary estimators                                                     | Pairwise estimators                                    | Implementation state at design acceptance                                                                         |
| ------------------ | -------------------------------------------------------------------- | ------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------- |
| Individual-level   | Existing GCTA GREML and GREML-LDMS; existing LDAK REML, HE, and PCGC | GCTA dense bivariate REML and GCTA bivariate REML-LDMS | Unary routes exist. The GCTA bivariate atomic modules are installed and tested, but production routing is absent. |
| Summary statistics | LDAK SumHer and standalone CBIIT Python 3 LDSC H2                    | LDAK SumCors and standalone CBIIT Python 3 LDSC RG     | The new SumHer, SumCors, LDSC munging, H2, and RG routes are not implemented.                                     |

Method selection uses explicit estimator tokens such as `ldak_sumher`, `ldak_sumcors`, `ldsc_h2`, `ldsc_rg`,
`gcta_bivariate_reml`, and `gcta_bivariate_reml_ldms`. These estimators are not interchangeable modes of a
generic `heritability` or `correlation` switch.

Both pipeline-generated and externally supplied summary statistics are first-class. They converge on one
canonical summary-statistics contract while retaining distinct provenance.

## User-supplied architecture

User-facing structure is divided into six items with one owner per entity. The field names and examples below
translate the accepted HTML architecture; future changes to input files, IDs, option organization, output
names, or publication paths must update this specification as one coherent contract.

| Item                              | Owns                                                                                                                                                     | Links to                                                                                                    | Does not own                                                  |
| --------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| `cohort_manifest.csv`             | One genotype representation, genome build, and declared ancestry provenance.                                                                             | A PGEN/PSAM/PVAR, BED/BIM/FAM, or VCF genotype bundle.                                                      | Traits, pair relationships, or estimators.                    |
| `analysis_manifest.csv`           | One focal trait analysis, phenotype and covariate inputs, trait metadata, and pipeline-generated association or unary individual-level method selection. | One `cohort_id` and its phenotype/covariate files.                                                          | External summary results, pair identity, or estimator tuning. |
| `summary_statistics_manifest.csv` | One externally supplied summary result, intrinsic provenance, and unary summary-method selection.                                                        | A raw source table or an already-canonical table.                                                           | Estimator-specific reference selection.                       |
| `relationship_manifest.csv`       | One exact oriented binding of two distinct declared trait endpoints, pair-method selection, and GCTA pair matrix/covariate context.                      | Explicit analysis and/or summary-statistics endpoint IDs.                                                   | Estimator tuning or implicit all-by-all expansion.            |
| `reference_catalog.json`          | Named family-specific LDSC and LDAK resource bundles and their declared metadata.                                                                        | HapMap3 allele lists, LD scores, regression weights, or supplied LDAK tagging files and model declarations. | Method selection or automatic ancestry inference.             |
| `method_options.json`             | Namespaced configuration of selected analysis, unary-request, and pair-request methods, including named additional requests.                             | Existing entity/request IDs and selected methods.                                                           | Selecting an otherwise unselected method.                     |

### Analysis declarations

Each `analysis_id` remains focal and single-trait. An analysis owns one declared `trait_id`, `trait_type`,
phenotype source and column, optional shared unary covariates, and selected pipeline methods. A binary analysis
may record `population_prevalence` and `sample_prevalence` independently. A quantitative analysis supplies
neither.

An illustrative accepted shape is:

```csv title="analysis_manifest.csv"
analysis_id,cohort_id,trait_id,trait_type,phenotype,phenotype_column,control_value,case_value,quant_covariates,cat_covariates,association_methods,heritability_methods,population_prevalence,sample_prevalence
ukb_height,ukb,height,quantitative,traits.tsv,height,,,qcov.tsv,catcov.tsv,"plink2,regenie",gcta_greml,,
ukb_t2d,ukb,t2d,binary,cases.tsv,t2d,0,1,qcov.tsv,catcov.tsv,regenie,"gcta_greml,ldak_pcgc",0.08,0.21
```

### Summary-statistics declarations and canonicalization

Every scientific summary result has a stable `summary_statistics_id`. A pipeline-generated ID may be derived
deterministically from its `analysis_id` and association method. An external result declares its own ID and
records source study, release, method, build, population, and trait metadata separately.

External input supports two modes:

- `raw`: declare a known source format and run validation/harmonization before canonicalization;
- `canonical`: assert the current canonical contract and validate it without avoidable transformation.

Both modes emit the same canonical table and provenance sidecar. The source file is not copied into `outdir`
by default. The sidecar records the stable ID, trait/build/population metadata, source format, source method and
release, source and canonical checksums, transformation mode, harmonization versions, and access constraints.
It must not record credentials or machine-local absolute paths.

```csv title="summary_statistics_manifest.csv"
summary_statistics_id,trait_id,trait_type,source,source_mode,source_format,genome_build,ancestry,source_method,source_release,heritability_methods,population_prevalence,sample_prevalence
giant_height_2025,height_giant,quantitative,giant_height.tsv.gz,raw,ssf,GRCh37,EUR,published_gwas,2025,"ldak_sumher,ldsc_h2",,
consortium_t2d_2026,t2d_consortium,binary,t2d.canonical.tsv.gz,canonical,nfcore_gwas_canonical_v1,GRCh37,EUR,regenie,4.1,ldsc_h2,0.08,0.19
```

Pipeline-generated and external results must converge before estimator-specific munging or conversion. The
canonical result is independent of the LDSC or LDAK reference selected by a later request.

### Relationship declarations

One `relationship_id` names one exact populated endpoint binding. Each side may carry:

- an `analysis_id` for individual-level GCTA methods;
- a `summary_statistics_id` for SumCors or LDSC methods; or
- both domains when several estimator families analyze corresponding endpoint representations.

A GCTA-only row populates both analysis slots. A summary-only row populates both summary-statistics slots. A
combined row populates all four and must prove the same-side analysis-to-summary correspondence using recorded
producer provenance.

```csv title="relationship_manifest.csv"
relationship_id,left_analysis_id,right_analysis_id,left_summary_statistics_id,right_summary_statistics_id,relationship_methods,pair_quant_covariates,pair_cat_covariates
ukb_height_bmi,ukb_height,ukb_bmi,,,"gcta_bivariate_reml,gcta_bivariate_reml_ldms",pair.qcov.tsv,pair.catcov.tsv
published_height_t2d,,,giant_height_2025,consortium_t2d_2026,"ldak_sumcors,ldsc_rg",,
ukb_height_t2d_all,ukb_height,ukb_t2d,ukb_height_regenie,ukb_t2d_regenie,"gcta_bivariate_reml,ldak_sumcors,ldsc_rg",pair.qcov.tsv,pair.catcov.tsv
```

The relationship rules are:

1. Selected methods determine which typed endpoint slots are required.
2. Adding or changing any populated endpoint requires a new `relationship_id`. Adding a method that consumes
   endpoints already present does not.
3. Left/right order is preserved for native arguments, prevalence order, result labels, and provenance.
4. Duplicate detection treats the pair as unordered while preserving each composite side intact. `A-B` and
   `B-A` are duplicate-equivalent and rejected rather than merged automatically.
5. Self-pair validation compares declared relationship-facing `trait_id` values only. Equal trait IDs are
   invalid. Different IDs are allowed even if a human would regard them as the same biological phenotype or
   their summaries came from different programs. The pipeline does not infer biological equivalence and does
   not introduce `biological_trait_id`.
6. The exact same endpoint cannot appear on both sides, and there is no `allow_self_pair` escape hatch.
7. One relationship may select multiple distinct estimators. Different estimators on the same relationship are
   expected and are not duplicates.
8. The same method and unordered consumed endpoint IDs may be owned by only one relationship declaration.
   Repeated configurations of that method use distinct request IDs beneath the retained relationship.

### Request identity and method options

Every selected unary or pair method produces one deterministic primary request:

```text
unary: <method>--<summary_statistics_id>
pair:  <method>--<relationship_id>
```

The accepted examples are:

```text
ldsc_h2--giant_height_2025
ldsc_rg--published_height_t2d
ldak_sumcors--published_height_t2d
```

The options document may configure the primary request and may declare independently resolved, explicitly
named additions of the same selected method:

```text
<primary_request_id>--<request_name>
```

Adding a sensitivity request must not rename the primary request. An additional request does not silently
inherit request-owned references or other scientific settings from its primary sibling. A method-options entry
for a method not selected in the corresponding manifest is invalid.

The accepted options namespaces are `analyses`, `unary_requests`, and `pair_requests`:

```json title="method_options.json"
{
  "analyses": {
    "ukb_height": {
      "gcta": { "reml_no_constrain": true }
    }
  },
  "unary_requests": {
    "ldsc_h2--giant_height_2025": {
      "reference_bundle_id": "ldsc_eur_grch37_hm3"
    },
    "ldsc_h2--giant_height_2025--alternate-weights": {
      "primary_request_id": "ldsc_h2--giant_height_2025",
      "request_name": "alternate-weights",
      "reference_bundle_id": "ldsc_eur_grch37_alt"
    }
  },
  "pair_requests": {
    "ldsc_rg--published_height_t2d": {
      "reference_bundle_id": "ldsc_eur_grch37_hm3"
    },
    "ldak_sumcors--published_height_t2d": {
      "reference_bundle_id": "ldak_eur_grch37_ldak_thin"
    }
  }
}
```

`primary_request_id` records which manifest-selected primary request authorizes the named addition; it does not
inherit configuration. Every named addition resolves and validates a complete effective configuration
independently.

### Reference catalog and request ownership

One reference ID names one complete estimator-family bundle, not a cross-tool profile or one individual file.
An LDSC bundle preserves separate roles for the HapMap3 allele list, reference LD scores, and regression
weights even when two roles point to the same physical resource. An LDAK bundle identifies a supplied tagging
file and its declared model metadata.

```json title="reference_catalog.json"
{
  "ldsc": {
    "ldsc_eur_grch37_hm3": {
      "genome_build": "GRCh37",
      "ancestry": "EUR",
      "variant_id_system": "rsid",
      "hapmap3_snplist": "w_hm3.snplist",
      "reference_ld_scores": "eur_w_ld_chr/",
      "regression_weights": "eur_w_ld_chr/"
    }
  },
  "ldak": {
    "ldak_eur_grch37_ldak_thin": {
      "genome_build": "GRCh37",
      "ancestry": "EUR",
      "variant_id_system": "rsid",
      "model": "LDAK-Thin",
      "tagging_file": "ldak_thin.tagging"
    }
  }
}
```

Reference selection belongs to each unary or pair method request. It is never inferred from ancestry or build,
and a canonical summary result does not permanently own one reference choice. Multiple sensitivity requests
may therefore analyze the same canonical result or relationship with different explicitly selected bundles.

Q42 accepts the user-declared LDAK model label without attesting that the supplied tagging file truly embodies
that model. The wrapper still checks that required paths and bundle roles are structurally available. It may
enforce the declared method/model role allowed by the first-release menu, but it does not reconstruct the
resource, inspect its source genotypes, or prove its scientific provenance.

Q47 is **provisional**: beyond the structural availability needed to launch a request, the pipeline currently
trusts the selected reference. It does not certify population, ancestry, build, allele, LD, tagging, or variant-
universe compatibility. Declared compatibility metadata and observable native overlap/exclusion diagnostics
remain provenance, not a pipeline guarantee.

## GCTA bivariate composition

The installed GCTA bivariate atoms consume one shared phenotype file with two ordered phenotype columns and one
cohort-specific GRM or MGRM family. The pipeline therefore owns the following composition:

- both analysis endpoints must resolve to the same cohort for GCTA;
- each unary phenotype remains independently normalized;
- a relationship-specific artifact full-joins both normalized phenotype tables on `(FID, IID)`;
- one deterministic row is retained per sample, with a missing phenotype represented as `NA`;
- the relationship declares one optional shared quantitative-covariate input and one optional shared
  categorical-covariate input;
- the relationship owns its dense/LDMS matrix kind and construction settings independently of unary method
  selection;
- a compatible matrix may be reused only under the exact scientific-derivation rule below;
- dense routing supplies one GRM bundle; LDMS routing supplies one MGRM manifest and its referenced GRM bundles.

The pair artifact does not force an inner join or require identical endpoint sample sets. The native GCTA
estimator decides which individuals contribute under its missingness and residual-covariance behavior.

## Trait types, prevalence, and scales

Quantitative-quantitative, binary-binary, and mixed binary-quantitative relationships are all supported.
Prevalence is declared per endpoint and consumed only by a method whose native contract supports it. The
pipeline never invents prevalence for a quantitative endpoint or substitutes sample prevalence for population
prevalence.

| Method                       | Native prevalence behavior                                                                                                                                                                                                                                                                                   | Required publication behavior                                                                                                                                                                                                                                                                                                                                                                                                                           |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| GCTA bivariate REML and LDMS | Use only `--reml-bivar-prevalence`: one population-prevalence value for a mixed pair, or two ordered values for a binary-binary pair. Ordinary `--prevalence` is invalid with `--reml-bivar`. Sample prevalence remains provenance.                                                                          | Retain the complete observed/native result. For a mixed pair, add a liability-scale marginal H2 companion for the binary endpoint when its population prevalence is supplied. For a binary-binary pair, invoke native bivariate conversion only when both ordered prevalences are available; one value is never duplicated. Genetic covariance and genetic correlation remain native outputs and are not relabeled as separately liability-transformed. |
| LDSC H2/RG                   | Supply ordered sample and population prevalence for binary endpoints and `nan` for quantitative endpoints.                                                                                                                                                                                                   | Preserve observed and supported liability-scale quantities with explicit scale labels. Genetic correlation remains scale-invariant.                                                                                                                                                                                                                                                                                                                     |
| LDAK SumHer                  | Use prevalence/ascertainment only through the verified native SumHer contract.                                                                                                                                                                                                                               | Always retain native observed-scale H2. Add liability-scale H2 only when population prevalence and scientifically defensible GWAS ascertainment are available.                                                                                                                                                                                                                                                                                          |
| LDAK SumCors                 | For a binary-binary pair, LDAK 6.3 may receive both ordered population prevalence and ascertainment pairs only when all four values are scientifically available. A mixed pair receives none of these paired liability arguments because the native interface cannot represent one-sided conversion cleanly. | Always publish native-scale marginal H2, coheritability/genetic covariance, and scale-invariant genetic correlation. Add supported liability-scale binary-binary companion quantities only for the complete four-value case. Do not fabricate one-sided mixed-trait liability conversion.                                                                                                                                                               |

For GCTA mixed pairs, current console and `.hsq` liability labels can be asymmetric between binary-quantitative
and quantitative-binary ordering. The adapter must test both orientations and bind each liability companion to
endpoint identity. For a binary-binary pair with only one known population prevalence, the observed bivariate
analysis still runs but native bivariate liability conversion is omitted; a unary route may separately convert
the endpoint with known prevalence. These are wrapper parsing/publication constraints and do not authorize a
GCTA source patch.

GCTA's native residual-covariance behavior is retained. It estimates residual covariance when its native sample-
overlap rule permits and drops that component when overlap is below its native threshold. The pipeline records
observed overlap and whether the component was retained or dropped. A deliberate `--reml-bivar-nocove` argument
is allowed as a scientific override; it is never activated automatically after a failure. No pipeline-specific
overlap threshold is added.

## LDAK SumHer and SumCors policy

### Estimands and construction boundary

The first release supports total common-SNP SumHer H2 and total SumCors genetic correlation. Partitioned or
category enrichment, custom annotations, alpha estimation, and the older confounding-analysis aim are separate
future scientific routes.

The pipeline consumes official precomputed or deliberately preconstructed tagging resources. It does not run
`--calc-tagging`, construct a resource from a reference genotype panel, or own the construction-time population,
sample, imputation, variant-QC, annotation, or weighting policy.

### Executable target

New SumHer and SumCors components target the official Linux LDAK 6.3 scientific interface. A durable exact-
version package is a readiness prerequisite. Until one exists, a pipeline-local container may use the official
binary pinned by checksum or the official image pinned by immutable digest. The implementation must not claim
6.3 paired behavior while executing an older 6.1 package. Existing LDAK components should ultimately converge
on one tested release rather than remain permanently split.

### First-release model menu

| Request role                                                         | Primary or recommended supplied model | Allowed deliberate sensitivities          | Excluded from this first release                                                                       |
| -------------------------------------------------------------------- | ------------------------------------- | ----------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| SumHer total H2 using official precomputed data                      | BLD-LDAK                              | Baseline-LD v2.2, LDAK-Thin, Uniform/GCTA | Alpha and BLD-LDAK-Lite+Alpha; unknown/custom model families.                                          |
| SumHer total H2 using an independently constructed matched resource  | Human Default                         | Baseline-LD v2.2, LDAK-Thin, Uniform/GCTA | Alpha and BLD-LDAK-Lite+Alpha; unknown/custom model families.                                          |
| SumCors total RG using official precomputed data                     | LDAK-Thin                             | Uniform/GCTA                              | BLD-LDAK and Baseline-LD as a deliberate pipeline scope limit; Alpha resources; unknown/custom models. |
| SumCors total RG using an independently constructed matched resource | Human Default                         | Uniform/GCTA                              | BLD-LDAK and Baseline-LD as a deliberate pipeline scope limit; Alpha resources; unknown/custom models. |

Excluding BLD-LDAK or Baseline-LD from first-release SumCors is a pipeline scope decision, not a claim that
upstream LDAK prohibits those resources.

### Predictor coverage

LDAK's native complete-predictor check remains enabled by default. Missing tagging predictors require a
deliberate native override.

- At least 80% coverage is classified as within LDAK's approximate “less than about 20% missing” guidance.
- Below 80% is permitted only with the deliberate override and receives a high-severity scientific warning.
- The exact coverage, numerator, denominator, exclusions, and override use are mandatory diagnostics.
- Empty, malformed, or natively unusable intersections are hard operational failures.

The 80% value is guidance, not a mathematical validity discontinuity. This policy supersedes the earlier Q32
hard floor.

### Allele orientation and large-effect loci

Unresolved strand-ambiguous A/T and C/G variants are excluded by default. Under the first-release Q50 thin-
wrapper contract, a deliberate native scientific override may suppress this default. The request records the
override and any orientation evidence supplied, but the wrapper does not independently certify that evidence.
Generic GWASLab harmonization alone must not be recorded as proof that orientation was established.

SumHer and SumCors apply LDAK's recommended `--cutoff 0.01` by default. The cutoff excludes a predictor whose
estimated marginal association explains approximately 1% or more of phenotypic variance; SumCors applies the
criterion when either endpoint crosses it. This is documented upstream guidance rather than a universal
validity boundary, so a deliberate native override may disable it or select another positive cutoff.

`--truncate` is a mutually exclusive, explicitly requested sensitivity policy. It must never be activated as a
silent fallback. The request provenance and diagnostics record the cutoff/truncation policy and affected
predictor counts.

## LDSC policy

Standalone pinned CBIIT Python 3 LDSC owns three atomic operations: summary-statistics munging, H2, and RG.
GWASLab remains the common upstream harmonization layer but does not replace standalone LDSC munging. GenomicSEM
and GWASLab's beta LDSC implementation are not execution owners in this release.

LDSC consumes supplied HapMap3 allele, reference-LD-score, and regression-weight roles. It neither downloads a
reference implicitly nor calculates LD scores in the first release.

Same-study and overlapping-sample pairs are allowed. LDSC estimates its cross-trait intercept by default;
SumCors likewise uses its native inflation and overlap nuisance estimation. Estimator-specific constraints are
accepted only when supplied deliberately as native scientific options. The pipeline never assumes zero overlap,
forces shared nuisance values across methods, or rejects a pair merely because its studies overlap.

## Scientific validation policy

The pipeline uses an evidence-tiered validity policy:

1. Enforce documented estimator requirements and product-scope boundaries.
2. Enforce established GWAS validity conventions, including defensible allele orientation.
3. Implement documented upstream recommendations as visible, explicitly overridable defaults.
4. Warn and preserve provenance for scientifically debatable but interpretable choices.
5. Do not invent hard thresholds without adequate upstream or conventional support.
6. Ignore cosmetic naming inconsistencies unless the actual relational key becomes ambiguous or resolves to the
   wrong object.

No universal sample-size cutoff is imposed. Weak requests receive warnings and retain their native uncertainty;
sample size alone does not establish invalidity across different architectures, predictor sets, and aims.

Under provisional Q47, scientific compatibility checking of a user-selected reference is the current exception
to this general policy: the pipeline trusts the reference declaration and performs only the structural checks
needed to launch it.

## Thin-wrapper argument contract

The first release is deliberately a thin wrapper. It passes through otherwise unrestricted, well-formed native
scientific arguments to the pinned GCTA, LDAK, or LDSC executable. The pipeline does not curate or endorse every
native option, and the native executable decides whether an unknown option is accepted.

This pass-through is bounded by a structural invocation firewall.

### Immutable wrapper-owned mechanics

The wrapper exclusively owns:

- the executable and principal operation, including LDAK `--sum-hers`/`--sum-cors`, LDSC `--h2`/`--rg`, and
  GCTA `--reml-bivar`;
- routed primary inputs: summary endpoints, tagging files, LDSC reference roles, phenotype/covariate inputs,
  and GRM/MGRM inputs;
- output prefix and destination;
- flags necessary to create and capture the declared output;
- workflow CPU/thread settings, staged paths, temporary paths, container/runtime environment, and version/log
  capture;
- mechanics required for mandatory diagnostic parsing; and
- shell execution structure.

A native argument cannot replace, negate, or conflict with those values.

### Overridable scientific defaults

Scientific defaults apply only when the user has not made an explicit accepted choice. Examples include
`--cutoff 0.01`, conservative ambiguous-variant handling, and LDAK's complete-summary check. An explicit
scientific choice suppresses the default instead of creating contradictory duplicate flags. Native mutual
exclusions, including `--cutoff` versus `--truncate`, remain enforceable.

Q50 refines Q33: conservative ambiguous-variant exclusion is the pipeline default, but a deliberate native
scientific override may suppress it. The effective choice and any supplied orientation evidence remain
mandatory provenance; the thin wrapper does not independently certify the scientific justification.

### Remaining native arguments

All other well-formed scientific options pass through without pipeline adjudication. A native rejection fails
that request. The wrapper does not reinterpret, correct, silently remove, or reuse the option as an automatic
fallback.

Pass-through means arguments, not arbitrary shell text. Reject command chaining, redirection, command
substitution, environment assignments, wrapper-owned paths or flags, and unstaged host paths. An option that
needs an additional file may use only a resource declared and staged through the accepted input architecture.
In the first release, unrestricted pass-through therefore applies only to well-formed options that do not need
an undeclared file. A file-taking option is available only when its file occupies an existing typed, declared,
and staged architecture role; there is no generic arbitrary auxiliary-file escape hatch.

## Diagnostics and result states

Native numerical estimates are never clipped into conventional ranges. Every request is classified using the
same four result states while retaining method-specific evidence.

| State                    | Contract                                                                                                                                                                                    |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `estimable`              | The command completed and converged; the primary estimand and required native uncertainty are finite; mandatory diagnostics are present.                                                    |
| `estimable_with_warning` | The estimate and uncertainty are finite, but the result is at a boundary, outside its theoretical range, weak, negative where sampling permits, or accompanied by a native quality warning. |
| `completed_nonestimable` | Native analysis completed, but the primary estimand or required uncertainty is absent/nonfinite, or the tool says it cannot be identified.                                                  |
| `failed`                 | Execution failed, the optimizer explicitly did not converge, an operational/scientific prerequisite is invalid, the output is corrupt/unparseable, or mandatory evidence is missing.        |

A negative LDSC H2 with finite SE is retained as `estimable_with_warning`. A SumCors RG with `SE=NA` is retained
as `completed_nonestimable`. Explicit GCTA nonconvergence is `failed` even if a partial `.hsq` file exists.

### Mandatory diagnostic core

| Estimator | Required evidence                                                                                                                                                                                                                                                                                                                                     |
| --------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| GCTA      | Analyzed sample count; likelihood and convergence; fitted genetic and residual variance/covariance components with SEs; native phenotypic quantities; marginal H2 with SE; bivariate genetic covariance and RG with SE; boundary/constraint state; every LDMS component.                                                                              |
| SumHer    | Total observed H2 and SE; liability H2/SE when applicable; tagging model and scientific settings; predictors used, coverage, exclusions; null/alternative `loglSS`, parameter count, fit/AIC evidence; large-effect policy; native warnings; confirmation of the accepted total-H2/no-confounding scope.                                              |
| SumCors   | Both marginal H2 values and SEs; coheritability/genetic covariance and SE; RG and SE; native inflation/intercept estimates; native overlap estimate; common predictors, coverage, exclusions; allele and large-effect treatment; tagging model; native warnings. The overlap estimate must not be labeled as a literal participant count or fraction. |
| LDSC H2   | Observed H2 and SE; liability H2/SE when applicable; intercept and SE; ratio when defined; mean chi-squared; lambda GC; regression-SNP count; warnings; selected reference and weight roles.                                                                                                                                                          |
| LDSC RG   | Both marginal H2 values and SEs; genetic covariance and SE; RG, SE, Z, and P; both univariate intercepts; cross-trait covariance intercept with SE or explicit constraint; mean `z1*z2`; regression-SNP count; warnings.                                                                                                                              |

## Failure containment and reuse

The complete declared design receives atomic preflight before expensive execution. Deterministic structural
invalidity rejects the launch. After execution begins, a runtime crash, explicit nonconvergence, or unparseable
result fails only its request; independent requests continue and completed work is retained. The overall run is
incomplete/nonzero if any requested analysis genuinely fails. A completed non-estimable result is a scientific
outcome and does not make the run fail.

Preflight hard failures include unknown endpoints, invalid self-pairs, duplicate bindings, unsupported first-
release method/model roles, impossible GCTA cohort/matrix composition, unavailable required bundle members,
malformed input, unconstructable commands, and empty or natively unusable intersections. Scientific warnings
and explicit overrides follow the evidence-tiered policy above.

Cost-aware retry and resource-escalation policy is deferred to issue #5. The first-release design must not add a
silent scientific fallback. A scientifically different rescue analysis is a separately declared request.

An expensive scientific intermediate may be reused only when its entire scientifically consequential
derivation is identical:

- a dense GRM requires the same genotype source identity, samples, variants, QC, relatedness filtering, and GRM
  model;
- an MGRM additionally requires the same partition/model definitions;
- an LDSC-munged result requires the same canonical summary result, allele universe and policy, sample-size
  semantics, filters, and relevant preparation context; and
- a supplied LDAK tagging file can be reused only as the same resolved artifact/model declaration, with request-
  level suitability left to the accepted Q42/Q47 policy.

Matching a broad ancestry and genome build alone is not reuse identity.

## Publication contract

Publication remains estimand-first. Existing individual-level unary routes retain their current first-release
paths so this extension does not silently migrate an already public contract:

```text
heritability/individual/
├── gcta_greml/<analysis_id>/
├── gcta_greml_ldms/<analysis_id>/
├── ldak_reml/<analysis_id>/
├── ldak_he/<analysis_id>/
└── ldak_pcgc/<analysis_id>/
```

The request store and normalized estimand-view hierarchy below apply to the new summary-statistics and pairwise
request routes. A multi-estimand native artifact is stored once in its request directory; lightweight normalized
estimand views point back to it rather than duplicating the native payload. Moving existing individual-level
unary outputs into a request-ID hierarchy would be a separate, explicitly versioned migration that defines
individual-level unary request IDs and the compatibility treatment for every old path.

```text
summary_statistics/
└── giant_height_2025/
    ├── giant_height_2025.canonical.tsv.gz
    └── giant_height_2025.provenance.json

requests/
├── gcta_bivariate_reml/
│   └── gcta_bivariate_reml--ukb_height_bmi/
│       ├── native.hsq
│       └── provenance.json
└── ldak_sumcors/
    └── ldak_sumcors--published_height_t2d/
        ├── native.sumcors
        └── provenance.json

heritability/
├── ldsc_h2/
│   └── ldsc_h2--giant_height_2025/
├── ldak_sumher/
│   └── ldak_sumher--giant_height_2025/
├── ldak_sumcors/
│   └── ldak_sumcors--published_height_t2d/
└── gcta_bivariate_reml/
    └── gcta_bivariate_reml--ukb_height_bmi/

genetic_correlation/
├── ldsc_rg/
│   └── ldsc_rg--published_height_t2d/
├── ldak_sumcors/
│   └── ldak_sumcors--published_height_t2d/
└── gcta_bivariate_reml/
    └── gcta_bivariate_reml--ukb_height_bmi/

genetic_covariance/
├── ldak_sumcors/
│   └── ldak_sumcors--published_height_t2d/
└── gcta_bivariate_reml/
    └── gcta_bivariate_reml--ukb_height_bmi/
```

Every request provenance record includes request and endpoint identity, relationship and orientation where
applicable, resolved native options, program/component/container identity, selected reference bundle and roles,
structural reference checks, native and normalized estimands, scales, warnings, and result classification.
Under provisional Q47 it must not claim that the pipeline scientifically certified the selected reference.

The pipeline presents all requested estimator results. It does not rank methods, choose a winner, average or
meta-analyze their estimates, define a consensus, suppress one result because another differs, or warn solely
because estimators disagree.

## Component and pipeline boundaries

No new reusable family subworkflow is part of the first release. Add one later only if real callers reveal a
stable composition free of pipeline policy and cross-request reuse identity.

| Capability                | Portable atomic component boundary                                                                                         | Pipeline-local ownership                                                                                                                                                        |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| GCTA bivariate REML       | Existing `gcta/bivariatereml` and `gcta/bivariateremlldms` atoms each own one native operation.                            | Relationship routing, pair phenotype/covariate composition, dense/LDMS matrix derivation and reuse, prevalence option construction, diagnostics normalization, and publication. |
| LDAK SumHer               | New `ldak/sumher` atom owns one native SumHer operation.                                                                   | Canonical summary selection, request/reference resolution, scientific defaults, classifications, and estimand publication.                                                      |
| LDAK SumCors              | New `ldak/sumcors` atom owns one native SumCors operation.                                                                 | Explicit pair binding, request/reference resolution, nuisance/default policy, classifications, and publication.                                                                 |
| LDSC                      | Separate atomic munging, H2, and RG operations owned by standalone CBIIT Python 3 LDSC.                                    | Canonical-to-munging adaptation, request/reference resolution, cross-request munging reuse, pair routing, classifications, and publication.                                     |
| External canonicalization | No upstream-component claim in the first release. Reuse portable GWASLab operations only where their native contract fits. | Source-format policy, stable IDs, internal/external convergence, and provenance sidecars.                                                                                       |

Atomic modules receive resolved metadata-bearing files and mandatory native scalars. Optional non-file native
behavior uses their standard extension seam. They do not know manifests, pipeline request/publication policy,
cross-estimator correspondence, global reuse keys, or ancestry inference.

Each new upstream-bound atom must ultimately resolve its executable/package owner, reproducible container,
native take/emit contract, metadata, outputs, versions, focused fixture, real test, and stub test under the
repository's component standards. A pipeline-local implementation does not by itself establish upstream
submission readiness.

## First-release validation

This is wrapper-level validation equivalent to the pipeline's existing workflows:

- real and stub tests for each new atomic wrapper;
- route-level tests showing correct command construction, selected inputs, execution, expected outputs,
  versions, and failure propagation;
- representative coverage of accepted optional inputs and wrapper-owned argument conflicts;
- deterministic parser/classifier cases for `estimable`, `estimable_with_warning`,
  `completed_nonestimable`, and `failed`, including mandatory-evidence absence and native nonconvergence;
- complete and incomplete binary-binary prevalence cases for GCTA and SumCors, plus both mixed GCTA endpoint
  orientations;
- structural-firewall rejection of reserved input/output/thread flags, command chaining, redirection, command
  substitution, environment assignment, and unstaged-path injection; and
- standard lint, formatting, and pipeline test gates for the changed surface.

The first release does not require a separate direct-native numerical-parity suite, cross-estimator numerical
agreement, a comprehensive scientific edge-case matrix, or representative UK Biobank-scale benchmarks. The
estimators are wrapped rather than independently reimplemented.

## Explicit non-goals

The first release does not include:

- partitioned heritability, predefined-category enrichment, custom annotation analysis, alpha estimation, or
  SumHer's older confounding-analysis aim;
- LDAK tagging construction or LDSC LD-score construction;
- implicit all-by-all relationship expansion;
- automatic reference downloads or ancestry-based reference selection;
- scientific certification of user-selected reference compatibility under provisional Q47;
- GenomicSEM, LD Hub, GWASLab's beta LDSC execution path, or legacy Python 2 LDSC;
- BLD-LDAK or Baseline-LD SumCors routes, pending a separately designed multi-category RG surface;
- automatic scientific fallback after failure;
- ranking, consensus, or synthesis across estimators;
- new reusable family subworkflows;
- comprehensive first-release scientific benchmarking beyond normal wrapper tests; or
- construction of cost-aware publication retention, retry, or resource-escalation policy.

## Implementation dependency graph

Implementation proceeds in dependency-complete lanes rather than making GCTA wait for unrelated LDAK or LDSC
packaging:

```text
1. Shared declaration and request foundation
   ├── 2A. Dense GCTA bivariate vertical slice
   ├── 2B. External canonical-summary seam
   │   ├── LDAK 6.3 SumHer/SumCors atoms and routes
   │   └── pinned CBIIT LDSC munging/H2/RG atoms and routes
   └── 2C. Internal-summary unary routing after its HTML-owned selector gate

3. Cross-cutting diagnostics and publication contracts
4. Integrated wrapper and pipeline gates
5. GCTA LDMS extension after the dense relationship route is stable
```

The shared foundation implements typed ID validation, duplicate/self-pair rules, deterministic primary and
named additional requests, and the structural invocation firewall for whichever declared surfaces have exact
contracts. Dense GCTA is the preferred first vertical slice because its atomic modules already exist and it can
exercise relationship identity, pair phenotype composition, matrix attribution, endpoint-aware prevalence,
diagnostics, and publication without a new program runtime.

The external-summary lane versions the canonical seam before wiring its estimator adapters. The LDAK lane then
resolves the exact 6.3 delivery route and implements/tests atomic SumHer and SumCors operations; the LDSC lane
pins CBIIT Python 3 and implements/tests separate munging, H2, and RG operations. Identical munged results may be
reused only under the accepted derivation rule.

Cross-cutting work makes the four result states and method-specific evidence durable, stores native artifacts
once, and publishes normalized views with complete request provenance. Integrated gates then cover route, stub,
failure, request-local containment, incomplete/nonzero overall behavior, formatting, lint, and affected pipeline
tests. Public usage/output documentation changes only when a route becomes implemented and user-visible.

No step authorizes patching GCTA, LDAK, LDSC, or GWASLab source.

## Remaining architecture and implementation-contract gates

The reviewed HTML explicitly left one user-input placement unresolved: where unary `ldak_sumher` and `ldsc_h2`
selection belongs for a summary result generated by a pipeline association route. The possibilities recorded in
the HTML were the producing analysis row, a synthesized internal-summary declaration, or a unified summary
manifest capable of referencing internal producers.

This specification does not choose among them because the user made the reviewed architecture—not further
verbal grilling—the authority for all input-file and selector organization. Resolve this by revising the
architecture coherently before wiring declaration/schema routing for pipeline-generated SumHer or LDSC H2.

This gate does **not** block:

- atomic SumHer, SumCors, LDSC munging/H2/RG wrapper implementation;
- external-summary unary routing that already has a selected `summary_statistics_id`;
- relationship/request identity foundations; or
- atomic GCTA component use and pair-phenotype adapter work.

Production GCTA relationship routing remains blocked until relationship-owned matrix settings have a defined
encoding, or until the first dense route explicitly adopts a complete deterministic primary default with no
undeclared inheritance from either unary endpoint.

The reviewed HTML also marked several exact contracts as unfinished even though their ownership and scientific
behavior are accepted. They are implementation contract-completion gates, not invitations to reopen the
scientific grilling:

- the final canonical summary minimum columns, optionality, allele-orientation fields, effective-sample-size
  semantics, contract version, and checksum semantics;
- the exact normalized estimand table columns, scale vocabulary, unavailable-value representation, and stable
  link from each lightweight estimand view to the request-owned native artifact;
- the exact relationship fields that encode dense/LDMS matrix requests, reuse identity, and pair covariate
  resources;
- the final reference-catalog URI/checksum representation and whether one physical resource may satisfy two
  distinct LDSC semantic roles; and
- the exact serialized primary/additional-request syntax, while preserving the already accepted identities,
  independent resolution, and single method-selection authority.

The relevant implementation owner must make each contract exact in this specification and the associated
schema/component metadata before exposing that route. These items do not block atomic wrappers whose native
file/scalar contracts are already independently definable, but they do block claiming that the corresponding
public pipeline input or normalized-output contract is complete.

## Deferred work

- [Issue #3: Optimize whole-pipeline compute and storage costs for metered platforms](https://github.com/lyh970817/gwas/issues/3)
  covers later profiling and retention/publication optimization for environments such as UK Biobank RAP and
  trusted research environments.
- [Issue #5: Design a cost-aware retry policy for metered execution environments](https://github.com/lyh970817/gwas/issues/5)
  owns retry classification, resource escalation, attempt caps, billing guardrails, and observability.
- [Issue #6: Evaluate curated controls for native scientific arguments after first release](https://github.com/lyh970817/gwas/issues/6)
  owns possible post-release curation of the unrestricted native scientific option surface.

## Decision ledger

| Question | Status                                               | Accepted decision or disposition                                                                                                                                                      |
| -------- | ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Q1       | Accepted                                             | Implement the complete initial surface: retain current unary methods and add GCTA bivariate, SumHer/SumCors, and standalone LDSC H2/RG.                                               |
| Q2       | Accepted                                             | Treat pipeline-generated and external summary statistics as first-class inputs that converge canonically.                                                                             |
| Q3       | Accepted                                             | Use estimator-specific method tokens and explicit pair declarations; never form implicit all-by-all pairs.                                                                            |
| Q4       | Accepted                                             | Preserve one entity per manifest plus a separate reference catalog.                                                                                                                   |
| Q5       | Accepted                                             | Use pinned standalone CBIIT Python 3 LDSC, not GenomicSEM or GWASLab's beta path.                                                                                                     |
| Q6       | Accepted                                             | Allow raw and already-canonical external summary input modes.                                                                                                                         |
| Q7       | Accepted                                             | Keep unary phenotype normalization and build a pair-specific GCTA phenotype artifact.                                                                                                 |
| Q8       | Accepted                                             | Select references explicitly by stable family-specific ID; never infer them from ancestry.                                                                                            |
| Q9       | Accepted                                             | Distinguish population from sample prevalence and preserve valid observed-scale results without liability metadata.                                                                   |
| Q10      | Accepted, refined by Q21 and final architecture      | Keep publication estimand-first; retain existing individual-level unary paths, while new summary/pair routes use the normative request store and normalized views.                    |
| Q11      | Accepted                                             | Give every canonical result a stable `summary_statistics_id` independent of source provenance.                                                                                        |
| Q12      | Accepted                                             | Preserve declared left/right orientation but detect reversed duplicates as unordered pairs.                                                                                           |
| Q13      | Accepted                                             | Make GCTA matrix kind/settings relationship-owned and reuse only an exactly compatible derivation.                                                                                    |
| Q14      | Accepted                                             | Full-join normalized pair phenotypes and write a missing side as `NA`.                                                                                                                |
| Q15      | Accepted                                             | Make one shared quantitative and one shared categorical covariate input relationship-owned.                                                                                           |
| Q16      | Accepted, represented by HTML                        | Use one namespaced options document; manifests select methods and options configure them. Final namespaces are `analyses`, `unary_requests`, and `pair_requests`.                     |
| Q17      | Accepted                                             | One reference ID names a complete estimator-family bundle with distinct semantic roles.                                                                                               |
| Q18      | Accepted                                             | One relationship may carry analysis endpoints, summary endpoints, or both, as required by selected methods.                                                                           |
| Q19      | Accepted after revision                              | References are method-request-owned rather than permanently result-owned.                                                                                                             |
| Q20      | Accepted                                             | Publish an external canonical table and deterministic safe provenance sidecar; do not copy the raw source by default.                                                                 |
| Q21      | Accepted and refined                                 | Use first-class method-first unary request IDs, deterministic primaries, and named sensitivity additions.                                                                             |
| Q22      | Accepted and corrected by Q51                        | Support all quantitative/binary pair combinations with method-specific prevalence handling and explicit scale labels.                                                                 |
| Q23      | Accepted                                             | `relationship_id` identifies the exact populated endpoint binding independently of method.                                                                                            |
| Q24      | Accepted after user correction                       | Use declared `trait_id` only; reject equal IDs; permit different IDs; do not create or infer `biological_trait_id`.                                                                   |
| Q25      | Accepted after clarification                         | Permit several distinct methods for one pair; reject reversed/repeated bindings rather than merging; use `pair_request_id` for repeated same-method configurations.                   |
| Q26      | Accepted                                             | Each selected pair method creates a deterministic primary request; named additions resolve independently.                                                                             |
| Q27      | Withdrawn                                            | All input/output files, fields, identities, option organization, paths, and names are owned by the reviewed architecture rather than further verbal grilling.                         |
| Q28      | Accepted                                             | Allow overlapping/same-study pairs and use native LDSC/SumCors nuisance estimation by default.                                                                                        |
| Q29      | Accepted                                             | Limit SumHer to total common-SNP H2.                                                                                                                                                  |
| Q30      | Accepted                                             | Consume supplied/precomputed tagging only; do not construct it.                                                                                                                       |
| Q31      | Accepted                                             | Retain observed-scale binary SumHer H2; add liability H2 only with defensible prevalence/ascertainment.                                                                               |
| Q32      | Superseded through Q45; final policy in Q42/Q46/Q47  | The original compatibility adjudication and hard 80% floor no longer apply; Q46 keeps native completeness by default and makes 80% guidance, while Q42/Q47 define trust.              |
| Q33      | Accepted, refined by Q50                             | Exclude unresolved A/T and C/G variants by default; a deliberate native override may suppress the default, with the choice and supplied evidence recorded.                            |
| Q34      | Accepted and refined by Q45                          | Default to `--cutoff 0.01`, allow explicit override, and keep truncation mutually exclusive and explicit.                                                                             |
| Q35      | Accepted and expanded by Q43                         | Preserve native numbers without clipping and classify estimable, warning, non-estimable, and failed states.                                                                           |
| Q36      | Accepted                                             | Warn on weak sample size; impose no universal hard cutoff.                                                                                                                            |
| Q37      | Accepted                                             | Reuse only when the complete scientifically consequential derivation is identical.                                                                                                    |
| Q38      | Accepted                                             | Target the official Linux LDAK 6.3 contract with a reproducible exact-version delivery route.                                                                                         |
| Q39      | Accepted after documentation review                  | Use the evidence-tiered LDAK model menu and label pipeline scope exclusions accurately.                                                                                               |
| Q40      | Accepted                                             | Add atomic modules only; keep initial composition pipeline-local.                                                                                                                     |
| Q41      | Accepted and refined by Q45/Q46                      | Preflight deterministic structural invalidity; contain runtime failure per request; retain independent work; finish incomplete/nonzero for true failures.                             |
| Q42      | Accepted, option 4                                   | Trust the user-declared LDAK model rather than attest the tagging resource's true model provenance.                                                                                   |
| Q43      | Accepted                                             | Require the method-specific diagnostic core and common four-state classification semantics.                                                                                           |
| Q44      | Deferred                                             | Cost-aware retry/resource escalation belongs to issue #5. No silent scientific fallback enters the first release.                                                                     |
| Q45      | Accepted                                             | Use the evidence-tiered scientific-validity policy; do not treat cosmetic naming inconsistencies as scientific invalidity.                                                            |
| Q46      | Accepted                                             | Preserve LDAK completeness by default; explicit missing-summary override; 80% is guidance, and below it warns rather than hard-fails.                                                 |
| Q47      | Provisional, option 4                                | Trust the selected reference and check only structural availability needed to launch.                                                                                                 |
| Q48      | Accepted for first release; future curation deferred | Provide unrestricted well-formed native scientific argument pass-through for thin wrappers; issue #6 owns later curation.                                                             |
| Q49      | Accepted                                             | Require the same standards-level automated wrapper tests as existing workflows, not new scientific validation gates.                                                                  |
| Q50      | Accepted                                             | Enforce the structural invocation firewall; accepted scientific defaults and their question-specific override/provenance semantics, including Q33 as refined by Q50, remain in force. |
| Q51      | Accepted                                             | Use endpoint-aware native GCTA bivariate prevalence conversion and retain observed/native results.                                                                                    |
| Q52      | Withdrawn                                            | Present every requested estimator result independently; do not rank, synthesize, or choose a best method.                                                                             |
| Q53      | Accepted                                             | Preserve native GCTA residual-covariance behavior, report it, permit explicit `--reml-bivar-nocove`, and add no pipeline overlap threshold.                                           |

## Supporting sources

- [Selected standalone LDSC research](../../docs/ldsc-research.md)
- [LDAK recommendations](https://dougspeed.com/recommendations/)
- [LDAK precomputed tagging files](https://dougspeed.com/pre-computed-tagging-files/)
- [LDAK SNP heritability](https://dougspeed.com/snp-heritability/)
- [LDAK genetic correlations](https://dougspeed.com/genetic-correlations/)
- [GCTA bivariate REML source: residual covariance](https://github.com/JianYang-Lab/GCTA/blob/2ff095cad2ea5ca213c1b008401382aa7b05715e/main/bivar_reml.cpp#L125-L145)
- [GCTA bivariate prevalence parser](https://github.com/JianYang-Lab/GCTA/blob/2ff095cad2ea5ca213c1b008401382aa7b05715e/main/option.cpp#L811-L829)
- [LDAK 6.3 source and release repository](https://github.com/dougspeed/LDAK/tree/b755ab71b6dcf8f36f40bb64c799ec858d2ca492)
