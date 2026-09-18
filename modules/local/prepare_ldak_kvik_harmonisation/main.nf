// GWASLab requires effect-allele frequency and effective N; the native association table's MAF is not EAF.
// Join A1Freq and n from the native summary table so harmonisation publishes the correct frequency and sample size.
process PREPARE_LDAK_KVIK_HARMONISATION {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/../ldak/kvikstep2/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/c9/c94e5424f08cbd7e0856ab3c3a9992b4080944a5d0c497ce0abcceb413db4a3e/data'
        : 'community.wave.seqera.io/library/ldak6_r-base:452828f72b3c9129'}"

    input:
    tuple val(meta), path(association_files), path(summary_files)

    output:
    tuple val(meta), path('*.harmonisation.tsv'), emit: harmonisation_input
    tuple val("${task.process}"), val("awk"), eval("awk -W version 2>&1 | head -n 1 | grep -oE '[0-9]+([.][0-9]+)+' | head -n 1"), emit: versions_awk, topic: versions

    script:
    def associations = association_files instanceof List ? association_files : [association_files]
    def assoc_paths = associations.collect { assoc -> '"' + assoc + '"' }.join(' ')
    """
    for assoc in ${assoc_paths}; do
        summary="\${assoc%.assoc}.summaries"
        harmonisation_input="\${assoc%.assoc}.harmonisation.tsv"
        awk '
            BEGIN { FS = OFS = "\\t" }
            NR == FNR {
                if (FNR == 1) {
                    for (i = 1; i <= NF; i++) {
                        if (\$i == "Predictor") summary_predictor = i
                        if (\$i == "A1") summary_a1 = i
                        if (\$i == "A2") summary_a2 = i
                        if (\$i == "n") summary_n = i
                        if (\$i == "A1Freq") summary_a1freq = i
                    }
                    next
                }
                key = \$summary_predictor SUBSEP \$summary_a1 SUBSEP \$summary_a2
                if (key in sample_count) {
                    print "Duplicate Predictor+A1+A2 key in LDAK-KVIK summary table: " \$summary_predictor, \$summary_a1, \$summary_a2 > "/dev/stderr"
                    exit 1
                }
                sample_count[key] = \$summary_n
                effect_allele_frequency[key] = \$summary_a1freq
                next
            }
            FNR == 1 {
                for (i = 1; i <= NF; i++) {
                    header[i] = \$i
                    if (\$i == "Predictor") association_predictor = i
                    if (\$i == "A1") association_a1 = i
                    if (\$i == "A2") association_a2 = i
                }
                first = 1
                for (i = 1; i <= NF; i++) {
                    if (\$i != "Wald_Stat" && \$i != "MAF") {
                        printf "%s%s", (first ? "" : OFS), \$i
                        first = 0
                    }
                }
                print OFS "EAF" OFS "N"
                next
            }
            {
                key = \$association_predictor SUBSEP \$association_a1 SUBSEP \$association_a2
                if (key in seen_association) {
                    print "Duplicate Predictor+A1+A2 key in LDAK-KVIK association table: " \$association_predictor, \$association_a1, \$association_a2 > "/dev/stderr"
                    exit 1
                }
                seen_association[key] = 1
                if (!(key in sample_count)) {
                    print "No LDAK-KVIK summary row for Predictor+A1+A2 key: " \$association_predictor, \$association_a1, \$association_a2 > "/dev/stderr"
                    exit 1
                }
                first = 1
                for (i = 1; i <= NF; i++) {
                    if (header[i] != "Wald_Stat" && header[i] != "MAF") {
                        printf "%s%s", (first ? "" : OFS), \$i
                        first = 0
                    }
                }
                print OFS effect_allele_frequency[key] OFS sample_count[key]
            }
            END {
                if (!association_predictor) {
                    exit 1
                }
                for (key in sample_count) {
                    if (!(key in seen_association)) {
                        print "LDAK-KVIK summary key has no association row" > "/dev/stderr"
                        exit 1
                    }
                }
            }
        ' "\${summary}" "\${assoc}" > "\${harmonisation_input}"
    done
    """

    stub:
    def associations = association_files instanceof List ? association_files : [association_files]
    def outputs = associations.collect { assoc -> '"' + assoc.baseName + '.harmonisation.tsv"' }.join(' ')
    """
    touch ${outputs}
    """
}
