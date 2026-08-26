#!/usr/bin/env python3
"""Cross-study allele alignment and inverse-variance meta-analysis with GWASLab.

The operation is strictly per variant, so it is safe to restrict every parent to one
chromosome and run the same command on each shard. Every count reported in the QC
document is therefore an additive per-shard quantity or a range that composes under
min/max, never a genome-wide-only statistic.
"""

import gzip
import hashlib
import json
import math
import os
import shlex
import sys
from pathlib import Path

# The packaged image is read-only at the locations selected by Numba and Matplotlib.
os.environ.setdefault("NUMBA_CACHE_DIR", os.path.abspath(".numba_cache"))
os.environ.setdefault("MPLCONFIGDIR", os.path.abspath(".matplotlib"))

import numpy as np
import pandas as pd
import gwaslab as gl
from gwaslab.g_SumstatsMulti import SumstatsMulti

CANONICAL_COLUMNS = ["SNPID", "CHR", "POS", "EA", "NEA", "STATUS", "EAF", "BETA", "SE", "P", "N"]
BUILDS = {"GRCh37": "19", "GRCh38": "38"}
COMPLEMENT = str.maketrans("ACGTacgt", "TGCATGCA")

# GWASLab writes every effect size and test statistic with a fixed four-decimal format,
# which annihilates the effect of a common variant in a well-powered study. Six-digit
# scientific notation holds the same significant digits at every magnitude and is used
# for the published candidate; the intermediate adapter inputs consumed by METASOFT and
# MR-MEGA use exact shortest round-trip representations so no precision is lost at all.
PUBLISHED_FLOAT = "{:.6e}"


def fail(message):
    raise ValueError(message)


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def exact(value):
    """Shortest representation that round-trips to the identical float64."""
    if value is None:
        return "NA"
    number = float(value)
    if not math.isfinite(number):
        return "NA"
    return repr(number)


def published(value):
    if value is None:
        return "NA"
    number = float(value)
    if not math.isfinite(number):
        return "NA"
    return PUBLISHED_FLOAT.format(number)


def reverse_complement(allele):
    return allele.translate(COMPLEMENT)[::-1]


def parse_args(raw):
    """Restricted option surface. No native GWASLab argument is passed through."""
    tokens = shlex.split(raw)
    settings = {"random_effects": False, "min_studies": 2, "chromosome": None}
    index = 0
    while index < len(tokens):
        token = tokens[index]
        if token == "--random-effects":
            settings["random_effects"] = True
            index += 1
        elif token == "--min-studies":
            if index + 1 == len(tokens):
                fail("--min-studies requires a value")
            settings["min_studies"] = int(tokens[index + 1])
            index += 2
        elif token == "--chromosome":
            if index + 1 == len(tokens):
                fail("--chromosome requires a value")
            settings["chromosome"] = tokens[index + 1]
            index += 2
        else:
            fail(
                "Unsupported option: {}. Accepted options are --random-effects, "
                "--min-studies and --chromosome".format(token)
            )
    if settings["min_studies"] < 2:
        fail("--min-studies must be at least 2; a single-study estimate is not a meta-analysis")
    return settings


def normalised_chromosome(series):
    text = series.astype("string").str.strip().str.upper()
    return text.str.replace("^CHR", "", regex=True)


