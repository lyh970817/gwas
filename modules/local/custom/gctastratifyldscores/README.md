# LD-by-MAF stratification

This module owns the R template `templates/gcta_stratify_ldscores.R`. It runs with
R 4.2.1 and does not depend on pipeline metadata, method names, or a matrix builder.
The template is versioned independently as `gcta_stratify_ldscores` 1.0.0.

Input is a whitespace-delimited GCTA LD-score table with `SNP`, `freq`, and
`ldscore_SNP` columns. The caller supplies a positive LD quantile-bin count and
strictly increasing MAF boundaries covering the selected predictors. MAF is
`min(freq, 1 - freq)`. LD boundaries use R type-7 quantiles. Intervals include their
lower boundary and exclude their upper boundary, except for the final interval on
each axis, which includes both boundaries. Empty groups are omitted.

Two tab-delimited tables reference the same one-SNP-per-line text files:

- `<prefix>.strata.tsv`: `model_key`, `stratum_key`, `ld_lower`, `ld_upper`,
  `maf_lower`, `maf_upper`, `predictor_count`, `group_filename`. This is the full
  scientific provenance; `model_key` is `ldms`.
- `<prefix>.groups.tsv`: `group_id`, `group_filename`. `group_id` equals
  `stratum_key`; this table is the generic matrix-builder input.

Both tables have identical LD-major, MAF-minor row order. Names have the form
`ld01_maf01`. Group files partition the scored variants; they do not imply that
GCTA retained every variant in the original genotype bundle. The caller retains
the full provenance when it passes the generic table to a matrix builder.
