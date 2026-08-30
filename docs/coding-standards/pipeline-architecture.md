# Pipeline architecture standards

Applies to pipeline-owned orchestration, routes, and helpers. Atomic component and reusable-subworkflow
interfaces remain owned by [`nf-core-modules.md`](nf-core-modules.md),
[`nf-core-subworkflows.md`](nf-core-subworkflows.md), and
[`gwas-component-contracts.md`](gwas-component-contracts.md); user-facing parameter contracts remain owned by
[`configuration-and-schema.md`](configuration-and-schema.md).

## Ingress and representation

- **[MUST]** Validate external manifests, parameters, and their relationships at pipeline ingress. Downstream
  stages consume the resulting trusted internal contract without revalidating it.
- **[MUST]** Representation adapters change representation only. Preserve the native result and its semantics;
  normalize or assemble output only when a consumer requires that product.

## Work, identity, and cardinality

- **[MUST]** Select scientific work explicitly. A route runs only the requested methods and analyses.
- **[MUST]** The scientific stage that performs reusable work owns its identity and reuse decision. Keep
  publication, retention, and restart/resume semantics separate from that decision.
- **[MUST]** Where a consumer requires ordered inputs, preserve and document the corresponding cardinality and
  order through scatter, gather, and assembly.

## Execution boundaries

- **[MUST]** Introduce a process only for an active native-program invocation or a concrete execution boundary.
  Keep channel reshaping and pure orchestration in the caller or route that owns it.
- **[MUST]** Keep a pipeline-owned route, helper, or adapter only while it has an active caller and consumer.
