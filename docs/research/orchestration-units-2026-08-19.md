# Orchestration units and the ~15-session ceiling — what each unit actually costs

**Date:** 2026-08-19 · **Box:** MacBookPro18,2 (M1 Max, hw.ncpu=10, 64 GiB, macOS 15.6) · **Binary:** Claude Code 2.1.220
**Method:** 14-agent measurement wave — 8 measurement axes, 4 adversarial verifiers on the
load-bearing claims, 1 synthesis, 1 completeness critic (3.28 M agent tokens, 61 min, 0 errors) — plus
lead-run instrumentation (two independent `ps`/`footprint` sampler series, n=164). Axis files in
`docs/research/orchestration-units-2026-08-19/`. Labels: **MEASURED** · **INFERRED** · **QUOTED** · **REFUTED**.
Where a verifier refuted a finder, §9 records which I took and why.

---

## 1. THE ANSWER

**The pane belongs to the `name:` parameter, not to subagents — so the operator is right about Agent
Teams and wrong about everything else, and the cost structure is exactly inverted from what a capacity
model would want: the ONE unit that costs a full process + pane + MCP server has NO concurrency cap at
all, while the two units that cost nothing but heap are capped at 8 and 20.**

Three facts carry it:

1. **`Agent({name: …})` — an Agent-Teams teammate/assignee — is a full session in everything but the
   label.** MEASURED: 11 of them alive simultaneously at 11:31:53Z, each a separate `claude.exe
   --agent-id` OS process in its own kitty pane with its own tty, its own MCP server, its own
   SessionStart hook, 18 threads and **382 MB** physical footprint. Eleven of them = 11 panes, 198
   threads, ~4.2 GB, and **12 conversations billed to one account the router counts as one**.
   Hypothesis **CONFIRMED** for this unit.
2. **An unnamed `Agent()` and a Dynamic-Workflow `agent()` create no process and no pane.** MEASURED
   over **937 Agent/Task calls against 565 pane splits, 12 days, 4 account stores**, joined in a
   ±1-minute window: **named 92.3% (585/634) coincide with a pane split, unnamed 15.5% (47/303)**.
   The signal is real and not a busy-fleet artefact — shifting the join by ±900 s collapses named to
   **13.2%** and by ±1 h to 4.1%. And the `name`/`subagent_type` confound **breaks in this
   conclusion's favour**, holding within every type: `deep-research` 154/179 named vs 7/76 unnamed ·
   `general-purpose` 353/370 vs 26/96 · `Explore` 23/27 vs 14/123. Hypothesis **REFUTED** for these
   units. Our N=12 research-subagent default is not a 12-pane, 4.5 GB event.

   🚨 **This corrects the figure this document first published.** §1 originally read *"named 11/11,
   unnamed 0/7 — a perfect control"*, from a **one-day n=18 sample in which `name` and
   `subagent_type` were 100% collinear**, so it could not have tested the confound it claimed to
   control. `A1-VERIFY` prescribed the extension; the completeness critic ran it and it did not
   reproduce as 100%/0%; I re-ran the critic's script (preserved out of `/tmp` as
   [`orchestration-units-2026-08-19/pane-attribution-join.py`](orchestration-units-2026-08-19/pane-attribution-join.py)) independently and got its
   numbers to the digit. **The direction is unchanged and better-evidenced; the crispness was an
   artefact of n=18.** The residual **15.5% of unnamed calls that DO coincide with a pane split is
   unexplained** — the standing hypothesis is temporal coincidence with a sibling teammate wave in
   the same session, and the probe that would settle it (attribute those 47 rows by `sessionId`) is
   filed in §8. Until it is settled, price L1 as *"1 pane → ~0.15 panes"*, not *"1 pane → 0"*.
3. **"Dynamic Workflows run 50–200 agents fine" is a COUNT read as a CONCURRENCY.** MEASURED across
   **231 workflow tool calls in 158 run dirs, four account stores: not one ever exceeded 8
   simultaneous.** The largest run ever attempted here is 229 agents over 7.2 h; its true simultaneous
   peak is 48, and that 48 is **eight parallel `Workflow` tool calls × ≤8 each** — the pools stack,
   they never merge.

**And the ~15 is not a Claude budget.** MEASURED today: non-Claude ambient load = **20.19 load units**
against a `CC_FIRE_MAX_LOAD_PER_CORE=2.0 × 10 cores = 20.0` gate — the gate is at its ceiling with
*zero* Claude units running, while all 14 live Claude units together contributed 5.65 runnable procs
(30%). Independently, the fleet's own utilization log puts the **median pane count at exactly 15**
(p95 37, max 51, n=517). So "~15" is a *descriptive median*, not an enforced limit; nothing in our
stack or Anthropic's enforces 15. What is enforced is listed in §5.

---

## 2. THE COMPARISON TABLE

Every cell is a measurement or an explicit UNKNOWN. Memory is `/usr/bin/footprint -p` **physical
footprint** or `vmmap --summary`, never summed RSS — RSS overstates by **1.29–3.01×**, *non-uniformly*
(pane agent 1.67–1.91×, session 1.29×, bg pty-host 3.01×), so it biases exactly the comparison this
table makes.

