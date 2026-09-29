# M5: does `/goal` survive a usage-limit death? (2026-09-29)

Scan: `raw/m5-goal-scan.py` → `raw/m5-goal-scan.txt`. Measured on 5,604 transcripts and 4,242 session uuids with mtime ≥ 2026-09-01, across all six config dirs. Transplant copies are unioned by record uuid.

**The premise is wrong.** `blocking_limit` is not the usage limit. The CC 2.1.278 binary's turn classifier (`Nh`) maps `blocking_limit`/`prompt_too_long`/`rapid_refill_breaker` to `stop, context_limit`, which does clear the goal. A usage-limit death is `api_error` with `errorKind:"rate_limit"` plus `quotaLimits`, which maps to `pause, usage_limit`: it leaves `activeGoal` set and prints "Goal paused · usage limit reached · send a message after it resets to continue". In 2.1.260 (`xKo`), `rate_limit` maps to null, meaning the goal stays armed with no notice. Measured over the corpus: `blocking_limit` appears as a structured field 0 times. Usage deaths are `error:"rate_limit"` (350 record copies).

## Record types
- `attachment.goal_status` is the only harness goal state. `sentinel:true,met:false` = set. No sentinel with `met:false` = evaluated. No sentinel with `met:true` = met. `sentinel:true,met:true` = clear marker.
- `system` notices: `Goal paused · …` (2.1.280+, 1 at a usage death) and `Goal cleared after an unrecoverable error (<label>)` (2× context limit, 2× auth; none at a usage death).
- Resume = attachment `SessionStart:resume`. **The restore itself writes no record.** On resume, CC re-arms iff the last `goal_status` attachment has `met:false` and no `failed`, and the `gbt` hooks/trust gate passes (binary `mbt`/`pDn`, telemetry only). So "armed after resume" shows only as a later same-hash `goal_status`.

## Sessions with a goal armed at a usage-limit death
pre = eval/stop records between set and death. Hashes and lengths are in the raw file; goal text was not read out.

| sid | set | death | ver | resumed / restore rule | goal evidence after death |
|---|---|---|---|---|---|
| b418b97a | 09-08 21:20 | 09-08 23:09 | .260 | yes (→tertiary) / true | same-hash EVAL 09-09 01:44, then MET |
| d83af9ce | 09-12 21:55 | 09-12 22:31 | .260 | yes (→secondary) / true | same-hash EVAL 09-13 00:06, then MET |
| e442434c | 09-19 16:08 | 09-19 16:58 | .260 | yes (→tertiary) / true | same-hash EVAL 17:48, then MET |
| 65186f1f | 09-19 18:04 | 09-19 19:57 | .260 | yes (→secondary) / true | same-hash EVAL 09-20 01:22 (×13), then CLR |
| 4101dbdf | 08-17 10:00 | 08-18 00:33 | .220 | yes, 27 d later / true | same-hash CLR "context limit" on the first post-resume turn (needs an armed goal) |
| 798afadf | 09-26 21:19 | 09-26 22:21 | .280 | yes / true | `Goal paused · usage limit` at death; 0 Stops after resume, so unobservable |
| 28f07827, 98f02458 | 09-19 | 09-19 | .260 | yes / true | none; 0 and 1 Stops after; pre 0/8 and 0/0 |
| 52e35019 | 09-08 22:08 | 09-08 23:11 (+09-09 05:15) | .260 | yes / true | none; 25 Stops after, but pre 0/3: the goal was never evaluated before the death either |
| 3c73a9d9, cc1f8d0a | 09-22, 09-16 | same day | .260 | no | none; pre 0/0 and 0/3 |
| 2de07510 | 09-04 19:34 | 09-05 03:31 | .260 | no | none; 0 Stops after |

## Counts (measured, `m5-goal-scan.py`)
12 sessions (13 outages) had a goal armed at a usage-limit death. **0 were cleared at the death.** 9 were resumed, and the restore rule held for all 9. **5 show the same goal still armed after the death, 4 of them after a cross-account transplant resume.** **0 were re-armed**, by tooling or by hand: `handoffs.jsonl` `goal-arm` rows are all fresh-pane arms, and `scripts/limit-recover/` has no re-arm. 6 have no goal record afterwards. 5 of those were already inert before the death (0 evals with ≥1 Stop, or 0 Stops), and the 6th, 2de07510, never ran a Stop afterwards. Absence of a record never pointed to a clear.

## Verdict: SURVIVES (5/12 proven, 0/12 cleared, 0/12 re-armed by tooling)
A usage-limit death pauses the goal (2.1.280) or leaves it silently armed (2.1.260). Neither writes a clear marker. On resume of the same uuid, including under another account's config dir, CC re-arms from the transcript's last `goal_status`.

**Daemon:** it does not need `goal_snapshot` + re-arm for pane-in-place `--resume` of the same transcript. It must (a) resume the full session (the `lr-fire-resume` option-2 path), never `--summary` or a fresh session; (b) carry the whole `.jsonl` on transplant, since the last `goal_status` must survive; (c) send a message after reset, because 2.1.280 says "send a message … to continue". A snapshot is needed only for paths that start a new uuid (recycle, which `handoff-fire` already covers).

Residual risks: restore is skipped when the `gbt` gate reports `hooks_gate` or `trust_gate`. A `blocking_limit` (context-wall) death does clear the goal, but that is not a usage-limit event.
