# P1-stopfail-coverage — receipts

Unit: does StopFailure fire on EVERY cap-class death and on teammate/assignee sessions?
Run 2026-09-19, read-only. Verdict **PARTIAL** — holds for `cli`; refuted for `sdk-cli`;
`monthly_spend` UNMEASURABLE; teammate UNMEASURABLE for cap-class, proven for `server_error`.

Artifacts in this directory: `hits.txt` (626 files), `records.json` (641 records),
`idl-sf.jsonl` (604 IDL rows), `main-joined.json`, `scan.py`. Analysis scripts `/tmp/p1join2.py`,
`/tmp/p1final.py`, `/tmp/p1ent.py`, `/tmp/p1side.py`, `/tmp/p1rev.py`.

## 0. Method + the instrument bug that nearly voided this unit

```
cd ~ && grep -rlF '"error":"rate_limit"' .claude/projects .claude-tertiary/projects .claude-quaternary/projects
  => 626 files    (hits.txt)
```

3 physical transcript stores, not 4 — `~/.claude-next/projects` is a symlink onto `~/.claude/projects`:

```
for d in ~/.claude ~/.claude-next ~/.claude-tertiary ~/.claude-quaternary; do readlink -f "$d/projects"; done
  => /Users/chrisren/.claude/projects
     /Users/chrisren/.claude/projects        <-- next SHARES .claude's store
     /Users/chrisren/.claude-tertiary/projects
     /Users/chrisren/.claude-quaternary/projects
ls -d ~/.claude-next2  => No such file or directory     # 4 config dirs exist, not 5
```

StopFailure is registered in all 4 that exist:

```
jq -r '[.hooks.StopFailure[]?.hooks[]?.command]|join(",")' <dir>/settings.json
  ~/.claude            => ~/.claude/hooks/stop-failure-marker.sh
  ~/.claude-next       => ~/.claude/hooks/stop-failure-marker.sh
  ~/.claude-tertiary   => ~/.claude/hooks/stop-failure-marker.sh
  ~/.claude-quaternary => ~/.claude/hooks/stop-failure-marker.sh
```

**INSTRUMENT BUG, recorded because it produced a confident false finding.** macOS `zcat` on a `.gz`
given as an ARGUMENT silently produces nothing (it wants `.Z`). My first IDL collection,
`(zcat idl.jsonl.*.gz; cat idl.jsonl) | grep stop-failure-marker`, returned **33 rows** and made the
hook look dead before 2026-09-18 — an apparent 66.7% session miss rate. The positive control that
caught it:

```
gunzip -c idl.jsonl.20260910T212018Z.gz | jq -r '.hook//.actor' | sort | uniq -c | sort -rn
  => ... 308 stop-failure-marker   # 308 rows in ONE archive the "33-row" scan said were absent
```

Correct collection (`gunzip -c`, never `zcat <file>`): **604 rows**. Every number below uses that.

Window: hook symlink deployed `Sep 7 00:31`
(`ls -la ~/.claude/hooks/stop-failure-marker.sh` => `-> /Users/chrisren/Development/claude-infrastructure/hooks/stop-failure-marker.sh`),
landed `53edbbcf3 2026-09-06 16:40:45 -0700`. IDL evidence begins at the earliest surviving archive
row, `2026-09-08T08:22:09Z` — **2026-09-06 → 2026-09-08 is UNMEASURABLE** (rotation, not absence).

## 1. Headline join — record level, ±5 s, same sid

```
UNIQUE main-transcript rate_limit records (dedup by sid+uuid): 128
matched: 126   missed: 2   miss_rate = 1.6%
latency (api-error record ts -> StopFailure IDL ts): min 0  p50 0  p95 1  max 1  seconds
latency histogram: {0s: 115, 1s: 11}
per class:  five_hour n=105 miss=2 | seven_day n=10 miss=0 | quotaLimits-NULL (Fable) n=13 miss=0
SESSION level: 42 sessions with >=1 main-transcript rate_limit record, 2 with no StopFailure row
```

