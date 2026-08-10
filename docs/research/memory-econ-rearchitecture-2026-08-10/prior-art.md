# Axis J — Prior art: settled decisions · graveyard · hard constraints

**Date:** 2026-08-10 · **Repo:** `~/Development/claude-infrastructure` @ `da04cf23` (trunk tip `2140b451`)
**Method:** repo + docs reading, git archaeology (`--diff-filter=A`, for-each-ref containment,
`merge-base --is-ancestor`), live `launchctl`/`ps`/`git worktree` reads. Every row cites `doc:line`
or a commit sha. Nothing modified.

---

## 0 · THE HEADLINE — read this before designing anything

🚨 **A 13-axis research wave answering THIS EXACT QUESTION completed ~14 hours ago and is on trunk.**
`docs/research/scaling-bottlenecks-2026-08-09.md` (landed `90880b95`, "the true bottlenecks to 150
sessions — 13-axis wave verdict") + 14 per-axis artifacts in
`docs/research/scaling-bottlenecks-2026-08-09/` (00–13, 5,457 lines). Its frozen scope
(`:5`): *"identify the true bottlenecks behind 'lags out, then crashes' and the path from 15+ to
150+ concurrent sessions, no hardware purchase."*

Axis-by-axis overlap with this wave's decomposition:

| This wave | Prior wave's answer | Where |
|---|---|---|
| A resident footprint | **ANSWERED** — 340 MB/session arrival cost (paired differential, n=1,194), usable denominator 38–42 GB, N≈103–132 resident | `scaling-bottlenecks-2026-08-09.md:30`, axis `01-memory-age.md` |
| B scheduled compute | **PARTIALLY** — 6 staged-inert mechanisms enumerated | `:49-58` |
| C session pollers | **CLOSED, PREMISE REFUTED** — idle session = 0.0031 runnable threads; the poller census was argv contamination | `CONCURRENCY_PROGRAM.md:1318-1344`, `:1695-1709` |
| D worktree lifecycle | **PARTIALLY** — janitor blindness root-caused `8cc16e41`; 558→252 dirs since | below §II.4 |
| E git maintenance | **THIN** — only "git shared store crosses `gc.auto` (6700 loose) within hours at 15×" | `:35` |
| F hook economics | **CLOSED** — `HOOK_CHAIN_COST.md` status `complete`; broker rejected, collapse deferred; hooks run in PARALLEL (measured) | `HOOK_CHAIN_COST.md:1-30`, `scaling-…:151` |
| G session levers | **ANSWERED + the biggest open lever** — MCP children ~507 MB/session, absent from every budget; forecloses 150 on its own | `:31` |
| H terminal | **SETTLED** — kitty; render is NOT a wall (idle panes 0.001 cores, occluded free) | `terminal-for-30-panes-2026-07-31.md:1-40`, `:37` |
| I stores | **PARTIALLY** — `cc-backlog list --blocked` = 92% of turn-end lag (2.1 MB store, ~60 jq forks) | `:39-41` |
| J prior art | **THIS IS ITS SUCCESSOR** — `11-prior-art.md` already did platform-lever prior art | `11-prior-art.md` |
| K/L/O adversarial | **3 adversarial axes already ran** (09, 10, 13) and produced the ranking inversion | `:18-24` |
| M dev-tool residency | **ROOT-CAUSED** — next-server postcss worker storm; remedy is a config flag | `crash-rootcause-2026-08-09.md:151` |
| N orchestration econ | **PARTIALLY** — claude.exe self-bursts (54 procs >4 GB in 11 d, max 41 GB) named as top open follow-on | `:32` |

**Implication:** this wave's value is (a) the ~6 genuinely-open residuals named at
`scaling-bottlenecks-2026-08-09.md:168-171`, (b) verifying the prior wave's P0 items actually landed
(**§IV shows 3 of 7 did not**), (c) the axes it genuinely did not cover (git maintenance depth,
per-store retention design, orchestration RAM economics). **Do not re-derive §I below.**

---

# REGISTER I — SETTLED DECISIONS PER DOMAIN

Status: **LIVE** = binding now · **SUPERSEDED** = replaced, cited so it is not re-adopted ·
**STAGED** = landed but not enforcing.

## I.1 Memory / capacity

| # | Decision | Cite | Status |
|---|---|---|---|
| 1 | **The box dies of VM-compressor SEGMENT exhaustion**, not RAM exhaustion — segments hit 100% of `vm.compressor_segment_limit` (1,629,615) at only ~28% mean segment fill. 8 incidents ledgered. | `crash-rootcause-2026-08-09.md:9-46` | **LIVE** |
| 2 | **Ignition is dev-tooling burst, not the CC fleet.** 18→372 procs in 90 s; 700 procs / 38.9 GB; 736 / 44.7 GB. node fleet = 91% of footprint at both panics. | `crash-rootcause-2026-08-09.md:66-76` | **LIVE** |
| 3 | **kitty and iTerm2 are EXONERATED as cause.** "Force Quit: kitty 4.73 TB" is a coalition/VSZ artifact; kitty's real anon = 0.11–0.17 GB, jetsam band 0, itself a victim. Crash #1 predates the kitty bundle by 2.5 h. | `crash-rootcause-2026-08-09.md:37-45` | **LIVE** |
| 4 | **macOS cannot save itself here.** Whole CC fleet in jetsam band 180 (killed last); `CONFIG_JETSAM` off; kernel `memoryPressure` read **False at the moment of death** in both decoded panics. | `crash-rootcause-2026-08-09.md:29-33` | **LIVE** |
| 5 | **Residency itself does not spend segments** — 34.5 GiB anon = 0.22% of segment limit, swap 0. The crash term is BURST-shaped, permanently. | `scaling-bottlenecks-2026-08-09.md:58` | **LIVE** |
| 6 | **RSS is the wrong instrument** — `ps` RSS charges ~992 MB of shared libs per session (511 MB/session). `vmmap` phys_footprint: 216 MB fresh / 232 MB median. | `CONCURRENCY_PROGRAM.md:1253-1258` | **LIVE** (but see 7) |
| 7 | **232 MB is the RESIDENT figure; an ACTIVE session costs ~2.2 GB — a 10× gap.** Measured: available memory 29.04 → 3.94 GB as 10 sessions worked. | `CONCURRENCY_PROGRAM.md:1877-1878` | **LIVE — supersedes the 232 MB planning figure** |
| 8 | **Session arrival cost re-measured at 340 MB**, not 232; usable denominator 38–42 GB, not 45. | `scaling-bottlenecks-2026-08-09.md:30` | **LIVE** |
| 9 | **MCP children ~507 MB/session are in NO budget** — 22 `chrome-devtools-mcp` procs / 5.1 GB at 10 sessions. ~49 GB at 150 ⇒ forecloses 150-resident alone. **Named the single biggest lever on the box.** | `scaling-bottlenecks-2026-08-09.md:31`, `:126` | **LIVE, OPEN** |
| 10 | **Session age is NOT the enemy** — equilibrium age 3.7 h contributes ≤35 MB. Transcript-span age is length-biased by `--resume` (34.6 h vs true 3.7 h). | `scaling-bottlenecks-2026-08-09.md:70`, `:150` | **LIVE** |
| 11 | **Memory + leaks were EXONERATED once already** (row 13): 30 sessions = 44.7 GB of 64 GiB, and that overcounts shared pages ~2.34×; RSS and fd both flat with age. | `GROUND_UP_REBUILD_MAP.md:30` (§8.5.7) | **LIVE — the "leak" framing is dead** |

## I.2 Load / lag / admission

| # | Decision | Cite | Status |
|---|---|---|---|
| 12 | **Idle sessions are ALREADY FREE** — 0.0031 runnable threads vs a 0.02 target (6× under). At 150 resident, whole fleet + every poller = 0.46 against a ceiling of 20. Phase A closed with **nothing built**. | `CONCURRENCY_PROGRAM.md:1318-1334`, `:1686-1693` | **LIVE** |
| 13 | **`occupancy = concurrency × duration`; fork RATE is not a capacity variable.** 2,376 forks/s at concurrency 4 = +1.6 load; 1,255 forks/s at concurrency 16 = +17.5. *"Make hooks fork less" buys nothing on its own.* | `CONCURRENCY_PROGRAM.md:1270-1273` | **LIVE** |
| 14 | **The binding load term is ACTIVE sessions: 2.5–5 runnable threads each** ⇒ ~4–8 concurrent active on the load-20 gate. Matches the felt 12–15-session pain and all 127/127 historic gate refusals. | `scaling-bottlenecks-2026-08-09.md:34` | **LIVE — supersedes the 1.6/session figure** |
| 15 | **Felt turn-end lag = 3.7 s p50 / 7.7 s p90, and 92% is ONE call** — `cc-backlog list --blocked --json` in the Stop readout (2.1 MB store, ~60 jq forks). | `scaling-bottlenecks-2026-08-09.md:39-41` | **LIVE, UNFIXED** (§IV) |
| 16 | **Chronic CPU load never stalls the box** — control: load 53, 0% idle, 21 sessions, max event-loop stall 13 s. All 91 whole-machine stalls in 47,108 samples occurred during compressor-segment ramps. | `scaling-bottlenecks-2026-08-09.md:41-45` | **LIVE** |
| 17 | **Hooks run in PARALLEL** (observed live + vendor doc). `hook-chain.sh`'s serial model would turn max() into sum() — "fixing" it would double turn-end lag. | `scaling-bottlenecks-2026-08-09.md:151-152` | **LIVE — a trap** |
| 18 | **The fire capacity gate is LIVE and has been all along** — `CC_FIRE_CAPACITY_GATE:-on`, `CC_FIRE_MAX_LOAD_PER_CORE:-2.0`, net-new fires refused `exit 9`; `--recycle` exempt by design. No activation step exists to withhold. | `GROUND_UP_REBUILD_MAP.md:30` (row 13 coordinator correction) | **LIVE** |
| 19 | **Router `KMAX` refuses the 33rd session** (`handoff-fire.sh:5266` turns rc 2 into HALT) — a fleet-self-imposed cap that binds before any kernel limit. | `scaling-bottlenecks-2026-08-09.md:35` | **LIVE, OPEN** |

## I.3 Terminal / render / ptys

| # | Decision | Cite | Status |
|---|---|---|---|
| 20 | **kitty is the pick.** 30–40 panes in ONE OS window at 7–8 total threads regardless of pane count. WezTerm 4.00 threads/pane; Ghostty 4.00/pane linear + highest loaded CPU (27.3% vs kitty 9.5% at 18 panes, byte-identical load). | `terminal-for-30-panes-2026-07-31.md:1-10`, `:52-58` | **LIVE** |
| 21 | **WINDOWS are the expensive unit; panes are nearly free.** Same 30 panes cost 2.35× more WindowServer CPU across 30 windows than in 1; surfaces *inside* a window barely matter (1.17×). | `terminal-for-30-panes-2026-07-31.md:13-16` | **LIVE** |
| 22 | **"Maximally utilise the GPU" is the WRONG goal** — the freeze was compositor OBJECTS (windows/layers/Mach ports), and GPU rendering ADDS them. iTerm2's 5-pane Metal cap is protecting you. | `terminal-for-30-panes-2026-07-31.md:18-30` | **LIVE** |
| 23 | **Render is NOT a wall.** Idle panes 0.001 cores; occluded/hidden windows free; unit = drawn OS window ~0.05 cores; corrected wall 226–440 all-visible-all-active panes; sane 150-topology = 0.4–0.6 cores. | `scaling-bottlenecks-2026-08-09.md:37` | **LIVE — supersedes `CONCURRENCY_PROGRAM.md:1266`'s "~20 panes"** |
| 24 | **ptys are NOT a wall** — 1/pane + 16 static legacy `/dev/ttys` nodes; binds at ~509 panes (3.6× further than render). Three independent methods agree (19 masters / 19 ttys / 35 nodes). | `CONCURRENCY_PROGRAM.md:1238`, `11-prior-art.md:105`, `:243-247` | **LIVE — supersedes the "2.2 ptys/session" scare at `:1675`** |
| 25 | **`repaint_delay 16` / `input_delay 5` are already spent** (vs kitty defaults 10/3). `sync_to_monitor no` is the wrong direction. | `11-prior-art.md:143-144` | **LIVE** |
| 26 | **tmux as residency substrate is REJECTED** — >200 panes ⇒ server OOM/exit (tmux#706, #2408); a tmux pane still allocates a pty, so it buys nothing and adds a SPOF. | `11-prior-art.md:148` | **LIVE** |

## I.4 Exec / platform levers

| # | Decision | Cite | Status |
|---|---|---|---|
| 27 | **Exec-assessment tax: `./script.sh` = 121–213 ms first exec; `bash ./script.sh` = 2.7–3.2 ms. 40×.** Single-threaded per-inode XProtect scan, cache keyed on **(device, inode)** not content. Serialises (8-way = 7% gain). | `11-prior-art.md:22-24`, `:33-46` | **LIVE** |
| 28 | **Per-file symlinks for `~/.claude/{hooks,bin,scripts}` are LOAD-BEARING** — one inode ⇒ assessed once box-wide. A "copy hooks per worktree" refactor would silently add 313 × ~136 ms per worktree. | `11-prior-art.md:61` | **LIVE — a design constraint** |
| 29 | **NOT a hook-path win** — same-inode re-exec is already free. The win is fresh-inode invocations (worktree setup, generated scripts). | `scaling-bottlenecks-2026-08-09.md:112-113` | **LIVE** |
| 30 | **Ad-hoc/clang-signed binaries pay the tax IN FULL** (119–170 ms). Compiling a dispatch binary does not escape assessment. | `11-prior-art.md:40`, `:64` | **LIVE** |
| 31 | **No third-party EDR is installed** — 3 system extensions, all HID drivers. The 121 ms is Apple's own stack; the axis is ruled out. | `11-prior-art.md:66`, `:239-242` | **LIVE** |
| 32 | **Spotlight / `mdutil` / worktree exclusion buys NOTHING** — `.worktrees` returns 0 indexed files (dot-dirs never indexed); a full `find` over all 382 worktrees moves load +4.5%. **Disk and FS are not capacity variables on this box.** | `CONCURRENCY_PROGRAM.md:1650-1652` | **LIVE** |
| 33 | **`kern.maxfiles`/`maxproc` are already ample** — maxfiles 491,520; maxprocperuid 10,666; measured storms peaked at 736 procs. | `11-prior-art.md:106-107` | **LIVE** |
| 34 | **All SIP-off levers are OFF-LIMITS and enumerated so they are not re-derived** — `vm.compressor_mode` (mode 2 additionally risks panic near ~50% compressed, i.e. *worsens* the target term), `tccutil`, system-wide `launchctl limit`, unloading XprotectService, disabling AMFI. | `11-prior-art.md:218-230` | **LIVE** |
| 35 | **Vendor env knobs exist and are unused**: `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`, `MAX_SUBAGENTS_PER_SESSION`, `MAX_TOOL_USE_CONCURRENCY`, `MAX_SUBAGENT_SPAWN_DEPTH`, `PROCESS_WRAPPER`, `DISABLE_BG_SHELL_PRESSURE_REAP`. Workflow concurrency is hardcoded `min(16, max(2, cores−2))` = **8** here. | `11-prior-art.md:199-206` | **LIVE, UNUSED** |
| 36 | 🚨 **`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` exists in the 2.1.220 binary** — the `deep-research.md` claim that nested fan-out "is not operational as of May 2026" is a **parked blocker that may be stale**. Re-verify. | `11-prior-art.md:208-214` | **CONTESTED** |

## I.5 Worktrees

| # | Decision | Cite | Status |
|---|---|---|---|
| 37 | **Disk is FALSIFIED as the worktree constraint** — 116.5 GiB across 198 dirs on a **7.28 TiB** volume. The binding resource is *un-recreatable content with no collector*. | `WORKTREE_MANAGEMENT_V2.md:52-60` | **LIVE** |
| 38 | 🚨 **A bare `git worktree remove` silently destroys gitignored content at exit 0.** `worktree-gc.sh` now carries `--ignored` (AC-1 MET). | `GROUND_UP_REBUILD_MAP.md:27` | **LIVE** |
| 39 | **`worktree-gc.sh:726` dirty⇒KEEP makes a corrupt worktree IMMORTAL.** There is **no staleness gate anywhere in the file** (no `rev-list --count`, no `merge-base`, no `is-ancestor`), so dirty-because-abandoned is indistinguishable from dirty-because-unlanded — and the tree is then re-handed to the next claimant. Fired on the campaign's own worktree, logged twice. | `GROUND_UP_REBUILD_MAP.md:27` (`worktree-gc-infra.log:1373`, `:1611`) | **LIVE, OPEN — ruled row 11's** |
| 40 | 🚨 **`worktree-gc.sh` has NO KILL SWITCH** — 16 `CC_WTGC_*` vars, greps for `DISABL`/`OFF`/`ENABLE`/`KILL` all return zero — while `com.claude.worktree-gc-infra` is launchd-registered. A **scheduled destructive job with no disable**, breaching the campaign's own standing rule. Re-verified open 2026-08-08. | `GROUND_UP_REBUILD_MAP.md:27` (AC-7) | **LIVE, OPEN** |
| 41 | **The janitor reported its own exit code while the population tripled** — 3 days of `verdict=ok` / `skipped` / no-row while the count went to 558 dirs / 427 registered. Fixed `8cc16e41` with four rungs reading facts about the world (`pop_before/after/delta`, `verdict=over-ceiling`, `prev=died-mid-sweep`, `missed_windows_h`) + `--assert`. | `8cc16e41` commit body | **LIVE, LANDED** |
| 42 | **HAZARD RULE (binding on every future session):** never point a test/probe/dry-run of `worktree-gc.sh`, `git worktree remove/prune`, or `git branch -d/-D` at a real worktree or branch — *not even with a flag believed read-only*. Build a throwaway repo. **There is no undo.** | `WORKTREE_MANAGEMENT_V2.md:30-40` | **LIVE — BINDING** |

## I.6 Landing / deploy / activation

| # | Decision | Cite | Status |
|---|---|---|---|
| 43 | **The inertness generator: no affirmative-permission gate may hold an advance; all safety is veto-after.** Four faces: live is a derived view of trunk · verification's only verb is veto · **activations become migrations** · ✅ moves one store right. | `inertness-generator-2026-08-07.md:148-178` | **LIVE (narrowed, see 44)** |
| 44 | **The law NARROWED under adversarial reply:** *"No gate on an actuation path may be unbounded"* — bounded permission is a legitimate tier inside its budget. Pure-veto is currently unsafe: the veto actuator succeeds **3 of 25 all-time**. | `inertness-generator-2026-08-07.md:298-318` | **LIVE — supersedes §3's absolute** |
| 45 | **`migrations/` contract:** one file per migration, lexical order, `# migration-class: mechanical\|c10`, **no default** (an undeclared class is a hard error — both defaults are wrong). `mechanical` runs at converge; `c10` is staged, never run, filed once to `cc-backlog`. | `migrations/README.md:1-60` | **LIVE** |
| 46 | 🚨 **The C10 rescope — "operator runs" → "operator can revert" — is the ONE clause a human must ratify, and IT HAS NOT BEEN RATIFIED.** Live state: 8 migrations, **1 applied, 7 staged c10** (0002–0008). Promoting each is a one-word diff after ratification. | `migrations/README.md:47-52`; `deploy-migrations.sh --status` (live, 2026-08-10) | **LIVE — the single largest blocker** |
| 47 | **`deploy-live.sh` target selection is three-tier with a blocked floor:** T1 VERIFIED (newest green descendant) · T2 DEGRADED (past budget, no RED stamp, loud banner + page) · T3 BLOCKED (all red). A single green-only tier deadlocks by construction — measured 534 identical refusals, 276 launchd runs all exit 1, live layer 91 commits stale, ZERO pages. | `deploy-live.sh:18-36` | **LIVE** |
| 48 | **Converge budget:** `WRAP_LIVE_BUDGET_COMMITS` 25 / `WRAP_LIVE_BUDGET_MIN` 60. **An ADD gets NO budget** — a landed file the live layer lacks breaches at lag 1, because every consumer guard (`[ -f x ] && . x`) is a *silent* skip. | `wrap-ledger.sh:324-330`, `:399-447`, `:525` | **LIVE** |
| 49 | **`ship-land` makes NO full-suite claim** — `GATE_EFFECTIVE_FULL=0` in both lanes, by construction. Optimistic rounds (default 3) + CAS on `(GATE_BASE, GATE_HEAD)` then an in-lock statics re-gate. `SHED=SKIP` at 1-min load ≥ `CC_GATE_MAX_LOAD` (derived: 8/core). | `ship-land.sh:22-71`, `:111-122`, `:190-193` | **LIVE** |
| 50 | **A land makes a VERDICT/NON-VERDICT distinction:** `GATE_RED` (real red) vs `GATE_KILLED` (died to a signal / unattributable). `gate_red()` is the only sanctioned raiser. | `ship-land.sh:201-217` | **LIVE** |
| 51 | **DONE on the ground-up map = designed + landed + adversarially proven + activation STAGED AND PLATTERED. It does NOT mean live.** And: **consume every other row's mechanism FAIL-SOFT** — assume landed-but-inert. And: **check, don't trust the word DONE.** | `GROUND_UP_REBUILD_MAP.md:102-120` | **LIVE — BINDING** |

## I.7 Context / token economy (explicitly out of this wave's scope — verified covered)

| # | Decision | Cite | Status |
|---|---|---|---|
| 52 | **The fill percentage has NO DURABLE DENOMINATOR.** `input_tokens` is durable; the *window* lives only in ephemeral `/tmp/cc-telemetry` (74 of 4,890 = 1.5%, wiped on reboot). `claude-opus-4-8` runs at BOTH 1,000,000 and 200,000. So `CC_CE_WALL=88`, `T=73`, `T_IDLE=35`, `T_BUSY=75` are all percentages of a number the system does not record. | `GROUND_UP_REBUILD_MAP.md:24`, `:54` | **LIVE** |
| 53 | **There is no auto-compaction wall.** 39/39 compactions fleet-wide are `trigger:"manual"`, 0 auto. What kills sessions is a bare `Prompt is too long` refusal — 7 sessions, 10 events, compaction saved **none** (6 of 7 had zero compactions). | `GROUND_UP_REBUILD_MAP.md:24` | **LIVE** |
| 54 | **Published percentiles DECAY** — p95 61.4% (n=59) re-derived to 58.5% (n=11) in 36 h after a panic wiped `/tmp`. Re-derive with `cc-ctx-audit`; never quote. | `GROUND_UP_REBUILD_MAP.md:54` | **LIVE** |
| 55 | **Context stewardship IS capacity** — median turn context ~200K, **68% of quota cost is cache-read**; halving context ≈ **+50% sustainable active work**, bigger than a fifth account. | `scaling-bottlenecks-2026-08-09.md:36`, `:136-137` | **LIVE** |
| 56 | **4 Max accounts sustain ~3.9 concurrent ACTIVE sessions 24/7** (~654 active-h/week); 10 active is affordable ~39% of the week. Residency ≈ free. | `scaling-bottlenecks-2026-08-09.md:36` | **LIVE** |
| 57 | **Fable's cost-justified delta has largely closed** — 2× the price ($10/$50 vs $5/$25) against an Opus 5 card that puts it comparable-or-ahead on many evals. Shrink the frontier apparatus to the residual. | `opus5-adaptation-2026-08-01.md:150-157` | **LIVE, OPEN (D6)** |
| 58 | **`output_config.task_budget` is NOT available on Claude Code surfaces.** Verified negative — do not design around it. | `opus5-adaptation-2026-08-01.md:165-168` | **LIVE** |
| 59 | **Corpus weight:** 94% of the global CLAUDE.md (356 of 377 lines) is duplicated verbatim in the project CLAUDE.md — ~25.8 KB per session in this repo. Total resident corpus ~88 KB / ~22k tokens. | `opus5-adaptation-2026-08-01.md:158-163` | **LIVE, OPEN (D7)** |

## I.8 Program-level acceptance

| # | Decision | Cite | Status |
|---|---|---|---|
| 60 | 🚨 **D1's stress ramp is SUPERSEDED by operator correction.** *"Pressure testing us to crash is not the solution."* An acceptance test that must approach the failure mode to prove safety is mis-specified — prove the MARGIN instead. | `CONCURRENCY_PROGRAM.md:1863-1899` | **LIVE — supersedes `:1836`** |
| 61 | **D1-V2:** D1a margin (`150 × active_cost + baseline ≤ 0.75 × 64 GB`) · D1b natural growth to 40 concurrent, never synthetic · D1c cost/session flat-or-falling. **No criterion requires spawning sessions.** `capacity-ramp.sh up` is diagnostic-only. | `CONCURRENCY_PROGRAM.md:1880-1895` | **LIVE** |
| 62 | **Every 150-session number is an 8× EXTRAPOLATION from a 19-session sample.** Largest count ever observed on this box is **19**. | `CONCURRENCY_PROGRAM.md:1827-1830` | **LIVE** |
| 63 | **Claude Managed Agents is OUT for this fleet — settled, do not re-investigate.** | `CONCURRENCY_PROGRAM.md:657` | **LIVE** |
| 64 | **Master program: 460 backlog items → 6 master efforts.** Firing order **M3 → M1 → M2 → M4 → M5 → M6**. M3 first *because a panic costs every live session*. | `BACKLOG_CONSOLIDATION_2026-08-09.md:206-209` | **LIVE** |
| 65 | **M3 "The fleet bounds its own footprint" IS THIS INVESTIGATION'S SUBJECT.** Falsifier: *"a spawn-depth cap is enforced at the actuator AND `ls ~/Development/.worktrees \| wc -l` is bounded by a reaper that runs."* | `BACKLOG_CONSOLIDATION_2026-08-09.md:149-161` | **LIVE, IN FLIGHT** |

---

# REGISTER II — THE GRAVEYARD

Built-then-abandoned, rejected-after-measurement, or landed-then-reverted. **Why** quoted.

## II.1 Rejected after measurement (do not rebuild)

| Attempt | Verdict | Why (quoted) | Cite |
|---|---|---|---|
| **Per-session poller consolidation into one box-wide daemon** (Wave A's whole brief) | **DECLINED, nothing built** | *"idle sessions were already free"* — 0.0031 vs a 0.02 target; *"the poller census below is **argv contamination** and is retained only as the evidence trail. Do not scope work from it."* `cc-reaper` 19→**0**, `cc-reconcile` 6→**0**, `cc-await-ping` 20→**1**. | `CONCURRENCY_PROGRAM.md:1301-1344`, `1695-1709` |
| **Hook serialisation broker** (Wave B / row 6) | **REJECTED on measured grounds; collapse DEFERRED** | Plan status flipped to `complete` *"rather than staying open with a remainders table"* because an open plan *"re-dispatches workers against work that no longer exists"* — 3 claim→reopen thrash cycles. | `HOOK_CHAIN_COST.md:1-30` |
| **`wrap-ledger --machine` memo** (60→27 git subprocesses per Stop — a real win) | **REVERTED before landing** `5da21949` | *"tests/wrap-ledger.bats goes 3 red with it on and 0 red with WRAP_CACHE=off… All three failures are ⛔-rung cases and the cause is not tunable"* — it staled the ⛔ rung. | `5da21949` body |
| **`taskpolicy -c background`** | **REJECTED, twice** | *"an 84–89× tax"*; superseded by M1-rev demoting to **utility** band instead. `nice` dropped as decorative (PRI stays 31). | `CONCURRENCY_PROGRAM.md:1653-1654`; `GROUND_UP_REBUILD_MAP.md:30` |
| **QoS shadow mode** | **REJECTED** | *"Shadow mode's rejection STANDS on the independent fork-storm."* | `GROUND_UP_REBUILD_MAP.md:30` (addendum 0) |
| **Spotlight / worktree exclusion** | **REJECTED — already free** | 0 indexed files; *"the exclusion premise FALSIFIED — dot-dirs already excluded."* | `CONCURRENCY_PROGRAM.md:1650-1652` |
| **A KEEP gate on ignored content in `worktree-gc`** (AC-2 as specced) | **REJECTED IN-FILE; blast-radius recording shipped instead** | `tests/worktree-gc.bats:776` — *"6 of 6 candidates carry ignored content, so a KEEP gate here would make oracle 3 inert."* **Attempt #3 must adjudicate, never implement the stranded prescription blind.** | `GROUND_UP_REBUILD_MAP.md:27` |
| **Ghostty / WezTerm as the terminal** | **ELIMINATED** | Ghostty: *"4.00 threads/pane linear, highest loaded CPU of the three, 3 processes per loaded pane"*; WezTerm 24.4% vs kitty 9.5% under matched load. | `terminal-for-30-panes-2026-07-31.md:52-58` |
| **Raising iTerm2's 5-pane Metal cap** | **REJECTED** | *"would add ~30 CAMetalLayers and their dispatch queues to exactly the axis that froze the machine. **The cap is protecting you.**"* | `terminal-for-30-panes-2026-07-31.md:29-30` |
| **tmux / abduco as residency substrate** | **REJECTED** | >200 panes ⇒ tmux server OOM; *"a tmux pane still allocates a pty, so it buys nothing over kitty on the pty axis and adds a single-point-of-failure server."* | `11-prior-art.md:148-149` |
| **Compiling a dispatch binary to escape exec assessment** | **REJECTED for that reason** | *"clang-built ad-hoc binary pays the identical 119–170 ms"* (may still be worth it for fork cost). | `11-prior-art.md:64` |
| **Deploying to "activate" the landed `capacity_gate`** | ⛔ **then SELF-RETRACTED** | Original: *"at ceiling 2.0/core it scores REFUSE 10/10 = a permanent dispatch outage."* Retraction: *"at 1.55/core the gate ADMITS, and the IDL holds 1498 `reason:capacity` rows."* Then moot entirely — the file is a symlink, so it was live all along. | `GROUND_UP_REBUILD_MAP.md:30` |
| **D1 stress ramp to 150** | **SUPERSEDED by operator** | *"Pressure testing us to crash is not the solution."* Three counts: validates by approaching the failure boundary · costs the operator their working fleet · measures the wrong quantity. | `CONCURRENCY_PROGRAM.md:1863-1878` |
| **`vm.compressor_mode` tuning** | **OFF-LIMITS + counterproductive** | Requires SIP off; *"mode 2 additionally risks kernel panic near ~50% compressed — i.e. it **worsens** the exact crash term it appears to target."* | `11-prior-art.md:225` |
| **Next.js upgrade to fix the postcss storm** | **REJECTED — no released Next fixes it** | `process_pool/mod.rs` byte-identical v16.2.6↔v16.2.12 (sha1 `4ae43bcf`); upstream #95108 bot-auto-closed 30 s after filing. Remedy is a **config flag**: `experimental.turbopackPluginRuntimeStrategy: 'workerThreads'`. | `crash-rootcause-2026-08-09.md:151` |
| **`reobserve-waiting-recycle`** (branch `cc/reobserve-waiting-recycle`, 2026-07-19) | **REJECTED from the graveyard sweep** | *"superseded by this row's own re-derive."* | `GROUND_UP_REBUILD_MAP.md:24` |
| **`tests/statusline-mail-badge.bats`** | **REJECTED from a graveyard pick** | *"belongs to a 📬 badge that is row 3's surface and that row 3 deliberately did not land, so taking the test alone would have landed a RED suite."* | `GROUND_UP_REBUILD_MAP.md:186-198` |

## II.2 Built, landed, then found INERT or half-built

| Artifact | State | Cite |
|---|---|---|
| **`compressor-sentinel` SIGSTOP actuator** | Shipped 08-05 (`13bfa557`), **91 trips Aug 6–9**, and *"printed `actuator: DISARMED (CC_SENTINEL_ACT=off)`"* at panic #5. Armed 2026-08-09 ~04:2x. Then found **running STALE bytes** on 08-10. **Live process now restarted `Mon 10 Aug 00:04:18` — resolved.** | `crash-rootcause-2026-08-09.md:82-95`, `scaling-…:51`, live `ps -p 64116` |
| **The page channel** | *"structurally cannot act in time — its only consumer is `autonomy-sweep` (300 s cadence, notification-only, 556 accumulated `.page` files). The whole fatal ramp fits inside one sweep interval."* | `crash-rootcause-2026-08-09.md:91-95` |
| **`MEMORY_KNOWLEDGE_V2` M1** (`cc-mem-budget`, `memory-budget.sh`, `MEM_INDEX_BYTE_CAP`) | **Design landed `1761b9ee`; build NEVER did.** `git ls-tree origin/main` empty, `git grep` 0 hits. Subsystem was **overtaken out-of-band** by `16dfe3b5`, which moved the predicate to the PreToolUse chokepoint — *arguably better*. AC1·2·3 ruled **SUPERSEDED, not failed**. Attempt #2 **reconciled rather than rebuilt** — *"not one line of M1 was built."* | `GROUND_UP_REBUILD_MAP.md:25` |
| **Row 3's `asyncRewake` arming** | *"proven, written up, and never wired"* — both greps empty, all 6 commits are `docs()`. `bin/cc-notify` absent from `a8b3a093`'s diff; `mailbox_resolve_key` has **zero sender call sites**. Strand grew 1,747 → **14,763 unacked lines, 99.4% under a key no live reader watches.** | `GROUND_UP_REBUILD_MAP.md:19`; `df5eca64` |
| **Row 4's session-beat oracle** | Declared INERT for 10 days; **all three inertness clauses now FALSE** — 1,102 beat files, wired into both live settings.json, activation `.done` exists. *"A status cell asserting absence decays exactly like one asserting presence, and nothing re-reads it."* | `GROUND_UP_REBUILD_MAP.md:20` |
| **`com.claude.relogin`** | *"was **undeclared** in `fleet.manifest` and never could have been caught (the coverage lint globs `launchd/*.plist`; this plist lives in `launchd/staged/` on purpose), so a tested poller stayed unscheduled and unreported since 2026-07-26."* | `GROUND_UP_REBUILD_MAP.md:23` |
| **`postland-verify`'s revert actuator** | Succeeds **3 of 25 all-time** (landed 3, FAILED 5, skipped 17). Skips ran under *"attempted once, skipped forever"*. Fixed asymmetrically 2026-08-07 (C26). | `inertness-generator-2026-08-07.md:310-336` |
| **`scripts/branch-reaper.sh`** (`f0be3f85`, *"647 of 1354 branches were dead weight"*) | **On trunk, but NOT SCHEDULED** — no plist references it; only a comment in `cloud-reconcile.sh:15`. Live: **394 unmerged branches** today. | live `grep -rl launchd/`, `git branch -a --no-merged` |
| **`scripts/scratchpad-reaper.sh`** (`97d4984b`) | Plist lives in **`launchd/staged/`** — never loaded. | `ls launchd/staged/` |
| **`com.claude.devserver-gc`** | Loaded but **observe-only by design** (`898f8eafb809`, blocked). Its 03:40 run logged `reaped=1` — *"would have removed an ownerless dev server 27 minutes before the 04:07 storm, had `DEVGC_ACT=1` been set."* | `crash-rootcause-2026-08-09.md:96-97` |
| **`com.claude.discovery` · `com.claude.lead-supervisor`** | Loaded, last exit **−15** (SIGTERM) — dead. | live `launchctl list` |

## II.3 The phantom

**`scripts/worktree-pool.sh` — referenced by 15 files; `git log --all` is EMPTY. It has never existed
anywhere in this repo's history.** Consequences, all live: `docs/WORKTREE_WORKFLOW.md:162` asserts
*"Warm pool feeds the front… 10 pre-provisioned slots"* as fact; `handoff-fire.sh:5508` gates on
`[ -x "$POOL" ]`, permanently false, making the ~60-line pool block (`:5509-5566`) **dead code**;
`hooks/worktree-setup.sh:154` references it too. One place already knows — `bin/cc-wave-plan:579`.
*"The mechanism is not merely unbuilt, it is documented as shipped and branched on at runtime, so
every reader and every code path agrees it exists."* Delete-or-build is row 11's call; a
`cherry-pick` from the reso implementations is legitimate. — `GROUND_UP_REBUILD_MAP.md:57` (verified
live: `git log --all -- scripts/worktree-pool.sh` empty; 12 referencing files outside `.worktrees`).

## II.4 Consolidations that DID land

| Attempt | Result | Cite |
|---|---|---|
| **Backlog triage + prune** (`9a65c791`, `a23e7f96`) | 460 items → 6 masters; **161 closed, 0 failed**; 130 of 383 adjudicated (34%) closable without work; the land/gate cluster was **59% dead**. | `BACKLOG_CONSOLIDATION_2026-08-09.md:96-107` |
| **Launcher consolidation** (`23e7f96`… `23551b01`) | *"collapse six name families onto claude + claude-prev"* | commit |
| **worktree-gc janitor rungs** (`8cc16e41`) | Population **558 dirs (Aug 9) → 252 today**; registered 427 → 120. The fix worked. | commit body; live `ls`/`git worktree list` |
| **Store-bounds ratchet** | `config/store-bounds.manifest`, `scripts/store-bounds-census.sh`, `tests/store-bounds.bats` — **ON TRUNK**. | `git ls-tree origin/main` |
| **Reaper-horizon lint** (`bf73e18a`) | *"the four reapers were declared; their justifications had rotted"* | commit |
| **Graveyard TAKE: `cd064644`** (session-continue IDL telemetry) | *"production-proven, its exact IDL vocabulary sits in 208 live records that stopped the day the checkout left the branch."* | `GROUND_UP_REBUILD_MAP.md:24` |
| **Graveyard TAKE: `78de6237`** (statusline refactor) | Recovered by `cherry-pick -x` → `df6b328f`; the coordinator's pointer *"was wrong in BOTH directions"* and this commit *"was not in the list at all."* Re-measured 108 ms → **63 ms**, not the claimed 25–30. | `GROUND_UP_REBUILD_MAP.md:186-198` |

---

# REGISTER III — HARD CONSTRAINTS ANY REDESIGN MUST HONOR

| # | Constraint | Consequence if violated | Cite |
|---|---|---|---|
| **C1** | **The live layer is per-file symlinks into ONE checkout.** For `hooks/ bin/ scripts/`, **landing IS deploying**; the file's own inode is shared box-wide (the exec-assessment win). | A "copy per worktree" refactor adds 313 × ~136 ms of serialised XProtect per worktree and breaks the landing model. | `11-prior-art.md:61`; `GROUND_UP_REBUILD_MAP.md:30` |
| **C2** | **`~/.claude/CLAUDE.md` is NOT a symlink** — a separate real file. Landing the repo copy changes nothing any running session reads. | *"The fix is inert by construction."* Cost a whole ruling once. | `GROUND_UP_REBUILD_MAP.md:54` |
| **C3** | **An ADD gets NO converge budget.** A landed file the live layer lacks is *absent*, and every consumer guard (`[ -f x ] && . x`, `command -v fn && fn`) is a **silent skip**. Measured on `pane-spawn-log.sh`: ledger read `BEHIND 7, within budget (25)` while all 20 instrumented call sites did nothing. | A new file ships INERT and reads green. | `wrap-ledger.sh:94-107`, global CLAUDE.md |
| **C4** | **C10 boundary: agents may not `launchctl` load, edit `settings.json`, register a hook, or deploy.** New wiring is a `c10` migration, staged and never run. **The rescope has NOT been ratified** — 7 of 8 migrations are staged. | Anything needing registration is inert until one human decision. | `migrations/README.md:47-52`; live `--status` |
| **C5** | **No gate on an actuation path may be unbounded.** Every affirmative-permission predicate carries a finite budget whose expiry converts the state into an event (advance+page / escalate / revert). Enforced by `scripts/permission-gate-lint.sh` (blocking leg of `run_gate`), ratcheted per-file by count. | A permission gate rots into a standing state and governs forever (534 refusals, 0 pages). | `inertness-generator-2026-08-07.md:298-308`, `:376-383` |
| **C6** | **A conclusion must reach the ENFORCING store in the same diff.** Docs/plans/queues are advisory behind a diode. Only `settings.json` / PATH / live-revision / launchd enforce. 8 correct analyses changed nothing. | Detection ships, actuation waits — measured 6× at program scale. | `inertness-generator-2026-08-07.md:35-46`, `:219-222` |
| **C7** | **Land-lock + content-verified landing.** Land only via project-local `/ship`; **verify by CONTENT (`git ls-tree origin/main -- <paths>`), never by count** — a count reads 0 after a sibling rebase and proves nothing. Never commit in the shared checkout. | Incident 2026-07-11: `dfacccd` (5 new files) silently dropped by a sibling land while `rev-list` read 0. | project `.claude/CLAUDE.md`; `GROUND_UP_REBUILD_MAP.md:24` |
| **C8** | **Damping is subject+state keyed, with STICKY terminal states.** Any change of reason re-pages immediately; a recovery clears the marker. `CC_DEPLOY_DAMP_S` 24 h. **An alarm that always fires and one that cannot fire are the same alarm.** | Zero-bit alarms; or a real event damped into silence. | `deploy-live.sh:38-39`, `:132-138`; `GROUND_UP_REBUILD_MAP.md:149-166` |
| **C9** | **Render budget is allocated per CLASS, never first-come.** Truncation may shorten a class, never delete one. `+N more` is not a completeness claim. | 55 manual steps through a 6-slot window left 2 of 5 classes unreachable at any depth. | `GROUND_UP_REBUILD_MAP.md:157-166` |
| **C10** | **PARTITION, never FILTER.** A threshold deciding *whether an item is mentioned at all* is where classes go to die (`activation-watch`'s `>24h` gate hid the newest 6 of 12 activations — the campaign's own top levers). | The operator reads a filtered count as the queue. | `GROUND_UP_REBUILD_MAP.md:168-177` |
| **C11** | **INTEGRATE, never overwrite.** `Edit` for every existing file; `Write` only for new. Plan docs accumulate decisions across sessions. Backed by the `backup-before-write` PreToolUse hook. | Destroys cross-session decision history; has happened multiple times. | global CLAUDE.md § File Update Rule |
| **C12** | **The caller cannot be trusted.** Sessions invoke `bats` by hand; any design needing a caller to demote itself was measured to fail 70% of the time. **Enforcement lives at the chokepoint**, and the gate must allow its own cure. | A polite convention buys nothing. | `GROUND_UP_REBUILD_MAP.md:30`; MEMORY `enforcement-must-live-at-the-chokepoint` |
| **C13** | **`pgrep -f` / any argv-keyed predicate is POISONED on this box** — argv carries whole agent briefs. Measured: `cc-reaper` 9 by argv, **0** by command position. Anchor on `ps -axo comm=` / command position, and control the denominator. | An entire wave was scoped on a contaminated census. | `CONCURRENCY_PROGRAM.md:1695-1718`; `capacity-ramp.sh:40-45` |
| **C14** | **`worktree-gc` HAZARD RULE** — never aim any invocation (even "read-only") at a real worktree or branch. Throwaway repo only. **No undo.** And it currently has **no kill switch** while being launchd-scheduled and destructive. | Destroys another row's unlanded rebuild. | `WORKTREE_MANAGEMENT_V2.md:30-40`; `GROUND_UP_REBUILD_MAP.md:27` |
| **C15** | **Fleet-cap: ONE ground-up subsystem per session, ONE or TWO concurrent fleet-wide.** | The skill's own bound; exceeded silently otherwise. | `skills/ground-up/SKILL.md:95`, `:3` |
| **C16** | **Unowned-surface rule:** when a rebuild finds a surface named in no row, **ping the coordinator, never claim it silently**. Rule by EXECUTABLE call sites (a comment is text, not evidence), and never with `--include='*.sh'` (this repo's `bin/` is extensionless). | The grep filter hides the very consumers that decide ownership. | `GROUND_UP_REBUILD_MAP.md:37-46` |
| **C17** | **A status cell asserting ABSENCE decays exactly like one asserting presence, and nothing re-reads it.** Consume every cross-row mechanism FAIL-SOFT; probe for existence evidence. | Row 4's oracle was skipped for 10 days after it went live. | `GROUND_UP_REBUILD_MAP.md:20`, `:112-120` |
| **C18** | **Every behavioural change needs a test AND a mutation check that fails when the change is neutered.** Binding on every S6 wave. Plus: never change `CC_FIRE_MAX_LOAD_PER_CORE` or any gate default as a side effect. | Anything touching spawn/fire/close strands real work box-wide. | `CONCURRENCY_PROGRAM.md:1245-1249` |
| **C19** | **Do not build an acceptance test that approaches the failure mode.** Prove the margin; let the real workload occupy it. No criterion may require spawning sessions. | Operator ruling; cost a whole session. | `CONCURRENCY_PROGRAM.md:1863-1899` |
| **C20** | **Landmine:** `docs/ground-up-payloads/LOCUS-GAP-BRIEF-2026-08-08.md` is **UNTRACKED** — no history, absent from `origin/main`, present only in the shared checkout's working tree, and a backlog item depends on it. **The next `git clean` destroys it.** Verified still untracked 2026-08-10. | Irrecoverable loss. | `BACKLOG_CONSOLIDATION_2026-08-09.md:200-204`; live `git status` |

---

# REGISTER IV — GROUND-UP PROGRAM STATE (so this lands as NEW map entries)

## IV.1 Map rows

| Row | Subsystem | Status |
|---|---|---|
| 1 Landing & deploy · 2 Session lifecycle · 3 Cross-session comms (RE-FIRED 08-09) · 4 Registry & reaping · 5 Autonomy dispatch · 7 Account routing · 8 Context economy · 10 Observability · 12 Daemon fleet · 13 Machine capacity | **DONE** (= landed + staged, not live) |
| **6 Guardrail/hook layer** | **open** — scheduled LAST by design (*"it is every other row's enforcement surface"*) |
| **9 Memory & knowledge** | **BUILT — attempt #2 RECONCILED, not rebuilt** |
| **11 Worktree & warm-pool** | **OPEN, RE-SCOPED — attempt #3 pending.** Live remainders: AC-7 (kill switch) · AC-4/5/6 · the AC-2 adjudication · §6 R-a…R-d |

## IV.2 In-flight worktrees / stranded branches (verified by `merge-base --is-ancestor`)

| Branch | Ahead | Contains |
|---|---|---|
| `gu-memory-knowledge` | 0 | **LANDED** |
| `gu-worktree-warmpool-b` | 1 | `217ca100` row-11 Phase 1 (map says rescued by `cherry-pick -x` — the branch itself is still ahead) |
| `gu13c/gate` | 3 | M10 headroom admission term + M11 load-immune fire suites |
| `gu13c/m4m5` | 6 | M4 watchdog immortality, M5 osa bounds |
| `gu13c/mem` | 5 | capacity-alarm both-families + store-bounds ratchet |
| `gu13c/qos` | 5 | M1-rev utility band + M7 Bash-boundary batch |
| `gu13c/render` | 3 | M8 render census + iTerm2 knob parity |
| `gu13c/wr` | 3 | M13 bounded waiting-recycle reads |
| **`m3-fleet-footprint`** | **3** | 🚨 **`77d33bdc` sentinel-reads-the-kernel · `ea58210f` worktree-gc rungs · `fa2abe97` spawn-gate account-tree** — **THE MASTER M3 WAVE, STRANDED** |
| **`crash-rootcause-2026-08-09`** | **1** | 🚨 **`c6ab83a8` arm devserver-gc (`DEVGC_ACT=1`) — OPERATOR-RATIFIED, packet `99637eaee7b9`, STRANDED** |
| `scale-150` | — | S6 program lead session (read-only reference in `11-prior-art.md:11`) |

⚠️ The map's row-13 cell claims the gu13c/* content LANDED at trunk tip `a73d7e2f` (content-verified);
the branches remaining ahead is consistent with a rebase-land. **Verify by CONTENT before treating
any as recoverable work** (constraint C7). **394 branches are unmerged into `origin/main` overall.**

## IV.3 Live daemon fleet (2026-08-10)

25 repo plists + 3 staged. Loaded: **`com.claude.*` 17 · `com.chrisren.*` 6 · `gl.reso.*` 2 · git-scm 3.**
Running now: dispatcher 51100 · compressor-sentinel 64116 (restarted 00:04:18) · postland-verify 86570 ·
capacity-alarm 73716 · deploy-live 73073 · autonomy-sweep 17772 · cc-reaper 9092 ·
session-search-sweep 53844 · teammate-reap-alarm 66955 · caffeinate-floor 818 · gl.reso.worktree-gc 62745.
**Dead (−15): `com.claude.discovery`, `com.claude.lead-supervisor`.**
🚨 **`bin/cc-fleet:97` pins a hardcoded prefix ALLOWLIST (`com.claude. com.chrisren.`) — the third
family `gl.reso.*` (incl. a *destructive* janitor) is structurally invisible to the census.** *"A
hardcoded prefix allowlist reproduces the original defect on every new family, silently — the
enumeration is not wrong, it is unfalsifiable."* Durable form: enumerate the live domain and report
**unclaimed** labels as a first-class verdict. — `GROUND_UP_REBUILD_MAP.md:28`

---

# ADVERSARIAL SELF-PASS — what I assumed and then checked

**Q1: "You assumed the prior wave's P0 items were done."** Checked. **3 of 7 are NOT.**

| P0 (`scaling-bottlenecks-2026-08-09.md:98-113`) | State today |
|---|---|
| 1 · restart the sentinel | ✅ **DONE** — live proc started `Mon 10 Aug 00:04:18` |
| 2 · guard/remove `setup-task-symlinks.sh` from SessionStart (~4 s CPU / ~800 forks/session, killed by its own `timeout: 5`, output discarded, 2,155 task dirs 97% empty) | ❌ **NOT DONE** — still registered at `~/.claude/settings.json:636`, `timeout 5` unchanged |
| 3 · take the `cc-backlog --blocked` fold off the Stop path (~3.4 s of felt lag/turn) | ❌ **NOT DONE** — `operator-readout.sh:702` still shells `cc-backlog list --blocked`; no memo/cache present |
| 4 · wrap-ledger transcript-keyed memo | ❌ **NOT DONE** — the prior memo was reverted (`5da21949`); the re-scoped key was never built |
| 5 · fix `render-census.sh` (kitty arm; stop charging 100% of WindowServer) | ❌ **NOT DONE** — `:129-130` still `if (cmd == "iTerm2")` / `WindowServer`; **no kitty branch exists** |
| 6 · freshness check in `capacity-ramp.sh breach()` | ❌ **NOT DONE** — `seg_pct()` still `tail -1 … .pct // 0`; **a dead sentinel still reads 0% = healthy** |
| 7 · `bash script.sh` for fresh-inode invocations | ⚪ unverified at scale (call-site conversion) |

⇒ **The prior wave's own conclusion has not reached the enforcing store — constraint C6, seventh
recurrence.** These are cheap, already-researched, and are the highest-confidence items this wave can
name. Items 3, 4, 5, 6 all live in files the fleet already symlinks, so **landing = deploying** (C1).

**Q2: "You assumed git maintenance is untouched."** Checked. `git config --get-all maintenance.repo`
returns **only `~/Development/reso-management-app`** — **claude-infrastructure is NOT enrolled**,
despite 120 registered worktrees. `org.git-scm.git.{hourly,daily,weekly}` are loaded but run against
that one enrolled repo. This repo's own object store is healthy (42 loose, 4 packs, 120 MB), so the
*local* cost is low — but the prior wave's *"git shared store crosses `gc.auto` (6700 loose) within
hours at 15×"* (`:35`) was about the **shared worktree store under load**, and nothing schedules
maintenance for it. **Axis E has a genuine, un-prior-arted gap.**

**Q3: "What axis did you assume irrelevant?"** The **backlog-consolidation master program**
(`BACKLOG_CONSOLIDATION_2026-08-09.md`) — I nearly treated it as bookkeeping. It is the **live
governing plan** for this exact goal, its **M3 is this investigation's subject**, its firing order is
already decided, and its **M3 wave is stranded on a branch**. Any output of this wave that does not
land as **M3 detail or as new GROUND_UP map rows for rows 6/11** will duplicate a claimed effort.
Its named falsifier is the acceptance test this wave should adopt verbatim:
*"a spawn-depth cap is enforced at the actuator AND `ls ~/Development/.worktrees | wc -l` is bounded
by a reaper that runs."*

---

# BLOCKERS / UNCERTAINTIES (named)

1. **The C10 ratification is the single gating decision** — 7 of 8 migrations staged, incl. 0006
   cold-compile admission and 0007 mailbox-wake-arm. A class-C packet was opened 2026-08-09; the
   `devserver-gc` half was ratified (packet `99637eaee7b9`) but **its commit is stranded**.
2. **I could not verify whether the gu13c/* branch content is genuinely on trunk** without a
   per-file content diff — the map asserts it, `merge-base` says the branches are ahead. Per C7,
   an ahead-count is not evidence either way. **Do not delete those worktrees on this report's word.**
3. **`deploy-migrations.sh --status` reports 0 applied beyond 0001** — I did not determine whether
   the converger has run since 0002 was staged, or whether the c10 wall is the only reason.
4. **`docs/plans/CLOUD_OBSERVABILITY.md` is modified in the working tree** (uncommitted, another
   session's) — off-box offload is an active third lane I read only at the edges.
5. **The `deep-research.md` no-recursion claim is contested** by the 2.1.220 binary's
   `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` string. Unresolved; affects this wave's own methodology.
