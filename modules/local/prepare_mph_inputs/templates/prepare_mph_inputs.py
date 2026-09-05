#!/usr/bin/env python3
"""Write exactly the CSVs MPH consumes for one analysis unit, and record what was written.

MPH's file interface differs from every other individual-level estimator this pipeline drives, in four ways
that are each silent when got wrong:

    it keys the phenotype and covariate tables by IID alone (issue #59), while indexing the relationship
        matrix itself by the *order* of that matrix's `.grm.iid` (issue #58). Both halves matter. A sample whose IID appears under one FID
        in the genotype FAM and another in the phenotype table would be included by MPH and dropped by GCTA,
        so the two estimators would silently be fitted on different samples; that case is an error here. And a
        `.grm.iid` whose order does not match its own `.grm.bin` is a silent wrong answer rather than a
        failure: measured on the pinned image, simply reversing the file moved the proportion of variance
        explained from 0.1156 to -0.2995 at exit 0, stably over five repeats, with nothing in the output
        indicating it. That order is therefore proved against the genotype FAM before anything else is done.
    an empty field is its only missing representation, and every other cell is parsed as a number. This is
        not a preference: measured on the pinned image, a literal `NA` in either file aborts the process with
        `std::invalid_argument what(): stof` at exit 139 and `-9` is read as the number minus nine, moving the
        phenotype's standard deviation from 0.855 to 2.827 (issue #60); and a cell spelled `nan` in the
        phenotype makes the solver loop without bound (issue #61) -- over five million trust-region attempts
        and 1.3 GB of output in seven minutes, still running, with neither the iteration limit nor the
        tolerance able to stop it. The
        pipeline's three missing spellings are therefore rewritten to empty fields, and a value that parses as
        a number but is not finite is refused here rather than handed over.
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
METHOD = $method_literal
PROCESS_NAME = $task_process_literal
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
    sys.exit("[nf-core/gwas] ERROR: analysis '{}': {}".format(ANALYSIS_ID, message))


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


def check_mph_names(names, role):
    """MPH splits every name list on commas, so a name carrying one addresses a different column."""
    for name in names:
        if "," in name or any(character.isspace() for character in name):
            fail(
                "{} name '{}' contains a comma or whitespace; MPH splits its name lists on commas and would "
                "silently address a different column".format(role, name)
            )
    duplicates = sorted({name for name in names if names.count(name) > 1})
    if duplicates:
        fail("{} names repeat: {}".format(role, ", ".join(duplicates)))


def read_sample_order():
    """Prove the matrix and the genotype bundle are the same view before anything is written against them."""
    fam_rows = read_table(FAM, "genotype FAM")
    fam_identities = []
    fam_by_iid = {}
    for number, fields in fam_rows:
        if len(fields) < 2:
            fail("row {} of the genotype FAM '{}' has fewer than two columns".format(number, FAM))
        fid, iid = fields[0], fields[1]
        if iid in fam_by_iid:
            # MPH keys samples by IID alone and aborts outright on a duplicated one (issue #59).
            fail(
                "the genotype FAM '{}' lists IID '{}' more than once. MPH keys samples by IID alone, so the "
                "duplicate rows would collapse into one entry of its sample map at exit 0 and the fit would "
                "silently use a different sample set".format(FAM, iid)
            )
        fam_by_iid[iid] = fid
        fam_identities.append((fid, iid))

    with open(GRM_IID) as handle:
        grm_order = [line.rstrip("\\r\\n") for line in handle if line.rstrip("\\r\\n") != ""]

    fam_order = [iid for _fid, iid in fam_identities]
    if grm_order != fam_order:
        fail(
            "the matrix sample list '{}' is not the IID column of '{}' in FAM order ({} against {} rows); the "
            "matrix was not built from this genotype bundle".format(GRM_IID, FAM, len(grm_order), len(fam_order))
        )
    return fam_identities, fam_by_iid, grm_order


def numeric_or_fail(value, description):
    """A finite number, or a named error.

    MPH parses every non-empty cell as a number and has no diagnostic for one it cannot use. A non-numeric
    cell aborts the process (issue #60), and a phenotype cell spelled `nan` sends the solver into an unbounded
    loop that neither the iteration limit nor the tolerance escapes (issue #61), so both are refused by name.
    """
    try:
        parsed = float(value)
    except ValueError:
        fail("{} is '{}', which is not a number; MPH aborts on a non-numeric cell rather than reporting it".format(description, value))
    if parsed != parsed or parsed in (float("inf"), float("-inf")):
        fail("{} is '{}', which is not finite; MPH does not terminate on a non-finite phenotype".format(description, value))
    return value


def read_traits(fam_by_iid):
    """Read the headerless `FID IID trait...` table the pipeline prepares, keyed by IID as MPH keys it."""
    check_mph_names(TRAIT_NAMES, "trait")
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
        if fam_by_iid[iid] != fid:
            fail(
                "MPH keys samples by IID only; phenotype row '{} {}' does not match the genotype FAM row "
                "'{} {}'. GCTA would drop this sample and MPH would include it, so the two estimators would "
                "not be fitted on the same individuals".format(fid, iid, fam_by_iid[iid], iid)
            )
        if iid in traits_by_iid:
            fail("the phenotype table '{}' lists IID '{}' more than once".format(PHENOTYPE_TABLE, iid))
        traits_by_iid[iid] = [
            ""
            if is_missing(value)
            else numeric_or_fail(value, "trait '{}' of sample '{} {}'".format(name, fid, iid))
            for name, value in zip(TRAIT_NAMES, fields[2:])
        ]
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
            values = []
            for name, value in zip(quant_names, row[2:]):
                values.append(
                    ""
                    if is_missing(value)
                    else numeric_or_fail(value, "quantitative covariate '{}' of sample '{} {}'".format(name, row[0], row[1]))
                )
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
        check_mph_names(covariate_names, "covariate column")

    written = [iid for iid in grm_order if iid in traits_by_iid]
    if not written:
        fail(
            "no individual of the matrix sample list '{}' has a phenotype row; MPH would be given an empty "
            "analysis set".format(GRM_IID)
        )

    per_trait_nonmissing = [0] * len(TRAIT_NAMES)
    all_traits_nonmissing = 0
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

    if analysis_set_expected == 0:
        fail(
            "no individual has a complete record across the {} trait(s) and {} covariate column(s) MPH is "
            "given, so the fit would have an empty analysis set".format(len(TRAIT_NAMES), len(covariate_names))
        )
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

    record = {
        "schema_version": "1.1",
        "result": {
            "kind": "heritability",
            "analysis_id": ANALYSIS_ID,
            "request_id": None,
            "relationship_id": None,
            "method": METHOD,
            "left_analysis_id": None,
            "right_analysis_id": None,
            "primary_files": ["{}.mq.vc.csv".format(PREFIX)],
        },
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
                "left_nonmissing": None,
                "right_nonmissing": None,
                "both": None,
                "union": None,
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
