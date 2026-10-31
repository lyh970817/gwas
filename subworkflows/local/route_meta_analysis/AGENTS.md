# Common-variant meta-analysis route

Apply the root responsibility split and minimal-adapter contract in [AGENTS.md](../../../AGENTS.md).

METASOFT #82 (RE2 p-value table K = 2..50), METASOFT #84 (native tiny-p-value zero), and MR-MEGA #88
(pc <= K-3) are documented contracts and are never guarded, validated against, or compensated for in this
route, in the `sumstats_metaanalysis_mrmega` composition it calls, or in their callers. A behaviour recorded as
a documented contract is never guarded, validated against, or compensated for, whatever its consequence.
