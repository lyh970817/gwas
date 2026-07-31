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

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table.

Edit the right-hand column to match whatever vocabulary you actually use.

`done` is ours, with no canonical role behind it, because the five roles all answer _who picks this up next_ and a finished ticket has no next. Without it, landed work has to borrow `ready-for-human`, which then means both "your turn to review" and "a human must build this" — and the `Status:` line stops answering whether the ticket is finished.

A ticket is `done` when nothing further is owed **by that ticket**. Unticked acceptance criteria do not block it, provided every one of them names its owner:

- **Another ticket** — either that ticket will close the criterion, or the criterion cannot be met until it lands. Name it. Issue 07 is `done` with two criteria that cannot pass until issue 29 publishes the fixtures upstream; issue 10 is `done` with two that issue 11, 12 or 15 closes by wiring a second association route.
- **A pre-existing condition this ticket did not create** — say what it is. Issue 06 is `done` with a lint criterion the base tree already failed before that work started.

A criterion left bare, owned by nobody, keeps the ticket out of `done`. Record the owner in the criterion itself or in a comment, so the next reader does not have to reconstruct it.

For ordinary implementation tickets, `done` is the completion-evidence commit
boundary rather than a long-lived file in the active tracker. After the updated
ticket has been committed, delete it in a separate closing commit as specified
in `issue-tracker.md`.