| | **1. Plain subagent** `Agent()` no name | **2. Named teammate** `Agent({name})` | **3. Workflow agent** `agent()` | **4. Dispatched pane session** | **5. Backgrounded `--bg`** | **6. Headless `claude -p`** | **7. Cloud** `--cloud` / `isolation:"remote"` |
|---|---|---|---|---|---|---|---|
| **OS process?** | **NO** — 15.5% (47/303) pane-split coincidence vs a 92.3% (585/634) named control, n=937 over 12 d; binary routes `local_agent` in-process | **YES** — `claude.exe --agent-id …`, 11 observed simultaneously | **NO** — `vm.runInContext` in the parent; 12 samples/2 min while 12 agents ran: `claude.exe` count constant at 3 | **YES** | **YES** — worker + pty-host, + a shared daemon | **YES** | **NO** locally — the local process holds an awaited promise |
| **pane / pty?** | **NO** | **YES** — own kitty pane + own tty. **By config, not by product**: `teammateMode:"iterm2"` on all 4 accounts, and our repo exports `ITERM_SESSION_ID` so `wpe()` is true even under kitty | **NO** | **YES** | **NO** — a fixed `200 50` (cols × rows) headless pty; frees the pane entirely | **NO** | **NO** |
| **MCP servers?** | shares parent's | **own** — `ms-365-mcp-server` measured as a direct child of pid 17602, **102 MB** | shares parent's | own, 101–103 MB | **UNMEASURED** — both verifier probes ran in `/tmp`, neither spawned one; this is the single number that flips §5's bg verdict ±20% | own, 101–107 MB | n/a locally |
| **hooks?** | tool hooks only, under the **parent's** session id | **full lifecycle incl. SessionStart** — own `mailbox-wake-arm.sh` child | tool hooks only, under the parent's sid | full | **full — measured**: our own Stop block rendered *inside* the bg worker | full — Stop hooks fired | n/a locally |
| **marginal footprint** | **0.6–11 MB** (2-point parent delta; no process to footprint) | **280 MB proc + 102 MB MCP ≈ 382 MB** | **0.6–11 MB**, same bound | fresh **143.6 MB** (no MCP) → **423 MB tree** @40 min → **449 MB** @5 d | **+302 MB / job** marginal, on a **300.1 MB fixed pool** (daemon 117.8 + spare 97.5 + its pty-host 84.8) | **185–199 MB + ~101 MB MCP ≈ 295 MB** | **0 local** |
| **threads** | ~**+1.5 each** (+12 threads for 8 agents, vs an 18-thread fresh-session baseline) | **18** | ~**+1.5 each**, same measurement | 16–19 fresh, 28–30 mature | **+25.5 / job** (fixed pool 23) | 15 | 0 local |
| **runnable-thread cost** | 0.315 R-procs ≈ **0.489 load units** while actively tool-calling | **0.020–0.088** R-procs API-blocked; **UNMEASURED mid-turn** (never caught one working) | same as col. 1 — same execution path | 0.041 idle / 0.216 working R-procs | `NI=5` but **`PRI=31`** — same QoS band as foreground; observed state `RN`, i.e. **in the load numerator** | **0.97–1.30 R-procs ≈ 1.5–2.0 load units** — the most load-dense unit measured | 0 local |
| **billed to** | **the parent's account, always** | **the parent's account, always** | **the parent's account, always** | **whichever account was chosen at launch — the ONLY routable unit** | the daemon's `CLAUDE_CONFIG_DIR` | routable at launch | same subscription meters; **QUOTED**: "no separate compute charge for the cloud VM" |
| **governed by which cap** | **20 concurrent** (`Et_`, `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`), 200/session lifetime, depth 3 (**=1 here**, `.zshrc:484`), and per-turn tool concurrency 10. Two bypasses: gate `tengu_amber_kestrel`, and `ultracode && effort=="xhigh"` | 🚨 **NONE on concurrency.** The teammate branch calls `N()` (lifetime 200) and never `U()` (`takeConcurrencySlot`). All **three** backends traced — `$W_` split-pane, `UW_` tmux, `ivd`→`PW_` in-process — **none** takes a slot | **8 concurrent, per workflow RUN** (`Xq_(e)=min(16,max(2,e−2))`, `Qq_=Xq_(os.cpus().length)`, 10 cores ⇒ 8) · **1000** `agent()` calls per run · 4096 items/`parallel()` (**doc-only, enforcement site unlocated by two agents**) | our `CC_FIRE_MAX_LOAD_PER_CORE` 2.0 + 4 GB headroom floor; router `KMAX`=8, `KMAX_RESIDENT`=40 | 🚨 **NONE.** No worker-count cap exists in the bg scheduler (positive-controlled: `tengu_bg_max`/`maxWorkers`/`bg_max` = 0 hits, `tengu_bg_` = 247). Only gate = `kern.memorystatus_vm_pressure_level ≥ 4` (CRITICAL) | none of ours | 50 concurrent remote workflow agents (`Zq_`) — **unreachable on 2.1.220** |
| **visible to OUR gates** | `agent-teams-enforce.sh` + `frontier-spawn-gate.sh` (PreToolUse `Agent`). Invisible to `k`, `k_work`, `cc_sp_trees`; charges `cc_sp_active` **0** (dedupes to the lead) | **every census we own** — `k`, `cc_sp_trees` (parent is `cc-pane-runner`, not in-family ⇒ own tree), `cc_sp_active` (own beat, own pid), `cc-registry` row, mailbox, `cc-teardown`. The **6-concurrent-teammate cap is prose only** — one hit repo-wide, `skills/agent-teams/SKILL.md:317` | 🚨 **NONE — 0 of 7.** MEASURED: 9 agents minted 11:43:46–49Z; `agent-tool` rows in `idl.jsonl` in that window = **0** while the same ledger took **874** other rows | `handoff-fire` capacity gate (load + headroom); everything except segments/active/tree | 🚨 **every pane-keyed rail is blind** — `cc-where` rendered 11 panes and zero of 3 live workers; `cc-registry` grep → no match. CC's own `sessions/<pid>.json` **does** see them (`kind:"bg"`) | excluded from `k` **by design** (`-p/--print` filtered in argv[1..6]) | none — but `cc-where` already models an `offbox` kind |

**Two structural notes the table cannot hold.**

- **Every per-session sensor we own sees N in-process agents as 1.** MEASURED: 297 `bash-commands.log`
  rows from 8 agents, all under one session id. That is the same blindness in the close protocol, the
  wake path, and `k_work`.
- **`grep -i claude` misses 52% of the claude-attributable process set.** Attributing by **ancestry**
  finds 128 processes; the naive name grep finds 61. The 67 missed include **all 13
  `ms-365-mcp-server` processes at 101–103 MB each ≈ 1.3 GB** — the second-largest Claude-caused
  memory class on this box, with no "claude" in argv *or* `p_comm`. **Attribute by ancestry, never by
  name.**

---

## 3. WHY WORKFLOWS FEEL UNLIMITED

The mechanism, stated so it survives contact with the truth:

**A workflow may CALL `agent()` 1000 times; it may only RUN 8 of them at once; and every one of those
8 is a generator inside the parent's own node process.**

- **The cap, read out of the binary and confirmed three ways.**
  `grep -a -o -b 'Math\.min(16,Math\.max(2,[a-zA-Z_$]*-2))'` → `234411135:Math.min(16,Math.max(2,e-2))`;
  `Qq_=Xq_(JSd.cpus().length)` @234433389, `JSd=require("os")` @234433351. Positive control: 375 lines
  hold `Math.min(`, and `Math.min(16` is unique. **10 cores ⇒ 8.** Scope is **per workflow run**, not
  per session. Excess **queues**; nothing is dropped.
