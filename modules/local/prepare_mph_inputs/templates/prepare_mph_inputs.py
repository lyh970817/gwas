#!/usr/bin/env python3
"""Write exactly the CSVs MPH consumes for one analysis unit, and record what was written.

MPH's file interface differs from every other individual-level estimator this pipeline drives, in four ways:

    it keys the phenotype and covariate tables by IID alone (issue #59), while indexing the relationship
        matrix itself by the *order* of that matrix's `.grm.iid` (issue #58). The adapter follows those native
        identities and that declared order. It cannot prove that a `.grm.iid` still matches its own
        `.grm.bin`; the route avoids that residual hazard by building both from the same genotype view.
    an empty field is its only missing representation, and every other cell is parsed as a number. This is
        not a preference: the pipeline's three missing spellings are therefore rewritten to empty fields.
    it synthesises an intercept only when no covariate is named (issue #62). A covariate file given with
        `--covariate_names` fits exactly the named columns, so a covariate-adjusted fit without an explicit
        column of ones is a no-intercept model. This adapter always writes that column and names it first.
    it never expands a categorical covariate (issue #64). A factor column passed through verbatim becomes a
        numeric covariate whose levels are read as magnitudes, and the resulting rank deficiency is only a
        warning at exit 0 (issue #65). Categorical columns are therefore dummy-encoded here, by the same rule
        `prepare_phenotype_inputs` applies for LDAK's matrix-adjustment design, so the two encodings agree.

The record written beside the CSVs is not published. It is the input to the writer that publishes the sidecar
after the fit, so every value is computed exactly once, here, and the post-fit writer only adds what could not
exist before the fit.
"""

import hashlib
import json
import sys

PHENOTYPE_TABLE = $phenotype_table_literal
QUANT_COVARIATES = $quant_covariates_literal
CAT_COVARIATES = $cat_covariates_literal
GRM_IID = $grm_iid_literal
FAM = $fam_literal
PREFIX = $prefix_literal
ANALYSIS_ID = $analysis_id_literal
PROCESS_NAME = $task_process_literal
# The route's own result identity: `kind: heritability` for one analysis unit, `kind: pairwise` for an oriented
# relationship. The serializer never infers which it is from the number of traits it was given.
RESULT = json.loads($result_literal)
TRAIT_NAMES = json.loads($trait_names_literal)
EFFECTIVE = json.loads($effective_literal)
MATRIX = json.loads($matrix_literal)
CAPABILITY = json.loads($capability_literal)
GRM_PREFIXES = json.loads($grm_prefixes_literal)

# The pipeline's own missing spellings, matching `prepare_phenotype_inputs`. Every one of them becomes an empty
# CSV field, which is MPH's only missing representation.
MISSING_TOKENS = frozenset(["", "na", "nan", "-9"])

# What the estimator's own guard enforces at exit 0, recorded so the sidecar states which checks were live.
NATIVE_CHECKS = [
    "primary_result_file_written",
    "no_error_line_in_log",
]

WARNINGS = []


def fail(message):
    role = "pair request" if RESULT.get("kind") == "pairwise" else "analysis"
    sys.exit("[nf-core/gwas] ERROR: {} '{}': {}".format(role, ANALYSIS_ID, message))


def is_missing(value):
    return value.strip().lower() in MISSING_TOKENS


def split_row(line):
    """Split one input line on whichever delimiter it actually uses, per line.

    The rule is `prepare_phenotype_inputs`' and it is copied rather than approximated, because getting it
    wrong here is a silent row shift rather than a parse error. Splitting on arbitrary whitespace collapses a
    run of tabs, so a genuinely empty cell -- the ordinary way a tab-delimited file spells a missing value --
    would vanish and the values to its right would each move one column left, arriving at MPH under the wrong
    covariate name. A line carrying a tab is therefore a tab-delimited line and is split on tabs.
    """
    line = line.rstrip("\\r\\n")
    return line.split("\\t") if "\\t" in line else line.split()