def load_parent(index, path, study_name, input_format, build, chromosome):
    """Load one canonical parent and enforce the per-contribution contract."""
    frame = pd.read_csv(
        path,
        sep="\\t",
        compression="gzip" if str(path).endswith(".gz") else "infer",
        dtype={"SNPID": "string", "CHR": "string", "EA": "string", "NEA": "string"},
        na_values=[""],
        keep_default_na=True,
    )
    missing = [column for column in CANONICAL_COLUMNS if column not in frame.columns]
    if missing:
        fail(
            "parent {} ({}) is missing required canonical columns: {}".format(
                index, study_name, ", ".join(missing)
            )
        )

    counts = {"input_rows": int(len(frame))}
    frame["CHR"] = normalised_chromosome(frame["CHR"])
    if chromosome is not None:
        wanted = str(chromosome).strip().upper()
        wanted = wanted[3:] if wanted.startswith("CHR") else wanted
        frame = frame.loc[frame["CHR"] == wanted].copy()
    counts["rows_in_shard"] = int(len(frame))

    frame["EA"] = frame["EA"].str.strip().str.upper()
    frame["NEA"] = frame["NEA"].str.strip().str.upper()
    for column in ["POS", "EAF", "BETA", "SE", "P", "N"]:
        frame[column] = pd.to_numeric(frame[column], errors="coerce")

    finite_beta = np.isfinite(frame["BETA"].to_numpy(dtype="float64", na_value=np.nan))
    se_values = frame["SE"].to_numpy(dtype="float64", na_value=np.nan)
    positive_se = np.isfinite(se_values) & (se_values > 0)
    n_values = frame["N"].to_numpy(dtype="float64", na_value=np.nan)
    valid_n = np.isfinite(n_values) & (n_values > 0)
    eaf_values = frame["EAF"].to_numpy(dtype="float64", na_value=np.nan)
    valid_eaf = np.isfinite(eaf_values) & (eaf_values >= 0) & (eaf_values <= 1)
    pos_values = frame["POS"].to_numpy(dtype="float64", na_value=np.nan)
    valid_position = frame["CHR"].notna().to_numpy() & np.isfinite(pos_values) & (pos_values > 0)
    valid_alleles = (
        frame["EA"].notna().to_numpy()
        & frame["NEA"].notna().to_numpy()
        & (frame["EA"].fillna("").str.len().to_numpy() > 0)
        & (frame["NEA"].fillna("").str.len().to_numpy() > 0)
    )

    effect_ok = finite_beta & positive_se
    complete = effect_ok & valid_n & valid_eaf & valid_position & valid_alleles
    counts["rows_valid_beta_se"] = int(effect_ok.sum())
    counts["rows_valid_beta_se_n_eaf"] = int((effect_ok & valid_n & valid_eaf).sum())
    counts["excluded_invalid_beta"] = int((~finite_beta).sum())
    counts["excluded_invalid_se"] = int((finite_beta & ~positive_se).sum())
    counts["excluded_invalid_position"] = int((effect_ok & ~valid_position).sum())
    counts["excluded_invalid_alleles"] = int((effect_ok & valid_position & ~valid_alleles).sum())
    # A valid effect estimate that disappears only because N or EAF is absent is the
    # silent-contribution-loss failure mode; it is attributed to its source here.
    counts["excluded_missing_n"] = int((effect_ok & ~valid_n).sum())
    counts["excluded_missing_eaf"] = int((effect_ok & valid_n & ~valid_eaf).sum())
    counts["contributions_lost_to_missing_n_eaf"] = int(
        (effect_ok & valid_position & valid_alleles & ~(valid_n & valid_eaf)).sum()
    )

    frame = frame.loc[complete].copy()
    frame["POS"] = frame["POS"].astype("int64")

    key = frame["CHR"] + ":" + frame["POS"].astype(str) + ":" + frame["EA"] + ":" + frame["NEA"]
    duplicated = key.duplicated(keep=False)
    counts["excluded_duplicate_key"] = int(duplicated.sum())
    frame = frame.loc[~duplicated.to_numpy()].copy()
    frame["_KEY"] = key.loc[~duplicated.to_numpy()]
    counts["retained_rows"] = int(len(frame))
    return frame, counts


def strand_conflicts(frames):
    """Positions where two parents disagree by reverse complement.

    The meta stage inherits strand resolution from the declared source harmonisation and
    is forbidden from making a new frequency-based guess. GWASLab aligns exact and
    swapped allele pairs only, so a reverse-complement representation would silently
    become a second union row holding a subset of the studies. Such positions are removed
    from every parent and counted instead.
    """
    seen = {}
    for frame in frames:
        for chromosome, position, ea, nea in zip(
            frame["CHR"], frame["POS"], frame["EA"], frame["NEA"]
        ):
            seen.setdefault((chromosome, int(position)), set()).add(frozenset((ea, nea)))
    conflicted = {}
    for site, allele_sets in seen.items():
        if len(allele_sets) < 2:
            continue
        bad = set()
        for left in allele_sets:
            for right in allele_sets:
                if left == right:
                    continue
                if frozenset(reverse_complement(a) for a in left) == right:
                    bad.add(left)
                    bad.add(right)
        if bad:
            conflicted[site] = bad
    return conflicted


