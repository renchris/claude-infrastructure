# Gap G3: losses the #8 reporter cannot see (foreign hooks; cancelled hooks that exit 0)

Read-only. No hook was run. Tags: **[M]** measured (command named), **[E]** estimated (method named).
Deviation: one scratch file, `/tmp/g3-cancels.txt` (56 cancel rows extracted by `rg` from the census
list), was written in /tmp. Nothing else outside this file was written.

## 1. Findings

### F1. In every startup cancel, the transcript holds the record, at the head of the file
- The census list holds **56** `hook_cancelled` + SessionStart records **[M]**. Command:
  `rg -n '"hook_cancelled"' <each file in /tmp/startup-hooks-census-files.txt> | rg SessionStart`
  and a jq tally. There are 3 more in the incident transcript. That transcript moved from quaternary to
  secondary after the list was built, so the list's path for it is stale.
  - mailbox-drain 30, dod-persist 16, dispatcher 4, desk-brief 1, setup-task-symlinks 1 (`SessionStart:fork`, 2026-10-01).
  - Foreign (project) hooks: **4**, all in reso-management-app. unblock-sweep ×3 (2 `:startup`, 1 `:resume`): 23.1, 31.9 and 20.4 s
    against a 20 s timeout. mcp-auth-guard ×1: 33.2 s against 30 s.
  - Every record names the full `command`, `durationMs`, `timeoutMs` and `timedOut:true`. The transcript is enough
    to name a foreign hook, and it needs no sentinel to do so.
- **54 of 54** `:startup` cancel records sit at line 3-15, before the first `"type":"user"` line, at byte
  offset ≤ 17,923 **[M]**. Command: `head -n <ln> | wc -c` per record, and `rg -n -m1 '"type":"user"'`.
  - The 2 non-startup records are mid-file: the `:resume` record at 1.57 MB and the `:fork` record at 9.4 MB **[M]**.
  - So a head read covers startup. Resume and fork need an offset or a timestamp floor.
- The first-user-record offset across all 398 readable census transcripts is p50 18 KB, p90 32 KB,
  p99 165 KB and max 336 KB **[M: `rg -m1 -b -o '"type":"user"'` per file]**.
  - Bound the read at "up to the first user record, cap 512 KB". Do not use a fixed 32 KB.

### F2. On the first prompt the transcript usually does not exist yet. 3.2 cannot confirm on prompt 1
- Q3, partly answered. In **42 of 42** cancel sessions, the first user record's timestamp is 0.3-14.3 s
  *before* the file's birth time **[M: `stat -f %B` against `.timestamp`]**.
  - The cancel records are flushed at birth: in all 42, the last cancel came 0.2-383 s before birth.
  - In the incident, the file was born at 05:56:25Z, 6.5 min after the 05:49:56-05:50:01 cancels.
  - One file had a birth reset by a copy (9aa483e9) and is excluded.
- Of the 33 sessions with an early UPS hook record, **16** have that record timestamped *before*
  the file existed. The other 17 are within +0.1-1.0 s of birth and started earlier **[M, same join]**.
  - The synchronous 3.2 front on prompt 1 therefore cannot read `hook_cancelled`. At best it sees the transcript
    from prompt 2, or the detached worker sees it once the file appears.
  - D20 is unchanged. An idle pane that never gets a prompt never gets a transcript, so sentinels are the only signal there.

### F3. A7-3 re-read: the "7 after the cancel" finished normally inside the harness's lag. The harness still discarded their output
- Re-join of `/tmp/a7skeptic/sis-cancels.jsonl` with `idl-sis.jsonl` against the cancel record's own
  timestamp, not just start + 5 s **[M: python join; IDL timestamps are floored to the second]**.
- 17 cancels have an exit row. **None** exited provably after the harness wrote `hook_cancelled`.
  - **≥9 exited ≥1.1 s before it.**
  - Of A7's 7 "after the timer" exits, 6 are before the record and 1 is ambiguous (−0.8 s, floored).
  - The one `exit:143` sits 0.8 s before its record. The kill comes first and the record follows within about 1 s.
