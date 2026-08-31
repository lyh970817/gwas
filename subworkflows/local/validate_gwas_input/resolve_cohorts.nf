include { getGenotypeGroups ; normaliseCellValue ; validateGenotypeGroup } from './manifest_contracts'

def resolveCohorts(cohort_rows, cohort_columns, cohort_manifest, errors) {
    def cohorts_by_id = [:]
    cohort_rows.eachWithIndex { row, index ->
        def line = index + 2
        def cohort_meta = row[0]
        def cells = [cohort_columns, row[1..-1]].transpose().collectEntries()
        def cohort_id = cohort_meta.cohort
        def reject = { field, message ->
            def named = field instanceof List ? field : [field]
            def label = named.size() > 1
                ? "fields ${named.collect { name -> "'${name}'" }.join(', ')}"
                : "field '${named.first()}'"
            errors << "  - ${cohort_manifest} row ${line} (cohort_id '${cohort_id}'), ${label}: ${message}"
        }

        def genotype_format = validateGenotypeGroup(cells, reject)
        def genotype_files = genotype_format
            ? getGenotypeGroups()[genotype_format].collect { column -> cells[column] }
            : []
        def definition = [
            genome_build: cohort_meta.build,
            ancestry: cohort_meta.ancestry,
        ] + getGenotypeGroups().values().flatten().collectEntries { field -> [(field): normaliseCellValue(cells[field])?.toString() ?: ''] }
        def known = cohorts_by_id[cohort_id]
        if (known) {
            if (known.definition == definition) {
                reject.call('cohort_id', "duplicate cohort_id '${cohort_id}', identical definition on row ${known.line}")
            }
            else {
                def differing_fields = definition.keySet().findAll { field -> known.definition[field] != definition[field] }
                reject.call('cohort_id', "duplicate cohort_id '${cohort_id}' conflicts with row ${known.line} in field${differing_fields.size() > 1 ? 's' : ''} ${differing_fields.collect { field -> "'${field}'" }.join(', ')}")
            }
        }
        else {
            cohorts_by_id[cohort_id] = [
                line: line,
                meta: cohort_meta,
                genotype_format: genotype_format,
                genotype_files: genotype_files,
                definition: definition,
            ]
        }
    }
    return [cohorts_by_id: cohorts_by_id]
}
