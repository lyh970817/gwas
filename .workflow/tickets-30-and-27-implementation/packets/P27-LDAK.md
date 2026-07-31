# P27-LDAK: Guard coverage and metadata contract

In a separate dedicated `../modules/.worktrees/modules/` worktree and focused
branch from committed `gwas/integration`, add the missing unsupported-estimator
test and repair `grm_heritability_ldak/meta.yml` so every declared output
matches an emitted metadata-bearing result or versions tuple. Keep runtime code,
all eight strict joins, positive tests, and stub tests unchanged. Run focused
lint and Docker nf-test, then commit only this component's files.
