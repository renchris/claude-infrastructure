---
status: open
---

# Goal-safe 2-way comms — the ground-up architecture (2026-08-13)

**Operator `/goal`:** *investigate the 100th percentile ground-up 2-way communication
architecture/methodology such that we can work with /goal without a watcher/listener blocking it.*

**Parents:** `docs/research/goal-in-handoff-2026-08-08.md` (the mechanism + R1–R3 resolution) ·
`docs/research/mechanical-wake-asyncrewake-2026-07-29.md` (W0 proof, W2 spec) ·
`docs/plans/CROSS_SESSION_COMMS_V2.md` (delivery SSOT) · `docs/plans/TWO_WAY_SESSION_COMMS_PLAN.md`.
Everything below marked MEASURED was read from the live tree, the live settings, or the 5-config-dir
transcript corpus this morning; DERIVED and UNPROBED are labelled as such.

---

## The answer, in three lines

1. **The conflict was never "watcher vs goal" — it is that a session has exactly TWO idle modes and
   needs a THIRD.** With a background task parked, CC defers goal evaluation indefinitely (the
   starvation pole); with the registry quiet, an unmet goal blocks every stop until the cap (the
   spin pole). MEASURED, post-R1–R3, 3-day window: **84 goal sessions · 47 never evaluated once ·
   spin runs of 90/16/11/11/10 consecutive unmet evaluations · 15 cap force-idles.**
2. **The missing primitive is an IDLE-SCOPED AWAITER** — a watcher that terminates on peer mail
   *and on any new turn of its own session* (beat-file oracle), so the deferral spans exactly the
   idle window and the goal is judged **once per new-information event** instead of 90 times while
   waiting or 0 times forever. It is `cc-await-ping` plus two exit conditions, admitted as the one
   sanctioned shape through the `validate-bash.sh` chokepoint that today denies the whole class.
3. **The safety net beneath it already has a name and a spec: W2** (re-arm the asyncRewake watcher
   at every Stop, idempotent via the existing `.watching` claim) — specified 2026-07-29, never
   built, gated on one probe the spec itself names. With W2, a session that idles having armed
   nothing is still wakeable, registry-free, for its whole life instead of its first 3h59m.

---

## 1 · Axioms — the binary facts any design must fit

All measured against CC 2.1.220 unless noted; sources in brackets.

| # | Fact | Status |
|---|---|---|
| A1 | `/goal` = session-scoped prompt-type Stop hook; the evaluator is a separate tool-less LLM that sees only what the session SURFACED (prose or tool_result) | MEASURED [goal-in-handoff §2] |
| A2 | At any Stop where the task registry holds a non-terminal `local_bash` (`Tio`) or subagent/teammate/workflow (`_We`), CC removes the goal hook before the runner sees it and restores it in a `finally` — evaluation silently skipped. Deliberate; correct for real in-flight work | MEASURED [§ RESOLVED, binary @233098] |
| A3 | An unmet evaluation is a `blockingError` — the same consecutive-block counter as every Stop blocker; at `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` the harness force-ends the turn; the counter resets per external stimulus (typed message / task-notification wake). Fleet default is **50** (`bin/claude-latest:348-349`) | MEASURED [R2] |
| A4 | `asyncRewake` is a GENERIC per-hook field: the harness launches the hook in the background **outside the task registry** (module Set, not `taskRegistry`) and wakes the model with the hook's stderr when it exits 2, via a synthesized task-notification. Proven live on SessionStart (W0), and the *outside-the-task-registry* half — with its consequence, that the goal keeps evaluating — probed directly on 2026-08-13 (`goal-asyncrewake-ab-2026-08-13/`: 30 Stops, 24 registry-empty → 24 evaluations, 6 registry-occupied → 0, with the asyncRewake watcher provably alive across 5 of the empty ones). **Never probed on Stop.** Skipped in one-shot print mode (the K gate; `hooks/mailbox-wake-arm.sh:46-93`) | MEASURED on SessionStart / UNPROBED on Stop |
| A5 | A background task's COMPLETION re-invokes an idle model (task-notification). Its stdout is dropped; stderr is carried | MEASURED [mechanical-wake §2] |
| A6 | Delivery into a running turn = the drain boundaries (SessionStart / UserPromptSubmit / PostToolUse + the Stop fold). Delivery into an IDLE session = only a wake: watcher completion, asyncRewake fire, typed message, composer injection | MEASURED [mailbox-drain.sh header] |
| A7 | A goal dies with its session; `--recycle` inherits a live goal by default since R3 | MEASURED [goal-in-handoff §3.4, § RESOLUTION R3] |
| A8 | Evaluation economics: across all 380 goals ever armed here, **82% of met goals were met on evaluation #1; the met rate falls to 27% at ≥10 evaluations**; the one `failed:true` goal burned 45 evaluations / 27.6 h / 390,885 tokens. Re-judging is grinding, not converging | MEASURED [commands/handoff.md § goal-condition rules] |
| A9 | One attestation per turn boundary already lands in `~/.claude/cc-beats/<sid>.json` — `{kind: UserPromptSubmit|Stop, t, seq, who}` — written fail-open by `hooks/session-beat.sh` on every session. Auto-driven re-prompts (task notifications, Stop-hook feedback) DO fire UserPromptSubmit | MEASURED [session-beat.sh header] |

