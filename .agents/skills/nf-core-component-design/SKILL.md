---
name: nf-core-component-design
description: Design or audit a proposed nf-core component portfolio before implementation. Use when an issue, specification, research task, or Wayfinder question decides module/subworkflow boundaries, executable ownership, public interfaces, containers, fixtures, validation, or pipeline-local scope.
---

# Design an nf-core component portfolio

Read the component and contribution topics indexed by `CODING_STANDARDS.md`, then use the lifecycle skills as
procedures:

- `nf-core-module-create` for each atomic component;
- `nf-core-subworkflow-create` for each reusable composition;
- `nf-core-containers` and `nf-core-fixtures` for package/data decisions;
- `nf-core-submission-review` for an independent contract audit.

## Design procedure

1. Extract every applicable stable constraint from the canonical topics. Consult only the cache topics needed
   for a specific unresolved upstream question.
2. Check the relevant programme documentation cache or index under `docs/`, then use primary programme, API,
   CLI, release, packaging, test, and container sources for unresolved details.
3. For each proposed component, record executable ownership, reproducible execution path, public name, atomic or
   reusable boundary, metadata/file/scalar roles, outputs and identity, package/container route, fixture decision,
   real/stub validation, and pipeline-local exclusions.
4. For composition, additionally trace take/emit shapes, focal identity, optional absence, scatter/gather
   cardinality, version flow, and dependency graph.
5. Audit the provisional portfolio with `nf-core-submission-review`. Record unresolved contract items as blockers
   rather than calling an interface exact.

Report canonical and fallback sources consulted, proposed components and executable owners, contract and
packaging/fixture decisions, pipeline-local boundaries, and remaining blockers.
