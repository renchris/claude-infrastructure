# Axis B — Scheduled compute (launchd) · full inventory + redesign
Measured 2026-08-10 00:30–00:45 PDT. Boot = Sun 2026-08-09 04:18:26 PDT; **uptime 20.4 h** at
measurement. All `runs=` counters are since last bootstrap (= boot, except where noted). Nothing was
unloaded, killed or edited; the one mutation was a throwaway label (`com.cc.parsetest.tmp`)
bootstrapped and booted out inside a single call as a positive control (§9), verified GONE.

---

## 0. Headline

**The scheduled fleet costs ~24,000 job wakes/day and ~656,000 process creations/day — and the four
largest line items are not doing the work they appear to be doing.**

| # | Line item | Cost/day | Verdict |
|---|---|---|---|
| 1 | `com.claude.dispatcher` | 196,357 forks | Largest single producer (30%); most runs end in "premise no longer holds" for the same 4 items |
| 2 | `com.claude.compressor-sentinel` | 189,360 forks | Load-bearing (tripped 07:09Z today) but runs at **PRI 20** — undemoted, competing with interactive sessions |
| 3 | `com.claude.lead-supervisor` | 102,588 forks | Also **PRI 20**; `ps -wwEo command=` (full environment of every process) every 30 s |
| 4 | `homebrew.mxcl.postgresql@14` | 8,556 failed spawns | **100% waste** — stale lock file, zero tenants, 193 MB log, spinning every 10 s for weeks |
| 5 | `com.claude.session-search-sweep` | 1,314 wakes | **100% no-op** — dies in `awk` on every single run; 41,460/41,460 log lines are the same fatal |

Two premises in the brief do not survive measurement, and one instrument does not either:

- **"5 overlapping reaper-family jobs"** → only **4 are loaded** (`team-orphan-reaper` is disabled),
  their subjects are **disjoint** (sessions / teammate-close-outcome / worktrees / dev-servers), and
  one of them (`teammate-reap-alarm`) is an **alarm, not an actuator** whose entire value is being
  independent of the mechanism it watches. Merging them is the wrong move — see §6.
- **"worktree-GC daemons exist yet counts stay high"** → the infra janitor **removed 319 worktrees
  and 389 branches in one run** at 2026-08-09 22:15. The residual 108 are kept *by policy*
  (`worktree-gc-infra.log:tail`), not by GC failure.
- **`plutil -lint` is the wrong oracle for a launchd plist.** Two reso plists fail it; launchd parses
  and runs them fine. **Proven by positive control** (§9). No reboot time-bomb exists here.

---

## 1. Inventory — one row per plist (39 owned)

Legend for **Live**: `run+act` = fires and changes state · `run+noop` = fires and changes nothing ·
`dead` = loaded but cannot run · `disabled` = persistent `launchctl disable` override · `future` =
calendar slot not yet reached this uptime.

### com.claude.* (21)

| Label | Trigger | Script | What it does | Wakes/day | Forks/wake | Live | Verdict |
|---|---|---|---|---|---|---|---|
| `boot-resume` | RunAtLoad + Interval 300 | `~/.claude/scripts/boot-resume.sh` | post-login resume/page of sessions killed by a reboot | **0** | — | **disabled** | **KEEP-OFF** — default mode is `page` not `resume`; C10 says operator loads it. Not a boot storm (§7) |
| `caffeinate-floor` | KeepAlive + RunAtLoad | `scripts/caffeinate-floor.sh --run` → `caffeinate -i -s` | prevents idle **and** system sleep | 1 (perpetual) | 0 | run+act (pid 818, RSS 1.26 MB, 20:11 h) | **CONVERT** — this is the *amplifier* that makes all 24 k wakes/day real (§8-R13) |
| `capacity-alarm` | Interval 60 | `scripts/capacity-alarm.sh --quiet` | 7-rung capacity verdict → `capacity-alarm.jsonl` | **1,338** | **47** | run+act | **KEEP + CONVERT cadence** — 62,863 forks/day, but it is the admission oracle 12 callers read |
| `compressor-sentinel` | KeepAlive (10 s internal loop) | `scripts/compressor-sentinel.sh` | vm_stat/swap watch; SIGSTOPs burst cohort when armed | 8,640 | ~13/tick | run+act (**TRIP 07:09Z** why=cbu) | **KEEP + DEMOTE** — plist has no `Nice`/`ProcessType` ⇒ **PRI 20** |
| `deploy-live` | Interval 600 + RunAtLoad | `scripts/deploy-live.sh --auto` | converges `~/.claude` live layer to trunk | 135 | 4 | run+act | **CONVERT → post-land event** |
| `desk-invariant` | RunAtLoad + Interval 300 | `scripts/desk-invariant.sh --once` | asserts a desk session exists | **0** | — | **disabled** | **DECIDE** — either re-enable or delete the plist; a disabled invariant asserts nothing |
| `devserver-gc` | Calendar `Minute 40` (hourly) | `scripts/devserver-gc-run.sh` (`DEVGC_ACT=1`) | reaps orphaned `next-server`/dev servers | 24 | ~10 | **re-armed 00:26 today** (plist mtime; `runs=0`) — every logged run to 06:40Z was `act=0` dry-run | **KEEP — UNPROVEN**; first armed run has not happened yet |
| `discovery` | Interval 3600 | `~/.claude/bin/cc-discover --once` | frontier-hole discovery sweep | 14 | 7 | run+act (41 KB stdout; a prior instance exited −15) | **KEEP** — cheap; the −15 is a killed instance, not a dead job |
| `dispatcher` | Interval 300 | `~/.claude/bin/cc-dispatch --once` | backlog → quota-place → spawn worker session | 153 | **1,284** | run+act, but **self-refusing** (`rc=9`, capacity gate at 2.03/core) | **CONVERT + MERGE** — 196 k forks/day, 30% of the fleet |
| `lead-supervisor` | KeepAlive (SWEEP=30 s) | `scripts/lead-supervisor.sh --daemon` | pages on lead/session anomalies | 2,880 | ~36/sweep | run+act (pid 85774, 3.86 MB, restarted 58 min ago after −15) | **KEEP + DEMOTE + WIDEN SWEEP** — **PRI 20**; `ps -wwEo` per sweep |
| `log-rotation` | Interval 3600 + RunAtLoad | `scripts/rotate-autonomy-logs.sh` | 25 MiB-gated rotation + IDL hash-chain seal | 25 | 5 | run+act | **KEEP** — but its target list misses the biggest logs (§8-R11) |
| `nightly-regression` | Calendar 04:00 | `scripts/nightly-regression.sh --run` | nightly suite | **0** | — | **disabled** | **⚠ COVERAGE HOLE** — surface to the operator, not a memory item |
| `postland-verify` | Interval 300 | `scripts/postland-verify.sh --run-if-needed` | post-land full-suite verifier (self-requeuing) | 118 | **531** | run+act; **single run has been alive 58 min** — it blocks its own re-fire | **CONVERT → land event** (62,464 forks/day) |
| `power-policy-verify` | Interval 3600 + RunAtLoad | `scripts/power-policy-verify.sh --verify` | asserts pmset policy | 25 | 5 | run+act | **KEEP** |
| `qos-census` | Interval 600 | `scripts/qos-census.sh --quiet` | PRI-band census of the fleet | 141 | 20 | run+act (both `.log` files 0 bytes since Jul 30 — writes elsewhere) | **CONVERT → on-spawn** |
| `relogin` | Interval 3600 | `cc-relogin-poll --once` | detects logged-out accounts | 24 | 5 | run+act | **CONVERT → auth-failure event** |
| `session-search-backfill` | Calendar Sun 03:00 | `session-index-backfill.sh --quiet` | weekly index backfill | 0 (ran 03:00 Aug 9, pre-count) | — | future | **KEEP** |
| `session-search-sweep` | Interval 60 + RunAtLoad | `~/.claude/hooks/session-index-sweep.sh` | 60 s safety net that indexes transcripts the SessionEnd hook missed | **1,314** | 3 | **run+noop — BROKEN** | **🚨 FIX** (§8-R2) |
| `team-orphan-reaper` | Interval 600 | `scripts/team-orphan-reaper.sh` | archives dead teams, auto-denies stale permission reqs | **0** | — | **disabled** | **DECIDE** — its function is unowned while disabled |
| `teammate-reap-alarm` | Interval 600 | `scripts/teammate-reap-alarm.sh` + `assignee-pane-residency.sh` | counts `✓ closed pane` outcomes; ALARM if the close path closed nothing | 124 | 1 | run+act | **KEEP — DO NOT MERGE** (§6) |
| `worktree-gc-infra` | Calendar 04:15 | `scripts/worktree-gc-infra-run.sh` | worktree + branch janitor for claude-infrastructure | **0 this uptime** | ~large | **scheduled arm never fired**; the real run (22:15, removed 319) came from the **event path** | **CONVERT — formalise the event path** (§8-R6) |

