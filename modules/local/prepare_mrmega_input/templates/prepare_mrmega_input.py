#!/usr/bin/env python3
"""Turn the shared aligned study views into native MR-MEGA per-study input files.

The aligned representation emitted by GWASLAB_META_ANALYZE is authoritative: this
adapter re-labels and re-parameterises it for MR-MEGA and never re-harmonises,
re-orients or re-keys anything.

Native contract points this file exists to satisfy (MR-MEGA v0.2 source reading):

* The per-study marker key is the *name string only* and is not collision safe --
  chromosome/position mismatches are counted and then ignored -- so the emitted
  MARKERNAME is the allele-aware META_VARIANT_KEY, never the rsID.
* ``atof("NA")`` returns 0.0 and the EAF validity test is only ``0 <= eaf <= 1``,
  so a missing EAF is silently accepted as a frequency of zero. Any study that
  contributes a variant must therefore carry a usable EAF before invocation.
* Duplicate marker names inside one study file overwrite silently (the
  de-duplication map is dead code), so keys must be unique.
* Zero markers shared by every study segfaults the binary (exit 139), so an empty
  intersection is rejected here rather than downstream.
* The manifest and the per-study files are whitespace tokenised, so no emitted
  path, marker key or allele may contain whitespace.
"""

import gzip
import json
import math
import os
import sys


# 97.5th percentile of the standard normal distribution.
Z_97_5 = 1.959963984540054

# MR-MEGA reconstructs the standard error from the lower bound alone, with a
# hard-coded 1.96 rather than the exact quantile (tools.cpp:173,
# ``se = (ln(OR) - ln(OR_95L)) / 1.96``). The bounds written here are true 95%
# bounds, so the SE the binary recovers is smaller than the canonical SE by
# exactly Z_97_5 / 1.96. The bias is recorded in the adapter QC document rather
# than compensated for, because compensating would make the emitted OR_95L/OR_95U
# columns stop being confidence bounds.
NATIVE_SE_INVERSE_CONSTANT = 1.96

# Round-trip tolerance: relative for magnitudes at or above one, absolute below
# it. A pure relative bound is unreachable through exp()/log() and has nothing to
# do with how the numbers are printed: near OR = 1 the float64 grid spacing is
# 2.2e-16 in absolute terms, so a log-effect of 1e-5 cannot round-trip better
# than ~1e-11 relative even with exact shortest-round-trip decimal output.
ROUND_TRIP_TOLERANCE = 1e-12

# Native chromosome handling: integers plus X/Y/XY/MT aliases, validity tested as
# ``0 < chr < 26``. MT maps to 26 and is therefore rejected by the binary itself.
CHROMOSOME_ALIASES = {"X": 23, "Y": 24, "XY": 25, "MT": 26, "M": 26}
CHROMOSOME_MIN = 1
CHROMOSOME_MAX = 25

VIEW_LEADING_COLUMNS = ["META_VARIANT_KEY", "SNPID", "CHR", "POS", "EA", "NEA"]
VIEW_STUDY_COLUMNS = ["STATUS", "EAF", "BETA", "SE", "P", "N"]

QUANTITATIVE_HEADER = ["MARKERNAME", "EA", "NEA", "EAF", "BETA", "SE", "N", "CHROMOSOME", "POSITION"]
BINARY_HEADER = ["MARKERNAME", "EA", "NEA", "EAF", "OR", "OR_95L", "OR_95U", "N", "CHROMOSOME", "POSITION"]

MARKER_EXCLUSION_REASONS = [
    "unrepresentable_chromosome",
    "invalid_position",
    "no_contributing_study",
]


def fail(message):
    raise ValueError(message)


def open_text(path):
    with open(path, "rb") as handle:
        magic = handle.read(2)
    if magic == b"\\x1f\\x8b":
        return gzip.open(path, "rt", encoding="utf-8", newline="")
    return open(path, "rt", encoding="utf-8", newline="")


def deterministic_gzip(path):
    return gzip.GzipFile(filename="", mode="wb", fileobj=open(path, "wb"), mtime=0)


def exact(number):
    """Shortest decimal that round-trips to the identical float64."""
    return repr(float(number))


def count_text(number):
    """Sample sizes print as integers when they are integral, exactly otherwise."""
    value = float(number)
    if value.is_integer() and abs(value) < 2.0**53:
        return str(int(value))
    return repr(value)


