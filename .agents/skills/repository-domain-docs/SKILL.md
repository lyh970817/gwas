---
name: repository-domain-docs
description: Route design, naming, architecture, or domain-model work through this repository's local CONTEXT.md and docs/adr/ decisions. Use when a task introduces or changes domain terminology, boundaries, invariants, or architecture. Do not use for mechanical edits, test execution, formatting, or component submission rules already owned by an nf-core skill.
---

# Consult repository domain documentation

Read `docs/agents/domain.md` when it exists in the active local checkout, then follow its routing to the relevant
domain context and ADRs. The domain documentation and records are intentionally ignored local state; do not copy
their contents into this skill, relocate them, or start tracking them as part of an instruction-maintenance task.

Report any applicable terminology or ADR constraint that materially changes the task. If the routed local files
are absent, continue without proposing them as prerequisite work.
