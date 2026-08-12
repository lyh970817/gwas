# GWAS and population-genetics component contracts

These repository-specific contracts refine the generic nf-core component standards for PLINK/PLINK 2,
phasing, imputation, GRM construction, association, summary statistics, reference data, and harmonisation.

## Genotype and relatedness bundles

- PLINK 1 is `tuple val(meta), path(bed), path(bim), path(fam)`. PLINK 2 is
  `tuple val(meta), path(pgen), path(psam), path(pvar)`.
- When PLINK 1 and PLINK 2 occupy the same identity and native CLI role, their accepted semantic union is
  `tuple val(meta), path(plink_genotype_file), path(plink_variant_file), path(plink_sample_file)`. Concrete
  PLINK 2 values are PGEN/PVAR/PSAM in that semantic primary/variant/sample order, intentionally different from
  the explicit PLINK 2-only order.
- Let the staged primary-genotype extension select the native flag. Split formats into separate metadata-bearing
  roles only when their native or semantic roles differ.
- An always-together GRM is one collected `path(grm_files)` input. A separate sidecar consumed by its own flag
  remains separate. For basename-driven tools, derive the prefix from the defining bundle member; do not
  destructure the public contract merely to obtain it.

## Metadata roles

- Model mutually exclusive primary formats with different semantic or CLI roles as separate metadata-bearing
  tuples. Use `meta`, `meta2`, `meta3`, in input order without gaps; callers pass `[]` for inactive roles. The
  active role determines emitted metadata and basename.
- Keep analysis-bearing resources such as phenotype, covariate, keep/remove, reference panel, scaffold, site,
  and genetic-map files in metadata-bearing tuples when the role clarifies identity. Plain `path(...)` is for a
  non-identity sidecar.
- If a support tuple shares the focal genetic/sample identity, outputs emit the primary `meta`. Emit secondary
  metadata only when that tuple defines a distinct output identity.

## Chromosome shards and prefix identity

- Repeated chromosome bundles retain one cohort/analysis `meta.id`; chromosome identity lives in the staged
  bundle basename, not a custom metadata key.
- A file or bundle prefix is never a standalone `val(...)` input. Use `meta.id` when metadata defines identity,
  or the staged basename when the native tool is basename-driven.
- When a caller contract requires matching staged basenames, document and test it. Do not repair a mismatch with
  `name:`, `stageAs`, ad hoc symlinks, or custom defensive exceptions.
- Work-directory name collisions are distinct from caller-contract mismatches. For genuine collisions, stage
  each input set in a separate subfolder or choose a distinct output prefix, covering every companion file.

## Scalars and optional files

- A scalar is an explicit module input only when the native tool always requires it or when one mutually
  exclusive mode must always be selected. Put a per-analysis scalar after the tuple's file members; use a
  standalone value only when it is process-global.
- Verify mandatory status from native behavior: if the tool errors when the flag is omitted, the value belongs
  in the interface. Do not hide it in metadata or an `ext.args` default.
- Optional phenotype-column selectors and other optional non-file behavior use `task.ext.args`, including values
  that vary per record through a closure. Optionality, not scientific importance, decides this placement.
- Optional files remain tuple path members and callers use `[]` for absence so Nextflow can stage present files.
  Build one mutually exclusive CLI fragment from the presence check and test both paths.
- A contract-defining scalar may appear last in an output tuple. Do not hide it in metadata or reconstruct it
  downstream.

## Extension variables and script order

- `task.ext.args` owns optional non-file CLI behavior. Use `task.ext.args2` only where native syntax requires a
  second argument segment. Extension seams never replace mandatory interface values.
- Order script locals by dependency: `args`, genuine `args2`, staged input basenames, output `prefix`, names
  derived from the prefix, mode/optional fragments in command order, then scalar fallbacks near consumption.
- Assign `prefix` without `def` when an `output:` declaration resolves it. Use `def prefix` only when it is local
  to the script/stub body. Stub variable eligibility remains governed by the generic module contract.

## Versions, tags, and consistency

- Inline components report each invoked executable and interpreter on the `versions` topic. Template-backed
  helpers may emit a version file on that topic when the template owns the capture.
- Every extraction yields only the bare version. Do not emit a leading `v`, tool name, archive suffix, or extra
  line.
- Tags identify runtime identities, commonly `${meta.id}_${meta2.id}` for two active roles. Do not prefix a tag
  with redundant tool/subcommand text.
- Treat `main.nf`, `meta.yml`, and tests as one contract. Review all three when an interface changes.
- Prefer deterministic setup-generated prerequisites over an additional fixture when an existing component can
  create the artifact cheaply and stably.