def parse_float(text, key, study, column):
    try:
        value = float(text)
    except (TypeError, ValueError):
        fail(
            "study {} contributes marker {} with a non-numeric {} value {!r}; "
            "MR-MEGA would parse it as 0.0 and accept it silently".format(study, key, column, text)
        )
    if not math.isfinite(value):
        fail(
            "study {} contributes marker {} with a non-finite {} value {!r}; "
            "MR-MEGA propagates it as NaN at exit 0".format(study, key, column, text)
        )
    return value


def chromosome_code(raw):
    """Native code for a canonical chromosome label, or None when unrepresentable."""
    text = raw.strip()
    if text[:3].upper() == "CHR":
        text = text[3:]
    upper = text.upper()
    if upper in CHROMOSOME_ALIASES:
        code = CHROMOSOME_ALIASES[upper]
    else:
        try:
            code = int(text)
        except (TypeError, ValueError):
            return None
    if code < CHROMOSOME_MIN or code > CHROMOSOME_MAX:
        return None
    return code


def scaled_error(recovered, original):
    return abs(recovered - original) / max(abs(original), 1.0)


def relative_error(recovered, original):
    if original == 0.0:
        return abs(recovered)
    return abs(recovered - original) / abs(original)


def read_header(handle, study_count_names):
    header_line = handle.readline()
    if not header_line:
        fail("study views table is empty")
    header = header_line.rstrip("\\n").split("\\t")
    if header[: len(VIEW_LEADING_COLUMNS)] != VIEW_LEADING_COLUMNS:
        fail(
            "study views header must start with {}; found {}".format(
                " ".join(VIEW_LEADING_COLUMNS), " ".join(header[: len(VIEW_LEADING_COLUMNS)])
            )
        )
    per_study = len(header) - len(VIEW_LEADING_COLUMNS)
    if per_study <= 0 or per_study % len(VIEW_STUDY_COLUMNS) != 0:
        fail("study views header carries {} per-study columns, which is not a multiple of 6".format(per_study))
    study_count = per_study // len(VIEW_STUDY_COLUMNS)
    if study_count != study_count_names:
        fail(
            "study views table describes {} studies but {} study names were supplied".format(
                study_count, study_count_names
            )
        )
    for index in range(1, study_count + 1):
        for offset, column in enumerate(VIEW_STUDY_COLUMNS):
            position = len(VIEW_LEADING_COLUMNS) + (index - 1) * len(VIEW_STUDY_COLUMNS) + offset
            expected = "{}_{}".format(column, index)
            if header[position] != expected:
                fail("study views column {} is {!r}; expected {!r}".format(position + 1, header[position], expected))
    return study_count


def validate_study_names(names):
    if not names:
        fail("no study names were supplied")
    seen = set()
    for name in names:
        if not name:
            fail("study names must be non-empty")
        if any(character.isspace() for character in name):
            fail(
                "study name {!r} contains whitespace; the MR-MEGA manifest tokeniser keeps "
                "the first whitespace-delimited token only".format(name)
            )
        if "/" in name or name in {".", ".."}:
            fail("study name {!r} is not a usable file-name component".format(name))
        if name in seen:
            fail("study name {!r} is repeated; study identity must be unique".format(name))
        seen.add(name)


