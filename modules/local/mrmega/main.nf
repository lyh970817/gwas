// MR-MEGA v0.2 native contract notes. The characterization on record was measured against a
// locally built Debian bookworm / glibc 2.36 image, while this module pins a third-party
// Ubuntu 18.04 / glibc 2.27 build that is NOT byte-identical to it (different binary sha256,
// different toolchain). The behavioural matrix has since been re-run against this exact pinned
// digest and every characterized behaviour transfers unchanged, with byte-identical numerical
// output. Treat the characterization as authoritative for this digest only; re-measure if the
// digest ever moves, because the native P-value defect thresholds in particular are libm
// dependent.
//
// This module emits raw native output only. The three native `P-value_*` columns are
// unconditionally invalid for `ndf != 2` and must be recomputed in log space downstream by
// NORMALISE_COMMON_VARIANT_META; nothing here reads, repairs or reports them.
process MRMEGA {
    tag "${meta.id}"
    label 'process_medium'

    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'docker://quay.io/loukas_moutsianas/mrmega@sha256:1143b7f016f00f0f32cbc6ad72b4a571e2f824e440a0b7fecf4ec4c8334ae1e8'
        : 'quay.io/loukas_moutsianas/mrmega@sha256:1143b7f016f00f0f32cbc6ad72b4a571e2f824e440a0b7fecf4ec4c8334ae1e8'}"

    input:
    tuple val(meta), path(study_files, stageAs: 'studies/*'), path(filelist), val(axes), path(precalculated_axes)

    output:
    tuple val(meta), path("${prefix}.result"), emit: result
    tuple val(meta), path("${prefix}.log"), emit: log
    path "versions.yml", emit: versions, topic: versions

    script:
    // There is deliberately no `task.ext.args` seam. Every remaining native option is either
    // silently wrong (`--no_alleles` negates beta for every study after the first), makes the
    // three chi-squares mutually inconsistent (`--gco`), applies an off-by-one median
    // (`--gc`, `--gco`), duplicates policy that belongs upstream (`-f`), or is entirely inert
    // (`-t`, `-m`, `--name_strand`).
    prefix = task.ext.prefix ?: meta.id
    def precalculated_flag = precalculated_axes ? '--precalculated' : ''
    def precalculated_file = precalculated_axes ?: ''
    // Must stay identical to the `container` directive above; it is the only reproducible
    // identifier this third-party build has.
    def image_reference = 'quay.io/loukas_moutsianas/mrmega@sha256:1143b7f016f00f0f32cbc6ad72b4a571e2f824e440a0b7fecf4ec4c8334ae1e8'

    """
    MRMEGA_BIN=/MR-MEGA/MR-MEGA
    AXES='${axes}'
    PREFIX='${prefix}'
    FILELIST='${filelist}'
    PRECALCULATED='${precalculated_file}'
    MANIFEST="\$PREFIX.mrmega.in"

    case "\$AXES" in
        '' | *[!0-9]*)
            echo "MRMEGA: axes must be a non-negative integer; got '\$AXES'." >&2
            exit 1
            ;;
    esac

    # A missing or empty manifest makes MR-MEGA die inside svd() with SIGSEGV (exit 139) and no
    # message naming the manifest, so it is checked here instead.
    if [ ! -s "\$FILELIST" ]; then
        echo "MRMEGA: study manifest '\$FILELIST' is missing or empty." >&2
        exit 1
    fi

    # The incoming manifest fixes cohort order, which is the order of the Effects string, of the
    # log principal-component block and of any precalculated coordinates. Its paths belong to the
    # producing task, so rebuild it against the staged copies while preserving that order.
    : > "\$MANIFEST"
    STUDY_COUNT=0
    while IFS= read -r MANIFEST_LINE || [ -n "\$MANIFEST_LINE" ]; do
        if [ -z "\$MANIFEST_LINE" ]; then
            continue
        fi
        STAGED="studies/\$(basename "\$MANIFEST_LINE")"
        if [ ! -s "\$STAGED" ]; then
            echo "MRMEGA: manifest entry '\$MANIFEST_LINE' is not staged as '\$STAGED'." >&2
            exit 1
        fi
        case "\$STAGED" in
            *[[:space:]]*)
                echo "MRMEGA: staged study path '\$STAGED' contains whitespace; the manifest tokeniser keeps the first token only." >&2
                exit 1
                ;;
        esac
        STUDY_COUNT=\$((STUDY_COUNT + 1))
        printf '%s\\n' "\$STAGED" >> "\$MANIFEST"
    done < "\$FILELIST"

    STAGED_COUNT=\$(find studies -mindepth 1 -maxdepth 1 | wc -l)
    if [ "\$STUDY_COUNT" -ne "\$STAGED_COUNT" ]; then
        echo "MRMEGA: manifest lists \$STUDY_COUNT studies but \$STAGED_COUNT study files were staged." >&2
        exit 1
    fi
    if [ "\$STUDY_COUNT" -lt 3 ]; then
        echo "MRMEGA: MR-MEGA needs at least 3 studies; got \$STUDY_COUNT. Fewer studies exit 0 with every row flagged SmallCohortCount and every statistic NA." >&2
        exit 1
    fi

    # The native gate is `cohortCount - 2 > pc`, i.e. `pc <= K - 3`, evaluated per marker. The
    # 2017 paper's `T <= K - 2` is wrong; `pc = K - 2` exits 0 with every row SmallCohortCount and
    # no message at all.
    MAX_AXES=\$((STUDY_COUNT - 3))
    if [ "\$AXES" -lt 1 ] || [ "\$AXES" -gt "\$MAX_AXES" ]; then
        echo "MRMEGA: axes must satisfy 1 <= axes <= K - 3; got axes=\$AXES with K=\$STUDY_COUNT (maximum \$MAX_AXES). Violating this exits 0 with silent all-NA output." >&2
        exit 1
    fi

    # A precalculated manifest whose coordinate block is narrower than --pc is another silent
    # wrong answer: MR-MEGA exits 0 with every axis coefficient zero and P-value_ancestry_het nan.
    if [ -n "\$PRECALCULATED" ]; then
        awk -v axes="\$AXES" -v manifest="\$MANIFEST" '
            BEGIN {
                studies = 0
                while ((getline entry < manifest) > 0) {
                    studies++
                    sub(/^.*\\//, "", entry)
                    expected[studies] = entry
                }
            }
            {
                rows++
                if (rows > studies) {
                    printf "MRMEGA: precalculated axes file has more rows than the %d staged studies.\\n", studies > "/dev/stderr"
                    bad = 1
                    exit 1
                }
                if (NF != axes + 1) {
                    printf "MRMEGA: precalculated axes row %d has %d fields; expected a study name plus exactly %d coordinates.\\n", rows, NF, axes > "/dev/stderr"
                    bad = 1
                    exit 1
                }
                name = \$1
                sub(/^.*\\//, "", name)
                if (name != expected[rows]) {
                    printf "MRMEGA: precalculated axes row %d names %s but manifest position %d is %s; every shard must carry the same study order.\\n", rows, name, rows, expected[rows] > "/dev/stderr"
                    bad = 1
                    exit 1
                }
                line = "studies/" expected[rows]
                for (field = 2; field <= NF; field++) {
                    if (\$field !~ /^[-+]?([0-9]+[.]?[0-9]*|[.][0-9]+)([eE][-+]?[0-9]+)?\$/) {
                        printf "MRMEGA: precalculated axes row %d coordinate %d (%s) is not numeric; atof would silently read it as 0.\\n", rows, field - 1, \$field > "/dev/stderr"
                        bad = 1
                        exit 1
                    }
                    line = line " " \$field
                }
                print line
            }
            END {
                if (bad) {
                    exit 1
                }
                if (rows != studies) {
                    printf "MRMEGA: precalculated axes file has %d rows; expected one per staged study (%d).\\n", rows, studies > "/dev/stderr"
                    exit 1
                }
            }
        ' "\$PRECALCULATED" > "\$PREFIX.precalculated.in"
        mv "\$PREFIX.precalculated.in" "\$MANIFEST"
    fi

    # The effect parameterisation is a property of the study files, and mixing the two routes is a
    # clean fatal error inside MR-MEGA, so select the route from the columns that are actually
    # present and require every study to agree.
    ROUTE=''
    while IFS= read -r STAGED; do
        STUDY_PATH=\${STAGED%% *}
        FILE_ROUTE=\$(gzip -cdf "\$STUDY_PATH" | head -1 | awk '
            {
                for (field = 1; field <= NF; field++) {
                    name = toupper(\$field)
                    if (name == "BETA") { beta = 1 }
                    if (name == "SE") { se = 1 }
                    if (name == "OR") { odds = 1 }
                    if (name == "OR_95L") { lower = 1 }
                    if (name == "OR_95U") { upper = 1 }
                }
                quantitative = (beta && se)
                binary = (odds && lower && upper)
                if (quantitative && binary) { print "ambiguous" }
                else if (quantitative) { print "quantitative" }
                else if (binary) { print "binary" }
                else { print "none" }
            }')
        if [ "\$FILE_ROUTE" = 'ambiguous' ] || [ "\$FILE_ROUTE" = 'none' ]; then
            echo "MRMEGA: study file '\$STUDY_PATH' must carry either BETA and SE or OR, OR_95L and OR_95U, but not both; found '\$FILE_ROUTE'." >&2
            exit 1
        fi
        if [ -z "\$ROUTE" ]; then
            ROUTE="\$FILE_ROUTE"
        elif [ "\$ROUTE" != "\$FILE_ROUTE" ]; then
            echo "MRMEGA: study files disagree on the effect parameterisation ('\$ROUTE' versus '\$FILE_ROUTE' for '\$STUDY_PATH')." >&2
            exit 1
        fi
    done < "\$MANIFEST"

    QT_FLAG=''
    if [ "\$ROUTE" = 'quantitative' ]; then
        QT_FLAG='--qt'
    fi

    # Absolute path on purpose: /MR-MEGA is only on this image's PATH, and Apptainer and Podman do
    # not reliably preserve a non-standard image PATH.
    RC=0
    "\$MRMEGA_BIN" \\
        -i "\$MANIFEST" \\
        --pc "\$AXES" \\
        \$QT_FLAG \\
        ${precalculated_flag} \\
        -o "\$PREFIX" \\
        > mrmega.stdout 2> mrmega.stderr || RC=\$?
    cat mrmega.stdout
    cat mrmega.stderr >&2

    # Exit codes are inconsistent, so assert on completeness and content as well as on the code.
    if [ "\$RC" -ne 0 ]; then
        echo "MRMEGA: MR-MEGA exited \$RC. Exit 139 is SIGSEGV, which this binary raises for a missing manifest or when no marker is shared by every study." >&2
        exit 1
    fi
    if grep -q 'Internal problem' mrmega.stdout mrmega.stderr; then
        echo "MRMEGA: MR-MEGA reported an internal problem and still exited 0; its output is not trustworthy." >&2
        exit 1
    fi
    for REQUIRED in "\$PREFIX.result" "\$PREFIX.log"; do
        if [ ! -s "\$REQUIRED" ]; then
            echo "MRMEGA: expected output '\$REQUIRED' is missing or empty." >&2
            exit 1
        fi
    done
    if ! grep -q 'Analysis finished' "\$PREFIX.log"; then
        echo "MRMEGA: '\$PREFIX.log' does not end with 'Analysis finished'; the run was truncated." >&2
        exit 1
    fi
    if ! grep -q 'Principal components:' "\$PREFIX.log"; then
        echo "MRMEGA: '\$PREFIX.log' carries no principal-component block; study coordinates cannot be recovered." >&2
        exit 1
    fi

    awk -F'\\t' -v axes="\$AXES" '
        NR == 1 {
            expected = 20 + 2 * (axes + 1)
            if (NF != expected) {
                printf "MRMEGA: result header has %d columns; expected %d for --pc %d.\\n", NF, expected, axes > "/dev/stderr"
                bad = 1
                exit 1
            }
            if (\$1 != "MarkerName") {
                printf "MRMEGA: result header starts with %s, not MarkerName.\\n", \$1 > "/dev/stderr"
                bad = 1
                exit 1
            }
            for (column = 1; column <= NF; column++) {
                if (\$column == "ndf_association") { ndf = column }
            }
            if (!ndf) {
                print "MRMEGA: result header has no ndf_association column." > "/dev/stderr"
                bad = 1
                exit 1
            }
            next
        }
        {
            rows++
            if (NF != expected) {
                printf "MRMEGA: result row %d has %d columns; expected %d.\\n", rows, NF, expected > "/dev/stderr"
                bad = 1
                exit 1
            }
            if (\$NF == "SmallCohortCount") { small++ }
            else if (\$ndf + 0 == axes + 1) { usable++ }
        }
        END {
            if (bad) { exit 1 }
            if (rows == 0) {
                print "MRMEGA: result carries a header and no marker rows." > "/dev/stderr"
                exit 1
            }
            if (small == rows) {
                printf "MRMEGA: all %d result rows are SmallCohortCount, which is the silent signature of an axis count the study set cannot support.\\n", rows > "/dev/stderr"
                exit 1
            }
            if (usable == 0) {
                printf "MRMEGA: no result row reports ndf_association == %d, so the requested axis count was not applied.\\n", axes + 1 > "/dev/stderr"
                exit 1
            }
        }
    ' "\$PREFIX.result"

    # There is no build stamp of any kind in this image. `--version` and the log banner are both
    # compile-time constants that attest nothing about a third-party laptop build, and the image
    # carries no licence material and no source, so the pinned digest is the authoritative identity.
    SELF_REPORTED=\$("\$MRMEGA_BIN" --version 2>/dev/null | sed -n 's/.*version: *//p' | head -1)
    if [ -z "\$SELF_REPORTED" ]; then
        SELF_REPORTED='unknown'
    fi
    BANNER=\$(sed -n 's/^# MR-MEGA v[.]\\{0,1\\}//p' "\$PREFIX.log" | head -1)
    if [ -z "\$BANNER" ]; then
        BANNER='unknown'
    fi
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mrmega: "\$SELF_REPORTED (self-reported constant; log banner \$BANNER; authoritative identity ${image_reference})"
    END_VERSIONS
    """

    stub:
    prefix = task.ext.prefix ?: meta.id
    def image_reference = 'quay.io/loukas_moutsianas/mrmega@sha256:1143b7f016f00f0f32cbc6ad72b4a571e2f824e440a0b7fecf4ec4c8334ae1e8'
    def stub_axes = axes as int
    def coefficients = (0..stub_axes).collect { index -> "beta_${index}\tse_${index}" }.join('\t')
    def stub_header = [
        'MarkerName\tChromosome\tPosition\tEA\tNEA\tEAF\tNsample\tNcohort\tEffects',
        coefficients,
        'chisq_association\tndf_association\tP-value_association',
        'chisq_ancestry_het\tndf_ancestry_het\tP-value_ancestry_het',
        'chisq_residual_het\tndf_residual_het\tP-value_residual_het',
        'lnBF\tComments',
    ].join('\t')
    def stub_effects = (1..(stub_axes + 3)).collect { '+' }.join('')
    def stub_coefficients = (0..stub_axes).collect { '0\t0' }.join('\t')
    def stub_row = [
        "1:1000:A:G\t1\t1000\tA\tG\t0.25\t1000\t${stub_axes + 3}\t${stub_effects}",
        stub_coefficients,
        "0\t${stub_axes + 1}\t1",
        "0\t${stub_axes}\t1",
        '0\t2\t1',
        '0\tNA',
    ].join('\t')
    def stub_axis_names = (0..(stub_axes - 1)).collect { index -> "PC${index}" }.join(' ')
    def stub_axis_rows = (1..(stub_axes + 3))
        .collect { index -> "studies/study_${index}.txt.gz${' 0.0' * stub_axes}" }
        .join('\\n')

    """
    printf '%s\\n%s\\n' '${stub_header}' '${stub_row}' > "${prefix}.result"
    printf '###################\\n# MR-MEGA v.0.2\\n###################\\n\\nPrincipal components:\\nPCs ${stub_axis_names}\\n${stub_axis_rows}\\n\\nAnalysis finished.\\n' > "${prefix}.log"
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mrmega: "0.2 (self-reported constant; log banner 0.2; authoritative identity ${image_reference})"
    END_VERSIONS
    """
}
