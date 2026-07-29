---
name: nf-core-component-design
description: Design or audit a proposed nf-core component portfolio before implementation. Use when an issue, specification, research task, or Wayfinder ticket decides module versus subworkflow boundaries, executable ownership, names, execution paths, public interfaces, metadata roles, selectors, outputs, containers, fixtures, validation, or pipeline-local boundaries.
---

Read `../nf-core-common.md` first. Treat the routed lifecycle skills below as authoritative. Use the
standards-cache fallback only when they leave a relevant question unclear or incomplete, or extra upstream
detail is needed.

Use nf-core standards as design inputs before external programme research. Route to the applicable skills:

- `nf-core-module-create` for each proposed atomic module.
- `nf-core-subworkflow-create` for each proposed reusable subworkflow.
- `nf-core-submission-review` to audit planned interfaces before declaring them settled.
- `nf-core-gwas-module-conventions` for GWAS or population-genetics contracts.
- `nf-core-containers` for executable ownership, packaging, templates, environments, or containers.
- `nf-core-fixtures` for fixtures, generated prerequisites, or validation matrices.

## Design gate

Do not declare the portfolio resolved until every proposed component has a checkable answer for each applicable
item:

1. Executable owner, reproducible execution path, namespace, and component name.
2. Atomic process boundary or reusable composition of at least two genuine modules.
3. Conceptual metadata-bearing inputs, optional and mutually exclusive roles, and opaque `meta` handling.
4. Required scalar selectors versus optional `task.ext.args` behaviour.
5. Fixed named outputs, identity rules, and version reporting for every executed tool or propagation into a
   subworkflow's combined public `versions` output.
6. Source-of-truth package/container strategy and reuse-first fixture decision.
7. Real and stub validation contract, plus an explicit reusable-versus-pipeline-local boundary.

For subworkflows, also settle conceptual `take`/`emit` contracts, focal identity flow, optional-resource
absence, scatter/gather cardinality, the combined public `versions` output, and composition-focused tests.
Record unresolved items as blockers rather than calling an interface exact.

## Research order

1. Extract applicable nf-core constraints from the routed skills. Consult the standards cache only for a
   specific unresolved question or needed extra detail.
2. Research the official programme, API, CLI, releases, packaging, tests, and container paths.
3. Map native and adapter-owned execution paths onto component boundaries.
4. Define provisional interfaces and audit them with `nf-core-submission-review`.
5. Publish the decision only when every applicable design-gate item is answered or explicitly blocked.

## Completion

Report the skills read and any standards-cache topics deliberately consulted, proposed components and executable owners, public contract decisions,
packaging and fixture decisions, pipeline-local boundaries, and remaining blockers.

## Trigger examples

Trigger for “define the first-release component portfolio”, “decide module versus subworkflow”, “research the
official CLI and nf-core execution path”, or “specify inputs, outputs, fixtures, and validation without
implementing”. Do not trigger for biological-method explanation that makes no nf-core interface, packaging,
testing, or submission decision.
