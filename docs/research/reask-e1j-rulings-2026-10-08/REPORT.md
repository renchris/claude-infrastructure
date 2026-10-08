# Row 15 after wave E1j: the five rulings and what to build now (decision research, 2026-10-08)

Produced by workflow `wf_fa396b30-e25` (four read-only research slots, a synthesis, a refuting critic and a steelman critic, a final revision), run by the research-program lead; written to disk by the lead. Every number is on tuning data or timing traces; no sealed set was opened.

**Answer.** Build five things now. None needs sealed data or a ruling, and all are above 90% conviction, so they are auto-approved:
1. A per-kind cold hedge with a clean early return (91).
2. A correction to the Haiku 4.5 retirement claim (96).
3. A record of four measured facts (93).
4. An A/B check of the hedge at real machine load (91).
5. A cert-store export for the warm workers (91).

Spend no sealed data now. The critiques showed that gate row 15 is itself a sealed read, re-run at every gate (gate_rows_b.py:351-362). truememory-2-0 cannot reach its gate before waves E2, E3 and E4 finish, so a standalone read now issues no certificate and adds a read the gate repeats.

Five rulings go to you. One more, leaving the live router as it is (92), clears 90 and is auto-approved.

| # | Question | Recommendation | Conviction |
|---|---|---|---|
| 1 | When is the next sealed read, and is it the "fixed as tooling" exit? | No standalone read. The next sealed read is the certifying gate's own row 15. It counts as the exit once the hedge has landed, the real-load A/B check passes (hedge-on fallback ≤ 0.03; p90 shown only), the careful call is pinned by a pre-registered tuning-only rule, and the gate's instrument is re-pinned with the load bound built in | 84 |
| 2 | Which careful call to certify | Do not pin yet. First re-tune Haiku 5.5 under a new pre-registered rule whose fallback is the Haiku 4.5 union, then pin explicitly. Haiku 4.5 likely retires around mid-December | 66 |
| 3 | Regex-missed and pushback data for the gate's read | Regex-missed from a fresh v5 once 400 unused candidates exist (about 2026-11-01 to 11-22). Pushback from v3 as a disclosed third read (2 items, near-zero information) | 72 |
| 4 | Regex-matched data for the gate's read | Fresh v5 if it yields 40 or more counted items, otherwise a disclosed second read of v4 with its conditioning stated | 70 |
| 5 | Load bound | Built into `heldout.evaluate` as a named row-15 method edit, so it applies to the gate itself | 76 |
| — | What the live router runs now | Leave it as is (Haiku 5.5 as built, configuration 983448663980). The hedge goes live on the converge with no restart | 92 |

**Glossary**
- **Row 15**: the gate check that the re-ask classifier (the "router") catches questions asked again. Every research certificate needs it, and it is defined as "this run" at the gate (REPORT.md:606).
- **Fast call / careful call**: the router asks Sonnet 5.5 (thinking off) and a second, careful model in parallel.
- **Union**: the router relays if either call says "relay".
- **Warm path**: resident workers started ahead of time by the daemon `classifier-warm.py`.
- **Cold call**: a fresh `claude -p` process.
- **Hedge**: a cold call started at 4 s while the warm call keeps running.
- **0059**: the migration that restarts the warm daemon. Running it is your step.
- **v3, v4, v5**: sealed held-out test sets. Each holds four strata:
  - **Regex-missed**: re-asks the pattern list misses. This stratum decides row 15.
  - **Regex-matched**: re-asks the pattern list catches.
  - **Pushback**: you pushing back on an answer.
  - **Other**: everything else.
- **RULE E1j / RULE 2'**: the selection rule and the read bars written into the plan before any call.
- **Instrument**: the pinned map from each stratum to the set that scores it.

## Build now
1. **The per-kind cold hedge** in `router.py` `classify()` (91).
   - At 4 s, start a cold twin for each kind still pending on the warm path, including when the other kind already holds a non-relay label.
   - For each kind the first label wins, under the unchanged join.
   - With no label in hand, return "unavailable" at about 8.7 s instead of 9.0 s, so cleanup kills the hedge's processes before heldout's 9 s kill.
   - Trace `hedge` per kind and a `held` row. Add a `CC_RESEARCH_HEDGE=0` off switch.
   - Tests go red before the change and green after, including one asserting no child process survives a row with no label. No configuration-id change and no restart.
