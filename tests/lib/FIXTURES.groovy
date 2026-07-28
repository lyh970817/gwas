// Locates the nf-core/test-datasets `gwas` fixture bundle for tests that need real genotypes.
//
// Validation-only tests get by with empty placeholder files, but anything that actually runs a
// programme needs the real bundle. The committed default is the upstream URL, so nothing
// machine-specific is stored in this repository; a checkout that is not yet merged upstream is
// supplied at run time instead.
//
// Resolution order:
//   1. `$GWAS_TEST_FIXTURES` — an explicit local checkout, e.g.
//      `GWAS_TEST_FIXTURES=/path/to/test-datasets nf-test test tests/ --profile docker`.
//   2. A sibling checkout of the pipeline repository, so the common local layout needs no setup.
//   3. The upstream URL, which is what continuous integration uses once the fixtures are merged.
class FIXTURES {

    // The prefix every file cell of assets/samplesheet.csv is written against.
    static final String UPSTREAM = 'https://raw.githubusercontent.com/nf-core/test-datasets/gwas/'

    // Present in a complete fixture bundle and in nothing else, so it recognises one.
    private static final String MARKER = 'results/fixtures/genotypes/example_all.pgen'

    // Directory names a local test-datasets checkout is conventionally given.
    private static final List<String> SIBLINGS = ['test-datasets', 'test-datasets-gwas']

    static String base(Object projectDir = null) {
        def declared = System.getenv('GWAS_TEST_FIXTURES')
        if (declared) {
            def resolved = withTrailingSlash(new File(declared).absolutePath)
            if (!new File(resolved + MARKER).exists()) {
                throw new IllegalStateException("GWAS_TEST_FIXTURES is set to '${declared}' but ${resolved}${MARKER} does not exist")
            }
            return resolved
        }

        def root = new File(projectDir?.toString() ?: System.getProperty('user.dir')).absoluteFile
        def sibling = SIBLINGS
            .collect { name -> new File(root.parentFile, name) }
            .find { candidate -> new File(candidate, MARKER).exists() }
        return sibling ? withTrailingSlash(sibling.absolutePath) : UPSTREAM
    }

    private static String withTrailingSlash(String path) {
        return path.endsWith('/') ? path : path + '/'
    }
}
