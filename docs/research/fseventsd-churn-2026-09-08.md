# fseventsd saturation, 2026-09-08 — the mechanism is a LIVELOCK, not client churn

**Verdict (conviction 96%):** `fseventsd` (pid 610) is **livelocked** — one thread spinning in
user space at ~98% of a core, delivering **zero** FSEvents to anybody. The `fsevent_add_client`
churn from the Claude fleet is a **co-occurring symptom, not the cost**, and no change to Claude
Code's watcher behaviour can clear it. The remedy is to restart the daemon, which is root-gated.

The brief that commissioned this work asked to "cut the registration rate". That would not have
worked, and this document exists to say why before anyone spends a change on it.

---

## 1. Two corrections to the incident's premise

### 1.1 The saturation is at most ~25 hours old, NOT 13 days (conviction 95%)

The original report read "fseventsd at 100% of a core for 13 days". That inference came from
`ps -o %cpu`, which on macOS is a **decaying recent average, not a lifetime average**. The 13-14
days is the process AGE (`etime` = `14-06:56:44`), not the duration of the fault.

The arithmetic refutes the long-duration reading outright:

| quantity | measured |
|---|---|
| `etime` (process age) | 14 d 06:56 = **~336 h** |
| accumulated CPU time | 101,678 s = **~28.2 h** |
| implied lifetime average | **8.4%** |
| current rate (measured, below) | **~110%** |

If the daemon had truly run at 100% for 13 days it would carry ~312 h of CPU time. It carries
28.2 h. At the current ~110%, the pinned period **cannot exceed ~25 h**. That is a hard bound, and
it matters: it means something changed *recently*, and it puts the fault inside the same window as
the 2026-09-07 CwdChanged/FileChanged wiring rather than 13 days before it.

### 1.2 Registrations are a symptom and could never have been the cost (conviction 97%)

Measured baseline: **188 `fsevent_add_client` lines per hour**. That is **0.052 per second**. Even
at an implausibly expensive 10 ms per registration this is 0.05% of a core. A registration rate
three orders of magnitude below the observed cost cannot be the cost. Any fix aimed at the
registration rate was aimed at the wrong term.

---

## 2. What the daemon is actually doing

### 2.1 One thread, spinning, in user space (conviction 96%)

`ps -M 610`, three samples 40 s apart:

| sample | main-thread %CPU | STAT | main-thread UTIME | Δ UTIME / 40 s |
|---|---|---|---|---|
| 09:49:38 | 100.0 | **R** | 1390:13.76 | — |
| 09:50:18 | 98.4 | **R** | 1390:52.96 | **39.20 s** |
| 09:50:58 | 98.2 | **R** | 1391:32.21 | **39.25 s** |

Two facts decide this:

- **Every other thread is idle.** Sum of non-main `%CPU` = **0** in all three samples; their
  UTIME values are frozen across the whole window.
- **The work is almost entirely user-space.** Over the same 40 s windows STIME grew ~0.27 s
  against UTIME's 39.2 s — a **145:1 user:system ratio**.

Event fan-out is syscall-dominated: delivering events to N clients means N mach messages. A
145:1 user:system ratio with a single pinned thread is not fan-out. It is a computation loop.

### 2.2 It is delivering nothing (conviction 97%)

Functional test — `fs.watch(dir, {recursive:true})` under bun (the same runtime Claude Code
embeds), then create a file in that directory and measure delivery latency:

| trial | FSEvents path (`fs.watch`) |
|---|---|
| 1 | **TIMEOUT at 30,000 ms** |
| 2 | **TIMEOUT at 30,000 ms** |
| 3 | **TIMEOUT at 30,000 ms** |

**Positive control on the same directory and the same writes**, using `fs.watchFile` (stat
polling, which does not touch FSEvents):

| trial | polling path (`fs.watchFile`) |
|---|---|
| 1 | delivered in **104 ms** |
| 2 | delivered in **110 ms** |

The control is what makes this admissible: the directory, the writes and the harness are all
fine. The fault is isolated to the FSEvents delivery path specifically. `fseventsd` is burning a
core and delivering nothing — the definition of a livelock.

This independently reproduces the machine-wide symptom that opened the incident (Hammerspoon
losing 5 of 13 screenshots; a `touch` undelivered after 40 s; a launchd `WatchPaths` agent not
firing in 20 s). Those consumers are not misconfigured. They are downstream of a dead daemon.

---

## 3. Who registers, and why it looked like the cause

Baseline census, last clean hour: **188 registrations**, every one of the form
`fsevent_add_client: no bundle id available for pid N`, and every pid a Claude Code process.

| pid | registrations/h | status |
|---|---|---|
| 50418 | 62 | **live** interactive session, up 1h25m |
| 29554 | 33 | **live**, up 10h51m |
| 89153 | 22 | **live**, up 55m |
| 66848 | 15 | live |
| 61423 | 12 | live |
| 37077 | 10 | short-lived, gone |
| tail | 1-5 each | mixed |

The top registrants are **live long-running sessions re-registering ~1/minute**, not short-lived
spawns as first supposed.

