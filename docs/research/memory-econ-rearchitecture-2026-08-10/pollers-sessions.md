# Axis C — Session-spawned pollers & watchers

Measured 2026-08-10 on the live box (observe-only; nothing killed, nothing reconfigured).
Fleet at snapshot: **16 `claude` lead sessions + 18 `claude.exe` subagents = 34 CC processes**
(comm-anchored: `ps -Ao comm= | grep -cx claude`, immune to the argv-mention miscount —
sibling research agents' briefs quote these script names, so `pgrep -f` overcounts).

## Verdict first

**The session poller population is a CPU/wakeup and correctness problem, not a memory one.**
Every session-spawned watcher on this box totals **~340 MB of physical footprint at 15 sessions
(~0.5% of 64 GB)**, and `memory_pressure` read **85% free** while 34 CC processes ran.
`kern.maxprocperuid` is 10666 against 816 live user processes (7.6%) — no proc-table wall either.
This corroborates prior art: `GROUND_UP_REBUILD_MAP.md` row 13 / `MACHINE_CAPACITY_V2.md` §8.5.7
already **exonerated memory and leaks** ("30 sessions = 44.7 GB and that overcounts shared pages
~2.34×; RSS and fds both flat with age"). **An axis-C answer that promises GB back is wrong.**

What axis C *does* deliver:
1. **18 of 36 watchdog daemons watch a `claude.exe` subagent** — a process class that owns no team,
   so the daemon's entire purpose is structurally inapplicable. 50% of the population is waste by
   construction (not orphaning — see §5, that reading is already falsified).
2. **The statusline is the dominant session poller by CPU** — 0.9 renders/s fleet-wide × 60 ms CPU
   = **5.4% of one core, continuously, O(N sessions)** — ~10× the whole shell-poller population.
3. **Both replacement primitives are already built and unused.** `bin/cc-deathwatch-kqueue`
   (EVFILT_PROC/NOTE_EXIT, ~1 ms, with the {pid,start} recycle guard) exists and the watchdog still
   polls `sleep 30`. `hooks/mailbox-wake-arm.sh` (asyncRewake arming for `cc-await-ping`) exists and
   is **not registered in `settings.json`**.

---

## 1. The poller table

| Poller | Spawn site (file:line) | Cardinality / session | Interval | Awaited event | Event-driven replacement | In-repo precedent |
|---|---|---|---|---|---|---|
| **lead-crash-watchdog daemon** | `hooks/lead-crash-watchdog.sh:829` (subshell) → loop `:898`, `sleep 30` at `:941`; registered `~/.claude/settings.json:646` (SessionStart) | **1 per SessionStart — incl. every `claude.exe` subagent.** Live: 28 daemons / 36 pidfiles / 34 CC procs | 30 s | "has the lead pid died, and is it still the same process" (`kill -0` + `ps -o lstart=` pin, `:875-896`) | **kqueue `EVFILT_PROC`/`NOTE_EXIT`** — fires at exit, no poll, and its arm-time {pid,start} check subsumes the hand-rolled pin | **`bin/cc-deathwatch-kqueue` (already built, selftest-gated by `scripts/wait-safety-gate.sh:48,78`)** — the exact mechanism, unused by this hook |
| **cc-await-ping (wake floor)** | Armed by the AGENT as a `run_in_background` Bash call, prompted at `hooks/session-continue.sh:426` and `hooks/mailbox-drain.sh:259`; loop `bin/cc-await-ping:490`, `sleep "$INTERVAL"` at `:556` | 0–1 per session (**8 live for 16 sessions** — half the fleet is deaf while idle) | 15 s (`--interval 15`, default `:54`) | "a line was appended to `~/.claude/mailbox/<key>.md`" (`mailbox_lines` > private cursor, `:519`) | **kqueue `EVFILT_VNODE` NOTE_WRITE/EXTEND** on the inbox keys, or **push at write time** (`cc-notify` already knows the key it wrote) | `bin/cc-deathwatch-kqueue` is the same Python kqueue shape, one filter away; `launchd WatchPaths` used at `launchd/com.chrisren.screenshot-clipboard.plist` and `gl.reso.worktree-gc.plist` |
| **statusline** | `~/.claude/settings.json` `statusLine.command = ~/.claude/statusline.sh` (377 lines) | **1 per session**, invoked by CC per TUI redraw | **event-ish, measured 0.9 renders/s fleet / ~0.056 per session-second** (1 per ~18 s; a busy session measured 0.091/s = 1 per 11 s) | a TUI redraw | n/a — already event-driven. The cost is per-render work, not cadence → **axis G's lever** | script's own header records the prior optimisation (8 jq pipelines → 1, `statusline.sh:44-52`) |
| **cc-pane-runner** | `bin/it2-kitty` launches `<shell> -l -i -c 'exec "$CC_PANE_RUNNER"'`; poll loop `bin/cc-pane-runner:186-193`, `sleep 0.05` | 1 per agent pane (**21 live**) | **50 ms, but BOUNDED — only until the command file arrives**, then `exec`s. Steady-state cost = 0 wakeups | "Claude Code wrote `$CC_PANE_CMD_DIR/$KITTY_WINDOW_ID.cmd`" | already correct-by-design; the file's own comment rejects a FIFO with a stated reason (`:186-191`) — **do not "fix" this one** | — |
| **cc-close-attrib wrapper** | wraps every `claude` launch; `bin/cc-close-attrib:205` spawns the real binary, blocks in `wait` at `:231-234` | 1 per session (**15 live**) + 1 `tee` (**15 live**) | **not a poller** — `while :; do wait; done` is a blocking wait, the loop exists only because a trapped signal makes `wait` return early (`:227-230`) | child exit | already event-driven | — |
| **caffeinate (per-turn)** | spawned by the **CC binary itself** (parents are `node_modules/.bin/claude` and `bin/claude.exe`) — no in-repo spawn site | 1 per active CC process (**31 live**) | `-t 300` ⇒ respawned every 5 min while active | idle-sleep suppression | vendor-owned; the standing floor `scripts/caffeinate-floor.sh` (`caffeinate -i -s`, pid 818, launchd) already covers the machine | `com.claude.caffeinate-floor` |
| **cc-wedge-watch** | `bin/cc-pane-runner:130` (`_arm_wedge_watch`) | ≤1 per agent pane, 0 live at snapshot | one-shot `sleep "$TIMEOUT"` (`bin/cc-wedge-watch:261`) | a pane that never produced a turn | fine as-is (single timer, not a loop) | — |
| **gitstatusd** | powerlevel10k, per interactive `zsh -l` pane shell | 1 per pane (**12 live**, 1.5–9.9 MB each, 61 MB total) | on-demand (request/response), not a timer | prompt render | n/a — **axis H (terminal layer)**; census handed over | — |
| `terminal-bench.sh --interval 1800 --watch 30` | `scripts/terminal-bench.sh` (ppid 1, 1 live) | 0 (ad-hoc) | 30 s watch / 1800 s bench | a benchmarking probe | out of scope | — |

**Not session-spawned (axis B, listed so the lead can de-duplicate my numbers from `sched-launchd`'s):**
`compressor-sentinel.sh` (`INTERVAL=10`, `:78`, loop `:536`), `capacity-alarm.sh --quiet`,
`lr-reset-poller.sh`, `lead-supervisor.sh --daemon`, `postland-verify.sh --run-if-needed`,
`cc-dispatch --once`, `cc-reaper sweep --reap`, `cc-discover --once`, `deploy-live.sh --auto`,
`autonomy-sweep.sh`, `session-index-sweep.sh`, `worktree-gc-run.sh`.

---

## 2. Aggregate wakes/s and forks/min (from measured intervals, at the measured 16-session state)

| Source | n | interval | wakes/s | forks/tick (counted from the loop body) | forks/min |
|---|---|---|---|---|---|
| lead-crash-watchdog | 28 | 30 s | 0.93 | 5 (`cat` pidfile · `ps -o lstart=` · `tr` · `sed` · `sleep`) | **280** |
| cc-await-ping | 8 | 15 s | 0.53 | ~8 (`mkdir -p` · `jq` owner-read · `grep -c` × keys · `mailbox_keyset` · `date` · `sleep`) | **256** |
| statusline | 16 | render-driven | 0.90 | 8 (`cat` · `jq`×3 · `git rev-parse` · `git status` · `mv` · `basename`) | **432** |
| caffeinate respawn | 31 | 300 s | 0.10 | 1 | 6 |
| **TOTAL (session-spawned steady state)** | | | **≈ 2.5 wakeups/s** | | **≈ 975 forks/min** |

**Machine-wide fork rate could NOT be attributed to pollers** — measured 809 forks/s then 1339
forks/s in two consecutive samples (pid-advance method, `bash -c 'echo $$'` delta over 60 s / 30 s),
because `postland-verify.sh --run-if-needed` was mid-run with 15 live `bats-exec-*` processes under
a `timeout -k 10 10800` (3 h) budget. **The poller contribution (~16 forks/s) is ~1–2% of that.**
Filed as a measurement blocker, not a finding: a fleet fork-rate baseline is unobtainable while a
/Users/chrisren/.claude/bin/cc-bats suite runs, and that suite's budget is 3 h.

CPU: statusline measured **87 ms wall / 60 ms CPU per render** (5 warm runs, in the 115-worktree
`claude-infrastructure` checkout — `git status --porcelain=v2` is the dominant term). At 0.9
renders/s that is **5.4% of one core continuously**, and it is O(sessions). Every shell poller
combined is a fraction of that (a 30 s tick of 5 sub-millisecond forks ≈ 0.1% of a core across 28
daemons).

---

## 3. Per-session process footprint (physical footprint, `vmmap --summary`, not RSS)

RSS overstates: a `sleep` reads 1180 KB RSS but **961 KB physical footprint**.

| Process | measured physical footprint | per lead session | per subagent |
|---|---|---|---|
| lead-crash-watchdog daemon | **1905 K** | 1 | **1** |
| cc-await-ping | **3969 K** | 0–1 | 0 |
| cc-close-attrib wrapper | **1953 K** | 1 | 0 |
| cc-pane-runner | **1969 K** | 1 | 0 |
| `tee` (stderr capture) | ~579 K (RSS) | 1 | 0 |
| `zsh -l` pane shell | ~3657 K (RSS) | 1 | 0 |
| gitstatusd | ~5128 K (RSS) | 1 | 0 |
| caffeinate | ~3642 K (RSS) | 1 | **1** |
| in-flight `sleep` | 961 K | ~1 | ~1 |
| **≈ per session** | | **~22 MB** | **~6.5 MB** |

**At 15 lead sessions + a 12-subagent research wave: ~330 MB + ~78 MB = ~408 MB.**
Command-position-anchored fleet total at snapshot: **438 MB RSS ⇒ ~350 MB physical.**

---

## 4. Findings (6-line row structure)

### C1 — Half the crash-watchdog population watches a process class it cannot help
- **Finding:** `lead-crash-watchdog.sh` spawns one 30 s-poll daemon on *every* SessionStart with no subagent guard, so `claude.exe` sidechain sessions each get one — and a subagent owns no team, no teammate inboxes and no panes, which is the daemon's entire job (`:2-10`).
- **Evidence:** measured — 36 watchdog pidfiles classified by the watched process's `comm`: **lead(`claude`)=18, subagent(`claude.exe`)=18, dead=0**. `grep -n "sidechain\|subagent" hooks/lead-crash-watchdog.sh` → 0 hits; the only early-exit is the duplicate-SessionStart guard at `:795`.
- **Cost now:** 18 daemons × (1.9 MB + 5 forks/30 s) = **34 MB + 180 forks/min for zero possible benefit**; each also holds a pidfile, a `.id` file and a log stream. Scales with wave width, not session count — a 20-subagent research wave adds 20.
- **Re-architecture:** one guard at the top of the hook — skip when the session is a sidechain (no pane id AND no team dir), the same discriminator `hooks/mailbox-wake-arm.sh:60-77` already applies for exactly this reason ("a sidechain/subagent session legitimately has neither id — waking each one would burn a turn per spawn").
- **Sizing:** −18 daemons, −34 MB, −180 forks/min · effort **S** (one conditional + one test) · risk **low** (strictly fewer daemons; a subagent crash is already handled by the parent session's own turn).
- **Existing mechanism:** `hooks/lead-crash-watchdog.sh` — **EXTEND**, and reuse `hooks/lib/agent-identity.sh` (already knows an assignee pane has no registry row, `:32`).

### C2 — The event-driven death primitive is built, tested, and the watchdog does not use it
- **Finding:** `bin/cc-deathwatch-kqueue` arms kqueue `EVFILT_PROC`/`NOTE_EXIT` per {pid, start-time} and streams a DEATH line "the INSTANT that process exits — an event, not a poll (verified: fires at child-exit within ~1 ms)" (`:1-13`). `lead-crash-watchdog.sh` re-implements the *same* {pid, lstart} identity by hand inside a `sleep 30` loop (`:875-896`, `:941`).
- **Evidence:** `bin/cc-deathwatch-kqueue:1-23` (the helper) · `scripts/wait-safety-gate.sh:48,78-79` (its L1 selftest gate: "real kqueue exit + SIGKILL-helper→alarm") · `scripts/never-stuck-gate.sh:103,126` (registered tool) · **zero call sites in `hooks/`** (`grep -rn cc-deathwatch-kqueue hooks/` → 0).
- **Cost now:** 28 daemons × 5 forks/30 s = **280 forks/min** and up-to-30 s detection latency, to answer a question the kernel will answer in 1 ms with zero wakeups.
- **Re-architecture:** ONE kqueue watcher process for the whole box, fed a registration line per session (`pid TAB start TAB label TAB waiter` — the helper's existing stdin contract), emitting DEATH to the existing `handle_crash` path. 34 pollers → **1 event source**.
- **Sizing:** −27 processes, −51 MB, −280 forks/min, detection 30 s → ~1 ms · effort **M** (the crash handler stays untouched; only the *trigger* moves) · risk **medium** — a single watcher is a SPOF, so it needs the heartbeat + own-death alarm that `scripts/lead-deathwatch.sh` already carries and `wait-safety-gate.sh:78` already tests.
- **Existing mechanism:** `bin/cc-deathwatch-kqueue` + `scripts/lead-deathwatch.sh` — **WIRE UP, do not rebuild.**

### C3 — The wake-path arming hook exists and is not registered, so half the fleet polls at 15 s
- **Finding:** `hooks/mailbox-wake-arm.sh` is a complete `asyncRewake` arming hook (runs `cc-await-ping`, exits 2 on mail = the harness wake, `:107-118`). It appears **nowhere in `~/.claude/settings.json`**. So the wake path is armed *by the agent typing a background Bash call*, prompted by `hooks/session-continue.sh:426` and `hooks/mailbox-drain.sh:259-261` — which is why only **8 of 16** sessions have one.
- **Evidence:** `grep -rn "mailbox-wake-arm" ~/.claude/settings.json` → 0 hits. Live: 8 `cc-await-ping` (command-position anchored; a naive `pgrep -f` reads 16 because the `zsh -c` wrapper argv quotes the name). `GROUND_UP_REBUILD_MAP.md:19` confirms: "arming is **STAGED, not live**: [migration] 0006 is c10 and waits for the operator."
- **Cost now:** two defects at once — 8 sessions burn **256 forks/min** on a 15 s poll, and **8 sessions are deaf while idle** (peer mail sits until someone types at them). Note `mailbox-drain.sh` already runs at PostToolUse/SessionStart/UserPromptSubmit (`settings.json:615,711,877`), so the 15 s poll only covers the **idle** window — the exact window an `asyncRewake` hook is for.
- **Re-architecture:** register the built hook (operator C10 step, already platter-ready), then replace `cc-await-ping`'s `sleep 15` inner loop with kqueue `EVFILT_VNODE` on the inbox keys — or better, have `bin/cc-notify` push on write, since the writer already knows the key. Fallback poll stays as a backstop at a much longer interval.
- **Sizing:** −256 forks/min, −32 MB, idle-wake latency 15 s → ~1 ms, and **coverage 8/16 → 16/16** · effort **S** for the registration (it is a queued activation), **M** for the kqueue conversion · risk **low** (dup-biased by design: `cc-await-ping:459-461` — "a duplicate wake is cheap, a lost wake is a 4-hour hang").
- **Existing mechanism:** `hooks/mailbox-wake-arm.sh` + c10 migration 0006 — **ACTIVATE**, not build.

### C4 — The statusline is the largest session poller, and it is the one that scales
- **Finding (CENSUS ONLY — levers are axis G's):** command = `~/.claude/statusline.sh`, one per session, invoked by CC per TUI redraw. Measured fleet rate **0.9 renders/s** across 16 live sessions (60 s sample, inode-change counting on `/tmp/cc-telemetry/*.json`, which `statusline.sh:86-144` writes on **every** render with no damper). Single active session: **0.091 renders/s**. Cost per render: **87 ms wall / 60 ms CPU** (5 warm runs) and **8 external forks** (`cat`, `jq`×3, `git rev-parse`, `git status --porcelain=v2`, `mv`, `basename`) plus a `ps` ancestry walk that is memoized per session (`:120-128`).
- **Evidence:** measured, this session. Method note for the lead: the telemetry `.json` is written atomically (tmp+rename) so inode-change counting catches every render; 1 s sampling makes 0.9/s a **lower bound**.
- **Cost now:** **5.4% of one core continuously, 432 forks/min**, both O(N sessions) — ~10× everything else on this axis combined.
- **Re-architecture:** not mine to design. Handing G the numbers: the dominant term is `git status --porcelain=v2` in a 115-worktree checkout; the script already collapsed 4 git calls → 2 and 8 jq → 1 (`:44-52`, `:155-172`).
- **Sizing:** for G — halving per-render cost recovers ~2.7% of a core at 16 sessions, ~5% at 30.
- **Existing mechanism:** `~/.claude/statusline.sh`; identity guarded by `tests/statusline-identity.bats`.

### C5 — `sleep(1)` processes are the visible tax of shell polling
- **Finding:** 29–45 live `sleep` processes at any instant, one per in-flight poll tick, each a real fork+exec of `/bin/sleep`.
- **Evidence:** `ps` snapshots — 29 then 43 then 45 `sleep` procs; intervals attributable by parent: 30 s → watchdogs, 15 s → `cc-await-ping`, 10 s → `compressor-sentinel` (axis B), 20 s/45 s → launchd jobs, 5 s → `mem-leash.sh`. Physical footprint **961 K** each.
- **Cost now:** ~43 KB×961 ≈ **41 MB** of transient `sleep` processes and ~16 forks/s, purely as the *representation* of "wait".
- **Re-architecture:** every one of these disappears with C2 + C3 — it is a symptom, not an independent item. (Where a shell must genuinely wait, `read -t` on a fd costs zero forks.)
- **Sizing:** folded into C2/C3 · effort n/a · risk n/a.
- **Existing mechanism:** n/a.

### C6 — Every MCP server carries a dead `npm exec` shim (handed to axis G)
- **Finding:** each `chrome-devtools-mcp` is a **2-process chain**: `npm exec chrome-devtools-mcp@latest --isolated` (~46 MB) → `chrome-devtools-mcp` (~48 MB, one at **1.63 GB**).
- **Evidence:** 4 pairs live: pids 88728→95531, 136→7993 (1.63 GB), 59185→69893, 74513→84462.
- **Cost now:** **~184 MB of `npm exec` wrappers doing nothing but holding a child** — larger than the entire shell-poller population.
- **Re-architecture:** axis G's (pin the version and invoke the resolved binary directly, dropping the npm shim).
- **Sizing:** ~46 MB per MCP-enabled session · effort S · risk low.
- **Existing mechanism:** MCP server config — **census only, handed over.**

---

## 5. Adversarial self-pass

Three things a hostile reviewer would say I got wrong — investigated, not assumed:

**(a) "You'll call the ppid=1 watchdogs orphans. That's already been falsified."** Correct, and I do
not. `GROUND_UP_REBUILD_MAP.md:528-530` records the exact trap: "`ppid=1` is deliberate (`disown`,
`lead-crash-watchdog.sh:816`); 33 watchdogs for 33 sessions". I re-measured independently: **36
pidfiles, 36 naming a LIVE claude/claude.exe pid, 0 dead or recycled.** `cc-reaper watchdog-census`
(read-only, both its controls OK) agrees: `tracked-orphan=0 UNTRACKED-orphan=0`. The immortality
wedge that produced 63 daemons in July is **fixed and stays fixed** — the {pid, lstart} pin at
`:875-896` works. C1 is a different claim entirely: not *orphaned*, **inapplicable**.

**(b) "Prior art already exonerated memory. Your axis has no memory finding."** Largely true and I
lead with it. `MACHINE_CAPACITY_V2.md` §8.5.7 measured RSS flat with age and load independent of
session count; my snapshot corroborates (85% memory free, 816/10666 user procs). The honest
re-framing: this axis' recoverable RAM is **~85 MB** (C1 34 MB + C2 51 MB), i.e. **0.13% of 64 GB** —
which will not lift a 15-session ceiling *by itself*. Its real deliverables are **−716 forks/min,
−27 processes, 30 s→1 ms detection, and 8/16→16/16 idle-wake coverage**, plus the measured statusline
number axis G needs. Anyone selling axis C as GB is mis-selling it.

**(c) "Did you check for pollers that aren't shell?"** Yes — that was the gap I nearly missed.
Swept `chrome-devtools-mcp`/node (→ C6), `python.*poll`, `tail -f`, `fswatch`, `watchman` (none), and
`gitstatusd` (12 live, 61 MB, per-pane — request/response, not a timer; handed to axis H). I also
verified `cc-pane-runner`'s 50 ms loop is **bounded and correct** and must NOT be "optimised": its own
comment (`:186-191`) rejects a FIFO with a stated reason — a FIFO would make open() ordering
load-bearing between two unsynchronised parents and could hang Claude Code's spawn call. Naively
converting it to an event primitive would re-introduce that hang. Likewise `cc-close-attrib`'s
`while :; do wait; done` **looks** like a poll and is a blocking wait (`:227-234`); a reviewer
skimming for `while :` would file it wrongly.

**One measurement I could not make:** a machine-wide fork-rate baseline. Both samples (809/s, 1339/s)
were dominated by `postland-verify`'s /Users/chrisren/.claude/bin/cc-bats suite under a 3 h budget. My 975 forks/min for pollers is
computed from measured cardinalities × measured intervals × counted loop-body forks — sound, but not
cross-checked against an independent total.

---

## 6. Ranked, for the lead

| # | Item | Effort | Recovers | Why it ranks here |
|---|---|---|---|---|
| 1 | **C3 activate `mailbox-wake-arm.sh`** | S (queued C10 activation) | 256 forks/min + fixes an 8/16 correctness hole | Already built, already staged; the *correctness* half (deaf idle sessions) outweighs the forks |
| 2 | **C1 subagent guard on the watchdog** | S | 18 procs, 34 MB, 180 forks/min | One conditional; the only pure-waste finding on this axis; scales with wave width |
| 3 | **C4 statusline** (axis G executes) | — | up to ~2.7% of a core at 16 sessions | Biggest measured CPU term and the only one that scales with N |
| 4 | **C2 kqueue deathwatch** | M | 27 procs, 51 MB, 280 forks/min, 30 s→1 ms | Highest raw win but introduces a SPOF; needs the heartbeat/own-death alarm `lead-deathwatch.sh` already has |
| 5 | **C6 drop the `npm exec` MCP shim** (axis G) | S | ~46 MB/session | Bigger RAM number than everything else here, and it is not mine |

**Do not touch:** `cc-pane-runner` (bounded, and the FIFO alternative is a documented hang) ·
`cc-close-attrib` (not a poller) · `caffeinate -t 300` (vendor-owned).

---

# ADDENDUM — 2026-08-10, after lead's steer: prior wave already closed this axis

Steer received: `docs/research/scaling-bottlenecks-2026-08-09.md` + `docs/plans/CONCURRENCY_PROGRAM.md`
§S6.3-MEASURED (:1301-1344) and §2 (:1695-1709) closed Phase A 14 h ago — idle sessions measured
**0.0031 runnable threads** (6× under the 0.02 target), box-wide consolidation **DECLINED as the wrong
trade**, and the indicting census shown to be **argv contamination**. This addendum reports **deltas
only**. Everything above the line that re-proposes consolidation (C2, and C1/C5's sizing) is
**superseded by that prior work** — see §A3, where I retract my own C1 sizing.

## A1 · Do the prior figures still hold? (command-position anchors only)

| Quantity | Prior wave 2026-08-09 | Today 2026-08-10 | Verdict |
|---|---|---|---|
| `cc-reconcile` (command position) | **0** | **0** | ✅ holds exactly |
| `cc-reaper` (command position) | **0** | **2** | ✅ holds — both `ppid 1`, `bin/cc-reaper sweep --reap` mid-sweep from the box-wide `com.chrisren.cc-reaper` (`StartInterval 300`). A sweep in flight, not a per-session poller |
| `cc-await-ping` (command position) | **1** | **9–10** | ⚠️ **DELTA — 9×. The one number that moved.** See A2 |
| `lead-crash-watchdog` (1:1 w/ sessions) | 1:1 | 17–28 daemons, **36 pidfiles, 36 naming a live pid, 0 dead/recycled** | ✅ holds; the July immortality wedge stays fixed |
| per-session poller population = **two** | two | **two** — confirmed independently | ✅ holds (see A4 for what is *not* a poller) |
| `claude` sessions | 15 | **15** `claude` + 18 `claude.exe` | ✅ same lead count |

**The contamination reproduces exactly**, on the same box, one day later:

| Process | `pgrep -f` (contaminated) | command position | ratio |
|---|---|---|---|
| `cc-await-ping` | **23** | **9** | 2.6× |
| `cc-reaper` | **7** | **2** | 3.5× |
| `cc-reconcile` | **5** | **0** | ∞ |

⚠️ **This report is now itself a contamination source.** It names all three strings, so every session
that reads it inflates the naive count by one per pane — the exact self-reinforcing loop
`CONCURRENCY_PROGRAM.md:1699-1709` documents ("the plan became the source of the evidence for its own
largest wave"). Any future census must use command position; `pgrep -f` is not usable on this box.

## A2 · The one real delta: armed watchers went 1 → 9, and it makes the cheap lever WORTH LESS

Prior measured **1** armed `cc-await-ping` at 12–19 sessions, while its own model said "a steady-state
resident carries one" (`:1344`). Today: **9–10 at 15 sessions = 0.65/session** — closer to the model
than the day the model was written. Re-pricing the lever with today's ratio:

```
prior pricing:  150 sessions × 1.0 watcher × (0.00216 − 0.00054) = 0.24 of 20   (1.2% of budget)
today's ratio:  150 sessions × 0.65 watcher × (0.00216 − 0.00054) = 0.157 of 20 (0.8% of budget)
```

**The lever is worth ~35% LESS than the prior wave priced it, not more.** Its "report it, do not take
it — a responsiveness call, not a capacity fix" verdict is **strengthened by the delta, not weakened.**

## A3 · Retraction of my own §4 sizing (C1/C2/C5)

The prior wave's per-term occupancy numbers reprice everything I wrote above, and I was pricing the
wrong currency (MB and forks/min, where the budget is runnable threads):

| My item | What I claimed | Priced against `lead-crash-watchdog` = **0.00024 runnable threads** (prior, 200-iteration loop-body timing) |
|---|---|---|
| **C1** subagent guard (−18 daemons) | 34 MB + 180 forks/min | **0.0043 runnable threads = 0.02% of the 20-unit budget.** Real, correct, and worth **nothing** on capacity. **Re-file as tidiness, not scaling.** |
| **C2** kqueue deathwatch (−27 daemons) | 51 MB + 280 forks/min | **0.0065 runnable = 0.03% of budget**, against a SPOF over the crash path. **Withdrawn** — this is the same negative-EV trade §S6.3-MEASURED declined, arrived at independently. |
| **C5** `sleep` process tax | 41 MB | symptom of C1/C2 — **withdrawn with them** |

C3 (activate `mailbox-wake-arm.sh`) and C4 (statusline census → axis G) stand: C3 is a **correctness**
item (8 of 15 sessions deaf while idle), not a capacity one, and C4 is a census hand-off.

## A4 · What the prior wave did NOT census — and what it is worth

Its subject was *processes*. Nothing has censused the **artifacts** the watcher population leaves.

**FINDING (new): 152 `.watching` heartbeat markers in `~/.claude/mailbox/`; 132 stale, 128 with a DEAD
owner pid; oldest 11 days; 25 stamped after the wave.**

- **Evidence:** per-marker `stat -f %m` + `kill -0` on the embedded `pid=` field. Ages span 1007 s to
  957,303 s. Live/fresh: **20**.
- **Mechanism, already documented and unreaped:** `cc-await-ping` removes its own marker in the EXIT
  trap (`bin/cc-await-ping:224`), so a **SIGKILL or pane teardown strands it** — stated verbatim at
  `hooks/session-continue.sh:244` and `bin/cc-await-ping:327`. Nothing reaps the residue.
- **Is it harmful? NO — and I checked rather than assumed.** All three readers gate on
  `age ≤ CC_WATCH_FRESH_S (90)`: `hooks/lib/mailbox-pending.sh:263`, `bin/cc-notify:943`,
  `bin/cc-await-ping:190` (which *also* requires `kill -0`). Every stale marker is ≥1007 s old, so
  **all 132 are structurally inert — no false "wake path armed" verdict is reachable.** Cost is 152
  inodes and 152 `stat`s per dir glob. **Not worth fixing on capacity grounds** — the same verdict,
  for the same reason, as the wave's own.
- **The one thing it IS worth:** a free, durable instrument nothing currently reads. **128 dead-owner
  markers = 128 watchers that died without running their EXIT trap over 11 days** — a direct measure
  of teardown hygiene (SIGKILL vs graceful). If teardown regressions matter to any other axis, this
  counter already exists on disk and costs one `ls | wc -l`.

**Also not pollers** (checked, so no one re-files them as such): `cc-pane-runner` bounded 50 ms then
`exec`s and its comment rejects a FIFO because open() ordering would hang CC's spawn call
(`:186-191`) · `cc-close-attrib`'s `while :; do wait; done` is a **blocking wait**, the loop exists
only because a trapped signal makes `wait` return early (`:227-234`) · `caffeinate -i -t 300` is
spawned by the **CC binary** (no in-repo site) · `gitstatusd` is request/response, not a timer.

## A5 · The 15 s → 60 s lever: CONFIRMED SAFE, by a measurement the prior wave did not make

The prior wave stated the bound (`CC_WATCH_FRESH_S=90`, stale at 120 s) but never measured how much of
that 90 s window the beat cadence actually consumes. **That is the gap, and it is now closed.**

**Measured on a live 15 s watcher (pid 87601, 100 s sample, `stat -f %m` on its `.watching` at 0.5 Hz):
6 beats, inter-beat period 15.0 s, 15.0 s, 15.0 s, 15.0 s, 15.0 s, 15.0 s — mean 15.00 s, ZERO jitter.**

`_beat()` runs once per loop iteration *before* the sleep (`bin/cc-await-ping:197-205`, called at
`:501`; sleep at `:556`), so **beat period = INTERVAL + tick_work**, and the measurement puts
`tick_work` below the 1 s mtime resolution.

| INTERVAL | beat period | max marker age | window | margin | verdict |
|---|---|---|---|---|---|
| 15 s (today) | 15.0 s | ~15 s | 90 s | 75 s | current |
| **60 s (the lever)** | **~60.0 s** | **~60 s** | 90 s | **30 s (50% headroom)** | ✅ **SAFE** |
| 75 s | ~75 s | ~75 s | 90 s | 15 s | thin |
| 90 s | ~90 s | ~90 s | 90 s | **0** | ⛔ boundary — `-le 90` flips on one second |
| 120 s | ~120 s | ~120 s | 90 s | −30 s | ⛔ the wave's stated failure |

**The failure mode is a cliff, not a gradient** — the readers' test is `[ $((now-mt)) -le 90 ]`, so it is
TRUE at exactly 90 and FALSE at 91. The true ceiling is `INTERVAL < 90 − tick_work`; **60 s is the
largest value that leaves a sane margin**, which is why the prior wave's number is the right one.

**Single-seam confirmed.** All three readers share one constant — `CC_WATCH_FRESH_S:-90` at
`hooks/lib/mailbox-pending.sh:263`, `bin/cc-notify:936,943`, `bin/cc-await-ping:190`. **No reader
carries a shorter hardcoded window** (grepped). So the interval change cannot desynchronise one
consumer from another.

**Where the change lands (4 sites, 3 of them hardcoded):**

| Site | Today | Note |
|---|---|---|
| `hooks/session-continue.sh:426` | `--interval 15` hardcoded | the Stop-blocking wake floor's own nudge text |
| `hooks/mailbox-drain.sh:259` | `--interval 15` hardcoded | drain re-arm nudge |
| `bin/cc-await-ping:280` | `--interval 15` hardcoded | the re-arm instruction the watcher prints on timeout |
| `hooks/mailbox-wake-arm.sh:99` | `${CC_WAKE_ARM_INTERVAL:-15}` — **already a seam** | but the hook is **unregistered** in `settings.json` (my C3) |
| `bin/cc-await-ping:54` | `INTERVAL=15` default | the actual default |

Clean shape: one `CC_WAKE_INTERVAL_S:-60` seam read by all five, so the arming nudges and the binary's
default cannot drift. **Cost of the change:** peer-mail wake latency ≤15 s → ≤60 s. **Benefit:** 0.157
of 20 at 150 sessions (A2). That is a responsiveness product call, exactly as the prior wave framed it
— and today's re-pricing makes the payoff *smaller*, so nothing about the delta argues for firing it.

## A6 · Bottom line for the lead

1. **Nothing in the prior wave has decayed.** Two per-session pollers, contamination reproduces, no
   orphaned watchdogs, sweepers remain single box-wide launchd jobs.
2. **The single delta (armed watchers 1 → 9) makes the cheap lever cheaper to skip, not likelier to
   fire** — 0.24 → 0.157 of 20.
3. **The 60 s lever is now measured-safe, not just arithmetic-safe** (beat period exactly = INTERVAL,
   zero jitter ⇒ 30 s margin at 60 s; a cliff at 90 s). If the responsiveness call is ever made, it is
   a one-seam change across five sites and it will not desynchronise the three readers.
4. **One new leak found, and it does not matter:** 128 stranded `.watching` markers, all structurally
   inert behind the 90 s freshness gate. Worth ONE line as a free teardown-hygiene counter, nothing more.
5. **I retract my own C1/C2/C5 sizing** — priced in MB and forks/min, they are 0.02–0.03% of a budget
   that is 2% consumed. C3 (registration, a correctness fix) and C4 (statusline census → G) stand.
