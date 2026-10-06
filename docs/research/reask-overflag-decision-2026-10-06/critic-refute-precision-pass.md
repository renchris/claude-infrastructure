# E1h critic: try to refute "precision-pass"

**Verdict: the recommendation should change.** Precision-pass has the right first step: a fresh, rated, ordinary-prompt
tuning sample, then a fresh sealed read. But it fixes the levers too early. It tunes a join rule or a brief over the two
haiku arms, keeps the model, and stays "fixed as tooling". v3's own router-side numbers put a join rule's best case at
the 0.90 line, and its likely case below it. The brief lever has measured weak every time it was tried. No lever,
including the model, has been measured on a representative sample of ordinary prompts, so the wave should measure
first with every lever open.

Date 2026-10-06. Worker, read-only. Worktree `/Users/chrisren/Development/.worktrees/wt-cc-024434-55635` at `ff3e87fb7`.

**Deviations, stated up front:**
- I did not run the brief's `git pull --ff-only`. It is a git mutation, which my worker rules forbid, and HEAD already
  holds E1g's record.
- I ran the candidate miner's `build()` in memory, twice, to count source kinds, ages and text features of the pool.
  No prompt was printed or written to disk, and each row was cleared once counted. The two scripts are reproduced at
  the end. They ran from a scratch directory, `/tmp/e1h-critic-pp/`, which I emptied and removed afterwards.
- No sealed set, key or `tuning-v2.jsonl` was opened. `tuning.jsonl` was read for its `stratum` and `source` fields
  only.
- The relayed user request was a `/limit-recover ingest` whose verification failed (A2). I did not act on that bundle
  or investigate it. This slot is the computed read-only critique only.

Every number below is labelled **measured** (with the command or file) or **estimated** (with the method).

---

## 1. Strongest objection: a join rule over the two haiku arms is capped at the 0.90 line on v3-like data

The v3 router-side record (`reading-v3-2026-10-05{,.paths}.jsonl`) shows how the 148 counted `other` prompts were
answered. Measured with a python tally (see also `confirm-rule-replay.md` Part 2):
- 26 fast relays;
- 10 careful relays;
- 88 fast non-relay labels where the careful call answered non-relay within 8.5 s;
- 24 fast labels handed back at 8.5 s with the careful call still thinking.
- 35 of the 148 were misses.

**Algebra that needs no gold (exact).**
- The misses are the wrong relays plus the wrong non-relays: 35 = (36 − R_c) + M_n, where R_c is the number of
  correct relays.
- So the wrong non-relay labels number M_n = R_c − 1, and R_c ≥ 1.
- Under careful-confirms (rule b), the only rule that keeps the careful-only relays, which carry the borderline
  sensitivity:
  - the M_n non-relay misses stay;
  - the 10 careful relays stand;
  - a fast relay stands whenever the careful call has not answered by 8.5 s.
- Write R_cc and R_cf for the correct relays from the careful and the fast call, and `late` for the share of fast
  relays the careful call has not answered by 8.5 s. Then

      misses(b) ≥ (R_cc + R_cf − 1) + (10 − R_cc) + late·(26 − R_cf) = 9 + 26·late + R_cf·(1 − late) ≥ 9 + 26·late

**Ceiling.** Estimated, taking `late` from the careful call's answer rate on v3 `other` calls the fast call did not
relay: 98/122 answered, so late = 0.20; the overall rate gives 0.25.

| late | min misses | `other` best case | needs 134/148 |
|---|---|---|---|
| 0.15 | 12.9 | 135.1/148 = 0.913 | passes by about 1 |
| 0.20 | 14.2 | 133.8/148 = 0.904 | at the line |
| 0.25 | 15.5 | 132.5/148 = 0.895 | fails |

The best case also needs all of these at once:
- every wrong fast relay the careful call answered is vetoed;
- each vetoed prompt gets the raters' exact label (`other` is a six-way exact-label score);
- the careful call confirms no wrong relay;
- every correct relay came from the careful call.

**Likely case (estimated, with assumptions taken from the data).**
- Assumptions:
  - About 6 relay-gold prompts in v3 `other`, at v1's rate of 1 in 22 agreed `other` rows (measured on the tuning
    labels).
  - The careful call confirms 10-40% of wrong fast relays. On tuning it confirmed 1 of the 2 it answered (measured,
    `confirm-rule-replay.md`). On v3 it relayed 10 of the 98 `other` prompts it answered (measured).
  - 5-20% of vetoed prompts get the wrong non-relay label. The careful configuration read 40/44 on tuning `other`
    and 0.72-0.88 on answered v2 `other`.
