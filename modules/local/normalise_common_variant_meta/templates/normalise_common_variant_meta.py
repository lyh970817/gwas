#!/usr/bin/env python3
"""Normalise one common-variant meta-analysis into a single candidate table and a complete derivation.

Canonical BETA/SE/P always mean the GWASLab fixed-effect result and are passed through verbatim. Optional
Han-Eskin RE2 and MR-MEGA results are joined on META_VARIANT_KEY only. Every MR-MEGA P value is recomputed
unconditionally from its chi-square statistic and degrees of freedom in log space, because the native values
are known to be wrong in the deep tail; the native values survive only as debug provenance.
"""

import csv
import gzip
import json
import math
import sys
from pathlib import Path

META_ANALYSIS = Path(${meta_analysis_literal})
STUDY_ORDER = Path(${study_order_literal})
QC = Path(${qc_literal})
UPSTREAM_DERIVATION = Path(${upstream_derivation_literal})
RE2 = ${re2_literal}
MRMEGA = ${mrmega_literal}
PREFIX = ${prefix_literal}

SCHEMA_VERSION = "1.0"
LN10 = math.log(10.0)

# 10 ** -307 is the smallest power of ten that is still a normal IEEE double. Below it a linear P value is
# not representable, so the linear column is written as NA rather than as a fabricated zero.
SMALLEST_REPRESENTABLE_LOG10P = -307.0

KEY = "META_VARIANT_KEY"

BASE_COLUMNS = [
    "SNPID",
    "CHR",
    "POS",
    "EA",
    "NEA",
    "STATUS",
    "EAF",
    "BETA",
    "SE",
    "P",
    "N",
    "N_STUDIES",
    "DIRECTION",
    "EAF_META",
    "EAF_MIN",
    "EAF_MAX",
    "N_TOTAL",
    "MAX_WEIGHT_SHARE",
    "Z_FIXED",
    "Q",
    "P_HET",
    "I2",
]
RANDOM_COLUMNS = ["BETA_RANDOM", "SE_RANDOM", "Z_RANDOM", "P_RANDOM", "TAU2_RANDOM"]
RE2_PUBLISHED_COLUMNS = ["P_RE2", "RE2_MEAN_COMPONENT", "RE2_HET_COMPONENT", "RE2_STATUS"]

# METASOFT's own fixed- and random-effect estimates are a numerical cross-check against GWASLab, not a
# published result family. They are summarised in the derivation and never reach the candidate table.
METASOFT_VALIDATION_COLUMNS = [
    "METASOFT_P_FE",
    "METASOFT_BETA_FE",
    "METASOFT_SE_FE",
    "METASOFT_P_RE",
    "METASOFT_BETA_RE",
    "METASOFT_SE_RE",
    "METASOFT_I_SQUARE",
    "METASOFT_Q",
    "METASOFT_P_Q",
    "METASOFT_TAU_SQUARE",
]

MRMEGA_TESTS = ["ASSOC", "ANCESTRY_HET", "RESIDUAL_HET"]
MRMEGA_SOURCE_COLUMNS = (
    ["MRMEGA_CHISQ_" + test for test in MRMEGA_TESTS]
    + ["MRMEGA_DF_" + test for test in MRMEGA_TESTS]
    + ["MRMEGA_NATIVE_P_" + test for test in MRMEGA_TESTS]
    + ["MRMEGA_LNBF"]
)
MRMEGA_PUBLISHED_COLUMNS = []
for _test in MRMEGA_TESTS:
    MRMEGA_PUBLISHED_COLUMNS += [
        "MRMEGA_CHISQ_" + _test,
        "MRMEGA_DF_" + _test,
        "MRMEGA_LOG10P_" + _test,
        "MRMEGA_P_" + _test,
    ]
MRMEGA_PUBLISHED_COLUMNS += ["MRMEGA_LNBF"]

MISSING = "NA"
UNMATCHED_EXAMPLE_LIMIT = 10


