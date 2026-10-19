# C1 judge (false-positive lens): `last_assistant_message` first

Round 2, 2026-10-18. Adversarial judge, lens: false positives and always-firing. I made no repo edits. Scratch work
is under `/tmp/r2-C1-judge-fp/`: my own `git archive HEAD` copy (72a18b575, hooks unchanged since the designer's
f12dd4b12), with `/tmp/r2-C1/C1-full.diff` applied (`git apply --check` ok, byte-identical to `/tmp/r2-C1/patched`).
Every hook run used a fresh sandbox run dir and a sandboxed HOME. Unlike the designer's runner, I left the operator
kill-switch **on**: `/tmp/r2-C1/scripts/run-hook.sh` sets `CC_CLOSE_KILLSWITCH=0`.

**Verdict: below-90.** The race is real, and I corroborate it on the second hook (§1). But "correct **and
net-positive** as specified, 93%" does not survive the FP lens. The finals C1 un-blinds are mostly interim
"waiting on X, watcher armed" turns and Q&A answers. The arms that would now judge them have low precision on
exactly those states. The report's constraint-1 and constraint-2 claims rest on "no arm changes", which says
nothing about the extra exposure. My estimate of C1's conviction as specified is about 65-70%.

## 1. What I confirm

- **The anti-deference hook shows the same race, on its own data.** I matched one anti-deference IDL row per
  Stop (same window rule as `analyze2.py`) for 7,799 of 7,847 Stops. I then ran the hook's text predicates on the
  final and on the previous message. The predicates are a Python port, `scripts/adpred.py`; it agrees with the
  exact bash extraction, `scripts/adpred.sh` (lines 165-319 and 453-471 of the hook), on **10,288 of 10,288**
  texts. 271 Stops discriminate. On 62 of them the live verdict is the previous message's: **22.9%** (measured).
  That is independent of the designer's completion-assert 20.3%.
- **The designer's breakdown reproduces from `cases.json`:** 369 = 271 + 7 + 19 + 11 + 35 + 22 + 2 + 2 (measured).
- **The 11 `latched-already-fired` cases do not become re-fire loops.** In all 11, the patched hook's final
  abstains `no-close-tell` (measured, `scripts/replay.py` → `stale.jsonl`).

## 2. What C1 newly exposes, and what the arms do with it

### 2.1 The un-blinded finals are mostly waiting turns (measured)

These are the 278 stale-read "misses", where the final passes the gate.
- **191 (69%)** have a machine message as the next user record: a task notification, peer mail, a teammate
  message or a handoff. So the agent was waiting on background work, as intended.
- 50 are followed by a new operator ask or question, and 37 by nothing.
- A push-to-continue regex matches **0** operator replies. Hand-reading the 50, about 5 show the operator having
  to push or to ask for the verdict (rs13, rs05, k2519, k576, k790).
- By regex on the text, 50% carry a waiting or armed-watcher phrase, against 41% in the final-read past-gate group.
  ⛔/decision wording appears in **11% against 36%**, and short messages (<300 chars) are 27% against 41%.

So the two groups differ in what they say. The report assumes flush timing does not depend on what the two
messages say, and that assumption is measurably false. The 63-fire projection then carries the wrong arm mix.

### 2.2 The sandbox replay: text-level would-fire rate (measured, upper bound)

I ran the patched hooks on all 369 stale-read Stops, with the transcript minus the final plus the payload. The
sandbox repo is clean and landed, and no session is a fired peer.
- **completion-assert fires on 193 of 278 (69%):** 172 pure D6 `shape`, 7 handoff+shape, 5 hedge+shape,
  5 handoff, 2 hedge and 2 offer+shape.
- **anti-deference fires on 23** (18 opaque-identifier).

This overstates live, because live fires depend on the rung, origin-identity and caps. On a 160-Stop sample of the
final-read past-gate group (`final.jsonl`), the sandbox fires 119 where live fired 40 and capped 58. Its value is
qualitative: on a clean ✅ ledger, about 2 in 3 newly visible finals fail D6's close contract, so they are shape
demands where nothing drivable remains.

### 2.3 Live precision of the fires C1 would add (hand-labelled, n=61 of 182)

The designer projects about 63 new completion-assert fires: 22.8%, i.e. 182 fired of 799 final-read past-gate
Stops, applied to the 278 misses. That rate is computed after caps; before caps, 494 of 799 (62%) would fire. The
182 fires were never labelled. I labelled all 25 at the ⛔ rung and stratified samples of the rest (`livefires.json`,
`livefires-sample.txt`). TP means the block led to drivable work: a commit, a land, a converge, a filed decision,
or an investigation the agent agreed it owed.

