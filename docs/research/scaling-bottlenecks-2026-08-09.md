# The true bottlenecks: 15 → 150+ concurrent sessions on the fixed M1 Max — verdict and drive plan

**Date:** 2026-08-09 (evening; same day as the crash root-cause arming and the S6 program's own corrections)
**Method:** 13-axis research wave (3 adversarial) over the open gaps ONLY — built on, not re-deriving, `crash-rootcause-2026-08-09.md`, `CONCURRENCY_PROGRAM.md` §S6/S6-UPDATE/S6-DOD, and the four same-day measurement docs. Per-axis evidence: `scaling-bottlenecks-2026-08-09/` (00–13; every number below carries its axis tag).
**Scope (frozen):** identify the true bottlenecks behind "lags out, then crashes" and the path from 15+ to 150+ concurrent sessions, no hardware purchase.

---

## 1 · The verdict

**"Lag" and "crash" are two different bottlenecks, and neither is what the program ranked first this
afternoon. The published wall order (render → memory → ptys → load) inverts: at the real design point
(150 resident / ~10 active) the walls are MEMORY (with three unbudgeted terms) and ACTIVE-SESSION
LOAD — render and ptys are not walls at all. Two fleet-self-imposed caps (router KMAX=32, account
quota ≈ 4 sustained-active) bind before any kernel limit. The crash term is real, orthogonal, and
NOT closed: the one armed guard is running stale bytes, and five other control-plane mechanisms are
staged-inert — the sixth recurrence of "detection ships, actuation waits."**

All three adversarial axes and the two measurement axes converged on the inversion independently
(01, 09, 10, 13). The generating defect of the old ranking: the four walls were priced in
incompatible machine states (render at 150-all-visible, load at 150-all-idle), each against its own
alarm floor rather than a failure point, using constants of which the FIFTH same-day instrument
artifact was still live (09/13: `render-census.sh` sums **iTerm2** CPU on a **kitty** fleet — "107%
of the render floor" was a ratio between two emulators, one absent).

## 2 · The corrected walls, ranked

| # | Wall | Corrected number | Binds at | Axis |
|---|---|---|---|---|
| 1 | **Memory — composite** | session arrival cost **340 MB** (paired differential, n=1,194 transitions; the process itself is 235–270 MB, the rest helpers) — not 232 MB. Usable denominator **38–42 GB**, not 45. | **N≈103–132 resident** before the unbudgeted terms below | 01, 09 |
| 1a | └ **MCP children (absent from every budget)** | **~507 MB/session** measured today (22 `chrome-devtools-mcp` procs / 5.1 GB at 10 sessions; two node procs >2 GB) | ~49 GB at 150 — **forecloses 150-resident on its own** unless MCP is consolidated/lazy for resident sessions | 08 |
| 1b | └ **claude.exe self-bursts (unbudgeted)** | 54 processes exceeded **4 GB** in 11 days, max **41 GB**, ramp up to ~8 GB/min ⇒ ~3 events/hour at 150 resident. Trigger unknown — top open follow-on. | any single event erases the burst margin | 01 |
| 1c | └ toolchain bursts (the crash igniter) | D3's 15% segment bar = **19.9 GB of anon at panic packing** — the entire S6.2 remainder; and S6.2's "19 GB left for bursts" recomputes to **−4 GB** at the corrected constant | ~1 cold compile | 05, 01 |
| 2 | **Active-session load** (the felt daily ceiling) | **2.5–5 runnable threads per genuinely-active session** (measured 27→44 load at 9 active), not 1.6 (a mixed-fleet average) | **~4–8 concurrent active** on the load-20 gate — matches the felt ~12–15-session pain and all 127/127 historic gate refusals | 09 |
| 3 | **Fleet-self-imposed caps** | router `KMAX=8` × 4 accounts — **refuses the 33rd session** (proven on the shipped binary; `handoff-fire.sh:5266` turns rc 2 into HALT). oauth refresh herd: one credential/expiry instant per ~37 sessions, rotating tokens ⇒ a losing racer logs out the whole account, and `heal()` refuses to run while sessions are live ⇒ can never fire at 150. git shared store crosses `gc.auto` (6700 loose) within hours at 15×. `.claude.json`: 171 KB whole-file rewrite, no lockfile. | 32 · any refresh instant · hours · races now | 07, 08 |
| 4 | **Account quota (active half only)** | residency ≈ free; 4 Max accounts sustain **~3.9 concurrent active 24/7** (~654 active-h/week); 10 active affordable ~39% of the week. **68% of quota cost is cache-read at median ~200K contexts ⇒ halving context ≈ +50% active capacity** — bigger than a fifth account. | active work, not residency | 07 |
| — | **NOT walls** (each with evidence) | render (idle panes 0.001 cores; occluded windows free; unit = drawn OS window ~0.05 cores; corrected wall 226–440 all-visible-all-active panes; sane 150-topology = 0.4–0.6 cores) · ptys (~30%, 1/pane+16 static) · pid-wrap (REFUTED: 923 pids/s ⇒ wrap every 108 s, live-observed; the panic correlation was a 2%-prior coincidence) · Mach ports (incident #0 re-explained as WindowServer CPU serialization — amplifier gone under kitty) · fd/kqueue/logd/disk/Spotlight/FS | — | 02, 08, 09 |

**Felt lag, precisely (12):** turn-end lag is **3.7 s p50 / 7.7 s p90** and 92% of it is ONE call —
`cc-backlog list --blocked --json` (2.1 MB store, ~60 jq forks) inside the Stop readout. Chronic CPU
load never stalls the machine (control tonight: load 53, 0% idle, 21 sessions, max event-loop stall
13 s); **all 91 whole-machine stalls in 47,108 sentinel samples occurred during compressor-segment
ramps** — the felt "lags out, THEN crashes" is the ramp's first perceptible symptom, ~4.5 min before
death, and a specific storm detector (not a death predictor: 82 of 91 stalls were on a day the box
survived).

## 3 · The crash side is NOT closed (05, 10)

| Mechanism | State measured tonight |
|---|---|
| compressor-sentinel SIGSTOP actuator | **ARMED but running STALE bytes** — the live process (04:36) holds fd on the 08-07 script (inode-verified); the parent-breaker (`cb21783b`, today 16:40) is on disk, not in the process. Operator restart FILED (`36c3107a9dc3`; my `launchctl kickstart` was classifier-denied). Until then the armed actuator is the version whose own successor commit says "freezing the horde changed nothing." |
| Wave C cold-compile admission (0006) | **Registered in 0 of 5 config dirs** (c10 migration staged, unratified) — the "LANDED" chokepoint executes on no command. AND (G4) it guards `PreToolUse(Bash)` while the Aug-9 storm ignited from **Edit/Write-driven invalidations** of a long-lived `next-server` — it binds the Aug-5 shape, not Aug-9's. Needs ratification AND re-aim. |
| reso `workerThreads` generator kill | set in **0 of 3** eligible apps (tasks filed: `d60fd1f9c375`, `0e4f795b3a20`) |
| devserver-gc | observe-only by design (`898f8eafb809`, blocked) |
| mailbox-wake-arm (0007) / boot-resume plist | unregistered / shipped-unloaded |
| ramp abort sensor | `capacity-ramp.sh:46` reads a **dead sentinel as pct=0 = healthy** — fails green |
| sentinel at scale (10) | trip base-rate 91/4 days; at design-point margin ≈ 0 ordinary jest/pnpm/tsc (all comm=node, >40 MB) enters the cohort, and **no SIGCONT sender exists anywhere in the tree** — frozen legit work would wedge sessions and retain RSS. Precondition for wider arming: replay the 91 trip snapshots through `select_stop_targets` offline to count would-be casualties. |
| Static residency (good news) | residency itself does not spend segments: 34.5 GiB anon today → **0.22%** of segment limit, swap 0. The crash term stays burst-shaped. |

**Meta-finding:** six mechanisms staged-not-enforced is the fleet's own documented generator
(crash doc §5.1) recurring at program scale. The consolidated remedy is ONE class-C ratification
decision — opened this session (see §6).

## 4 · What the walls mean for the target

```
150 RESIDENT on-box:   REACHABLE only with (a) MCP consolidation/lazy-spawn for resident
                       sessions (~0.5 GB/session back — the single biggest lever on the box),
                       (b) the 340 MB constant held (recycle discipline; age is NOT the enemy —
                       equilibrium age 3.7 h contributes ≤35 MB), and (c) bursts bounded
                       (ratified+re-aimed 0006, workerThreads, sentinel current).
                       Otherwise the honest on-box ceiling is ~100–130 resident.
ACTIVE concurrency:    ~4–8 sustained is what BOTH the box (load slope 2.5–5) and the quota
                       (~3.9 sustained 24/7; 10 for ~39% of the week) support. This is the real
                       "15 sessions lag" fix: fewer simultaneously-ACTIVE turns, cheaper turns,
                       cheaper contexts — not fewer resident sessions.
150+ TOTAL:            residency on-box + the active half split between on-box actives and
                       OFF-BOX sessions. Off-box is 2 small fixes away (06): the payload pushes
                       to an invented branch name (vendor allows only the session's current
                       branch — `git switch -c` first, the fix the repo documented and never
                       carried into the payload) and fires skip the existing preflight. 54.5%
                       create → ~91%/fire with 3 retries; 128 backlog items already eligible.
                       Per-session token draw (T3) still unmeasured — the honest off-box number
                       until then is ~10, not 110.
```

**Render/headless correction:** hidden/occluded windows being free means plain kitty tabs already
deliver the "headless" render win with zero build. Wave E's substrate matters for a different
reason than the program thought: **33 pane-less sessions already run in this fleet and are already
invisible** — the registry keys on kitty's reusable small-integer window ids (a fake pane UUID),
subagents share pids, and the headless-precondition "PASS" leaked a pane id into its own probe
child (03). The substrate spec (03: 15+8 edits, identity = session-id + pid,lstart + beat
freshness; wake = migration 0007 + FIFO user-message) is CORRECTNESS work for the fleet that
already exists, not render work.

## 5 · The drive plan (dependency order)

**P0 — free, this week, no decisions** *(each item's evidence axis in parens)*
1. Operator: restart the sentinel job — FILED `36c3107a9dc3` with the exact command (05).
2. Guard or remove `setup-task-symlinks.sh` from SessionStart — today it burns ~4 s CPU / ~800
   forks per session start, is killed by its own `timeout: 5`, and its output is discarded; 2,155
   task dirs, 97% empty. Cutting it cannot regress a thing (04).
3. Take the `cc-backlog --blocked` fold off the Stop path (cache or async) — **~3.4 s of felt lag
   back per turn-end**; compact `backlog.jsonl` (12).
4. Land the wrap-ledger transcript-keyed memo (key = `session_id ⊕ stat -f '%m %z' transcript`,
   2.25 ms; absent-key ⇒ no cache): 1,260 → 216 ms and 133 → 19 git per Stop; fixes the withdrawn
   memo's staleness defect by re-scoping the key, not by fingerprinting stores (04).
5. Fix `render-census.sh`: add the kitty arm, stop charging 100% of WindowServer (4 displays + a
   browser at 73% CPU) to terminal render (02, 09).
6. Add the 5-line freshness check to `capacity-ramp.sh breach()` so a dead sentinel reads DEAD (10).
7. Adopt `bash script.sh` over `./script.sh` for fresh-inode invocations (worktree setup, spawned
   tools): first-exec assessment is 121 → 2.9 ms, inode-keyed (hardlinks share it; copies re-pay).
   NOT a hook-path win — same-inode re-exec is already free (11, 04).

**P1 — the one decision + its preconditions**
- **⛔ Class-C packet (opened this session): ratify the staged c10 migrations** — 0006
  cold-compile admission + 0007 mailbox-wake-arm + boot-resume plist + `DEVGC_ACT=1` — the
  six-mechanism staged-inert gap in one decision. Preconditions attached: the 91-snapshot offline
  replay (bounds sentinel false-positive casualties before wider arming) and the 0006 re-aim at the
  Edit/Write ignition shape (05, 10).
- Build the sentinel's SIGCONT/unfreeze arm — an actuator with no release path is a freeze
  machine at design-point margins (10).

**P2 — the capacity builds (unblocked, parallelizable)**
- **MCP consolidation** for resident sessions (shared daemon or spawn-on-first-use): recovers
  ~0.5 GB/session — the difference between ~100 and 150+ resident (08).
- **KMAX re-derivation**: key the router cap on ACTIVE sessions (its real risk), not resident
  count; today one integer refuses the 33rd session. Also fix `concurrency()` failing OPEN on ps
  timeout — it disarms both KMAX and heal()'s rotation gate (07).
  **DONE 2026-08-13** → `docs/plans/ACCOUNT_ROUTING_V2.md` §15. `KMAX` is now the ACTIVE cap (8,
  unchanged) and `KMAX_RESIDENT` (40) the resident one, selected per row by the INSTRUMENT that
  charged it (`k_src` / `k_cap`, shared with the KF denominator). `concurrency()` returns `None`
  on an unreadable `ps` and all three gates refuse on UNKNOWN — the third being
  `handoff-fire.sh`'s pre-fire sweep, which re-spells the rotation gate as `(.k // 0)` and was not
  in 07 §6.5's count.
- **oauth herd**: jitter refresh within an account + let heal() run with live sessions (08).
- **off-box**: the `git switch -c` payload fix + preflight call + 3-retry wrapper; then measure T3
  per-session draw before claiming any number above 10 (06).
- ✅ **DONE 2026-08-13** (`61e39ef3`, backlog `1c45598a91be`) — **Wave D re-termed** (now
  evidence-backed): admission keys on ACTIVE concurrency (ceiling ~8) with a memory term that can
  actually bind (compressor/swap-aware — 0 of 127 refusals ever came from memory). The design
  point's "~10 active" finally gets its enforcement (09, 13, 07). Shipped as `segments` (50%,
  provisional and re-derivable from its own rows) + `active` (8) + `reserve-active` (1, on proven
  presence) in `scripts/lib/capacity-admit.sh`, with the mid-turn census in
  `scripts/lib/spawn-presence.sh`; D7 closed by decision rather than by waiver. Details and the
  three corrections the build produced: `docs/plans/CONCURRENCY_PROGRAM.md` §S6.6-LANDED. **This
  closes the F3 half that a SPAWN gate can close and no more** — axis 10's thundering-herd path is
  a *wake* of existing residents, which no spawn gate sees by construction, so wake-side damping
  remains open and unowned.
- Standing policy: **context stewardship IS capacity** — median turn context ~200K, 68% of quota
  cost is cache-read; halving context ≈ +50% sustainable active work (07).

**P3 — prove it (only after P1+P2):** D1 ramp 19→40→80→150 with the fixed abort sensors;
D8 re-specified (cold compile at ≥80 needs its synthetic-spawn contradiction resolved, 05);
oauth/KMAX/gc watched at each stage per 08's flip conditions.

## 6 · Instrument corrections this wave adds to the series' ledger

1. `render-census.sh` sums iTerm2 on a kitty fleet (the FIFTH same-day artifact) — and separately
   charges all of WindowServer to render (02, 09).
2. CC transcripts repeat `message.usage` once per content block — **dedup on `message.id` or
   overcount ~2.1×** (bit axis 7's own first pass) (07).
3. Transcript-span session age is length-biased by `--resume` (34.6 h vs a true 3.7 h equilibrium —
   would have manufactured an age effect) (01).
4. Hooks run in PARALLEL (observed live + vendor doc) — `hook-chain.sh`'s serial model would turn
   max() into sum() and double turn-end lag if ever "fixed" (12, 04).
5. The felt-lag replay rig must pin `CLAUDE_CONFIG_DIR` (not `$HOME`) — sessions here run
   config-rooted at `~/.claude-tertiary` (04); and `relay-verbatim.sh` false-fires on greps that
   merely contain `cc-do` (12).

## 7 · Filed / opened this session

| What | Where |
|---|---|
| Sentinel stale-bytes restart (operator, exact command) | backlog `36c3107a9dc3` |
| Class-C c10 ratification decision (0006+0007+boot-resume+DEVGC_ACT, with preconditions) | `cc-decide` packet (this session) |
| MCP resident-session memory consolidation | backlog (this session) |
| Off-box payload `switch -c` + preflight fix | backlog (this session) |
| claude.exe 4–40 GB burst trigger identification | backlog (this session) |
| Everything else in §5 | this doc + the per-axis artifacts; the S6 program (scale-150 session) owns intake — notified |

**Residuals, named honestly:** the claude.exe self-burst trigger (01, no argv in the historic
sampler); WindowServer's true per-pane slope under a closed-browser control (02, operator-gated);
whether kitty enjoys the Developer-Tools exec exemption (11, one settings toggle to test); T3
off-box token draw (06); the Write/Edit event rate (04's one unmeasured rate).
