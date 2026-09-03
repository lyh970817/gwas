process GENIE_G {
    tag "${meta.id}"
    label 'process_high'

    // GENIE is not packaged for Bioconda -- the `genie` name there belongs to an unrelated tool -- so this
    // module ships a digest-pinned image and no `environment.yml`, following `metasoft/re2`. The image is
    // `linux/amd64` only and there is no Conda fallback, so the module cannot run on another architecture.
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'docker://ghcr.io/lyh970817/genie@sha256:c4b836f6bdf5853c49d902e29f70a9a6540388a23d9b6840c9f3c67ad40d47e0'
        : 'ghcr.io/lyh970817/genie@sha256:c4b836f6bdf5853c49d902e29f70a9a6540388a23d9b6840c9f3c67ad40d47e0'}"

    input:
    // `bed`, `bim` and `fam` share one basename: GENIE takes a `-g` prefix, not three paths. That is a caller
    // contract stated in `meta.yml` rather than a defensive check here.
    tuple val(meta), path(bed), path(bim), path(fam)
    // `expected_counts` is a two-column TSV of the sample, covariate and per-bin variant counts GENIE must
    // echo back. `memory_efficient` selects between the two executables the image ships; exactly one of them
    // always runs, so it is a mandatory tuple-local scalar rather than an `ext` seam.
    tuple val(meta2), path(phenotype), path(covariates), path(annotation), path(expected_counts), val(memory_efficient)

    output:
    tuple val(meta), path("${prefix}.out"), emit: results
    tuple val(meta), path("${prefix}.out.xsum"), emit: xsum, optional: true
    tuple val(meta), path("${prefix}.out.wgxsum"), emit: wgxsum, optional: true
    tuple val(meta), path("${prefix}.log"), emit: log
    // GENIE reports no version of its own: `--version` and `--help` both exit 1, the runtime banner
    // self-reports `v1.0.0` for the v1.1.1 tag, and the image bakes in no version file to read. The only
    // authoritative marker is the image's `org.opencontainers.image.version` label, which a task cannot read,
    // so the pinned digest and this literal move together or not at all.
    tuple val("${task.process}"), val('genie'), val('1.1.1'), emit: versions_genie, topic: versions

    script:
    def args = task.ext.args ?: ''
    def binary = memory_efficient ? 'GENIE_mem' : 'GENIE'
    prefix = task.ext.prefix ?: "${meta.id}"
    def covariate_arg = covariates ? "-c \"${covariates}\"" : ''
    """
    ${binary} \\
        -g "${bed.baseName}" \\
        -p "${phenotype}" \\
        ${covariate_arg} \\
        -a "${annotation}" \\
        -m G \\
        -np 0 \\
        -i 1 \\
        -t "${task.cpus}" \\
        -o "${prefix}.out" \\
        ${args} \\
        2>&1 | tee "${prefix}.log"

    # Everything below guards a measured silent-wrong-answer mode of this pinned image, each of which exits 0
    # with a plausible-looking result file. They are part of the documented operation, not defensive noise.

    # GENIE exits 0 and writes nothing when `-o` names an unwritable path, so the file itself is the contract.
    test -s "${prefix}.out"

    # A phenotype that is constant across the retained samples, a monomorphic variant, and an annotation GENIE
    # read as empty all yield `-nan` variance components in a well-formed 1.1 kB file at exit 0.
    if grep -qE '(^|[^A-Za-z])-?(nan|inf)([^A-Za-z]|\$)' "${prefix}.out"; then
        echo "[nf-core/gwas] ERROR: ${meta.id}: GENIE returned a non-finite estimate (-nan/inf) at exit 0; see ${prefix}.out" >&2
        exit 1
    fi

    # GENIE matches the phenotype and covariate rows positionally against the FAM and never checks an identity,
    # counts an annotation/BIM row-count mismatch as a warning while silently adopting the annotation's count,
    # and reads a header row in either file as data. Each of those shows up as a count GENIE echoes that the
    # prepared inputs do not declare, and nowhere else.
    #
    # The two executables write the same numbers in two header dialects, which is why the patterns below match
    # neither the separator nor the noun: `GENIE` writes "Number of individuals after filtering: 200" and
    # "Number of features in bin 0 : 220", while `GENIE_mem` writes "... filtering = 200" and "Number of SNPs
    # in bin 0 = 220" under a different banner version. The field positions coincide in both.
    awk -v out="${prefix}.out" -v tag="${meta.id}" '
        NR == FNR { want[\$1] = \$2; next }
        /^Number of individuals after filtering/ { got["individuals"] = \$NF }
        /^Number of covariates/                  { got["covariates"]  = \$NF }
        /^Number of (features|SNPs) in bin /     { got["bin_" \$6]    = \$NF }
        END {
            rc = 0
            for (key in want) {
                if (!(key in got)) {
                    printf "[nf-core/gwas] ERROR: %s: GENIE did not echo %s in %s\\n", tag, key, out > "/dev/stderr"
                    rc = 1
                }
                else if (got[key] + 0 != want[key] + 0) {
                    printf "[nf-core/gwas] ERROR: %s: GENIE reports %s = %s but the prepared inputs declare %s (%s)\\n", tag, key, got[key], want[key], out > "/dev/stderr"
                    rc = 1
                }
            }
            exit rc
        }
    ' "${expected_counts}" "${prefix}.out"
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    // Branching on the same scalar as the script keeps `GENIE_mem`'s output cardinality exercised in stub mode.
    def stub_memory_efficient = memory_efficient ? "touch \"${prefix}.out.xsum\" \"${prefix}.out.wgxsum\"" : ''
    """
    printf 'OUTPUT: \\nVariance components: \\nSigma^2_g[0] : 0  SE : 0\\nSigma^2_e : 0  SE : 0\\nTotal h2 : 0 SE: 0\\n' > "${prefix}.out"
    printf 'stub\\n' > "${prefix}.log"
    ${stub_memory_efficient}
    """
}
