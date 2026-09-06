#!/usr/bin/env python3
"""Publish the per-result provenance sidecar for one completed MPH fit.

This writer runs after the estimator rather than before it, which is unusual for this pipeline and is forced by
MPH itself. Both of MPH's quality failures are printed as `Warning:` lines at exit 0 with a complete result set
written beside them (issues #65 and #66), and the number of variants each component actually contributed
exists only in the result file. An adapter running before the fit could publish neither, and would have to
leave the fields it is required to carry as nulls.

Everything the serializer already decided is copied through unchanged, so no value is computed twice. This
writer adds exactly what could not exist earlier:

    the quality classification and the warning vocabulary, read from the log
    the analysis-set size MPH itself reports, cross-checked against what the serializer predicted, and
        promoted into the sidecar's shared `inputs.samples.retained` key
    the fitted covariate columns, reconciled against the columns the serializer asked MPH to fit
    the post-quality-control variant count of each component, matched by name and never by row position
    the effective thread count, which the executor chose and which moves the estimate
    the iteration count and the final predicted log-likelihood change the solver stopped on

Two of those are fatal on purpose.

The analysis-set cross-check is the runtime proof that this pipeline's missing-value semantics and MPH's own
agree on which individuals were fitted; a disagreement means the published estimate describes a different
sample than the sidecar claims.

The covariate reconciliation exists because of a measured silent model change (issue #65). When the
covariate matrix is rank deficient MPH prints one warning, prunes columns until the design has full rank, and
names none of the columns it dropped. On the pinned image a collinear design dropped the pipeline's own
explicit `intercept` column, turning a covariate-adjusted fit into a fit through the origin with nothing in
the result saying so. That is a different model, not a rounding difference: fitting the same two covariates
with and without an intercept moved the proportion of variance explained from 0.0849 to 0.1083, identically
over three repeats. The whole reason this pipeline writes an explicit column of ones is that MPH synthesises
no intercept once a covariate is named (issue #62), so an intercept MPH then prunes voids the
guarantee and is refused rather than recorded. Any other pruned column is recorded by name as a warning,
because a redundant covariate is the researcher's design choice to correct and not a misstatement of the
model that was fitted.
"""

import json
import re
import sys

SERIALIZATION = $serialization_literal
VARIANCE_COMPONENTS = $variance_components_literal
FIXED_EFFECTS = $fixed_effects_literal
ITERATIONS = $iterations_literal
LOG = $log_literal
# Empty for a one-trait fit: MPH writes the correlation result only when more than one trait is named.
CORRELATIONS = $correlations_literal
PREFIX = $prefix_literal
ANALYSIS_ID = $analysis_id_literal
PROCESS_NAME = $task_process_literal

# Warnings this writer raises itself, kept beside the ones it reads out of the log.
WARNINGS = []

# The two documented quality failures (issues #66 and #65), each measured on the pinned image at exit 0 with
# every `mq.*` file written. Any other `^Warning:` line is carried through verbatim rather than discarded.
WARNING_PATTERNS = [
    (re.compile(r"^Warning: not converged after .*"), "not_converged"),
    (re.compile(r"^Warning: the covariate matrix is not of full rank\\."), "covariate_matrix_rank_deficient"),
]
ANALYSIS_SET_PATTERN = re.compile(r"^Non-missing analysis set contains ([0-9]+) individuals")
NUM_THREADS_PATTERN = re.compile(r"^OPTION num_threads with ARG ([0-9]+)")


def fail(message):
    sys.exit("[nf-core/gwas] ERROR: analysis '{}': {}".format(ANALYSIS_ID, message))


def read_csv(path):
    with open(path) as handle:
        rows = [line.rstrip("\\r\\n").split(",") for line in handle if line.strip() != ""]
    if not rows:
        fail("the native result '{}' is empty".format(path))
    return rows[0], rows[1:]


def read_log():
    with open(LOG) as handle:
        return [line.rstrip("\\r\\n") for line in handle]


def classify(log_lines):
    warnings = []
    for line in log_lines:
        if not line.startswith("Warning:"):
            continue
        matched = None
        for pattern, token in WARNING_PATTERNS:
            if pattern.match(line):
                matched = token
                break
        warnings.append(matched if matched is not None else line)
    return warnings


def finite_or_none(value, label):
    """MPH's correlation columns can hold `-nan` or `nan` at exit 0 (issue #73).

    A non-finite entry is published as null and named in the warning vocabulary rather than rewritten,
    clamped or dropped: the fit ran, MPH reported this, and the record says so.
    """
    try:
        parsed = float(value)
    except ValueError:
        WARNINGS.append("non_finite_correlation:{}".format(label))
        return None
    if parsed != parsed or parsed in (float("inf"), float("-inf")):
        WARNINGS.append("non_finite_correlation:{}".format(label))
        return None
    return parsed


