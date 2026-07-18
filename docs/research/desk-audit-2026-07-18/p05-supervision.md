# P5 — Orchestrator-desk: supervision loops + session registry (the observability substrate)

Beat scope: what the desk can SEE about every session (registries + board/context) and what the four
supervisor/watchdog loops actually do. Ground truth = LIVE `~/.claude/settings.json`, `launchctl list`,
running procs, and on-disk state (read 2026-07-18 ~03:30 PDT), NOT install-time intent. Coverage: read the
full code of all 22 in-scope files + the telemetry spine (statusline.sh), the C10 activation bundle
(docs/activation/wiring-all.sh), both live settings.json, the live supervisor plist, and runtime state.

Goal legend: a = desk-sees-truth · b = FM1 (desk keeps purpose) · c = FM2 (working/waiting classified right).

## 1. Inventory

| Asset | Role in desk loop | Wiring | Depends on | Verified by | Goal | Gap |
|---|---|---|---|---|---|---|
| statusline.sh (spine) | Exports per-turn telemetry `/tmp/cc-telemetry/<sid>.json{ts,session_id,cwd,config_dir,model,effort,pid,window,used_pct}` | **hook-enforced** (`.statusLine.command`, both accts) | jq; ps ancestry walk | telemetry-e2e.sh; 111 live files | a,c | spine for everything; not in P5 scope but load-bearing |
| hooks/session-register.sh | Writes cc-registry `<paneUUID>.json{paneUUID,name,cwd,account,pid,startedAt,session_id}` (comms/addressing) | **hook** SessionStart (both) | jq; $ITERM_SESSION_ID; ps walk | session-registry.bats; 81 live | a,c | — |
| hooks/session-deregister.sh | Removes pane's cc-registry row on SessionEnd | **DEAD (unwired)** — absent from both SessionEnd arrays | jq; $ITERM_SESSION_ID | bats green but hook not installed | a | G-P5-5 |
| bin/cc-sessions | Lister/addressing view of cc-registry; lazy stale-sweep (dead pid / gone pane), 24h dead-row retention | **manual/prompt** CLI; cc-notify consumer | cc-registry; it2 session list | session-registry.bats | a,c | — |
| hooks/live-session-registry.sh | Worktree-GC liveness registry `~/.reso/live-sessions/<wt-base>`=`pid\tsid\tcwd`, scope `~/Development/.worktrees/*` | **hook** SessionStart+SessionEnd (both) | ps walk; kill -0 | (reaper-side) 5 live | a,c | consumed by reaper beat |
| bin/cc-board | "Single pane of glass": telemetry × claude-accounts quota × registry-absence join; states OK/DUE/LIMIT/DEAD/STALL?/STALE + DIED-UNRENDERED/NO-RENDER? | **manual/prompt** (`watch -n5 cc-board`) | telemetry; claude-accounts; cc-registry | (none — no bats) | a,b,c | G-P5-9 |
| bin/cc-context | Self/peer context-fill read; own age+quota fuse; on-read telemetry sweep (reaps provably-dead after 6h) | **manual/prompt** CLI | telemetry; claude-accounts | (none — no bats) | a,c | sole reaper of dead telemetry |
| scripts/lead-supervisor.sh | **THE live watcher**: 30s telemetry sweep → PAGE (DEAD/STALL?/PAST-THRESHOLD) + effect-reobserve (S-3b) + heartbeat | **launchd** com.claude.lead-supervisor (PID 17867, up 3d) | telemetry; kill -0; git/mtime; teammate-checkpoint.sh | supervisor-e2e.sh (8 cases) | a,b,c | G-P5-1,2,6,7 |
| scripts/lead-deathwatch.sh | L1 event-instant death (kqueue) → capture orphan-WIP ref + PAGE (never respawn); own heartbeat | **NOT RUNNING** — no plist loaded; heartbeat 4d stale | bin/cc-deathwatch-kqueue; P8 watch-list | selftest 7/7; lead-deathwatch.bats | c | G-P5-4 |
| scripts/lead-reconciler.sh | L4 three-way roster anti-entropy (tasks×registry×disk); persistent divergence → PAGE; own heartbeat | **NOT RUNNING + NOT INVOKED** — no plist, supervisor sweep doesn't call it; heartbeat MISSING | cc-registry; deathwatch records; harness task reader | selftest 5/5; lead-reconciler.bats | c | G-P5-3 |
| hooks/lead-crash-watchdog.sh | Per-session detached daemon; on LEAD crash with active TEAM → shutdown_request to teammates + CRASH_REPORT.md + macOS notify | **hook** SessionStart (both), spawns nohup daemon | team config.json leadSessionId; kill -0 | (none — no bats) | c | G-P5-8 |
| hooks/session-index-start.sh | Crash-safe stub row in sqlite index on SessionStart | **hook** SessionStart (both) | session-index-helpers.sh; sqlite | (via sweep) | a | history layer |
| hooks/session-index-end.sh | Full session index on SessionEnd (summary/prompt/files/cmds) | **hook** SessionEnd (both) | helpers; transcript; sessions-index.json | (indirect) | a | history layer |
| hooks/session-index-sweep.sh | Catches sessions missed by SessionEnd; upserts changed transcripts | **launchd** com.claude.session-search-sweep (~60s) | helpers; sqlite | DB live 47MB, mtime seconds-fresh | a | history layer, LIVE |
| hooks/session-save-id.sh | Writes `.last-session` / `.last-session-id` for resume | **hook** SessionEnd (both) | jq | (none) | b | — |
| hooks/session-end.sh | Session-end log + stale claude-version GC | **hook** SessionEnd (both) | — | (none) | — | tangential |
| hooks/session-start.sh | MCP-status log + additionalContext + backup prune | **hook** SessionStart (both) | claude mcp list | (none) | — | tangential |
| scripts/supervisor-e2e.sh | Regression gate for the supervisor (8 cases incl S-3b VOID/ESCALATE) | **manual/gate** (`lead-supervisor --selftest` execs it) | git; a live pid | self (green) | — | gate |
| scripts/session-lifecycle-safety-gate.sh | Un-hold bar for AUTONOMOUS REAPING (CL classifier/RP reaper/TD actuator) | **manual/gate** | bin/cc-classify,cc-reaper,cc-teardown | reports NOT-BUILT for CL/RP | c | reaper machinery unbuilt (adjacent beat) |
| tests/{session-registry,lead-deathwatch,lead-reconciler}.bats | Regression suites | **manual/gate** (bats) | — | green | — | — |
| docs/D2-RUNTIME-ACTIVATION.md | C10 runbook: boundary hook + supervisor activation | doc | — | — | — | says boundary hook INERT (no gate-green marker-writer) |

