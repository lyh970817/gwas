# Component package and container contracts

Applies to upstream-bound module package declarations, container directives, and `meta.yml` container metadata.
The `nf-core-containers` skill owns live lookup, verification, repair, and evidence procedure.

## Package source of truth

- `environment.yml` is the package-requirement source of truth. Pin every dependency with its channel and
  version, not its build. Add channels only when necessary and never add `defaults`; pin `pip` itself when pip
  dependencies are present.
- Account explicitly for reproducibility and supported platforms, including ARM64/Bioconda constraints.

## Runtime directive

- Route both Singularity and Apptainer through the frozen Singularity-compatible branch:

  ```nextflow
  workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ? '<singularity-uri>' : '<docker-uri>'
  ```

- Docker/Podman and Singularity/Apptainer may require different frozen URI forms. Prefer a verified direct
  Seqera Containers HTTPS blob for Singularity when available. Never invent a Wave/Seqera reference.
- GPU-capable modules follow the current nf-core GPU component specification.

## `meta.yml` containers

`meta.yml` container metadata is separate from the `main.nf` directive. Use platform keys such as
`linux/amd64` and `linux/arm64`; the underscore form remains valid only where a lock filename requires it.

```yaml
containers:
  conda:
    linux/amd64:
      lock_file: "modules/nf-core/<component>/.conda-lock/<file>.txt"
  docker:
    linux/amd64:
      build_id: "bd-..."
      name: "community.wave.seqera.io/library/<tool>:<version>--<hash>"
      scan_id: "sc-..."
  singularity:
    linux/amd64:
      build_id: "bd-..."
      name: "oras://community.wave.seqera.io/library/<tool>:<version>--<hash>"
      https: "https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/.../data"
```

- Use `scan_id`, never `scanId`.
- Include a `conda` entry whenever the module has `environment.yml`.
- Lock-file existence and exact schema requirements are validated against the current nf-core tooling; do not
  encode a warning from one tool version as an eternal contract.
