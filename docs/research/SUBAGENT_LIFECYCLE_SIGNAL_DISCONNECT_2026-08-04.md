
---

## Mode 5 (added after capture) — an agent finished, wrote its report, and the report never left

`H-failures` **completed its axis at 03:11 and its report did not reach the lead until 11:15** —
**70 minutes late, and only because the lead chased it by hand on a final-call sweep.** Cause: it
emitted the report as **plain text in its own turn** instead of calling `SendMessage`. A subagent's
prose is not visible to anyone; only a tool call transmits.

Meanwhile it emitted `idleReason: "available"` throughout — so from the lead's side it was
indistinguishable from mode 2 (permanently stuck, nothing to deliver). The lead had already
**reconstructed the entire axis by hand** from its landed raw data.

**Why this mode matters more than the other four:** its report contained the wave's single
most consequential finding — that a **paid** photography regen would make the defect *worse*
(the 4k master cohort bands **10.7× worse** post-encode than the 2k cohort, and every FAIL is 4k).
A silently-undelivered report is not a lost status update; it is a lost decision. Had the lead
not swept, that money decision would have gone the wrong way on no evidence.

It also caught a **real bug in the lead's own harness** — `cambiOfAvif` decodes to `yuv444p10le`,
so a 12-bit encode is downconverted through **swscale's default-on dither**, inflating bd12 scores
~25× — which had already produced (and nearly shipped) a false headline recommendation.

**What this adds to the frame.** The other four modes are about a *signal* the lead cannot trust.
This one is about a *delivery channel the agent can silently fail to use* — and the two compound:
the unreliable signal is exactly what stops a lead noticing the undelivered report. Any fix that
addresses idleness without also making **delivery** an asserted, checkable act leaves this mode
fully intact.

Corollary for the completion contract: "task complete" must mean **deliverable handed over**, not
"turn ended" and not "agent believes it is done". A contract the agent asserts, with nothing
delivered, is the same failure wearing a new name.
