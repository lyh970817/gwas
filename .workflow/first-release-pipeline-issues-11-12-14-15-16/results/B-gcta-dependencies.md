# Packet B dependency preparation

Status: committed and clean; waiting for F schema foundation before route
implementation.

Commits:

- `e0a69ad` — `Install the GCTA fastGWA module`
- `77ba817` — `Vendor GCTA LDMS preparation components`

Source provenance:

- `gcta/fastgwa` installed with nf-core pipeline mechanics and pinned in
  `modules.json` to upstream revision
  `b5e95182ba240127c1c78f33d405a35fe0fc5302`.
- LDMS composition and custom helpers vendored from committed sibling revision
  `ffb2b4d4220644c704e5fac83193e9024f192a39`, not the sibling checkout's dirty
  working tree. The source revision is recorded in the commit message.
- Helper files are byte-identical to the named source. The pipeline-local LDMS
  subworkflow differs only for local include paths, purpose header, and removal
  of an incompatible legacy versions helper/emit.

Evidence:

- `nextflow lint` passed for all three new production `main.nf` files.
- `git diff --check` passed.
- `nf-core modules lint gcta/fastgwa`: 56 passed, zero failed, one upstream
  missing-containers warning.
- Pipeline lint: 388 passed; five generated container-config failures and
  existing warnings were recorded for later integrated triage.

Next:

- Integrate the F foundation commit, then implement Issues 14 and 15 route
  slices and their route-level tests.