def apply_strand_conflicts(frame, conflicted):
    if not conflicted:
        return frame, 0
    mask = [
        (chromosome, int(position)) in conflicted
        and frozenset((ea, nea)) in conflicted[(chromosome, int(position))]
        for chromosome, position, ea, nea in zip(
            frame["CHR"], frame["POS"], frame["EA"], frame["NEA"]
        )
    ]
    mask = np.asarray(mask, dtype=bool)
    return frame.loc[~mask].copy(), int(mask.sum())


def palindromic_count(frame):
    return int(
        sum(
            1
            for ea, nea in zip(frame["EA"], frame["NEA"])
            if reverse_complement(ea) == nea
        )
    )


def consensus_status(status_frame, contributes):
    """Derive the output STATUS conservatively from the aligned contributing statuses.

    A digit is retained only when every contributing parent agrees. Otherwise GWASLab's
    'unknown' digit 9 is written, so the derived summary never claims that a reference or
    strand check happened when the parents disagree about whether it did. The merge copies
    the mold's STATUS onto rows a parent never supplied, so only contributing parents are
    consulted.
    """
    output = []
    for row, mask in zip(status_frame, contributes):
        codes = [
            str(int(value)).zfill(7)
            for value, used in zip(row, mask)
            if used and value == value
        ]
        if not codes:
            output.append("9999999")
            continue
        digits = []
        for position in range(7):
            characters = {code[position] for code in codes}
            digits.append(characters.pop() if len(characters) == 1 else "9")
        output.append("".join(digits))
    return output


