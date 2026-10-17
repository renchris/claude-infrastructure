# Axis C: per-session daemons and polling loops (2026-10-17)

Scope: the long-lived helpers that Claude Code sessions leave running (watchdogs, inbox watchers, sidecars), plus the machine-wide loops named in the brief. For each one: who launches it, its cadence, how many processes each wake creates, how many it creates per second machine-wide, and which of them can be made event-driven or cheaper with the same outcome. Everything here was read-only. Nothing was killed, signalled, run or edited apart from this file.

Labels: **MEASURED** means a named command was run during this investigation. **ESTIMATED** means a static count from the cited file:line, calibrated against measured per-poll CPU where that was possible.

## 0. Headline

- **The machine-wide fork rate is 866-1,640 process creations/s.** The lead's "150 new pids per 5 s" (30/s) undercounts by about 30-55x.
  - MEASURED with a perl fork-pid delta: `perl -e '... fork ... select(undef,undef,undef,20) ... fork ...'`.
  - 07:34Z, load 133: pids 29724→47047 in 20 s = **866/s**.
  - 07:45Z, load 51: pids 25962→75147 in 30 s = **1,640/s**.
  - The macOS pid space (99,999) therefore wraps every **61-115 s**.
- **The per-session daemons on this axis create about 54 processes/s in total** (ESTIMATED, table below). That is **3-6 % of the machine's fork rate**, and about **0.1-0.2 of a core** (ESTIMATED at ~2 ms of system CPU per fork+exec).
  - This axis is not the root of the load average. That agrees with O5 (`docs/research/load-hook-timeouts-2026-10-11/O5-EXEC-TRACE.md`: test runs ≈84 % of execs, hooks ≈3-5 %).
- **The largest single source is `cc-await-ping`, not `lead-crash-watchdog`.**
  - 15 live inbox watchers, each running a ~31-35-process poll body every 15 s, or every 5 s in `--idle-scoped` mode.
  - Together ≈45 forks/s, about 8x the 28 watchdogs (≈5.6/s).
- **Both loops can become event-driven with no loss of function**, using kqueue (EVFILT_PROC NOTE_EXIT plus EVFILT_VNODE) through one tiny compiled helper that replaces their `sleep`. Wake latency improves at the same time:
  - lead-death detection: ≤30 s → milliseconds;
  - mail wake: ≤15 s (or ≤5 s) → milliseconds.
- **Projected effect** (ESTIMATED): this axis drops from **≈54 to ≈3 forks/s (−95 %)**.
- Side finding for the test-run axis: 85 `sleep` processes orphaned to launchd, all in process group 30621. They belong to the agent-context-sync `install.sh` tests under pytest (§4).

## 1. Snapshot and method

- **Process table, one snapshot.** MEASURED at 07:34:32Z, load 133.60: `gtimeout 40 /bin/ps -axww -o pid=,ppid=,pgid=,etime=,time=,stat=,command=`.
  - 1,523 rows.
  - Saved as Claude tool output (`…/tool-results/bpxxtpfx7.txt`, outside the repo).
- **Instance counts** (MEASURED, `grep -cE` on the snapshot):

| Process | Count |
|---|---|
| `bash …/lead-crash-watchdog.sh` | 28 |
| `bash …/cc-close-attrib` | 27 |
| `bash …/cc-await-ping` | 15 (11 `--interval 15`, 1 `--interval 30`, 3 `--idle-scoped` at 5 s) |
| python `cc-await-ping-sender` sidecars | 15 |
| `mailbox-wake-arm.sh` | 10 processes = 5 arms (parent plus a `$(…)` subshell each) |
| `cc-pane-runner` | 6 |
| `compressor-sentinel.sh` | 1 |
| `assignee-pane-residency.sh` | 3 |
| `session-index-sweep.sh` | 2 |
| `.bin/claude` | 56 |
| `claude.exe` | 3 |
| `ms-365-mcp-server` | 29 |
| `gitstatusd` | 19 |
| `caffeinate` | 9 |
| `<defunct>` | 223 |

- **Who parents each `sleep`.** MEASURED with an awk join of each `sleep N` row to its parent's command:
  - `sleep 30` ×28 ← lead-crash-watchdog;
  - `sleep 15` ×11 and `sleep 5` ×3 ← cc-await-ping;
  - `sleep 10` ← compressor-sentinel and reso-management-app `load-sampler.sh`;
  - 58 `sleep 5`, 17 `sleep 120` and 10 `sleep 10` have **ppid 1**, all in pgid 30621 (§4).
