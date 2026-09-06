#!/usr/bin/env python3
"""Derive the genome-wide total genetic correlation of a multi-component GCTA bivariate REML fit.

GCTA's `--reml-bivar --mgrm` reports one genetic correlation per component and no genome-wide total. That is
an unimplemented feature rather than a numerical fault: univariate REML sums its components deliberately and
fences bivariate mode out, the newer HEreg estimator in the same package does print a total for the same
model, and the complete sampling variance/covariance matrix a valid total needs is already written. Issue #34
records the analysis and the decision to derive the total here; #21 is the closed gap record.

    rg_total = sum_k C(Gk)_tr12 / sqrt( sum_k V(Gk)_tr1 * sum_k V(Gk)_tr2 )

with a delta-method standard error over the 3K genetic parameters, taken from the full sampling
variance/covariance matrix. It is never computed from the marginal per-component standard errors, which would
ignore every cross-component covariance and is the construction #12 forbids.

Everything published here is labelled derived. The native `.hsq` and `.log` are republished untouched beside
these files, the derived table names its own file, its `origin` column and its provenance sidecar, and the
per-component rows carry GCTA's own text verbatim with `origin = native`.

Where the inputs come from, measured on the pinned image `gcta:1.94.1--9bc35dc424fcf6e9`:

    the variance components, their standard errors and the per-component rG rows are in the `.hsq`
    the sampling variance/covariance matrix is in the `.log` ONLY -- it is in no `.hsq` of any bivariate
        layout (K = 1, K = 2, and K = 2 without a residual covariance were all measured)
    with `--reml-bivar-prevalence` the liability-scale `V(G)/Vp_*_L` rows are likewise in the `.log` only
        (issue #41), which is why nothing here reads a scale-transformed row out of the `.hsq`

Two runtime checks stand between the parsed matrix and the published standard error, because the delta-method
variance is a pure function of the matrix and would be silently wrong if the parameter order were not what
this parser assumes:

    the diagonal check -- sqrt of each diagonal entry must reproduce the corresponding `.hsq` standard error
    the per-component check -- GCTA's own `calcu_rg` construction, recomputed from each component's own 3x3
        block, must reproduce the `rGk` row GCTA printed

The diagonal check alone is not sufficient: it is invariant under any permutation of parameters with similar
standard errors and sees no off-diagonal entry at all, while the delta-method variance depends on nothing but
the off-diagonals. Only the per-component check sees them.

Failure policy. This runs after a successful native fit whose result is already published, so a non-zero exit
here aborts a run that answered its question. Only a STRUCTURAL contradiction exits non-zero -- the heading
absent or repeated, a non-square block, a dimension or label order that disagrees with the `.hsq`, a failed
cross-check -- because those mean the parser's assumptions about GCTA's output no longer hold and any derived
number would be untrustworthy. Every DATA outcome of a converged fit -- a non-finite native value, a
non-positive genetic variance sum, a non-positive delta-method variance -- is classified and named in the
warning vocabulary, never raised.
"""

import json
import math
import re
import sys

META_JSON = $meta_literal
CAPABILITY_JSON = $capability_literal
NATIVE_RESULT = $native_result_literal
NATIVE_LOG = $native_log_literal
PREFIX = $prefix_literal
PROCESS_NAME = $task_process_literal

# MANDATORY: both literals are JSON *strings*, not Python dict literals. A single Groovy encoding would emit
# JSON `true`/`false`/`null`, which are not Python literals.
META = json.loads(META_JSON)
CAPABILITY = json.loads(CAPABILITY_JSON)

HEADING = "Sampling variance/covariance of the estimates of variance components:"
CONVERGED = "Log-likelihood ratio converged."
AI_REML_START = "Running AI-REML algorithm"
BENDING_NOTE = "is bended to be positive definite"
CONSTRAINED_PATTERN = re.compile(r"\\((\\d+) component\\(s\\) constrained\\)")
INDIVIDUALS_PATTERN = re.compile(r"^(\\d+) individuals are in common in these files\\.")
NONMISSING_PATTERN = re.compile(r"^(\\d+) non-missing phenotypes for trait #1 and (\\d+) for trait #2")
GENETIC_VARIANCE_PATTERN = re.compile(r"V\\(G(\\d*)\\)_tr1")

