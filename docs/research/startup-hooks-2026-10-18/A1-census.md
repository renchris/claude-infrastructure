# A1: run-time census of SessionStart hooks (2026-10-18)

Axis A1 of the 9-axis startup-hooks study. Read-only: I ran no hook script. Inputs were the 411 main transcripts in
`/tmp/startup-hooks-census-files.txt`, the IDL disposition log, `net-context.jsonl` and the 1-per-minute load series. The repo was at
`b59a1b30f`.

Tags: **[M]** measured (the command is named), **[E]** estimated (the method is named). Unless a line says otherwise, every [M] number
comes from one command:

```
python3 -I docs/research/startup-hooks-2026-10-18/a1_census.py            # ~10 s at load ~50/core
python3 -I docs/research/startup-hooks-2026-10-18/a1_census.py --json /tmp/a1-events.json   # + per-event dump
```

The full output of that run is reproduced in the Appendix.

---

## 0. Answer first

1. **The harness holds the first turn until every sync hook in all four groups has finished. All sync hooks start at the same instant.**
   - Sync-hook start times within one firing differ by p99 0.2 s and at most 0.8 s, so the harness spawns all of them in parallel [M §3].
   - The `hook_additional_context` record is written right after the last hook finishes (p50 gap 0.0 s) [M §3].
   - 94 of 382 startup sessions already had their first prompt queued before the hooks finished. Those prompts waited p50 4.7 s, p90 9.2 s,
     max 12.5 s. No assistant record ever came before the hooks finished (0/94) [M §3].
   - So the startup critical path is the slowest sync hook. **That is `session-start-dispatch.sh` in 315/410 firings**, `dod-persist.sh` in
     67 and `mailbox-drain.sh` in 22 [M §3].

2. **The dispatcher's 9 s child bound is hit almost only on the three non-default config dirs.**

   | Config dir | Dispatcher runs > 9 s [M] |
   |---|---|
   | `.claude` | 6/195 (3 %) |
   | `.claude-secondary` | 41/84 (49 %) |
   | `.claude-quaternary` | 48/90 (53 %) |
   | `.claude-tertiary` | 12/41 (29 %) |

   That puts 101 of the 107 runs over 9 s outside `.claude`. Measured with `python3 -I -c` over `/tmp/a1-events.json`, the per-event dump
   from `--json`; see the last lines of the Appendix.

   - The gap holds at low load. Below 5 load/core, `.claude` p50 is 2.7 s while the others are 5.4–7.8 s and pin at about 9.3 s by p75–p90
     [M §8].
   - The one child with heavy work that depends on the config dir is `config-mirror-assert.sh`:
     - It exits at once for `~/.claude` (`hooks/config-mirror-assert.sh:10-12`).
     - On every other account it runs `_cc_sync_account` (`:17`). That walks the union of about 18.2 k project slugs on each side
       (`lib/config-mirror.zsh:298-302`, `:456-471`; `ls ~/.claude-secondary/projects | wc -l` = 18,197 [M]).
     - The `~/.zshrc` launchers already run the same sync before launch (`~/.zshrc:241,257`).
   - **Inferred [E]:** `config-mirror-assert.sh` is the child being killed at the bound. When it is killed, its later checks never run:
     - settings parity (`:46-50`)
     - hook-surface drift (`:65-87`)
     - agent-budget (`:95-99`)

     That is a silent loss of three fault detectors on about half of non-default starts.

3. **Each child that always prints was present in 100 % of successful dispatcher outputs, even in the 9.6–12 s bucket [M §7].** Those
   children are session-start.sh (MCP line), setup-plan-symlinks, setup-task-symlinks, frontier-status and accounts-board.
   - The child killed at the bound is therefore one that is normally silent, so the kill usually drops little model content. It still
     costs about 6 s of first-turn latency, and a warning that child would have raised is lost with no record.
   - session-index-start was never killed either: 381/381 in-window startups have its EXIT-trap row `passed exit:0` [M §2].

4. **Timeouts depend on load, and the harness enforces timeouts late.**
   - Events with any cancel, by load per core:
     - below 5/core: 0/210 [M §4]
     - 5–10/core: 4/89
     - 10–20/core: 12/32 (38 %)
     - 20/core and above: 28/78
   - Cancelled sync hooks ran past their `timeoutMs` by p50 0.6–2.6 s and at most 25.2 s. One dod-persist with a 5 s timeout ran 30.2 s
     [M §1].
   - 31 sync hooks recorded success after running longer than their own timeout [M §7].
   - Under load, therefore, a registered timeout does not bound startup latency.

5. **Fault-tolerance gaps, each measured:**

   | Drop | Count over 2 days [M] | Who can see it |
   |---|---|---|
   | Dispatcher child killed at its 9 s bound (output dropped, no record) | up to 107/410 runs (§1) | nobody |
   | Whole-dispatcher timeout: board and all context lost | 6 cancels (plus 1 success at 15.6 s past the 12 s timeout) | transcript only |
   | `dod-persist.sh` timeout: frozen-DoD context lost | 18 | transcript only |
   | `mailbox-drain.sh` timeout: mail context lost (dup-biased cursor, see Q4) | 34 | transcript only |
   | `desk-brief-inject.sh` timeout | 1 | transcript only |
   | Async hook stderr | 57 records, none rendered (§5) | nobody |
   | `pre-session-validate` false "ERROR: no working version … session will likely fail" | 24 transcripts; 28 "broken" verdicts in its log for Oct 16–18 | nobody |

   - **Total: 64 `hook_cancelled` records across 45 sessions.** None of them reaches the operator's terminal.
   - Async responses are written at the first turn boundary and carry no `rendered` field, so neither the model nor the operator sees
     them.

6. **Tokens:**
   - Per firing, `additionalContext` is mean 3,655 chars, p50 2,467, p90 6,798, max 9,473 [M §6].
   - **`dod-persist.sh` is about 79 % of it.** It averages 3,424 chars in the 338/410 firings where it prints [M]; spread over all 410
     firings that is about 2,823 chars, ~79 % [E: 3424×338/410 ÷ 3655].
   - The dispatcher contributes about 619 chars.
   - `mailbox-drain.sh` contributes 438 chars mean. In 272 of its 295 outputs it is the same 254-character "🔔 No inbox wake path armed" nag
     [M: `rg`/`jq` over the census files, command in §6].
   - That nag is likely false by the time the model reads it, because `mailbox-wake-arm.sh` arms the watcher at the same instant (Q5).

---

## 1. Method

**Corpus.**
- `/tmp/startup-hooks-census-files.txt` lists 411 main transcripts (subagent paths excluded) across four config dirs: `.claude` 193,
  `-secondary` 78, `-quaternary` 77, `-tertiary` 63 [M: `awk -F/ '{print $4}' … | sort | uniq -c`].
- One `rg -H --null '"hookName":"SessionStart'` pass collects every SessionStart record: 2,028 lines in 0.2 s [M: `time …| wc -lc`].

**Record schema** [M: `jq '[.attachment.type, (.attachment|keys)]' | sort | uniq -c`]:

| Record type | n | Fields |
|---|---|---|
| `hook_success` | 1069 | command, durationMs, exitCode, stdout, stderr, content, toolUseID |
| `hook_cancelled` | 64 | command, durationMs, timedOut, timeoutMs, toolUseID |
| `hook_system_message` | 429 | content (rendered to the terminal) |
| `hook_additional_context` | 409 | content array, one entry per printing hook; toolUseID is the literal "SessionStart"; carries `rendered` |
| `async_hook_response` | 57 | exitCode, processId ("async_hook_NNN"), stdout, stderr, response; **no command, no durationMs, no per-hook name** |

