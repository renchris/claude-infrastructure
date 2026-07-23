<!-- source: /Users/chrisren/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/e77e2802-d1d2-4c79-8905-ebbb87a81977.jsonl
 turns=64 assistant_texts=7 last_stop=end_turn mail_injections=['SCOPE UPDATE'] -->

Saturated. Final resolutions: dispatcher stdout **empty** (loaded, never observed firing this boot); discovery log **shows active candidate-feed output** (functional when it fires); idl seal-chain has **no scheduler and rotation ignores it entirely** → tamper-evidence is dormant, not a live-firing break. Predict-next-call test now fails (further plist/script reads yield predictable structure, answer-invariant). Composing.

Adversarial pass integrated below (3 gaps checked: dispatcher execution-health, seal-chain scheduling, session-end sweep effectiveness — each shifted a verdict).

---

# Daemon / Background-Process Layer Audit — claude-infrastructure

**Basis**: live `launchctl list`/`print`, `ps aux`, plist + script reads, frontier write-up `docs/research/handoff-memory-review-2026-07-22.md` §Part 7 (on branch `feat/handoff-memory-review`). Timestamped ~01:55 Jul 23; machine re-bootstrapped ~00:35 Jul 23 (LaunchAgents mtimes).

**Top-line corrections to prior memory** (both stale):
- `desk-autonomy-dormancy-staged-not-loaded.md`: dispatcher **and** discovery are now **loaded** (`launchctl list` + plist domain), not "BUILT but INERT / never launchctl-loaded." Dispatcher = LOADED-IDLE (runs=0, empty log); discovery = LOADED and **has fired** (`/tmp/claude-discovery.stdout.log`: "[plan-open] fired: added 3 of 4 candidate(s)").
- Frontier finding "`rotate-autonomy-logs.sh` has zero callers" is **fixed** — it's now wired to `com.claude.log-rotation` (hourly); a rotation ran Jul 23 00:35 (`idl.jsonl.20260723T073520Z.gz`). But this *created* a sharper live defect (seal-chain break, §c-3).

---

## (a) Process census

**States**: RUNNING = executing/persistent-alive · LOADED-IDLE = registered, awaiting trigger, not executing · STAGED-INERT = script on disk, never loaded · STALE = alive but obsolete/wedged.

### launchd jobs (core CC autonomy)

| Unit | Kind / trigger | State | Double-instance guard | Watcher-of-it |
|---|---|---|---|---|
| `com.claude.lead-supervisor` | launchd KeepAlive+RunAtLoad (persistent) | **RUNNING** pid 57651, **runs=9, last-exit −9 (SIGKILL)**, pid churned mid-audit (67327→57651) | launchd label only — **no in-script flock/pgrep** | launchd KeepAlive (hard-death only) |
| `com.claude.caffeinate-floor` | launchd KeepAlive+RunAtLoad | **RUNNING** pid 64234 (`caffeinate -i -s`) | launchd label | launchd KeepAlive ✓ (healthy) |
| `com.chrisren.cc-reaper` | launchd StartInterval 300s | **RUNNING** every 5m, runs=950 | **NONE** (grep: no flock/pgrep/LOCK) | launchd re-fire |
| `com.claude.discovery` | launchd StartInterval 3600s, RunAtLoad=false | **LOADED-ACTIVE** (log shows candidate feed; `print` runs=0 — see uncertainty) | launchd label | launchd |
| `com.claude.dispatcher` | launchd StartInterval 900s, RunAtLoad=false | **LOADED-IDLE** (runs=0, stdout+stderr empty — not observed firing this boot) | launchd label | launchd |
| `com.chrisren.autonomy-sweep` | launchd StartInterval 300s | LOADED-IDLE (runs=0) | launchd label | launchd |
| `com.claude.desk-invariant` | launchd StartInterval+RunAtLoad | **RUNNING** runs=1 | launchd label | launchd — *watches desk **sessions**, not daemons* |
| `com.claude.team-orphan-reaper` | launchd StartInterval+RunAtLoad | LOADED-IDLE (exit 0) | launchd label | launchd |
| `com.claude.boot-resume` | launchd RunAtLoad@login + StartInterval 300 retry | LOADED-IDLE (exit 0) | launchd label | launchd |
| `com.claude.power-policy-verify` | launchd RunAtLoad + StartInterval 3600 | LOADED-IDLE (exit 0) | launchd label | *defers own liveness to caffeinate-floor KeepAlive (per its plist comment)* |
| `com.claude.log-rotation` | launchd StartInterval 3600s | LOADED-IDLE (produced Jul 23 gz) | launchd label | launchd |
| `com.chrisren.screenshot-clipboard` | launchd watcher | LOADED (exit 0) | launchd label | launchd (benign, non-core) |
| `com.chrisren.watch-claude-code-2118-hold` | launchd | LOADED, **last-exit = 1 (nonzero)** | launchd label | launchd — minor anomaly, likely obsolete version-hold |
| `session-search-{sweep,backfill}`, `nightly-regression`, `verify-2114-archive`, `restic-claude-archive` | launchd periodic | LOADED-IDLE (exit 0) | launchd label | launchd (peripheral) |
| `com.reso.*`, `gl.reso.*` (8 jobs) | launchd | out of scope (different project) | — | — |