- Consequences:
  - A `.done` rc 0 can coexist with a cancel even when the hook beat the harness to the finish.
  - The sentinel's own elapsed time can also read *under* timeoutMs. Its start lags the harness spawn (bash start and
    sourcing at load ~52/core), and 6 of 17 exits floored to before start + 5 s.
  - So "elapsed > timeoutMs" is not a sound trigger. Use elapsed ≥ timeoutMs − 1 s **[E: largest floored early offset −0.7 s, plus margin]**.
  - D16 (`mailbox-drain` commits `.seen` at `:928-929` after printf at `:924`) gets worse. The commit can precede
    the cancel record, so "the hook exited before it was cancelled" cannot be used as proof of delivery either.
- rc 141: no `exit:141` exists in any IDL row on disk. `~/.claude/autonomy/idl.jsonl` holds 8 exit rows
  after rotation, and the A7 corpus holds 2,041 `exit:0` and 1 `exit:143` **[M: `rg -o '"reason":"exit:[0-9]+"' | uniq -c`]**.
  141 is a mechanism only (write after the harness closes the pipe). Still treat it as a possible loss **[E]**.

### F4. What the foreign hooks owe, and evidence for Q2
- `~/Development/reso-management-app/.claude/settings.json` `.hooks.SessionStart` registers **6** sync
  hooks, not 4 **[M: jq]**:
  - `pnpm install` guard, 600 s
  - `.env.local` copy, 5 s
  - DB provisioning, 300 s
  - `worktree-gc.wake` touch, 5 s
  - unblock-sweep, 20 s
  - mcp-auth-guard, 30 s
  - Only the last two were cancelled in the window **[M]**. Both end in `|| true` / `exit 0`
    (`mcp-auth-guard.sh:21,103`), so neither could ever leave a non-zero rc.
- **unblock-sweep** owes the unpushed-branch report. The 2 successes printed "164 branches with unpushed work…" **[M: transcript stdout]**.
  - It writes its 20 h throttle stamp in `finally`, after `render` (`scripts/unblock-sweep.ts:171-195`).
  - After the 10-17T04:45Z cancel, the next run at 06:31Z (+1.8 h) still swept. After the 10-18T04:16Z cancel,
    the 05:28Z resume (+1.2 h) also swept **[M: record timeline]**.
  - So both cancelled sweeps were killed before `recordRun()`. The harness cancel reached the node grandchild
    **[M-inferred: throttle stamp]**. That is Q2 evidence: the process tree was killed, not just the pid.
  - The report is lost, not deferred, but it re-fires at the next start in that repo.
- **mcp-auth-guard** owes the "MCP UNAUTHENTICATED" / "UNREACHABLE" lines (`:90-100`). Today's cache has no such
  lines **[M: `grep` on `~/.claude/cache/mcp-auth-state.txt`, mtime 07:46]**, so a cancel now probably costs nothing.
  What the 10-17 cancel cost cannot be recovered. Its slow path is `claude mcp list` (`:68`, ~5-15 s per its own header).

## 2. Design change for #8 / Wave 3 (closes G3)

| Unit | Change |
|---|---|
| 3.1 Sentinels | Unchanged in role: they cover the window before the transcript exists and the idle pane. They record what each hook owed: `.done` carries rc, elapsed and `owed=<bytes>` (stdout length written). New: the first sentinel writer stores `transcript_path`, its size at start (`stat -f %z`, 0 if absent) and the start time in `<sid>/session.start`, which gives resume/fork an offset and a timestamp floor. |
| 3.2 Front (sync, builtins) | Prompt 1: flag a **possible loss** for an own hook with no `.done` past timeout + 2 s, `.done` with any rc ≠ 0 (143, 141, …), or elapsed ≥ timeoutMs − 1 s with owed > 0. Print "⚠ startup: <hook> may not have delivered (<reason>) — confirming". From prompt 2: print the worker's confirmed list (below). Latch per hook only on confirmation or on proof that it was delivered. |
| 3.4 Worker (detached, extended to startup) | Once `transcript_path` exists (poll in the existing worker, cap 60 s), read from offset 0 for startup, or from the stored size / timestamp floor for resume and fork. Read up to the first `"type":"user"` line, cap 512 KB, with `rg -F hook_cancelled \| rg SessionStart`, then jq on the hits only. Write `<sid>.startup-cancels`: command, hookName, durationMs, timeoutMs. **The transcript is the authority.** Every SessionStart `hook_cancelled` is a confirmed loss, own or foreign. A possible loss with no matching record is cleared as delivered. |
| 3.3 `cc-startup-health` | Join sentinels with transcript records. Show confirmed, possible-unconfirmed and cleared states. |
| §3 note (`README.md:102`) | Replace "carries owed bytes" with: a confirmed cancel is a loss when `owed>0` or when the hook has no sentinel (foreign hook: owed is unknown, so report it). A cancel with `owed=0` is shown as "cancelled, nothing owed" and gets no recovery. |
| D1 recovery, foreign hooks | `⚠ startup: project hook cancelled after <t> s: <command, first 60 chars> — re-run in <cwd>: <command>`. Named rows: unblock-sweep → `pnpm unblock` (= `pnpm exec tsx scripts/unblock-sweep.ts`); mcp-auth-guard → `bash .claude/hooks/mcp-auth-guard.sh`, or read-only `rg 'Needs authentication\|Failed to connect' ~/.claude/cache/mcp-auth-state.txt`; pnpm install → `pnpm install`; DB → `bash scripts/db-ensure.sh`. Re-running a mutating command (install, DB) is the operator's or agent's call; the line names it and never runs it. |