- **Confirmed by live queueing, on a run whose demand exceeded the cap.** This 13-agent wave *is* a
  Dynamic Workflow. Eight agents start inside **2.1 s**; agents 9–12 each start **4–6 s after a
  predecessor's last write** (+906.7 s, +932.9 s, +1003.7 s, +1111.4 s). Sweep-line max simultaneous =
  **8**. That is a semaphore of 8 releasing and re-acquiring — not an interval-estimator artefact.
- **Confirmed by every workflow we have ever run.** 231 tool calls, peak distribution
  `{1:40, 2:26, 3:16, 4:20, 5:12, 6:26, 7:9, 8:82}`, **peaks >8: 0 of 231**. Largest single call: 83
  agents, still peaking 8.
- **In-process, positive-controlled.** The workflow module holds **0** occurrences of `child_process` /
  `spawn(` / `execFile` / `--agent-id` / `use_splitpane` while the binary holds 138 / 119 / 42 / 19 / 3
  elsewhere. Live: 12 samples over 2 min while 12 agents ran — `claude.exe` procs constant at 3,
  `--agent-id` procs constant at 1 (an unrelated leftover teammate). Zero new processes, zero panes.
- **Where the "50" and the "200" actually come from.** `Zq_ = 50` is the **remote/cloud** agent
  limiter — real, but unreachable on 2.1.220. `QSd = 1000` is a lifetime call cap per run. `vt_ = 200`
  is the per-session *subagent lifetime* cap (added 2.1.212, **removed 2.1.224**). The CHANGELOG
  sentence that seeded the operator's number is 2.1.154: *"it orchestrates work across tens to
  hundreds of agents in the background."* True as throughput. The tool's own doc string says *"only
  ~10 run at any moment"* — **that is a 12-core number; here it is 8. Do not quote the ~10.**
- **The pools stack, they never merge.** `takeConcurrencySlot` occurs **0** times in the workflow
  module (6× binary-wide). So one session can hold **8 workflow + 20 subagent + N teammates = 28+
  in-process agents**, with three separate counters and **no aggregate**. The account router counts
  *sessions* and is blind to all of it.
- **Not configurable.** No env var reads the workflow cap (the binary's env registry holds only
  `DISABLE_WORKFLOWS`, `WORKFLOWS`, `WORKFLOW_SIZE_WARNING_{AGENTS,TOKENS}`). The only lever is
  `os.cpus().length`.

---

## 4. WHAT EACH UNIT COSTS IN QUOTA

Every in-session unit is **structurally unroutable**. Closed, not merely suggested: the agent process
inherits exactly one identity input (`CLAUDE_CONFIG_DIR`), carries **zero** credential-shaped env vars
(positive control passes), **no config dir holds an on-disk credentials file** (0 of 4), and the
keychain service is `sha256(NFC(dir))[:8]` with all four derived hashes present. There is no path by
which an `--agent-id` process can bill a different account.

| unit | measured cost | source |
|---|---|---|
| named teammate, live 11-agent wave | **0.22–0.68 pp each, 5.58 pp total in ~15 min** | per-agent token sums, deduped on `message.id` (verifier reproduced all three sampled agents **byte-exact**) |
| Workflow agent (2,704 runs / 159 workflows) | median **0.213 pp**, mean 0.268, p90 0.478 | median agent emits **230 output tokens** and pays **109 K cache-creation to boot** — ~95% arrival tax |
| a whole workflow | **12–40 pp**; the 229-agent run = **39.1 pp = 39% of an account's 5-hour allowance** | — |
| fleet, last 60 h | 612 pp-equivalent: main-session 377 (62%), **teams-agent 167 (27%), workflow-agent 68 (11%)** | **38% of what this fleet spends is already spent by unroutable units** |

**Fan-out concentrates identical burn 4×.** The same 8 units of work cost the same total pp either
way; 8-on-one-account charges one 100-pp meter, 8-over-four charges 25% to each of four. Spreading is
a free 4× — available to exactly one unit type. Measured consequence: `next3` hit 100% of its 5-hour
window on 08-18, and **68% of the output that saturated it was teams-agent output**.

**And the same 4× axis concentrates a worse, discontinuous risk (NEW, INFERRED).** Agents inherit the
parent's config dir ⇒ the same `.oauth_refresh.lock` and the same *rotating* refresh token
(`tengu_oauth_refresh_legacy_lock_contended` is in the binary; token TTL measured ~8 h). An 11-agent
wave puts **12 contenders on one lock**; the documented blast radius of a lost race is an
**account-wide logout**, which has no reset to wait for. Corroborating and independent: Anthropic's
**2.1.225** changelog entry is *"Fixed parallel Claude Code sessions all logging out simultaneously
after wake-from-sleep when many sessions share one credential store"* — our 4-account fleet exactly.
We are on 2.1.220.

---

## 5. WHICH WALL BINDS FIRST

**The duty-cycle distinction is load-bearing and was the single biggest error in the wave.** Resident
≠ active. MEASURED fleet-wide over 517 minutes: `k_work / k` = **0.36** (median). A pane is working
about a third of the time. Any comparison of a *working-unit* budget against a *resident-pane* count
without that factor is wrong by ~3×.

### For a resident pane session (the unit the operator counts)

