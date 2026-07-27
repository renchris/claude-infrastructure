# Wake-on-ping — making the cross-session wake path MECHANICAL, and what to absorb from AgentMail

**Date:** 2026-07-26 · **Scope (frozen):** exhaustively+recursively investigate
`github.com/agentmail-to` and absorb its transferable mechanisms into our 2-way session comms; AND
drive our 2-way comms to 100th percentile so an agent is **woken on ping** — mail must never land
unread in an idle Claude Code session that then stays idle forever.
**Parent SSOT:** `docs/research/cross-session-mail-2026-07-20.md` (v2 substrate + v3 design D1–D13) ·
**Plan:** `docs/plans/TWO_WAY_SESSION_COMMS_PLAN.md § v3`.

## Verdict

The wake mechanism is **sound and proven**. The defect is that **nothing actuates it**.

Live end-to-end probe, this session, on CC 2.1.219 + `claude-opus-5` (§2): an armed
`cc-await-ping` detected a `cc-notify` write within one 5 s poll, exited 0, and the harness's
**task-completion notification re-invoked the model**. Transport, cursor, verdict and wake all
worked on the first attempt. Yet at the same moment the fleet held **0 armed watchers across 74
mailboxes and 1,300 unacked lines**.

That is the whole problem in one sentence: *arming is prose, not mechanism.* Every call site of
`cc-await-ping` in the repo is either a document telling the model to arm it, or a lint that
detects it — never a mechanism that makes it happen. A capability that depends on an agent
choosing to invoke it, every time, before every idle, is inert by construction
([[feature-durability-mechanism-not-memory]]).

Two further facts turn "add a nudge" into "add an actuator":

1. **The wake is self-disarming.** `cc-await-ping` deletes its own `.watching` heartbeat in its
   EXIT trap (correctly — a stale heartbeat would make `cc-notify` promise a wake that cannot
   happen). So the instant a session is woken it is deaf again. One-shot arming is insufficient
   *by construction*; arming must recur at **every** idle boundary.
2. **The contracted-wait primitive does not fit the standing-listener shape.** `cc-wait` is
   fail-closed on `{waitee, signal, deadline, on-timeout}` (`bin/cc-wait:19-28`) — correct for "I
   am blocking on peer X's reply", wrong for "wake me if *anyone* writes to me, ever". There is no
   waitee and no meaningful deadline. Meanwhile `scripts/wait-contract-lint.sh:63-75` lints a raw
   `cc-await-ping` **RED** as an "uncontracted wait". So the only sanctioned wait shape excludes
   the standing wake, and the standing wake is linted as a defect. **The lint is a contributing
   cause of the 0-watcher state.**

## 1 · Live loss, measured (2026-07-26 22:0x PT)

Six days after v3-P1 landed role addressing (`e542db4`). Counted directly off `~/.claude/mailbox`:

| Metric | Value |
|---|---|
| UUID-named boxes | **74** |
| Total lines ever delivered | **2,855** |
| **Unacked (never consumed)** | **1,300 — 46%** |
| Armed watchers (`.watching`) | **0** |
| D4 arm stamps (`.armed`) | **0** (D4 is unlanded — see §3) |
| Orphan `.acked` cursors with no `.md` | **120** |
| Non-UUID junk files in the live store | **3** — `DESK-UUID-1.md`, `deskA.md`, `deskC.md` |

The 78% → 46% improvement is real and is P1's role-addressing working. The residue is the
*receivable* half, untouched:

- `D08B4FC0` (a former desk) — **691 pending**, last write 43.9 h ago. Dead box, nothing will ever
  read it.
- `D5D419C8` — 294 lines, **`acked=0`**. An inbox that was **never drained once** in its whole life.
- `3D6CE48E` — 157 pending, 31.4 h old.

**The three junk files are test fixtures leaking into the live store.** `deskA.md` / `deskC.md` /
`DESK-UUID-1.md` are fixture names, written into the real `~/.claude/mailbox`. This is exactly the
hermeticity class `scripts/comms-hermetic-lint.sh` was built to catch — and that lint is unlanded
(§3). Live-store contamination also means every "unacked" count above is *slightly* pessimistic and
every fixture run pages real recipients.

## 2 · The wake path WORKS — live proof, not docs

Method: RED-proof by effect, not by reading ([[effect-read-predicate-red-proof]]).

```
1. arm      cc-await-ping <own-uuid> --timeout 240 --interval 5   (Bash run_in_background)
2. observe  ~/.claude/mailbox/<own-uuid>.watching  ->  "pid=48751"       ← heartbeat live
            fleet-wide .watching count 0 -> 1                            ← I was the ONLY armed session
3. ping     cc-notify <own-uuid> "WAKE-PROBE: …"
            -> verdict=delivered enqueued=1 reason=wake-path-armed       ← sender saw the armed path
4. effect   watcher printed the line and exited 0 within one 5 s poll
            harness emitted <task-notification> status=completed         ← THE WAKE: model re-invoked
5. teardown .watching removed by the EXIT trap; fleet count back to 0    ← self-disarming (see Verdict)
```

Every link in the chain is confirmed on the running binary. This retires any remaining doubt about
the substrate: **we are not missing a transport, we are missing an actuator.**

It also confirms the harness floor stands unchanged — the wake worked *because* a pre-armed
in-session background task existed. No external process reached into the session.

## 3 · What is built but NOT landed — and one thing that is actively broken

