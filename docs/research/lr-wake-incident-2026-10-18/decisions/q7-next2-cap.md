# Q7: was next2 at its weekly limit before 09:00Z? No.

**Answer.** next2 (`~/.claude-secondary`) was **not capped**. Conviction **97%**.

- The "weekly limit" line on 5232121f was written by the **next4 process**, at 06:51:35Z.
  - That was 9 to 14 minutes **before** the transplant to next2, which ran 07:00:25Z to 07:05:20Z.
  - The next2 transcript holds a byte-for-byte copy of that line (same uuid). The copy came with the transplant.
- `lr-reset-poller.sh` then read the copied line as a next2 event. It logged `PARKED 5232121f (next2, weekly) resets 09:00Z`, and did the same for 7b50757e.
- **The router does not need a new rejection fact.** It already has one, `wire_rejects()`, and it never fired for next2 in this window.
- **The fact that went wrong is the poller's.** It treats a limit event inherited through a transplant as a limit on the account the transcript now lives on. The fix belongs in the poller's park path (see "Fix owner").

The earlier phrase "5 s after its swap onto next2" is wrong:
- 06:49:55Z: the move was **planned** (assign_id `20261018T064955Z-next4-next2-7738`).
- 06:51:33Z → 06:51:35Z: the 5-second gap is between a background-task notification and the 429. Both happened on next4.
- 07:00:06Z: admit (`gate-exempt: swap`).
- 07:00:25Z: lock claimed.
- 07:05:20Z: tombstone written.

## 1. Which process wrote the error

The line exists in both stores, and it is identical in both:

```
$ grep '"error":"rate_limit"' <store>/…/5232121f-….jsonl[.handed-off]   # per store
src (.claude-quaternary …5232121f….jsonl.handed-off)  2026-10-18T06:51:35.192Z  uuid a051ad65-82b8-40f0-bad4-cd8eda6d094a  "You've hit your weekly limit · resets 4am (America/Chicago)"
dst (.claude-secondary  …5232121f….jsonl)             2026-10-18T06:51:35.192Z  uuid a051ad65-82b8-40f0-bad4-cd8eda6d094a  same text
```

The line itself (line 114) reads `model:"<synthetic>"`, `isApiErrorMessage:true`, `error:"rate_limit"`, `version:"2.1.293"`. The lines before it, from the source file:

```
100 06:16:47Z  "UPDATE 06:16Z: recycle onto next4 ENGAGED (pane 21 …"
106 06:17:06Z  turn ends (claude-opus-5-5)
113 06:51:33Z  <task-notification> bhxafkleg  (Bash background task completed)
114 06:51:35Z  <synthetic> rate_limit — weekly, resets 4am Chicago
115 06:51:35Z  turn_duration
```

What proves the copy happened after the error:

- **lr-audit at 06:54:18Z** (`~/.reso/limit-recover/5232121f-…/bundle-20261018T065312Z/audit.json`):
  - It read `config_dir=/Users/chrisren/.claude-quaternary`, `lead_state.pids=[44391]` (alive), and `last_api_error.line=114, status 429`.
  - At that moment the session was still a next4 process.
- **Transplant record** (`bundle-…065312Z/transplant.json`):
  - `ts_first=2026-10-18T07:00:25Z`.
  - Its `sha256=3f0c7ffc…` is the same hash the audit recorded at 06:54 for the **next4** transcript. The next2 file therefore began as a byte copy that already contained line 114.
- **Tombstone** (`~/.claude-quaternary/…/5232121f-….HANDOFF.json`): `"ts":"2026-10-18T07:05:20Z"`, `handed_off_to: ~/.claude-secondary`.
- **The reset text names next4's window, not next2's.**
  - "4am America/Chicago" is 09:00Z on Sun 10-18. next4's `weekly_reset_at` was `2026-10-18T09:00Z`.
  - next2's weekly window resets `2026-10-24T11:00Z` (Saturday, 6am Chicago).