### hook-spawned & session-spawned (NOT visible to launchd)

| Unit | Kind | State | Double-instance guard | Watcher-of-it |
|---|---|---|---|---|
| `lead-crash-watchdog.sh` daemon | **hook** (SessionStart), per-session, `setsid+nohup+disown` | **RUNNING ×21 live** + **83 stale pidfiles** (oldest daemon Jul 15, 8d) | **NONE** — source-blind, no per-sid spawn lock (`lead-crash-watchdog.sh:95-101`) | **NONE for the daemon** — self-exits on pid-death, but pid-recycle → immortal; `session-end.sh` reaps only the *pidfile* |
| `caffeinate -i -t 300` | **session** (CC per-turn) | RUNNING ×15 | n/a — self-expire 300s | self (timeout) — benign |
| handoff watchers (`__selfclose`≤180s, `__recycle`≤600s, `cc-await-ping`≤1800s) | session (per-fire) | none live now | self-terminating (doc A3, verified) | self (bounded timeout) ✓ |

**Watchdog dir live counts**: 104 `.pid` + 104 `.id` + **1985 `cp-*.count`** = 2193 files. Live-pid 21 / stale-pid 83. cp-counts grew **1941→1985 (+44 in ~1 day)** vs the doc's snapshot — net-growth continues.

---

## (b) Lifecycle gap list

1. **Watchdog daemon has no reaper for the *process*.** Exit conditions are (i) pidfile gone or (ii) `kill -0 pid` fails (`lead-crash-watchdog.sh:114-121`). Bare pid, **no starttime/generation check** → once the OS recycles a dead lead's pid to any new process, `kill -0` succeeds forever and the daemon is pinned. `session-end.sh` reaps the *pidfile* on clean exit but cannot kill the already-detached daemon. **Empirical**: 21 live daemons, oldest Jul 15.
2. **`session-end.sh` backlog sweep present but not draining.** Lines 41-58 background (`( … ) & disown`) a correct dead-pid reap on every clean exit, yet **83 stale pidfiles are unchanged from the Jul-22 measurement**. Likely mechanism: the backgrounded sweep races the `/exit` process-group SIGKILL and dies before finishing the O(104) loop; and crash-wave exits skip SessionEnd entirely (no reap runs). Cleanup is coupled to the dying process it must outlive.
3. **No consumer for the supervisor's own heartbeat.** `lead-supervisor.sh:20-22` (S-4) declares "the watcher's heartbeat is an outcome record; its ABSENCE is the alarm" — but **grep finds no reader** of heartbeat-freshness anywhere in bin/scripts/hooks. launchd KeepAlive restarts on *process death* only; a **wedged-but-alive** or stale-code supervisor is undetected. runs=9 + last-exit SIGKILL + pid churn = the memory's "went stale, fired zombie pages until reloaded" class, resolved only by **manual** bootout/bootstrap.
4. **`cc-reaper` has no single-instance lock.** No flock/pgrep (`bin/cc-reaper` grep empty). launchd single-fires the label, but a second invoker (2 PIDs observed at one instant: 10056 @01:52 + 96967 @01:49) or a >300s sweep can overlap. *Uncertainty: both PIDs exited before I could confirm parent/child overlap — no lock is grep-certain; live overlap is suggestive not conclusive.*
5. **Activation doesn't survive reboot.** Dispatcher/discovery/autonomy-sweep are `RunAtLoad=false`; the `.done` markers (Jul 19-20) assert activation but `print` shows runs=0 today → a reboot with no re-bootstrap leaves them registered-but-cold. **The `.done` marker is a claim about the past, not current liveness** (the effect-read-predicate lesson, live).
6. **`caffeinate -i -t 300` swarm (×15)** is session-scoped and self-expiring — expected, but no registry ties them to their sessions, so an orphaned one is indistinguishable from a live one until it self-expires.

