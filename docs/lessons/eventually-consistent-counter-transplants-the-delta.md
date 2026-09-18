# An eventually-consistent counter does not go stale — it TRANSPLANTS one window's value into the next

**2026-09-18.** A controlled two-arm A/B returned **both arms exactly inverted**, and the probe
printed the wrong conclusion in its own output. Nothing in the experiment was wrong except *when
the counter was read*.

## What happened

Question: does OpenRouter's `openrouter/pareto-code` router actually bill us? Design was sound —
a treatment arm, a control arm, an account-level counter read before and after each, and a 35s
settle between them:

| arm | reported per-call cost | observed `usage` delta |
|---|---|---|
| 1 — three `pareto-code` calls (treatment) | $0.00108 | **$0.00000000** |
| 2 — three `:free` calls (control) | $0.00000000 | **$0.00108** |

Read naively this says the paid thing is free and the free thing costs money. The probe
duly printed `=> pareto-code is FREE to us`. Both readings are backwards.

The counter is **eventually consistent with latency > 35s**. Arm 1's charge had not posted when
arm 1's "after" was read, and *had* posted by the time arm 2's "after" was read. The value did
not merely arrive late — it arrived **inside the next arm's measurement window**, where it was
attributed to that arm.

## Why this is worse than ordinary staleness

Stale data is *old*. This is *misfiled*. A stale counter makes a delta too small and you suspect
it. A transplanted counter makes one delta too small **and another too large by the same amount**,
which:

- preserves the total, so any sanity check on the sum still passes;
- produces a **non-zero** delta on the control arm, which is exactly the signature a careful
  experimenter reads as "my control is contaminated, the treatment must be real";
- and yields a clean, plausible, self-consistent story in the wrong direction.

A control arm can therefore be **convicted of the treatment arm's cost**. The better the
experimental hygiene (tight arms, back-to-back, small settle), the *more* likely the transplant,
because shortening the gap between arms is what puts arm N's posting inside arm N+1's window.

## The rule

**Before any before/after delta on a counter you do not own, settle it with a NO-NEW-CALLS HOLD.**

1. **Stop all activity.** Issue nothing.
2. **Poll the counter until it stops moving.** Here it held at `0.00943675` across 120s. Only
   then is the account quiescent and a delta attributable.
3. **Reconcile independently.** Sum the **per-item values the API returned with each response**
   and compare to the account total. They agreed to the cent — and *that* is what proved a
   **lag** rather than a **discount**. Without the reconciliation, "the treatment arm cost $0"
   and "the treatment arm was free" are indistinguishable.

The disambiguating test costs **nothing**: it is a hold and a poll, no extra calls.

## Generalisation — this is not about billing

Any counter written by a system other than the one you are measuring, and read by polling, has
this failure mode. Candidates seen in this repo's own tooling: quota/usage meters, rate-limit
remaining, queue depth, "records processed", replication lag, CI minutes, cache hit counters,
webhook delivery tallies. The property that matters is **not** "is it a cost" but **"is the
write asynchronous to the action I am attributing it to."**

⇒ When an arm's delta is suspiciously zero **and** a neighbouring arm's delta is suspiciously
non-zero, suspect a transplant before you believe either. Two errors of equal magnitude and
opposite sign, adjacent in time, are the signature.

## Companion, from the same investigation

The conclusion the transplant nearly hid was itself a second-order reading error: the vendor's
FAQ said *"the pricing shown for Pareto Code Router is zero, so you are not charged for prompt or
completion tokens"*, which means **the router takes no markup** — the model it dispatches to bills
normally (here `anthropic/claude-fable-5.1`, 8 of 8 calls, $0.00036–$0.00242 each). *"The router
is free"* and *"the inference is free"* are different claims, and a page asserting the first gets
read as the second. See [[zero-limit-credential-cannot-measure-free]] for the other half of this
pair — the instrument that could not price at all.

**And the cap is the hero of the story.** The whole truth cost **$0.0094** to establish because a
$1 ceiling was set first. A bounded experiment is how you buy a fact you cannot read your way to.
