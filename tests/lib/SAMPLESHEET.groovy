// Samplesheet builder for the pipeline-level tests.
//
// Every sheet the tests feed the pipeline is derived from the shipped demo samplesheet,
// assets/samplesheet.csv, so the suite tracks the committed 35-column contract rather than keeping a
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

    // The columns that carry files, and therefore the ones that need a placeholder on disk. Read
    // out of the input schema rather than restated here, so this cannot drift from the contract the
    // pipeline validates against: a file column is exactly one declaring "format": "file-path".
    static List<String> fileColumns(Object projectDir) {
        def properties = new groovy.json.JsonSlurper()
            .parseText(new File("${projectDir}/assets/schema_input.json").text)
            .items
            .properties
        return properties.findAll { column, definition -> definition.format == 'file-path' }.keySet().toList()
    }

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
        return materialise(outputDir, name, demo(projectDir), mutate, null, fileColumns(projectDir))
    }

    // As `build`, but with every file cell pointing at the real fixture bundle, for tests that run a
    // programme rather than only exercising validation.
    static String fixtures(Object projectDir, Object outputDir, String name, Closure mutate) {
        return materialise(outputDir, name, demo(projectDir), mutate, FIXTURES.base(projectDir), fileColumns(projectDir))
    }

    // Materialise a superseded public contract by dropping named headers. File cells use hermetic
    // placeholders because the mandatory-header gate rejects the sheet before any process can read them.
    static String withoutColumns(Object projectDir, Object outputDir, String name, List<String> omitted, Closure mutate) {
        def source = demo(projectDir)
        source.header = source.header.findAll { column -> !omitted.contains(column) }
        return materialise(outputDir, name, source, mutate, null, fileColumns(projectDir))
    }

    // Rewrite one fixture file for the sheet named `name` and return the path to put in the cell it
    // came from. `transform` is handed the file's lines and returns the lines to write.
    //
    // Called from inside a `mutate` closure, for the cases the committed fixtures do not cover: they
    // carry no missing value and code their binary trait one way only, so a test of missingness or of
    // an unusual trait coding has to supply its own file. The shared test-datasets checkout is
    // read-only as far as this suite is concerned, so the copy is written beside the generated
    // samplesheet, outside the output directory, where it can never reach a published snapshot.
    static String rewrite(Object projectDir, Object outputDir, String name, Object cell, Closure transform) {
        def source = cell.toString().replace(FIXTURES.UPSTREAM, FIXTURES.base(projectDir))
        def text = source.startsWith('http') ? new URL(source).text : new File(source).text
        // Beside the sheet's placeholder directory rather than in it: a rewritten fixture is a
        // deliberate statement about content, where a placeholder is an empty file that exists only
        // so a path resolves.
        def directory = new File(new File(new File(outputDir.toString()).parentFile, "samplesheets/${name}"), 'mutated')
        directory.mkdirs()
        def target = new File(directory, source.tokenize('/').last())
        target.text = transform(text.readLines()).join('\n') + '\n'
        return target.absolutePath
    }

    // Materialise a samplesheet from an explicit header and rows, bypassing the demo sheet. Used for
    // the superseded input format, which shares no columns with the current contract and therefore
    // needs no placeholders.
    static String buildRaw(Object outputDir, String name, List<String> header, List<Map> rows) {
        return materialise(outputDir, name, [header: header, rows: rows], null, null, [])
    }

    private static String materialise(Object outputDir, String name, Map sheet_source, Closure mutate, String fixture_base, List<String> file_columns) {
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
            header.findAll { column -> column in file_columns }.each { column ->
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
