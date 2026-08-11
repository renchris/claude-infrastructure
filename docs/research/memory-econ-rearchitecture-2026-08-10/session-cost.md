# Axis G — Session levers: what one Claude Code session costs, and the config knobs that move it

Measured 2026-08-10 on the live box (34 CC processes, 0 B swap, 68.7 GB RAM). Read-only: nothing
was changed, killed, or reconfigured. Every number below is a live measurement with its command.

---

## 0. Two corrections that change every other axis's arithmetic

**G-0a. `ps rss` overstates CC residency by 2.28×. Use `vmmap` physical footprint.**

| metric | value |
|---|---|
| Σ `ps rss` over 34 CC processes | **22 609 MB** |
| Σ `vmmap --summary` *Physical footprint* over the same 34 | **9 899 MB** |
| ratio | **2.28×** |

Cause, from `vmmap` on any CC pid: `ReadOnly portion of Libraries: Total=991.8M resident=268.4M` —
the 256 908 272-byte `claude.exe` Mach-O text plus system frameworks are **shared**, counted once
per process by `rss`, resident once in physical memory.

This is not a new discovery, it is a *re-derivation*: `scripts/capacity-alarm.sh:23` already states
"`ps rss` summed over sessions OVERCOUNTS ~2.34x (it double-counts shared pages) — do not use". My
independent 2.28× confirms it. **The pre-spawn census line "claude ×14 = 8.7GB · claude.exe ×5 =
2.7GB" is an `rss` sum and overstates by ~2.3×.** Re-price every axis in footprint before summing.

**G-0b. There are no in-process subagents on this box right now. All 34 CC processes are top-level
sessions — and 18 of them are Agent-Teams *teammates*.**

Ancestry walk over all 34: **0 have a `claude`/`claude.exe` parent**; 33 have a `bash` parent, 1 an
`expect` parent. The `claude.exe` cohort is not "subagents" — argv proves it:

```
85388 … /bin/claude.exe --agent-id r-session@session-626d9307 --agent-name r-session \
                        --team-name session-626d9307 --agent-color cyan --parent-session-id …
      parent = /bin/bash /Users/chrisren/Development/claude-infrastructure/bin/cc-pane-runner
```

15 of the 18 carry `--team-name session-626d9307` — **this very research wave**. (`r-session` is
this agent, pid 85388, footprint 239.5 MB.) The other 3: `dep-types-node@session-119ce481`,
`recon-stopchain` + `recon-transcripts@session-c72f15e7`.

Consequence: **a 15-member research wave is 15 additional full OS-level CC sessions**, 44 % of all
CC processes on the box and ~3.3 GB of the 9.9 GB CC footprint. The Agent tool's in-process runner
exists (`inProcessRunner`, `inProcessFallbackActive` in the binary) but is not what this fleet uses.

---

## 1. The measured per-session cost model

n = 21 distinct live sessions, joined `/tmp/cc-telemetry/<sid>.json` (`.pid`, `.input_tokens`,
`.window`) ↔ `vmmap --summary <pid>` ↔ `ps -o etime=`.

```
FOOTPRINT_MB = 227.7  +  0.343 × (K input tokens)  +  0.071 × (minutes alive)     R² = 0.71
```

- **Fixed floor ≈ 228 MB** per CC process. Corroborated independently: `docs/research/
  scaling-bottlenecks-2026-08-09/11-prior-art.md:206` measures **232 MB**/session (§S6.2).
- **Context term = 0.343 MB per 1 K input tokens** → 34 MB per 100 K, **343 MB at a full 1 M window**.
- **Age term = 4.3 MB/hour** — small but non-zero. This *narrows* `docs/plans/
  MACHINE_CAPACITY_V2.md:236` ("RSS is flat with age; there is no leak to contain"): flat-with-age is
  right about the age term, but the per-session growth that matters is **context-driven**, and
  context is a config lever. The 20 h session (pid 56864) sits at 457 MB.
- Observed live spread: **219 MB** (pid 71372, 19 min, 203 K tok) → **469 MB** (pid 98361, 8 h, 586 K tok).

