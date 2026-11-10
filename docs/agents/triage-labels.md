# Triage Labels

The skills speak in five canonical triage roles. In this repo they are Beads labels with the same strings.

| Role | Label in our tracker | Meaning |
| --- | --- | --- |
| `needs-triage` | `needs-triage` | Maintainer needs to evaluate this issue |
| `needs-info` | `needs-info` | Waiting on reporter for more information |
| `ready-for-agent` | `ready-for-agent` | Fully specified, ready for an AFK agent |
| `ready-for-human` | `ready-for-human` | Requires human implementation |
| `wontfix` | `wontfix` | Will not be actioned |

Beads has no label registry — a label exists once it is applied to an issue — so there is nothing to pre-create.

- Apply: `bd label add <id> needs-triage`
- Replace: `bd label remove <id> <old>` then `bd label add <id> <new>`
- Inspect: `bd label list <id>`, `bd label list-all`

Category roles use the native Beads issue type: `-t bug` is `bug`, `-t feature` is `enhancement`. The labels above are only for state.
