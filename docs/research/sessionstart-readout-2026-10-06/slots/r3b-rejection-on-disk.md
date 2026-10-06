# R3b: limit rejections on disk, joined to the account-utilization series (slot r3b, 2026-10-06)

Scope: every weekly or 5-hour refusal recorded on disk in the last 30 days, joined to the utilization series and the wire-read log. The question is whether a zero-token, zero-network "this account was just refused" signal exists that the keepwarm producer could fold into the board before its next wire read.
Everything below is read-only. The scripts and intermediate JSON are under `/tmp/ssr-research/r3b_*.py` and `r3b-*.json`.

## Verdict

- **Yes, the signal exists and is already being written.** The StopFailure marker store `~/.claude/autonomy/stop-failure/rate_limit__<acct>.jsonl` is written by `hooks/stop-failure-marker.sh` when a session dies on a 429. It takes the account from the hook's own `CLAUDE_CONFIG_DIR`, so it is right even after a transplant.
  - **Timing (measured):** the marker landed within 2 s of the first transcript refusal in 13 of 13 wire-era onsets.
  - **Read cost (measured):** 0.107 ms p50 / 0.342 ms p99 in-process.
  - **False positives against the wire: none.** 197 of 197 markers that had a wire read within the next hour were followed by `rejected` for the same window.
- **Folding it in only at the regular tick buys little.** In the incident, the 06:04:46 keepwarm tick served a cache that already held the 06:03:49 `rejected` wire read. A fold at that tick changes nothing. The gain comes from making the board react to the event: kick the producer on the first marker, and let it fold the marker without a wire read. In the incident that shrinks the board's false "still accepts work" window from about 125 s (inferred) to a few seconds (estimated).
- **Do not use the existing derived indexes on the board path:**
  - `cc-limited --json` takes about 1 s per call.
  - `lr-fleet --locate --json` just runs `cc-limited` (`exec`).
  - The reconciler's `recon/facts/` ledger has three measured defects; see the candidate table in (iii).

## (a) Where the refusal is recorded in a transcript

`~/.claude-tertiary/projects/-Users-chrisren-Development-voiceink/4ad354fc-d65d-4275-8711-806b59e98e4b.jsonl.handed-off`, lines 2211, 2217 and 2222. The file was renamed `.handed-off` by the transplant; the same three records are copied into `~/.claude-secondary/.../4ad354fc-....jsonl` (lines 2211/2217/2222). Shape of line 2211, with IDs and paths elided:

```json
{"parentUuid":"<str>","isSidechain":false,"type":"assistant","uuid":"<str>","timestamp":"2026-10-06T06:03:04.512Z",
 "message":{"id":"<uuid>","model":"<synthetic>","role":"assistant","stop_reason":"stop_sequence","type":"message",
   "usage":{"input_tokens":0,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,...},
   "content":[{"type":"text","text":"You've hit your weekly limit · resets 7am (America/Chicago)"}]},
 "requestId":"<str>",
 "quotaLimits":{"status":"rejected","resetsAt":1791288000,"unifiedRateLimitFallbackAvailable":false,
   "rateLimitType":"seven_day","overageStatus":"rejected","overageDisabledReason":"org_level_disabled","isUsingOverage":false},
 "error":"rate_limit","isApiErrorMessage":true,"apiErrorStatus":429,"perTurnEffort":"high",
 "sessionId":"<str>","userType":"external","entrypoint":"cli","cwd":"<str>","version":"2.1.284","gitBranch":"<str>"}
```

- **Discriminators:** the top-level fields `isApiErrorMessage:true`, `error:"rate_limit"`, `apiErrorStatus:429` and `quotaLimits`. The `quotaLimits` object holds `rateLimitType` (`seven_day`/`five_hour`), `status`, and `resetsAt` (epoch; 1791288000 = 2026-10-06T12:00:00Z). The model is `<synthetic>` and all usage counts are 0, so the refusal itself cost zero tokens.
- **`quotaLimits` is only on error records.** In the incident transcript it appears 3 times in 2,233 lines, all on the three error records. Across tertiary and quaternary transcripts modified in the last 3 days: 141 `quotaLimits` lines, 154 API-error lines, and 0 non-error assistant records carrying `quotaLimits` (`rg -c` pass). So transcripts never carry an "allowed_warning" signal from a successful turn.
- **Versions:** `quotaLimits` is present on 2.1.260, 2.1.280 and 2.1.284 records (726/51/378 of them). It is absent on the 2.1.220 and 2.1.114 records (8), where only the text is available (`r3b_q2.py`).
- **Not every `rate_limit` is a quota wall.** Some `error:"rate_limit"` records are not account-wide quota refusals:
  - 35 are "You've reached your Fable limit…": model-scoped, 2026-09-10..12, with no `quotaLimits`.
  - 3 are "API Error: Server is temporarily limiting requests (not your usage limit)…" (next4, 2026-09-30T06:50Z).
  - Any classifier must key on `rateLimitType`, or on the text `hit your (weekly|session) limit`, never on `error` alone.