There are no `hook_error` records in the window.

**Event model** (`a1_census.py`, docstring):
- All records of one firing share `toolUseID`. The additional-context record and async responses are attached to the firing whose record
  comes before them in the file.
- A record's timestamp is when that hook finished, so **start = ts − durationMs**.
- Check: for incident session 5759497b, dod-persist (8,323 ms), mailbox-drain (10,051 ms) and the dispatcher (13,544 ms) all compute
  start = 05:49:48.16Z.

**Telling "silent success" from "never ran".** `hook_success` is written only when a hook prints, so I joined three independent ran
records by session id:
- `~/.claude/autonomy/idl.jsonl` plus its two newest `idl.jsonl.<ts>.gz` rotations:
  - `desk-brief-inject.sh` writes one row on every exit path (`hooks/desk-brief-inject.sh:29-31,76,94-110`).
  - `session-index-start.sh` writes an EXIT-trap row (`hooks/session-index-start.sh:17`).
  - `session-start.sh` writes a `memory-snapshot` row.
  - Coverage from 2026-10-09T19:30Z: 381 of 382 post-0056 startup firings.
- `~/.claude/telemetry/net-context.jsonl`, written by the async `net-context-stamp.sh`; 4,186 rows.

**Load.**
- Only `~/.claude/logs/capacity-alarm.jsonl` has a timestamped load series: `load_1m` and `load_per_core` about once a minute, 9,603
  samples from 2026-10-09 [M].
- `net-context-stamp.sh` records no load (`~/.claude/hooks/net-context-stamp.sh:48-50`).
- `attrib.jsonl` has host busy/idle seconds per ~470 s window but no load average.
- Each firing is joined to the nearest load sample within 180 s; 409/410 joined.

**Known limits.**
- Per-child durations inside the dispatcher are not recorded anywhere (`hooks/session-start-dispatch.sh:52-68` logs nothing). Which child
  was killed is inferred from signature lines and the config-dir split.
- IDL and net-context timestamps have 1 s resolution.
- Async hooks have no duration record, so their run time is bounded only through their side-effect rows.

---

## 2. Measurements

### 2.1 Corpus

Firings [M §header]:

| Split | Count |
|---|---|
| Total firings | 413 |
| Post-migration-0056 (start ≥ 2026-10-04T18:04Z) | 410 |
| Source startup / resume / clear / fork | 383 / 28 / 1 / 1 (no `compact` in the window) |
| Config dir `.claude` / `-quaternary` / `-secondary` / `-tertiary` | 198 / 90 / 84 / 41 |
| Entrypoint cli / sdk-cli | 399 / 14 |
| Version 2.1.293 / 2.1.291 / other | 396 / 12 / 5 |

Main transcripts with **no SessionStart record at all: 27**, and none has ran-evidence in IDL or net-context [M §2].
- 24 are SDK probes under `/private/var/folders/...`.
- 3 are rater sessions in `truememory-2-0-round`.
- The first record of each is `queue-operation` followed by a `user` prompt, with no hook attachments. They look like hook-less headless
  launches (by design?), not drops; see Q1.

### 2.2 Per-command durationMs

Successes and timed-out cancels combined [M §1]:

| Hook (mode, timeout) | n | p50 | p75 | p90 | p95 | p99 | max | timedOut | overshoot past timeout (p50 / max) |
|---|---|---|---|---|---|---|---|---|---|
| session-start-dispatch.sh (sync, 12 s) | 410 | 5.8 s | 9.2 | 9.7 | 10.3 | 13.4 | 21.7 | 6 | 2.6 / 9.7 s |
| dod-persist.sh (sync, 5 s) | 359 | 2.0 | 3.3 | 4.6 | 5.9 | 9.2 | 30.2 | 18 | 2.1 / 25.2 s |
| mailbox-drain.sh session-start (sync, 5 s) | 330 | 1.9 | 3.2 | 5.5 | 6.2 | 11.4 | 14.7 | 34 | 0.6 / 9.4 s |
| desk-brief-inject.sh (sync, 5 s) | 1 record | | | | | | 13.4 | 1 | 8.4 s |
| project: reso `unblock-sweep` (sync) | 5 | 20.4 | | | | | 31.9 | 3 | |
| project: reso `pnpm install` guard | 1 | 120.8 s | | | | | | 0 | |
| project: reso `mcp-auth-guard.sh` | 1 | 33.2 | | | | | | 1 | |

- desk-brief-inject never prints on this machine, so it has only that one record. Its completion time comes from IDL instead: p50 0.2 s,
  p90 1.5 s, p99 4.1 s, max 8.2 s after firing start (±1 s), n=381 [M §2].
- Older pre-dispatcher records (children registered directly, n=1–3 each) put each child at about 2.2–7.2 s. They are too few to rank.

Splits by source and config dir [M §1]:

| Hook | Split | p50 | p90 | p99 |
|---|---|---|---|---|
| dispatcher | startup | 5.5 s | 9.7 s | 13.9 s |
| dispatcher | resume | 7.1 s | 9.3 s | 10.6 s |
| dispatcher | `.claude` | 3.0 s | 6.5 s | 15.6 s |
| dispatcher | quaternary | 9.2 s | 10.9 s | 13.8 s |
| dispatcher | secondary | 9.0 s | 9.6 s | 10.7 s |
| dispatcher | tertiary | 5.6 s | 9.8 s | 10.8 s |
| dod-persist | `.claude` | 3.0 s | 5.7 s | 11.4 s |
| dod-persist | secondary | 1.7 s | 2.4 s | 6.0 s |
| mailbox-drain | `.claude` | 2.5 s | 5.8 s | 12.4 s |
| mailbox-drain | secondary | 1.5 s | 2.1 s | 3.8 s |

Dispatcher thresholds [M §1]:
- **107/410 (26 %) > 9 s**, of which 54 in (9.0, 9.6] s.
- 7 runs > 12 s: 6 cancelled, plus 1 success at 15.6 s for session b70276b2 (2026-10-17T04:45Z), which beat a late timer.
- "> 9 s" is an approximation of "a child hit the bound". The harness clock also counts bash spawn, `mktemp`, `cat` of the payload, and
  the merge `jq` (`hooks/session-start-dispatch.sh:46-48,79-91`). A run just over 9 s may have had no kill; a run at 9.0–9.6 s almost
  surely did.

### 2.3 Presence per post-0056 startup firing (n=382)

[M §2]

| Hook | success | cancelled | no record | Ran-evidence |
|---|---|---|---|---|
| dispatcher | 376 | 6 | 0 | session-index-start child row: 381/381 |
| dod-persist | 310 | 18 | 54 | none. **All 54 absences are in cwds that never produced dod output in any firing**, consistent with an empty store (`hooks/dod-persist.sh:416-417`), i.e. silent success [M §8] |
| mailbox-drain | 282 | 34 | 66 | none. Prints whenever no watcher is armed or mail exists, so the 66 are probably silent successes with a watcher armed, but this cannot be proven (Q4) |
| desk-brief-inject | 0 | 0 (1 earlier in the window) | 382 | IDL rows: 381/381. 380 `no-role-file`, 1 `no-pane` (the 382nd firing is outside IDL coverage) |
| net-context-stamp (async) | n/a | n/a | n/a | rows 382/382, written p50 0.4 s, p99 5.0 s, max 11.2 s after start [M §8] |