**Every live session runs `window: 1000000`** (all 56 telemetry files, `model: claude-opus-5`,
`exceeds_200k: true`), and **`autoCompactEnabled: false`** in `~/.claude/settings.json`,
`~/.claude-tertiary/settings.json` and `~/.claude.json`. So the context term has a 343 MB ceiling
and no automatic brake — that is the mechanism behind CLAUDE.md's own "39/39 compactions are
`trigger:"manual"`, 0 auto".

---

## 2. What a session spawns at start (measured tree, pid 99699)

| child | count/session | footprint | avoidable? |
|---|---|---|---|
| `caffeinate -i -t 300` | 1 | 3.3 MB | no (sleep inhibitor) |
| `/bin/zsh -c source shell-snapshots/snapshot-zsh-*.sh` | 2–4 persistent | 1–5 MB each | no (Bash-tool shells) |
| `npm exec chrome-devtools-mcp@latest --isolated` | 1 **iff cwd carries reso's `.mcp.json`** | 117 MB | **yes** |
| └ `chrome-devtools-mcp` | 1 | 95–1900 MB | **yes** |
| &nbsp;&nbsp;└ `telemetry/watchdog/main.js` | 1 | 88–110 MB | **yes** |

Eager, not lazy: pid 99699 elapsed 1:40:19, its `npm exec` child 1:39:26 — **the MCP chain starts
53 s after session init**, before any tool call. Three of the four live chains have never opened a
browser (server RSS 46 MB, and **zero Chrome/Chromium processes exist on the box**).

MCP config reality (all four account dirs `~/.claude{,-next,-secondary,-tertiary,-quaternary}`):
- `$CFG/.claude.json` → `mcpServers: {motion, motion-plus}`, both **`type: http`** ⇒ 0 local processes.
- `$CFG/.mcp.json` → `browsermcp` via `/Users/chrisren/bin/browsermcp-wrapper.sh` — **inert**. CC
  reads `.mcp.json` from the *project root*, not the config dir. No `browsermcp` process exists, and
  `enabledMcpjsonServers: ["browsermcp","agent-browser"]` in settings.json has nothing to enable.
- The only stdio server actually running is `chrome-devtools`, from the **git-tracked**
  `~/Development/reso-management-app/.mcp.json` (`npx chrome-devtools-mcp@latest --isolated`),
  inherited by all three `~/Development/.worktrees/wt-cc-*` reso worktrees.
- `enableAllProjectMcpServers: true` is set in `~/.claude-next/settings.json` (account 1 only).

---

## 3. LEVER TABLE

MB are **physical footprint**. "×15" = the brief's 15-session multiplier; where the true multiplier
differs it is named. Risk is operational, not just technical.