The deployed R1–R3 state was re-verified live this morning: `mailbox-wake-arm.sh` registered
`asyncRewake:true` in **all five** config dirs, `goal-inert-watch.sh` registered on Stop in all
five, cap default 50 live in `bin/claude-latest`. The resolution shipped; what follows is what it
measurably did not close.

## 2 · The measured residual (2026-08-13; all five config dirs; transcripts touched in 72 h)

Method: count `goal_status` ATTACHMENTS only (`type=="attachment"` — the prose-decoy filter the
08-09 addendum mandates), split sentinel (arm) from non-sentinel (evaluation), track the longest
run of consecutive `met:false` evaluations per session, and flag the harness's cap-override
message. Mirrored projects dirs double-count a handful of sids (the knowledge-layer mirror), which
moves totals, not the shape.

```
84 goal sessions · 37 with ≥1 evaluation · 47 with ZERO evaluations · 15 cap force-idles
longest unmet runs: 90 · 16 · 11 · 11 · 10 · 10 · 9 …
```

**The spin pole, type specimen** — session `8f478e5c` (2026-08-11): condition = *"the three
dispatched land-arch sessions … are landed on origin/main and content-verified, then the serialized
remainder P4→P3→P2"*. A wave lead whose end state lived in OTHER sessions' lands. **90 unmet
evaluations in 76 minutes — one evaluator LLM call plus one forced model turn every ~51 seconds —
all of them re-judging a world in which nothing had changed.** By A8, evaluations past #1 on an
unchanged world carry ~no information; this is the 390K-token anti-example's mechanism running at
fleet scale, and it is invisible in any per-session view because each turn looks like diligence.

**The starvation pole** — 47/84 zero-eval sessions. Not all defects: a goal deferred behind a REAL
subagent/build is A2 working as designed, and a session that died before its first clean Stop never
had an evaluation to show. But the class provably contains the pathological case, because the
transcripts cannot show task terminal-status (the § RESOLVED census caveat) — the decomposition is
retrospectively unknowable, which is itself a finding: **evaluation-liveness has no oracle today**
(§9 B5).

**The operator's screenshot (2026-08-13, this goal's trigger):** a session with a live goal killed
its own pre-goal inbox watcher to un-starve the goal — correct per current doctrine — and the
background task surfaced as `"Arm inbox wake watcher" failed with exit code 144` (the harness
sentinel for an external group-TERM, i.e. the session's own kill: `bin/cc-await-ping:37-47`,
`docs/research/await-ping-exit-144-2026-08-07.md`). Three defects in one frame: the arm existed to
be killed (pre-goal habit), the kill reads as a failure, and the killed watcher's own inbox notice
(`_wake_down_notice`, `bin/cc-await-ping:274-283`) then instructs **RE-ARM** — the exact act
`validate-bash.sh:232` denies under a live goal. The session ends the exchange deaf when idle.

## 3 · The state model — three session states, and the idle mode each needs

```
ACTIVE     goal evaluates at every stop attempt; unmet blocks feed the work; drains
           deliver peer mail at every boundary.                     → correct today (A2/A3/A6)
AWAITING   fired peers / an operator decision / any external event: the session holds
           NOTHING actionable. Needs: quiet idle + wake-on-event + eval-ON-event.
           Today it must choose starvation (park a task) or spin (stay bare). ← THE GAP
DONE       a clean stop with the condition met: evaluator writes met:true, auto-clears.
```

The whole design reduces to one new invariant:

> **Deferral must be idle-scoped.** A background task may exist under a live `/goal` only if it
> terminates on every wake of its session — including wakes it did not cause. Then A2's deferral
> spans exactly the idle window: the goal is never judged while nothing has changed (no spin), and
> never skipped once something has (no starvation). Evaluation cadence becomes **once per
> new-information event** — which A8 says is where all the verdict value lives anyway.

Everything else in this doc is the mechanism that enforces that invariant without asking any model
to remember it.

## 4 · The primitive: `cc-await-ping --idle-scoped`

Not a new tool — a mode on the existing watcher, which already owns the hard parts: the private
cursor that the drain cannot starve (F-3), the keyset cover (pane AND session box), the claim
files, the owner guard, the signal verdicts. The mode adds two exit conditions and three refusals:

