include { getMethodCapability ; getMethodTokensWithCapabilities } from './method_registry'

// Which native LDSC operation a request owns follows from its registered domain: a unary summary request owns
// `--h2` and a pairwise one owns `--rg`, so each is protected for its own method and refused for the other.
def getLdscProtectedNativeArgumentMatches(method, argument_tokens) {
    def ldsc_typed_resources = [
        '--annot',
        '--bfile',
        '--cts-bin',
        '--extract',
        '--frqfile',
        '--frqfile-chr',
        '--h2-cts',
        '--keep',
        '--print-snps',
        '--ref-ld',
        '--ref-ld-chr-cts',
        '--w-ld',
    ]
    def protected_by_method = getMethodTokensWithCapabilities([option_family: 'ldsc']).collectEntries { token ->
        def is_pairwise = getMethodCapability(token, 'domain') == 'pairwise'
        [(token): [
            wrapper_owned: [is_pairwise ? '--rg' : '--h2', '--ref-ld-chr', '--w-ld-chr', '--samp-prev', '--pop-prev', '--out'],
            typed_resource: ldsc_typed_resources,
            alternate_operation: ['--l2', is_pairwise ? '--h2' : '--rg'],
        ]]
    }
    def protection_sets = protected_by_method[method] ?: [:]
    return argument_tokens.collectEntries { argument_token ->
        def option_name = argument_token.contains('=') ? argument_token.substring(0, argument_token.indexOf('=')) : argument_token
        def exact = protection_sets.collectMany { kind, options -> options.findAll { protected_option -> protected_option == option_name }.collect { protected_option -> [kind: kind, option: protected_option] } }
        def prefix = option_name.startsWith('--') && option_name.size() > 2
            ? protection_sets.collectMany { kind, options ->
                options
                    .findAll { protected_option -> protected_option.startsWith(option_name) }
                    .collect { protected_option -> [kind: kind, option: protected_option] }
            }
            : []
        def matches = exact ?: prefix
        [(argument_token): matches ? [option_name: option_name, exact: !exact.isEmpty(), matches: matches.unique()] : null]
    }
}

def validateSummaryNativeArgumentTokens(method_options, namespace, request_id, method, native_args) {
    def fail = { reason ->
        error("[nf-core/gwas] ERROR: Method-options document '${method_options}', namespace '${namespace}', request_id '${request_id}', option 'native_args': ${reason}")
    }
    if (!(native_args instanceof List)) {
        fail.call('expected an array of individual command-line argument tokens')
    }
    if (native_args && !native_args.first().toString().startsWith('--')) {
        fail.call("the first token must be a native option beginning with '--'")
    }
    // Both LDAK summary estimators run the same wrapper-owned invocation shape, so one protection set covers
    // every registered LDAK summary method rather than one literal key per token.
    def ldsc_methods = getMethodTokensWithCapabilities([option_family: 'ldsc'])
    def ldak_summary_methods = getMethodTokensWithCapabilities([option_family: 'ldak', input_backend: 'summary_statistics'])
    def reserved_by_method = ldak_summary_methods.collectEntries { token ->
        [(token): [
            '--sum-hers',
            '--sum-cors',
            '--summary',
            '--summary2',
            '--tagfile',
            '--out',
            '--threads',
            '--max-threads',
            '--prevalence',
            '--ascertainment',
            '--prevalence2',
            '--ascertainment2',
        ]]
    }
    def undeclared_file_options = ldak_summary_methods.collectEntries { token ->
        [(token): [
            '--alternative-tags',
            '--categories',
            '--exclude',
            '--extract',
            '--keep',
            '--labels',
            '--matrix',
            '--remove',
            '--weights',
        ]]
    }
    native_args.eachWithIndex { token, index ->
        if (!(token instanceof String) || !token) {
            fail.call("token ${index + 1} must be a non-empty string")
        }
        if (!(token ==~ /^[A-Za-z0-9_.:+,@%=-]+$/)) {
            fail.call("token ${index + 1} '${token}' contains whitespace, shell syntax or a path separator; pass individual non-file native tokens only")
        }
        if (token ==~ /^[A-Za-z_][A-Za-z0-9_]*=.*/) {
            fail.call("token ${index + 1} '${token}' resembles an environment assignment; native arguments cannot alter the task environment")
        }
        def option_name = token.contains('=') ? token.substring(0, token.indexOf('=')) : token
        if (method in ldsc_methods) {
            def protection = getLdscProtectedNativeArgumentMatches(method, [token])[token]
            if (protection) {
                if (!protection.exact) {
                    def matched_options = protection.matches.collect { match -> match.option }.unique().sort().join(', ')
                    fail.call("token ${index + 1} '${token}' is a protected LDSC option abbreviation matching ${matched_options}; abbreviated options cannot bypass wrapper-owned invocation, typed-resource or primary-operation controls")
                }
                def kind = protection.matches.first().kind
                if (kind == 'wrapper_owned') {
                    fail.call("token ${index + 1} '${token}' conflicts with wrapper-owned invocation mechanics")
                }
                if (kind == 'typed_resource') {
                    fail.call("token ${index + 1} '${token}' requires a typed staged resource, but this request architecture declares no such file role")
                }
                fail.call("token ${index + 1} '${token}' selects a different primary operation from wrapper-owned method '${method}'")
            }
        }
        else {
            if (option_name in (reserved_by_method[method] ?: [])) {
                fail.call("token ${index + 1} '${token}' conflicts with wrapper-owned invocation mechanics")
            }
            if (option_name in (undeclared_file_options[method] ?: [])) {
                fail.call("token ${index + 1} '${token}' requires a typed staged resource, but this request architecture declares no such file role")
            }
        }
        def argument_value = token.contains('=') ? token.substring(token.indexOf('=') + 1) : token
        if (!token.startsWith('--') || token.contains('=')) {
            def candidate = file(argument_value)
            def looks_like_file = argument_value ==~ /(?i).+\.(gz|bgz|txt|tsv|csv|list|tagging|annot|l2\.ldscore|weights|sumstats)/
            if (candidate.exists() || looks_like_file) {
                fail.call("token ${index + 1} '${token}' resembles an undeclared file input; file-taking native options require a typed staged resource")
            }
        }
    }
    if (method in ldak_summary_methods) {
        def option_names = native_args
            .findAll { token -> token instanceof String && token.startsWith('--') }
            .collect { token -> token.split('=', 2)[0] }
        if (option_names.contains('--cutoff') && option_names.contains('--truncate')) {
            fail.call("'--cutoff' and '--truncate' are mutually exclusive LDAK large-effect policies")
        }
    }
    return native_args
}