- **Watchdog leak check.** MEASURED: for each `~/.claude/watchdog/*.daemon` whose daemon pid is live, I read `<sid>.pid` and looked that pid up in the snapshot.
  - 28 live daemons; **28 watch a live lead, 0 watch a dead one**.
  - The {pid, start-time} fixes at `hooks/lead-crash-watchdog.sh:1890-1903` and `:2035-2045` hold. No daemons have leaked. The count tracks the session count.
- **Per-poll CPU calibration.** MEASURED as each loop's own bash CPU (`time` column) ÷ (etime ÷ interval):

| Loop | bash CPU per wake |
|---|---|
| lead-crash-watchdog | **1.29-1.59 ms/poll** |
| cc-await-ping `--interval 15` | **6.6-8.3 ms/poll** |
| cc-await-ping `--idle-scoped` | **9.0-9.1 ms/poll** |
| compressor-sentinel | **13.1 ms/tick** |

  - Parent CPU scales with the number of forks the shell itself makes (fork, pipe read, wait).
  - The watchdog makes 3 such forks per poll, so ≈0.45 ms each. cc-await-ping's 6.6-9 ms therefore corresponds to ≈15-20 parent-level fork equivalents, which matches the static count in §2.
- **RSS of resident helpers.** MEASURED with `ps -o rss= -p <list>`:

| Helper | Total RSS |
|---|---|
| ms-365-mcp-server | 29 × 34 MB = **996 MB** |
| python sigrecord sidecars | 13 × 4.8 MB = **63 MB** |
| watchdog bash | 28 × 1.9 MB = 53 MB |
| cc-close-attrib | 27 × 1.8 MB = 48 MB |
| cc-await-ping bash | 13 × 4.2 MB = 55 MB |
| gitstatusd | 19 × 2.6 MB = 49 MB |

### Counting rule for the static estimates

The scripts run under `/bin/bash` 3.2.57 (MEASURED: `/bin/bash --version`).

| Construct | Processes counted |
|---|---|
| `$(simple-command)` | 1 |
| `$(function)` | 1 subshell, plus whatever the function forks |
| `$(a \| b \| c)` | 1 subshell + 3 |
| external command | 1 |
| builtins (`kill -0`, `[`, `printf`, `read`) | 0 |

Bash before 5.1 also implements every here-document **with a temporary file** (create, write, reopen, unlink). Bash 5.1 CHANGES: "Here documents and here strings now use pipes for the expanded document if it's smaller than the pipe buffer size". So `<<EOF` in a 3.2 loop costs filesystem churn rather than a fork.

## 2. Inventory table, ranked by forks/s