def read_correlations(record):
    """Read `.mq.cor.csv` and orient it against the trait order this pipeline declared.

    MPH reverses the trait pair in this file -- `--trait_names A,B` yields rows labelled `trait_x = B`,
    `trait_y = A` -- consistently, in every row and in the cross block of `.mq.vc.csv` too (issue #73). Nothing
    is therefore keyed by row position or by which label happens to sit in which column: the pair is read as an
    unordered set, checked against the pair the caller asked for, and the order MPH used is recorded verbatim
    so the relabelling is auditable rather than trusted.

    Every value is MPH's own. The genome-wide aggregate is MPH's synthetic `G` row, published as it stands;
    nothing here recomputes a total or a standard error.
    """
    header, body = read_csv(CORRELATIONS)
    for column in ["vc_name", "trait_x", "trait_y", "cor", "se"]:
        if column not in header:
            fail("the native correlation result '{}' has no '{}' column".format(CORRELATIONS, column))
    rows = [dict(zip(header, row)) for row in body if len(row) >= len(header)]
    if not rows:
        fail("the native correlation result '{}' has no data rows".format(CORRELATIONS))

    declared = list(record.get("trait_names") or [])
    if len(declared) != 2:
        fail(
            "the correlation result '{}' was produced for a fit this record declares {} trait(s) for; "
            "the pair route declares exactly two".format(CORRELATIONS, len(declared))
        )
    labelled = {(row["trait_x"], row["trait_y"]) for row in rows}
    if len(labelled) != 1 or set(labelled.pop()) != set(declared):
        fail(
            "the native correlation result '{}' labels its trait pair {} but this request declared {}; the "
            "result does not describe the pair that was requested".format(
                CORRELATIONS,
                sorted({label for row in rows for label in (row["trait_x"], row["trait_y"])}),
                declared,
            )
        )
    first = rows[0]

    # `G` is MPH's synthetic aggregate row rather than a component name; every component this pipeline builds
    # is named after its staged matrix prefix, so the two cannot collide.
    by_name = {}
    for row in rows:
        by_name.setdefault(row["vc_name"], row)
    entry = lambda row, label: {
        "vc_name": row["vc_name"],
        "correlation": finite_or_none(row["cor"], label),
        "se": finite_or_none(row["se"], "{}.se".format(label)),
    }

    components = []
    for component in record["component_plan"]["components"]:
        row = by_name.get(component["vc_name"])
        if row is None:
            fail(
                "the native correlation result '{}' has no row named '{}'; it names {}".format(
                    CORRELATIONS, component["vc_name"], ", ".join(sorted(by_name))
                )
            )
        components.append(dict(entry(row, "G{}".format(component["ordinal"])), ordinal=component["ordinal"], name=component["name"]))

    for required in ["err", "G"]:
        if required not in by_name:
            fail(
                "the native correlation result '{}' has no '{}' row; it names {}".format(
                    CORRELATIONS, required, ", ".join(sorted(by_name))
                )
            )

    return {
        "source": CORRELATIONS.split("/")[-1],
        "declared_trait_order": declared,
        "native_trait_pair_labels": {"trait_x": first["trait_x"], "trait_y": first["trait_y"]},
        "native_pair_order": "declared" if [first["trait_x"], first["trait_y"]] == declared else "reversed",
        "total": entry(by_name["G"], "total"),
        "residual": entry(by_name["err"], "residual"),
        "components": components,
    }


def scalar_from_log(log_lines, pattern, description):
    for line in log_lines:
        match = pattern.match(line)
        if match:
            return int(match.group(1))
    fail("the native log '{}' does not report {}".format(LOG, description))