Corpus shape (`scan.py` output): 641 rate_limit api-error records since 2026-09-06 across 536 files,
17 of them `.handed-off`; all `version: 2.1.260`; 483 `isSidechain:true`; `rateLimitType` =
five_hour 532 / seven_day 41 / null 68.

## 2. THE MISS IS `sdk-cli`, AND IT IS NOT A HOOK-LOADING PROBLEM

```
MISS sid=18227cc7-1b51-4f7c-861d-93efda60251b ts=2026-09-10T17:03:14Z five_hour store=.claude-quaternary idl_rows_for_sid=0
MISS sid=f367a503-649d-4044-9430-c42d1f21db95 ts=2026-09-10T17:03:25Z five_hour store=.claude-tertiary   idl_rows_for_sid=0
```

Entrypoint split over all 42 dying sessions:

```
Counter({('cli','HIT'): 39, ('sdk-cli','MISS'): 2, ('?','HIT'): 1})
```

These two are the **only** `sdk-cli` transcripts in the entire 626-file rate_limit corpus:

```
while read p; do grep -qF '"entrypoint":"sdk-cli"' "$HOME/$p" && echo "$p"; done < hits.txt
  => .claude-tertiary/.../f367a503-….jsonl
     .claude-quaternary/.../18227cc7-….jsonl        (2 of 626)
```

The session was a `-p` probe that lived 3 seconds (`queue-operation enqueue 17:03:13.471` →
api-error `17:03:14.386`). **Other hooks DID run in it**, so hook loading is not the cause:

```
gunzip -c idl.jsonl.*.gz | grep 18227cc7-1b51-4f7c-861d-93efda60251b
 {"ts":"2026-09-10T17:03:11Z","hook":"desk-brief-inject","disposition":"abstained","reason":"other-holder"}
 {"ts":"2026-09-10T17:03:11Z","hook":"session-register","disposition":"refused",
  "reason":"pane 69 held by live ancestor pid 45903 — nested session, not the tenant"}
 # …and NO stop-failure-marker row, 3 s later, at the death.
```

=> **StopFailure does not reach the headless/SDK death path** while SessionStart-family hooks do.
Mechanism (event never emitted vs. process exits before dispatch) is UNMEASURED. n=2 — thin, but it
is 100% of the sdk-cli population and 100% of the misses.

## 3. `monthly_spend` does not exist as a cap class — UNMEASURABLE, not covered

```
grep -rhoE '"error":"[a-z_]+","isApiErrorMessage":true' --include='*.jsonl' --include='*.handed-off' \
     .claude/projects .claude-tertiary/projects .claude-quaternary/projects | sort | uniq -c | sort -rn
  677 "error":"rate_limit"
  182 "error":"server_error"
   56 "error":"authentication_failed"
   12 "error":"invalid_request"
    4 "error":"unknown"
    3 "error":"oauth_org_not_allowed"
```

No `monthly_spend`, ever, in any store. The "You've hit your monthly spend limit" string the premise
quotes matches 5,336 files — because it is text inside the **limit-recover skill description
injected into every session's context**, not an api-error record. Do not count it.
`quotaLimits.rateLimitType` only ever takes `five_hour` or `seven_day`; it is `null` on 68 records,
all of them the Fable-scoped cap.

## 4. Fable-scoped cap: COVERED, but the cause key cannot express it

13 unique Fable-scoped records (`quotaLimits: null`, text
`You've reached your Fable limit. Run /usage-credits to continue or switch models with /model.`),
**0 missed**. But the marker path is `rate_limit__<acct>.jsonl` — keyed on `error` + account
(`hooks/stop-failure-marker.sh:92-93`, `CAUSE_KEY="$(_sf_slug "$ERR")__$(_sf_slug "$ACCOUNT")"`), and
`error` is `rate_limit` for both. Measured collision inside ONE session:

```
sid 7193ec2b  five_hour:11, NULL(Fable):7     # both classes, one session, one marker file
sid 2d71c6d8  five_hour:13, NULL(Fable):10
sid 6b8b69c2  five_hour:3,  NULL(Fable):3
```