| # | Lever | Mechanism | MB/session | ×15 | Risk | Exact config change |
|---|---|---|---|---|---|---|
| **G1** | Cap the chrome-devtools-mcp node heap | Server is **real node v22.21.1** (`heap_size_limit 4144 MB`), so `--max-old-space-size` **does** bind (unlike the CC binary — see G9). One live server holds **1.9 GB** footprint (peak 3.1 GB) with no browser attached | 900 MB on the leaking one | ~**2.1 GB** today (1 of 4) | **Med** — a hard cap can OOM-kill the server mid-use; 946 real calls in 7 d | In `~/Development/reso-management-app/.mcp.json` → `"chrome-devtools": { …, "env": { "NODE_OPTIONS": "--max-old-space-size=1024" } }` |
| **G2** | Kill the chrome-devtools-mcp telemetry watchdog | `WatchdogClient.js:31` spawns a **detached third node process** per server purely for Clearcut telemetry; gated by `chrome-devtools-mcp-cli-options.js:340` on `CI` or `CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS` | **88–110 MB** per MCP-carrying session | 4 chains today = **~410 MB** | **Low** — telemetry only | same `env` block: `"CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS": "1"` |
| **G3** | Drop the `npm exec … @latest` wrapper | `npx` leaves a resident **117 MB** `npm exec` parent for the process's whole life, and re-resolves `@latest` from the registry at every session start | **117 MB** per MCP-carrying session | 4 chains = **~470 MB** | **Low** — pins the version (a feature) | `"command": "/Users/chrisren/Library/Application Support/fnm/node-versions/v22.21.1/installation/bin/node", "args": ["/Users/chrisren/.npm-cache/_npx/15c61037b1978c83/node_modules/chrome-devtools-mcp/build/src/bin/chrome-devtools-mcp.js","--isolated"]` — the pattern `~/Development/taxes-2026/.mcp.json` already uses |
| **G4** | Make chrome-devtools **opt-in**, not always-on | Started eagerly in 100 % of reso-worktree sessions; **used in 19 of 600 transcripts (3.2 %) over 7 d** (946 `tool_use` calls, so heavily used *when* used). It is also started per **teammate** — 2 of the 5 live chains belong to teammates in the same worktree | **312 MB** per session/teammate that never calls it | a 12-member wave in a reso worktree = **13 chains ≈ 4.0 GB** | **Med** — a browser task in a session that didn't opt in fails until restart | move the `chrome-devtools` block out of the tracked `.mcp.json` into `.mcp.browser.json`, or add the worktree paths to `disabledMcpjsonServers` in each account `settings.json` and enable per-need |
| **G5** | **`teammateMode: "in-process"`** | `sql=["auto","tmux","iterm2","in-process"]` in the binary; fleet sets `"iterm2"` in both settings.json files ⇒ **every teammate is a full 228 MB-floor OS process**. In-process teammates cost only their context (0.343 MB/1 K tok) | **~220 MB × (team size)** | this live 15-member wave = **3.3 GB** → ~1.0 GB in-process ⇒ **−2.3 GB per wave** | **High — values conflict.** Operator standing preference is VISIBLE panes (memory `feedback-dedicated-split-pane-sessions-for-parallel-work`); and all teammate context then lands in ONE process's window | `~/.claude*/settings.json` → `"teammateMode": "in-process"`. **Do not adopt silently — this is an operator call, not an F1-F4 auto-pass** |
| **G6** | Bound fan-out at the source: `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` | Default is **20** (`function wHu(){return Z.CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS??Et_}`, `Et_=20`); `MAX_SUBAGENTS_PER_SESSION` default **200** (`vt_=200`). At 233 MB mean per teammate that is a **4.7 GB per-session tail**, ×15 sessions = an unbounded 70 GB ceiling | bounds the tail, saves 0 at rest | tail: **−1.9 GB/session** at cap 12 | **Low-Med** — a cap of 12 would have *refused this 15-member wave*; set 15–16, not 12 | `settings.json` `env` → `"CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS": "16"`. **Already flagged as unused prior art**: `docs/research/scaling-bottlenecks-2026-08-09/11-prior-art.md:200` |
| **G7** | ~~Turn off the 1 M context window~~ **RETRACTED 2026-08-11 — do not do this** | `function Nje(){return Z.CLAUDE_CODE_DISABLE_1M_CONTEXT}` … `function OH(e){if(Nje())return!1; … r?.native_1m …}` — a real, load-bearing gate. Caps the context term at 200 K × 0.343 = 69 MB instead of 343 MB | **−60 MB** at today's mean fill (~320 K); **−274 MB** of ceiling | **−0.9 GB** now, **−4.1 GB** of tail | **High** — invalidates the whole Context-Stewardship threshold system (35 %/50 %/75 % of 1 M) and forces ~5× more handoffs | `settings.json` `env` → `"CLAUDE_CODE_DISABLE_1M_CONTEXT": "1"`. **Prefer the softer knob if it works: `CLAUDE_CODE_MAX_CONTEXT_TOKENS` (semantics UNVERIFIED — see §6)** |
| **G8** | Undo the self-inflicted context inflation | `settings.json` sets `"CLAUDE_CODE_MAX_WEB_SEARCHES_PER_SESSION": "1000"`; the binary default is **200** (`wt_=200`). Each extra search puts thousands of tokens into the window at 0.343 MB/1 K | up to **−140 MB** on a search-heavy research session | research waves only | **Low** — 200 is already generous; a wave worker rarely exceeds it | delete the key, or set `"200"` |
| **G9** | ~~`NODE_OPTIONS` / `--max-old-space-size` on the CC process~~ | **INERT — do not do this.** `claude.exe` is a **bun-compiled Mach-O arm64** (binary contains `bun-repl`, `BUN_INSPECT_NOTIFY`, `BUN_CONFIG_TOKEN`) ⇒ JavaScriptCore, not V8. Confirms `docs/plans/MACHINE_CAPACITY_V2.md:1080` and `TERMINAL_AGNOSTIC_L3_L4.md:163`, and the rejection at `docs/research/l3-l4-terminal-and-workflow-2026-07-31.md:296` | 0 | 0 | — | none. G1 is the *different* case: node-based **MCP servers**, where the flag does bind |
| **G10** | ~~Statusline~~ | **Not a memory lever.** 0.06–0.13 s wall per render, peak transient child RSS **4 MB**, already collapsed to 2 git calls (`statusline.sh` header, audit 06 §5.2) | ~0 | ~0 | — | none — axis C's cardinality question stands, but the *memory* answer is nil |

