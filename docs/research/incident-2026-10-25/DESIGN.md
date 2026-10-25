# DESIGN: lockup telemetry, early warning, automatic mitigation and break-glass (incident 2026-10-25)

**Author:** solution architect (workflow slot), written 2026-10-25 ~15:00 CDT and revised ~16:00 CDT against two critique lenses (§12). The repo was read at `ba9e991dc`. The only file written is this one.

**Inputs:**
- the six lane notes in this directory: `otel.md`, `mac-forensics.md`, `existing-instruments.md`, `watchdog-design.md`, `fleet-governor.md` and `break-glass.md`.
- `rca/RCA-draft.md` (15:06; it settles the `PCATCH` question from source and states runbook R17 and requirements R1–R18), plus `rca/diag-reports.md`, `transcripts-fleet.md`, `experiments.md`, `prior-research.md` and `ps-census.md`.
- `RCA.md` **does not exist yet**. Items that depend on its verdict, or on its VM reproduction (RCA-draft §11 Q2), are tagged **[RCA-DEP]**.

**Labels:** **C** = Confirmed (a file:line, a log row or a command run here is cited), **L** = Likely, **S** = Speculative.

**Correction to the brief:** this boot ran macOS **15.8.1 (24H32)**, not 15.7.x. **C** (`zsh-sample.txt:13`; `rca/diag-reports.md` §4).

---

## 0. Answer: the design in ten lines

1. **Host.** `compressor-sentinel.sh` (KeepAlive; the only instrument that stayed alive) spawns and respawns **one** child, `lockprobe.py`, and does nothing else on the lockup axis. lockprobe is the **sole lockup actor**: it senses, sets levels, captures, diagnoses, pages and, once armed, unpoisons. Nothing time-critical runs in the bash tick. On 10-25 the tick's median gap was 16–17 s, but there were 9 gaps over 120 s per hour (max 277–380 s) in 07–09Z (**C**, counted from `compressor-sentinel.jsonl` for this revision). Activation stays zero-human, because the sentinel self-restarts on new bytes.
2. **Trigger on liveness, never on load.** The triggers are a fresh-pty `zsh` canary; a `/dev` walk canary that names the node it is stuck on; a census of stuck `ps`/`login`/`zsh` (starvation-scaled, confirmed by a `sample` leaf); orphaned or exiting pty session leaders, joined to their members by **process group**; and kitty main-thread progress against its RC sockets. Load is refuted as a trigger: capacity-alarm read ALARM on 62% of 15,162 rows (**C**, `watchdog-design.md` F20).
3. **Thresholds** sit at 60%/80% of a measured or hard ceiling, or use "healthy = 0" persistence. Deadlines scale with a starvation gauge, so a timeout taken under starvation records `unknown` (lesson 3). A rule over its fire budget leaves the level machine, not only paging (lesson 4).
4. **Ladder: L1 WATCH** (brownout vote, 0.4 s snapshot) → **L2 DIAGNOSE** (forced full capture, automatic diagnosis, a page that carries the cure command) → **L3 ESCALATE** (off-box page, a files-only session roster for recovery, a second spindump). **There is no SIGSTOP actuator.** Freezing cannot release a kernel wait, and the replay showed no effect for this class. The mitigations with measured effect stay: brownout, RC circuit breaker, dispatcher backoff, and a Bash-hook refusal of `kitten @` while kitty RC is dead.
5. **Cure for the observed class: `rescue.sh unpoison <pgid>`.** It SIGKILLs the whole process group of an exiting or orphaned pty session leader (RCA-draft R17, R3). The opener's carrier wait is `PCATCH` (**C** from source, xnu-11417 `tty_dev.c:295-299`). That the kill releases the node is **L** and untested. The operator gets the cure as a chooser item and in the L2 page now. It runs automatically at L2 only after the RCA's VM reproduction (Q2) passes; until then it logs `WOULD` rows.
6. **Prevention that does not wait for the RCA.** `hooks/validate-bash.sh` logs, and after its shadow audit refuses, a SIGKILL of a pty session leader by pid, and suggests the pgid form. cc-reaper and the sentinel's kill rung never SIGKILL a pty session leader or master holder.
7. **Forensics are hang-proof by construction.**
   - Probes are disposable children, one outstanding per type. The parent owns the deadline and never waits, output goes to files, and every mutex is `(pid, lstart, kern.bootsessionuuid)`.
   - `perl -e 'alarm N; exec'` does **not** bound a caller stuck in an uninterruptible kernel wait (**C**: `capacity-alarm.sh:106-108`; `mac-forensics.md` §2.4).
   - The diagnosis names the stuck node, holder, leader and pgid, **and the cause**: the transcript command that killed the leader.
8. **Break-glass needs no tty.**
   - Hammerspoon was alive 12:28–13:11 (**C** `break-glass.md` §2 row 1). Its chooser offers Capture, Unpoison, Brownout hold, Rescue terminal, Kernel stacks, and Kill kitty, which warns under a devfs verdict.
   - A dormant iTerm2 profile runs bash without `login`. Apple-menu Restart writes the `shutdown_stall` stackshot.
   - A mechanical migration installs all of it. The only human step is one TCC click.
9. **After a halt.**
   - `boot_classify` first **preserves** raw evidence: copies of the DiagnosticReports, a bounded `log collect`, and the last boot's series.
   - It then classifies `LOCKUP_*`/`STORM_*` and points the existing `freeze` row at its JSON.
   - Recovery: boot-resume stops trusting an empty heartbeat roster after a lockup boot, and worktree-gc holds the interrupted sessions' worktrees for one boot.