| # | Wall | Binds at | Evidence |
|---|---|---|---|
| **1** | **Our own load gate** — `CC_FIRE_MAX_LOAD_PER_CORE=2.0 × 10 = load1 20.0` | **~4–8 *mid-turn* sessions** (2.5–5 runnable threads per genuinely-active session) — and **the ambient alone already exceeds it**: non-Claude load measured **20.19** with zero Claude units | 19 real refusals in 9 days, all `under_test:false` (8.6% of production evaluations). Worst: `load 118.95 on 10 cores = 11.89/core`. Counter-evidence that it is *not* a residency cap: at load 22.70 the box carried **20 resident trees with only 3 mid-turn** |
| **2** | **Quota — the weekly meter** | **crossover at 26 resident panes (17–30)** | Model-free: weekly-meter slope ÷ mean `k_work`, 5 account-windows ⇒ **6.08 %/day per working unit** vs a 14.29 %/day allowance ⇒ **9.4 working units fleet (6.2–11.0)** ⇒ 9.4 ÷ 0.36 = **26 panes**. Cross-check: predicts `next` at 109%/reset; the readout independently renders **111%** |
| **3** | **Terminal panes** | **~30** (iTerm2 froze at ~30 concurrent CC panes — prior repo work) | kitty currently carries 11–13 panes; untested at 30 in this wave |
| **4** | **Memory** | **~70 sessions / ~70 pane agents** (26.6 GB available ÷ ~375–382 MB) | `vm_stat`: free 366,838 + inactive 1,224,126 + purgeable 31,621 pages × 16 KiB. **Swap 0.00 MB**; 8.0–9.6 GB already in the compressor at 92% memory use. **This is a RAM-bytes wall and nothing else.** The compressor-segment failure mode this cell used to name here is not a residency term and does not belong in this ordering — §5a |

⇒ **Ordered: load gate (~4–8 active / felt ~15) < quota (26 panes) < terminal (~30) < memory (~70).**
The prior repo ranking "memory > active-load" does **not** reproduce at today's numbers. The axis that
actually kills this box is in **§5a**, and it is not in this ordering at all.

### 5a. The segment axis is not a residency wall — per-unit is measured ~0, not unmeasured

Wall #4's evidence cell used to end *"the failure mode is compressor exhaustion / watchdog panic, not
OOM"*. True of the box, wrong in this table: naming a failure mode inside a **resident-capacity**
ordering implies a per-unit segment cost that could be divided into `vm.compressor_segment_limit`
the way 26.6 GB was divided into 375 MB. **No such quotient exists, and that is a measurement, not a
gap.**

**MEASURED — the per-unit resident segment cost of all seven units is ~0.**
`session-capacity-ceiling-2026-08-09.md:409-411` states it as a property of the term:
*"it is **not** a session-capacity term — at steady state a session compresses nothing, so `seg_pct`
stays ~0 regardless of session count. It is a burst guard, and it produces no session capacity
number."* Three independent readings on this box agree, against a limit of **1,629,615** segments:

| Fleet state | Segments | % of limit | Source |
|---|---|---|---|
| ~20 sessions · 90 Claude procs · 9.7 GB Claude RSS · 45–47 G used · swap 0 | 106,060 in-core | **6.5%** | `machine-lag-and-kitty-2026-08-06.md:43` |
| armed daemon, ordinary fleet, 9 h uptime | `"seg":0,"lim":1629615,"pct":0.00` | **0.00%** | `session-capacity-ceiling-2026-08-09.md:404` |
| the quiet box, both gate terms side by side | `segs_in_core 0 + segs_swapped 0` | **0.00%** | ibid. `:391` |

⇒ **A resident unit compresses nothing, so it consumes no segments.** Even charging the *entire*
segment stock of the 08-06 anchor to Claude — the most hostile apportionment available — puts the
stock-term wall at 1,629,615 ÷ 106,060 × 20 = **~307 sessions**, looser than memory's ~70 and looser
than every wall above it. That is the arithmetic's own way of reporting that the axis does not bind
on residency. The decisive datum is that segments **drain when the burst exits**: at panic #6 the
sentinel logged a peak of **88.5%** that *self-recovered to 3.4%* when one wave left, before a second
wave killed the box 4 minutes later (`crash-rootcause-2026-08-09.md:58`). A residency term does not
do that.

**What the axis is.** An **ignition** wall, measured six times: *"hundreds of 60–180 MB near-idle
`node` interpreters appearing in 1–3 minutes"* — 18→372 procs in 90 s; 700 procs / 38.9 GB; 736 /
44.7 GB — flooding the compressor until it exhausts segment structures at **~28% mean fill**, while
the compressed-pages gauge reads 31–32% "OK" and the kernel's own `memoryPressure` reads **False**
(`crash-rootcause-2026-08-09.md:20-26`). Ignition is *"never CC residency"* and is
**harness-independent** (`jcode-due-diligence-2026-08-11.md:54`). For the record the class is **six
panics, 5 of 8 ledgered events** — panic #2 (07-31) was an unrelated spinlock timeout and incident #0
a WindowServer mach-port freeze.

**The per-unit number that DOES discriminate the seven units is a burst-ignition surface**, not a
segment count. A unit can ignite the measured storm only if it can run a repo's dev toolchain — which
needs a tool-call path and a repo cwd. Read straight off §2's own rows:

| Unit | Ignition surface | Why |
|---|---|---|
| **4.** Dispatched pane session | **full** | own process, own repo cwd, full hooks |
| **5.** Backgrounded `--bg` | **full, and unbounded** | full hooks; no cap of any kind |
| **6.** Headless `claude -p` | **full** | own process, routable cwd |
| **2.** Named teammate | **full** | own process, own worktree cwd |
| **1.** Plain subagent | **full, charged to the parent** | no process of its own, but its Bash calls run in the parent's cwd |
| **3.** Workflow agent | **full, charged to the parent** | same execution path as col. 1 |
| **7.** Cloud | **none** — zero local segments | runs off-box |

⇒ **Six of seven units carry the full ignition surface, and the two cheapest ones (§2 cols. 1 and 3)
carry it at zero marginal footprint.** So **L1 buys nothing on the axis that kills the box**: moving
fan-out from named teammates to workflow agents moves 382 MB → 0.6–11 MB of *bytes* and leaves the
*toolchain bursts* exactly where they were — now behind **zero** of our seven admission gates (§7).
That is §1's asymmetry restated on the failure mode that actually fires.

**Nothing per-unit needs adding to the meter.** `compressor-sentinel.sh` computes
`(segs_in_core + segs_swapped) ÷ vm.compressor_segment_limit` every 10 s from cheap sysctls and trips
on **level AND rate** (>15% of limit *and* >600 segments/s), deliberately far below the ceiling, on
the way up. Because the term is a burst term, the **rate** arm is the load-bearing half — a
level-only guard on a quantity that idles at 0.00% would never fire.

### For an in-process agent (workflow / plain subagent)

| Wall | Binds at |
|---|---|
| memory | **~2,400** (26.6 GB ÷ ~11 MB) |
| load, all simultaneously mid-tool-call | **~37** (18 available load units ÷ 0.489) |
| **the product's own cap** | **8** (workflow, per run) / **20** (plain subagent, per session) |

