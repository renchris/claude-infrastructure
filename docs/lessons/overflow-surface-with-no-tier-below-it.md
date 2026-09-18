# An overflow surface with no tier below it fills until it hits its own cap

_Written 2026-09-17 from the tiering of this very file (landed 08586078e, 3d8fb2cb5)._

2026-09-17, `.claude/rules/agent-operating-lessons.md` at 190,960 loader chars against a
stated 150,000 limit.

**A warning that says "over the limit" is not evidence of loss, and the three things a
consumer can do at a ceiling demand three different responses** — TRUNCATE (rules vanish
from the middle), SKIP (the whole file vanishes, total and silent), or WARN (nothing
happens at all). Reading it as truncation makes the job "cut until the number drops",
which is a diet; reading it correctly made the job a TIER move, which is non-lossy.
Measured: this consumer has TWO ceilings and they are not the same kind of thing
(`bin/cc-memory-rotate:255`) — 4 MiB is HARD and the loader SKIPS the file entirely, while
the char cap is COSMETIC. At 191k we were at 4.7% of the hard one and **nothing was being
dropped**, proven directly rather than inferred: the file arrived WHOLE in a live session's
injected context, head/middle/tail all present, while over the stated limit. ⇒ **before
sizing a cut against a limit, establish what the consumer DOES at it, and prefer a direct
observation of the artifact arriving intact over any constant read out of a comment.** The
cost actually being reported was context budget — ~48K tokens of every session — which is a
real reason to act and a different one, authorising a different remedy.

🚨 **THE GENERATOR: an overflow surface with no tier below it fills until it hits its own
cap.** This file is the documented relief valve for MEMORY.md — `cc-memory-rotate
--drain-oversized` MOVES an over-cap index line here and its header calls that "non-lossy in
the strong sense" because the destination still loads unprompted. True, and it has no exit:
70 of 121 lessons carried `](.)` as their link target — no body file ever written — at 2,442
chars average against 289 for the ones using the hook+link shape, an 8.4x gap and 89.5% of
the file. Four say why in their own text: MEMORY.md was at its hard cap with zero append
slots, so the body had nowhere to go. **The inline form was never chosen, it was forced**,
which is what made restoring hook+link a repair rather than an override of a judgment. ⇒
**when you add a relief valve, ask what its DESTINATION overflows into** — the tell is a
population where one shape is an order of magnitude fatter than its sibling.

⚠️ **And the generator was ONE SENTENCE, not the file.** `hooks/memory-nudge.sh` reaches
every session and said the rules file *"has no 25,000-char/200-line cap … append it VERBATIM
as a whole line and do not shorten it."* That produced all 70. Fixing the file without fixing
that sentence would have re-inflated it inside a week. **When you clean up an accumulated
surface, grep for the instruction that told people to fill it** — see
[[enforcement-must-live-at-the-chokepoint]].

**Four companions, each separable and each paid for here.**
(a) **A milder repro EXONERATES:** `shellcheck -S warning` passed a file the land gate
reddened at `info` level — run the gate's own invocation, never a gentler one. Sibling of
[[prescribed-repro-weaker-than-the-harness]].
(b) **A rebase onto a moved trunk brings in siblings' lines, and a whole-file verdict then
convicts YOUR land for them** — my own new gate did this to me, naming three lines on trunk
before I started. Scope a ratchet to lines the range ADDED (no coverage lost — every line is
added by SOME land), and fail CLOSED when the diff is unreadable so "I could not tell who
added it" never renders as "nobody did". Same polarity as
[[gate-attributes-by-reachability-not-causation]].
(c) **A ratchet asserting a live file is GLOBALLY clean contradicts its own own-scope design**
and reds the moment a sibling lands an untiered entry — a content event in someone else's
diff surfacing as a failure in your suite. Pin the invariant that matters (it still PARSES;
a non-verdict is the only forbidden answer), not the transient state.
[[stale-assertion-becomes-an-inverted-guard]].
(d) **Patching a file trunk is concurrently appending to does NOT converge.** Stacked
fold-in + dedupe fixups re-create duplicate pairs on every replay — three land attempts. Write
an IDEMPOTENT normalizer that re-derives the whole file (body if absent, hook if known,
collapse duplicates); it is re-runnable after any rebase and converges in one pass.