> 🚨 **G7 RETRACTED 2026-08-11 — the 0.343 MB/1K-token coefficient does not reproduce, and the
> window *setting* costs nothing.** Measured by the context-economy assessment
> ([`../context-economy-100p-2026-08-11.md`](../context-economy-100p-2026-08-11.md), `wf_5e9f820e-438`):
>
> - **Interleaved A/B, 4 reps each**, identical prompt/model/cwd, peak `vmmap` physical footprint:
>   1M-eligible **190.5 MB** mean vs `CLAUDE_CODE_DISABLE_1M_CONTEXT=1` **192.9 MB** mean — the
>   *capped* arm reads nominally **higher**, inside a 7 MB within-arm spread. **There is no
>   preallocation by window size**, so the setting has no independent memory value at all.
> - **The coefficient is RSS-shaped and was fitted where the regressor had zero variance.** A causal
>   probe (fresh process, real token loads, same instrument) measured **0.045–0.060 MB/K-token**; a
>   within-session fixed-effects panel measured **0.098–0.147** (rss slope 0.302 vs footprint slope
>   0.019 in that same panel). All 21 sessions in the original cohort sat at `window=1,000,000`.
>   Applied to today's fleet it over-predicts the highest-token session by **216 MB (81%)**.
> - **Therefore the whole prize from 1M down to zero is ≤45 MB/session**, and moving a recycle
>   threshold across the entire 30–60% band is worth ~110 MB across a 16-session fleet — **0.17% of
>   64 GiB**, against 12.6 GB free + 22.8 GB inactive and **0.00 M swap in use**.
>
> **Operator ruling 2026-08-11:** a static cap is rejected. The system must keep context small by
> *understanding, handoff and self-recycling at good pause-points* — never by amputating the ceiling,
> because the ability to hold high-signal detail up to 1M is the thing the policy exists to protect.
> The decisive argument is **capability, not megabytes**: the terminal failure (`Prompt is too long`)
> is a pure token-count event with zero memory content, and a 200K cap would *raise* its frequency by
> ~5×-ing the handoff rate. **Retire the memory cost model from this decision rather than re-fitting
> it.** The real lever is the absolute-token arm at `hooks/boundary-handoff.sh:105` — see the
> assessment's ranked table.

**Ranked by MB recovered today, no operator decision required (G1–G4):** ≈ **3.0 GB**, all of it
inside one MCP server family that has no browser attached.

---

## 4. Findings in the 6-line row structure

**Finding: one chrome-devtools-mcp server is holding 1.9 GB with no browser attached**
Evidence: `vmmap --summary 7993` → `Physical footprint: 1.9G`, `peak 3.1G`, `Writable regions … written=1.9G`; its only child is the telemetry watchdog (pid 8190); `ps -Ao comm | grep -i chrome` returns **zero** browser processes box-wide
Cost now: 1.9 GB (server) + 118 MB (npm wrapper) + 110 MB (watchdog) = **2.13 GB**, up 1 h 39 m
Re-architecture: per-server `env: {NODE_OPTIONS: "--max-old-space-size=1024"}` in the project `.mcp.json`; the node default heap here is 4144 MB, so nothing bounds it today
Sizing: recovers ~0.9 GB immediately, caps the class at 1 GB · effort **S** (one JSON block) · risk **Med** (OOM mid-use)
Existing mechanism: the `env` field is already used by `~/Development/taxes-2026/.mcp.json` and `~/Development/inventory-management/.mcp.json` — **EXTEND that pattern**, do not invent one