## 2. Mechanism (end-to-end, file:line)

### 2a. Three distinct registries + telemetry (NOT one registry — this is the crux)
1. **cc-registry** (comms/addressing) — `$HOME/.claude/cc-registry/<paneUUID>.json`, FIXED $HOME/.claude (cross-account),
   keyed by **paneUUID**. Schema `{paneUUID,name,cwd,account,pid,startedAt,session_id}` (session-register.sh:75-81).
   `session_id` is the P8 JOIN KEY added so cc-board can notice a registered-but-never-rendered pane (register.sh:47-52).
   Written on SessionStart (register.sh:89, hard 3s timeout, always exit 0). Removed on SessionEnd ONLY via
   session-deregister.sh — **which is unwired** (§3 G-P5-5); actual cleanup is cc-sessions' lazy stale-sweep
   (cc-sessions.sh:82-103): dead pid (kill -0) OR gone pane (it2 list) → **hidden from addressing but RETAINED 24h**
   for forensics (P8 "presence must not encode liveness", cc-sessions.sh:62-77), then age-reaped.
2. **live-sessions** (worktree-GC) — `$HOME/.reso/live-sessions/<wt-basename>` = `pid\tsid\tcwd`
   (live-session-registry.sh:55), scope `~/Development/.worktrees/*` only (:26-29). Positive durable liveness for
   the reaper (kill -0), because cwd/lsof scans are flaky (:5-10). Wired SessionStart+SessionEnd; SessionEnd removes
   only if sid matches (:33-38) — the race-guard that makes in-place handoff safe (below).
3. **session-index** (history/search) — sqlite `$HOME/.claude/session-index.db` (LIVE 47MB, mtime fresh). Stub on
   SessionStart (session-index-start.sh:58-75), full on SessionEnd (session-index-end.sh:94-111), sweep-daemon
   catches misses (session-index-sweep.sh). Source-priority: sessions-index>sweep>session-start.
4. **telemetry** (live liveness+context spine) — `/tmp/cc-telemetry/<sid>.json`, keyed by **session_id**, written by
   statusline.sh:57-95 each turn boundary. `pid` = real claude ancestor (memoized; reuse-if-alive else ps-walk,
   statusline.sh:73-81). ATOMIC (.tmp+rename :82-91). This is the ONLY per-turn liveness clock.

