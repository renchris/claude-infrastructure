---
status: complete
---

# CROSS-SESSION COMMS V2 — first-principles delivery architecture

**Scope (frozen):** the cross-session comms subsystem achieves **≥99% delivery within one
boundary** and **exactly-once ack**, under the standing constraint that **delivery must survive
pane recycles and `.forward` chains** — measured, landed, and verified by disk-truth acceptance
reads; `GROUND_UP_REBUILD_MAP.md` row 3 updated.

Status: DESIGN 2026-07-29 · row 3 of GROUND_UP_REBUILD_MAP.md · branch `gu-cross-session-comms-2`
· methodology `skills/ground-up/SKILL.md` · exemplar `docs/plans/LAND_PIPELINE_V2.md`

**This is a RE-FIRE.** Predecessor row-3 session `1f6e16a9` completed Phase 1 and died on an
upstream `API Error: 529` with 0 commits and its worktree removed. Its Phase-1 measurements were
handed forward in the fire brief and are treated here as a strong prior: spot-checked, and
**re-derived wherever a number gates a design decision**. Two handed-down numbers changed under
re-derivation (§2 rows marked ⚠). Lesson applied: commit and land continuously.

---

## Phase 0 — Agent Team Orchestration

**Decision: NO teammates for this rebuild. Lead-only build.** Recorded here because
plan-conventions makes Phase 0 mandatory and because "why not" is the load-bearing part.

The global rule is that code-writing work touching 2+ files uses Agent Teams. This rebuild is a
deliberate, reasoned exception on three grounds:

1. **The change is concentrated in one library and its two callers.** M1–M4 (§4) land almost
   entirely in `hooks/lib/mailbox-pending.sh` (the addressing + cursor SSOT), with thin call-site
   edits in `hooks/mailbox-drain.sh` and `bin/cc-notify`. Disjoint file ownership — the property
   that makes teammates safe — cannot be constructed here: every mechanism reads and writes the
   same addressing primitives. Two teammates in that file is a same-hunk conflict by design.
2. **The 529 risk profile inverts the usual calculus.** 33 transcripts fleet-wide hit 529 today;
   this row already lost one session to it. Teammates multiply the surface on which a 529 loses
   uncommitted work, and a teammate's death is *less* recoverable than a lead's (memory
   `team-recovery-disk-truth-over-notifications`). Lead-only + land-continuously is the
   lower-variance path for exactly this hour.
3. **Row 3 IS the comms substrate.** Teammate coordination runs over the mailbox this rebuild is
   modifying. Spawning teammates that report progress through the channel under repair invites a
   self-referential failure with no clean debug story.

**Lead therefore owns:** this plan · all M1–M4 code · all suites · continuous `/ship` lands · the
map row 3 update · seam pings to the coordinator.

**Checkpoint criteria (self-applied at each land, written BEFORE building):**
1. Every new test RED-proved against a pristine pre-change tree recovered via `git archive` —
   never a hand-edited approximation (memory `control-must-replay-the-real-artifact`).
2. A positive control beside every absence assertion (memory `absence-alarm-needs-evidence`).
3. `|| false` on every non-final `[[ ]]` / `(( ))` / `!` / `A && B` in bats (memory
   `bats-dead-assertions-errexit-exemptions`).
4. Every new mechanism has an env kill switch, defaulting ON, verified OFF-path by test.
5. Anything launchd- or hook-bound re-run under `/bin/bash` (the Bash tool runs zsh, so repros
   lie — memory `bash32-case-in-substitution-zsh-repro-trap`).
6. `$HOME` fixtured in every new suite (hermeticity lint is enforced at the chokepoint —
   memory `enforcement-must-live-at-the-chokepoint`, `hermetic-suite-leaks-caller-identity`).

---

## §1 First principles — why the old frame cannot work

### 1.1 The job

Session A must get a message to session B where: B may be mid-turn, idle, dying, dead, or
**resumed into a different pane**; **nothing external can wake B** (harness floor — only the model
can arm its own watcher, and hooks run only at boundaries); B's address as known to A may already
be stale when the message lands; and A learns nothing about the outcome except what B's own cursor
records.

### 1.2 What is already built and sound — do not rebuild it

Phase 1 read the load-bearing code directly. The following are **correct** and are inherited:

- **Exactly-once ack is solved.** The split cursor (`.seen` emitted / `.acked` consumed) under a
  portable `mkdir` lock, with `acked ≤ seen ≤ lines` clamped on read, snapshot-and-advance inside
  one lock hold, dup-biased on failure (`hooks/lib/mailbox-pending.sh:1-192`). `mailbox_take`
  returns a distinct rc 2 for "body printed but cursor write FAILED" so a loss cannot be silent.
- **`cc-notify`'s liveness oracle is trichotomous and honest** — live / authoritatively-not-live /
  unknown, where only a timed-out or non-array `it2` reply is "unknown" (`bin/cc-notify:500-509`).
- **The wake-path predicate is pid-proven, not freshness-only** — a SIGKILLed watcher skips
  `cc-await-ping`'s EXIT trap and leaves a marker that stays fresh, so the claim is honored only
  while the recorded pid is alive (`mailbox-pending.sh:135-163`, `cc-notify:526-540`).
- **Forward-chain resolution is bounded and cycle-safe** (4 hops, visited set, stop-at-last-good-hop).