### 2.4 Critical path

[M §3]

| Measure | Result |
|---|---|
| Start-time spread among sync hooks of one firing | p50 0.0, p99 0.2, max 0.8 s (all spawned together) |
| Firing span (earliest start to last record) | p50 5.9, p75 9.2, p90 9.8, p95 10.9, p99 21.8 s, max 120.8 s (reso `pnpm install`) |
| Last finisher | dispatcher 315, dod-persist 67, mailbox-drain 22, project hooks 6 |
| First prompt queued before hooks ended | 94/382; wait p50 4.7, p75 7.2, p90 9.2, max 12.5 s; assistant record before the end: 0 |
| `instructions` attachment after hooks end | p50 1.9, p90 6.2 s. This is post-hook startup work, not hooks |
| Context written after the last *recorded* hook | 0.0 s p50 |

The last row has a tail: 9 firings with a gap of 0.7–12.4 s.
- In baf8f054 (2026-10-16T05:19Z) every sync hook was done by +10.8 s: desk-brief-inject's IDL row is at +1.4 s and the dispatcher record
  at +10.8 s. The context was still written only at +23.2 s [M: `jq`/`rg` on `/tmp/a1-events.json` and `idl.jsonl.20261016T081034Z.gz`].
- Some harness-side wait sits after the hooks: event-loop starvation, or a descendant holding a hook's stdout pipe (`hooks/session-start.sh`
  notes process-exit vs pipe-EOF 83 ms vs 3,096 ms). It is not attributable from the transcript (Q3).

### 2.5 Timeouts in time and versus load

[M §4]

64 cancel records fall into 25 clusters (records ≤ 300 s apart). The four largest hold 35 records (55 %):

| Window (Z) | Records | Sessions | Hooks | Load at the time |
|---|---|---|---|---|
| 10-17 17:52:09–17:52:55 | 13 | 12 | mailbox-drain 12 | 14–17/core; two sdk-cli batches of 6 sessions starting in the same second in `/private/tmp/o14probe` |
| 10-17 04:08–04:12 | 10 | 4 | mixed, incl. 2 dispatcher | 22–30/core |
| 10-16 11:39:09 | 6 | 4 | 4 sessions in the same second | 5.5/core: a batch launch at moderate load |
| 10-18 05:49–05:52 | 6 | 2 | the incident | 55–71/core |

Load samples quoted from `jq 'select(.ts|startswith(...))' ~/.claude/logs/capacity-alarm.jsonl` [M].

By load per core [M §4]:

| Load/core | Firings | With any cancel | Dispatcher > 9 s | Dispatcher timeout | Dispatcher p50 / p90 / max |
|---|---|---|---|---|---|
| 0–2 | 55 | 0 % | 1 | 0 | 4.9 / 7.3 / 9.2 s |
| 2–5 | 155 | 0 % | 28 | 0 | 5.5 / 9.3 / 10.0 |
| 5–10 | 89 | 4 % | 30 | 0 | 6.9 / 9.5 / 10.5 |
| 10–20 | 32 | 38 % | 17 | 0 | 9.5 / 10.0 / 10.8 |
| 20–35 | 48 | 27 % | 11 | 3 | 5.5 / 10.6 / 15.9 |
| ≥35 | 30 | 50 % | 19 | 3 | 9.8 / 11.5 / 21.7 |

Co-starting firings (within ±30 s) do not predict cancels by themselves: 0 others → 10 %, 1–2 → 15 %, 3–5 → 11 % [M §9]. Ambient load is
the driver. The exception is same-second batches, where mailbox-drain timed out in 12 of 12 sessions while the dispatcher survived (Q4).

### 2.6 Async hooks

[M §5]

57 `async_hook_response` records over 413 firings. **They appear only when the hook wrote stderr/stdout, and none carries a command,
duration or per-hook name.**
- session-register.sh "Killed: 9" job notices: 33. This is the bash job report for its own watchdog `sleep` being killed after a normal
  finish (`hooks/session-register.sh:607-613`). Benign noise.
- pre-session-validate warnings: 24 (`hooks/pre-session-validate.sh:122,154`).

These records are stamped at the first turn boundary. In 5759497b the response carries the first-turn `auto_mode` attachment's timestamp
(05:56:23.581Z), and it has **no `rendered` field**: neither the model nor the operator sees it [M: `sed -n` around the record].

`pre-session-validate.sh:113-122` probes `~/.claude-versions/current`, which points at **2.1.114**, with `timeout 2 … --version`.
Sessions actually run 2.1.291–2.1.296 (transcript `.version` [M §header]). Its "broken" verdicts follow load: 13 on Oct 16, 10 on Oct 17,
5 on Oct 18 out of about 380 starts [M: `rg 'current version broken' ~/.claude/logs/pre-session-validate.log | awk '{print $1}' | uniq -c`].
The check is a stale target that false-positives under load.

### 2.7 Context per firing (model-billed)

[M §6]

| Producer | Mean chars | p90 | max | n |
|---|---|---|---|---|
| Merged additionalContext per firing | 3,655 | 6,798 | 9,473 | 406 (4 firings had none) |
| dod-persist | 3,424 | 5,936 | 5,936 | 338 |
| dispatcher (MCP / Plans / Tasks / Frontier lines) | 619 | 643 | 677 | 404 |
| mailbox-drain | 438 | 254 | 3,687 | 295 |

- dod-persist's max equals its p90, which reads as a budget ceiling.
- The 254-char wake-path nag accounts for 272 of mailbox-drain's 295 outputs [M: `rg 'No inbox wake path armed' | jq length | uniq -c`].
- Dispatcher systemMessage (the board) is mean 2,278 chars and costs 0 model tokens. 404/410 firings rendered it; the 6 without are
  exactly the 6 dispatcher timeouts [M §6].

---

## 3. Findings

**F1. The first turn waits for the slowest of about four sync processes. The dispatcher sets that bound in 77 % of firings.**
Evidence §2.4. Every second removed from the dispatcher's tail comes straight off first-turn latency for the 25 % of launches with a queued
prompt (teammates, dispatches, SDK). Interactive users mostly hide it behind reading time.

**F2. The dispatcher is slow mostly on non-default config dirs, and the inferred cause is `config-mirror-assert.sh`.**
Evidence §0.2 and §2.2.
- At load below 5/core the non-default dirs still sit at about 9.3 s by p75–p90, the bound plus overhead.
- The child has the only config-dir-gated heavy path: an 18 k-slug zsh walk (`lib/config-mirror.zsh:298-302`) that the launcher already
  did (`~/.zshrc:241,257`).
- The hook's own header says it "fixes the NEXT session, not the running one" (`hooks/config-mirror-assert.sh:6-7`). It gains nothing by
  being on the critical path.
- Attribution [E]: no per-child timing exists. The other children don't read `CLAUDE_CONFIG_DIR` beyond a cache path
  (`rg -c CLAUDE_CONFIG_DIR` over the 10 children [M]), and session-start.sh's per-config-dir MCP cache line is present 100 % of the time.

**F3. A kill at the dispatcher bound is invisible and also turns off detectors.**
- `session-start-dispatch.sh:61-68` kills the child's group and `:33` discards stderr. Nothing logs which child died.
- Because the always-printing children survive (§0.3), what gets dropped is the conditional warnings: config-mirror-assert's FORKED,
  parity, drift and budget lines; activation-watch and escalation-watch alerts; a recycle packet. These are exactly the alarm lines.