# GCTA positively announces every reason a residual covariance is absent, so nothing here is inferred by
# elimination. The automatic drops are printed by `bivar_reml.cpp`; the requested drop is echoed into the
# log's `Accepted options:` block by `option.cpp` and was confirmed on the pinned image.
RESIDUAL_COVARIANCE_MARKERS = [
    (
        "Note: the residual covariance component is ignored because no individuals were measured for both traits.",
        "dropped_disjoint",
    ),
    (
        "Note: the residual covariance component is ignored because < 10% of individuals were measured for both traits.",
        "dropped_low_overlap",
    ),
    ("--reml-bivar-nocove", "dropped_by_request"),
]

# The `.hsq` standard error is printed fixed at six decimals, so it carries a half-ulp of 5e-7 in absolute
# terms; the log prints each sampling variance as `%.6e`, so its square root carries 2.5e-7 in RELATIVE terms.
# The exact rounding bound is therefore `5e-7 + 2.5e-7 * SE`, and the constants below are that with twice the
# slack. Observed maxima on the pinned image over the K = 1, K = 2 and K = 2 no-residual-covariance probes:
# 3.53e-07, 4.43e-07 and 4.87e-07 (evidence-gcta-rg/contract_report.txt).
DIAGONAL_ABSOLUTE_TOLERANCE = 1e-6
DIAGONAL_RELATIVE_TOLERANCE = 1e-6
# The block is written from a symmetric matrix and was measured to be exactly symmetric, so this admits only
# a formatting artefact.
SYMMETRY_ABSOLUTE_TOLERANCE = 1e-12
SYMMETRY_RELATIVE_TOLERANCE = 1e-6
# GCTA's own per-component standard error is recomputed from six-decimal inputs, so it agrees to a few parts
# in ten thousand rather than exactly.
COMPONENT_SE_ABSOLUTE_TOLERANCE = 1e-4
COMPONENT_SE_RELATIVE_TOLERANCE = 1e-3
# A component GCTA pinned at its constrain floor has a near-singular block whose native standard error is not
# reproducible from it. GCTA's floor is a fraction of the phenotypic sum of squares (`est_hsq.cpp`), so the
# predicate compares each parameter against the phenotypic variance of the trait it belongs to. It must not
# be a fraction of the largest GENETIC variance in the fit: the candidate's own parameters are part of that
# maximum, so the component attaining it can never satisfy the test, and a single-component fit -- which the
# one-stratum LDMS plan produces -- can therefore never be exempt at all.
CONSTRAIN_FLOOR_RATIO = 1e-3

WARNINGS = []


def fail(message):
    sys.exit("[nf-core/gwas] ERROR: pair request '{}': {}".format(META["request_id"], message))


def is_finite(value):
    return value == value and value not in (float("inf"), float("-inf"))


def finite(value):
    """The JSON form of a number GCTA printed: the value itself, or null when it is not a real number.

    Every float that reaches the provenance record goes through this, so `allow_nan=False` on the writer
    stays the assertion it was meant to be rather than a crash path. A non-finite value is a DATA outcome of
    a fit that already succeeded, and this module classifies those rather than raising.
    """
    if value is None or not is_finite(value):
        return None
    return value


def read_lines(path):
    with open(path) as handle:
        return [line.rstrip("\\r\\n") for line in handle]


