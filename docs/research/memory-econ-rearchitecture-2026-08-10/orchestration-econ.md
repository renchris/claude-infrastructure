# N · Orchestration-layer economics — the fan-out's memory bill, and where it actually lands

**Measured live 2026-08-10 00:15–00:55 PDT on the 15-axis wave this brief was written from.**
Specimen: session `626d9307` (15 subagents) + 2 sibling waves + 15 sessions = **33 claude processes**.

---

## 0 · 🚨 LIVE INCIDENT while this axis was measuring — and it IS the axis's answer

A single `ugrep` grew **4.25 → 6.55 → 9.37 → 10.89 → 11.38 GB RSS in 4m37s** (~2.5 GB/min,
`phys_footprint` 6,423 MB at the 6.55 GB sample). Box went **11 GB unused → 260 MB unused in 12
minutes**; compressor 3.25 → 4.31 GB. `swapouts` still 0 — this is the wall being reached without a
swap event.

```
pid 68030  ugrep -G --ignore-files --hidden -I --exclude-dir=.git … -o .\{0,260\}FORCE_…
  ← zsh -c (shell-snapshot)  ← zsh -c  ← pid 99699 .bin/claude --model claude-opus-5   [a SESSION]
```

Three facts make this the axis's central finding, not an anecdote:

1. **It is harness-generated, not agent error.** The agent asked for `FORCE_…`; the Grep tool wrapped
   it as `-o .{0,260}<pattern>` with `--hidden`. Every Grep tool call in the fleet has this shape.
2. **It out-weighs the entire agent fleet it came from.** 11.38 GB from one tool call vs **4.22 GB
   phys_footprint for all 18 subagent processes combined**.
3. **No bound exists.** `launchctl limit rss` = `unlimited`; `ulimit -d`/`-l` = unlimited.

**Left running as found** (brief boundary: measure and read only). Flagged to lead in the return.

---

## 1 · Cost model — measured, in `phys_footprint`, not RSS

🚨 **RSS overstates this fleet by 2.34× and must not be used for a budget.** `footprint -p` (the
`phys_footprint` macOS actually charges, and what jetsam reads) vs `ps` RSS, all 33 processes:

| Unit | count now | RSS each | **footprint each** | RSS→fp ratio | fleet RSS | **fleet footprint** |
|---|---|---|---|---|---|---|
| research subagent (`claude.exe --agent-id`) | 18 | 592–827 MB (avg 630) | **201–354 MB (avg 235)** | 2.7× | 11.34 GB | **4.22 GB** |
| session (`.bin/claude`) | 15 | 633–964 MB (avg 733) | **219–464 MB (avg 355)** | 2.06× | 11.00 GB | **5.33 GB** |
| **claude fleet total** | **33** | | | **2.34×** | **22.34 GB** | **9.55 GB** |

Why the gap, from `vmmap`/`footprint` on pid 54677 (this agent): `__TEXT` 171.6 MB + `__LINKEDIT`
40.6 MB + `__OBJC_RO` 51.7 MB + `__BUN` 151 MB are **all DIRTY=0, clean, file-backed** — one copy
machine-wide, counted 18× by RSS. The identical `185 MB clean` column appears in all four processes
sampled.

**And 85% of the real charge is not heap.** Same process, footprint 243 MB:

| category | dirty | reclaimable |
|---|---|---|
| **IOAccelerator** (GPU-backed) | **200 MB** | **166 MB** |
| JS JIT generated code | 18 MB | 64 KB |
| JS VM Gigacage | 6.9 MB | 32 KB |
| all MALLOC zones | 12.8 MB | — |
| ⇒ **truly non-reclaimable** | | **≈ 77 MB** |

IOAccelerator is 166–367 MB in **both** subagents (166–302) and sessions (169–367), so it is the
binary's shape, not a subagent defect. Consequence for budgeting: a per-agent cost of **235 MB
charged / ~77 MB incompressible**, not 630 MB.

### Secondary units