⇒ **The binding wall for the cheap unit is the cap, not any resource — by one to two orders of
magnitude.** That is the asymmetry the whole document turns on.

### For the units nobody counts

- **Backgrounded `--bg`:** no cap of any kind. The sole admission gate is
  `kern.memorystatus_vm_pressure_level ≥ 4` (CRITICAL) — **MEASURED at 1 (NORMAL) with 59 G of 64 G
  used and 8.0 GB compressed.** And when it *does* fire it **sheds then admits**; there is no path
  that rejects a job.
- **Headless `-p`:** **~8.9 concurrent starts** against the load gate — the arrival cost, not the
  residency cost, is what binds.
- **Cloud:** zero local slots. Not bounded by anything on this box.

---

## 6. LEVERS, RANKED BY MEASURED HEADROOM PER UNIT OF EFFORT

### Positive

| # | Lever | What it buys (measured) | Risk | Available today? |
|---|---|---|---|---|
| **L1** | **Stop using named teammates for fan-out; use Workflow agents or unnamed subagents** | Per agent: **382 MB → 0.6–11 MB**, **1 pane → 0**, **18 threads → ~1.5**. The observed 11-teammate wave (**11 panes / 198 threads / ~4.2 GB**) becomes ~0.1 GB, 0 panes, +17 threads | 🚨 **A running Workflow has NO abort path in anything we own** — no pane (so no `cc-teardown`), no `shutdown_request` (not a teammate), no `claude stop` (not a bg job), no registry row, no mailbox. Our largest historical run is **229 agents / 7.2 h / 39 pp**; if one goes wrong the only lever is killing the parent session, which takes the operator's context with it. **Bound it with `budget.total` at author time — that is the only brake that exists.** Also loses **all 7** of our Agent-tool gates for workflow agents (§ L8 is the mitigation); caps at 8 (workflow) / 20 (subagent); breaks the "one teammate = one pane you can look at" operating model. 🚨 **And it buys nothing on the axis that kills the box** — a workflow agent's Bash calls run in the parent's cwd, so it keeps the *full* toolchain-burst ignition surface at zero marginal footprint (§5a) | **YES — zero config** |
| **L2** | **Route fan-out work as dispatched sessions across the 4 accounts** | **4× on quota** (four 100-pp meters instead of one) **and 4× on the OAuth-refresh herd** (≈3 contenders per lock instead of 12) | Costs a real pane + ~423 MB per unit — the expensive unit. Only worth it for work that runs long enough to amortise | **YES** |
| **L3** | **`claude --cloud "<task>"`** | **Zero local slots, zero local memory, zero panes**, and QUOTED: *"no separate compute charge for the cloud VM"*. Proven live on this account: `RemoteTrigger list` → HTTP 200, cloud env `env_017yBYRpWo1riDX3bs6h7fkV`, one job already fired | 2.1.220 **refuses `--print` and requires a TTY** — fire it *into a pane*; `handoff-fire` already does this. The cloud VM clones the **GitHub remote at your current branch, not your local checkout** (unpushed work invisible unless `CCR_FORCE_BUNDLE=1`). `--teleport` is one-way (cloud→terminal). `claude -p "msg" --cloud <id>` is exempt from the TTY rule and IS scriptable | **YES** |
| **L4** | **Non-Claude backends — Codex CLI, Pi·Codex** | The **only** units in this wave that consume **neither** ceiling: no Claude pane, no Claude meter. Both render `✅ routable` on a ChatGPT Plus plan | **No axis in this wave owns them** — capability, cost and fidelity are unmeasured here | **YES, already routable** |
| **L5** | **`teammateMode: "in-process"`** (4 settings.json files) | Removes a teammate's process + pane + MCP server. The binary carries a real in-process backend (`ivd`→`PW_`) plus a fallback path | 🚨 **Does NOT restore governance** — all three backends skip `takeConcurrencySlot`, so in-process teammates are un-capped too. Breaks every pane-keyed rail for teammates. **The in-process teammate's actual cost is UNMEASURED** | **YES, but unpriced — measure first** |
| **L6** | **Advance the binary 2.1.220 → ≥2.1.225** | **2.1.221** memory-leak fixes in long sessions + reduced per-tool-call CPU with many MCP tools · **2.1.225** fixes the mass-logout-on-shared-credential-store failure (§4) · **2.1.229** staggers same-prefix workflow siblings for prompt-cache reuse · **2.1.235** cuts cloud-session render cost | **2.1.224 REMOVES the 200/session spawn cap**, leaving depth — **which is pinned to 1 here** — as the only lifetime bound | **YES** — gate it through `cc-version-audit` / `cc-upgrade-gate` |
| **L7** | **Adopt CC's own `sessions/<pid>.json` registry** | PID-keyed, **self-GC'ing**, carries `status` + `waitingFor:"permission prompt"` + `kind:"bg"` **for free** — a large part of what our beacon/inbox-guard machinery reconstructs — and unlike `cc-where` it **already sees paneless workers** (3 rows, one per live bg worker; the unclaimed spare had none) | A second registry to reconcile against our 19-row pane registry | **YES — cheap** |
| **L8** | **Give the Workflow path a chokepoint** | Closes the largest governance hole found: 7 gates bypassed by changing orchestration unit | The `Agent` PreToolUse matcher provably does not fire for workflow agents; whether that is a **tool-name** gap (matcher edit) or a **spawn-path** gap (new chokepoint) is unresolved — the fix differs | needs the 2.1.220 tool list |
| **L9** | **Make `k_work` recurse** | Fixes a measured inversion: **19 invisible writers vs 11 visible (63%)**; `.claude-quaternary` read **0 visible / 10 invisible**, so the router scored the busiest account as the idlest and `cc-wave-plan` hands it the **widest** allowance | May over-refuse: 10 workflow agents *are* 10 API streams but share one 5-h window position. Compounded by `k_work` reading `None` in **73%** of samples (walk over budget) | **YES**, one-line walk change — but decide the semantics first |

### Negative — levers that look attractive and are refuted by measurement

