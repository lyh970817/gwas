---
name: nf-core-gwas-module-conventions
description: Design or review nf-core contracts for GWAS and population-genetics components. Use for portfolios, summary-statistics interfaces, association outputs, genotype or reference bundles, tuple roles, selectors, identity, versions, or implementations involving GWAS/popgen tools and harmonisation.
---

Read `../references/nf-core-guidance-sources.md`.

Use this skill whenever planning, researching, specifying, creating, wiring, or reviewing an nf-core component
that handles PLINK/PLINK2, phasing, imputation, GRM construction, association or summary-statistics outputs,
reference data, or harmonisation. These are prescriptive repository-local standards that are intentionally
narrower than the generic nf-core module specifications. Treat them as the target shape for new work and for
maintenance already touching the same contract surface. If deliberately consulted current upstream standards
conflict with a bullet, surface the conflict and update this skill before applying the upstream rule; otherwise
apply these rules by default and document any intentional deviation.

## Genotype bundle contracts

- Explicit format-specific contracts retain their established order: PLINK1 is
  `tuple val(meta), path(bed), path(bim), path(fam)`; PLINK2 is
  `tuple val(meta), path(pgen), path(psam), path(pvar)`.
- Preserve an accepted dual-format PLINK semantic union when PLINK1 and PLINK2 occupy the same identity and
  CLI role. Name and order its members as primary genotype, variant metadata, sample metadata:
  `tuple val(meta), path(plink_genotype_file), path(plink_variant_file), path(plink_sample_file)`. Its concrete
  values are BED/BIM/FAM or PGEN/PVAR/PSAM; the latter ordering is intentional and differs from an explicit
  PLINK2-only contract.
- Let the staged primary-genotype extension select the native PLINK flag. Introduce separate metadata-bearing
  roles only when the formats differ structurally or semantically at the public interface.
- A GRM bundle (and analogous always-together multi-file bundles) is declared as a single collected
  `path(grm_files)` input — mirroring the GCTA house style (`gcta/reml`, `gcta/grmcutoff`, etc.) — not
  destructured into separate `path(grm_bin), path(grm_id), path(grm_details), path(grm_adjust)[, path(grm_root)]`
  members. When the tool is basename-driven, derive the prefix by globbing the collected list for the defining
  member, e.g. `def grm_prefix = grm_files.find { grm_file -> grm_file.name.endsWith('.grm.bin') }.name.replaceFirst(/\.grm\.bin$/, '')`
  (use an explicit closure parameter, not implicit `it`, to avoid a nextflow-lint deprecation warning). A
  genuinely separate file that travels alongside the bundle but is consumed by its own flag (e.g. a `--keep`
  list) stays its own `path(keep)` member. Do not destructure a bundle just to reference one member — and never
  add a basename-equality assertion across the members (see "Prefix / identity: one source of truth" below).

## Meta roles and tuple numbering

- Model mutually exclusive primary formats with different semantic or CLI roles (for example, a PLINK semantic
  union versus VCF, BCF, or BGEN) as separate metadata-bearing tuples. Use `meta` for the focal/preferred role,
  `meta2`, `meta3`, … for additional mutually exclusive primary roles. Callers pass `[]` placeholders for
  inactive roles. The active role determines the emitted `meta` and basename; preserve compatible encodings in
  one accepted semantic union rather than splitting them by file extension.
- Number the first element of each tuple positionally in `input:` declaration order: first tuple `val(meta)`, second `val(meta2)`, third `val(meta3)`, increasing without gaps. Never declare `meta2` before `meta`. If input order changes, update `main.nf`, `meta.yml`, and nf-test `input[...]` together.
- Keep analysis-bearing/role-defining support resources (phenotype, covariate, keep/remove lists that define membership, reference panels, scaffold files, site lists, chromosome/panel-specific genetic maps) in metadata-bearing tuples. Use plain `path(...)` only for non-identity-bearing sidecars where a metadata role would not clarify the contract.
- When a support-file tuple (`meta2`, `meta3`, …) carries the same genetic/sample identity as the primary `meta`, outputs MUST emit the primary `meta`. Emit `meta2`+ only when that tuple is a distinct emitted identity (an active alternative input format or a separate bundle identity that defines the output).

## Multi-chromosome shards

Model chromosome-sharded PLINK bundles as repeated PLINK tuples, not metadata suffixes:

- Keep a shared cohort/analysis-level `meta.id` across shards; do not add `meta.chr` just to reconstruct prefixes.
- Chromosome identity lives in the staged PLINK basename shared by the `.bed/.bim/.fam` (or `.pgen/.psam/.pvar`) files for that shard.
- When the CLI consumes a PLINK prefix, derive it from the staged basename without the extension. `meta.id` tracks the analysis unit; the staged basename tracks the chromosome-specific bundle.