| Unit | footprint | count under doctrine | notes |
|---|---|---|---|
| **agent-forked TOOL process** | **UNBOUNDED (11.38 GB measured)** | ≥1 per *active* agent | §0. The dominant term. |
| session MCP tree (`npm exec` + `chrome-devtools-mcp --isolated`) | 94 MB idle → **1.63 GB used** (pid 7993) | 1 per MCP-enabled session **and subagent** | pid 74513 is parented by **subagent** 73566 — subagents inherit MCP config and spawn their own tree |
| standing daemon layer — 11 live `com.claude.*` + `com.chrisren.*` jobs incl. dispatcher (51100), lead-supervisor (85774), postland-verify, compressor-sentinel, cc-reaper, autonomy-sweep | 32.5 MB resident + ~20 MB children = **≈50 MB total** | 24/7 | **0.08% of RAM.** See §3. |
| pane aux tax (`login` + `bash` + `caffeinate` + `zsh` tool shells per agent pane) | ~10 MB/pane; 29 caffeinate, 142 bash live | 1 set per agent | ~0.2 GB; feeds the 37% sys time, not RAM |

### Steady state vs doctrine-implied

| Scenario | footprint |
|---|---|
| **Measured now** (18 subagents + 15 sessions) | **9.55 GB** |
| **Doctrine-implied busy afternoon**: 15 sessions (5.3) + 3 concurrent waves × N=12 (8.5) + 6 teammates (1.4) + MCP trees (1.5) + daemons (0.05) + pane tax (0.5) | **≈17.3 GB** |
| Same scenario read in RSS (the number a naive census produces) | ≈40 GB — **the figure that would falsely convict residency** |

**Independent corroboration:** the prior wave's `01-memory-age.md:245` derives a per-process constant
of **232 MB** and a marginal of **340 MB/session** by a different method (11-day historic sampling).
I measure **235 MB** and **355 MB**. Two methods, two instruments, agreeing within 2%.

⇒ **Orchestration residency is NOT the ~15-session ceiling.** At 33 processes the box reports 30.8 GB
reclaimable headroom, 0 swapouts in 20h27m uptime, and its own alarm estimates *room for 49 more
sessions*.

---

## 2 · Findings

**Finding 1 — the fan-out's memory bill is in the tools, not the agents; the one guard designed for it is researched, filed, and inert**
Evidence: §0 (11.38 GB ugrep, `rss` rlimit unlimited) vs 4.22 GB for 18 agent processes. `docs/research/resource-guard-2026-08-08.md` already resolved this exact shape — backlog `2af4c4908422`, generating incident 2026-08-02, its own §6 line 79 reads *"that is the observed shape exactly: the runaway ugrep sat at…"*. It measured that Darwin returns **EINVAL for `RLIMIT_AS`, `RLIMIT_RSS`, `RLIMIT_DATA`** (4-of-8 split as its positive control) so no memory cap exists; resolution = **bound CPU at the Bash tool boundary, make the RETURN the notification** (`exit 152`, `verdict=cpu-ceiling-exceeded limit_cpu_s=60`), because grep/ugrep/rg/find all die on default SIGXCPU disposition.
Cost now: 11.38 GB and climbing from one call; 62 GB used / 260 MB unused; compressor +1.06 GB in 12 min.
Re-architecture: deploy the 2026-08-08 design. A 60s CPU ceiling stops this ugrep at ~1.3 min ≈ 3–4 GB instead of 11.4 GB.
Sizing: recovers the single largest unbudgeted term · effort S (design done, adjudicated) · risk low (declared ceiling, no reaper, no selector).
Existing mechanism: `resource-guard-2026-08-08.md` + `compressor-sentinel.sh:25-35` (SIGSTOP for the observed-from-outside shape). **EXTEND/DEPLOY — do not redesign.** This is `[[conclusion-must-reach-the-enforcing-store]]`: correct analysis, no enforcing store, paid for live.

**Finding 2 — the Agent-spawn gate is wired, memory-only, and has never once refused; the term that would have bound it is deliberately off**
Evidence: `hooks/agent-teams-enforce.sh:79` — `CC_ADMIT_LOAD_TERM=off cc_capacity_admit agent-tool "<type> spawn"`. Floor `CC_HW_DEFAULT_MIN_HEADROOM_GB=4` (`scripts/lib/capacity-admit.sh:122`); live reclaimable **30.96 GB** = 7.7× the floor. Ledger `~/.claude/autonomy/idl.jsonl`: **114 rows `agent-tool|admit|headroom-only`, 0 refusals.** The load term is off for a *documented and sound* reason (`capacity-admit.sh:313-319`: loadavg swings 2.05× at constant session count, dominated by TUI renderer + WindowServer).
Cost now: the fleet's highest-volume spawn surface is effectively ungated — 15-wide waves admitted at 0.0% CPU idle.
Re-architecture: keep loadavg off; add a term that is **fan-out-attributable and TUI-independent** — reuse `capacity-alarm.sh`'s own `sessions_exe` derivation (it read 18 exactly right) as a live agent-process count, refusing above K. One derivation, not a third copy (the lib's own §109 rule).
Sizing: bounds wave width at the one chokepoint that already exists · effort S · risk low (bounded-release already built: `CC_ADMIT_BUDGET=3` then admit-and-page).
Existing mechanism: `capacity-admit.sh` + `agent-teams-enforce.sh` — **EXTEND**.