| Clause | Behaviour | Why |
|---|---|---|
| C1 exit-on-mail | unchanged: new inbox line → print body → exit 0 → task completes → **completion notification wakes the idle model with the mail** (A5) | the wake half of 2-way comms, as today |
| C2 exit-on-turn | poll `~/.claude/cc-beats/<sid>.json`; any **UserPromptSubmit-kind** beat the session did not drive itself → exit 0 silently, `verdict=stood-down` | the session was woken by something else (typed message, task notification, asyncRewake fire). The awaiter's deferral job is over; the next natural Stop is registry-quiet and the goal judges the NEW state. The arm turn's own close cascade — its trailing Stop, and any `Stop hook feedback:` / ⟳⚑⚠ re-prompt a blocking Stop hook turns it into — is absorbed, so it cannot self-cancel (see §4.2) |
| C3 single-instance | refuse to arm when a live sibling claim exists for the keyset (the `.watchers` claim machinery, `cc-await-ping:179-196`) | overlapping awaiters re-create d33abf12's permanent deferral |
| C3′ **declare the mode** — a `mode=idle-scoped` line in the `.watching` marker AND in the per-pid `.watchers/<key>.<pid>` claim, re-stamped every poll beside the pid | **REQUIRED OF B3, and the reader already shipped** (E2, 2026-08-15): `mailbox_wake_idle_scoped` in `hooks/lib/mailbox-pending.sh` accepts EITHER file, and its absence means "plain" — so an idle-scoped watcher that omits the stamp will be reported to its own session as goal-blocking, with a `kill` beside it. The claim is the sturdier of the two: `_unbeat`'s hand-over rewrites the marker on behalf of a sibling whose mode it does not know. | the drain must tell a sanctioned awaiter apart from the 14400 s park it is replacing, and it can only do that from what the watcher writes |
| C4 refuse-on-pending | refuse to arm while `mailbox_has_pending` is true on any key | mail waiting = you have work; arming would defer the judgment of state you already hold |
| C5 bounded | `--timeout` default 3600 (not 14400): timeout → exit 2 → *as a plain background task* that completion also wakes the model (A5) — a periodic "re-look at the world" floor, and the in-session deadline check for a peer that will never ping | staleness bound; custody-overdue detection cadence |
| C6 chokepoint carve-out | `validate-bash.sh` allows exactly `cc-await-ping --idle-scoped …` in command position under a live goal; every other shape of the deny class stays denied, and the deny message TEACHES this form | enforcement stays at the chokepoint, and the chokepoint admits its own cure (MEMORY: enforcement-must-live-at-the-chokepoint) |
| C7 who arms it | the goal-blocked turn: drain nudge + the deny text + the wake floor all currently say "do not arm" under a live goal — they switch to instructing THIS form when the state is awaiting | the arm is taught at the exact moment the model has nothing else to do; no memory required |

**The cycle it produces** (DERIVED from A1–A5, each link individually measured):

```
event (ping/mail/answer) → awaiter exits → completion wake → model processes it
  → tries to stop → registry quiet → goal EVALUATES the new state (once)
     ├─ met  → auto-clear, done
     └─ unmet → ONE blocked turn → model re-arms --idle-scoped → next stop DEFERRED → quiet idle
```

Per event: **1 evaluation + 1 blocked turn.** The type specimen's 90-evaluation wait becomes ~2
evaluations (one per peer land it was actually waiting on). Starvation cannot outlive an idle,
because C2 kills the deferral on any wake.

**Known race, bounded:** a wake turn can end before the awaiter's next poll notices the beat, so
one Stop can still be deferred; the awaiter then stands down within one `--interval` and its
completion re-wakes the model, whose next stop evaluates. Cost: one bounce turn, only on wake,
never periodic. Default `--interval` for the mode: 5 s (beat file is one small stat).

**Interaction with our own Stop blockers** (session-continue 🔧, completion-assert): if one blocks
the arm-turn's stop, the continuation fires a UserPromptSubmit beat and self-cancels the awaiter —
converging one bounce later. Discipline unchanged by this doc: the arm is the turn's LAST action on
a clean, committed state, which the close protocol already demands.

**Under NO live goal:** the bare 14400 s form remains correct and remains the nag's instruction —
nothing to starve, and the parked watcher is the idle wake. The two modes are selected by the same
`goal_live_condition` predicate every producer already sources (`hooks/lib/goal-state.sh`).

### 4.1 · As built (B3, landed 2026-08-16) — the four deltas from the spec above

C1–C7 shipped as written. Four things the build settled that the spec left open, each measured:

