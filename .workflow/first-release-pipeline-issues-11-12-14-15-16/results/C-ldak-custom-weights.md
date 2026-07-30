# Packet C custom-weight result

Status: complete, committed, focused-green, reviewed, and ready for integration.

Core commits:

- `172e8ce` — equal/default-weight LDAK REML route.
- `2e0f39c` — custom LDAK weights keyed by content.
- `4628b71` — address all route Standards/spec review findings.
- `1fe7c97` — apply uniform stub scenarios to every real LDAK route scenario.
- `e029033` is Packet C's resolved equivalent of foundation `d4692ed`; do not
  duplicate it in integration.

Custom-weight evidence:

- Utility functions: 22/22.
- LDAK matrix route: 4/4.
- Liability/publication: 1/1.
- Same bytes at different paths produced one CALCKINS build with key
  `2be27b8074df`.
- Different bytes with the same basename produced two builds with keys
  `2be27b8074df` and `d75cd202b48d`.
- Equal mode generates `--ignore-weights`; supplied mode generates `--weights`.

Review remediation:

- Added independent model-only and power-only route forks.
- Corrected custom-weight documentation to content-SHA identity.
- Fixed test config banner/resources/metadata, missing declarations,
  multi-input composition, assertion grouping, route-input exception/config
  documentation, and explicit stub policy.
- Added global-stub topology scenarios for matrix and REML route composition.
- Re-review required the repository's uniform stub model, so the final test-only
  follow-up pairs five real scenarios with five corresponding `-stub` variants.
  All five stubs plus a representative real regression passed; real assertions
  remain intact and stub assertions are limited to success, topology, output
  tree, and file existence.
- Focused function shards, real matrix/REML scenarios, stub scenarios,
  lint/format, pre-commit, and diff checks passed.
- An initial test-only 15 GB resource ceiling was corrected to the repository's
  8 GB test cap and the affected scenarios passed.
- Spec re-review passed with no findings; Standards' final uniform-stub finding
  is addressed by `1fe7c97`.