**Finding 3 — the gate's metric counts the fan-out's own idle pages as headroom for more fan-out**
Evidence: `cc_hw_headroom_gb()` = free + speculative + inactive + purgeable. Measured: free 7.53 + spec 0.43 + **inactive 22.60** + purge 0.40 = 30.96 GB — inactive is **73%** of it. But `File-backed pages` total only **12.30 GB**, so **≥10.30 GB of "reclaimable" is anonymous live-process heap**. Reclaiming anonymous pages on macOS **compresses** them (compressor already 3.24→4.31 GB, 5.83M compressions, 2.4:1 ratio) — it does not free them.
Cost now: gate over-reports true headroom by ≥4 GB, and the over-report **grows with the fan-out the gate exists to bound** — positive feedback in the wrong direction.
Re-architecture: exclude anonymous-inactive; use free + speculative + purgeable + file-backed-inactive, or gate on `phys_footprint` sum of the claude fleet against an explicit budget.
Sizing: makes an existing gate able to fire at all · effort S · risk low.
Existing mechanism: `capacity-admit.sh:cc_hw_headroom_gb` — **CORRECT IN PLACE**. This is `[[proxy-must-be-independent-of-what-it-supplements]]`.

**Finding 4 — the one numeric cap in doctrine is on the cheaper unit; the expensive one is explicitly uncapped**
Evidence: `~/.claude/CLAUDE.md:194` — teammates "max **6 concurrent**". `:206-207` — research subagents "**No parallelism cap**; decomposition determines count… Default N=12". Measured: both are the *same process shape* — `claude.exe --agent-id … --team-name session-<sid> --agent-type <t>`, identical 235 MB footprint, identical 5–11% CPU. This wave ran **15**, i.e. 2.5× the capped unit's limit.
Cost now: 15×235 MB = 3.5 GB/wave charged, ×3 concurrent waves observed today.
Re-architecture: state the cap on the *process*, not the role — "≤6 concurrent agent processes per session, ≤N fleet-wide", enforced at Finding 2's chokepoint (which already sees both, via `SUBAGENT_TYPE`).
Sizing: aligns doctrine with the measured unit · effort S (one doctrine edit + one gate term) · risk medium (narrower waves = slower research; N=12 is a research-quality decision, not only a RAM one).
Existing mechanism: `agent-teams-enforce.sh` already reads `SUBAGENT_TYPE` — **EXTEND**.

**Finding 5 — subagent RSS grows ~6 MB/min with no plateau inside an hour**
Evidence: two samples 7m16s apart, 15-agent cohort: mean **+44.5 MB** (range +6.5 to +165), = **6.1 MB/min ≈ 370 MB/h**. Cross-cohort: `r-blindspots` 480 MB @1:33 → `dep-types-node` **847 MB RSS / 354 MB footprint @1:05:44**. `phys_footprint_peak` runs 1.23× current (299 vs 243).
Cost now: a 60-min wave costs ~1.5× a 10-min wave. Peak is LATE (all N alive and old), not at spawn.
Re-architecture: budget waves on **N × footprint × expected duration**, and prefer several narrow short waves to one wide long one; the OASIS stop criterion is already the lever.
Sizing: reframes the budget, no new mechanism · effort S · risk low.
Existing mechanism: research-subagents skill § OASIS stop — **no change needed, just cite the number.**

**Finding 6 — subagents exit cleanly (no lingering, no orphans), but a straggler holds ~300 MB at 1.7% duty for 45+ min**
Evidence (question e): `dep-nanoid-webvitals` (40804) EXITED between samples. **0 orphans** — every `claude.exe` has a live `bash` parent (`cc-pane-runner` → `login`/`bash`), none at `ppid 1`. But `recon-stopchain` (9953): 51 min elapsed, **1:47 CPU = 3.5% duty**, RSS flat 466 MB / footprint 307 MB, while its wave-sibling `recon-transcripts` runs at 9.7%. Aggregate frees as a decaying staircase, but the *lead* cannot proceed until the slowest returns.
Cost now: ~307 MB × straggler-count × straggler-duration; no leak.
Re-architecture: nothing to reap — the correct lever is wave-width + per-agent stop discipline, not a reaper. **Do not build a subagent reaper**; it would have no victims.
Sizing: n/a (negative finding — closes a plausible-but-empty work item) · effort 0.
Existing mechanism: `com.claude.teammate-reap-alarm` (66955) already live for the teammate shape.

