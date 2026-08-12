---
name: local-issue-tracker
description: Read, create, triage, update, close, or route repository-local Markdown records under .scratch/. Use for feature specs, implementation issues, triage statuses, completion evidence, Wayfinder maps, or Wayfinder child questions. Do not use for GitHub issues or public PR tracking.
---

# Operate the local tracker

Read `docs/agents/issue-tracker.md` before acting. It defines the separate implementation-ticket and Wayfinder
record types. For an implementation ticket, also read `docs/agents/triage-labels.md` before interpreting or
changing status.

Identify the record type from its structure and the requested workflow. Do not translate status between record
types. Preserve the file format and lifecycle owned by the routed documentation.

Treat tracker writes, status changes, claims, resolutions, completion commits, and deletion commits as external
state changes: perform only the actions the user requested, and report the record path and resulting state.
