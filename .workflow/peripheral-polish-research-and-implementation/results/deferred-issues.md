# Deferred peripheral-polish issues

## Sources and tracker constraints

This decomposition follows `docs/agents/issue-tracker.md` and
`docs/agents/triage-labels.md`:

- publish one issue per Markdown file under a feature-specific `.scratch/`
  directory;
- put `**Blocked by:**` before `**Status:**`, then the acceptance criteria;
- use a canonical status that identifies who can act next;
- record implementation and verification under `## Comments` when work lands;
- close a completed local ticket with a committed `done` evidence update, then
  delete it in a separate commit.

The current first-release tracker demonstrates two useful patterns:

- `.scratch/first-release-pipeline/issues/20-release-readiness.md` keeps a
  release-boundary verification ticket separate from feature development.
- `.scratch/first-release-pipeline/issues/29-publish-first-release-fixtures-and-samplesheet-to-test-datasets.md`
  marks external publication as `ready-for-human` and names exact artifacts and
  destinations rather than allowing an agent to infer publication authority.

No production issue files were created by this packet. When the root agent
publishes the accepted drafts, use a new feature directory so these later
enhancements do not become blockers for the existing first-release contract:

```text
.scratch/reporting-and-release-polish/
|-- spec.md
`-- issues/
    |-- 01-add-association-diagnostic-reporting.md
    |-- 02-add-heritability-result-reporting.md
    |-- 03-document-visual-reports-and-public-full-results.md
    `-- 04-finalize-first-release-identity-and-metadata.md
```

The feature spec should explicitly state that the current peripheral-polish run
does not owe these capabilities. Tickets 01 and 02 create report content; ticket
03 documents and illustrates that content only after it is stable; ticket 04
finalizes public release identity at the release boundary.

## 01 - Add association diagnostic reporting

**Proposed filename:**
`.scratch/reporting-and-release-polish/issues/01-add-association-diagnostic-reporting.md`

**Proposed status:** `ready-for-agent`

**Blocked by:** None. It is intentionally outside the current polish run, but
the desired outcome is implementable without a new product decision. It must
not be retroactively made a blocker for first-release issue 20, whose current
criterion explicitly expects no custom Manhattan or QQ content.

**What to build:** Add truthful, route-aware association diagnostics to the
published report. Generate QQ plots and, if accepted within the same design,
Manhattan plots only from standardized association results whose column and
build contracts are known. Keep plotting and report policy outside atomic
upstream-candidate modules. A missing or ineligible result must be represented
as unavailable, never as a successful empty plot.

**Acceptance criteria:**

- [ ] The design names the exact eligible standardized result artifact and the
  required variant identifier, chromosome, position, effect and p-value fields;
  native method-specific files are not parsed through unverified heuristics.
- [ ] Every plotted panel is keyed by stable `analysis_id`, cohort, trait and
  method identity, and its title/description does not imply that `ancestry`
  selected a scientific reference when it only records provenance.
- [ ] QQ plotting rejects invalid, missing, non-finite or out-of-range p-values
  deterministically and reports input/filter counts alongside the plot.
- [ ] Observed and expected QQ coordinates use a documented convention;
  genomic-inflation or other scalar diagnostics are omitted unless their
  definition and supported interpretation are separately specified and tested.
- [ ] Large result files are handled with a documented bounded-memory or
  deterministic down-sampling strategy that does not silently change reported
  counts.
- [ ] The report gracefully handles a heterogeneous run containing eligible,
  failed, absent and heritability-only analyses.
- [ ] Focused nf-tests cover at least one eligible quantitative association,
  one binary association, malformed p-values, and a run with no eligible
  association result; snapshots assert stable report identifiers and content.
- [ ] `docs/output.md` explains the plots, their inputs, filtering, limitations
  and exact output locations without offering scientific significance advice.
- [ ] Existing software-version, methods-description and compact run-summary
  sections remain present and non-duplicative.

**Required completion evidence format:** Under `## Comments`, record:

1. `Implementation:` exact process/subworkflow/config/docs paths and the
   standardized input contract used.
2. `Fixtures:` exact fixture analyses and why they exercise the supported
   column/build/trait cases.
3. `Verification:` exact nf-test commands with pass counts, report output path,
   and a manual inspection note naming the rendered sections.
