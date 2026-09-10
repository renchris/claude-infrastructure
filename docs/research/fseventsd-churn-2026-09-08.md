# fseventsd saturation, 2026-09-08 — the mechanism is a LIVELOCK, not client churn

**Verdict (conviction 96%):** `fseventsd` (pid 610) is **livelocked** — one thread spinning in
user space at ~98% of a core, delivering **zero** FSEvents to anybody. The `fsevent_add_client`
churn from the Claude fleet is a **co-occurring symptom, not the cost**, and no change to Claude
Code's watcher behaviour can clear it. The remedy is to restart the daemon, which is root-gated.

The brief that commissioned this work asked to "cut the registration rate". That would not have
worked, and this document exists to say why before anyone spends a change on it.

> **STATUS 2026-09-10 — CURED AND VERIFIED.** The §5 remedy was applied 2026-09-08 15:49:38;
> `fseventsd` now runs at 2.5-4.3% with FSEvents delivery at a median of 8 ms. The row that
> commissioned this (`ae75073ef319`) is closed. See **§8**, which also refutes §6's prediction
> under control. No change to Claude Code's watcher behaviour was made, or is warranted.

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
  the moment the daemon is healthy again. — **REFUTED 2026-09-10 (§8.2):** the daemon is healthy,
  the churn re-measured *higher* at 40.1 files/s, and `fseventsd` costs 4.34% of a core. The
  prediction is kept as the record of what was believed; it is not an open exposure.
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

---

## 8. Post-cure verification, 2026-09-10 (backlog `ae75073ef319`)

The remedy of §5 was applied: `fseventsd` pid 610 was terminated and launchd respawned it as
**pid 10437 at 2026-09-08 15:49:38** — 108 s before hammerspoon-config `e2220ac` recorded it.
This section verifies the cure held, **~46 h later, on a busy box**, and closes the row.

### 8.1 The cure held

| quantity | during the fault (§2) | now (2026-09-10 13:37-13:45) |
|---|---|---|
| `fseventsd` CPU | ~110% of a core | **4.34% mean, 10.2% peak** (30 × 4 s samples); **2.50%** on an independent 40 s re-sample |
| FSEvents delivery (`fs.watch` recursive) | **TIMEOUT at 30,000 ms**, 3/3 | **median 8 ms, max 14 ms**, 30/30 delivered |

Latency was measured on **both** `/private/tmp` and a path under `$HOME` — confirmed the same
volume (`/dev/disk3s5`), since FSEvents streams are per-volume and a one-volume probe would not
generalise. Ambient conditions during the reading: **load 13.89**, **39 live `claude` processes**,
and `postland-verify.sh` mid-run with a large `bats` suite.

No drift toward the fault: the process's **lifetime** average is 9.85% (270:56 CPU over 45.9 h)
against a **current** 2.5-4.3%, i.e. front-loaded by the expected post-restart rescan, not rising.

### 8.2 §6's multiplicand did not materialise — measured, not assumed

§6 predicted the fleet's file churn "becomes the fan-out multiplicand the moment the daemon is
healthy again". The daemon is healthy and **the prediction is refuted under control**: churn was
re-measured at **40.1 files/s** (12,039 files in 300 s across the repo, `TMPDIR` and `~/.claude`)
— **167% of the ~24/s** that prompted the worry — with `fseventsd` costing 4.34% of a core at the
same moment. The churn is real; it is simply not expensive to fan out. This is the positive
control that makes §8.1 a reading about the daemon rather than about a quiet box.

`postland-verify.sh` still mints its per-run cell inside `~/.claude` (`WT_ROOT` defaults to
`$STATE` = `~/.claude/autonomy/postland`), so the structural condition §6 named is unchanged. That
is now a recorded non-problem rather than an open exposure.

### 8.3 The decision the row asked for: ACCEPT, do not cut the spawn rate

Both premises of the row's framing are refuted, and §3 already refuted the third:

- **Not a cost.** Registrations are ~3 orders of magnitude below a core (§1.2).
- **Not headless.** Only **2 of 39** live `claude` processes were `-p`. The top registrant was a
  **28-minute-old interactive session** emitting 41 of the hour's 127 events, in bursts of 3-4
  every 1-2 minutes — per-turn re-registration by long-lived sessions, not spawn churn.
- **Rate is not rising.** 127 registrations/h now against the 188/h of §3 and the ~250/h of the
  original report.

The registering code path stands as recorded in §3.1 (Bun-bundled chokidar v4; of nine `.watch()`
sites, four do not pass `usePolling` — `FileChanged`, the settings/atomic-save watcher, `theme`,
`ScheduledTasks`). No change is warranted, for the reasons §4 already gives.

### 8.4 A recurrence detector was considered and declined — with the criterion to revisit

Nothing on this box monitors `fseventsd` health, and the fault was invisible for ~25 h until a
*screenshot* investigation stumbled on it. That argues for a detector. It was not built, on two
grounds: the payoff is **unmeasured** (n=1, an external daemon bug, no recurrence in the 46 h
since), and the remedy is root-gated (§5), so a detector could only page rather than act.

Recording the criterion rather than the verdict, because the verdict perishes: **build it on a
second occurrence, or if a sample ever shows sustained CPU with no delivery.** Both terms in one
command — a healthy daemon answers with a low percentage and a small latency, a livelocked one
with a high percentage and a timeout:

```sh
F=$(pgrep -x fseventsd); a=$(ps -o time= -p $F); sleep 10; b=$(ps -o time= -p $F)
echo "cpu: $a -> $b"   # >90%/s sustained + a TIMEOUT below ⇒ livelock, see §5
node -e 'const fs=require("fs"),o=require("os"),p=require("path"),d=fs.mkdtempSync(p.join(o.tmpdir(),"fsev"));
const t=Date.now(),w=fs.watch(d,{recursive:true},()=>{console.log("delivered in",Date.now()-t,"ms");process.exit(0)});
setTimeout(()=>fs.writeFileSync(p.join(d,"x"),"x"),300); setTimeout(()=>{console.log("TIMEOUT");process.exit(1)},15000)'
```

### 8.5 Instrument note that cost this session a false "cured"

§7's first bullet reproduced exactly, and it is worth stating as the failure it produces rather
than as a caveat: the row's own stored `run` field invokes `log show ...`. `log` is a **zsh
builtin/function** in this harness, so the command returns `(eval):log:1: too many arguments`, and
the row's `| grep -oE 'pid [0-9]+' | sort | uniq -c` renders that as **zero registrations** — a
clean, tidy, entirely false "the churn has stopped". A positive control (`log show --last 5m` with
no predicate, which also returned 0) is what exposed it. Use `/usr/bin/log`.

The same class bit a second time in the same session: `find` is a shell function resolving to
**bfs**, whose `-newermt '-10 minutes'` is a parse error, not a predicate — piped through
`2>/dev/null | wc -l` it also renders as a clean **0 files changed**. Use `-mmin -N`, or
`/usr/bin/find`, and never suppress stderr on a null you intend to believe.
