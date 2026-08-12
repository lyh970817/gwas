---
name: nf-core-containers
description: Resolve and verify package/container provenance for an nf-core module. Use when selecting or changing environment.yml, a container directive, frozen Seqera/Wave references, or meta.yml container metadata.
---

# Resolve component containers

Read [`component-containers.md`](../../../docs/coding-standards/component-containers.md). Use
`docs/nf-core-standards/module-containers.md` only for unresolved upstream detail.

## Procedure

1. Identify every executable owner and reconcile it with `environment.yml`.
2. Obtain exact current frozen Docker and Singularity/Apptainer references from Seqera Containers or another
   primary package source. Never guess a Wave/Seqera URL.
3. Verify a direct HTTPS blob with `curl -I -L --max-time 20 '<url>'` and expect HTTP 200.
4. Reconcile the `main.nf` directive and `meta.yml` container metadata with the canonical contract.
5. Run the target lint. Do not use `nf-core modules lint --fix` to repair the container block; hand-edit the
   intended keys and re-run lint.
6. Runtime evidence wins over a plain-URL lint probe. After changing the Singularity branch, run the target
   Singularity wrapper test. Treat container-link or build-ID warnings as tooling noise only after a real runtime
   proves the image resolves and runs.

Report package versions, resolved references, probe and runtime commands/results, lint warnings interpreted, and
any unverified platform or container blocker.
