# Memory-economy ground-up re-architecture — 15-axis wave verdict (2026-08-10)

**Scope (frozen):** deep-research investigation of claude-infrastructure identifying what can be
ground-up improved and re-architected to eliminate tech debt and streamline memory utilization,
addressing the bottleneck limiting ~15 concurrent Claude Code + claude-infrastructure + Kitty
sessions on the fixed M1 Max 64GB 10-core MacBook Pro — explicitly including pollers/watchers/
cron/schedulers, worktree lifecycle without event-driven cleanup, and git maintenance/hooks —
**plus the operator's standing widener**: *"we are relying on you to exhaustively explore our
blind spots of topics of investigation not said where you have high signal for."* Deliverable =
this doc + 15 per-axis artifacts; implementation is FILED (landing map §8), not executed here.

**Position in the program.** This is the successor to `scaling-bottlenecks-2026-08-09.md`
(13-axis wave, landed `90880b95`, ~14h before this one) — NOT a rival. Its findings land as
**master-program M3 detail** (`BACKLOG_CONSOLIDATION_2026-08-09.md:149-161`, "The fleet bounds its
own footprint", in flight) and as input to GROUND_UP map rows 6 (guardrail/hook layer) and 11
(worktree & warm-pool). Where this wave re-measured the prior wave's ground, the result is marked
CONFIRMS or CORRECTS; everything else is delta. Method note that governs every number here:
**`phys_footprint`, never `ps` RSS** (RSS overstates a CC session 1.6-2.8×, understates kitty
~10×, and inflates fleet sums 2.34× via shared pages — axis A §0, axis N §1, axis H §1).

---

## 1 · The verdict

**The "~15-session memory bottleneck" is three stacked constraints, and none of them is "RAM
total".** Ranked by what binds first (axis L, evidence per rung):

1. **Burst admission — the killer.** The box has died 5× in 11 days of VM-compressor **segment-
   table exhaustion** (100% of `vm.compressor_segment_limit` at only 28-33% mean segment fill —
   fragmentation, not bytes; `memoryPressure=False` and ~20GB free at every death; jetsam never
   fires — the CC fleet sits in band 180 and `log show` has 0 memorystatus lines; the box "dies
   whole"). Ignition is never CC residency: it is **90-second storms of agent- and dev-tool-
   spawned processes** — a 736-proc node swarm (44.7GB, headroom 39.9→10.8GB and swap 0→30GB in
   300 seconds), and **unbounded agent search/compile tools**: a single harness-generated `ugrep`
   measured live growing 4.25→11.38GB in 4m37s; historical max 17.65GB — 27% of RAM in one grep.
2. **Active-session CPU.** The *felt* ceiling is ~4-8 concurrently-ACTIVE sessions (2.5-5
   runnable threads each on 10 cores; 127/127 historic gate refusals were load, 0 memory). Felt
   turn-end lag is 3.7s p50, 92% of it ONE call (`cc-backlog list --blocked` on the Stop path).
3. **Self-imposed caps.** Router KMAX refuses the 33rd session (`handoff-fire.sh:5266`); 4 Max
   accounts sustain ~~~3.9~~ → **6.2–11.0** active 24/7 (corrected 2026-08-27 — the 3.9 was priced
   with the refuted 68%-cache-read composition; `scaling-bottlenecks-2026-08-09.md` §2a).

**Residency is nearly free.** Marginal session = 230MB arrival / 400-460MB steady footprint,
**saturating at ~450MB within 1.5h — no lifetime leak** (log-curve fit, r²=0.695/0.967; a 20h
session reads 449MB). 64GB/0.46GB ≈ 139 sessions before per-session footprint binds. The whole
CC fleet (16 sessions + 18 subagents) was 9.7GB of 29.3GB machine footprint mid-wave; the 24/7
daemon layer is **~50MB** (one subagent costs 4.7× the entire standing orchestration).

**And the sprawl is not the villain.** On the machine's own attribution record the indicted
daemon/hook/poller sprawl is **~9% of the memory problem and ~90% of the incident-prevention
layer** (axis K). The prior consolidation record is 9 attempts that made things worse (§7). The
re-architecture below therefore has a different shape than "simplify": **bound the burst class,
arm the built-but-inert lifecycle, fix the meters, and close the activation gap** — the prior
wave's own P0 list was verified **3-of-7 undone** (C6's "conclusion never reached the enforcing
store", seventh measured recurrence). Every recommendation here names its enforcing-store edge.

---

## 2 · Where the 64GB actually goes (measured mid-wave, `phys_footprint`)

| Class | GB | n |
|---|---|---|
| macOS system | 6.76 | 646 |
| CC main sessions | 5.61 | 16 |
| CC subagents (`claude.exe`) | 4.09 | 18 |
| chrome-devtools-mcp stack | 3.02 | 13 |
| Dia (operator browser) | 2.95 | 18 |
| Next.js dev servers + esbuild | 2.48 | 10 |
| kitty (GPU IOSurface — per OS *window*, not pane) | 1.93 | 3 |
| other operator apps | 0.87 | 22 |
| shells + helpers | 0.84 | 279 |

At the wall it looks nothing like this: the 08-09 panic snapshot holds **780 node procs / 144GB
Σ-RSS (uniform swarm, median 178MB)**, wired TRIPLED to 15.2GB (compressor metadata + page tables
for 1,454 tasks), free 0.01GB, pageout reclaiming 2.7% of wanted pages. Burst, not level.
Unowned tranches found by the blind-spot sweep (axis O): third-party autolaunch residue ~1.3GB ·
Apple media/intelligence fleet ~0.5GB competing at peak *because `caffeinate-floor` never lets
the box reach true idle* · 13 `~/.claude*` homes 11.3GB on disk · WindowServer 1.5GB footprint
(9× its RSS) on four displays · 2.9GB system log store + an unread serial bash-segfault cluster ·
a Docker 4GB armed bomb + Time Machine with zero exclusions · 643MB subagent scratch.

---

## 3 · Thesis 1 — Bound the burst class (the panic-killer; highest value)

The storm population is **agent-spawned tools and dev-workers with no owner-class bound**. Darwin
returns EINVAL for `RLIMIT_AS/RSS/DATA` (measured, `resource-guard-2026-08-08.md`) — there is no
memory rlimit on macOS, so every bound must be CPU-time, cardinality, or actuator-shaped:

| # | Change | Evidence | Recovers | Effort | Enforcing-store edge |
|---|---|---|---|---|---|
| T1.1 | **Harden the `grep()` wrapper** (ours — injected into shell snapshots): `-m` max-count, max-files, reject `-o` with unanchored `.{0,N}` over a directory root; generalize reso's `mem-leash.sh` | one ugrep = 11.4GB live, 17.65GB max; 747 sentinel rows >500MB | 8-17GB of peak | S | the shell-snapshot function body (symlinked live layer — landing = deploying) |
| T1.2 | **Deploy the researched CPU ceiling** at the Bash boundary: `ulimit -t 600` PREFIX for any command containing a search binary (inherited by children; cannot break pipelines; the design's own positive control) | qos-rewrite coverage measured **0.21%** of Bash calls; the compound-exclusion survey REFUTED by tonight's two 8.5/4.8GB greps ("the grep WAS the heavy job") | stops any runaway at ~3-4GB | S | `hooks/qos-rewrite.sh` transform (already live symlink) — **✅ LANDED, ceiling 60 CPU-s not 600 (§11b)** |
| T1.3 | **Second sentinel selector** — single-proc footprint > ~4GB AND rising, comm-agnostic (cohort today is `comm ~ ^node` only: it froze an innocent 1.73GB tsc and left 10.4GB of ugrep running) **+ bounded auto-SIGCONT** (a false positive costs latency, not a hung build — today it costs a silent stall with no thaw path) | `compressor-sentinel.sh:252,279`; trip 2026-08-10T07:09 | the 7-10GB class at the moment it matters | M | EXTEND `com.claude.compressor-sentinel` (never a new daemon — band diversity is survival, axis K) |
| T1.4 | **Land the Next.js `experimental.turbopackPluginRuntimeStrategy: 'workerThreads'` flag** — in NO live config today; 2.38GB of build-worker pool per dev server running now; the named ignition of the panics. Item `0e4f795b3a20` is filed under project `agent-build-hackathon` where infra waves never look → **re-file on reso's board**, land via reso's rails | axis M F6 | −2.38GB per dev server, −6 procs each | XS | reso `next.config.js` + the re-filed item |
| T1.5 | **Process-class admission**: extend the LIVE spawn gate (`agent-teams-enforce.sh:79` → `capacity-admit.sh`) with (a) an **agent-process-count term** (reuse `capacity-alarm.sh`'s `sessions_exe` derivation — one derivation, no third copy) and (b) the **corrected headroom** — today's `cc_hw_headroom_gb()` counts anonymous-inactive as reclaimable, over-reporting by ≥10GB, and the over-report GROWS with fan-out (114 admits / 0 refusals ever). Class-cardinality (node > ~120) is observable ~60s before the memory it becomes | axis N F2/F3; axis A storm A | prevents the 44.7GB excursion class | S-M | `scripts/lib/capacity-admit.sh` + the wired PreToolUse hook |
| T1.6 | **Sentinel trip attribution**: add `ps -axo comm= \| sort \| uniq -c` + a ppid histogram of the top class to every trip (~200 bytes, 2 forks) — the 736-node storm could not be attributed to a parent from any existing record; **+ a page-only claude.exe watch row** (54 multi-GB self-bursts in 11d are invisible to the guard because the actuator correctly exempts claude-shaped procs; their trigger is still unknown for want of exactly this argv) | axis A gap; axis L rank 3 | names the next storm's owner in one line | S | EXTEND sentinel census tick |

Also standing: `capacity-ramp.sh breach()`'s missing freshness check (a dead sentinel reads 0% =
healthy — P0-6, five lines, verified still absent tonight) and the **ARM-2 exec-path freeze**
(xpcproxy/tccd/syspolicyd serialization — the desktop-freeze mode with NO guard; `why=exec` rows
ride the same tick).

## 4 · Thesis 2 — Arm the built-but-inert lifecycle (event-driven cleanup at the causing event)

The operator's instinct ("worktrees left open without proactive event-driven clean-up") is
correct and **generalizes**: the fleet's pattern is *detection built, actuation unarmed*. Found
armed-but-never-run, built-but-unwired, or missing-the-event:

| # | Change | Evidence | Recovers | Effort | Enforcing edge |
|---|---|---|---|---|---|
| T2.1 | **devserver-gc: run once ATTENDED, then trust the schedule** — plist rewritten `DEVGC_ACT=1` (ratified, packet `99637eaee7b9`) but `launchctl print` shows `runs = 0`; every logged run is `act=0`. "Armed" is an unverified claim; backlog `898f8eafb809` still says blocked — store and machine disagree | axis M F7 | the 27.5h-orphan class | XS | one attended run + close the item with its `verdict=` line |
| T2.2 | **devserver-gc: cap arm ABOVE the owner arm** — the blocking predicate is *ownership*, which is not a clock: an owned server is immortal at any size (100% keep since 08-08; a 3.78GB tree unreapable). ≤1 owned server/session, ≤2 fleet-wide; evict oldest by SIGTERM; ownership decides WHICH, never WHETHER. **+ narrow the owner oracle**: `lsof -c claude` prefix-matches `claude.exe`, so research subagents extend dev-server immortality (50 cwds / 11 worktrees live) — restrict to session leaders / the live-session registry | axis M F3/F5 | bounds the class at ~4GB | S | `scripts/devserver-census.sh` (the actuator stays the arbiter) |
| T2.3 | **SessionEnd dev-server reap arm** — 0 of 7 SessionEnd hooks mention dev servers; orphan tail is ~90min by schedule, 27.5h observed. TERM servers whose cwd is the exiting session's worktree and no other live session owns; hourly sweep becomes backstop | axis M F4 | orphan exposure → seconds | S | SessionEnd hook (c10 migration for the registration) |
| T2.4 | **Pane-close guard: split the UNKNOWN arm** — `it2-kitty:852` rc=67 refused 73 closes since 08-07, **100% UNKNOWN / 0% NON-EMPTY (the protective arm has never fired)**; nothing retries; 10 stranded panes measured holding **~6.2GB** + 10 OS windows (+~3.4GB IOSurface). Split: unreadable-and-CC-alive ⇒ keep refusing; **agent-process-EXITED ⇒ close** (no composer left to protect). NON-EMPTY arm untouchable (real 08-07 incident) | axis H §5 | ~6.2GB + windows | M | `bin/it2-kitty` state machine (live symlink) — **✅ LANDED as prescribed: `AGENT-PANE`/`AGENT-NO-BOX`/`DEAD-PANE` (§11b)** |
| T2.5 | **No crash-watchdog for subagents** — 18 of 36 watchdog daemons watch `claude.exe` subagents, which own no team/panes: the daemon's purpose is structurally inapplicable; scales with wave width | axis C C1 | 34MB + 180 forks/min + noise | S | `hooks/lead-crash-watchdog.sh` sidechain guard (reuse `mailbox-wake-arm.sh:60-77` discriminator) |
| T2.6 | **One kqueue deathwatch, not 28 polling daemons** — `bin/cc-deathwatch-kqueue` is built, selftest-gated, and has ZERO hook call sites; the watchdogs re-implement its {pid,lstart} identity in `sleep 30` loops (~22K forks/hour fleet-wide) | axis C C2, axis A §6 | −27 procs, −280 forks/min, 30s→1ms detection | M (SPOF → needs the heartbeat `lead-deathwatch.sh` already has) | ~~WIRE UP existing binary~~ **✅ WIRED — 6 call sites + 2 suites + migration 0004 (§11b)** |
| T2.7 | **MCP lifecycle** (no mechanism exists — genuine gap): (a) do NOT inherit MCP servers into `--agent-id` subagents (they spawn their own trees — measured); (b) pin the version, drop the `npm exec …@latest` wrapper (118MB × N + a registry round-trip per session start); (c) idle-TTL for zero-tool-call servers (~15min); (d) restart-on-footprint for the leak (one instance 1.93GB, peak 3.21GB; **4 of 5 instances never launched a browser** — 1.6GB idle scaffolding). **Wave-verified + extended 2026-08-10 → `docs/research/mcp-memory-groundup-2026-08-10.md`**: (a)-(d) confirmed with vendor-issue + tree-census evidence; class re-measured ~945 MB true RAM box-wide / 9-16% hosting; **shared-daemon consolidation REJECTED on measured architecture** (global tool mutex, one-browser-per-process, leak concentration, cloud-lane degradation, >6 s restart-strand); (a)'s mechanism refined — in-process Task subagents SHARE the parent's clients, the multiplier is `--agent-id` teammate PROCESSES bootstrapping from their cwd; add (e) zero-entry scoping of the reso stanza (×79 worktrees) and (f) telemetry-watchdog off (`CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS=1`, ~88-110 MB/chain) | axis A §4, axis N F7, axis C C6 | ~1.6GB standing + 3.2GB peak | S-M | `.claude.json` project MCP config + per-agent `CLAUDE_CONFIG_DIR` — **RE-OWNED 2026-08-11 by `docs/plans/MCP_MEMORY_100P_IMPLEMENTATION.md` (5 waves, `status: open`); no longer M3-wave detail (§11b)** |
| T2.8 | **Drop 31 redundant per-session `caffeinate -i -t 300`** — pid 818's standing `caffeinate -i -s` floor already asserts; the per-session ones respawn every 5min (~370 forks/h) for an assertion already held. (Vendor-spawned: needs the vendor env/config check first; if not suppressible, accept — cost is small) | axis A §6 | fork noise; 112MB | S | launcher env or accept — **premise now MECHANISED: `scripts/caffeinate-floor.sh` (T-P16-4) is the standing floor, not an observed pid. The cull itself is still open (§11b)** |
| T2.9 | **Reap orphaned `gitstatusd`** (10 of 12 at ppid 1, oldest 7h55m) at pane death — `cc-teardown:524` already enumerates the name in its skip list; extend that arm | axis H §8 | 41MB + growth stopped | S | `bin/cc-teardown` |
| T2.10 | **Editor cold-state hygiene**: Cursor 5.1GB (`state.vcdb` 1.46GB; 98 workspaces incl. dead worktree +/tmp paths minted by the `cursor /tmp/…` delivery doctrine). Prune workspaceStorage entries whose folder is gone — hang it off worktree removal; vacuum the db | axis M §6 | 5.1GB disk; window-restore risk | S | new tiny arm on worktree-gc's removal path |

## 5 · Thesis 3 — Fix the meters (every capacity decision is currently made on a wrong number)

| # | Change | Evidence | Effort | Enforcing edge |
|---|---|---|---|---|
| T3.1 | **footprint (= `top -stats mem`) as the primary metric** in capacity-alarm, sentinel snap ranking, and every census; RSS demoted to secondary | RSS: CC 1.6-2.8× over, kitty 10× under, fleet sums 2.34× over; `capacity-alarm.sh:641` already has the footprint rung — EXTEND to primary | S | 2 scripts, both live symlinks |
| T3.2 | **Correct `cc_hw_headroom_gb()`** — exclude anonymous-inactive (≥10GB phantom headroom; reclaim = compression, not freeing) | axis N F3 | S | `capacity-admit.sh` |
| T3.3 | **capacity-ramp freshness check** (dead sentinel reads 0% = healthy) | P0-6, ~~absent tonight~~ **✅ LANDED — `breach()`'s three-outcome D3 arm, mutation-tested (§11b)** | XS | `capacity-ramp.sh breach()` |
| T3.4 | **Instrument corrections, recorded**: `ps -axo arch=` silently ignored on this macOS (false "no Rosetta"); `launchctl list` status column is LAST EXIT, not liveness (this wave's own prespawn census mis-read discovery + lead-supervisor as dead — both alive); argv-keyed predicates poisoned box-wide (C13); `tmutil destinationinfo` truncation hides the verdict | axes O/N + this wave's own errors | XS | docs + the census scripts that encode them |
| T3.5 | **Benefit column for every guard** — fire-counts (sentinel 91 trips Aug 6-9; backup-before-write restores; stranded-sweep recoveries; completion-assert blocks) so cut-rankings stop reading pure prevention as pure cost | axis K missed-dimension 2 | S | wrap into the fleet census renderer |

## 6 · Thesis 4 — Close the recurrence: the prior wave's P0s, verified and re-owned

Verified live this wave (axis J adversarial pass) — **the cheapest, highest-confidence items on
the box**, all in symlinked files (landing = deploying).

🚨 **Re-verified 2026-08-13 (§11b): 4 of these 6 rows are now DISCHARGED and their ❌ is stale.** The
cheapness was real — the recurrence closed itself within three days of being named. What did NOT
close is the row this table cannot fix on its own: the `settings.json` registration in row 1, which
is C10-gated (`migrations/README.md:72-77`, ratification still absent).

| P0 | State tonight | Fix |
|---|---|---|
| setup-task-symlinks.sh at SessionStart (~4s CPU / ~800 forks / session, output DISCARDED by its own `timeout: 5`) | ❌ still registered (`settings.json:636`) | remove/guard the registration (c10) |
| `cc-backlog list --blocked` on the Stop path — **92% of felt turn-end lag** (3.4s/turn) | ~~❌ still at `operator-readout.sh:702`~~ **✅ `blg_list_cached()` at `operator-readout.sh:138` (§11b)** | memo/cache off the hot path |
| wrap-ledger transcript-keyed memo (60→27 git subprocesses/Stop) | ~~❌ reverted (`5da21949` — the memo staled the ⛔ rung); re-scoped key never built~~ **✅ built on the re-scoped key — `wrap-ledger.sh:149` § THE MEMO, one ledger per Stop EVENT (§11b)** | rebuild on the re-scoped key |
| render-census kitty arm (still charges 100% of WindowServer to iTerm2) | ~~❌ no kitty branch~~ **✅ landed 2026-08-11, the day after this doc — `render-census.sh:11` (§11b)** | add the arm |
| capacity-ramp freshness | ~~❌ absent~~ **✅ landed + mutation-tested (§11b)** | T3.3 |
| `bash script.sh` for fresh-inode invocations (40× exec-assessment tax) | ⚪ unverified at scale | worktree-setup call sites |

## 7 · Thesis 5 — The scheduler fleet: kill the dead weight, convert calendars to events

The 39 owned plists cost **~24,000 wakes and ~656,000 process creations per day** — and the wakes
mostly land at *peak*, because `caffeinate-floor` never lets the box reach true idle (the
amplifier: Apple's DAS idle tasks — mediaanalysisd 278MB etc. — then compete WITH the fleet
instead of running while it sleeps). `screenshot-clipboard` (WatchPaths) is the reference
event-driven design; almost everything else polls. Verdicts (full 39-row table in the axis file):

| Class | Items | Action | Edge |
|---|---|---|---|
| **🚨 dead-looping waste** | `postgresql@14` — **8,556 failed spawns/day** for weeks (stale lock, zero tenants, 193MB log) · `ollama` (0 tenants, 25MB) | KILL (bootout + brew services disable) | c10 migration (agents may not bootout) |
| **🚨 broken-but-firing** | `session-search-sweep` — 1,314 wakes/day, **100% no-op** (41,460/41,460 runs die on one awk fatal) | FIX the awk, then it earns its keep | script (live symlink) |
| **stale-subject** | `watch-claude-code-2118-hold` (subject 15 minor versions gone, fails daily) · `rum-verify-launchflash` (its date passed; now fires annually forever) · `loki-parity-revisit` (a calendar entry as a to-do) | KILL / re-file as backlog items | c10 |
| **poll → event** | `lr-reset-poller` (polls 600s for a **known timestamp** — one-shot `StartCalendarInterval` at the timestamp) · `deploy-live` (600s → post-land event) · `postland-verify` (300s self-blocking → land event; 62K forks/day) · `relogin` (hourly → auth-failure event) · `qos-census` (600s → on-spawn) | CONVERT | plists (c10) + the event emitters that already exist |
| **band placement** | `compressor-sentinel` + `lead-supervisor` run **undemoted at PRI 20**, competing with interactive sessions (189K + 103K forks/day) | demote to **utility** band (M1-rev doctrine) — NEVER Background (background-band samplers die ~3min before every wedge; band diversity is survival) | plist `ProcessType`/`Nice` (c10) |
| **top fork producer** | `dispatcher` — 196K forks/day (30% of fleet), most runs ending "premise no longer holds" for the same 4 items, currently self-refusing on its own capacity gate | premise-cache + widen interval; MERGE candidate only within its own family | `bin/cc-dispatch` |
| **throttle an abused WatchPath** | `gl.reso.worktree-gc` — reso's pool touches the wake file continuously (mtime 23s old) ⇒ 424 forks/run × 56/day | damp the wake-file writer | reso pool script |
| **disabled-but-load-bearing** | `boot-resume` (KEEP-OFF by design — C10, page-mode default) · `desk-invariant` · `team-orphan-reaper` (its function now UNOWNED) · **`nightly-regression` — a coverage hole, surface to operator** | DECIDE per item, delete-or-enable; a disabled invariant asserts nothing | operator decision packet |

Instrument correction (proven by positive control): **`plutil -lint` is the wrong oracle for
launchd plists** — two reso plists fail it and launchd runs them fine; no reboot time-bomb exists
in those two. And **"5 overlapping reapers" was my census's error**: only 4 are loaded, their
subjects are disjoint (sessions / teammate-close-outcomes / worktrees / dev-servers), and
`teammate-reap-alarm` is an *alarm deliberately independent of the actuator it watches* — merging
it away is the classic consolidation failure. DO NOT MERGE the reaper family.

## 8 · Thesis 6 — Worktree lifecycle: the janitor's calendar never fires, and the dirty gate blocks on one artefact

**`com.claude.worktree-gc-infra`: `runs = 0` — launchd has never once executed the scheduled arm.**
Every effective sweep in the repo's history was hand-/event-fired (the 2026-08-09 22:15 sweep
removed **319 worktrees + 389 branches** in 47 minutes). *Creation is event-driven; removal is
calendar-driven; the calendar never fires.* Current populations (fleet 274; 246 in the shared
`~/Development/.worktrees` across 5 repos): infra ~118 · reso 74 (**144GB disk**, mean 2GB) ·
doc_classifier 62 (**no janitor exists**; 26 are landed+clean = fully reapable today).

Per-arm blocking, evaluated independently against all 118 infra worktrees (the janitor's own log
prints priority-ordered attributions, not per-arm counts):

| Arm | blocks | blocks ALONE |
|---|---|---|
| dirty tree (`worktree-gc.sh:726`) | 87 | **71** |
| unlanded (`git cherry` patch-id) | 35 | 17 |
| LIVE / idle-floor / exclude / detached | 9/9/3/2 | 2/0/0/1 |

**84% of the dirty blockage is ONE shared banner/blender asset set** — staged `A ` entries in 73-78
worktree indexes (mtimes Jul-30/31) whose content landed on `origin/main` Aug-8. Content-hashing
every dirty blob against trunk: **38 of 87 dirty worktrees carry ZERO unique content** (removal
cannot lose a byte; all 38 are permanent KEEPs today); real work at risk ≈ **17 worktrees, not 87**.
The producer of those staged entries is **unattributed** (three suspects ruled out by code-reading —
§8 of the axis file; genuinely open).

Deliberately refuted (so the memory link is stated honestly): 274 worktrees hold **no RAM** (110 of
118 have zero open fds), do **not** slow git ops (0.02-0.04s measured), and are not a disk-capacity
problem on a 7.28TiB volume (reso's 144GB is the one real disk term). The binding resource remains
*un-recreatable content with no collector* + the scan/index surfaces.

| # | Change | Effort | Edge |
|---|---|---|---|
| T6.1 | **Formalize the event path as primary** (post-land + pane-death triggers wake the janitor; calendar becomes backstop) — the 22:15 sweep already proved the event path | S | janitor wake-file + /ship post-land hook (c10 for wiring) |
| T6.2 | **Content-hash zero-loss arm**: a dirty worktree whose every dirty blob is reachable from `origin/main` is disposable (38 today) — this is the repo's own verify-by-CONTENT doctrine applied to the janitor | M | `scripts/worktree-gc.sh` new arm + tests (HAZARD C14: develop in a throwaway repo) |
| T6.3 | **AC-7 kill switch** on the scheduled destructive janitor (still absent) + attribute and stop the staged-asset producer | S / open | worktree-gc-infra-run.sh |
| T6.4 | **doc_classifier janitor** (none exists; 26 reapable now) + reso DISPOSE class | S | extend the existing janitors, per-repo config |
| T6.5 | `worktree-pool.sh` phantom (15 referencing files, never existed, dead gate at `handoff-fire.sh:5508`) — row 11's delete-or-build call | — | row 11 |

## 9 · Thesis 7 — Git maintenance: enrollment as practiced is an anti-pattern; fix the mechanism, then enroll

**The only enrolled repo is the only unhealthy repo — *because* it is enrolled.** `git maintenance
start` set `maintenance.auto=false` (switching off git's own in-process gc) and delegated to
launchd timers; the Aug-5 00:16 daily run crashed mid-`incremental-repack` and left a **0-byte
`objects/maintenance.lock`** that has silently no-op'd ~130 runs for 5.5 days (launchd: exit 0
throughout). reso: **1,352MB `.git`, 11,660 loose objects, 22 packs, 97 prune-packable** vs the
busier unenrolled claude-infrastructure at **254MB / 87 / 4**. Loose-object birth-dates confirm the
freeze (Aug-7 alone: 5,446).

Also found: **`git maintenance start` writes `Day` where it means `Weekday`** — the "daily" plist
fires only on the 1st-6th of each month (upstream git bug on macOS; verified in the plist).
`finance-ai-web-app`: 5,513 loose / 0 packs / no commit-graph (never maintained at all).
**fsmonitor is settled: DO NOT enable** — it is per-*worktree*, so infra alone would spawn up to
253 daemons × 5.3MB (and `extensions.worktreeConfig` is unset everywhere, so any `.git/config`
setting hits ALL worktrees of a repo — the binding constraint on every recommendation).
Git itself is NOT a memory term (4.5-9.6MB max-RSS/op; ≲150MB fleet transient at 15 sessions);
the latent risk is an unbounded detached gc (10 threads, no `pack.windowMemory` cap).

| # | Change | Effort | Edge |
|---|---|---|---|
| T7.1 | `rm` the verified-stale reso maintenance.lock (0 bytes, 5.5d, no lsof holder) — one command, ~100MB + 11.6K inodes back on the next cycle | XS | the lock file; then a staleness pre-flight in the runner (git has no lock TTL) |
| T7.2 | Fix the daily plist `Day`→`Weekday` (and report upstream) | XS | `~/Library/LaunchAgents/org.git-scm.git.daily.plist` (c10) |
| T7.3 | Enroll the fleet **after** T7.1/T7.2 prove the mechanism: claude-infrastructure + doc_classifier + finance (with `pack.windowMemory` capped, `maintenance.auto` left ON as the backstop unless measured otherwise) | S | `~/.gitconfig` maintenance.repo (c10) |
| T7.4 | Missing repo-local hooks: none needed for memory; the worktree-hygiene triggers land via T6.1's event path, not per-repo githooks (7 of 8 repos already carry gate hooks; sevenrooms + whisper.cpp have none — accepted, low-churn) | — | — |

## 10 · Thesis 8 — Stores: bounded by defaults nobody set, unbounded only where they are ours

12.08GB across 25 stores. The harness's own stores are all bounded (CC `cleanupPeriodDays`
default 30 — **unset**, i.e. load-bearing vendor default; verified: 22 of 7,956 transcripts
survive past 30d). Every unbounded store is ours:

| # | Change | Evidence | Recovers | Effort | Edge |
|---|---|---|---|---|---|
| T8.1 | **Install the staged scratchpad reaper** — script complete, plist in `launchd/staged/`, zero call sites; its own header: 10.67GB / 461 dirs / +810MB/day, "its ONLY bound is a reboot"; 23 of 42 worktree scratch dirs point at worktrees that no longer exist | axis I F1 | 214MB now; caps +810MB/day | XS | install the plist (c10) |
| T8.2 | **Cap the DoD injection, not the file** — `dod-persist.sh` injects the WHOLE append-only DoD file (~30KB ≈ 7,480 tokens) at every SessionStart AND PreCompact; ×15 sessions ≈ 112K tokens per restart wave; the INTEGRATE contract governs the file, nothing requires the consumer to read all of it | axis I F2 | −87% per injection | S | emit-path `awk` — reuse `hooks/lib/memory-index-budget.sh`'s budget shape |
| T8.3 | **Spotlight, settled properly**: dot-stores were NEVER indexed (both prior claims reconciled — `mdls`/`mdfind` controls); the 738MB resident indexer is driven by `~/Development`'s non-hidden 4.94M items; exactly ONE repo script uses Spotlight (a benchmark) | axis I F3 | several hundred MB RSS | XS | `mdutil -i off ~/Development` — operator call (kills Finder/Alfred search there) |
| T8.4 | **Repoint restic** — it currently backs up 971MB of re-downloadable npm tarballs and NOTHING else; transcripts/memory/DoD/idl-chain/plan-history are unbacked AND on the 30-day cliff (highest value, shortest guaranteed life) | axis I F4 | protects ~150MB irreplaceable | S | `restic-claude-archive-backup.sh` source list |
| T8.5 | **Pin `cleanupPeriodDays` explicitly** (a CC upgrade could silently change the default that currently does all retention); birth rate accelerating 215→315→477 MB/day ⇒ steady state ~14.3GB at 30d | axis I F5 | ~4GB at 14d (risk: forensic reach — coordinate with limit-recover readers) | XS | settings.json (c10) |
| T8.6 | Small dead weight: orphaned 49.3MB `session-index.db.bak` (larger than the live db) · 8 stale mailbox `.lock` dirs · `prune-plan-history.sh` exists with launchd=0 · `backups/` has per-source cap but no age bound (105d entries) | axis I table | ~100MB + hygiene | XS | one sweep + install the pruner |

Hook-layer verdict folded in (axis F): hooks are **0.10% of RAM, 1.2% of turn latency** — 79
entries (not 41; matcher-groups understate 1.9×), all-parallel confirmed from the vendor doc +
measured burst walls (1.35× self-contention). Two robustness items ride the landing map: two
hooks declare NO timeout (default 600s — can block a tool 10 minutes) and one SessionStart
backstop spends 2.68s/433 forks re-doing the launcher's work.

## 10c · Thesis 9 — Session levers: context is the variable cost; the MCP family is the free 3GB

Measured cost model (n=21, R²=0.71): **`footprint_MB = 228 + 0.343 × K-input-tokens + 0.071 ×
minutes`**. The fixed floor is un-movable (bun-compiled binary — `NODE_OPTIONS` is INERT on CC
itself, re-confirming three prior rejections); the **context term is the whole variable cost**:
every live session runs `window: 1000000` with `autoCompactEnabled: false` ⇒ 343MB/session
ceiling, ~1.7GB across 16 sessions at today's fill. Context stewardship IS the memory lever, in
MB now, not only quota.

**Identity correction that re-prices the orchestration doctrine:** the 18 `claude.exe` processes
are NOT in-process subagents — ancestry proves all 34 CC processes are top-level OS sessions
launched via `cc-pane-runner` panes (`teammateMode: "iterm2"`). A 15-member research wave = 15
full 228MB-floor sessions (~3.3GB). The binary supports `teammateMode: "in-process"` (≈ −2.3GB
per wave) — **operator decision, not an F1-F4 pass**: it trades away the visible-split-pane
standing preference and lands all teammate context in one window.

| # | Lever | MB | Effort/Risk | Edge |
|---|---|---|---|---|
| T9.1 | Heap-cap chrome-devtools-mcp (real node v22, default heap 4144MB; one server at 1.9GB/peak 3.1GB with **zero browsers on the box**) | ~0.9GB now, caps class at 1GB | S / Med (OOM mid-use) | reso `.mcp.json` `env.NODE_OPTIONS=--max-old-space-size=1024` (taxes-2026 pattern exists) |
| T9.2 | Kill the MCP telemetry watchdog (a detached third node process per server, pure Clearcut telemetry) | 88-110MB × chain (~410MB now) | S / Low | same env block: `CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS=1` |
| T9.3 | Drop `npx …@latest` wrapper (117MB resident + a registry re-resolve per session start) | ~470MB now | S / Low (pins version — a feature) | direct node path in `.mcp.json` |
| T9.4 | chrome-devtools **opt-in** — eager today (starts 53s post-init, pre-any-tool-call) in 100% of reso-worktree sessions AND teammates, used in 3.2% of transcripts; 3 chains in one worktree = 936MB; a 12-wave = 13 chains ≈ **4.0GB — the largest single avoidable term found** | 312MB per non-user | M / Med | `disabledMcpjsonServers` (supported, unused) or `.mcp.browser.json` opt-in |
| T9.5 | Source-side fan-out cap: `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` (binary default **20**; `MAX_SUBAGENTS_PER_SESSION` **200** ⇒ a 4.7GB per-session tail) — set **16** (12 would have refused this very wave) | bounds the tail −1.9GB/session | S / Low-Med | settings.json env (the machine-side admit gate then backstops) |
| T9.6 | Delete the self-inflicted `CLAUDE_CODE_MAX_WEB_SEARCHES_PER_SESSION=1000` (binary default 200) | up to 140MB on search-heavy waves | XS / Low | settings.json env |
| T9.7 | **Idle-minutes term in waiting-recycle** — the recycle rails are 100% context-%-keyed and desk-only-eligible; memory never reaps: 4 sessions idle >10min held 1.6GB; a recycle returns a session to the 228MB floor | ~1.2GB at any moment | M / Med (wrong recycle interrupts a builder — the reason the desk-only gate exists; extend, don't bypass) | `hooks/waiting-recycle.sh` idle tier |
| T9.8 | OPERATOR-CLASS (filed, not auto): `teammateMode: "in-process"` (−2.3GB/wave, values conflict) · `CLAUDE_CODE_DISABLE_1M_CONTEXT=1` (−4.1GB tail, breaks the Context-Stewardship threshold system) · softer `CLAUDE_CODE_MAX_CONTEXT_TOKENS` — **semantics unverified, do not design around it until probed** | — | — | operator decision packet |

Config bug found riding along: the `browsermcp` entry in `$CFG/.mcp.json` is **inert** — CC reads
`.mcp.json` from the *project root*, not the config dir; `enabledMcpjsonServers` has nothing to
enable. The only real stdio server is reso's git-tracked project `.mcp.json`. G1-G4 ≈ **3.0GB
recoverable today with no operator decision, all inside one MCP family with no browser attached.**

## 10d · What we will NOT do (defended mechanisms + graveyard — burden of proof already paid)

**Load-bearing, do not consolidate** (each answers a cited incident — axis K): the daemon
*population* with QoS-band diversity (background-band samplers die ~3min before every wedge; the
sentinel survives BECAUSE it diverged) · the 5 distinct reapers (distinct populations, kill
disciplines, oracle failure modes) · the 74 hooks (**hooks run in PARALLEL — a serializing
dispatcher would turn max() into sum() and double turn-end lag**; `hook-chain.sh` was built,
measured, premise falsified, deliberately unwired) · per-session pollers (idle sessions = 0.0031
runnable threads; consolidation declined as negative-EV; the 15s→60s interval is the one priced
lever) · worktree fail-closed KEEPs (age alone NEVER disposes; 13/37 "stale" were LIVE; `dfacccd`)
· per-file-symlink deploy (one inode = one XProtect assessment box-wide; copy-per-worktree adds
313 × ~136ms serialized) · standing orchestrators (operator directive; ~50MB total) · dual
terminal transports (a 2nd transport makes an arm ambient) · `cc-pane-runner`'s 50ms loop
(bounded; the FIFO alternative is a documented hang) · iTerm2 stays installed (0 RAM, the only
bench counterfactual).

**Graveyard (measured rejections — never re-propose):** box-wide poller daemon · hook broker ·
Spotlight `.worktrees` exclusion (dot-dirs never indexed; but see the OPEN root-checkout
node_modules question, §9) · tmux/abduco substrate · `taskpolicy -c background` (84-89× tax;
utility band instead) · raising iTerm2's Metal cap · compiled dispatch binary (pays assessment in
full) · `vm.compressor_mode` (worsens the crash term) · Next.js *upgrade* for the postcss storm
(the config flag is the remedy) · stress-ramp acceptance tests (operator: *"Pressure testing us
to crash is not the solution"* — prove the MARGIN: `150 × active_cost + baseline ≤ 0.75 × 64GB`,
natural growth only) · **age-based session recycling as a MEMORY argument** (new this wave:
sessions plateau at ~450MB; recycling stands on context-rot only) · **a subagent reaper** (new
this wave: 0 orphans across 18 — they exit cleanly; the lever is wave width, not reaping) ·
**off-box offload as a capacity valve** (new this wave: 13 cloud sessions created, 0 ever acted,
no `claude/*` refs; `isolation:"remote"` gated off on all 4 accounts AND silently downgrades to
local — forbidden as a capacity lever until one observed cloud execution; unblocks = B1 branch-
switch ~3 lines at `handoff-fire.sh:5547` + B2 wire the existing `cc-cloud preflight`).

## 11 · Landing map (every item needs an owner and an edge, or it is the inertness generator's next input)

| Owner | Items |
|---|---|
| **M3 wave detail** (its falsifier is already this doc's acceptance: *"a spawn-depth cap is enforced at the actuator AND `.worktrees` count is bounded by a reaper that runs"*) | T1.2/3/5/6 · T2.1-2.6 · T3.1-3.3 — ~~**note the M3 wave itself is STRANDED on branch `m3-fleet-footprint` (+3: sentinel-reads-kernel, worktree-gc rungs, spawn-gate account-tree); land or supersede it first**~~ **← REFUTED BY CONTENT 2026-08-13, see §11b: all three commits' content IS on trunk (rebase-landed under new shas). This row's stated precondition no longer blocks anything, and 9 of its own items are already discharged.** |
| **GROUND_UP row 11** (worktree/warm-pool, attempt #3 pending) | worktree DISPOSE arming · AC-7 kill switch · staleness oracle (content-based, `git cherry`) · `worktree-pool.sh` phantom resolution (referenced by 15 files, never existed) · branch-reaper scheduling (on trunk, unscheduled, 394 unmerged branches) |
| **GROUND_UP row 6** (hooks — scheduled LAST by design) | T2.5/2.6 wiring · P0 items 1-2 · statusline per-render cost (5.4% of a core O(N), dominant term `git status` in the 115-worktree checkout) |
| **reso board** | T1.4 workerThreads flag (re-file `0e4f795b3a20` off `agent-build-hackathon`) |
| **c10 migrations (⛔ the single gating decision: the C10 rescope is UNRATIFIED — ~~7 of 8 migrations staged, incl. 0006 mailbox-wake-arm~~ still unratified 2026-08-13 per `migrations/README.md:72-77`, but the LADDER has advanced past this count: trunk carries `0007-mailbox-wake-arm-registration.sh` + 0008-0011 — §11b)** | every settings.json/plist registration above |
| **operator-only, filed** | C10 ratification · devserver-gc attended first armed run (T2.1) · Time Machine exclusions + destination decision (O-6) · third-party autolaunch cull (O-1, `sfltool dumpbtm` needs admin) · postgres@14 + ollama bootout (T5) · nightly-regression re-enable decision (coverage hole) · reso maintenance.lock rm (T7.1 — one command, or agent-run if sanctioned) |
| **stranded, content-verify then land** | `crash-rootcause-2026-08-09` branch (+1) — devserver-gc arming commit; ~~`m3-fleet-footprint` (+3)~~ **← content ON TRUNK, §11b**; gu13c/* (5 branches, map claims rebase-landed — verify by content per C7) |

## 11b · Landing-map re-verification against trunk (2026-08-13)

Written by the dispatch of backlog item `0095e83a191f` ("execute the §11 landing map"), whose brief
required the premise be checked before acting. **It was three days old and half wrong**, in both
directions: the one thing it named as BLOCKING had already landed, and nine of the items it listed as
work were already discharged. Every verdict below is a content read of `origin/main`, named so the
next dispatch inherits a measurement instead of re-deriving one. Method per C7: **content, never
sha** — a rebase-land changes the sha and leaves `git branch --contains` and any count-based check
reading "not landed" over code that is right there.

**The blocking precondition is REFUTED.** `m3-fleet-footprint`'s three commits are not ancestors of
`origin/main` — and their content is on it anyway, which is exactly what a rebase-land looks like:

| stranded commit | added lines present on trunk | the 100%-negative, read |
|---|---|---|
| `77d33bdc` sentinel-reads-the-kernel | `compressor-sentinel.sh` **138/138** · `tests/compressor-sentinel.bats` **77/77** | none — byte-identical additions; trunk reads the kernel at `compressor-sentinel.sh:762` (`read_num_sysctl vm.compressor_segment_limit`) |
| `ea58210f` worktree-gc rungs | `worktree-gc-infra-run.sh` **187/189** · `tests/worktree-gc-infra.bats` **124/124** | the 2 are the same two invocation lines, **evolved forward** on trunk — `worktree-gc-infra-run.sh:444,446` add `${GC_DIRT_FLAG:+…}`, a strict superset |
| `fa2abe97` spawn-gate account-tree | `agent-teams-enforce.sh` **107/109** · `tests/agent-teams-enforce.bats` **80/80 (blob-identical to trunk)** · `tests/capacity-admit-coverage.bats` **7/7** | the 2 are reflowed comment prose, no code |

So "land or supersede it first" gated the whole M3 row on work that was already live. **The
generalisable defect: a landing map recorded branch NAMES as its precondition.** A branch name is
not a fact about the tree — it survives its own content landing, and a map that keys on one goes
stale silently while every reader believes it is blocked.

The sibling row is the same story. `crash-rootcause-2026-08-09` (+1, `c6ab83a8` "arm devserver-gc")
is also **on trunk by content**: `launchd/com.claude.devserver-gc.plist:48` exports `DEVGC_ACT=1` and
cites the same ratification packet `99637eaee7b9`. What is genuinely left of T2.1 is the *attended
first run* (`launchctl print` → `runs = 0`) — operator-only, and already filed as such. So of the
three "stranded, content-verify then land" entries, **two are landed and the third (gu13c/*) is the
one the row already suspected**. Both carriers corrected in
`memory-econ-rearchitecture-2026-08-10/prior-art.md` §IV.2.

**Nine rows the doc marks ❌ / "no mechanism" are DISCHARGED on trunk.** Two landed *after* this doc
was written, which is why it could not know:

| row | doc says | trunk says |
|---|---|---|
| T1.2 CPU ceiling at the Bash boundary | proposes `ulimit -t 600` | **LANDED, and calibrated tighter** — `config/qos-bound.patterns` + `hooks/qos-rewrite.sh` transform (c) + `bin/cc-cpubound`; ceiling **60** CPU-s not 600, chosen against 56,269 paired agent Bash calls (0 of the 233 simple search-binary calls exceeded 30 s) |
| T3.3 / P0-6 capacity-ramp freshness | "absent tonight" | **LANDED** — `capacity-ramp.sh` `breach()` has the three-outcome D3 arm (no reading ⇒ UNVERIFIABLE; sample older than `SEG_MAX_AGE` ⇒ UNVERIFIABLE). `tests/capacity-ramp.bats` **20/20 green** even on a Linux container, incl. test 18 *"MUTATION: neutering the freshness check makes a STALE sentinel read healthy again"* |
| P0-2 `cc-backlog list --blocked` on the Stop path (92% of felt lag) | "❌ still at `operator-readout.sh:702`" | **LANDED** — `hooks/operator-readout.sh:138` `blg_list_cached()`, citing its own predecessor item `d1b453ddf16e` |
| P0-3/P0-4 wrap-ledger memo | "❌ reverted; re-scoped key never built" | **LANDED on the re-scoped key** — `scripts/wrap-ledger.sh:149` § THE MEMO, one ledger per Stop EVENT keyed on the transcript |
| P0-4 render-census kitty arm | "❌ no kitty branch" | **LANDED 2026-08-11**, the day after this doc — `scripts/render-census.sh:11` *"THE RENDER SUM COUNTS kitty … closing the FIFTH instrument artifact"* |
| T2.4 pane-close UNKNOWN split | "the protective arm has never fired", proposes agent-EXITED ⇒ close | **LANDED as prescribed** — `bin/it2-kitty` `composer_state()` now returns `AGENT-PANE`/`AGENT-NO-BOX`/`DEAD-PANE`; :655 *"Both exits below used to be an unconditional UNKNOWN; they now consult the [dead check]"*. NON-EMPTY arm untouched |
| T2.6 wire `cc-deathwatch-kqueue` | "ZERO hook call sites" | **WIRED** — `scripts/lead-deathwatch.sh`, `scripts/deathwatch-watchfile.sh`, `scripts/never-stuck-gate.sh`, `launchd/fleet.manifest`, `migrations/0004-lead-deathwatch-l1-activation.sh`, + `tests/deathwatch-watchfile.bats` / `tests/lead-deathwatch.bats` |
| T2.7 MCP lifecycle | "no mechanism exists — genuine gap" | **RE-OWNED, not M3 detail** — `docs/plans/MCP_MEMORY_100P_IMPLEMENTATION.md` (2026-08-11, `status: open`): 5 waves, Phase 0, six named backlog successors it discharges |
| T2.8 caffeinate | premise = "pid 818's standing assertion already holds" | that premise is now a **mechanism**, not an observed pid — `scripts/caffeinate-floor.sh` (T-P16-4) is a RunAtLoad+KeepAlive floor. The **cull** of the 31 per-session ones is still open |

**Eleven rows are STILL LIVE, verified absent by content** — this is the real remaining work, and it
is a *shorter* list than §11's:

| row | the negative that proves it open |
|---|---|
| T1.3 second sentinel selector | `compressor-sentinel.sh:358` still *"Deliberately UNDER-inclusive: the cohort test is the EXECUTABLE NAME (comm basename ~ `/^node/`)"* — no comm-agnostic >4GB arm, no bounded auto-SIGCONT |
| T1.5 process-class admission | no agent-process-count term in `scripts/lib/capacity-admit.sh`; `sessions_exe` exists only in `capacity-alarm.sh`'s IDL row (:1227) — still the two-copy problem the row wants collapsed |
| T3.2 corrected headroom | `capacity-admit.sh:169` `cc_hw_headroom_gb()` still sums free + speculative + **inactive** + purgeable — the ≥10GB anonymous-inactive phantom is intact |
| T1.6 trip attribution | the only `uniq -c` in the sentinel is :700, the **panic-report** parse; the live trip census tick (`census()`, :328) still emits no comm/ppid histogram, and there is no claude.exe page-only watch row |
| T2.2 devserver cap arm | no cap constant in `scripts/devserver-census.sh` (`grep -c 'MAX_OWNED\|fleet-wide cap\|evict'` = 0); :301 still concludes *"every server is owned, busy, or young"* — ownership still decides WHETHER, not WHICH |
| T2.3 SessionEnd dev-server reap | `hooks/session-end.sh` mentions dev servers **0** times |
| T2.5 subagent watchdog guard | no `--agent-id`/subagent discriminator in `hooks/lead-crash-watchdog.sh` |
| T2.9 gitstatusd reap | `bin/cc-teardown:524` still only **skips** `gitstatusd*` in its case list — the doc's own observation, unextended |
| T2.10 Cursor cold-state | no `workspaceStorage` / `state.vcdb` reference anywhere in `scripts/`, `hooks/`, `bin/` |
| T3.1 footprint as *primary* | the rung exists (`capacity-alarm.sh:642`, "per-proc physical-footprint outlier") but the promotion to primary is **not verifiable off-Mac** — `top -stats mem` does not exist here. Left UNVERIFIED rather than guessed |
| T3.5 benefit column | no fire-count column in any census renderer |

**Why this dispatch stopped at the disproof instead of writing the eleven.** Two blockers, both
still true, and both are facts about the enforcing store rather than about effort:

1. **⛔ C10 is still unratified, confirmed in-repo** — `migrations/README.md:72-77`: *"§3's rescope of
   C10 … is explicitly the one clause the doc says a human must ratify, once. **That ratification has
   not**"*. Every settings.json/plist registration in §11 (T2.3's SessionEnd hook among them) stays
   operator-gated. One correction to §11's own row: the ladder has **advanced past** what it recorded
   — trunk carries `0007-mailbox-wake-arm-registration.sh` (numbered 0007, not 0006) plus 0008-0011.
2. **The dispatch ran in a Linux cloud container, and the gate for these files is red there by
   construction.** `vm_stat`, `top -stats mem`, `launchctl`, `lsof -c claude`, kqueue and the pane
   layer are all absent, so `tests/capacity-admit.bats` fails its own P1/P2/P3 positive controls
   (*"the REAL sysctl is reachable at the absolute path the library resolves"*, *"vm_stat is
   reachable on a MINIMAL PATH"*). A T1.3/T1.5/T3.2 diff written there could not be gate-verified —
   and per the same C7 logic that refuted the stranded branch, an unverifiable diff against code
   whose cure may already be on trunk is how a correct-looking change reverts trunk. **Docs-only was
   the only honestly-verifiable deliverable from that box; the eleven rows want a Mac session.**

### 11b.1 · Two land-gate findings this dispatch produced by trying to land at all

Recorded here rather than only in the backlog because the ledger (`~/.claude/autonomy/backlog.jsonl`)
is **not tracked in this repo** and is unreachable from a cloud container — so trunk is the only
durable carrier a cloud dispatch has. Both are about the *land path*, not about memory economy; they
are here because this is the doc whose dispatch found them.

**1 · A `/ship`-blocking bug, FIXED (`c2073d41`) — the hermeticity ratchet read a MATCH as "could not
run".** `test-hermeticity-lint.sh`'s `is_hermetic()` probed `setup_bodies "$f" | grep -qE …` and
captured the *pipeline* status under `set -o pipefail`. `grep -q` exits the instant it matches, the
awk producer takes SIGPIPE, and 141 is promoted — **so the predicate failed exactly when the suite
WAS hermetic.** 141 is neither 0 nor 1, so it fell through to `CHECK_FAILED`, the lint exited 2, and
`ship-land` turned that into **exit 9 GATE-KILLED**. The arm is fail-fast and runs *before* the
smoke, so while it was live **no land of any kind could complete from that box — a docs-only land
included** (verified: the docs commit alone hit it too). Measured head-to-head over the same producer
and suite, 40 trials each: **old form 36/40 false failures, here-string form 0/40**; the lint went
from exit 2 with no rule-1 verdict at all to `clean — 465 suite(s) … 0 new leaks`.

Three properties make it a nastier bug than its exit code suggests, and all three generalise:
  · **it fires because the tree is CORRECT** — no match, no early exit, no SIGPIPE;
  · **its own diagnostic misdirects** — `CHECK_FAILED` prints *"re-run when the box is quieter; do
    not 'fix' any suite"*, which is right for the fork pressure it was written for and useless for a
    deterministic race. Observed at load **0.31** on an idle box, three lands in a row;
  · **the fix was already known and already written down in the same file.** Rule 4's predicates use
    here-strings, and the note above them explains this exact SIGPIPE promotion — then bets that the
    other predicates' inputs are *"small enough that it has never been observed"*. That clause is
    what kept rules 1-3 on pipes. The bet lost, and it is corrected in place with the measurement.

**2 · The ratchet built for this hazard class did not catch it — FILED, not fixed.**
`scripts/pipefail-sigpipe-lint.sh` exists precisely to ratchet `producer | early-exit-consumer` under
`pipefail`, with a shrink-only allowlist. It reported **clean** across all five defective sites,
before and after. Cause is its rule clause 4, which counts a pipeline's status as *consumed* only in
an `if`/`elif`/`while`/`until` condition, a `!` operand, or — **under `set -e`** — a bare pipeline or
top-level `VAR=$(…)`. The defective form was `producer | grep -q …; rc=$?` in a file that sets
`set -uo pipefail` and **not** `set -e`. So the single most explicit way to consume a pipeline's
status — assigning it — is the one form the detector does not recognise. Left filed rather than
fixed: it is not land-blocking, the current tree holds **one** other instance
(`scripts/git-identity-lint.sh:235`, exempt anyway under clause 3 since its producer is a `printf` of
a shell variable), and a false RED in a shared gate lint blocks *every* session's land — the wrong
blast radius to accept from a box that cannot run the macOS half of the suite.

**And the residual blocker is environmental, pre-existing, and not fixable from Linux.**
`unattended-path-lint --selftest` fails **10 of 24** in a cloud container — verified identically on
**pristine `origin/main`** (`a54569db`), so it is nothing this branch did. It is not a defect either:
the lint asks *"will this bare name resolve for the job that runs it"* and answers by resolving
against the live filesystem, and macOS's `/sbin/md5` · `/usr/sbin/sysctl` · `/usr/sbin/lsof` are
simply absent on Linux, so its fixtures stop discriminating. Consequence for any cloud dispatch of
this repo: **a land must carry the fix in finding 1 (or the hermeticity arm kills it), and carrying
any `.sh` pulls this arm into own-scope where it is red — so the first land from a Linux box is a
deadlock.** The branch is pushed and content-complete; landing it wants a macOS session.

## 12 · Open questions this wave could not settle (named, not hedged)

1. ~~Spotlight~~ **SETTLED by axis I** (T8.3): dot-stores never indexed; the cost is
   `~/Development`'s non-hidden tree (4.94M items, 738MB resident indexer); exclusion is safe for
   every mechanism (one benchmark script) and is an operator preference call on Finder/Alfred.
2. The `claude.exe` 4-41GB self-burst trigger (54 in 11d) — still unknown; T1.6's watch row is the
   instrument that will name it.
3. Whether an empty `~/.claude/cc-roles/orchestrator` reads as absent or broken at `it2py anchor`
   — it currently HOLDS every headless fire (backlog `b0a237b76793`).
4. The 6MB/min subagent growth: context accumulation vs leak — bounded either way by wave budget
   `N × footprint × duration`.
5. Transcript-size → footprint coupling: n=1 (+40MB at 34.5MB transcript), inferred only.
6. The producer of the staged banner/blender asset entries polluting 73-78 worktree indexes —
   three suspects ruled out by code-reading; unattributed (axis D §8).
7. Boot-resume respawn storm (panic #6's re-kill 38min post-reboot) vs `boot-resume` currently
   DISABLED with page-mode default — which path respawned the fleet on Aug-9 is unresolved;
   matters because the boot storm is the one ignition a calendar can pre-commit.

## 13 · Corrections to this wave's own prespawn census (recorded so the next census inherits them)

`kitty ×1 = 157MB` → **1.9GB footprint** (ps blind to IOSurface) · `Dead (-15): discovery,
lead-supervisor` → **both alive** (status column = last exit) · `postgresql@14 resident` → **not
running** (failing LaunchAgent, last exit 1) · `Browser/Google/Dia ≈ 7.7GB operator` → 2.25GB of
it at the trip was **infra-owned puppeteer Chrome** under chrome-devtools-mcp · `esbuild ×6 =
850MB` → the unit is the *tree* (one next-server tree = 3.78GB / 9 procs) · `claude.exe ×N =
"subagents"` → **full OS-level teammate sessions** (teammateMode iterm2; ancestry-proven; the
in-process runner exists unused) · `"5 overlapping reapers"` → 4 loaded, subjects disjoint,
one is an alarm-by-design · every RSS sum in the anchor → re-price ×~0.44 (footprint).

## 14 · Per-axis artifact index

`docs/research/memory-econ-rearchitecture-2026-08-10/` — census-fleet · sched-launchd ·
pollers-sessions · worktrees · git-maint · hook-forks · session-cost · terminal-layer ·
stores-bloat · prior-art · devtools-residency · orchestration-econ · adversary-defend ·
bottleneck-refute · blindspots. Axis reports are the evidence layer; this doc is the verdict
layer. Where they disagree with each other the disagreement is named here (§9) — do not silently
prefer either.