def main():
    view_path = $study_views_literal
    study_names = $study_names_literal
    trait_type = $trait_type_literal
    prefix = $prefix_literal

    if trait_type not in {"quantitative", "binary"}:
        fail("trait_type must be 'quantitative' or 'binary'; got {!r}".format(trait_type))
    validate_study_names(study_names)

    binary = trait_type == "binary"
    header = BINARY_HEADER if binary else QUANTITATIVE_HEADER

    directory = "{}.mrmega_inputs".format(prefix)
    os.makedirs(directory, exist_ok=True)
    width = max(2, len(str(len(study_names))))
    study_paths = [
        os.path.join(directory, "{}_{}.txt.gz".format(str(index + 1).zfill(width), name))
        for index, name in enumerate(study_names)
    ]
    for path in study_paths:
        if any(character.isspace() for character in path):
            fail("emitted study path {!r} contains whitespace, which the MR-MEGA manifest cannot express".format(path))

    emitted_rows = [0] * len(study_names)
    excluded_markers = dict.fromkeys(MARKER_EXCLUSION_REASONS, 0)
    excluded_study_rows = dict.fromkeys(MARKER_EXCLUSION_REASONS, 0)
    markers_input = 0
    markers_emitted = 0
    markers_intersection = 0
    max_scaled_error = 0.0
    max_relative_error = 0.0
    keys_seen = set()

    handles = [deterministic_gzip(path) for path in study_paths]
    join_map = deterministic_gzip("{}.join_map.tsv.gz".format(prefix))
    try:
        header_bytes = ("\\t".join(header) + "\\n").encode("utf-8")
        for handle in handles:
            handle.write(header_bytes)
        join_map.write(("\\t".join(VIEW_LEADING_COLUMNS) + "\\n").encode("utf-8"))

        with open_text(view_path) as source:
            study_count = read_header(source, len(study_names))
            for line in source:
                line = line.rstrip("\\n")
                if not line:
                    continue
                markers_input += 1
                fields = line.split("\\t")
                expected_fields = len(VIEW_LEADING_COLUMNS) + study_count * len(VIEW_STUDY_COLUMNS)
                if len(fields) != expected_fields:
                    fail(
                        "study views row {} has {} fields; expected {}".format(
                            markers_input, len(fields), expected_fields
                        )
                    )
                key, snpid, chromosome_raw, position_raw, effect_allele, other_allele = fields[
                    : len(VIEW_LEADING_COLUMNS)
                ]
                if key in keys_seen:
                    fail(
                        "META_VARIANT_KEY {!r} occurs more than once; MR-MEGA silently overwrites "
                        "a repeated marker name with the later record".format(key)
                    )
                keys_seen.add(key)
                for label, value in (
                    ("META_VARIANT_KEY", key),
                    ("EA", effect_allele),
                    ("NEA", other_allele),
                ):
                    if not value or any(character.isspace() for character in value):
                        fail(
                            "{} {!r} for marker {!r} is empty or contains whitespace; the MR-MEGA "
                            "tokeniser collapses runs of whitespace and cannot express it".format(label, value, key)
                        )

                # Presence is decided before any value check so that a marker the
                # native tool cannot represent at all is excluded and counted
                # rather than raising on its contents.
                present = [
                    index
                    for index in range(study_count)
                    if not all(
                        slot == "NA"
                        for slot in fields[
                            len(VIEW_LEADING_COLUMNS)
                            + index * len(VIEW_STUDY_COLUMNS) : len(VIEW_LEADING_COLUMNS)
                            + (index + 1) * len(VIEW_STUDY_COLUMNS)
                        ]
                    )
                ]

                code = chromosome_code(chromosome_raw)
                if code is None:
                    excluded_markers["unrepresentable_chromosome"] += 1
                    excluded_study_rows["unrepresentable_chromosome"] += len(present)
                    continue
                try:
                    position = int(position_raw)
                except (TypeError, ValueError):
                    position = 0
                if position <= 0:
                    excluded_markers["invalid_position"] += 1
                    excluded_study_rows["invalid_position"] += len(present)
                    continue

                contributions = []
                for index in present:
                    base = len(VIEW_LEADING_COLUMNS) + index * len(VIEW_STUDY_COLUMNS)
                    slots = fields[base : base + len(VIEW_STUDY_COLUMNS)]
                    study = study_names[index]
                    _status, eaf_raw, beta_raw, se_raw, _p_raw, n_raw = slots
                    frequency = parse_float(eaf_raw, key, study, "EAF")
                    effect = parse_float(beta_raw, key, study, "BETA")
                    error = parse_float(se_raw, key, study, "SE")
                    size = parse_float(n_raw, key, study, "N")
                    if not 0.0 < frequency < 1.0:
                        fail(
                            "study {} contributes marker {} with EAF {!r}, which is outside the open "
                            "interval (0, 1); MR-MEGA parses a missing EAF as exactly 0.0 and accepts "
                            "it, so an in-band 0 or 1 cannot be distinguished from that failure".format(
                                study, key, eaf_raw
                            )
                        )
                    if error <= 0.0:
                        fail("study {} contributes marker {} with a non-positive SE {!r}".format(study, key, se_raw))
                    if size <= 0.0:
                        fail("study {} contributes marker {} with a non-positive N {!r}".format(study, key, n_raw))
                    contributions.append((index, frequency, effect, error, size))

                if not contributions:
                    excluded_markers["no_contributing_study"] += 1
                    continue

                for index, frequency, effect, error, size in contributions:
                    if binary:
                        odds = math.exp(effect)
                        lower = math.exp(effect - Z_97_5 * error)
                        upper = math.exp(effect + Z_97_5 * error)
                        for label, value in (("OR", odds), ("OR_95L", lower), ("OR_95U", upper)):
                            if not math.isfinite(value) or value <= 0.0:
                                fail(
                                    "study {} marker {} has a log effect that is not representable as "
                                    "{} (BETA {!r}, SE {!r})".format(
                                        study_names[index], key, label, effect, error
                                    )
                                )
                        recovered_effect = math.log(odds)
                        recovered_error = (math.log(upper) - math.log(lower)) / (2.0 * Z_97_5)
                        for recovered, original in (
                            (recovered_effect, effect),
                            (recovered_error, error),
                        ):
                            max_scaled_error = max(max_scaled_error, scaled_error(recovered, original))
                            max_relative_error = max(max_relative_error, relative_error(recovered, original))
                        effect_fields = [exact(odds), exact(lower), exact(upper)]
                    else:
                        effect_fields = [exact(effect), exact(error)]
                    row = [key, effect_allele, other_allele, exact(frequency)]
                    row += effect_fields
                    row += [count_text(size), str(code), str(position)]
                    handles[index].write(("\\t".join(row) + "\\n").encode("utf-8"))
                    emitted_rows[index] += 1

                join_map.write(
                    (
                        "\\t".join([key, snpid, chromosome_raw, str(position), effect_allele, other_allele]) + "\\n"
                    ).encode("utf-8")
                )
                markers_emitted += 1
                if len(contributions) == study_count:
                    markers_intersection += 1
    finally:
        join_map.close()
        for handle in handles:
            handle.close()

    if binary and max_scaled_error > ROUND_TRIP_TOLERANCE:
        fail(
            "odds-ratio round trip lost precision: max scaled error {!r} exceeds {!r}".format(
                max_scaled_error, ROUND_TRIP_TOLERANCE
            )
        )
    if markers_emitted == 0:
        fail("no marker survived adaptation; MR-MEGA segfaults on an empty study set")
    if markers_intersection == 0:
        fail(
            "no marker is shared by all {} studies; MR-MEGA dies with "
            "'Internal problem: matrix with no rows in svd()' and SIGSEGV (exit 139)".format(len(study_names))
        )

    with open("{}.filelist.txt".format(prefix), "w", encoding="utf-8", newline="\\n") as filelist:
        for path in study_paths:
            filelist.write(path + "\\n")

    report = {
        "schema_version": "1.0",
        "trait_type": trait_type,
        "study_count": len(study_names),
        "markers_input": markers_input,
        "markers_emitted": markers_emitted,
        "markers_union": markers_emitted,
        "markers_intersection": markers_intersection,
        "study_rows_emitted_total": sum(emitted_rows),
        "studies": [
            {
                "study_index": index + 1,
                "study_name": study_names[index],
                "study_file": study_paths[index],
                "rows_emitted": emitted_rows[index],
            }
            for index in range(len(study_names))
        ],
        "excluded_markers": dict(excluded_markers),
        "excluded_study_rows": dict(excluded_study_rows),
        "or_round_trip_max_scaled_error": max_scaled_error if binary else None,
        "or_round_trip_max_relative_error": max_relative_error if binary else None,
        "or_round_trip_tolerance": ROUND_TRIP_TOLERANCE if binary else None,
        "or_confidence_quantile": Z_97_5 if binary else None,
        "native_se_inverse_constant": NATIVE_SE_INVERSE_CONSTANT if binary else None,
        "native_se_relative_bias": (Z_97_5 / NATIVE_SE_INVERSE_CONSTANT) - 1.0 if binary else None,
    }
    with open("{}.adapter_qc.json".format(prefix), "w", encoding="utf-8", newline="\\n") as handle:
        json.dump(report, handle, sort_keys=True, indent=2)
        handle.write("\\n")

    with open("versions.yml", "w", encoding="utf-8", newline="\\n") as versions:
        versions.write('"$task.process":\\n')
        versions.write("    python: {}\\n".format(sys.version.split()[0]))


if __name__ == "__main__":
    sys.exit(main())