| # | Helper | Launched by | Scope | Wake interval | Processes per wake (ESTIMATED, file:line) | Instances (MEASURED) | Forks/s machine-wide (ESTIMATED) | Share of 866-1,640/s |
|---|---|---|---|---|---|---|---|---|
| 1 | `bin/cc-await-ping` | `hooks/mailbox-wake-arm.sh:229` (SessionStart + Stop asyncRewake hook, 5 live) and models arming it from the Bash tool (10 live) | per session | 15 s default (`:153`), 5 s idle-scoped (`:200`), 30 s on request | default ≈31, idle-scoped ≈35 (breakdown below) | 15 | 11×31/15 + 1×31/30 + 3×35/5 ≈ **45** | 2.7-5.2 % |
| 2 | `hooks/lead-crash-watchdog.sh` daemon (`:1988-2377`) | SessionStart hook, one detached daemon per lead | per session | 30 s (`:2121`) | 6: `$(cat pidfile)` 1 (`:2088`), `$(ps -o lstart= \| tr \| sed)` 4 (`:2039`), `sleep` 1 | 28 | 28×6/30 = **5.6** | 0.3-0.6 % |
| 3 | `scripts/compressor-sentinel.sh` | launchd `com.claude.compressor-sentinel` (KeepAlive) | machine | 10 s (`:90`, loop `:1871-2207`) | ≈36 per tick (below); census every 6 ticks adds 3 full-table `ps` + ≈8 awk (`:651-661`, `:1952`) | 1 | ≈3.6 + 0.2 = **3.8** | 0.2-0.4 % |
| 4 | python `cc-await-ping-sender` sidecar (`bin/cc-await-ping:675-729`) | each cc-await-ping at arm | per watcher | `time.sleep(5)` getppid poll (`:720-723`) | 0 forks; 1 wakeup | 15 | 0 forks (3 wakeups/s; 63 MB RSS) | 0 |
| 5 | `bin/cc-close-attrib` | launcher exec-wrapper around claude | per session | none: blocking `wait "$child"` (`:533-536`); launch watchdog sleeps once for 20 s, then exits (`:494-496`) | 0 in steady state | 27 | **≈0** | 0 |
| 6 | `hooks/mailbox-wake-arm.sh` | SessionStart + every Stop (asyncRewake) | per session | none: blocks in `$(cc-await-ping …)` (`:233`) | per Stop: ≈20-30 (ancestry `ps` per hop `:105-112`, `lsof` `:126`, jq `:139`, keyset), then the claim guard `:188-203` | 5 | Stop-rate bound; < 1/s | < 0.1 % |
| 7 | `bin/cc-pane-runner` | kitty pane launch | per pane | 50 ms (`:366-371`), only in FILE mode until the command file lands; then it waits on its zsh child | 0 in steady state | 6 | **≈0** | 0 |
| 8 | `hooks/session-index-sweep.sh` | launchd `StartInterval` 60, internal minimum interval 300 (plist env) | machine | 60 s gate | gate cost only, when not due | 1 run (9.5 min old) | < 0.2 | ≈0 |
| 9 | `scripts/assignee-pane-residency.sh` | `teammate-reap-alarm.sh`, launchd 600 s | machine | 600 s | one sweep | 1 run | < 0.1 | ≈0 |
| | **Total, this axis** | | | | | | **≈54** | **3.3-6.3 %** |

### cc-await-ping, one default-mode poll (`bin/cc-await-ping:1568-1687`, pane key with an alias)

- `resolve_uuid` in `$()`: 1 (`:1569`).
- `mkdir -p` ×2: 2 (`:1578`, `:412`).
- `_keys` computed **twice** per poll, by `_beat` `:411` and the loop `:1592`. Each call is ≈8: `$(_keys)` 1 → `mailbox_keyset` → `$(mailbox_alias_of)` 1 → `$(tail -n1 "$(_mbx_alias_file)" | awk)` = 1 + `$(_mbx_alias_file)` 1 + `$(_mbx_alias_dir)` 1 + `$(_mbx_dir)` 1 + tail 1 + awk 1 (`hooks/lib/mailbox-pending.sh:112-114`, `:900-906`, `:1183-1190`). Subtotal 16.
- `_owner_dead` jq: 1 (`:1263`).
- Per key, ×2 keys:
  - `$(_woke_get)`: 1, plus a here-doc temp file (`:1314-1321`);
  - `$(mailbox_lines)` → `$(mailbox_file)` → `$(_mbx_dir)` → `$(grep -c '')`: 4 (`mailbox-pending.sh:232-237`).
  - Subtotal 10.
- `sleep`: 1.
- **Total ≈31 processes**, plus **4 here-doc temp files** and **4 marker rewrites** (`.watching` and the claim file per key, `:409-423`) per poll.
- `--idle-scoped` adds `_turn_moved`, 1-2 jq via `$(_beat_field)` (`:627-635`), so ≈35. Its measured CPU per poll is 20 % higher (9.0 vs 7.4 ms), which is consistent.

### compressor-sentinel, one tick (`scripts/compressor-sentinel.sh:1871-2207`)

| Step | Processes |
|---|---|
| `date` | 1 |
| `read_vm_stat` (subshell, `vm_stat`, `awk`; `:395-396`) | 3 |
| `read_swap_used_bytes` (`:387`) | 3 |
| `read_num_sysctl` ×7, each a subshell + `sysctl` (`:363-365`; called at `:1880-1882`, `:1925-1928`) | 14 |
| `segs_in_core` / `segs_swapped` awk (`:418`, `:426`) | 4 |
| `SEG_PCT` awk (`:1910`) | 1 |
| `CLIFF` awk (`:1918`) | 1 |
| 3 rate awks (`:1943-1945`) | 3 |
| `classify_breach` | 2 |
| clear-streak awk | 1 |
| `TS` `date` | 1 |
| `ROW` `printf` subshell | 1 |
| `sleep` | 1 |
| **Total** | **≈36** |