| # | Refuted lever | Why |
|---|---|---|
| **N1** | *"Raise `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` (20)"* | **Wrong lever.** The capped path is the cheap one. The expensive path — named teammates — has **no concurrency cap to raise**; 200 of them is permitted by the binary and would kill the box long before it refused |
| **N2** | *"Force in-process teammates to get the cap back"* | **REFUTED.** All three teammate backends (`$W_`, `UW_`, `ivd`→`PW_`) were traced; **none** invokes `takeConcurrencySlot`. In-process removes the cost, not the ungovernedness |
| **N3** | *"Backgrounding is a lighter execution mode"* | **REFUTED in both directions.** It is not 1.9× worse (that charged a one-time 300 MB pool to the first job and compared a bg *tree* against a foreground *process* whose 95.6 MB MCP child was never counted): measured slope over 1→3 concurrent jobs is **+302 MB / +25.5 thr per job** vs a real foreground **tree** at **423 MB / 30 thr** — *parity*. But it is not lighter either: `NI=5` with **`PRI=31`**, the same QoS band as foreground, observed `RN` |
| **N4** | *"CC's own memory admission gate protects us"* | **REFUTED by measurement.** `kern.memorystatus_vm_pressure_level` read **1 (NORMAL)** at 59 G/64 G used with 8.0 GB compressed. The gate needs **≥4 (CRITICAL)**, and even then it sheds-then-admits |
| **N5** | *"The evictor is the ceiling-breaker — N conversations, K live processes"* | **REFUTED as stated.** K falls by **wall clock, not pressure**: a *finished* bg job held **217.8 / 207.4 / 225.2 MB and 18–19 threads two minutes after reporting `state:"done"`**, and the 60 s fast path needs the CRITICAL pressure that N4 shows never arrives. Residency is **1 hour**, flat |
| **N6** | *"`isolation:'remote'` moves work off-box"* | **REFUTED.** Gated on `tengu_neapolitan` (server flag, **default false**) and — in the Agent-tool path — it **does not raise**: it silently becomes a **LOCAL worktree agent**, logged only on the debug channel. Anything assuming it offloaded is spending local slots. (In the *workflow* path a sibling axis read a hard `throw "not available in this build"`; see §8 Q6) |
| **N7** | *"Halving context ≈ +50% active capacity"* — still standing policy in `scaling-bottlenecks-2026-08-09.md:36,150` | **REFUTED.** That figure priced 68% of quota as cache-read; the 2026-08-16 meter experiment measures Opus-5 cache-read at **0.000** (p95 ≤ 0.0017 over ≥590 M tokens), and `exchange-rate.md:223` gives the *opposite* advice. Two repo documents contradict each other and neither cites the other. ~~**Needs a filed decision, not another measurement.**~~ ✅ **DECISION FILED 2026-08-24** (class A, backlog `564d151b76e5`; `Z-completeness-critic.md` G15 was right that the synthesis named this and filed nothing). Struck at both sites; the two docs now cite each other. Ruling + reasoning: `scaling-bottlenecks-2026-08-09.md` **§2a**. It survives §C6's *bound-not-a-point* caveat — the 68% premise fails under the API-list hypothesis too (~28%), so the lever is worth 0% to ≤+16% either way. Corrected, that doc's "~3.9 concurrent active 24/7" becomes 3.9 / 0.32 = **12.2** under the free hypothesis (~5.4 under API-list); rank 4 now carries §C4's **model-free 6.2–11.0** instead, which owes nothing to either fit and brackets both. 🚨 **"Both sites" was two of three — SWEEP CLOSED 2026-09-02, §2c.** §2a struck `:36` and the standing-policy bullet, §2b chased the origin and the jcode cluster, and both missed **§4 of `scaling-bottlenecks` itself**, which restated the lever in the summary's own words (*"cheaper contexts"* as part of *"the real '15 sessions lag' fix"*, plus the dead `~3.9` as a co-binding constraint) — a paraphrase carries no quoted premise for a citation-following grep to land on. Corrected there and in the last two derived carriers (`bottleneck-refute.md:7,52`; `02-provenance.md:203`, footnoted). N7 is now closed against a re-swept repo, not against a citation trail |
| **N8** | *"The ~15 is a Claude budget"* | **REFUTED.** Non-Claude ambient = **20.19 load units** vs a 20.0 gate, with all 14 Claude units contributing 5.65 R-procs (30%). Reproduces `gc-cpu-vs-session-ceiling-2026-08-18`'s 4.7% from an independent instrument. **Every capacity refusal in the fleet is substantially a refusal about the box's background** |
| **N9** | *"Watch `uptime` / fork rate to price one unit"* | **REFUTED with data.** During a probe the box load *fell* (28.96 → 26.75 → 25.81); fork rate read 1206.8/s baseline vs 617.2/s mid-probe. The **paired arrival differential failed independently for two agents** (Δ never returned to baseline; drift > signal). **Per-process ancestry attribution is the only instrument that resolves a unit** |

---

## 7. WHAT BREAKS IN OUR RAILS

Every rail below was built on **one session = one pane**. Each lever above violates that in a
different place.

| Rail | Already broken today | Breaks further under |
|---|---|---|
| **Pane census** (`k`, `cc_sp_trees`, `cc-where`) | Blind to in-process agents (they mint no process) and, INFERRED from the matcher, **counts the daemon and each `bg-pty-host` as a live session** (argv[0] matches; `daemon run` / `--bg-pty-host` contain none of `-p/--print/--version`) | L1, L5, L7 — the census under-counts by exactly the number of units moved off panes |
| **`cc_sp_active`** (ceiling 8 — the term the Agent gate leans on hardest) | Dedupes to the nearest claude ancestor, so a **13-agent in-process wave charges 1** | L1 makes this worse in exact proportion |
| **`k_work` / account router** | **19 invisible vs 11 visible writers (63%)**; the walk is one level deep and agent transcripts sit at `<sid>/subagents/[workflows/wf_*/]agent-*.jsonl`. Falsifies `bin/claude-accounts:543` ("subagents append to `.jsonl` **siblings**") | L1 — every workflow agent is another invisible burner scoring its account as idle |
| **Reaper / teardown** | Pane-keyed ⇒ **cannot reap a bg worker**; conversely CC's own retire logic would kill one out from under us. `shutdown_request` only works for teammates | L5 (in-process teammates have no pane to close), L6 (`--bg`) |
| **Mailbox / `cc-await-ping`** | 🚨 **Demonstrated live, 3/3**: a bg session ran *our* hooks, which armed `cc-await-ping <session-uuid> --timeout 14340` on a **session with no pane** — the wake path is pane-addressed, so it can never be woken. All three survived `claude stop` by ~13 min and needed `kill -9`. Converse of backlog **#127** | any paneless unit |
| **Custody** (`--notify-back` debt keyed on firing cwd) | Workflow agents and subagents have no fire ⇒ custody never opens (correct). A bg session's return **cannot be discharged** — nothing reads `jobs/<short>/state.json` | L6 |
| **Close protocol / `wrap-ledger`** | Per-session write attribution sees **8 agents as 1 session** (297 hook rows, one sid). A wave's loose ends collapse onto the lead | L1 at scale |
| **`agent-teams-enforce` + `frontier-spawn-gate`** | **Do not fire at all for workflow agents** (0 of 874 ledger rows). The deny text itself cites the incident this cap exists to prevent — *"reached 224 spawns / 167 sessions"* and ignited kernel watchdog panics — **a workflow reproduces that shape with the counter reading zero** | L1 |
| **6-concurrent-teammate cap** | **Prose only.** One hit repo-wide, in a markdown file. 11 were spawned and 11 ran | already broken |