def read_table(path, role):
    rows = []
    with open(path) as handle:
        for number, line in enumerate(handle, start=1):
            fields = split_row(line)
            # A row of nothing but empty cells is a blank line, not a sample missing everything.
            if any(field.strip() for field in fields):
                rows.append((number, fields))
    if not rows:
        fail("the {} file '{}' has no data rows".format(role, path))
    return rows


def read_headered_table(path, role):
    """Read a prepared covariate table: two identifier columns, then one column per named covariate.

    The shape of the identifier columns is not re-checked here. Ingress already admitted this file and
    `prepare_phenotype_inputs` wrote it, so a check would only be able to fail a row the pipeline had already
    accepted -- and the incoming header is never forwarded to MPH in any case, because this module emits its
    own `IID,...` line from the covariate names it derives.
    """
    rows = read_table(path, role)
    header = rows[0][1]
    if len(header) < 3:
        fail(
            "the {} file '{}' has {} columns; two identifier columns and at least one named covariate "
            "column are required".format(role, path, len(header))
        )
    # A ragged row would otherwise be handed to MPH as a short CSV line under a full-width header, which MPH
    # reads without complaint.
    for number, fields in rows[1:]:
        if len(fields) != len(header):
            fail(
                "the {} file '{}' declares {} columns but line {} carries {} fields".format(
                    role, path, len(header), number, len(fields)
                )
            )
    return header, [fields for _number, fields in rows[1:]]


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(65536), b""):
            digest.update(block)
    return digest.hexdigest()