4. `Contract checks:` observed invalid-p-value behavior, no-result behavior,
   and deterministic identity/down-sampling evidence.
5. `Deferred/owned elsewhere:` any Manhattan, scalar diagnostic or scientific
   interpretation criterion deliberately split to another named ticket.

## 02 - Add heritability result reporting

**Proposed filename:**
`.scratch/reporting-and-release-polish/issues/02-add-heritability-result-reporting.md`

**Proposed status:** `ready-for-agent`

**Blocked by:** None. Keep it separate from association diagnostics because
GCTA and LDAK emit estimator-specific result contracts, while QQ plots consume
variant-level association statistics. Combining them would hide different
scientific semantics and verification surfaces.

**What to build:** Produce a compact report section for completed individual-
level heritability analyses. Normalize only a deliberately supported set of
estimator outputs into a documented pipeline-owned summary contract, retain the
method/estimator identity, and expose estimates and uncertainty without trying
to compare unlike estimators.

**Acceptance criteria:**

- [ ] A documented pipeline-owned tabular or JSON contract defines one record
  per reportable analysis/estimator and names required identity, estimate,
  standard-error or interval, sample-count and status fields.
- [ ] Parsers are explicit for each supported GCTA and LDAK result family;
  method-specific meanings are not collapsed into a generic `heritability`
  value without an estimator label and definition.
- [ ] Missing, failed, non-converged, boundary and otherwise unreportable
  estimates retain their status and do not appear as zero or successful rows.
- [ ] The MultiQC presentation is a compact table suitable for heterogeneous
  runs, preserves `analysis_id`, cohort, trait, method and estimator identity,
  and avoids ranking or cross-estimator comparison.
- [ ] Population prevalence, liability-scale transformations and other
  estimator-specific quantities appear only where the executed method consumes
  them and the output semantics are verified.
- [ ] Focused nf-tests cover at least one supported GCTA result, one supported
  LDAK result, a missing/failed result and an association-only run; snapshots
  assert stable normalized output and rendered report content.
- [ ] `docs/output.md` identifies native outputs as authoritative, defines every
  normalized report field, and states limitations and unsupported estimators.
- [ ] The existing compact run-summary table links or maps unambiguously to the
  detailed heritability rows without duplicating conflicting values.

**Required completion evidence format:** Under `## Comments`, record:

1. `Implementation:` exact parsers, normalized schema, MultiQC config and docs.
2. `Estimator mapping:` a table of each supported native output field to the
   normalized field, units/scale and missing/failure rule.
3. `Fixtures:` exact successful and unsuccessful GCTA/LDAK fixture artifacts.
4. `Verification:` exact nf-test commands with pass counts, normalized artifact
   paths, generated report path and manual inspection note.
5. `Unsupported:` named estimator/result families deliberately not summarized.

## 03 - Document visual reports and public full results

**Proposed filename:**
`.scratch/reporting-and-release-polish/issues/03-document-visual-reports-and-public-full-results.md`

**Proposed status:** `needs-info`

**Blocked by:** 01 - Add association diagnostic reporting; 02 - Add
heritability result reporting. It also requires a maintainer-designated stable
public full-results run and durable public URLs. `needs-info` is more accurate
than `ready-for-agent` until those artifacts and publication destinations
exist.

**What to build:** Once the real report panels and a representative public run
exist, add curated screenshots and a concise public-results narrative to the
README/output documentation. Explain what the run exercises and where users
can inspect its report and artifacts. Do not manufacture screenshots from mock
UI or present the small fixture suite as a scalability or scientific benchmark.

**Information the maintainer must supply before implementation:**

- the immutable or versioned public run URL;
- the exact pipeline revision/release, input dataset and profile represented;
- confirmation that the run may be publicly displayed;
- which runtime/cost/scale claims, if any, have sufficient provenance to print;
- the preferred durable location for image assets.

**Acceptance criteria:**

- [ ] Every screenshot is captured from the designated public run after
  tickets 01 and 02 are complete and contains no secret, private path, personal
  identifier or misleading failed/partial state.
- [ ] Screenshots include useful alt text, legible crops/resolution and a
  caption naming the pipeline version and represented analysis type.
- [ ] The narrative names dataset scale, routes exercised, execution profile,
  pipeline revision and known limitations, each traceable to the public run.
