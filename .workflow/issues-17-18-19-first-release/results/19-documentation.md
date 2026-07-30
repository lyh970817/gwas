# Result: Issue 19 usage and output documentation

Accepted:

- Usage documentation describes all 35 live samplesheet columns, the three mutually exclusive
  genotype encodings, all association and heritability selectors, and the prepared-genotype
  precondition.
- Output documentation describes the live association, summary-statistics, heritability,
  relatedness, optional intermediate, MultiQC and pipeline-information layouts.
- Filename grammar, the `.gwaslab` suffix, version lookup, PLINK 2 passthrough publication and dual
  row numbering are explicit.
- Non-trivial defaults are paired with their rationales.
- README and citations now describe the first-release scientific graph; the RO-Crate description is
  synchronized to the README.

Verification:

- Both inline samplesheets parse as 35-column headers and 35-column rows.
- The usage table contains exactly 35 field rows.
- Local links and anchors, details blocks and code fences are balanced.
- No obsolete FastQ, single-end, paired-end, raw-read or FastQC claims remain.
- Documentation diff and full repository `git diff --check` are clean.

Recorded contract drift:

- The live schema has four save controls although the old specification says five.
- `sample_prevalence` is validated and retained in metadata but is not consumed by an estimator.
- The GWASLab module metadata contains an unrelated DOI, so user-facing citations use the project
  documentation link rather than propagating it.
- Validation failures do not publish a quality-control report.
