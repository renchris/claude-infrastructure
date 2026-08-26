# The third dispatch of `8f59467c92b0`, and why the filed remedy would not have stopped it

**2026-08-26 · written from inside the cloud VM that received the dispatch.**
Sixth entry in the `venue-*` family; direct successor to
`venue-foreign-master-redispatch-2026-08-17.md`, which measured the *second* dispatch of this same
row and predicted this one.

**Finding, in one line:** the master row `8f59467c92b0` was cloud-dispatched a **third** time, nine
days after its own disproof was landed into the plan it points at — and the ~0-cost remedy that
disproof proposed (*"set `projectName` in the plan index to a foreign project"*) **cannot hold its
value**, because `hooks/plan-index-update.sh` recomputes that field from the plan's path and
overwrites it, in both of its modes.

---

## 1 · What arrived, and what the VM holds

Dispatched to drive `8f59467c92b0` — *"advance MASTER: product repos"*, project
`claude-infrastructure`, DoD ref `docs/plans/MASTER_PRODUCT_REPOS.md`. Every open wave in that plan
(R1, R2, R3 edit `reso-management-app`; R4 edits `doc_classifier`) targets a tree this VM does not
have:

```
$ ls ~/Development                 → No such file or directory
$ ls /home/user                    → claude-infrastructure          (one checkout)
GitHub MCP scope                   → renchris/claude-infrastructure (one repo)
$ find / -name backlog.jsonl       → (nothing, before this session ran)
```

`git rev-list --count HEAD..origin/main` = **0**, so the tree is trunk and every read below is a
read of trunk, not of a stale clone. The plan is unchanged and **not refuted**: R1–R4 are open,
correct as filed, and unstarted. What is refuted, for the third time, is that this venue can work
them.

**Dispatch census for this one row:** 2026-08-15, 2026-08-17, 2026-08-26. The 08-17 entry's
first finding — *"a disproof in plan prose does not park an item — nothing in the dispatch chain
reads it, so the 08-15 entry bought two days"* — is now confirmed at a longer horizon: the 08-17
entry bought **nine** days, and bought them the same way, by chance rather than by mechanism.

---

## 2 · The filed remedy is not durable — measured, not argued

`MASTER_PRODUCT_REPOS.md`'s 08-17 status entry corrected the 08-15 cost estimate like this:

> *"a `projectName` entry in the plan index"* is **not a build** — `scripts/find-plan.sh:73` already
> reads `.plans[$k].projectName` and prefers it over the path basename, so it is a ~0-cost data
> entry, and setting it to a foreign project composes with fail-closed to park THIS row
> specifically.

The read side of that is exactly right. `scripts/find-plan.sh:70-81` does prefer the index value:

```sh
project_name_for() {
  local p="$1" pn=""
  if [[ -f "$CC_PLAN_INDEX_PATH" ]]; then
    pn=$(jq -r --arg k "$p" '.plans[$k].projectName // empty' "$CC_PLAN_INDEX_PATH" 2>/dev/null)
  fi
  if [[ -z "$pn" ]]; then
    case "$p" in
      */docs/plans/*)    pn=$(basename "${p%/docs/plans/*}") ;;
      ...
```

**The write side destroys it.** `hooks/plan-index-update.sh` owns that field and derives it purely
from the path — `classify_path()` sets `PN="$(basename "$PROJ")"` where `PROJ` is the path prefix —
and then writes it back **unconditionally**, in both modes:

- **Hook mode** (PostToolUse `Write|Edit`, matching `*/docs/plans/*.md` — i.e. this very plan), at
  `hooks/plan-index-update.sh:148-154`:
  ```
  | .project     = $project
  | .projectName = $projectName
  ```
  Plain `=`, not `//=`. So the first edit anyone makes to `MASTER_PRODUCT_REPOS.md` after the
  operator hand-sets the field resets it — **including the edit that records the remedy in the
  status log.**

- **`reconcile` mode**, at `hooks/plan-index-update.sh:96-110`, builds a *fresh* object per plan
  from the path-derived TSV and preserves exactly one prior field:
  ```
  { project: $e[1], projectName: $e[2], path: …, basename: …, namespace: $e[3],
    firstIndexed: (… $prev.firstIndexed …), lastSeen: $now }
  ```
  `firstIndexed` survives; `projectName` does not. And `reconcile` is wired at **SessionStart**
  (`docs/activation/ledger-activate-snippet.md:22`), so the hand-set value is wiped at the start of
  the next session even if nobody ever edits the plan.