def fail(message):
    sys.exit("[nf-core/gwas] ERROR: normalise_common_variant_meta '{}': {}".format(PREFIX, message))


def chi2_logsf(statistic, degrees_of_freedom):
    """Natural log of the chi-square upper tail, computed entirely in log space.

    Returns log Q(k/2, x/2) for the regularized upper incomplete gamma function Q, or None when the inputs
    cannot define a tail probability. The continued-fraction branch never forms the linear tail probability,
    so results such as log10 P = -1617.87 stay exact where a linear recomputation underflows to zero.
    """
    try:
        x = float(statistic)
        k = float(degrees_of_freedom)
    except (TypeError, ValueError):
        return None
    if not math.isfinite(x) or not math.isfinite(k) or k <= 0.0:
        return None
    if x <= 0.0:
        return 0.0
    a = k / 2.0
    z = x / 2.0
    if z < a + 1.0:
        # Shallow tail: the lower regularized series converges quickly and Q = 1 - P is well conditioned.
        term = 1.0
        total = 1.0
        for n in range(1, 100000):
            term *= z / (a + n)
            total += term
            if abs(term) <= abs(total) * 1e-18:
                break
        else:
            return None
        log_lower = -z + a * math.log(z) - math.lgamma(a + 1.0) + math.log(total)
        lower = math.exp(log_lower)
        if lower >= 1.0:
            return -math.inf
        return math.log1p(-lower)
    # Deep tail: modified Lentz evaluation of the continued fraction for Q itself.
    tiny = 1e-300
    b = z + 1.0 - a
    c = 1.0 / tiny
    d = 1.0 / b if abs(b) >= tiny else 1.0 / tiny
    h = d
    for i in range(1, 100000):
        numerator = -i * (i - a)
        b += 2.0
        d = numerator * d + b
        if abs(d) < tiny:
            d = tiny
        c = b + numerator / c
        if abs(c) < tiny:
            c = tiny
        d = 1.0 / d
        delta = d * c
        h *= delta
        if abs(delta - 1.0) <= 1e-17:
            break
    else:
        return None
    return -z + a * math.log(z) - math.lgamma(a) + math.log(h)


def chi2_log10sf(statistic, degrees_of_freedom):
    natural = chi2_logsf(statistic, degrees_of_freedom)
    if natural is None:
        return None
    return natural / LN10


def parse_number(text):
    if text is None:
        return None
    cleaned = text.strip()
    if cleaned == "" or cleaned.upper() in {"NA", "NAN", "N/A", "."}:
        return None
    try:
        value = float(cleaned)
    except ValueError:
        return None
    return value if math.isfinite(value) else None


def format_log10p(value):
    return MISSING if value is None or not math.isfinite(value) else "{:.6f}".format(value)


def linear_from_log10p(value):
    if value is None or not math.isfinite(value) or value < SMALLEST_REPRESENTABLE_LOG10P:
        return MISSING
    return "{:.6e}".format(10.0**value)


def open_text(path):
    with path.open("rb") as handle:
        is_gzip = handle.read(2) == b"\\x1f\\x8b"
    if is_gzip:
        return gzip.open(path, "rt", encoding="utf-8", newline="")
    return path.open("rt", encoding="utf-8", newline="")


def read_table(path, label, required_columns):
    with open_text(path) as handle:
        reader = csv.reader(handle, delimiter="\\t")
        try:
            header = next(reader)
        except StopIteration:
            return fail("{} table '{}' is empty".format(label, path.name))
        repeated = sorted({column for column in header if header.count(column) > 1})
        if repeated:
            fail("{} table '{}' repeats columns: {}".format(label, path.name, ", ".join(repeated)))
        missing = [column for column in required_columns if column not in header]
        if missing:
            fail(
                "{} table '{}' is missing required columns: {}".format(label, path.name, ", ".join(missing))
            )
        rows = []
        for number, row in enumerate(reader, start=2):
            if len(row) != len(header):
                fail(
                    "{} table '{}' row {} has {} fields; expected {}".format(
                        label, path.name, number, len(row), len(header)
                    )
                )
            rows.append(dict(zip(header, row)))
    return header, rows


