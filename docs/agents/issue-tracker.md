# Local Markdown record types

This repository stores two record types under `.scratch/`. Identify the record type before reading or changing
status; their fields and status vocabularies are intentionally different and must not be translated between
them.

## Implementation issues and specs

Use this record type for ordinary feature planning, implementation, triage, and closure.

### Conventions

- One feature per directory: `.scratch/<feature-slug>/`
- The spec is `.scratch/<feature-slug>/spec.md`
- Implementation issues are one file per ticket at `.scratch/<feature-slug>/issues/<NN>-<slug>.md`, numbered from `01` — never a single combined tickets file
- Triage state is recorded as a bolded `**Status:**` line in each issue file, directly after the `**Blocked by:**` line and before the acceptance criteria (see `triage-labels.md` for the role strings)
- Comments and conversation history append to the bottom of the file under a `## Comments` heading

### Completion lifecycle

Closing a local ticket mirrors closing a GitHub issue, with Git history retaining
the completed record instead of leaving finished files in the active tracker:

The durable history must contain a completed record before deletion: set `**Status:** done`, reconcile
acceptance criteria, and record implementation/verification evidence under `## Comments`; commit that record,
then delete the active ticket in a separate commit. `local-issue-tracker` owns the operational steps.

`done` is therefore a transitional on-disk state and a permanent state in Git
history. Active tracker scans should not retain ticket files whose completed
record has already been committed. Preserve the feature spec, map, handoff, and
unfinished sibling tickets unless their own lifecycle says otherwise.

## Wayfinder maps and child questions

Use this record type only for a Wayfinder operation. The **map** is a file with one **child** file per question.
Wayfinder `claimed`/`resolved` state is not an implementation-ticket triage label and does not use the bolded
`**Status:**` convention above.

- **Map**: `.scratch/<effort>/map.md` — the Notes / Decisions-so-far / Fog body.
- **Child question**: `.scratch/<effort>/issues/NN-<slug>.md`, numbered from `01`, with the question in the body. A `Type:` line records the question type (`research`/`prototype`/`grilling`/`task`); a plain `Status:` line records `claimed`/`resolved`.
- **Blocking**: a `Blocked by: NN, NN` line near the top. A child question is unblocked when every child it lists has `Status: resolved`.
- **Frontier**: scan `.scratch/<effort>/issues/` for child questions that are open, unblocked, and unclaimed; first by number wins.
- **Claim semantics**: work begins only after the child is durably `Status: claimed`.
- **Resolution semantics**: a resolved child contains its answer and the map's Decisions-so-far contains a
  context pointer. `local-issue-tracker` owns the write procedure.