- **The events after the transplant** (`bundle-…065312Z/events.jsonl`):
  - 07:01:44Z `SWITCHED-UNPROVEN`.
  - 07:06:55Z `STRANDED … recycle did not verify`.
  - No next2 process ran this session until 10:04Z.

## 2. Utilization: next2 and next4, 05:00Z to 10:00Z

Source: `~/.claude/logs/account-utilization.jsonl`, filtered to acct ∈ {next2, next4}. The table shows a few of the rows, picked to show the trend.

| ts (Z) | next4 5h / wk | next4 wire 7d status | next2 5h / wk | next2 wk reset | next2 wire |
|---|---|---|---|---|---|
| 05:06 | 22 / 93 | – | 0 / 0 | 10-24T11:00 | – |
| 06:37 | 6 / 99 | allowed_warning (0.99) | 0 / 0 | 10-24T10:59 | – |
| 06:45 | 12 / 100 | allowed_warning | 0 / 0 | 10-24T11:00 | – |
| **06:53** | 12 / 100 | **rejected (1.0)** | 0 / 0 | 10-24T11:00 | – |
| 07:00 | 12 / 100 | rejected | 0 / **1** | 10-24T11:00 | – |
| 07:18 | 12 / 100 | rejected | **1** / 1 | 10-24T10:59 | – |
| 08:53 | 12 / 100 | rejected | 1 / 1 | 10-24T10:59 | – |
| 09:05 | 12 / **0** (reset 10-25T09:00) | – | 1 / 1 | 10-24T11:00 | – |

- **next4** was the account that ran out.
  - Weekly usage climbed 93 → 100 between 05:06Z and 06:45Z.
  - From 06:53Z the server's own verdict was `wire_7d_status=rejected`.
  - It went back to 0 at 09:00Z. That matches "resets 4am Chicago" exactly.
- **next2** ran at 0–1% for 5h and 0–1% for the week through the whole window.
  - Its numbers moved off 0 at 07:00–07:18Z, so real usage landed on it.
  - No wire probe exists for next2, so the endpoint is the only meter. It never showed next2 close to a limit.

Limit errors in next2 transcripts. I scanned every next2 transcript, subagent transcripts included, from 05:00Z to 10:00Z for `"error":"rate_limit"`. Every hit is a copied line from next4:

```
06:46:05–06:47:14Z  12× 5759497b subagents/workflows/wf_7c1e0d3e-19e/*  (5759497b handed off 10:32:51Z → all pre-handoff, next4)
06:47:16.921Z       5759497b main  uuid f1aa0935…  identical in .claude-quaternary …handed-off
06:51:35.192Z       5232121f       uuid a051ad65…  identical in .claude-quaternary …handed-off (handoff 07:05:20Z)
07:07:33.452Z       7b50757e       uuid 1bcd3a2f…  identical in .claude-quaternary …handed-off (handoff 07:08:48Z)
```

All of them say "resets 4am (America/Chicago)", which is next4's reset. None is timestamped after its session's handoff.

## 3. Did sessions on next2 take turns before 09:00Z?

**Sessions moved to next2.** I counted real (non-synthetic) assistant turns written after each session's HANDOFF `ts`. Script: `/tmp/q7_moves.py`.

| sid | handoff ts | turns after handoff, before 09:00Z | first turn after 09:00Z | limit errors after handoff |
|---|---|---|---|---|
| e52f1f63 | 07:05:19Z | 0 | 19:03:39Z (18) | 0 |
| 5232121f | 07:05:20Z | 0 | **10:04:52Z (93)** | 0 |
| 7b50757e | 07:08:48Z | 0 | 11:50:06Z (35) | 0 |
| 43e6eb4b | 07:12:11Z | 0 | – | 0 |
| 756b68c8 | 07:53:43Z | 0 | 20:38:46Z (29) | 0 |

