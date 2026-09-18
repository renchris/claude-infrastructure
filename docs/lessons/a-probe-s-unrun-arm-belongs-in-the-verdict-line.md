# A probe's unrun arm belongs in the verdict line, not in a caveat below it

**The rule.** When a question has two named arms and you can only build one, the verdict sentence
must name the arm you did not run. A caveat further down does not survive the reader, and it does
not survive *you*: the conclusion you write is the one the next session, and the plan, and the
backlog row all inherit.

## The incident (claude-infrastructure, 2026-09-17)

`docs/plans/NONLIMIT_RESUME_LADDER.md` carried W2-0, the gate on design item D4, as *"👤 ON-BOX
ONLY"* for eight days. Its own row names **two** arms:

1. a synthesized prompt with `promptSource=system` appears after an api-error turn end — i.e. a
   watcher armed EARLIER, still alive, whose `exit 2` lands while the session sits idle;
2. Stop-hook absence at that boundary (assert no `stop_hook_summary`).

I built a four-arm probe for **arm 2** — two controls firing both hooks, two tests firing neither —
and it answered cleanly: no Stop hook runs when the turn it ends died with an API error. Then I
wrote the verdict as **"D4 as specified is not implementable"** and landed it (`0dc8ed879`).

Both halves of that sentence were wrong.

- It generalised arm 2's result to arm 1, which I had not run.
- D4 had **never proposed arming at the death.** The same plan's § W1.2 hazard table carries the row
  `nothing can be armed at the death`, resting on transcript evidence, whose remedy column reads:
  *"D4 arms at SessionStart and at every PRIOR Stop, idempotently — it must already exist when the
  death happens."* The design had anticipated my result before I measured it. **I had that table
  open in the same file I was editing.**

Arm 1, run later the same session, came back **YES**: a watcher armed at SessionStart does get its
`exit 2` honoured after an api-error turn end — control plus two independent test runs, all
synthesizing the same second turn. So the correct verdict was the opposite of the one that landed:
D4 is implementable exactly as specified, and arm 2 is the *reason* its "arm it earlier" clause is
load-bearing rather than defensive.

## Why the caveat position is the whole lesson

The landed note *did* carry limits — a `## What this does NOT establish` section, three numbered
items, near the bottom. None of them said "there is a second arm and I did not run it", because at
the time I had not noticed there was one. But even had I written it there, the verdict line would
still have read *"D4 as specified is not implementable"*, and that is the sentence a plan's task
table, a backlog row, and the next session's first read all copy. A limit that contradicts the
verdict must BE the verdict.

## What arms 2's result was actually worth, stated rather than quietly downgraded

It converts arm 2 from transcript archaeology into a controlled experiment: the plan *inferred*
Stop-hook absence from records of a death nobody staged; the probe stages the death, holds
everything else fixed, and shows two controls firing where two tests do not. That is a real upgrade
in evidence class. Correcting an overclaim does not require discarding the measurement underneath it
— and saying so explicitly is what stops the correction from overshooting.

## The check that costs nothing

Before writing a probe's verdict: **re-read the item's own statement of the question and count its
arms.** If the count exceeds the number you ran, the verdict line says so. This is cheaper before
the land than after — mine cost two follow-up commits and a superseded research note that a reader
could have acted on in between.

## Companion

The same session produced the other half of this failure: two arm-C runs were discarded because the
driver's own timeout killed them mid-retry, and a killed process's empty log is byte-identical to a
real negative. Both are the same family — **a verdict about your own instrument wearing the
evidence's clothes** — and both are recorded in
`docs/research/api-error-rewake-proof-2026-09.md` § The two errors.
