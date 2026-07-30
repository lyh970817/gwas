# Packet 17: LDAK HE and PCGC routes

Objective: Implement issue 17 as the blocking first-release gate.

Context: The established LDAK REML route and shared relatedness-matrix machinery are the reference.
HE and PCGC are separate public method tokens. Covariates trigger matrix adjustment; their absence
must bypass it. All three LDAK estimators reuse one kinship build.

Files / sources: issue 17, first-release spec, LDAK heritability subworkflow, workflow wiring,
module configuration, pipeline tests, and the vendored `ldak/adjustgrm` contract.

Ownership: Root owns all issue-17 code/tests and its commit.

Do: Work as vertical public-seam slices; verify the actual LDAK container's adjustment arguments;
test route outputs, conditional adjustment, shared kinship execution count, and three-result fan-out.

Do not: Start issue 18/19, commit machine-local fixture paths, or modify user-owned scratch state.

Expected output: One focused-green issue-17 commit and a result note.

Verification: Focused `nf-test` route file(s), trace/output assertions, `git diff --check`.