**One hygiene finding from the wave itself:** a sibling axis's `claude --bg` probe left **1 daemon +
4 `bg-pty-host` processes (462 MB)** running after reporting a verified teardown. It was later reaped
by that axis's own verifier. The apparent contradiction with "spare pool = exactly 1" is **resolved**:
4 = 3 claimed workers + 1 idle spare, and **argv does not change on claim** (both read
`claude bg-spare --bg-spare …claim.sock`). Discriminate on **thread count — 9 idle vs 18–19 live** —
never on argv.

**Instrument warning that invalidates counts wave-wide:** a Bash tool call runs the whole script as one
`zsh -c`, so every pattern you type is in the tool shell's own argv. **A token that exists nowhere on
the machine reads 3** via `ps | grep -c`. Redirect `ps` to a file, then grep the file, and anchor on
`claude.exe --agent-id`. Related nulls that are instruments, not absence: `pgrep -c` does not exist on
macOS BSD pgrep (rc=2, reads 0 for every input); BSD `find -newermt '-10 minutes'` matches **nothing**;
BSD `grep` caps interval repetition at 255; recursive `grep -R` will not walk the `~/.claude` symlink
layer; and **there is no `cli.js` in 2.1.220** — the package ships one 256,908,272-byte Mach-O arm64
Bun executable, so any axis grepping `cli.js` gets a blind null.

---

## 8. OPEN QUESTIONS, EACH WITH THE PROBE THAT SETTLES IT

**Q1 — the largest unexplained number in the wave.** Why does a terminal-UI binary hold **78–241 MB of
private `IOAccelerator` (GPU)**? It is **86–91% of every `claude.exe` footprint**, present even in
`bg-pty-host` processes that have no terminal at all, and it scales with role (78 MB pty-host → 102 MB
daemon → 194 MB session → 241 MB busy teammate). The JS heap is ~30 MB. **If this is a per-process
Metal heap that can be shrunk or disabled it is a bigger memory lever than any orchestration-unit
choice.** Probe: diff `footprint -p` composition on a cold 2.1.220 start vs `~/.claude-156`; or
`fs_usage` on IOAccelerator opens during a cold start; or start with rendering/telemetry flags off.

**Q2 — decides L5.** What does an in-process teammate actually cost, and which rails survive? Probe:
flip **one** account's `teammateMode` to `"in-process"`, fire a 2-teammate wave, then re-run the
pane-ledger joiner, `ps -o lstart`, `cc-where`, and `cc-teardown` against it.

**Q3 — could invalidate every capacity model here.** Are `tengu_amber_kestrel` and
`EK(mainLoopModel, effortValue, ultracode)` live for **Opus-5 at effort high** — our default? Either
bypasses the 20-concurrent subagent cap entirely, in which case **we have no concurrent-subagent cap
today**. Probe: one `Ke()` gate read, or issue 25 concurrent unnamed `Agent()` calls and observe
whether #21 queues.

**Q4 — reorders the recommendation if yes.** Does an `--agent-id` process ever **acquire**
`.oauth_refresh.lock`, or only read a token the parent already refreshed? Probe:
`fs_usage -w -f filesys | grep oauth_refresh` across a known expiry instant with a teammate wave live.

**Q5 — flips the `--bg` verdict ±20%.** Does a bg worker **in a repo** spawn its own
`ms-365-mcp-server`? Both verifier probes ran in `/tmp` and neither did. Probe: one `claude --bg` with
`cwd` = the repo, then `ps -axo pid,ppid,command | awk '$2==<worker>'`.

