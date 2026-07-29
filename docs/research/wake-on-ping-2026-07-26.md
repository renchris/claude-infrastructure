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

**Method:** the 32-repo org read recursively — docs (real-time + data model), `agentmail-mcp`,
`agentmail-skills` + `openclaw-plugin`, the Python/TS/Go SDKs, `agentmail-examples`, `openclaw`
itself, and the CLI/schemas/convex/langchain surfaces — each surface deep-read, then passed through
a second stage that kept only what maps onto a file/hook world with no server.

### 5.0 The shape of their answer

AgentMail has exactly **one** true wake primitive: a WebSocket channel at `wss://ws.agentmail.to/v0`
with a `subscribe` frame (`{type:"subscribe", event_types:[…], inbox_ids:[…]}`), server events
carrying `type:"event"` + `event_type` (10 types: `message.received`, `.sent`, `.delivered`,
`.bounced`, …). Everything else is HTTP webhooks or hand-rolled polling. Notably:

- **Their MCP server — the Claude Code integration — has NO wake primitive at all.** No blocking
  "wait for next message" tool, no way to surface a message to a running agent. Whatever we build
  here, we cannot buy it from them.
- **Their Go SDK and CLI have no streaming at all** — no `watch`/`tail`/`listen`.
- **Their WebSocket has no cursor, no sequence number, no backfill and no dedupe.** A dropped
  connection loses its whole window. Our `.seen`/`.acked` split cursor under a lock, `.forward`
  chains, and SessionStart `mailbox_migrate` adoption are **strictly ahead** — we cannot lose a
  line; they can lose a reconnect window.

So the transferable value is narrow and concentrated in one place — **the arm/re-arm lifecycle** —
plus one architectural idea from `openclaw` that is genuinely bigger than anything we have.

### 5.1 Ranked absorb list

| # | Take | Closes | Effort | wake_impact | Status |
|---|---|---|---|---|---|
| A1 | **Subscribe on OPEN, not on message.** Their SDK docs mandate `on("open") → sendSubscribe` precisely because subscribing once after the first connect silently stops delivering after any reconnect. Our re-arm nudge lived on the "message arrived" path — below `[ -n "$body" ] \|\| exit 0` — so a session with an empty inbox was never told to arm. | R-1 | S | **HIGH** | **DONE** `cca3b3c9` |
| A2 | **A supervised re-arm loop, made mechanical.** Their Python client does *not* auto-reconnect; the skill mandates a `while True:` + backoff + **re-subscribe** loop. We cannot run a loop across idle, so the equivalent is an actuator at the idle boundary. | R-1 | M | **HIGH** | **DONE** (wake floor, `57cc374a`) |
| A3 | **A host-driven turn.** `openclaw`'s `channelRuntime.inbound.run` with `admission:"exclusive"` and `activation:{onStartup:true}`: an inbound message *creates* an agent turn, and the **host** starts the ingress worker — the agent never has to be looping. This is the one idea strictly bigger than ours: it converts "landed" into "read" for a session that is already idle and unarmed. | R-1, R-2 | **L** | **HIGH** | **SPECIFIED, NOT BUILT** — §5.2 |
| A4 | **Redeliver, don't just page.** `openclaw` runs a REST catch-up (60 s overlap / 900 s deep sweep) *concurrently with* the live socket, on the principle that the durable sweep is not a fallback. Our `cc-inbox-guard` has exactly the right shape and the wrong terminal action: it classifies overdue boxes and escalates to the phone. **Our sweeper pages the human about a session it is standing right next to.** | R-1, S-2 | M | MED-HIGH | backlog |
| A5 | **Class filtering at subscribe time** (`Subscribe{event_types:[…]}`). `cc-await-ping` wakes on *any* line, so a routine reaper page burns a wake the same as a blocking decision request. A `--class urgent` filter makes a standing watcher affordable. | S-3 | S | MED | backlog |
| A6 | **`minUptime` before declaring health.** Their reconnecting socket refuses to reset its backoff until a connection has survived 5 s, so a flapping endpoint cannot masquerade as healthy. Nothing of ours records whether an armed watcher *survived* — "arming is broken" and "never armed" look identical on disk. A one-line-per-exit `watch-log.jsonl` + a guard alarm for "≥3 arms under 60 s" converts an invisible failure into a loud one. | new | S | MED | backlog |
| A7 | **Capacity: reject NEW, never evict old** (their `450` cap + 30 d TTL raising a typed capacity error). Our store has no cap at all and no GC — 74 boxes, 120 orphan cursors, oldest lines from Jul 15. D6 `cc-mailbox-gc` (parked branch) is the archive half; the *refusal* half is the part to take. | R-4 | S | LOW | with D6 |
| A8 | **Content-addressed event id** — `sha256(account\ninbox\nmessage)` as the cross-transport identity, so the same message arriving by socket and by sweep dedupes. Directly relevant the moment A4 gives us a second delivery path. | new | S | LOW (HIGH once A4 lands) | with A4 |
| A9 | **Baseline fencing + a poison ceiling** — replay never reaches before the monitoring baseline; a message terminally fails after N attempts rather than retrying forever. | R-4 | S | LOW | backlog |