def parse_native_result():
    """Read the `.hsq` variance-component rows and the per-component correlations.

    The variance-component rows are exactly the rows before the first `Vp_tr1` row. Nothing after it is read
    positionally and the correlations are selected by label, because GCTA appends rows whose value column is
    not a number: `--reml-bivar-lrt-rg`, which the pipeline's native-argument firewall accepts, adds
    `logL0 -1868.587 (when rG fixed at 0.000)` and `Pval 1.9293e-01 (one-tailed test)`.
    """
    rows = []
    for line in read_lines(NATIVE_RESULT):
        if not line.strip():
            continue
        parts = line.split("\\t")
        if parts[0] == "Source":
            continue
        rows.append(parts)
    if not rows:
        fail("the native result '{}' has no rows".format(NATIVE_RESULT))

    variance_rows = []
    for row in rows:
        if row[0].startswith("Vp_tr1"):
            break
        variance_rows.append(row)
    labelled = {row[0]: row for row in rows}

    suffixes = []
    for row in variance_rows:
        match = GENETIC_VARIANCE_PATTERN.fullmatch(row[0])
        if match:
            suffixes.append(match.group(1))
    if not suffixes:
        fail(
            "the native result '{}' has no 'V(G)_tr1' or 'V(G<k>)_tr1' row, so it is not a bivariate REML "
            "result this pipeline recognises".format(NATIVE_RESULT)
        )
    if suffixes == [""]:
        layout = "single_component"
    else:
        layout = "multi_component"
        if suffixes != [str(index + 1) for index in range(len(suffixes))]:
            fail(
                "the native result '{}' numbers its genetic components {} rather than 1..{}".format(
                    NATIVE_RESULT, ", ".join(suffixes), len(suffixes)
                )
            )
    n_components = len(suffixes)

    expected = []
    for suffix in suffixes:
        expected += ["V(G{})_tr1".format(suffix), "V(G{})_tr2".format(suffix), "C(G{})_tr12".format(suffix)]
    expected += ["V(e)_tr1", "V(e)_tr2"]
    observed = [row[0] for row in variance_rows]
    residual_covariance_estimated = observed[len(expected) :] == ["C(e)_tr12"]
    if residual_covariance_estimated:
        expected += ["C(e)_tr12"]
    if observed != expected:
        fail(
            "the native result '{}' lists variance components as [{}] but this parser and the sampling "
            "covariance block it reads require [{}]".format(
                NATIVE_RESULT, ", ".join(observed), ", ".join(expected)
            )
        )

    values = []
    values_text = []
    standard_errors = []
    standard_errors_text = []
    for row in variance_rows:
        if len(row) < 3:
            fail("row '{}' of the native result '{}' has no standard error".format(row[0], NATIVE_RESULT))
        try:
            value = float(row[1])
            standard_error = float(row[2])
        except ValueError:
            fail(
                "row '{}' of the native result '{}' does not hold a numeric variance and standard "
                "error".format(row[0], NATIVE_RESULT)
            )
        if not (is_finite(value) and is_finite(standard_error)):
            WARNINGS.append("non_finite_native_value")
        values.append(value)
        values_text.append(row[1])
        standard_errors.append(standard_error)
        standard_errors_text.append(row[2])

    correlations = []
    for suffix in suffixes:
        label = "rG{}".format(suffix)
        row = labelled.get(label)
        if row is None:
            fail(
                "the native result '{}' has no '{}' row for the genetic component it declares".format(
                    NATIVE_RESULT, label
                )
            )
        if len(row) < 3:
            fail("row '{}' of the native result '{}' has no standard error".format(label, NATIVE_RESULT))
        # The correlation rows are inspected for finiteness too, not only the variance-component rows: GCTA
        # does print `-nan` in an `rG` row of this family, with every other row a real number.
        for cell in row[1:3]:
            try:
                if not is_finite(float(cell)):
                    WARNINGS.append("non_finite_native_value")
            except ValueError:
                WARNINGS.append("non_finite_native_value")
        correlations.append([row[1], row[2]])

    observations = None
    if "n" in labelled:
        try:
            observations = int(float(labelled["n"][1]))
        except (IndexError, ValueError):
            observations = None
    log_likelihood = None
    if "logL" in labelled:
        try:
            log_likelihood = float(labelled["logL"][1])
        except (IndexError, ValueError):
            log_likelihood = None

    # The two phenotypic variances, which are the scale GCTA's own constrain floor is a fraction of. They are
    # read here rather than recomputed from the components, because a fit without a residual covariance sums
    # a different set of rows.
    phenotypic_variances = []
    for label in ["Vp_tr1", "Vp_tr2"]:
        row = labelled.get(label)
        try:
            phenotypic_variances.append(float(row[1]))
        except (IndexError, TypeError, ValueError):
            phenotypic_variances.append(None)

    return {
        "layout": layout,
        "n_components": n_components,
        "labels": expected,
        "values": values,
        "values_text": values_text,
        "standard_errors": standard_errors,
        "standard_errors_text": standard_errors_text,
        "correlations": correlations,
        "phenotypic_variances": phenotypic_variances,
        "residual_covariance_estimated": residual_covariance_estimated,
        "observations": observations,
        "log_likelihood": log_likelihood,
    }