def validateNativeArgumentTokens(method_options, request_id, native_args) {
    def fail = { reason ->
        error("[nf-core/gwas] ERROR: Method-options document '${method_options}', pair_request_id '${request_id}', option 'native_args': ${reason}")
    }
    if (!(native_args instanceof List)) {
        fail.call('expected an array of individual command-line argument tokens')
    }
    if (native_args && !native_args.first().toString().startsWith('--')) {
        fail.call("the first token must be a native option beginning with '--'")
    }

    def reserved = [
        '--reml-bivar',
        '--reml-bivar-prevalence',
        '--HEreg-bivar',
        '--bfile',
        '--pfile',
        '--mbfile',
        '--mpfile',
        '--grm',
        '--mgrm',
        '--grm-gz',
        '--mgrm-gz',
        '--pheno',
        '--mpheno',
        '--qcovar',
        '--covar',
        '--keep',
        '--remove',
        '--extract',
        '--exclude',
        '--update-sex',
        '--dosage-mach',
        '--dosage-beagle',
        '--raw-files',
        '--out',
        '--thread-num',
        '--prevalence',
        '--help',
        '--version',
    ]
    def primary_operations = [
        '--reml',
        '--reml-ldms',
        '--make-grm',
        '--make-grm-part',
        '--make-bK-sparse',
        '--fastGWA-mlm',
        '--fastGWA-mlm-binary',
        '--mlma',
        '--cojo-slct',
        '--cojo-joint',
        '--HEreg',
        '--pca',
        '--pca-loading',
        '--freq',
        '--ld',
        '--ld-score',
        '--sblup',
        '--blup-snp',
        '--simu-qt',
        '--simu-cc',
        '--simu-causal-loci',
        '--GTDT',
    ]

    native_args.eachWithIndex { token, index ->
        if (!(token instanceof String) || !token) {
            fail.call("token ${index + 1} must be a non-empty string")
        }
        if (!(token ==~ /^[A-Za-z0-9_.:+,@%=-]+$/)) {
            fail.call("token ${index + 1} '${token}' contains whitespace, shell syntax or a path separator; pass individual non-file native tokens only")
        }
        if (token ==~ /^[A-Za-z_][A-Za-z0-9_]*=.*/) {
            fail.call("token ${index + 1} '${token}' resembles an environment assignment; native arguments cannot alter the task environment")
        }
        def option_name = token.contains('=') ? token.substring(0, token.indexOf('=')) : token
        if (option_name in reserved) {
            fail.call("token ${index + 1} '${token}' conflicts with wrapper-owned invocation mechanics")
        }
        if (option_name in primary_operations || option_name.startsWith('--make-') || option_name.startsWith('--fastGWA') || option_name.startsWith('--mlma') || option_name.startsWith('--cojo-') || option_name.startsWith('--simu-')) {
            fail.call("token ${index + 1} '${token}' selects a different primary GCTA operation")
        }
        def argument_value = token.contains('=') ? token.substring(token.indexOf('=') + 1) : token
        if (!token.startsWith('--') || token.contains('=')) {
            def candidate = file(argument_value)
            def looks_like_file = argument_value ==~ /(?i).+\.(bed|bim|fam|pgen|pvar|psam|vcf|bcf|gz|bgz|txt|tsv|csv|list|keep|remove|grm|mgrm|phen|pheno|covar|qcovar|dat)/
            if (candidate.exists() || looks_like_file) {
                fail.call("token ${index + 1} '${token}' resembles an undeclared file input; file-taking native options require a typed staged resource")
            }
        }
    }
    return native_args
}