New fixtures in `tests/startup-health.bats`. Each is a static transcript plus sentinel dir; no hook runs.
- (a) Project-hook cancel: a transcript with an unblock-sweep `hook_cancelled` and no sentinel → one confirmed line naming the command and the re-run.
- (b) Exit-0-after-cancel: `.done` with rc 0, elapsed 5.3 s, owed > 0, plus a matching `hook_cancelled` → possible, then confirmed. The same `.done` with no record → cleared, no output.
- (c) rc 141: `.done` with rc 141 → possible. With a record → confirmed. Without one → cleared, plus an IDL row.
- (d, added) Resume: a cancel past the stored offset is reported. One before it is ignored.
- (e, added) Transcript absent: prompt 1 prints the possible line only and the worker writes nothing.

## 3. Recommendations

| # | Recommendation | Impact | Effort | Risk | settings.json | Conviction |
|---|---|---|---|---|---|---|
| G3-1 | Transcript-authority worker scan for SessionStart cancels (3.4 extended to startup, offset/timestamp floor) | Closes 2 drop paths: foreign-hook cancels (4 per 2 d **[M]**) and rc-0/141 cancels that sentinels read as healthy (≥9 of 17 joined cancels **[M]**). 0 ms on the prompt path (detached); 0 tokens when healthy. | M | Low. Read-only scan; the 512 KB cap bounds the cost. | no | 85 |
| G3-2 | 3.2 "possible loss" rule: rc ≠ 0, or elapsed ≥ timeoutMs − 1 s with owed > 0, or no `.done` past timeout + 2 s. Confirm or clear from the transcript. | No false-healthy reading from rc 0. A one-turn-late confirmation is the cost of F2. | S | Low. False "possible" lines are cleared by the worker; show possible lines only for own hooks with owed > 0. | no | 80 |
| G3-3 | Foreign-hook recovery lines in D1 (command-as-recovery, named rows above) | 4 per 2 d become named with a re-run **[M]** | S | None (text only) | no | 85 |
| G3-4 | Suggest to the reso-management-app owner: write unblock-sweep's stamp only after a delivered run, and give mcp-auth-guard a cache-only fast path, with the `claude mcp list` refresh detached. | Removes 3 of 4 foreign cancels' root cause **[E: all were >20 s sweeps or the `mcp list` path]**. | S | Foreign repo; owner's call. A project settings timeout bump would be an operator edit. | project settings only if timeouts change | 60 |

## 4. How this changes the README
- **#8 / Wave 3.2** (`README.md:38`, `:184`): the reader can no longer decide alone. On prompt 1 it reports *possible* losses. The authority is the 3.4 worker's transcript scan, which is moved from phase 2 into Wave 3 for SessionStart.
- **3.1** adds `session.start` (transcript path, size, time) and `owed=`.
- **D1** (`:80`): count project hooks as 4 (not 4-5) **[M]**. Its recovery column gains the foreign rows. Its durable record becomes "transcript record (authority) plus sentinels".
- **§3 note** (`:102`): reworded as in §2.
- **D16 / Q8** (`:95`, `:266`): "exited normally after their cancel" should read "finished normally inside the harness lag; output still discarded" (F3). This raises the priority of commit-by-proof.
- **Q2** (`:260`): partial evidence that the process tree is killed (F4). **Q3** (`:261`): answered "usually no" (F2).
