# Troubleshooting documentation research

## Recommendation

Add one concise `## Troubleshooting` section at the end of `docs/usage.md`. Organise it by the phase visible to the user, not by implementation component or scientific method. The current validator already produces unusually precise diagnostics, so the guide should teach users how to act on those diagnostics and should not duplicate every schema constraint.

Proposed section order:

1. `### Start with the reported phase`
2. `### Manifest validation failed`
3. `### Method-options validation failed`
4. `### A process failed`
5. `### Expected results are missing`
6. `###` followed by `` `-resume` did not reuse work ``
7. `### Get help`

This is deliberately smaller than Sarek's very large `# Troubleshooting & FAQ`. Sarek demonstrates that pipeline-specific questions belong in the usage guide, but much of its section is an operations manual and scientific-method catalogue rather than troubleshooting. MAG's closer and better pattern is to document a recognisable message, explain whether it is fatal, state the output consequence, and give the supported response adjacent to the relevant feature. RNA-seq likewise places focused failure/limitation notes beside the feature they qualify. For GWAS, the generic failure workflow belongs in one final section, while detailed method behaviour should remain in the existing linked-manifest, defaults, and output sections.

No web fallback is needed for the organisation or content: the three local references, the repository's documented standards, and the live validator establish the relevant style and contracts.

## Exact content outline

### Start with the reported phase

Use a short opening paragraph and a three-row table:

| What the user sees | Meaning | First evidence to inspect |
| --- | --- | --- |
| An error naming a manifest, CSV row, identity and field | Preflight rejected input before task submission | The complete grouped error report; fix every listed row, then relaunch |
| `Method-options document ... analysis_id ... option ...` | The JSON document is malformed or an option is unknown, invalid, inapplicable, or points at a missing resource | The named `analysis_id`, fully qualified option and reason |
| `Process ... terminated with an error` | A task was submitted and failed | `.nextflow.log` and the task's `.command.err`, `.command.out` and `.command.log` in the reported work directory |

The distinction is evidence-backed by the central preflight validator, which aggregates linked-manifest failures and aborts before channel construction/task submission, while method-options failures use their own stable prefix. Avoid promising that every possible failure is preflighted: phenotype contents and tool-level compatibility can still fail in a process.

### Manifest validation failed

Lead with the shape of the diagnostic rather than fabricated literal output:

> Read the reported CSV path, row number, `cohort_id` or `analysis_id`, field name, and reason from left to right. The validator reports all linked-manifest errors it can find in one launch, so correct every bullet before rerunning.

Then use a compact symptom/action table containing only implemented contracts:

