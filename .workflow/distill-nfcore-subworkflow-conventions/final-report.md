# Final report

The companion-library survey covered naming/layout, public contracts/metadata, composition/versioning, and tests/configuration in parallel. The integrated guidance was added to the shared nf-core common rules, subworkflow creation workflow, component design gate, and submission review checklist. A separate review found five overstatements; all were corrected.

The pipeline GCTA constructors were renamed to the format-first contracts `plink_prepare_grm_gcta` and `plink_prepare_grm_ldms_gcta`. Targeted Nextflow lint/config checks and four real/stub Docker route tests passed. The dirty companion checkout was not modified.