- **The StopFailure marker row** (`hooks/stop-failure-marker.sh`, the final `jq -cn … >> "$MARKER"` block) has the shape `{ts (second resolution), error, account, config_dir, session_id, cwd, transcript_path, hook_event_name:"StopFailure", pane, last_assistant_message (≤200 chars)}`. It carries no `resetsAt`/`rateLimitType`. Those can be read from `transcript_path`'s tail: 0.087 ms p50 in the timing below.

## Method (receipts)

- **Transcript scan:** `find <4 config dirs + ~/.claude-next4>/projects -name '*.jsonl*' -mtime -30 | xargs rg -F '"isApiErrorMessage":true'`, about 10 GB (`du -ck`).
  - 6.5 s wall (`r3b-scan.log`); 1,680 API-error records; 1,231 `rate_limit`.
  - These dedupe by `uuid` to 612 unique records, because transplant and salvage copies repeat them; 780 of the 1,231 are in `subagents/` transcripts.
  - `~/.claude-next/projects` is a symlink to `~/.claude/projects` and is scanned once.
- **Account attribution:**
  - Where a record exists in only one config dir: that dir (148 records).
  - Otherwise: the copy whose account's series `weekly_reset_at`/`session_reset_at` matches `quotaLimits.resetsAt` within 120 s (438), or the `.handed-off` copy (5).
  - 21 are ambiguous, all of them model-scoped.
  - 0 conflicts between path and reset-match (`r3b_join.py`).
- **Episodes:** consecutive refusals per account × window, split at gaps over 30 min (`r3b_episodes2.py`).
- **Board-state proxies:** the board itself has no history on disk, so two proxies are used:
  - The utilization series, `~/.claude/logs/account-utilization.jsonl` (44,586 rows). **It is decimated:** at most one batch per 300 s (`UTIL_MIN_INTERVAL_S = 300`, `bin/claude-accounts:5483`; gate at `:5510`). Its ~6 min row spacing is the recorder's rate limit, not the sweep cadence.
  - The wire-read log, `~/.claude/logs/claude-accounts.log` `probe <acct>: wire — …` lines: 4,755 reads with millisecond timestamps since 2026-09-19T19:45Z. This is the true sweep record, and lag B below is measured on it (`r3b_wirejoin.py`).
- **Board writes:** keepwarm tick times come from `log show --predicate 'eventMessage CONTAINS "com.claude.accounts-keepwarm"'` (run by this slot). A `stat` poll of `/tmp/claude-accounts-board.txt` saw writes at 06:21:15, 06:24:31 and 06:27:31Z, one per keepwarm tick (~180 s).

## (i) Refusal events, last 30 days (2026-09-06 .. 2026-10-06)

- **Totals:** 606 unique `rate_limit` records. 568 of them are quota refusals (5h/7d) across 123 sessions:
  - next: 187 × 5h, 21 × 7d
  - next2: 51 × 5h, 32 × 7d
  - next3: 21 × 5h, 49 × 7d
  - next4: 126 × 5h, 81 × 7d
- **55 episodes.** "Latest series row then" is the newest utilization row before the first refusal ("aw" = `allowed_warning`). "First sid" is the session of the first refusal.
- **Config dirs:** next = `~/.claude-next` (same projects tree as `~/.claude`), next2 = `~/.claude-secondary`, next3 = `~/.claude-tertiary`, next4 = `~/.claude-quaternary` (`~/.claude/accounts.json`).