**Finding: every stdio MCP server costs 3 node processes, and 2 of the 3 are pure overhead**
Evidence: process chain `npm exec chrome-devtools-mcp@latest --isolated` (117 MB) → `chrome-devtools-mcp` (95 MB) → `node …/telemetry/watchdog/main.js --parent-pid=N` (88–110 MB); `WatchdogClient.js:31` spawns it `detached: true` + `unref()`
Cost now: **312 MB per chain**, 4 chains live = 1.25 GB, of which **~830 MB is wrapper + telemetry**
Re-architecture: direct node path instead of `npx @latest` (kills the wrapper and the per-start registry fetch) + `CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS=1` (kills the watchdog, gate at `chrome-devtools-mcp-cli-options.js:340`)
Sizing: recovers **~830 MB** now, ~205 MB per future MCP-carrying session · effort **S** · risk **Low**
Existing mechanism: `.mcp.json` `command`/`args`/`env` — no new machinery

**Finding: MCP servers are spawned per *teammate*, not per session — the cost multiplies by fan-out**
Evidence: of the 5 live chains, the parents are pids 99699/58413/88196 (sessions) **and** 40804/73566 (`claude.exe --agent-id … --team-name …` teammates), all in reso worktrees
Cost now: 3 chains in the single worktree `wt-cc-232530-26432` (1 session + 2 teammates) = **936 MB**
Re-architecture: gate stdio MCP servers off for teammate processes (they are research/implementation workers that almost never drive a browser), or move `chrome-devtools` out of the tracked `.mcp.json` into an opt-in file
Sizing: a 12-member wave in a reso worktree spawns **13 chains ≈ 4.0 GB** — the largest single avoidable term found · effort **M** · risk **Med**
Existing mechanism: `disabledMcpjsonServers` per project in each account `settings.json` — already a supported key, currently unused

**Finding: the recycle rails are blind to memory, and only the desk is eligible at all**
Evidence: `hooks/waiting-recycle.sh:192` `T_IDLE=35`, `:194` `T_IDLE_FLOOR=25`, `:195` `IDLE_DECAY_S=3600` — all thresholds are **context fill %**; `:40-44` "ARMED — the desk opted in … OR it HOLDS the monitoring-desk role … A builder (no arm sentinel, not the desk role) is still never touched". `grep -rl "memory_pressure\|phys_footprint\|vm_stat"` over `hooks/ scripts/ bin/` → only `capacity-alarm.sh`, `capacity-ramp.sh`, `capacity-admit.sh`, `compressor-sentinel.sh`, `lead-crash-watchdog.sh` — all **alarm/admit**, none **reap**
Cost now: 3 sessions idle > 20 min holding **1 222 MB**; 4 idle > 10 min holding **1 597 MB** (idle = transcript-mtime age; the 20 h session 56864 has been idle 149 min at 457 MB)
Re-architecture: add an **idle-minutes** term beside the context-% term in `waiting-recycle.sh`, and extend eligibility past the desk role for sessions with a clean tree; a recycle at 30 min idle returns the session to the 228 MB floor
Sizing: recovers ~1.2 GB at any given moment · effort **M** · risk **Med** (a wrong recycle interrupts a healthy builder — which is exactly why the desk-only gate exists)
Existing mechanism: `waiting-recycle.sh` — **EXTEND** with an idle-time tier; do not build a new reaper

