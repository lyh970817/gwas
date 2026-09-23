# nf-core-gwas-biofuse

Host-side launcher that serves a VCF Zarr cohort to nf-core/gwas as a [BioFuse](https://github.com/sgkit-dev/biofuse)
PLINK 1 view. It runs on the host before Nextflow starts: it mounts one cohort, waits until the virtual
`.bed`/`.bim`/`.fam` are readable, writes a temporary cohort manifest that declares the view's content-addressed
`genotype_view_id`, runs the command you give it, and tears the mount down on every exit path, including a `SIGKILL`
of the launcher itself.

## Environment

The launcher is installed into the conda environment it needs anyway; `environment.yml` pins the encoder versions
that enter the view identity and the `libfuse3` floor the mount daemon requires.

```bash
conda env create -f launcher/biofuse/environment.yml -p /path/to/env
```

`pyfuse3` is x86-64 only on conda-forge. The mount is readable by Apptainer or Singularity tasks but not by rootful
Docker, and it is visible on the launching host only, so the launcher refuses a multi-node Slurm allocation.

## Invocation

```bash
nf-core-gwas-biofuse run \
    --vcz /data/cohort.vcz --cohort-id cohort_a --genome-build GRCh38 --ancestry EUR \
    --autosomes-only --readahead-buffer-size 64M \
    -- nextflow run nf-core/gwas -profile apptainer \
         --cohort_manifest '{cohort_manifest}' --analysis_manifest analysis_manifest.csv --outdir results
```

`{cohort_manifest}` is replaced by the generated manifest path, and the command's exit status is the launcher's. The
view always excludes multiallelic sites (`--max-alleles 2`), and a store with variants on any contig other than
autosomes 1-22 needs `--autosomes-only`. Cancel a backgrounded launcher with `SIGTERM`.

Other subcommands:

- `nf-core-gwas-biofuse identity --vcz ...` prints the identity and its preimage without mounting anything.
- `nf-core-gwas-biofuse reap-stale` tears down views whose launcher is gone.

## View identity

`genotype_view_id` is `biofuse:` followed by the SHA-256 of a canonical JSON preimage: the store's content digest (or
the `--source-revision` token you declare for an externally versioned store), its VCF Zarr version and writer, the
`biofuse` and `vcztools` versions, and every selection option. Options that change only how the view is served, such
as the basename, readahead and log settings, the mountpoint and the cohort metadata, are left out, so changing them
never moves the identity. `nf_core_gwas_biofuse/identity.py` documents the exact preimage.

Each run writes `<cohort_id>.biofuse_view.json` to `--record-dir` (default: the current directory) with the preimage,
the identity, every runtime version including the `libfuse3` the daemon loaded, the readiness time and the
information a PLINK 1 view cannot carry. `--identity digest` leaves the manifest's `genotype_view_id` empty so the
pipeline digests the trio through the mount instead.

## Tests

`pip install -e 'launcher/biofuse[test]'`, then `pytest launcher/biofuse/tests` for the pure tier. The FUSE tier,
`VCZ=/path/to/store.vcz launcher/biofuse/tests/lifecycle_matrix.sh`, needs `/dev/fuse`, this environment and
Apptainer; it exits 0 with `SKIPPED: <reason>` when the host cannot run it.
