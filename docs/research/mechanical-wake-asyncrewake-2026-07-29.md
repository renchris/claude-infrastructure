# The wake path can be MECHANICAL: `asyncRewake` falsifies the harness floor

**Date:** 2026-07-29 · **Binary:** CC 2.1.219 (`~/.claude-219`, the binary this session and every
`claude-next*` session already runs) · **Probe artifacts:** `scratchpad/w0probe/PROOF-transcript.jsonl`,
`PROOF-watch.log`
**Scope (frozen):** investigate whether the SessionStart hook should arm the 2-way mail inbox itself,
instead of the Stop hook asking the operator/agent to arm it reactively; ground-up the mailbox so mail
is not lost while sessions are idle.
**Supersedes the load-bearing premise of:** `docs/research/wake-on-ping-2026-07-26.md` §4 ·
**Parent SSOT:** `docs/plans/CROSS_SESSION_COMMS_V2.md`

## Verdict

**Yes — arm it at SessionStart. And the mechanism is strictly stronger than every prior doc believed.**

Two findings, in priority order:

1. **The harness floor is NOT immovable.** CC 2.1.219 exposes `asyncRewake` as a **generic per-hook
   field**. A `SessionStart` hook declared `asyncRewake: true` is launched by the **harness** in the
   background at session birth, outlives the birth turn, and **when it exits 2 the harness synthesizes
   a turn and wakes the model** — carrying the hook's output. Arming stops being something a model must
   remember to do and becomes a declarative line of settings JSON. **PROVEN live this session** (§2).

2. **But a P0 must land first, or a better wake just reaches the wrong mailbox faster.** `cc-notify`
   **writes** to the pane-keyed box; the drain, the watcher and the wake floor all **read** the
   session-keyed box. **1,747 unacked lines** sit in 79 pane-keyed boxes right now, one of them written
   94 seconds before this measurement (§3). Prior work fixed the *advertiser* and never the *writer*.

The prior conclusion — *"nothing external can wake a fully-idle session except keystrokes (banned) or a
pre-armed in-session background task"* — was correct about **every mechanism it tested** and wrong
because a new one shipped. It is the [[inherited-impossibility-needs-a-configured-control]] shape: a
handed-down "structurally impossible" is disproved by ONE correctly-configured instance, never by more
analysis of the broken ones. Notably, a research subagent tasked this session with enumerating wake
mechanisms re-derived the old floor **from our own docs** and never found `asyncRewake` — a documented
capability is invisible to an evidence sweep that starts from the existing conclusion.

## 1 · The schema (read off the shipped binary, not the docs)

`strings` on `~/.claude-219/…/bin/claude.exe` — the per-hook command config fields:

| Field | Contract (verbatim) |
|---|---|
| `once` | "If true, hook runs once and is removed after execution" |
| `async` | "If true, hook runs in background without blocking" |
| **`asyncRewake`** | **"If true, hook runs in background and wakes the model on exit code 2 (blocking error). Implies async."** |
| `rewakeMessage` | "@internal Custom prefix for the system-reminder shown to the model when an asyncRewake hook exits with code 2. The hook output is appended after this prefix." |
| `rewakeSummary` | "@internal One-line summary shown to the user in the terminal… Defaults to \"Stop hook feedback\"." |

`asyncRewake` is **not** a `FileChanged` feature — it is available to **any** hook event. That is the
whole unlock, and it is why the earlier reading (which went looking for it under `FileChanged`) found a
narrower capability than what shipped.

Two corrections to the W0 task premise, both load-bearing:

