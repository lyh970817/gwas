#!/usr/bin/env python3
"""Normalize native dense or LDMS GCTA bivariate REML or HEreg outputs without selecting a result."""

import json
import math
import re
import sys

META = json.loads(${meta_literal})
NATIVE_RESULT = ${native_result_literal}
GCTA_LOG = ${gcta_log_literal}
PAIR_LOG = ${pair_log_literal}
PROCESS_NAME = ${task_process_literal}
CONTAINER = ${task_container_literal}
METHOD = META["method"]
LDMS = METHOD.endswith("_ldms")
HEREG = METHOD in ("gcta_bivariate_he", "gcta_bivariate_he_ldms")
# The total row is the primary published result of a multi-component model; the per-component rows
# are secondary diagnostics of the same fit. GCTA HEreg emits the total natively, so nothing here
# reconstructs one from marginal component standard errors.
TOTAL_COMPONENT = "total"


def fail(message):
    sys.exit("[nf-core/gwas] ERROR: pair request '{}': {}".format(META["request_id"], message))


def parse_number(text):
    try:
        value = float(text)
    except (TypeError, ValueError):
        return None
    return value if math.isfinite(value) else None


def display(value):
    return "NA" if value is None else format(value, ".15g")


def component_sources(suffix):
    return {
        "left_variance": "V(G{})_tr1".format(suffix),
        "right_variance": "V(G{})_tr2".format(suffix),
        "covariance": "C(G{})_tr12".format(suffix),
        "left_heritability": "V(G{})/Vp_tr1".format(suffix),
        "right_heritability": "V(G{})/Vp_tr2".format(suffix),
        "correlation": "rG{}".format(suffix),
    }


# HEreg reports every estimate as a proportion of the standardised phenotypic variance, so there is
# no separate raw variance row and the covariance is on the standardised scale. A model with more than
# one component additionally carries native `Sum of ...` totals and a native `Total rG`.
def hereg_component_sources(suffix):
    if suffix == TOTAL_COMPONENT:
        return {
            "left_heritability": "Sum of V(G)/Vp_tr1",
            "right_heritability": "Sum of V(G)/Vp_tr2",
            "covariance": "Sum of C(G)/Vp_tr12",
            "correlation": "Total rG",
        }
    return {
        "left_heritability": "V(G{})/Vp_tr1".format(suffix),
        "right_heritability": "V(G{})/Vp_tr2".format(suffix),
        "covariance": "C(G{})/Vp_tr12".format(suffix),
        "correlation": "rG{}".format(suffix),
    }


def parse_hsq(path):
    components = {}
    with open(path) as handle:
        lines = [line.strip() for line in handle if line.strip()]
    for line in lines:
        fields = line.split()
        if fields[:3] == ["Source", "Variance", "SE"]:
            continue
        if len(fields) not in (2, 3):
            continue
        source = fields[0]
        if source in components:
            fail("native result '{}' repeats component '{}'".format(path, source))
        estimate_text = fields[1]
        se_text = fields[2] if len(fields) == 3 else None
        components[source] = {
            "estimate": parse_number(estimate_text),
            "standard_error": parse_number(se_text) if se_text is not None else None,
            "native_estimate": estimate_text,
            "native_standard_error": se_text,
        }
    if LDMS:
        suffixes = sorted(
            [
                match.group(1)
                for source in components
                for match in [re.fullmatch(r"V\\(G(\\d*)\\)_tr1", source)]
                if match
            ],
            key=lambda suffix: int(suffix) if suffix else 0,
        )
        if not suffixes:
            fail("native LDMS result '{}' contains no genetic variance components".format(path))
    else:
        suffixes = [""]
    mandatory = ["V(e)_tr1", "V(e)_tr2", "Vp_tr1", "Vp_tr2", "logL", "n"]
    for suffix in suffixes:
        mandatory.extend(component_sources(suffix).values())
    missing = [source for source in mandatory if source not in components]
    if missing:
        fail("native result '{}' is missing mandatory components {}".format(path, ", ".join(missing)))
    return components, suffixes


