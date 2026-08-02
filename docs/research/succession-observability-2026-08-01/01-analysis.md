# Analysis — three masks, two of them reader problems (2026-08-01)

Companion to `00-inventory.md`. Committed before the proposal, deliberately.

---

## 1 · The measurement the class has never had

`~/.claude/cc-fired/*.json`, restricted to **schema-2 records that reached engagement** (the only
population where `closedAt` is initialised at fire, so its absence means something). Window
2026-07-30 → 2026-08-02 — three days.

| Outcome | n | share |
|---|---|---|
| `closedAt` set — proved it finished and retired through the rails | **134** | 81.7 % |
| open, pane still alive (correct: 157, and this session 170) | 2 | 1.2 % |
| **engaged, then no terminal record at all, pane gone** | **28** | **17.1 %** |

(Unrestricted: 141/301 closed, 158 open-gone — but 129 of those predate schema 2 and never had the
field, so the unrestricted 52 % is an artifact. 17.1 % is the honest figure.)

**~1 in 6 fired peers engages and then goes dark.** Incident B is not exotic; it is the second-most
common outcome, running at roughly nine a day. And the 82 % *success* case is equally unread — no
consumer distinguishes it from the 17 %.

**What the predicate does and does not prove.** `closedAt == null AND pane not alive` proves *no
terminal record was written*. It does **not** prove death: the operator may have closed the pane by
hand, or a reaper took it. That indistinguishability **is** the defect — only one code path
(`self_close`) writes a terminal record, so every other ending is recorded identically to a crash.

---

## 2 · The three masks are two different defects, not one

| Mask | Does the state exist? | Is it read? | Class |
|---|---|---|---|
| **A — armed recycle** | **No.** No record, no handle, no disarm path (`ARMED_SUCCESSION_LIFECYCLE.md` §2) | n/a | **missing state** |
| **B — fired peer** | **Yes.** `closedAt` + `succession` on every schema-2 record | **No.** One grep hit: the writer | **missing reader** |
| **C — ship policy** | **Yes.** `disable-model-invocation: true` in reso's `commands/ship.md` | **No.** Hooks are repo-blind | **missing reader** |

So the unifying thesis in the brief is *nearly* right and worth stating precisely: **two of the
three are reader problems, and only one is a state problem.** That matters for cost — B and C need
no new writer, no new store, and no new ceremony. They need something to look.

**A missing reader is worse than missing state.** Absent state produces acknowledged ignorance.
An unread record produces a *confident false conclusion*: the operator adjudicated Incident B from
proxies and concluded "died producing nothing" about a session that had delivered 400 lines to
`origin/main` and retired cleanly, while the correct answer sat in `cc-fired/158.json` for five
hours.

---

## 3 · Why the fired-peer path went silent: every safeguard is opt-in, and the default omits it

This is the finding that decides the fix. Three mechanisms already exist that would each have
caught Incident B. All three are armed by a flag the default fire does not pass.

### 3.1 The delivery receipt exists and has no producer

`handoff-disposition.sh` parses `DELIVERABLE: <path>` out of `--payload` and reports
`deliverables_missing` — a stay-OPEN reason. Its own comment states the exact Incident-B scenario:

> *"a fired peer that returns a PARTIAL deliverable then dies leaves `fired_peers_alive=[]` → the
> mechanical read would green-light a close over incomplete work."* (a19 §4)

Census of the string `DELIVERABLE` across the entire repo: **4 files** — two bats suites, one
activation snippet, and the consumer itself. It appears in **neither** `handoff-fire.sh`,
`commands/handoff.md`, nor the handoff skill.

Across ~290 stored fired payloads, **3 declare a `DELIVERABLE:`** — about 1 %. Not 157, not 158,
not this session's own fire. **A parser with tests, and no producer.**

### 3.2 The dead-peer path exists — but only if `--notify-back` armed it

`commands/handoff.md` R-PING already covers a peer's death, verbatim:

> *"the ping lands — or the timeout fires: check fired-pane liveness via `cc-sessions`; a DEAD peer
> escalates to R-DECIDE (the user rules on the lost track)"*