10. **Human steps.**
    - **Phase-0 MUST:**
      - H5, the Pushover credential. `~/.config/lr-page/` is empty today (**C**), and without it no page reaches a person off-box.
      - H7, two c10 `--confirm` lines, including 0079 (the sentinel's Interactive band). Without 0079, lockprobe and its captures run at the sentinel's PRI 20. At that band the 03:43:05 snapshot came back empty (`own-instruments.md:87`).
    - H6 is one TCC click.
    - Optional, sudo-only: tailspin (H1), a fixed-argument spindump wrapper (H2), a KDK (H3). Attributing the 43% sys time needs H1/H2.
    - OTel is out of this design (§11).

---

## 1. What the RCA material says, and what the design does with it

| # | Finding | Label | Design consequence |
|---|---|---|---|
| R1 | The incident stack: `zsh_main→init_io→ttyname→ttyname_r→devname_r→lstat`, 1715/1715 samples | **C** `zsh-sample.txt:25-31` | Canaries reproduce exactly this path (fresh pty on stdin, full `/dev` walk) |
| R2 | 17 `login` and 23 `ps` processes asleep on **one** kernel path: `lstat→devfs_lookup→devfs_dntovn→vnode_getiocount→msleep`, at 0 CPU. No `blocked by` owner annotation | **C** `diag-reports.md` §2a | The lock-owner chain cannot name it. The canary's `last=` node plus the session census must name it (§3.3) |
| R3 | Session leader `bash 68298` was a zombie stuck in `proc_exit→vn_revoke→drain→msleep`. Its descendant `bash 96296` had been asleep in `open()→spec_open→pty driver` since **03:03:43**. All five pids (68298, 94459, 95771, 96296, 96310) are in **pgid 68298** | **C** stacks, `ps-prereboot.txt`; **L** causal link (RCA-draft §3) | Precursor rules P5/P6 (§4) join by pgid. The cure is a pgid kill |
| R4 | At **03:48:58** teammate t1-runner ran `kill -KILL 94459 68298` during `bats -f 'A1t pty'`, killing by pid, not by pgid. The call never returned | **C** act; **L** as the trigger (RCA-draft §3.4) | Kill guard in `validate-bash.sh`. cc-reaper and the sentinel's kill rung never kill a pty leader by pid (I9). The pty-lifecycle fixes R1–R5 belong to the RCA fix stream (§10) |
| R5 | `/dev` poisoning began between 03:41:14 and 03:50:19. The first permanently stuck `ps` started 03:50:19 | **C** `diag-reports.md` §0.4 | A canary every 30 s would read WEDGED by about 03:50 (§9) |
| R6 | kitty RC last succeeded at 03:47:23. The first "Too many peers" (PEER_LIMIT 256) at 06:11:40; 8,738 drops in total | **C** `transcripts-fleet.md` §0.1; `prior-research.md` §0.1 | kitty deafness is a **separate** chain that precedes the kill. It gets its own liveness probe and a `kitty_rc` circuit breaker |
| R7 | At 03:40, 20 `ps` were asleep **inside the `__sysctl` kern_proc handler** (ages 0–89 s) | **C** `diag-reports.md` §3b | `KERN_PROC_ALL` and `KERN_PROCARGS2` are **not** core-safe. They run only in the disposable `procscan` child (I3) |
| R8 | A blocked writer or a draining closer does not slow `/dev` lookups at k≤3. Last-close drain is bounded at ~0.6 s | **C** `experiments.md` §2 | P5's `E` threshold is 60 s plus pty-leader corroboration, because a multi-GB teardown can sit in `E` for seconds |
| R9 | Load during the dead window was 13–100, against a peak of 1,016 at 03:37 | **C** `existing-instruments.md` §1 | Load is forensics only |
| R10 | The sentinel tick on 10-25: median gap 16–17 s in 08–09Z, but 9 gaps over 120 s per hour (max 277–380 s in 07–09Z) and one 956 s gap in 03Z | **C**, counted from `~/.claude/logs/compressor-sentinel.jsonl` | The bash tick is a survivable host but neither a timely sensor nor a timely actor. lockprobe senses and acts; the sentinel only respawns it |
| R11 | `/goal` runaway 12:05–13:14: about 640 Bash calls, each running `/Applications/kitty.app/Contents/MacOS/kitten @ ls` 8 times **by absolute path**. The dispatcher re-fired 69 times | **C** `transcripts-fleet.md:257-262`; `fleet-governor.md` §2.3 | The breaker inside it2-kitty never sees this loop. `validate-bash.sh` refuses `kitten @`/`kitty @` in any form while RC is dead (C5) |
| R12 | The opener's carrier wait is `PCATCH` (`ptsopen`, xnu-11417 `tty_dev.c:295-299`). So SIGKILL of 96296, or `kill -KILL -- -68298`, would very likely have let the revoke finish | **C** source; **L** effect, untested (RCA-draft §1.5, §11 Q2) | `rescue.sh unpoison` ships now, invoked by the operator. It becomes automatic at L2 only after the Q2 VM reproduction **[RCA-DEP]** |
| R13 | An exiting session leader reports `e_tdev = NODEV`: `proc_exit` calls `session_clear_tty_locked` before `VNOP_REVOKE`, and `kinfo_proc.e_tdev` is read from `s_ttydev` | **C** xnu main source (`kern_exit.c:2321,2336`; `kern_proc.c:2675-2686`; `kern_sysctl.c:1056-1060`); **L** for 11417 (critique lens 1) | Never join a wedged node to its session by tdev. Join by pgid, and keep a `(pid, lstart) → last-seen tdev` map from healthy samples (C1) |
| R14 | Recovery failed. boot-resume accepted the empty 13:09 heartbeat roster, then worktree-gc-infra removed 49 worktrees, 11 of them needed for a resume | **C** `scripts/boot-resume.sh:599-603`; `session-inventory.md` §1 rows 1-4, 12; RCA-draft R16 | Lane E (C6) |

**Bottom line for mitigation.** For this class, the automatic outcome would have been:
- a precursor snapshot and a `WOULD unpoison pgid 68298` from about 03:05;
- by about 03:51, a diagnosis and a page carrying `rescue.sh unpoison 68298`;
- a cure without a reboot once unpoison is armed (**L**).

Once armed, the kill guard would have refused the 03:48:58 kill-by-pid outright.

---

## 2. Architecture and hang-proof invariants

```
launchd gui/501 ── com.claude.compressor-sentinel  [KeepAlive; bash loop 10 s; ProcessType Interactive (0079)]
   │  existing compressor axis + FROZEN_DB, unchanged except the C2 guards
   │  NEW: spawn/respawn lockprobe · spawn boot_classify · cc-fleet --json every 5 min
   └─ lockprobe.py core  [$PY -I; 1 thread, 2 s tick; QoS user-interactive + band read-back; flock lease]
        │  per tick: no fork/exec, no /dev, no KERN_PROC_*, no proc_pidinfo
        └─ spawner  [os.fork of the core at start; posix_spawn only; never opens /dev]
             ├─ procscan.py      10 s   KERN_PROC_ALL (pid, ppid, pgid, tdev, stat), kitty threads + RC sockets, CPU deltas
             ├─ ptycanary.py     30 s, 10 s at L1   openpty → dup2 slave → /bin/zsh -fc ': lockwatch-canary; exit'
             ├─ devfs-canary.pl  30 s   per-entry lstat walk; names the node it is stuck on
             ├─ fdscan.py        300 s  vnode-fd census: pty masters, slave holders, orphaned masters
             └─ on level entry:  capture.sh · diagnose.py · rescue.sh unpoison · lr-page.sh · alarm-reboot-prep.sh --files-only
consumers (read files only): capacity-admit · handoff-fire · cc-dispatch · it2-kitty · validate-bash.sh · Hammerspoon
root (optional, H2): /usr/local/libexec/cc-forensics-root.sh {spindump|tailspin}
```

**Why a sentinel child and not its own launchd label** (**L**, a design judgement):
- **Zero-human activation.** A new plist is a `c10` migration: one that touches a launchd plist "declares c10 and waits for a human" (`migrations/README.md`). A sentinel child activates on land.
- **The bash tick's lateness (R10) only delays a respawn after lockprobe dies.** Hammerspoon's dead-man page covers that case. Every time-critical action runs inside lockprobe.
- **Promotion stays cheap.** lockprobe does not depend on how it is launched, so moving it to its own KeepAlive label costs one plist plus one manifest row. The trigger is respawn lag over 60 s in shadow (§10).
- **Boot identity.** Every `(pid, lstart, boot)` record uses `kern.bootsessionuuid`, which is readable unprivileged (**C**, `sysctl` this run).
- **Single writer.** lockprobe holds `flock` on `lockwatch/.lease` for its whole life. The kernel drops the lock when the process dies, so no stale lease survives a crash or a reboot, and a second instance exits 0. The core owns the spawner's request pipe. A replacement spawner gets a new pipe, so an old spawner that wakes late reads EOF and exits.

**Invariants (every lane obeys them; tests pin them):**

| # | Rule | Why |
|---|---|---|
| I1 | No `#!` exec. Run scripts as `/bin/bash X.sh`, `/usr/bin/perl X.pl` or `$PY -I X.py` | lesson 1. 15.8.1 still leaks ~1.1 KiB per exec (**C** `prior-research.md` §2.6) |
| I2 | Every probe follows the same pattern: the **parent** owns the deadline; output goes to a **file** (never a pipe or `$(…)`); the parent never `waitpid`s past the deadline; the child calls `setsid()`; stdio are regular files. One outstanding instance per probe type. Mutexes and pidfiles hold `(pid, lstart, kern.bootsessionuuid)` in a boot-scoped dir, and a holder that fails any of the three is stale and broken (the `loop_owner_live` pattern, `compressor-sentinel.sh:1211`) | `mac-forensics.md` §2.4; `capacity-alarm.sh:2223-2230` |
| I3 | The lockprobe **core** may call only: `sysctlbyname` scalars, `host_processor_info`, `thread_info` on its own thread (band read-back), `mach_*_time`, `kill(2)`, `flock`, a non-blocking write to the spawner pipe, `waitpid(WNOHANG)`, read/`pwrite`/`rename` of regular files under `~/.claude/autonomy`, and `os.fork` to recreate the spawner (per-type cap 2). **No exec, no `/dev`, no `KERN_PROC_*`, no `proc_pidinfo`, no `mach_zone_info`.** Per-fd vnode calls (`PROC_PIDFDVNODEPATHINFO`, `vn_stat`→`DEVFS_LOCK`) run **only** in `fdscan` | R7. A blocked call in the core makes the watchdog a casualty |
| I4 | Nothing on a watchdog path uses: `ps` with `tt`/`tty`/`-M`/`-t`/`-T`, `ps` without `-x`/`-A`, multi-pid `-p a,b`, `lsof`, `ls /dev`, `pgrep` without `-a`, zsh, or `login` | `mac-forensics.md` §1, §8 (adv_cmds `ps.c:681-690`) |
| I5 | No StartInterval for anything that waits. KeepAlive loops only. No Background band and no Nice | lesson 2. `man launchd.plist`: a running job misses its interval firings (**C**) |
| I6 | Liveness means a lock or pid plus an increasing `seq` plus a `phase` written **before** each risky step. Output age never counts as liveness. lockprobe's freshness is `hb` (written every tick) within 10 s | lesson 5 |
| I7 | Every rule logs its fire rate. A rule over budget becomes `noisy` and is **removed from the level computation** (so from actuation and votes too) until it is re-fitted. Load per core, capacity-alarm `verdict` and coalition counts are never triggers | lesson 4 |
| I8 | Sleep and lid-close are excluded with `mach_continuous_time − mach_absolute_time`. Streaks reset across a stretched tick. Hammerspoon applies a 2 min post-wake grace (`hs.caffeinate.watcher`) | `watchdog-design.md` §4.2 |
| I9 | **No actor SIGKILLs a pty session leader by pid.** The only signal any lockwatch actor sends to a pty session is `kill -KILL -- -<pgid>` from `rescue.sh unpoison`, after it re-verifies the leader's `(pid, lstart, boot)`. Canaries are abandoned, never killed. Exception: probe and capture children that were `setsid`'d and opened any tty with `O_NOCTTY` (so have no ctty) may be SIGKILLed at their deadline | R3/R4, RCA-draft R3 |

---

## 3. Components

Each block lists: what it is → files → tests → rollout / rollback → sudo.

### C1. `lockprobe.py`: the sensing core, levels and the state contract (lane A)

- **Interpreter.** `$PY` is the first executable of: python.org 3.11, the Xcode 3.9 framework python, `/usr/bin/python3` (an xcrun shim, last resort). All candidates are Mach-O, so no `#!` exec (critique lens 1, checked with `file`). Stdlib only, 3.9 syntax.
  - A startup self-test checks the struct parsers against lockprobe's own pid, ppid, pgid and comm.
  - On mismatch it writes `state.verdict="blind"` and exits 3. A parse failure never reads as 0.
- **Core: one thread, 2 s tick, I3 calls only.**
  - It sets its own QoS to user-interactive, reads its band back every 60 s and publishes `band_pri`. `shadow-audit` refuses every `pass_*` until lockprobe **and** a capture child read PRI ≥ 31.
  - The oversleep (starvation) gauge lives in the core, which never touches `/dev`.
  - It writes `hb` every tick, and `state.json` every 5 s and on every change.
- **Spawner and probes.**
  - The spawner is forked once from the core. It runs each probe as a disposable `setsid` child with regular-file stdio.
  - One probe per type is outstanding at a time. A probe older than 3× its load-scaled p99 is `stuck:<type>`; that is itself a signal, and the probe is abandoned, never killed.
  - Per-type stuck caps: procscan 2, every other type 1.
  - The spawner's own `spawn_ms` is the exec-latency gauge.
- **tty history map.**
  - From each healthy procscan the core keeps `(pid, lstart) → {last non-NODEV tdev, pgid, ppid, sleader}`, and persists the map each minute to a boot-scoped `ttymap.json`.
  - An exiting leader reads NODEV (R13). The map is how its node, pgid and members still get named. In this incident 68298 held ttys063 from 03:03 to 03:48.
- **`ptycanary.py`.**
  - It creates the pty with `posix_openpt`/`grantpt`/`unlockpt`/`ptsname`, all ioctls.
  - It opens the slave itself with `O_RDWR|O_NOCTTY|O_NONBLOCK` and `dup2`s it onto fds 0/1/2 of `/bin/zsh -fc ': lockwatch-canary; exit'`. There is **no setsid and no TIOCSCTTY**, so the canary can never be a revoking leader.
  - The **master stays open for zsh's whole life**. zsh's `init_io` re-opens its tty by path, and a re-open after master close is exactly the 96296 carrier wait.
  - It closes with `O_NONBLOCK`: 3 ms instead of 600 ms (**C** `experiments.md` §2b). `PATH=/usr/bin:/bin`.
- **Outputs** (§5):
  - `state.json`, `hb`, `levels.jsonl`, `pty.json`, `ttymap.json` and `shadow-audit.json`.
  - `metrics-YYYYMMDD.jsonl` is the **one** 10 s series: ~2.6 MB/day, kept for the whole current boot plus 14 days (~36 MB). Its rows include `kitty_zombies`, the age of kitty's newest live child, `spawn_ms` and the top CPU rates.
  - `F_FULLFSYNC` on `levels.jsonl`, `state.json` and the bundle manifest, at level transitions only.
- **Exit.** On `getppid()==1` it writes `verdict="host_dead"` and exits. It restores its level from a same-boot `state.json` under 120 s old.
- **Files (new):** `scripts/lockwatch/{lockprobe.py, libproc_probe.py, rules.py, ptycanary.py, fdscan.py}`.
  - `libproc_probe.py` lifts its ctypes from `lr_recon/band.py:75-210`, `capacity-attrib.py:23-57` and the S07 offsets.
  - `kinfo_proc` arm64 offsets: ppid@560, pgid@564, e_tdev@572, uid@420 (**C** `mac-forensics.md` §4).
- **Tests:** `tests/lockprobe.bats`.
  1. A seam-injected bad offset → exit 3, `blind`.
  2. A probe that never replies → `stuck:<type>`, never two outstanding, per-type caps hold.
  3. High oversleep plus a slow canary → `unknown`, not a breach.
  4. **The core never touches `/dev` and never execs.** With `os.lstat`/`os.stat`/`open` on `/dev/*`, `os.ttyname`, `os.posix_spawn`, `subprocess` and `os.exec*` patched to raise inside the core module, ticks continue.
  5. `seq` strictly increases, `phase` precedes each step, renames are atomic. A second instance fails the lease and exits 0.
  6. **Positive control.**
     - Input: `ps-prereboot.txt` tables with `tdev=NODEV` on 68298, 94459, 95771 and 96296; a `ttymap` with 68298→ttys063; a walk canary `WEDGED last="lstat ttys063"`.
     - Expected: L2, `devfs_poison(ttys063)`, holder 96296, leader 68298, pgid 68298.
  7. **Negative control.** Replayed 10-10..10-24 inputs → 0 L2, and L1 on ≤ 2% of awake ticks.
  8. A canary pidfile from a previous boot, whose pid is now reused by a live process → no `WEDGED`.
  9. `getppid()==1` → exit.
- **Rollout:** the code lands inert, and the sentinel's spawn line starts it. **Rollback:** `CC_SENTINEL_LOCKPROBE=off`, or `git revert`. **Sudo:** none.

### C2. Sentinel: host, and guards on its existing actuator (lane B)

- **Spawn and respawn lockprobe.**
  - Each tick: `kill -0` plus a `(pid, lstart, boot)` check of lockprobe's pidfile.
  - Dead → respawn, at most once per 60 s. 5 deaths in 10 min → page `lockprobe-crashloop`.
  - No `seq` supervision and no replacement while lockprobe is alive: the lease forbids a second writer. A wedged lockprobe is Hammerspoon's dead-man page.
  - The row gains only `lp_pid`. lockprobe and its children are excluded from the compressor cohort.
- **No lockup actuator.** The tiered SIGSTOP actuator, its thaw, probation, L2b rung and H8 are cut (§12). `FROZEN_DB` gets no new kinds, so `release_frozen`/`kill_escalate` cannot meet lockup custody.
- **Guards on the existing compressor actuator.** Each closes a latent hazard the critique found.
  - **Capture never-list.** `capture.sh` writes each step's `(pid, lstart, boot)` to `~/.claude/autonomy/forensics/active.pids`. `select_stop_targets` (`:850`; it spares only argv matching `/claude/`, `:877`) and `kill_escalate` (`:1430`) skip the live entries. So a `sample` or `log collect` running against a 3.9 GB kitty is never frozen or killed.
  - **pty guard (R3).** `kill_escalate` never SIGKILLs a pty session leader or a pty master holder. It reads `pty.json` when that is fresh; otherwise it spares comm `expect|script|login|tmux|sshd`.
  - **Bounded forks.** `proc_stat_lstart` (`:1199-1201`, an unbounded `$()` per custody row per tick) and the census `ps` (`:750-760`, `:2153`) move to the I2 file-output runner. While `state.json` is fresh, the census reads procscan's table instead of forking `ps`.
- **Producer freshness via cc-fleet.**
  - Every 5 min the sentinel runs `/bin/bash bin/cc-fleet --json` detached, with a 60 s deadline, writing to a file that a later tick reads.
  - S4/S5 rows for `run` labels page once per label per episode when corroborated (lockprobe level ≥ 1, or ≥ 2 labels in S5), or uncorroborated after 30 min.
  - This replaces the hand-listed watchdog of watchdogs. A new sampler is covered by its manifest row (`bin/cc-fleet:31-34,88`).
- **Band.** The plist gains `ProcessType Interactive`, and the false comment at `:22-23` is corrected. The sentinel measures **PRI 20** (**C** F23). Applied by `migrations/0082-sentinel-interactive-band.sh` (c10; H7).
- **`bin/cc-reaper`.**
  - `GARBAGE_WL` (`:745`) gains `lockwatch|forensics|break-glass|devfs-canary`, and `orphan-zsh` (`:964`) honours `wl` as well.
  - `orphan-bash` (`:973`) selects exactly the 68298 shape. A candidate that is a pty session leader (pid == pgid, tdev major 16) is **skipped and paged** with the R17 command, never TERMed by pid. `ps -o pgid=,tdev=` is devname-safe.
- **Files:** `scripts/compressor-sentinel.sh`, `launchd/com.claude.compressor-sentinel.plist`, NEW `migrations/0079-…`, `bin/cc-reaper`.
- **Tests:** `tests/compressor-sentinel-lockup.bats`:
  - (a) Respawn is rate-limited, and the crashloop page fires.
  - (b) A `sample … -file ~/Library/Logs/cc-forensics/…` pid listed in `active.pids` is not selected.
  - (c) With `KILL=on`, an `expect` custody row and a pty-leader row both survive retrip-over-debt.
  - (d) With a stub `ps` that never returns, the tick still writes its row.
  - (e) A cc-fleet S5 fixture → one deduped page.
  - (f) The boot-class pointer is idempotent (C7).

  The existing `tests/compressor-sentinel.bats` stays green unmodified. `tests/cc-reaper.bats` gains a fixture pair per new `wl` token, plus a case where a pty-leader orphan is skipped and paged.
- **Rollout:** self-restart on land. **Rollback:** `CC_SENTINEL_LOCKPROBE=off`, `0079 --undo`, or `git revert`. **Sudo:** none.

### C3. Forensics: precursor snapshot, lockup capture, automatic diagnosis (lane A)

- **Promote the self-tested kit** from `solution/mac-forensics-kit/` to `scripts/forensics/{capture.sh, procscan.py, devfs-canary.pl}`.
  - Tiers 0–1 take < 0.4 s; the full kit takes 31–42 s and ~430 MB (**C** `mac-forensics.md` §4). Its WEDGED and sudo paths are unexercised.
  - **Drift fixes:**
    - **Locks.** Two locks become `(pid, lstart, boot)` records in a boot-scoped dir, and stale holders are broken. One is the bare-`mkdir` `.capture.lock` (`capture.sh:26-33`). The other is the canary pidfile, which only checks `kill(0,pid)` (`devfs-canary.pl:21-27`).
    - **Tiers.** Each tier gets its own mutex and rate key: snapshot 300 s, full 900 s. Until now `capture.sh:24,36-39` shared one of each. L2 and L3 pass `CC_FX_FORCE=1`. On rc 75, lockprobe retries every tick until the episode has a full bundle with `diagnosis.json`.
    - **I2.** kitty's pid is read from `02-procscan.out`, not from an unbounded `$(pgrep …)` in the parent (`capture.sh:87`).
    - **Sudo.** Steps call the H2 wrapper, `sudo -n /bin/bash /usr/local/libexec/cc-forensics-root.sh …`. The old call to `/usr/sbin/spindump` (`capture.sh:82-84`) is refused by H2's rule. Without H2 the manifest records `missing:H2`.
    - **I9.** Children are `setsid`'d and open any tty with `O_NOCTTY`. So the deadline SIGKILL (`capture.sh:59`, `devfs-canary.pl:58`) never hits a session that has a ctty.
    - Every step registers in `active.pids` (C2).
- **Precursor snapshot (L1, ~1 MB):**
  - `procscan --threads`, the canary verdicts, and `ps -axww -o pid,ppid,pgid,tdev,stat,lstart,…` (no `tt`).
  - `sample <pid> 2` of up to 4 pids. First come members of an exiting or orphaned pty leader's pgid. Then come the top claude/node processes by **current** CPU rate, taken from two procscans 2 s apart, not lifetime `cpu_s`.
  - `sample` names the syscall (`__open`) same-uid (**C** `mac-forensics.md` §0.3).
- **Lockup capture (L2, forced):**
  - `sample` of the stuck canary child, of the oldest stuck `ps`/`zsh`, and of kitty.
  - `log collect --last 30m` (root-free, **C**) and an index of DiagnosticReports.
  - spindump/tailspin through H2, else `missing:H2`. A second spindump at L3.
  - Retention: the last 3 bundles plus every non-OK one, capped at 3 GB.
- **Automatic diagnosis.** `scripts/lockwatch/diagnose.py` writes `DIAGNOSIS.md` and `diagnosis.json`. Each rule cites the evidence files it matched.

  | Signature | Verdict |
  |---|---|
  | walk canary `WEDGED last="lstat ttysNNN"` + a leader whose `ttymap` tdev is NNN, in `E` or orphaned (ppid 1) + a member of its **pgid** whose `sample` leaf is `__open` | **devfs_poison(ttysNNN)**: holder, leader, pgid, exiting-since, the R17 command, the cause |
  | stuck `ps`/`login` ≥ 5 with a ttyname-class leaf + starvation OK | **devfs_lookup_stall** (node unknown) |
  | kitty thread-0 CPU flat ≥ 60 s + sockets → 256 | **kitty_rc_deaf** (#10632 class) |
  | ≥ 10 claude at ≥ 10% CPU each, no transcript append for > 10 min (design values) | **idle_session_spin**, with their `sample` leaf frames |
  | canary slow in proportion to starvation, stuck census 0 | **cpu_starvation_31band** |
  | `stuck:procscan` while the walk canary and fdscan are healthy | **proc_table_stall** (R7) |
  | sentinel seg trip / kalloc slope | **compressor** / **kalloc** (existing owners) |

- **Cause attribution.** The RCA found the 03:48:58 kill only by a manual search of 397 files (`transcripts-fleet.md` §0.2). This automates it.
  - diagnose.py and boot_classify.py scan `~/.claude*/projects/**/*.jsonl` files modified within ±10 min of `exiting-since`. The scan is file-only, bounded at 60 s and 200 MB.
  - They look for Bash `tool_use` commands with `kill`/`pkill`/`killall` that name the leader, the holder or the pgid. They also read `kill-guard.jsonl` (C5).
  - Each hit adds session id, cwd and command to `evidence[]`.
- **Files (new):** `scripts/forensics/*`, `scripts/lockwatch/diagnose.py`.
- **Tests:** `tests/forensics-capture.bats`.
  - (a) A step past its deadline is `ABANDON`ed, and the run returns within deadline + 1 s.
  - (b) A PATH-stub recorder proves no banned I4 form is used.
  - (c) A lock from a previous boot is broken. A live, reused pid with a different lstart is not `WEDGED`.
  - (d) An L1 snapshot followed 20 s later by L2 still yields a full bundle.
  - (e) The stall seam `CC_FX_CANARY_STALL_AT=<name>` → `WEDGED_PREVIOUS last="lstat <name>"`, and no second child.
  - (f) diagnose.py over the NODEV fixture names ttys063, holder 96296 and leader 68298. Over a transcript fixture containing `kill -KILL 94459 68298` it adds the cause. A healthy fixture → `none`.
- **Rollout:** a dependency of C1. **Rollback:** `CC_FX=off`. **Sudo:** optional H1/H2.

### C4. Admission gate brownout, dispatcher backoff, RC circuit breaker (lane C)

- **`cc_brownout()`** in `scripts/lib/capacity-admit.sh`. It is called from `cc_capacity_admit` (`:1296`) right after token redemption and before the per-caller term switches (load block ~`:1406`), and from `capacity_gate()` in `handoff-fire.sh:11163` after the cloud branch. It runs **no `ps`, no `/dev` and no `kitty @`**. Votes:
  - **V1:** `state.json.level ≥ 1` and `hb` fresh within 10 s. A stale `hb` gives **no vote**; the dead-watchdog case pages through Hammerspoon (C5).
  - **V2:** fleet-governor's 2-of-3 over `tail -n 20 ~/.claude/logs/capacity-alarm.jsonl`: sessions ≥ 40, `coal_procs` ≥ 600, fewer than 10 rows in 900 s. Replay: 0–10% of normal-day rows, 56–60% on bad days, first fire 10-24 21:57Z (**C** replay; **L** thresholds, n=1).
  - **V3: dropped.** It was pure output age. capacity-alarm was stale > 600 s for 2.2 h on 10-10, 1.5 h on 10-12 and 25 min on 10-16, all non-lockup days (critique lens 1). A stuck alarm run is now cc-fleet's to report (C2).
  - **V4:** `~/.claude/autonomy/brownout.json.surface_unavailable_since` is under 30 min old. It is set by R2, or by the operator's chooser item "Brownout hold" with `by=operator`.
  - **V5:** `boot-<epoch>.json.class` is `LOCKUP_*` and uptime is under 30 min. boot-resume's fires are then spaced as recovery-class (below), so it does not rebuild the same 40-session fleet at once. The roster read itself is never delayed (C6).
- **Policy by caller class,** from a table in the library:
  - **Discretionary** (cc-dispatch, strand-fill, lr-move-*, lr-fleet, lr-reset-poller, named agent-tool, headless jobs) is **refused**. The refusal is not charged to `CC_ADMIT_BUDGET` and no `CC_ADMIT_*_TERM=off` can disable it.
  - **Recovery** gets at most 1 admit per 5 min while in brownout.
  - `--recycle` is exempt.
  - An operator-typed fire may override with `CC_ADMIT_BROWNOUT=off` for one fire.
  - Bound, per the file's own law (`capacity-admit.sh:31-35`): 30 min of continuous brownout turns into an **escalation page**, once per episode.
  - New `basis`/`term` value: `brownout`. Every decision logs its vote inputs so the term can be re-fitted.
- **R2.** handoff-fire's anchor-probe INCONCLUSIVE path (`handoff-fire.sh:20094-20101`, today plain rc 1) returns **76**. `bin/cc-dispatch` maps 76 to a pass-wide abstain with backoff 5→10→20→40 min, and writes the V4 latch.
- **R3.**
  - `scripts/dl-sweep.sh` runs `/bin/bash "$HOME/.claude/scripts/lib/capacity-admit.sh" --brownout-check discretionary || exit 75` before `claude -p`.
  - `classifier-warm.sh` runs under KeepAlive with ThrottleInterval 30 (`com.claude.research-classifier-warm.plist:22-23`). It must not `exit 75`, or launchd restarts it every 30 s. Instead it **sleeps in a 60 s loop** until the brownout clears.
  - `scripts/research-kit/classifier-warm.py` checks admission before **each** worker spawn, because the `serve` process spawns workers in-process after the exec.
- **RC circuit breaker: one detector, in `scripts/lib/kitty-queue.sh`.** That file already exists so that there is only one detector (`:8-10`), so no new library is added.
  - It gains `cc_kitty_rc_open`, a file read with no fork. It returns 0 when `state.json.kitty_rc=="dead"` and `hb` is fresh.
  - `kq_deaf` is widened to accept the same passive evidence: `kitty_rc=dead`, or `hb.kitty-ls.json` older than 2 heartbeat ticks. So boot-resume's deaf page (`boot-resume.sh:464-474`) and the breaker read one predicate.
  - lockprobe sets `dead` from passive evidence only: thread-0 CPU flat while sockets rise. Active probing would add peers.
  - `bin/it2-kitty` and handoff-fire's kitty calls fail fast with rc 75 and do **not** connect. Every abandoned client becomes a held peer toward PEER_LIMIT 256 (`prior-research.md` §2.5).
  - Model-authored loops are refused in `validate-bash.sh` (C5). Scripted callers beyond these two follow later (§10).
  - The unbounded `ps` at `kitty-queue.sh:52-58` is bounded per I2.
- **R5.** `launchd/com.chrisren.{autonomy-sweep,dl-sweep,cc-reaper}.plist` change from `/bin/zsh -lc` to `/bin/bash -c`. A mitigation tool must not depend on a login zsh. `migrations/0083-spawner-plists-bash.sh` (c10).
- **devname hazards in lane C's files:** handoff-fire's `ps -o tty= -p` sites (`:2151,2478,2496,2664,3186`) become `ps -o tdev=`, and its `ps -t` sites (`:4445,5528,7575,7976-8078,10030,13365`) become `ps -axo pid=,tdev=,tpgid=,comm= | awk` (`mac-forensics.md` §8).
- **Files:** `scripts/lib/capacity-admit.sh`, `scripts/handoff-fire.sh`, `bin/cc-dispatch`, `bin/it2-kitty`, `scripts/lib/kitty-queue.sh`, `scripts/dl-sweep.sh`, `scripts/research-kit/jobs/classifier-warm.sh`, `scripts/research-kit/classifier-warm.py`, the 3 plists, `migrations/0080-*`.
- **Tests:**
  - `tests/capacity-admit-brownout.bats`:
    - (a) the real 10-24/25 rows refuse from 21:57Z;
    - (b) the 10-15 and 10-23 rows refuse on 2% of rows or fewer;
    - (c) one mutant per input turns the replay red;
    - (d) immune to `CC_ADMIT_LOAD_TERM=off` and `CC_ADMIT_ACTIVE_TERM=off`;
    - (e) not budget-charged, so 10 consecutive refusals never become `budget-expired`;
    - (f) recovery admits are spaced 1 per 5 min;
    - (g) a stale `hb` gives no V1 vote;
    - (h) observe mode logs `would-refuse` and admits;
    - (i) under brownout, `classifier-warm.sh` sleeps and never exits 75, and `classifier-warm.py` spawns no worker.
  - `tests/cc-dispatch-surface-backoff.bats`: a stub fire returning 76 → the pass abstains, the backoff sequence runs, and it resets on the first success.
  - `tests/kitty-queue-breaker.bats`:
    - the dead state makes `it2-kitty` exit 75 without spawning `kitty @` (the PATH stub records zero calls);
    - a stale `hb` disarms the breaker;
    - `kq_deaf` returns DEAF on the passive fixture.
- **Rollout:**
  - `CC_ADMIT_BROWNOUT` defaults to `observe`. The term **auto-arms** when `shadow-audit.json.pass_gate=true`: at least 7 days of data, V1∨V2 true on ≤ 2% of awake ticks, `pass_band`, and the replay tests green.
  - R2, R3 and the breaker are armed on land, because they only stop futile work.
  - **Rollback:** `CC_ADMIT_BROWNOUT=off` (operator kill switch), `git revert`, or `0080 --undo`.
- **Sudo:** none.

### C5. Break-glass with no tty, and the Bash-hook guards (lane D)

- **Primary: Hammerspoon.** It is KeepAlive, PRI 37, and was alive 12:28–13:11 during the lockup (**C**).
  - **`hsc/breakglass.lua`** (from `break-glass.md` Appendix B). Only `hs.task` is used, never `hs.execute`/`io.popen`. ⌃⌥⌘⇧C runs a capture with no UI. ⌃⌥⌘⇧B opens a chooser:
    - Capture.
    - **Unpoison.** It shows `diagnosis.json`'s pgid, leader and holder; after a confirm it runs `rescue.sh unpoison <pgid> <leader_lstart>`.
    - **Brownout hold 60 min.** It writes the V4 latch with `by=operator`.
    - Open Rescue terminal.
    - Kernel stacks (GUI admin password).
    - Restart guidance. It runs the files-only roster (C6), then says to use Apple menu › Restart.
    - **Kill kitty** (confirm). Under a `devfs_*` verdict the dialog says: Unpoison first; killing kitty makes expect panes re-exec zsh into the same wait (RCA-draft §3.8); if Unpoison fails, use Apple menu › Restart.
    - Self-test.
    - There are **no Freeze/Thaw items**, so there is no third SIGSTOP actor and no second ledger.
  - **`hsc/lockwatch.lua`.**
    - A 15 s `hs.timer` reads `state.json`/`hb` with `io.open`, never a fork.
    - The menubar shows `OK / WATCH / DIAG / ESC / STALE` and `band_pri`.
    - **Dead-man page.** lockprobe's `hb` stale for more than 120 s, outside a 2 min post-wake grace (`hs.caffeinate.watcher`), sends Pushover through `hs.http.asyncPost`. It uses the same `~/.config/lr-page/pushover.env` credential. Sentinel row age is never read, because that row went over 120 s 40 times on 10-25 before onset (critique lens 1).
    - Sentinel death is caught by lockprobe (`getppid()==1` → `host_dead`).
    - There is no `hs.notify` for pages that lr-page already posts.
- **`scripts/break-glass/rescue.sh`** has modes `capture | unpoison | brownout | selftest`. Every step is detached and abandoned at its deadline. `capture` delegates to `capture.sh`.
  - **`unpoison <pgid> <leader_lstart>`** re-verifies the target with a fresh, bounded procscan:
    - the leader's `(pid, lstart, boot)` matches;
    - the leader is in `E` or orphaned (ppid 1) with a ttymap tdev of major 16;
    - at least one pgid member has an `__open` leaf or is still asleep.
  - It then runs `kill -KILL -- -<pgid>`, plus any descendant pgids that ttymap recorded, and logs to `lockwatch/actions.jsonl`. It re-runs both canaries and prints the result.
  - lockprobe calls the same mode at L2 when `CC_LOCKWATCH_UNPOISON=on`. The default is `observe`, which logs `WOULD`. One code path serves both callers.
- **Secondary: iTerm2 Dynamic Profile "Rescue"** (`config/iterm2/break-glass-rescue.json`).
  - It runs `/bin/bash --noprofile --rcfile …/rescue.bashrc -i` and never `/usr/bin/login`, which hangs in `ttyname` (17 `login` sleepers, **C**).
  - It is **non-default** and relies on `OpenNoWindowsAtStartup=1` (**C** `break-glass.md` §2 row 2).
  - `rescue.bashrc` shadows zsh, login, su, tty, less, screen, tmux, lsof and `ps` without `-x` with warnings, and sets `PAGER=cat`. It also warns on `pgrep -f claude`, `pkill -f claude` and `taskpolicy -b`, which match lockwatch and the sentinel too. It suggests the comm-exact `pkill -STOP -x 'claude(\.exe)?'` and `rescue.sh brownout` instead. The live comms are `claude` (28) and `claude.exe` (6) (**C**, `ps -axo comm=` this run).
- **Tertiary.** Activity Monitor (Sample, Force Quit, Spindump); the sysdiagnose chord ⌃⌥⌘⇧. (H4); **Apple menu › Restart, never the power button**, because it writes the `shutdown_stall` stackshot (**C**).
- **Guards in `hooks/validate-bash.sh`.** That hook is already registered for PreToolUse/Bash, so adding checks needs no settings change. The checks read files only.
  - (a) **RC refusal.** A command containing `kitten @` or `kitty @`, in any form or path, is refused while `kitty_rc=dead` and `hb` is fresh. The refusal message names the breaker. This catches the absolute-path `/goal` loop (R11).
  - (b) **Kill guard.** For `kill -9|-KILL <pid…>` and `pkill -9`, any pid that `pty.json` lists as a pty session leader is logged to `kill-guard.jsonl` (observe). The log entry suggests `kill -KILL -- -<pgid>`. Once `shadow-audit.pass_killguard` passes (7 days, the same gate as the brownout), the command is refused.
  - (c) **Goal-loop guard.** The 6th identical command from one session within 10 min, after 5 real failures, is refused with a stop message. Failures come from `log-bash.sh`'s real exit codes (`hooks/log-bash.sh:1-2`).
  - Kill switches: `CC_KITTY_RC_BREAKER=off` and `CC_KILLGUARD=off`.
- **Install, zero-human except one click.** `migrations/0081-break-glass-install.sh` is **mechanical**, because it touches no settings, plist or credential. It copies the profile JSON, creates the symlinks and runs `hs -t 5 -c 'hs.reload()'`. The registry line lands in `hammerspoon-config`. Only the TCC grant is human (H6).
- **Files:**
  - `scripts/break-glass/{rescue.sh,rescue.bashrc}`, `config/iterm2/break-glass-rescue.json` and `migrations/0081-…` (all new);
  - `hooks/validate-bash.sh`;
  - in the **separate repo** `~/Development/hammerspoon-config`: `hsc/{breakglass,lockwatch}.lua` and one `init.lua` registry line.
- **Tests:**
  - `tests/break-glass.bats`:
    - (a) capture summary fields are present and `progress` ends in `EXIT`;
    - (b) a `sleep 30` step with deadline 1 → `ABANDON` within 3 s;
    - (c) unpoison against a fixture whose leader lstart differs sends **no** signal; against a throwaway `setsid` sleep tree it kills the whole pgid;
    - (d) `rescue.bashrc` has no `\l` prompt escape.
  - `tests/validate-bash-lockwatch.bats`:
    - the absolute-path `kitten @ ls` is refused under fresh `dead` and allowed under a stale `hb`;
    - a leader kill-by-pid is logged in observe and refused when armed, and a pgid kill passes;
    - the goal-loop guard fires on the 6th failure.
  - Lua: a `pcall(require,"hsc.lockwatch")` compile check, plus the weekly idle self-test.
- **Rollback:** `0081 --undo`, delete the registry line, and the two kill switches. **Sudo:** none.

### C6. Recovery after a lockup (lane E)

- **Before the power-off (L3).**
  - lockprobe spawns `/bin/bash scripts/alarm-reboot-prep.sh --files-only` once per episode, detached, with a 60 s deadline. The chooser's "Restart guidance" runs it too.
  - The new mode writes `reboot-<date>.roster.json` from files only: `~/.claude*/sessions/*.json` (lost at this reboot, RCA-draft §9 item 13), the newest heartbeat dir's `hb.session.tsv`/`hb.kitty-ls.json`, and the tombstones.
  - It calls no `cc-sessions`, no `ps` and no `kitty @`.
- **At boot.**
  - boot-resume DETECT (`boot-resume.sh:599-603`) no longer treats a parsed-but-empty heartbeat roster as final in two cases: when `boot-<epoch>.json.class` is `LOCKUP_*`, or when that heartbeat's `hb.kitty-ls.json` was more than 2 ticks old at its last write. It falls through to the files-only roster, the tombstones and the registry (RCA-draft R16).
  - For one boot cycle after a `LOCKUP_*` boot, `worktree-gc-infra-run.sh` skips worktrees of sessions in the previous boot's roster or tombstone set.
- **Files:** `scripts/alarm-reboot-prep.sh`, `scripts/boot-resume.sh`, `scripts/worktree-gc-infra-run.sh`.
- **Tests:**
  - `tests/boot-resume-lockup.bats`:
    - an empty roster plus a `LOCKUP_DEVFS` fixture falls through to the files-only roster;
    - an empty roster on a `CLEAN` boot still ends the search.
  - `tests/alarm-reboot-prep-files-only.bats`: PATH stubs for `ps`/`cc-sessions`/`kitten` record zero calls.
  - `tests/worktree-gc-lockup-hold.bats`: a listed session's worktree survives one cycle.
- **Rollback:** `CC_BOOT_RESUME_LOCKUP_DISTRUST=off`, `CC_WTGC_LOCKUP_HOLD=off`. **Sudo:** none.

### C7. Post-boot crash/halt classifier (lanes A + B)

- **Step 0: preserve, then classify (lane A).**
  - `boot_classify.py` first copies three things into `~/Library/Logs/cc-forensics/<boot>-postboot/`:
    - the DiagnosticReports files whose mtime falls inside the window;
    - the last boot's `levels`, `metrics`, `ttymap` and `pty.json`;
    - a bounded `log collect --start <last good metrics row − 30 min> --end <shutdown>` (300 s deadline, `--size 1024m`; `log help collect` accepts only k/m, **C**).
  - It then classifies **from the copies**. The sentinel's own `panic_scan` stores only fields, and macOS rotates the source reports away. This RCA's evidence had to be copied by hand.
- **Logic (lane A):** `scripts/lockwatch/boot_classify.py`, a pure function over those copies. For the **previous** boot window it reads:
  1. `levels.jsonl` and the last `state.json`;
  2. bundles in `~/Library/Logs/cc-forensics/` and their `diagnosis.json`;
  3. the copied `DiagnosticReports/{shutdown_stall_*.shutdownStall, *.hang, *.panic, ResetCounter-*.diag}`. Binary reports are converted with `spindump -i <f> -o <tmp>` in a bounded child (60 s; root-free, **C**). Signatures are counted on **user** frames, which are stable across builds: `ttyname_r`/`devname`→`lstat`, `init_io→__open`, `spec_open`, `vn_revoke`;
  4. per-sampler last rows and staleness, which fixes the `dark_minutes 1.6` blind spot;
  5. a bounded `log show` count of kitty "Too many peers" over the window;
  6. `kern.shutdownreason`;
  7. the cause-attribution scan (C3).

  Output: `~/.claude/autonomy/lockwatch/boot-<epoch>.json` with `{class, confidence, first_signal_ts, evidence[], summary}`.
  - `class` ∈ `LOCKUP_DEVFS | LOCKUP_KITTY_RC | LOCKUP_UNKNOWN | STORM_COMPRESSOR | CLEAN`.
  - Panic boots stay with `panic_scan`, as the sentinel's rule against recording one death twice requires.
  - With no evidence the class is `LOCKUP_UNKNOWN` or `CLEAN`; it never fabricates a class.
- **Host (lane B):**
  - `compressor-sentinel.sh` spawns the classifier **detached** after `freeze_scan`. The existing rule "never let the post-mortem stop the sensor from starting" (`:1868`) is kept.
  - `freeze_scan`'s existing `freeze` row gains a `boot_class` pointer, `boot-<epoch>.json`, whose path is deterministic. No second row is written.
  - A later tick, within 5 min, writes **one** page, `pages/boot-class-<boot>.page`, through lr-page.
- **Tests:** `tests/boot-classify.bats`.
  - Fixture shutdown-stall excerpts (the login/ps/68298 blocks of `rca/shutdown_stall_2026-10-25.txt`) → `LOCKUP_DEVFS`, high confidence.
  - The 10-21 stall (no tty pattern) → `CLEAN`.
  - A `.panic` → no class (left to panic_scan).
  - Empty → `LOCKUP_UNKNOWN`, only when `kern.shutdownreason` is `force_off`.
  - The preserve step runs before classification, and a source report deleted after the copy still classifies.
  - A re-run → no second page; lane B's half is `compressor-sentinel-lockup.bats` (f).
- **Rollout:** active on the first boot after landing. **Rollback:** `CC_SENTINEL_BOOT_CLASSIFY=off`.
- **Sudo:** none. H3 (KDK) improves kernel names in evidence.

### C8. Remove hang points from existing instruments, plus a lint (lanes B + D)

- **Lane B:** `scripts/capacity-alarm.sh`.
  - The unbounded `ps … -p <pids> | cut | awk` at `:863-871` (`read_argv0`, the Likely 03:48 hang), `:939`, `:1014`, `:1049` and `:1746` become the `zone_bounded` file-output pattern (`:2223`) or the ps-free `capacity-attrib.py` path.
  - The `/dev/ttys[0-9][0-9][0-9]` glob at `:2018-2019` reads `state.json.ptys` (from fdscan) when fresh, otherwise a bounded child.
  - Tests: `tests/capacity-alarm-no-hang.bats`. A stub `ps` that sleeps forever → the tick still writes its row within its bound, with `argv_blind:true`.
- **Lane D:** devname-hazard fixes in `hooks/accounts-board.sh:139`, `hooks/lead-crash-watchdog.sh:1628,2275`, `hooks/teammate-auto-shutdown.sh:602`, `bin/dia-cdp-launch.sh:277` and `scripts/handoff-selfclose-e2e.sh:108,127`.
  - Add `scripts/devname-hazard-lint.sh`, wired into `scripts/ship-land.sh` beside `hook-shebang-lint` (`:3974-3990`), with a `--selftest`. It bans the I4 forms in `scripts/{lockwatch,forensics,break-glass}/`, `compressor-sentinel.sh`, `capacity-alarm.sh` and `hooks/`.
  - Tests: `tests/devname-hazard-lint.bats`. The selftest discriminates, each banned form is flagged, the fixed tree passes.
- **Retire** `~/incident-2026-10-25/monitor.sh` once lockprobe is live. It runs `ls /dev`, `lsof /dev/ptmx` and `top` every 30 s (`watchdog-design.md` §12). That is the operator's or incident session's stop (`CHANGELOG.md` 13:59:19), not a lane's.

---

## 4. Thresholds: 60% and 80% of measured ceilings, levels, hysteresis

- WATCH (L1) enters at 60% of the ceiling held for 2 consecutive probes.
- DIAGNOSE (L2) enters at 80% held for ≥ 30 s, or on a definitive binary signal. Row numbers P2, P9, P10 and P12 are retired (§12).
- Exit is below 40% for 3 consecutive probes (≥ 90 s).
- Every value is a tunable in `rules.py` and is logged per tick.

| # | Metric (source; I3 placement) | Ceiling (basis) | 60% → L1 | 80% → L2 | Healthy measured |
|---|---|---|---|---|---|
| P1 | fresh-pty `zsh -fc` (ptycanary) | 2.0 s user SLO to a shell (design value) | 1.2 s | 1.6 s; stuck ≥ 15 s with starvation OK → L2 | 8–14 ms **C** (F18) |
| P3 | `/dev` walk `scan_ms` (devfs-canary) | 250 ms (~180× healthy) | 150 ms | 200 ms; **WEDGED stuck_s ≥ 20 → L2** (definitive, `mac-forensics.md` §5; boot-scoped state) | 2–3.5 ms **C** |
| P4 | stuck `ps`/`login`/`zsh`/`ls`: age > 20 s × starvation ratio, no CPU delta over 2 procscans; `login` with no child | none; healthy 0 | ≥ 1 for 2 probes | ≥ 3 **and** the oldest one's `sample` leaf is ttyname-class (`devname_r`/`lstat`/`__open`). At load 624, every `ps` timed out at 42 s with no lockup (F4, F24) | 0 (**L**) |
| P5 | **`E` (P_WEXIT) persistent > 60 s** **and** a pty session leader per ttymap | 0.6 s worst healthy drain (**C** `experiments.md` §2b); multi-GB teardowns take longer | 1 → snapshot | only with P3 | 0 in 3 samples (**C**, load 76); plain `E` > 10 s is a metric only |
| P6 | **orphan pty session leader**: `EPROC_SLEADER && ppid==1 && e_tdev` major 16 (KERN_PROC only), with a pgid member whose `sample` leaf is `__open` for > 5 min | healthy 0 | 1 → snapshot + `WOULD unpoison` (shadow until its base rate is measured) | — | matches 68298 from ~03:03:28 (critique lens 1); base rate **S** |
| P7 | kitty RC sockets (procscan, `PROC_PIDLISTFDS` type socket; no vnode) | PEER_LIMIT 256 (**C** `prior-research.md` §0.1) | 154 | 205 | — |
| P8 | kitty thread-0 CPU flat while sockets grow | 60 s | 36 s | 48 s, then `kitty_rc=dead` | — |
| P11 | probe stuck age per type | 3× its own load-scaled p99 | — | `stuck:walk` or `stuck:fdscan` corroborate devfs; `stuck:procscan` → proc_table_stall | — |
| — | pty slots, own-uid procs, threads, files, vnodes (former P9/P10), `kitty_zombies`, `spawn_ms` | metrics columns only, until a recorded event reaches 40% of a ceiling | — | — | ptys 62–80 of 511; procs ~20% of maxprocperuid; vnodes 11–16% **C** |
| — | load, capacity-alarm verdict, coalition counts, sys%, sampler silence | **not triggers** (I7). Sampler silence pages separately through cc-fleet (C2) | — | — | forensics only |

| Level | Action | Exit |
|---|---|---|
| L1 WATCH | brownout V1 vote; precursor snapshot; canary cadence 10 s; menubar yellow; **no page** | L1-exit holds 90 s |
| L2 DIAGNOSE | forced full capture → diagnose → **one page through lr-page** (os + phone legs) carrying the verdict and the R17 runbook: the exact `rescue.sh unpoison <pgid> <lstart>`, and "do not kill the leader by pid or kill kitty". When armed, unpoison runs and both canaries re-run. Menubar red | canaries clean for 90 s |
| L3 ESCALATE | L2 for ≥ 10 min with a canary still stuck, or unpoison ran without recovery → second page, files-only roster (C6), second spindump (H2). Hammerspoon's dead-man page is the independent path | operator ack (trigger file), or L0 for 10 min |

- **Calibration (lesson 4):** 7 days of shadow mode.
  - Replaying the 10-10..10-24 inputs, every rule must give 0 L2 and L1 on ≤ 2% of awake ticks.
  - The positive-control fixtures must still reach L2.
  - A rule that busts its budget is marked `noisy` in `shadow-audit.json` and **leaves the level computation** until its threshold moves to the healthy p99.9 (I7).

---

## 5. Interface contracts (pinned here so the lanes can build in parallel)

| Artifact | Writer → readers | Contract |
|---|---|---|
| `~/.claude/autonomy/lockwatch/state.json` | lockprobe → gate, sentinel, it2-kitty, kitty-queue, validate-bash, Hammerspoon, capacity-alarm | Atomic rename, every 5 s and on every change. `{v:1, seq, pid, boot, ts, ttl_s:90, mode, level, level_since, verdict, reasons[], band_pri, kitty_rc:"ok"|"dead"|"unknown", canary:{zsh_ms,walk_ms,stuck_s,last_node}, stuck:{n,oldest_s}, probes_stuck:{type:n}, exiting[], orphan_leaders[], ptys, procs, threads, spawn_ms, cpu:{usr,sys,idle}, starvation_ms, unpoison:{mode,pgid,leader,lstart,would_ts,done_ts}, capture:{last_dir,last_ts,full_ok}}` |
| `…/lockwatch/hb` | lockprobe → gate, breaker, validate-bash, sentinel, Hammerspoon | 4 KiB pre-opened `pwrite` every tick: `seq phase phase_mono tick_end_mono pid boot`. **Fresh = written within 10 s** |
| `…/lockwatch/pty.json`, `…/lockwatch/run/<bootuuid>/ttymap.json` | lockprobe → sentinel, validate-bash, rescue.sh, diagnose | pty leaders `{pid,lstart,pgid,tdev,ppid,state}`, master holders, members in `__open`; the `(pid, lstart) → last tdev/pgid` map. Boot-scoped |
| `…/lockwatch/levels.jsonl`, `metrics-YYYYMMDD.jsonl`, `shadow-audit.json`, `boot-<epoch>.json`, `actions.jsonl`, `kill-guard.jsonl` | lockprobe / boot_classify / rescue.sh / validate-bash → sentinel, gate, classifier | Append-only JSONL with `ts` (Z) and `boot`. The audit carries `pass_gate`, `pass_killguard`, `pass_band` and per-rule `fires_24h`/`noisy` |
| `~/.claude/autonomy/forensics/active.pids` | capture.sh → sentinel | `pid lstart boot` per live step; the compressor actuator's never-list |
| `/bin/bash ~/.claude/scripts/forensics/capture.sh <tier> <reason>` | lockprobe, rescue.sh | Writes `~/Library/Logs/cc-forensics/<UTC>-<reason>/{steps.tsv, manifest.json, DIAGNOSIS.md, diagnosis.json}`. Per-tier `(pid, lstart, boot)` mutex and rate key; `CC_FX_FORCE=1` overrides the rate limit; rc 75 = busy or rate-limited, so retry |
| `/bin/bash ~/.claude/scripts/break-glass/rescue.sh unpoison <pgid> <lstart>` | lockprobe (armed), Hammerspoon | Re-verifies, then `kill -KILL -- -<pgid>`; rc 0 cured (canaries clean), 1 still stuck, 2 verification refused (no signal sent) |
| `~/.claude/autonomy/brownout.json` | cc-dispatch, rescue.sh → gate | `{surface_unavailable_since, by}` |
| exit codes | — | 75 = refused by brownout or breaker; 76 = surface unavailable |

---

> **Contract amendment (2026-10-25 16:24, lane A, from final RCA §1/R3/R6):** `rescue.sh unpoison <pgid> <lstart>` does NOT mean `kill -KILL -- -<pgid>`. It computes targets = ppid-descendants of the exiting leader ∪ pids with getsid==leader ∪ every pgid in that set (openers first); the exiting leader and proc_parent waiters are unkillable and are reported, not signalled. lane A emits `targets`/`unkillable` in diagnosis.json/pty.json; lane D recomputes when absent.

## 6. Lanes and file ownership (disjoint; each lane lands inert and the contracts in §5 join them)

| Lane | Owns (only these files) | Builds | Depends on |
|---|---|---|---|
| **A: probe, forensics, diagnosis** | NEW `scripts/lockwatch/{lockprobe.py, libproc_probe.py, rules.py, ptycanary.py, fdscan.py, diagnose.py, boot_classify.py}`, NEW `scripts/forensics/{capture.sh, procscan.py, devfs-canary.pl}`, NEW `tests/{lockprobe,forensics-capture,boot-classify}.bats`, NEW `tests/fixtures/lockwatch/**` | C1, C3, C7 logic | none (writes the §5 files) |
| **B: sentinel host and our own killers** | `scripts/compressor-sentinel.sh`, `launchd/com.claude.compressor-sentinel.plist`, NEW `migrations/0082-sentinel-interactive-band.sh`, `scripts/capacity-alarm.sh`, `bin/cc-reaper`, NEW `tests/{compressor-sentinel-lockup,capacity-alarm-no-hang}.bats`, `tests/cc-reaper.bats` (new cases only) | C2, the C7 host, C8 (alarm half) | §5 `pty.json`, `active.pids`, `boot-*.json` (fixtures; no code dependency on A) |
| **C: fleet governor** | `scripts/lib/capacity-admit.sh`, `scripts/handoff-fire.sh`, `bin/cc-dispatch`, `bin/it2-kitty`, `scripts/lib/kitty-queue.sh`, `scripts/dl-sweep.sh`, `scripts/research-kit/{jobs/classifier-warm.sh, classifier-warm.py}`, `launchd/com.chrisren.{autonomy-sweep,dl-sweep,cc-reaper}.plist`, NEW `migrations/0083-spawner-plists-bash.sh`, NEW `tests/{capacity-admit-brownout,cc-dispatch-surface-backoff,kitty-queue-breaker}.bats` | C4 | §5 `state.json`, `hb`, `boot-*.json` (fixtures) |
| **D: operator surface and Bash guards** | NEW `scripts/break-glass/{rescue.sh, rescue.bashrc}`, NEW `config/iterm2/break-glass-rescue.json`, NEW `migrations/0081-break-glass-install.sh` (mechanical), `hooks/validate-bash.sh`, `hooks/{accounts-board,lead-crash-watchdog,teammate-auto-shutdown}.sh`, `bin/dia-cdp-launch.sh`, `scripts/handoff-selfclose-e2e.sh`, NEW `scripts/devname-hazard-lint.sh`, `scripts/ship-land.sh` (one lint block), NEW `tests/{break-glass,validate-bash-lockwatch,devname-hazard-lint}.bats`; **separate repo** `~/Development/hammerspoon-config/{hsc/breakglass.lua, hsc/lockwatch.lua, init.lua}` | C5, C8 (sweep half) | §5 `capture.sh`, `rescue.sh unpoison`, `pty.json`, `kill-guard.jsonl`; unpoison's re-verify calls lane A's `procscan.py` by path |
| **E: recovery** | `scripts/alarm-reboot-prep.sh`, `scripts/boot-resume.sh`, `scripts/worktree-gc-infra-run.sh`, NEW `tests/{boot-resume-lockup,alarm-reboot-prep-files-only,worktree-gc-lockup-hold}.bats` | C6 | §5 `boot-<epoch>.json` (fixtures) |

- **Merge order:** A and B first, in either order: B's spawn line does nothing while `lockprobe.py` is absent. C, D and E can merge at any time.
- Migration numbers 0079, 0080 and 0081 are pre-assigned to avoid collisions. The last migration in the repo today is 0078 (**C**).
- **Rules every lane follows:**
  - Bash 3.2 for launchd paths (`.claude/rules` "Deployment interpreter ≠ yours").
  - Shellcheck bare, as the gate runs it.
  - Assert the `1..N` plan line before trusting a filtered bats run.
  - No `git stash`.

---

## 7. Rollout (zero human wherever repo policy allows) and master rollback

| Phase | What turns on | Human? |
|---|---|---|
Phases are ordered by how certain each part is (§12, lens 2).

| Phase | What turns on | Human? |
|---|---|---|
| 0 (today, parallel with coding) | **MUST:** H5 (credential), H7 (0079 and 0080). Then H6 (one click). Optional: H1–H4 | operator, ~10 min |
| 1 (on land; mechanism-independent) | lockprobe live: canaries, stuck census, capture, diagnosis with cause attribution, L2/L3 pages from definitive signals (P1/P3/P8/P11). Also: boot classifier with evidence preservation; recovery fixes (C6); RC breaker, `kitten @` refusal, goal-loop guard; R2/R3; sentinel/cc-reaper guards; hang-point fixes and lint; break-glass via mechanical 0081. Gate brownout and kill guard run in `observe`. Rules P4/P5/P6 are shadow | **none**: the sentinel self-restarts on new bytes, and mechanical migrations run at deploy |
| 2 (+7 days, automatic) | the brownout term (`pass_gate`), the kill-guard refusal (`pass_killguard`) and the shadow rules that pass their audit. Every pass also needs `pass_band` (PRI ≥ 31 read back) | none |
| 3 (RCA-gated, automatic on the artifact) | unpoison auto-run at L2 once the Q2 VM reproduction records that release works; P6 promoted to auto-unpoison of orphan sessions; devfs_poison tuned to RCA.md **[RCA-DEP]** | none beyond the RCA lane's reproduction |

**Master rollback (one line each):**
- `CC_SENTINEL_LOCKPROBE=off`
- `CC_LOCKWATCH_UNPOISON=off`
- `CC_ADMIT_BROWNOUT=off`
- `CC_KILLGUARD=off`
- `CC_KITTY_RC_BREAKER=off`
- `0079|0080|0081 --undo`
- the Hammerspoon registry line

Nothing in this design deletes data or kills processes on rollback.

---

> **Migration renumbering (2026-10-25 15:50, lane B):** trunk already had 0079/0080. Sentinel Interactive band = **0082**, spawner plists = **0083**, break-glass = 0081. Wherever this doc says 0079 (sentinel) or 0080 (spawner plists), read 0082 / 0083.

## 8. HUMAN-ACTIONS (exact commands; sudo only where marked)

- **H1 [sudo]: enable the tailspin ring buffer.** It is disabled today (**C** `tailspin info`), so neither the tailspin chord nor sysdiagnose can carry pre-trigger history.
  ```
  sudo tailspin enable && tailspin info        # undo: sudo tailspin disable
  ```
- **H2 [sudo]: a root-owned fixed-argument wrapper plus a NOPASSWD rule** (`mac-forensics.md` §7 H2, verbatim). `capture.sh` calls exactly this wrapper (C3); a direct `sudo -n /usr/sbin/spindump` would be refused by this rule.
  - Do **not** use `/usr/local/sbin`, which is world-writable (**C**).
  - **Reject** the broader `NOPASSWD: /usr/sbin/spindump, /usr/bin/tailspin` from `break-glass.md` §7: it allows arbitrary `-o` targets as root.

  ```
  sudo install -d -o root -g admin -m 0755 /Library/Logs/cc-forensics-root
  sudo tee /usr/local/libexec/cc-forensics-root.sh >/dev/null <<'EOF'
  set -u
  OUT=/Library/Logs/cc-forensics-root
  TS=$(/bin/date -u +%Y%m%dT%H%M%SZ)
  case "${1:-}" in
    spindump) /usr/sbin/spindump -notarget 3 10 -noProcessingWhileSampling -timelimit 80 -o "$OUT/$TS.spindump" ;;
    tailspin) /usr/bin/tailspin save -n -r cc-forensics "$OUT/$TS.tailspin" ;;
    *) exit 64 ;;
  esac
  /bin/chmod 0644 "$OUT/$TS".* 2>>"$OUT/wrapper.err"
  exit 0
  EOF
  sudo chown root:wheel /usr/local/libexec/cc-forensics-root.sh && sudo chmod 0755 /usr/local/libexec/cc-forensics-root.sh
  echo 'chrisren ALL=(root) NOPASSWD: /bin/bash /usr/local/libexec/cc-forensics-root.sh spindump, /bin/bash /usr/local/libexec/cc-forensics-root.sh tailspin' | sudo tee /etc/sudoers.d/cc-forensics >/dev/null
  sudo chmod 0440 /etc/sudoers.d/cc-forensics && sudo visudo -cf /etc/sudoers.d/cc-forensics
  sudo -n /bin/bash /usr/local/libexec/cc-forensics-root.sh spindump && ls -la /Library/Logs/cc-forensics-root   # test
  # undo: sudo rm /etc/sudoers.d/cc-forensics /usr/local/libexec/cc-forensics-root.sh
  ```

  - **Rejected alternative:** a root `WatchPaths` LaunchDaemon (`watchdog-design.md` §11). WatchPaths failed to fire for 20 s while fseventsd was livelocked on 2026-09-07 (`break-glass.md` §2 row 5), so it shares a failure mode with what it should capture.
- **H3 [sudo/GUI]: install the Kernel Debug Kit for 15.8.1 24H32** from https://developer.apple.com/download/all/. Availability is **S**. Then re-render:
  ```
  spindump -i /Library/Logs/DiagnosticReports/shutdown_stall_2026-10-25-131537_*.shutdownStall -o ~/stall-sym.txt
  ```
  This names the msleep sites in evidence. It **no longer gates** unpoison, because the source read settled `PCATCH` (R12); the Q2 VM reproduction gates it.
- **H4 [GUI, once while healthy]:** press ⌃⌥⌘⇧. (period) with Finder focused. Record whether a password was asked for and how long until `/private/var/tmp/sysdiagnose_*` appears. This turns the chord from **L** into **C**.
- **H5 [MUST, credential, no sudo]:** the Pushover token goes in `~/.config/lr-page/pushover.env` (read by `capacity-alarm.sh:2241-2244`, `lr-page.sh` and `lockwatch.lua`), or via `agent-secrets add`. Allow `api.pushover.net` in the egress allowlist if one is enforced. The directory is empty today (**C**). Without H5, every page is a Notification Center banner on a machine nobody may be watching.
- **H6 [GUI, one click]:** ⌃⌥⌘⇧B → "Open Rescue terminal" → allow "Hammerspoon wants to control iTerm2".
- **H7 [MUST, no sudo, c10]:** these lines put lockprobe and its captures in the Interactive band (`pass_band` stays false until they do).
  ```
  bash ~/Development/claude-infrastructure/migrations/0082-sentinel-interactive-band.sh --confirm launchd
  bash ~/Development/claude-infrastructure/migrations/0083-spawner-plists-bash.sh --confirm launchd
  ```

---

## 9. Replay: what this design would have done on 10-24/25 (all **L**; times CDT)

| Time | Evidence | Design reaction |
|---|---|---|
| 10-24 16:57 (21:57Z) | 2-of-3 alarm-row predicate true | V2 → brownout (refusing from phase 2). The 01:38 9-worker lr-move batch is refused |
| 03:03:28–03:03:43 | 68298 orphaned (ppid 1, ctty ttys063); 96296 enters `open()` | P6 candidate from KERN_PROC alone; ttymap records 68298→ttys063; pgid members sampled → `__open` |
| ~03:09 | persists > 5 min | L1 precursor snapshot and `WOULD unpoison pgid 68298`. With phase 3 armed, the pgid kill happens **before** any revoke: no poisoned node (**L**) |
| 03:36–03:45 | swap 1.85→6.3 GB, load ~1,000 | the sentinel's compressor axis (existing); the starvation gauge marks canary slowness `unknown` |
| 03:48:58 | t1-runner `kill -KILL 94459 68298` | kill guard logs leader 68298 and suggests `kill -KILL -- -68298`. With phase 2 armed, the command is **refused** |
| 03:48:58→ | 68298 exiting; its `e_tdev` now reads NODEV (R13) | P5 (E > 60 s, leader per ttymap) → snapshot at ~03:50 |
| ~03:49:30–03:50:00 | walk canary blocks on ttys063 | P3 WEDGED ≥ 20 s → **L2**. Forced capture (retried while the snapshot holds its own lock). `devfs_poison(ttys063)`: holder 96296, leader 68298, pgid 68298, cause = session `cc5a6d48`'s Bash command. Page at ~03:51 carrying `rescue.sh unpoison 68298 <lstart>` |
| ~03:52–03:58 | kitty main thread stops | P8 → `kitty_rc=dead`: breaker and `kitten @` refusal, so our callers add no held peers |
| ~04:01 | canaries still stuck | **L3**: second page, files-only roster, second spindump (with H2) |
| 04:09–04:48 | the compressor kill rung fired at 09:09Z/09:36Z/09:48Z (`own-instruments-sentinel-actions.txt`) | never-list and pty guard spare capture children, `expect` holders and pty leaders |
| 08:43–13:15 | dispatcher re-fires; `/goal` loop by absolute path | R2 backoff (69 fires → ~5); `validate-bash.sh` refuses all ~640 calls before any connect |
| next login | — | `boot_classify` preserves the stall report and the logs → `LOCKUP_DEVFS` with the cause; boot-resume uses the files-only roster; worktree-gc keeps the 11 worktrees |

That is a page carrying the cure command at ~03:51, against roughly 5.5–9 h before a human noticed. Once unpoison is armed, the box recovers without a reboot (**L**, pending Q2). Once the kill guard or the P6 precursor is armed, the node is never poisoned.

---

## 10. Depends on the RCA's final root cause, and deliberately out of these lanes

| Item | If the RCA confirms… | Then |
|---|---|---|
| unpoison auto-run at L2 | the Q2 VM reproduction shows that SIGKILL of the opener (or its pgid) releases the drain on 24H32 | flip the `CC_LOCKWATCH_UNPOISON` default to `on`. Otherwise it stays operator-invoked |
| P6 precursor → auto-unpoison of orphan sessions | the shadow base rate is ≤ 1 per week on normal days, and Q2 passes | promote P6; otherwise it stays a snapshot |
| devfs_poison rule tuning, P5 promotion | RCA.md's final chain | adjust signatures and thresholds |
| pty lifecycle R1–R5: `bin/cc-pane-verdict:135` blocking open, `bin/cc-pane-runner:292` trap inheritance, pty test drivers, kitty-restart re-exec | — | **RCA fix stream, not these lanes.** This design's RCA-independent overlap is the kill guard (C5) and the reaper/sentinel pty guards (C2). There is no shared bats teardown helper; the A1t test already kills by pgid (`tests/cc-pane-runner-hold.bats:63`, **C**) |
| kitty RC deafness (R6), kitty main thread on `/dev` (RCA-draft R13) | — | the kitty build/patch decision `891ea9e9d0f3` stays the operator's. The breaker contains the blast radius either way |
| scripted `kitten @` callers beyond it2-kitty and handoff-fire (~70 files) | — | phase-2 sweep onto `cc_kitty_rc_open` in `kitty-queue.sh`. Model-authored commands are already covered by `validate-bash.sh` |
| fleet-governor R4: move autonomous workers off kitty | — | **deferred structural mitigation.** It removes the failure domain shared with the operator's terminals (734 kitty descendants at the incident). Interim step: drop the expect relay in `lr-fire-resume` and `reso-resume-one`. Known gaps per `fleet-governor.md:177-187` |
| lockprobe as its own KeepAlive label | shadow shows respawn lag > 60 s | promote (one plist, one manifest row; c10) |
| OTel local sink (former C6) | 14 days of lockprobe shadow data show a kitty-stall case it missed | run it as a separate experiment per `otel.md`, with its own migration |

---

## 11. Alternatives rejected, and adversarial pass

**Rejected:**
- **Probes launched from the sentinel's bash tick** (`existing-instruments.md` G1, as hosted there). Its process model is adopted inside lockprobe: disposable, never-awaited children, one per type, where a stuck child's age is the signal. Hosting it in the tick is rejected. The tick had 9 gaps over 120 s per hour (max 277–380 s) at onset (R10), and every launch would cost bash forks during exec-latency spikes.
- **A Mach-RT core thread with persistent probers A/B and a sentinel `seq` supervisor.** Cut as over-built. A 2 s tick with no forks meets canary thresholds of 20–30 s. RT under a launchd Standard job is unmeasured; the band read-back and 0079 are the measured path.
- **The tiered SIGSTOP lockup actuator, L2b and H8.** Cut. Its benefit for this class was zero in replay. It shared `FROZEN_DB` with code that thaws and kills by row kind, and T1/T3 freezes could recreate the trigger (§12).
- **Break-glass Freeze/Thaw, the CC Capture applet, the GET 4318 page and ssh (H9).** Dropped as duplicate or low-yield paths.
- **OTel (the former C6 and its settings migration).** Moved out (§10). Number 0081 now belongs to the break-glass install.
- **A load or pty-count gate.** Rejected per `fleet-governor.md` §5 "Not recommended".
- **Shortcuts "Run Shell Script" as break-glass.** It is a security trade-off, and Hammerspoon covers the case (`break-glass.md` §2 row 4).
- **A WatchPaths root daemon.** Rejected per §8 H2.

**Adversarial pass (each item checked with a tool call):**
1. **"Is `KERN_PROC_ALL` core-safe?"** No: 20 `ps` were asleep in the kern_proc handler at 03:40 (`diag-reports.md` §3b). Only procscan calls it.
2. **"Is the sentinel tick really late?"** Partly. Counted again for this revision: the median gap was 16–17 s in 08–09Z, with 9 gaps over 120 s per hour. Lens 1's "150–380 s throughout" overstates the median but is right about the tail, and the tail is what matters to an actor.
3. **"Are all incident pids in one pgid?"** Yes: 68298, 94459, 95771, 96296 and 96310 all have pgid 68298 (`ps-prereboot.txt`). So `kill -KILL -- -68298` reaches the opener.
4. **"Can a canary poison a node itself?"** It has no setsid and no ctty, so its exit revokes nothing. Its master stays open, so zsh's re-open never meets a dead master, and it is never killed (I9).
5. **"Do new Bash guards need a settings change?"** No. `validate-bash.sh` is already registered for PreToolUse/Bash (`~/.claude/settings.json`), and failures reach `log-bash.sh` with real exit codes.

**Residual risks:**
- QoS self-promotion under a Standard job is unmeasured. `pass_band` refuses arming until a PRI ≥ 31 read-back, and 0079 is the certain fix.
- P5/P6 base rates and the brownout thresholds rest on a small n.
- The release by unpoison is **L** until Q2 runs.
- The capture kit's WEDGED and sudo paths are unexercised.
- The kill guard sees only agent-typed commands, not kills from inside scripts. C2 covers the two script killers we know of: cc-reaper and the sentinel's kill rung.

---

## 12. Critique resolution

Lens 1 = failure modes replayed against 10:15–13:15. Lens 2 = completeness and sprawl. **Accepted** = done as proposed. **Adapted** = the problem is fixed by another route. **Dissolved** = a cut removed the problem.

| # | Sev | Problem (short) | Disposition |
|---|---|---|---|
| 1.1 | blocker | Lockup rows in `FROZEN_DB` get thawed by `release_frozen` and SIGKILLed by `kill_escalate` | **Dissolved.** There is no lockup actuator and no break-glass freeze, so no non-compressor rows exist. The latent hazard (an `expect` master holder getting killed) is fixed by C2's pty guard and capture never-list, each with a bats case |
| 1.2 | blocker | The verdict and the cure join by ctty minor, but an exiting leader reads NODEV | **Accepted.** The join is by pgid plus the `(pid, lstart) → tdev` ttymap (R13, C1). The NODEV fixture must still name ttys063, holder 96296 and leader 68298 (C1 test 6, C3 test f) |
| 1.3 | major | Detects but cannot cure; L2b gated on the KDK | **Accepted.** `rescue.sh unpoison` with a chooser item, and the L2 page is the R17 runbook. Auto-run is gated on the Q2 VM reproduction, not the KDK. Kill kitty warns under a devfs verdict (C5, §4) |
| 1.4 | major | Capture lock and canary pidfile have no boot or liveness check | **Accepted.** `(pid, lstart, bootuuid)` in a boot-scoped dir, with stale holders broken (I2, C3), plus two tests |
| 1.5 | major | L1 snapshot blocks the L2 capture | **Accepted.** Per-tier mutex and rate key; `CC_FX_FORCE` at L2/L3; retry on 75 until a full bundle exists; plus a test |
| 1.6 | major | Core does pty, `ttyname` and `posix_spawn` | **Accepted.** The core makes no exec and no `/dev` call (I3). A forked spawner and disposable `ptycanary` handle them, the slave is passed by `dup2`, and the master is held for zsh's life. Patch-to-raise test (C1 test 4) |
| 1.7 | major | Vnode-fd calls in prober-A; P6 blind to the precursor | **Accepted.** Vnode calls run only in `fdscan`, whose wedge is itself a signal. P6 is the KERN_PROC-only orphan-leader rule plus `__open` > 5 min, in shadow (§4) |
| 1.8 | major | Rules fire on load, sleep or slow output | **Accepted.** Hammerspoon pages on `hb` only, behind a wake guard. P4 is starvation-scaled and needs a sample leaf. V3 is dropped. P5 is raised to 60 s with leader corroboration. Noisy rules leave the level machine (I7). Replay 10-10..10-24 must give ≤ 2% L1 (§4) |
| 1.9 | major | Bash tick runs minutes late; custody forks storm | **Adapted.** lockprobe is the sole lockup actor and the sentinel only respawns it. There are no custody rows to fork over. `proc_stat_lstart` and census `ps` are bounded, and `cc-fleet` runs every 5 min instead of `launchctl` per label. lockprobe gets **no** own label yet, because a plist is c10 (non-zero-human); the promotion trigger is in §10 |
| 1.10 | major | Compressor actuator can freeze or kill capture children | **Accepted.** The `active.pids` never-list is read by `select_stop_targets` and `kill_escalate`, with a fixture (C2) |
| 1.11 | major | T1/T3 freezes recreate the trigger and target the wrong pgid | **Dissolved** by cutting the actuator |
| 1.12 | major | The breaker misses the absolute-path `/goal` loop | **Accepted.** `validate-bash.sh` refuses `kitten @`/`kitty @` in any form while RC is dead, plus a goal-loop guard (C5) |
| 2.1 | major | No automatic mitigation for the observed class | **Accepted.** Kill guard (observe, then auto-arm), unpoison (operator now, automatic after Q2), and the P6 precursor (§0 items 5–6) |
| 2.2 | major | Diagnosis names no cause | **Accepted.** A bounded transcript scan plus `kill-guard.jsonl` add session, cwd and command to `evidence[]` (C3) |
| 2.3 | major | Recovery after the lockup is untouched | **Accepted.** New lane E (C6): files-only roster at L3, boot-resume distrusts an empty roster after a lockup boot, worktree-gc holds for one boot. V5 narrowed to pacing |
| 2.4 | major | Raw evidence not preserved at boot | **Accepted.** boot_classify step 0 copies reports, runs a bounded `log collect`, copies the series, then classifies from the copies (C7) |
| 2.5 | major | No notification reaches a person with zero human action | **Accepted.** H5 and H7 are phase-0 MUST (§0, §7). The break-glass install is a mechanical migration, so only the TCC click is human |
| 2.6 | major | The SIGSTOP actuator is the biggest mechanism with zero benefit | **Accepted.** Cut, together with the tiers, thaw, probation, L2b, H8 and test (b) |
| 2.7 | major | lockprobe tree over-built | **Adapted.** RT core, probers A/B, OTel prober, `seq` supervisor and replacement logic are cut, and G1's disposable-child model is adopted. Hosting in the bash tick is rejected on R10's measured tail (§11) |
| 2.8 | major | Second kitty-deaf detector | **Accepted.** `cc_kitty_rc_open` lives in `kitty-queue.sh`, and `kq_deaf` is widened, so there is one predicate. `kitty-rc-breaker.sh` is dropped (C4) |

**Minors, all accepted unless noted:**
- **Lens 1:**
  - The gauge moves to the core (never `/dev`), with per-type stuck caps.
  - Writer lease via `flock`, and the spawner pipe acts as the spawner's lease.
  - V1 and the breaker judge freshness on `hb` within 10 s, and `state.json` is written every 5 s.
  - cc-reaper: `wl` tokens, `orphan-zsh` honours `wl`, pty leaders are skipped and paged.
  - Capture kit drift: kitty pid read from procscan, sudo through the H2 wrapper, the I9 exception plus `O_NOCTTY`.
  - H7 is phase-0 MUST, and `pass_band` needs PRI ≥ 31.
  - classifier-warm sleeps in a loop, and the `.py` checks before each spawn.
  - rescue.bashrc warns on `pgrep -f claude`/`taskpolicy -b`, and the menubar shows `band_pri`.
- **Lens 2:**
  - Suspects ranked by current CPU rate, plus an `idle_session_spin` row.
  - `kitty_zombies` and newest-child age as metrics.
  - Metrics kept for the boot plus 14 days, with `F_FULLFSYNC` at transitions.
  - Fleet-governor R4 added to §10.
  - cc-fleet replaces the hand-listed watchdog of watchdogs.
  - Break-glass Freeze/Thaw dropped.
  - boot_classify writes a pointer on the `freeze` row instead of a second row, and panics stay with panic_scan.
  - `/dev` probes cut to the zsh and walk canaries; prober-B and the 5-min `zsh -i` trend probe dropped. `fdscan` is kept at 300 s as the only no-`/dev` source of master and holder state.
  - P9/P10 become metrics only.
  - OTel moved out.
  - One 10 s series and one notification path; applet, GET 4318 and H9 dropped.
  - Phases rebuilt by certainty (§7).