def parse_sampling_covariance(log_lines, order):
    """Read the P x P sampling variance/covariance block out of the native log.

    GCTA writes it to the log and to no other file. `--reml-bivar-lrt-rg` makes the process fit a second,
    correlation-fixed model, but the block is still written once and belongs to the first model.
    """
    positions = [index for index, line in enumerate(log_lines) if line.strip() == HEADING]
    if not positions:
        fail(
            "the native log '{}' carries no '{}' block. GCTA writes the sampling variance/covariance of the "
            "variance-component estimates only there, and the delta-method total cannot be derived without "
            "it".format(NATIVE_LOG, HEADING)
        )
    if len(positions) > 1:
        fail(
            "the native log '{}' carries {} '{}' blocks; exactly one is expected and this parser cannot tell "
            "which model each belongs to".format(NATIVE_LOG, len(positions), HEADING)
        )

    matrix = []
    for line in log_lines[positions[0] + 1 :]:
        if not line.strip():
            break
        try:
            matrix.append([float(cell) for cell in line.split()])
        except ValueError:
            fail(
                "a row of the sampling covariance block in '{}' is not numeric: '{}'".format(NATIVE_LOG, line)
            )

    size = len(order)
    widths = sorted({len(row) for row in matrix})
    if len(matrix) != size or widths != [size]:
        fail(
            "the sampling covariance block in '{}' is {}x{}, but the native result declares {} variance "
            "components [{}]".format(
                NATIVE_LOG, len(matrix), widths or "[]", size, ", ".join(order)
            )
        )
    # A non-finite entry is a data outcome of a converged fit, so it is named rather than raised. It is
    # recorded before the symmetry check, whose `> tolerance` comparison is False for a NaN and would
    # otherwise let one through in silence.
    if not all(is_finite(cell) for row in matrix for cell in row):
        WARNINGS.append("non_finite_native_value")
    for i in range(size):
        for j in range(i):
            if not (is_finite(matrix[i][j]) and is_finite(matrix[j][i])):
                continue
            deviation = abs(matrix[i][j] - matrix[j][i])
            if deviation > SYMMETRY_ABSOLUTE_TOLERANCE + SYMMETRY_RELATIVE_TOLERANCE * abs(matrix[i][j]):
                fail(
                    "the sampling covariance block in '{}' is not symmetric at ({}, {}): {} against {}".format(
                        NATIVE_LOG, order[i], order[j], matrix[i][j], matrix[j][i]
                    )
                )
    return matrix


def check_diagonal(matrix, native):
    """sqrt of every diagonal entry must reproduce the standard error the `.hsq` printed for that row.

    A row whose entry or standard error is not a real number is skipped and excluded from the reported
    maximum, because folding a NaN into the comparison would report a deviation of zero for a row that was
    never actually compared. Its non-finiteness is already in the warning vocabulary.
    """
    worst = 0.0
    for index, label in enumerate(native["labels"]):
        entry = matrix[index][index]
        standard_error = native["standard_errors"][index]
        if not (is_finite(entry) and is_finite(standard_error)):
            continue
        if entry < 0.0:
            fail(
                "the sampling variance of '{}' in '{}' is negative ({}), so it cannot be the variance of an "
                "estimate".format(label, NATIVE_LOG, entry)
            )
        deviation = abs(math.sqrt(entry) - standard_error)
        worst = max(worst, deviation)
        if deviation > DIAGONAL_ABSOLUTE_TOLERANCE + DIAGONAL_RELATIVE_TOLERANCE * abs(standard_error):
            fail(
                "the sampling covariance block in '{}' does not describe the native result '{}': the square "
                "root of its diagonal entry {} for '{}' is {:.9f}, against the standard error {:.6f} that "
                "row reports. The block's dimension, its parameter order, or the fit it belongs to is not "
                "the one this parser assumes".format(
                    NATIVE_LOG, NATIVE_RESULT, entry, label, math.sqrt(entry), standard_error
                )
            )
    return worst