- The operator cannot tell "healthy, nothing to say" from "killed before it could say it". `desk-brief-inject.sh:19-28` documents the same
  failure class already happening once.

**F4. A dispatcher timeout loses everything, and can lose a recovery packet that has already been marked delivered.**
- Merging and printing only at the end (`session-start-dispatch.sh:70-92`) means a harness kill at 12 s+ drops the board and all context
  (6 in 2 days, including the 2026-10-18 incident).
- `recycle-failed-inject.sh:14-17,55` stamps `injected_at` after printing. Its "print" goes to the dispatcher's temp file, not to the
  harness.
- A dispatcher timeout after that child finishes therefore marks the packet injected while nothing reached the model. Its print-then-stamp
  guarantee does not hold through the dispatcher [E: static reading; no packet was observed lost in the window].

**F5. Registered timeouts do not bound latency under load.**
- Cancel overshoot reaches 25 s, and 31 successes ran past their timeouts (§0.4).
- Every sync hook needs its own internal deadline below its registration, and a deadline-driven emit, so that a slow harness timer cannot
  stretch startup.

**F6. Cancels and async output are recorded but shown to nobody.**
- 64 `hook_cancelled` records in 2 days, all `timedOut:true`, each naming the hook, duration and timeout. Async responses carry no
  `rendered` field.
- The transcript holds everything needed for a loud, attributable notice at the next boundary. Nothing reads it today.

**F7. pre-session-validate is a stale, load-sensitive check that still spawns a CLI at every start.**
- It spawns `claude --version` under `timeout 2` against a version tree (2.1.114) that sessions do not use.
- It raises a false "session will likely fail" in about 7 % of starts [E: 28 verdicts / ~380 starts, Oct 16–18], and the error is never
  shown.
- That makes it alarm noise and CPU contention at the worst moment.

**F8. Most mailbox-drain output at SessionStart is a nag whose premise the sibling hook removes at the same instant.**
272/295 (92 %) outputs are the 254-char "No inbox wake path armed" text (`hooks/mailbox-drain.sh:519,559-560`), while
`mailbox-wake-arm.sh` arms the watcher at birth in the same group (`hooks/mailbox-wake-arm.sh:2-8`).

**F9. Under load, mailbox-drain is the hook most often cancelled (34).** It times out in batches of same-second launches (12/12) even when
the dispatcher survives. That suggests a shared lock or IO contention, not CPU alone [E].

**F10. Measurement debt: the print-only-success bias plus no per-child timing leaves three questions open.**
- Which child the dispatcher kills.
- Whether a silent dod-persist or mailbox-drain ran at all.
- How long async hooks take.

session-index-start's EXIT-trap row (`hooks/session-index-start.sh:10-17`) is the pattern that answered this for one child.

---

## 4. Recommendations

None of these throttles, caps, kills or demotes live session work, and none reduces the session count. All act on startup hooks. Where an
option removes a kill (R3), it replaces killing with detaching.

**R1. Take config-mirror-assert off the critical path.**
- Change: run `_cc_sync_account` detached, with stdio closed and a lock so concurrent starts don't stack. Write its findings (FORKED,
  parity, drift, budget) to a state file. The next start's child `cat`s that file and emits it as `systemMessage`.
- Alternative: make the slug walk incremental, e.g. only slugs whose mtime is newer than a stamp.
- Same next-session semantics the hook already claims (`hooks/config-mirror-assert.sh:6-7`).
- Files: `hooks/config-mirror-assert.sh:17` (and `lib/config-mirror.zsh:298-302` for the incremental variant).
- Impact [E]:
  - On the 52 % of starts on non-default dirs, dispatcher p50 should fall from about 7–9 s toward the `.claude` level of about 3 s, a
    saving of roughly 4–6 s.
  - About 101/107 bound hits per 2 days should go away (parity with `.claude`'s 3 %).
  - The three detectors at `:46-99` would run on every start instead of about half.
- Effort S–M. Risk: low. A stale-by-one mirror is already the documented model; the detached job must not hold the hook's stdout (the
  `session-start.sh` pipe-EOF lesson).
- Settings edit: no; the child list is `hooks/session-start-dispatch.sh:40`.
- **Conviction 80.**

**R2. Dispatcher child ledger, plus loud attribution.**
- For every child, append `{ts, sid, cfg, child, rc, ms, killed_at_bound, out_bytes, cut_by_cap}` to e.g.
  `~/.claude/logs/ssd-children.jsonl`.
- When any child was killed, or the cap cut context (`:88`), add one line to the merged `systemMessage`, for example:
  `⚠ startup: config-mirror-assert.sh killed at 9 s bound — its checks did not run; re-run: <cmd>`.
- File: `hooks/session-start-dispatch.sh:52-92`.
- Impact: up to 107 silent drops per 2 days become loud and attributable, and F2's attribution becomes measured.
- Effort S. Risk: low (one `date` and one append per child). Settings edit: no.
- **Conviction 90.**

**R3. Emit at a deadline instead of killing.**
- The dispatcher prints the merged output at a fixed deadline from its own start (e.g. 8 s), using whatever children have finished. It
  then exits without killing the stragglers.
- Stragglers finish detached and write their output to `~/.claude/state/ssd-late/<sid>.json`.
- That late output is delivered at the next boundary by an existing UserPromptSubmit or Stop hook (e.g. `mailbox-drain.sh prompt` mode or
  `operator-readout.sh`), as `systemMessage` for operator lines and context only where the model needs it.
- Fixes F4: a harness kill of the dispatcher becomes unlikely, because it prints well before 12 s even with spawn overshoot. It also
  removes the kill that F3 hides.
- Files: `hooks/session-start-dispatch.sh:61-68`, plus one reader in an existing next-boundary hook.
- Impact: up to 107 child drops and the 6–7 whole-output losses per 2 days → 0 [E]; dispatcher p99 bounded near 8–9 s even at ≥35/core.
- Effort M. Risk: medium. Straggler children write state concurrently with the live session; children already tolerate detached helpers
  (`:61-63`).
- Settings edit: no.
- **Conviction 75.**

**R4. A next-boundary reporter for SessionStart cancels.**
- On the first UserPromptSubmit or Stop of a session, scan `transcript_path` for `hook_cancelled` (and `timedOut`) records of event
  SessionStart.
- Emit one top-level `systemMessage` naming each hook, its duration and timeout, what was lost (board, DoD context, mail context) and the
  recovery command. Example: `bash ~/.claude/hooks/accounts-board.sh </dev/null` for the board, `dod-persist.sh get` for the contract.
- Once per session, idempotent through a marker.
- Should live inside an existing hook that already gets `transcript_path`; mailbox-drain prompt mode and operator-readout both qualify.
- Impact: 64 per 2 days (45 sessions) → loud and prescribed; covers the incident class exactly.
- Effort M. Risk: low; it reads its own transcript once. Settings edit: no, if added to an existing hook.
- **Conviction 85.**

**R5. Self-deadlines in the two sync context hooks, plus a precomputed DoD.**
- dod-persist: render the injection at capture time (`set` and PreCompact), so SessionStart only needs a `cat` of the cached render.
  Today it does `git rev-parse`, `shasum`, awk lineage filtering and `jq` at every start (`hooks/dod-persist.sh:416-461`).
- mailbox-drain session-start: put an internal deadline about 1 s under 5 s. If it is about to expire, emit "mail pending, not drained —
  delivered at next prompt" rather than being cancelled. Mail stays pending through the `.acked` cursor (`hooks/mailbox-drain.sh:12-17`).