### com.chrisren.* (6)

| Label | Trigger | Script | What it does | Wakes/day | Live | Verdict |
|---|---|---|---|---|---|---|
| `autonomy-sweep` | Interval 300 | `scripts/autonomy-sweep.sh` | autonomy-state sweep | 164 | run+act (5 forks) | KEEP |
| `cc-reaper` | Interval 300 | `cc-reaper sweep --reap` | reaps provably-terminal sessions, checkpoint-first | 194 | run+act (3 forks) | KEEP |
| `restic-claude-archive` | Calendar Sat 02:00 | `restic-claude-archive-backup.sh` | weekly restic backup | 0 (future) | future | KEEP |
| `screenshot-clipboard` | **WatchPaths** `~/Screenshots` | `~/bin/screenshot-to-clipboard.sh` | copies new screenshot to clipboard | 8 (event) | run+act | **KEEP — the reference event-driven design** |
| `verify-2114-archive` | Calendar Sun 09:00 | `claude-code-archive/scripts/verify-integrity.sh` | archive integrity | 1 | run+act (exit 0) | KEEP |
| `watch-claude-code-2118-hold` | Calendar 09:12 | `scripts/watch-claude-code-2118-hold.sh` | watches a hold on CC **2.1.18** | 1 | **run+fail (exit 1)** | **KILL** — running CC is 2.1.220; the hold's subject is 15 minor versions stale |

### com.reso.* + gl.reso.* (7)

| Label | Trigger | What it does | Wakes/day | Live | Verdict |
|---|---|---|---|---|---|
| `com.reso.dead-monitoring` | Calendar 05:23 | tsx dead-monitoring check in reso | 1 | run+fail (**exit 2**) | **DECIDE** — fails daily; owner is reso |
| `com.reso.loki-parity-revisit` | Calendar **Day 7** monthly | a *revisit reminder* from June | 0.03 | future | **KILL** — a calendar entry as a to-do item |
| `com.reso.lr-reset-poller` | Interval 600 + RunAtLoad | polls for a usage-limit reset time | 142 | run+act (1 fork) | **CONVERT** — the reset time is a **known timestamp**; use a one-shot, not a poll |
| `com.reso.qa-nightly` | Calendar 04:17 | nightly QA on `reso-qa-runner`; **`git reset --hard main`** | 1 | runs=0 (boot-race) | **KEEP w/ warning** — a destructive `reset --hard` on a cron |
| `com.reso.rum-verify-launchflash` | Calendar **Month 6 Day 13** | one-shot verification for 2026-06-13 | 0 (annual) | past | **KILL** — its date passed; it now fires once a year forever |
| `gl.reso.csp-smoke` | Calendar 03:45 | CSP smoke test | 1 | runs=0 (boot-race) | KEEP |
| `gl.reso.worktree-gc` | Calendar 03:15 **+ WatchPaths** `~/.reso/worktree-gc.wake` | reso worktree janitor w/ kill-0 liveness registry | **56** | run+act, **424 forks/run = 23,941/day** | **KEEP design, THROTTLE** — `~/.reso/bin/worktree-pool.sh` touches the wake file continuously (mtime was 23 s old at measurement) |

### Third-party (5)

| Label | Trigger | Wakes/day | Live | Verdict |
|---|---|---|---|---|
| `org.git-scm.git.hourly` | Calendar ×24 | 24 | run+act | **KEEP but ENROLL** — `maintenance.repo` has **exactly 1 repo**: `reso-management-app`. claude-infrastructure (115 worktrees) is **not enrolled** → hand to axis E |
| `org.git-scm.git.daily` | Calendar Day 1–6 @ 00:16 | ~0.2 | runs=0 | KEEP (day-of-**month** 1–6 only — 6 days in 30) |
| `org.git-scm.git.weekly` | Calendar Day 0 @ 00:24 | 0.14 | run+act (runs=1) | KEEP |
| `homebrew.mxcl.ollama` | KeepAlive + RunAtLoad | 1 (perpetual) | run+act, **0 tenants** | **KILL** (§8-R5) |
| `homebrew.mxcl.postgresql@14` | KeepAlive + RunAtLoad | **8,556** | **dead-looping** | **🚨 KILL** (§8-R1) |

---

## 2. Aggregate — wakes/day and the fork bill

| Job | wakes/day | forks/wake (measured) | forks/day |
|---|---:|---:|---:|
| `dispatcher` | 153 | 1,284 | **196,357** |
| `compressor-sentinel` | 8,640 (10 s loop) | ~13 | **189,360** |
| `lead-supervisor` | 2,880 (30 s sweep) | ~36 | **102,588** |
| `capacity-alarm` | 1,338 | 47 | **62,863** |
| `postland-verify` | 118 | 531 | **62,464** |
| `gl.reso.worktree-gc` | 56 | 424 | **23,941** |
| `postgresql@14` | 8,556 | 1 | **8,556** |
| `session-search-sweep` | 1,314 | 3 | 3,942 |
| `qos-census` | 141 | 20 | 2,823 |
| `autonomy-sweep` · `cc-reaper` · `deploy-live` · `teammate-reap-alarm` · `lr-reset-poller` · `log-rotation` · `power-policy-verify` · `relogin` · `git.hourly` · `discovery` | 970 | 1–5 | ~2,570 |
| **TOTAL** | **≈24,070** | | **≈655,600** |

Method: `launchctl print gui/501/<label>` exposes per-instance `forks` / `execs` counters. Sampled 7×
at 12 s spacing (`/tmp/forksample.txt`); reported value is the highest observed for a single instance,
so these are **lower bounds** for jobs whose run outlived the sampling window. This is a measured
fork count, not a static `$(` count.

**Resident RSS of the always-on jobs is negligible — 44.6 MB total.**

| pid | job | RSS | PRI | elapsed |
|---:|---|---:|---:|---|
| 806 | ollama | 25.5 MB | 20 | 20:11 h |
| 51100 | dispatcher | 6.80 MB | 4 | 15 m |
| 64116 | compressor-sentinel | 5.73 MB | **20** | 26 m |
| 85774 | lead-supervisor | 3.86 MB | **20** | 58 m |
| 28530 | gl.reso.worktree-gc | 3.55 MB | **20** | 7 m |
| 86570 | postland-verify | 2.93 MB | 4 | 58 m |
| 27860 | capacity-alarm | 2.03 MB | 4 | 1.5 m |
| 17431 | qos-census | 1.94 MB | 4 | 1.7 m |
| 53844 | session-search-sweep | 1.81 MB | 4 | 1.1 m |
| 818 | caffeinate | 1.26 MB | 4 | 20:11 h |

