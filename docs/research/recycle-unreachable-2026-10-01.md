# Pane 19 recycle abort, 2026-10-01: verdict and fixes

Read-only investigation. Nothing was typed, closed, killed or edited. Times are UTC.

## Verdict

**This is a real, intermittent outage of kitty's remote-control API.** It is not a misread, and the outer `timeout 110` did not cut anything.

- Attempt 1 ran with no outer timeout. It took 12.5 min under load 150-250 on 10 cores. Its own resolver gave up after 5 queries; each one hit the per-query 10 s bound. It aborted safely, with the correct message and the correct row.
- Attempt 2, the "retry", is **not** evidence of anything. It exited in about 0.6 s, wrote no row to `handoffs.jsonl`, and its output went through `grep -E "ABORTED|recycle|→|!!"`, which kept nothing. The session's claim that it "got the same result" is unsupported. The cause of that 0.6 s exit could not be recovered. The candidates I checked are ruled out: the in-flight guard, the recycle lock, the capacity gate, a missing prompt file, and a checkout advance mid-run (the 06:55:37 advance was docs-only).
- The API is deaf **right now** too. At 07:01 (load 51) `kitten @ ls` answered in 0.10-0.12 s and `it2 session list` in 0.30-0.33 s, three times each. At 07:08-07:09 (load 120-133), 9 of 9 queries failed at exactly 10 s: `kitty @ ls`, `kitty @ ls --match id:19`, `kitten @ ls` with a 40 s outer bound, and `it2 session list`. The error was `Error: read unix ->/tmp/kitty-610: i/o timeout`.
- The likely driver is kitty's main process (pid 610), which sits at **PRI 4, the Darwin background band**. Six samples gave 4 every time. The frontmost app is `loginwindow`, meaning the screen is locked, and `NSAppSleepDisabled` is not set for `net.kovidgoyal.kitty`. 32 `.app` processes are at PRI 4, so this looks like macOS deprioritizing a non-frontmost GUI app, not our tooling: `bin/cc-reaper:551` exempts kitty. Background band plus load 120-250 means kitty's event loop starves and its socket stops answering. I have not proven App Nap is the mechanism (about 60%).

## Evidence

### Q1: pane 19's socket and environment are correct
- Pane 19's claude pid is 19014 (cwd film-mvk, `--resume 3a06361f…`, started 15:54:32 CDT, after the reboot). Its environment: `KITTY_PID=610 KITTY_WINDOW_ID=19 KITTY_LISTEN_ON=unix:/tmp/kitty-610`.
- That matches this session exactly. `/tmp/kitty-610` was created at 15:29, and kitty pid 610 started at 15:29:01 CDT, after the 15:26 reboot. There is one kitty instance (10 OS windows, 32 windows).
- When the API answers, window 19 resolves: pid 18805, title "Launch film with motion-video-kit".
- Process ancestry: claude 19014 (ttys030) → expect 19003 (ttys016) → bash 18805 (ttys016) → kitty 610. So the pane's tty is ttys016.

There is no stale environment, no second socket and no second kitty.

### Q2: the exact refusal
Transcript: `~/.claude-quaternary/projects/-Users-chrisren-Development--worktrees-film-mvk/3a06361f-b508-4002-ad3b-e4b476c8c209.jsonl`.

Attempt 1 started at 06:42:45 with `handoff-fire.sh --recycle --prompt-file /tmp/fire-film-mvk-recycle.txt 2>&1 | tail -6`. The Bash tool moved it to the background at 120 s, and it completed at 06:55:16. Its output (task `bb1ml3w7h`):

```
⚠ self-identity UNPROVEN for pane 19 (the terminal API returned no owner) — proceeding on the environment's claim, as before this gate existed
→ recycle: $PWD is a linked worktree — relaunch falls back to /Users/chrisren/Development/claude-infrastructure if it is removed during exit (...)
⚠ payload-lint (advisory): one-way fire with no back-channel block (...)
!! recycle ABORTED (resolver CANNOT TELL): the pane→tty resolver never answered for session 19 — 5 attempt(s), every one a FAILED query. This says nothing about the pane; it is almost certainly still here (you are running inside it).
!!   recover: retry once the terminal API answers again. Nothing was typed and nothing was closed.
```

`~/.claude/logs/handoffs.jsonl` shows `recycle-intent` at 06:54:25Z, then `recycle-held-unreachable` at 06:55:16Z ("pane→tty resolver never answered (5 failed queries)"). That is 51 s, which equals 5 × 10 s plus 4 × 0.3 s.

Attempt 2 ran at 06:55:26: `timeout 110 … --recycle … 2>&1 | grep -E "ABORTED|recycle|→|!!" | tail -5; tail -1 /tmp/mvk-r5.log`. Its whole result was `frame 480/720 83.4s`, the render log line. There was no row.