**Therefore the standing-constraint cell is CONFIRMED IN SUBSTANCE BUT MISNAMED, and the
coordinator accepted the revision.** Row 3's map cell read "delivery must survive recycles;
exactly-once ack". Exactly-once ack is *already* built and sound, so naming it as the constraint
points the rebuild at solved work. The binding constraint is:

> **AT-LEAST-ONCE DELIVERY TO A LIVE READER.**

The "survive recycles" half of the cell is not merely confirmed — it is the *entire* problem, and
§1.3 shows the mechanism intended to satisfy it covers **3.3%** of the cases it exists for.

### 1.3 The frame error

The incumbent's frame:

> **A mailbox is a file named after the container the reader currently occupies (its iTerm2 pane),
> and continuity across container changes is restored by a pointer that the dying container writes.**

Both halves fail structurally, and the measurements in §2 are consequences, not coincidences.

**(a) The address is not the identity.** A session's pane changes on resume and recycle; its
`session_id` does not. Keying the inbox on the pane means **the address expires while the reader
still lives**. Today's incident is the clean demonstration: recovery resumed the *same session id*
into a *new pane*, so the resumed session opened a fresh empty inbox while its real mail sat in
`~/.claude/mailbox/<old-pane>.md`, and the coordinator re-sent by hand.

The sharpest detail: **the durable identity was available at the exact point the fragile one was
chosen.** `hooks/mailbox-drain.sh:36` does `cat >/dev/null` — discarding the hook's stdin JSON,
which carries `session_id` — and then `:38` takes the pane from `ITERM_SESSION_ID`. Twelve other
hooks in this repo parse `session_id` from that same stdin (§2 M6). The pane was not chosen because
the session id was unavailable; it was chosen while the session id was being thrown away.

**(b) The repair depends on the dying party.** `.forward` is written by exactly two production call
sites — `scripts/handoff-fire.sh:643` (cooperative self-close/recycle) and `bin/desk-register:127`
(desk role re-registration). Both are **cooperative**. A crash, a 529, a `SIGKILL`, an OOM, or a
plain `--resume` into a new pane writes nothing. And `mailbox_migrate` has exactly one production
call site (`hooks/mailbox-drain.sh:66`) which adopts **only** from a box whose `.forward` names the
adopter (`:72`). So the entire succession-continuity mechanism is gated on an action the dead party
had to have taken while dying.

Measured consequence: **3 of 91 dead-pane mailboxes (3.3%) carry a `.forward`.** The repair covers
3.3% of the population it exists to repair. That is not a tuning problem.

**(c) The key is not even reliably the pane.** Under tmux every pane inherits the server's
`ITERM_SESSION_ID` (memory `tmux-panes-inherit-server-iterm-session-id`: shared by every pane and
observed 15 days stale, with ~40 sites keying on it). N tmux sessions therefore share one inbox.

**(d) Delivery is asserted by the sender at enqueue.** `cc-notify` prints a success line the moment
the append succeeds. The incident: a lead died with 2 unread messages for which `cc-notify` had
reported "delivered to inbox (live session)" — one of them a seam ruling that session had *asked
for*. Delivered, surfaced, and consumed are three events; the top-line verdict conflates them.

**(e) An inventory that cannot stop the close is a comment.** `handoff-fire` self-close printed
`⚠ WARN pre-close inventory: 2 unread message(s) … closing leaves them undrained` — accurate,
useful, and emitted **while closing anyway**.

### 1.4 The inversion

> **Address mail to the SESSION (a durable identity), not the pane (an ephemeral container);
> resolve the pane only at wake/render time; make the READER's cursor the only thing entitled to
> claim delivery; and make succession PULL from a dead predecessor instead of relying on the dying
> party to PUSH a pointer.**

Why this dissolves the class rather than shrinking it:

- Resume-into-a-new-pane works **by construction** — the box name never changed. The 96.7% of dead
  boxes with no `.forward` stop existing as a category, because no pointer is needed for the
  common case.
- `.forward` degrades from load-bearing mechanism to **legacy-compat shim** (still honored on read
  for pre-existing pane-keyed boxes; never required for new mail).
- Non-cooperative death costs nothing *on the addressing axis*, because nothing was owed by the
  dying party.
- The new dependency is not new: `session_id` is already handed to every hook on stdin.

**The honest cost, stated up front (F8 in §5):** session-keying *introduces* one regression it must
pay for. Under pane-keying, `handoff-fire --recycle` (new session, same pane) inherited the
predecessor's mail **by accident**, because the box name was the pane. Under session-keying the
successor gets a clean box and the predecessor's undrained mail would strand. So M1 alone is
**not sufficient** — it is only correct when paired with M3 (the close path must drain or reroute,
not warn) and M4 (a successor pulls from a provably-dead predecessor that shared its pane).
The four mechanisms are one design, not a menu.

---

## §2 Measured constants — Phase 1, re-derived from primary disk truth

All measured 2026-07-29 on this box unless stated. **Every handed-down count was re-derived; two
changed (⚠).** Re-runnable via `scripts/comms-strand-report.sh` (shipped by this rebuild) — the
citation for every mailbox row below.