**Explicitly NOT taken:** hosted webhooks with signature verification (no server, no public endpoint —
the file *is* the durable path); Pods/multi-tenancy (one operator); IMAP/SMTP; labels as a general
state machine (our two-cursor model is simpler and already exactly-once); `agentmail-schemas` (stale,
superseded by the Fern definitions); their reconnect semantics wholesale — a normal close (code 1000)
*permanently disables* reconnection in their client, which is a bug shape worth naming, not copying:
a graceful termination indistinguishable from a deliberate stop silently retires the recovery path.

### 5.2 A3 — the host-driven turn (specified, deliberately not built here)

This is the only remaining mechanism that reaches a session which is **already idle and unarmed** —
the ~1,300 lines sitting in boxes today, which the wake floor cannot retroactively help.

**The finding that shapes it:** `openclaw` has everything our substrate lacks — a persistent daemon,
a live socket to a long-running agent process, an in-process plugin — and it *still* cannot wake an
idle agent from a message. Its only proactive wake is `agents.*.heartbeat`: **a scheduled cron job
that starts an agent turn.** Everything else in its stack (webhook → durable journal → dispatch →
adoption) is about not *losing* the message; the read happens when a turn runs. That is our harness
floor restated by a system that had every reason to beat it — which means the answer is not a
cleverer transport, it is **a scheduler that creates turns**, and we already own one.

Two candidate implementations, and the research changed the ranking:

**A3a — fire a session (PREFERRED).** `cc-inbox-guard` promotes from *alarm* to *reader of last
resort*: on `unacked > 0` past deadline with the owner pane dead-or-idle, it fires a session via
`scripts/handoff-fire.sh --window` — the documented non-anchoring surface that
`scripts/desk-invariant.sh:fire_replacement()` already drives headlessly from launchd — with the
brief "drain `<uuid>`, act, report". The human is paged only if the fire fails. This touches **no
live composer**, so it cannot re-open the v1 race at all; its costs are tokens and session sprawl,
so it needs hard damping (per-uuid TTL, a fleet-wide concurrent-fire cap, and the existing
`cc-teardown` lifecycle).

**A3b — drive the existing pane (riskier, keep in reserve).** Reuse `handoff-fire.sh`'s composer
transport (`async_send_text` + CR — the Ink-safe submit the recycle path relies on, explicitly *not*
the AppleScript `write text` char-stream behind the ttys018 mis-inject) against an *existing* pane,
gated by a file analogue of openclaw's `admission:"exclusive"`: `<uuid>.idle` written at Stop and
cleared at UserPromptSubmit, required present AND newer than the transcript mtime AND quiet ≥ N s,
under a `<uuid>.driving` mkdir lock. Payload is one line ("you have N unread"), never the body, so
delivery still runs through the audited `mailbox_take` path.

**Why neither is built in this pass:** A3b re-opens the exact race that killed v1 mail, and its
admission gate *is* the whole safety argument — it needs a RED-proof against a half-typed composer
and a permission modal, plus a shadow-default arm (`scripts/desk-arm-live.sh` pattern). A3a is
safe by construction but spends real tokens per fire and needs its damping designed before it runs
unattended. Both are builds with their own gates, not riders on this one.

