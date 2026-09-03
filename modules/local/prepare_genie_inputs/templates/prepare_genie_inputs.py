#!/usr/bin/env python3
"""Write exactly the files GENIE consumes for one analysis unit, in exactly the order it consumes them.

GENIE reads the identifier columns of its phenotype and covariate files and then discards them: rows are
matched positionally against the FAM. Shuffling the rows of an otherwise correct phenotype file, identifiers
intact, moved the estimate from 0.0925 to -0.068 at exit 0 with no warning on the pinned image. There is no
identity check to rely on, so this adapter emits one row per FAM row in FAM order, and every downstream check
is expressed against counts GENIE itself echoes.

Four more of GENIE's contracts are silent when broken, which is why they are validated here rather than left to
the tool:

    a header row is mandatory in the phenotype and covariate files, and its first two fields must be the
        literal, case-sensitive `FID` and `IID`. GENIE does not simply skip line one: it reads the header to
        decide which columns are identifiers and how many trait or covariate columns follow. A malformed
        header is not merely wrong, it is *non-deterministic*: eight repeats on one unchanged body at a fixed
        seed returned four different values including `-nan`, while the well-formed control returned the same
        value all eight times. That is an uninitialised or out-of-bounds read, so no single number
        characterises it and none is quoted here. A header with fewer fields than the data rows segfaults, and
        a headerless covariate file reports two extra covariates and returns -nan
    the annotation must be space-delimited with one row per BIM variant (a tab-delimited file yields
        "0 SNPs in bin 0" and -nan, and a row-count mismatch is only a warning before GENIE adopts the
        annotation's own count)
    a monomorphic variant yields zero variance components and -nan
    a covariate cell GENIE cannot parse is read as a value rather than excluding the sample

At most six files are written:

    <prefix>.genie.pheno            FID IID PHENO, header, FAM order, NA missing     always
    <prefix>.genie.annot            one 0/1 row per BIM variant, space-delimited      always
    <prefix>.genie.covar            FID IID cov_1 .., header, FAM order               when the row has covariates
    <prefix>.genie_expected.tsv     counts the atom asserts GENIE's own echo against  always
    <prefix>.genie_effective.json   resolved stochastic settings and native arguments always
    <prefix>.provenance.json        the per-result invocation record                  always

Standard library only, deliberately: the inputs run to a few thousand rows at most, and the BED scan is a bit
operation over integers, so a dataframe dependency would add container weight and a second version to report.
"""

import hashlib
import json
import sys

# Interpolated as JSON literals, which are valid Python syntax. Optional paths are serialized as empty
# strings when the analysis did not supply them.
BED_FILE = ${bed_literal}
BIM_FILE = ${bim_literal}
FAM_FILE = ${fam_literal}
PHENOTYPE_FILE = ${phenotype_literal}
ADJUSTMENT_COVARIATES_FILE = ${adjustment_covariates_literal}
ANNOTATION_FILE = ${annotation_literal}
PREFIX = ${prefix_literal}
ANALYSIS_ID = ${analysis_id_literal}
METHOD = ${method_literal}
REQUESTED = json.loads(${requested_settings_literal})
CAPABILITY = json.loads(${capability_literal})
PROCESS_NAME = ${task_process_literal}

MISSING = "NA"
MISSING_TOKENS = frozenset(["", "na", "nan", "-9"])

# GENIE's own missing rule for the phenotype is numeric, not textual: it drops every sample whose trait
# parses to exactly this value, however it is spelled. Measured on the pinned image, `-9`, `-9.0`,
# `-9.000000` and `-9e0` all take 200 retained samples to 180 with identical estimates, while `-8.999999`
# and `-10` are kept. A textual comparison would let `-9.0` through as a value, GENIE would drop the sample
# anyway, and the count this adapter declares would then disagree with the count GENIE echoes -- surfacing
# as an estimator-side assertion that names neither the cause nor the samples.
NATIVE_MISSING_PHENOTYPE = -9.0

# Keep diagnostics useful without allowing an unbounded message for bad input.
MAX_REPORTED = 10

# GENIE's own default, spelled here because the adapter has to record which settings are native.
NATIVE_RANDOM_VECTORS = 10
NATIVE_JACKKNIFE_BLOCKS = 1000