| Stratum (live arm / rung) | In 182 | Labelled | TP | Neutral (poll of a running job) | FP / no drivable work |
|---|---|---|---|---|---|
| ledger at ⛔ (all) | 25 | 25 | 4 | 6 | **15** (11 are correct ⛔ closes: "❌ Good to close: no … ⛔ Blocked, need your call", k128, k130, k164, k439, k2203, k2258, k2352, k2355, k6840, k7215, k7258) |
| ledger at 🔧 | 71 | 12 | 2 | 0 | 10 (waiting on dispatched panes with the watcher armed; 103 dirty files "not mine"; a **write-free** Q&A, k2861) |
| ledger at 📦 | 40 | 10 | 2 | 2 | 6 (land queued on a lock or load; stated parks required by the brief, k2953, k5530) |
| shape / act / handoff at ✅ or 👤 | 46 | 14 | 0 | 1 | 13 (re-close with a rewritten line 1; honest "✅ safe to close", k4577; **peer-ping acks** "📬 pane 261: …", k4260, k7014; D1 on steps already filed, k6344) |

Weighted to the 182 live fires: **about 13% TP, about 10% neutral, about 77% FP** (estimated from the labelled
strata). The correct-⛔ blocks pass the gate on a body CLOSE token, then convict on `RUNG=⛔` (`completion-assert.sh:1131`).
GENUINE lacks "need your call". The comment at `:1126` says a correct ⛔ close "abstains at the close-tell gate";
11 live counter-examples say otherwise. The designer's rs01 (a D6 nudge on a legitimate value fork) belongs to the
same class.

### 2.4 anti-deference: the side the report did not measure

The report checks only `TELLS` (7 Stops). Counting every text arm (measured, `ad-disc.json`):
- **55 stale-read Stops** have a final that fires an arm the previous message does not, with the live result
  `no-tell`. By arm: opaque-identifier 49, peer 3, category 1, pane 1, deference 1.
- 48 of the 55 have cap headroom.
- C1 removes 7 wrong-target opaque-identifier fires.

Of 16 sampled opaque-identifier adds, **13-14 are FPs**. In most, the id is explained in the same sentence, in a form
`OPAQUE_GLOSS_RE` does not recognise: "(decision \`1bec72cbb3b8\`):", "This is decision \`58d62776eb1f\`" after the
question, "filed as \`8cb6c23f59c1\`", "(backlog row \`29cc988519e8\`)". In others it is a quoted state render or a
command argument (`cc-do 29cc988519e8`). Examples:
- honest "✅ Good to close: yes. Nothing of mine is open" (k7629);
- "I'm on standby … Nothing is in flight" (k2198, fire confirmed with the full patched hook);
- ⛔ decision closes (k7214, k3788, k3527).

### 2.5 Net effect over 7.5 days (estimated from the measured counts above)

Live fires in the window were completion-assert 352 and anti-deference 174 (measured, IDL).

| | Added by C1 | Removed by C1 | Net |
|---|---|---|---|
| completion-assert | ~63 (13% TP) | 19 wrong-target (about 5 of 19 still led to work: k2944, k3483, k3500, k409, k7208) | +44 (+12%) |
| anti-deference | ~48 (mostly opaque-identifier, ~85% FP) | 7 | +41 (+24%) |
| **FP blocks** | **~95** | **~20** | **≈ +75 (~10/day fleet-wide)** |
| TP blocks | ~10 | ~5 | ≈ +5 |

That is not always-firing, but it is a clear rise in FP blocks on turns where nothing drivable remains, on genuine
⛔ closes and on peer-ping acks. Constraint (1) asks for silence there, and constraint (2) forbids blocking a
genuine ⛔. C1 also leaves the incident close itself unchanged (the report says so in §6).

## 3. Specific report claims that do not hold

1. Constraint 1 ("no new arm and no new message, silent when nothing drivable remains"): **unsupported**. About 77%
   of the fires C1 adds land where nothing drivable remains.
2. Constraint 2 ("GENUINE … now reads the message that contains the ask"): **contradicted**. The ⛔-rung term blocks
   correct ⛔ closes 11 or more times in the 25 live examples, and C1 exposes about 20% more finals to it.
3. "Those fires carry the existing arms' precision": true, but that precision was never measured. Measured here,
   it is about 13%.
4. anti-deference corroboration on "7 Stops": the real exposure is 55 Stops, mostly opaque-identifier.
5. Projection basis: the report treats the 278 and the 799 as alike, but their composition differs (§2.1).
6. Sandbox fidelity: the designer's replays disable the kill-switch. That is harmless for the 6/6 reproduction,
   but it is not the live path.

## 4. What would get C1 above 90 under this lens

- **Land C1 together with FP guards, or behind a shadow period.** Log the payload-source verdict to the IDL (a
  `msg_src` field plus the would-be disposition) while blocking stays on today's path. Then measure precision on
  the post-land census before the switch is flipped.
- **Guard the ⛔-rung term.** Abstain when line 1 is a no-verdict (`CA_VERDICT_NO` / `close_verdict_polarity`) or
  leads with ⛔. That reuses the existing matcher, so it adds no new concept.
- **Widen the opaque-identifier gloss.** Accept "(decision|row|backlog|packet) \`id\`", an id that follows a question
  or a bold title on the same line, and ids inside a `▶ Run this` command span.
- **Treat an armed-wake interim turn as a stated park for the ledger and D6 arms.** That covers a watcher, an
  R-PING disposition or a queued land, read from the existing wake or custody state, not from new prose matching.
- **Re-measure after the guards:** label at least 50 of the fires that would be added, require TP at or above the
  current baseline, and count net FP blocks per day.