🚨 **The RAM answer for this axis is: scheduled jobs are not a RAM problem — they are a CPU/QoS
problem.** 44.6 MB resident against a 64 GB box is noise. What they *do* cost is 656 k process
creations/day and, for the three PRI-20 daemons, ~315 k of those forks land in the **same scheduling
band as the interactive Claude sessions**. `Nice` alone does not demote on Darwin; only launchd's
`ProcessType Background` (or `taskpolicy -c background`) reaches PRI 4, and the three plists that omit
`ProcessType` sit at PRI 20 — `compressor-sentinel`, `lead-supervisor`, `gl.reso.worktree-gc`.

---

## 3. Act / no-op / dead — the per-job verdict

- **run+act (17):** capacity-alarm (1,068 OK / 278 WARN / 94 ALARM in the last day — real information,
  not a stuck alarm) · compressor-sentinel (TRIP recorded 07:09Z) · dispatcher (fires, and correctly
  *refuses* at the capacity gate) · lead-supervisor · postland-verify · deploy-live · cc-reaper ·
  autonomy-sweep · teammate-reap-alarm · qos-census · discovery · relogin · log-rotation ·
  power-policy-verify · gl.reso.worktree-gc · screenshot-clipboard · verify-2114-archive.
- **run+noop (1, total):** `session-search-sweep` — see §8-R2. Confirmed by executing the change
  detector read-only: `rows=0`.
- **run+noop (1, historical):** `devserver-gc` — every logged run through 06:40Z reported `act=0`
  (dry-run). Re-armed with `DEVGC_ACT=1` at 00:26 today; **its first armed run has not occurred**, so
  no claim either way is yet warranted.
- **run+fail (3):** `postgresql@14` (exit 1 × 7,273) · `watch-claude-code-2118-hold` (exit 1) ·
  `com.reso.dead-monitoring` (exit 2).
- **disabled (4):** boot-resume · desk-invariant · nightly-regression · team-orphan-reaper.
- **never-fires-usefully (2):** `rum-verify-launchflash` (its date is in the past) ·
  `loki-parity-revisit` (a to-do encoded as a monthly calendar entry).
- **scheduled-arm-never-fired (1):** `worktree-gc-infra` — calendar slot 04:15, boot at 04:18. The
  slot is **3 minutes** wide against this boot time; the whole uptime produced `runs=0` while the
  event path did the actual work.

---

## 4. Poll → event conversion table (with the causing event named)

| Job | Poll now | Causing event | Mechanism that already exists |
|---|---|---|---|
| `postland-verify` | 300 s | **a land** | `scripts/ship-land.sh` post-land step; queue file under `~/.claude/autonomy/postland/` → `WatchPaths` |
| `deploy-live` | 600 s | **trunk moved** | `WatchPaths` on the trunk ref, or chain off the same post-land step |
| `dispatcher` | 300 s | **backlog item opened / claim released** | `cc-backlog` store write → `WatchPaths` |
| `worktree-gc-infra` | Calendar 04:15 | **pane death / `/ship` land / teardown** | already called by `bin/cc-teardown`; formalise + keep a daily floor |
| `teammate-reap-alarm` | 600 s | **`TeammateIdle` / `TaskCompleted`** | both events are already wired in `~/.claude/settings.json` |
| `relogin` | 3600 s | **an auth failure** | `claude-accounts` already classifies `logged-out` |
| `qos-census` | 600 s | **a session spawn** | `scripts/lib/pane-spawn-log.sh` |
| `lr-reset-poller` | 600 s | **a known reset timestamp** | replace the poll with a one-shot `StartCalendarInterval` at the reset |
| `gl.reso.worktree-gc` | WatchPaths (already event-driven) | — | **throttle**: debounce the `.wake` touch in `~/.reso/bin/worktree-pool.sh`; 56 full GC passes/day at 424 forks each |
| `capacity-alarm` | 60 s | **admission decision** | `scripts/lib/capacity-admit.sh` already reads it — but a *cache floor* is what the 60 s tick is for; widen to 120–180 s rather than converting |
| `session-search-sweep` | 60 s | **`SessionEnd`** | the hook already exists; the sweep is the *net*, so fix it — do not convert it |

**Reference implementation already on the box:** `com.chrisren.screenshot-clipboard` — pure
`WatchPaths`, 8 wakes/day, zero polling. This is the shape every row above should converge to.

---

## 5. Redundancy clusters