### 5.3 The detector this exposes

`.watching` is our `listChanged`: a capability flag that two independent consumers branch on, that
was **universally false fleet-wide**, and that nothing announced. AgentMail ships the same shape —
`listChanged: true` advertised by a bridge that structurally cannot deliver the notification. The
lesson is not about either flag; it is that **a capability every consumer trusts needs a detector
that fires when it is false everywhere at once**. A per-session nudge (A1) cannot see "0 of 74". The
fleet-level check — `cc-inbox-guard` or the Operator Board reporting *armed watchers / live
sessions* — is what would have made the 0-watcher state loud on day one instead of on day six.

## 6 · Checked assumptions (things that could have made this wrong)

- **The heartbeat is not racy.** The floor's budget would be wasted if `.watching` appeared slowly
  after arming — a freshly-armed session would read as unarmed at the next Stop. Measured: the
  heartbeat lands **0.15 s** after launch (`_beat` runs on the first loop iteration, before the
  first `sleep`). A single 400 ms probe under load 143 did miss it, which is interpreter + lib
  startup, not the poll interval. The next Stop is a full model turn away, so the race is not
  material.
- **The floor cannot override an operator stop.** Kill-switch detection was hoisted out of the
  sentinel path specifically so the floor consults it; pinned by a test.
- **The floor cannot loop.** Bounded by attempts × TTL, and the exhausted branch *allows* the stop
  with a `systemMessage`. A repeating Stop hook is not evidence that more work exists.
- **The existing suites were pane-dependent.** `tests/session-continue.bats` was hermetic in paths
  and stubs yet still keyed `$_ouid` on whichever pane ran it; adding the floor turned that latent
  leak into four failures. Pinned now.
- **Only D11 of the parked branch is superseded**, not D4. The operator-visible `systemMessage`
  landed on main today via the `bin/cc-mail` work (`hooks/mailbox-drain.sh` greps 2 hits), so D11 is
  genuinely redundant. D4 is **not**: main's only `armed` hits in `bin/cc-await-ping` are two
  *comments*, no `.armed` file is ever written, and `bin/cc-wait` has zero `wake_path` hits — the
  durable arm-stamp and its certification exist only on `wt-02ba4e52389a`. (A research agent
  reported "D4/D11 superseded"; checked against `origin/main` directly, that is half right, and the
  half that is wrong would silently drop a wanted feature during reconciliation.) The branch's
  still-valuable set is therefore **D4 + D5/D6/D9/D10/D12/D13**.

## Status log

- **2026-07-26** — This session. Live wake-path probe PASSED end-to-end (§2). Live loss re-measured
  at 46% / 1,300 lines / 0 watchers (§1). Found the unrunnable `12-mailbox-posttool` activation on
  main (§3a) and the `cc-wait` vs standing-listener shape gap (Verdict). Wake-ladder design frozen
  (§4). Work branch `feat/wake-on-ping`.
- **2026-07-26** — agentmail-to investigated recursively (32 repos, 19-agent workflow). Absorb list
  §5. **A1 + A2 BUILT and landed from this branch** — the arm-on-open fix and the wake floor, the
  two HIGH-impact rows. A3 (host-driven turn) specified but deliberately unbuilt (§5.2); A4–A9
  backlogged. The single most useful external finding: **openclaw, with a daemon and a live socket,
  still cannot wake an idle agent from a message** — its only proactive wake is a scheduled turn.
  Our harness floor is therefore not a Claude Code deficiency; it is the shape of the problem, and
  the answer is a scheduler that creates turns, which we already own.
