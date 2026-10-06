# Skeptic: conviction audit of synthesis-draft.md

M = measured, R = reasoned. Code at b87e6da64.

**The brief's two questions**
- **Above 90%, is any change really the operator's call?** Ranks 2, 4, 7 and 8 are not. At 90, rank 1's glyph is. Rank 10's "judge on 5.3 only" rewrites H1.
- **At or below 90%, is any change already settled by measurement?** Rank 5 (the plan's W1 mandates the control; red on HEAD is measured), rank 10 (the plan mandates the re-measure) and rank 26 (the binary's doc string).

| rank | refuted | adj | reason |
|---|---|---|---|
| 1 | no | 90 | The tenth is settled. The glyph is the operator's. A wire-less E=99 cell would print the same text and bar (:6362-6367, :6413-6418), but M: all 49 E=99 rows since 09-19 carry wire |
| 2 | no | 92 | M jsonl: s 2→7 since 03:08:26 |
| 3 | **yes** | 75 | Tense, clock time and bound ≈90. The load clause is the measured non-predictor: the incident read (kw 4) was in the k_work 0-4 bin (2/55), while points-spent ≥4 was 6/22 (r3a). k_work None on 29/105 reads. HH:MM must be local (`_fmt_asof` :6127) |
| 4 | no | 95 | M `skc-blank.sh`: 32/32 same verdicts (8 edge inputs, 2 bashes, 2 locales) |
| 5 | no | 92 | Mandated by the plan's W1. Red on HEAD (10/15) measured |
| 6 | **yes** | 50 | Its receipt is a refused row, where "0% of the week left · not used for new work" is true (M: live board 01:50). After rank 3, 0% is no contradiction |
| 9 | **yes** | 45 | Wire is never inherited (:2484-2489), so rank 3 does not need it. Unstated: `_place_fact_live` (:5043-5059) would expire refusal facts |
| 10 | **yes** | 95 reframed | Re-measure both arms. Rank 4 makes 3.2 fall 12×. Production is R1 row 3 (dispatcher 3.2 → child 5.3) |
| 12 | no | 50 | A kick with cache >90 s sweeps, so it reads the wire. "2-6 s" is optimistic. M, last 120 ticks: 99 swept, p50 9.8 s, p90 21.5 s |
| 13 | no | 40 | Partly covered by 12 |
| 15 | no | 55 | /accounts pastes `--readout` (commands/accounts.md:23-29) |
| 16 | no | 60 | M: largest marker file is 98 lines, and CAP 500 was a ruling (marker.sh:72-79). Align anyway: cc-limited uses 5000 (:93) |
| 17 | no | 75 | M grep: nothing parses the line |
| 19 | **yes** | 65 | Two slots measured it independently (r3a 3-6 pts; r5 5-8). This is the load figure rank 3 needs |
| 21 | no | 40 | Line 1 already prints the render clock |
| 24 | no | 30 | Routing on the last 1% is the operator's (10-01) |
| 25 | **yes** | 20 | Redundant: wire is not inherited, and the hook flags ≥300 s (hook:52-53). It also redefines "unconfirmed" |
| 26 | **yes** | 80 | Settled by the binary string (r2 §3b) |
| 33 | no | 82 | Measured ETA error 0.88-2.6× (r3a) |

Held as set: 7 (95), 8 (93), 11 (65), 14 (65), 18 (55), 20 (50), 22 (45), 23 (35), 27 (15), 28 (5), 29 (25), 30 (85), 31 (90), 32 (88; reconcile it with rank 12's extra sweep).

## Missed
- **Keep the note gated on `weekly_pct >= 100` (:6744).** An (E99, W0.99) row means u ∈ [98.5, 99] (r2 §4), so "under 1%" would be false there. Add a W-11 sibling on that row.
- A W-11 sibling with k_work None.
- Fix the comments at :1231 and :6728. The in-band rate is ~0.27 (r2 §4).
- Kick as a confirm read: rank 12 gives Rule B without a new plist in about half of kicks (R).
- Plan defect 2's "burn trajectory" (R6 6(iii)/11) is neither adopted nor rejected.