**Finding 7 — subagents inherit MCP config and spawn their own MCP trees**
Evidence: `npm exec chrome-devtools-mcp@latest --isolated` pid 74513 → **ppid 73566 = subagent `dep-types-node`**. 12 MCP procs, 2.07 GB RSS total; worst single `chrome-devtools-mcp` pid 7993 at **1.63 GB**. `--isolated` ⇒ no profile sharing.
Cost now: +94 MB per agent idle; +1.6 GB per agent that actually drives a browser. Unbudgeted in every wave estimate.
Re-architecture: MCP servers should not be inherited by research subagents that cannot use them — gate MCP startup on agent type, or ship a research-agent config with the browser MCP absent.
Sizing: up to 1.4 GB at 15-wide idle, far more if used · effort M · risk low.
Existing mechanism: per-agent config dir already exists (`CLAUDE_CONFIG_DIR`) — **EXTEND**. Hand-off to axis G (session-cost), which owns MCP policy.

**Finding 8 — the standing orchestrator is free; on-demand fan-out is the entire bill**
Evidence: 11 live daemons = **32.5 MB resident + ~20 MB children ≈ 50 MB**, vs 4.22 GB for 18 subagents. **One subagent costs 4.7× the whole 24/7 daemon layer.**
Correction to the shared census (`prespawn-decomposition.md:26`): it lists `com.claude.discovery` and `com.claude.lead-supervisor` as *"Dead: (-15)"*. Both hold **live pids** (18421, 85774) — `launchctl list`'s status column is the **last exit status**, not liveness. Cf. `[[daemon-fleet-v2]]` (`list|grep` hides 4 broken states).
Cost now: 0.08% of RAM. A 24/7 orchestrator is not worth converting to on-demand for memory.
Re-architecture: **none on memory grounds.** Any daemon-consolidation case must be argued on fork/CPU (axis B/F), never RAM.
Sizing: closes a plausible work item · effort 0 · risk n/a.

---

## 3 · Off-box offload (question c/d) — NOT the lever today, and one venue is actively dangerous

| Venue | State (verified live 2026-08-10) | Blocker |
|---|---|---|
| `cc-offload` / cloud sessions | `setup` reads `✓ READY` and that is honest about the FIRE path. **13 sessions created, ZERO have ever acted.** | Live `git ls-remote origin` = **3 refs** (`HEAD`, `main`, `wt-b4f93c9fa73c`) — **no `claude/*`**. 20 `.decl` files, 0 pushes. |
| `Agent(isolation:"remote")` | **OFF, all 4 accounts.** Gate `ian()` = `hasUsedRemoteSession && hasRemoteEnvironment && Ke("tengu_neapolitan")`. I verified live: `hasRemoteEnvironment: true` in `.claude-secondary/-tertiary/-quaternary/-next`, but `hasUsedRemoteSession` is **absent from every config dir** and `tengu_neapolitan` appears only inside transcripts/tool-results, in **no** `cachedStatsigGates`. 2 of 3 terms still false. | 🚨 **It silently downgrades to LOCAL when gated** (`docs/research/cloud-observability-2026-08-07.md:435`). Writing "waves >N go remote" into doctrine would yield **zero relief with zero error signal.** |
| claude.ai/code web | 4 sessions were visible historically | operator-driven only; return channel unreadable locally |

**What moved and what did not** (`docs/plans/CLOUD_OBSERVABILITY.md` §12.4, working tree, written
today): the operator installed the Claude GitHub App at ~07:10Z; the next fire went **clean on
attempt 1, no bundle** — and `claude/*` refs **still 0**, same `NOT-STARTED` verdict. Two distinct
create blockers have now been found and fixed and **neither moved the number, because neither was
ever binding**. `da04cf23` correctly made the App marker *retractable* rather than flipping it to
`present` (a clean create cannot discriminate bundle from `git_repository`).

**The generator-class fact:** the scarce thing was never a session id — it is an **observed cloud
execution**, and this box structurally cannot see one. Next step is operator-shaped and already
filed: open `https://claude.ai/code/session_018YsHzozWKCzxx5cifEQw1L` and read what it did.