# Pipeline policy, with no native counterpart. GENIE returns a finite, plausible and meaningless number for a
# handful of samples -- three retained samples gave h2_g[0] = -0.394 with a standard error of 22.06 at exit 0 --
# and a constant phenotype returns -nan. Both are stated in docs/usage.md as pipeline rules.
RETAINED_SAMPLE_FLOOR = 30
PHENOTYPE_VARIANCE_FLOOR = 1e-12

# GENIE and RHE-mc target biobank scale. Below this the estimate is reported, with the warning recorded.
RECOMMENDED_SAMPLE_SCALE = 1000

# The build identity of the pinned image, kept in one place. GENIE reports no version at runtime, so the image
# digest is the only authoritative build identity a published result can carry.
BUILD = {
    "version": "1.1.1",
    "source": "https://github.com/sriramlab/GENIE",
    "source_revision": "4457b03ded49523f6aa014e508db1dbe0f8cbd7c",
    "build_type": "Release",
    "compiler": "GCC 12.2.0 (Debian 12.2.0-14+deb12u1)",
    "architecture": "linux/amd64",
    "simd": "ENABLE_SSE=OFF (SSE_SUPPORT=0)",
    "floating_point_precision": "single (Eigen::Matrix<float>)",
    "image": "ghcr.io/lyh970817/genie@sha256:c4b836f6bdf5853c49d902e29f70a9a6540388a23d9b6840c9f3c67ad40d47e0",
    "self_reported_version": "1.0.0 (banner; not authoritative)",
}

# The assertions GENIE_G makes in the same task, each of which fails it. This sidecar is written before the
# native invocation and structurally cannot classify the fit, so it names the checks that make a published
# non-estimable result unreachable rather than guessing a classification.
NATIVE_CHECKS = [
    "no_nan_or_inf",
    "individuals_match_expected",
    "covariates_match_expected",
    "bin_variant_counts_match_expected",
]

WARNINGS = []


def fail(message):
    """Abort naming the analysis unit, so a large samplesheet can be fixed without bisecting it."""
    sys.exit("[nf-core/gwas] ERROR: analysis '{}': {}".format(ANALYSIS_ID, message))


def note(message):
    print("[nf-core/gwas]: analysis '{}': {}".format(ANALYSIS_ID, message))


def split_row(line):
    """Split one input line on whichever delimiter it actually uses, preserving empty cells.

    The same rule prepare_phenotype_inputs.py applies: a line carrying a tab is tab-delimited and is split on
    tabs, so an empty cell survives to be normalised rather than collapsing and leaving the row ragged.
    """
    line = line.rstrip("\\r\\n")
    return line.split("\\t") if "\\t" in line else line.split()


def is_missing(value):
    return value.strip().lower() in MISSING_TOKENS


def is_native_missing_phenotype(value):
    """Whether GENIE will drop this sample, under GENIE's own numeric rule."""
    if is_missing(value):
        return True
    try:
        return float(value) == NATIVE_MISSING_PHENOTYPE
    except ValueError:
        return True


def read_keyed_table(path, role, minimum_columns):
    """Read one headerless FID/IID-keyed file, rejecting the shapes that cannot be aligned."""
    with open(path) as handle:
        rows = [split_row(line) for line in handle]
    rows = [row for row in rows if any(field.strip() for field in row)]
    if not rows:
        fail("the {} file '{}' is empty".format(role, path))
    width = len(rows[0])
    if width < minimum_columns:
        fail(
            "the {} file '{}' declares {} column(s); at least {} are required".format(
                role, path, width, minimum_columns
            )
        )
    for number, row in enumerate(rows, start=1):
        if len(row) != width:
            fail(
                "the {} file '{}' declares {} columns but line {} carries {} fields".format(
                    role, path, width, number, len(row)
                )
            )
    by_pair = {}
    for row in rows:
        pair = (row[0], row[1])
        if pair in by_pair:
            fail("the {} file '{}' declares sample '{} {}' more than once".format(role, path, row[0], row[1]))
        by_pair[pair] = row
    return rows, by_pair