1. **A FOURTH refusal, and it is the keystone: the ORACLE ITSELF.** C2 reads
   `~/.claude/cc-beats/<sid>.json`, so an arm that cannot resolve its sid, or finds no beat, or finds
   one older than `CC_AWAIT_BEAT_FRESH_S` (900 s), is REFUSED (`reason=no-session-id|no-beat|
   stale-beat`; `no-mailbox-lib` likewise, since C3/C4 must be judged over the whole keyset). Without
   it the flag would be a licence to park with no self-cancel — *the starvation pole, armed
   deliberately and blessed by a flag* — which is precisely the shape the chokepoint is being asked
   to admit on trust. Refusals exit **6**, park nothing, and disturb no marker.
2. **The sid is part of the instructed command, not an optional extra.** All three C7 producers
   interpolate `--sid <session_id>` (they each hold it already: `mailbox-drain.sh:83`,
   `session-continue.sh:133`, and the PreToolUse payload for the deny). A producer that cannot
   resolve one emits the placeholder and says so, rather than teaching a form the tool refuses.
3. **C2 is an OFFSET, not a `kind` filter.** The beat file holds only the LATEST boundary, so a whole
   turn can complete inside one poll and leave the watcher looking at a Stop-kind beat whose prompt
   predecessor it never sampled — and a watcher that ignores that stays parked over a session that
   has moved on, i.e. the starvation pole re-entering through the oracle. Turns alternate, so
   `seq > baseline + allowance` (allowance 1 iff the baseline beat was prompt-kind) excludes exactly
   the arm turn's own trailing Stop and nothing else. Erring toward standing down early costs one
   bounce turn; erring the other way costs the goal.
4. **The wake floor now BLOCKS under a live goal instead of abstaining.** The 08-10 abstain rested on
   "the goal itself keeps this session awake", which holds only BELOW the block cap — and the 15
   measured cap force-idles are exactly the population above it. It stays budgeted, TTL'd and
   kill-switched; the only thing the goal changes is WHICH command the block names. **One case still
   abstains: mail already pending** — the session has work, C4 would refuse the arm for that very
   reason, and the goal-forced turns deliver it, so blocking would be a pure round-trip.

Also fixed in passing, because C3 rested on it: `_claim_live`'s mtime read used the repo's usual
`stat -f %m … || stat -c %Y …` order, which is silently WRONG on coreutils (`-f` is `--file-system`
and `%m` parses as a FILE, so it prints a filesystem block to stdout and exits 1; the fallback then
appends the epoch to that block and the `*[!0-9]*` guard clamps the result to 0). Every claim read
STALE, so C3 would have refused nothing. GNU-first is the order that degrades cleanly both ways.

Suites: `tests/cc-await-ping.bats` (C1–C5, all four refusals + their discriminators, and the
two-pole red-proof against a fixture goal that models only A2 and A3) · `tests/wake-floor.bats` ·
`tests/mailbox-drain.bats` · `tests/validate-bash-goal-guard.bats` (17–23: the carve-out, its
per-segment scope, and that the loop shape still swallows it).

### 4.2 · UPDATE 2026-08-26 — item 3 above was wrong by one beat, and item C7 shipped with no writer

Backlog `b60eb29e97dd`. Both halves of the mode were inert in the same direction, and the direction
is the one that matters: **the wake floor was blocking a Stop to demand an arm that no-opped.**

**(a) The offset counted the wrong thing.** An arm turn does not end at its Stop — it ends when its
Stop is finally *allowed*. The wake floor blocks a Stop to demand this very arm, so the watcher is
born INSIDE a close cascade, and the next hook that blocks (the mechanical 🔧, the ship floor, the
origin close contract) makes that cascade another `Stop hook feedback:` prompt at baseline+2 — one
past an allowance of exactly 1, on the turn that armed it. Measured 2/2, banner thresholds `seq>3`
and `seq>6`. The floor then had `cnt=1` and would not re-block, so the session went idle **deaf**
with its budget spent: the alarm firing and the remedy it named being inert at the same time.
Item 3's reasoning about the sampling hole was sound; its arithmetic assumed a cascade of fixed
length. Fixed by making the baseline **roll**: every poll that can prove the newest beat belongs to
this session's own close cascade advances onto it, so the cascade can be any length (it is bounded
by `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` anyway). Two beats are absorbable — a Stop at exactly
baseline+1, and a prompt the session drove itself — and nothing else. The gap bound (≤2 for a
self-drive prompt: itself plus the Stop that must have preceded it) is what keeps the sampling hole
closed, so item 3's asymmetry still holds.

