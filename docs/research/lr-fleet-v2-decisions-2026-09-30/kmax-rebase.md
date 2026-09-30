# KMAX binding, re-based after the D1.8 working-count fix

Decision 8 kept `KMAX = 8` and asked for the binding count to be re-measured once the working-session over-count was fixed (FLEET_V2 W6, resolution 5, step D1.8). This note records that measurement for the two accounts that sat at the cap on the night of 2026-09-29 (`next` and `next4`).

**Result.** At the six sweeps where either account was logged at or over 8, the cap bound in **11 of 12** account-sweeps under the old count and **4 of 12** under the new one. At 06:16:09Z, the sweep the ruling cites, `next` falls from 14 to 3 and `next4` from 11 to 7, so neither is capped. KMAX stays 8.

## What changed in the count

`working_concurrency` in `bin/claude-accounts` used to call a transcript "working" when its file was modified in the last 10 minutes. It now:

1. judges a file by its last timestamped user or assistant record, not its mtime;
2. counts a session waiting on a tool call as working, for up to 30 minutes (`CC_ROUTE_KWORK_TOOLWAIT_MIN`);
3. counts a subagent only while it is unfinished. It is finished once its final answer is written, once its workflow run journal has a `result` or `failed` row for it, or once its parent has a task notification for it at or after its last record.

A file with no turn record is still judged by mtime. `bound_kwork` still caps the top-level term at the account's live processes. The kill switch `CC_ROUTE_KWORK_TURNS=off` restores the old count.

## Before and after

"Before" is the `k_work` logged in `~/.claude/logs/account-utilization.jsonl` at each sweep (after `bound_kwork`). The two replay columns re-run both rules over the same transcripts as they stood at that instant. Records stamped later are ignored, and files created later do not exist. A file's mtime at the instant is its newest record at or before it. "Bounded" applies `bound_kwork` with the logged pane count `k`. Headless process counts were not logged, so they are taken as 0.

| sweep (2026-09-29 UTC) | account | panes k | before: logged k_work | old rule replayed (top+sub → bounded) | new rule (top+sub → bounded) | at KMAX 8, before → after |
|---|---|---|---|---|---|---|
| 05:44:06 | next | 6 | 23 | 17+17 → 23 | 16+1 → 7 | capped → under |
| 05:44:06 | next4 | 11 | 7 | 6+1 → 7 | 6+0 → 6 | under → under |
| 05:50:28 | next | 6 | 10 | 5+5 → 10 | 4+0 → 4 | capped → under |
| 05:50:28 | next4 | 11 | 12 | 20+1 → 12 | 20+0 → 11 | capped → capped |
| 05:56:43 | next | 6 | 19 | 14+13 → 19 | 14+7 → 13 | capped → capped |
| 05:56:43 | next4 | 10 | 12 | 23+5 → 15 | 22+0 → 10 | capped → capped |
| 06:03:54 | next | 7 | 27 | 23+20 → 27 | 24+7 → 14 | capped → capped |
| 06:03:54 | next4 | 9 | 10 | 4+5 → 9 | 3+0 → 3 | capped → under |
| 06:16:09 | next | 6 | 14 | 3+9 → 12 | 3+0 → 3 | capped → under |
| 06:16:09 | next4 | 9 | 11 | 8+3 → 11 | 7+0 → 7 | capped → under |
| 06:21:15 | next | 5 | 11 | 3+7 → 10 | 3+0 → 3 | capped → under |
| 06:21:15 | next4 | 9 | 8 | 6+1 → 7 | 4+0 → 4 | capped → under |

**The replay is faithful.** The old rule, replayed, reproduces the logged value exactly in 8 of 12 cells. The largest gap is 3 (next4 at 05:56, 15 against 12). The gaps are consistent with the unlogged live-process counts that `bound_kwork` used.

**Where the cap still binds, it is real load.** At 05:56 and 06:03, `next` still carries 7 subagents. All are workflow agents with no terminal row in their run journal at that instant; 13 other workflow agents on the same account had already finished and are no longer counted. The rest of the remaining charge is top-level sessions with a turn in the last 10 minutes, capped at the live pane count. That half of the rule is unchanged by design: a session that ended a turn minutes ago is likely to take the next one.

**Live check, 2026-09-30 ~03:05Z.** Old and new rule differ by 1 on two accounts. `next3`'s top level goes from 1 to 2, a session waiting on a long tool call. `next2` goes from 2 to 1. The walk took 0.9 s under the new rule against 2.2 s cold under the old.

## Re-derive

```
python3 docs/research/lr-fleet-v2-decisions-2026-09-30/kmax-rebase.py bin/claude-accounts accounts.json \
  ~/.claude/logs/account-utilization.jsonl \
  2026-09-29T05:44:06+00:00,2026-09-29T05:50:28+00:00,2026-09-29T05:56:43+00:00,2026-09-29T06:03:54+00:00,2026-09-29T06:16:09+00:00,2026-09-29T06:21:15+00:00
```

The script loads the module and calls its own `_file_working` and `_session_settled`, so it measures the shipped rule rather than a copy of it. It prints one JSON row per account and sweep. The reconciler's census (`lr_recon/plan.py`) should use the same definition; that half belongs to wave W6d.
