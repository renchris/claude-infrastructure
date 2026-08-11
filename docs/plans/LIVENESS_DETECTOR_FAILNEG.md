---
status: open
---

# LIVENESS DETECTOR FAIL-NEGATIVE — five measured instances of "it didn't happen" about things that did

**Created:** 2026-08-11 · **Backlog:** `1364bc327ccf` · **Origin:** measured incidentally across one
long session (2026-08-10/11) while running the Codex adversarial-slot probe.

**Scope (frozen):** find the shared mechanism behind two independent liveness detectors that both
answer NOT-HAPPENED about events that demonstrably happened, and resolve it so that
*happened* · *did-not-happen* · *cannot-tell* are three distinct verdicts rather than two.

---

## Phase 0 — Agent Team Orchestration

**EXECUTION LOCUS PER WAVE:**

| Wave | Locus | Why |
|---|---|---|
| W1 Derive the shared mechanism | **S** (dispatched session, Fable) | default; this is a derivation task, not an evidence sweep |
| W2 Fix + prove both detectors | **S** | default |

**Dependency:** W1 → W2. W1 may conclude the two detectors share NO mechanism, in which case W2
splits into two independent fixes — that conclusion is itself a valid W1 deliverable.

---

## The five instances (all measured, all in one session)

| # | Detector | Claimed | Actually |
|---|---|---|---|
| 1 | `self-close` announce-before-retire | "fired with `--notify-back` but NO ping was ever sent from this pane" | the pane had sent **two** `cc-notify` messages, each returning `verdict=delivered ... reason=wake-path-armed` |
| 2 | `handoff-fire` engagement detector | `FIRE FAILED — never engaged` (pane 296) | pane had ingested the brief and was mid-preflight (its transcript holds the brief as a user message + 3 assistant turns) |
| 3 | `handoff-fire` engagement detector | `FIRE FAILED — never engaged` (pane 297) | same — ingested, working, and it went on to produce the session's most valuable report |
| 4 | peer 296 `self-close` | "never sent its own status ping" | it had just sent a detailed completion ping that was delivered |
| 5 | `handoff-fire` engagement detector | `FIRE FAILED — never engaged` (pane 346) | ingested; already building blinded panel bundles |

## Why this is expensive, and why the DIRECTION is the bug

Both detectors fail toward **NOT-HAPPENED**. That asymmetry is the defect, not the individual
misreads:

- A fail-POSITIVE is noise a human discards.
- A fail-NEGATIVE **manufactures work**. Instance 2 caused a re-fire for work already running:
  two sessions in one worktree, a duplicated 36-run paid model grid (Fable + Codex), and a
  guaranteed collision on a single `index.json`. It was caught only because a human-directed check
  read the transcript instead of trusting the verdict.
- Instances 1/4 make a peer's close report its status as UNREPORTED when it reported fully —
  which then instructs the *reader* to go re-verify work that was already verified.

**The pattern to test in W1:** each detector appears to assert a NEGATIVE from the absence of a
signal within a TIME WINDOW, on a box whose load ranged 13–24 during every instance. Absence of
evidence inside a window is being encoded as evidence of absence. That is the same shape as
`lookup-miss-is-not-absence` and `probe-that-acts-on-absence-must-confirm-presence` in MEMORY.md —
check whether those entries' remedy applies here, or whether this is a genuinely distinct third case.

## Constraints on any fix

1. **Do NOT simply lengthen the timeout.** It trades one wrong answer for a slower wrong answer, and
   the load that produced every instance will recur.
2. **Do NOT make either detector always answer yes.** A genuinely never-engaged pane and a genuinely
   unsent ping must still be caught — that is the positive control.
3. **Prefer the durable artifact over the window.** Engagement = "the session's transcript contains a
   user message carrying the brief" (a file on disk). Ping = "the target mailbox holds a line from
   this pane" — and `cc-notify` already returns a parseable `verdict=` token, so consume it rather
   than re-deriving the fact.
4. **Where a window is unavoidable, make the non-verdict distinct.** "Could not tell within 120s" and
   "did not happen" must not share an exit code or a message.

## Open question for W1 (the derivation, not a sweep)

Is there a THIRD detector on this box with the same shape that has not yet produced a visible
instance? The two found here were discovered only because their false negatives happened to be
expensive and observed. A detector whose fail-negative is cheap would never surface at all — which
is exactly the class this investigation exists to find.

## Status log

- **2026-08-11** — Plan created from five measured instances. Not started. Related but distinct:
  `docs/research/codex-probe-screen-2026-08-10/screen-session-writes.md` independently indicts
  `hooks/completion-assert.sh:326` (`session_unlanded_mine`) for returning "not mine" where the
  truthful answer is "cannot tell" — the SAME three-state collapse, in a third place, found by a
  different method. Treat it as a candidate instance #6 and verify it.