- Impact: 18 + 34 cancels per 2 days, and dod-persist's p90 4.6 s and p99 9.2 s tail, which is the critical path in 67 firings [E: a `cat`
  costs ~0.1 s at low load].
- Effort M. Risk: low to medium (cache staleness; key it by store mtime). Settings edit: no.
- **Conviction 65.**

**R6. Re-point or retire pre-session-validate.**
- It validates `~/.claude-versions/current` → 2.1.114, a tree sessions do not run, with a 2 s `--version` probe that fails under load
  (`hooks/pre-session-validate.sh:110-122,153-154`).
- Options:
  - Fix the target: resolve the running binary from `$PPID` the way session-start.sh does.
  - Skip the probe under load and trust MANIFEST.
  - Retire it. That needs the operator to remove it from settings.json (class c10).
- If a real failure is found, it must be loud through R4's channel, not async stderr.
- Impact: one fewer CLI spawn per start; 24 false and invisible ERRORs per 2 days → 0.
- Effort S. Risk: low. Settings edit: only for full retirement (c10, operator-only).
- **Conviction 70.**

**R7. Suppress the wake-path nag in session-start mode.**
- `mailbox-wake-arm.sh` arms the watcher at birth, so in `session-start` mode the "no watcher armed" branch is almost always a race
  (`hooks/mailbox-drain.sh:558-561`).
- Re-check after wake-arm's claim lands, or skip the nag for MODE=session-start and leave it to the prompt and Stop boundaries.
- Impact: ~254 chars, about 64 tokens [E: chars/4], in 92 % of mailbox-drain outputs, re-billed at every /clear and resume.
- Effort S. Risk: low; the prompt-mode nag still fires if arming truly failed. Settings edit: no.
- **Conviction 55.**

**R8. Close the instrumentation gaps that kept this census inferential.**
- Add EXIT-trap rows like `hooks/session-index-start.sh:17` to dod-persist, mailbox-drain session-start and the dispatcher:
  `{hook, sid, rc, ms, printed_bytes}`.
- Add the same `{hook, sid, ms, rc}` row to the four async SessionStart hooks.
- Re-run `a1_census.py` after R1/R2 land to confirm or refute the config-mirror attribution.
- Impact: "silent success vs never ran" becomes decidable (54 dod and 66 mailbox absences per 2 days are ambiguous today), and async run
  time becomes visible.
- Effort S. Risk: low. Settings edit: no.
- **Conviction 80.**

**R9. Fold desk-brief-inject into the dispatcher, or keep it with a cheaper early exit (lower priority).**
- It abstained `no-role-file` in 380 of 381 starts and is one of four sync spawns; its tail reached 8.2 s, plus one 13.4 s cancel.
- Without a settings edit: move its role-file test ahead of the lib source, the stdin read and `jq` (`hooks/desk-brief-inject.sh:70-107`).
- Folding it into the dispatcher frees a harness spawn but needs a c10 settings edit, and runs into the 10 k cap that kept it separate
  (`hooks/session-start-dispatch.sh:11-12`).
- Impact: small; the hook was last finisher in ≤ 4 firings [M §3 gap analysis].
- Effort S. Risk: low. Settings edit: only if folded (c10).
- **Conviction 45.**

---

## 5. Open questions

- **Q1.** The 27 transcripts with zero SessionStart records and no ran-evidence (SDK probes and rater sessions): are hooks disabled on
  purpose (`--setting-sources`, bare mode), or are SessionStart hooks skipped for some SDK launch paths? If the latter, it is a "never ran"
  class with no record.
- **Q2.** Is `config-mirror-assert.sh` really the child that hits the bound? R2's ledger, or one read-only `ps` sample of a live
  non-default start, would settle it. The other non-printing candidates are activation-watch, escalation-watch and recycle-failed-inject.
- **Q3.** What fills the 0.7–12.4 s gap between the last recorded hook and the `hook_additional_context` record in 9 firings
  (baf8f054: 12.4 s)? Harness event-loop starvation, or a descendant holding a hook's stdout pipe? Is `durationMs` measured at process exit
  or at pipe EOF?
- **Q4.** In a mailbox-drain cancel, was mail moved to `.seen` but not delivered? The header says re-surfacing from `.acked` makes it
  dup-biased, which needs checking against the 34 cancels. Separately, why does it time out 12/12 in same-second batches while the
  dispatcher survives (lock contention on a shared inbox)?
- **Q5.** Does `mailbox-wake-arm.sh` reliably arm before the model's first turn? If so, R7 is safe; if not, the nag is the only backstop at
  birth.
- **Q6.** Does an async hook's top-level `systemMessage` reach the model or the terminal? The dispatcher header asserts it reaches the
  model (`hooks/session-start-dispatch.sh:14-15`). The 57 async responses here carried only stderr with exit 0, and none was rendered.
- **Q7.** `session-register.sh` has a 5 s async registration but a 20 s internal bound (`P8_TIMEOUT`, `:42`). Is an async hook killed at its
  registration timeout recorded anywhere? No async cancel record type appeared in 2 days.
- **Q8.** There were no `SessionStart:compact` firings in this window, so the compact path is unmeasured.

---

## Appendix: full output of `python3 -I docs/research/startup-hooks-2026-10-18/a1_census.py` (2026-10-18 ~06:25Z)

