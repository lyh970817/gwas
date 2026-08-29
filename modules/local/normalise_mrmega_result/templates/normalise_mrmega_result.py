#!/usr/bin/env python3
"""Map the native MR-MEGA result table into the keyed schema the normalizer accepts.

This is a pure column mapping and deliberately computes nothing. `MarkerName` already IS the
`META_VARIANT_KEY`, because PREPARE_MRMEGA_INPUT wrote the allele-aware key into it rather
than an rsID, so no key is re-derived and no join is attempted on a name.

Two native contract points drive the whole file:

* The result column count is `20 + 2(T+1)` and therefore moves with `--pc`, so every source
  column is located by name in the header. Reading by position would silently shift the
  meaning of every statistic the moment the axis count changed.
* The three `P-value_*` columns are carried through only as `MRMEGA_NATIVE_P_*`, for debug
  provenance. They are numerically invalid whenever the corresponding `ndf` is not 2 -- the
  native tail saturates to exactly 1.0 on a real top hit and goes negative in between -- and
  which of the three happens to be sound flips with `--pc` and the study count. The downstream
  normalizer therefore discards all three unconditionally and recomputes the tail in log
  space. Nothing here recomputes them and nothing here publishes them as a result.

A row whose `Comments` says `SmallCohortCount` or `collinear` is not a usable result. The
former is the per-marker `pc <= Ncohort - 3` gate, which the binary applies silently at exit 0;
the latter is the regression's own refusal. Passing either row's numbers through would publish
garbage that looks like an answer, so every chi-square, degree of freedom and Bayes factor on
such a row is written as NA and counted.
"""

import gzip
import json
import sys

KEY_COLUMN = "MarkerName"
COMMENTS_COLUMN = "Comments"

# Native source column -> emitted column, in emitted order. The emitted set is exactly
# NORMALISE_COMMON_VARIANT_META's MRMEGA_SOURCE_COLUMNS, prefixed by the key.
FIELD_MAP = [
    ("chisq_association", "MRMEGA_CHISQ_ASSOC"),
    ("chisq_ancestry_het", "MRMEGA_CHISQ_ANCESTRY_HET"),
    ("chisq_residual_het", "MRMEGA_CHISQ_RESIDUAL_HET"),
    ("ndf_association", "MRMEGA_DF_ASSOC"),
    ("ndf_ancestry_het", "MRMEGA_DF_ANCESTRY_HET"),
    ("ndf_residual_het", "MRMEGA_DF_RESIDUAL_HET"),
    ("P-value_association", "MRMEGA_NATIVE_P_ASSOC"),
    ("P-value_ancestry_het", "MRMEGA_NATIVE_P_ANCESTRY_HET"),
    ("P-value_residual_het", "MRMEGA_NATIVE_P_RESIDUAL_HET"),
    ("lnBF", "MRMEGA_LNBF"),
]

REQUIRED_COLUMNS = [KEY_COLUMN, COMMENTS_COLUMN] + [source for source, _ in FIELD_MAP]

CHISQ_COLUMNS = [
    ("assoc", "chisq_association"),
    ("ancestry_het", "chisq_ancestry_het"),
    ("residual_het", "chisq_residual_het"),
]

# Documented unusable-result flags. Anything else in Comments is reported, not acted on.
UNUSABLE_COMMENTS = ["SmallCohortCount", "collinear"]

MISSING = "NA"
MISMATCH_EXAMPLE_LIMIT = 10


def fail(message):
    raise ValueError(message)


def open_text(path):
    with open(path, "rb") as handle:
        compressed = handle.read(2) == b"\\x1f\\x8b"
    if compressed:
        return gzip.open(path, "rt", encoding="utf-8", newline="")
    return open(path, "rt", encoding="utf-8", newline="")


def finite(text):
    """Parse a native numeric field, returning None for NA, non-numeric text and non-finite values."""
    try:
        value = float(text)
    except (TypeError, ValueError):
        return None
    if value != value or value in (float("inf"), float("-inf")):
        return None
    return value


def integral(text):
    value = finite(text)
    if value is None or not float(value).is_integer():
        return None
    return int(value)


