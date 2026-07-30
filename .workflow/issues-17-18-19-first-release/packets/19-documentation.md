# Packet 19: Usage and output documentation

Objective: Replace obsolete user-facing documentation and satisfy every issue-19 acceptance criterion.

Context: Document only live contracts after issue 17. Include every samplesheet column, genotype
encoding exclusivity, selectors, prepared-genotype precondition, output layouts and naming grammar,
default rationales, save controls, PLINK 2 pass-through publication, and dual row-numbering behavior.

Files / sources: issue 19 and carried comments, first-release spec, schemas/assets, live
`publishDir`/`saveAs` configuration, current route outputs, reference pipeline documentation, and
documentation standards.

Ownership: The worker owns `docs/usage.md`, `docs/output.md`, `README.md`, and `CITATIONS.md` only.
Root owns tracker files, workflow artifacts, commits, and cross-packet integration edits.

Do: Ground every claim in the current tree; preserve nf-core boilerplate and required structure;
adapt to concurrent issue-18 changes without reverting them.

Do not: Edit code/config/tests, `.scratch/`, `.workflow/`, `.claude-scratch/`, or run `git commit`.

Expected output: Direct documentation edits plus a concise mapping of ticket criteria to sections.

Verification: Search for obsolete FastQ/single-end/paired-end claims, validate links/structure,
compare described directories and filenames to live publishing configuration, `git diff --check`.