Two things follow. First, it is **conditional on `--notify-back`** — R-PING is armed by that flag
and by nothing else, so a one-way fire arms no discharge condition and nothing is ever awaiting
anything. Second, even when it *does* fire, its terminal move is **escalate to the operator** — the
designed happy path for a dead peer is the very operator-fork the brief is trying to delete.

### 3.3 The lint saw it coming and was built not to stop it

`handoff-fire.sh` (grep `payload-lint (advisory)`):

> `⚠ payload-lint (advisory): one-way fire with no back-channel block — a fired session cannot
> announce back. Add --notify-back or a cc-notify recipe if a completion ping is expected.`

and, ~70 lines above (grep `is NOT`):

> *"A pure one-way fire (no such reference) is NOT gated: fire-and-forget is the documented default
> (`commands/handoff.md` §8)."*

The advisory is deliberately non-blocking. That is a defensible call — see §4 — but it means the
documented default configuration is the one with **no receipt, no ping, and no reader.**

---

## 4 · The tension the fix must respect: a ping is an obligation, a receipt is not

The tempting conclusion — "make `--notify-back` the default" — is **wrong**, and the taxonomy says
why. `--notify-back` **arms R-PING**, and R-PING is a *stay-OPEN* reason in
`handoff-disposition.sh`'s exit-1 OR. Defaulting it on would mean every fire converts the **firing**
session into one that mechanically cannot close until the peer pings. A desk firing six peers could
never retire. That is the opposite of autonomy, and it would flood the mailbox besides.

The two things must be separated:

| | Ping (`--notify-back` → R-PING) | Receipt (`closedAt` + outcome) |
|---|---|---|
| Who acts | the **peer**, into a live firer | the **peer**, into its own record |
| Cost to the firer | a stay-open obligation | none |
| Requires firer alive | **yes** | no |
| Timeliness | live | durable, readable later by anyone |
| Right default | **opt-in** (unchanged) | **on** |

Incident B needed the **receipt**, not the ping. And the receipt is not new machinery: the peer
already calls `self-close`, which already writes `closedAt` and `succession`. Adding *what it
delivered* to a write that already happens is the smallest possible change — no new store, no new
ceremony, no stay-open term.

**And for the death case, not even that is needed.** `closedAt == null AND pane gone` is computable
**today**, from state that already exists on every schema-2 record, for all 28 dark peers. Making a
silent death loud requires **a reader and nothing else.**

---

## 5 · Identity discipline the reader must carry (the land-lock lesson, restated)

Pane UUIDs in this fleet are of two kinds — iTerm2 integer ids (`133`, `157`, `170`) and full
UUIDs. Integer ids **recycle** across terminal restarts. So a reader that concludes "pane alive"
from a bare id match can attribute a *new* pane's life to a *dead* peer's record — a false negative
on death, in the same family as the `land-lock.sh` pid-recycling bug that `ps -o lstart=` was added
to defeat, and the same family as the `cc_alive` tty-grep the recycle watcher still uses.

Any liveness reader must therefore match on `(pane, firedAt)` or `(pane, marker)`, never on pane
alone — and must treat an unreadable registry as **unknown**, never as **dead**
(`handoff-disposition.sh` already gets this right: `registry_indeterminate` fails *closed*).

---

## 6 · What this implies for the four asks

1. **Lifecycle model** — for fired peers the states already exist on disk; what is missing is a
   *terminal-state writer for the non-self-close endings* and a reader. For armed recycles the
   record itself is missing (§A, already designed in `ARMED_SUCCESSION_LIFECYCLE.md` §3).
2. **Smallest change** — (a) scope pivot: supersede-on-arm, already proposed. (b) silent death: a
   reader over `cc-fired × cc-sessions`, needing no new state.
3. **Whose decision** — a dead peer whose payload is still on disk at `cc-fired/<pane>.prompt` and
   whose deliverable is missing is a **re-fire**, not a question. The current design escalates it
   to R-DECIDE. That is a fork that can be deleted outright.
4. **`handoff-disposition.sh`** — it already carries the right two axes (`fired_peers_alive`,
   `deliverables_missing`); they are simply never populated by the fire path. The change is on the
   **producer** side, not the consumer side.
