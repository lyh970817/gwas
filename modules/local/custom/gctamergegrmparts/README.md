# Ordered GCTA row-part merge

GNU `cat` concatenates each of three corresponding ordered file lists: binary GRM
values (`.grm.bin`), per-pair marker counts (`.grm.N.bin`), and sample identifiers
(`.grm.id`). The lists contain the parts of one GCTA `--make-grm-part` operation in
numeric part order. File names need not sort lexically into that order.

The caller supplies all ordering and part-selection information. The module emits
one native dense GRM bundle and preserves the incoming metadata. It performs no
SNP-group planning, cohort selection, normalisation, or scientific recomputation.
The executable owner and version provider is GNU coreutils, pinned in
`environment.yml`; no separate helper package is required.
