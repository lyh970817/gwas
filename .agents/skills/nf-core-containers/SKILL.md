---
name: nf-core-containers
description: Container-directive and provenance rules for nf-core modules — environment.yml as source of truth, Singularity/Apptainer directive branching, and Wave/Seqera URI verification. Use when selecting, writing, or reviewing a module container directive or environment.yml.
---

Read `../references/nf-core-guidance-sources.md`. This skill is authoritative for routine container decisions.
If extra upstream detail is needed, use `docs/nf-core-standards/module-containers.md` as the cache topic hint.

Use this skill when selecting or reviewing a module container strategy, editing `environment.yml`, or resolving Wave/Seqera Container URIs. During component design, identify the executable owner and how it enters `environment.yml` before accepting a module namespace or an embedded adapter path. Apply every bullet below by default; in reviews, surface each deviation as a finding unless a stricter specification overrides it.

## Package sourcing

- Treat `environment.yml` as the source of truth for package requirements. Follow the Seqera Containers guidance for modern container generation and provenance.
- Be explicit about reproducibility and platform compatibility. ARM64/Bioconda nuances are part of the review surface, not an afterthought.

## Container directive branching

- Route both Singularity and Apptainer engines through the frozen Singularity-compatible image branch:

  ```nextflow
  workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ? '<singularity-uri>' : '<docker-uri>'
  ```

  Do not check only `workflow.containerEngine == 'singularity'` unless a concrete engine-specific reason exists.

- For Wave-backed containers the Docker/Podman branch and the Singularity/Apptainer branch may need different URI forms. If a direct Seqera Containers HTTP blob URL is available for Singularity, prefer it over `docker://community.wave.seqera.io/...` in the Singularity branch.

## Wave / Seqera URI verification

- Never invent `community.wave.seqera.io/...` or other Wave/Seqera URLs. Use the Seqera Containers page to obtain the exact frozen reference and HTTP/Singularity URL, then verify the HTTP blob URL before committing it, e.g. `curl -I -L --max-time 20 '<https-blob-url>'` expecting HTTP 200. If a container cannot be verified, keep the standard container approach instead of guessing a Wave tag.
- Runtime verification matters more than plain HTTP probing. `nf-core modules lint` may emit a `container_links` warning that a `community.wave.seqera.io/library/...` string returns 404 as a normal URL even though the runtime resolves it correctly (the authenticated OCI manifest exists). Differing Wave docker/singularity build IDs can also trigger `main_nf_container: Container versions do not match`. Treat both as ignorable tooling noise once the module really runs — confirm by running `nf-core modules test <tool[/subtool]> --profile singularity` after changing the Singularity branch, not by trusting or over-reacting to the lint URL check.

## meta.yml `containers:` block

Modern nf-core lint (v4.0.3.dev0+) validates a `containers:` section in `meta.yml` with a pydantic model, separate from the `container` directive in `main.nf`. Get the format exactly right or the module passes its own PR checks but is later rejected — use `modules/nf-core/fastqc/meta.yml` on upstream `master` as the canonical reference. Required shape:

```yaml
containers:
  conda:
    linux/amd64:
      lock_file: "modules/nf-core/<tool[/subtool]>/.conda-lock/<file>.txt"
  docker:
    linux/amd64:
      build_id: "bd-..._1"
      name: "community.wave.seqera.io/library/<tool>:<ver>--<hash>"
      scan_id: "sc-..._2"
  singularity:
    linux/amd64:
      build_id: "bd-..._1"
      name: "oras://community.wave.seqera.io/library/<tool>:<ver>--<hash>"
      https: "https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/.../data"
```

- Platform keys use a **slash**: `linux/amd64` (and `linux/arm64`). The underscore form `linux_amd64` is rejected (`Invalid platform key: linux_amd64`). Note the `.conda-lock/` _filename_ still uses the underscore form — only the YAML key changed.
- Docker/Singularity entries use `scan_id:` (snake_case), never `scanId:`.
- A `conda:` sub-section is **mandatory** whenever the module ships a conda `environment.yml`; omitting it fails with `No containers specified for conda`. A minimal entry is just `lock_file:` under `linux/amd64`.
- A missing `.conda-lock` file is only a **warning** (`containers_conda_lock_exists`), so it does not fail the lint job (which exits non-zero only on FAILED tests). Generating the real Wave-matched lock file clears the warning but is not required to merge.
- Do not use `nf-core modules lint --fix` to repair this block — it is destructive (strips the schema comment, reorders `notes`, rewrites `licence`, injects ontologies) and still does not fix the platform keys. Hand-edit the block and re-verify with `nf-core modules lint <tool[/subtool]>`.