**(b) `who` could not answer the question, so the producer grew `src`.** "Is this prompt my own close
cascade or a wake?" is invisible to `who`, which collapses `Stop hook feedback:` and
`<task-notification>` into the same `auto`. Only `hooks/session-beat.sh` ever sees the prompt text,
so the classification is attested there, once, on the prompt already in hand — the same economics
that put `who` there. `src` is subordinate to `who` (`who=operator` ⇒ `src=operator`), so the
`CC_CLASSIFY_AUTO_RX` seam still governs the split and the two fields cannot disagree; it only
partitions the auto side into `stopfeedback` · `advisory` · `tasknote` · `localcmd` · `interrupt` ·
`auto`. C2 absorbs the first two and stands down on everything else, **including an absent `src`** —
a pre-field beat reads UNKNOWN, and unknown keeps the pre-existing stand-down, which is the mode's
licence (it can always prove it will self-cancel).

**(c) The `mode=idle-scoped` declaration had a documented reader and no writer.** `mailbox-pending.sh`
§ THE WRITER CONTRACT specifies the line, `mailbox_wake_idle_scoped` reads it, and
`mailbox-drain.sh:390` consumes it to exempt a sanctioned watcher from the "🚨 a parked watcher is
holding your LIVE /goal inert … `kill <pid>`" nudge. `cc-await-ping` never wrote it, so the reader
was constant-false and the exemption unreachable: the floor blocked to demand the arm and the very
next boundary told the session to kill it. `_beat` now stamps both files it already rewrites every
poll — the marker AND the per-pid claim, because `_claim_live`'s hand-over rewrites the marker on
behalf of a sibling whose mode it does not know, and the claim is never handed over.

New suite coverage: `tests/cc-await-ping.bats` — the cascade regression, a real wake after the
cascade, a non-self-drive `auto` beat (task-notification) as the discriminator, the gap bound, and
the mode declaration with the bare watcher as its control · `tests/session-beat.bats` — `src` as a
discriminator and its subordination to `who` under a rewritten `CC_CLASSIFY_AUTO_RX`.

**Still open after B3, and now reachable:** E4 — `goal-inert-watch.sh` will fire on a *sanctioned*
idle-scoped deferral, which is an alarm losing its polarity rather than a wrong verdict. Filed
separately; the fix is the one §8 already names (recognise the idle-scoped claim, downgrade to an
info line).

## 5 · The safety net: W2 — re-arm the asyncRewake watcher at every Stop

The birth watcher (migration 0007) is **one-shot**: consumed by its first fire, or expired at
3h59m, and nothing re-arms it — SessionStart does not recur mid-session, and under a live goal
every model-armed re-arm is (rightly) denied. So today a goal-armed session that reaches cap
force-idle after its birth watcher is spent is **deaf until someone types** — the residual half of
the pane-248 "8 pings, none entered context" incident, and the terminal state of the screenshot
session. `session-continue.sh:427`'s comment ("the goal itself keeps this session awake — a
stronger wake path than any watcher") is true only below the cap; the 15 measured force-idles are
exactly the population above it.

W2 is already specified (`mechanical-wake-asyncrewake-2026-07-29.md` W1/W2 table): **the same
`mailbox-wake-arm.sh`, additionally declared on `Stop` with `asyncRewake:true`, guarded by the
pid-bearing `.watching` claim so it is a no-op whenever any live watcher (birth, idle-scoped, or a
prior W2 instance) already covers the keyset.** Every idle boundary then re-establishes the wake
path mechanically — settings fact, not model memory — and it never enters the task registry (A4),
so it never defers the goal.

**UPDATE 2026-08-16 — the probe RAN and W2 is BUILT.** All four arms green on CC 2.1.233:
`docs/research/w2-stop-rewake-proof/`. The registration is `migrations/0012-mailbox-wake-arm-stop-rearm.sh`
(c10 — staged, awaiting the operator, like every settings.json migration in this repo), and the
claim guard is `_armed_already` in `hooks/mailbox-wake-arm.sh` (21/21 in `tests/mailbox-wake-arm.bats`,
22/22 in `tests/mailbox-wake-arm-migration.bats`).

**One assumption in the paragraph above was WRONG and the probe caught it.** This section says the
hook is "guarded by the pid-bearing `.watching` claim so it is a no-op whenever any live watcher …
already covers the keyset", which reads as a property the marker supplies. It is not: P-W2c measured
the harness deduping **nothing** — every Stop launches another watcher, and in phase C two of them
fired on the SAME mail line and burned TWO model turns. Only the hook can decline, so the guard is
code in the subject (asked over the whole keyset, fresh heartbeat AND live pid, failing OPEN to
arming when it cannot tell), and `0012` refuses to register against a subject that lacks it.