2. **Correct the retirement claim** at plan :1070, :1281, :1547-1548 and :1555 (96). The correct statement: "no earlier than 60 days after a notice; none as of 2026-10-08." Add the Sonnet 4.5 precedent.
3. **Record four measured facts** beside E1j's rulings (93):
   - The hedge rarely rescues a Haiku 4.5 careful call (143 of 1,078 cold calls finish within 4.5 s).
   - 10 of 178 answered rows were held with one call silent.
   - The workers lack the cert-store variable.
   - Gate row 15 is itself an unbounded sealed read.
4. **Real-load A/B check** after the converge (91). 300 tuning rows, alternating hedge on and off. The bar is committed before the run. Rows held with one call silent are reported, a 1 Hz sidecar watches worker state, and a stated rule covers the case where no high load arrives.
5. **Export `CLAUDE_CODE_CERT_STORE=bundled`** in `jobs/classifier-warm.sh` (91). It takes effect at the pin wave's 0059 restart.

Not now:
- Hashing the binary path and version into the configuration id. It needs the 0059 restart, so it goes with the pin.
- ProcessType Interactive in the plist, or a readiness check in the daemon's pool. Do these only if the A/B check fails and the sidecar names the cause.
- The Haiku 5.5 re-tune wave (needs ruling 2).
- The load bound in `heldout.evaluate` (needs ruling 5).
- Any draw, seal or read (needs rulings 1, 3 and 4).

## What changed from the proposal
- **Ruling 1** moved from "one standalone read once the fix is in" to "the gate's own row 15 is the next read".
- **Ruling 2** moved from "pin Haiku 4.5" to "re-tune Haiku 5.5 first". The live vendor page shows the deprecation pattern, and the router must keep serving certified sessions after the gate.
- **Rulings 3 and 4** now name the gate's instrument, with corrected power figures. Ruling 4 dropped from 91 to 70 and now goes to you.
- **Ruling 5** is now built into `heldout.evaluate`.
- **The hedge** became per-kind, returns early and has a no-orphan test.
- **The check** became an interleaved A/B.
- **Build-now item 5** was added.

## Critique responses
**Critique 1**
1. *Ruling 1(b)'s p90 bar contradicts the Haiku 4.5 pin.* **Accepted.** Verified: E1i's live p90 was 8.78 s (plan :1334), its latency clause "selects nothing" (:1337), and E1j itself says the selection would fail this bar (:1545). p90 is now shown only, and ruling 2 no longer pins Haiku 4.5 now.
2. *Ruling 4 states the power wrongly.* **Accepted.** Recomputed: P(at most 4 misses in 13) is 0.9987 at 0.93, against 0.212 for a fresh 93. Ruling 4 is now at 70, goes to you, and is reframed.
3. *Ruling 3 has the same error.* **Accepted.** P(at most 1 miss in 12) is 0.659 at a true recall of 0.90.
4. *The hedge misses single-kind stalls.* **Accepted.** Python over the E1j trace: 10 of 178 answered rows had one call that "had not answered", at 8.50-8.64 s, loads 96-301, 4 of them below load 150. The hedge is now per kind, and a `held` trace row was added.
5. *The hedge leaves orphaned processes.* **Accepted, with one qualifier.** Verified heldout.py:557-562 (9 s kill), router.py:524 (cold children start in their own session) and :638 (with no label, the router waits to the deadline). The orphans are transient, since each ends when its own call returns, but they add load during exactly the bursts that matter. The early return and a no-orphan test were added.
6. *Missing cert store as a competing cause.* **Accepted as a second live hypothesis.** Verified: absent on 4 of 4 workers (ps eww), set at settings.json:13, and `Pool.take` has no readiness check (classifier-warm.py:219-228). **Rebutted only as a replacement** for the starvation reading: answered walls at load 250 and over form a continuum up to 8.98 s, which still reads as slow, not dead. Both hypotheses predict that session-started hedges escape the stall, so the hedge stands either way. Build-now item 5 and the sidecar were added.
7. *The load bound does not reach the gate.* **Accepted.** heldout.py has no load check, and gate_rows_b.py:351-362 calls evaluate with no bound. Ruling 5 is restated.
8. *The check has no A/B and depends on load nobody controls.* **Accepted.** Arms are interleaved, there is a rule for when no high load arrives, the sidecar was added, and the pin gets its own check after its restart.
9. *Ruling 2 compares a selected winner against unselected arms.* **Partly accepted.** Haiku 4.5's lead is in-sample, so the 0.73 forecast is overstated. **Rebutted on validity**: the gate's verdict comes from unseen data, so the bias inflates the forecast, not the verdict. A Haiku 5.5 pin now runs under a new pre-registered rule, which meets 1(c).
10. *The retirement date is perishable.* **Accepted.** The vendor page was re-read today.