# `.HEreg` is a padded fixed-width table whose coefficient labels contain single spaces
# ("Sum of V(G)/Vp_tr1", "Total rG"), and the longest of them fills its 20-character field so
# completely that only one space separates it from the estimate. Neither a whitespace split nor a
# two-space split can therefore recover the label, so the accepted coefficient names are enumerated.
HEREG_ROW = re.compile(
    r"^(Coefficient"
    r"|Intercept_tr\\d+"
    r"|Sum of [VC]\\(G\\)/Vp_tr\\d+"
    r"|[VC]\\(G\\d*\\)/Vp_tr\\d+"
    r"|Total rG"
    r"|rG\\d*"
    r"|N_tr\\d+)\\s+(\\S.*?)\\s*\\Z"
)


def parse_hereg(path):
    components = {}
    columns = None
    sections = []
    with open(path) as handle:
        for raw_line in handle:
            line = raw_line.rstrip("\\r\\n")
            if not line.strip():
                continue
            match = HEREG_ROW.match(line)
            if not match:
                sections.append(line.strip())
                continue
            source = match.group(1).strip()
            values = match.group(2).split()
            if source == "Coefficient":
                columns = values
                continue
            if source in components:
                fail("native result '{}' repeats coefficient '{}'".format(path, source))
            components[source] = {
                "estimate": parse_number(values[0]),
                "standard_error": parse_number(values[2]) if len(values) > 2 else None,
                "standard_error_ols": parse_number(values[1]) if len(values) > 1 else None,
                "native_estimate": values[0],
                "native_standard_error": values[2] if len(values) > 2 else None,
                "native_standard_error_ols": values[1] if len(values) > 1 else None,
                "native_p_ols": values[3] if len(values) > 3 else None,
                "native_p_jackknife": values[4] if len(values) > 4 else None,
            }
    if "HE-CP" not in sections:
        fail("native result '{}' contains no HE-CP section".format(path))
    if columns is None or columns[:3] != ["Estimate", "SE_OLS", "SE_Jackknife"]:
        fail("native result '{}' does not declare the expected Estimate/SE_OLS/SE_Jackknife columns".format(path))
    numbered = sorted(
        [
            match.group(1)
            for source in components
            for match in [re.fullmatch(r"V\\(G(\\d+)\\)/Vp_tr1", source)]
            if match
        ],
        key=int,
    )
    if not LDMS:
        ordered = [""]
    elif numbered:
        ordered = [TOTAL_COMPONENT] + numbered
    else:
        # A component plan that resolves to one stratum makes GCTA emit the one-component layout even
        # under `--mgrm`: there is nothing to sum, so it writes no `Sum of ...` rows and no `Total rG`.
        # The single component is then itself the genome-wide total and is published as such.
        ordered = [TOTAL_COMPONENT]
    sources_by_component = {
        component: hereg_component_sources("") if component == TOTAL_COMPONENT and not numbered else hereg_component_sources(component)
        for component in ordered
    }
    mandatory = ["Intercept_tr1", "Intercept_tr2", "Intercept_tr12", "N_tr1", "N_tr2"]
    for component in ordered:
        mandatory.extend(sources_by_component[component].values())
    missing = [source for source in mandatory if source not in components]
    if missing:
        fail("native result '{}' is missing mandatory coefficients {}".format(path, ", ".join(missing)))
    jackknife_order = [
        "{}_{}".format("G{}".format(suffix) if suffix else "G", part)
        for suffix in (numbered or [""])
        for part in ["tr1", "tr2", "tr12"]
    ]
    return components, ordered, sources_by_component, jackknife_order


# GCTA writes the complete jackknife sampling variance/covariance matrix of the estimates to the log
# and never to the `.HEreg` table. Retaining it is what makes the native total standard error
# auditable and what a later delta-method derivation would need.
def parse_jackknife_covariance(text, expected_order):
    match = re.search(
        r"Jackknife sampling variance/covariance of the estimates of heritability:\\s*\\n((?:\\s*[-0-9].*\\n)+)",
        text,
    )
    if not match:
        return None
    rows = []
    for line in match.group(1).splitlines():
        cells = line.split()
        if not cells:
            continue
        row = [parse_number(cell) for cell in cells]
        if any(value is None for value in row):
            return None
        rows.append(row)
    if not rows or any(len(row) != len(rows) for row in rows):
        return None
    if len(rows) != len(expected_order):
        return None
    return {"parameter_order": expected_order, "matrix": rows}


