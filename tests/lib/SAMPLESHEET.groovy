// Samplesheet builder for the pipeline-level tests.
//
// Every sheet the tests feed the pipeline is derived from the shipped demo samplesheet,
// assets/samplesheet.csv, so the suite tracks the committed 31-column contract rather than keeping a
// second copy of it that can drift. A test declares only what it wants to be different.
//
// The demo sheet's file columns point at nf-core/test-datasets URLs, and there are two ways to use
// them:
//
//   `build`    rewrites every file cell to an empty local file of the same basename. Input
//              validation only ever asks whether a path exists, never what is in it, so this is
//              enough for the validation suite and makes it hermetic.
//   `fixtures` rewrites every file cell to the resolved fixture bundle, for tests that run a
//              programme over real genotypes. See FIXTURES for how the bundle is located.
//
// Either way no machine-specific path is committed: nothing here is stored except this file and the
// demo samplesheet it reads.
class SAMPLESHEET {

    // The columns that carry files, and therefore the ones that need a placeholder on disk.
    static final List<String> FILE_COLUMNS = [
        'pgen',
        'psam',
        'pvar',
        'bed',
        'bim',
        'fam',
        'vcf',
        'vcf_index',
        'phenotype',
        'quant_covariates',
        'cat_covariates',
        'ldak_kvik_step1_extract',
    ]

    // Read the shipped demo samplesheet as an ordered header plus a list of column-keyed rows.
    static Map demo(Object projectDir) {
        def lines = new File("${projectDir}/assets/samplesheet.csv").readLines().findAll { line -> line.trim() }
        def header = splitLine(lines.first())
        def rows = lines.tail().collect { line -> [header, splitLine(line)].transpose().collectEntries() }
        return [header: header, rows: rows]
    }

    // Materialise a samplesheet named `name` from the demo sheet, after `mutate` has had a chance to
    // break it, with every file cell pointing at an empty placeholder. Returns the absolute path of
    // the written CSV.
    static String build(Object projectDir, Object outputDir, String name, Closure mutate) {
        return materialise(outputDir, name, demo(projectDir), mutate, null)
    }

    // As `build`, but with every file cell pointing at the real fixture bundle, for tests that run a
    // programme rather than only exercising validation.
    static String fixtures(Object projectDir, Object outputDir, String name, Closure mutate) {
        return materialise(outputDir, name, demo(projectDir), mutate, FIXTURES.base(projectDir))
    }

    // Materialise a samplesheet from an explicit header and rows, bypassing the demo sheet. Used for
    // the superseded input format, which shares no columns with the current contract.
    static String buildRaw(Object outputDir, String name, List<String> header, List<Map> rows) {
        return materialise(outputDir, name, [header: header, rows: rows], null, null)
    }

    private static String materialise(Object outputDir, String name, Map sheet_source, Closure mutate, String fixture_base) {
        def header = sheet_source.header
        def rows = sheet_source.rows.collect { row -> new LinkedHashMap(row) }
        if (mutate) {
            mutate(rows)
        }

        // Written beside the output directory rather than inside it, so generated inputs never show
        // up in a published-output snapshot.
        def directory = new File(new File(outputDir.toString()).parentFile, "samplesheets/${name}")
        def data = new File(directory, 'data')
        data.mkdirs()

        rows.each { row ->
            header.findAll { column -> column in FILE_COLUMNS }.each { column ->
                def value = row[column]
                if (value) {
                    row[column] = fixture_base
                        ? value.toString().replace(FIXTURES.UPSTREAM, fixture_base)
                        : placeholder(data, value.toString())
                }
            }
        }

        def sheet = new File(directory, "${name}.csv")
        def body = rows.collect { row -> header.collect { column -> quote(row[column]) }.join(',') }
        sheet.text = ([header.join(',')] + body).join('\n') + '\n'
        return sheet.absolutePath
    }

    private static String placeholder(File data, String value) {
        def file = new File(data, value.tokenize('/').last())
        if (!file.exists()) {
            file.createNewFile()
        }
        return file.absolutePath
    }

    // Minimal CSV splitter: enough for the demo sheet, which quotes only the comma-delimited method
    // selector cells and never embeds a quote character.
    private static List<String> splitLine(String line) {
        def cells = []
        def current = new StringBuilder()
        def quoted = false
        line.each { character ->
            if (character == '"') {
                quoted = !quoted
            }
            else if (character == ',' && !quoted) {
                cells << current.toString()
                current = new StringBuilder()
            }
            else {
                current.append(character)
            }
        }
        cells << current.toString()
        return cells
    }

    private static String quote(Object value) {
        def text = value == null ? '' : value.toString()
        return text.contains(',') ? "\"${text}\"" : text
    }
}