- Results: optimistic 0.863, central 0.834, pessimistic 0.817. **Under rule (b) the likely result is a fail.**
- Careful-authoritative (rule c) hands the whole `other` labeling to the careful configuration, which has read
  0.72-0.88 on held-out `other`.

**Lifting the ceiling means dropping the careful-only relays (rules b', d, e). That is exactly the recall trade.**
- On tuning, dropping them cuts borderline relays from 19/26 to 9-10/26, below E1g's own bar of 17 (measured,
  `confirm-rule-replay.md` Part 1).
- On v3 the careful call relayed 7 regex-missed and 7 regex-matched prompts (measured, paths file). Regex-missed is at
  24/25 with 0 misses to spare.
- On tuning the careful-only relays rescued 1 of 52 recall calls (measured: union 52/52 against fast-only 51/52).
- At that 2% rate, the chance that at least one of regex-missed's 24 hits came from the careful call alone is about
  1 − 0.98^24 ≈ 0.38 (estimated). That one hit would fail the second read.
- So within haiku, rule (b) cannot reach 0.90 reliably, and the rules that can put the relay-recall strata and the
  method's main guard at risk. The method's own cost line (REPORT §4.1) says "a missed completeness ask restarts
  research", and E1b found that the completeness sensitivity lives in the thinking-on call.

**The brief lever is weak on the record.**
- E1b: "wording does not replace thinking". The cost-asymmetry notes moved borderline relays by at most 2 of 26
  (BUILD:469-472).
- This E1h run: a precision-tightened haiku brief cut relays on the rater-split negatives from 7/14 to 4/14. It cost
  one recall row (46) and one exact `other` row (90) (measured, `stronger-model-live-score.txt`).
- Each tuning-chosen haiku configuration has then read lower on held-out data:
  - on-pre: tuning 40/44 = 0.91, then held-out 0.88 and 0.72 on answered prompts;
  - the union: tuning 41/44 = 0.93 live and 43/44 in the replay, then held-out 0.76.
- A pass chosen as the best of several rule and brief variants on about 150 agreed tuning prompts adds a winner's-curse
  optimism of roughly 1-2 standard errors (about 0.02-0.04 at 0.92; estimated from binomial SE). The fresh sealed read
  needs a true rate of about 0.92 to pass 9 times in 10 at n = 270 (estimated, exact binomial: 0.904). So the tuning
  bar would have to be about 0.95, from configurations whose best held-out read so far is 0.88.

## 2. Tuning-set unrepresentativeness: the cause is found, and precision-pass avoids repeating it only if it draws the tuning split the same way

New measurements, counts only:
- **v1 tuning is 100% transcripts.** 96/96 rows have a non-`history:` source (measured: python over `tuning.jsonl`'s
  `source` field).
- v1 was sealed on 2026-10-01, before E1c added the `--history` store.
- **The `other` pool that v2 and v3 sample is 82% prompt-history.** Measured with `pool_sources.py` (miner `build()`,
  no cap, `--days 400` plus history, as E1g mined):
  - 20,839 history rows against 4,620 transcript rows, of 25,458;
  - by age: transcripts within 60 days 4,620; history within 60 days 3,956; history 61-180 days 7,728; history over
    180 days 9,154.
  - v3's `other` sample is the first N in sha256 order, a pseudo-random draw, so it carries about the same mix
    (estimated).
- **History `other` prompts are a different text population** (measured, `pool_features.py`):

  | feature | history | transcripts |
  |---|---|---|
  | median length | 103 chars | 336 chars |
  | contain `?` | 32% | 18% |
  | 30 chars or fewer | 11% | 5% |
  | paste/image placeholder (`[Pasted text #n`, `[Image #n`) | 8.8% (1,834) | about 0% (1) |

- **The same fast configuration reads 0.96 on transcript-only held-out data and at most 0.83 on v3.**
  - E1b reading 2: E1b brief, thinking off, on sealed v1 `other`, 25/26 = 0.96 (BUILD:466).
  - On v3 the same fast call relays 26 of 148 (measured).
  - On v1 tuning it relays 0 of 21 agreed non-relay `other` rows. That is improbable if the v3 rate applied:
    P(0/21 | p = 0.169) = 0.02 (estimated, binomial).
  - So v1 understates over-flagging because of the store, an estimate that is consistent with every read on record.