def parse_pair_log(path):
    values = {}
    with open(path) as handle:
        for line_number, line in enumerate(handle, start=1):
            fields = line.rstrip("\\r\\n").split("\\t")
            if len(fields) != 2 or not fields[0]:
                fail("pair diagnostic '{}' line {} must contain one metric and one value".format(path, line_number))
            values[fields[0]] = fields[1]
    required = ["left_samples", "right_samples", "endpoint_overlap_samples", "union_samples", "left_nonmissing", "right_nonmissing", "both_nonmissing", "quantitative_covariate_samples", "categorical_covariate_samples"]
    missing = [name for name in required if name not in values]
    if missing:
        fail("pair diagnostic '{}' is missing metrics {}".format(path, ", ".join(missing)))
    return values


with open(GCTA_LOG) as handle:
    log_text = handle.read()
if HEREG:
    components, component_suffixes, hereg_sources, jackknife_order = parse_hereg(NATIVE_RESULT)
    sources_for = hereg_sources.get
else:
    components, component_suffixes = parse_hsq(NATIVE_RESULT)
    sources_for = component_sources
pair_diagnostics = parse_pair_log(PAIR_LOG)

common_match = re.search(r"(\\d+) individuals are in common", log_text)
nonmissing_match = re.search(r"(\\d+) non-missing phenotypes for trait #1 and (\\d+) for trait #2", log_text)
version_match = re.search(r"version v([0-9.]+)", log_text)

if HEREG:
    # A moment estimator has nothing to converge; the native run either produced the table or failed.
    converged = None
    jackknife_covariance = parse_jackknife_covariance(log_text, jackknife_order)
else:
    converged = bool(re.search(r"Log-likelihood ratio converged", log_text, flags=re.IGNORECASE))
    jackknife_covariance = None
    if not converged:
        fail("native log '{}' does not confirm REML convergence".format(GCTA_LOG))

warning_patterns = [
    ("bended_information_matrix", r"matrix is bended"),
    ("constrained_component", r"component\\(s\\) constrained|constrain the .* component"),
    ("unreliable_standard_error", r"SE is unreliable"),
]
warnings = [name for name, pattern in warning_patterns if re.search(pattern, log_text, flags=re.IGNORECASE)]
# The classification describes the request's primary published result. A multi-component HEreg request
# publishes the native genome-wide total as that result, so a component the moment estimator could not
# resolve is a recorded warning on a secondary row rather than a nonestimable request.
primary_suffixes = [TOTAL_COMPONENT] if HEREG and LDMS else component_suffixes
primary_components = []
for suffix in component_suffixes:
    sources = sources_for(suffix)
    component = TOTAL_COMPONENT if suffix == TOTAL_COMPONENT else "G{}".format(suffix)
    warning_suffix = ":" + component if LDMS else ""
    rg = components[sources["correlation"]]["estimate"]
    if rg is not None and abs(rg) > 1:
        warnings.append("genetic_correlation_outside_unit_interval" + warning_suffix)
    elif rg is not None and abs(rg) == 1:
        warnings.append("genetic_correlation_at_boundary" + warning_suffix)

    for side, source in [("left", sources["left_heritability"]), ("right", sources["right_heritability"])]:
        h2 = components[source]["estimate"]
        if h2 is not None and (h2 < 0 or h2 > 1):
            warnings.append("{}_heritability_outside_unit_interval{}".format(side, warning_suffix))
        elif h2 is not None and h2 in (0, 1):
            warnings.append("{}_heritability_at_boundary{}".format(side, warning_suffix))

    estimands = [components[sources[name]] for name in ["left_heritability", "right_heritability", "covariance", "correlation"]]
    if suffix in primary_suffixes:
        primary_components.extend(estimands)
    elif any(estimand["estimate"] is None or estimand["standard_error"] is None for estimand in estimands):
        warnings.append("nonestimable_component:" + component)

variance_sources = ["V(e)_tr1", "V(e)_tr2", "Vp_tr1", "Vp_tr2"] if not HEREG else []
for suffix in component_suffixes:
    sources = sources_for(suffix)
    variance_sources.extend([sources[name] for name in ["left_variance", "right_variance"] if name in sources])
for source in variance_sources:
    if components[source]["estimate"] is not None and components[source]["estimate"] < 0:
        warnings.append("negative_variance_component:" + source)

estimable = all(component["estimate"] is not None and component["standard_error"] is not None for component in primary_components)
if converged is False or not estimable:
    classification = "completed_nonestimable"
