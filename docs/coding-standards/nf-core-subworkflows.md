# nf-core subworkflow contracts

Applies to reusable upstream-bound composition, including candidate compositions under `subworkflows/local/`.
Pipeline routes and helpers classified by the descendant instructions remain pipeline-owned.

## Reusable boundary and naming

- A reusable subworkflow composes at least two genuine modules into one logical unit. Keep pipeline publication,
  scientific routing, cross-request reuse identity, and pipeline-only utilities outside it.
- Format-specific names normally begin with the primary input format, followed by concise semantic operation
  tokens and an optional tool/tool-chain token. Generic orchestration and genuinely co-primary formats may use a
  semantic exception. The directory and `meta.yml` name are lowercase snake case; the workflow symbol uses the
  same tokens in uppercase.
- The standard files are `main.nf`, `meta.yml`, optional integration or test configuration, and
  `tests/main.nf.test`.

## Composition contract

- Includes precede optional pure helpers and the workflow. Alias repeated imports by semantic role. Keep the
  workflow body ordered `take:`, `main:`, `emit:` and document public channel/value shapes at both boundaries.
- Define required and optional inputs explicitly. Optional files use the documented empty-list convention.
- Keep temporary routing and orchestration channels private. Emit stable public products by fixed names.
- Preserve focal metadata through reshaping. Temporary join/scatter keys must be collision-free and removed
  before emission. Guard expected one-to-one joins with `failOnMismatch: true` and `failOnDuplicate: true`.
- Use `groupKey`/`groupTuple`/`getGroupTarget` when gather completion depends on actual cardinality. Use
  `collect()` only when the native consumer requires one global collection.

## Scatter and routing

- Composition owns scatter/gather state. Pass a requested shard count only to the splitter whose native command
  consumes it, then derive actual cardinality and keys from native splitter outputs. Scatter and gather by those
  observed keys and emit aggregate execution provenance separately when it is part of the public contract.
- For workflow-wide selectors, initialize every conditionally produced public channel with `channel.empty()`,
  invoke the selected branch, and keep the emitted API stable. Use `branch` for per-record mutually exclusive
  routing and `mix` compatible products. Reject invalid selector/input combinations before execution.

## Identity, metadata, and versions

- `meta.yml` documents every public `take` and named `emit` once, in the same order and shape as `main.nf`.
  Structured tuple members, optionality, patterns, scalar constraints, and identity transformations agree.
- Inventory the invoked module/subworkflow graph under `components`; subworkflows have no `tools` or `topics`
  section.
- Current module version topics flow through composition without manual collection or re-emission. Emit an
  explicit `versions` channel only when a called legacy component exposes ordinary version channels; never emit
  an empty channel merely to satisfy an obsolete convention, and never document a version output absent from
  `main.nf`.

## Integration and tests

- A component-root `nextflow.config` documents integration selectors a caller must transplant. A
  `tests/nextflow.config` is test-only and is loaded explicitly; do not conflate them.
- Tests cover every distinct real composition route and each optional-input, skip, or selector path that changes
  behavior. Include representative end-to-end stub coverage and assert routing, identity, or absence explicitly
  when a snapshot obscures it.
- Directory, workflow symbol, `main.nf`, `meta.yml`, config, tests, and snapshots are one public contract.

GWAS-specific interface semantics are owned by
[`gwas-component-contracts.md`](gwas-component-contracts.md); fixture and assertion rules are owned by
[`component-fixtures-and-testing.md`](component-fixtures-and-testing.md).
