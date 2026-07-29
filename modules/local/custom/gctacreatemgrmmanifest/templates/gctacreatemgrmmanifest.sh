#!/usr/bin/env bash

for grm_id in *.grm.id; do
    echo "\${grm_id%.grm.id}"
done | sort -V > "${prefix}.mgrm"

cat <<-END_VERSIONS > versions.yml
"${task.process}":
    coreutils: \$(cat --version | head -n 1 | cut -d ' ' -f 4)
END_VERSIONS