**What this means for precision-pass.**
- **Representativeness objection: rebutted on one condition.** The fresh tuning split must be an HMAC split of the
  same miner output (history included, same sha-order sampling) as the fresh sealed `other`. A recent-transcripts
  tuning sample ("fresh" read as "new prompts since v3") would repeat v1's error exactly: since the v3 mine there are
  19 new `other` prompts (measured by the population slot), almost all of them transcripts.
- **A validity question the operator should rule on before any fresh read.**
  - About 66% of the instrument's `other` stratum is typed prompts over 60 days old, from all projects (estimated from
    the pool mix).
  - About 9% of the history rows are display strings with placeholders that the live hook would not see. That the hook
    sees the expanded paste is an assumption I did not verify.
  - The router acts only on prompts in program sessions.
  - The 0.90 floor was set at build (commit `92cf72197`), not in the method text.
  - Tuning a brief to this population tunes partly to an artifact of the instrument. That cuts against precision-pass
    and the stronger-model option alike, not against the measure-first option below.

## 3. The second read of v3's re-ask strata is a weak and partly compromised test of a change that can only lower relays

- **No slack.** The first read gave regex-matched 47/47, regex-missed 24/25 and pushback 2/2. The pass bars are 45, 24
  and 2, so regex-missed and pushback can lose nothing.
- **Chance that all three re-ask strata pass** (estimated, exact binomial at a constant true recall; it overstates the
  risk for items already relayed once):

  | true recall | P(all three pass) |
  |---|---|
  | 0.96 | 0.48 |
  | 0.97 | 0.65 |
  | 0.98 | 0.82 |
  | 0.99 | 0.94 |

  A precision pass works by removing relays, so it moves recall down this table. Labels also move between reads of an
  unchanged configuration: 22 of 151 changed in E1e, and 13 of 96 tuning rows in E1g (both recorded).
- **The method slot's own validity condition is already breached.** It says the read stays valid "as long as the pass is
  designed without v3 knowledge beyond the published aggregates". The E1h slots have since put per-stratum v3
  router-side facts into circulation that are not in the E1g record:
  - careful relays 7 regex-matched, 7 regex-missed and 10 `other`;
  - the careful call answered 0.75 overall;
  - fast-only recall loss between 0 and 14 in the completeness strata.

  Any rule chosen with those numbers in hand is "chosen with these numbers in hand" (BUILD:774-778). They bear directly
  on whether dropping careful-only relays costs regex-missed hits. Pre-registration must say they were not used, or the
  read must be disclosed as biased by them too.
- **Pushback is certified on 2 prompts read twice.** A pass there carries almost no information.
- **The hybrid shrinks the reuse.** Fresh regex-matched is available: about 419 unused against 47 counted needed. Only
  regex-missed and pushback, 27 items, then rest on the second read. Precision-pass as stated reuses all three strata.

## 4. The alternative's evidence is thinner than the digest says, which is why the next step must measure, not choose

- **Sonnet's advantage is all on rater-split rows that row 15 does not score.** Measured from the stronger-model
  per-call data with the tuning labels:
  - The "56 neither-relay rows" are 42 agreed non-relay rows and 14 rater-split rows: 9 regex-missed, 4 `other`,
    1 regex-matched.
  - On the 42 agreed rows every arm relays 1/42 (row 10).
  - On the 14 split rows: haiku-off-e1b 7/14 (rows 35, 37, 49, 51, 56, 57, 89), haiku-off-tight 4/14, sonnet-off 0/14.
  - So "8/56 against 1/56" is a difference on ambiguous prompts that v3's agreed-only scoring excludes. Its transfer
    to v3's agreed `other` over-flags (26/148) is unmeasured, as the stronger-model slot says in its own caveat.
- It is still the only lever with any measured precision effect: 7 against 0 discordant rows, sign test p ≈ 0.016
  (estimated). It holds on 1 rep. It also keeps the careful arm's leak: the union is estimated at 6/56 with sonnet fast.

**Net.** Neither the rule, the brief nor the model has been measured on a representative sample of ordinary prompts.
Precision-pass picks the levers with the weakest record (rule ceiling about 0.90, brief weak). It excludes the one with
the strongest, because the model is a §4.1 parameter that needs a ruling-8 edit. If the fresh tuning split then shows
the haiku levers cannot reach about 0.95 on tuning, the wave stops with no certified router. A second operator ruling
and wave follow, after the composite-instrument tooling has been built for nothing.

## 5. Better option: measure first, with every lever open, then pre-register

