# Packet F schema foundation

Status: committed, clean, and ready for all three streams.

Commit:

- `d4692ed` — `Expand samplesheet to 35-column analysis contract`

Implemented:

- Expanded the exact public input header and every shipped row from 31 to 35
  columns.
- Added, in method-family order:
  `ldak_weights`, `gcta_ld_score_region_kb`, `gcta_ld_bins`, and
  `gcta_sparse_cutoff`.
- Defaults: GCTA LD-score region `200`, LD bins `4`, sparse cutoff `0.05`;
  absent LDAK weights means equal weights.
- Kept the weights `Path` outside row settings/metadata so Packet C can derive a
  portable content digest before matrix-key construction.
- Added method-conditioned validation and tuple plumbing for the optional
  weights file.
- Enforced the exact 35-column header: a legacy 31-column header now fails at
  header row 1 naming all four missing columns. Individual cells retain their
  default/optional behavior.

TDD and validation:

- RED: utility suite ran 19 tests with the two new field/settings cases failing
  and 17 existing tests passing.
- GREEN: utility suite 19/19.
- Focused input-validation suite 27/27 during the implementation pass.
- Dedicated legacy-header regression 1/1 after exact-header enforcement.
- Schema and CSV header/rows each report exactly 35 columns in the agreed order.
- Nextflow lint checked 19 files with no errors; only two pre-existing
  normaliser unused-variable warnings remained.
- `git diff --check` passed and the worktree is clean.

Contract decision:

- The superseded 4-column input still fails earlier through nf-schema as
  `Entry 1`; the superseded 31-column input reaches and fails the explicit
  `header row 1` gate.