=> a consumer reading the marker FILENAME cannot separate a five-hour cap from a Fable-only cap
(which is cleared by `/model`, not by waiting). Only `last_assistant_message` distinguishes them, and
the hook truncates it to 200 chars (`:122`) — enough; the Fable string is 95.

## 5. Re-fires while blocked: YES, 1:1 with each retry, hours apart

```
== e442434c                        == 28f07827                        == 09e64dcb
 REC 16:58:33.848 five_hour         REC 17:07:35.697                    REC 17:01:34.319
 SF  16:58:34Z marker-opened        SF  17:07:35Z                       SF  17:01:34Z
 REC 16:58:43.293                   REC 17:09:46.159                    REC 17:11:29.347
 SF  16:58:43Z marker-appended      SF  17:09:46Z                       SF  17:11:29Z
 REC 16:58:49.027                   REC 17:09:50.091                    REC 19:53:38.683
 SF  16:58:49Z marker-appended      SF  17:09:50Z                       SF  19:53:38Z   (+2h52m)
 REC 17:27:19.549  (+29 min)        REC 17:14:48.414
 SF  17:27:19Z marker-appended      SF  17:14:48Z
```

22 of 42 sessions re-fire; unique rate_limit records per session:
`{1:20, 2:8, 3:5, 4:6, 7:1, 16:1, 30:1}`. Fires are append-only and **not deduped**, so `wc -l` of a
marker counts RETRIES, never distinct dead sessions. A consumer must group by `session_id` and take
the latest row.

## 6. Abstains: ZERO in 604 fires

```
jq -r '"\(.disposition) \(.reason)"' idl-sf.jsonl | sort | uniq -c | sort -rn
  569 fired marker-appended
   35 fired marker-opened
```

No `abstained` row of any reason (`no-stdin`, `no-jq`, `unparseable-payload`, `no-error-field`,
`marker-dir-unwritable`) and no `passed marker-capped`. Every StopFailure delivery the hook saw
carried a parseable payload with a non-empty `error`. Fires per day:

```
12 (09-08) 47 (09-09) 271 (09-10) 19 (09-11) 44 (09-12) 142 (09-13)
13 (09-14) 10 (09-15)  12 (09-16)  1 (09-17)  5 (09-18)  28 (09-19)
```

Peak 271/day fleet-wide against `STOP_FAILURE_CAP=500` per file — never breached, but within ~2x.

## 7. Marker <-> IDL reconcile EXACTLY today (instrument health)

```
jq -r 'select(.ts>="2026-09-19")|.ts' idl-sf.jsonl | wc -l            => 28
wc -l ~/.claude/autonomy/stop-failure/rate_limit__next3.jsonl          => 12
wc -l ~/.claude/autonomy/stop-failure/rate_limit__next4.jsonl          => 14
  + the 2 IDL sids absent from those (e9561f51, 7c81d279) resolve to
    authentication_failed__.claude.jsonl                               =>  2
12 + 14 + 2 = 28.   No marker write lost, no IDL row orphaned.
```

## 8. Teammate / assignee sessions

```
grep -rlF '"agentName"' --include='*.jsonl' --include='*.handed-off' <3 stores> | wc -l   => 202
comm -12 <those 202 files> <hits.txt, the 626 rate_limit files>                           =>   0
```

**No teammate session in the corpus has ever died on a cap** => the cap-class half of the teammate
clause is UNMEASURABLE. The surface itself does reach teammate sessions — existence proof, n=1:

```
sid 91a7168e-a7fe-4a01-a710-a1f4463a6c85
  .claude/projects/-Users-chrisren-Development-mac-bootstrap/91a7168e-….jsonl
  agentName present, isSidechain:false, entrypoint:"cli"
  2026-09-15T20:05:55.747Z error='server_error' "API Error: Connection lost mid-response…"
  {"ts":"2026-09-15T20:05:55Z","hook":"stop-failure-marker","sid":"91a7168e-…",
   "disposition":"fired","reason":"marker-opened"}
```

