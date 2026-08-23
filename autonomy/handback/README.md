# autonomy/handback — ledger verdicts in transit

Each `*.json` here is **one verdict a worker owed the backlog ledger and could not write**, waiting
for the box that owns the ledger to fold it in.

The ledger is `~/.claude/autonomy/backlog.jsonl`, and it exists on the operator's box and nowhere
else. A cloud Claude Code VM has no `~/.claude`, so `cc-backlog done|block` returns `unknown id`
there and `cc-notify` is `unresolvable`. Without a transport, a cloud worker that FINISHES a row
cannot record that it finished — so the row stays open, the next wave dispatches it again, and the
slot is spent re-deriving an answer that already landed. Measured on `354c73ebd400`: three
dispatches, one cure, landed on the first.

Git is the only channel the two venues share, so the verdict rides in the repo and arrives by the
same land that brings the diff home.

| | |
|---|---|
| **Written by** | `scripts/backlog-handback.sh record <id> --verb done --evidence "<sha>"` (or `--verb block --needs "<step>"`) — run at the off-box venue, committed with the work |
| **Read by** | `scripts/backlog-handback.sh list` / `render` — read-only, safe anywhere |
| **Spent by** | `CONFIRM=1 scripts/backlog-handback.sh apply` — on the box, and only there |
| **Surfaced by** | `scripts/cloud-reconcile.sh` (`--list` / `--land` / `--all`), report-only: a cloud branch can only reach trunk through it, so a landed record cannot go unseen |

Records are **evidence and are never deleted**. An applied one stops being reported because the
ledger fold agrees with it, which is a stronger statement than its absence: the file is the receipt
that the venue asserted the verdict, and the ledger is the proof the box accepted it.

The ceiling on what a record may do — no row creation, two verbs only, no `eval`, `apply`
default-off — is enforced in `scripts/backlog-handback.sh` and argued in its header.