## 3. Which polling can be event-driven on macOS with no loss of function

### Mechanism: kqueue, not fswatch

- kqueue `EVFILT_PROC`/`NOTE_EXIT` attaches to a process the caller may signal (same uid). It fires at exit, with no polling.
  - The repo already depends on this: `bin/cc-deathwatch-kqueue:1-6`, "verified: fires at child-exit within ~1ms".
  - `/usr/bin/caffeinate -w <pid>` uses the same facility for arbitrary pids.
- `EVFILT_VNODE` on an `O_EVTONLY` fd gives `NOTE_WRITE|NOTE_EXTEND` for appends, and `NOTE_DELETE|NOTE_RENAME` when a file is replaced.
- It suits these writers:
  - cc-notify appends with `>>` on the same inode (`bin/cc-notify:1197`), so NOTE_EXTEND fires;
  - session-beat replaces with `mv -f` (`hooks/session-beat.sh:224`, `:248`), so the watched old vnode gets NOTE_DELETE;
  - the watchdog pidfile is rewritten in place or deleted (`lead-crash-watchdog.sh:1922`; `session-end.sh` deletes it), so NOTE_WRITE or NOTE_DELETE fires.
- fswatch is **not installed** (MEASURED: `which fswatch` → not found). It also sits on FSEvents, i.e. fseventsd, which is already at 114 % CPU. kqueue VNODE events are per-vnode in the kernel and do not pass through fseventsd.

### Delivery: one compiled helper, `cc-kqwait`

- It replaces `sleep` inside each loop.
- It is a ~120-line C program embedded in a bin script and compiled on demand into a hash-keyed cache. The repo precedent is `bin/cc-jetsam-exec:205-245` (embedded C source, `clang -O2`, cache `~/.cache/cc-jetsam/<srchash>-<arch>`, smoke-tested before use).
- Interface:

```
cc-kqwait [--pid PID[@START_EPOCH]]... [--file PATH[@SIZE:MTIME_NS]]... [--appear PATH]... --timeout S
  → prints exactly one line, then exits 0:
      exit <pid> | gone <pid> | vnode <path> <flags> | appear <path> | timeout
    and, for every --file, prints its current "@SIZE:MTIME_NS" so the caller can pass it back next time
  → if any --file's current stat differs from the baseline passed in, it returns at once: an event that
    landed while the caller was running its body is never lost
  → --appear PATH: kqueue NOTE_WRITE on the parent directory, filtered INSIDE the helper with stat(PATH),
    so a busy directory such as ~/.claude/mailbox (3,198 entries; cursor files are rewritten with tmp+mv,
    hooks/lib/mailbox-pending.sh:228) does not cause spurious wakes
  → @START_EPOCH is checked with proc_pidinfo(PROC_PIDTBSDINFO).pbi_start_tvsec AFTER EV_ADD, so a
    recycled pid reads "gone" (the pid space wraps every 61-115 s here)
```

- If the helper cannot be built or exec'd, the caller runs `sleep "$INTERVAL"` exactly as today. Behaviour is never worse than the current state.

### Per-loop verdict