Code map (`scripts/handoff-fire.sh` at 871ec4fce, which is live):
- `:2127-2133` `verify_self_pane`: `pane_ownership` returns `unknown`, which prints "self-identity UNPROVEN". This was the first deaf probe, around 06:43.
- `:14997` emits the `recycle-intent` row.
- `:15027-15036` calls `as_tty_classified "$SID"`. On rc 3 it emits `recycle-held-unreachable`, prints the abort, and exits 1. Exits 0 and 1 go elsewhere.
- `:1696-1710` `as_tty_classified` makes `HANDOFF_TTY_RETRIES` (5) attempts with a 0.3 s sleep between them. Each failed query is retried, and the result is rc 3, "CANNOT TELL".
- `:1744-1766` `_as_tty_query`, kitty branch: `kt_window_field "$1" pid`, which is `kt ls | python3` (`:1397`). A failed `kitty @ ls` gives rc 1.
- `:1359` `kt` = `hf_bounded kitty @ …`. `hf_bounded` (`:1005`, `:1027-1033`) is `timeout -k 3 $HF_TIMEOUT_S`, with `HF_TIMEOUT_S=10` (`:979`).
- This path does not call `it2 session list`. `await_pane_proof`/`pane_proof` (`:1838`) are on the watcher and self-close side.

### Q3: did `timeout 110` cut an inner wait? No, but it is still the wrong shape
- Attempt 1 had no outer timeout, and the resolver gave up on its own bound.
- Attempt 2 finished in 0.6 s, so the 110 s bound never fired.
- Even so, 110 s is far below the work this command does:
  - The measured end-to-end time for attempt 1 was **12.5 min**. Before the intent row alone it took 11.7 min (06:42:45 to 06:54:25), and I could not attribute that time; nothing in the script records per-phase timing.
  - In-process inner budgets: the resolver is about 51-66 s per call and runs twice (self-identity, then the recycle query). The composer gate takes up to `CC_RECYCLE_DRAFT_WAIT` 180 s (`:15102`). The relogin path takes `HANDOFF_RELOGIN_TIMEOUT_S` 90 s (`:495`).
- An outer 110 s bound can only convict a slow but healthy recycle. This is the same shape `docs/lessons/never-wrap-ship-in-your-own-timeout.md` describes.
- On TERM the EXIT trap (`:8441`) releases the recycle lock. Nothing writes an outcome row for a run killed after the intent row.
- The second defect in attempt 2 was piping through `grep`. That hid the only evidence of why it exited.

### Q4: do 476712b2f (F-e) and 7eb551b39 (F-b) cover --recycle, and are they live?
- **Both are live.** `~/.claude/scripts/handoff-fire.sh` links to the shared checkout, which is at 871ec4fce, equal to origin/main with 0 commits behind. The reflog shows the checkout first carried both commits at 06:21:08Z (01:21:08 CDT), 21 min before attempt 1. The `recycle-held-unreachable` row at 06:55:16 is F-e working.
- **F-e covers this case only for reporting.** You get an honest message ("says nothing about the pane") and an outcome row. Before it, panes 3 and 38 left `recycle-intent` rows with no outcome.
- **F-b does not cover recycle's retry.** Its wait-and-re-arm (`CC_SELFCLOSE_NOANSWER_WAIT_S` 75 s, up to 3 arms, header at `:1850-1859`) runs only on self-close. For recycle, 7eb551b39 adds only the rc 3 row on the watcher's probe (`:15334`). The resolver rc 3 at `:15029` still exits 1 at once, with no wait and no retry.
- F-b's durable half is inert on trunk anyway. `scripts/lib/pane-close-queue.sh` and `scripts/pane-close-retry.sh` are absent from origin/main and from `~/.claude`. They exist only on unlanded `fix/husk-fb`, as `selfclose-failures-2026-10-01.md` row M2 says.

### Q5: how often over 7 days
Two sources:
- Transcripts in all four config dirs modified in the last 7 days. I kept only tool results whose own command ran `handoff-fire.sh --recycle`, not quotes of the code.
- `handoffs.jsonl`. It is rotated and only reaches back to 2026-09-29 10:39Z.

Both agree: **3 real recycle aborts on "resolver CANNOT TELL", 3 sessions, 3 panes, all on 2026-10-01 after the reboot and under heavy load.**

| pane | session | intent → abort | later outcome |
|---|---|---|---|
| 3 | 0ad2deb9 (one transcript copy is 5e4cbbe8) | 02:36:07 → 02:36:59 | retried 03:07, held on an unreadable composer; recycled 05:06 (about 2.5 h later) |
| 38 | 4d7c9bce (w5b2) | 05:24:15 → 05:25:07 | recycled 06:24 (59 min later) |
| 19 | 3a06361f (film-mvk) | 06:54:25 → 06:55:16 | still in place |