def component_pinned(native, index):
    """Is component `index` pinned at GCTA's constrain floor?

    The floor is a fraction of the phenotypic sum of squares rather than an absolute constant, so the
    reference has to be the phenotypic variance of the trait each parameter belongs to. Deliberately NOT the
    largest genetic variance in the fit: that maximum includes the candidate's own parameters, so the
    component attaining it could never be exempt, and a single-component fit -- the one-stratum LDMS layout --
    could never be exempt at all.
    """
    left_vp, right_vp = native["phenotypic_variances"]
    if not (left_vp and right_vp and is_finite(left_vp) and is_finite(right_vp) and left_vp > 0.0 and right_vp > 0.0):
        return False
    base = 3 * index
    return (
        abs(native["values"][base]) <= CONSTRAIN_FLOOR_RATIO * left_vp
        and abs(native["values"][base + 1]) <= CONSTRAIN_FLOOR_RATIO * right_vp
        and abs(native["values"][base + 2]) <= CONSTRAIN_FLOOR_RATIO * math.sqrt(left_vp * right_vp)
    )


def check_components(matrix, native, constrained_components):
    """Recompute each `rGk` and its standard error from that component's own 3x3 block.

    This is GCTA's own `calcu_rg` construction. It is the only runtime check that reads the off-diagonal
    entries the delta-method variance is built from, so it is what actually validates the parameter order.
    """
    records = []
    for index in range(native["n_components"]):
        base = 3 * index
        left = native["values"][base]
        right = native["values"][base + 1]
        covariance = native["values"][base + 2]
        label = "G{}".format(index + 1)
        native_rg = native["correlations"][index][0]
        native_se = native["correlations"][index][1]
        record = {
            "component": label,
            "rg_abs_deviation": None,
            "rg_tolerance": None,
            "se_relative_deviation": None,
            "se_checked": False,
        }

        # Nothing is recomputed from a value that is not a real number: a NaN passes every `> tolerance`
        # comparison below silently and would then be stored in the record.
        if not all(is_finite(value) for value in (left, right, covariance)):
            WARNINGS.append("component_se_cross_check_skipped:{}".format(label))
            records.append(record)
            continue
        # GCTA's own guard is the product rather than each factor: two negative variances still yield a
        # printed correlation, so the recomputation must use the same rule.
        if not (left * right > 0.0) or covariance == 0.0:
            WARNINGS.append("component_se_cross_check_skipped:{}".format(label))
            records.append(record)
            continue
        try:
            native_rg_value = float(native_rg)
            native_se_value = float(native_se)
        except ValueError:
            WARNINGS.append("component_se_cross_check_skipped:{}".format(label))
            records.append(record)
            continue
        if not (is_finite(native_rg_value) and is_finite(native_se_value)):
            WARNINGS.append("component_se_cross_check_skipped:{}".format(label))
            records.append(record)
            continue

        recomputed = covariance / math.sqrt(left * right)
        # The rounding of the three six-decimal `.hsq` inputs propagated through the correlation, plus the
        # half-ulp of the printed correlation itself, with twice the slack. A fixed absolute tolerance is
        # wrong here: the propagated bound spans four orders of magnitude across real fits.
        tolerance = 2.0 * (
            5e-7
            + 5e-7 / math.sqrt(abs(left * right))
            + abs(recomputed) * 5e-7 * (1.0 / (2.0 * abs(left)) + 1.0 / (2.0 * abs(right)))
        )
        deviation = abs(recomputed - native_rg_value)
        record["rg_abs_deviation"] = finite(deviation)
        record["rg_tolerance"] = finite(tolerance)
        if deviation > tolerance:
            fail(
                "the native result '{}' reports {} = {:.6f} for component {}, but its own variance "
                "components give {:.6f}. The '.hsq' rows this parser reads are not the rows GCTA computed "
                "that correlation from".format(NATIVE_RESULT, "rG" + str(index + 1), native_rg_value, label, recomputed)
            )

        variance = recomputed * recomputed * (
            matrix[base][base] / (4.0 * left * left)
            + matrix[base + 1][base + 1] / (4.0 * right * right)
            + matrix[base + 2][base + 2] / (covariance * covariance)
            + matrix[base][base + 1] / (2.0 * left * right)
            - matrix[base][base + 2] / (left * covariance)
            - matrix[base + 1][base + 2] / (right * covariance)
        )
        if variance <= 0.0 or not is_finite(variance):
            WARNINGS.append("component_se_cross_check_skipped:{}".format(label))
            records.append(record)
            continue
        if constrained_components > 0 and component_pinned(native, index):
            # A component held at the constrain floor has a near-singular block. GCTA still prints a standard
            # error for it and it is not reproducible from the block, so the comparison says nothing.
            WARNINGS.append("component_se_cross_check_skipped:{}".format(label))
            records.append(record)
            continue

        recomputed_se = math.sqrt(variance)
        record["se_relative_deviation"] = finite(
            abs(recomputed_se - native_se_value) / native_se_value if native_se_value else None
        )
        record["se_checked"] = True
        if abs(recomputed_se - native_se_value) > max(
            COMPONENT_SE_ABSOLUTE_TOLERANCE, COMPONENT_SE_RELATIVE_TOLERANCE * abs(native_se_value)
        ):
            fail(
                "the sampling covariance block in '{}' does not reproduce the standard error GCTA printed "
                "for {} of component {}: {:.6f} recomputed from its 3x3 block against the native {:.6f}. The "
                "block's off-diagonal entries are not in the parameter order this parser assumes, and the "
                "delta-method standard error of the total depends on nothing else".format(
                    NATIVE_LOG, "rG" + str(index + 1), label, recomputed_se, native_se_value
                )
            )
        records.append(record)
    return records