| Loop | Event sources that cover every exit or wake condition the loop tests today | Remaining need for a timer | Verdict |
|---|---|---|---|
| lead-crash-watchdog (`:2051-2122`) | lead NOTE_EXIT (the crash branch `:2096-2100`); pidfile NOTE_DELETE (clean end `:2071-2080`) and NOTE_WRITE (SUPERSEDED `:2088-2092`) | none for correctness. A 300 s safety timeout re-runs the same body (keeps the DST/TZ re-pin path `:2101-2120` reachable and bounds any missed event) | **Event-driven. The loop body stays byte-identical; only `sleep 30` changes.** |
| cc-await-ping (`:1568-1687`) | mail: NOTE_EXTEND/NOTE_WRITE on each key's `.md`, or `--appear`; owner death: NOTE_EXIT on the registry pid (`_owner_dead` `:1260-1270`); role re-point: VNODE on `$ROLES_DIR/$ROLE` (`:206-215`); alias change: VNODE on the alias file (`mailbox-pending.sh:113`); idle-scoped turn: NOTE_DELETE on `$BEAT_DIR/$SID.json` (`:627-635`) | **Yes, a heartbeat.** Readers treat a claim older than `CC_WATCH_FRESH_S:-90` as dead (`bin/cc-await-ping:389`, `hooks/lib/mailbox-pending.sh:320`), so `_beat` must re-stamp within 90 s. Use a 30 s timeout, and on a timeout wake run only `_beat` + `_owner_dead`. Mail cannot be missed, because the stat baseline makes the helper return immediately on any change. | **Event-driven plus a 30 s heartbeat.** Mail and turn wakes become instant. |
| python sigrecord sidecar (`:720-723`) | parent death: NOTE_EXIT on the parent | none | Fold into `cc-kqwait` (§5 R5). |
| compressor-sentinel | none: every trip term is a RATE over a fixed sample period (plist comment, `launchd/com.claude.compressor-sentinel.plist:36-42`) | intrinsic | **Not convertible.** Streamline the tick instead (R4). |
| cc-close-attrib, cc-pane-runner, mailbox-wake-arm | already blocking waits | none | No change needed. |

### One machine-wide multiplexing supervisor, considered and rejected for now

- **What it would save beyond per-wait `cc-kqwait`:**
  - ≈0.5 forks/s (the heartbeat/timeout re-execs);
  - ≈28 idle bash processes (53 MB RSS MEASURED).
- **Costs:**
  1. A single point of failure for every session's crash alarm, the "who watches the watcher" problem that `scripts/lead-deathwatch.sh:23-27` already has to solve.
  2. It serializes `handle_crash` across simultaneous deaths unless it forks per death anyway. `pane_verdict_settle` sleeps in 5 s steps (`:1581-1590`) and `pane_verdict_close` sleeps 20 s (`:1821`). A panic or a kitty crash kills many leads at once, which is exactly when serialization would delay alarms.
  3. The per-session daemon captures the lead's TTY, pane, config dir, cwd and teammate argv **by value at spawn** (`:1924-1955`). A hub would have to persist and re-read that per session.
  4. The plan's Rejected list already excludes new daemons (`docs/plans/LOAD_AND_PROMPT_HOOK_TIMEOUTS.md:157`).
- The per-wait helper gets ≈95 % of the saving with none of these costs.
- Hub variant also rejected: watchers blocking on `read` from a per-watcher FIFO (bash builtin, zero forks). It needs `read -t <interval>` to fall back when the hub is dead, and that fallback re-introduces today's cadence unless the hub also sends liveness ticks. That adds complexity for ≈0.5 forks/s.

## 4. Side finding for the test-run axis (not this axis's fix)

- All 85 `sleep` processes reparented to launchd sit in **pgid 30621**: 58 `sleep 5` (etime 0-5 s), 10 `sleep 10`, 17 `sleep 120` (6 s - 1:57).
- The group leader is a Claude Bash-tool `zsh -c source …snapshot… lockf /tmp/b13-r13…` that runs the agent-context-sync `r13-d` pytest gate.
- The same group holds nested `install.sh --report-only` chains and `xcodebuild -license check`.
- So each `install.sh` invocation under test leaves a background `sleep` alive after it exits. With 58 `sleep 5` in flight, that is ≈12 leaked sleep forks/s from one gate alone (MEASURED counts; rate ESTIMATED as count ÷ sleep length).
- Owner: the test-run axis (agent-context-sync `scripts/install.sh`).

## 5. Recommendations

### R1 (P0): lead-crash-watchdog waits on kqueue instead of polling

- **Change:** `hooks/lead-crash-watchdog.sh:2121`, `sleep 30` → `_lcw_wait`. That is `cc-kqwait --pid "$pid@$LEAD_START_EPOCH" --file "$pid_file" --timeout 300`, falling back to `sleep 30` when the helper is absent.
- **Pure-bash streamlining** for the fallback path, and for the body that still runs on every wake:
  - `holder=$(cat "$pid_file")` (`:2088`) → `IFS= read -r holder < "$pid_file"`, 0 forks;
  - `lead_alive`'s `ps | tr | sed` (`:2039`) → a single `ps -o lstart= -p`, normalized in-shell with `set -f; set -- $cur; cur="$*"`, giving 1 fork instead of 4.
  - Keep the `sed` only for the leading/trailing-space semantics. Word-splitting already produces the identical string, but a parity test must confirm it.
