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

## 5 · The land rail is unusable from this venue too — so even the disproof cannot reach trunk

Attempting to land this document via the project-local `/ship` returns **exit 6 (GATE RED)**, and the
red is not in the diff:

```
✗ gate: unattended-path-lint --selftest FAILED — the detector no longer discriminates, so
  its clean verdict would mean nothing. Fix the lint before landing.
✗ ship-land: GATE RED — not pushing.
```

**Attribution, proved rather than argued.** The same selftest was run on a pristine `origin/main`
worktree with this session's commit entirely absent, and failed **identically — 11 of 42**. The red
is a property of trunk *in this environment*, not of this diff. Independently: `scripts/ship-land.sh`
builds the arm's own-set from `lint_own_scope`, which reports `scripts/* bin/* hooks/* hooks/*.sh
tests/*.bats`, and this land changes exactly two files — `docs/plans/MASTER_PRODUCT_REPOS.md` and
this document. **The intersection is empty.** The arm has nothing to judge here and blocks anyway,
because the selftest gate at `scripts/ship-land.sh:3138-3143` fires unconditionally, *before*
own-scope is consulted.

**Why the detector is inert here, and why the gate is nonetheless right.** `unattended-path-lint.sh`
reads launchd plists through `/usr/libexec/PlistBuddy` (`:992`, `:1003`) and its own header calls that
binary "stock" (`:119`) — true on macOS, and this VM is **Linux**:

```
$ uname -s                        → Linux
$ ls /usr/libexec/PlistBuddy      → No such file or directory
$ command -v plutil shellcheck    → (both absent; jq, rg, perl, python3 present)
$ grep -n 'Darwin\|uname' scripts/unattended-path-lint.sh   → (no match)
```

There is **no platform guard anywhere in the lint**, so on Linux its detectors return "found nothing"
for environmental reasons, and 11 selftest assertions fail as `want 1, got 0`. The gate arm's refusal
is then exactly correct by its own stated logic — *"the detector no longer discriminates, so its
clean verdict would mean nothing"* — a genuinely inert instrument must never be read as green. The
arm is not the defect; the defect is that a **macOS-only instrument sits on the mandatory land path
of a repo that is dispatched to Linux VMs.**

**Consequence, and it generalises past this item:** a cloud worker in this venue cannot land *any*
diff, including a docs-only one that touches nothing the arm judges. So the venue defect is one layer
worse than "the assigned work is unreachable" — the **disproof of that unreachability is also
unlandable from the venue that produces it**, which is why entries in this family keep needing a
later on-box session to carry them onto trunk.

**No bypass was taken.** `SHIP_LAND_UNATTENDED_LINT` would skip the arm (the `[[ -x … ]]` test fails
on a bad path), and pointing it at `/nonexistent` would have landed this commit. That is disabling a
safeguard to get green, which this repo forbids outright, and it would be a *worse* act from a cloud
VM than the venue-rule edit §4 already declines: the same reasoning that says a VM must not decide its
own admission says it must not weaken the gate that admits its own commit. Fixing the lint properly —
a Darwin guard, or a `skip`-with-nonverdict when `PlistBuddy` is absent — is a change to the land
gate, cannot be tested here (`bats` absent), and belongs to an on-box session.

⚠️ **Not dated.** This clone is **shallow** (`.git/shallow` present, 52 commits), so when this arm
entered the gate is not answerable from here, and no claim is made that it is new. Earlier entries in
this family record cloud sessions that *did* reach trunk (`venue-dod-offtrunk-2026-08-24.md` §6), so
the arm may postdate them or the environments may differ — an on-box session can date it with
`git log -S unattended-path-lint -- scripts/ship-land.sh`.

---

## 6 · Disposition

The item is **blocked on an operator-side action**, and this VM cannot record that: `cc-backlog
block` exits 3 against a store that does not exist here (§3). This document plus the
`MASTER_PRODUCT_REPOS.md` status-log entry are the only durable record reachable from this venue —
and per §5 they are reachable only on the session branch, **not on trunk**.

**Three things an on-box session should do, in this order:**

1. `cc-backlog block 8f59467c92b0 --needs "route this cross-repo master away from a
   claude-infrastructure-scoped venue; R1-R4 edit reso-management-app and doc_classifier"` — the park
   this venue cannot apply. **Block, not reopen:** reopening re-cycles the row, which is what
   produced dispatches two and three.
2. Land this branch's commits, which carry §1-§5. They are gate-blocked here for the reason in §5,
   not for anything in their content.
3. Decide the lint's platform guard (§5) and the `plan-index-update.sh` overwrite (§2). Both are land-gate
   / dispatch-chain changes that a one-item cloud worker should not make unilaterally.

**The park must be applied on the operator's box.** Nothing in R1–R4 should be re-derived: they are
open, correct, and unstarted.