- None of the moved sessions ran before 09:00Z. Each was STRANDED, PARKED, or refused at the gate (c2 §4). This set therefore cannot answer the question in either direction.
- It does answer it **after** 09:00Z. next2's weekly window does not roll until 10-24T11:00Z. If next2 had been weekly-capped at 06:51Z, it would still have been capped at 10:04Z.
- 5232121f took 93 turns on next2 from 10:04:52Z with no limit error. 7b50757e, e52f1f63 and 756b68c8 also ran clean. **So next2 was never weekly-capped.**

**Sessions native to next2.** These ran during the disputed window. Neither has a copy in any other store.

- **5059949f** (reso-landing-design-research):
  - First record 06:50:02Z.
  - 54 real opus-5-5 turns between 06:53:01Z and 08:56:00Z, 41,953 output tokens, 0 errors.
- **ceaea24a** (personal):
  - First record 07:11:21Z.
  - 64 turns between 07:11:30Z and 07:44:11Z, 25,814 output tokens, 0 errors.

## 4. Verdict, and who owns the fix

**Verdict: the error came from the source process, and next2 was not capped. Conviction 97%.**

The remaining 3% has one source: next2 has no wire probe in this window. I have no server-side 7d status for next2. The verdict rests on three things:
- endpoint readings of 0–1%;
- 118 clean turns on next2 inside the window;
- 93 clean turns after 10:04Z, while next2's weekly window was still the same one.

**The moves were not futile.** Every move to next2 before 09:00Z would have worked. Two things held these sessions back:
- recycles that did not verify (STRANDED);
- the poller wrongly parking them until 09:00Z, which was **next4's** reset.

**The router does not need a new per-account rejection fact.** It has one:
- `bin/claude-accounts:1881` `wire_rejects()`, consumed at `:5711` (`if wire_rejects(r, "7d"): return "weekly-exhausted"`).
- It correctly read next4 as `rejected` from 06:53Z and stayed silent about next2.

**What went wrong is attribution.** The poller treats a limit line inherited through a transplant as a limit on the destination account.

Fix owner:

- **`scripts/limit-recover/lr-reset-poller.sh:1977-2047`**, the park loop.
  - `$acct` is the store where the transcript now lives.
  - `kind`/`reset` come from lr-audit's last `limit_events` entry.
  - The rate_limit pre-filter at `:1988` matches on tail bytes. The copied line sits at the tail because the stranded session appended nothing after it.
  - Result: `PARKED 5232121f (next2, weekly) resets 2026-10-18T09:00:00Z` at `poller.log:217129`, and the same for 7b50757e at 07:34:37Z.
  - The bad park then set off `REROUTE … parked on next2, but next3 routes now` churn (`poller.log:217142`, `:217330`).
- **The rule to add:** drop a limit event whose timestamp is at or before the session's transplant time in this store.
  - The transplant time is the tombstone `ts` in the source store's `<sid>.HANDOFF.json`, or `transplant.json ts_first`.
  - The poller already locates HANDOFF.json at `:2296`, `:2312` and `:2435`.
  - Alternative: attribute such an event to the tombstone's source account and its reset.
- **A cheaper alternative:** have `scripts/limit-recover/lr-audit.py` (limit_events assembly, around `:1370`/`:1555`) stamp each event with the config dir it was written under.
  - The data for this exists: the line is present in the `.handed-off` source with the same uuid.
  - Every consumer would then get the correct attribution.

## Adversarial pass

- **Could next2 have hit a 5h limit instead?** No.
  - next2's 5h reading was 0–1% all morning.
  - The text says "weekly".
- **Could the copies be next2 errors that were written back into the source?** No.
  - `.handed-off` files are written only at transplant.
  - The source file's sha at 06:54:18Z (before the transplant) already matched the transplanted copy, and line 114 was already in it.
- **Could a subagent on next2 have hit a limit?** I scanned the subagent transcripts too. The only hits are the 5759497b workflow agents at 06:46Z, and those were pre-handoff next4 lines (handoff 10:32Z).