| Diagnostic fragment | Supported action |
| --- | --- |
| `header row 1 does not match the mandatory ...-column input contract` | Start from the shipped example/header and restore missing columns; remove unexpected or repeated column names. Optional values may be blank, but their columns must remain present. Column order is not significant. |
| `no genotype group is populated`, `a second genotype group is populated`, or `genotype group ... is only partly populated` | Populate exactly one complete representation: `pgen`/`psam`/`pvar`, `bed`/`bim`/`fam`, or `vcf`. |
| `duplicate cohort_id` or `duplicate analysis_id` | Keep one row for each identity. Do not use repeated identical cohort rows as aliases; a conflicting duplicate also reports the fields that differ. |
| `undefined cohort_id` | Make the analysis row's `cohort_id` match one cohort-manifest identity exactly. |
| `unknown method`, `listed more than once`, or `row selects no method` | Use each documented selector token at most once and populate at least one of `association_methods` or `heritability_methods`. Link back to [Analysis manifest fields](#analysis-manifest-fields), rather than restating the vocabularies. |
| Binary `case_value`/`control_value` diagnostics | Supply both source codes for a binary trait and make them distinct. Remove both from a quantitative row. Do not claim that `trait_type` is inferred from phenotype values. |
| `population_prevalence` diagnostic | Use it only for a binary heritability row whose selected estimator consumes it; provide it for `ldak_pcgc`. Link back to [Analysis manifest fields](#analysis-manifest-fields). |

Do not add speculative entries for genome-build mismatches, phenotype column absence, sample-ID overlap, covariate encodings, or ancestry-driven reference selection. They may be reasonable future validations or task failures, but the current central validator does not emit the row-level contracts proposed in the earlier audit for them.

### Method-options validation failed

Explain the stable diagnostic fields: document path, `analysis_id`, fully qualified option, and reason. Then give four action bullets:

- Fix malformed JSON or make the root an object keyed by an `analysis_id` declared in the analysis manifest.
- Use only the `gcta` and `ldak` families and the options documented under [Advanced method options](#advanced-method-options).
- Remove an option when its consuming method is not selected; operational settings such as GCTA partition count and tool threads belong in run/profile configuration, not `--method_options`.
- Resolve each stageable resource path from the launch environment and check the policy pairing: `weights_policy: provided` requires `weights`, and `kvik_step1_subset: provided` requires `predictor_extract`; the resources are rejected when absent or when supplied under an incompatible policy.

Do not duplicate all option ranges in the troubleshooting section. The existing option tables are the single contract reference and the diagnostic already prints the exact rejected option and expected type/range.

### A process failed

Use a short operational sequence:

1. Copy the process name and work-directory hash from the terminal or `.nextflow.log`.
2. Inspect `.command.err`, `.command.out` and `.command.log` in that task directory; `.command.sh` records the executed command.
3. Correct the input, configuration, container, filesystem, or resource problem identified there.
4. Relaunch the same command with `-resume`; do not delete `work/` or `.nextflow/` first.

Then state the repository-backed resource behaviour: selected retryable failures are automatically retried with larger requests, but `--max_cpus`, `--max_memory`, and `--max_time` cap those requests. Link to the existing [Resource requests](#resource-requests) section and the official [nf-core troubleshooting guide](https://nf-co.re/docs/running/troubleshooting). Do not prescribe arbitrary memory numbers or process overrides because no dataset-size evidence supports them.

### Expected results are missing

Distinguish absence by contract from a failed task:

- Confirm that the analysis row selected the method whose result you expected.
- Check the exact route-specific paths in the [output documentation](output.md).
- Prepared genotypes, normalised phenotypes/covariates, relatedness matrices, and REGENIE predictions are unpublished by default; enable the corresponding save control before expecting those directories.
- GWASLab reference parameters are optional. Standardised association output is still produced without them, but reference-dependent allele checks/flips, rsID assignment, and strand inference are not. `genome_build`, not `ancestry`, selects the build-specific resource set.
- Do not imply that published intermediates can be imported as cross-run caches. The supported reuse mechanism is retained Nextflow work plus `-resume`.

Avoid an entry about absent QQ plots or heritability panels: those are deferred product features, not failed outputs in the current contract.

### `-resume` did not reuse work

State the narrow current contract:

> Nextflow reuses a task only when its inputs, pipeline code, and relevant configuration still match a retained cache entry. Keep the original `work/` directory and `.nextflow/` cache, rerun from the same launch context where practical, and use `nextflow log` to find a run name for `-resume <run-name>`. A changed input file, manifest, method option, pipeline revision, process configuration, or missing work directory can require recomputation.

This refines the existing `-resume` section without making cache-key guarantees beyond what the current guide and references support. It should link to [`-resume`](#-resume), not repeat the whole core-argument section.

### Get help

Before opening a support request, ask the user to retain/provide:

- pipeline version and exact launch command with secrets removed;
- `.nextflow.log`;
- failing process name and relevant `.command.*` files;
- the reported manifest row or a minimal redacted reproducer;
- executor/profile and container runtime;
- whether the relaunch used `-resume` and whether the original `work/` directory remains.

Link to the official [nf-core troubleshooting guide](https://nf-co.re/docs/running/troubleshooting), the pipeline's existing GitHub issue/support destination already used elsewhere in the repository, and the nf-core community support page if the integrator confirms its canonical current URL. Do not invent a project-specific Slack channel.

## Reference findings

- Sarek has a dedicated top-level troubleshooting/FAQ section in `docs/usage.md`. Its strongest reusable pattern is question-shaped, pipeline-specific headings with concrete commands or exact error evidence. Its length and mixture of testing, method selection, resource preparation, and troubleshooting should not be copied wholesale.
- MAG mostly keeps troubleshooting adjacent to domain features. Its `A note on bin refinement` section shows the preferred symptom -> interpretation -> expected output consequence -> adjustment sequence and explicitly distinguishes an ignored process error from pipeline failure.
- RNA-seq similarly puts errors, reporting, limitations, and compatibility warnings beside the affected input or feature. It does not add a generic FAQ merely for template parity.
- All three contain the standard `-resume`, resource-request, background-execution, and Nextflow-memory material. GWAS already has those sections, so troubleshooting should link to them rather than duplicate them.
- The local coding standard requires GitHub-native alerts, sentence-case headings, language-tagged fences, inline links, backticked flags/paths/column names, and second-person user instructions. The new section needs no code fence unless a real stable diagnostic example is quoted.

## Evidence map

- `subworkflows/local/utils_nfcore_gwas_pipeline/main.nf:579-607`: mandatory complete headers; missing, unexpected, and repeated headings; column order is ignored by the comparison.
- `subworkflows/local/utils_nfcore_gwas_pipeline/main.nf:662-760`: method selector, genotype-group, binary-code, and prevalence messages.
- `subworkflows/local/utils_nfcore_gwas_pipeline/main.nf:786-1035`: method-options parsing, family/option applicability, ranges, policies, and stageable-resource existence.
- `subworkflows/local/utils_nfcore_gwas_pipeline/main.nf:1062-1185`: aggregated row/identity/field diagnostics, duplicate and orphan identities, and abort before returning validated rows.
- `docs/usage.md:17-152`: authoritative manifest fields, method-option tables, diagnostics, normalisation, save controls, and output link.
- `docs/usage.md:202-255`: reproducibility, `-resume`, resources, background execution, and Nextflow memory.
- `docs/output.md:124-134`: optional GWASLab resources and build-specific selection.
- `docs/output.md:191-224`: optional published intermediates and pipeline information.
- `.references/sarek/docs/usage.md:525-1445`: dedicated question-oriented troubleshooting/FAQ.
- `.references/mag/docs/usage.md:448-460`: message interpretation and output consequence adjacent to the relevant feature.
- `.references/rnaseq/docs/usage.md:30-86,526-769`: feature-local error/reporting and compatibility guidance.
- `docs/coding-standards/documentation-and-assets.md:48-71,191-205`: `docs/usage.md` structure, alert/fence/link rules, heading case, flag/path formatting, and prose voice.

## Documentation verification

After integration:

1. Run Prettier on the edited file through the repository hook: `pre-commit run prettier --files docs/usage.md`.
2. Run `nf-core pipelines lint .` so template/documentation links and repository conventions are checked in the same gate as the rest of the polish work.
3. Check local Markdown targets and anchors explicitly: every relative file exists; `#analysis-manifest-fields`, `#advanced-method-options`, `#resource-requests`, and `#-resume` match actual headings.
4. Search the new section for diagnostic fragments and compare each against the current validator with `rg`; do not paraphrase a fragment inside backticks if the code does not emit it.
5. Run one existing invalid linked-manifest nf-test scenario and one invalid method-options scenario, then confirm that the guide's phase classification matches the observed report. Suitable focused surfaces are `tests/relational_input_plink2.nf.test` and either `tests/relational_gcta_greml.nf.test` or `tests/relational_ldak_kvik.nf.test`.
6. Inspect the rendered Markdown on GitHub or an equivalent preview for table width and anchor rendering. No pipeline execution is required solely for prose, beyond the focused diagnostic confirmation above.

## Acceptance boundary

Accept the section only if it remains a navigation and diagnosis aid. Reject additions that invent an error contract, restate every schema field, promise scientific interpretation, treat optional/deferred report content as a failure, or suggest destructive cache cleanup before `-resume`.