### 2b. In-place /handoff correctness (KEY QUESTION 1) — VERDICT: registry stays correct
Same pane, NEW sessionId, NEW claude pid. (i) cc-registry is pane-keyed → the successor's SessionStart OVERWRITES
`<pane>.json` with the new sid+pid (register.sh:81), and now carries session_id so readers join on sessionId per the
desk memory (cc-notify-session-pane-mapping.md) — CORRECT. (ii) live-sessions dereg is sid-guarded
(live-session-registry.sh:36-37): the predecessor's SessionEnd won't delete a row already rewritten by the successor
(sid mismatch) — no clobber race. (iii) telemetry (sid-keyed) transiently shows the predecessor sid as DEAD (dead pid)
until cc-context's 6h sweep reaps it — a real dead process, not a bug. Residual: because session-deregister is unwired,
a CLEAN-exited predecessor lingers as a retained-dead cc-registry row for 24h (self-heals; §3 G-P5-5).

### 2c. The four loops — trigger / cadence / detection / action
- **lead-supervisor (LIVE, the workhorse)**: launchd KeepAlive daemon, `--daemon` loop `sleep 30` (SWEEP=30,
  supervisor.sh:34,173). Per sweep, assess() every telemetry row (supervisor.sh:126-154): DEAD = `pid && !kill -0`
  → checkpoint_preserve + PAGE (never respawn, :136-137); STALL? = alive + age≥1800s → PAGE candidate + resolve_page
  (:142-144); PAST-THRESHOLD = used≥73 ∧ age<1800 (B-1, the case the Stop-hook is blind to, :148-149); else OK →
  clear_page. S-3b (:96-113): at a 900s page deadline, reobserve_effects (new commits OR file mtimes, :74-93) — fresh
  ⇒ VOID, dark ⇒ ESCALATE; **disposition never reached from silence alone** (the §3h near-miss law). Heartbeat every
  sweep to IDL (:54-57). Only operator-facing acts = PAGE + safe git checkpoint; bash physically cannot close a live
  pane (ruling #1, :4-8). Running since Jul-14 19:56, matches last commit (Jul-14 17:50) → no drift.
- **lead-deathwatch L1 (NOT RUNNING)**: designed as launchd `--watch` over a P8-registry-derived watch-list
  (wiring-all.sh:121). kqueue EVFILT_PROC/NOTE_EXIT via bin/cc-deathwatch-kqueue → instant DEATH → capture_orphan_wip
  (git plumbing ref `refs/deathwatch/…`, deathwatch.sh:59-84) BEFORE page (L1-b), then PAGE, no respawn (:87-93).
  {pid,start} recycle guard + ESRCH (:189-203). Own heartbeat (:96-101). **Inert**: no plist loaded, heartbeat.json
  mtime Jul-14 (4d stale). So instant-death detection is off; deaths caught only by the supervisor's 30s poll.
- **lead-reconciler L4 (NOT RUNNING + NOT INVOKED)**: `--once` reconcile of 3 rosters keyed by pid — A=harness tasks
  (**empty default**, operator must wire, reconciler.sh:50-55), B=cc-registry kill-0 (:56-65), C=deathwatch disk
  records (:66-75). Persistent pairwise divergence past 60s grace → PAGE naming the pair (:92-111). Own heartbeat.
  **Inert**: no plist; the live supervisor sweep does NOT call it (grep-confirmed); reconciler/heartbeat.json MISSING.
  wiring-all.sh:124 intends it to run FROM the supervisor sweep, un-actioned.
- **lead-crash-watchdog (LIVE, teammate-scope only)**: SessionStart hook spawns a detached daemon polling the LEAD pid
  every 30s (watchdog.sh:60-70). On crash, scans team config.json across 3 config dirs for leadSessionId==sid
  (:83-95); if a TEAM is owned → shutdown_request into each teammate inbox + CRASH_REPORT.md + osascript notify
  (:105-113). Protects Agent-Team teammates from an orphaned lead; does NOT cover a desk-spawned SOLO session's death
  (that is L1/supervisor's job). Non-persistent (nohup subshell, not launchd): 114 .pid markers, 77 stale.

## 3. Gaps & fragilities

| id | file:line | FM | sev | failure scenario | fix sketch |
|---|---|---|---|---|---|
| G-P5-1 | com.claude.lead-supervisor.plist `CC_PAGE_TO=""` + supervisor.sh:61-70 | FM2 | **P1** | Supervisor DETECTS DEAD/STALL?/ESCALATE/PAST-THRESHOLD but delivers to nobody: no cc-notify (CC_PAGE_TO empty), output = IDL lines + 181 unread `.page` files. Desk learns only if it manually tails IDL. The high-value S-3b ESCALATE + B-1 advice are supervisor-only (not on cc-board) → silently lost. | set CC_PAGE_TO=$(cat ~/.claude/cc-roles/desk) in plist env + kickstart; or a page→desk relay that reads pages dir |
| G-P5-2 | supervisor.sh sweep():156-168 vs cc-board:70-96 | FM2/24x7 | **P1** | The one always-running detector is BLIND to spawn-death: sweep() iterates only telemetry files, so a session that died before its first statusline render has no file → never assessed. The registry×telemetry join that catches DIED-UNRENDERED/NO-RENDER? exists ONLY in cc-board (a manual poll). D8-trigger-1 spawn death is invisible to automation. | port cc-board's P8 registry-join loop into the supervisor sweep |
| G-P5-3 | lead-reconciler.sh (no plist; supervisor doesn't call) | FM2 | **P1** | L4 built+tested but dead in runtime: heartbeat MISSING, nothing invokes it. The exact incident it exists for — harness task-table lists a dead teammate (tasks×registry divergence) — is currently UNWATCHED. Naive activation also mis-fires: roster_tasks empty + roster_disk depends on the also-down L1. | wire `reconciler --once` into supervisor sweep with a real roster_tasks reader, AFTER L1 runs |
| G-P5-4 | lead-deathwatch.sh (no plist; heartbeat 4d stale) | FM2 | **P1** | L1 instant-death CAPTURE+PAGE is inert; out-of-band session/teammate deaths caught only by the 30s telemetry poll (slower; blind to never-rendered). Its heartbeat-absence alarm is moot (the reconciler that would read it is also down). | load com.chrisren.lead-deathwatch.plist `--watch` on the P8 watch-list |
| G-P5-6 | ~/.claude/autonomy/idl.jsonl (no rotation) | 24x7 | **P1** | IDL unbounded: 114 MB / 570K lines, ~28 MB/day, no rotation. Driven by the supervisor RE-paging + RE-checkpointing the SAME dead telemetry rows every 30s (169 page+164 checkpoint per 400 lines) until cc-context's on-read 6h sweep reaps them — but the daemon never runs that sweep. Days-long autonomy bloats disk + slows every jq/tail consumer. | dedupe (page/checkpoint a DEAD sid once, marker like resolve_page); add rotation; supervisor self-reaps dead telemetry |
| G-P5-5 | session-deregister.sh — absent from both SessionEnd arrays | FM2-minor | **P2** | Code+bats exist but hook not installed. Clean-exited sessions never remove their cc-registry row; rely on cc-sessions lazy sweep → linger as retained-dead 24h. Self-heals, but dead-wired machinery + longer-lived ghosts. | add to SessionEnd in settings-templates + live settings, or delete if intentionally superseded by P8 age-retention |
| G-P5-7 | supervisor.sh clear_page:153 | 24x7 | **P2** | 181 `.page` files accumulate: clear_page fires only on the OK path, but a DEAD sid's telemetry file is deleted while still DEAD → never transitions to OK → its `.page` never clears. | clear_page when the sid's telemetry file disappears; age-reap pages dir |
| G-P5-8 | lead-crash-watchdog.sh:48-114 | FM2-minor | **P2** | Detached daemons don't survive reboot (not launchd); 77/114 .pid markers stale, no reaper. Also scope = Agent-TEAM leads only (:83-95); a desk-spawned solo session death isn't its concern (must be L1/supervisor). | startup reaper for stale watchdog markers; document the solo-session gap |
| G-P5-9 | bin/cc-board | FM2 | **P2** | Partial pane of glass: joins telemetry×quota×registry-absence but NOT supervisor findings (STALL?/ESCALATE/PAST-THRESHOLD live only in IDL) nor deathwatch/reconciler state. Operator must watch board AND IDL. Pull-only. | add a recent-IDL/escalation summary row to cc-board |

## 4. Task candidates

| id | action | acceptance | depends-on |
|---|---|---|---|
| T-P5-1 | Set CC_PAGE_TO=cc-roles/desk in supervisor plist + `launchctl kickstart -k` | a synthetic DEAD row produces a cc-notify page in the desk JSONL | G-P5-1 |
| T-P5-2 | Port cc-board's P8 registry×telemetry join into supervisor sweep() | a registered-but-never-rendered fixture yields a DIED-UNRENDERED page from the daemon | G-P5-2 |
| T-P5-4 | Load com.chrisren.lead-deathwatch.plist `--watch` on a P8-registry watch-list | deathwatch/heartbeat.json refreshes each cycle; a killed watched pid → instant DEATH capture+page | G-P5-4 |
| T-P5-3 | Invoke `lead-reconciler --once` from supervisor sweep with a real roster_tasks reader | reconciler heartbeat refreshes; a tasks×registry divergence pages once past grace | T-P5-4 |
| T-P5-5 | Dedupe supervisor DEAD paging/checkpoint (once per sid) + IDL rotation + self-reap dead telemetry | IDL steady-state ≈ heartbeat-only; idl.jsonl rotates at a size cap; pages dir bounded | G-P5-6,7 |
| T-P5-6 | Wire session-deregister.sh on SessionEnd (or remove the script) | a clean SessionEnd removes the pane's cc-registry row immediately | G-P5-5 |
| T-P5-7 | Reboot-startup reaper for stale ~/.claude/watchdog/*.{pid,id} | markers whose lead pid is dead are swept on boot | G-P5-8 |
| T-P5-8 | Add an IDL/escalation summary line to cc-board | one screen shows both detection (states) and delivery (recent pages/escalations) | G-P5-9 |

## 5. Cross-beat dependencies
- **statusline/handoff beat OWNS the telemetry spine** (statusline.sh). The ENTIRE live-supervision substrate
  (cc-board, cc-context, supervisor sweep, cc-board DEAD/STALL?) depends on it. If the per-turn export breaks, the
  whole substrate goes dark SILENTLY (no telemetry files = ABSENT, and absence is silent). Highest cross-beat risk.
- **comms beat (cc-notify / it2)** is the page DELIVERY leg (CC_PAGE_TO) AND cc-sessions addressing. FM2 delivery
  (G-P5-1) depends on it. Desk memory (cc-notify-session-pane-mapping.md): resolve pane by sessionId, not name/age.
- **reaper beat (cc-reaper / worktree-gc / session-lifecycle-safety-gate)** consumes live-session-registry.sh + the
  classifier; its reap decisions ride this beat's liveness signals. Gate reports CL/RP NOT-BUILT.
- **quota beat (claude-accounts)** feeds cc-board/cc-context quota columns; a stale/absent feed degrades to "?".
- **Agent-Teams beat** owns the team config.json that lead-crash-watchdog reads (leadSessionId).

## 6. Adversarial self-pass (hostile reviewer — then covered)
- "Supervisor running stale code?" — No: PID 17867 start Jul-14 19:56 > last commit Jul-14 17:50; KeepAlive + 3d
  uptime = current. Covered.
- "Is DEAD trustworthy or does pid drift?" — statusline.sh:65-81 walks to the real claude ancestor + memoizes;
  cc-board:44-48 uses \037 IFS to stop an empty config_dir shifting a path into $pid (false DEAD). Sound.
- "Does anyone consume supervisor pages?" — No (G-P5-1): CC_PAGE_TO empty, 181 unread .page, no consumer. THE FM2 gap.
- "Is the always-on daemon blind to spawn-death?" — Yes (G-P5-2): sweep is telemetry-only; the registry-join is
  cc-board-only (manual). Automation can't see a never-rendered death.
- "Is session-deregister-unwired a bug or deliberate?" — Ambiguous; ranked P2 either way because cc-sessions
  self-heals + P8 retention is age-based. Not overstated.
- "Reconciler/deathwatch — maybe they ARE wired elsewhere?" — Checked launchctl, ps, all plists, grep of the live
  daemon: neither runs, neither is invoked. Heartbeats MISSING/4d-stale confirm.

## 7. Uncertainties
- Did NOT run cc-board/cc-context live (avoided slow claude-accounts calls); confirmed data sources populated
  (111 telemetry, 81 registry, DB fresh) + read all code paths.
- session-search-sweep exact StartInterval unread (plutil returned empty for both live+repo plist); relied on the
  script's own "every 60s" doc + DB mtime seconds-fresh + launchctl status 0.
- Whether session-deregister-unwired is a deliberate P8-era drop vs a regression — git blame on settings-templates
  would decide; severity is P2 regardless.
- 77 stale watchdog markers inferred to be reboot-orphaned; did not confirm last boot time.
- lead-deathwatch's kqueue helper (bin/cc-deathwatch-kqueue) not read (out of the 22-file scope); L1 behavior taken
  from the orchestrator + its selftest, which drive a real child through the helper.