None happened on 09-24 to 09-30. All three later retries that reached kitty while it answered succeeded, which points to a transient stall rather than a lasting fault.

The self-close twin (M2 in `selfclose-failures-2026-10-01.md`) had 10 attempts across 6 sessions between 01:40 and 02:36Z, also on 10-01.

## Ranked fixes

1. **The recycle resolver should wait for an answer instead of aborting, and the wait should run detached** (`scripts/handoff-fire.sh:15029-15033`). Conviction **80%**.
   - Reuse F-b's shape (`:1850-1859`, the `sc_*` helpers). On rc 3, poll a cheap liveness probe (`kitty_socket_accepting` at `:1320`, then one `kt ls`) every 10 s, up to about 5 min, then re-run `as_tty_classified`.
   - Kitty's deaf episodes run from tens of seconds up to more than 12 min under this load. A 51 s resolver window cannot outlast them.
   - Run the wait in a `detach`ed (setsid) helper that owns the `recycle-intent` row. The tool call then returns at once with "recycle armed, waiting for the terminal (row …)", and an outer bound cannot kill it.
   - Add a bats test using the existing `HANDOFF_TTY_FAIL_FILE` seam (`:1741`): a countdown longer than 5 failures must still recycle.

2. **Resolve a self-recycle's tty from the process ancestry, with no IPC** (`_as_tty_query` kitty branch, `:1744-1766`, or at the recycle call site when `RCY_SOURCE_PANE` is empty). Conviction **70%**.
   - The ancestor whose ppid is `$KITTY_PID` is the process kitty launched in this window. Verified here: bash 18805 on ttys016 is window 19's pid.
   - This removes two 51 s deaf points: the self-identity probe at `:2127` and the resolver at `:15028`. It is no less safe, because the walk is live process truth and cannot be stale the way an environment variable can.
   - Typing `/exit`, the composer read and the watcher still need the socket, so this shortens exposure rather than removing it. Pair it with fix 1.

3. **Keep kitty out of the background QoS band.** This is an operator step and machine configuration, so it was not done here. Conviction **60%** that it is the main driver.
   - Run `defaults write net.kovidgoyal.kitty NSAppSleepDisabled -bool YES`. It takes effect only at the next kitty launch.
   - Then check that `ps -o pri= -p <kitty pid>` reads 31, not 4, while the screen is locked.
   - The other lever is load itself: 28 sessions plus `node render.mjs` renders at load 120-250 on 10 cores. The capacity gate admits on memory and mid-turn counts, not on run-queue length.

4. **Record per-phase timing, and stop re-probing a resolver already shown to be deaf.** Conviction **65%**.
   - Attempt 1 spent 11.7 min before its intent row, and nothing records where. Stamp each gate onto stderr, or into the intent row.
   - When `pane_ownership` (`:2057`) has just returned `unknown` because the resolver was deaf, carry that verdict to `:15028` rather than spending another 51 s to learn the same thing.

5. **Make the abort message prescriptive** (`:15031-15032`). Conviction **75%**.
   - Name the probe, as self-close does at `:10720`: `kitten @ ls` should answer in under 2 s.
   - Say "do not wrap this in `timeout`, and do not filter its output".
   - Name the measured runtime under load (minutes, not seconds).

6. **Land `fix/husk-fb`** (`scripts/lib/pane-close-queue.sh`, `scripts/pane-close-retry.sh`) so F-b's durable row and retrier exist on trunk. This is self-close, not recycle, but it is the same class. Conviction **75%**.

## Advice for pane 19 now

Ranked:

1. **Keep working in place for now.** Conviction **85%**.
   - Kitty is deaf at this moment: 9 of 9 probes timed out at 07:08-07:09.
   - A recycle now would spend about 13 min and abort again on the same branch. It is safe, but it does nothing.
   - At 74% context, cheap render polling has room before the 85% line. Keep each poll's output to one line.
2. **Retry once kitty answers.** Gate it on `kitten @ ls >/dev/null` answering in under 2 s on 3 probes in a row; the end of the round-5 render, which lowers load, is a natural time.
   - Run it bare, in the foreground, with the Bash tool's `timeout: 600000`.
   - No outer `timeout`, and no `grep` filter, only `2>&1 | tail -15`, so a refusal is readable.
   - If it ends in the Bash tool's background, read the task output file before concluding anything.
3. **Never wrap the recycle in `timeout 110` again.** The measured runtime under this load is 12.5 min, and an outer bound can only convict a healthy recycle.
4. **Do not treat attempt 2 as a second data point.** It produced no recycle output at all.
5. **If 85% context arrives while kitty is still deaf:**
   - Persist state, which `RECYCLE-BRIEF.md` already does.
   - Keep probing with `kitten @ ls` and recycle at the first clean window.
   - A handoff needs the same API, so it is no escape.