## Prefix / identity: one source of truth

Output naming defaults to the active input role's declared identity source:

```nextflow
def prefix = ""
if (bed) {
    prefix = bed.baseName
} else if (vcf) {
    prefix = task.ext.prefix ?: "${meta2.id}"
    meta = meta2
} else if (bcf) {
    prefix = task.ext.prefix ?: "${meta3.id}"
    meta = meta3
}
```

- If the tool contract defines identity in metadata, use the active metadata map; if it is basename-driven, use the staged basename and keep output naming aligned to it.
- Do not pass file/bundle prefixes (including GRM prefixes) as standalone `val(...)` inputs. GRM and prefix identity have one source of truth: `meta.id` when metadata identity is the contract, or the staged bundle basename when the tool is basename-driven.
- When a tool requires staged input basenames to match the consumed prefix, make that basename part of the module contract and assume callers stage correctly named files. Do not repair mismatches with `name:`, `stageAs:`, or ad hoc symlinks, and do not add defensive Groovy that scans bundles, derives a basename, and throws custom exceptions when `meta.id` differs. Document the basename contract in `meta.yml`, exercise it in tests, and let the tool fail naturally on invalid caller input.
- This anti-`stageAs` rule is about a _caller basename/prefix contract_ and is distinct from a genuine _work-directory name collision_. When a module takes two same-typed input bundles that could stage under identical names (e.g. two PLINK trios in `plink/bmerge`), or an output would overwrite an input of the same name, staging each set into its own subfolder with `stageAs` (as `samtools/merge` does) or defaulting `ext.prefix` to a distinct value is the correct fix — and it must cover every companion file of the bundle (`.bed`/`.bim`/`.fam`), not just the primary (#12273, #12277).

## Scalar selectors vs. file identity

- Required scalar selectors always consumed by the tool (e.g. LDAK `--window-prune`/`--window-kb`) MUST be explicit `val(...)` inputs, not metadata fields or `task.ext` values. Keep metadata for file identity, not scalar analysis selectors. Litmus test: if the tool errors when the flag is omitted (verify by running it), the flag is mandatory and belongs in the interface as a `val(...)` — never smuggle it back in as a baked `task.ext.args ?: '--flag value'` default.
- Optional phenotype-column selectors within a phenotype file follow the existing PLINK/REGENIE/GCTA pattern: keep the phenotype file as an input and pass selectors such as `--pheno-name`, `--phenoColList`, or `--mpheno` through `task.ext.args`, with tests asserting the generated command when the selector matters.
- A scalar becomes a module input — standalone `val(...)`, or (when specific to a metadata-bearing analysis unit) a member of that tuple after `val(meta)` and the file/path members — **only when it is mandatory**, in one of two senses: (a) _required_, i.e. the tool errors when it is omitted (litmus above); or (b) a _mandatory, mutually-exclusive mode selector_, where one of N modes must always be emitted — typically distinct native subcommands/executables or output schemas (e.g. `is_binary` choosing GCTA fastGWA `--fastGWA-mlm` vs `--fastGWA-mlm-binary`, or LDAK-KVIK `--binary YES`; LDAK PCGC `prevalence`, which PCGC requires). Place such a scalar in the tuple that owns its analysis unit, or standalone only when genuinely process-global. A chromosome/shard selector that a composition sets per shard is a routing value of that kind and may travel in its genotype-shard tuple.
- **An _optional_ flag/scalar belongs in `task.ext.args`, never in a tuple or `val(...)` input — even when it is scientifically meaningful, phenotype-specific, or varies per row.** The litmus is optionality, not relevance: if the tool runs correctly without it and the module emits nothing when it is absent (`def x_arg = x ? "--x ${x}" : ''`), it is optional. This covers REGENIE `--bt` (absent ⇒ default quantitative model) and the GCTA/LDAK REML `--prevalence` liability flag (absent ⇒ observed-scale output). Supply these through `ext.args`, constructed from canonical pipeline fields in method configuration, using a closure when they vary per row: `ext.args = { meta.trait_type == 'binary' ? '--bt' : '' }`. Do **not** thread them through the phenotype/genotype tuple on the grounds that they are "specific to that analysis" — per-row variation is handled by the closure, not a tuple member. Upstream review established this precedent (#11008): review removed `is_binary` from the `regenie/step1` phenotype tuple in favour of exactly this `ext.args` closure. This governs scalar flags/values only: an optional _file_ input instead stays a `path(...)` tuple member passed `[]` when absent (see "Optional support-file absence" below), because Nextflow must stage files into the task work directory and cannot do so through an `ext.args` string.
- These placements do not relax the requirement that every atomic-module input — tuple member or standalone — be consumed by the native command or staged for its runtime manifest/list; never declare an input the command ignores. (A split-part `job_number` or a model/stratum selector is a legitimate _required_ tuple-scalar of this kind.)
- Allow scalar `val(...)` members in output tuples only when contract-defining; keep them explicit, place them last (after metadata and file/path members), and do not hide them in metadata or reconstruct them downstream.

## Extension seams and `script:` variable order

- `task.ext.args` for optional non-file CLI behaviour; `task.ext.args2` only when the tool syntax genuinely requires a second argument segment (e.g. plugin args after `--`); suffix overrides only when the contract truly exposes multiple output-suffix behaviours. Do not turn extension seams into substitutes for required interface-defining inputs.
- Do not add `set -euo pipefail` to inline command blocks unless a reviewer explicitly requests it for a concrete shell-pipeline failure mode. Put `${args}` on its own command line, usually after the required options.
- Order `script:` local variables by dependency: (1) `def args = task.ext.args ?: ''` first, `def args2` immediately after when genuinely needed; (2) staged input basename variables (`input_prefix`, `bfile_prefix`, `grm_prefix`); (3) the emitted output basename `prefix = task.ext.prefix ?: <active identity>`; (4) names derived from `prefix` (e.g. `run_prefix`); (5) tool-mode flags and optional CLI fragments in consumption order; (6) scalar fallback/default variables close to the fragment they support.
- Assign `prefix` without `def` when `output:` declarations reference `path("${prefix}...")` so the declaration
  can resolve it; use `def prefix` only when `prefix` is used solely inside the script/stub body (e.g. outputs
  declared with broad globs like `path("*.log")`). `nf-core-module-create` owns which variables may appear in a
  stub; order the variables it permits by the same dependency rule used for `script:`.

## Optional support-file absence

Represent optional file-like inputs explicitly in the tuple contract; callers omit them with `[]`. Build CLI fragments from presence checks, e.g. `def map_cmd = map ? "--map ${map}" : ""`, `def sites_cmd = sites_vcf ? "--sites ${sites_vcf}" : ""`. Test both present and absent paths. When the absent branch still needs its own flag (a tool that demands either `--weights` or `--ignore-weights YES`), keep it in the same ternary's else branch — `def weights_arg = weights_file ? "--weights ${weights_file}" : "--ignore-weights YES"` — rather than emitting a second mutually exclusive variable and interpolating both.

## Versions on the `versions` topic

Inline GWAS/popgen modules emit versions on the `versions` topic, not `versions.yml`:

```nextflow
output:
tuple val("${task.process}"), val("tool_x"), eval("tool_x --version"), emit: versions_tool_x, topic: versions
```

Migrating an existing inline module from `versions.yml` to topic-based versions is the correct direction when you are already changing the contract. (Template-backed static helper scripts under `templates/` instead write a `versions.yml` inside the template and emit it as `path "versions.yml", emit: versions, topic: versions`. Current nf-core lint (`main_nf_version_topic`) hard-fails any module with meta-bearing outputs that omits the `topic: versions`, so keep it even for file-based version reporting; the reference template module `soupx` uses exactly this form.)

- Report a version for **every** tool the script invokes, including secondary interpreters (R/`r-base`, Python) used for post-processing — add a separate `versions_<tool>` topic entry for each, not just the headline GWAS tool (#10999).
- Craft each `eval` so only the **bare** version string reaches the output: strip a leading `v`, any file extension/suffix, and extra lines (`eval("regenie --version | head -n 1")` reduced to `4.1.2`). Reviewers reject values like `v4.1.2.gz` and ask for the extraction to be tightened (#11008).

## Process tags

`tag` values identify the specific runtime item, not the process/tool name Nextflow already reports:

```nextflow
tag "${meta.id}_${meta2.id}"
```

Do not prefix tags with redundant tool/subcommand text (e.g. `gcta_reml_ldms_...`) unless that text is itself part of the runtime identity being distinguished.

## One contract, three files

Treat `main.nf` (executable contract), `meta.yml` (documented contract), and tests (enforced contract) as one interface surface. When one changes, review the other two in the same edit.

## Prefer setup-generated prerequisites

If an upstream artefact is cheap and deterministic, generate it in `setup { run(...) }` rather than checking in another fixture. This keeps GWAS tests small and makes the interface between dependent modules explicit.
