# The capacity park is the design, and an env override is what turned it into a husk

2026-09-19, during a five-session `/limit-recover fleet` recovery off a capped next4.

## What I filed, and why it was wrong

I filed decision packet `cbab9581db20` claiming the machine-capacity load check was a defect:
that it refused the relaunch and so left transplanted sessions as husks needing a hand-typed
command. Four of five recoveries did return PARTIAL with `relaunch typed but no claude process
appeared within 90s`. The inference was still wrong.

**Parking is the documented, intended outcome.** `commands/limit-recover.md` § fleet: the probe
"spends none of its 3-refusal budget — a pane is never `/exit`ed unless its relaunch can be
admitted; **at the wait cap the session stays PARKED with the term named**". My first run did
exactly that: `PARKED on capacity after 600s`, nothing charged, pane 112 untouched, zero loss.
That is the gate working.

## What actually produced the husks

I passed `CC_ADMIT_LOAD_TERM=off` to the `lr-fleet.sh` process. The fleet's probe then admitted —
but the **relaunch is typed into the pane's own shell**, a fresh process tree that never saw that
variable, so `lr-fire-resume.sh` re-evaluated with the load term ON and exited 9. Probe says yes,
launcher says no; the transplant had already completed in between, so the session landed on the new
account with nothing running it.

**The env override is what broke the probe/launcher agreement.** Under default settings both
evaluate identically and you get a clean park, never a husk. The failure mode was self-inflicted.

## The residual, stated honestly

`lr-fire-resume.sh:306` states the invariant "a limit-recovery resume must be delayable but never
permanently blockable", discharged by `CC_ADMIT_BUDGET` consecutive refusals releasing. That path
charges and does release — observed live in pane 121: `refusal 2 of 3; once the budget is spent the
next evaluation ADMITS and pages`. The fleet probe is non-charging *by design*, so repeated fleet
invocations do not advance that budget; on a box under sustained load the fleet path parks and the
operator retries or overrides. That is a designed trade-off already argued at length in
`scripts/lib/capacity-admit.sh`, not a defect, and not a decision to re-open unasked.

## The rule

A gate that REFUSES and a gate that STRANDS are different findings. Before filing the second,
check whether the refusal was the documented behaviour and whether your own overrides split one
evaluation into two disagreeing ones — an env var set on the driver does not reach a command typed
into another process's shell.

Companion: `docs/lessons/empty-selector-is-a-universal-selector.md` (same class — an assignment
that binds to one command and not to the stage that actually reads it).
