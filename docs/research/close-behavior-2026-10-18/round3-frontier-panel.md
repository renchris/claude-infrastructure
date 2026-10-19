# Round 3: frontier panel on the continuation gap (H-CLOSE-1), 2026-10-19

Two Fable 5.1 panelists (`frontier-derivation`, baseline-blind, read-only), inline on the wall that README §8
names: nothing landed turns finished research or an honest "❌ no" into the next action. Cost: about 227K
subagent tokens (107K + 120K, measured from the task notifications), 2 of the session's 6 frontier spawns.

## Answer first

1. **The leak is the yes-with-follow-on close, not the honest no.** Panelist 1 proposed a "verdict-no latch"
   (block a `Good to close: no` close unless the turn wrote a store act). Its own falsifier was probed and the
   design fails on precision: 51 sessions ended on a no-close in 14 days (about 40 unique transcripts; some appear
   under two config dirs), and hand-reading every one found that nearly all already name who drives the remainder
   (a fired pane, a recycled successor, a ⛔ decision, filed operator steps, an outside event). One or two had
   undriven work (measured: `/tmp/close-behavior-lead/p1/nocloses.py`, hand-labelled). **REFUTED as a build.**
2. **That makes the landed rule change (C5) the right lever, and gives it measured support.** C5 makes a yes over
   unfiled, undriven work a contract breach and asks the no-form for "who drives it". The census above says the
   no-form, when agents write it, carries a driver about 95% of the time. C5's efficacy number (35-45% that line 1
   then leads with the remainder) is still an estimate; the next measurement is a post-land census (§4).
3. **The strongest new framing is "disposition is a store act, not prose"** (both panelists independently). Every
   prose matcher retires once a non-✅ close must end with one of {`session-continue.sh set`, a fire, a `cc-decide`
   packet, a `--why-not-now` row}, each already a store write. Of those, `set` is one command and arms the actuator,
   so the cheapest compliance is driving. Measured: 34 agent `set` arms in 14 days against 1,945 Stops (panelist 2,
   IDL). **NEW**, not built: it changes the close contract for every session, and its precision rests on the
   no-close census above (where the close already names a driver, the act is cheap; where it does not, it blocks).

## 2. Findings, tagged

| Tag | Finding | Evidence |
|---|---|---|
| NEW | Continuation as a hand-back field: subagent and workflow returns carry no machine "next drivable" field. `agents/deep-research.md:68` has `RECOMMENDED_LEAD_ACTION`, consumed by nothing (`grep -rln RECOMMENDED_LEAD_ACTION hooks scripts bin` is empty). A PostToolUse consumer could arm `session-continue.sh set` from it. | panelist 2 seam 1 |
| NEW | A self-minted ⛔ is the cheapest compliant stop: `cc-decide open --class C --conviction 85` converts every arm to "state ⛔ and close". Filed conviction mass sits at 80 (57) and 85 (59), just under the 90 gate. Proposed: a class-C packet at ≥80 with a reversible default is born class B, so the session continues on the default. | panelist 2 seam 2; `bin/cc-decide:16,182-183` |
| NEW | Docs-only lands as a mechanical "research landed, not enacted" fact: of 72 sessions with a docs-only land in 14 days, 62 (86%) never landed code afterwards. Upper bound about 4 a day; precision needs a `docs/research|docs/plans` path filter and a custody check. | panelist 1 design 2; `~/.claude/land.log` |
| CONFIRMED | The research close is ledger-clean by construction (REMAINDER counts `- [ ]` boxes only) and the rules disarm continuation there (slim:34 research row, slim:217 clear-on-read-only). | README R1, R8 |
| CONFIRMED | Hook remedies offer textual exits, and per-session caps go silent: 14 of 101 sessions exhausted `assert`; 14% of Stops happened post-cap. | README R3; round2/C2 |
| CONFIRMED | `SubagentStop` is unwired on every config dir; `migrations/0014` stages it (operator-only, c10). | `docs/plans/HOOK_SURFACE_100P.md:96` |
| REFUTED | Verdict-no latch as a build (precision, §1.1). | probe above |
| REFUTED | The mid-turn return point as the leak: 75 of 79 completed task-notification turns went on to call a tool. | panelist 2 |
| REFUTED | Task boards as a birth point: 1 of 607 session boards held a non-completed task. | panelist 1 |
| OPEN (operator-only) | A settings-level `type:"prompt"` Stop hook as a standing semantic judge. It contradicts the standing non-action "no LLM judge" (axis 08 F6, 88) and needs `~/.claude/settings.json`. Its premise rests on goals covering 29% of sessions (43 of 150), unverified here. | panelist 2 seam 3 |

## 3. Disposition

- Built: nothing new from this round. C5 and C2a (README §8) are the landed set.
- The two NEW framings (store-act disposition; hand-back continuation field) change the close contract for every
  session or need the mailbox-drain PostToolUse path another session owns. Both are below 90 on net-positive until
  the post-C5 census in §4 says whether the yes-with-undriven shape survives C5.

## 4. Next measurement (the falsifier for "C5 is enough")

After C5 is live for 7 days: count main-transcript closes whose verdict is yes and whose `follow-on:` value is
prose with no id, pane or decision (axis 06 method), and compare with the 30-day baseline in README §3.1. If the
rate does not fall, the store-act disposition is the next build.