def main():
    result_path = json.loads(r'''$result_literal''')
    axes_text = json.loads(r'''$axes_literal''')
    prefix = json.loads(r'''$prefix_literal''')

    try:
        axes = int(str(axes_text).strip())
    except (TypeError, ValueError):
        return fail("axes must be an integer; got {!r}".format(axes_text))
    if axes < 0:
        fail("axes must not be negative; got {}".format(axes))

    emitted = ["META_VARIANT_KEY"] + [target for _, target in FIELD_MAP]

    rows_read = 0
    rows_usable = 0
    nulled = dict.fromkeys(UNUSABLE_COMMENTS, 0)
    unexpected_comments = {}
    duplicate_keys = 0
    seen_keys = set()
    # ndf_association == axes + 1 and ndf_ancestry_het == axes are fixed identities. There is no
    # identity to check on ndf_residual_het, which is Ncohort - axes - 1 on the per-marker
    # Ncohort and so legitimately varies row to row; its observed range is reported instead.
    mismatches = {"assoc": 0, "ancestry_het": 0}
    mismatch_examples = []
    residual_df = {"min": None, "max": None}
    chisq_range = {name: {"min": None, "max": None} for name, _ in CHISQ_COLUMNS}
    non_finite_chisq = dict.fromkeys([name for name, _ in CHISQ_COLUMNS], 0)

    with open_text(result_path) as source:
        first = source.readline()
        if not first:
            fail("the MR-MEGA result table is empty; it must carry a header line")
        header = first.rstrip("\\n").split("\\t")
        repeated = sorted({column for column in header if header.count(column) > 1})
        if repeated:
            fail(
                "the MR-MEGA result header repeats columns, so a source value cannot be located "
                "unambiguously: {}".format(", ".join(repeated))
            )
        missing = [column for column in REQUIRED_COLUMNS if column not in header]
        if missing:
            fail(
                "the MR-MEGA result header is missing required columns: {}".format(
                    ", ".join(missing)
                )
            )
        index = {column: position for position, column in enumerate(header)}

        with open("{}.mrmega_fields.tsv.gz".format(prefix), "wb") as raw:
            with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as output:
                output.write(("\\t".join(emitted) + "\\n").encode("utf-8"))
                for line in source:
                    line = line.rstrip("\\n")
                    if not line:
                        continue
                    rows_read += 1
                    fields = line.split("\\t")
                    if len(fields) != len(header):
                        fail(
                            "MR-MEGA result row {} has {} fields; expected {}".format(
                                rows_read, len(fields), len(header)
                            )
                        )
                    key = fields[index[KEY_COLUMN]]
                    if not key:
                        fail("MR-MEGA result row {} has an empty MarkerName".format(rows_read))
                    if key in seen_keys:
                        duplicate_keys += 1
                    seen_keys.add(key)

                    comment = fields[index[COMMENTS_COLUMN]].strip()
                    unusable = comment in UNUSABLE_COMMENTS
                    if unusable:
                        nulled[comment] += 1
                    elif comment and comment != MISSING:
                        unexpected_comments[comment] = unexpected_comments.get(comment, 0) + 1

                    if unusable:
                        output.write(
                            ("\\t".join([key] + [MISSING] * len(FIELD_MAP)) + "\\n").encode("utf-8")
                        )
                        continue

                    rows_usable += 1
                    values = [fields[index[source_column]] for source_column, _ in FIELD_MAP]
                    output.write(("\\t".join([key] + values) + "\\n").encode("utf-8"))

                    for name, source_column in CHISQ_COLUMNS:
                        statistic = finite(fields[index[source_column]])
                        if statistic is None:
                            non_finite_chisq[name] += 1
                            continue
                        bounds = chisq_range[name]
                        if bounds["min"] is None or statistic < bounds["min"]:
                            bounds["min"] = statistic
                        if bounds["max"] is None or statistic > bounds["max"]:
                            bounds["max"] = statistic

                    for name, source_column, expected in (
                        ("assoc", "ndf_association", axes + 1),
                        ("ancestry_het", "ndf_ancestry_het", axes),
                    ):
                        observed = integral(fields[index[source_column]])
                        if observed != expected:
                            mismatches[name] += 1
                            if len(mismatch_examples) < MISMATCH_EXAMPLE_LIMIT:
                                mismatch_examples.append(
                                    {
                                        "key": key,
                                        "column": source_column,
                                        "expected": expected,
                                        "observed": fields[index[source_column]],
                                    }
                                )

                    residual = integral(fields[index["ndf_residual_het"]])
                    if residual is not None:
                        if residual_df["min"] is None or residual < residual_df["min"]:
                            residual_df["min"] = residual
                        if residual_df["max"] is None or residual > residual_df["max"]:
                            residual_df["max"] = residual

    if rows_read == 0:
        fail(
            "the MR-MEGA result table carries a header but no data row; an empty result is "
            "never a valid meta-regression"
        )

    report = {
        "schema_version": "1.0",
        "request": prefix,
        "axes": axes,
        "rows_read": rows_read,
        "rows_usable": rows_usable,
        # Additive with rows_usable: every row read is either usable or nulled by a comment.
        "rows_nulled": nulled,
        "rows_nulled_total": sum(nulled.values()),
        "unexpected_comments": unexpected_comments,
        "duplicate_keys": duplicate_keys,
        "df_identity_expected": {"assoc": axes + 1, "ancestry_het": axes},
        "df_identity_mismatches": mismatches,
        "df_identity_mismatch_examples": mismatch_examples,
        "residual_df_range": residual_df,
        "chisq_range": chisq_range,
        "non_finite_chisq": non_finite_chisq,
        # Recorded so a reader can see that the native P values leave here as debug provenance
        # only; the downstream normalizer discards all three and recomputes in log space.
        "native_p_columns_carried": [
            target for source, target in FIELD_MAP if source.startswith("P-value_")
        ],
        "columns": emitted,
    }
    with open("{}.mrmega_qc.json".format(prefix), "w", encoding="utf-8") as handle:
        json.dump(report, handle, sort_keys=True, indent=2)
        handle.write("\\n")

    with open("versions.yml", "w", encoding="utf-8") as handle:
        handle.write('"$task.process":\\n')
        handle.write("    python: {}\\n".format(sys.version.split()[0]))


if __name__ == "__main__":
    sys.exit(main())