elif warnings:
    classification = "estimable_with_warning"
else:
    classification = "estimable"


def write_tsv(path, header, rows):
    with open(path, "w", newline="") as handle:
        handle.write("\\t".join(header) + "\\n")
        for row in rows:
            handle.write("\\t".join(str(value) for value in row) + "\\n")


# HEreg standardises both phenotypes before fitting, so its covariance is expressed in standardised
# units rather than on the raw observed phenotype scale REML reports. The correlation is scale free
# and therefore directly comparable between the two estimators.
COVARIANCE_SCALE = "observed_standardised" if HEREG else "observed"

common = [META["relationship_id"], META["request_id"], METHOD]
heritability_rows = []
for component_suffix in component_suffixes:
    sources = sources_for(component_suffix)
    component = TOTAL_COMPONENT if component_suffix == TOTAL_COMPONENT else "G{}".format(component_suffix)
    for side, source in [
        ("left", sources["left_heritability"]),
        ("right", sources["right_heritability"]),
    ]:
        endpoint = {
            "analysis_id": META[side + "_analysis_id"],
            "trait_id": META[side + "_trait_id"],
            "trait_type": META[side + "_trait_type"],
        }
        observed = components[source]
        prefix = common + ([component] if LDMS else [])
        heritability_rows.append(prefix + [side, endpoint["analysis_id"], endpoint["trait_id"], endpoint["trait_type"], "observed", display(observed["estimate"]), display(observed["standard_error"]), classification])
        liability_key = source + "_L"
        if liability_key in components:
            liability = components[liability_key]
            heritability_rows.append(prefix + [side, endpoint["analysis_id"], endpoint["trait_id"], endpoint["trait_type"], "liability", display(liability["estimate"]), display(liability["standard_error"]), classification])
write_tsv(
    "heritability.tsv",
    ["relationship_id", "request_id", "method"] + (["component"] if LDMS else []) + ["endpoint", "analysis_id", "trait_id", "trait_type", "scale", "estimate", "standard_error", "classification"],
    heritability_rows,
)

correlation_rows = []
covariance_rows = []
for suffix in component_suffixes:
    sources = sources_for(suffix)
    component = TOTAL_COMPONENT if suffix == TOTAL_COMPONENT else "G{}".format(suffix)
    prefix = common + ([component] if LDMS else [])
    rg = components[sources["correlation"]]
    covariance = components[sources["covariance"]]
    correlation_rows.append(prefix + [META["left_analysis_id"], META["right_analysis_id"], META["left_trait_id"], META["right_trait_id"], display(rg["estimate"]), display(rg["standard_error"]), classification])
    covariance_rows.append(prefix + [META["left_analysis_id"], META["right_analysis_id"], META["left_trait_id"], META["right_trait_id"], COVARIANCE_SCALE, display(covariance["estimate"]), display(covariance["standard_error"]), classification])
write_tsv(
    "genetic_correlation.tsv",
    ["relationship_id", "request_id", "method"] + (["component"] if LDMS else []) + ["left_analysis_id", "right_analysis_id", "left_trait_id", "right_trait_id", "estimate", "standard_error", "classification"],
    correlation_rows,
)
write_tsv(
    "genetic_covariance.tsv",
    ["relationship_id", "request_id", "method"] + (["component"] if LDMS else []) + ["left_analysis_id", "right_analysis_id", "left_trait_id", "right_trait_id", "scale", "estimate", "standard_error", "classification"],
    covariance_rows,
)

diagnostics = dict(pair_diagnostics)
if HEREG:
    # HE-CP regresses off-diagonal cross-products on off-diagonal relatedness, so no residual
    # covariance term is identified and GCTA 1.94.1 exposes no option that would introduce one.
    residual_covariance_status = "no_residual_covariance_parameter"
    residual_covariance = "NA"
elif "C(e)_tr12" in components:
    residual_covariance_status = "retained"
    residual_covariance = components["C(e)_tr12"]["native_estimate"]
elif "--reml-bivar-nocove" in META.get("native_args", []):
    residual_covariance_status = "dropped_by_native_option"
    residual_covariance = "NA"
else:
    residual_covariance_status = "dropped_by_native_overlap_rule"
    residual_covariance = "NA"