The contrast is inside the same subsystem and looks deliberate elsewhere:
`hooks/migrate-plans-index.sh:48` uses `//=` for the same two fields, and therefore *would* preserve
an operator-set value. The indexer does not.

**Consequence for the open decision.** `cloud-venue-project-repo-mismatch-2026-08-16.md` §3 offers
(a) fail-closed and (b) route-correctly, and the plan's 08-17 entry proposed the index entry as a
cheap way to park this specific row while that decision is settled. That park **does not exist as a
data entry.** Making it durable is a code change to `plan-index-update.sh` — minimally `=` → `//=`
for `projectName` in both modes, or a separate never-clobbered override field — which is a change to
the dispatch chain's behaviour, i.e. the same decision, not a way around it.

---

## 3 · One correction to the 08-17 entry: the write rails fail LOUDLY

The 08-17 status entry closes with:

> **Disposition: `cc-backlog block`, not `reopen`** — blocked on where it was sent; the rails fail at
> rc 0 from a VM, so verify the block took rather than assuming it.

The advice to verify is sound. The stated reason is **wrong for the write verbs**, and the
distinction matters to whoever tries this next. Measured this session, on this VM:

| Verb | stdout | real exit code |
|---|---|---|
| `cc-backlog block 8f59467c92b0 --needs …` | `cc-backlog: unknown id 8f59467c92b0` | **3** |
| `cc-backlog done 8f59467c92b0 --evidence …` | *(same shape)* | **3** |
| `cc-backlog list --all` | *(empty)* | **0** |

So a cloud session **cannot** silently mis-report a park or a close: both write verbs fail with a
clear message and a non-zero status, and a caller checking `$?` gets the truth. The rc-0 direction is
the **read** verb — an absent store reads as an *empty ledger*, which is indistinguishable from "no
work here" — and `list` **creates** a 0-byte `~/.claude/autonomy/backlog.jsonl` as a side effect, so
the second reader on the same box finds a store that exists and is empty.

⚠️ **Methodological note, because it nearly became the finding.** The first measurement here read
`rc=0` for `block` and appeared to confirm the 08-17 claim spectacularly. It was an artifact:
the command was piped to `head`, so `$?` was `head`'s status. `bin/cc-backlog block … | head` reports
success for a failed park. Any wrapper in this fleet that pipes a rail through `head`, `tee` or
`grep` without `PIPESTATUS`/`set -o pipefail` has the silent-park bug that 08-17 attributed to the
rail itself.

---

## 4 · Why no code cure was attempted from here

Two independent rails close it, and both are the repo's own:

1. **`bin/cc-venue:55`** — *"🚨 THE GUARD, KEYED ON THE DANGEROUS EFFECT. A cloud VM must never build
   or run the venue rule: it would be deciding its own admission, and its 50-commit clone cannot read
   the history that justifies"* it. `bin/cc-eligible:82` restates it. The only fix that would park
   this row at dispatch is a venue-rule change, so it is out of bounds from this venue by
   construction.
2. **The gate cannot run.** `bats` and `shellcheck` are both **absent** on this VM (`jq` is present).
   `cloud-venue-project-repo-mismatch-2026-08-16.md` §3 already refused to land an ungated guard into
   the fire path on exactly this ground — *"a wrong refusal starves the cloud tap"*, trading a bounded
   waste for an unbounded one. That reasoning is unchanged.

The `plan-index-update.sh` one-word change in §2 is likewise a dispatch-behaviour change that cannot
be gated here, and it is properly part of the open decision rather than a unilateral edit by a
one-item worker.

---

## 5 · Disposition

The item is **blocked on an operator-side action**, and this VM cannot record that: `cc-backlog
block` exits 3 against a store that does not exist here (§3). This document plus the
`MASTER_PRODUCT_REPOS.md` status-log entry are the only durable record reachable from this venue.

**The park must be applied on the operator's box.** Nothing in R1–R4 should be re-derived: they are
open, correct, and unstarted.
