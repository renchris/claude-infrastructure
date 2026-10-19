# C2 judge: false positives and always-firing

Round 2, 2026-10-18 (written 2026-10-19T04:52Z). Adversarial judge, FP lens, on
`round2/C2-per-fact-latch.md`: a per-(fact, HEAD) latch on completion-assert's `assert` class, plus
the stated-⛔ guard on the BLOCKED ON YOU term. The repo was read-only for this pass, and this file is
the only thing I wrote to it. Scratch work is in `/tmp/r2-C2-judge-fp/`: my own IDL re-extract, my own
`annotate.py` run, base and patched copies from `git archive HEAD`, and sandboxed hook probes. Labels:
**[M]** measured (the command is named), **[E]** estimated (the method is named). Load during the pass
was 243-285 on 10 cores [M: `uptime`].

**Verdict: below 90.** I agree with the designer's own verdict, and on this lens C2 is somewhat worse
than the report says. The measurements reproduce exactly, and the net effect on false-positive volume
is real: about 130 blocks go silent, nearly all of them on honest closes, against 41 new ones. But
C2 does not just leave constraint (2) partly unmet. **It creates new violations of it**:
- The 41 blocks it recovers from the cap land on closes that are silent today, and about 90% of
  them are false positives.
- 4 of the 41 are genuine ⛔ operator-decision closes, among them a paid action that auto mode had
  refused. 5 are 📬 acks of peer pings, 4 are conversational answers and about 23 are stated parks
  or waits. I reproduced one of these end to end through the real patched hook.
- §8's claim "⛔-stated closes go from 27 blocks to 0" is wrong. Blocks on those closes go from
  27 to **11**: 7 survive through D1, D4 or a residual fact, and 4 are new.
- The guard has a measured loophole. A `✅ Good to close: yes` verdict with ⛔ on line 2 is
  exonerated, and that is the incident's own shape over an open decision.

Conviction that C2 as written clears 90 on the FP lens: **about 10%**. My conviction in the below-90
verdict: **about 93%** [E: the replay numbers are measured to the unit and reproduced. The FP shares
come from my own hand-read of all 41 recovered closes, plus 4 hook-level probes].

## 1. What I re-ran

| Check | How | Result |
|---|---|---|
| IDL window | `gzip -dc ~/.claude/autonomy/idl.jsonl.2026*.gz; cat idl.jsonl`, grep completion-assert, `jq` on the window 10-05T01Z..10-19T01Z | 10,089 records, 466 fired, 492 `capped:3>=3`, 345 `class:assert` fires. My `ca14.jsonl` is byte-identical to the designer's [M: `cmp`] |
| Repeat spend | `jq` + `python3 -I` over fact-bearing assert fires | 331 fires in 146 sessions, 70 sessions with 3 or more; 144 exact and 165 normalized repeats. Matches §2.1 [M] |
| session-continue extract | same pipeline | **7,291** records against the designer's 6,506 (theirs is a subset). The replay result is identical on both [M: `sim2.py` run on each] |
| Annotation | the designer's `annotate.py`, re-run on my extract and a fresh transcript index (1,732 files) | 837 events, all matched to a close [M] |
| Cap replay | `sim2.py --key head --k 1`, with and without `--guard blocked` | no guard: 345 → 265, 43 recovered, 32 sessions. Guard: 345 → **256**, **41** recovered, 31 sessions. Matches §2.2 and §7 [E: counterfactual replay, as the designer labels it] |
| Key sensitivity | the same, for `sess`/`exact`/`head` at K=1 | 220 / 248 / 256 blocks, 29 / 39 / 41 recovered. The net reduction holds whichever key is chosen [E] |
| Patch | `patch -p1` of `/tmp/r2-C2/C2-hook.diff` onto `git archive HEAD` | applies. The result is `diff -q`-identical to the designer's `final/` [M] |
| Other `.fired` readers | `grep -rn` over hooks, scripts, bin, lib and tests | no reader outside completion-assert itself, so the third column cannot break a consumer [M] |
| bats | `CC_BATS_QOS=off taskpolicy -c utility bats --filter '⛔ STATED\|FACT LATCH: a close that ALSO'` on my patched copy | see §7 |

## 2. The 41 blocks C2 adds, hand-read (all of them)

These are evaluations that are `capped:3>=3` today, so the operator sees nothing, and that fire under
C2 [E: `sim2.py -dump`, then the first 7 lines of each close printed by `closeat.py` and read one by
one]. My count agrees with the designer's on precision but not on what the false positives are:

| class | n | sessions (ts) |
|---|---|---|
| plausible true positive | ~3.5 (5 items, two of them half) | 36b81fea 03:56 `hedge`; 2328e32b 07:03 (an open decision buried in ¶5); 5759497b 14:27 (the incident, wrong arm); e7666118 06:16, "Nothing here needs you tonight" over an open decision (½); e7ed8439 22:38, "the Otto call is yours", a phone call (½) |
| **genuine ⛔ operator decision** | **4** | e131c8d2 10:23 "⛔ Blocked, need your call"; 9fd1dbab 06:52 "⛔ Blocked — need your call"; 69778275 23:52 "⛔ Blocked — need your call: fire 4 paid draws … blocked in auto mode, so you run the command"; 6069b9d3 19:58 "❌ Good to close: no … ⛔ Should the log keep entries forever" (its residual dirty-tree fact is a report edit "parked uncommitted because you rejected the push") |
| 📬 ack of a peer ping | 5 | b351c528 05:19; 6207f5b4 09:32; e739e5b5 03:35, 07:30, 10:31 (two of these also pass the operator push-approval prompts on) |
| conversational answer | 4 | 46a0fdc8 "Yes, it's correct. Leave it as it is." (a calendar time zone); e3fb3dc4 19:37 "Yes, pane 343 is a duplicate"; 69778275 00:19 "only moet-nectar-4.webp makes the cut"; e7659abe 15:00 the eviction research answer |
| stated park, wait, in-flight land or honest no | ~23 | e.g. a3cd5943 20:29 "I'm holding the push **on purpose** until the full gate run passes"; 3776f14b "Not done yet"; 7046d8d0, f7351f3b ×2, 22a76c8a, d8964eb2 (❌ no-verdicts); 5a6b8a40, 4f7d7e9e, 407a191d ×2, 6db28068, c577dd04 (waits with the watcher armed) |

The genuine-decision row is the one that matters for constraint (2). Each of the four draws a block it
does not draw today. Three of them get D1's text: "An operator-only step is not an escape hatch … If you
can run it, run it now". On 69778275 that pushes the agent to retry a paid action auto mode had already
refused, the same "worse than useless" failure §3 attributes to the latch's *removed* repeats.

**End to end through the real hook** [M: `/tmp/r2-C2-judge-fp/bin/probe.sh <base|final> recov`,
`/bin/bash` 3.2, every state seam sandboxed]. The ledger stub is ⛔ (BLOCKED=1). Three non-⛔-led status
closes ("Nothing has landed yet; the watcher is armed") come first, then e131c8d2's real ⛔ close:

| Stop | base | final |
|---|---|---|
| 1-3 status closes | `fired` ledger 1/3, 2/3, 3/3 | `fired` 1/3, then `latched-same-fact` ×2 |
| 4 genuine ⛔ decision close | `capped:3>=3` (silent) | **`fired` handoff 2/3** |

So the freed slot goes to blocking the one close in the sequence that is an operator decision.

## 3. The stated-⛔ guard: 27 → 11, not 27 → 0

§2.3 and §7 count BLOCKED ON YOU **convictions** on ⛔-stated closes, which do go 27 → 0. §8 row 2 turns
that into "⛔-stated closes go from 27 blocks to 0", and that is not what happens [E: tally of
`guarded` × outcome in my `sim2.py --guard blocked -dump`]:

| ⛔-stated evaluation (rung line carries ⛔, BLOCKED in facts) | n |
|---|---|
| fired today → silent under C2 | 18 (+2 fact-latched) |
| fired today → **still fires** (D1 `handoff`, D4 `offer`, or another ledger fact) | **7**: 99b5cd2f, 9fd1dbab 06:51, eedec145 17:33, 14233392 06:09, baf8f054 14:54, 69778275 15:59, 5059949f 06:57 |
| capped today → **newly fires** | **4**: the four in §2 |
| capped today → silent | 37 |

Blocks on genuine ⛔ decision closes therefore go from 27 to 11 per 14 days. The hook confirms it: the
real texts of e131c8d2, 69778275 and 9fd1dbab, on a fresh budget, fire `ledger+handoff` on base and
**`handoff`** on final [M: `probe.sh` scenarios `e131`, `6977`, `9fd1`]. The guard changes the message;
it does not stop the block. Exempting D1 when the rung line states ⛔ and the ledger's BLOCKED count
proves the decision is filed would cover 3 of the 4 new blocks and 4 of the 7 that survive [E: arm
strings in the table].

Open risk 4 is also understated. It says the glyph-only guard misses "one" decision close (6069b9d3).
Measured, 28 actual BLOCKED fires have no ⛔ on the D6 rung line [M: `python3 -I` over `events.jsonl`].
At least 5 of them state the open operator decision in words: ecb81dfc 08:33 "three of my questions to
you are still open"; 3df4b1b4 14:04 "❌ Good to close: no … round 1 waits on your OpenAI choice";
c294596e 04:49; 6069b9d3 17:59 and 18:21. The 6069b9d3 close that the risk names is the 19:58 one, and
the guard **does** cover that one: ⛔ is on line 2 under a verdict line 1. Its block comes from the
residual dirty-tree fact.

## 4. The guard's loophole: containment, not lead, and any verdict polarity

The guard asks only that the rung line *contain* ⛔, and its verdict-line clause accepts a **yes**
verdict. Both shapes fire on base and go silent on final [M: `probe.sh` scenarios `quote` and `yesv`]:
- `✅ Complete & live on trunk — landed, all green; the ⛔ from this morning no longer applies.`
- `✅ Good to close: yes. Everything is landed and live.` / `⛔ One decision of mine is still open …`