**Correcting the naive routing intuition:** "send cheap read-only research to the cloud" is backwards
on the *reachability* axis. Both classes need the same unblock — the prior wave's **B1** (`git switch
-c <branch>` before push; `claude/fire-…` is a name the firing side invented and the proxy refuses
any non-working-branch push — ~3 lines, `handoff-fire.sh:5547`) and **B2** (`cc-cloud preflight`
exists at `bin/cc-cloud:560-571` to refuse a branch absent from origin, and `--cloud` never calls
it). Once a branch round-trips, a research report is just a file on it. The `say`/read-back cursor
gap only blocks interactive steering, not deliverable return.

### The decision rule, stated honestly

Because off-box relieves **0 GB today**, the doctrine amendment cannot route on venue. It must be a
**local bound with a serial fallback** — which the existing deny message already prescribes
(*"shed first… then spawn. Run this work SERIALLY on the lead if it cannot wait"*).

> **Proposed amendment.** Wave width is bounded at the **Agent PreToolUse chokepoint**
> (`hooks/agent-teams-enforce.sh`), on **agent-process count** (via `capacity-alarm.sh`'s
> `sessions_exe` derivation) and **corrected** reclaimable headroom (Finding 3) — never on loadavg.
> Above the bound: narrow the wave, or serialize on the lead. **Off-box is not an escape valve until
> one cloud session is observed to act** (B1+B2 landed AND a `claude/*` ref exists). Until then,
> `isolation:"remote"` is **forbidden as a capacity lever** — it silently runs local.
>
> Enforcement chokepoint: `agent-teams-enforce.sh:79`. It is the only place that sees every subagent
> *and* teammate spawn before it happens, it already fails-loud-not-silent when the lib is missing
> (`idl.jsonl` `disposition:"abstained"`), and it already has bounded release so a refusal cannot
> wedge the fleet.

---

## 4 · Adversarial self-pass

| Hostile reading | Answer |
|---|---|
| *"Your RSS numbers double-count 18 copies of a shared binary."* | **Conceded and corrected before publishing** — that is §1. Every headline uses `phys_footprint`; the RSS figure is shown only to name the 2.34× error. Verified with `vmmap` DIRTY=0 on `__TEXT`/`__LINKEDIT`/`__OBJC_RO`/`__BUN`. |
| *"You convicted a 15-wide wave for CPU it doesn't consume."* | **Correct, and I do not.** The 18 subagents sum to **~1.07 of 10 cores (~11%)**. The 0.0%-idle saturation is tool processes (ugrep 76%, `log show` 76%, `du` 44%) + Spotlight (`mds_stores` 19%, `fseventsd` 22%, `mdfind` 21%) + WindowServer 30% + Dia ~30%. The wave's CPU cost is **in what it forks**, which is the same conclusion as its memory cost. |
| *"So is memory the ceiling at all?"* | **Not as residency** — 9.55 GB of 64 GB at 33 processes, 0 swapouts in 20h, gate 7.7× from its floor, 0/114 refusals. **Yes as variance** — §0 took the box to 260 MB unused in 12 min. The ceiling is a *burst* property, not a *level* property. |
| *"The prior wave already found the 4–40 GB burst term — you're re-reporting it."* | **Different population, and I checked before claiming.** `scaling-bottlenecks-2026-08-09.md:32` and `01-memory-age.md:28` count *54 `claude.exe` processes* >4 GB (max 41 GB, ~8 GB/min) and state at `:325` *"What triggers the 4–40 GB bursts is unknown"* — at `:168`, because there was *"no argv in the historic"* data. Their classifier keys on the **`claude.exe` name**, so a `ugrep` **child** is structurally invisible to it. I caught a burst **with argv**, same order of ramp (2.5 vs 8 GB/min) — a **second burst population**, not their trigger. I cannot and do not claim to have identified theirs. |
| *"Quota, not RAM, limits fan-out width."* | **Plausible rival and I defer.** The prior wave measured *"~4 sustained-active across 4 accounts"* — if that binds, a 15-wide wave is quota-bound before either RAM or CPU. Owned by axis 07-accounts-api / the accounts axis; my bound is a *machine* bound and composes under whichever binds first. |
| *"You never checked ptys/maxproc."* | Checked, not binding: `ptys_used 35 / ptys_max 511` (6%), `kern.maxproc 16000`, `maxprocperuid 10666` at 56 claude-attributable procs. Consistent with the prior wave's "ptys are not the wall". |
| *"Is the 6 MB/min growth a leak?"* | **Unresolved, and named as such.** Context accumulation would be bounded by the window; a leak would not. One hour is too short to separate them. Not load-bearing: either way the budget is N × footprint × duration. |

---

## 5 · Answers to the brief's five questions

**(a) Per-subagent RSS vs lifetime, and doctrine-implied steady state.** 235 MB footprint (630 MB
RSS) at spawn+3min, growing 6.1 MB/min to 354 MB (847 MB RSS) at 66 min; ~77 MB incompressible.
Doctrine-implied busy afternoon ≈ **17.3 GB footprint** (≈40 GB if wrongly read in RSS) — comfortable
on 64 GB. **Residency is not the ceiling.**

**(b) Desk architecture residency.** ≈**50 MB** total for 11 live daemons incl. dispatcher 51100 and
lead-supervisor 85774 (both alive — the census's "Dead (-15)" reads a last-exit column). One subagent
= 4.7× the entire 24/7 layer. **No memory case for on-demand conversion.**

**(c) cc-offload state and reachability.** `237ecf24` shipped `bin/cc-offload` (566 lines, 31 tests,
3 mutation-proven) as a composing entrypoint over parts that already worked — it owns no state and
computes no verdict. `da04cf23` made the App marker retractable. **Round trip still 0/13.** No work
class can run off-box today: `isolation:"remote"` is gated off on all 4 accounts *and fails silently
to local*; cloud sessions create but have never been observed to act.

**(d) Local-vs-remote decision rule.** Cannot route on venue (§3). Bound locally at
`agent-teams-enforce.sh:79` on agent-process count + corrected headroom; fall back to narrower waves
or serial-on-lead; forbid `isolation:"remote"` as a capacity lever until a `claude/*` ref exists.

**(e) Subagent lifetime.** They exit cleanly and promptly; **0 orphans** across 18. No reaper needed.
The real cost is the straggler (~307 MB at 3.5% duty for 51 min) and the growth rate, not lingering.

---

## 6 · Handoffs to sibling axes

- **Axis L (bottleneck-refute):** your own `log show --last 8h` (pid 73609) was 76% CPU / 475 MB for
  7m45s during my measurement — you are a specimen of Finding 1.
- **Axis G (session-cost):** Finding 7 — subagents spawn their own MCP trees; MCP policy is yours.
- **Axis H (terminal-layer):** `capacity-alarm.jsonl` reports kitty at **1,940 MB** while `ps` RSS
  reads 388 MB. Cf. `[[gui-memory-dialog-blames-the-coalition-host]]` — the alarm may be quoting a
  coalition figure. Worth one `footprint` call; it affects that alarm's `top_procs`.
- **Axis F (hook-forks):** 37.42% **sys** time at 142 bash + 29 caffeinate is your denominator.
- **Axis J (prior-art):** `resource-guard-2026-08-08.md` / backlog `2af4c4908422` is a researched,
  adjudicated, **undeployed** remedy — the highest-value single item this axis found.


---

## 7 · Addendum — lead steers (a)–(d), measured

### (a) Off-box lane coordination
`docs/plans/CLOUD_OBSERVABILITY.md` and `bin/cc-offload` were read **strictly as text**; no write,
no fire, no `cc-offload` invocation. Everything in §3 is **input to that lane, not a competing
plan** — specifically B1 (`git switch -c` before push) and B2 (call the existing `cc-cloud
preflight`) are that lane's items, and my only addition is the **routing consequence**: until a
`claude/*` ref exists, off-box relieves 0 GB and must not appear in any capacity rule.

### (b) Extend the existing actuators — and one of them is already refusing because of this wave

Three actuators exist; they are **not** parallel and my rule extends rather than duplicates them:

| Actuator | Term | Load term | Status |
|---|---|---|---|
| `capacity_gate()` — **fire path** (dispatched sessions) | load 2.0/core + headroom | **ON** (`CC_FIRE_MAX_LOAD_PER_CORE`, default 2.0) | live; `handoff-fire.sh:5110` `capacity_gate \|\| exit 9`; `--recycle` exempt; kill-switch `CC_FIRE_CAPACITY_GATE=off`. `:454` records **453 of 633 admits carry `basis:"gate-off"`** |
| `cc_capacity_admit` — **Agent path** (subagents + teammates) | headroom only | **OFF by design** (`agent-teams-enforce.sh:79`) | live; **114 admits, 0 refusals** |
| **router KMAX** — `bin/claude-accounts` | per-account live-session count `k` | n/a | live; `:1094` `if k >= KMAX: refuse`; KMAX **hand-raised 4→8** (`:224`) |

🚨 **The asymmetry is the defect: the same fleet gates dispatched sessions on load at 2.0/core and
exempts subagent spawns from load entirely.** At 0.0% idle and 5.9–8.5/core (measured, this window)
the fire path refuses while the Agent path admits — so the fleet throttles its *cheap, budgeted*
spawn surface and leaves its *high-volume, unbudgeted* one open.

🚨 **KMAX counts subagents as sessions, and this wave is over it — proven live.** `bin/claude-accounts:
361-372` matches `argv[0] == "claude" | */claude | *claude.exe | cli.js`, and its own comment says so
explicitly: *"`claude.exe` … is the argv[0] of every session this repo's own dispatcher creates …
cc-pane-runner-dispatched workers, **teammates and research subagents** exec the RESOLVED native
binary"* (measured there 2026-08-04: next2 read 2 against a truth of 10). `grep -n 'agent-id|--agent|
team-name|parent-session' bin/claude-accounts` → **zero matches**: nothing filters subagents.
Attribution is by inherited `CLAUDE_CONFIG_DIR`, so they are credited to the parent's account.

