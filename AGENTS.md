# AGENTS.md

## Coding standards

`CODING_STANDARDS.md` at the repo root is the documented coding standard, indexing the topic files under
`docs/coding-standards/`. It is the standards source for the `code-review` skill. For anything destined for
upstream `nf-core/modules`, the `nf-core-*` skills under `.agents/skills/` take precedence over it.

### Reference pipelines

`../sarek`, `../mag` and `../rnaseq` are checkouts of established official nf-core pipelines and are the
style reference for this repository. `CODING_STANDARDS.md` was derived from them, so consult the checkouts
directly whenever a question is not settled by the written standard — how a `.nf` file is laid out, how
`conf/modules.config` selectors are written, how `nextflow_schema.json` is structured, how nf-test files and
snapshots are organised, how `docs/usage.md` and `docs/output.md` read. Prefer what these three actually do
over what looks reasonable in the abstract.

Two caveats when reading them. Where the three disagree, the disagreement is usually a migration in
progress rather than a genuine choice — take the newer side (lowercase `channel.*` factories, topic-channel
version reporting, the newer container ternary, Wave container URIs). And they are not uniformly clean;
`CODING_STANDARDS.md` records their inconsistencies as well as their conventions, so where it has already
ruled on a point, it wins over a contrary example found in a checkout.

## Agent skills

### Issue tracker

Issues and specs live as markdown files under `.scratch/<feature-slug>/` in this repo. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles are used as-is (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`), recorded as a `Status:` line in each issue file. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