Building it also uncovered that the guard's own predicate was inert on Linux — `stat -f %m` is BSD
mtime and GNU `--file-system`, so `mailbox_wake_armed` read every live watcher as dead on a cloud
worker. Fixed in `hooks/lib/mailbox-pending.sh` (`_mbx_mtime`); the other 51 sites carrying that
idiom are filed, not touched.

*The original gate, kept for the record:*

**Gated on one probe, still un-run** (the spec's own §2 note, restated with today's knowledge):

- P-W2a: a Stop-declared `asyncRewake:true` hook is dispatched ASYNC (the A4 gate is per-hook and
  looks event-agnostic in the binary — `(e.async || e.asyncRewake && K) && !d` — but W0 proved
  SessionStart only). Assert an ordinary stop is not blocked and not delayed.
- P-W2b: its exit 2 while the session is idle synthesizes the wake (not a retroactive Stop
  "blocking error" — exit 2 is overloaded as Stop's block code, which is exactly why this needs a
  probe, not a citation).
- P-W2c: idempotency — a second Stop while a watcher claim is fresh launches and exits 0 without a
  second watcher.
- P-W2d: no interaction with a same-Stop `decision:"block"` from a shell hook (the one-blocker
  question the spec flagged).

Method identical to W0: hermetic `CLAUDE_CONFIG_DIR`, detached pane, positive control first,
red-proof by effect. Until it passes, W2 stays unbuilt — a documented-but-inert surface is this
repo's most-measured trap.

## 6 · Doctrine — where goals live in a wave topology, and how conditions are written

Unchanged by this design, now stated in one place because the specimen shows conditions doing the
awaiter's job badly:

- Fired workers carry goals (the `--goal` recipe; end state in-session). Leads may carry goals over
  dispatched work — that is the operator's standing recipe — and with §4 an awaiting lead is
  QUIET, not spinning. Custody, the ship floor, and the origin close contract remain the
  non-goal enforcement spine; the goal adds drive, not the bookkeeping.
- The four no-goal exceptions stand (commands/handoff.md): standing-role/desk · `--cloud` ·
  throwaway harness probes · a "done" that is an operator decision. Through-line: no reachable end
  state ⇒ no goal.