**Critique 2**
1. *The p90 contradiction.* **Accepted** (as in 1.1).
2. *The case for "no read until fresh data".* **Accepted, and it changes ruling 1.** Verified: programs.json shows "registered"; the plan holds TM2 read-only until E4 (:425), E2 is still running (:1574), and E4 follows E3 (:1844); evaluate logs a read before its first call (heldout.py:583, :635). **Rebutted on the number only**: the proposed 72 scored the old recommendation. The new one stands at 84, below 90 because it ends the E1b-E1j cadence.
3. *Sonnet 4.5 precedent.* **Accepted.** On the live page today, Sonnet 4.5 was deprecated 2026-09-30 and retires 2026-11-30. Opus 4.1 was deprecated 06-05 and retired 08-05. Haiku 5.5's floor is 2027-10-07. This changes ruling 2.
4. *Ruling 3 power, and the widened stratum is easier.* **Accepted.** Every careful arm relays 24 of 24 relay-gold "other" calls (python over the tuning data, v1 rows excluded as the "other" rule does). The critique's 26 of 26 used another filter and reaches the same conclusion.
5. *Ruling 4.* **Accepted.** It is now the question of which data scores regex-matched at the gate.
6. *Ruling 5 does not reach the certificate.* **Accepted.**
7. *Per-kind hedge.* **Accepted.** The critique's 8 is the careful-call subset of the 10.
8. *Items the critique verified* (router.py lines, the 143 of 1,078, the load table, the live router). Noted; no change.

## Evidence (origin/main ba1fdc86c)
**The defect.** `warm_classify` gets the whole remaining limit (router.py:494, :420), and the cold call runs only after it returns (:505-509). In E1j, all 22 of 22 fallbacks had both calls warm, accepted and silent past 8.6 s (plan :1494-1500):

| 1-min load | rows | fallbacks |
|---|---|---|
| under 150 | 95 | 0 |
| 150-250 | 61 | 6 |
| 250 and over | 44 | 16 |

**Hedge window.** Cold calls finishing within 4.5 s (out of 1,078 each):

| call | finished ≤ 4.5 s |
|---|---|
| Sonnet fast call | 1,034 (2.1.291) |
| Haiku 5.5 arms | 1,022-1,060 |
| Haiku 4.5 | 143 |

**Careful pin.** RULE E1j replay (plan :1530-1537), union with Sonnet:

| careful call | recall (of 163) | regex-missed (of 42) | p90 |
|---|---|---|---|
| Haiku 4.5 | 162 | 41 | 8.5 s |
| Haiku 5.5 medium | 159 | 38 | 4.15 s |
| Haiku 5.5 low | 160 | 39 | 4.23 s |
| Haiku 5.5 as built | 160 | 39 | 4.55 s |

Without Haiku 4.5, the fast call alone reads 0.94 pooled recall and 0.81 regex-missed (plan :1286).

**Load.** E1i's corrected table: 1 timeout in 89 items at load 0-40, 72 in 228 at load 60-100. The gate has no load check today.

**Data supply.**
- About 34 unused regex-missed candidates; 400 arrives around 2026-11-01 to 11-22.
- v4 took all 257 regex-matched candidates, and 3 have arrived since.
- Neither v3 nor v4 is in the tuning data.

## Unknowns
- **Whether the hedge cures the stall at load 150 and above.** Cold calls have never been measured above load 75. Check 4 settles this.
- **Which cause is real:** low-priority starvation, workers stuck at start on the keychain, or an upstream stall. The sidecar attributes it.
- **Whether a Haiku 5.5 re-tune reaches E1j's bars** without overfitting 42 tuning calls.
- **When Haiku 4.5 is actually deprecated.** The forecast rests on precedent, not an announcement.
- **When the gate runs:** after E2, E3 and E4, plus TM2's own stages.
- **The fresh regex-matched yield by mid-November.**
- **Whether you treat the E1e and E1h "no third read" rules as binding.**