Same-second fire in a named teammate session. (Sensitivity control: `agentName` appears in 202 files,
so the test can say yes.)

## 9. isSidechain (in-process subagent) records — 483 of 641, and their parents ARE covered

```
records in MAIN transcript & isSidechain=false: 158 (128 unique)
records isSidechain=true, all under a /subagents/ path: 483, across 7 distinct parent sids
parent sid8    n   window                                     StopFailure fires in window
b418b97a        2  2026-09-08T23:09:33..23:09:36                        4
2d71c6d8       97  2026-09-10T05:47:32..21:14:54                       64
6b8b69c2       32  2026-09-10T05:47:33..20:57:03                       23
7193ec2b      323  2026-09-10T05:47:35..21:00:57                      117
d83af9ce       13  2026-09-12T22:30:40..22:53:01                       16
22100d17       14  2026-09-12T22:30:40..22:32:20                       16
11569d45        2  2026-09-19T19:53:44..19:53:45                        3
```

All 7/7 parents covered. Note the RATIO: 323 subagent deaths -> 117 parent fires. StopFailure is a
**session-level** signal; it can never enumerate which slots died. A subagent-only cap in a lead that
keeps running would produce 0 fires — not observed here (the parent was capped too), so that failure
mode is UNMEASURED rather than ruled out.

## 10. The strongest design finding: 21% of StopFailure fires have NO usable transcript

```
sids with StopFailure fires: 113
  with a main-transcript rate_limit record:  40
  without:                                   73
error classes found in those 73 sids' transcripts:
  authentication_failed                21
  server_error                         17
  TRANSCRIPT-NOT-FOUND                 15     <-- renamed .handed-off / deleted
  NO-API-ERROR-RECORD                   9     <-- file exists, carries no api-error record at all
  authentication_failed,server_error    4
  invalid_request                       4
  unknown                               3
```

24 of 113 (21%) are invisible to ANY transcript-scanning census (`lr-fleet --locate`), while the
marker holds them. Conversely the IDL alone is useless as a detector: its row is only
`{ts, hook, sid, disposition, reason}` — no error, no account, no pane. The MARKER is the store with
the cause.

## 11. Account resolution is BROKEN for `~/.claude`, and the SSOT has a stale row

```
jq -r '.accounts[]?|"\(.name)\t\(.config_dir)"' ~/.claude/accounts.json
  next   ~/.claude-next
  next4  ~/.claude-quaternary
  next3  ~/.claude-tertiary
  next2  ~/.claude-secondary          <-- does not exist on this box
```

`~/.claude` has no row, so `stop-failure-marker.sh:84-89` falls through to
`ACCOUNT="$(basename "$CFG")"` and writes `authentication_failed__.claude.jsonl` — an account named
`.claude`. Observed today, 5 lines. And since `~/.claude-next/projects` is a symlink onto
`~/.claude/projects`, **a transcript's store does NOT identify its account**; the marker's
`config_dir` field is the only per-death account evidence, and for the default dir it degrades to a
directory basename. This directly damages the operator's "group the dead sessions by account" ask.

## 12. What the marker does NOT carry

`stop-failure-marker.sh:119-126` writes exactly
`{ts, error, account, config_dir, session_id, cwd, transcript_path, hook_event_name, last_assistant_message}`.
No pane id, no `KITTY_WINDOW_ID`, no `ITERM_SESSION_ID`, no pid — although `KITTY_WINDOW_ID` and
`CLAUDE_CONFIG_DIR` are both in the hook's inherited env (only the latter is read).
`transcript_path` is a snapshot: the corpus carries 17 `.handed-off` files among the hits, and 15
StopFailure sids whose transcript cannot be located at all.

GC: `find "$MARKER_DIR" -name '*.jsonl' -mmin "+$TTL_MIN" -delete` with `TTL_MIN=1440`
(`:98-100`) — the marker set is a **24-hour rolling window keyed on the FILE's mtime**, so it is a
live detector and never a history. Everything in §1-§5 above older than 24 h came from the IDL, not
from markers.