**Cluster A — "reapers" (the brief's premise, corrected).** Four loaded, one disabled, **subjects
disjoint**:

| Job | Subject | Kind |
|---|---|---|
| `cc-reaper` | live *sessions* across 4 accounts | actuator (checkpoint-first) |
| `teammate-reap-alarm` | the *close-path outcome* (`✓ closed pane` count) | **alarm — never closes anything** |
| `worktree-gc-infra` / `gl.reso.worktree-gc` | worktree *directories* + branches | actuator (per-repo) |
| `devserver-gc` | *dev servers* (`next-server`) | actuator |
| `team-orphan-reaper` (disabled) | *team records* + stale permission requests | actuator |

Only one genuine merge exists: the **two worktree janitors** share a decision module shape and both
resolve liveness through `lsof`. Merge them into **one repo-parameterised janitor** (the infra
wrapper already documents the reso incident it inherits its PATH hardening from). Everything else in
this cluster is a distinct subject and merging would delete an incident answer — see §6.

**Cluster B — capacity/telemetry (real overlap).** `capacity-alarm` (60 s) + `qos-census` (600 s) +
`compressor-sentinel` (10 s) all read `vm_stat`, `sysctl`, and the process table. Three independent
process-table walks. **MERGE the sampling, keep the verdicts separate**: one sampler writes a
`/tmp/cc-vmsample.json` at the sentinel's 10 s cadence; the other two read it. Saves the duplicate
`ps`/`vm_stat` in ~1,479 wakes/day.

**Cluster C — land-triggered (real overlap).** `postland-verify` (300 s) + `deploy-live` (600 s) +
`worktree-gc-infra` all want to run *after a land*. One post-land event, three subscribers. Saves
~253 polls/day and, more importantly, removes the 58-minute `postland-verify` instance that blocks
its own re-fire.

---

## 6. Anti-merge — what a consolidation would destroy

🚨 **`teammate-reap-alarm` must not be folded into any reaper.** Its own header
(`scripts/teammate-reap-alarm.sh:3-17`) records the incident: on 2026-07-25 the last automatic
teammate pane close happened; for **nine days** every close attempt refused and nobody noticed, while
**four separate investigations each found a real defect, fixed it, verified the fix, and declared the
class resolved.** They were all honest and all wrong, because they verified a *mechanism* while the
*outcome* stayed at zero. Line 17 is explicit: *"THIS IS AN ALARM, NOT A GATE. It never refuses a
spawn, never closes a pane, never blocks a land."* Its value is exactly its independence from the
thing it measures. Merging it into `cc-reaper` re-creates the blind spot it was built to close.
124 wakes/day at 1 fork each is 0.02% of the fork bill — there is no economic case for touching it.

Same test applied to the rest: `capacity-alarm` is read by 12 call sites including
`scripts/lib/capacity-admit.sh`, `handoff-fire.sh` and `cc-teardown` — it is the oracle behind the
dispatcher's observed refusal (*"capacity gate: REFUSING a net-new fire — load 20.26 on 10 cores =
2.03/core > ceiling 2.0/core"*). Its cadence can widen; it cannot be removed.
`compressor-sentinel` tripped **today** (07:09Z, `why=cbu`, compressor growing 191 MB/s) — it is the
only instrument that sees a compression burst before swap does.

---

## 7. Boot storm — answered: **there is none**

- `com.claude.boot-resume` is **disabled** (`launchctl print-disabled gui/501`), has **no stdout log
  at all** (`/tmp/claude-boot-resume.*.log` does not exist), and even when enabled its **default mode
  is `page`, not `resume`** (`boot-resume.sh:12-17`) — it pages the reboot delta once and stops.
- `com.claude.relogin` is `RunAtLoad=0`, interval 3600 — it polls for logged-out accounts; it does
  not launch sessions.
- GUI login items are entirely non-Claude: DJ-controller autolaunchers ×8, Hammerspoon, VoiceInk,
  Wispr Flow, Dia, FigmaAgent, BetterDisplay, Acrobat sync.
- `RunAtLoad=1` among ours: 10 plists, of which 2 are disabled → **8 fire at login**, and only two of
  those are daemons (`compressor-sentinel`, `lead-supervisor`); the rest are one-shot or `caffeinate`.

**Conclusion: the ~15-session ceiling is not pre-committed at boot.** Sessions are created
interactively and by `handoff-fire.sh`, and the *only* boot-time pre-commitment is the two KeepAlive
daemons (9.6 MB combined) plus ollama (25.5 MB).

---

## 8. Redesign findings (contract row structure)

**R1 — postgresql@14 has been fork-bombing itself for weeks with zero tenants**
Evidence: `launchctl print gui/501/homebrew.mxcl.postgresql@14` → `runs = 7273`, `last exit code = 1`,
`state = spawn scheduled` in 20.4 h = one spawn per 10 s. `/opt/homebrew/var/log/postgresql@14.log` is
**193 MB / 1,735,420 lines**, of which **867,266** are `FATAL: lock file "postmaster.pid" already
exists`. `postmaster.pid` names **PID 907**, which is
`/System/Library/.../localspeechrecognition.xpc` (started 04:19:12, three seconds after the postgres
line — a PID reuse). `lsof -iTCP:5432` → nothing listening. `psql -l` → nothing. No reference to
`5432`/`postgres` anywhere in `claude-infrastructure/{scripts,hooks,bin}`.
Cost now: 8,556 fork+exec/day · 193 MB log and growing · a permanently red KeepAlive job that masks
any real postgres failure.
Re-architecture: `brew services stop postgresql@14` (or `launchctl bootout` + remove the plist). If it
is wanted, delete the stale `postmaster.pid` first — but nothing on this box uses it.
Sizing: recovers ~8.5 k spawns/day + 193 MB disk + one always-red daemon · effort **XS** · risk
**low** (zero tenants measured; restart is one brew command).
Existing mechanism: homebrew services — **KILL**, do not rebuild.

**R2 — the 60 s session-index sweep has never indexed anything; it dies in `awk` every run**
Evidence: `~/.claude/logs/sweep-daemon.log` is **41,460 lines, 41,460 of which** are
`awk: newline in string /Users/chrisren/.cla... at source line 1` (`sort | uniq -c` → one line kind).
Root cause at `hooks/lib/session-index-helpers.sh:673`: `awk -F'\t' -v tracking="$tracking"` where
`$tracking` is the whole `file_tracking` table (one row per file, newline-separated). **BWK awk
(`/usr/bin/awk`, version 20200816) rejects a newline inside a `-v` value** — reproduced in isolation:
`awk -v t="$(printf 'x\ny')" '{print t}'` → same fatal, rc 2; single-line control → rc 0. Executing
the function read-only returns `rows=0`. It fails *silently* because the sweep consumes it as
`done < <(session_index_changed_files ...)` (`session-index-sweep.sh:188`) — a process substitution,
so `set -euo pipefail` never sees the rc.
Cost now: 1,314 wakes/day of a dead safety net; the SessionEnd hook is the *only* indexer, and
whatever it misses is now permanently unindexed. (Independently: retention reports `sessions
before=3018 … deletable=16`, so the DB itself is healthy — the *net* is what is gone.)
Re-architecture: pass the tracking table through a **file or stdin**, not `-v` —
`awk -F'\t' 'NR==FNR{...;next}{...}' <(printf '%s\n' "$tracking") -` — or switch that one call to
`/opt/homebrew/bin/gawk`. Then add the missing verdict: the sweep must emit
`verdict=ok changed=<n>` per run so "ran but indexed nothing" is distinguishable from "ran".
Sizing: restores the index safety net · effort **S** · risk **low** · **also add a positive control**
that fails when `changed_files` returns 0 rows against a known-changed transcript.
Existing mechanism: `session-index-sweep.sh` — **FIX**, not replace.

**R3 — the dispatcher is 30% of the fleet's fork bill and re-litigates the same refusals every run**
Evidence: `forks = 1284` for one instance (`launchctl print gui/501/com.claude.dispatcher`), 153
runs/day = **196,357 forks/day**. `/tmp/claude-dispatcher.stderr.log` (94 KB) shows the same four ids
skipped every pass — `087db20c3a24`, `0298535c1584`, `885cccce4c0f` — with *"its premise no longer
holds (claim refused at the actuator)"*, plus a standing *"3 open item(s) in project(s) OUTSIDE the
dispatch set"* notice. `dispatch-fires.log` shows the terminal state is usually `rc=9` (capacity gate).
Cost now: ~196 k forks/day, most of it re-deciding items that are structurally undispatchable, plus
an instance that outlives its own 300 s interval (etime 15 m).
Re-architecture: (a) **convert the trigger** to `WatchPaths` on the `cc-backlog` store — a dispatch
decision has exactly one cause, a backlog write; (b) **negative-cache** the refused ids with a TTL so
a permanently-refused claim is not re-walked 153×/day; (c) **short-circuit on the capacity gate** —
read `capacity-alarm.jsonl`'s last verdict *first* and exit before the backlog walk when it is ALARM.
Sizing: (c) alone cuts most of the 196 k on a saturated box · effort **M** · risk **medium** (this is
the autonomy spine — needs its selftest, which `cc-dispatch selftest` already provides).
Existing mechanism: `bin/cc-dispatch` — **EXTEND**.

**R4 — three daemons run in the interactive scheduling band**
Evidence: `ps -o pri` → `compressor-sentinel` PRI 20, `lead-supervisor` PRI 20,
`gl.reso.worktree-gc` PRI 20; every job whose plist carries `ProcessType Background` reads PRI 4.
`com.claude.compressor-sentinel.plist` and `com.claude.lead-supervisor.plist` have **no `Nice` and no
`ProcessType`** keys at all; `gl.reso.worktree-gc.plist` likewise. Together they produce ~315,900
forks/day.
Cost now: ~48% of the fleet's process creations compete directly with Claude sessions for CPU. At the
measured load (86.20 / 10 cores) that is the binding constraint, not RAM.
Re-architecture: add `<key>ProcessType</key><string>Background</string>` + `LowPriorityIO` to the
three plists. `Nice` alone does **not** demote on Darwin — only the launchd `ProcessType` band (or
`taskpolicy -c background`) reaches PRI 4, and that band is a one-way ratchet.
Sizing: no functional change, ~316 k forks/day moved out of the interactive band · effort **XS** ·
risk **low** — but note `compressor-sentinel` is an *incident responder*; demoting it slows its
reaction during exactly the burst it exists to catch. **Demote `lead-supervisor` and
`gl.reso.worktree-gc`; leave the sentinel at PRI 20 deliberately and say so in the plist.**
Existing mechanism: the plists — **EDIT**.

**R5 — ollama: 36 GB of disk and a KeepAlive daemon with zero tenants**
Evidence: `lsof -iTCP:11434` shows only its own LISTEN socket — no client. `du -sh ~/.ollama` = **36 G**.
`~/.ollama/models/manifests/` last modified **2025-08-02** (a year ago). The single grep hit across
`hooks/ scripts/ bin/` is `hooks/curl-gate.py:312`, where `11434` appears in a *localhost dev-port
allowlist* alongside 3000/3001/4040/6006/9229 — that is not a dependency.
Cost now: 25.5 MB resident + 36 GB disk + a RunAtLoad/KeepAlive slot, for zero consumers.
Re-architecture: `brew services stop ollama`; keep the models if local inference is a future
intention, or reclaim 36 GB.
Sizing: 25.5 MB RAM + 36 GB disk · effort **XS** · risk **low** — but **confirm with the operator**
before deleting models (they cost bandwidth to re-pull).
Existing mechanism: homebrew services — **KILL the service**, decide the models separately.

**R6 — the infra worktree janitor's scheduled arm has never fired; the event path is doing the work**
Evidence: `launchctl print gui/501/com.claude.worktree-gc-infra` → **`runs = 0`** for the whole
20.4 h uptime, because its `StartCalendarInterval` is **04:15** and the box booted at **04:18** — a
3-minute miss that costs a full day. Meanwhile `~/.claude/logs/worktree-gc-infra.log` records a real
run at **2026-08-09 22:15:24** — `removed=319 disposed=0 kept=108 branches=389 refusals=46 rc=0` —
fired from the event path (`bin/cc-teardown` and `scripts/devserver-census.sh` both invoke
`worktree-gc-infra-run.sh`).
Cost now: the janitor's *reliability* rests entirely on an undeclared event path; a day with no
teardown is a day with no GC. The 108 kept are **policy**, not failure: 8 unlanded past the 72 h
horizon with **no ownership oracle at all**, 5 unlanded but provably owned (open/claimed item or live
team), 1 abandoned-reapable needing `--dispose-abandoned`.
Re-architecture: (a) make the event path first-class — call it at `/ship` post-land and at pane death,
not only at teardown; (b) keep a **daily floor** but move it off the boot-race window (04:15 → 05:15)
and/or add `RunAtLoad` with a debounce; (c) the 8 no-oracle worktrees need an *ownership* decision,
not a GC change — the janitor is correctly refusing.
Sizing: makes an already-working janitor deterministic · effort **S** · risk **low**.
Existing mechanism: `com.claude.worktree-gc-infra` + `worktree-gc-infra-run.sh` — **EXTEND**.

**R7 — `postland-verify` outlives its own interval**
Evidence: `run interval = 300 seconds` but the live instance (pid 86570) had `ELAPSED 58:19` and
`forks = 531`. launchd will not re-fire a running job, so the effective cadence is "whenever the last
one finishes" — `runs=100` against a theoretical 245.
Cost now: 62,464 forks/day, and a verifier whose real cadence is unknowable from its plist.
Re-architecture: convert to the **land event** (§4) and bound the run; `--run-if-needed` self-requeues,
so assert one effect per *edge*, never per sweep.
Sizing: effort **S** · risk **low**. Existing mechanism: `postland-verify.sh` — **CONVERT**.

**R8 — `gl.reso.worktree-gc` is event-driven and firing 56×/day at 424 forks**
Evidence: `WatchPaths: ~/.reso/worktree-gc.wake`; that file's mtime was **23 seconds old** at
measurement; `runs = 48` in 20.4 h against a *daily* calendar arm. The toucher is
`~/.reso/bin/worktree-pool.sh`.
Cost now: 23,941 forks/day — a full worktree census per pool operation.
Re-architecture: debounce at the producer (touch at most once per N minutes) or coalesce in the
consumer (exit early if the last run was <5 min ago).
Sizing: ~20 k forks/day · effort **XS** · risk **low**. Existing mechanism: **THROTTLE**.

**R9 — `plutil -lint` is not the launchd parser; the two "malformed" reso plists are a false alarm**
Evidence: `plutil -lint` rejects `com.reso.dead-monitoring.plist` (line 7) and
`com.reso.qa-nightly.plist` (line 11) with *"Encountered unknown ampersand-escape sequence"* — the
raw `&&` inside a `<string>`. **Positive control**: a purpose-built plist with the identical `&&`
shape was rejected by `plutil -lint` and **accepted by `launchctl bootstrap gui/501` (rc 0)**, with
the `&&` surviving verbatim into the loaded `arguments`. Corroborated in the wild: dead-monitoring's
file has been malformed since **Jun 7**, yet launchd loaded it at the Aug 9 login and ran it at
05:23 (`/tmp/reso-dead-monitoring.err.log` mtime 05:23:05, `runs = 1`).
Cost now: zero — but the *false* finding would have generated a remediation item and, worse,
established `plutil -lint` as the plist oracle for future audits.
Re-architecture: audit plists with `launchctl print` (or a throwaway bootstrap) — never `plutil` alone.
Sizing: effort **0** · risk **0** — this row exists to **prevent** work.
Existing mechanism: none needed. (Distinct from the JSON-format plists a prior task fixed — those
were a real class; `plutil -lint` is now clean on all 39 except these two false positives.)

**R10 — four jobs are disabled, and two of those are unowned functions**
Evidence: `launchctl print-disabled gui/501` → `boot-resume`, `desk-invariant`, `nightly-regression`,
`team-orphan-reaper` all `=> disabled`; all four absent from `launchctl list`.
Cost now: `nightly-regression` = **no nightly suite runs at all**. `team-orphan-reaper` = dead team
records and stale permission requests accumulate with no collector. (`boot-resume` disabled is
correct — C10 says the operator loads it. `desk-invariant` needs a call.)
Re-architecture: operator decision per job — re-enable or delete the plist. A disabled invariant that
still ships a plist reads, to every future audit, as a live guarantee.
Sizing: effort **XS** · risk **operator's call** — this is a `cc-backlog needs`, not an agent action.
Existing mechanism: **DECIDE**.

**R11 — log rotation is size-gated at 25 MiB and the biggest logs sit just under it**
Evidence: `ROTATE_MAX_BYTES` default **26,214,400** (`rotate-autonomy-logs.sh:75`). Live sizes:
`cc-reaper.log` 23.1 MB, `teammate-checkpoint.log` 22.9 MB, `compressor-sentinel-snap.log` 14.5 MB —
all *below* the gate, all growing. `postgresql@14.log` at **193 MB** is not a target at all (homebrew
owns it). `capacity-alarm.jsonl` 11,498 rows; `compressor-sentinel.jsonl` 47,861 rows.
Cost now: ~250 MB of daemon logs, and the largest single file is invisible to the rotator.
Re-architecture: hand the store-growth design to axis I; the scheduling-side action is to add the
homebrew logs to `ROTATE_TARGETS` **only if** their producers survive R1/R5 — killing postgres and
ollama removes the 193 MB producer entirely, which is the better fix.
Sizing: ~200 MB · effort **XS** · risk **low**. Existing mechanism: `rotate-autonomy-logs.sh` — **EXTEND**.

**R12 — git maintenance is enrolled for exactly one repo, and it is not the one with 115 worktrees**
Evidence: `git config --global --get-all maintenance.repo` → **1 line**,
`/Users/chrisren/Development/reso-management-app`. Three launchd jobs
(`org.git-scm.git.{hourly,daily,weekly}`) service it. claude-infrastructure is absent.
Cost now: the hourly job is cheap (24 wakes/day, ~5 forks) — the cost is the *omission*.
Re-architecture: axis E owns the enrollment design. Scheduling note: `org.git-scm.git.daily` uses
`Day` 1–6 = **day of month**, so "daily" maintenance runs 6 days in 30.
Sizing: hand-off, not an action here.

**R13 — `caffeinate -i -s` is the amplifier that makes all 24,070 wakes/day real**
Evidence: pid 818, `caffeinate -i -s`, elapsed 20:11:12 = the entire uptime, KeepAlive, RunAtLoad.
`-i` blocks idle sleep and `-s` blocks system sleep on AC.
Cost now: every poller above runs at full cadence overnight and while the operator is away. Without
it, macOS would coalesce and suppress a large share of ~24 k wakes.
Re-architecture: scope the floor to *when work is in flight* — hold the assertion only while a live
session or an in-flight wave exists (`cc-sessions` registry non-empty), release it otherwise. The
`caffeinate` process is 1.26 MB; the cost is entirely in what it *enables*.
Sizing: potentially halves realized wakes on idle nights · effort **S** · risk **medium** — a sleeping
box breaks `handoff-fire` wake-backs and overnight waves. **This one needs an operator call**, not a
unilateral change.
Existing mechanism: `scripts/caffeinate-floor.sh` — **EXTEND with a condition**.

---

## 9. Adversarial self-pass

Three things I assumed and then checked:

1. **"`plutil -lint` failure ⇒ the job will not load after reboot."** *Refuted* by positive control
   (§8-R9). Had I shipped it, it would have produced a fix for a non-problem and installed the wrong
   audit oracle. The control was cheap and decisive; the wild corroboration (file malformed since
   June, ran on Aug 9) is what made me look.
2. **"The reaper family is redundant, merge it."** *Refuted* by reading each subject.
   `teammate-reap-alarm:17` states in terms that it is an alarm, not a gate, and its header records
   the nine-day silent failure that four mechanism-verifying investigations missed. Consolidating it
   would re-open that exact blind spot for 0.02% of the fork bill. Only the two worktree janitors are
   genuinely mergeable.
3. **"capacity-alarm at 1,440 wakes/day is a stuck alarm carrying zero bits."** *Refuted*: the last
   day is 1,068 OK / 278 WARN / 94 ALARM, and 12 call sites consume it — including the dispatcher
   refusal observed live. Its cadence is a tuning question, not a removal question.

Axes I did not cover and should be picked up elsewhere:

- **Session-spawned pollers** (`cc-await-ping`, keepalives, statusline) are axis C. My census covers
  launchd only; I verified there is no second scheduler — `/Library/LaunchAgents` holds only Pioneer
  DJ launchers, `/Library/LaunchDaemons` has none of ours, `crontab -l` is empty, `atq` is empty,
  `/etc/periodic/{daily,weekly}` is empty, and Hammerspoon's only `hs.timer` uses are one-shot
  `doAfter` calls plus a single animation `doEvery` — **no hidden standing poller**.
- **A datum that cuts against the whole investigation's framing** (hand to axis L): the capacity
  alarm's own last row reads `sessions:34, headroom_gb:29.21, swap_used_mb:0.00,
  per_session_mb_est:636, est_room_sessions:47`. Its model says there is room for **47 more**
  sessions. What is actually red is **load** — `uptime` returned `load averages: 86.20 47.73 39.78`
  on 10 cores = **8.6/core** against the alarm's 2.5/core ceiling, and the dispatcher is refusing
  fires on exactly that rung. **On this box, at this moment, the binding constraint is CPU, not RAM**
  — which is consistent with §2's finding that the entire scheduled fleet is 44.6 MB resident but
  656 k forks/day.

---

## 10. Blockers / uncertainties

- **`devserver-gc` was re-armed at 00:26 today** (plist mtime + `runs=0` after re-bootstrap). Every
  logged run to 06:40Z was `act=0`. Its first armed run has not happened, so its act/no-op verdict is
  **unproven** — re-check after 00:40 PDT.
- **`forks` values are lower bounds.** They are per-instance and monotonic during a run; I sampled 7×
  over 84 s, so jobs whose runs exceed that window (dispatcher, postland-verify) are undercounted.
  Method is sound for ranking; the absolute totals should be treated as ≥.
- **`runs` resets on re-bootstrap**, not only on boot. Confirmed for `devserver-gc`. Everything else
  matched its interval × uptime within a few percent, so I treat those as boot-anchored.
- **`com.reso.*` ownership.** `dead-monitoring` fails daily (exit 2) and `qa-nightly` runs
  `git reset --hard main` from a cron. Both belong to reso, not claude-infrastructure — surfaced, not
  actioned.
- **The 8 unlanded worktrees with no ownership oracle** are a policy gap the janitor is correctly
  refusing to resolve. That is axis D's call, not a scheduling fix.

---
---

# Addendum — lead steer (a)–(e), verified 2026-08-10 00:50–01:05 PDT

INTEGRATE-only: §§1–10 above stand as written except where **§A6 corrects** one row.
The decisive instrument for this pass was **`bin/cc-fleet --check` / `--plist-parity` run read-only** —
the fleet board is the arbiter, and it both corroborates §§1–8 and finds two things my hand census
missed.

## A1 — (a) CONFIRMED: the fleet census is scoped away from the destructive janitor

`bin/cc-fleet:97` → `FLEET_PREFIXES="${CC_FLEET_PREFIXES:-com.claude. com.chrisren.}"`, consumed by
`fleet_plists()` at :99-103 as a **non-recursive glob per prefix**. The header at :95 is explicit and
deliberate: *"Deliberately NOT in scope: com.reso.\* / gl.reso.\* belong to a different project."*

The reasoning is sound for *ownership* and wrong for *blast radius*. `gl.reso.worktree-gc` is:

- the **only** scheduled job on this box that deletes directories outside its own project tree by
  default (§1: 56 wakes/day, 424 forks/run, WatchPaths-driven),
- the job that **already wrongly reaped a live worktree** — `wt-cc-233227-53597`, 2026-06-19 — for a
  PATH defect (`lsof` in `/usr/sbin`), an incident cited *by name* in the headers of two
  claude-infrastructure files that inherited its hardening (`worktree-gc-infra-run.sh:13-17`,
  `devserver-gc-run.sh:9-14`),
- and it runs at **PRI 20** (§8-R4).

So the repo's own janitors are hardened against an incident caused by a job the repo's own board
cannot see. The prefix list makes the board answer for *labels we author*; the risk is *labels that
act on our filesystem*.

**Design — unclaimed labels.** Add a third state to the board alongside `declared` / `staged`:

| State | Definition | Board behaviour |
|---|---|---|
| `declared` | in `fleet.manifest`, ours | full ladder (today) |
| `staged` | declared, not loaded | UNDECIDED (today) |
| **`unclaimed`** | **loaded in `gui/501`, matches no fleet prefix, and is not a vendor label** | **ONE summary row: count + labels + a per-label `writes` flag** |

Vendor set is enumerable and stable (`com.apple.`, `com.adobe.`, `com.google.`, `com.microsoft.`,
`com.razer.`, `homebrew.mxcl.`, `org.git-scm.`, `com.voiceink.`, `com.pioneerdj.`) — everything else
loaded under our uid is *unclaimed*, i.e. something on this machine schedules it and no board owns
it. Today that set is exactly `com.reso.*` (5) + `gl.reso.*` (2). Keep them out of the health ladder
(the board must not answer for another project's exit codes) but **surface their existence and
whether they mutate the filesystem** — one row, not seven. This is strictly additive to
`FLEET_PREFIXES`; the existing scoping argument survives intact because `unclaimed` asserts nothing
about health.
**Migration class: `mechanical`** (script + manifest only; no plist, no settings.json, no credentials).

## A2 — (b) CORRECTED AND SHARPENED: `launchd/staged/` does not hide a label, it fabricates a *false* finding

Half of the steer is already fixed and half is worse than described.

- **Manifest coverage is complete.** `com.claude.relogin` **is** declared (`fleet.manifest:153`, row 7,
  `expect=run`, `ok_exits 0,5`), and `comm` of live labels against manifest labels is **empty** — every
  loaded `com.claude.*`/`com.chrisren.*` label is declared. The "undeclared since 07-26" state was
  closed by the operator running `21-relogin-poll-activate.sh` on 2026-07-30.
- **Plist-parity coverage is not, and it fails in the wrong direction.** `fleet_plists()` globs
  `"$d/$pfx"*.plist` — non-recursive — so `launchd/staged/com.claude.relogin.plist` is invisible to
  the parity leg. The result is not a *missing* finding but a **wrong** one:

```
LIVE-ONLY      com.claude.relogin.plist  (one rm from unrecoverable — no repo SSOT)
```

The SSOT exists; it is 5 directory-levels away in `staged/`. A false "one rm from unrecoverable" is
worse than silence: it burns triage on a non-problem and trains the reader to discount the LIVE-ONLY
class — which on the same board is telling the truth about `com.chrisren.restic-claude-archive` and
`com.chrisren.verify-2114-archive` (both genuinely SSOT-less).

**Full parity output (5 findings, all real manifest-lint failures except the relogin false positive):**

| Class | Label | Verdict |
|---|---|---|
| REPO-ONLY | `com.claude.auth-timeseries` | committed 2026-08-09 23:33, **never installed** — a 7th staged-inert mechanism, newer than the six enumerated in `scaling-bottlenecks-2026-08-09.md:49-58` |
| CONTENT-DRIFT | `com.claude.devserver-gc` | **= finding (d)**, see §A4 |
| LIVE-ONLY | `com.claude.relogin` | **FALSE** — SSOT is `launchd/staged/` |
| LIVE-ONLY | `com.chrisren.restic-claude-archive` | true |
| LIVE-ONLY | `com.chrisren.verify-2114-archive` | true |

`com.claude.scratchpad-reaper` is confirmed staged-never-loaded (`launchd/staged/`, board says
`UNDECIDED — staged: NOT-INSTALLED`), as is `com.claude.lead-reconciler` (staged, absent from live).

**Fix:** make `fleet_plists()` search `staged/` as a second tier and emit a distinct class —
`STAGED-SSOT` — so a live job whose only committed copy is staged reads as *"declared, installed,
SSOT is staged"* rather than *"no repo SSOT"*. **Migration class: `mechanical`.**

## A3 — (c) CONFIRMED: `branch-reaper.sh` is trunk-resident, tested, and scheduled by nothing

`scripts/branch-reaper.sh` (8,366 B, 2026-08-01) deletes local branch refs already ancestors of trunk,
dry-run by default (`:37`). It has a real test file (`tests/branch-reaper.bats`) and appears in the
tsv-field-collapse corpus. Its only non-test reference is a **comment** —
`scripts/cloud-reconcile.sh:15`. No plist, no manifest row, no hook invokes it.

It is **not** redundant with the worktree janitor, and the difference matters: `worktree-gc-infra`
deletes branches only *incidentally* — the ones attached to worktrees it is removing (measured:
`removed=319 … branches=389` on 2026-08-09 22:15, i.e. ~1.2 branches per removed worktree). A branch
whose worktree was already gone, or which never had one, is outside that path entirely.
`branch-reaper` is the only mechanism that collects those, and it has never run on a cadence.

**Verdict: SCHEDULE (or delete).** Cheapest correct form is not a new plist — it is a
**subscriber on the same post-land event as §5 Cluster C**, since "a branch became an ancestor of
trunk" is caused by exactly one thing: a land. **Migration class: `c10` if it lands as a plist;
`mechanical` if it lands as a call inside the existing post-land path** — prefer the latter, since it
adds no launchd surface and needs no operator ratification.

## A4 — (d) CONFIRMED AND ESCALATED: the arming commit is not on a branch at all

The steer says "stranded on branch `crash-rootcause-2026-08-09` (`c6ab83a8`)". Measured, it is worse:

- `git for-each-ref --contains c6ab83a8` → **0 refs**. Not on `main`, not on
  `crash-rootcause-2026-08-09` (that branch is checked out at
  `.worktrees/wt-crash-rootcause-2026-08-09`, head `3a2d63ca`, which does **not** contain it).
- `git log --all --not --remotes | grep -c c6ab83a8` → 0. `git reflog --all` → 3 hits.
- **It is an unreferenced commit, reachable only from the reflog.**

The change's three copies now disagree, and the *only* correct one is the one no tool tracks:

| Location | State |
|---|---|
| `~/Library/LaunchAgents/com.claude.devserver-gc.plist` (**enforcing store**) | `DEVGC_ACT=1` — armed, reloaded, verified carrying the export |
| `origin/main:launchd/com.claude.devserver-gc.plist` | **no `DEVGC_ACT`** |
| working copy `launchd/com.claude.devserver-gc.plist:19` | comment asserting the opposite: *"There is deliberately no DEVGC_ACT in this plist"* |
| commit `c6ab83a8` (operator-ratified, packet `99637eaee7b9`) | **unreferenced** |

Consequences, in order of severity: (1) any reinstall/redeploy from the repo **silently disarms** an
operator-ratified reaper; (2) the SSOT actively documents the wrong policy, so the next reader
"corrects" the live copy back to observe-only in good faith; (3) `gc.pruneExpire` (default 2 weeks
for unreachable objects, 30 days of reflog protection) puts the ratification record on a clock.

This is the inverse of the standing "conclusion must reach the enforcing store" failure — here the
**enforcing store is the only place the conclusion reached**, and every durable record contradicts it.

**Action: recover `c6ab83a8` onto a branch and land it** (`git branch rescue/devserver-arm c6ab83a8`
→ cherry-pick onto main), including deleting the now-false comment at `:19`. Until then
`cc-fleet --plist-parity` will keep — correctly — reporting `CONTENT-DRIFT`.
**Migration class: `c10`** (touches a launchd plist; the operator has already ratified the *decision*
— `'ratify all except cold-compile'`, 2026-08-10 — so the c10 step is the land, not a fresh ask).

Note this also settles §3's open item: devserver-gc's arming is **operator-ratified and live**, so its
first armed run is expected — my §10 "unproven" caveat stands only for the *outcome*, not the arming.

## A5 — (e) migration class per verdict

Per `migrations/README.md:34-49`: *"any migration that touches settings.json, a launchd plist, or
credentials declares `c10` and waits for a human"*; an undeclared class is a hard error, never a
default (`:54-60`, asserted by `tests/deploy-migrations.bats`).

| Finding | Verdict | Class | Why |
|---|---|---|---|
| R1 postgres respawn loop | KILL | **`c10`** | homebrew launchd plist |
| R2 sweep `awk -v` | FIX | `mechanical` | `hooks/lib/session-index-helpers.sh` only |
| R3 dispatcher short-circuit + negative cache | CONVERT | `mechanical` | `bin/cc-dispatch` only |
| R3 dispatcher trigger → WatchPaths | CONVERT | **`c10`** | rewrites the plist trigger |
| R4 `ProcessType Background` ×2 | EDIT | **`c10`** | launchd plists |
| R5 ollama | KILL | **`c10`** | homebrew launchd plist |
| R6 worktree-gc-infra event path | EXTEND | `mechanical` (call site) + **`c10`** (calendar 04:15→05:15) | split the diff |
| R7 postland-verify → land event | CONVERT | **`c10`** | plist trigger |
| R8 worktree-pool `.wake` debounce | THROTTLE | `mechanical` | `~/.reso/bin/worktree-pool.sh` — **and it is a reso file, so it is out of this repo's c10 scope entirely** |
| R10 four disabled jobs | DECIDE | **`c10`** | `cc-backlog needs`, one step per job |
| R11 rotate targets | EXTEND | `mechanical` | script default list |
| R13 caffeinate condition | EXTEND | **`c10`** | plist + power policy |
| KILL `rum-verify-launchflash`, `loki-parity-revisit`, `watch-claude-code-2118-hold` | KILL | **`c10`** | launchd plists (first two are reso-owned) |
| A1 unclaimed-labels | ADD | `mechanical` | `bin/cc-fleet` + `fleet.manifest` |
| A2 `STAGED-SSOT` parity tier | FIX | `mechanical` | `bin/cc-fleet` |
| A3 branch-reaper scheduling | SCHEDULE | `mechanical` (post-land call site) | avoids new launchd surface |
| A4 recover `c6ab83a8` | LAND | **`c10`** | launchd plist |
| A6 autonomy-sweep dead drop | FIX | `mechanical` | script + role registration |
| A7 capacity-alarm `ok_exits` + interval | FIX | `mechanical` | `fleet.manifest` data row |

**11 of 19 are `c10`** — i.e. most of this axis's remediation is operator-gated by construction, and
the honest sequencing is: land the 8 `mechanical` items first, then file the `c10` set as **one**
`cc-do` batch rather than 11 separate asks.

## A6 — 🚨 CORRECTION to §1/§3: `com.chrisren.autonomy-sweep` is a dead drop, not `run+act`

My original row read *"run+act (5 forks)"* from `runs=139` plus a fresh `.err.log` mtime. The fleet
board disagreed, and the board is right:

```
{"state":"STALLED","detail":"evidence 536h old; bound 15m","subject":"com.chrisren.autonomy-sweep"}
```

Verified directly: `autonomy-sweep.out.log` is **0 bytes, mtime 2026-07-18 16:43** (536 h stale), while
`.err.log` is 74 KB and current, carrying the same line on every run:

> `autonomy-sweep: NEW records but no desk role at /Users/chrisren/.claude/cc-roles/desk — undelivered, will retry`

So it wakes **164×/day, finds NEW records every time, and cannot deliver a single one** because no
desk role is registered. It is the third confirmed dead drop in this axis, alongside
`session-search-sweep` (§8-R2) and — in effect — `postgresql@14` (§8-R1). All three share one shape:
**a job that runs, fails, logs the failure to a file nobody reads, and reports success to launchd.**

That shape, not the wake count, is the real finding of this axis. Its instrument already exists —
`cc-fleet`'s `evidence` column with a staleness bound — and it caught this one. It did **not** catch
`session-search-sweep`, whose manifest evidence is presumably its DB or `auto`; that is the gap to
close: **every scheduled job must name an evidence artifact it writes ONLY on a successful effect**,
never one it writes on every tick regardless of outcome. `fleet.manifest:255-257` makes exactly this
distinction for `teammate-reap-alarm` (*"evidence `auto` is honest here … unlike lead-supervisor and
worktree-gc-infra, whose runners route their output elsewhere and leave stdout at 0 bytes"*) — the
principle is written down; it is not yet applied to every row.

My §3 tallies are corrected to: **run+act 16 · run+noop 2 (`session-search-sweep`,
`autonomy-sweep`) · run+fail 3 · disabled 4.**

## A7 — new: two defects in the board's own capacity-alarm row

Found while checking A6, both in `launchd/fleet.manifest:147`:

```
com.claude.capacity-alarm | run | 600 | ~/.claude/logs/capacity-alarm.jsonl | 13 | 19-capacity-alarm-activate.sh
```

1. **No `ok_exits` field** → the board reports
   `FAILING — last exit code 2 after 1149 runs`. Exit 2 is `capacity-alarm.sh:31-34`'s **designed
   ALARM verdict**, and the box is genuinely in ALARM (load 8.6/core). The correct value is written
   down **in the same file, for the job with the identical verdict ladder** — `fleet.manifest:250`,
   `teammate-reap-alarm`: *"ok_exits 0,1,2,3 — every one of those is a DESIGNED verdict (OK 0 · WARN 1
   · ALARM 2 · NO-DATA 3) … Key S4 on `exit != 0` here and cc-fleet would file a permanent, unfixable
   daemon-fault row for exactly as long as the outage it is reporting lasts — the alarm-fatigue
   failure this file exists to end."* The prose even names the casualty: *"this file never goes RED on
   the lander who comes after (**capacity-alarm** and scratchpad-reaper each cost that)."* The
   remedy was derived, documented, applied to the twin, and not applied to the original.
   **The board goes red precisely when the machine is loaded — i.e. exactly when it is being read.**
2. **Interval drift 10×** — the manifest declares `600`; the live plist is `StartInterval 60`
   (measured `run interval = 60 seconds`, 1,338 wakes/day). The staleness bound the board computes
   from that column is therefore 10× too loose, so this row could go stale for ten missed ticks
   before anything notices.

Fix both in the data row: `… | 60 | … | 19-capacity-alarm-activate.sh | 0,1,2,3`.
**Migration class: `mechanical`.**

## A8 — the six staged-inert mechanisms, re-measured tonight

Per the steer, verified rather than rediscovered (`scaling-bottlenecks-2026-08-09.md:49-58`):

| Mechanism (as enumerated 08-09) | State 08-10 01:00 | Δ |
|---|---|---|
| compressor-sentinel SIGSTOP actuator — "armed but running stale bytes" | **restarted**: `runs=3`, current instance elapsed 26 min (started ~00:15 today), so the operator restart landed. Armed and **tripped at 07:09Z** (`why=cbu`, +191 MB/s). | **RESOLVED** |
| Wave C cold-compile admission (0006) — registered in 0/5 config dirs | not re-measured (config-dir registration is axis F/J); **explicitly excluded from tonight's ratification** (`'ratify all except cold-compile'`) | unchanged, by decision |
| reso `workerThreads` kill — 0/3 apps | out of this axis (reso app config) | — |
| **devserver-gc — "observe-only by design, blocked"** | **ARMED** — live plist carries `DEVGC_ACT=1`, job reloaded 00:26, board reports CONTENT-DRIFT | **CHANGED — see §A4** |
| mailbox-wake-arm (0007) / boot-resume plist — unregistered / shipped-unloaded | boot-resume: **still `disabled`**, absent from `launchctl list`, no stdout log ever written. 0007 was refused by its own preflight in tonight's ratification. | unchanged |
| ramp abort sensor — reads a dead sentinel as pct=0 = healthy | sentinel is now **alive**, so the fail-green path is not currently exercised — but the defect is latent, not fixed | unchanged (latent) |

**Plus a seventh, newer than that list:** `com.claude.auth-timeseries` — committed to `launchd/`
2026-08-09 23:33, **never installed** (`REPO-ONLY` on the parity board, `NOT-INSTALLED` on the
health board). The generator the meta-finding names is still producing.

## A9 — what this addendum changes about §0's conclusion

Nothing in the cost ranking: dispatcher / compressor-sentinel / lead-supervisor / postgres /
session-search-sweep are still the five that matter, and the fork bill stands at ~656 k/day.

What it changes is **the character of the problem**. §0 framed the waste as *cadence*. The addendum
says it is **delivery**: of the 26 loaded jobs, three run at full cadence and deliver nothing
(`session-search-sweep` → awk; `autonomy-sweep` → no desk role; `postgresql@14` → stale lock), one
delivers to an unreferenced commit (`devserver-gc`), one is invisible to its own board
(`gl.reso.worktree-gc`), one is falsely reported as SSOT-less (`relogin`), and one is falsely
reported as failing (`capacity-alarm`). Fixing cadence on a job that delivers nothing saves forks and
changes no outcome.

**The one-line redesign principle for this axis: every scheduled job must write an evidence artifact
ONLY on a successful effect, and the board must key staleness on that artifact — not on the job's
exit code, and not on a log it writes whether it worked or not.**