---

## (c) Deadlock / stacking / arming findings — status

| # | Finding (frontier §Part 7) | Mechanism | Live status |
|---|---|---|---|
| c-1 | **Watchdog daemon stacking** | SessionStart is source-blind + spawn-unguarded → `/clear`//compact//resume stack N daemons per sid; all N fire on death → N duplicate crash rows + **N racing jq inbox rewrites = lost shutdown-message races** | **OPEN.** Doc: 3262 spawns vs 3098 sids. Live: 21 concurrent, no spawn guard in current `lead-crash-watchdog.sh`. |
| c-2 | **Subagent false-crashes** | Agents run the full watchdog at SessionStart but never fire SessionEnd → each completing subagent leaves a pidfile → false CRASH + Basso (the 16-cluster) | **OPEN.** No `--agent-id`/`isSidechain` guard in the live hook. |
| c-3 | **idl seal-chain vs rotation** | `cc-idl` seal-chain is append-only/monotonic; rotation truncates sealed records → `verify` reports tamper | **EVOLVED → LATENT.** Rotation is **now wired** (`log-rotation`, hourly, ran Jul 23 00:35). Chain **frozen Jul 19 01:55**; **no scheduled seal** (grep empty) and **rotation does not re-epoch the chain** (grep empty). Tamper-evidence is *dormant* (no live `verify` consumer) but **provably void** if resumed. |
| c-4 | **cc-reaper no single-instance lock** | concurrent sweeps race shared reap state | **OPEN** (grep-confirmed no lock; 2 PIDs observed). |
| c-5 | **rm-race cross-incarnation disarm** | `handle_crash` deleted a pidfile a successor now owns → disarms a live session (125 proven) | **FIXED (live)** — `lead-crash-watchdog.sh:188,205` guards "only rm if pidfile still holds our pid." |
| c-6 | **`/clear` flips team-orphan-reaper to lead-dead** | pidfile removal on `/clear` (process survives) archives a live team | **FIXED (live)** — `session-end.sh:27` skips removal on `reason=clear`. |
| c-7 | **93% false LEAD-CRASH floor** | no SessionEnd removed the pidfile | **FIXED (live)** — `session-end.sh:28-30` reaps on clean exit. |
| c-8 | session-index O(size²) 60s re-parse; `refs/checkpoints` unbounded (1842); SessionStart mailbox-drain context-spike | assorted | **OPEN** (not re-verified this pass — flagged, out of deep scope). |

Empirical-vs-doc: c-1/c-2/c-4 I confirm the *shape* live (no guards in current code + 21 daemons + 2 reaper PIDs) but the *magnitudes* (3262v3098, 125 disarms) are the doc's, not re-measured here.

---

## (d) Registered-state absorption map + launchd-underuse

**What already exists**: `cc-registry/` holds **70 session records** `{paneUUID, name, cwd, account, pid, startedAt, session_id}` (`session-register.sh:75-78`) — a working proof-of-concept that **already carries `startedAt` (a generation field)**. The supervisor *uses* a generation check (`OWNER_PAT` + `GC_S`, `lead-supervisor.sh:42-43`) to defeat pid-recycle. **The watchdog does not** — same repo, same lesson, un-applied.

**A unified `{label, pid, role, generation, heartbeat, TTL, owner}` registry + one reconciler would dissolve**:

| Failure mode | How the registry kills it |
|---|---|
| Watchdog pid-recycle immortality (§b-1) | generation (starttime) mismatch → reconciler retires the daemon |
| Watchdog stacking (§c-1) | role/label single-instance at register time |
| 83 stale pidfiles (§b-2) | reconciler GCs by dead-generation, **session-independent** (not coupled to a dying exit) |
| cc-reaper concurrent sweep (§c-4) | role-lock in the registry |
| Supervisor wedge-undetected (§b-3) | heartbeat field + reconciler pages on staleness — the missing consumer |
| N-racing crash rows (§c-1) | single registered crash-writer per sid |

**launchd already gives for free — and the scripts correctly *don't* re-implement (for launchd jobs)**: duplicate-label prevention, `KeepAlive` (restart-on-death), `ThrottleInterval` (restart backoff), `RunAtLoad`, `StartInterval`. **So the registry is only needed for the ~36 non-launchd processes** (21 watchdogs + 15 caffeinate + handoff watchers) that launchd never sees. The registered-state campaign should scope to the **hook/session-spawned tier only** — re-registering launchd's 15 jobs would duplicate what launchd authoritatively owns.

**launchd underused where hand-rolled**:
- `lead-crash-watchdog.sh` = `setsid+nohup+disown` per session with **no** label-singleton, **no** generation, **no** KeepAlive-equivalent reaper. It's session-scoped so a launchd *label* doesn't fit, but its **backlog reap belongs on a launchd StartInterval** (session-independent), not on `session-end.sh` (couples cleanup to the dying process — §b-2).
- `cc-reaper`'s second (non-launchd) invocation path bypasses launchd's same-label single-fire — routing *all* reaps through the one launchd label would give the mutex for free.

---

## (e) Candidate frontier problems

**CANDIDATE 1 — Watchdog identity-without-generation (pid-recycle immortality + source-blind stacking)**
- **Evidence**: `lead-crash-watchdog.sh:117` bare `kill -0 "$pid"` (no starttime); `:95-101` source-blind spawn, no per-sid lock; live 21 daemons + 83 stale pidfiles, oldest Jul 15; frontier §Part7 "3262 spawns vs 3098 sids."
- **Mechanism class**: ABA / identity-without-generation on a raw OS pid.
- **Mitigations + status**: rm-race guard FIXED (`:188,205`); session-end pidfile reap FIXED but backlog **not draining** (83 stable); stacking + subagent-arming OPEN.
- **Why it resists**: the fix is a cross-cutting identity **contract** (pid+starttime+role) every consumer must adopt — the supervisor already did, the watchdog+reaper haven't; a point patch to one leaves the class alive.
- **Cost**: unmeasured — N-duplicate crash rows + N racing `jq` inbox rewrites (lost shutdown messages) on a real team-lead crash. **Measure**: count duplicate-sid rows in `claude-crashes.jsonl`; count daemons whose watched pid's starttime ≠ recorded.
- **Frontier sketch**: the registered-generation contract (§d) scoped to the non-launchd tier; watchdog registers `{sid, pid, starttime, role}`, exits on generation-mismatch, single-instance per role.
- **Confidence**: HIGH / stale-risk LOW.

**CANDIDATE 2 — The who-watches-the-watcher chain terminates at launchd (liveness ≠ correctness)**
- **Evidence**: `lead-supervisor.sh:20-22` asserts "heartbeat absence is the alarm" but **grep finds no reader**; supervisor runs=9, last-exit −9, pid churned mid-audit; memory "went stale, fired zombie pages until reloaded."
- **Mechanism class**: KeepAlive detects *process death*, never *alive-but-wrong* (stale code / wedged loop).
- **Mitigations + status**: launchd KeepAlive (hard-death only); manual bootout/bootstrap for staleness. OPEN.
- **Why it resists**: a heartbeat-freshness auditor is itself a watcher needing a watcher — infinite regress terminates only at launchd, which is *semantically blind*. Needs a mutual-heartbeat lattice, not one more daemon.
- **Cost**: unmeasured zombie-page windows (the paged-desk gets spurious/absent pages until a human reloads). **Measure**: gap-detect on `idl.jsonl` `kind:heartbeat` timestamps per actor.
- **Frontier sketch**: a launchd StartInterval "heartbeat auditor" that pages on any registered daemon's heartbeat-gap > TTL, cross-checking peers so no single reader is trusted; version-stamp heartbeats to catch stale code.
- **Confidence**: MED-HIGH / stale-risk LOW.