### 3.1 The registration mechanism (conviction 92%)

The installed binary is a **Bun-compiled single-file Mach-O** (198 MB;`BUN_WATCHER_TRACE` present)
that bundles **chokidar v4**. In Bun on macOS, every `fs.watch()` creates one FSEvents client;
`fs.watchFile()` (polling) creates none.

Nine chokidar `.watch()` call sites exist in the build. Five already pass `usePolling:!0` (or
`usePolling: platform==="macos"`), so they cost nothing. **Four do not**, and those are the
FSEvents clients: `FileChanged`, the settings/atomic-save watcher, `theme`, and `ScheduledTasks`.

Measured A/B on the real binary, one `claude -p` run per arm, registrations attributed by pid:

| arm | env | registrations |
|---|---|---|
| A (control) | native | **3** |
| B | `CHOKIDAR_USEPOLLING=1 CHOKIDAR_INTERVAL=2000` | **1** |

So the lever is real in direction (and `settings.json`'s `env` block was verified to reach the
Claude Code process itself, not just hooks — all 8 existing keys were readable from a live
session's own environment). It is simply aimed at a term that does not matter here.

### 3.2 FileChanged is already inert (conviction 90%)

Both configured matchers resolve to paths that do not exist —
`/Users/chrisren/.claude/file-watch-paths` (absent) and `*`, which chokidar 4 does not treat as a
glob and which becomes the literal path `<cwd>/*`. So FileChanged currently watches nothing. This
is worth recording because it removes the one functional argument for flipping the fleet to
polling: there is no working behaviour to restore.

---

## 4. Why the obvious fix was NOT landed

The candidate change was `CHOKIDAR_USEPOLLING=1` + `CHOKIDAR_INTERVAL=2000` in the `env` block of
`~/.claude/settings.json`. It is measured, reversible, and cheap. It was deliberately **not**
landed, on three grounds:

1. **It cannot fix the incident.** The daemon is livelocked. Removing clients from a spinning
   daemon does not stop it spinning (conviction 93%).
2. **It restores nothing.** FileChanged already watches no paths (§3.2).
3. **It only reaches new sessions.** `env` is read at process start, so the 247 live sessions keep
   their native watchers until they recycle. The acceptance criterion of "CPU below 30 within ten
   minutes" is unreachable by this change *by construction*.

It carries a real if small downside — a fleet-wide watcher-behaviour change whose polling cost is
unbounded if a broad `FileChanged` matcher is ever added (that watcher passes no `depth`). Landing
a change with a known downside, no measured upside against the actual fault, and a causal story
sitting at ~35% conviction would be scope-metastasis. It is carried into the decision packet as a
costed option instead.

---

## 5. What actually clears it — and why it is the operator's

`fseventsd` is a **system-domain LaunchDaemon** running as root:

```
system/com.apple.fseventsd = { state = running
  path = /System/Library/LaunchDaemons/com.apple.fseventsd.plist
  type = LaunchDaemon }
```

The session is uid 501 and sudo is a hard constraint of this work, so the remedy is not reachable
from here (conviction 93% that no non-root path exists). Restarting it is also not a free action —
it can provoke Spotlight/Time Machine rescan work — which makes it a genuine blast-radius decision
rather than a step to fire silently.

---

## 6. Standing exposure this uncovered (not fixed here)

- **~87,000 file modifications/hour (~24/s sustained)**, of which ~95% of the hottest root is this
  repo's own `postland-verify` harness (~40,600 `bats-run-*` + ~11,000 `gate-home.*` + ~10,900
  `postland-run.*` files/hr). Harmless while FSEvents is dead; it becomes the fan-out multiplicand
  the moment the daemon is healthy again.
- `postland-verify.sh:112` does a `git worktree add` of a 2,704-file checkout **into `~/.claude`**,
  which is itself a watched settings tree — 86% of that directory's writes.
- **Headless `claude -p` spawns SIGTERM peers' `cc-await-ping` watchers.** Observed twice during
  this session's controlled A/B: each `-p` run killed the watcher armed for session 574, because
  the reaper matches on `pgrep -f` against argv. Benign here (classified `B-BENIGN`, recycle
  teardown) but it is a real cross-session side effect of any headless spawn.

## 7. Instrument notes for whoever repeats this

- **`log` is shadowed by a zsh builtin** in this harness. `log show ...` returns
  `(eval):log:1: too many arguments` and a bare pipe to `wc -l` renders that as a clean **0** —
  i.e. a silent false "no churn". Always use **`/usr/bin/log`**.
- `grep` here is **ugrep**; `.{0,300}` style patterns hit complexity/repetition limits. Use
  `LC_ALL=C /usr/bin/grep` with windows ≤ 250 for binary spelunking.
- `ps -o %cpu` is a decaying recent average (§1.1). To get an instantaneous rate, difference
  `ps -o time=` across a known interval.
- `lsof -p <claude-pid>` showing no CoreServices and no `/dev/fsevents` fd is **not** evidence
  against FSEvents use — system frameworks live in the dyld shared cache and FSEvents clients talk
  to the daemon over mach, not a device fd.
