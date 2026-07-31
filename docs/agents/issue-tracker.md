# Issue tracker: Local Markdown

Issues and specs (you may know a spec as a PRD) for this repo live as markdown files in `.scratch/`.

## Conventions

- One feature per directory: `.scratch/<feature-slug>/`
- The spec is `.scratch/<feature-slug>/spec.md`
- Implementation issues are one file per ticket at `.scratch/<feature-slug>/issues/<NN>-<slug>.md`, numbered from `01` — never a single combined tickets file
- Triage state is recorded as a bolded `**Status:**` line in each issue file, directly after the `**Blocked by:**` line and before the acceptance criteria (see `triage-labels.md` for the role strings)
- Comments and conversation history append to the bottom of the file under a `## Comments` heading

## When a skill says "publish to the issue tracker"

Create a new file under `.scratch/<feature-slug>/` (creating the directory if needed).

## When a skill says "fetch the relevant ticket"

Read the file at the referenced path. The user will normally pass the path or the issue number directly.

## Closing a completed ticket

Closing a local ticket mirrors closing a GitHub issue, with Git history retaining
the completed record instead of leaving finished files in the active tracker:

1. Finish the work and reconcile the ticket while its file still exists: set
   `**Status:** done`, check every completed acceptance criterion, and record the
   implementation and verification evidence under `## Comments`.
2. Commit that ticket-file update. This commit is the durable closed-issue
   record and must contain enough evidence to understand why the ticket is done.
3. Only after that commit exists, delete the completed ticket file and commit
   the deletion separately. Never combine completion evidence and deletion in
   one commit.

`done` is therefore a transitional on-disk state and a permanent state in Git
history. Active tracker scans should not retain ticket files whose completed
record has already been committed. Preserve the feature spec, map, handoff, and
unfinished sibling tickets unless their own lifecycle says otherwise.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a file with one **child** file per ticket.

- **Map**: `.scratch/<effort>/map.md` — the Notes / Decisions-so-far / Fog body.
- **Child ticket**: `.scratch/<effort>/issues/NN-<slug>.md`, numbered from `01`, with the question in the body. A `Type:` line records the ticket type (`research`/`prototype`/`grilling`/`task`); a `Status:` line records `claimed`/`resolved`.
- **Blocking**: a `Blocked by: NN, NN` line near the top. A ticket is unblocked when every file it lists is `resolved`.
- **Frontier**: scan `.scratch/<effort>/issues/` for files that are open, unblocked, and unclaimed; first by number wins.
- **Claim**: set `Status: claimed` and save before any work.
- **Resolve**: append the answer under an `## Answer` heading, set `Status: resolved`, then append a context pointer (gist + link) to the map's Decisions-so-far in `map.md`.
