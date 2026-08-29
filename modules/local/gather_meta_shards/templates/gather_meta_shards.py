#!/usr/bin/env python3
"""Gather per-chromosome meta-analysis shards into exactly one complete result.

The gather contract is deliberately strict, because the failure this guards against is a
result that looks complete but silently lost a chromosome. An absent output is never read
as an empty chromosome: a chromosome that genuinely has no eligible variant must arrive as
a valid header-only shard whose completion record says so.
"""

import gzip
import json
import sys
from pathlib import Path

# Deterministic publication order. Anything unrecognised sorts after these, lexically, so an
# unexpected contig is still ordered reproducibly rather than by channel arrival.
CHROMOSOME_ORDER = {str(number): number for number in range(1, 23)}
CHROMOSOME_ORDER.update({"X": 23, "Y": 24, "XY": 25, "MT": 26, "M": 26})

# An unscattered request is gathered too, as a one-shard gather, so that the completeness and
# duplicate-variant checks apply identically whether or not the run was scattered.
GENOME_WIDE = "ALL"


def fail(message):
    raise ValueError(message)


def normalise(label):
    text = str(label).strip().upper()
    return text[3:] if text.startswith("CHR") else text


def sort_key(label):
    return (CHROMOSOME_ORDER.get(label, 99), label)


def open_table(path):
    with open(path, "rb") as handle:
        compressed = handle.read(2) == b"\\x1f\\x8b"
    return gzip.open(path, "rt", encoding="utf-8") if compressed else open(path, "rt", encoding="utf-8")


def main():
    shards = json.loads(r'''$shards_literal''')
    records = json.loads(r'''$records_literal''')
    expected = [normalise(value) for value in json.loads(r'''$expected_literal''') if str(value).strip()]
    prefix = json.loads(r'''$prefix_literal''')

    if not expected:
        fail("the requested chromosome list is empty; a gather must state what it expects")
    if len(set(expected)) != len(expected):
        fail("the requested chromosome list repeats a chromosome")

    # Shard tables and completion records are paired by basename stem, a documented caller
    # contract. Positional pairing would silently mismatch under channel reordering.
    record_by_stem = {}
    for path in records:
        stem = Path(path).name.split(".")[0]
        if stem in record_by_stem:
            fail("two completion records share the shard identity {}".format(stem))
        record_by_stem[stem] = path

    shard_by_chromosome = {}
    for path in shards:
        stem = Path(path).name.split(".")[0]
        if stem not in record_by_stem:
            fail("shard {} has no completion record; an unrecorded shard cannot be gathered".format(stem))
        with open(record_by_stem[stem], encoding="utf-8") as handle:
            record = json.load(handle)
        if "chromosome" not in record:
            fail("the completion record for shard {} does not declare a chromosome".format(stem))
        chromosome = (
            GENOME_WIDE if record["chromosome"] is None else normalise(record["chromosome"])
        )
        if chromosome not in expected:
            fail(
                "shard {} reports chromosome {}, which was not requested".format(stem, chromosome)
            )
        if chromosome in shard_by_chromosome:
            fail("chromosome {} was produced by more than one shard".format(chromosome))
        shard_by_chromosome[chromosome] = {
            "stem": stem,
            "table": path,
            "eligible": int(record.get("fixed_eligible_variants", 0)),
        }

    missing = [chromosome for chromosome in expected if chromosome not in shard_by_chromosome]
    if missing:
        fail(
            "no shard completed for chromosome(s) {}; an absent output is never an empty "
            "chromosome".format(", ".join(sorted(missing, key=sort_key)))
        )

    header = None
    seen_keys = set()
    per_chromosome = []
    total_rows = 0

    with open("{}.gathered.tsv.gz".format(prefix), "wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as output:
            for chromosome in sorted(expected, key=sort_key):
                shard = shard_by_chromosome[chromosome]
                rows = 0
                with open_table(shard["table"]) as handle:
                    shard_header = handle.readline().rstrip("\\n")
                    if not shard_header:
                        fail("shard {} is empty; a shard must always carry a header".format(shard["stem"]))
                    if header is None:
                        header = shard_header
                        output.write((header + "\\n").encode("utf-8"))
                    elif shard_header != header:
                        fail(
                            "shard {} has a different header from the first shard; the shards "
                            "were not produced by one compatible plan".format(shard["stem"])
                        )
                    columns = header.split("\\t")
                    chromosome_index = columns.index("CHR") if "CHR" in columns else None
                    key_index = (
                        columns.index("META_VARIANT_KEY") if "META_VARIANT_KEY" in columns else None
                    )
                    if chromosome_index is None or key_index is None:
                        fail("the shard header must carry both CHR and META_VARIANT_KEY")
                    for line in handle:
                        line = line.rstrip("\\n")
                        if not line:
                            continue
                        fields = line.split("\\t")
                        if len(fields) != len(columns):
                            fail(
                                "shard {} row {} has {} fields; expected {}".format(
                                    shard["stem"], rows + 1, len(fields), len(columns)
                                )
                            )
                        if chromosome != GENOME_WIDE and normalise(fields[chromosome_index]) != chromosome:
                            fail(
                                "shard {} carries a row labelled chromosome {} but the shard is "
                                "chromosome {}".format(
                                    shard["stem"], fields[chromosome_index], chromosome
                                )
                            )
                        key = fields[key_index]
                        if key in seen_keys:
                            fail(
                                "variant {} appears more than once within or across shards".format(key)
                            )
                        seen_keys.add(key)
                        output.write((line + "\\n").encode("utf-8"))
                        rows += 1
                if rows != shard["eligible"]:
                    fail(
                        "shard {} wrote {} rows but its completion record reports {} eligible "
                        "variants".format(shard["stem"], rows, shard["eligible"])
                    )
                per_chromosome.append(
                    {"chromosome": chromosome, "shard": shard["stem"], "variants": rows}
                )
                total_rows += rows

    report = {
        "schema_version": "1.0",
        "request": prefix,
        "requested_chromosomes": sorted(expected, key=sort_key),
        "shards_gathered": len(per_chromosome),
        "per_chromosome": per_chromosome,
        # A chromosome that legitimately produced nothing is recorded explicitly, so a reader can
        # tell "nothing survived the filters here" from "this chromosome never ran".
        "empty_chromosomes": [
            entry["chromosome"] for entry in per_chromosome if entry["variants"] == 0
        ],
        "total_variants": total_rows,
        "columns": header.split("\\t") if header else [],
    }
    with open("{}.gather_report.json".format(prefix), "w", encoding="utf-8") as handle:
        json.dump(report, handle, sort_keys=True, indent=2)
        handle.write("\\n")

    with open("versions.yml", "w", encoding="utf-8") as handle:
        handle.write('"$task.process":\\n')
        handle.write("    python: {}\\n".format(sys.version.split()[0]))


if __name__ == "__main__":
    sys.exit(main())