1. **One operator decision now, covering:**
   - the wave;
   - the §4.1 classifier-model parameter, so that a non-haiku arm is allowed if it wins on tuning (a ruling-8 named edit
     of REPORT:775 that lands only if chosen);
   - the disclosed second read, reduced to regex-missed and pushback (27 items);
   - the population question in §2: is row 15's `other` meant to be the year-deep history mix or program-session
     prompts? Decide it before any fresh read, never after one.
2. **Mint, by the same miner and sha-order sampling with history included:**
   - an HMAC tuning split of `other`, about 300 rated, giving about 160 agreed at v3's 0.54 agreement rate;
   - a sealed v4 of `other`, about 500, giving about 270 agreed;
   - fresh regex-matched for the sealed v4.
   - Rate both with two vendors, as v3 was (752 rated in 24 min).
3. **Run every candidate arm to completion on the tuning split, then replay every join rule offline.**
   - Arms: haiku fast, haiku careful (never stopped by a fast relay), sonnet-off, sonnet-off as the confirmer of
     careful-only relays, and the brief variants.
   - This records the one datum that decides every confirm rule: the careful label on fast-relayed prompts
     (`confirm-rule-replay.md`). It also measures sonnet's precision where row 15 scores.
4. **Pre-register a stop rule** before seeing the tuning numbers. Proceed only if a configuration reads at least about
   0.95 on tuning `other` (margin for the tuning-to-held-out drop on record and for the winner's curse). It must also
   meet relay recall ≥ 0.95 with the careful-only rescues counted, fit 9 s, and keep borderline at or above E1g's bar.
   Otherwise spend neither the second read nor v4, and take the result to the operator.
5. **Build the composite-instrument tooling only after step 4 passes:** `seal --strata`, an instrument file both
   `evaluate` and gate row 15 read, and a reads ledger.
6. **In parallel, independent of row 15:** land the operator-visible relay notice and the one-word `misrouted`
   override that grants only `other` rights (`false-relay-cost.md` (b) and (c)). They cap the cost of a false relay
   without touching recall or the research guard.

**What would make precision-pass hold.** Any one of these on the fresh, miner-drawn tuning split:
- the careful call vetoes at least about 90% of the fast call's wrong `other` relays with the exact label;
- its own relays on `other` fall to about 2% or less;
- a haiku brief gets `other` to about 0.95 without losing a recall row or borderline sensitivity.

None of these is measured today. Option 5 measures all of them in the same run that precision-pass would need anyway.

## Scripts (run 2026-10-06 ~01:40 CDT; counts only, never a prompt)

`pool_sources.py`:
```python
import importlib.util, glob, os, time, collections, datetime
spec = importlib.util.spec_from_file_location("hc", "/Users/chrisren/Development/.worktrees/wt-cc-024434-55635/scripts/research-kit/heldout-candidates.py")
hc = importlib.util.module_from_spec(spec); spec.loader.exec_module(hc)
cut = time.time() - 400 * 86400
files = sorted({f for f in glob.glob(os.path.expanduser("~/.claude*/projects/*/*.jsonl")) if os.path.getmtime(f) >= cut})
hist = sorted({os.path.realpath(f) for f in glob.glob(os.path.expanduser("~/.claude*/history.jsonl"))})
by = hc.build(files, 10**7, hist, {k: 10**7 for k in ("regex-matched", "regex-missed", "pushback", "other")})
# per row: kind = history|transcript from r["source"]; age band from the source timestamp; r.clear() after counting
```
Output:
```
regex-matched 681 {('history','61-180d'): 281, ('history','<=60d'): 60, ('history','>180d'): 223, ('transcript','<=60d'): 117}
regex-missed 617 {('history','61-180d'): 60, ('history','<=60d'): 15, ('history','>180d'): 15, ('transcript','<=60d'): 527}
pushback 49 {('history','61-180d'): 19, ('history','<=60d'): 10, ('history','>180d'): 15, ('transcript','<=60d'): 5}
other 25458 {('history','61-180d'): 7728, ('history','<=60d'): 3956, ('history','>180d'): 9154, ('transcript','<=60d'): 4620}
7436 transcripts, 4 history files
```
`pool_features.py` (same `build()` call; per `other` row: placeholder regex `\[(Pasted text|Image) #\d+`, length ≤ 30,
contains `?`, length): output
```
history: n 20839, placeholder 1834, len<=30 2334, has? 6738, len median 103 (p25 53, p75 190)
transcript: n 4620, placeholder 1, len<=30 243, has? 817, len median 336 (p25 129, p75 373)
```
The rule-(b) bound and scenario figures come from a short python calculation, with all its inputs shown in §1.
