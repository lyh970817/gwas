# Packet F: Public row-contract foundation

Packet ID: F-schema-foundation

Objective: Expand the first-release samplesheet contract once, from 31 to 35
columns, so the three implementation streams share one authoritative parsing
and validation foundation.

Owned fields:

- `gcta_ld_score_region_kb`
- `gcta_ld_bins`
- `gcta_sparse_cutoff`
- `ldak_weights`

Ownership: public input schema, example samplesheet, pipeline schema
description/count, shared field parsing/defaults, method-conditioned validation,
and focused input/function tests.

Do: work red to green at the public input and utility seams; preserve portable
file handling; provide Packet C enough normalized information to derive
weights-file content identity; document migration impact; commit the foundation
in isolation.

Do not: implement route-specific GCTA/LDAK matrix keys, use basename or absolute
path as weights identity, touch association routing, stage main-checkout
untracked files, or push.

Expected output: a committed schema foundation that B and C can integrate before
their schema-dependent slices.
