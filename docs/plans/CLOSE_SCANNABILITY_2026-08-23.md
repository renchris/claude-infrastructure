---
status: open
---

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