- **Effect:** 28 × 6/30 = 5.6/s → 28 × 3/300 ≈ 0.3/s with the helper (**−5.3 forks/s**), or → 28 × 2/30 = 1.9/s on the bash-only fallback. Lead-death detection: ≤30 s → milliseconds. ESTIMATED.
- **Constraint:** removes idle polling of a process that is not doing session work; the crash ladder still runs, and runs sooner.
- **Verify:** all `tests/lead-crash-*.bats`; a new bats that kills a fixture lead and asserts the `LEAD CRASH detected` log line within 1 s; and a count of the daemon's children over 5 min with `pgrep -P`, single pid.

### R2 (P0): cc-await-ping waits on kqueue, with a 30 s heartbeat

- **Change:** `bin/cc-await-ping:1685-1686`, `sleep "$INTERVAL"` / `elapsed+=INTERVAL` → `cc-kqwait` on:
  - each key's `.md` (or `--appear` when it does not exist yet), with the stat baseline;
  - the registry pid, the role file, the alias file, and the beat file when idle-scoped;
  - `--timeout 30`.
- `elapsed` comes from the wall clock (`_elapsed_s`, `:135`).
- On a `timeout` wake, run only `_beat` and `_owner_dead`; on any other wake, run the full body as today. Every 10th timeout wake also runs the full body as a backstop.
- **Effect:** ≈45 forks/s → (15 watchers × ≈3/30 s) ≈ 1.5/s (**−43 forks/s**). Here-doc temp files and marker rewrites go from ≈11/s to ≈1/s. Mail wakes ≤15 s (≤5 s) → milliseconds. ESTIMATED.
- **Verify:** `tests/cc-await-ping*.bats`, plus a new case that appends a line and asserts wake latency < 1 s. Heartbeat freshness < 90 s must hold under `mailbox_wake_armed`.
- **Risk:** the most semantics-dense loop in the fleet. The orphan exit (rc 5) and stood-down exits must keep parity, so build the test first.

### R3 (P1): cc-await-ping per-poll streamlining, independent of R2

- **Changes:**
  - Compute `_keys` once per poll and reuse it in `_beat` (`:411`) and the loop (`:1592`).
  - Memoize it across polls until the alias file changes, tested with the `-nt` builtin against a remembered stamp variable or file.
  - Resolve the mailbox file path once at arm instead of `$(mailbox_file)` → `$(_mbx_dir)` on every count.
  - Replace the here-doc scans in `_woke_get` / `_woke_set` (`:1314-1340`) with `case`/parameter expansion over `$WOKE_MAP`.
  - Turn `mkdir -p` (`:1578`, `:412`) into `[ -d ] || mkdir -p`.
- **Effect:** ≈31 → ≈9 processes per poll and 4 → 0 temp files per poll, i.e. ≈45 → ≈13 forks/s (**−32/s**) even if R2 never lands. ESTIMATED.
- **Constraint:** same predicates over the same files; it only stops recomputing the same answer.

### R4 (P1): compressor-sentinel tick in fewer processes

- **Changes:**
  - Read the 9 sysctls in **one** `sysctl vm.a vm.b …` call (names kept, so a missing OID cannot shift values) and parse with `while read`. Sites: `:363-365`, `:387`, `:1880-1882`, `:1925-1928`.
  - Compute every derived value in **one** awk per tick: `:418`, `:426`, `:1910`, `:1918`, `:1943-1945`, `classify_breach`.
- **Effect:** ≈36 → ≈8 processes per tick, 3.6 → 0.8 forks/s (−2.8/s). ESTIMATED.
- It also shortens tick wall time under load, which is when this guard matters: `:1912-1914` records ticks stretched from 10 s to 121-146 s at the cliff.
- **Verify:** a differential replay comparing old vs new JSON rows byte for byte over recorded sysctl/vm_stat fixtures (seam: `CC_SENTINEL_*` snapshot seams, `:341`).

### R5 (P2): fold the python sigrecord sidecar into the helper