**Finding: the Agent-spawn capacity gate exists and is wired, but its memory term only binds at the cliff**
Evidence: `hooks/agent-teams-enforce.sh:79` `CC_ADMIT_LOAD_TERM=off cc_capacity_admit agent-tool "…spawn"`; `scripts/lib/capacity-admit.sh:122` `CC_HW_DEFAULT_MIN_HEADROOM_GB=4`; `:163` headroom = free+speculative+inactive+purgeable. Live headroom now = **29.6 GB** (vm_stat) ⇒ the gate admits every spawn
Cost now: 0 today, but the gate cannot see a 15-teammate wave arriving until reclaimable headroom is already under 4 GB
Re-architecture: add a **source-side** bound — `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` — so fan-out is capped before the machine-level rung is consulted
Sizing: bounds the per-session tail from 4.7 GB (20 × 233 MB) to 3.7 GB at cap 16 · effort **S** · risk **Low-Med**
Existing mechanism: `agent-teams-enforce.sh` + `capacity-admit.sh` already exist and already gate the Agent tool — this is the **unused knob** `11-prior-art.md:200` already named, not new machinery

**Finding: the 1 M window with auto-compact off is the whole variable cost of a session**
Evidence: all 56 `/tmp/cc-telemetry/*.json` report `window: 1000000`; `autoCompactEnabled: false` in `~/.claude/settings.json`, `~/.claude-tertiary/settings.json`, `~/.claude.json`; regression `FP = 228 + 0.343·Ktok + 0.071·min` (R²=0.71, n=21); live spread 219 MB → 469 MB
Cost now: mean context term ≈ 110 MB/session ⇒ **~1.7 GB across 16 sessions**; ceiling 343 MB/session ⇒ 5.1 GB of tail
Re-architecture: `CLAUDE_CODE_DISABLE_1M_CONTEXT=1` (hard, doctrine-breaking) or `CLAUDE_CODE_MAX_CONTEXT_TOKENS=<n>` (soft, semantics unverified) or re-enable auto-compact
Sizing: −60 MB/session at today's fill, −274 MB of per-session ceiling · effort **S** to set, **L** to absorb · risk **High** (all Context-Stewardship thresholds are expressed as % of 1 M; `/compact` crashes teammates, GH #49593 — which is *why* auto-compact is off)
Existing mechanism: `settings.json` `env` block — already carries 8 `CLAUDE_CODE_*` keys

---

## 5. Adversarial self-pass (what I got wrong, and what a hostile reviewer would say)

1. **I mis-classified `claude.exe` as subagents — and so does the pre-spawn brief.** My first three
   tool calls assumed `claude.exe` = CC-spawned subagent. The ancestry walk refuted it: **0 of 34 CC
   processes has a CC parent**; the 18 `claude.exe` are Agent-Teams *teammates* spawned through
   `bin/cc-pane-runner`. The decomposition file's "claude.exe (subagents) ×5 = 2.7GB" should read
   *teammates*, and there are 18 of them, not 5. Corrected in §0b; it changes the lever (G5/G6, not
   an in-process heap knob).