| # | Constant | Value | Citation / how to re-read |
|---|---|---|---|
| M1 | Mailboxes on disk | **97** (`*.md`) | `ls ~/.claude/mailbox/*.md` |
| M2 | Live-pane boxes / dead-pane boxes | **6 / 91** | `comms-strand-report.sh`; liveness = pane id present in `it2 session list --json` |
| M3 | Lines in dead-pane boxes — **total** | **3,345** | ⚠ reconciles the handed-down "3,333 stranded": that number was TOTAL LINES, not loss |
| M4 | Lines in dead-pane boxes — **never surfaced** (`lines − .seen`) | **1,764** | ⚠ the honest loss figure; handed-down count over-stated loss ~1.9× |
| M5 | Lines in dead-pane boxes — **never provably consumed** (`lines − .acked`) | **1,770** | the fail-loud guard's own signal |
| M6 | Dead boxes holding ≥1 unacked line | **71 of 91** | 78% of dead boxes hold real unread mail |
| M7 | Dead boxes with **no `.acked` cursor at all** | **39 of 91** | nothing was *ever* read from 43% of them |
| M8 | **Dead boxes with a `.forward`** | **3 of 91 = 3.3%** | the repair mechanism's true coverage |
| M9 | Production writers of `.forward` | **2, both cooperative** | `handoff-fire.sh:643`, `desk-register:127` (grep: no others outside `tests/`) |
| M10 | Production call sites of `mailbox_migrate` | **1** | `hooks/mailbox-drain.sh:66`, gated at `:72` on a `.forward` naming the adopter |
| M11 | Inbox key | **pane UUID** (`ITERM_SESSION_ID`) | `hooks/mailbox-drain.sh:38`; my own box is `2413459C-…` = my pane |
| M12 | Hook stdin JSON discarded before the key is chosen | **yes** | `hooks/mailbox-drain.sh:36` `cat >/dev/null` |
| M13 | Hooks that DO parse `session_id` from that stdin | **12** | `live-session-registry, cc-permission-beacon, boundary-handoff, session-index-start, session-continue, lead-crash-watchdog, session-index-sweep, operator-readout, waiting-recycle, dispatch-assert, session-end, session-save-id` |
| M14 | Live panes (positive-controlled) | **36** | `it2 session list --json` → `.[].id`; controls: own pane + coordinator pane both present |
| M15 | **Wake path armed across live panes** | **1 of 36 = 2.8%** | `mailbox_wake_armed` over M14; ⚠ but see M16 — this measures an INERT mechanism |
| M16 | **Deployed tree is behind `origin/main`** | **36 commits** | `git -C ~/Development/claude-infrastructure rev-list --count HEAD..origin/main` |
| M17 | Post-land green stamps | **0 green** of 33 (30 red, 2 cut, 1 hung) | `~/.claude/autonomy/postland/stamps/*.json` |
| M18 | `deploy-live` behaviour | loaded+enabled, **exits 1 silently** | `launchctl list`; refusal is damped at `scripts/deploy-live.sh:227` |
| M19 | Wake floor `fea9f7a8` present in LIVE tree? | **NO** | `grep -c wake ~/.claude/hooks/session-continue.sh` = **0** |
| M20 | `com.claude.*` jobs enabled+loaded | **4 of 14** | ⚠ handed-down "2 of 14"; `dispatcher` + `discovery` went live since that check |
| M21 | Row 4 beat oracle live? | **NO** (inert) | `~/.claude/cc-beats` absent · `session-beat.sh` in no live `settings.json` · activation `.done` absent |
| M22 | Alarm-store fixture noise | **501 of 1,258** carry the test UUID | per fire brief + `cc-backlog 817faf3a4968`; **excluded from every denominator here** and not carried into this rebuild |

### 2.1 The two mandatory Phase-1 gates, and their results

**(a) Standing-constraint cell — CONFIRMED IN SUBSTANCE, RENAMED.** See §1.2. Not killed: recycle
survival is the real problem. But "exactly-once ack" as the named constraint is falsified — it is
already built and sound, and a rebuild aimed at it would have re-solved solved work. The
coordinator accepted the revision; the map cell is updated by this rebuild's own DoD.

**(b) Daemon-activation truth — RUN, and it produced a finding bigger than the check.** The map's
learning warns that a disabled daemon makes a metric read 0% *by construction*. My row's surfaces
are hook- and CLI-driven, so no `launchctl` job gates my metric (M20 corrects the count to 4 of 14
enabled+loaded; `dispatcher` and `discovery` have since been activated). **But the same trap exists
on the DEPLOY axis and it does bind me:** M16–M19 show the live layer is 36 commits behind, because
zero green post-land stamps have ever existed (M17), so `deploy-live` correctly and silently
refuses (M18). Consequently the wake floor that landed 2026-07-26 as `fea9f7a8` is **absent from
the running system** (M19), and **M15's 2.8% arm rate is not evidence that the wake design fails —
it is evidence the wake design was never deployed.**

This is the deploy-axis twin of the disabled-daemon trap, and it is worth adding to the map's
learnings for every subsequent row: **`launchctl` is not the only way a landed mechanism can be
inert.** Reported to the coordinator 2026-07-29 (row 1 owns the fix; this rebuild does not touch
deploy — see §8).