- [ ] Runtime, cost or resource figures are included only when their executor,
  region/hardware and measurement basis are recorded; otherwise they are
  omitted rather than generalized.
- [ ] README and output-guide links resolve to durable public artifacts and do
  not point at local work directories, expiring task URLs or a moving `dev`
  result presented as a release result.
- [ ] The text distinguishes correctness demonstration from scientific and
  performance benchmarking.
- [ ] Markdown link/image checks pass and the pages are manually inspected in a
  rendered view at desktop and narrow widths.

**Required completion evidence format:** Under `## Comments`, record:

1. `Public run:` immutable URL, revision/version, profile, dataset identifier,
   completion date and maintainer publication confirmation.
2. `Assets:` each source panel, committed asset path, alt text and redaction
   check.
3. `Claims:` each scale/runtime/resource claim and the artifact supporting it.
4. `Verification:` link-check command/output plus rendered desktop/narrow-view
   inspection notes.

## 04 - Finalize first-release identity and metadata

**Proposed filename:**
`.scratch/reporting-and-release-polish/issues/04-finalize-first-release-identity-and-metadata.md`

**Proposed status:** `ready-for-human`

**Blocked by:** Existing first-release issue 46 - Validate the relational
contract as the release boundary, and issue 20 - Release readiness. The human
owner must choose/mint the public release and DOI; repository metadata edits can
then be delegated within this ticket or split into an agent follow-up.

**What to build:** At the actual first-release boundary, replace prerelease and
template placeholders with one coherent public identity across manifest,
README, citations, changelog, documentation links, MultiQC metadata and
RO-Crate. Record the confirmed contributor `lyh970817` with
`lyh970817@yandex.com` where email is supported, without inventing affiliation,
ORCID or contributor roles beyond those approved by the maintainer.

**Human-owned inputs/actions:**

- approve the release version, date, default/release branch and release tag;
- mint or select the DOI/archive record and confirm its canonical citation;
- approve contributor ordering, roles and any affiliation/ORCID data;
- publish the release/archive and supply durable versioned documentation URLs.

**Acceptance criteria:**

- [ ] No fake DOI, template TODO, placeholder contributor guidance or stale
  prerelease citation remains in user-visible files.
- [ ] README badges/citation, `nextflow.config` manifest identity, changelog,
  `CITATIONS.md`, MultiQC metadata and RO-Crate agree on pipeline name, release
  version, release date, repository URL, DOI and canonical citation.
- [ ] `lyh970817` is present in the supported contributor metadata with
  `lyh970817@yandex.com`; affiliation, ORCID and roles are included only if the
  maintainer explicitly supplies them.
- [ ] Development builds link to development documentation and the release
  artifact links to durable versioned documentation; no historical report is
  made to silently point at a changing output contract where versioned links
  are supported.
- [ ] The default branch recorded in metadata agrees with the live repository
  policy and release automation.
- [ ] RO-Crate is regenerated from finalized source metadata rather than edited
  as an independent, potentially divergent snapshot.
- [ ] The changelog contains the real version/date and describes user-visible
  input, route and output contracts, including breaking changes and migrations.
- [ ] Schema/config validation, Markdown link checking, nf-core lint and the
  repository's release metadata checks pass against the tagged candidate.
- [ ] Release/archive publication, push, tag and external writes occur only
  after explicit human approval and are recorded separately from local edits.

**Required completion evidence format:** Under `## Comments`, record:

1. `Human approvals:` approver and confirmed version, tag, date, branch, DOI,
   citation and contributor fields.
2. `Consistency matrix:` each identity field and its value across README,
   manifest, citations, changelog, MultiQC and RO-Crate.
3. `Generated artifacts:` exact RO-Crate generation command/version and diff
   review note.
4. `Verification:` exact validation/lint/link-check commands and results.
5. `External actions:` release/tag/archive URLs and actor, or an explicit note
   that publication remains outstanding and is owned by a named follow-up.

## Dependency graph

```text
01 association diagnostics -----\
                                  +--> 03 screenshots and public results
02 heritability reporting -------/        (also waits for a designated public run)

existing 46 relational validation --> existing 20 release readiness --> 04 release identity
```

Tickets 01-03 are enhancements, not blockers for the present first release
unless the maintainer later changes that scope. Ticket 04 is intentionally at
the release boundary and must not be completed with guessed identifiers.
