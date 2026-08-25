---
status: complete
---

> **DONE 2026-08-23.** W1 measured, W2 shipped as `completion-assert` arm **D7** + `close_act_*` in
> `hooks/lib/close-shape.sh`. Outcome, learnings and the two scope changes the numbers forced are in
> § W1 RESULT and § W2 AS BUILT at the foot of this file. Everything above is preserved as filed.

# CLOSE SCANNABILITY — the decision must be findable in one line

**Filed 2026-08-23**, from a live operator complaint during the sevenrooms-bridge session.
Extends [CLOSE_INTEGRITY_2026-08-10](CLOSE_INTEGRITY_2026-08-10.md) (which made closes *honest*)
and [OPERATOR_SURFACE_V2](OPERATOR_SURFACE_V2.md) (which made operator-owned steps *rendered*).
Neither made them **scannable**, and that is the gap this closes.

---

## Phase 0 — Agent Team Orchestration

| Wave | Locus | Why |
|---|---|---|
| W1 · measure | **S** (dispatched session) | Default locus for an implementation wave. |
| W2 · implement | **S** | Same session continues; the measurement is its own input. |

Single dispatched session, both waves. No teammates: the deliverable is a small number of edits to
three hook files that must stay mutually consistent, so splitting them across agents would cost more
in merge coordination than it saves. Lead (this session) holds nothing after firing.

---

## R1 — Current state, in the operator's own words

> "the way it is now forces me to scan really long and hard what the actual decisions are and it's
> not 'scan one line' for an actionable 'silver plattered / spoon-fed / hand-held' what to do"

And, earlier in the same session, after a close that ended `⛔ Blocked on you`:

> "Whats blocked on me? Be explicit: lead with the answer."

That second one is the load-bearing evidence. The close **had** a `⛔` rung, **had** the blocker in
its supporting lines, and the operator still had to ask what was blocked on them. So the defect is
not "the rung was missing" and not "the information was absent" — it is that **the actionable thing
was not resolvable to a specific act** without reading and synthesising several lines.

## R2 — Desired state

The operator reads **line 1** and knows (a) whether they must act, and (b) if so, the single
physical act. Everything else in the close is optional detail they may never read.

---

## What is already true (do NOT rebuild these)

- `wrap-ledger.sh` computes the rung from live git/gate reads. The rung is not the problem.
- `operator-readout.sh` renders operator-owned steps from disk truth, and `cc-do` collapses multiple
  runnable steps to one command. The rendering path is not the problem.
- `completion-assert.sh` already blocks a close that *offers* remaining work instead of driving or
  filing it (D-series asserts). That machinery is the right place to hang a new assert.
- `close-shape.sh` already matches the origin-close contract (Complication/Solution/Outcome +
  `Good to close:`).

## The actual gap — three named defects, all observed 2026-08-23

**D1 · A rung names a category, not an act.** `⛔ Blocked on you — need your call: <decision>` tells
the operator a decision exists. It does not tell them *what to do in the next ten seconds*. The
close that triggered this listed "resend the code / tick Trust this browser / close Chrome" spread
across three supporting bullets; the operator asked "is this what you need; are you unblocked?"
because no single line said *which act, right now*.

**D2 · The blocking act is not distinguishable from context.** Supporting lines and the blocking act
render identically (`- ` bullets). Chrome-closing (blocking) sat beside cookie-lifetime explanation
(context) with no visual or structural difference.

**D3 · Multi-step operator actions have no canonical single-act form.** `cc-do` handles *runnable
commands*. A physical/GUI sequence — "enter this code, tick that box, quit the window" — has no
equivalent, so it becomes prose, and prose is where it gets buried. This is the true novel gap: the
existing machinery assumes an operator step is a command.

---

## W1 — Measure before changing (the session's FIRST act)

Do not start from the three defects above; they are one session's sample. Establish the base rate.

1. Sample the last ~200 closes across transcripts (`claude-search`, or the transcript JSONL under
   the per-project dirs). A "close" = a final assistant message on a write turn.
2. For each, record: rung; whether an operator act was required; **the line index at which the act
   first becomes unambiguous** (1 = line 1, N = buried, ∞ = never stated as an act).