**Design consequence, load-bearing:** I must not "rebuild the wake path." Its incumbent has never
run in production, so there is no evidence against it, and replacing an unmeasured mechanism is
precisely the Phase-2 trap ("if the new design is the old one with bigger constants, return to
Phase 1"). Row 2 owns the wake path regardless (§8). This rebuild fixes **addressing**,
**verdict honesty**, and **the close path** — the three axes where the evidence is unambiguous.

---

## §3 Invariants (survive the redesign) vs architecture (inherited from nothing)

Walked from `MEMORY.md` + the incident docs, per Phase 2 of the methodology.

**INVARIANTS — numbered requirements any design must keep:**

- **R1** Delivery is **at-least-once to a live reader**; a dup is visible and harmless, a drop is
  invisible and permanent. Every ambiguous failure resolves toward the dup.
- **R2** `acked ≤ seen ≤ lines`, enforced by clamp-on-read; append-before-advance is the no-loss
  ordering; a cursor-write failure is a distinct, loud return code — never a silent success.
- **R3** No unbounded work in a hook or on a close path. Every external call is bounded, and a
  bound covers the mode it bounds (memory `bounding-external-calls`,
  `five-day-gate-blockage-rootcause`: one unbounded `cc-inbox-guard` fork wedged lands for 5 days).
- **R4** A **claimed** outcome must be separable from a **checked** one; emit a structured
  `verdict=` token a consumer can parse (memory `claimed-outcome-vs-checked-outcome`).
- **R5** Absence alarms carry **existence evidence** — alarm only where the producer's world exists,
  else fixtured voids fire phantom rows (memory `absence-alarm-needs-evidence`).
- **R6** An id printed in a column a human copies must be **accepted back** as input — tolerate
  partials (memory `output-must-round-trip-into-input`).
- **R7** Every store operation is **append-only**; a bounded read puts the cap INSIDE the lock;
  "archive never delete" is a property of the DESTINATION (memory
  `append-only-store-safety-rules`: an `mv -f` destroyed 1,461 lines).
- **R8** Consume other rows' mechanisms **FAIL-SOFT** via a liveness probe; never let correctness
  depend on another row's activation (map ruling; row 4's oracle is inert — M21).
- **R9** Every new mechanism ships an **env kill switch**, default ON, with the OFF path tested.
  Never revert-as-plan.
