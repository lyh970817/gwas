# Component fixtures and testing contracts

Applies to upstream-bound module and subworkflow tests. The fixture and submission-test skills own discovery,
commands, runtime matrices, stopping gates, evidence, and reporting.

## Fixture policy

- Search existing `nf-core/test-datasets` fixtures first, especially the target component branch. Prefer a small
  existing fixture when the tool executes and assertions remain meaningful.
- Prefer deterministic `setup { run(...) }` generation by an existing component when that is more stable than a
  new shared fixture. Add new test data only when reuse and practical setup generation cannot cover the contract.
- New shared fixtures must be minimal, portable, and prepared in a separate writable
  `nf-core/test-datasets` branch/worktree. Local paths and overrides never enter committed component tests or
  public reviewer text.

## Test surface

- Module tests use `tests/main.nf.test`; subworkflow tests use the standard `nextflow_workflow` wrapper. Dotted
  infixes may distinguish genuine scenario variants. Snapshots sit beside the matching test.
- Cover each distinct output type or extension, each real composition route, and every optional-input, selector,
  or skip path that changes behavior. Include representative stub coverage and valid compressed stub files.
- Tests are deterministic. Do not branch on fixed per-case inputs, rely on timestamps/random IDs/unordered output
  without normalization, or weaken assertions to conceal a contract defect.

## Assertions and snapshots

- Assert process/workflow success before snapshots.
- For stable module outputs, prefer a complete sanitized output snapshot. Use `unstableKeys` for isolated unstable
  channels. Use a narrower semantic projection only when full output is unstable or low-signal; then assert
  success, public names, metadata identity, file presence, and versions explicitly.
- Keep targeted assertions only for behavior not visible in output, such as command construction, expected
  failure, or selected stable content. Do not duplicate cardinality, filenames, and file-presence facts already
  captured by the complete sanitized snapshot.
- Update snapshots only for intentional, understood contract changes.

## Test configuration

- Add `tests/nextflow.config` only for genuine test-specific extension arguments, prefixes, collisions, runtime
  behavior, or matrix controls, and load it explicitly from the test.
- For optional command arguments, define an empty safe default such as `params.module_args = ""`, map it to
  `ext.args`, and override the parameter only in scenarios that need it.
- Never commit local test-dataset paths. Keep standard portable test-data parameters intact and apply local
  overrides only in the execution environment.

## Readiness boundary

Pipeline CI discovery of colocated local component tests is useful regression coverage but is not component
submission readiness. Readiness requires the current lint and wrapper-test procedure in the actual writable
`nf-core/modules` submission worktree, including every required runtime profile or an explicitly reported gap.
