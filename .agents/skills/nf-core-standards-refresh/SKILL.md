---
name: nf-core-standards-refresh
description: Refresh the ignored local cache of distilled nf-core module, subworkflow, test, PR, and fixture standards for this repository.
---

Read `../nf-core-common.md` first.

Use this skill when the user asks to fetch, refresh, update, or verify nf-core standards documentation for module or subworkflow submissions.

## Write scope

By default, write only under `docs/nf-core-standards/`. This directory is ignored by git and should remain uncommitted. Do not edit `.agents/skills/` during a refresh unless the user explicitly asks to update the skills, or the current task is to create or revise the skills themselves.

## Source manifest

Use a curated primary-source manifest. Prefer current nf-core documentation pages and primary upstream repositories; do not crawl broad sites or rely on blog posts, issue comments, or community lore for standards. Use the WebFetch tool to retrieve each source page.

Include these topics unless the user narrows the request:

- `index.md`: source map, fetch date, and topic routing.
- `component-creation.md`: component creation and contribution flow.
- `module-file-structure.md`: module directory/file expectations and naming.
- `module-main-nf.md`: process, inputs, outputs, args, meta maps, versions, stubs, and formatting.
- `module-meta-yml.md`: metadata, documentation links, bio.tools, EDAM, inputs, outputs, and topic outputs.
- `module-args-params.md`: `ext.args`/`args2..99`, `ext.prefix`, and the no-hardcoded-params rule.
- `module-meta-map.md`: `meta`/`meta2`/`meta3` maps and the assumable keys.
- `module-testing.md`: nf-test, snapshots, stubs, `nextflow.config`, profiles, and test data.
- `module-containers.md`: conda, Docker, Singularity, BioContainers, and resource labels.
- `subworkflows.md`: subworkflow structure, naming, inputs/outputs, parameters, documentation, tests, versions, and formatting.
- `test-datasets.md`: fixture reuse, `nf-core/test-datasets`, branch expectations, and test-datasets CLI commands.
- `test-data-general.md`: general test-data spec (size, licensing, reuse) across all branches.
- `contributing-prs.md`: lint/test commands, PR body expectations, review readiness, and reviewer-facing notes.

Pipeline-contribution topics (PRs against an existing pipeline; not new-pipeline creation/release):

- `pipeline-contributing.md`: fork/`dev`-branch model, commit strategy, reviewer requests, review gating.
- `pipeline-adding-components.md`: installing/updating/patching and wiring modules & subworkflows into a pipeline.
- `pipeline-schema-config.md`: `nextflow_schema.json`, parameters, and `conf/modules.config`.
- `pipeline-testing.md`: pipeline nf-test organisation, assertions/stabilisers, and `nf-core pipelines lint`.

Recommended source URLs:

- `https://nf-co.re/docs/developing/components/creating-components`
- `https://nf-co.re/docs/contributing/contribute-components`
- `https://nf-co.re/docs/specifications/components/overview`
- `https://nf-co.re/docs/specifications/components/modules/general`
- `https://nf-co.re/docs/specifications/components/modules/naming-conventions`
- `https://nf-co.re/docs/specifications/components/modules/input-output-options`
- `https://nf-co.re/docs/specifications/components/modules/documentation`
- `https://nf-co.re/docs/specifications/components/modules/resource-requirements`
- `https://nf-co.re/docs/specifications/components/modules/software`
- `https://nf-co.re/docs/specifications/components/modules/testing`
- `https://nf-co.re/docs/specifications/components/modules/formatting`
- `https://nf-co.re/docs/specifications/components/subworkflows/general`
- `https://nf-co.re/docs/specifications/components/subworkflows/naming-conventions`
- `https://nf-co.re/docs/specifications/components/subworkflows/input-output-options`
- `https://nf-co.re/docs/specifications/components/subworkflows/subworkflow-parameters`
- `https://nf-co.re/docs/specifications/components/subworkflows/documentation`
- `https://nf-co.re/docs/specifications/components/subworkflows/testing`
- `https://nf-co.re/docs/specifications/components/subworkflows/formatting`
- `https://nf-co.re/docs/specifications/components/modules/module-parameters`
- `https://nf-co.re/docs/developing/components/ext-args`
- `https://nf-co.re/docs/developing/components/meta-map`
- `https://nf-co.re/docs/specifications/test-data/overview`
- `https://nf-co.re/docs/specifications/test-data/general`
- `https://nf-co.re/docs/specifications/test-data/modules`
- `https://nf-co.re/docs/nf-core-tools/cli/modules/lint`
- `https://nf-co.re/docs/nf-core-tools/cli/modules/test`
- `https://nf-co.re/docs/nf-core-tools/cli/subworkflows/create`
- `https://nf-co.re/docs/nf-core-tools/cli/subworkflows/lint`
- `https://nf-co.re/docs/nf-core-tools/cli/subworkflows/test`
- `https://nf-co.re/docs/nf-core-tools/cli/test-datasets/list`
- `https://nf-co.re/docs/nf-core-tools/cli/test-datasets/list_branches`
- `https://github.com/nf-core/test-datasets`

Pipeline-contribution sources (existing pipeline only; skip new-pipeline creation/release/template-sync):

- `https://nf-co.re/docs/contributing/overview`
- `https://nf-co.re/docs/contributing/contribute-existing-pipelines`
- `https://nf-co.re/docs/specifications/reviews/overview`
- `https://nf-co.re/docs/specifications/reviews/commit-strategy`
- `https://nf-co.re/docs/specifications/reviews/request-reviewers`
- `https://nf-co.re/docs/developing/pipelines/adding-modules`
- `https://nf-co.re/docs/developing/pipelines/template-files`
- `https://nf-co.re/docs/nf-core-tools/modules/install`
- `https://nf-co.re/docs/nf-core-tools/modules/update`
- `https://nf-co.re/docs/nf-core-tools/cli/modules/patch`
- `https://nf-co.re/docs/nf-core-tools/subworkflows/install`
- `https://nf-co.re/docs/nf-core-tools/cli/pipelines/schema`
- `https://nf-co.re/docs/specifications/pipelines/requirements/parameters`
- `https://nf-co.re/docs/developing/testing/overview`
- `https://nf-co.re/docs/developing/testing/assertions`
- `https://nf-co.re/docs/developing/testing/advanced`
- `https://nf-co.re/docs/nf-core-tools/cli/pipelines/lint`
- `https://nf-co.re/docs/specifications/pipelines/recommendations/testing`

## Cache format

For each cached file:

- Start with the title.
- Include `Fetched: YYYY-MM-DD`.
- Include a `Sources` list with source URLs.
- Distill standards into concise, task-oriented bullets.
- Separate upstream nf-core rules from repository-specific submission mechanics when both are relevant.
- Do not mirror raw pages or copy long passages.
- Keep the cache text-first and narrow enough for agents to read quickly.

## Refresh procedure

1. Check `git status --short --untracked-files=all` and note unrelated changes.
2. Fetch the curated sources with WebFetch. Verify moved URLs against primary nf-core or GitHub sources.
3. Rebuild the topic files under `docs/nf-core-standards/`.
4. Update `docs/nf-core-standards/index.md` with source URLs, fetch date, and topic routing.
5. Run `git diff --check -- .agents/skills .gitignore AGENTS.md` if committed files changed; otherwise run a whitespace check over the changed cache files if convenient.
6. Report changed cache files and any skill procedure that now appears stale. Do not commit unless explicitly asked.