2. **I nearly reported "browsermcp is never used" from a substring count.** `grep -l mcp__browsermcp`
   hit **583 of 600** transcripts — but that string appears in the *global CLAUDE.md text* ("the
   `mcp__browsermcp__*` tool list"), not in tool calls. Parsing `tool_use` blocks properly:
   browsermcp **0 calls**, chrome-devtools **946 calls / 19 transcripts**, motion 16, motion-plus 10,
   uidotsh 3. Same class as memory `pgrep-f-matches-agent-briefs`. The corrected reading is what makes
   G4 "opt-in", not "delete".
3. **"Correlation, not causation" on the context regression.** A single-predictor fit was weak
   (R²=0.48) and confounded with age. Controlling for `etime` gives R²=0.71 with the age coefficient
   collapsing to 0.071 MB/min — i.e. the context term survives age control, and age-matched pairs
   agree (pid 8042: 28 min/119 K/263 MB vs pid 71372: 29 min/203 K/295 MB vs pid 2795: 55 min/430 K/338 MB).
4. **Axis I could claim the transcript is the memory, not the context.** Transcript file sizes range
   0.7 MB → 19.1 MB and do *not* track footprint (pid 4501 has a 19.1 MB transcript at 390 MB; pid
   98361 has 9.2 MB at 469 MB). The regressor that works is `input_tokens`, i.e. the *live* window,
   not the on-disk log. Recycling therefore helps; truncating logs does not.
5. **The prescription I would have re-committed.** `NODE_OPTIONS=--max-old-space-size` was already
   proposed, measured and **rejected** for CC (`l3-l4-terminal-and-workflow-2026-07-31.md:14,296`;
   `MACHINE_CAPACITY_V2.md:1080`). I verified independently (bun/JSC strings) and marked it dead —
   G9. G1 is the *distinct* case (node-based MCP servers) and I say so explicitly so the next reader
   does not fold them back together.
6. **What I still cannot see:** whether `CLAUDE_CODE_MAX_CONTEXT_TOKENS` actually clamps the window
   or is Bedrock/Vertex-only plumbing — it sits in a string table next to `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`
   and `CLAUDE_CODE_AUTO_COMPACT_WINDOW`, and `docs/KIMI_METERED_INTEGRATION.md:48` uses it as a
   *provider* setting. Verifying costs one live `-p` session; I did not spend one (boundary: change
   nothing).

---

## 6. Ruled out / negative findings (do not re-research these)

| Candidate | Verdict | Evidence |
|---|---|---|
| `NODE_OPTIONS` on the CC process | **inert** | `claude.exe` = bun-compiled Mach-O (JavaScriptCore) |
| Statusline memory | **~0** | peak transient child RSS 4 MB; 0.06–0.13 s/render; already 2 git calls |
| `browsermcp` / `agent-browser` servers | **not running, 0 cost** | `$CFG/.mcp.json` is never read (CC reads the *project* `.mcp.json`); 0 processes; 0 tool calls in 7 d |
| `motion` / `motion-plus` / `uidotsh` | **0 local RAM** | all `type: http` — no child process; cost is tool-schema context only |
| `CLAUDE_CODE_MCP_TOOL_IDLE_TIMEOUT` as an idle-server reaper | **wrong mechanism** | binary string: *"…no response or progress for Ns; aborting"* — it aborts a silent **tool call**, it does not shut down an idle **server**. There is no CC-side idle-MCP reaper |
| `CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP` | **leave ON (unset)** | the default path registers `process.on("memoryPressure")` and kills background shells under pressure — CC's only built-in memory defence. Disabling it removes a protection |
| `CLAUDE_CODE_DISABLE_FILE_CHECKPOINTING` | **not a RAM lever** | checkpointing is disk-backed (`~/.claude/file-history`) |
| `caffeinate` / shell snapshots | **negligible** | 3.3 MB + 1–5 MB each |
| Leftover isolated Chrome profile dirs | **none** | no `chrome-devtools-mcp*` dirs under `$TMPDIR`; no browser processes at all |

---

## 7. Blockers and uncertainties (named)

1. **`CLAUDE_CODE_MAX_CONTEXT_TOKENS` semantics unverified** — the soft alternative to G7 hinges on
   it. One headless `claude -p` run in a throwaway `CLAUDE_CONFIG_DIR` settles it; out of my boundary.
2. **G5 (`teammateMode: "in-process"`) is an operator value call, not an F1-F4 auto-pass.** It is the
   largest single lever measured (−2.3 GB on this wave) and it contradicts a standing operator
   preference for visible panes. Surface it; do not adopt it.
3. **`~/Development/reso-management-app/.mcp.json` is git-tracked** — G1/G2/G3 edit a shared,
   committed file in a *different* repo. That repo's own `CLAUDE.md` governs landing there; a
   claude-infrastructure session cannot see it (global CLAUDE.md § ship policy).
4. **The 2.28× rss:footprint ratio is a snapshot** with swap at 0. Under real pressure, compressed
   and swapped pages move between the two figures. Re-derive with `vmmap`, never quote this ratio.
5. **The idle census uses transcript mtime as the idle proxy.** A session thinking for 20 min with no
   tool call reads as idle. `hooks/lib/context-econ.sh:388-416` already documents the pid-recycling
   hazard in the adjacent join; any idle-based reaper must key on the subject's own mutex, not age
   (memory `liveness-proxy-cannot-be-output-age`).