```
# A1 census — 411 main transcripts, 384 with >=1 SessionStart record
events (SessionStart firings): 413; post-0056 (start >= 2026-10-04T18:04:31Z): 410
event window: 2026-10-01T05:45:30Z .. 2026-10-18T05:52:43Z
by source: startup=383, resume=28, clear=1, fork=1
by config dir: .claude=198, .claude-quaternary=90, .claude-secondary=84, .claude-tertiary=41
by entrypoint: cli=399, sdk-cli=14
by version: 2.1.293=396, 2.1.291=12, 2.1.284=3, 2.1.296=2

## 1. Per-command durationMs (hook_success + hook_cancelled; cancelled durations included)
- session-start-dispatch.sh: n=410 p50=5.8s p75=9.2s p90=9.7s p95=10.3s p99=13.4s max=21.7s; cancelled(timedOut)=6
    kill overshoot past timeoutMs: n=6 p50=2.6s p75=3.8s p90=6.8s p95=8.3s p99=9.4s max=9.7s
    source=startup: n=382 p50=5.5s p75=9.2s p90=9.7s p95=10.4s p99=13.9s max=21.7s
    source=resume: n=27 p50=7.1s p75=8.9s p90=9.3s p95=9.5s p99=10.6s max=10.9s
    source=clear: n=1 p50=6.0s ... max=6.0s
    cfg=.claude: n=195 p50=3.0s p75=4.3s p90=6.5s p95=7.9s p99=15.6s max=21.7s
    cfg=.claude-quaternary: n=90 p50=9.2s p75=9.9s p90=10.9s p95=11.4s p99=13.8s max=15.6s
    cfg=.claude-secondary: n=84 p50=9.0s p75=9.4s p90=9.6s p95=9.7s p99=10.7s max=10.8s
    cfg=.claude-tertiary: n=41 p50=5.6s p75=9.2s p90=9.8s p95=10.0s p99=10.8s max=11.0s
- dod-persist.sh: n=359 p50=2.0s p75=3.3s p90=4.6s p95=5.9s p99=9.2s max=30.2s; cancelled(timedOut)=18
    kill overshoot past timeoutMs: n=18 p50=2.1s p75=3.9s p90=11.7s p95=18.2s p99=23.8s max=25.2s
    source=startup: n=329 p50=2.1s p75=3.3s p90=4.9s p95=6.1s p99=9.3s max=30.2s
    source=resume: n=28 p50=1.5s p75=2.0s p90=3.2s p95=4.1s p99=5.2s max=5.5s
    cfg=.claude: n=161 p50=3.0s p75=3.7s p90=5.7s p95=6.9s p99=11.4s max=21.9s
    cfg=.claude-secondary: n=82 p50=1.7s p75=1.9s p90=2.4s p95=2.7s p99=6.0s max=6.6s
    cfg=.claude-quaternary: n=76 p50=1.8s p75=3.1s p90=5.1s p95=5.5s p99=14.4s max=30.2s
    cfg=.claude-tertiary: n=40 p50=1.2s p75=1.8s p90=2.6s p95=3.0s p99=5.9s max=6.9s
- mailbox-drain.sh session-start: n=330 p50=1.9s p75=3.2s p90=5.5s p95=6.2s p99=11.4s max=14.7s; cancelled(timedOut)=34
    kill overshoot past timeoutMs: n=34 p50=0.6s p75=2.1s p90=4.8s p95=6.1s p99=8.5s max=9.4s
    source=startup: n=317 p50=1.9s p75=3.2s p90=5.5s p95=6.3s p99=11.5s max=14.7s
    source=resume: n=12 p50=2.1s p75=2.6s p90=4.3s p95=4.9s p99=5.3s max=5.5s
    cfg=.claude: n=152 p50=2.5s p75=4.2s p90=5.8s p95=6.9s p99=12.4s max=14.4s
    cfg=.claude-quaternary: n=73 p50=2.2s p75=5.2s p90=5.6s p95=7.8s p99=11.3s max=14.7s
    cfg=.claude-secondary: n=73 p50=1.5s p75=1.8s p90=2.1s p95=2.9s p99=3.8s max=4.4s
    cfg=.claude-tertiary: n=32 p50=1.1s p75=1.6s p90=2.2s p95=2.5s p99=4.4s max=5.1s
- [project] reso unblock-sweep: n=5 p50=20.4s ... max=31.9s; cancelled(timedOut)=3
- (pre-dispatcher child records, n=1-3 each: accounts-board 2.2s, activation-watch 2.2-4.9s, setup-plan 2.2s,
   config-mirror-assert 2.2-3.5s, session-start 2.2-3.6s, setup-task 2.3-5.2s (1 timeout), escalation-watch 2.3-7.2s,
   frontier 2.2s, session-index-start 9.5s; desk-brief-inject 13.4s (1 timeout); reso project hooks 2.6-120.8s)

dispatcher runs with duration > 9.0s (>= one child hit CC_SSD_BOUND_S and was killed, output dropped): 107/410 (26%)
dispatcher runs > 12.0s registration (whole output lost): 7
dispatcher runs in (9.0s, 9.6s] (bound fired, then merge+exit): 54

## 2. Presence of sync-hook records per post-0056 STARTUP event (bias: success recorded only if it printed)
(independent ran-evidence: idl.jsonl rows from 2026-10-09T19:30:17Z; net-context.jsonl rows=4186)
post-0056 startup events: 382; of which inside idl coverage: 381
- session-start-dispatch.sh: success=376 cancelled=6 absent(no record)=0
- dod-persist.sh: success=310 cancelled=18 absent(no record)=54
- mailbox-drain.sh session-start: success=282 cancelled=34 absent(no record)=66
- desk-brief-inject.sh: idl row present=381 absent=0; completion offset: n=381 p50=0.2s p75=0.7s p90=1.5s p95=2.4s p99=4.1s max=8.2s
- dispatcher outcome x session-index-start idl row: disp-cancelled/six-row: 6 · disp-success/six-row: 375
  session-index-start completion offset from event start: n=381 p50=0.8s p75=1.6s p90=3.4s p95=4.4s p99=8.4s max=14.5s
transcripts with NO SessionStart record at all: 27 — no ran-evidence (hooks never ran / disabled): 27

## 3. Critical path (post-0056 events with a start estimate)
start-time spread across timed sync hooks of one event: n=400 p50=0.0s p75=0.0s p90=0.0s p95=0.1s p99=0.2s max=0.8s
event span: n=410 p50=5.9s p75=9.2s p90=9.8s p95=10.9s p99=21.8s max=120.8s
hook finishing LAST per event: session-start-dispatch.sh=315, dod-persist.sh=67, mailbox-drain.sh session-start=22, [project]=6
additional_context written after last hook record by: n=406 p50=0.0s p75=0.0s p90=0.0s p95=0.1s p99=1.4s max=12.4s (negatives=0)
startup events whose first user prompt was already queued before hooks finished: 94/382
  hook-imposed wait on that queued prompt: n=94 p50=4.7s p75=7.2s p90=9.2s p95=9.5s p99=10.7s max=12.5s
  first assistant record BEFORE hooks finished (would disprove blocking): 0
instructions attachment written after hooks end by: n=382 p50=1.9s p75=3.7s p90=6.2s p95=10.9s p99=275.6s max=6034.6s

## 4. Timeouts/cancels in time; load cross-check
cancelled records: 64 across 45 sessions
clusters (gap <= 300s): 25; sizes: [13, 10, 6, 6, 3, 2, 2, 2, 2, 2, 2, 1 x14]
load samples (capacity-alarm.jsonl): 9603, 2026-10-09T01:51:01Z .. 2026-10-18T06:24:31Z
post-0056 events joined to a load sample within 180s: 409 (unjoined 1)
  [0,2)    | 55  | 0 (0%)   | 1  | 0 | p50=4.9s p90=7.3s max=9.2s
  [2,5)    | 155 | 0 (0%)   | 28 | 0 | p50=5.5s p90=9.3s max=10.0s
  [5,10)   | 89  | 4 (4%)   | 30 | 0 | p50=6.9s p90=9.5s max=10.5s
  [10,20)  | 32  | 12 (38%) | 17 | 0 | p50=9.5s p90=10.0s max=10.8s
  [20,35)  | 48  | 13 (27%) | 11 | 3 | p50=5.5s p90=10.6s max=15.9s
  [35,inf) | 30  | 15 (50%) | 19 | 3 | p50=9.8s p90=11.5s max=21.7s

## 5. async_hook_response records
records: 57 over 413 events; none carries command/durationMs/hookName-per-hook
- session-register: bash 'Killed: 9' job notice exit=0: 33
- pre-session-validate: version WARNING exit=0: 24
net-context-stamp.sh (async) ran-evidence per post-0056 startup event: {'row': 382}

## 6. Context size (model-billed) per event
additionalContext chars per event: n=406 mean=3655 p50=2467 p90=6798 max=9473; events with none: 4
- dod-persist.sh: mean=3424 p90=5936 max=5936 (n=338)
- session-start-dispatch.sh: mean=619 p90=643 max=677 (n=404); systemMessage chars mean=2278
- mailbox-drain.sh session-start: mean=438 p90=254 max=3687 (n=295)
events with a hook_system_message: 404/410; post-0056 startup events WITHOUT one (board not rendered): 6

## 7. Dispatcher children: signature presence by dispatcher duration
buckets: [0,8)s n=284 | [8,9)s n=19 | [9,9.6)s n=54 | [9.6,12)s n=46 | [12,inf)s n=1
- session-start.sh (MCP:)      100% | 100% | 100% | 100% | 0/1
- setup-plan-symlinks (Plans:) 100% in every bucket
- setup-task-symlinks (Tasks:) 100% in every bucket
- frontier-status (Frontier:)  100% in every bucket
- session-index-start          0% in every bucket (filters to silence when no summaries; session-index-start.sh:39-49)
- accounts-board (board)       100% in every bucket
dispatcher SUCCESS records with durationMs > 12000: [('2026-10-17T04:45:11Z', 'b70276b2', 15603)]
sync SUCCESS records whose durationMs exceeds their registered timeout: dod-persist 15, mailbox-drain 15, dispatcher 1

## 8. Dispatcher duration by config dir WITHIN load/core bins
- .claude lpc<5: n=91 p50=2.7s p90=4.2s max=8.2s     | 5-20: n=52 p50=2.4s p90=4.5s | >=20: n=52 p50=4.7s p90=9.9s max=21.7s
- .claude-quaternary lpc<5: n=45 p50=6.8s p90=9.3s   | 5-20: n=27 p50=9.6s p90=10.1s | >=20: n=17 p50=10.9s max=13.5s
- .claude-secondary lpc<5: n=43 p50=7.8s p90=9.5s    | 5-20: n=36 p50=9.2s p90=9.5s | >=20: n=5 p50=9.7s max=10.8s
- .claude-tertiary lpc<5: n=31 p50=5.4s p90=9.2s     | 5-20: n=6 p50=9.3s | >=20: n=4 p50=9.8s max=11.0s
dod-persist absence split: {'absent, cwd never produced dod output': 54}
net-context-stamp.sh (async) row ts minus event start: n=382 p50=0.4s p75=1.0s p90=1.9s p95=2.7s p99=5.0s max=11.2s

## 9. Startup storms (other firings within +-30 s)
- co-starters 0:   events=197 with-cancel=20 (10%) dispatcher p50=6.4s p90=9.9s
- co-starters 1-2: events=61  with-cancel=9 (15%)  dispatcher p50=5.8s p90=10.1s
- co-starters 3-5: events=152 with-cancel=16 (11%) dispatcher p50=3.4s p90=9.5s
```

