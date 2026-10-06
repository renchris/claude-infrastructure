# E1h critic: steelman of the non-recommended options for row 15 (2026-10-06 ~01:40 CDT)

Read-only critic. No classifier call was made. No sealed set, key, `tuning-v2.jsonl` or miner prompt was opened
or printed. No tracked file was edited and nothing was committed. Every number is labeled **measured** (with the
command or file it came from) or **estimated** (with the method used).

**Assumption about the recommendation.** The digest does not state the recommendation. The task lists the options
it does not recommend, so I take the recommended option to be the **precision-pass**: change the join rule on the
current pair of haiku calls (careful-confirms, or a variant of it), pre-register it on tuning data plus a fresh
HMAC-split `other` tuning set, then do a composite read (v4 `other` read for the first time, plus a disclosed second
read of v3's re-ask strata). If the recommendation already uses a stronger model as the relay checker, §2 and §3.1
below mostly agree with it.

**Deviation.** I did not run `git pull --ff-only`, because it is a git mutation. `git ls-remote origin main` shows
`b87e6da64`, one commit ahead of the worktree's `ff3e87fb7`. That commit only touches
`docs/plans/SESSIONSTART_READOUT.md` (measured: `git show --stat b87e6da64`), so nothing this critique reads is
stale.

---

## 1. What any option has to clear on v3-like `other`

- **The target** (measured, from E1g's record and `reading-v3-2026-10-05.jsonl`):
  - 113/148 now; a pass needs 134, so the number of misses must fall from 35 to 14.
  - The router relayed 36 prompts: 26 from the fast call and 10 from the careful call.
  - Let *c* be the number of correct relays (*c* ≥ 1). Then wrong relays = 36 − *c*, and wrong non-relay labels =
    *c* − 1.
- **Non-relay labeling is already good** (measured algebra on the published counts):
  - The router's 112 non-relay labels on `other` were exact (113 − *c*)/112 of the time.
  - That is ≥ 0.95 if *c* ≤ 7. On v1, 1 of 22 agreed `other` rows had relay gold, which suggests *c* of about 7
    (estimated).
  - **So the `other` failure is almost entirely relay votes.**
- **How far relays must fall** (estimated):
  - Best case, where every removed relay was wrong and gets the exact agreed label: removing *R* relays gives 113 + *R*.
    Passing needs *R* ≥ 21, i.e. **at most about 15 relays left out of 36, a cut of at least 58%**.
  - If 90% of the demoted prompts get the exact label: at most about 13 relays left.
- **Correction to the brief's framing: v1 cannot predict v3's `other`, because the two are different populations**
  (measured: in-memory `heldout-candidates.build()` over `~/.claude*/projects/*/*.jsonl` (400 d) plus
  `~/.claude*/history.jsonl`, all caps 10⁷; counts only, no prompt printed or written; and tuning.jsonl, which v1 tuning
  data may read):

  | `other` population | n | from history | ≤ 80 chars | > 300 chars | `!`-prefixed (bash-mode lines) | ≤ 3 words | paste/image placeholder |
  |---|---|---|---|---|---|---|---|
  | candidate pool that v3 and v4 sample from | 25,458 | **20,838 (82%)** | **9,022 (35%)** | 4,929 (19%) | 1,101 (4.3%) | 1,227 (4.8%) | 1,836 (7.2%) |
  | tuning v1 `other` | 30 | **0** | **3 (10%)** | 18 (60%) | 0 | 0 | — |

  - v1 was mined from transcripts only, before E1c added the history store. A sha-order sample of the pool should
    look like the pool (estimated). So v3's `other` is probably about 80% history `display` strings, and a third
    of it is short, context-free prompts.
  - On v1's 21 agreed non-relay `other` rows, every thinking-off arm relayed 0. If v3's 17.6% fast-relay rate held
    there, a run with 0 of 21 would have probability 0.824²¹ = 0.017 (estimated). The gap is a population shift,
    not chance.
- **Both leading options rest on the same 56 rows.** The precision-pass and the stronger-model option draw their
  over-flagging evidence from v1's 56 rows where neither rater says relay:
  - 25 of the 56 are `other`-stratum transcript prose; 24 are regex-missed and 7 regex-matched (measured).
  - The 7 rows haiku relays and sonnet does not are **6 regex-missed (35, 37, 49, 51, 56, 57) and 1 `other`
    (row 89)** (measured).
  - So transfer to v3-like `other` is unmeasured for both options. The comparison below is fair only because both
    are scored on the same rows.

## 2. A new measurement: the careful call shares the fast call's errors, so a veto has little to act on

Measured (E1c `tune-2reps.json`, fast = `off-e1b`, careful = `on-pre`, paired by row and rep, on the 56 neither-relay
rows, 112 calls):

- The haiku fast call over-flags in **14 of 112** calls.
- On those 14 calls, the careful call within 8.5 s **confirmed 6, vetoed 2, and was silent on 6**.
- Given unlimited time, the careful call's own label was a **relay on 9 of 14** (Wilson 0.39–0.84). It was a
  non-relay, so a veto was possible, on only **5 of 14** (0.16–0.61).
- The careful call also relays on its own: 11 of 112 within 8.5 s and 17 of 112 unbounded, as much as the fast
  call's 14 of 112.

**Both calls are haiku, both read the same route definitions, and they flag the same prompts.** The confirm-rule
replay found "1 call to act on" because it scored only the agreed non-relay rows. On the hard negatives the error
correlation is plain.

**Per-rule estimate on v3 `other`.** Method:
- Start from v3's measured counts: fast relays 26, careful-only relays 10, and the careful call answering within
  8.5 s on 0.80 of `other` calls.
- Multiply by the tuning conditional rates above: veto-capable share *v* = 5/14 (0.16–0.61), and sonnet/haiku
  over-flag ratio *r* = 1/8 (95% CI about 0.003–0.72, from 1 against 8 of 56).
- The score assumes 90% of the demoted prompts get the exact label, and *c* = 1. That is the most favourable case
  for every rule. A larger *c* lowers every row: for sonnet fast only, *c* = 7 gives 0.92.
- All values are estimated.

| rule | relays left of 36 (point; range over the CI) | `other` (point; range) | keeps sensitivity on tuning? |
|---|---|---|---|
| (a) as built (union) | 36 (measured) | 0.76 (measured) | 19/26 |
| (b) careful-confirms, careful-only relays stand | 29 (23–33) | **0.81** (0.78–0.84) | 19/26 |
| (c) careful-authoritative | 29 (23–33) | **≤ 0.81** (it also hands the non-relay labels to the careful call, which read 0.72–0.88 on v2) | 19/26 |
| (b') confirms, careful-only relays dropped | 19 (13–23) | **0.87** (0.84–0.90) | **10/26** (E1g's bar was 17) |
| (d) strict intersection | 13 relays + 5 fallbacks | **0.87** (0.84–0.90) | 9/26, fallbacks +9/192 |
| (e) haiku fast only | 26 | 0.82 (E1g: at most 0.83) | 10/26 |
| sonnet fast + haiku careful (union) | 25 | **0.83** | 20–22/26 est. (10–11/13 per rep) |
| **sonnet fast only** | **5** (1–26) | **0.95** (0.82–0.98); 0.92 at *c* = 7 | 14/26 est. (7/13 in 1 rep) |
| sonnet fast, haiku careful may only veto | 4 | ≈0.95 | ≤ 14/26 |

Reading the table:
- **No join rule on the haiku pair that keeps sensitivity reaches 0.90, at any point in the CI.**
  - (b) needs the careful call to veto essentially every fast relay it answers. Even with *v* = 1, (b) leaves
    10 + 26 × 0.2 ≈ 15 relays and reads about 0.89.
  - (b') and (d) reach 0.90 only at the top of the *v* interval. They also give back the borderline sensitivity
    that was the careful call's reason to exist.
- The configurations that pass on point estimates share one property: **a model much more precise than haiku is
  the only relay voter.**
- Even sonnet's pass is plausible, not established. It breaks even at *r* ≈ 0.33 (*c* = 1) or *r* ≈ 0.18
  (*c* = 7), against a measured *r* of 0.125 whose CI runs to 0.72.

## 3. Steelman of each option

### 3.1 Stronger model (sonnet-5-5, thinking off). The strongest alternative, and in my reading the better pick
- **Best case.**
  - It is the only lever with a measured effect on the failure mode. Same rows, same minute: 8/56 → 1/56. Paired by
    row it is 7–0, exact sign test p = 0.016 (measured: stronger-model-live).
  - The tighter haiku brief moved it only to 5/56.
  - The precision-pass's mechanism, a haiku veto, is contradicted on those same rows (§2).
  - It fits inside the time limit. Cold median 2.77 s, p90 4.71 s (measured). Warm about 1.7 s, p90 about 3.5 s
    (estimated). Inside 8.5 s.
  - The ruling cost is about the same as the precision-pass's. Both need an operator ruling for the wave and for the
    second read. This option adds one named-section edit (§4.1 "the classifier is the model config's
    `haiku_latest`", REPORT:775; BUILD:488), made "from measured results" as ruling 8 requires, and 1/56 against
    8/56 is a measured result.
  - Changing the model also makes the v3 second read *less* biased: v3 says nothing about sonnet beyond the decision
    to select it.
- **What actually limits it.**
  - **Recall.** 25/26 in one rep: row 29, regex-missed, which the haiku careful call caught.
    - If sonnet's true recall is 0.96, the chance of passing all three v3 re-ask strata on a re-read is **0.48**
      (estimated: exact binomial, 45/47 · 24/25 · 2/2). It is 0.82 at 0.98 and 0.94 at 0.99.
    - The union's measured 73/74 is safer on recall.
  - **Sensitivity.** 7/13 borderline per rep, against 10–11/13 for the union and E1g's bar of 8.5/13.
  - **Transfer to `other`.** It rests on one `other`-stratum row (row 89). The 1/56 is mostly regex-missed
    after-claim prompts; v3's `other` is about 82% short history strings (§1).
  - **Tails.** One cold call took 20.4 s and one sister-arm call exited with rc 1, in 192 sonnet calls. The CLI
    printed an unrecognized-model warning, and the daemon's `ping` config hash is unchecked with sonnet.
  - **Cost.** Unmeasured. It is not only per prompt: the warm daemon's canary runs one classification per kind every
    900 s (`classifier-warm.py:90`), so at least 96 sonnet calls a day even with no program active (estimated from the
    cadence). The operator's weekly limits are a live constraint: this run is a limit-recover ingest, and trunk's
    newest commit is about weekly-limit headroom.

### 3.2 Lower the floor
- **Best case.**
  - 0.90 is not method text. §10 item 11 (REPORT:1379) names no number. It was set at build (`92cf72197`) and is
    labeled an assumed input until §6.6 calibration.
  - The method's own asymmetry ranks a missed ask above a lost turn (REPORT:783-785).
  - A false relay never unlocks research, so G1 holds whatever the floor is.
  - At n = 148, a configuration whose true rate is exactly 0.90 passes only about 48% of the time
    (method-second-read). A floor stated as a point estimate is a coin flip for a borderline configuration.
- **Why it loses.**
  - §10 item 11's stated purpose is to fail "an … over-labeling router". That is exactly what v3 measured: at least
    29 of the 35 misses are relays if *c* ≤ 7 (estimated).
  - Passing v3 needs a floor at or below 0.76, chosen after seeing 0.76. That fits the instrument to the result.
  - It would accept about 0.24 false relays per ordinary prompt: about 3 a day at TM2's planning pace and 8–10 a day
    in a build phase (false-relay-cost, estimated).
  - Each false relay costs:
    - a turn with no answer;
    - up to 2 forced Stop-check re-answers;
    - every background agent in the session stalled until the operator types again.
- **The only defensible form.** A floor (or a confidence-bounded rule) fixed from a cost argument *before* a fresh
  read. Even then it rescues nothing on v3.

### 3.3 Run uncertified
- **Best case.**
  - The half of row 15 the method exists for passed on a pre-registered single read: 73/74 relay-gold relayed and 0
    fallbacks.
  - The failing half costs operator time, not research integrity.
  - Living with the router would measure the false-relay rate on *live* program prompts. The instrument cannot do
    that, given its 82%-history `other` frame.
- **Why it loses.**
  - The method text forbids it: "no certificate issues until the router is fixed as tooling" (REPORT:1078). Row 15
    is PASS/FAIL only, and it is not in the "stated, never blocking" list (REPORT:608).
  - Getting there is a rubric (b) change plus ruling 8 plus an operator ruling.
  - It buys nothing today. 0 programs are in a blocking state; TM2 is `registered`; E2 is still running; E3 and E4
    are ahead (BUILD:1046-1056, 1316). No certificate is waiting on row 15 this week.

### 3.4 Wait for population (a fully fresh v4)
- **Best case.** Clean under every rule: no second read, and no subset-seal tooling.
- **Why it loses.**
  - Pushback binds the date. The current rate is 0.25/wk (1 in 4 weeks, none since 2026-09-14), which gives about
    Feb–Apr 2027 at best, about a year at the year-average rate, and years at the current rate (population-rate,
    estimated).
  - Fresh regex-missed must be mined within about 8 weeks of its first prompt, so it cannot sit and wait for pushback.
  - Waiting fixes nothing in the classifier. The only failing stratum, `other`, is the one that can be made fresh in
    under a week (about 1,000 a week).
- **The salvageable part.** A hybrid:
  - fresh `other` and regex-matched now (about 419 regex-matched unused);
  - fresh regex-missed in about 4–9 weeks;
  - only v3's 2 counted pushback items on the second read.

  TM2's gate is not near, so this costs little calendar time.

### 3.5 Bound the cost of a false relay (new)
- **Best case.** It is cheap, independent of row 15, and fixes real defects whatever else is chosen:
  - (c) an operator-visible notice on each relay turn;
  - (d) no relay label carried into envelope or subagent turns, following §10 item 3's precedent for fallback labels;
  - (e) narrow `--requires-gate`. Today any typed `--requires-gate <any slug>` labels the turn `work-order`, which
    unlocks every tool including research (router.py:105, 528-530). That is a G1 hole, not only a cost issue.
  - (b) the one-word `misrouted` override, limited to `other` rights, cuts the per-incident cost from "rephrase, which
    is re-relayed about 2 times in 7, and stalled agents" to one word.
- **Limit.** It does not change the rate, so row 15 still fails. It complements the other options; it does not
  replace them.

### 3.6 A risk the brief did not raise: row 15 scores over-relay only in `other`
- By subtraction from E1g's record (estimated), v3 had about 26 false relays among 155 non-relay-gold regex-missed
  prompts and about 11 among 67 regex-matched.
- A fix keyed to the miner's regexes, for example one that lets careful-only relays stand only on GAP/WIDE/after-claim
  prompts, would pass `other` by construction while leaving the operator's cost in place.
- Any pre-registered rule should also *state* the false-relay rate on agreed non-relay items in every stratum, and
  `other` split by source (history or transcript). Neither needs to block.

## 4. What a careful operator would pick, concretely

1. **Now:** land the cost bounds (c), (d) and (e) (one tooling wave, red-then-green tests). Put (b) in with the §4.2
   text change. None of this touches row 15, and (e) closes a guard hole.
2. **One pre-registered tuning run, the run that both the precision-pass and the stronger-model option lack:**
   - **Data:**
     - an HMAC tuning split of fresh `other` from the current pool, about 300 sealed-equivalent for about 160 agreed
       at v3's 0.54 agreement rate, labeled by the same two raters;
     - plus a fresh regex-matched tuning split for recall (419 unused);
     - plus v1's 96 rows for borderline.
   - **Arms:** haiku-off-e1b, on-pre, sonnet-off-e1b, and sonnet thinking-on if it fits 8.5 s. Every call runs to
     completion, so all join rules in §2 (union, b, b', d, sonnet-only, sonnet + haiku veto) replay offline from the
     one dataset. This is the missing datum the confirm-rule replay names.
   - **Pre-registered rule:**
     - `other` ≥ 0.93 on fresh tuning. That is margin for a 0.90 read: at n = 148, a true 0.92 passes 0.79
       (estimated).
     - recall ≥ 0.98 on the pooled tuning relay rows, because the re-read's joint pass is 0.48 at 0.96 and 0.82 at
       0.98.
     - a stated borderline floor;
     - latency within 8.5 s.
3. **Composite read:** v4 `other` and v4 regex-matched read for the first time, plus a disclosed second read of v3's
   regex-missed and pushback, under an operator ruling. That uses the tooling in method-second-read §3: subset seal,
   instrument.json and a reads ledger.

On this evidence the expected winner of step 2 is **a sonnet relay voter** (sonnet fast alone, or sonnet with the
haiku careful call allowed only to veto). The precision-pass on the haiku pair should stay in that run as a
comparison arm, not be the chosen configuration: every haiku-pair rule that keeps sensitivity is estimated at
0.78–0.84 on v3-like `other` (§2). Lowering the floor and running uncertified are both rejected on the method's own
text. Waiting is rejected except as the hybrid in step 3.

## 5. Caveats
- Every conditional rate in §2 rests on 14 fast over-flag calls on 9 rows, and on sonnet's 1 of 56. The intervals
  are wide, and transfer to v3's history-heavy `other` is assumed for both options.
- The pool composition describes the population v3 was sampled from, not v3 itself. v3 is sealed and was not
  reconstructed: no ids were matched and no prompt was read.
- E1c's walls are cold calls. The 0.80 in-time answer rate is v3's resident-path figure, and the two are combined
  as if independent.
- *c*, the number of correct relays on v3 `other`, is unknown without gold. The estimate of about 7 comes from v1's
  1 of 22.
- Whether the live UserPromptSubmit population includes bash-mode `!` lines, or matches history `display` strings at
  all, is unverified. It bears on instrument fidelity, not on this ranking.

## 6. How the new numbers were made (reproducible; nothing written but this file)
- **Pool composition.** `python3 -c` imports `scripts/research-kit/heldout-candidates.py` and calls
  `build(files, 10**7, history)`, with transcripts modified within 400 d and `~/.claude*/history.jsonl` realpaths.
  It counts, per stratum, the source prefix (`history:` or not), length bins, a leading `!` or `#`, the word count
  ≤ 3, and the `[Pasted text` or `[Image` substrings. Nothing is printed or written beyond the counts.
- **Tuning v1 `other`.** The same counts over `~/.claude/autonomy/research/router-heldout/tuning.jsonl`.
- **Careful against fast.**
  - Neither-relay rows: both raters' labels are outside {completeness, pushback} (`tuning-labels-{anthropic,openai}.jsonl`),
    56 rows.
  - The calls are E1c `tune-2reps.json` arms `off-e1b` and `on-pre`, paired by row and rep.
  - Fast counts as a relay if its label is valid and `wall_s` ≤ 9.0. Careful counts as relay, non-relay or silent
    at ≤ 8.5 s, and its eventual label is read with no limit.
- **Binomials.** Exact sums: P(≥45/47) · P(≥24/25) · P(2/2) at p = 0.94–0.99. Exact Poisson bisection for 1/56 and
  8/56; Wilson intervals for 9/14 and 5/14.
