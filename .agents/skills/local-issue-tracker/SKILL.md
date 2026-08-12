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