| # | first refusal (UTC) | acct | config dir | first sid | window | recs / sids | latest series row then | message (first) |
|---|---|---|---|---|---|---|---|---|
| 1 | 09-08T23:09:32 | next2 | ~/.claude-secondary | 6e29fee9 | 5h | 7 / 3 | accepting(meter 86%) | session limit · resets 7:50pm (Chicago) |
| 2 | 09-08T23:51:27 | next2 | ~/.claude-secondary | e5a9e11d | 5h | 3 / 3 | REFUSED(meter 100%) | session limit · resets 7:50pm (Chicago) |
| 3 | 09-09T05:15:43 | next2 | ~/.claude-secondary | 52e35019 | 5h | 7 / 3 | accepting(meter 96%) | session limit · resets 12:50am (Chicago) |
| 4 | 09-10T05:47:32 | next | ~/.claude-next | 25de8822 | 5h | 83 / 7 | accepting(meter 87%) | session limit · resets 2:30am (Chicago) |
| 5 | 09-10T06:43:43 | next | ~/.claude-next | 2d71c6d8 | 5h | 3 / 3 | REFUSED(meter 100%) | session limit · resets 2:30am (Chicago) |
| 6 | 09-10T13:40:54 | next4 | ~/.claude-quaternary | 0e586e90 | 5h | 7 / 3 | accepting(meter 69%) | session limit · resets 1:10pm (Chicago) |
| 7 | 09-10T13:44:47 | next | ~/.claude-next | 7193ec2b | 5h | 98 / 6 | accepting(meter 87%) | session limit · resets 11:40am (Chicago) |
| 8 | 09-10T14:25:20 | next3 | ~/.claude-tertiary | dfad6fcd | 5h | 5 / 4 | accepting(meter 81%) | session limit · resets 2pm (Chicago) |
| 9 | 09-10T15:24:09 | next4 | ~/.claude-quaternary | 982be072 | 5h | 2 / 1 | REFUSED(meter 100%) | session limit · resets 1:10pm (Chicago) |
| 10 | 09-10T15:30:01 | next | ~/.claude-next | 06f419d9 | 5h | 1 / 1 | REFUSED(meter 100%) | session limit · resets 11:40am (Chicago) |
| 11 | 09-10T16:24:30 | next3 | ~/.claude-tertiary | f09d1c7b | 5h | 4 / 4 | REFUSED(meter 100%) | session limit · resets 2pm (Chicago) |
| 12 | 09-10T16:34:06 | next | ~/.claude-next | 6f00af69 | 5h | 2 / 1 | REFUSED(meter 100%) | session limit · resets 11:40am (Chicago) |
| 13 | 09-10T16:43:01 | next4 | ~/.claude-quaternary | 3870af4e | 5h | 3 / 3 | REFUSED(meter 100%) | session limit · resets 1:10pm (Chicago) |
| 14 | 09-10T20:55:32 | next4 | ~/.claude-quaternary | 6b8b69c2 | 5h | 29 / 5 | REFUSED(meter 100%) | session limit · resets 6:30pm (Chicago) |
| 15 | 09-12T03:55:02 | next2 | ~/.claude-secondary | 82354751 | 7d | 9 / 1 | REFUSED(meter 100%) | weekly limit · resets 6am (Chicago) |
| 16 | 09-12T22:30:40 | next4 | ~/.claude-quaternary | d83af9ce | 7d | 32 / 2 | REFUSED(meter 100%) | weekly limit · resets 4am (Chicago) |
| 17 | 09-14T15:27:55 | next3 | ~/.claude-tertiary | 5e0d69f7 | 7d | 4 / 4 | REFUSED(meter 100%) | weekly limit · resets 7am (Chicago) |
| 18 | 09-15T04:03:48 | next3 | ~/.claude-tertiary | 26a195ae | 7d | 1 / 1 | REFUSED(meter 100%) | weekly limit · resets 7am (Chicago) |
| 19 | 09-16T23:00:01 | next2 | ~/.claude-secondary | cc1f8d0a | 5h | 8 / 1 | accepting(meter 96%) | session limit · resets 7:30pm (Chicago) |
| 20 | 09-16T23:36:15 | next2 | ~/.claude-secondary | cc1f8d0a | 5h | 1 / 1 | REFUSED(meter 100%) | session limit · resets 7:30pm (Chicago) |
| 21 | 09-19T16:58:33 | next4 | ~/.claude-quaternary | e442434c | 5h | 12 / 5 | accepting(meter 87%) | session limit · resets 2:40pm (Chicago) |
| 22 | 09-19T19:28:05 | next4 | ~/.claude-quaternary | fff83638 | 5h | 2 / 2 | REFUSED(meter 100%) | session limit · resets 2:40pm (Chicago) |
| 23 | 09-19T19:52:33 | next3 | ~/.claude-tertiary | 98f02458 | 5h | 12 / 8 | accepting (wire aw 0.99) | session limit · resets 4:30pm (Chicago) |
| 24 | 09-19T21:35:29 | next4 | ~/.claude-quaternary | 7f533f05 | 7d | 22 / 5 | REFUSED(meter 100%) | weekly limit · resets 4am (Chicago) |
| 25 | 09-19T21:40:08 | next | ~/.claude-next | c0f857b6 | 7d | 3 / 3 | REFUSED(meter 100%) | weekly limit · resets 11pm (Chicago) |
| 26 | 09-19T22:57:38 | next | ~/.claude-next | df12fe89 | 7d | 1 / 1 | REFUSED (wire rej 1.0) | weekly limit · resets 11pm (Chicago) |
| 27 | 09-22T08:03:45 | next3 | ~/.claude-tertiary | 3c73a9d9 | 7d | 5 / 1 | accepting (wire aw 0.99) | weekly limit · resets 7am (Chicago) |
| 28 | 09-22T09:01:43 | next3 | ~/.claude-tertiary | b6125384 | 7d | 1 / 1 | REFUSED (wire rej 1.0) | weekly limit · resets 7am (Chicago) |
| 29 | 09-22T10:13:02 | next3 | ~/.claude-tertiary | 696eb098 | 7d | 1 / 1 | REFUSED(meter 100%) | weekly limit · resets 7am (Chicago) |
| 30 | 09-22T11:00:02 | next3 | ~/.claude-tertiary | 7c8201f8 | 7d | 1 / 1 | REFUSED (wire rej 1.0) | weekly limit · resets 7am (Chicago) |
| 31 | 09-22T11:41:49 | next3 | ~/.claude-tertiary | b6125384 | 7d | 2 / 2 | REFUSED (wire rej 1.0) | weekly limit · resets 7am (Chicago) |
| 32 | 09-24T22:18:49 | next2 | ~/.claude-secondary | 4a956c3b | 7d | 7 / 3 | accepting (wire aw 0.99) | weekly limit · resets Sep 26 at 6am (Chicago) |
| 33 | 09-26T20:23:53 | next | ~/.claude-next | 60ccb8f4 | 7d | 7 / 2 | accepting (wire aw 0.99) | weekly limit · resets 11pm (Chicago) |
| 34 | 09-26T22:19:33 | next4 | ~/.claude-quaternary | adb89f78 | 7d | 5 / 2 | accepting (wire aw 0.99) | weekly limit · resets 4am (Chicago) |
| 35 | 09-26T23:03:13 | next4 | ~/.claude-quaternary | 18e3fd78 | 7d | 2 / 2 | REFUSED (wire rej 1.0) | weekly limit · resets 4am (Chicago) |
| 36 | 09-27T01:11:14 | next4 | ~/.claude-quaternary | 798afadf | 7d | 1 / 1 | REFUSED (wire rej 1.0) | weekly limit · resets 4am (Chicago) |
| 37 | 09-27T04:52:54 | next4 | ~/.claude-quaternary | adb89f78 | 7d | 2 / 1 | REFUSED (wire rej 1.0) | weekly limit · resets 4am (Chicago) |
| 38 | 09-29T03:02:05 | next3 | ~/.claude-tertiary | 415a3aac | 7d | 10 / 2 | accepting (wire aw 0.99) | weekly limit · resets 7am (Chicago) |
| 39 | 09-29T03:58:07 | next2 | ~/.claude-secondary | 7c395da7 | 5h | 18 / 4 | accepting (wire aw 0.99) | session limit · resets 1:30am (Chicago) |
| 40 | 09-29T05:32:07 | next2 | ~/.claude-secondary | 0715cd0c | 5h | 1 / 1 | REFUSED (wire rej 1.0) | session limit · resets 1:30am (Chicago) |
| 41 | 09-29T06:17:22 | next2 | ~/.claude-secondary | 84f3533b | 5h | 6 / 3 | REFUSED (wire rej 1.0) | session limit · resets 1:30am (Chicago) |
| 42 | 09-30T07:09:48 | next2 | ~/.claude-secondary | c8c2adc0 | 7d | 6 / 4 | accepting (wire aw 0.99) | weekly limit · resets Oct 3 at 6am (Chicago) |
| 43 | 09-30T10:49:51 | next2 | ~/.claude-secondary | 68691067 | 7d | 1 / 1 | REFUSED (wire rej 1.0) | weekly limit · resets Oct 3 at 6am (Chicago) |
| 44 | 09-30T15:01:48 | next2 | ~/.claude-secondary | c8c2adc0 | 7d | 4 / 1 | REFUSED (wire rej 1.0) | weekly limit · resets Oct 3 at 6am (Chicago) |
| 45 | 09-30T15:45:14 | next2 | ~/.claude-secondary | c8c2adc0 | 7d | 1 / 1 | REFUSED (wire rej 1.0) | weekly limit · resets Oct 3 at 6am (Chicago) |
| 46 | 09-30T21:26:29 | next2 | ~/.claude-secondary | 4d7c9bce | 7d | 2 / 1 | REFUSED (wire rej 1.0) | weekly limit · resets Oct 3 at 6am (Chicago) |
| 47 | 09-30T21:58:15 | next2 | ~/.claude-secondary | ceaa8922 | 7d | 2 / 1 | REFUSED (wire rej 1.0) | weekly limit · resets Oct 3 at 6am (Chicago) |
| 48 | 10-01T19:59:04 | next4 | ~/.claude-quaternary | 13d7be20 | 7d | 17 / 15 | accepting (wire aw 0.99) | weekly limit · resets Oct 4 at 4am (Chicago) |
| 49 | 10-01T20:52:18 | next | ~/.claude-next | 492a787a | 7d | 7 / 2 | accepting (wire aw 0.99) | weekly limit · resets Oct 3 at 11pm (Chicago) |
| 50 | 10-01T21:39:11 | next | ~/.claude-next | 492a787a | 7d | 1 / 1 | REFUSED (wire rej 1.0) | weekly limit · resets Oct 3 at 11pm (Chicago) |
| 51 | 10-01T23:40:58 | next | ~/.claude-next | 40ebc527 | 7d | 1 / 1 | REFUSED (wire rej 1.0) | weekly limit · resets Oct 3 at 11pm (Chicago) |
| 52 | 10-02T01:20:02 | next | ~/.claude-next | c28362b6 | 7d | 1 / 1 | REFUSED (wire rej 1.0) | weekly limit · resets Oct 3 at 11pm (Chicago) |
| 53 | 10-02T01:50:22 | next3 | ~/.claude-tertiary | 0962ca47 | 7d | 11 / 3 | accepting (wire aw 0.99) | weekly limit · resets Oct 6 at 7am (Chicago) |
| 54 | 10-04T07:55:54 | next4 | ~/.claude-quaternary | b671b47e | 5h | 71 / 13 | accepting(meter 98%) | session limit · resets 4:40am (Chicago) |
| 55 | 10-06T06:02:41 | next3 | ~/.claude-tertiary | e131c8d2 | 7d | 13 / 3 | accepting (wire aw 0.99) | weekly limit · resets 7am (Chicago) |

