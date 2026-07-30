# Packet A implementation result

Status: complete, committed, focused-green, and ready for integration.

Committed:

- `6b944a3` — Issue 11 REGENIE route.
- `ca8ab79` — Issue 12 LDAK-KVIK route.
- `d4e1942` — adapt both association routes to the 35-column contract.

Shared-equivalent commits in the stream branch:

- `62d9f81` and `4da2ca8` are local cherry-pick equivalents of shared commits
  `17bafd73` and `146b0cda`.
- `62e54a7` is the stream's resolved equivalent of foundation `d4692ed`.
- Integration should land the original shared commits once and then apply only
  the three association-specific commits above.

Issue 11 evidence:

- Focused Docker route suite passed 3/3.
- Covers standard Step 1 + Step 2 + GWASLab, predictions absent by default,
  no hidden `minMAC`, all 22 fixture autosomes, chunked
  split/run-L0/run-L1 with saved predictions, and binary/Firth behavior.
- Schema lint, Nextflow lint, and `git diff --check` passed; only the two
  pre-existing normaliser unused-variable warnings remained.

Issue 12 progress:

- Focused Docker route suite passed 4/4 for `all`, `thin_common`, provided
  extract, and binary mapping.
- Input-validation exposed and the stream fixed a mixed-sheet strict-join bug
  by filtering the phenotype channel to KVIK before the fail-on-mismatch join.
- Shared default-sheet/snapshot reconciliation is integration-owned so the
  default test profile remains light as required by Issue 18.

Final combined evidence:

- Exact-35-column REGENIE suite: 3/3.
- Exact-35-column KVIK suite: 4/4.
- Combined focused run: 7/7 in 167.332 seconds.
- Mandatory 35-column contract: 1/1.
- Earlier shared PLINK 1 seam: 3/3.
- Earlier association/default compatibility: 15/15.
- Schema lint passed with 44 parameters.
- Complete Nextflow lint covered all 55 tracked `.nf` files with no errors and
  only pre-existing unused-variable warnings.
- Both dedicated samplesheets have exactly 35 fields in header and data row.
- `git diff --check` and final worktree cleanliness passed.