The second shape is real. 2328e32b 07:24 and 07:54 read "✅ Good to close: yes. Nothing of mine is open.
Follow-on: the Panda 2 decision below." over `⛔ Your call: …` on line 2, which is the incident's exact
shape over an open decision. The guard exonerates both [M: the same scan]. Both are `capped` today, so
the live effect is nil, but the guard writes the exoneration into the design.

A lead-anchored guard costs nothing. The rule would be: line 1 *leads* with ⛔, or line 1 is a
**NO**-polarity verdict and line 2 leads with ⛔. It keeps 66 of the 68 ⛔-stated evaluations (fired
plus capped), and the only 2 it drops are those two yes-verdict closes [M: `python3 -I` scan with
`lstrip('*#>-• _`')`]. The polarity read should come from `close_verdict_polarity` in
`hooks/lib/close-shape.sh`, not a new regex (constraint 6).

## 5. Other things I checked, and what holds

- **No new arm becomes reachable.** When the guard sets `contra=0`, D6 and D7 are still gated to
  RUNG ∈ {✅, 👤} and 👤 (`completion-assert.sh:1428-1429`, `:1537`), so a ⛔ close cannot draw a shape
  or act demand. The sim's "guard empties the facts ⇒ abstain unless a prose arm fired" matches the
  hook [M: the `quote` probe abstains `ledger-clean:exonerated:blocked-rung-stated`].
- **The silenced set is false-positive.** Of the 130 fires C2 silences, the 4 led by ✅/"yes" are on
  89-90-file shared dirty trees with authorship UNRESOLVED (66936177, 99e83151, e7659abe ×2) [M: `jq`
  on their facts]. All 14 prose, non-park ones I read are status, conversational or honest not-done
  closes [E: hand-read of l1].
- **Always-firing (constraint 1): met.** C2 adds no firing condition, and every recovered fire is
  still bounded by the unchanged per-session cap of 3. No session can see more assert blocks than it
  can today.
- **Stated park, first conviction: unchanged, not fixed.** a3cd5943's "holding the push on purpose"
  fires on base and on final [M: `probe.sh park`]. That is the designer's open risk 1, confirmed.
- **The latch cannot read text** (efficacy, noted only). A re-asserted false "✅ Done — everything is
  landed and live" on the same unlanded fact at the same HEAD is `latched-same-fact` on final and
  fires 3/3 on base [M: `probe.sh redone`]. In 14 days the only such cases were the 89-file trees
  above, so today this costs nothing measurable.

## 6. Constraints, on this lens

| # | designer | judge |
|---|---|---|
| 1 silent when nothing is drivable | met | **met**: bounded by the unchanged cap; no new condition |
| 2 never block a ⛔ decision or a stated park | partly met | **not met, and newly violated**: 4 new blocks on genuine ⛔ decisions, about 23 on parks, waits and honest-no closes that are silent today. Blocks on ⛔-stated closes go 27 → 11, not 0 |
| 3-5 | met | not re-litigated (outside this lens); no settings.json, rule-text or forbidden-file touch, by `diff` |
| 6 one matcher per concept | met | met for the rung line. The fix in §4 must reuse `close_verdict_polarity` |

## 7. bats (my patched copy)

`CC_BATS_QOS=off taskpolicy -c utility bats --formatter tap --filter '⛔ STATED|FACT LATCH: a close that ALSO'
tests/completion-assert.bats`: **1..6, 6 ok, 0 not ok**, 254 s [M]. These are the guard's own five
tests and the prose-not-latched test, and they are green as the designer reports. They pass because
they do not test the cases in §2-§4. None of them puts a D1 phrase on a ⛔-led close, none puts a
yes verdict over a ⛔ line 2, and none drives a recovered slot into a genuine decision close. I did not
re-run the full suite: the designer's composition argument is outside this lens.

## 8. What C2 needs before it can be re-judged on this lens

1. **Stop the recovered budget landing on ledger-only fires.** 33 of the 41 recovered fires are
   ledger-only (19 🔧, 8 ⛔, 6 📦), and they carry almost all the false positives. One option: count
   a `latched-same-fact` evaluation against a ledger-only fire's budget, as today, while prose arms
   (D1/D3/D4/D5) draw on the slot the latch saved. That keeps the incident's `handoff` recovery and
   cuts the new blocks from 41 to 8 [E: arm strings in the recovered set]. It has to be measured
   against the D7 CLASS pin (`tests/completion-assert.bats:1894`).
2. **Exempt D1 on a ⛔-stated close whose ledger BLOCKED count is greater than 0.** The decision is
   already filed through cc-decide, so "file each operator-only step" is answered. That removes 3 of
   the 4 new ⛔-decision blocks and 4 of the 7 that survive [E].
3. **Anchor the guard to the lead glyph, and require NO polarity under a verdict line** (§4).
   Measured cost: 0 genuine closes lost and 2 incident-shaped yes-verdicts no longer exonerated.
4. **Correct §8 row 2 and open risk 4** to the measured numbers in §3.
5. Re-run the replay and a fresh hand-read of whatever set the change recovers. The bar for this
   lens is that no genuine ⛔ decision and no stated park draws a block that is silent today.
