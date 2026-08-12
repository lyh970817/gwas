# nf-core guidance sources

Use `AGENTS.md` as the single owner of this checkout's repository identity and component-candidate scope.

Apply guidance in this order:

1. The user's current request.
2. Repository identity and safety constraints in `AGENTS.md`.
3. The applicable `nf-core-*` lifecycle skills.
4. The ignored standards cache under `docs/nf-core-standards/`, only when an active skill leaves a relevant
   question unresolved or extra upstream detail is needed.
5. Current upstream examples and nearby code for style only.

Before using the cache, read `docs/nf-core-standards/index.md` and its fetch date. Refresh it with
`nf-core-standards-refresh` only when its age affects the decision. If cached or live upstream guidance
conflicts with an active skill, surface the conflict and update the owning skill deliberately.

For pipeline conventions, use `CODING_STANDARDS.md` and its routed topic files.

For an upstream-bound module or subworkflow, inspect the companion component-library checkout named in
`AGENTS.md` when the lifecycle skills do not settle a current convention. Compare established, unrelated
components rather than using the candidate's own mirrored implementation as precedent.