3. Report the distribution. **The metric this work moves is that line index.**
4. Report how often a close that required an operator act was followed by an operator message that
   is a *clarifying question* rather than an action — the round-trip rate, which is the outcome
   measure.

Write findings to `docs/research/close-scannability-2026-08-23.md`. If the base rate shows the
problem is rare or concentrated in one rung, **say so and scope W2 down** — do not implement the
full design against a problem that is not there.

## W2 — Implement, guided by W1

Design direction, not a specification — W1's numbers decide the final shape:

- **An `ACT:` line, mechanically placed.** When the ledger computes `⛔` or `👤`, the close must
  carry exactly one line stating the single next physical act, in the imperative, before any
  supporting line. One act, even when the act has sub-steps ("finish the login in the open Chrome
  window, then quit it" is ONE act; three bullets is not).
- **Extend `completion-assert.sh`**, since it already owns close-shape enforcement and already has
  the latch/cap discipline that stops a hook becoming an infinite loop. A `⛔`/`👤` close with no
  matched `ACT:` line blocks once, with the reason naming the missing line. Reuse the existing cap
  and latch — do not invent a second one.
- **Extend `close-shape.sh`** with the matcher, so the pattern lives beside the existing
  Complication/Solution/Outcome matchers rather than in a second place.
- **Non-runnable acts must render like runnable ones.** Today `▶ Run this:` + an inline-code span is
  the proven-visible form (screenshot-verified 2026-08-01: a ```bash fence renders plain white; a
  blockquote's `│` corrupts the paste). Find the equivalent for a physical act and record what was
  measured, not what was assumed — that rule cost a shipped regression to learn once already.

### Constraints

- **No new Stop hook.** `additionalContext` at Stop forces a turn and increments the same
  consecutive-block counter as `decision:"block"`; there is no whisper channel. Hang this off the
  existing `completion-assert` arm, latched and capped.
- **The assert must be able to fire negatively.** Give it a close that SHOULD block and prove it
  does. An assert that never blocks is indistinguishable from one that is not wired up.
- **Do not touch the rung computation** in `wrap-ledger.sh`. The rungs are correct; the prose
  built on them is not.
- Never weaken an existing gate to make a new one pass.

## Definition of done

- `docs/research/close-scannability-2026-08-23.md` exists with the W1 distribution and round-trip
  rate.
- The assert is wired, latched, capped, and demonstrated to block a bad close AND pass a good one —
  both shown as command output in the transcript.
- `bats` (or the repo's gate) green, and the change landed on `origin/main`.

---

## W1 RESULT — DONE 2026-08-23 (`5a565ba79`)

Full report: [`docs/research/close-scannability-2026-08-23.md`](../research/close-scannability-2026-08-23.md).
300 rung-carrying closes, 1,373 transcripts, 14-day window, all four account roots.

**63.3% of closes require an operator act. One of 190 states it at line 1; median line 6; 54.7%
never state it as its own line at all.** Whether the operator then *acts* splits **35.4% vs 9.4%**
on exactly that axis — p = 2.7e-05, measured within the 185 closes that all contain a command, so
runnability is held fixed and position is doing the work.

**Three learnings the plan could not have had:**

1. **The plan's assumed outcome measure was the wrong one.** Counting clarifying questions gives
   1.8% against a 1.1% control — noise. The operator mostly does not ask, they just do not act. The
   corpus records an act directly (`<bash-input>`), and only that measure separates.
2. **The defect is position, not styling and not absence.** The `▶` marker is already present in
   40.5% of act-required closes and **has never once put the act at line 1**. 2026-08-01 solved
   *is this a command*; nothing ever governed *where it goes*.
3. **Being early is not the property that matters; being a LINE is.** An act welded into line 1 is
   acted on 4.2% of the time — *worse* than a close with no act verb anywhere (15.4%). The cliff is
   is-a-line vs is-not-a-line; lines 1-3 / 4-6 / 7+ are flat within noise.

## W2 AS BUILT — DONE 2026-08-23

`completion-assert.sh` arm **D7** + `close_act_missing` / `close_act_ok` / `close_act_template` /
`close_act_reason` in `hooks/lib/close-shape.sh`; pulled by `/wrap` from the same code path. All
four constraints held: no new Stop hook, no change to rung computation in `wrap-ledger.sh`, no gate
weakened, and the arm is proven to fire negatively (`bats -f D7`, plus a live block/pass pair on the
real hook with the same ledger, session and substance — only the act's placement differs).

### Two scope changes the numbers forced, and one the mechanism forced

- **DROPPED — a new canonical form for multi-step physical acts (the plan's D3, "the true novel
  gap").** It is 2.6% of act-required closes (n=5). Instead: `▶` is reused, because the corpus shows
  it has *already* generalised past commands — 81 occurrences, 19 labels, including `▶ Open this:`,
  `▶ Look here:`, `▶ Reopen and tap:`, `▶ Reply with this to unblock it:` — and `ACT: <sentence>` is
  accepted as the second legal shape for the case with nothing to paste. **Nothing here is a new
  rendering claim:** the 2026-08-01 screenshot-verified span form is reused byte for byte, and
  position was measured *behaviourally*, never visually.
- **CHANGED — a window (3 non-empty unfenced lines), not literal line 1.** Line 1 is already owned
  by the rung, and R3 shows position within the message is flat. Demanding they share one row would
  buy nothing measurable.
- **SCOPED to `👤`, and `⛔` is an exclusion with a reason, not an oversight.** The ⛔ ledger term
  sets `contra=1` for every ⛔ close that reaches the arms, so a contra-gated D7 term would be
  unreachable and an ungated one would divert a conviction's arm and budget. A branch no fixture can
  drive is a claim with no control. The reachable ⛔ gap is *upstream of every arm* — a correct ⛔
  close asserts no done-tell and abstains at the close-tell gate — so closing it means widening that
  gate, which changes the population every existing arm was tuned against. **Filed as separate work,
  not smuggled in here.**

### Known issues / follow-on

- **`⛔` closes remain unreachable by any arm** (above). Needs its own evidence and its own
  regression set for the widened close-tell gate.
- **`✅` closes requiring an act are out of scope by construction** (42 of 190 in the sample). By the
  ledger's own definition a ✅ close has no filed operator step; those 42 are closes whose rung and
  whose prose disagree, which is a different defect (the rung is wrong, or the step was never filed)
  and belongs to D1, not D7.
- **`CLOSE_SHAPE_LIB` was a fallback, not an override** — found only by writing the fail-safe test,
  which blocked instead of abstaining because the fixture path fell through to the checkout. Now a
  hard override, matching `AGENT_IDENTITY_LIB`'s documented correction. *An untestable failure path
  is an untested one.*
- **One existing D1 test became order-dependent** and is now pinned (`CC_CLOSE_ACT=0`) with its D7
  half asserted separately end-to-end. Filing a step is *also* what makes wrap-ledger compute `👤`,
  so that fixture reaches two arms at once; it passed or failed on whether the ledger memo handed it
  a cached `✅`. Pinning the axis is the suite's existing technique, not a weakening — the conviction
  it would have produced is asserted in `D7 END-TO-END`.

---

## D8 — THE QUESTION IS NOT ASKED AT A CLOSE (2026-08-24)

Operator, unprompted, after this doc's work had landed: *"we should probably distill this into a
skill since I ask this a lot if we can't make this incredibly apparent with our CLAUDE.md return
communication / stop hook behavior. Ideally we do that but we haven't gotten this to work in months
of trying."*

The question, verbatim and recurring: **"what are our current tasks and decisions; are we working or
are we idling; are we 100% good to complete with no loose-ends or follow-on work remaining?"**

### The measurement that explains the months

`hooks/operator-readout.sh:1389` already quotes this operator's phrasing almost exactly and exists
to answer it. It is not broken. It fires **only on a `✅` write-turn close** — deliberately, because
"a certificate that fired on every close would carry exactly as many bits as one that never fires."

Both times the question was asked in the wake-path session, **no close was happening.** Work was
in flight, the model was emitting `🔧 Unchanged.` one-liners, and the certificate was correctly
silent. The same file names the cost of that silence: *"silence is not an answer; it is
indistinguishable from 'the hook didn't run', 'the model forgot', and 'nobody looked'."*

**Every close-side improvement is therefore off-target by construction.** That is the whole answer
to "months of trying": the surface being tuned is not the surface the question arrives on.

### Coverage, measured per axis

| axis of the question | renderer today |
|---|---|
| tasks & decisions | PARTIAL — `cc-backlog` holds *filed* rows; a decision the agent makes autonomously is in no store until filed |
| **working vs idling** | **NONE — 0 of `wrap-ledger`'s 33 machine fields, 0 `pgrep`/`ps` in either renderer** |
| good to close | YES — but only at `✅` closes |

The uncovered axis is the one the operator names **first**. It is also the one they cannot obtain
for themselves: background tasks are invisible to them, so `🔧 Unchanged.` is indistinguishable
from a 20-minute gate and from a stuck poll loop. That is a **missing sensor**, not a discipline
failure, and no amount of close-message doctrine can supply it.

### The precedent that makes it small

`scripts/wrap-ledger.sh:991` already renders `📦 Land IN FLIGHT (pid …, …s) — do NOT fire a second
/ship`, sourced from `hooks/lib/land-inflight.sh` under an explicit "ONE reader for the predicate,
shared with the producer — never a second copy" rule. **Liveness as a ledger field is already
accepted architecture; it is simply scoped to one activity.**

### Design

1. **`hooks/lib/session-busy.sh`** — `session_busy_live <dir>` → `<n> <sample-argv>` or empty.
   Three states, because they have different answers: **BUSY** (a job of mine is executing),
   **IDLE-ARMED** (nothing executing, wake path armed), **IDLE-DEAF** (nothing executing, no wake
   path). Collapsing the last two re-creates the wake-floor blindness.
2. **`wrap-ledger`** consumes it as ordinary machine fields, beside `LANDING`.
3. **`operator-readout`** renders it **where it is silent today** — the inverse of the current gate.
   The certificate is untouched.
4. **`/wrap`** renders all three axes from that same code, so the typed fallback and the automatic
   line cannot drift.

### Rejected, with reasons

- **A new skill/command.** It would be a *second renderer* for a question that already has one,
  against this repo's own "ONE renderer" rule — two answers to reconcile instead of one to trust.
  A thin caller of the same renderer is fine; a parallel implementation is not.
- **Reusing `gate-cleanup.sh --dry-run --quiet` as the arbiter.** Tempting (it is the actuator, and
  its contract is clean: pids on stdout, diagnostics on stderr) but its selection is *gate execs +
  descendants*, so it reads **idle while `deploy-live` runs**. That fails toward "idle", which is
  precisely the wrong direction for this question.

### Open, and deliberately not decided here

- **The scoping helpers must not be copied.** `gate-cleanup.sh:69-92` holds `ps_all` / `cwd_of` /
  `under_worktree` / self+ancestor exclusion, carrying two hard-won properties: physical paths
  (`pwd -P`; macOS `/tmp`→`/private/tmp` silently matches nothing otherwise) and **argv-POSITION
  matching**, because a Claude session's argv embeds its whole prompt and a substring match once
  selected a live peer for `SIGKILL`. The correct build extracts these into the shared lib and has
  `gate-cleanup` source them. That is a refactor of a kill-scoping script and needs its own
  regression run — it is the first step of the build, not a footnote.
- **Always-on risk.** The rung must stay newsworthy. Working↔idle genuinely varies turn to turn,
  unlike a close certificate, but that is an argument, not a measurement — it needs the same
  edge-not-level treatment `copy_drift_notice` uses.

### D8 addendum — the sensor prototyped, and the naive form FALSIFIED (2026-08-24)

Run before building, on this worktree, against known ground truth.

**Positive control (a land in flight):** the cwd-scoped predicate — physical path, self+ancestor
exclusion, `claude` sessions excluded because a session is not a job — returned **11**, sample
`/bin/bash scripts/ship-land.sh`. Correct.

**Negative control (the land exited): 9, not 0.** The naive predicate is therefore **useless as
written**: a count that is never zero cannot answer "are we working or idling", and would have
shipped as a permanently-on light (MEMORY: `alarm-polarity-and-attention-budget`,
`orphanhood-is-not-a-discriminating-signal` — key the alarm on an axis the HEALTHY population
lacks).

The residual 9, enumerated rather than guessed:

```
cc-await-ping × 2 (armed watchers)   + their python SA_SIGINFO side-cars × 2
mailbox-wake-arm.sh × 2              lead-crash-watchdog.sh
caffeinate -i -t 300                 a zsh shell-snapshot process
```

Every one is **wake/watchdog infrastructure** — i.e. precisely the `IDLE-ARMED` state, not work.
So the three states in the design are not a nicety; without them the sensor reads BUSY forever.

**Candidate discriminator, structural rather than a spelling list:** work executes a path under the
WORKTREE (`scripts/ship-land.sh`, `tests/*.bats`); infrastructure executes a path under
`~/.claude/` (`bin/cc-await-ping`, `hooks/mailbox-wake-arm.sh`). A denylist of infrastructure names
would rot as hooks are added (MEMORY: `denylist-enumerates-spellings-not-the-class`), and an
allowlist of work-names would miss novel jobs — failing toward "idle", the wrong direction.

**Unresolved, and the reason this wants a fresh context rather than the tail of this one:** test
runners break the rule. `bats-exec-test` has argv[0] under `/opt/homebrew` with the suite path as
an operand, so the worktree path appears at an argv POSITION that is not argv[0..1] — and widening
to a substring scan over argv is the exact defect `gate-cleanup`'s `is_gate_exec` header documents
(a Claude session's argv embeds its whole prompt; a substring match once selected a live peer for
`SIGKILL`). `claude` sessions are already excluded here, which weakens but does not remove the
hazard. **Resolve this before writing the lib, not after.**

### D8 addendum 2 — the open fork, RESOLVED: there is no single clean discriminator (2026-08-24)

The previous addendum left one thing to settle before writing the lib: how to classify
`bats-exec-test` as work without substring-scanning argv. Measured against the live population, and
the answer is that **every single-rule candidate fails on a nameable member** — so the rule is a
composition, and what actually matters is choosing its fail direction on purpose.

| candidate | fails on |
|---|---|
| argv[0..1] resolves under the WORKTREE | `bats-exec-test` — argv0 is `/opt/homebrew/…`, argv1 is `--dummy-flag`, and the suite path sits at argv[2+]. **False NEGATIVE.** |
| argv[0..1] under `~/.claude` ⇒ infrastructure | classifies `lead-crash-watchdog.sh` correctly; `caffeinate -i -t 300` (a harness-spawned utility at `/usr/bin`) reads as **WORK**. False positive. |
| parentage (descends from a hook vs from the tool shell) | backgrounded work is reparented to pid 1, so parentage is not discriminating at all (MEMORY: `orphanhood-is-not-a-discriminating-signal`) |
| widening to a substring scan over argv | the defect `gate-cleanup`'s `is_gate_exec` header exists to prevent |

**Resolution.** Compose two structural rules, then fail deliberately:

1. `INFRA` if argv[0..1] is under `~/.claude/` — structural, and *new hooks install there too*, so it
   covers the growing population instead of rotting like a name list.
2. `INFRA` if argv0 is a harness-spawned session utility (`caffeinate` today). This one IS a list,
   and is written down as such: short, stable, and to be re-checked when it grows.
3. Otherwise **`WORK`** — the unknown case reads BUSY, not idle.

**Why the fail direction is toward BUSY, and why that is safe only with the sample attached.** A
false IDLE is silent and actively misleading — it tells the operator nothing is happening while a
gate runs, which is the confusion this whole row exists to end. A false BUSY is self-diagnosing
*provided the renderer always names the sample process*: the operator sees `caffeinate` and knows
instantly it is noise. So `session_busy_live` MUST return `<n> <sample-argv>`, never a bare count —
the sample is not a nicety, it is what makes the chosen fail direction correctable.

The build in `a3eaa0dc1be2` is now unblocked: its one open design question is answered here.