- **21 of 55 episodes are onsets** (the latest row showed the window as not refused). The other 34 are re-hits on an account the series already showed as refused (`r3b_stats.py`).
- **Onsets in the meter era** (before 2026-09-19T19:50Z, no wire fields): 8, measured on the decimated series.
  - First refusal to first refused row: median 188 s, max 905 s.
  - 168 refusals from 19 sessions fell inside those windows.
  - The meter read as low as 69% at a 5h refusal (#6).
- **Onsets in the wire era:** 13. In 12 of them the last reading was wire `allowed_warning 0.99`; #54 was meter 98% with no wire read in band.
- **Correction to the plan's incident line:** the first refusal on next3 was session **e131c8d2** (a subagent turn) at **06:02:41.736Z**, 22.8 s before 4ad354fc's at 06:03:04.512Z.

## (ii) Lag: last non-refused reading → refusal → first refused reading (wire-era onsets)

Lag A = first refusal minus the last reading that showed the window as not refused. Lag B = first refused wire read minus first refusal. Both are measured on the millisecond probe log, except #23 (no 5h `rejected` probe exists for next3; series used) and #54's lag A (series). The marker lag is the first marker for that account and window, minus the first transcript refusal (marker `ts` has 1 s resolution).

| ep | first refusal (UTC, ms) | acct/win | k | last non-refused reading before it | lag A (s) | first refused reading after | lag B (s) | lag B on decimated series (s) | marker lag (s) | refusals / sessions inside B |
|---|---|---|---|---|---|---|---|---|---|---|
| 23 | 09-19T19:52:33.116 | next3/5h | 8 | 19:50:07 wire aw 0.99 | 145.7 | 19:57:17 series meter 100% | 284 | 284 | 0 | 5 / 3 |
| 27 | 09-22T08:03:45.319 | next3/7d | 18 | 08:00:21 wire aw 0.99 | 204.3 | 08:05:32 wire rejected | 107.0 | 107 | -2 | 5 / 1 |
| 32 | 09-24T22:18:49.183 | next2/7d | 3 | 22:02:00 wire aw 0.99 | 1008.6 | 22:26:41 wire rejected | 472.7 | 475 | 1 | 7 / 3 |
| 33 | 09-26T20:23:53.916 | next/7d | 3 | 20:21:00 wire aw 0.99 | 173.1 | 20:24:06 wire rejected | 12.9 | 139 | 0 | 2 / 1 |
| 34 | 09-26T22:19:33.990 | next4/7d | 4 | 22:16:17 wire aw 0.99 | 196.7 | 22:19:39 wire rejected | 5.9 | 19 | 0 | 2 / 1 |
| 38 | 09-29T03:02:05.992 | next3/7d | 3 | 03:01:39 wire aw 0.99 | 26.5 | 03:04:21 wire rejected | 135.9 | 317 | 0 | 10 / 2 |
| 39 | 09-29T03:58:07.500 | next2/5h | 6 | 03:57:55 wire aw 0.99 | 12.0 | 04:01:02 wire rejected | 174.7 | 362 | 0 | 14 / 1 |
| 42 | 09-30T07:09:48.729 | next2/7d | 6 | 07:08:18 wire aw 0.99 | 90.4 | 07:10:56 wire rejected | 67.5 | 122 | 0 | 4 / 2 |
| 48 | 10-01T19:59:04.050 | next4/7d | 14 | 19:56:56 wire aw 0.99 | 127.4 | 19:59:08 wire rejected | 4.8 | 7 | 0 | 1 / 1 |
| 49 | 10-01T20:52:18.662 | next/7d | ? | 20:50:46 wire aw 0.99 | 92.2 | 20:54:41 wire rejected | 143.1 | 25 (meter) | 0 | 6 / 1 |
| 53 | 10-02T01:50:22.975 | next3/7d | 18 | 01:47:30 wire aw 0.99 | 173.0 | 01:51:05 wire rejected | 42.1 | 54 | 1 | 10 / 2 |
| 54 | 10-04T07:55:54.804 | next4/5h | ? | 07:53:32 series meter 98% | 142 | 07:56:52 wire rejected | 58.0 | 278 | 2 | 46 / 7 |
| 55 | 10-06T06:02:41.736 | next3/7d | 11 | 06:01:41.857 wire aw 0.99 | 59.9 | 06:03:49.211 wire rejected | 67.5 | 329 | 0 | 11 / 3 |

- **Summary, measured (`r3b_final.py`):**
  - Lag A: median 142 s (range 12–1009 s).
  - Lag B: median 67.5 s, max 472.7 s, 1,576 s in total over 30 days.
  - 123 refusals from 28 sessions happened while the newest sweep still said "accepting".
  - The decimated series doubles lag B (median 139 s). Any R3/R4 figure built on series spacing alone overstates it.
- **Lag B is a lower bound for the board.** Only keepwarm writes the board, about every 180 s. A sweep by another process reaches the board only at the next tick.
- **Incident timeline, 2026-10-06 (UTC):**
  - Wire reads (`claude-accounts.log`): 06:01:41.857 aw 0.99 → 06:03:49.211 rejected 1.0 → 06:05:29 → 06:07:56.
  - Keepwarm ticks (`log show`): 06:01:40.885–06:01:46.138; 06:04:46.156–06:04:47.154 (1.0 s, consistent with `served-cache`); 06:07:47.170–06:08:13.876 (26.7 s, swept; this tick wrote the 06:08:11 series row).
  - The only sweep between the 06:01:46 and 06:04:46 board writes is the 06:03:49 probe.
  - **Inferred board blind window:** 06:02:41.736 → 06:04:47.154 = **125.4 s**, holding 11 refusals from 3 sessions (e131c8d2, 4ad354fc, 7913752f). There is no board archive, so this is inferred from tick timing plus the probe log, not observed.
- **Is the account at the wall when this happens?** Time at wire ≥0.99 (not rejected) before an onset ranged from 8 s to 10,455 s. The incident had 28 consecutive 0.99 reads (2.9 h) before the refusal (`r3b_stats.py`).
- **Routing harm inside the window:** `account-assignments.jsonl` starts 2026-10-02T01:33Z. For the 3 onsets after that, it records 0 assignments to the refused account in [first refusal, first rejected read + 180 s]. The measurable harm is the board's claim, not new placements.

## (iii) Candidate signals: where, latency, cost, false-positive risk

| candidate | where | appears | read cost (measured unless noted) | false-positive / blind risk | verdict |
|---|---|---|---|---|---|
| **StopFailure marker** | `~/.claude/autonomy/stop-failure/rate_limit__<acct>.jsonl` (hook `hooks/stop-failure-marker.sh`, registered `StopFailure` in `~/.claude/settings.json:1073`, symlinked into every config dir) | within ≤2 s of the transcript record (13/13 onsets) | `stat`×4: 0.009 ms p50 / 0.017 p99; tail 8 KB×4 + parse: 0.107 / 0.342 ms (`r3b_timeit.py`, 200 iters, warm) | **Against the wire:** 0/197 contradicted. **Coverage:** 203/207 deduped quota refusals since 09-20 have a same-sid marker within ±5 s; the 3 main-chain misses (next4, 2026-10-01T20:16:12–29Z) were inside a mass cap that other sessions' markers covered within 1 s. **Account:** from the hook env, so transplant-safe. **Risks:** (1) the file also takes non-quota `rate_limit` text (model-scoped, server-throttle), so filter on text. (2) The hook stops appending at 500 lines (`CAP=500`, early exit before the append), which freezes the file until the 7-day mtime GC; `cc-limited` checks a cap of 5000 (`bin/cc-limited:93`), so it would never flag this. (3) Whole files are GC'd 7 days after their last touch, so it is not a 30-day archive (earliest surviving row 2026-09-19T19:52:33Z; the next4 file restarted 09-26). | **Use**, as the producer's input |
| transcript `quotaLimits` record | `<cfg>/projects/<slug>/<sid>.jsonl[.handed-off]`, `subagents/*.jsonl` | at the refusal (ms) | full scan 6.5 s / ~10 GB; per-marker tail via `transcript_path` 0.087 ms p50 | **Path misattributes after a transplant:** one record lives in 2–4 copies under different config dirs (612 unique records vs 1,231 copies). Needs dedupe by uuid plus `resetsAt` matching. | Use only as an **enrichment** of a marker (`rateLimitType`, `resetsAt`), never as a scan |
| `cc-limited --json [--all]` | `~/.claude/bin/cc-limited` (read-only without `--reaper --persist`/`--kitty`/`ack`; writes only at `:1007-1023`, `:1073-1076`) | at read time, from the markers plus transcript tails plus `ps` | 2,745 / 1,042 / 911 / 945 / 1,197 ms (5 runs, 111 KB, 97 session rows) | Per session, not per account; attribution correct (`acct_death` next3, `cap seven_day`, `resets_at` 1791288000, `resets_source quotaLimits` for e131c8d2/4ad354fc/7913752f) | Correct but about 10⁴× the cost of reading the markers; do not fork it per tick and never from the hook |
| `lr-fleet.sh --locate --json` | `~/.claude/scripts/limit-recover/lr-fleet.sh:1451-1457` | same | runs `cc-limited --all --json` (`exec`), plus bash start-up (not run; same output by construction) | same | Same as `cc-limited`; the non-JSON `--locate` also runs the husk arm (not run) |
| reconciler fact ledger | `~/.reso/limit-recover/recon/facts/<acct>.<scope>.json` (`lr_recon/facts.py`) | at reconciler census cadence (`src:"census"`); hook ARM 3 is off (`recon.on` absent) | 0.103 ms p50 | **Measured defects:** (1) `next2.7d.json` `first_sid 4ad354fc`, `observed_at` 06:10:22.955Z, `resets_at` 2026-10-06T12:00Z (next3's reset; next2's is 2026-10-10T11:00Z) blames next2 for next3's refusals, copied in by the 06:09:33Z handoff. (2) `next3.7d.json` kept `observed_at` 2026-10-02T01:50:20Z (merge keeps the first, `facts.py:95-110`) through an early server reset: next3's meter went to 0 at 2026-10-02T01:58:01Z with `weekly_reset_at` unchanged. (3) `_wire_clears` reads `wire.read_at` (`facts.py:231-249`), which no producer writes; `claude-accounts` stamps `row["wire_at"]` (`bin/claude-accounts:1961`). `blocking()` ignores `contradicted`. | **Reject** for the board |
| claude-accounts wire-probe log | `~/.claude/logs/claude-accounts.log` | per sweep (~100–150 s apart at the wall) | not zero-token: each read is one inference call | it is the wire itself | Use as the measuring instrument only (this report) |
| `cc-beats` `limited` beats | `~/.claude/cc-beats/<sid>.json` (6,914 files) | at death (written by the hook's limited arm) | full enumeration 1,450 ms | Per session; no top-level `kind:"limited"` found in this pass (schema not examined further) | Reject (cost) |
| parked records / requests | `~/.reso/limit-recover/parked/`, `requests/` | after the poller parks, or drained and deleted | not measured | lag behind the death; requests are transient | Not pursued |

## (d) Folding the marker into the board: cost, rule, and where it actually helps

- **Cost per keepwarm tick (measured).** Reading the four marker tails costs 0.107 ms p50 / 0.342 ms p99. Optionally add one 128 KB transcript-tail read per new marker for `rateLimitType`/`resetsAt` (0.087 ms p50). For scale, a tick costs 390–26,206 ms (`accounts-keepwarm.out.log` tail). The SessionStart hook is untouched.
- **Rule** (mirrors `_place_fact_live`, `bin/claude-accounts:5043-5061`, which already encodes "rejected until reset+60 or a newer allowed wire read"; adds the early-reset clause it lacks):
  ```
  for each account a, after get_data, before write_board (bin/claude-accounts ~7795-7810):
    m := newest line of rate_limit__<a>.jsonl with account==a whose last_assistant_message
         starts "You've hit your weekly limit" (win=7d) or "You've hit your session limit" (win=5h)
         # never: "reached your <Model> limit", "not your usage limit", or error alone
    if m is None                                   -> no observed refusal
    if row.wire_at >= m.ts                         -> wire governs (both directions)
    reset := quotaLimits.resetsAt from m.transcript_path tail, else row.{weekly,session}_reset_at
    if now >= reset + 60                           -> expired
    if meter(win) now < meter(win) at first sweep after m.ts   -> early-reset evidence, expired
    else row.observed_refusal = {win, at: m.ts, age_s: now - m.ts, sid8, sessions since wire_at}
  ```
  - **Consumers:**
    - `wire_rejects(r, win)` (`bin/claude-accounts:1371`): its contract is "may only ever ADD a refusal the endpoint could not see". It, and therefore `weekly_headroom`, routing, `board_eff`, `pct_text` and the wall note, would read the observed refusal as refused.
    - The note would carry the age ("refused 1m 59s ago: a session hit the weekly limit"). It must never say "still accepts work" while `observed_refusal` is set.
  - **Fit with the measured data.** The wire never contradicted a marker (0/197), so the `wire_at >= m.ts` hand-back loses nothing. The early-reset clause is needed: without it, the Oct 2 → Oct 6 next3 case would have held next3 "refused" for about 4 days while it kept serving sessions (k 16–18 in the rows right after the reset). That is exactly what the facts ledger did.
- **Where it helps (reasoned from the measured timings):**
  - **Fold-at-tick alone:** it helps only when a tick serves a cache whose newest sweep predates the refusal. In the incident the 06:04:46 tick's cache already held the 06:03:49 rejected read (inferred from the 1.0 s tick plus the probe log), so the gain was 0 s.
  - **Event kick:** inside the hook's existing `rate_limit` limited arm, for quota text only, run `launchctl kickstart gui/$UID/com.claude.accounts-keepwarm`. This is the same bare-kickstart pattern the arm already uses for `com.reso.lr-reset-poller` behind `$LIM/.kick-on`. It would sit behind its own O_EXCL latch keyed `<acct>__<win>` with a short TTL.
    - The page latch cannot be reused: it is keyed on message text that repeats weekly, with a 7-day TTL.
    - The kicked tick then folds the marker. With cache age under `--max-age 90` it serves the cache (0.4–1.0 s ticks measured), so it makes no wire read and spends zero tokens.
    - **Incident replay (estimated):** a kick at 06:02:42 → board shows next3 refused by about 06:02:43–06:02:48, against the inferred 06:04:47 (125 s down to about 2–6 s).
    - **Death-path cost:** one `launchctl` fork, for the latch winner only. Its ms cost is not measured.
- **Hard constraints.** This keeps all four: the hook is not touched, the producer spends zero tokens and zero network, and wire reads stay gated to near-wall accounts (a kicked tick that does sweep stays inside the existing `wire_wanted` gate, `bin/claude-accounts:1338`). The render can stay inline; the open question is whether a session-observed refusal may print "100%".

## Alternatives considered

- **Hook-side `[ rate_limit__X -nt board ]`** (bash builtin, zero forks). Rejected as primary: the hook cannot tell weekly from session from model-scoped from server-throttle text without reading the line, and the brief keeps the hook a pure board read.
- **Recompute from transcripts per tick:** 6.5 s scan plus copy misattribution. Rejected.
- **Fork `cc-limited` per tick:** about 1 s, and per session. Rejected; the board needs a per-account bit.
- **Force a wire read on each new marker:** accurate, but spends one inference call per event that the marker already answers (0/197 contradictions). Not needed.

## Blockers named

1. **Marker cap.** At 500 lines the marker file stops growing (the hook's cap exit sits before the append), so a reader sees a frozen last row. A reader must treat line count ≥ 500 as degraded, or the hook's cap must move. The files currently hold 21/48/59/98 lines for next/next2/next3/next4.
2. **The ruling on "100%".** The operator ruling reserves "100%" for a server-confirmed refusal. A session's 429 with `quotaLimits.status:"rejected"` is the server's own refusal, but it is not the producer's read. Whether it may print "100%" or needs its own inline state is the operator's call.
3. **Untested kickstart behaviour.** Neither `launchctl kickstart` against a running keepwarm instance nor any launchd throttle on repeated kicks is measured.
