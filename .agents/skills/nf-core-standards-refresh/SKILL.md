---
name: nf-core-standards-refresh
description: Refresh or verify the ignored docs/nf-core-standards cache from the curated primary-source manifest. Do not use for changing canonical repository standards or lifecycle skills.
---

# Refresh the nf-core standards cache

Read [`../references/nf-core-standards-sources.tsv`](../references/nf-core-standards-sources.tsv) for the curated
topic/source inventory and
[`contribution-boundaries.md`](../../../docs/coding-standards/contribution-boundaries.md) for precedence.

## Write boundary

Write only under ignored `docs/nf-core-standards/` unless the user explicitly asks to change the manifest,
skills, or canonical standards. Do not commit generated cache files.

## Procedure

1. Record repository status and preserve unrelated changes.
2. Fetch each source selected by the manifest from primary nf-core documentation or its upstream repository.
   Verify moved URLs; do not replace a primary source with a blog, issue anecdote, or community summary.
3. Rebuild only the selected topic files. Each starts with a title, fetch date, and source list, then distills
   concise task-oriented rules. Separate upstream rules from repository-specific mechanics.
4. Update `docs/nf-core-standards/index.md` with source mapping, fetch date, and topic routing. Do not mirror raw
   pages or long passages.
5. Check changed cache files for whitespace and broken source references. If the user also authorized tracked
   guidance changes, run `git diff --check` on those exact tracked paths.

Report changed cache topics, fetch date, source failures or moves, and any skill procedure or canonical standard
that now appears stale. Do not commit unless explicitly asked.