diagnostics.update({
    "classification": classification,
    "native_common_samples": common_match.group(1) if common_match else "NA",
    "native_trait1_nonmissing": nonmissing_match.group(1) if nonmissing_match else "NA",
    "native_trait2_nonmissing": nonmissing_match.group(2) if nonmissing_match else "NA",
    "residual_covariance": residual_covariance,
    "residual_covariance_status": residual_covariance_status,
    "warnings": ",".join(sorted(set(warnings))) if warnings else "none",
})
if HEREG:
    diagnostics.update({
        "native_estimator": "haseman_elston_cross_product",
        "native_observations_trait1": components["N_tr1"]["native_estimate"],
        "native_observations_trait2": components["N_tr2"]["native_estimate"],
        "standard_error_basis": "jackknife",
        "covariance_scale": COVARIANCE_SCALE,
        # GCTA 1.94.1 lists --qcovar/--covar under its accepted options for this analysis but never
        # reads them, so the pipeline refuses covariate-bearing HE requests before execution.
        "covariate_adjustment": "not_supported_by_method",
        # The cross-trait coefficient is fitted on the lower triangle only, with the left trait on
        # the row member and the right trait on the column member, so the declared orientation
        # changes the point estimate. See docs/output.md.
        "native_cross_product_orientation": "left_trait_row_right_trait_column",
        "jackknife_sampling_covariance": "available" if jackknife_covariance else "unavailable",
    })
    if LDMS:
        diagnostics["primary_result_component"] = TOTAL_COMPONENT
        diagnostics["total_result_origin"] = "native"
        diagnostics["native_component_layout"] = (
            "multi_component" if len(component_suffixes) > 1 else "single_component"
        )
else:
    diagnostics.update({
        "native_converged": str(converged).lower(),
        "native_observations": components["n"]["native_estimate"],
        "native_log_likelihood": components["logL"]["native_estimate"],
    })
if LDMS:
    diagnostics["genetic_components"] = ",".join(
        TOTAL_COMPONENT if suffix == TOTAL_COMPONENT else "G{}".format(suffix) for suffix in component_suffixes
    )
write_tsv(
    "diagnostics.tsv",
    ["relationship_id", "request_id", "metric", "value"],
    [[META["relationship_id"], META["request_id"], name, value] for name, value in sorted(diagnostics.items())],
)

provenance = {
    "schema_version": "1.0",
    "relationship_id": META["relationship_id"],
    "request_id": META["request_id"],
    "method": METHOD,
    "orientation": {
        "left": {"analysis_id": META["left_analysis_id"], "trait_id": META["left_trait_id"], "trait_type": META["left_trait_type"]},
        "right": {"analysis_id": META["right_analysis_id"], "trait_id": META["right_trait_id"], "trait_type": META["right_trait_type"]},
    },
    "cohort_id": META["cohort"],
    "matrix": {
        "kind": META["matrix_kind"],
        "key": META["matrix_key"],
        "basename": META["matrix_basename"],
        "settings": META["matrix_settings"],
    },
    "effective_prevalence": META["reml_bivar_prevalence"],
    "declared_prevalence": {
        "left": META["left_population_prevalence"],
        "right": META["right_population_prevalence"],
    },
    "native_args": META["native_args"],
    "classification": classification,
    "warnings": sorted(set(warnings)),
    "diagnostics": diagnostics,
    "native_components": components,
    "execution": {"process": PROCESS_NAME, "container": CONTAINER},
    "tool": {"name": "gcta", "version": version_match.group(1) if version_match else None},
    "artifacts": {
        "native": ["native.HEreg" if HEREG else "native.hsq", "native.log"],
        "normalized": ["heritability.tsv", "genetic_correlation.tsv", "genetic_covariance.tsv", "diagnostics.tsv", "provenance.json"],
    },
}
if LDMS:
    provenance["genetic_components"] = [
        TOTAL_COMPONENT if suffix == TOTAL_COMPONENT else "G{}".format(suffix) for suffix in component_suffixes
    ]
if HEREG:
    provenance["native_sampling_covariance"] = jackknife_covariance
with open("provenance.json", "w", newline="") as handle:
    json.dump(provenance, handle, indent=2, sort_keys=True, allow_nan=False)
    handle.write("\\n")

with open("versions.yml", "w", newline="") as handle:
    handle.write('"{}":\\n'.format(PROCESS_NAME))
    handle.write("    python: {}\\n".format(sys.version.split()[0]))
