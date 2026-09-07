#!/usr/bin/env python3
"""Write the one multi-column phenotype file a REGENIE fit batch shares.

REGENIE fits and tests every column named by `--phenoColList` in a single invocation, and splits its
Step 2 results into one file per column, named after the column. Batching compatible analyses into one
invocation therefore needs a phenotype file whose columns are named by `analysis_id`, so every native
output can be attributed back to the analysis that asked for it.

Each input is one member's prepared phenotype, written by `PREPARE_PHENOTYPE_INPUTS` in the canonical
`FID IID PHENO` layout with `NA` for a missing value. The columns are re-headed with the members'
analysis identifiers and merged into one table.

The merge asserts the property the batch key already claims: every member covers the same samples and
the same non-missing samples. It is not a formality. REGENIE mean-imputes missing observations across
the whole invocation, so a member whose missingness differs from its batch-mates would be fitted
against a different sample set than it would be alone, and the batched result for that member would
stop reproducing the per-analysis result. Measured on regenie 4.1.2: a trait with 20 missing samples
gave BETA 0.0623 fitted alone and 0.0736 batched with a complete sibling, while the complete sibling
was unchanged. So an unequal batch is a wrong answer, not an inefficiency, and it stops here.

Standard library only, deliberately: the inputs run to a few thousand rows at most, so a dataframe
dependency would add container weight and a second version to report for no gain.
"""

import sys

# Interpolated as JSON literals, which are valid Python syntax.
PHENOTYPE_FILES = ${phenotype_files_literal}
ANALYSIS_IDS = ${analysis_ids_literal}
PREFIX = ${prefix_literal}
BATCH_ID = ${batch_id_literal}
PROCESS_NAME = ${task_process_literal}

MISSING = "NA"

# The layout `PREPARE_PHENOTYPE_INPUTS` writes, and the only layout this module accepts. The trait
# always lands in the third column under the constant name PHENO, which is what makes the members
# positionally mergeable at all.
EXPECTED_HEADER = ["FID", "IID", "PHENO"]

# Keep a mismatch message useful without allowing an unbounded one.
MAX_REPORTED_SAMPLES = 10


def fail(message):
    """Abort naming the batch, so the failing member can be found without bisecting the run."""
    sys.exit("[nf-core/gwas] ERROR: REGENIE batch '{}': {}".format(BATCH_ID, message))


def read_member(analysis_id, path):
    """Read one member's prepared phenotype, rejecting anything but the canonical layout."""
    with open(path) as handle:
        rows = [line.rstrip("\\r\\n").split("\\t") for line in handle]
    rows = [row for row in rows if any(field.strip() for field in row)]
    if not rows:
        fail("analysis '{}' phenotype '{}' is empty".format(analysis_id, path))

    header = rows[0]
    body = rows[1:]
    if header != EXPECTED_HEADER:
        fail(
            "analysis '{}' phenotype '{}' must carry the header {}, but carries {}".format(
                analysis_id, path, " ".join(EXPECTED_HEADER), " ".join(header) or "nothing"
            )
        )
    for number, row in enumerate(body, start=2):
        if len(row) != len(EXPECTED_HEADER):
            fail(
                "analysis '{}' phenotype '{}' line {} carries {} fields, expected {}".format(
                    analysis_id, path, number, len(row), len(EXPECTED_HEADER)
                )
            )

    samples = []
    values = {}
    for row in body:
        identity = (row[0], row[1])
        if identity in values:
            fail(
                "analysis '{}' phenotype '{}' declares sample '{} {}' more than once".format(
                    analysis_id, path, row[0], row[1]
                )
            )
        samples.append(identity)
        values[identity] = row[2]
    return samples, values


def describe(samples):
    """Render a bounded sample list for a mismatch message."""
    displayed = sorted(samples)[:MAX_REPORTED_SAMPLES]
    elided = len(samples) - len(displayed)
    rendered = ", ".join("{} {}".format(fid, iid) for fid, iid in displayed)
    return "{}{}".format(rendered, "; {} further omitted".format(elided) if elided else "")


if len(PHENOTYPE_FILES) != len(ANALYSIS_IDS):
    fail(
        "the caller staged {} phenotype file(s) for {} analysis identifier(s); the two are paired "
        "positionally and must have the same length".format(len(PHENOTYPE_FILES), len(ANALYSIS_IDS))
    )

reference_samples, reference_values = read_member(ANALYSIS_IDS[0], PHENOTYPE_FILES[0])
reference_present = set(reference_samples)
reference_observed = set(sample for sample in reference_samples if reference_values[sample] != MISSING)

columns = [reference_values]
for analysis_id, path in list(zip(ANALYSIS_IDS, PHENOTYPE_FILES))[1:]:
    _samples, values = read_member(analysis_id, path)
    present = set(values)
    observed = set(sample for sample in values if values[sample] != MISSING)
    if present != reference_present:
        fail(
            "analysis '{}' covers {} sample(s) but batch member '{}' covers {}; a batch shares one "
            "phenotype file, so every member must cover the same samples. Only in '{}': {}. Only in "
            "'{}': {}".format(
                analysis_id,
                len(present),
                ANALYSIS_IDS[0],
                len(reference_present),
                analysis_id,
                describe(present - reference_present) or "none",
                ANALYSIS_IDS[0],
                describe(reference_present - present) or "none",
            )
        )
    if observed != reference_observed:
        fail(
            "analysis '{}' has {} non-missing observation(s) but batch member '{}' has {}; REGENIE "
            "mean-imputes missing observations across the whole invocation, so members whose "
            "missingness differs must not share one fit. Only in '{}': {}. Only in '{}': {}".format(
                analysis_id,
                len(observed),
                ANALYSIS_IDS[0],
                len(reference_observed),
                analysis_id,
                describe(observed - reference_observed) or "none",
                ANALYSIS_IDS[0],
                describe(reference_observed - observed) or "none",
            )
        )
    columns.append(values)

# Rows keep the first member's order and every value is written through verbatim: this module renames
# and merges columns, it never recodes a trait.
lines = ["\\t".join(["FID", "IID"] + ANALYSIS_IDS)]
for sample in reference_samples:
    lines.append("\\t".join([sample[0], sample[1]] + [column[sample] for column in columns]))

with open("{}.pheno".format(PREFIX), "w", newline="\\n") as handle:
    handle.write("\\n".join(lines) + "\\n")

# Written here rather than captured by an `eval` output, which Nextflow allows only on a Bash script.
with open("versions.yml", "w", newline="\\n") as handle:
    handle.write('"{}":\\n    python: {}\\n'.format(PROCESS_NAME, sys.version.split()[0]))