def sum_standard_error(matrix, indices):
    """Standard error of a sum of estimates: the square root of the sum of their covariance sub-block."""
    variance = 0.0
    for i in indices:
        for j in indices:
            variance += matrix[i][j]
    # A non-finite sum is already named `non_finite_native_value` by the block parser, so it is not also
    # reported as a non-positive sampling variance, which it is not.
    if not is_finite(variance):
        return None
    if variance < 0.0:
        WARNINGS.append("total_se_nonpositive_sampling_variance")
        return None
    return math.sqrt(variance)


def derive_total(matrix, native):
    """The genome-wide total and its delta-method standard error over the 3K genetic parameters."""
    left_indices = [3 * index for index in range(native["n_components"])]
    right_indices = [3 * index + 1 for index in range(native["n_components"])]
    covariance_indices = [3 * index + 2 for index in range(native["n_components"])]
    left = sum(native["values"][index] for index in left_indices)
    right = sum(native["values"][index] for index in right_indices)
    covariance = sum(native["values"][index] for index in covariance_indices)

    total = {
        "left_variance": left,
        "left_variance_se": sum_standard_error(matrix, left_indices),
        "right_variance": right,
        "right_variance_se": sum_standard_error(matrix, right_indices),
        "covariance": covariance,
        "covariance_se": sum_standard_error(matrix, covariance_indices),
        "rg": None,
        "rg_se": None,
    }

    # A non-finite sum is already named `non_finite_native_value` where it was read, and is not a
    # non-positive genetic variance, so it is not reported as one. The total is simply not derivable.
    if not (is_finite(left) and is_finite(right) and is_finite(covariance)):
        return total
    # Deliberately stricter than GCTA's per-component `V1 * V2 > 0`: two negative sums give a real square
    # root and a meaningless genome-wide correlation.
    if not (left > 0.0 and right > 0.0):
        WARNINGS.append("total_nonestimable_nonpositive_genetic_variance")
        return total

    scale = math.sqrt(left * right)
    correlation = covariance / scale
    total["rg"] = correlation

    # d rg / d V(Gk)_tr1 = -rg / (2 * sum V(Gk)_tr1), the same for every k; likewise for tr2; and
    # d rg / d C(Gk)_tr12 = 1 / sqrt(sum V(Gk)_tr1 * sum V(Gk)_tr2). The residual parameters do not enter.
    gradient = [0.0] * len(native["labels"])
    for index in range(native["n_components"]):
        base = 3 * index
        gradient[base] = -correlation / (2.0 * left)
        gradient[base + 1] = -correlation / (2.0 * right)
        gradient[base + 2] = 1.0 / scale

    variance = 0.0
    for i, gi in enumerate(gradient):
        if gi == 0.0:
            continue
        for j, gj in enumerate(gradient):
            if gj == 0.0:
                continue
            variance += gi * matrix[i][j] * gj
    # A non-finite variance follows from a non-finite entry in the block, which is already named where it was
    # read; it is not a non-positive sampling variance and is not reported as one.
    if not is_finite(variance):
        return total
    # GCTA reports that it bends a variance-covariance matrix to positive-definiteness, so the block is not
    # guaranteed to be positive semi-definite and a negative variance is reachable. Never take its root.
    if variance < 0.0:
        WARNINGS.append("total_se_nonpositive_sampling_variance")
        return total
    total["rg_se"] = math.sqrt(variance)
    if abs(correlation) > 1.0:
        WARNINGS.append("total_genetic_correlation_outside_unit_interval")
    return total