def read_json(path, label):
    try:
        with path.open("rt", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError) as error:
        return fail("{} document '{}' is not readable JSON: {}".format(label, path.name, error))


def index_by_key(rows, label):
    index = {}
    duplicates = []
    for row in rows:
        key = row[KEY]
        if key in index:
            duplicates.append(key)
            continue
        index[key] = row
    if duplicates:
        sys.stderr.write(
            "[nf-core/gwas] WARNING: {} input repeats {} {} value(s); the first occurrence is used\\n".format(
                label, len(duplicates), KEY
            )
        )
    return index, sorted(set(duplicates))


def relative_difference(observed, reference):
    if observed is None or reference is None or reference == 0.0:
        return None
    return abs(observed - reference) / abs(reference)


def new_validation_accumulator():
    return {"maximum": None, "rows_compared": 0, "rows_skipped": 0}


def accumulate_validation(accumulator, observed, reference):
    difference = relative_difference(observed, reference)
    if difference is None:
        accumulator["rows_skipped"] += 1
        return
    accumulator["rows_compared"] += 1
    if accumulator["maximum"] is None or difference > accumulator["maximum"]:
        accumulator["maximum"] = difference


def new_native_accumulator():
    return {
        "rows_with_parseable_native_value": 0,
        "rows_without_parseable_native_value": 0,
        "native_minimum": None,
        "native_maximum": None,
        "rows_native_not_positive": 0,
        "rows_native_exactly_one": 0,
        "rows_native_off_by_more_than_one_order_of_magnitude": 0,
        "rows_recomputed": 0,
    }


def accumulate_native(accumulator, native_text, log10p):
    if log10p is not None:
        accumulator["rows_recomputed"] += 1
    native = parse_number(native_text)
    if native is None:
        accumulator["rows_without_parseable_native_value"] += 1
        return
    accumulator["rows_with_parseable_native_value"] += 1
    if accumulator["native_minimum"] is None or native < accumulator["native_minimum"]:
        accumulator["native_minimum"] = native
    if accumulator["native_maximum"] is None or native > accumulator["native_maximum"]:
        accumulator["native_maximum"] = native
    if native <= 0.0:
        accumulator["rows_native_not_positive"] += 1
    if native == 1.0:
        accumulator["rows_native_exactly_one"] += 1
    if native > 0.0 and log10p is not None and math.isfinite(log10p):
        if abs(math.log10(native) - log10p) > 1.0:
            accumulator["rows_native_off_by_more_than_one_order_of_magnitude"] += 1