Per-config-dir ">9 s" share (§0.2), from `python3 -I -c` over `/tmp/a1-events.json`:
quaternary 48/90 (53 %), secondary 41/84 (49 %), tertiary 12/41 (29 %), `.claude` 6/195 (3 %).

---

## Skeptic verdicts

Adversarial review, 2026-10-18, resumed after a usage-limit move. Read-only: I executed no hook. The checks were inline `python3 -I -c`
over `/tmp/a1-events.json` (the per-event dump written at census time) and the census list, plus `rg`/`jq`, static reads, and one re-run
of `a1_census.py`. That re-run sent stdout to two `/tmp` scratch files, which I have since deleted; it was a deviation from read-only.
**Reproducibility caveat [M]:** 9 of the 411 listed transcripts are no longer at their listed paths, because limit-recover moved them
(5759497b now lives under `~/.claude-secondary`). A re-run today gives 400 events and 56 cancels, and it **loses the 2026-10-18 05:49Z
incident cluster** (window ends 05:28Z). So I checked the published numbers against the dump.

| id | verdict | severity | one line |
|---|---|---|---|
| A1-F1 | amended | minor | Blocking reproduced. "Dispatcher last in 315" counts 41 tied firings by string order; strictly last is 285/410 (70 %) |
| A1-R1 | amended | minor | The cause (memory walk) is right, but the "`.claude`" bucket is 95 % `.claude-next`, where the child runs and prints. The split is by isolated `projects/`, not default vs non-default |
| A1-R2 | amended | minor | Sound. The loud line fires on about 46 % of isolated-account starts until R1 lands, and bash 3.2 has no ms clock |
| A1-R3 | amended | major | "→ 0 whole-output losses" is overclaimed: 3 of 7 dispatcher runs over 12 s were harness starvation, which a dispatcher-side deadline cannot beat |
| A1-R4 | amended | minor | Counts hold (one row mislabelled). operator-readout at Stop is itself cancelled under load, so it is the wrong host |
| A1-R5 | amended | major | The dod-persist lines cited are the `CC_DOD_LINEAGE_ONLY=0` legacy path. The live render depends on the starting session's pane lineage, so a capture-time cache cannot be session-independent |
| A1-R6 | amended | minor | Holds, and is worse than stated: the failure path re-points `~/.claude-versions/current` |
| A1-R7 | confirmed | none | Measured: the nag is a race in 189 of 196 sessions |
| A1-R8 | amended | major | The exit-trap pattern it copies logs a SIGTERM kill as `passed exit:0` under bash 3.2. A1's own "session-index-start never killed" rests on that |
| A1-R9 | amended | minor | The facts hold. The reorder would drop the IDL dead-consumer row pinned by `tests/desk-brief-ssot.bats:145`, or save nothing |

**A1-F1.**
- Reproduced:
  - Start spread p99 184 ms, max 810 ms.
  - 94 queued prompts.
  - 0 assistant records before the hooks finished.
- Stronger blocking test [M, inline python over the 371 readable startup transcripts]:
  - The first assistant record came 1.16 s at the earliest after the hooks ended (p10 1.8 s, p50 4.2 s).
  - Prompts that were not queued got their first answer p10 1.9 s and p50 5.9 s after the prompt (n=277), the same floor.
  - All 21 prompts that waited more than 8 s were answered 1.4 to 18.4 s after the hooks ended, never before.
  - Blocking is real.
- **Last finisher, with ties within 1.5 ms labelled [M]:**
  - Strictly last: dispatcher 285, dod-persist 61, mailbox-drain 17, project hooks 6.
  - **Ties: 41**. Of these, 21 are dispatcher with dod-persist, 10 dispatcher with mailbox-drain, 8 three-way and 2 dod-persist with
    mailbox-drain.
  - `a1_census.py:511-513` takes `max()` over `(t, command)` tuples, so a tie goes to the larger string, `session-start-dispatch` > `mailbox-drain` > `dod-persist`.
  - Ties between independent processes at 1 ms resolution mean the harness records completions in batches. `durationMs` therefore
    includes event-loop lateness.
- Impact bound [E]:
  - On the 101 isolated-account firings over 9 s, the next-slowest recorded sync hook is p50 2.4 s, p90 5.9 s.
  - So a dispatcher at about 3 s saves p50 about 6.3 s of span (p10 4.2, p90 6.8).
  - This is not "each second": the saving stops at dod-persist/mailbox-drain, and their silent durations are unrecorded.

**A1-R1.**
- File:lines confirmed:
  - `config-mirror-assert.sh:10-12,17`
  - `lib/config-mirror.zsh:298-302,456-471`
  - `~/.zshrc:241,257` (also `:270` claude4)
- Slug counts today: secondary 18,258, quaternary 18,177, tertiary 18,204 [M: `ls … | wc -l`].
- **But the "`.claude`" bucket is not account 1.**
  - `~/.claude-next/projects` is a symlink to `~/.claude/projects`.
  - 183 of 193 `~/.claude/projects` transcripts contain `knowledge-layer mirror (.claude-next)` [M: `rg -l`].
  - On `.claude-next`, config-mirror-assert is not a no-op. It runs `_cc_sync_account` and emits a FORKED systemMessage, while
    `:298` skips only the memory walk. So the discriminator is "the isolate set keeps `projects/` real", i.e.
    secondary/tertiary/quaternary.
