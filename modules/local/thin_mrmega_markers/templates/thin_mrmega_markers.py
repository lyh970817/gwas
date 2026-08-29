#!/usr/bin/env python3
"""Thin the aligned per-study views to the genome-wide marker set MR-MEGA pass 1 needs.

Pass 1 exists only to derive the axes of genetic variation. MR-MEGA derives them from a
deterministic 1 Mb thinning of the markers that every study contributes with a usable minor
allele frequency, so reproducing that selection here removes nothing the axes would have
used and bounds the memory of the one pass that has to hold every study at once.

The three selection rules mirror the native ones (MR-MEGA v0.2 main.cpp:309-338):

* only chromosomes 1-22 and X take part in axis derivation, because the native sweep runs
  over codes 1-23 and excludes Y, XY and MT;
* a marker qualifies only when every study contributes it with minor allele frequency above
  1 per cent, which is `allAboveMAF()` and which also requires presence in every study;
* at most one qualifying marker survives per chromosome per 1 Mb bin.

Where the native rule is "the last qualifying marker in file order wins each bin", which makes
axis derivation depend on input ordering, the winner here is the marker with the largest
minimum minor allele frequency across studies, tie-broken on the lowest position and then on
the key. That is deterministic under channel reordering and picks the marker carrying the most
frequency information for a frequency-distance axis.

Emitting an empty table is a failure, not a result: MR-MEGA dies inside svd() with SIGSEGV and
exit 139 when no marker is shared by every study, and it names neither the manifest nor the
cause, so an empty axis-derivation set has to be rejected here.
"""

import gzip
import json
import sys
from pathlib import Path

VIEW_LEADING_COLUMNS = ["META_VARIANT_KEY", "SNPID", "CHR", "POS", "EA", "NEA"]
VIEW_STUDY_COLUMNS = ["STATUS", "EAF", "BETA", "SE", "P", "N"]

# Native axis derivation sweeps chromosome codes 1-23 only. X is code 23, so both spellings
# are accepted and rank identically, after every autosome.
AXIS_CHROMOSOMES = {str(number): number for number in range(1, 23)}
AXIS_CHROMOSOMES["X"] = 23
AXIS_CHROMOSOMES["23"] = 23

BIN_WIDTH = 1000000
MAF_THRESHOLD = 0.01

# Additive by construction: every row read lands in exactly one of these or in the retained set.
DROP_REASONS = [
    "chromosome_filter",
    "incomplete_study_contribution",
    "maf_filter",
    "bin_thinning",
]


def fail(message):
    raise ValueError(message)


def open_text(path):
    with open(path, "rb") as handle:
        compressed = handle.read(2) == b"\\x1f\\x8b"
    if compressed:
        return gzip.open(path, "rt", encoding="utf-8", newline="")
    return open(path, "rt", encoding="utf-8", newline="")


def chromosome_rank(raw):
    """Axis-derivation rank for a chromosome label, or None when it takes no part."""
    text = raw.strip()
    if text[:3].upper() == "CHR":
        text = text[3:]
    return AXIS_CHROMOSOMES.get(text.upper())


def finite(text):
    """Parse a view field, returning None for NA, non-numeric text and non-finite values."""
    try:
        value = float(text)
    except (TypeError, ValueError):
        return None
    if value != value or value in (float("inf"), float("-inf")):
        return None
    return value


def parse_header(line, shard, study_count):
    header = line.rstrip("\\n").split("\\t")
    leading = len(VIEW_LEADING_COLUMNS)
    if header[:leading] != VIEW_LEADING_COLUMNS:
        fail(
            "shard {} must start with {}; found {}".format(
                shard, " ".join(VIEW_LEADING_COLUMNS), " ".join(header[:leading])
            )
        )
    per_study = len(header) - leading
    if per_study <= 0 or per_study % len(VIEW_STUDY_COLUMNS) != 0:
        fail(
            "shard {} carries {} per-study columns, which is not a multiple of {}".format(
                shard, per_study, len(VIEW_STUDY_COLUMNS)
            )
        )
    observed = per_study // len(VIEW_STUDY_COLUMNS)
    for index in range(1, observed + 1):
        for offset, column in enumerate(VIEW_STUDY_COLUMNS):
            position = leading + (index - 1) * len(VIEW_STUDY_COLUMNS) + offset
            expected = "{}_{}".format(column, index)
            if header[position] != expected:
                fail(
                    "shard {} column {} is {!r}; expected {!r}".format(
                        shard, position + 1, header[position], expected
                    )
                )
    if observed != study_count:
        fail(
            "shard {} describes {} studies but study_count is {}; the axis derivation would "
            "silently run on the wrong cohort set".format(shard, observed, study_count)
        )
    return header