`wt-02ba4e52389a` holds **8 commits / 2,420 insertions** of mail-v3 P2–P4, built 2026-07-25, never
landed (LAND-BLOCKED on fleet test contention, not on a red gate — [[gate-never-ran-vs-gate-red]]):
D5 mid-turn PostToolUse drain · D9 `cc-thread` · D10 statusline 📬 badge · D12 board comms store ·
D6 `cc-mailbox-gc` lifecycle · D13 `comms-hermetic-lint` · D4 arm-stamp + `cc-wait` certification.

It is now **141 commits behind main with 6 real conflicts** (`git merge-tree --write-tree`):
`bin/cc-blockers` · `docs/activation/pending-activation/12-mailbox-posttool-activate.sh` (add/add) ·
`docs/plans/TWO_WAY_SESSION_COMMS_PLAN.md` · `hooks/mailbox-drain.sh` · `tests/cc-await-ping.bats` ·
`tests/cc-notify.bats`. The conflicts exist because a **parallel stream** landed an overlapping
operator-visibility fix on main today (`bin/cc-mail` + the `systemMessage` digest now at
`hooks/mailbox-drain.sh:117-146`). Reconcile by **composition**, never by supersession
([[parallel-stream-convergence-protocol]]).

### 3a · An activation on main that can never succeed

`main` ships `docs/activation/pending-activation/12-mailbox-posttool-activate.sh` — and it is **in
the operator's live activation queue right now**, nagging as "staged >24 h and NOT run". It wires
`hooks/mailbox-drain.sh post-tool` into every account's `PostToolUse`.

But on `main`:
- `hooks/mailbox-drain.sh:41-45` accepts only `session-start` and `prompt`; `post-tool` falls to
  `*) exit 0`.
- `settings-templates/settings.example.json` contains **no** PostToolUse drain entry.

So the script hits its own fail-closed guard — `✗ no 'mailbox-drain.sh post-tool' entry under
.hooks.PostToolUse in $TEMPLATE — nothing to copy. STOP.` — and **can never succeed**. The
activation half of D5 landed without its implementation half, which sits only on the parked branch.

It fails *closed*, so nothing silently no-ops — the guard did its job. But the operator has been
nagged for over a day about a step that is unrunnable by construction. This is the
activation-queue analogue of an inert mechanism: the queue asserts work is pending when the work is
in fact *blocked on an unlanded branch*. Landing that branch is the fix; it is also why one of the
five queue items will not clear.

## 4 · The design — a wake LADDER, not a nudge

The harness floor is immovable: **only the model can arm its own watcher.** Therefore the only
levers that can force arming are the two channels that reach the model — `additionalContext`
(ignorable prose) and Stop `decision:block` (a forced turn). A 100th-percentile floor cannot rest on
the ignorable one.

The SSOT forbids a *competing* Stop blocker (`hooks/mailbox-drain.sh:8-10`, critique fix B): mail
delivery folds into `hooks/session-continue.sh`, the ONE hook already blocking at Stop. The wake
actuator must therefore fold into that same hook — not add a second blocker.

| Rung | Mechanism | Guarantees | Fails loud by |
|---|---|---|---|
| **R1 — arm before idle** (new) | fold into `session-continue.sh` at its "no sentinel → allow the stop" branch (`:112`): if the session is a real inbox-bearing pane AND no fresh `.watching`, `decision:block` once with the exact arm command | a session cannot reach idle without a wake path | after its bounded attempts, a `systemMessage` naming the lever, then ALLOW the stop — never a loop (precedent `session-continue.sh:33`) |
| **R2 — re-arm after every wake** | the wake is self-disarming, so the drain's existing D4 nudge (`mailbox-drain.sh:112-113`) must fire on the boundary a woken session actually hits — its next tool call ⇒ **D5 PostToolUse drain** | a woken session re-arms instead of going deaf | the nudge is counted; an unarmed session with pending mail is a guard alarm |
| **R3 — backstop** | `cc-inbox-guard` already escalates live-but-unwatched overdue mail; route it to the desk role (D3) + the board comms store (D12) + the statusline 📬 badge (D10) | a session that will not arm still gets its mail triaged by a human or the desk | board + badge + phone leg |

R1 is the new invention. R2 and R3 are **already built on the parked branch** — which is why
landing it is not optional bookkeeping but a load-bearing part of this design.

### Damping (R1 must not become noise)

A Stop with no sentinel is the *common* case, so an unconditional block would fire on every turn of
every session. R1 blocks only when: the pane has an inbox identity · no fresh `.watching` · AND
(first idle of this session OR pending mail > 0) · under a per-session attempt cap · not already
attempted within a TTL. Exhausting the cap degrades to the human-visible `systemMessage`, never to
a loop — a repeating Stop hook is not evidence that more work exists
([[classifier-ceiling-is-a-terminal-state]]).

## 5 · What to absorb from AgentMail

*(filled in from the recursive org investigation — see § Absorb list)*

## Status log

- **2026-07-26** — This session. Live wake-path probe PASSED end-to-end (§2). Live loss re-measured
  at 46% / 1,300 lines / 0 watchers (§1). Found the unrunnable `12-mailbox-posttool` activation on
  main (§3a) and the `cc-wait` vs standing-listener shape gap (Verdict). Wake-ladder design frozen
  (§4). Work branch `feat/wake-on-ping`.
