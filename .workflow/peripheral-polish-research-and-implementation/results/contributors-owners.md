# Contributor and CODEOWNERS research

## Recommendation

Add `lyh970817` to the pipeline manifest and README as a contributor. Do not
invent a personal name, affiliation, or ORCID, and do not label the user an
`author` or `maintainer` when the explicit request was to be added as a
contributor.

In `nextflow.config`, append this record to `manifest.contributors`:

```groovy
[
    name: 'lyh970817',
    affiliation: '',
    email: 'lyh970817@yandex.com',
    github: 'lyh970817',
    contribution: ['contributor'],
    orcid: '',
],
```

The existing project uses GitHub handles without a leading `@`, as does MAG;
retain that local convention. Sarek and RNA-seq demonstrate that empty optional
fields may simply be omitted, while this project's current compact records
include all fields. Either shape is accepted by the reference style, but the
explicit full record above minimizes churn within the local list.

In `README.md`, replace the template TODO beneath the existing assistance
sentence with:

```markdown
- [lyh970817](https://github.com/lyh970817)
```

This keeps the original authorship sentence intact and records contribution in
the same location used by the mature reference READMEs for additional
contributors. Do not expose the email address in the README; the manifest is
the appropriate structured metadata location.

## Evidence

- The local coding standard requires `manifest.contributors[]` with GitHub and
  ORCID fields (`docs/coding-standards/configuration-and-schema.md`, manifest
  rule). The current project records the three original authors there.
- Sarek, MAG, and RNA-seq distinguish `author`, `maintainer`, and `contributor`
  in `manifest.contributors`; MAG contains an explicit contributor-only record.
- Their READMEs preserve narrative original authorship and list later code or
  assistance contributors separately under `## Credits`.
- Repository history strongly verifies the requested identity: `git shortlog
  -sne --all` reports 155 commits as `lyh970817 <lyh970817@yandex.com>` plus 7
  under the matching GitHub noreply identity. The configured Git identity is
  also `lyh970817 <lyh970817@yandex.com>`.
- The same identity is the leading human committer for `subworkflows/local`,
  `workflows`, `conf`, `tests`, `docs`, and `nextflow.config`, and is a leading
  contributor to `modules/local`. This is much stronger evidence than merely
  accepting an unverified display name.

## CODEOWNERS decision

Do **not** add a speculative path-specific CODEOWNERS map in this run.

The three references do not establish a universal ownership contract:

- Sarek uses a blanket pair of maintainers, then assigns `*.nf.test*` to the
  nf-core nf-test team and `.github/workflows/` to the nf-core a-team.
- MAG uses only one blanket line with five owners.
- RNA-seq has no CODEOWNERS file.

The local standard marks CODEOWNERS as **SHOULD**, not MUST, and prefers
path-specific rules. Git history proves that `lyh970817` contributes broadly,
but contribution history alone does not authorize assigning review
responsibility to nf-core teams or declaring maintenance responsibility for
the existing named authors. The user explicitly asked to be added as a
contributor, not designated as maintainer.

If the user later confirms that `lyh970817` accepts repository-wide review
responsibility, the smallest truthful initial file is:

```text
* @lyh970817
```

That is less granular than the local SHOULD preference, but it is more honest
than manufacturing domain ownership. Add path-specific owners only when real
maintainers or teams have accepted those responsibilities. In particular, do
not copy Sarek's `@nf-core/nf-test` or `@nf-core/a-team` entries without
confirmation that those teams are intended reviewers for this repository.

## Validation

After integrating the contributor edits:

1. Run `nextflow config -flat` (or the repository's ordinary focused config
   validation) and confirm the manifest parses.
2. Run `nf-core pipelines lint` if available and inspect the manifest/README
   checks; an empty ORCID may be reported as prerelease metadata to finish,
   but no value should be fabricated.
3. Search with `rg -n "lyh970817|TODO nf-core: If applicable" README.md
   nextflow.config` and confirm the manifest and Credits entry agree and the
   replaced Credits TODO is gone.
4. Confirm `git diff --check` is clean.
5. If CODEOWNERS is revisited, validate every referenced GitHub user/team
   exists and has consciously accepted the ownership role before adding it.