def main():
    views = json.loads(r'''$views_literal''')
    study_count_text = json.loads(r'''$study_count_literal''')
    prefix = json.loads(r'''$prefix_literal''')

    try:
        study_count = int(str(study_count_text).strip())
    except (TypeError, ValueError):
        return fail("study_count must be an integer; got {!r}".format(study_count_text))
    if study_count < 1:
        fail("study_count must be at least 1; got {}".format(study_count))
    if not views:
        fail("no study-view shards were supplied; an axis-derivation set cannot be empty")

    header = None
    header_shard = None
    columns = 0
    leading = len(VIEW_LEADING_COLUMNS)

    shard_rows = []
    dropped = dict.fromkeys(DROP_REASONS, 0)
    seen_keys = set()
    # Only the current winner of each occupied bin is retained, so peak memory is bounded by
    # the number of megabase bins rather than by the number of markers read.
    winners = {}
    rows_read = 0

    for path in sorted(views, key=lambda value: Path(value).name):
        shard = Path(path).name
        rows = 0
        with open_text(path) as handle:
            first = handle.readline()
            if not first:
                fail("shard {} is empty; a shard must always carry a header".format(shard))
            shard_header = parse_header(first, shard, study_count)
            if header is None:
                header = shard_header
                header_shard = shard
                columns = len(header)
            elif shard_header != header:
                fail(
                    "shard {} has a different header from shard {}; the shards were not "
                    "produced by one compatible plan".format(shard, header_shard)
                )
            for line in handle:
                line = line.rstrip("\\n")
                if not line:
                    continue
                rows += 1
                rows_read += 1
                fields = line.split("\\t")
                if len(fields) != columns:
                    fail(
                        "shard {} row {} has {} fields; expected {}".format(
                            shard, rows, len(fields), columns
                        )
                    )
                key = fields[0]
                if key in seen_keys:
                    fail(
                        "META_VARIANT_KEY {!r} appears more than once across the shards; a "
                        "repeated marker name silently overwrites the earlier record in "
                        "MR-MEGA".format(key)
                    )
                seen_keys.add(key)

                rank = chromosome_rank(fields[2])
                if rank is None:
                    dropped["chromosome_filter"] += 1
                    continue
                try:
                    position = int(fields[3])
                except (TypeError, ValueError):
                    return fail(
                        "shard {} marker {!r} has a non-integer POS {!r}".format(
                            shard, key, fields[3]
                        )
                    )
                if position <= 0:
                    fail(
                        "shard {} marker {!r} has POS {}; MR-MEGA requires a positive "
                        "position".format(shard, key, position)
                    )

                # Presence in every study is what the native allAboveMAF() gate demands, and
                # an unusable effect estimate is the same thing as an absent study for a run
                # that has to regress on all of them.
                complete = True
                minimum_maf = None
                for index in range(study_count):
                    base = leading + index * len(VIEW_STUDY_COLUMNS)
                    frequency = finite(fields[base + 1])
                    effect = finite(fields[base + 2])
                    error = finite(fields[base + 3])
                    sample_size = finite(fields[base + 5])
                    if frequency is None or effect is None or error is None or sample_size is None:
                        complete = False
                        break
                    if error <= 0.0 or sample_size <= 0.0:
                        complete = False
                        break
                    maf = min(frequency, 1.0 - frequency)
                    if minimum_maf is None or maf < minimum_maf:
                        minimum_maf = maf
                if not complete:
                    dropped["incomplete_study_contribution"] += 1
                    continue
                if minimum_maf <= MAF_THRESHOLD:
                    dropped["maf_filter"] += 1
                    continue

                bin_index = position // BIN_WIDTH
                # Largest minimum minor allele frequency wins the bin; ties fall to the lowest
                # position and then to the key, so the choice never depends on arrival order.
                candidate = (-minimum_maf, position, key)
                slot = (rank, bin_index)
                held = winners.get(slot)
                if held is None:
                    winners[slot] = (candidate, minimum_maf, line)
                elif candidate < held[0]:
                    winners[slot] = (candidate, minimum_maf, line)
                    dropped["bin_thinning"] += 1
                else:
                    dropped["bin_thinning"] += 1
        shard_rows.append({"shard": shard, "input_rows": rows})

    if not winners:
        fail(
            "no marker survived thinning, so pass 1 would receive an empty manifest; MR-MEGA "
            "dies inside svd() with SIGSEGV and exit 139 on an empty marker intersection, so "
            "this is reported here instead"
        )

    retained = sorted(
        (
            (slot[0], entry[0][1], entry[0][2], entry[1], entry[2])
            for slot, entry in winners.items()
        )
    )

    with open("{}.thinned_views.tsv.gz".format(prefix), "wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as output:
            output.write(("\\t".join(header) + "\\n").encode("utf-8"))
            for _, _, _, _, line in retained:
                output.write((line + "\\n").encode("utf-8"))

    minimum_mafs = [entry[3] for entry in retained]
    report = {
        "schema_version": "1.0",
        "request": prefix,
        "study_count": study_count,
        "bin_width": BIN_WIDTH,
        "maf_threshold": MAF_THRESHOLD,
        "shards": shard_rows,
        "rows_read": rows_read,
        # Additive counts: rows_read equals the sum of these plus markers_retained, so the
        # document stays readable if this step is ever sharded and the reports are combined.
        "rows_dropped": dropped,
        "rows_dropped_total": sum(dropped.values()),
        "bins_occupied": len(winners),
        "markers_retained": len(retained),
        # Range of the per-marker minimum minor allele frequency across studies, which is the
        # quantity the bin winner maximises.
        "retained_min_maf": min(minimum_mafs),
        "retained_max_maf": max(minimum_mafs),
        "columns": header,
    }
    with open("{}.thin_qc.json".format(prefix), "w", encoding="utf-8") as handle:
        json.dump(report, handle, sort_keys=True, indent=2)
        handle.write("\\n")

    with open("versions.yml", "w", encoding="utf-8") as handle:
        handle.write('"$task.process":\\n')
        handle.write("    python: {}\\n".format(sys.version.split()[0]))


if __name__ == "__main__":
    sys.exit(main())
