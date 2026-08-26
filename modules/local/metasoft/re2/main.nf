process METASOFT_RE2 {
    tag "${meta.id}"
    label 'process_medium'

    // METASOFT is not packaged in Bioconda, so there is no `conda` directive and no environment.yml.
    // The image bakes in Metasoft.jar and HanEskinPvalueTable.txt; nothing is fetched at runtime.
    // Redistribution permission from the author is recorded in
    // /usr/share/doc/metasoft/REDISTRIBUTION-PERMISSION.md inside the image.
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'docker://ghcr.io/lyh970817/metasoft@sha256:29dfc8a85266582cf5a05039c41b90d3003b3e06920fa010ed3a20268027c2f3'
        : 'ghcr.io/lyh970817/metasoft@sha256:29dfc8a85266582cf5a05039c41b90d3003b3e06920fa010ed3a20268027c2f3'}"

    input:
    tuple val(meta), path(effect_matrix)

    output:
    tuple val(meta), path("${prefix}.metasoft.txt"), emit: native_result
    tuple val(meta), path("${prefix}.re2.tsv.gz"), emit: re2
    tuple val(meta), path("${prefix}.metasoft.log"), emit: log
    path "versions.yml", emit: versions, topic: versions

    script:
    prefix = task.ext.prefix ?: meta.id
    def heap = task.memory ? (task.memory.toMega() * 0.8).intValue() : 3072
    """
    set -eu

    # Preflight. METASOFT accepts a partial BETA/SE pair silently: it drops that study and emits a row
    # bit-identical to a correctly paired `NA NA` row, so the corruption cannot be detected downstream.
    # Every structural property the native tool will not check is therefore checked here first.
    awk '
        BEGIN { studies = 0; rows = 0; bad = 0 }
        /^[ \\t]/ {
            printf "row %d begins with whitespace, which METASOFT fails on with an uncaught exception\\n", NR > "/dev/stderr"
            bad = 1
            exit 1
        }
        {
            if (NF < 5 || NF % 2 == 0) {
                printf "row %d has %d fields; expected an identifier plus one BETA/SE pair per study\\n", NR, NF > "/dev/stderr"
                bad = 1
                exit 1
            }
            k = (NF - 1) / 2
            if (studies == 0) { studies = k }
            if (k != studies) {
                printf "row %d declares %d studies but row 1 declared %d\\n", NR, k, studies > "/dev/stderr"
                bad = 1
                exit 1
            }
            if (seen[\$1]++) {
                printf "duplicate variant key %s at row %d; the join contract requires unique keys\\n", \$1, NR > "/dev/stderr"
                bad = 1
                exit 1
            }
            contributing = 0
            for (i = 1; i <= k; i++) {
                b = \$(2 * i)
                s = \$(2 * i + 1)
                bna = (b == "NA" || b == "N/A")
                sna = (s == "NA" || s == "N/A")
                if (bna != sna) {
                    printf "row %d study %d has a partial BETA/SE pair (%s %s); absence must be the paired NA NA\\n", NR, i, b, s > "/dev/stderr"
                    bad = 1
                    exit 1
                }
                if (!bna) {
                    if (b !~ /^[+-]?([0-9]+\\.?[0-9]*|\\.[0-9]+)([eE][+-]?[0-9]+)?\$/ || s !~ /^[+-]?([0-9]+\\.?[0-9]*|\\.[0-9]+)([eE][+-]?[0-9]+)?\$/) {
                        printf "row %d study %d has a non-numeric BETA/SE pair (%s %s)\\n", NR, i, b, s > "/dev/stderr"
                        bad = 1
                        exit 1
                    }
                    if (s + 0 <= 0) {
                        printf "row %d study %d has a non-positive SE (%s)\\n", NR, i, s > "/dev/stderr"
                        bad = 1
                        exit 1
                    }
                    contributing++
                }
            }
            if (contributing < 1) {
                printf "row %d has no contributing study\\n", NR > "/dev/stderr"
                bad = 1
                exit 1
            }
            rows++
        }
        END {
            if (bad) { exit 1 }
            if (rows == 0) { print "the effect matrix is empty" > "/dev/stderr"; exit 1 }
            # The Han-Eskin probability table covers 2..50 studies. At 51 the correction ratio jumps from
            # about 0.61 to exactly 1.000 with no warning, shifting RE2 p-values roughly 1.6x
            # anti-conservative, so this is a hard refusal rather than a note in the log.
            if (studies > 50) {
                printf "%d studies exceeds the 50 covered by the Han-Eskin probability table\\n", studies > "/dev/stderr"
                bad = 1
                exit 1
            }
            if (studies < 2) { printf "%d studies is not a meta-analysis\\n", studies > "/dev/stderr"; exit 1 }
            printf "%d %d\\n", studies, rows > "preflight.txt"
        }
    ' "${effect_matrix}"

    STUDIES=\$(cut -d' ' -f1 preflight.txt)
    ROWS=\$(cut -d' ' -f2 preflight.txt)

    # RE2 needs no flag: FE, RE and RE2 are always computed. Only binary effects and m-values are opt-in
    # and both stay off. No native argument is exposed to the caller.
    JAVA_TOOL_OPTIONS="-Xmx${heap}M" metasoft \\
        -input "${effect_matrix}" \\
        -output "${prefix}.metasoft.txt" \\
        -log "${prefix}.metasoft.log"

    # METASOFT's exit codes are not trustworthy: it leaves truncated output behind at 255, returns 255
    # with a good output when only the log is unwritable, and throws at exit 1 on leading whitespace.
    # Completeness is therefore asserted from the output itself.
    awk -v studies="\$STUDIES" -v rows="\$ROWS" '
        NR == 1 { next }
        {
            expected = 16 + 2 * studies
            # Every data row is terminated with a tab, so a tab-separated read reports one trailing
            # empty field that the header does not have. Drop it before checking the width.
            n = NF
            if (n > 0 && \$n == "") { n-- }
            if (n != expected) {
                printf "output row %d has %d fields; expected %d for %d studies\\n", NR, n, expected, studies > "/dev/stderr"
                bad = 1
                exit 1
            }
            seen++
        }
        END {
            if (bad) { exit 1 }
            if (seen != rows) {
                printf "METASOFT wrote %d result rows for %d input rows\\n", seen, rows > "/dev/stderr"
                exit 1
            }
        }
    ' FS='\\t' "${prefix}.metasoft.txt"

    # Normalise. Columns 9/10/11 are PVALUE_RE2, STAT1_RE2, STAT2_RE2; 10 and 11 are statistics whose sum is
    # the Han-Eskin statistic, not p-values. The FE/RE columns are carried as numerical validation checks and
    # are labelled as such; they are not a published result family.
    awk 'BEGIN {
            FS = "\\t"
            OFS = "\\t"
            print "META_VARIANT_KEY", "P_RE2", "RE2_MEAN_COMPONENT", "RE2_HET_COMPONENT", "RE2_STATUS",
                  "METASOFT_N_STUDIES", "METASOFT_P_FE", "METASOFT_BETA_FE", "METASOFT_SE_FE",
                  "METASOFT_P_RE", "METASOFT_BETA_RE", "METASOFT_SE_RE",
                  "METASOFT_I_SQUARE", "METASOFT_Q", "METASOFT_P_Q", "METASOFT_TAU_SQUARE"
        }
        NR == 1 { next }
        {
            p = \$9
            status = "ok"
            # A tail below about 1e-307 is written as the literal string 0.00000. That is IEEE double
            # underflow, not a probability, and is reachable through heterogeneity alone. Never publish it
            # as zero.
            if (p == "0.00000" || p + 0 == 0) { status = "underflow"; p = "NA" }
            else if (p ~ /[Nn][Aa][Nn]/) { status = "nan"; p = "NA" }
            print \$1, p, \$10, \$11, status, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$13, \$14, \$15, \$16
        }
    ' "${prefix}.metasoft.txt" | gzip -n -c > "${prefix}.re2.tsv.gz"

    rm -f preflight.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        metasoft: \$(metasoft --version)
        busybox: \$(busybox 2>&1 | head -n 1 | sed 's/^BusyBox v//; s/ .*//')
    END_VERSIONS
    """

    stub:
    prefix = task.ext.prefix ?: meta.id
    """
    printf 'RSID\t#STUDY\tPVALUE_FE\tBETA_FE\tSTD_FE\tPVALUE_RE\tBETA_RE\tSTD_RE\tPVALUE_RE2\tSTAT1_RE2\tSTAT2_RE2\tPVALUE_BE\tI_SQUARE\tQ\tPVALUE_Q\tTAU_SQUARE\tPVALUES_OF_STUDIES(Tab_delimitered)\tMVALUES_OF_STUDIES(Tab_delimitered)\\n' \\
        > "${prefix}.metasoft.txt"
    printf 'META_VARIANT_KEY\tP_RE2\tRE2_MEAN_COMPONENT\tRE2_HET_COMPONENT\tRE2_STATUS\tMETASOFT_N_STUDIES\tMETASOFT_P_FE\tMETASOFT_BETA_FE\tMETASOFT_SE_FE\tMETASOFT_P_RE\tMETASOFT_BETA_RE\tMETASOFT_SE_RE\tMETASOFT_I_SQUARE\tMETASOFT_Q\tMETASOFT_P_Q\tMETASOFT_TAU_SQUARE\\n' \\
        | gzip -n -c > "${prefix}.re2.tsv.gz"
    printf 'stub\\n' > "${prefix}.metasoft.log"
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        metasoft: \$(metasoft --version)
        busybox: \$(busybox 2>&1 | head -n 1 | sed 's/^BusyBox v//; s/ .*//')
    END_VERSIONS
    """
}