- **Change:** while `cc-kqwait` waits (≈99.9 % of a watcher's life), it installs SA_SIGINFO handlers for TERM/HUP/INT and writes the same `sig= si_pid= …` line that `bin/cc-await-ping:700-709` writes.
- **Effect:** 13-15 python processes (63 MB RSS MEASURED, 3 wakeups/s) and one python3 start per arm → 0.
- **Gap:** a group signal landing during the ≈10 ms body window is not recorded. That window is ≈0.03 % of the time.

### R6 (P2): mailbox-wake-arm runs the claim guard first on Stop

- **Change:** in `hooks/mailbox-wake-arm.sh`, compute `_key` and run `_armed_already` (`:188-203`) **before** the ancestry `ps` walk and `lsof` (`:99-135`), but only when `_key` is non-empty. Otherwise keep today's order, so the `.unaddressable` marker semantics hold (`:155-168`).
- When a watcher already covers the inbox, both orders end in `exit 0`.
- **Effect:** saves ≈10-15 processes and one `lsof` per already-armed Stop. The rate is bounded by Stops, likely < 1/s machine-wide.

### Total

| | Forks/s (ESTIMATED) |
|---|---|
| Today | ≈54.4 |
| R1 + R2 + R4 | ≈0.3 + 1.5 + 0.8 ≈ **2.6** (−51.8/s, **−95 %**) |
| R1-fallback + R3 + R4, no compiled helper | ≈1.9 + 13 + 0.8 ≈ **15.7** (−71 %) |

- Machine-wide this is −3 to −6 % of the measured fork rate. It is a real cut, but **not** the load-average lever; per O5 and §4, that lever is test-run concurrency and its fixtures.
- What this axis delivers beyond the cut: millisecond lead-death detection and mail wakes, ≈11 → ≈1 filesystem mutations/s from watchers, and −63 MB of python sidecars.

## 6. Refuted or rejected

- **"150 new pids per 5 s"** (lead's context): refuted. The pid-counter delta measured 866/s and 1,640/s.
- **lead-crash-watchdog as the top per-session cost:** refuted. cc-await-ping is ≈8x larger (§2).
- **DESIGN item 10 / WP11** (`docs/research/load-hook-timeouts-2026-10-11/DESIGN.md:173-178`, "−400 spawns/min ≈1.4 %"): consistent. I measure 5.6/s = 336/min, now 0.3-0.6 % of a higher total.
  - It was parked on O5 (`LOAD_AND_PROMPT_HOOK_TIMEOUTS.md:37`). R1 re-scopes it from a "one watcher" rewrite (≈400 LOC) to a `sleep` swap.
- **Python `cc-deathwatch-kqueue` per session as the waiter:** rejected. It costs ≈10 MB footprint each (`bin/cc-await-ping:661-665` measured ~10.3 MB per python sidecar), i.e. ≈280 MB for 28 sessions under memory compression, plus a python start per re-arm.
- **`caffeinate -w PID`:** rejected. It takes an idle-sleep power assertion as a side effect and cannot watch files.
- **fswatch / FSEvents / launchd WatchPaths:** rejected. Not installed, and it adds load to fseventsd (114 % CPU) with coalescing latency. WatchPaths spawns a process per event.
- **A machine-wide hub supervisor:** rejected for now (§3).
- **Longer poll intervals, nice/QoS demotion:** out of scope by the operator's constraint (they slow wakes).

## 7. Open questions

- I could not measure per-poll fork counts directly. That needs either running the script under an exec-logging PATH stub, which writes scratch files and so was excluded by the brief, or `eslogger`/`dtrace`, which need sudo. They are ESTIMATED by static count and calibrated by measured CPU per poll. A 30 s `eslogger fork exec` capture (O5 tooling, `/tmp/loadinv/o5-exec-trace.sh`) would confirm them.
- The ms-365-mcp-server runs one node process per session: 29 × 34 MB = 996 MB RSS (MEASURED), and new sessions fail to connect within 30 s.
  - The installed v0.143.0 has `--http [address]` with Streamable HTTP (`…/@softeria/ms-365-mcp-server/dist/cli.js:25`).
  - But HTTP mode switches to OAuth bearer auth and disables account routing (`dist/server.js:114`).
  - Whether one shared localhost server can serve all 4 Claude config dirs from the shared token cache (`docs/plans/MS365_MCP_ALL_ACCOUNTS.md:84-85`) is an MCP-axis question I did not settle.
- I did not count the Stop rate per session, so R6's magnitude is bounded but not measured.
