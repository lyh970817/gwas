# P27-GCTA: Heritability guard coverage

In a dedicated `../modules/.worktrees/modules/` worktree and focused branch
from committed `gwas/integration`, add only the two missing negative
estimator/MGRM tests for `grm_heritability_gcta`. Keep runtime code, all four
strict joins, positive tests, stub tests, and existing unsupported-estimator
coverage unchanged. Run focused lint and Docker nf-test, then commit only this
component's files.