def align_to_fam(order, by_pair, role, path):
    """Return one row per FAM row, refusing to guess an identity GENIE would never check.

    An IID that occurs under a different FID is the one ambiguity worth stopping on: it is the shape a
    researcher produces by rebuilding a family column, and GENIE would happily fit whatever landed in that
    position. A sample simply absent from the table is not an error -- every estimator in this pipeline
    intersects sample sets natively -- so it is counted and carried through as missing.
    """
    by_iid = {}
    for pair in by_pair:
        by_iid.setdefault(pair[1], []).append(pair)
    aligned = []
    absent = 0
    for pair in order:
        if pair in by_pair:
            aligned.append(by_pair[pair])
            continue
        alternatives = [other for other in by_iid.get(pair[1], []) if other != pair]
        if alternatives:
            fail(
                "sample '{} {}' in the FAM is '{} {}' in the {} table '{}'; GENIE matches rows positionally "
                "and the pipeline will not guess which family identifier is meant".format(
                    pair[0], pair[1], alternatives[0][0], alternatives[0][1], role, path
                )
            )
        aligned.append(None)
        absent += 1
    surplus = len(by_pair) - (len(order) - absent)
    return aligned, absent, surplus


def sha256_text(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def write_lines(path, lines):
    with open(path, "w", newline="\\n") as handle:
        handle.writelines(line + "\\n" for line in lines)
        handle.flush()


def read_fam():
    rows, by_pair = read_keyed_table(FAM_FILE, "FAM", 6)
    return [(row[0], row[1]) for row in rows], by_pair


def read_bim():
    with open(BIM_FILE) as handle:
        rows = [split_row(line) for line in handle if line.strip()]
    if not rows:
        fail("the BIM file '{}' is empty".format(BIM_FILE))
    return [row[1] for row in rows]


def monomorphic_variants(n_samples, variant_ids):
    """Name every BIM variant with no polymorphism over the whole FAM.

    GENIE standardises each variant over every FAM sample rather than the retained subset, and a variant with
    no minor-allele carrier there divides by a zero standard deviation: on the pinned image one such variant
    took the whole fit to Sigma^2_g[0] = 0 and h2_g[0] = -nan at exit 0. The scan is a bit operation per
    variant over the PLINK 1 genotype codes (00 homozygous A1, 01 missing, 10 heterozygous, 11 homozygous A2,
    two bits per sample, least significant first), which is fast enough to be unconditional here.
    """
    bytes_per_variant = (n_samples + 3) // 4
    valid = (1 << (2 * n_samples)) - 1
    low = int("01" * n_samples, 2)
    found = []
    with open(BED_FILE, "rb") as handle:
        magic = handle.read(3)
        if magic != b"\\x6c\\x1b\\x01":
            fail(
                "the BED file '{}' is not a variant-major PLINK 1 genotype table (magic {})".format(
                    BED_FILE, magic.hex()
                )
            )
        for index, variant_id in enumerate(variant_ids):
            block = handle.read(bytes_per_variant)
            if len(block) != bytes_per_variant:
                fail(
                    "the BED file '{}' ends after {} variants but the BIM declares {}".format(
                        BED_FILE, index, len(variant_ids)
                    )
                )
            calls = int.from_bytes(block, "little") & valid
            lower = calls & low
            upper = (calls >> 1) & low
            homozygous_a1 = (low & ~lower & ~upper).bit_count()
            heterozygous = (low & ~lower & upper).bit_count()
            homozygous_a2 = (lower & upper).bit_count()
            if heterozygous == 0 and (homozygous_a1 == 0 or homozygous_a2 == 0):
                found.append(variant_id)
        if handle.read(1):
            fail(
                "the BED file '{}' carries more variants than the {} the BIM declares".format(
                    BED_FILE, len(variant_ids)
                )
            )
    return found


def read_annotation(n_variants, variant_ids):
    """Return the annotation rows GENIE will read, as a disjoint partition of the BIM.

    Without a caller file the single all-SNP component is one column of ones. With one, the partition rule is
    strict in both directions and each direction answers a measured failure: a variant in no column is silently
    dropped from the analysed set, and a variant in more than one makes GENIE print two different values under
    the same `h2_g[k]` label in one file -- 0.0160 under `Heritabilities:` and 0.1060 under `overlapping
    setting` on the compact fixture -- with no basis in this route for choosing between them, because issue #10
    defers partitioned-heritability enrichment. Under a partition the two blocks agree to six significant
    figures by construction.
    """
    if not ANNOTATION_FILE:
        return [["1"] for _ in range(n_variants)], None
    with open(ANNOTATION_FILE) as handle:
        rows = [line.split() for line in handle if line.strip()]
    if len(rows) != n_variants:
        fail(
            "the GENIE annotation '{}' declares {} row(s) but the cohort's BIM declares {} variant(s); GENIE "
            "reports the mismatch as a warning and then analyses the annotation's own count".format(
                ANNOTATION_FILE, len(rows), n_variants
            )
        )
    width = len(rows[0])
    if width < 1:
        fail("the GENIE annotation '{}' declares no columns".format(ANNOTATION_FILE))
    for number, row in enumerate(rows, start=1):
        if len(row) != width:
            fail(
                "the GENIE annotation '{}' declares {} column(s) but row {} carries {}".format(
                    ANNOTATION_FILE, width, number, len(row)
                )
            )
        for token in row:
            if token not in ("0", "1"):
                fail(
                    "the GENIE annotation '{}' carries the value '{}' on row {}; every cell must be 0 or 1, "
                    "and GENIE reads a non-binary cell as no component at all (0 SNPs in bin 0, h2 = -nan). A "
                    "header row is the usual cause and is not accepted".format(ANNOTATION_FILE, token, number)
                )
        assigned = row.count("1")
        if assigned == 0:
            fail(
                "variant '{}' (annotation row {}) is in no component column; GENIE silently drops such "
                "variants from the analysed set. Remove the variant from the cohort genotypes "
                "instead".format(variant_ids[number - 1], number)
            )
        if assigned > 1:
            fail(
                "variant '{}' (annotation row {}) is in {} component columns; overlapping component "
                "definitions make GENIE report two different values under the same 'h2_g[k]' label in one "
                "file, and partitioned-heritability enrichment is deferred. Supply a disjoint partition with "
                "exactly one column per variant".format(variant_ids[number - 1], number, assigned)
            )
    return rows, sha256_file(ANNOTATION_FILE)


def streams_jackknife_safely(n_variants, jackknife_blocks):
    """Whether `GENIE_mem` can survive this jackknife count on this many variants.

    `GENIE_mem` reads each jackknife block into a buffer sized for the nominal block, and gives the trailing
    block every leftover variant. When that leftover exceeds the nominal block size it reads past the buffer
    and dies with `malloc(): corrupted top size` or a segmentation fault -- exit 134 or 139, no message a
    researcher could act on. Measured across 40 jackknife counts on a 2200-variant cohort, the boundary is
    exact in both directions: a trailing remainder equal to the block size runs, one greater by a single
    variant aborts. `GENIE` is unaffected at every one of those counts. At the scale this estimator is built
    for the question does not arise -- a million variants in a thousand blocks leaves a remainder far below
    the block size -- so this only ever bites a small cohort.
    """
    return n_variants % jackknife_blocks <= n_variants // jackknife_blocks


def resolve_settings(n_variants):
    """Resolve the stochastic controls without ever silently rewriting a curated one.

    Only the jackknife-block default is spelled unconditionally, because omitting it is not safe: GENIE
    defaults to 1000 blocks and raises a floating-point exception when that exceeds the variant count. A
    *requested* count is never substituted -- running a different number of blocks changes the reported
    standard error -- so a count the selected executable cannot survive is refused instead.
    """
    memory_efficient = bool(REQUESTED.get("memory_efficient"))
    requested_blocks = REQUESTED.get("jackknife_blocks")
    if requested_blocks is None:
        jackknife_blocks = min(NATIVE_JACKKNIFE_BLOCKS, n_variants)
        if jackknife_blocks != NATIVE_JACKKNIFE_BLOCKS:
            WARNINGS.append("jackknife_blocks_clamped_default")
        if memory_efficient and not streams_jackknife_safely(n_variants, jackknife_blocks):
            # The pipeline owns this default, so choosing one the selected executable survives is choosing a
            # default rather than overriding an instruction. The largest such count below the clamped one
            # keeps the standard error as close to the native default's as the executable allows.
            safe = jackknife_blocks
            while safe > 2 and not streams_jackknife_safely(n_variants, safe):
                safe -= 1
            jackknife_blocks = safe
            WARNINGS.append("jackknife_blocks_memory_efficient_default")
    elif requested_blocks > n_variants:
        fail(
            "genie.jackknife_blocks {} exceeds the {} variant(s) in the cohort; GENIE aborts with a "
            "floating-point exception when a jackknife block is empty".format(requested_blocks, n_variants)
        )
    elif memory_efficient and not streams_jackknife_safely(n_variants, requested_blocks):
        # The predicate is *not* monotone in the block count -- 300 aborts on 2200 variants while both 274 and
        # 440 run -- so "this value or lower" would be false advice that walks a researcher into the same
        # refusal, or into the crash itself outside the pipeline. Name only counts measured to be safe.
        nearest = [
            candidate
            for candidate in range(requested_blocks - 1, 1, -1)
            if streams_jackknife_safely(n_variants, candidate)
        ][:3]
        assert all(streams_jackknife_safely(n_variants, candidate) for candidate in nearest)
        fail(
            "genie.jackknife_blocks {0} leaves a trailing jackknife block of {1} variant(s) against a nominal "
            "block of {2}, which GENIE_mem reads past the end of its own buffer and aborts on (exit 134 or "
            "139, no diagnostic). The safe counts are not an interval, so lowering the value is not itself a "
            "fix: use one of {3}, use any divisor of the {4} variant(s) in the cohort, or set "
            "genie.memory_efficient to false".format(
                requested_blocks,
                n_variants // requested_blocks + n_variants % requested_blocks,
                n_variants // requested_blocks,
                ", ".join(str(candidate) for candidate in nearest) if nearest else "a divisor of the cohort",
                n_variants,
            )
        )
    else:
        jackknife_blocks = requested_blocks

    requested_vectors = REQUESTED.get("random_vectors")
    native_defaults = []
    if requested_vectors is None:
        random_vectors = NATIVE_RANDOM_VECTORS
        native_defaults.append("random_vectors")
        WARNINGS.append("random_vectors_native_default")
    else:
        random_vectors = requested_vectors

    seed = REQUESTED.get("seed")
    if seed is None:
        WARNINGS.append("seed_native_unseeded")

    # Only an explicitly requested value is spelled, so a native omission stays native -- except `-jn`, whose
    # omission is unsafe below 1000 variants. `-m G`, `-np 0` and `-i 1` are the atom's own literals.
    native_args = ["-jn", str(jackknife_blocks)]
    if requested_vectors is not None:
        native_args += ["-k", str(random_vectors)]
    if seed is not None:
        native_args += ["-s", str(seed)]
    return {
        "random_vectors": random_vectors,
        "jackknife_blocks": jackknife_blocks,
        "jackknife_blocks_source": (
            "requested"
            if requested_blocks is not None
            else (
                "memory_efficient_safe_default"
                if "jackknife_blocks_memory_efficient_default" in WARNINGS
                else "clamped_native_default"
            )
        ),
        "seed": seed,
        "memory_efficient": memory_efficient,
        "native_args": native_args,
        "native_defaults_apply": native_defaults,
    }


def main():
    fam_order, _fam_by_pair = read_fam()
    n_samples_fam = len(fam_order)
    variant_ids = read_bim()
    n_variants = len(variant_ids)

    # Covariates are read before the phenotype guards because the saturated-design guard needs their width.
    covariate_columns = 0
    covariate_rows = None
    if ADJUSTMENT_COVARIATES_FILE:
        rows, by_pair = read_keyed_table(ADJUSTMENT_COVARIATES_FILE, "covariate", 3)
        covariate_columns = len(rows[0]) - 2
        covariate_rows, _absent, _surplus = align_to_fam(
            fam_order, by_pair, "covariate", ADJUSTMENT_COVARIATES_FILE
        )

    _phenotype_rows, phenotype_by_pair = read_keyed_table(PHENOTYPE_FILE, "phenotype", 3)
    aligned_phenotype, absent_from_table, not_in_fam = align_to_fam(
        fam_order, phenotype_by_pair, "phenotype", PHENOTYPE_FILE
    )
    if not_in_fam:
        note(
            "the phenotype table '{}' describes {} sample(s) absent from the cohort FAM; they are "
            "dropped".format(PHENOTYPE_FILE, not_in_fam)
        )

    values = []
    missing_phenotype = 0
    native_sentinel = []
    for index, row in enumerate(aligned_phenotype):
        if row is None:
            values.append(MISSING)
            continue
        if not is_missing(row[2]) and is_native_missing_phenotype(row[2]):
            # A value the researcher wrote that GENIE will silently drop: numerically the missing sentinel,
            # but not spelled the way this pipeline spells missing. Normalised so the declared count matches
            # what GENIE will retain, and named so the drop is never silent.
            native_sentinel.append((fam_order[index], row[2]))
        if is_native_missing_phenotype(row[2]):
            values.append(MISSING)
            missing_phenotype += 1
            continue
        values.append(row[2])
    if native_sentinel:
        WARNINGS.append("phenotype_native_missing_sentinel")
        displayed = native_sentinel[:MAX_REPORTED]
        note(
            "{} sample(s) carry a phenotype that GENIE reads as its own missing sentinel ({}) although it is "
            "not written as '{}' (first {}: {}{}); they are dropped, as GENIE would drop them".format(
                len(native_sentinel),
                NATIVE_MISSING_PHENOTYPE,
                MISSING,
                len(displayed),
                ", ".join("{} {} = {}".format(fid, iid, raw) for (fid, iid), raw in displayed),
                "; {} further omitted".format(len(native_sentinel) - len(displayed))
                if len(native_sentinel) > len(displayed)
                else "",
            )
        )
    retained = [float(value) for value in values if value != MISSING]
    n_retained = len(retained)

    if n_retained == 0:
        fail("every phenotype value is missing after alignment to the cohort FAM")
    mean = sum(retained) / n_retained
    variance = sum((value - mean) ** 2 for value in retained) / n_retained
    if variance < PHENOTYPE_VARIANCE_FLOOR:
        fail(
            "the phenotype is constant (value {}) across all {} retained sample(s); GENIE returns '-nan' "
            "variance components at exit 0 for a degenerate phenotype".format(retained[0], n_retained)
        )
    if n_retained <= covariate_columns + 1:
        fail(
            "{} retained sample(s) cannot support an intercept plus {} covariate column(s); the design would "
            "be saturated and GENIE would report a finite meaningless number".format(
                n_retained, covariate_columns
            )
        )
    if n_retained < RETAINED_SAMPLE_FLOOR:
        fail(
            "{} retained sample(s) is below the pipeline's floor of {} for a randomised Haseman-Elston fit; "
            "GENIE returns a finite but meaningless estimate at exit 0 for a handful of samples (three "
            "retained samples gave h2_g[0] = -0.394 with a standard error of 22.06)".format(
                n_retained, RETAINED_SAMPLE_FLOOR
            )
        )
    if n_retained < RECOMMENDED_SAMPLE_SCALE:
        WARNINGS.append("retained_below_recommended_scale")
        note(
            "{} retained sample(s) is far below the scale a randomised Haseman-Elston estimator is designed "
            "for; the estimate is reported but its Monte-Carlo and sampling error will dominate".format(
                n_retained
            )
        )

    # The analysed sample set is decided by the phenotype alone. GENIE excludes a sample with a missing
    # phenotype whatever its covariate cells hold, and it excludes nothing for a covariate cell it cannot
    # parse -- one `NA` cell moved the estimate from 0.0925 to 0.0873 at exit 0 with all 200 samples still
    # reported as retained. The pipeline therefore refuses an incomplete covariate file at ingress
    # (`requires_complete_covariates`) rather than changing the sample set inside a representation adapter.
    # The two checks below are the ones that rule structurally cannot see, because it iterates cells that
    # exist rather than FAM rows that should have one.
    covariate_lines = None
    if covariate_rows is not None:
        phenotyped_without_covariates = [
            fam_order[index]
            for index, row in enumerate(covariate_rows)
            if row is None and values[index] != MISSING
        ]
        if phenotyped_without_covariates:
            displayed = phenotyped_without_covariates[:MAX_REPORTED]
            fail(
                "{} sample(s) with a phenotype value have no row at all in the covariate design (first {}: "
                "{}{}); GENIE reads the covariate file positionally against the FAM and has no "
                "covariate-missing code".format(
                    len(phenotyped_without_covariates),
                    len(displayed),
                    ", ".join("{} {}".format(fid, iid) for fid, iid in displayed),
                    "; {} further omitted".format(len(phenotyped_without_covariates) - len(displayed))
                    if len(phenotyped_without_covariates) > len(displayed)
                    else "",
                )
            )
        # A cell is only ever read by GENIE for a sample whose phenotype survived, so completeness is required
        # for exactly those samples -- which is also the set the shared ingress rule polices, and the set the
        # padding branch below excludes. Validating every row instead would refuse a file ingress deliberately
        # accepts, and would do it while asserting that an internal invariant had been violated.
        covariate_lines = []
        for index, row in enumerate(covariate_rows):
            fid, iid = fam_order[index]
            phenotyped = values[index] != MISSING
            if row is None or not phenotyped:
                # Either the sample has no covariate row at all -- and the check above proved it has no
                # phenotype either -- or it has one that GENIE will never read. Measured on the pinned image, a
                # sample excluded by a missing phenotype gives a byte-identical fit whether its covariate cells
                # are complete, `NA` or an arbitrary number, so the slot exists only to keep the file's rows
                # aligned with the FAM and is filled with a value GENIE can parse.
                covariate_lines.append(" ".join([fid, iid] + ["0"] * covariate_columns))
                continue
            cells = row[2:]
            for column, cell in enumerate(cells, start=1):
                if is_missing(cell):
                    fail(
                        "covariate column {} is missing for sample '{} {}', which has a phenotype value; "
                        "preparation should have rejected this analysis "
                        "(requires_complete_covariates)".format(column, fid, iid)
                    )
                try:
                    float(cell)
                except ValueError:
                    fail(
                        "covariate column {} for sample '{} {}' is '{}', which is not numeric; GENIE reads "
                        "such a cell as a value rather than excluding the sample".format(column, fid, iid, cell)
                    )
            covariate_lines.append(" ".join([fid, iid] + list(cells)))

    monomorphic = monomorphic_variants(n_samples_fam, variant_ids)
    if monomorphic:
        displayed = monomorphic[:MAX_REPORTED]
        fail(
            "{} cohort variant(s) are monomorphic across the FAM (first {}: {}{}); GENIE standardises every "
            "variant over the whole FAM and returns zero variance components with h2 = -nan at exit 0 when "
            "one has no minor-allele carrier. Filter them out of the cohort genotypes".format(
                len(monomorphic),
                len(displayed),
                ", ".join(displayed),
                "; {} further omitted".format(len(monomorphic) - len(displayed))
                if len(monomorphic) > len(displayed)
                else "",
            )
        )

    annotation_rows, annotation_source_sha256 = read_annotation(n_variants, variant_ids)
    annotation_columns = len(annotation_rows[0])
    annotation_column_sums = [
        sum(1 for row in annotation_rows if row[column] == "1") for column in range(annotation_columns)
    ]
    empty_columns = [column for column, total in enumerate(annotation_column_sums) if total == 0]
    if empty_columns:
        # Measured: a two-column annotation whose second column claims no variant gives
        # `Number of features in bin 1 : 0` and takes *every* component to -nan, not just the empty one.
        fail(
            "the GENIE annotation '{}' declares component column(s) {} that contain no variant; GENIE fits an "
            "empty component and returns '-nan' for every component in the model, not only the empty "
            "one".format(ANNOTATION_FILE, ", ".join(str(column) for column in empty_columns))
        )

    settings = resolve_settings(n_variants)

    # GENIE requires a header row in both files and skips it; it accepts either delimiter and reads NA and -9
    # alike as a missing phenotype. The annotation must be space-delimited: a tab-delimited one is read as no
    # variants at all.
    phenotype_lines = ["FID IID PHENO"] + [
        " ".join([fid, iid, values[index]]) for index, (fid, iid) in enumerate(fam_order)
    ]
    write_lines("{}.genie.pheno".format(PREFIX), phenotype_lines)
    write_lines("{}.genie.annot".format(PREFIX), [" ".join(row) for row in annotation_rows])
    if covariate_lines is not None:
        header = " ".join(["FID", "IID"] + ["cov_{}".format(column) for column in range(1, covariate_columns + 1)])
        write_lines("{}.genie.covar".format(PREFIX), [header] + covariate_lines)

    # GENIE always adds its own intercept, so it reports one covariate more than the file declares.
    expected = ["individuals\\t{}".format(n_retained), "covariates\\t{}".format(covariate_columns + 1)]
    expected += [
        "bin_{}\\t{}".format(column, annotation_column_sums[column]) for column in range(annotation_columns)
    ]
    write_lines("{}.genie_expected.tsv".format(PREFIX), expected)

    effective = {
        "random_vectors": settings["random_vectors"],
        "jackknife_blocks": settings["jackknife_blocks"],
        "seed": settings["seed"],
        "memory_efficient": settings["memory_efficient"],
        "native_args": settings["native_args"],
        "native_defaults_apply": settings["native_defaults_apply"],
        "n_variants": n_variants,
        "n_samples_fam": n_samples_fam,
        "n_samples_retained": n_retained,
        "annotation_columns": annotation_columns,
        "annotation_column_sums": annotation_column_sums,
        "covariate_columns": covariate_columns,
    }
    write_lines("{}.genie_effective.json".format(PREFIX), [json.dumps(effective)])

    provenance = {
        "schema_version": "1.1",
        "result": {
            "kind": "heritability",
            "analysis_id": ANALYSIS_ID,
            "request_id": None,
            "relationship_id": None,
            "method": METHOD,
            "left_analysis_id": None,
            "right_analysis_id": None,
            "primary_files": ["{}.out".format(PREFIX)],
        },
        "estimator": CAPABILITY,
        "stochastic_settings": {
            "seed": settings["seed"],
            "random_vectors": settings["random_vectors"],
            "requested": {
                "seed": REQUESTED.get("seed"),
                "random_vectors": REQUESTED.get("random_vectors"),
                "jackknife_blocks": REQUESTED.get("jackknife_blocks"),
            },
            "native_defaults_apply": settings["native_defaults_apply"],
            "deterministic": settings["seed"] is not None,
            "deterministic_meaning": "reproducible_given_seed",
            "monte_carlo_error": "not_included_in_reported_se",
            "family_options": {
                "jackknife_blocks": settings["jackknife_blocks"],
                "jackknife_blocks_source": settings["jackknife_blocks_source"],
                "memory_efficient": settings["memory_efficient"],
            },
        },
        "component_plan": {
            "plan_key": None,
            "matrix_key": None,
            "settings": None,
            "components": [
                {
                    "ordinal": column + 1,
                    "name": "all_variants" if annotation_columns == 1 else "annotation_column_{}".format(column),
                    "predictor_count": annotation_column_sums[column],
                }
                for column in range(annotation_columns)
            ],
        },
        "inputs": {
            "samples": {
                "order_source": "fam",
                "retained": n_retained,
                "dropped": n_samples_fam - n_retained,
                "dropped_by_cause": {
                    "missing_phenotype": missing_phenotype,
                    "absent_from_phenotype_table": absent_from_table,
                    "missing_covariate": 0,
                },
                "not_in_fam": not_in_fam,
                "left_nonmissing": None,
                "right_nonmissing": None,
                "both": None,
                "union": None,
            },
            "variants": {
                "retained": n_variants,
                "annotation_columns": annotation_columns,
                "annotation_column_sums": annotation_column_sums,
                "annotation_source": "caller" if ANNOTATION_FILE else "generated_all_ones",
                "annotation_partition": "disjoint",
            },
            "covariates": {"columns": covariate_columns, "intercept": "native"},
            "sha256": {
                "phenotype": sha256_file("{}.genie.pheno".format(PREFIX)),
                "covariates": sha256_file("{}.genie.covar".format(PREFIX)) if covariate_lines is not None else None,
                "annotation": sha256_file("{}.genie.annot".format(PREFIX)),
                "annotation_source": annotation_source_sha256,
                "sample_order": sha256_text("".join("{}\\t{}\\n".format(fid, iid) for fid, iid in fam_order)),
                "variant_order": sha256_text("".join(variant_id + "\\n" for variant_id in variant_ids)),
                "grm_iid": None,
            },
        },
        "residual_covariance": None,
        # Required nullable core member of the shared sidecar schema: this route derives nothing, publishing
        # GENIE's native estimate unchanged. Present so the on-disk shape is the same for every writer.
        "derivation": None,
        "software": {
            "tool": "genie",
            "process": "GENIE_G",
            "executable": "GENIE_mem" if settings["memory_efficient"] else "GENIE",
            "versions_record": "pipeline_info/nf_core_gwas_software_mqc_versions.yml",
            "build": BUILD,
        },
        "native_checks": {"writer": "GENIE_G", "enforced": NATIVE_CHECKS},
        "native_arguments": ["-m", "G", "-np", "0", "-i", "1"] + settings["native_args"],
        "classification": None,
        "warnings": WARNINGS,
    }
    write_lines("{}.provenance.json".format(PREFIX), [json.dumps(provenance, indent=2)])

    # Written here rather than captured by an `eval` output, which Nextflow allows only on a Bash script.
    write_lines("versions.yml", ['"{}":'.format(PROCESS_NAME), "    python: {}".format(sys.version.split()[0])])
    return 0


if __name__ == "__main__":
    sys.exit(main())
