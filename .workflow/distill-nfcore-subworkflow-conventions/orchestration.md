# Orchestration

1. Run four independent research packets against the companion subworkflow tree.
2. Integrate repeated conventions, rejecting observations that are isolated, stale, or already covered.
3. Update the applicable shared references under `.agents/skills/references/` and the owning lifecycle skills
   only where their decision responsibilities require it.
4. Run a separate review pass over the integrated skill changes.
5. Validate Markdown diffs, repository status, and the original GCTA rename tests.

Packets:

- naming-layout: directory names, workflow names, ordering, file layout, comments.
- contracts-metadata: take/emit structures, identity, optional inputs, meta.yml.
- composition-versions: module inclusion, channel operators, versions, scatter/gather.
- tests-config: nf-test structure, tags, snapshots, nextflow.config, fixtures and stubs.

Integration policy: accept only rules with clear evidence and meaningful behavioural value; record exceptions alongside the rule when they change application.
