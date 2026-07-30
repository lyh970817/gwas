# Packet B GCTA matrix-family result

Status: complete, committed, focused-green, and ready for integration.

GCTA-specific commits:

- `e0a69ad46fced3cea67b722978c5c3f0b5414893` — install official fastGWA.
- `77ba8175d545603ba15df1334c0d681948636ca3` — vendor LDMS preparation.
- `44d1e13` — vendor the repaired pipeline-local fastGWA MLM component.
- `bd5677a` — wire GREML-LDMS and fastGWA routes.
- `4189cbb` — snapshot route software versions.
- `375478f` — refresh generated container configurations.

Integration notes:

- Omit `375478f` initially and regenerate container configurations once after all
  streams are integrated.
- The branch's `8483bb4`, `5454d27`, and `66d1463` are local equivalents of
  shared commits `d4692ed`, `17bafd73`, and `146b0cda`; do not duplicate them.
- `44d1e13` supersedes the earlier amended hash `f029aa8`.

Implemented:

- Separate matrix families `gcta_dense`, `gcta_ldms`, and `gcta_sparse`.
- LDMS reuse keys include region, bins, and parsed MAF boundaries; sparse keys
  include cutoff; `gcta_grm_parts` remains an outside-key operational control.
- Differing LD-bin counts correctly produce distinct builds.
- LDMS consumes the one shared lazy PLINK 1 derivative, calculates/stratifies
  LD scores, constructs ordered stratum matrices/MGRM manifest, and routes
  GREML-LDMS through the existing heritability composition.
- fastGWA is invoked inline, preserves focal analysis identity, accepts staged
  sparse sidecars, exposes only MLM/MLM-binary flags, publishes native output,
  and feeds GWASLab with populated `N`.
- The official installed module remains registry-clean at upstream
  `b5e95182ba240127c1c78f33d405a35fe0fc5302`; the required repaired contract is
  pipeline-local from committed source
  `ffb2b4d4220644c704e5fac83193e9024f192a39`.

Evidence:

- Key utility suite: 21/21.
- fastGWA Docker suite: 3/3.
- GREML-LDMS Docker suite: 2/2.
- Combined route snapshots: 5/5.
- Existing GREML regression: 1/1.
- Explicit pre-commit and focused Nextflow lint passed; 27 files, zero errors,
  only two pre-existing normaliser warnings.
- Official installed fastGWA module lint: 56 passed, zero failed, one unchanged
  upstream container-metadata warning.
- Broad pipeline lint: 407 passed, 7 ignored, 10 existing warnings, one
  foundation-owned failure because
  `tests/input_contract_35_columns.nf.test` lacks a versions snapshot.

Binary-route follow-up:

- Real Docker coverage now includes fastGWA MLM-binary end to end.
- Live GCTA 1.94.1 output established that the native binary result reports
  `BETA` rather than `OR` and includes `N`; harmonisation therefore maps
  `beta:BETA` and `n:N`.
- The binary route verifies both the genuine native header and the canonical
  harmonised `BETA`/`N` contract. The earlier quantitative-only review boundary
  is superseded by this evidence.