def main():
    required_meta_columns = BASE_COLUMNS + [KEY]
    meta_header, meta_rows = read_table(META_ANALYSIS, "meta-analysis", required_meta_columns)

    present_random = [column for column in RANDOM_COLUMNS if column in meta_header]
    if present_random and len(present_random) != len(RANDOM_COLUMNS):
        fail(
            "meta-analysis table carries a partial random-effects block; found {} but require all of {}".format(
                ", ".join(present_random), ", ".join(RANDOM_COLUMNS)
            )
        )
    random_joined = len(present_random) == len(RANDOM_COLUMNS)

    re2_joined = RE2 is not None
    re2_index = {}
    re2_rows = []
    re2_duplicates = []
    if re2_joined:
        _, re2_rows = read_table(
            Path(RE2),
            "Han-Eskin RE2",
            [KEY] + RE2_PUBLISHED_COLUMNS + METASOFT_VALIDATION_COLUMNS,
        )
        re2_index, re2_duplicates = index_by_key(re2_rows, "Han-Eskin RE2")

    mrmega_joined = MRMEGA is not None
    mrmega_index = {}
    mrmega_rows = []
    mrmega_duplicates = []
    if mrmega_joined:
        _, mrmega_rows = read_table(Path(MRMEGA), "MR-MEGA", [KEY] + MRMEGA_SOURCE_COLUMNS)
        mrmega_index, mrmega_duplicates = index_by_key(mrmega_rows, "MR-MEGA")

    columns = list(BASE_COLUMNS)
    if random_joined:
        columns += RANDOM_COLUMNS
    if re2_joined:
        columns += RE2_PUBLISHED_COLUMNS
    if mrmega_joined:
        columns += MRMEGA_PUBLISHED_COLUMNS
    columns += [KEY]

    metasoft_validation = {
        "beta_fixed": new_validation_accumulator(),
        "standard_error_fixed": new_validation_accumulator(),
        "p_fixed": new_validation_accumulator(),
    }
    native_debug = {test: new_native_accumulator() for test in MRMEGA_TESTS}

    matched_keys_re2 = set()
    matched_keys_mrmega = set()
    rows_missing_re2 = 0
    rows_missing_mrmega = 0

    candidate_name = "{}.candidate.tsv.gz".format(PREFIX)
    with open(candidate_name, "wb") as raw_output:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw_output, mtime=0) as handle:
            handle.write(("\\t".join(columns) + "\\n").encode("utf-8"))
            for row in meta_rows:
                key = row[KEY]
                # Passed-through columns keep the upstream numeric text byte for byte; reparsing and
                # reformatting a {:.6e} value is a silent precision hazard.
                fields = [row[column] for column in BASE_COLUMNS]
                if random_joined:
                    fields += [row[column] for column in RANDOM_COLUMNS]

                if re2_joined:
                    record = re2_index.get(key)
                    if record is None:
                        rows_missing_re2 += 1
                        fields += [MISSING] * len(RE2_PUBLISHED_COLUMNS)
                    else:
                        matched_keys_re2.add(key)
                        fields += [record[column] for column in RE2_PUBLISHED_COLUMNS]
                        accumulate_validation(
                            metasoft_validation["beta_fixed"],
                            parse_number(row["BETA"]),
                            parse_number(record["METASOFT_BETA_FE"]),
                        )
                        accumulate_validation(
                            metasoft_validation["standard_error_fixed"],
                            parse_number(row["SE"]),
                            parse_number(record["METASOFT_SE_FE"]),
                        )
                        accumulate_validation(
                            metasoft_validation["p_fixed"],
                            parse_number(row["P"]),
                            parse_number(record["METASOFT_P_FE"]),
                        )

                if mrmega_joined:
                    record = mrmega_index.get(key)
                    if record is None:
                        rows_missing_mrmega += 1
                        fields += [MISSING] * len(MRMEGA_PUBLISHED_COLUMNS)
                    else:
                        matched_keys_mrmega.add(key)
                        for test in MRMEGA_TESTS:
                            chisq_text = record["MRMEGA_CHISQ_" + test]
                            df_text = record["MRMEGA_DF_" + test]
                            # Unconditional recomputation: the native P value is never consulted here.
                            log10p = chi2_log10sf(parse_number(chisq_text), parse_number(df_text))
                            accumulate_native(
                                native_debug[test], record["MRMEGA_NATIVE_P_" + test], log10p
                            )
                            fields += [
                                chisq_text,
                                df_text,
                                format_log10p(log10p),
                                linear_from_log10p(log10p),
                            ]
                        fields += [record["MRMEGA_LNBF"]]

                fields += [key]
                handle.write(("\\t".join(fields) + "\\n").encode("utf-8"))

    meta_keys = {row[KEY] for row in meta_rows}
    re2_unmatched = sorted({row[KEY] for row in re2_rows} - meta_keys)
    mrmega_unmatched = sorted({row[KEY] for row in mrmega_rows} - meta_keys)

    _, study_order_rows = read_table(STUDY_ORDER, "study order", ["study_index", "study_name"])

    derivation = {
        "schema_version": SCHEMA_VERSION,
        "operation": "normalise_common_variant_meta",
        "prefix": PREFIX,
        "upstream": {
            "derivation": read_json(UPSTREAM_DERIVATION, "upstream derivation"),
            "qc": read_json(QC, "upstream QC"),
            "study_order": study_order_rows,
        },
        "models": {
            "fixed": True,
            "random": random_joined,
            "re2_joined": re2_joined,
            "mrmega_joined": mrmega_joined,
        },
        "join_contract": "META_VARIANT_KEY is the only join key; rsID and SNPID are never used to join",
        "join_counts": {
            "meta_analysis_rows": len(meta_rows),
            "re2_rows": len(re2_rows),
            "re2_rows_matched": len(matched_keys_re2),
            "re2_rows_unmatched": len(re2_unmatched),
            "re2_unmatched_key_examples": re2_unmatched[:UNMATCHED_EXAMPLE_LIMIT],
            "re2_duplicate_keys": len(re2_duplicates),
            "meta_analysis_rows_without_re2": rows_missing_re2,
            "mrmega_rows": len(mrmega_rows),
            "mrmega_rows_matched": len(matched_keys_mrmega),
            "mrmega_rows_unmatched": len(mrmega_unmatched),
            "mrmega_unmatched_key_examples": mrmega_unmatched[:UNMATCHED_EXAMPLE_LIMIT],
            "mrmega_duplicate_keys": len(mrmega_duplicates),
            "meta_analysis_rows_without_mrmega": rows_missing_mrmega,
        },
        "mrmega_native_p_debug": {
            "kind": "debug_provenance",
            "note": (
                "Native MR-MEGA P values are recorded here only. Every published MR-MEGA P value is "
                "recomputed unconditionally from its chi-square statistic and degrees of freedom, because "
                "the native values are unreliable for df != 2 and collapse to 1.0 in the deep tail."
            ),
            "recomputation": "unconditional",
            "tests": native_debug,
        },
        "metasoft_validation": {
            "kind": "validation_check",
            "note": (
                "Maximum absolute relative difference between the GWASLab fixed-effect result and "
                "METASOFT's own fixed-effect result over joined rows. These are numerical cross-checks "
                "only; METASOFT FE and RE estimates are never published in the candidate table. Rows whose "
                "METASOFT reference value is missing or exactly zero are skipped, because METASOFT "
                "underflows small tails to a literal zero."
            ),
            "comparisons": metasoft_validation,
        },
        "canonical_contract": (
            "BETA, SE and P are the GWASLab fixed-effect result, passed through unchanged. No other model's "
            "effect size or P value is ever written into them."
        ),
        "mrmega_p_contract": (
            "MRMEGA_LOG10P_* is the authoritative always-populated column. MRMEGA_P_* is derived from it and "
            "written only when log10 P >= {:.0f}, otherwise NA; an underflowed P is never written as 0.".format(
                SMALLEST_REPRESENTABLE_LOG10P
            )
        ),
        "published_float_format": "{:.6e} for newly computed linear values, {:.6f} for log10 scale values",
        "passthrough_contract": "upstream numeric text is copied verbatim and never reparsed or reformatted",
        "candidate_columns": columns,
        "python_version": sys.version.split()[0],
        "outputs": {
            "candidate": candidate_name,
            "derivation": "{}.derivation.json".format(PREFIX),
        },
    }

    with open("{}.derivation.json".format(PREFIX), "w", encoding="utf-8") as handle:
        json.dump(derivation, handle, sort_keys=True, indent=2)
        handle.write("\\n")

    with open("versions.yml", "w", encoding="utf-8") as handle:
        handle.write('"$task.process":\\n')
        handle.write("    python: {}\\n".format(sys.version.split()[0]))


if __name__ == "__main__":
    sys.exit(main())
