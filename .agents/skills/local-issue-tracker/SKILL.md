---
name: local-issue-tracker
description: Read, create, triage, update, close, or route repository-local Markdown records under .scratch/. Use for implementation issues/specs, triage state, completion evidence, Wayfinder maps, or Wayfinder child questions. Do not use for GitHub issues or public PRs.
---

# Operate the local tracker

Read `docs/agents/issue-tracker.md`; for an implementation ticket, also read
`docs/agents/triage-labels.md`. Identify the record type from its structure, then follow its canonical schema and
lifecycle without translating state between record types.

Perform only the requested create/fetch/claim/resolve/triage/close actions. Before a close, record completion
state, acceptance reconciliation, and evidence in the ticket; commit that durable record before a separate
deletion commit. Report the record path, actions/commits, and resulting state.

## Wayfinder write procedure

When the requested action includes operating a Wayfinder child:

1. Read the map and child records, then select the explicitly named child or the first numbered open child whose
   `Blocked by:` dependencies are all `Status: resolved`.
2. Before doing the child work, change only its plain `Status:` field to `claimed` and commit that claim as a
   durable boundary. Do not use an implementation-ticket triage label or bold `**Status:**` syntax.
3. When the question is answered, append the result under `## Answer`, change its plain status to `resolved`,
   and append a concise gist plus a link to the child under the map's Decisions-so-far section.
4. Commit the resolved child and map pointer together. Report both the claim commit and resolution commit; do not
   call the child resolved if either the answer or map pointer is missing.