- **`watchPaths` is NOT a SessionStart output field.** The only two documented producers are
  `CwdChanged` ("to register with the FileChanged watcher") and `FileChanged` itself ("to dynamically
  update the watch list"). SessionStart's contract is the unchanged `stdout shown to Claude` / `exit 2
  show stderr to user only`. A `FileChanged`-based design therefore has a **bootstrap problem** (to
  register a watch you must already be inside a watched event or a cwd change), and its matcher is
  *cwd-relative* filenames — our mailbox lives at `~/.claude/mailbox/<key>.md`, outside any project cwd.
- **`FileChanged`'s own exit-code table does not promise a wake** — it says "Other exit codes: show
  stderr to user only". The wake comes from `asyncRewake`, not from the event.

⇒ **The watcher-as-asyncRewake-hook path beats the FileChanged path** for our case: no bootstrap, no
cwd coupling, and it reuses `cc-await-ping`, which already owns the split-cursor ack, the forward
chain, and the owner guard. `FileChanged` remains interesting as a *zero-process* alternative (a
harness-owned chokidar watcher, nothing of ours polling) — worth a later probe, not the first build.

## 2 · The probe — PASSED end-to-end

Method: RED-proof by effect, with a positive control, per [[effect-read-predicate-red-proof]]. A
documented-but-inert surface is the known failure mode here (Stop `additionalContext` is documented and
empirically dead), so a citation was never going to be enough.

**Subject:** a fresh CC 2.1.219 interactive session in a detached tmux pane, hermetic
`CLAUDE_CONFIG_DIR` containing **only** the probe hook — no inherited Stop/SessionStart hooks that
could manufacture a turn and counterfeit the result.

**Settings under test:**

```json
{ "hooks": { "SessionStart": [ { "hooks": [ {
  "type": "command", "command": ".../watcher.sh", "asyncRewake": true, "timeout": 600,
  "rewakeMessage": "W0 PROBE — your mailbox watcher fired. Incoming peer mail:",
  "rewakeSummary": "W0 probe: mailbox wake" } ] } ] } }
```

**Positive control (run first):** the watcher standalone → fires within one poll, `exit 2`, body on
both streams. So any null result downstream could only mean "the harness did not wake", never "the
watcher was broken".

**Observed:**

```
06:16:34  START pid=99121            ← harness launched it in BACKGROUND at session birth
06:16:34  baseline=0                    (session start was NOT blocked — `implies async` holds)
06:16:55  alive poll=10              ← still polling 21 s later: it OUTLIVES the birth turn
   …      session answers, goes genuinely IDLE at the prompt
06:17:32  [external process appends one line to mail.txt — zero model participation]
06:17:33  FIRE body=[PEER-MAIL: …] — exiting 2 now
```

The idle session's transcript then grew 10 → 15 lines, the new turn being a **harness-synthesized user
message**:

```
<task-notification><summary>W0 probe: mailbox wake</summary></task-notification>
<system-reminder>
W0 PROBE — your mailbox watcher fired. Incoming peer mail: W0-PROBE-WAKE-STDERR: PEER-MAIL: this line
was written by an EXTERNAL process at 06:17:32
</system-reminder>
```

Every link confirmed: harness-armed at birth · survives to idle · external write · exit 2 · **model
re-invoked with the mail body in hand**. The subject was unauthenticated (the hermetic config dir has
no credentials), so the woken assistant turn is `Not logged in · Please run /login` — an **orthogonal**
failure that does not touch the claim. The wake is what was under test, and the wake happened.

### Implementation details the probe settled

- **`stderr` is the carried stream, `stdout` is not.** `W0-PROBE-WAKE-STDERR` appears in the
  system-reminder; `W0-PROBE-WAKE-STDOUT` appears **0 times**. A watcher that prints the mail body only
  to stdout would wake the session with an **empty** reminder — a wake that says nothing, which is the
  worst of both worlds. `cc-await-ping` currently prints the body on **stdout** (`mailbox_take`), so
  this is a required change, not a detail.
- `rewakeSummary` → the `<task-notification><summary>`, and is what the operator sees in the pane
  (`⏺ W0 probe: mailbox wake`). `rewakeMessage` → the system-reminder prefix. Both work as documented.
- The hook is **not** killed at the end of the birth turn.

### What the probe did NOT establish (do not over-claim)

- **Re-arm.** The hook fires once and exits; `SessionStart` will not fire again. Untested whether a
  `Stop`-declared `asyncRewake` hook re-arms cleanly, and whether an exit-2 async hook on `Stop`
  interacts with the existing `decision:block` wake floor (only ONE Stop blocker is permitted).
- Behaviour when the session sits at a **permission modal**, and whether `timeout` **kills** the
  background hook (ours polls 300 s under a 600 s timeout, so the ceiling was never reached).
- Whether the wake survives `/compact`, and the fleet cost of ~1 long-lived process per session.

## 3 · P0 — the writer and the reader disagree about the address

**This is live, active mail loss and it outranks the new mechanism.**

| Hop | file:line | Key used |
|---|---|---|
| WRITE | `bin/cc-notify:508` `>> "$MAILBOX_DIR/$uuid.md"`, target resolved via the **pane-keyed** registry | **PANE** |
| READ | `hooks/mailbox-drain.sh:64-68` — `own_uuid = own_sid` (the session id) | **SESSION** |
| resolver | `mailbox_resolve_key`, whose docstring calls it *"the one resolver every SENDER uses"* | **0 call sites in `cc-notify`** — `git log -S` finds none, ever |

`9586f1ac` ("advertise the box key the drain reads, not the bare pane") fixed the **advertiser**. The
**writer** was never touched. Measured live:

| | boxes | unacked lines |
|---|---|---|
| **PANE-keyed** | 79 | **1,747** |
| SESSION-keyed | 30 | 267 |

`D40A5752` holds **397 unacked** and was last written **94 seconds** before measurement — a box being
actively filled that nothing will ever read. A correctly-armed live session was measured holding two
real coordinator rulings undelivered for 3h45m, while its session box had never been written to at all.

Third-order harm: `cc-notify:644` checks `wake_path_armed` against the **pane**, finds no marker, and
reports `reason=no-watcher` — **a false negative about a correctly-armed peer** — then promises a
fallback drain on the peer's next turn, which is also false, because only SessionStart migrates
pane→session, never UserPromptSubmit. Both ends read normal. This is `9586f1ac`'s own thesis — *a wrong
key is indistinguishable from no mail* — surviving at the one hop the fix did not reach.

**Also still live:** fixture names (`deskA`, `deskC`, `DESK-UUID-1` — 276 unacked between them) are in
the operator's real store, `DESK-UUID-1` written 4h59m ago. The hermeticity leak is **active**, not
historical, so every fixture run pages real recipients and every count above is slightly pessimistic.

## 4 · The design — three rungs, all mechanical

Replaces the wake-ladder in `wake-on-ping-2026-07-26.md` §4, whose R1 rung exists only because arming
was assumed to require the model.

| Rung | Mechanism | Why it is now mechanical |
|---|---|---|
| **W1 — arm at birth** | `SessionStart` hook, `asyncRewake: true`, command = the mailbox watcher (`cc-await-ping`, body emitted on **stderr**) | the harness arms it. No Bash tool call, no model choice, no prose, nothing to forget. Proven §2. |
| **W2 — re-arm at every idle boundary** | the same hook declared on `Stop` with `async`/`asyncRewake`, guarded by the existing pid-bearing `.watching` marker so it is a no-op when already armed | the wake is self-disarming by design (EXIT trap clears `.watching`); re-arm must therefore recur, and this makes recurrence a settings fact rather than a nudge the model may ignore. **Needs the §2 re-arm probe first.** |
| **W3 — backstop for sessions already idle and unarmed** | `cc-inbox-guard` promotes from *alarm* to *reader of last resort* (existing task #57 / A3a): fire a session to drain, page only if the fire fails | W1 is birth-forward and cannot retroactively help the 1,747 stranded lines. Unchanged from the prior design and still correct. |

**Order of work is not negotiable:** §3 (address) → W1 → W2 → W3. Shipping a better wake on top of a
mis-addressed writer delivers nothing faster.

**Keep the existing `cc-await-ping` semantics.** The split `.seen`/`.acked` cursor, the forward chain,
the owner guard (registry pid, never `$PPID`) and the fail-closed cursor-write escalation are all
hard-won and all still needed — `asyncRewake` changes **who launches the watcher**, not what it does.
This is a ~1-line-of-JSON change plus a stream fix, not a rewrite.

**Do NOT rebuild the substrate.** Verified against `origin/main` by content: session-keyed addressing
(M1), pull-adopt (M4), the close-path actuator (M3), the wake floor, the self-reaping watcher, read
receipts and the operator-visible digest are all **landed and live** — 23 pid-proven armed watchers
right now, not the "0 of 74" the docs still claim. The residue is a **land + activate** problem:
`wt-02ba4e52389a` (8 commits, D5/D6/D10/D12) is 547 behind and LAND-BLOCKED on test contention, not on
a red gate; `bin/cc-mail` exists **only** as a hand-placed live file, one `rm` from unrecoverable.

## 5 · A second defect the new mechanism deletes for free

The wake floor currently demands arming from sessions that **structurally cannot comply**: a research
subagent is classifier-denied for a background `Bash` spawn and has no `SendMessage`, so it gets the
`decision:block`, cannot arm, has no inbox worth arming, and burns a real model turn per attempt —
`hooks/session-continue.sh:240-312` gates on *having a key*, never on *ability to arm*. Same shape as
the `12-mailbox-posttool` activation that can never succeed: **a demand whose remedy is forbidden at
the callee.**

Under W1 this class evaporates — the harness arms the watcher, so no session is ever asked to do
something it is not permitted to do. Until W1 lands, the floor should gate on ability-to-arm (skip
subagents/sidechains).

## 6 · Corrections to prior docs (do not re-derive the old floor)

- `wake-on-ping-2026-07-26.md` §4 — *"The harness floor is immovable: only the model can arm its own
  watcher"* → **FALSE on 2.1.219.** §2 above is the counter-example.
- Same doc §1 metrics (0 armed watchers / 74 boxes) → **stale**; re-measure before citing.
- Task #58's premise (`watchPaths` as a SessionStart output field; `FileChanged` as the wake) →
  **half wrong**; the wake is `asyncRewake` and it is event-agnostic. The task's *instinct* — that
  2.1.219 contained an un-probed mechanical wake — was right.
- The general lesson, and the reason this took three sessions to find: **a capability enumeration that
  starts from our own docs inherits their conclusions.** The binary is the SSOT for what the harness
  can do; a `strings` sweep of the shipped bundle found in minutes what a docs-grounded sweep declared
  impossible.

## Status log

- **2026-07-29** — `asyncRewake` schema read off the 2.1.219 bundle; **W0 probe PASSED** (task #58):
  an external file write woke a genuinely idle session with zero model participation, mail body
  delivered in the system-reminder. `stderr`-only carriage discovered. `watchPaths`/`FileChanged`
  premise corrected. P0 writer/reader key split confirmed and quantified at **1,747 unacked lines in
  79 pane-keyed boxes**. Design W1–W3 frozen. **Nothing implemented yet** — this is the investigation
  deliverable; W1 is a settings + stream change, ordered behind the P0 address fix.