- Condition-writing under this architecture: end state + the check that proves it + the constraint,
  as a pointer (A8: 82% of met goals close on evaluation #1). A condition whose truth lives in
  OTHER sessions' progress is legitimate **only with the idle-scoped awaiter armed** — otherwise it
  is a 90-evaluation grinder by construction.

## 7 · The delivery/addressing layer beneath all of this — verified sound, inherited as-is

One mailbox substrate (`~/.claude/mailbox/`), session-keyed with the read-side coverage fold
healing pane-keyed writes at every boundary; drains at SessionStart / UserPromptSubmit / PostToolUse
with the Stop fold promoting `.acked`; dup-biased cursors ("a visible dup over a silent loss")
everywhere; `HANDOFF-PING` rides the same substrate, so there is no second transport to make
goal-safe. Composer injection (cc-notify) stays what it is — the best-effort interrupt, never the
load-bearing wake. Pane-less and resumed sessions arm via the harness's own `session_id`
(`mailbox-wake-arm.sh:26-36`); headless one-shots skip arming by design (the K gate). Nothing in
§§4–5 adds a transport, a daemon, or a registry — the 100th-percentile move here is that the
architecture needed one new *contract* (idle-scoped deferral), not new machinery.

## 8 · Sharp edges found on the way (each is a one-line fix, filed)

| | Edge | Fix |
|---|---|---|
| E1 | `_wake_down_notice` (`cc-await-ping:274-283`) tells a killed watcher's session to RE-ARM the exact form `validate-bash` denies under a live goal | goal-aware notice text: under a live goal, name `--idle-scoped` (post-§4) or the goal-forced boundaries — **BUILT 2026-08-15 (B4)**. The line states BOTH branches rather than branching on a predicate: the watcher is handed no transcript path, `goal_live_condition` would mean a multi-MB grep inside a SIGTERM handler, and it would answer a READ-time question at WRITE time — the notice sits in the box until a boundary drains it, by which point the goal may have been armed, met or cleared. The reader is not left guessing: the drain evaluates the live predicate at that same boundary (E2). The two sibling stderr verdicts (`verdict=killed`, `verdict=timeout`) carried the identical unconditional RE-ARM and now carry the same qualifier — the timeout path is the more common one, so leaving it would have left the defect in its likelier home. |
| E2 | A watcher armed BEFORE `/goal` arrives defers the goal, and nothing model-facing surfaces the kill (goal-inert-watch is `systemMessage`-only = operator-only); the screenshot session knew by luck | the drain (already goal-sourcing, already at every boundary) additionally names the live watcher pid + the one `kill` when goal-live ∧ fresh claim ∧ that claim is not `--idle-scoped` — **BUILT 2026-08-15 (B4)**, exactly as specified. Two new readers next to the predicate they extend (`mailbox_wake_pid`, `mailbox_wake_idle_scoped`); the idle-scoped exemption reads the declaration C3′ above obliges B3 to write, and absence means "plain", which is what every watcher in the fleet is today. The drain's empty-inbox exit is now keyed on the presence of a message rather than on `_watched` (which used to imply it) — armed + no goal still exits 0 byte-identically, pinned by the pre-existing suite. |
| E3 | `session-continue.sh:427` encodes "the goal keeps it awake" without the cap qualifier | comment + the W2 closure; no behaviour change |
| E4 | `goal-inert-watch.sh` will correctly fire on a §4 deferred idle (armed goal + non-terminal bash) — true but now-sanctioned | recognize the idle-scoped claim marker; downgrade that case to an info line so the alarm keeps its polarity (MEMORY: alarm-polarity-and-attention-budget) |
| E5 | Evaluation-liveness has no oracle (§2): zero-eval vs healthy-deferral is unmeasurable after the fact | B5 below — surface non-sentinel eval count + last verdict in the wrap ledger (`◎ goal: N evals · last unmet@HH:MM`), which also gives closes an honest goal line |
| E6 | A goal-armed session's own RESEARCH FAN-OUT is a starvation source with no alarm: named background Agent spawns are `in_process_teammate` tasks that defer the goal while they live, `goal-inert-watch` ABSTAINS on that type by design, and an agent briefed without a file-delivery contract leaves its report unharvestable if the return channel drops (see Addendum) | goal-armed sessions fan out research only with the research-subagents field-7 Delivery contract (each agent WRITES an artifact path) or synchronously; harvest = Read the file, then `TaskStop` the agent to un-starve the goal |

## 9 · Build list — filed, ordered, each independently landable

| id | backlog | Item | Gate |
|---|---|---|---|
| B1 | `62e0b88a58b5` | ~~**Run the W2 probe** (P-W2a–d, §5), commit artifacts like W0~~ **DONE 2026-08-16** → `docs/research/w2-stop-rewake-proof/` | none — read-only probe |
| B2 | `3118d712f668` | ~~Register W2 (same hook, Stop, `asyncRewake:true`) as a c10 migration across all five config dirs, claim-guarded~~ **DONE 2026-08-16** → `migrations/0012-…` + `_armed_already` | B1 green ✓ |
| B3 | `6290f0ee6b52` | **LANDED 2026-08-16** — `cc-await-ping --idle-scoped` (C1–C5) + the `validate-bash` carve-out (C6) + producer messaging flips (C7: drain nudge, deny text, wake floor) + suites — red-proof BOTH poles: a mutant that never self-cancels must starve a fixture goal; a mutant that never defers must spin one | none |
| B4 | `b33f424c747b` | E1 + E2 message fixes | none (E1 standalone; E2's final text references B3's form) |
| B5 | `b0ce82d745be` | Goal-liveness oracle in `wrap-ledger.sh` + `/wrap` (E5) | none — **BUILT 2026-08-15, `78791cd8`** |

| B1 | `62e0b88a58b5` | **Run the W2 probe** (P-W2a–d, §5), commit artifacts like W0 | none — read-only probe |
| B2 | `3118d712f668` | Register W2 (same hook, Stop, `asyncRewake:true`) as a c10 migration across all five config dirs, claim-guarded | B1 green |
| B3 | `6290f0ee6b52` | `cc-await-ping --idle-scoped` (C1–C5) + the `validate-bash` carve-out (C6) + producer messaging flips (C7: drain nudge, deny text, wake floor) + suites — red-proof BOTH poles: a mutant that never self-cancels must starve a fixture goal; a mutant that never defers must spin one | none |
| B4 | `b33f424c747b` | E1 + E2 message fixes — **LANDED 2026-08-15**. 12 tests, both arms red-proofed against `origin/main` (`tests/cc-await-ping.bats` 46/46, `tests/mailbox-drain.bats` 37/37). E2's text names the goal-forced boundaries rather than `--idle-scoped`, because B3 has not landed — the FORM is deferred, the EXEMPTION is not: the reader shipped, and C3′ records what B3 owes it. | none (E1 standalone; E2's final text references B3's form) |
| B5 | `b0ce82d745be` | Goal-liveness oracle in `wrap-ledger.sh` + `/wrap` (E5) | none |

Acceptance for the whole architecture, as disk-truth reads: in a fixture wave, non-sentinel
evaluations per session ≈ external events ± 1 (today: 90 for ~2 events) · fleet p95 longest-unmet-run
≤ 2 within a week of B3 (today: 90) · cap force-idles → ~0 (today: 15/3d) · zero-eval sessions
holding a goal ≥30 min with ≥1 clean Stop → explained by A2-legitimate work or ~0 (needs B5 to be
measurable) · a goal-armed idle session receives a 2nd and 3rd ping without an operator keystroke
(today: guaranteed deaf after the birth watcher is spent).

**B5 BUILT — 2026-08-15, `78791cd8`.** The acceptance clause above says the zero-eval class needs
B5 "to be measurable"; it now is, per SESSION and at the CLOSE rather than only in a corpus sweep.
`hooks/lib/goal-state.sh::goal_liveness` counts the non-sentinel `goal_status` attachments **since
the last arm** and reports the last verdict; `scripts/wrap-ledger.sh` emits
`GOAL_SRC/EVALS/LAST/LAST_T/AGE_MIN/LINE` (`--machine`), a `Goal (◎):` row (`--full`) and the ◎
line alone (`--goal`), which `/wrap` prints on its default path. Three design points worth keeping:

- **Reported, never a rung.** A live goal is a normal state, so a rung would fire at every close of
  every goal-armed session (the alarm-polarity law that bounds 👤/⛔/🚀 in that ledger). The ◎ LINE
  is emitted for a LIVE goal only, for the same reason; the FIELDS are emitted in every state,
  because the fields ARE the measurement §2 lacked.
- **Since the last arm, never over the file.** A session that armed, met and re-armed a goal is on
  its second goal; carrying the first's evaluations into the second's count reports a healthy
  number over a goal that has never been judged — the exact false negative this closes.
- **The pole is now visible where it can be acted on**: `◎ goal: 0 evals · armed@12:31 (142m ago)
  — armed but NEVER judged` at a close, instead of "47 of 84, decomposition unknowable" three days
  later. The remaining acceptance rows still need B3; this one is now readable per session.
  (E5's own row in §8 is thereby closed; E1/E2/E3/E4 remain open under B4.)

## 10 · What was deliberately NOT designed

- **No defeat of CC's deferral** — A2 is correct; §4 *aligns* our idle with it instead of judging
  half-finished work.
- **No external wake daemon / keystroke injector as a load-bearing path** — injection stays the
  interrupt it is; every load-bearing wake is a harness-native mechanism (A4/A5) with a
  deterministic consumer.
- **No second transport** for pings, decisions, or operator answers — one substrate, one drain, one
  wake discipline; the failure modes of a parallel channel (2nd-transport-makes-an-e2e-ambient) are
  already in the memory index.
- **No change to `/goal` semantics or the cap** — 50 stays a runaway bound; §4 makes reaching it
  rare instead of routine.

---

## Addendum 2026-08-13 — the investigating session was its own specimen

The session that wrote this doc armed the operator's `/goal` at birth, fanned out two named
background research agents for corroboration breadth, landed §§1–10, and then sat idle 142 minutes.
Its own transcript afterwards read **1 sentinel arm · 0 evaluations** — the starvation pole, live,
in the author. Four measured observations, one of which sharpens A2:

1. **Named background `Agent` spawns are `in_process_teammate` tasks** (the `TaskStop` receipts
   name the type), not `local_bash` — so a goal-armed session's own research fan-out is a deferral
   source the `validate-bash` chokepoint structurally cannot see (it gates Bash, not Agent).
2. **The binary's `isIdle` exclusion did not exempt them once idle.** `_We` excludes
   `in_process_teammate && isIdle`, and both agents had emitted `idle_notification` hours before
   the session's last stop — yet that stop produced no evaluation (0 on disk, goal still armed, no
   spin). Either the registry never carried `isIdle` for them or the exclusion did not reach this
   path — UNKNOWN which; the B1 probe rig settles it cheaply (arm a fixture goal + one idle
   teammate, count evaluations). Until then, treat an idle teammate as a live deferrer.
3. **No alarm fired the whole time, correctly:** `goal-inert-watch` abstains on `teammate`-type
   deferrers by design (`cip()` ships no idle flag). The doc's author spent its idle inside the
   sensor's documented blind spot — under-reporting stays the right alarm polarity, but E6's rule
   is what actually covers the gap.
4. **The corroboration reports were unharvestable after the fact** — no completion notification,
   no task-id lookup, no on-disk transcript, two `SendMessage` resumes unanswered — because the
   spawn briefs said "your final message is the report" instead of the research-subagents skill's
   field-7 Delivery contract (each agent WRITES an absolute artifact path; a subagent's prose is
   invisible). Nothing load-bearing was lost — every §§1–10 claim traces to firsthand reads — but
   under a live goal the cost of that omission compounds: the agent defers the goal while it lives
   AND delivers nothing durable if the return channel drops. The E6 rule is the remedy, and ending
   the fan-out with `TaskStop` is what un-starved this session's goal.