Replicating that exact predicate read-only (never invoking the tool — `:471` holds an `auth login`
heal path that could rotate tokens mid-wave):

| account | k as router sees it | sessions | **subagents** | vs KMAX=8 |
|---|---|---|---|---|
| `.claude-tertiary` | **26** | 10 | **16 (62%)** | **REFUSED** — 3.25× the cap |
| `.claude-next` | 5 | 3 | 2 | ok |
| `.claude-secondary` | 1 | 1 | 0 | ok |
| `.claude-quaternary` | 1 | 1 | 0 | ok |
| **fleet** | **33** | 15 | **18 (55%)** | vs 4×8 = 32 capacity |

**This reframes the investigation's premise.** The "~15-session ceiling" and "the router refuses the
33rd session" are the same wall reached by two different counts, and **55% of the count is research
fan-out, not sessions.** One 15-wide wave takes an account from k=10 to k=26 and makes it
unroutable for every subsequent dispatched fire — a *hidden coupling from research fan-out to
dispatch capacity*, which no doctrine mentions.

**Do NOT "fix" this by un-counting `claude.exe`.** That count is load-bearing for a different
question — rotation safety (*"a heal that reads 0 redeems a refresh token concurrently with N
sessions that rotate it"*). One population, **two predicates**: count every `claude.exe` for
rotation safety (correct today); count only `--agent-id`-free processes for **routing capacity**.
Cf. `[[sibling-auditors-must-share-the-state-model]]`, `[[positive-control-the-denominator]]`.

### (c) Burst quantification — the ledger CORRECTS the attribution, and my own §4 note was too generous to me

From `~/.claude/logs/capacity-alarm.jsonl` — the machine's own 11,508-row, 11-day ledger
(2026-07-30 → 2026-08-10):

| metric | value |
|---|---|
| `max_proc_gb` p50 | **2.20 GB** |
| `max_proc_gb` max | **40.00 GB** |
| rows >4 GB / >8 GB / >20 GB | **1,090 / 216 / 17** |
| **today** (418 rows) | max_proc_gb **16.00 GB**, 53 ALARM rows, swap **0.00**, headroom min 21.70 GB |
| `cmd` on >4 GB bursts | **`node` 1,296** · `claude.exe` **135** · Chrome 21 · cmux 2 |

**`node` outnumbers `claude.exe` 9.6:1 in the >4 GB burst population** — and the alarm labels
`chrome-devtools-mcp` as `node` (verified: pid 7993 appears as `"cmd":"node"`). So the burst
population is dominated by **children** — MCP servers and tool processes — not by agent heap.

🚨 **And the runaway I caught was logged as `claude.exe`, which explains the prior wave's open
question.** The alarm's own rows through my §0 incident:

```
07:46:51  headroom 30.59  max_proc_gb  5.20  top1=claude.exe:5324MB
07:48:15  headroom 28.50  max_proc_gb 11.00  top1=claude.exe:11264MB
07:53:47  headroom 26.39  max_proc_gb 12.00  top1=claude.exe:12288MB
07:55:13  headroom 36.46  max_proc_gb  2.21  top1=node:2267MB      ← ugrep exited
```

Those MB values track my independently-measured `ugrep` (9.37 → 10.89 → 11.38 GB) exactly. **So I
must withdraw the "second, distinct population" framing in §4**: it is the *same* population,
**mis-attributed by the instrument** — consistent with the repo memory that `grep` in a Bash tool
call is a shell function that *execs the claude binary as `ugrep -G`*, so `cmd`-based attribution
sees `claude.exe`. The prior wave's *"trigger unknown … no argv in the historic"*
(`scaling-bottlenecks-2026-08-09.md:168`) is therefore explained not by a missing sampler but by the
**`cmd` field never carrying argv** — and the trigger is now named with argv:
**a harness-generated `ugrep -o .{0,260}<pattern> --hidden` over a large tree.**

**Wave-size doctrine tied to the burst term:** the budget is
`N × 235 MB × duration` (residency, comfortable) **+ 1 × unbounded** (burst, fatal). Residency at
N=15 is 3.5 GB; a single burst was 12 GB. **Therefore wave width is not the primary lever — bounding
the burst is** (Finding 1). Width matters second, via KMAX coupling (b), not via RAM.

🚨 **Finding 3, proven by the fleet's own instrument.** Through the entire near-panic
`headroom_gb` read **26.39–36.46 GB and never dipped** — its *highest* reading (36.46) came at the
peak — while `top` showed the box at **260 MB unused**. The compressor absorbed it (3.22 → 5.72 GB,
+2.5 GB) and `swap_used_mb` stayed 0.00. **The gate's headroom metric is a compression-lagging
figure that structurally cannot see a burst**, so the one gate on the Agent path is blind to the one
event that matters. (Runaway has since exited; box back to 12 GB unused, compressor still elevated
at 5.43 GB vs a 3.24 GB baseline.)

### (d) Vendor knobs — verified in the 2.1.220 binary, with defaults, and all three UNSET

Corrected names — **all three require the `CLAUDE_CODE_` prefix**; the bare forms in the steer are
substring-only (`MAX_SUBAGENTS_PER_SESSION` exact=0, `MAX_SUBAGENT_SPAWN_DEPTH` exact=0):

| env var | default | mechanism | set here? |
|---|---|---|---|
| `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` | **20** (`wHu(){return Z.CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS??Et_}`, `Et_=20`) | hard refusal + telemetry `subagent_launch`/`subagent_concurrency_cap` | **NO** |
| `CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION` | **200** (`XYr(){…??vt_}`, `vt_=200`) | per-session lifetime total | **NO** |
| `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` | **statsig-gated**, not a constant (`bee()` → `getFeatureValue_CACHED_MAY_BE_STALE`) | recursion depth | **NO** |
| `CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY` | (present; not extracted) | **bounds concurrent TOOL calls** — relevant to Finding 1 | **NO** |

The vendor's refusal text is already correct on retry semantics: *"Concurrent subagent limit
reached. You can run N subagents at once. **Do not retry.** If the user wants more concurrent
subagents, ask them to increase `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`."*

🚨 **The default permits ~300 concurrent subagents on this box.** The cap is **per session**, so 15
sessions × 20 = 300 × 235 MB ≈ **70 GB of footprint — more than the machine has** — and no vendor
term is fleet-wide. My 15-wide wave sat 5 below a per-session cap it could never have hit.
`CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION` appears in the binary's **settings-allowlist array**
(alongside `CLAUDE_CODE_MAX_RETRIES`, `CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY`), so these are settable
via `settings.json` `env` — a real enforcing store, not just a shell export.

**Revised amendment (supersedes §3's, same chokepoint principle):**

1. **Enforcing store first** — set `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` in `~/.claude/settings.json`
   `env` to align the uncapped unit with the capped one (**6**, per CLAUDE.md:194's teammate cap).
   Vendor-native, fails loud, correct no-retry semantics, no hook needed.
2. **Fleet-wide term** — the vendor cap is per-session, so the machine-wide bound stays at
   `agent-teams-enforce.sh:79`, keyed on `capacity-alarm.sh`'s `sessions_exe` derivation (one
   derivation, not a third copy).
3. **Fix the metric before trusting the gate** (Finding 3) — headroom cannot see a burst; until it is
   corrected, the Agent-path gate should be treated as unarmed, not as protection.
4. **Bound the burst** (Finding 1) — deploy `resource-guard-2026-08-08.md` / backlog `2af4c4908422`,
   plus consider `CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY`.
5. **Decouple routing from fan-out** (b) — split the `k` predicate so subagents stop consuming
   account-routing capacity, keeping the rotation-safety count intact.
6. **Off-box stays out of the rule** until a `claude/*` ref exists; `isolation:"remote"` remains
   forbidden as a capacity lever (silently runs local).