def main():
    settings = parse_args(json.loads(r'''$args_literal'''))
    parents = json.loads(r'''$parents_literal''')
    study_names = json.loads(r'''$study_names_literal''')
    input_format = json.loads(r'''$input_format_literal''')
    genome_build = json.loads(r'''$genome_build_literal''')
    prefix = json.loads(r'''$prefix_literal''')

    if len(parents) < 2:
        fail("a meta-analysis requires at least two canonical parents")
    if len(study_names) != len(parents):
        fail(
            "study_names has {} entries but {} parents were staged".format(
                len(study_names), len(parents)
            )
        )
    if len(set(study_names)) != len(study_names):
        fail("study_names must be unique so that study order is unambiguous")
    if settings["min_studies"] > len(parents):
        fail("--min-studies cannot exceed the number of parents")
    if not input_format or input_format.strip().startswith("auto"):
        fail("an explicit canonical input format is required; automatic detection is not supported")
    if genome_build not in BUILDS:
        fail("genome_build must be GRCh37 or GRCh38")

    log_lines = []

    def note(message):
        log_lines.append(message)

    note("gwaslab_meta_analyze prefix={}".format(prefix))
    note("input_format={} genome_build={}".format(input_format, genome_build))
    note(
        "random_effects={} min_studies={} chromosome={}".format(
            settings["random_effects"], settings["min_studies"], settings["chromosome"] or "all"
        )
    )

    frames = []
    parent_counts = []
    for index, (path, study_name) in enumerate(zip(parents, study_names), start=1):
        frame, counts = load_parent(
            index, path, study_name, input_format, genome_build, settings["chromosome"]
        )
        counts["study_index"] = index
        counts["study_name"] = study_name
        counts["staged_name"] = Path(path).name
        counts["sha256"] = sha256(path)
        counts["palindromic_rows"] = palindromic_count(frame)
        frames.append(frame)
        parent_counts.append(counts)
        note(
            "parent {} ({}): {} input rows, {} retained".format(
                index, study_name, counts["input_rows"], counts["retained_rows"]
            )
        )

    conflicted = strand_conflicts(frames)
    conflict_rows = 0
    for position, frame in enumerate(frames):
        frames[position], removed = apply_strand_conflicts(frame, conflicted)
        parent_counts[position]["excluded_strand_conflict"] = removed
        parent_counts[position]["retained_rows"] = int(len(frames[position]))
        conflict_rows += removed
    if conflicted:
        note(
            "removed {} rows at {} sites where parents disagree by reverse complement".format(
                conflict_rows, len(conflicted)
            )
        )

    for index, frame in enumerate(frames, start=1):
        if frame.empty:
            fail(
                "parent {} ({}) retained no usable variant".format(index, study_names[index - 1])
            )

    keys_per_parent = [set(frame["_KEY"]) for frame in frames]
    union_keys = set().union(*keys_per_parent)
    intersection_keys = set(keys_per_parent[0]).intersection(*keys_per_parent[1:])

    objects = []
    for frame, study_name in zip(frames, study_names):
        objects.append(
            gl.Sumstats(
                frame.drop(columns=["_KEY"]),
                fmt=input_format,
                build=BUILDS[genome_build],
                species="homo sapiens",
                study=study_name,
                verbose=False,
            )
        )

    multi = SumstatsMulti(
        objects,
        group_name=prefix,
        build=BUILDS[genome_build],
        engine="pandas",
        merge_by_id=False,
        keep_all_variants=True,
        verbose=False,
    )
    wide = multi.data
    note("aligned representation holds {} variants".format(len(wide)))

    study_count = len(parents)
    beta_columns = ["BETA_{}".format(i) for i in range(1, study_count + 1)]
    se_columns = ["SE_{}".format(i) for i in range(1, study_count + 1)]
    eaf_columns = ["EAF_{}".format(i) for i in range(1, study_count + 1)]
    n_columns = ["N_{}".format(i) for i in range(1, study_count + 1)]
    status_columns = ["STATUS_{}".format(i) for i in range(1, study_count + 1)]
    for column in beta_columns + se_columns + eaf_columns + n_columns + status_columns:
        if column not in wide.columns:
            wide[column] = np.nan

    betas = wide[beta_columns].to_numpy(dtype="float64", na_value=np.nan)
    ses = wide[se_columns].to_numpy(dtype="float64", na_value=np.nan)
    eafs = wide[eaf_columns].to_numpy(dtype="float64", na_value=np.nan)
    ns = wide[n_columns].to_numpy(dtype="float64", na_value=np.nan)
    contributes = (
        np.isfinite(betas)
        & np.isfinite(ses)
        & (ses > 0)
        & np.isfinite(ns)
        & np.isfinite(eafs)
    )
    contributing = contributes.sum(axis=1)

    weights = np.where(contributes, 1.0 / np.square(np.where(contributes, ses, 1.0)), 0.0)
    weight_total = weights.sum(axis=1)
    with np.errstate(invalid="ignore", divide="ignore"):
        max_weight_share = np.where(weight_total > 0, weights.max(axis=1) / weight_total, np.nan)
        weight_square_total = np.square(weights).sum(axis=1)
    eaf_present = np.where(contributes, eafs, np.nan)
    with np.errstate(invalid="ignore"):
        eaf_min = np.nanmin(np.where(contributes, eaf_present, np.nan), axis=1, initial=np.inf)
        eaf_max = np.nanmax(np.where(contributes, eaf_present, np.nan), axis=1, initial=-np.inf)
    eaf_min = np.where(np.isfinite(eaf_min), eaf_min, np.nan)
    eaf_max = np.where(np.isfinite(eaf_max), eaf_max, np.nan)

    key = (
        wide["CHR"].astype("string")
        + ":"
        + wide["POS"].astype("int64").astype(str)
        + ":"
        + wide["EA"].astype("string")
        + ":"
        + wide["NEA"].astype("string")
    )
    # Duplicate normalised keys are removed per parent, so a repeat here can only come
    # from the union itself; the occurrence index keeps the key deterministic either way.
    occurrence = key.groupby(key).cumcount()
    wide["_META_KEY"] = np.where(occurrence == 0, key, key + "#" + occurrence.astype(str))
    wide["_CONTRIBUTING"] = contributing
    wide["_MAX_WEIGHT_SHARE"] = max_weight_share
    wide["_EAF_MIN"] = eaf_min
    wide["_EAF_MAX"] = eaf_max
    wide["_W_SUM"] = weight_total
    wide["_W2_SUM"] = weight_square_total
    wide["_STATUS_OUT"] = consensus_status(
        wide[status_columns].to_numpy(dtype="float64", na_value=np.nan), contributes
    )

    result = multi.run_meta_analysis(random_effects=settings["random_effects"])
    fixed = result.data.copy()
    fixed["CHR"] = fixed["CHR"].astype("string")
    fixed["EA"] = fixed["EA"].astype("string")
    fixed["NEA"] = fixed["NEA"].astype("string")
    fixed["_JOIN"] = (
        fixed["CHR"] + ":" + fixed["POS"].astype("int64").astype(str) + ":" + fixed["EA"] + ":" + fixed["NEA"]
    )
    wide["_JOIN"] = key
    carried = wide[
        [
            "_JOIN",
            "_META_KEY",
            "_CONTRIBUTING",
            "_MAX_WEIGHT_SHARE",
            "_EAF_MIN",
            "_EAF_MAX",
            "_W_SUM",
            "_W2_SUM",
            "_STATUS_OUT",
        ]
    ].drop_duplicates(subset="_JOIN", keep="first")
    fixed = fixed.merge(carried, on="_JOIN", how="left")

    fixed["N_STUDIES"] = fixed["_CONTRIBUTING"].astype("int64")
    reported = fixed["DOF"].astype("float64") + 1
    if not np.allclose(reported.fillna(-1).to_numpy(), fixed["N_STUDIES"].to_numpy()):
        fail("GWASLab contributing-study counts disagree with the validated contribution mask")

    # Cochran's Q is a difference of large weighted sums and can land marginally below
    # zero through cancellation alone; it is clamped, and the heterogeneity statistics are
    # withheld entirely when there is no second study to be heterogeneous with.
    fixed["Q"] = fixed["Q"].astype("float64").clip(lower=0.0)
    single = fixed["N_STUDIES"] < 2
    fixed.loc[single, ["Q", "P_HET", "I2"]] = np.nan

    if settings["random_effects"]:
        constant = fixed["_W_SUM"] - (fixed["_W2_SUM"] / fixed["_W_SUM"])
        degrees = (fixed["N_STUDIES"] - 1).astype("float64")
        tau2 = np.where(
            (constant <= 0) | (fixed["Q"] <= degrees) | ~np.isfinite(fixed["Q"]),
            0.0,
            (fixed["Q"] - degrees) / constant,
        )
        fixed["TAU2_RANDOM"] = np.where(single, np.nan, np.clip(tau2, 0.0, None))

    excluded_by_min_studies = int((fixed["N_STUDIES"] < settings["min_studies"]).sum())
    distribution = {
        str(int(count)): int(number)
        for count, number in fixed["N_STUDIES"].value_counts().sort_index().items()
    }
    retained = fixed.loc[fixed["N_STUDIES"] >= settings["min_studies"]].copy()
    note(
        "{} variants excluded by min_studies={}, {} retained".format(
            excluded_by_min_studies, settings["min_studies"], len(retained)
        )
    )

    # pandas sorts with a non-stable algorithm by default; an explicit total order over the
    # allele-aware key makes output order independent of merge and channel order.
    retained = retained.sort_values(
        by=["CHR", "POS", "EA", "NEA"], kind="mergesort"
    ).reset_index(drop=True)

    published_columns = [
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
    if settings["random_effects"]:
        published_columns += ["BETA_RANDOM", "SE_RANDOM", "Z_RANDOM", "P_RANDOM", "TAU2_RANDOM"]
    published_columns += ["META_VARIANT_KEY"]

    out = pd.DataFrame(index=retained.index)
    out["SNPID"] = retained["SNPID"].astype("string")
    out["CHR"] = retained["CHR"].astype("string")
    out["POS"] = retained["POS"].astype("int64").astype(str)
    out["EA"] = retained["EA"].astype("string")
    out["NEA"] = retained["NEA"].astype("string")
    out["STATUS"] = retained["_STATUS_OUT"].astype("string")
    out["EAF"] = [published(value) for value in retained["EAF"]]
    out["BETA"] = [published(value) for value in retained["BETA"]]
    out["SE"] = [published(value) for value in retained["SE"]]
    out["P"] = [published(value) for value in retained["P"]]
    out["N"] = retained["N"].astype("Int64").astype("string").fillna("NA")
    out["N_STUDIES"] = retained["N_STUDIES"].astype("int64").astype(str)
    out["DIRECTION"] = retained["DIRECTION"].astype("string")
    out["EAF_META"] = out["EAF"]
    out["EAF_MIN"] = [published(value) for value in retained["_EAF_MIN"]]
    out["EAF_MAX"] = [published(value) for value in retained["_EAF_MAX"]]
    out["N_TOTAL"] = out["N"]
    out["MAX_WEIGHT_SHARE"] = [published(value) for value in retained["_MAX_WEIGHT_SHARE"]]
    out["Z_FIXED"] = [published(value) for value in retained["Z"]]
    out["Q"] = [published(value) for value in retained["Q"]]
    out["P_HET"] = [published(value) for value in retained["P_HET"]]
    out["I2"] = [published(value) for value in retained["I2"]]
    if settings["random_effects"]:
        for column in ["BETA_RANDOM", "SE_RANDOM", "Z_RANDOM", "P_RANDOM", "TAU2_RANDOM"]:
            out[column] = [published(value) for value in retained[column]]
    out["META_VARIANT_KEY"] = retained["_META_KEY"].astype("string")

    with gzip.GzipFile(
        filename="", mode="wb", fileobj=open("{}.meta.tsv.gz".format(prefix), "wb"), mtime=0
    ) as handle:
        handle.write(("\\t".join(published_columns) + "\\n").encode("utf-8"))
        for row in out[published_columns].itertuples(index=False, name=None):
            handle.write(("\\t".join("NA" if value is None else str(value) for value in row) + "\\n").encode("utf-8"))

    # Aligned per-study views: the lossless adapter input every downstream native tool
    # consumes instead of re-reading and re-harmonising the parents.
    view_keys = set(out["META_VARIANT_KEY"])
    views = wide.loc[wide["_META_KEY"].isin(view_keys)].copy()
    views = views.sort_values(by=["CHR", "POS", "EA", "NEA"], kind="mergesort").reset_index(drop=True)
    view_columns = ["META_VARIANT_KEY", "SNPID", "CHR", "POS", "EA", "NEA"]
    for index in range(1, study_count + 1):
        view_columns += [
            "STATUS_{}".format(index),
            "EAF_{}".format(index),
            "BETA_{}".format(index),
            "SE_{}".format(index),
            "P_{}".format(index),
            "N_{}".format(index),
        ]
    with gzip.GzipFile(
        filename="", mode="wb", fileobj=open("{}.study_views.tsv.gz".format(prefix), "wb"), mtime=0
    ) as handle:
        handle.write(("\\t".join(view_columns) + "\\n").encode("utf-8"))
        for _, row in views.iterrows():
            fields = [
                str(row["_META_KEY"]),
                "NA" if pd.isna(row["SNPID"]) else str(row["SNPID"]),
                str(row["CHR"]),
                str(int(row["POS"])),
                str(row["EA"]),
                str(row["NEA"]),
            ]
            for index in range(1, study_count + 1):
                status = row["STATUS_{}".format(index)]
                fields.append("NA" if pd.isna(status) else str(int(status)).zfill(7))
                for column in ["EAF", "BETA", "SE", "P", "N"]:
                    fields.append(exact(row["{}_{}".format(column, index)]))
            handle.write(("\\t".join(fields) + "\\n").encode("utf-8"))

    # Narrow effect matrix: key, then one BETA/SE pair per study in manifest order. It is
    # deliberately headerless because METASOFT's parser rejects any non-numeric token that
    # is not NA and stops on the first offending line. Absence is written as a paired
    # NA NA, and a partial pair is impossible by construction because BETA and SE are
    # masked together by one contribution mask.
    contributes_view = np.stack(
        [
            np.isfinite(views["BETA_{}".format(index)].to_numpy(dtype="float64", na_value=np.nan))
            & np.isfinite(views["SE_{}".format(index)].to_numpy(dtype="float64", na_value=np.nan))
            & (views["SE_{}".format(index)].to_numpy(dtype="float64", na_value=np.nan) > 0)
            & np.isfinite(views["N_{}".format(index)].to_numpy(dtype="float64", na_value=np.nan))
            & np.isfinite(views["EAF_{}".format(index)].to_numpy(dtype="float64", na_value=np.nan))
            for index in range(1, study_count + 1)
        ],
        axis=1,
    )
    with open("{}.effect_matrix.txt".format(prefix), "w", encoding="utf-8", newline="\\n") as handle:
        for position, (_, row) in enumerate(views.iterrows()):
            fields = [str(row["_META_KEY"])]
            for index in range(1, study_count + 1):
                if contributes_view[position, index - 1]:
                    fields += [
                        exact(row["BETA_{}".format(index)]),
                        exact(row["SE_{}".format(index)]),
                    ]
                else:
                    fields += ["NA", "NA"]
            handle.write(" ".join(fields) + "\\n")

    with open("{}.study_order.tsv".format(prefix), "w", encoding="utf-8", newline="\\n") as handle:
        handle.write(
            "study_index\\tstudy_name\\tstaged_name\\tsha256\\tinput_rows\\tretained_rows\\n"
        )
        for counts in parent_counts:
            handle.write(
                "{}\\t{}\\t{}\\t{}\\t{}\\t{}\\n".format(
                    counts["study_index"],
                    counts["study_name"],
                    counts["staged_name"],
                    counts["sha256"],
                    counts["input_rows"],
                    counts["retained_rows"],
                )
            )

    dominated = int((retained["_MAX_WEIGHT_SHARE"] > 0.8).sum())
    mrmega_eligible = int((retained["N_STUDIES"] >= 3).sum())
    qc = {
        "schema_version": "1.0",
        "shard_composable": True,
        "chromosome": settings["chromosome"],
        "min_studies": settings["min_studies"],
        "random_effects": settings["random_effects"],
        "study_count": study_count,
        "per_parent": parent_counts,
        "union_variants": len(union_keys),
        "intersection_variants": len(intersection_keys),
        "aligned_variants": int(len(wide)),
        "strand_conflict_sites": len(conflicted),
        "strand_conflict_rows_excluded": conflict_rows,
        "contributing_study_count_distribution": distribution,
        "variants_excluded_by_min_studies": excluded_by_min_studies,
        "fixed_eligible_variants": int(len(retained)),
        "mrmega_eligible_variants": mrmega_eligible,
        "variants_dominated_by_one_study": dominated,
        "eaf_min": None if retained.empty else float(np.nanmin(retained["_EAF_MIN"].to_numpy(dtype="float64"))),
        "eaf_max": None if retained.empty else float(np.nanmax(retained["_EAF_MAX"].to_numpy(dtype="float64"))),
    }
    with open("{}.qc.json".format(prefix), "w", encoding="utf-8") as handle:
        json.dump(qc, handle, sort_keys=True, indent=2)
        handle.write("\\n")

    derivation = {
        "schema_version": "1.0",
        "operation": "gwaslab_inverse_variance_meta_analysis",
        "prefix": prefix,
        "input_format": input_format,
        "genome_build": genome_build,
        "chromosome": settings["chromosome"],
        "min_studies": settings["min_studies"],
        "models": ["fixed"] + (["random"] if settings["random_effects"] else []),
        "study_order": [
            {
                "study_index": counts["study_index"],
                "study_name": counts["study_name"],
                "staged_name": counts["staged_name"],
                "sha256": counts["sha256"],
            }
            for counts in parent_counts
        ],
        "variant_key_contract": "CHR:POS:EA:NEA with a #<occurrence> disambiguator",
        "fixed_effect_contract": "w=1/SE^2; BETA=sum(w*BETA)/sum(w); SE=sqrt(1/sum(w)); Z=BETA/SE; two-sided normal P",
        "random_effect_contract": "DerSimonian-Laird" if settings["random_effects"] else None,
        "status_contract": "per-digit consensus of contributing parents, otherwise GWASLab unknown digit 9",
        "strand_contract": "exact and swapped allele pairs aligned by GWASLab; reverse-complement disagreements excluded, never inferred",
        "published_float_format": PUBLISHED_FLOAT,
        "adapter_float_format": "shortest round-trip repr",
        "gwaslab_version": gl.__version__,
        "python_version": sys.version.split()[0],
        "outputs": {
            "meta_analysis": "{}.meta.tsv.gz".format(prefix),
            "study_views": "{}.study_views.tsv.gz".format(prefix),
            "effect_matrix": "{}.effect_matrix.txt".format(prefix),
            "study_order": "{}.study_order.tsv".format(prefix),
            "qc": "{}.qc.json".format(prefix),
        },
    }
    with open("{}.derivation.json".format(prefix), "w", encoding="utf-8") as handle:
        json.dump(derivation, handle, sort_keys=True, indent=2)
        handle.write("\\n")

    with open("{}.meta.log".format(prefix), "w", encoding="utf-8", newline="\\n") as handle:
        for line in log_lines:
            handle.write(line + "\\n")
        handle.write(getattr(multi.log, "log_text", ""))
        handle.write("\\n")

    with open("versions.yml", "w", encoding="utf-8") as handle:
        handle.write('"$task.process":\\n')
        handle.write("    gwaslab: {}\\n".format(gl.__version__))
        handle.write("    python: {}\\n".format(sys.version.split()[0]))


if __name__ == "__main__":
    sys.exit(main())
