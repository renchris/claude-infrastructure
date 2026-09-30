# Decision 8: keep KMAX = 8 — evidence note

**Ruling (2026-09-30, operator "proceed with all as recommended"):** keep `router.KMAX = 8` (`accounts.json:44`); no storm raise, and a recovery-only raise is also rejected. Conviction 86%. Packet `4a08882545c5`. Step D8.2 of `rulings.json`; both skeptics' corrections are folded in below. The analysis scripts that survived in `/tmp` are copied into `kmax-decision-8/` beside this note (their JSON outputs were not kept, and `sim4.py` was left out because it never parsed, so it produced none of these numbers).

**The premise it corrects.** The plan and the architecture justified KMAX by "a measured infrastructure limit of 5-6 concurrent requests per account". That band was never measured on this machine; it came from GH#62426 and habit. What was measured: 0 of 40 probe first turns failed at N = 2..6 simultaneous cold starts (W0 item 9), 0 terminal limiter errors, and retries are not persisted to disk.

**Re-based after D1.8.** The working-session over-count fix (W6c `75b0f84a0`) changed what KMAX binds on. Re-measured on the two accounts capped on 2026-09-29: the cap bound in 11 of 12 account-sweeps under the old count and 4 of 12 under the new one (`kmax-rebase.md` in this directory). D1.8 loosened KMAX in effect; the ruling is unchanged.

## Measurements

**(1) The night of 2026-09-29.**
- 12 hook-lane recovery runs. 5 had an account excluded by `kmax-concurrency`, and all 5 went to `next4` at k_work 7, 2, 2, 2, 2. 0 parked on the cap.
- The 2 parks at 06:30-06:31Z were `--max-wait` router timeouts, not the cap.
- Every account was at the cap in the sweeps at 06:16 and 06:21. The 06:26 three-session cohort still routed, because `next` was not excluded by the cap.

**(2) All 31 parked rows in `fleet/*/results.tsv`.**
- `ac0f0123` on 09-26 waited 17.6 min or less.
- The 09-19 22:35-22:36Z cap parks would have saved about 4 min and 0 recoveries at a higher cap.
- `75c7e2a5` cannot be recovered from disk.

**(3) Share of storm sweeps with every account at the cap.**
- Tonight: 10 of 29 at K=8, 3 at K=12, 1 at K=16.
- History: 4.9%, 3.0% and 1.6% respectively, with blocked accounts at a median k_work of 20.
- Wall episodes: at K=8, p50 13, p90 38, max 78 min. At K=12, p90 40, max 59. At K=16, max 33.

**(4) What the count was made of** (before D1.8).
- 223 of 354 (63%) counted transcripts were subagents, 81% of them Workflow agents.
- The W0 burst probe's finished headless runs caused the `next4` readings at 05:50 and 05:56Z.

**(5) The floor mechanism, corrected.** This is the reason to keep 8; the earlier "22-40% of moves cancelled" claim is dropped.
- `floors_ok` charges only `placed_n`, which starts at 0 on every `--place` call (`bin/claude-accounts:4525`, charged at `:4550`).
- Reconciler passes run every 3 s when active (`lr_recon/__main__.py:46`), so the floor limits seats per pass, not over time.
- The accumulating guard against pile-on is KMAX through phantoms, which live 15 min (`ASSIGN_TTL_MIN`, `accounts.json:56`; `bin/claude-accounts:2240`).
- The hook lane's floor (`_su_projected`, `bin/claude-accounts:2873`) charges no phantoms at all.

**(6) Heavy movers.** 155 modeled wait-minutes at K=8. K=12 saves 21, K=16 saves 76-88, and charging every mover weight 1 saves about 154. The lever is the weight rule, not the cap; it is a separate question (D8.6), not part of this decision.

**(7) Server side, with its limits.**
- 0 terminal limiter errors.
- Retries are not kept on disk: 2 of about 15.9k transcripts carry `retryAttempt`, both `sdk-cli`.
- 32 terminal 529s, all at k_work of 5 or less. But 30 came from Claude Code 2.1.220, 29 predate the 09-04 change that started counting subagents, and the 08-24 pair looks fleet-wide.
- 0 of 40 probe first turns failed; all were one-word `claude -p` cold starts, so this bounds cold-start bursts, not long turns.

**(8) Hook-lane tail.**
- A request gets 3 dispatches at least 10 min apart (`RQ_MAX_ATTEMPTS`, `RQ_RETRY_MIN`, `lr-reset-poller.sh:974-975`); poller tick gaps have p50 11.3 min and p90 20.0 min.
- 0 `REQUEST-EXHAUSTED` so far.

**(9) Shadow blindness.** Phantoms are charged only in act mode with `recon.on` (`_own_and_charge`, `lr_recon/__main__.py:1187-1188`), so the W5b shadow cannot show a cap filled by the cohort itself.

## Revisit condition

Reopen if act-mode `recon/plans/*.json` show a cohort waiting on `kmax-concurrency` for more than about 10 min, or a `REQUEST-EXHAUSTED` whose attempts were all kmax-excluded. The real levers, each separate from KMAX:
- (a) mover weight — as built it counts subagents written in the 10 min before the death (`lr_recon/plan.py:135-138`, W6d `f8f1e07ea`); the rule itself is D8.6's open question.
- (b) `bound_kwork` compares counts, not session ids (`bin/claude-accounts:2380`).
- (c) the source-account skip in `lf_pick_target` (`lr-fleet.sh:780`).
- (d) the hook lane falls back to `KMAX_RESIDENT` (40) when k_work is unmeasured (`k_cap`, `bin/claude-accounts:2537-2548`).
