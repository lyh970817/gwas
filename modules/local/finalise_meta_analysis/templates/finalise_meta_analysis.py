#!/usr/bin/env python3
"""Select the derived fixed summary and attach native optional-model fields."""

import json
import sys
from pathlib import Path

import pandas as pd


RANDOM_COLUMNS = {name: name for name in ("BETA_RANDOM", "SE_RANDOM", "Z_RANDOM", "P_RANDOM")}
RE2_COLUMNS = {
    "PVALUE_RE2": "P_RE2",
    "STAT1_RE2": "RE2_MEAN_COMPONENT",
    "STAT2_RE2": "RE2_HET_COMPONENT",
}
MRMEGA_COLUMNS = {
    "chisq_association": "MRMEGA_CHISQ_ASSOC",
    "ndf_association": "MRMEGA_DF_ASSOC",
    "P-value_association": "MRMEGA_P_ASSOC",
    "chisq_ancestry_het": "MRMEGA_CHISQ_ANCESTRY_HET",
    "ndf_ancestry_het": "MRMEGA_DF_ANCESTRY_HET",
    "P-value_ancestry_het": "MRMEGA_P_ANCESTRY_HET",
    "chisq_residual_het": "MRMEGA_CHISQ_RESIDUAL_HET",
    "ndf_residual_het": "MRMEGA_DF_RESIDUAL_HET",
    "P-value_residual_het": "MRMEGA_P_RESIDUAL_HET",
    "lnBF": "MRMEGA_LNBF",
}


def read_table(path, sep="\t"):
    # Preserve native numeric spelling, zeros and missing-value tokens.
    return pd.read_csv(path, sep=sep, dtype=str, keep_default_na=False)


def variant_keys(frame):
    return frame["CHR"] + ":" + frame["POS"] + ":" + frame["EA"] + ":" + frame["NEA"]


def attach(result, native, key, columns):
    fields = native.reindex(columns=list(columns)).rename(columns=columns)
    fields.index = pd.Index(key, name="META_VARIANT_KEY")
    return result.join(fields, how="left", validate="one_to_one")


def finalise(fixed, random, metasoft, mrmega, min_studies, output):
    result = read_table(fixed)
    result.index = pd.Index(variant_keys(result), name="META_VARIANT_KEY")
    # DOF is the native contributing-study count minus one.
    result["N_STUDIES"] = (pd.to_numeric(result["DOF"].replace("NA", pd.NA)) + 1).astype("Int64")
    result = result.loc[result["N_STUDIES"] >= min_studies]
    if random:
        native = read_table(random)
        result = attach(result, native, variant_keys(native), RANDOM_COLUMNS)
    if metasoft:
        native = read_table(metasoft, sep=r"\s+")
        result = attach(result, native, native["RSID"], RE2_COLUMNS)
    if mrmega:
        native = read_table(mrmega, sep=r"\s+")
        result = attach(result, native, native["MarkerName"], MRMEGA_COLUMNS)
    result.to_csv(output, sep="\t", index=False, na_rep="NA", compression={"method": "gzip", "mtime": 0})


def main():
    finalise(
        json.loads(r'''$fixed_literal'''),
        json.loads(r'''$random_literal'''),
        json.loads(r'''$metasoft_literal'''),
        json.loads(r'''$mrmega_literal'''),
        $min_studies,
        json.loads(r'''$output_literal'''),
    )
    process = json.loads(r'''$task_process_literal''')
    Path("versions.yml").write_text(
        f'"{process}":\\n    python: {sys.version.split()[0]}\\n    pandas: {pd.__version__}\\n',
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
