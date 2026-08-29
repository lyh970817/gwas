#!/usr/bin/env python3
"""Read MR-MEGA's derived ancestry axes out of a pass-1 log and canonicalize their signs.

MDS axes carry an arbitrary sign: the same geometry can come back mirrored from run to run.
Negating an axis is a pure post-hoc transform on MR-MEGA's output -- it flips exactly the
coefficient `beta_{j+1}` and leaves `se`, every chi-square, every `ndf`, every P value and
`lnBF` bit-identical -- so fixing the sign here, between the two passes, costs nothing and
makes every scattered shard born canonical rather than needing a correction afterwards.

This is also the only place study coordinates are ever emitted. MR-MEGA prints them to the
log with six significant figures and offers no way to raise that, which is the entire source
of the small residual between a scattered and an unscattered run; the scatter itself
contributes none of it.
"""

import json
import math
import sys
from pathlib import Path

MARKER = "Principal components:"


def fail(message):
    raise ValueError(message)


def parse_filelist(path):
    """Cohort order is defined by the manifest, and everything downstream depends on it."""
    names = []
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            # MR-MEGA's own tokeniser keeps the first whitespace-separated token only.
            entry = line.strip().split()
            if not entry:
                continue
            names.append(Path(entry[0]).name)
    if not names:
        fail("the study manifest is empty")
    return names


def parse_axes(path, study_count, axes):
    """Take the `Principal components:` block: a header row, then one row per study.

    Studies are matched to coordinates by position, never by the path in the log, because
    that path is whatever the manifest happened to contain and the manifest is rewritten
    against staged copies before MR-MEGA ever sees it.
    """
    with open(path, encoding="utf-8", errors="replace") as handle:
        lines = handle.read().splitlines()
    try:
        start = next(index for index, line in enumerate(lines) if line.strip() == MARKER)
    except StopIteration:
        fail(
            "the MR-MEGA log has no '{}' block; pass 1 did not derive axes".format(MARKER)
        )
    header = lines[start + 1].split() if start + 1 < len(lines) else []
    if not header or header[0] != "PCs":
        fail("the principal-component block is not followed by its 'PCs' header row")
    if len(header) - 1 != axes:
        fail(
            "the log reports {} axes but {} were requested".format(len(header) - 1, axes)
        )

    coordinates = []
    paths = []
    for offset in range(study_count):
        index = start + 2 + offset
        if index >= len(lines):
            fail(
                "the principal-component block ends after {} of {} studies".format(
                    offset, study_count
                )
            )
        fields = lines[index].split()
        if len(fields) != axes + 1:
            fail(
                "principal-component row {} has {} fields; expected a path plus {} "
                "coordinates".format(offset + 1, len(fields), axes)
            )
        paths.append(fields[0])
        row = []
        for value in fields[1:]:
            try:
                number = float(value)
            except ValueError:
                fail(
                    "principal-component row {} holds a non-numeric coordinate {}".format(
                        offset + 1, value
                    )
                )
            if not math.isfinite(number):
                fail(
                    "principal-component row {} holds a non-finite coordinate {}".format(
                        offset + 1, value
                    )
                )
            row.append(number)
        coordinates.append(row)
    return coordinates, paths


def canonicalize(coordinates, axes):
    """Deterministic sign rule: the largest-magnitude coordinate on each axis is made positive.

    Ties in magnitude are broken by the lowest study index, so the rule depends only on the
    ordered source coordinates and never on iteration order. An axis whose coordinates are all
    zero carries no information and is rejected rather than silently published.
    """
    flipped = []
    for axis in range(axes):
        column = [row[axis] for row in coordinates]
        best = 0
        for index in range(1, len(column)):
            if abs(column[index]) > abs(column[best]):
                best = index
        if abs(column[best]) == 0.0:
            fail(
                "ancestry axis {} is identically zero across every study; the "
                "ancestry-distance solution is degenerate".format(axis + 1)
            )
        if column[best] < 0:
            for row in coordinates:
                row[axis] = -row[axis]
            flipped.append(axis + 1)
    return flipped


def main():
    log_path = json.loads(r'''$log_literal''')
    filelist_path = json.loads(r'''$filelist_literal''')
    prefix = json.loads(r'''$prefix_literal''')
    axes_text = json.loads(r'''$axes_literal''')

    try:
        axes = int(axes_text)
    except ValueError:
        fail("axes must be an integer; got {}".format(axes_text))
    if axes < 1:
        fail("axes must be at least 1")

    studies = parse_filelist(filelist_path)
    if axes > len(studies) - 3:
        # The native gate is `cohortCount - 2 > pc`. Violating it exits 0 with every row
        # flagged SmallCohortCount, so it has to be caught outside the binary.
        fail(
            "axes must satisfy 1 <= axes <= K - 3; got axes={} with K={}".format(
                axes, len(studies)
            )
        )

    coordinates, logged_paths = parse_axes(log_path, len(studies), axes)
    flipped = canonicalize(coordinates, axes)

    # The precalculated manifest MR-MEGA reads in pass 2: one study per line, in cohort order,
    # followed by exactly `axes` coordinates. A block narrower than --pc is a silent wrong
    # answer, so the width is fixed here and re-checked by the MRMEGA module.
    with open("{}.precalculated_axes.txt".format(prefix), "w", encoding="utf-8", newline="\\n") as handle:
        for name, row in zip(studies, coordinates):
            handle.write(name + " " + " ".join(repr(value) for value in row) + "\\n")

    with open("{}.ancestry_axes.tsv".format(prefix), "w", encoding="utf-8", newline="\\n") as handle:
        handle.write(
            "study_index\\tstudy_name\\t"
            + "\\t".join("AXIS_{}".format(axis + 1) for axis in range(axes))
            + "\\n"
        )
        for index, (name, row) in enumerate(zip(studies, coordinates), start=1):
            handle.write(
                "{}\\t{}\\t{}\\n".format(index, name, "\\t".join(repr(value) for value in row))
            )

    spans = [
        max(row[axis] for row in coordinates) - min(row[axis] for row in coordinates)
        for axis in range(axes)
    ]
    qc = {
        "schema_version": "1.0",
        "axes": axes,
        "studies": len(studies),
        "study_order": studies,
        "sign_rule": "largest-magnitude coordinate per axis made positive, ties broken by lowest study index",
        "axes_sign_flipped": flipped,
        "axis_span": spans,
        # Recorded so a mismatch between the manifest and what MR-MEGA echoed is auditable even
        # though the match is deliberately positional.
        "logged_paths": logged_paths,
        "coordinate_precision": "six significant figures, as MR-MEGA prints them",
    }
    with open("{}.axes_qc.json".format(prefix), "w", encoding="utf-8") as handle:
        json.dump(qc, handle, sort_keys=True, indent=2)
        handle.write("\\n")

    with open("versions.yml", "w", encoding="utf-8") as handle:
        handle.write('"$task.process":\\n')
        handle.write("    python: {}\\n".format(sys.version.split()[0]))


if __name__ == "__main__":
    sys.exit(main())