def main():
    with open(SERIALIZATION) as handle:
        record = json.load(handle)

    log_lines = read_log()

    header, body = read_csv(VARIANCE_COMPONENTS)
    for column in ["vc_name", "m"]:
        if column not in header:
            fail("the native result '{}' has no '{}' column".format(VARIANCE_COMPONENTS, column))
    vc_name_index = header.index("vc_name")
    m_index = header.index("m")

    # One row per component per trait pair, so the same component appears once per pair with the same `m`.
    # Keyed by name, first occurrence wins, and the residual row is never a component. The header repeats its
    # component labels in the appended covariance blocks (issue #74), so nothing is keyed by header name
    # beyond the ten fixed leading columns.
    native_m = {}
    for row in body:
        if len(row) <= max(vc_name_index, m_index):
            fail("a row of the native result '{}' is shorter than its header".format(VARIANCE_COMPONENTS))
        name = row[vc_name_index]
        if name == "err" or name in native_m:
            continue
        try:
            native_m[name] = int(row[m_index])
        except ValueError:
            fail("component '{}' reports a non-integer variant count '{}'".format(name, row[m_index]))

    components = record["component_plan"]["components"]
    for component in components:
        vc_name = component.get("vc_name")
        if vc_name is None:
            fail(
                "component {} of the serialised plan carries no vc_name to match the native result by".format(
                    component["ordinal"]
                )
            )
        if vc_name not in native_m:
            fail(
                "the native result '{}' has no row named '{}'; it names {}. The component plan and the fitted "
                "matrices are not the same family".format(
                    VARIANCE_COMPONENTS, vc_name, ", ".join(sorted(native_m)) or "no components"
                )
            )
        component["native_predictor_count"] = native_m[vc_name]
    record["inputs"]["variants"]["retained"] = sum(native_m.values())

    # MPH names the covariates it fitted and never the ones it pruned, so the fitted set is what has to be
    # compared against the requested set.
    requested_covariates = list(record.get("covariate_names") or [])
    fitted_covariates = []
    if requested_covariates:
        blue_header, blue_body = read_csv(FIXED_EFFECTS)
        if "covar" not in blue_header:
            fail("the native fixed-effect result '{}' has no 'covar' column".format(FIXED_EFFECTS))
        covar_index = blue_header.index("covar")
        for row in blue_body:
            if len(row) > covar_index and row[covar_index] not in fitted_covariates:
                fitted_covariates.append(row[covar_index])
        dropped = [name for name in requested_covariates if name not in fitted_covariates]
        if "intercept" in dropped:
            fail(
                "MPH pruned the explicit 'intercept' column out of a rank-deficient covariate design, so the "
                "published fit has no intercept and is a different model than the one requested. The fitted "
                "columns are {} against the requested {}. Remove the collinear covariate(s) from this "
                "analysis".format(", ".join(fitted_covariates), ", ".join(requested_covariates))
            )
        if dropped:
            WARNINGS.append(
                "covariate_columns_pruned: MPH dropped {} from a rank-deficient covariate design".format(
                    ", ".join(dropped)
                )
            )
    record["inputs"]["covariates"] = {
        "requested": requested_covariates,
        "fitted": fitted_covariates,
        "intercept": "explicit" if "intercept" in requested_covariates else "native",
    }

    iteration_header, iteration_body = read_csv(ITERATIONS)
    if not iteration_body:
        fail("the native iteration trace '{}' has no rows".format(ITERATIONS))
    last = dict(zip(iteration_header, iteration_body[-1]))
    try:
        record["solver_settings"]["iterations_run"] = int(last["iter"])
    except (KeyError, ValueError):
        fail("the native iteration trace '{}' does not end in a numbered iteration".format(ITERATIONS))
    record["solver_settings"]["final_dLLpred"] = float(last["dLLpred"]) if "dLLpred" in last else None

    observed = scalar_from_log(log_lines, ANALYSIS_SET_PATTERN, "its non-missing analysis set size")
    expected = record["inputs"]["samples"]["detail"]["analysis_set_expected"]
    if observed != expected:
        fail(
            "MPH reports a non-missing analysis set of {} individuals but the prepared inputs declare {}. The "
            "pipeline's missing-value semantics and MPH's disagree, so the published estimate would describe a "
            "different sample than this record claims".format(observed, expected)
        )
    record["inputs"]["samples"]["detail"]["analysis_set_observed"] = observed
    # `retained` is the shared core key and means the sample the estimate was computed on, so it must be the
    # size MPH itself reports rather than the count the serializer predicted. They are equal by the check
    # above; assigning it here is what makes that true by construction rather than by convention.
    record["inputs"]["samples"]["retained"] = observed
    record["inputs"]["samples"]["dropped"] = record["inputs"]["samples"]["detail"]["fam"] - observed
    record["stochastic_settings"]["num_threads"] = scalar_from_log(
        log_lines, NUM_THREADS_PATTERN, "the thread count it ran with"
    )

    # The multi-trait correlation result, oriented against the declared pair. Both its presence and the
    # residual-covariance statement follow from the fit that was actually run: MPH always estimates the
    # residual covariance of a multi-trait model and offers no option to drop it, so a pair result records
    # `estimated` and publishes the residual correlation MPH reported beside the genetic ones.
    if CORRELATIONS:
        record["correlations"] = read_correlations(record)
        record["residual_covariance"] = "estimated"

    record["warnings"] = list(record.get("warnings") or []) + WARNINGS + classify(log_lines)
    # A fit whose aggregate genetic correlation is not a number completed and is published, but it answers
    # nothing, so it is classified rather than presented as an estimate.
    total_nonestimable = CORRELATIONS and record["correlations"]["total"]["correlation"] is None
    record["classification"] = (
        "completed_nonestimable"
        if total_nonestimable
        else "estimable" if not record["warnings"] else "estimable_with_warning"
    )

    with open("{}.provenance.json".format(PREFIX), "w", newline="\\n") as handle:
        handle.write(json.dumps(record, indent=2) + "\\n")

    # Written here rather than captured by an `eval` output, which Nextflow allows only on a Bash script.
    with open("versions.yml", "w", newline="\\n") as handle:
        handle.write('"{}":\\n    python: {}\\n'.format(PROCESS_NAME, sys.version.split()[0]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