def count_constrained_components(log_lines):
    """The constrained-component count of the FITTED model.

    The scan stops at the first convergence marker. `--reml-bivar-lrt-rg` makes GCTA fit a second,
    correlation-fixed null model whose iterations carry their own constrained markers, and the sampling
    covariance this module integrates over belongs to the first model.
    """
    started = False
    count = 0
    for line in log_lines:
        if not started:
            if line.startswith(AI_REML_START):
                started = True
            continue
        if line.strip() == CONVERGED:
            break
        match = CONSTRAINED_PATTERN.search(line)
        if match:
            count = int(match.group(1))
    return count


def resolve_residual_covariance(log_lines, native):
    """Decide why a residual covariance is absent from positive native markers, never by elimination."""
    if native["residual_covariance_estimated"]:
        return "estimated", None
    WARNINGS.append("residual_covariance_absent")
    for marker, value in RESIDUAL_COVARIANCE_MARKERS:
        for line in log_lines:
            if line.strip() == marker:
                return value, line.strip()
    return "absent_reason_undetermined", None


def scalar_from_log(log_lines, pattern, group=1):
    for line in log_lines:
        match = pattern.match(line)
        if match:
            return int(match.group(group))
    return None


def render(value):
    """Derived numbers render at GCTA's own six decimals; the provenance carries the full double.

    A value that is not a real number renders as `NA` rather than as the literal `nan` or `inf`, because the
    published contract is that a value the fit does not support is `NA` and never a number.
    """
    return "NA" if finite(value) is None else format(value, ".6f")


