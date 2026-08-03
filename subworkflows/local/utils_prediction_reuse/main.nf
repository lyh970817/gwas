// Any file-like input contributing to scientific identity is hashed by content. Byte-identical files
// materialised for different analysis IDs are valid reuse candidates; equal basenames are not sufficient.
def digestScientificInput(input_file) {
    if (!input_file) {
        return 'absent'
    }
    def input_path = input_file instanceof java.nio.file.Path ? input_file : input_file.toPath()
    def digest = java.security.MessageDigest.getInstance('SHA-256')
    java.nio.file.Files
        .newInputStream(input_path)
        .withCloseable { input ->
            input.eachByte(8192) { buffer, count ->
                digest.update(buffer, 0, count)
            }
        }
    return digest.digest().encodeHex().toString()
}

// Prediction reuse keys share one deterministic map serialisation and the same 12-character SHA-256 prefix.
def buildCanonicalPredictionKey(identity) {
    def canonical = identity
        .sort { entry -> entry.key }
        .collect { name, value -> "${name}=${value}" }
        .join('\n')
    return java.security.MessageDigest
        .getInstance('SHA-256')
        .digest(canonical.getBytes('UTF-8'))
        .encodeHex()
        .toString()
        .substring(0, 12)
}

// REGENIE Step 1 reuse requires every cohort-defining and scientific input to agree. Execution-only
// controls are intentionally absent; Step 1 block size remains because it changes the fitted model.
def buildRegeniePredictionKey(meta, phenotype, covariates, step1_bsize) {
    def identity = [
        cohort: meta.cohort,
        trait: meta.trait,
        is_binary: meta.is_binary,
        phenotype: digestScientificInput(phenotype),
        covariates: digestScientificInput(covariates),
        step1_bsize: step1_bsize,
    ]
    return buildCanonicalPredictionKey(identity)
}

// LDAK-KVIK Step 1 reuse additionally depends on predictor policy and optional predictor-list bytes.
def buildKvikPredictionKey(meta, phenotype, quant_covariates, cat_covariates, subset_policy, predictor_extract) {
    def identity = [
        cohort: meta.cohort,
        trait: meta.trait,
        is_binary: meta.is_binary,
        phenotype: digestScientificInput(phenotype),
        quant_covariates: digestScientificInput(quant_covariates),
        cat_covariates: digestScientificInput(cat_covariates),
        subset_policy: subset_policy,
        predictor_extract: digestScientificInput(predictor_extract),
    ]
    return buildCanonicalPredictionKey(identity)
}
