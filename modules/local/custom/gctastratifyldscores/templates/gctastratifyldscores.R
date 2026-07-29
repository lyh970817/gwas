#!/usr/bin/env Rscript

input_file <- "$ld_scores"
output_prefix <- "$prefix"
ld_bin_value <- suppressWarnings(as.numeric("$ld_bins"))
maf_boundaries <- c(${maf_edges.join(',')})

fail <- function(message) stop(message, call. = FALSE)
format_bound <- function(value) format(signif(value, 8), scientific = FALSE, trim = TRUE)

if (length(ld_bin_value) != 1L || !is.finite(ld_bin_value) || ld_bin_value < 1L || ld_bin_value != floor(ld_bin_value)) {
  fail("ld_bins must be one positive integer")
}
ld_bin_count <- as.integer(ld_bin_value)

if (length(maf_boundaries) < 2L || any(!is.finite(maf_boundaries))) {
  fail("maf_edges must contain at least two finite numeric boundaries")
}
if (any(diff(maf_boundaries) <= 0)) fail("maf_edges must be strictly increasing")
if (any(maf_boundaries < 0 | maf_boundaries > 0.5)) fail("maf_edges must be between 0 and 0.5")

scores <- read.table(input_file, header = TRUE, check.names = FALSE, stringsAsFactors = FALSE)
required_columns <- c("SNP", "freq", "ldscore_SNP")
missing_columns <- setdiff(required_columns, colnames(scores))
if (length(missing_columns) > 0L) {
  fail(paste("LD-score input is missing required columns:", paste(missing_columns, collapse = ", ")))
}

ld_scores <- scores\$ldscore_SNP
maf <- pmin(scores\$freq, 1 - scores\$freq)
if (any(!is.finite(ld_scores)) || any(!is.finite(maf) | maf < 0 | maf > 0.5)) {
  fail("LD scores and frequencies must be finite with MAF between 0 and 0.5")
}

ld_boundaries <- as.numeric(quantile(
  ld_scores,
  probs = seq(0, 1, length.out = ld_bin_count + 1L),
  names = FALSE,
  type = 7
))

manifest_rows <- list()
row_index <- 1L
assignment_count <- integer(nrow(scores))

for (ld_index in seq_len(ld_bin_count)) {
  ld_lower <- ld_boundaries[ld_index]
  ld_upper <- ld_boundaries[ld_index + 1L]
  ld_member <- ld_scores >= ld_lower & if (ld_index == ld_bin_count) ld_scores <= ld_upper else ld_scores < ld_upper

  for (maf_index in seq_len(length(maf_boundaries) - 1L)) {
    maf_lower <- maf_boundaries[maf_index]
    maf_upper <- maf_boundaries[maf_index + 1L]
    maf_member <- maf >= maf_lower & if (maf_index == length(maf_boundaries) - 1L) maf <= maf_upper else maf < maf_upper
    member <- ld_member & maf_member
    assignment_count <- assignment_count + as.integer(member)
    predictor_count <- sum(member)
    if (predictor_count == 0L) next

    stratum_key <- sprintf("ld%02d_maf%02d", ld_index, maf_index)
    group_filename <- sprintf("%s_snp_group_%s.txt", output_prefix, stratum_key)
    writeLines(as.character(scores\$SNP[member]), group_filename)

    manifest_rows[[row_index]] <- data.frame(
      model_key = "ldms",
      stratum_key = stratum_key,
      ld_lower = format_bound(ld_lower),
      ld_upper = format_bound(ld_upper),
      maf_lower = format_bound(maf_lower),
      maf_upper = format_bound(maf_upper),
      predictor_count = predictor_count,
      group_filename = group_filename,
      stringsAsFactors = FALSE
    )
    row_index <- row_index + 1L
  }
}

if (any(assignment_count != 1L)) fail("Each predictor must be assigned to exactly one stratum")
if (length(manifest_rows) == 0L) fail("No non-empty strata produced; check ld_bins and maf_edges")

manifest <- do.call(rbind, manifest_rows)
write.table(manifest, paste0(output_prefix, ".strata.tsv"), sep = "\t", quote = FALSE, row.names = FALSE)

version_lines <- c(
  paste0('"$task.process":'),
  paste0("    r-base: ", as.character(getRversion()))
)
writeLines(version_lines, "versions.yml")