def main():
    native = parse_native_result()
    log_lines = read_lines(NATIVE_LOG)
    if not any(line.strip() == CONVERGED for line in log_lines):
        fail(
            "the native log '{}' does not record '{}', so the fit whose sampling covariance this reads did "
            "not converge".format(NATIVE_LOG, CONVERGED)
        )

    matrix = parse_sampling_covariance(log_lines, native["labels"])
    diagonal_deviation = check_diagonal(matrix, native)
    constrained_components = count_constrained_components(log_lines)
    component_records = check_components(matrix, native, constrained_components)
    total = derive_total(matrix, native)

    bended = any(BENDING_NOTE in line for line in log_lines)
    if bended:
        # GCTA prints this only when it actually bent a genetic or residual 2x2 block to
        # positive-definiteness, which is exactly when it declares the standard errors unreliable.
        WARNINGS.append("sampling_covariance_bended_se_unreliable")
    if constrained_components > 0:
        WARNINGS.append("constrained_components:{}".format(constrained_components))
        # The inverse of the average-information matrix is not the asymptotic sampling covariance of a
        # boundary-constrained estimator, so the published standard error is not a confidence statement.
        WARNINGS.append("standard_error_unreliable_constrained_fit")

    residual_covariance, residual_evidence = resolve_residual_covariance(log_lines, native)

    columns = [
        "request_id", "relationship_id", "method", "component",
        "left_analysis_id", "right_analysis_id", "left_trait_id", "right_trait_id",
        "scale",
        "left_variance", "left_variance_se", "right_variance", "right_variance_se",
        "covariance", "covariance_se", "rg", "rg_se", "origin", "n_components",
    ]
    identity = [
        META["request_id"], META["relationship_id"], META["method"], None,
        META["left_analysis_id"], META["right_analysis_id"], META["left_trait_id"], META["right_trait_id"],
        # `scale` qualifies the variance and covariance columns only. GCTA's observed-to-liability transform
        # rescales the variances and leaves the correlation unchanged, so `rg`/`rg_se` need no conversion and
        # the declared prevalence is recorded in the provenance instead.
        "observed",
    ]

    rows = [
        identity[:3] + ["total"] + identity[4:] + [
            render(total["left_variance"]), render(total["left_variance_se"]),
            render(total["right_variance"]), render(total["right_variance_se"]),
            render(total["covariance"]), render(total["covariance_se"]),
            render(total["rg"]), render(total["rg_se"]),
            "delta_method", str(native["n_components"]),
        ]
    ]
    for index in range(native["n_components"]):
        base = 3 * index
        # Native rows carry GCTA's own text verbatim rather than a reformatting of it.
        native_text = [
            native["values_text"][base], native["standard_errors_text"][base],
            native["values_text"][base + 1], native["standard_errors_text"][base + 1],
            native["values_text"][base + 2], native["standard_errors_text"][base + 2],
        ]
        rows.append(
            identity[:3] + ["G{}".format(index + 1)] + identity[4:]
            + native_text
            + [native["correlations"][index][0], native["correlations"][index][1], "native", str(native["n_components"])]
        )

    with open("{}.total_rg.tsv".format(PREFIX), "w", newline="\\n") as handle:
        handle.write("\\t".join(columns) + "\\n")
        for row in rows:
            handle.write("\\t".join(row) + "\\n")

    warnings = sorted(set(WARNINGS))
    classification = "estimable"
    if finite(total["rg"]) is None:
        classification = "completed_nonestimable"
    elif warnings:
        classification = "estimable_with_warning"

    record = {
        "schema_version": "1.1",
        "result": {
            "kind": "pairwise",
            "analysis_id": None,
            "request_id": META["request_id"],
            "relationship_id": META["relationship_id"],
            "method": META["method"],
            "left_analysis_id": META["left_analysis_id"],
            "right_analysis_id": META["right_analysis_id"],
            "primary_files": ["{}.total_rg.tsv".format(PREFIX)],
        },
        "estimator": CAPABILITY,
        "stochastic_settings": None,
        "solver_settings": None,
        "component_plan": {
            "plan_key": META.get("plan_key"),
            "matrix_key": META.get("matrix_key"),
            "settings": META.get("matrix_settings"),
            "components": META.get("matrix_components"),
        },
        "inputs": {
            "samples": {
                "order_source": None,
                "retained": scalar_from_log(log_lines, INDIVIDUALS_PATTERN),
                "dropped": None,
                "left_nonmissing": scalar_from_log(log_lines, NONMISSING_PATTERN, 1),
                "right_nonmissing": scalar_from_log(log_lines, NONMISSING_PATTERN, 2),
                # GCTA computes the two-trait overlap and never prints it, so neither can be reported.
                "both": None,
                "union": None,
            },
            "variants": None,
            "sha256": None,
        },
        "residual_covariance": residual_covariance,
        "derivation": {
            "total_rg": "sum(C(Gk)_tr12) / sqrt(sum(V(Gk)_tr1) * sum(V(Gk)_tr2))",
            "standard_error": "delta_method",
            "native_layout": native["layout"],
            "n_components": native["n_components"],
            "parameter_order": native["labels"],
            "sampling_covariance_source": "native_log",
            # Every float below goes through `finite`, so a value GCTA printed as `nan` or `inf` is published
            # as JSON null rather than aborting the writer. `allow_nan=False` on the dump stays as the
            # assertion that nothing slipped past.
            "sampling_covariance": [[finite(cell) for cell in row] for row in matrix],
            "diagonal_check_max_abs_deviation": finite(diagonal_deviation),
            "component_cross_check": component_records,
            "total_rg_value": finite(total["rg"]),
            "total_rg_standard_error": finite(total["rg_se"]),
            "log_likelihood": finite(native["log_likelihood"]),
            "converged": True,
            # GCTA reports twice the number of individuals here for a bivariate fit, so it is recorded under
            # its own key and never mapped onto a sample count.
            "n_observations": native["observations"],
            "constrained_components": constrained_components,
            "sampling_covariance_bended": bended,
            "residual_covariance_evidence": residual_evidence,
            "reml_bivar_prevalence": META.get("reml_bivar_prevalence"),
            "scale": {"variances": "observed", "correlation": "scale_invariant"},
        },
        "software": {
            "tool": "gcta",
            "process": PROCESS_NAME,
            "versions_record": "pipeline_info/nf_core_gwas_software_mqc_versions.yml",
        },
        "native_arguments": META.get("native_args") or [],
        "classification": classification,
        "warnings": warnings,
    }

    with open("{}.provenance.json".format(PREFIX), "w", newline="\\n") as handle:
        handle.write(json.dumps(record, indent=2, sort_keys=True, allow_nan=False) + "\\n")

    # Written here rather than captured by an `eval` output, which Nextflow allows only on a Bash script.
    with open("versions.yml", "w", newline="\\n") as handle:
        handle.write('"{}":\\n    python: {}\\n'.format(PROCESS_NAME, sys.version.split()[0]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