- The "incremental via mtime stamp" alternative as worded still pays the 18k-entry globs.
  - Those globs are 9.0 of 13.8 s in A2's read-only replay (A2-child-cost.md:44).
  - Use "own slug inline, full sweep detached and single-flight" instead (A8 R1).
- `tests/config-mirror-assert.bats` pins synchronous FORKED output, so it needs rewriting.
- Correction: "The 9 s bound is hit almost only on the three accounts whose `_CC_ISOLATE` keeps `projects/` real
  (`lib/config-mirror.zsh:46-48,298`). `.claude-next`, which is most of the `~/.claude/projects` bucket, runs the same child fast."
- The recommendation stands.

**A1-R2.**
- Confirmed: `session-start-dispatch.sh:33` (`exec 2>/dev/null`), `:56`, `:65-68` and `:88` (`$c[:$cap]`, no marker).
- Amend:
  - Until R1 lands, the named-kill line fires on about 46 % of isolated-account starts. Land R1 first or together, or it becomes
    near-always-firing noise.
  - `/bin/bash` 3.2 has no `$EPOCHREALTIME`. Per-child ms costs a fork, or accept 1 s resolution.
  - The rc of a TERM-killed leader is 143 from `wait`, which is enough to set `killed_at_bound`.

**A1-R3.**
- Confirmed statically:
  - The merge and print happen only at the end (`:70-92`).
  - `recycle-failed-inject.sh:48-56` stamps after printing into the dispatcher's temp file.
  - The 6 board-less firings are exactly the 6 dispatcher cancels [M].
- **Overclaim.** The 7 dispatcher runs over 12 s split into two groups:
  - 4 on quaternary (e52f1f63, 5759497b, dbc1098e, and the b70276b2 success). R1 or R3 would likely fix these.
  - 3 on `~/.claude/projects` during 10-17 04:12-04:33Z (54b18e51, a86d22e3, 87e54489). In those, every sibling 5 s hook was
    cancelled at 9.4-21.9 s. That is harness and process starvation (A3 §2.6).
- `hook_cancelled` carries no stdout (A3 §2.7), and the dispatcher's own `sleep` deadline starves too. So "→ 0" is unsupported.
- Amend:
  - Pair R3 with an outbox: write the merged output to a file before printing, and have the next boundary deliver it when the
    transcript shows the cancel (R4).
  - Give stragglers a hard outer bound (a hung child would otherwise live forever).
  - Write their output outside `$T`, which the `:47` EXIT trap deletes.

**A1-R4.**
- 64 cancels in 45 sessions reproduced from the dump. "Project hooks 5" is really 4 project hooks plus 1 pre-0056 `setup-task-symlinks` record.
- Nothing in `hooks/ bin/ lib/ scripts/` reads SessionStart `hook_cancelled` [M: `rg`].
- Host: `operator-readout.sh` at Stop was itself cancelled twice in the incident session (05:59:38Z 10,054 ms; 06:03:11Z 10,523 ms) [M].
  A reporter inside a cancelled hook is a new silent drop.
- Use mailbox-drain prompt mode instead. UserPromptSubmit cancels measured 0 at load 520-680 after WP4
  (`docs/plans/LOAD_AND_PROMPT_HOOK_TIMEOUTS.md:33`).
- First prove that a UserPromptSubmit top-level `systemMessage` renders; the R5b proof covers SessionStart only.

**A1-R5.**
- With `CC_DOD_LINEAGE_ONLY` defaulting to 1, SessionStart leaves at `hooks/dod-persist.sh:418-420` for `_dod_inject_lineage_only`
  (`:310-356`). The cited `:422-461` is the opt-out legacy frame.
- The live output is keyed on the starting session's sid plus its pane's alias trail (`_dod_lineage_sids`, `:206-230`), which
  mailbox-drain appends to concurrently. A render made at `set`/PreCompact time cannot know the next session's lineage.
- Correction: cache per (pane trail head, store mtime, predecessor toplevels), or cut the per-start work in `:310-356`.
- mailbox-drain deadline: fine, and emit-then-commit (`mailbox-drain.sh:277-297`) already keeps mail pending on a reap.
- But "removes about 52 cancels" is overclaimed. In 5 of the 6 dispatcher-cancel firings the 5 s hooks were cancelled 3-17 s late
  by a starved harness, and an internal deadline cannot help with that.

**A1-R6.**
- Confirmed: `readlink ~/.claude-versions/current` gives `2.1.114`.
- "broken" verdicts are now 13/10/8 for Oct 16/17/18 [M: `rg … | uniq -c`].
- Missed: on a failed probe the hook **re-points `current`** (`pre-session-validate.sh:158-159`, `ln -sfn`).
  - Today it is inert only because both alternatives are MANIFEST `skip` (log 06:12:56Z: "fallback skip 2.1.183", "fallback skip 2.1.113").
  - The log holds 8 past rollbacks, including 2.1.114→2.1.80→2.1.114 within 2 min on 2026-07-21 [M].
  - A load-induced false negative is therefore a latent write to shared state.
- This raises R6's priority. Settings-edit flagging is correct (retirement is c10).

**A1-R7.**
- Confirmed and measured [M, inline python over 402 readable transcripts]:
  - Of 196 sessions with a SessionStart nag and a UserPromptSubmit record, 189 had no nag at the first prompt. 7 got it again.
  - The nag is gated by `nudge` (`mailbox-drain.sh:559,621`), so skipping it for session-start mode leaves the goal nudge (`:554`)
    and breadcrumb (`:585`) intact.

**A1-R8.**
- Reproduced: `timeout -s TERM 1 /bin/bash -c 'trap "echo trap-rc=\$?" EXIT; sleep 3'` prints `trap-rc=0` on bash 3.2.57.
- So `session-index-start.sh:17` logs a 9 s-bound kill as `passed exit:0` (A5 P13).
- A1's §0.3 "session-index-start was never killed: 381/381 passed" is not evidence. Its completion offset reaches p99 8.4 s and
  max 14.5 s (Appendix §2), past the 9 s bound.
- Correction: add `trap 'exit 143' TERM` next to the EXIT trap, plus a START row so that SIGKILL (no trap) shows as start-without-end.

**A1-R9.**
- `desk-brief-inject.sh:70-107` loads the lib, reads stdin and runs jq in order to write the per-exit IDL disposition row with SID
  (`:18-35`). That row was added because the consumer had been dead and silent since 2026-07-26, and `tests/desk-brief-ssot.bats:145`
  pins it.
- Testing the role file first either drops that row or still pays for the lib, stdin and jq. Its completion is p50 0.2 s.
- Correction: drop the reorder. The real choice is to retire the dead consumer (c10) or leave it.

**Missed by this axis.**
1. The config-dir split mislabels account 1. "`.claude`" means `~/.claude/projects`, which is 95 % `.claude-next` sessions.
2. config-mirror-assert's `.claude-next` FORKED warning (`mcp-needs-auth-cache.json statusline.sh`) is an always-firing operator
   alarm. Its presence or absence by duration is a measured kill signature (A3 §2.2: present in 190/284 fast runs, 2/101 at 9 s or more), which A1 left as [E].
3. 41/410 last-finisher ties show that durations are harness-observed.
4. Re-running the census needs path resolution by session id, because limit-recover moves transcripts.
5. A harness timeout of the dispatcher may orphan its children: `set -m` (`:32`) gives each its own group, and the `:47` trap deletes
   their output dir. This is a static [E]; the harness's kill target is unverified.
6. The merged systemMessage has no cap, while the harness swaps output over 10,000 chars for a preview (A3 §2.7). The current max is about 2.9k.