- **2026-07-29** — Backlog `a98084b79b2c` driven to done. Three landings, all gate-green:

  **1. The wake work had left trunk RED in 5 assertions** (`d6c3a7bd`) — nobody had re-run the
  suites after landing. Both reds were green when written: arm-on-open moved the nudge onto every
  boundary, silently inverting four `[ -z "$output" ]` exactly-once assertions in
  `tests/mailbox-drain.bats` from "no mail was surfaced" into "the nudge did not fire"; and the
  wake-floor RED-proof pinned its control to `origin/main`, which was the pre-fix tree only until
  this very change landed on it — from that moment the control IS the fixed tree and the proof
  fails permanently against a green one. Pinned to `a219de9d`. **A control can only promise to
  replay the pre-fix artifact if its ref is immutable** ([[control-must-replay-the-real-artifact]]).

  **2. The second gap — delivered ≠ read — is closed** (`a8b57f3c`). This was the half the ledger
  named and nothing had touched. `mailbox_receipt <uuid> <line>` turns the existing cursors into a
  verdict (unread | surfaced | **read**, keyed on `.acked` because seen is a promise and acked is
  evidence); every post-enqueue `cc-notify` verdict now carries `line=` and `unacked=`; and
  `cc-notify --receipt <target> <line>` is the read side, resolved through the same forward chain a
  send follows, with **the exit code as the verdict** (0 = read) so a desk claim can be *gated*
  rather than asserted. Without that verb the cited line is a number nobody can check and "cite the
  cursor" decays back into the prose this whole item is about. Every string `cc-announce`
  classifies on is preserved.

  **3. A defect the fix itself created, found by verifying the ledger's own care conditions
  rather than assuming them** (`33471d66`). MEASURED: a watcher whose owner dies is reparented to
  pid 1 and keeps polling; on the next message it takes the line with `ack_now=1`, advancing BOTH
  cursors, and prints the body to a stdout no model will ever read. The line is then marked
  **provably consumed for a session that no longer exists** — `cc-inbox-guard` sees `unacked=0` and
  never alarms, a read receipt reports `read`, and the successor's adoption (which migrates from
  `.acked`) inherits nothing. A silent loss wearing the costume of a successful delivery: the exact
  failure this channel exists to end, re-created by the mechanism that closes it. Latent before,
  **fleet-wide the moment the floor arms every session**. The owner oracle is the registry pid,
  never `$PPID` — a legitimate `run_in_background` arm has its launching shell exit immediately, so
  a healthy watcher's ppid becomes 1 exactly like an orphan's (verified; keying on it would have
  disarmed the entire fleet). Fail-safe: only a PRESENT row naming a DEAD pid proves death.

  Care conditions from the ledger item, adjudicated against disk rather than assumed: **(b) bounded
  / not held open at teardown** — satisfied, and better than the proposed `cc-teardown` reap, since
  a self-reaping watcher does not depend on teardown ever running. **(c) a dead watcher is
  detectable** — already true (pid-bearing heartbeat + `kill -0`). **(a) one watcher per session** —
  substantially satisfied (floor and nudge both arm only when unarmed, so a duplicate needs a
  sub-0.15 s race), with one **known residual, backlogged not built**: two concurrent watchers share
  one `.watching` file, so the first to exit removes the marker while the second still lives. The
  failure direction is conservative — the survivor merely reads as unarmed, mail drains on the next
  turn and the guard backstops — so a single-watcher lock would add a new failure mode to remove a
  benign one.

  **Not closed by this item:** A3 (host-driven turn) is still the only mechanism that reaches the
  sessions already idle and unarmed — the wake floor is birth-forward and cannot retroactively help
  the ~1,300 stranded lines. A4–A9 remain backlogged.

  **Surfaced, deliberately not fixed here (another stream owns it):** `hooks/mailbox-drain.sh`'s
  operator digest points at `cc-mail` ("full text: cc-mail"), and that command works today only
  because `~/.claude/bin/cc-mail` is a **hand-placed real file, not a symlink into the checkout** —
  its commit (`57579877`) sits on an unlanded branch, and the path is absent from `origin/main` and
  from the checkout working tree alike. So the live layer is the only copy: one `rm` from
  unrecoverable, and absent for anyone who redeploys from the checkout, at which point the digest
  names a command the operator cannot run ([[deploy-lag-checkout-behind-origin]]). Landing it
  belongs with the parked-branch reconciliation in §3, by composition — not as a rider here
  ([[parallel-stream-convergence-protocol]]).