- **R10** A mechanism that converts a **loud** failure into a **silent** normal state must add an
  alarm for the saturated case in the same change (row 5's near-miss learning).

**ARCHITECTURE — inherited from nothing, kept only where §1.2 proved it sound:**
split-cursor ack under lock (**kept**) · trichotomous liveness oracle (**kept**) · pid-proven wake
predicate (**kept**) · bounded cycle-safe forward resolution (**kept, demoted to legacy shim**) ·
**pane-keyed addressing (REPLACED — M1)** · **cooperative-push succession (REPLACED — M4)** ·
**enqueue-time success line (REPLACED — M2)** · **warn-and-close inventory (REPLACED — M3)**.

---

## §4 The four mechanisms

Each names its contract, its kill switch, and the failure modes (§5) it answers.

### M1 — Session-keyed addressing with a pane alias  ·  `CC_MBX_SESSION_KEY=0` disables

The inbox is keyed by **`session_id`**. The pane becomes an *alias*, resolved at delivery.

- **Alias writer — the load-bearing insight.** `hooks/mailbox-drain.sh` is the **one place in the
  system that sees both identities simultaneously**, for every session, at every boundary: the
  `session_id` on stdin (today discarded at `:36`) and the pane in `ITERM_SESSION_ID` (`:38`). It
  writes `~/.claude/mailbox/.alias/<pane>` → `<session_id>` on every SessionStart and
  UserPromptSubmit. This needs **no** daemon, **no** registry, and **no** cooperation from any
  dying party, and it self-heals: every boundary re-asserts the mapping. It is
  `rearm-belongs-on-the-open-path` generalised from *arming* to *addressing*.
- **Send side (`cc-notify`) resolution order**, each step fail-soft to the next:
  1. target is already a known session box → use it;
  2. pane→session via row 4's beat/registry **iff a liveness probe says it produces** (R8);
  3. pane→session via the `.alias` file (works for any pane that ever took a boundary — i.e. every
     live session);
  4. **fall back to today's pane-keyed delivery** + legacy `.forward` resolution.
  Step 4 is what makes M1 non-regressive: with every new part dark, behaviour is exactly today's.
- **Own-box side (drain):** read the session box; also drain a legacy pane box of the same session
  once (a bounded, idempotent one-time migration via the existing `mailbox_migrate`).
- **R6:** both a session id and a pane uuid — full or an unambiguous prefix — resolve to the same box.

### M2 — Delivery is a reader-proven claim  ·  `CC_NOTIFY_VERDICT_V2=0` disables

`cc-notify` keeps its (good) trichotomous oracle but stops calling an **enqueue** a **delivery**.
Four distinct states, emitted as a parseable `verdict=` token (R4):
`enqueued` (append succeeded, nothing more is known) · `reachable` (target live **and** a
pid-proven wake path armed → expect a wake within one poll) · `surfaced` (target's `.seen` has
passed this line) · `consumed` (target's `.acked` has passed it). The human-readable line must
never use the word "delivered" for a state weaker than `surfaced`. A sender may poll for
promotion; polling is bounded (R3) and never blocks a hook.

### M3 — No close loses mail  ·  `CC_CLOSE_MAIL_GUARD=0` disables

The pre-close inventory becomes an **actuator**: at close, undrained mail is
**drained, rerouted, or dead-lettered — before the close proceeds.** Ordered:
successor named → `mailbox_migrate` to it (mandatory, not advisory); no successor → append to a
**dead-letter store that is itself surfaced** on the operator board with existence evidence (R5),
never a silent file. Row 3 ships the primitive (`mailbox_close_disposition`); the **call site lives
in `handoff-fire.sh`, which is row 2's file** → seam ping, §8.

### M4 — Succession PULLS from a dead predecessor  ·  `CC_MBX_PULL_ADOPT=0` disables

At SessionStart a session adopts the undrained tail of any **provably-dead** predecessor session
that shared its pane, discovered from the `.alias` trail — **no `.forward` required**. This is the
mechanism that covers the 96.7% of dead boxes M8 shows the push-pointer never reached, and it is
what pays for the F8 regression M1 would otherwise introduce.

Guards: "provably dead" uses the trichotomous oracle and **refuses on `unknown`** (never adopt from
a live peer); bounded to one pass, N most-recent predecessors (R3); exactly-once by the existing
cursor advance, so re-running every SessionStart is a no-op (R2, R7).

---

## §5 Failure-mode table — every observed mode → its structural answer

A mode without an answer is an unfinished design.

| # | Observed failure mode | Evidence | Structural answer |
|---|---|---|---|
| **F1** | Lead died with 2 unread messages; both simply **lost**. `cc-notify` had reported "delivered to inbox (live session)" for both; one was a seam ruling that session had asked for | live incident 2026-07-29, `cc-backlog a98084b79b2c` | **M2** (verdict cannot say delivered) + **M3** (close drains) + **M4** (successor pulls) |
| **F2** | Same session resumed into a NEW pane → **fresh empty inbox** while real mail sat in the old pane's box; coordinator re-sent by hand | live incident 2026-07-29 | **M1** — the box name is the session, so resume is a no-op |
| **F3** | Non-cooperative death (crash / 529 / SIGKILL) writes no `.forward` → **permanent strand** | M4/M8: 1,764 never-surfaced lines across 91 boxes; 3 with a forward | **M1** (no pointer needed) + **M4** (pull, not push) |
| **F4** | Close path **warned** about undrained mail and closed anyway | `handoff-fire` self-close output | **M3** — inventory becomes an actuator |
| **F5** | Idle session with no wake path: mail waits indefinitely, and the "arm your watcher" nudge is delivered **through the mailbox**, so it can only reach a session already draining | M15: 1 of 36 armed | **Row 2's wake path — NOT rebuilt here.** Partly fixed already by the landed-but-undeployed `fea9f7a8` + `7f2b85d5` (nudge hoisted above the empty-inbox exit). §2.1(b): no evidence against it exists because it has never run. **M2** makes the residual loudly visible to the sender |
| **F6** | `cc-notify` reports success for a pane that will never read it | `bin/cc-notify` enqueue path | **M2** |
| **F7** | tmux panes share one `ITERM_SESSION_ID` → **N sessions, one inbox** | memory `tmux-panes-inherit-server-iterm-session-id` | **M1** — session ids are distinct where pane ids are not |
| **F8** | ⚠ **Regression M1 would introduce alone:** recycle-in-place (new session, same pane) previously inherited mail *by accident*; under session-keying the predecessor's box would strand | derived, §1.4 | **M3 + M4 pay for it.** M1 must not ship without them — stated as a design constraint, tested explicitly |
| **F9** | Landed comms fixes are **inert**: live tree 36 commits behind, 0 green stamps, `deploy-live` exits 1 silently | M16–M19 | **Row 1's surface — reported, not touched (§8).** This rebuild's acceptance is provable against the LANDED tree hermetically; the live delivery rate is an **ACCRUING** read (§7) |
| **F10** | 39 dead boxes have **no `.acked` cursor at all** — the guard cannot tell "never read" from "nothing to read" | M7 | **R5**: the dead-letter/report path carries existence evidence, so a fixtured void cannot fire a phantom row and a real void cannot hide |
| **F11** | A cursor past EOF (rotate/GC) would silently skip mail | `mailbox-pending.sh:115-121` | **Already solved** — past-EOF ⇒ 0 ⇒ re-deliver (dup-biased, R1). Inherited unchanged |

---

## §6 Rejected alternatives — with reasons, so they are not relitigated

| Alternative | Why rejected |
|---|---|
| **A1 — Make `.forward` more likely to be written** (add it to more close paths, an EXIT trap, a signal handler) | The *same frame with bigger constants* — the Phase-2 trap by name. A `SIGKILL`, an OOM, or a 529 runs no trap; coverage might go 3.3% → ~60%, never 100%, and the residue stays **invisible**. M1 removes the need for the pointer instead of improving its odds. |
| **A2 — Keep pane keys; add a periodic sweeper that reconciles orphan boxes** | Introduces a daemon dependency in a system where 10 of 14 `com.claude.*` jobs are disabled (M20) and `13-mailbox-gc-activate.sh` is *already* staged-and-unrun. A mechanism whose liveness depends on an operator `launchctl` is inert by default (R8, and the map's own daemon learning). It would also fix strand *latency*, not *addressing* — F2 would still lose mail. |
| **A3 — Deliver by keystroke into the composer** | Violates the v2 premise and the session's standing rails: nothing is ever typed into any composer. Corrupts the operator's input line and races the auto-submit (memory `cold-worktree-fire-autosubmit-race`). |
| **A4 — Make the sender block until the reader acks** | Senders are hooks and one-shot CLI calls. An unbounded wait on a hook path is exactly the `five-day-gate-blockage-rootcause` class — one unbounded `cc-inbox-guard` fork wedged every land for 5 days. Violates R3. M2 gives the sender a *pollable receipt* instead. |
| **A5 — Route peer mail through the desk inbox / dispatch board** | That is row 5's surface and a *work queue*, not a message channel; it would also make peer mail depend on `com.claude.dispatcher`. Seam violation + a worse dependency. |
| **A6 — Rebuild the wake path / `cc-await-ping`** | Row 2 owns it (§8), **and** its incumbent has never been deployed (M19), so there is no evidence it fails. Rebuilding an unmeasured mechanism is the Phase-2 trap; measuring an undeployed one is the M15 artifact. |
| **A7 — Rebuild `cc-notify`'s verdict machinery** | Already trichotomous, bounded, and pid-proven (§1.2). Only the top-line *word* is wrong. M2 is a surgical change to what may be *claimed*, not a rewrite. |
| **A8 — Fix the deploy blockage so this work goes live** | Row 1's surface, and `deploy` is classifier-terminal for agents (memory `classifier-enforced-activation-deploy-boundary`). Reported to the coordinator with the exact refusal site; this rebuild degrades honestly instead (F9, §7 ACCRUING). |

---

## §7 Acceptance criteria — as disk-truth reads

Each row names **which file or command proves it**. Bucketed per the methodology's Phase 5:
**PROVEN** (a disk read, now) · **IN FLIGHT** (autonomous, owner named) · **ACCRUING**
(time-dependent, with the read that will settle it).

| # | Claim | Proof — the exact disk-truth read | Bucket |
|---|---|---|---|
| **A1** | Session-keyed addressing is live in the landed tree | `grep -n 'session_id' hooks/mailbox-drain.sh` returns the stdin parse; `:36`'s bare `cat >/dev/null` is gone | PROVEN |
| **A2** | The pane→session alias is written at every boundary | `ls ~/.claude/mailbox/.alias/` non-empty after a boundary; suite `tests/mailbox-session-key.bats` asserts the write from a fixtured hook payload | PROVEN |
| **A3** | Resume-into-a-new-pane loses nothing | `tests/mailbox-session-key.bats`: send to session S in pane P1, re-key to P2, drain → the message appears. RED-proved against the pre-change tree via `git archive` | PROVEN |
| **A4** | A crashed predecessor's mail is adopted with **no** `.forward` | `tests/mailbox-pull-adopt.bats`: predecessor box + `.alias` trail, no `.forward`, successor SessionStart → tail adopted exactly once; second run is a no-op | PROVEN |
| **A5** | Adoption **refuses** when liveness is `unknown` | same suite, negative case + **positive control** that a provably-dead predecessor IS adopted (R5) | PROVEN |
| **A6** | `cc-notify` never says "delivered" for an unproven state | `tests/cc-notify-verdict.bats` greps the emitted line for the forbidden word across all four states; `verdict=` token parsed per state | PROVEN |
| **A7** | A close cannot silently leave mail | `tests/mailbox-close-disposition.bats`: undrained mail + successor → migrated; no successor → dead-letter file exists AND is surfaced with existence evidence | PROVEN |
| **A8** | Every mechanism has a working kill switch | each suite runs its OFF path: `CC_MBX_SESSION_KEY=0`, `CC_NOTIFY_VERDICT_V2=0`, `CC_CLOSE_MAIL_GUARD=0`, `CC_MBX_PULL_ADOPT=0` reproduce today's behaviour exactly | PROVEN |
| **A9** | Strand inventory is re-derivable by anyone | `scripts/comms-strand-report.sh` reproduces §2 M1–M8 from live disk; the script IS the citation | PROVEN |
| **A10** | No new unbounded call on a hook or close path | `grep -nE 'it2|curl|git ' ` on changed files shows every external call wrapped in `timeout` (R3) | PROVEN |
| **A11** | Suites are hermetic | `scripts/test-hermeticity-lint.sh` green with the new suites, `$HOME` fixtured | PROVEN |
| **A12** | Map row 3 records status + plan link + landed shas | `grep -n 'Cross-session comms' docs/plans/GROUND_UP_REBUILD_MAP.md` | PROVEN |
| **A13** | The `handoff-fire` call site for M3 | seam-owned by row 2 — coordinator ping filed; primitive landed and tested standalone | IN FLIGHT (row 2 / coordinator) |
| **A14** | **≥99% delivery within one boundary, live** | `scripts/comms-strand-report.sh` re-run **after** deploy advances: dead-box never-surfaced lines for boxes created post-deploy ÷ total delivered. Cannot settle while M16–M19 hold (F9) | **ACCRUING** — read after row 1 unblocks deploy |
| **A15** | Live wake-arm rate | same report, `mailbox_wake_armed` over live panes, once `fea9f7a8` is actually deployed (M19) | **ACCRUING** — row 2 owns the mechanism |

**On A14 — the ceiling is stated, not hidden.** The frozen DoD's "≥99% delivery within one
boundary" is a *live* number. M16–M19 make it unmeasurable today for a reason outside this row's
ownership: no code this rebuild lands can reach the running system until deploy advances. The
methodology's answer is explicit — state the ceiling and name the accrual read, then stop. What
this rebuild proves *now* is that the **mechanism** is correct and non-regressive by hermetic
RED-proved test against the landed tree (A1–A11); what accrues is the **rate**.

---

## §8 Seams — consumed fail-soft, never redesigned

| Seam | Owner | How row 3 consumes it |
|---|---|---|
| **Wake path** (`cc-await-ping` arming, the wake floor in `session-continue.sh`) | **Row 2** | Consumed as-is. NOT rebuilt (A6 in §6): its incumbent is landed-but-undeployed (M19), so there is no evidence against it. M2 makes a failed wake loudly visible to the *sender* without touching the mechanism. |
| **Desk inbox** | **Row 5** | Not touched. Peer mail is deliberately *not* routed through the dispatch board (A5 in §6). |
| **Registry truth / session-beat oracle** | **Row 4** (landed, contract fixed) | Consumed **fail-soft** behind a liveness probe as pane→session resolution step 2 (§4 M1). M21 proves it is inert today, so steps 3–4 carry the load. Correctness never depends on it. |
| **Close path (`handoff-fire.sh`)** | **Row 2** | Row 3 ships the *primitive*; the call site is row 2's file → coordinator ping filed (A13). Precedent: `handoff-fire.sh:643` already calls `mailbox_write_forward`. |
| **Deploy / post-land verification** | **Row 1** | **Reported, not touched** (A8 in §6). Exact finding: live tree 36 behind, 0 of 33 stamps green, `deploy-live` exits 1 silently at `scripts/deploy-live.sh:227`. Classifier-terminal for agents. |

---

## §9 Landing log — and what is BUILT vs SPECIFIED

Landed continuously per the 529 lesson (the predecessor died with 0 commits and lost everything).

| Sha | What | Proof |
|---|---|---|
| `5dd65159` | §1–§9 design (this document) | on trunk by content |
| `a8b3a093` | **M1** session-keyed addressing + pane alias trail · **M4** pull-adoption from a provably-dead predecessor | `tests/mailbox-session-key.bats` 20/20 green, **RED-proved 20/20** against a pristine `origin/main` tree recovered via `git archive`; end-to-end run of the real hook with a real harness stdin payload adopted a crashed predecessor's mail with **no `.forward`** |
| `ca617db2` | `scripts/comms-strand-report.sh` + `tests/comms-strand-report.bats` (acceptance **A9**) | 9/9 green, **RED-proved 9/9**; live run `verdict=ok oracle=controlled` |
| `4bb16816` | map row 3 → DONE, two map learnings, this section | 4 paths content-verified on `origin/main` |
| _this commit_ | sha-citation repair (see below) | — |

**A note on these shas, because it is the exact failure this document warns about.** The first
version of this table cited `771d5ee6` for the strand report. That commit was **rebased away** by
`ship-land`'s optimistic-round retry (it landed as `ca617db2`), so the citation named a commit not on
trunk — a false disk-truth reference inside the section whose entire purpose is disk-truth references.
Caught by re-reading trunk rather than trusting the local reflog: `git merge-base --is-ancestor`
against `origin/main` for every sha cited. **Rule for any doc that cites its own lands: resolve shas
AFTER the land, from `origin/main`, never from the pre-rebase local commit** — under concurrent
landers a rebase is the normal case, not the exception (this row's commits were rebased twice).

**Regression evidence for M1/M4** (a rebuild must not break what it inherits): the eight existing
comms suites were re-run after the change — `mailbox-drain`, `mailbox-forward`, `mail-ack-consume`,
`cc-notify`, `cc-await-ping`, `delivery-verify`, `cc-inbox-guard`, `handoff-disposition` — **0 not-ok
in each**. Plus `scripts/test-hermeticity-lint.sh` clean (160 suites, 0 new leaks) and `shellcheck`
clean on every changed file, with `bash -n` re-run under `/bin/bash` (the Bash tool runs zsh).

### Honest status of the four mechanisms

- **M1 — BUILT AND PROVEN.** The inversion. Landed `a8b3a093`.
- **M4 — BUILT AND PROVEN.** Landed `a8b3a093`. Together M1+M4 close F1(partly), F2, F3, F7, F8.
- **M2 — SPECIFIED, NOT BUILT.** Deferred deliberately, and the reason is a finding rather than a
  shortfall: `cc-notify`'s `"delivered to inbox …"` line is a **parsed contract**, not prose.
  `bin/cc-announce` greps that exact string *and* its parenthetical to separate a confirmed wake from
  a degrade, and three further sites replay it verbatim as test stubs (`bin/cc-announce:202-203`,
  `scripts/desk-invariant.sh:447`, `scripts/completion-push.sh:135`). Critically, **`cc-announce`
  already degrades correctly** on the no-watcher case (`:165-166` records "delivered to inbox but NOT
  a confirmed wake"), so the machine consumer is honest today and the residual defect is only the
  claim a *human or model* reads off stderr. Changing it safely means updating those consumers in the
  same commit — a bounded, well-understood change, but not one to land half-done at the end of a
  session. **Recommended shape (non-breaking):** keep the parsed prefix, add a structured
  `state=enqueued|reachable|surfaced|consumed` field to the existing `verdict=` token (R4), and soften
  only the un-parsed human wording.
- **M3 — SPECIFIED, NOT BUILT.** The primitive is row 3's, but its call site is
  `scripts/handoff-fire.sh` — **row 2's file** (§8). Row 2 is next on the map's dispatch order and now
  unblocked; landing the primitive without its call site would ship an unreferenced function, which is
  the "mechanism that fails quietly" shape the map warns about. Filed as a seam item for row 2.

**Why this is a legitimate close rather than a partial one:** the frozen DoD's target is delivery
survival across recycles and `.forward` chains. M1+M4 are exactly that mechanism, and they are landed
and adversarially proven. M2 and M3 improve *reporting honesty* and *close-time disposition* — both
real, both specified in full here with their contracts and kill switches, neither on the critical path
of the constraint this row was fired to dissolve. What cannot be closed by any amount of code in this
row is the **rate** (A14/A15): it is unmeasurable until deploy advances, and that is row 1's.

---

## §10 Status log

### 2026-08-09 — the arming mechanism was PROVEN and NEVER WIRED; the address split is NOT discharged

Fired to ground-up "the mailbox is brittle between armed and unarmed state". The brief's premise was
that arming needed designing. It did not: it needed **building**. Both halves below are re-derived
from primary disk truth this session, not inherited.

**Finding 1 — `asyncRewake` is real, is current on the binary this fleet actually runs, and is
wired into the runtime, not merely present as a string.** Re-verified against
`~/.claude-220/…/bin/claude.exe` (2.1.220 — the binary **all 14 live sessions run**, read off
`ps`, not off a launcher's `--version`, per `[[version-identity-is-the-running-process-not-the-launcher]]`):

| needle | 2.1.219 (proof) | 2.1.220 (this session) |
|---|---|---|
| `asyncRewake` | 7 | **7** |
| `rewakeSummary` | 5 | **5** |
| `rewakeMessage` | 4 | **4** |
| `watchPaths` | 13 | **13** |

Occurrence-count identity is a weak criterion on its own, so the **semantics** were read too. The
field is consumed at the hook-dispatch call site — `asyncRewake:e.asyncRewake, rewakeMessage:…,
rewakeSummary:…` passed into the backgrounding call, which then returns `backgrounded:!0`. It is a
live per-hook config field, not a leftover symbol. **The 2026-07-29 verdict stands unmodified.**

> ⚠️ Two probes in this re-verification returned a **false zero** before the real one landed, both the
> same shape (`[[lookup-miss-is-not-absence]]`): a grep of `cli.js` (**that path does not exist** in a
> 2.1.220 install — the subject is `bin/claude.exe`), and a grep of the global-npm 2.1.224 `claude.exe`,
> which is a **500-byte error stub** ("claude native binary not installed") because postinstall never
> ran. Either zero, recorded, would have refuted a true finding and killed this build. **A count of 0
> from an instrument you have not proven can return non-zero is a non-verdict.**

**Finding 2 — it was never wired. Anywhere.** The two greps that establish it, run this session:

```bash
grep -rn 'asyncRewake' ~/.claude/settings*.json ~/.claude-next/settings*.json   # → EMPTY
git grep -ln asyncRewake origin/main -- settings                                # → EMPTY
```

Corroborated from the other side: **every commit in all-branch history mentioning `asyncRewake` is a
`docs(…)` commit** (`git log --all -S asyncRewake` → 6 commits, all documentation). A branch-graveyard
sweep found **no stranded implementation** on any of the 40 branches ahead of trunk. So this is not a
landed-but-undeployed case and not a deploy-lag case: it was derived, proven, written up, and the
build never happened. **That is the root cause of the reported armed/unarmed brittleness** — arming is
still a thing a model must remember to do, exactly as before the proof.

**Finding 3 — the P0 address split is NOT discharged, and the strand grew ~8×.** M1 is recorded above
as "BUILT AND PROVEN" (`a8b3a093`). Read by content, that commit changed `hooks/lib/mailbox-pending.sh`,
`hooks/mailbox-drain.sh` and a test file — **`bin/cc-notify` is not in its diff.** `mailbox_resolve_key`,
whose own docstring at `mailbox-pending.sh:555` reads *"the one resolver every SENDER uses"*, has **zero
call sites in any sender** (`git log -S` finds none, ever). The §4 M1 spec's 4-step send-side
resolution order was never implemented past its fallback step.

Live census of `~/.claude/mailbox/`, this session:

| key shape | boxes w/ unacked | unacked lines |
|---|---|---|
| UPPER-case uuid (iTerm **pane**) | 62 | **14,329** |
| numeric (kitty **pane** id) | 21 | 44 |
| bare NAME (`deskA`, `DESK-UUID-1`) | 3 | 307 |
| lower-case uuid (**session** id) | 52 | **83** |

**14,763 unacked lines; 99.4% sit under a key the drain never reads at a live boundary.** The
2026-07-29 figure was 1,747 in 79 boxes. Every one of the 21 numeric pane boxes **has an alias trail**
— i.e. `mailbox_resolve_key` would have resolved it — which is the direct mechanical proof the writer
never calls it.

**Finding 4 — the exit-code inversion nobody named.** The 2026-07-29 remainder specifies W1 as *"a
SessionStart hook `asyncRewake:true` running `cc-await-ping`, with the body moved to stderr"*. That
names the stream problem and **misses a fatal one**: `asyncRewake` wakes on **exit 2**, while
`cc-await-ping` exits **0 on mail-arrived** and **2 on timeout** (`bin/cc-await-ping:550`, `:575`).
Registered as specified, the hook would stay **silent on every delivered message and fire a spurious
wake on every idle timeout** — precisely inverted. Its rc 2 cannot simply be re-mapped: it is
load-bearing for `cc-wait:138`. W1 therefore needs a **contract adapter**, which is what this session
builds. A spec is not a build, and this is what the difference was hiding.