**Q6 — two axes read opposite behaviour.** Does `isolation:"remote"` **throw** (read in the workflow
runner: *"agent({isolation:'remote'}) is not available in this build"*) or **silently downgrade to a
local worktree agent** (read in the Agent tool's `call()` body)? Both may be true at different call
sites. Probe: force it from each site with the debug channel on and grep for the literal
`[remote agent] isolation:'remote' is unavailable`; presence ⇒ gated off and names the failing clause.

**Q7 — decides L9's shape.** Should `k_work` **recurse**, or should nested agents be **charged to
their lead**? Recursing counts 10 workflow agents as 10 burners against `KMAX`=8, which may be correct
(10 concurrent API streams) or may over-refuse (one 5-h window position). Probe: `os.walk` vs
`scandir` over the 4 stores during a live 10-agent workflow, scored against `KMAX`.

**Q8 — bounds every absolute capacity number in §5.** Re-derive the R-procs → load-units conversion
(single-point fit, **×1.553**) at loads 10 / 20 / 40 before quoting §5's arithmetic externally.

**Q9 — two agents failed to find it.** Where is the documented **4096-item `parallel()` cap**
enforced? The only `4096` in the workflow module is an unrelated classifier schema-length limit.
Probe: one `parallel()` call with 5,000 items.

**Q10 — undocumented and load-bearing.** Is `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` (`~/.zshrc:484`,
no comment, no repo doc) deliberate? It silently forbids a workflow agent from spawning anything — our
fan-out is structurally two levels deep because of one un-commented line.

**Q11 — unowned.** The two routable non-Claude backends (Codex CLI, Pi·Codex) consume neither ceiling
and no axis in this wave measured them. Probe: run one real task on each and compare wall-clock,
fidelity, and whether our rails can see them at all.

---

## 9. WHERE FINDER AND VERIFIER DISAGREED, AND WHICH I TOOK

| Contested claim | Taken | Why |
|---|---|---|
| Workflow cap "≥8" (finder, demand==cap) vs **"exactly 8"** (verifier, observed queueing) | **verifier** | The finder's run demanded exactly 8 and could only bound below. The verifier's run demanded 13 and the queue is observable at 4–6 s release intervals. Strictly stronger evidence, and it agrees with the binary constant |
| "A bare `Agent({})` might also take a pane" (finder's top gap) vs **"it does not"** (verifier) | **verifier — but on the CRITIC's evidence, not the verifier's** | The verifier's `0/7` vs `11/11` was n=18 with `name`/`subagent_type` 100% collinear. The completeness critic ran the prescribed 12-day extension (**92.3% vs 15.5%, n=937**, offset controls, confound broken within every agentType) and I reproduced it independently. Same verdict, different and much stronger warrant — see the 🚨 in §1 fact 2. The verifier's *live* probe was correctly declared confounded (headless forces in-process) and is not what carries it |
| "The pane is a product requirement" (finder) vs **"the pane is `teammateMode:"iterm2"`, a config choice"** (verifier) | **verifier** | It read all four `settings.json` files directly and found the in-process backend in the binary. Both are right that CC's own `ITermBackend` — not our `cc-pane-runner` — drives the split (`cc-pane-runner` = **0 hits** in the binary, the control). This answers A8's "is the pane ours?" as **no, it is Claude Code's, via a setting we pinned** |
| "Named teammates ⇒ processes, definitionally" vs **"conditional on the resolved backend"** | **both, reconciled** | `Lrn()` would route in-process on a kitty box with `teammateMode` unset — but it is **not** unset here (pinned `iterm2` ×4) and our repo exports `ITERM_SESSION_ID` besides. So on **this** box, unconditionally a process; the observable discriminator is `--agent-name` in argv |
| "Backgrounding costs ~1.9× memory" (finder) vs **"parity at N≥2"** (verifier) | **verifier** | Two named, independent errors in the finder's comparison — a one-time 300 MB pool charged to the first job, and a bg *tree* compared against a foreground *process* whose 95.6 MB MCP child went uncounted. The verifier measured the slope over 1→3 jobs and built a matched fresh-session control |
| "`state:"done"` ⇒ no live process; the operator never ran one concurrently" (finder) vs **both REFUTED** (verifier) | **verifier** | The job schema has **no pid field at all** (all 24 keys enumerated) — a blind instrument. And the verifier held 3 live 217–225 MB workers all reporting `done`, while the operator's own `daemon.log` shows three jobs claimed within 13 s and settling 8.6 h / 8.9 h / 2.1 days later |
| "Quota binds first on the weekly horizon, 8–23 fleet" (finder) vs **"hardware binds first on both; crossover 26 panes"** (verifier) | **verifier** | A unit error: the finder compared *working* units against *resident* panes without the duty cycle, which is measurable and is **0.36** (n=517). The verifier's replacement derivation is **model-free** (weekly slope ÷ `k_work`), immune to every objection against the token fit, and cross-checks against the readout to 2 points. The finder's measurements all survive; only the ordering flipped |
| "Cache-read is confirmed free" / `RMSE=1.73, n=23` (finder) | **verifier's downgrade** | The finder forced `cr=0` then argued from the constrained residual — that tests the model, not the coefficient; its own cited source says *"a bound, not a point"* (`cond(X)=23,556`). And a published in-criteria residual of 17.7 pp contributes 313 against a total SSR budget of 68.8. Neither damages §5, which never touches the token model |
| "`isolation:'remote'` is the origin of the operator's '50 agents'" (finder) | **verifier's downgrade to inference** | No evidence any of our 158 runs used remote isolation; the supporting grep matched the tool's own doc prose quoted into prompts. The explanation our data *does* support is count-read-as-concurrency |
| "Transcript span over-counts slot occupancy" (finder) vs **"it under-counts"** (verifier) | **verifier** | `[first write, last write] ⊆ [acquire, release]`, so the sweep-line max is a lower bound. This makes "exactly 8" a *saturation* result, not merely a respected cap |
| "I am a plain research subagent" (two finders) | **corrected** | Their own transcripts sit at `subagents/workflows/wf_06556f35-03a/agent-*.jsonl` with `{"agentType":"workflow-subagent","spawnDepth":1}`. Their measurements (no process, no pane, `ppid` = the lead) stand — they evidence the **Workflow-agent** unit, not the plain-subagent unit. The plain-subagent row in §2 rests on the pane-ledger control and the binary read instead |

---

## 10. THE ONE-PARAGRAPH VERSION

Your hypothesis is right about **Agent Teams** and wrong about everything else, and the correction
matters because the two readings prescribe opposite things. A named `Agent({name})` teammate really
does take a pane and a slot — 382 MB, 18 threads, its own MCP server, billed to the lead's account —
and it is the **only** unit with no concurrency cap at all, capped by nothing but a 200-per-session
lifetime counter that Anthropic *deleted* in 2.1.224. An unnamed `Agent()` and a Dynamic-Workflow
`agent()` take no pane and no process; they are generators inside the parent's heap, and they are the
**only** units that *are* capped — at 20 and 8 respectively. Workflows feel unlimited because 1000
calls queue through an 8-wide semaphore: 231 tool calls in our whole history, not one above 8 ever.
Meanwhile the ~15 you feel is not a Claude budget — the load gate that produces it is already at its
ceiling from non-Claude background alone, all fourteen Claude units together supply 30% of the
numerator, and 15 is simply the fleet's median pane count. The real ordered walls are: our load gate
(~4–8 mid-turn), quota (crossover at **26** resident panes), the terminal (~30), then memory (~70).
The thing that actually *kills* the box — compressor-segment exhaustion — is in none of those,
because it is an ignition wall, not a residency one: a resident unit compresses nothing and the
measured per-unit segment cost of all seven is **~0** (§5a).
The cheapest correct move is to stop expressing fan-out as named teammates — but do it knowing that
the Workflow path passes through **zero** of our seven admission gates, and that every rail we own
(pane census, reaper, mailbox wake, close ledger, account router) was built assuming one session =
one pane.