**CANDIDATE 3 — Rotation and seal-chain are two correct subsystems with an unowned interface**
- **Evidence**: chain frozen Jul 19 01:55; `log-rotation` wired + ran Jul 23 00:35; **no scheduled `cc-idl seal`** and **rotation does not re-epoch** (both greps empty); `cc-idl:13-16` chain is append-only/monotonic, truncation ⇒ tamper report.
- **Mechanism class**: unowned seam between two independently-landed features (integration debt).
- **Mitigations + status**: none — the two shipped separately. LATENT (dormant tamper-evidence, no live `verify` consumer) but **provably void** on resume.
- **Why it resists**: rotation must *become* a seal-chain epoch operation (seal → archive sealed prefix → genesis-from-sealed-head) — a protocol change, not a flag; and someone must *own* running `verify`.
- **Cost**: the tamper-evidence guarantee is silently absent. **Measure**: `cc-idl verify` today (expect truncation report).
- **Frontier sketch**: rotation-as-epoch + a scheduled seal + a verify consumer; or retire the chain if tamper-evidence isn't a live requirement.
- **Confidence**: MED (latent) / stale-risk MED (dormant feature — may be intentionally abandoned).

**CANDIDATE 4 — Cleanup coupled to the process it must outlive**
- **Evidence**: `session-end.sh:41-58` backgrounds the backlog reap with `( … ) & disown`; 83 stale pidfiles unchanged Jul22→Jul23; crash-wave exits skip SessionEnd entirely.
- **Mechanism class**: a GC that runs *inside* the dying session races the `/exit` group-SIGKILL and dies before completing; and the no-SessionEnd death path (crash/OOM/kill) runs it *never*.
- **Mitigations + status**: the reap exists and is liveness/age-gated; ineffective in practice. OPEN.
- **Why it resists**: correctness requires the reaper to be *session-independent* — the same reason `cc-reaper` is launchd-based (its own plist comment: "a hook dies with its session and cannot run when NO session is alive — exactly when an orphaned pane needs reaping").
- **Cost**: 2193 watchdog-dir files (1985 cp-counts) accumulating; inode/dir-entry growth, not RSS. **Measure**: `ls ~/.claude/watchdog | wc -l` trend.
- **Frontier sketch**: move watchdog-dir backlog GC into `cc-reaper` (already launchd, session-independent, quadruple-gated) or a dedicated StartInterval sweep; fold into Candidate 1's reconciler.
- **Confidence**: MED-HIGH / stale-risk LOW.

---

### Blockers / uncertainties (explicit)
- **dispatcher/discovery runs=0 vs discovery-log-has-output**: `launchctl print` reported runs=0 for both, yet discovery's stdout shows real candidate additions. Either the `print` read was momentary/stale or the log predates a reload. Net claim (defensible): both **loaded**; discovery **has produced output**; dispatcher **not observed executing this boot**. Not resolved to a single reads-count.
- **cc-reaper concurrency**: no-lock is grep-certain; the 2-PID overlap is a one-instant snapshot (both exited before re-inspection) — suggestive, not a captured concurrent-overlap.
- **supervisor restart cadence**: runs 8→9 + pid churn during the audit window; can't distinguish a genuine crash-loop from a coincidental periodic reload — reported as "≈9 restarts since load, SIGKILL last-exit."
- **Not re-verified this pass** (flagged, deep-scope-deferred): frontier §c-8 (session-index O(size²), `refs/checkpoints` 1842 unbounded, mailbox context-spike-at-birth). `com.chrisren.watch-claude-code-2118-hold` last-exit=1 (nonzero) — minor, likely obsolete.
- **Empirical vs doc**: live-measured = 21 daemons, 83 stale pidfiles, 1985 cp-counts, chain-Jul19-vs-idl-Jul23, no-lock greps, empty heartbeat-reader grep, dispatcher-empty-log. Doc-sourced (not re-measured) = 3262v3098 stacking, 125 rm-race disarms, 93% false-crash floor.