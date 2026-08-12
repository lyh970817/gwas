# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the actual label strings used in this repo's issue tracker, and adds one label of our own.

| Label in mattpocock/skills | Label in our tracker | Meaning                                                |
| -------------------------- | -------------------- | ------------------------------------------------------ |
| `needs-triage`             | `needs-triage`       | Maintainer needs to evaluate this issue                |
| `needs-info`               | `needs-info`         | Waiting on reporter for more information               |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent                |
| `ready-for-human`          | `ready-for-human`    | Requires human implementation                          |
| `wontfix`                  | `wontfix`            | Will not be actioned                                   |
| —                          | `done`               | Work has landed; nothing further is owed by this ticket |

A ticket is `done` when nothing further is owed **by that ticket**. Unticked acceptance criteria do not block it, provided every one of them names its owner:

- **Another ticket** — name the ticket that owns or blocks the criterion.
- **A pre-existing condition this ticket did not create** — name the condition and explain the boundary.

A criterion left bare, owned by nobody, keeps the ticket out of `done`. Record the owner in the criterion itself or in a comment, so the next reader does not have to reconstruct it.

For ordinary implementation tickets, `done` is the completion-evidence boundary rather than a long-lived file
in the active tracker. The canonical close lifecycle is in `issue-tracker.md`.