def sha256_text(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def write_lines(path, lines):
    with open(path, "w", newline="\\n") as handle:
        handle.writelines(line + "\\n" for line in lines)
        handle.flush()


def read_sample_order():
    """Read the genotype identities and the matrix order that MPH applies to the prepared tables."""
    fam_rows = read_table(FAM, "genotype FAM")
    fam_identities = []
    fam_by_iid = {}
    for number, fields in fam_rows:
        if len(fields) < 2:
            fail("row {} of the genotype FAM '{}' has fewer than two columns".format(number, FAM))
        fid, iid = fields[0], fields[1]
        fam_by_iid[iid] = fid
        fam_identities.append((fid, iid))

    with open(GRM_IID) as handle:
        grm_order = [line.rstrip("\\r\\n") for line in handle if line.rstrip("\\r\\n") != ""]

    # MPH indexes the matrix by this file's line order and never cross-checks it: a `.grm.iid` reordered
    # against its own `.grm.bin` gives a complete, stable, wrong estimate at exit 0 (pve 0.1156 -> -0.2995,
    # 5/5 runs, pinned image). Not asserted here: MPH_MAKEGRM builds every matrix from this view. See #58.
    return fam_identities, fam_by_iid, grm_order


def read_traits(fam_by_iid):
    """Read the headerless `FID IID trait...` table the pipeline prepares, keyed by IID as MPH keys it."""
    expected_columns = 2 + len(TRAIT_NAMES)
    rows = read_table(PHENOTYPE_TABLE, "phenotype")
    traits_by_iid = {}
    dropped_not_in_grm = 0
    for number, fields in rows:
        if len(fields) != expected_columns:
            fail(
                "row {} of the phenotype table '{}' has {} columns, expected {} for traits {}".format(
                    number, PHENOTYPE_TABLE, len(fields), expected_columns, ", ".join(TRAIT_NAMES)
                )
            )
        fid, iid = fields[0], fields[1]
        if iid not in fam_by_iid:
            dropped_not_in_grm += 1
            continue
        if iid in traits_by_iid:
            fail("the phenotype table '{}' lists IID '{}' more than once".format(PHENOTYPE_TABLE, iid))
        traits_by_iid[iid] = ["" if is_missing(value) else value for value in fields[2:]]
    return traits_by_iid, dropped_not_in_grm


def encode_covariates():
    """Reapply the pipeline's covariate encoding rule against the headered prepared tables.

    MPH's covariate interface is name-keyed, so this adapter reads the headered `.qcovar`/`.catcovar` tables
    rather than the headerless numeric design LDAK consumes. The encoding itself is the rule of
    `prepare_phenotype_inputs.adjustment_covariates`: quantitative columns verbatim, every categorical column
    treatment-coded against its lexically first observed level, and a missing factor value missing across all
    of that factor's dummies. Keeping the two in step is what a parity test exists for.
    """
    quant = read_headered_table(QUANT_COVARIATES, "quantitative covariate") if QUANT_COVARIATES else None
    cat = read_headered_table(CAT_COVARIATES, "categorical covariate") if CAT_COVARIATES else None
    if quant is None and cat is None:
        return None

    quant_names = []
    quant_by_identity = {}
    if quant is not None:
        quant_header, quant_body = quant
        quant_names = quant_header[2:]
        for row in quant_body:
            values = ["" if is_missing(value) else value for value in row[2:]]
            quant_by_identity[(row[0], row[1])] = values

    dummy_names = []
    cat_by_identity = {}
    if cat is not None:
        cat_header, cat_body = cat
        factor_levels = []
        for index, name in enumerate(cat_header[2:], start=2):
            levels = sorted({row[index] for row in cat_body if not is_missing(row[index])})
            encoded_levels = levels[1:]
            factor_levels.append((index, encoded_levels))
            dummy_names.extend("{}_{}".format(name, level) for level in encoded_levels)
        for row in cat_body:
            values = []
            for index, levels in factor_levels:
                value = row[index]
                if is_missing(value):
                    values.extend([""] * len(levels))
                else:
                    values.extend("1" if value == level else "0" for level in levels)
            cat_by_identity[(row[0], row[1])] = values

    if cat is None:
        return quant_names, quant_by_identity
    if quant is None:
        return dummy_names, cat_by_identity
    # The inner join `prepare_phenotype_inputs` applies for the same reason: a sample described by only one of
    # the two files has an incomplete covariate vector, which MPH would drop anyway.
    merged = {
        identity: quant_by_identity[identity] + cat_by_identity[identity]
        for identity in quant_by_identity
        if identity in cat_by_identity
    }
    return quant_names + dummy_names, merged


def main():
    fam_identities, fam_by_iid, grm_order = read_sample_order()
    traits_by_iid, dropped_not_in_grm = read_traits(fam_by_iid)
    covariates = encode_covariates()

    covariate_names = []
    covariate_by_identity = {}
    if covariates is not None:
        source_names, covariate_by_identity = covariates
        # `intercept` is written first and is always 1. MPH synthesises an intercept only when no covariate is
        # named (issue #62), so omitting this column would silently fit a model through the origin.
        covariate_names = ["intercept"] + list(source_names)

    written = [iid for iid in grm_order if iid in traits_by_iid]

    per_trait_nonmissing = [0] * len(TRAIT_NAMES)
    all_traits_nonmissing = 0
    any_trait_nonmissing = 0
    covariate_complete = 0
    analysis_set_expected = 0
    phenotype_lines = ["IID," + ",".join(TRAIT_NAMES)]
    covariate_lines = ["IID," + ",".join(covariate_names)] if covariates is not None else None

    for iid in written:
        values = traits_by_iid[iid]
        for index, value in enumerate(values):
            if value != "":
                per_trait_nonmissing[index] += 1
        traits_complete = all(value != "" for value in values)
        if traits_complete:
            all_traits_nonmissing += 1
        if any(value != "" for value in values):
            any_trait_nonmissing += 1
        phenotype_lines.append(",".join([iid] + values))

        if covariates is not None:
            row = covariate_by_identity.get((fam_by_iid[iid], iid))
            # A sample the covariate tables do not describe is written with empty cells rather than omitted, so
            # the two files stay row-aligned and the accounting below states why MPH dropped it.
            row = [""] * (len(covariate_names) - 1) if row is None else list(row)
            covariates_complete = all(value != "" for value in row)
            if covariates_complete:
                covariate_complete += 1
            covariate_lines.append(",".join([iid, "1"] + row))
        else:
            covariates_complete = True

        if traits_complete and covariates_complete:
            analysis_set_expected += 1

    if analysis_set_expected < len(written):
        WARNINGS.append(
            "complete_case_attrition: {} of {} individuals written have a missing trait or covariate cell and "
            "are dropped by MPH".format(len(written) - analysis_set_expected, len(written))
        )
    if dropped_not_in_grm:
        WARNINGS.append(
            "dropped_not_in_grm: {} phenotype row(s) name an individual absent from the matrix sample "
            "list".format(dropped_not_in_grm)
        )

    write_lines("{}.mph.pheno.csv".format(PREFIX), phenotype_lines)
    if covariate_lines is not None:
        write_lines("{}.mph.covar.csv".format(PREFIX), covariate_lines)

    # MPH copies each `--grm_list` entry verbatim into the matching result row's `vc_name`, so the staged
    # prefix is the only reliable key between the plan this pipeline built and the result MPH wrote. Recording
    # it here is what lets the post-fit writer match by name rather than by row position.
    if len(GRM_PREFIXES) != len(MATRIX["components"]):
        fail(
            "the matrix family stages {} component prefix(es) but the plan declares {} component(s)".format(
                len(GRM_PREFIXES), len(MATRIX["components"])
            )
        )
    components = [
        {
            "ordinal": component["ordinal"],
            "name": component["name"],
            "vc_name": prefix,
            "plan_predictor_count": component["plan_predictor_count"],
            # Filled in after the fit from MPH's own `m` column, matched by `vc_name`.
            "native_predictor_count": None,
        }
        for component, prefix in zip(MATRIX["components"], GRM_PREFIXES)
    ]

    # The shared core keys of the sidecar's sample block. They are null for a one-trait fit and populated for an
    # oriented pair, where the pair's own overlap is the fact a reader of two pair results needs: MPH fits the
    # complete-case intersection of the two endpoints and every named covariate, so `retained` can be far below
    # `union` without anything else in the published output saying so.
    pair_counts = {"left_nonmissing": None, "right_nonmissing": None, "both": None, "union": None}
    if RESULT.get("kind") == "pairwise":
        pair_counts = {
            "left_nonmissing": per_trait_nonmissing[0],
            "right_nonmissing": per_trait_nonmissing[1],
            "both": all_traits_nonmissing,
            "union": any_trait_nonmissing,
        }

    record = {
        "schema_version": "1.1",
        "result": dict(RESULT, primary_files=["{}.mq.vc.csv".format(PREFIX)] + (
            ["{}.mq.cor.csv".format(PREFIX)] if len(TRAIT_NAMES) > 1 else []
        )),
        "estimator": CAPABILITY,
        "stochastic_settings": {
            "seed": EFFECTIVE["seed"],
            "random_vectors": EFFECTIVE["random_vectors"],
            "save_memory": EFFECTIVE["save_memory"],
            # Read from the fit's own option echo: the executor decides the thread count and it moves the
            # estimate in the sixth to seventh significant digit, so no upstream component can know it.
            "num_threads": None,
            "requested": EFFECTIVE["requested"],
            "native_defaults_apply": EFFECTIVE["native_defaults_apply"],
            # Not a boolean `deterministic`: MPH's default seed is the fixed 0, so a run is reproducible, but
            # only against the same thread count and the same memory mode (issues #67, #68).
            "reproducibility": "seed_stable_given_threads_and_memory_mode",
        },
        "solver_settings": {
            "iterations": EFFECTIVE["iterations"],
            "tolerance": EFFECTIVE["tolerance"],
            "iterations_run": None,
            "final_dLLpred": None,
        },
        "component_plan": {
            "plan_key": MATRIX["plan_key"],
            "matrix_key": MATRIX["key"],
            # The settings that decided the components: the shared plan's when there is one, and the matrix's
            # own when the family has a single component and no plan above it.
            "settings": MATRIX["plan_settings"] if MATRIX["plan_key"] else MATRIX["settings"],
            "components": components,
        },
        "inputs": {
            "samples": {
                "order_source": "grm_iid",
                # The shared core keys mean the sample the estimate is computed on, so that one number is
                # comparable across every route that publishes a sidecar. MPH fits complete cases only, so
                # that is the complete-case count, not the number of rows this adapter handed it; the
                # post-fit writer confirms it against the size MPH itself reports. The written-row count and
                # every intermediate total live under `detail`.
                "retained": analysis_set_expected,
                "dropped": len(fam_identities) - analysis_set_expected,
                "left_nonmissing": pair_counts["left_nonmissing"],
                "right_nonmissing": pair_counts["right_nonmissing"],
                "both": pair_counts["both"],
                "union": pair_counts["union"],
                "detail": {
                    "fam": len(fam_identities),
                    "grm": len(grm_order),
                    "written": len(written),
                    "phenotype_rows": len(traits_by_iid) + dropped_not_in_grm,
                    "dropped_not_in_grm": dropped_not_in_grm,
                    "per_trait_nonmissing": dict(zip(TRAIT_NAMES, per_trait_nonmissing)),
                    "all_traits_nonmissing": all_traits_nonmissing,
                    "covariate_complete": covariate_complete if covariates is not None else None,
                    "analysis_set_expected": analysis_set_expected,
                    "analysis_set_observed": None,
                    # Named rather than implied: MPH restricts the fit to individuals with every named trait
                    # and every named covariate observed, which is not what GCTA's bivariate REML does with
                    # the same two endpoints.
                    "sample_policy": "complete_case_intersection",
                    "order_sha256": sha256_text("".join(iid + "\\n" for iid in written)),
                },
            },
            "variants": {
                "retained": None,
                # A stratified family does not restate the universe in its own settings: its plan is
                # autosome-only by construction, because GCTA refuses `--ld-score-region` on anything else,
                # and the SNP-information writer asserts that the plan and the BIM agree on it.
                "universe": MATRIX["settings"].get("variant_universe", "autosomes"),
                "bim_rows": MATRIX["variant_counts"]["bim_rows"],
                "assigned": MATRIX["variant_counts"]["assigned"],
                "unassigned": MATRIX["variant_counts"]["unassigned"],
                "annotation_columns": None,
            },
            "sha256": {
                "phenotype": sha256_file("{}.mph.pheno.csv".format(PREFIX)),
                "covariates": sha256_file("{}.mph.covar.csv".format(PREFIX)) if covariate_lines is not None else None,
                "grm_iid": sha256_file(GRM_IID),
                "annotation": None,
            },
        },
        "residual_covariance": None,
        # Required nullable core member of the shared sidecar schema: this route publishes MPH's native
        # estimate unchanged and derives nothing. Present so the on-disk shape is the same for every writer.
        "derivation": None,
        "software": {
            "tool": "mph",
            "process": "MPH_REML",
            "versions_record": "pipeline_info/nf_core_gwas_software_mqc_versions.yml",
        },
        "native_checks": {"writer": "MPH_REML", "enforced": NATIVE_CHECKS},
        "native_arguments": EFFECTIVE["native_arguments"],
        # Both stay null here and are resolved by the post-fit writer: MPH reports non-convergence and a
        # rank-deficient covariate matrix as `Warning:` lines at exit 0, which no upstream component can see.
        "classification": None,
        "warnings": WARNINGS,
        "trait_names": TRAIT_NAMES,
        "covariate_names": covariate_names,
    }
    write_lines("{}.mph.inputs.json".format(PREFIX), [json.dumps(record, indent=2)])

    # Written here rather than captured by an `eval` output, which Nextflow allows only on a Bash script.
    write_lines("versions.yml", ['"{}":'.format(PROCESS_NAME), "    python: {}".format(sys.version.split()[0])])
    return 0


if __name__ == "__main__":
    sys.exit(main())
