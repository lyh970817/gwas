# nf-core module contracts

Applies to new or maintained upstream-bound atomic components, including the candidate families under
`modules/local/`. The component task skills own creation, review, and validation procedure.

## Atomic boundary and files

- A module invokes one atomic tool operation and defines exactly one `process`. Routing, fan-out strategy,
  scientific policy, publication, and reuse identity belong in composition or the caller.
- The portable component contains `main.nf`, `meta.yml`, `environment.yml`, and `tests/main.nf.test`; snapshots
  change only when the understood output contract changes.
- Process names are uppercase and module directories lowercase. The process directives are `tag`, `label`,
  `conda`, and `container`. New and upstream-bound modules do not use a process-level `when:` seam; conditional
  routing belongs in composition.
- Choose a resource label that reflects the operation's CPU, memory, and time profile.

## Inputs and native interface

- Put metadata-bearing tuples before process-global values. Each tuple starts with `val(meta)`, `val(meta2)`,
  and so on in declaration order, followed by file/path members and then mandatory tuple-local scalar values.
  Tuple-local scalars are not metadata keys.
- Every input is consumed by the native command or staged because a runtime manifest/list references it. Keep
  cleanup-only files and composition state outside the atomic interface.
- A mandatory native value is an explicit `val(...)` input. Optional non-file CLI behavior uses `task.ext.args`.
  Optional files remain path members and callers represent absence with `[]`.
- Keep file and selector roles native. Put a shard count on the splitting atom only when its native command
  consumes it. The atom handles the unsplit case without assuming a particular composition.
- Metadata keys are limited to the nf-core component specification. Do not invent keys for selectors, shard
  counts, model type, or output basenames. Preserve incoming metadata on output rather than rebinding it to a
  generated filename.

## Extension seams and command construction

- Name the optional-arguments variable `args` and default it exactly with
  `def args = task.ext.args ?: ''`. Use `args2` only when tool syntax requires a second argument segment.
  Required native flags never hide in an `ext.args` default.
- Derive `prefix` from the active contract identity and keep it overridable with `task.ext.prefix`. Use the
  staged basename for basename-driven tools and `meta.id` when metadata defines identity.
- Define `args`, `args2`, `prefix`, or other locals only when the command or an output declaration consumes them.
  A stub defines only variables needed to create its declared stub outputs; it does not manufacture a use for
  optional command arguments.
- Keep command construction direct. Put optional fragments in consumption order, avoid unexplained collection
  tricks, and justify non-trivial in-script post-processing as part of the documented operation.
- Do not add `set -euo pipefail` to inline commands without a concrete shell-pipeline failure mode.

## Staging, identity, and outputs

- When two same-typed input sets, or an input and output, could collide in the work directory, stage each set in
  a distinct subfolder with `stageAs` or give the output a distinct default prefix. Cover every member of a
  multi-file bundle.
- Do not use `stageAs`, renamed inputs, symlinks, or defensive basename-equality checks to conceal a caller
  contract mismatch. Document the required basename relationship and let the native tool reject invalid input.
- Emit one channel per semantically distinct file or file group. Bundle only files that always travel together
  and are consumed as a unit.
- `tag` identifies the runtime item, normally from active metadata identities; do not repeat the process/tool
  name unless it distinguishes runtime identity.

## Metadata, stubs, and versions

- `main.nf`, `meta.yml`, tests, and snapshots describe one interface: input/output order, roles, optionality,
  patterns, identity, and emitted names agree.
- Every file entry in `meta.yml` has `ontologies:` with matching EDAM terms or an empty list. Keywords include
  spelled-out forms of tool acronyms. Inputs and outputs remain ordered as in `main.nf`.
- Stubs create valid files for every output, including valid gzip streams. Stub behavior preserves output names,
  cardinality, and structure without invoking the real program.
- Report every invoked tool, including secondary interpreters, on the `versions` topic. Each version extraction
  yields a bare version string without a tool-name prefix, leading `v`, suffix, or extra line.

Package and container requirements are owned by
[`component-containers.md`](component-containers.md). GWAS-specific tuple, selector, and bundle semantics are
owned by [`gwas-component-contracts.md`](gwas-component-contracts.md). Test contracts are owned by
[`component-fixtures-and-testing.md`](component-fixtures-and-testing.md).
