# E — Marginal local cost of one more agent, by kind (M1 Max, 10 cores, 64 GB, CC 2.1.284)

**Date:** 2026-10-04 01:45–02:05 local · **Box state while measuring:** load1 123–168, `top` CPU **0.0% idle (60.6% user / 39.4% sys)**,
PhysMem 61 G used / 1.25 G unused, compressor 6.9 G, swap 1.75 G used, 1,448–1,691 processes, ~400 new pids/s.
Read-only throughout; no process killed or started apart from my own `ps`/`lsof`/`footprint` probes.
Labels: **[M]** measured here · **[I]** inferred · **[Q]** quoted from a prior doc (path given).

---

## 0 · Answer first

1. **(a) In-process subagents and workflow agents cost almost no memory: ≈0–5 MB of physical footprint each [M].**
   Lead pid 82868 hosted 10 concurrent subagents at **364–370 MB `phys_footprint`**. Idle peer sessions measured 347–397 MB.
   They are **not free on CPU**, though. Over a 1,027 s window the lead burned **15.3% of a core with a mean of 6.7 subagents
   mid-turn**, which is **≈1.9% of a core per active subagent** on the lead's single JS thread. On top of that comes each
   tool call's hook chain and the command itself. Together this measured **≈0.42 runnable processes per active subagent [M]**.
2. **(b) Each Bash call now fires 20 registered hook processes [M]** (11 PreToolUse, 8 PostToolUse, 1 PostToolBatch).
   On 2026-08-09 the chain was 13. Each hook execs more children inside itself (≈80–110 execs per Bash call [I]).
   **The hooks fire for subagent tool calls too [M].** A 20-member no-op burst costs **240 ms of CPU and 636 ms of wall time at
   today's load [M]**. That is the floor; the real chain costs ~0.5–1.1 s of CPU [I].
3. **(c) Cheapest shape for 1,000 agents:** in-process subagents or workflow agents under a few long-lived lead processes.
   Each lead should be headless (`--bg`/`-p`), carry ≤ ~40 active agents, and run with a stripped per-tool hook chain.
   The agents get no per-agent MCP server and no per-agent browser. **Teammates are the most expensive shape**
   (≈380 MB, a pane, a worktree, and 18 SessionStart + 13 Stop hooks per turn).
4. **The ceiling does not reach 1,000 on one M1 Max at current per-agent CPU [I].** With today's hook chain, about
   **50–80** agents can be tool-calling at once. Stripping the hooks raises that to about **150–200**. The lead's JS alone costs
   ~1.9%/active agent, so 1,000 working agents need ~19 cores. **1,000 is reachable only if ≤ ~20% of agents are mid-turn at any
   instant, or across ~5 boxes.** Memory is not what binds the in-process shape.
5. **(d) Most prior numbers hold on 2.1.284.** Two changed materially:
   - the hook chain grew 13 → 20 per Bash call;
   - the dominant non-Claude load is now **orphaned `agent-browser` Chrome trees**: 7 trees, ~10.4 GB RSS, 23.6 runnable
     processes. They are the largest single item on the box right now.

---

## 1 · Per-agent-kind table

Footprint = `footprint -p` `phys_footprint` (the honest memory number). RSS is shown because the operator quotes it, and it
overstates: the lead read **1,022 MB RSS at 364 MB footprint (2.8×) [M]**. Over 17 minutes the lead's RSS grew +180 MB
while its footprint stayed flat (370 → 364 MB) [M]. So **RSS growth is not memory growth**, and the "380–900 MB per
session" figure overstates real cost by 1.3–2.8×.

| Agent kind | Memory (footprint; RSS) | Idle CPU | Active CPU | Processes / fds | Attached tool work |
|---|---|---|---|---|---|
| **Top-level session in a kitty pane** | proc **248–397 MB** fp (RSS 330–830) [M]; **+101–103 MB** `ms-365-mcp-server` fp [M]; +~10 MB watcher shells ⇒ **≈360–510 MB/unit** | **0.7–3.5% core** (150 s window, 9 idle sessions; median ~3%) [M]; R-procs 0.02–0.06 [M] | 6–17% core self, **≈1.0 R-proc** per active session [M]; Aug marginal **2.39 ± 0.53 load units / active session** [Q `marginal-load-per-active-session-2026-08-19.md` §6e] | 15–24 threads, **27–64 fds**, 2–30 TCP [M]; 5–8 resident descendants: MCP node, `cc-await-ping` (zsh+bash+Python, forks `sleep` every 15 s), `lead-crash-watchdog` (30 s poll), `mailbox-wake-arm` [M]; 1 pty / kitty window | SessionStart: **18 hooks** (Aug: ≥4.7 s serial CPU, ~865 forks [Q `memory-econ…/hook-forks.md`]); every turn end: **13 Stop hooks** (Aug ~2.2–3.8 s, 124 execs [Q]); per tool call: see §2 |
| **In-process subagent (Agent tool)** | **≈0–5 MB** fp [M: lead 364–370 MB with 10 vs peers 347–397]; Aug **0.6–11 MB** [Q `orchestration-units-2026-08-19/A8-marginal-cost.md` §3] | ≈0 when API-blocked [I; A8 0.02 load] | **≈1.9% core on the lead's JS thread** [M] + hooks + the command; **0.42 R-procs/active subagent** [M: 4.18 R for lead+~10] (Aug 0.315 [Q A8]) | **0 processes, 0 panes, ~0 fds of its own** [M: 0 extra claude pids]; ~1.5–3 TCP streams per active subagent on the lead (lead 17–30 established) [M] | Tool calls fire the full PreToolUse/PostToolUse chain [M]. **No SubagentStart/SubagentStop hooks are configured** [M `~/.claude/settings.json`], so the lifecycle is hook-free. Default concurrency cap per session is set by `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` [M: present in the 2.1.284 binary]; the default value is not readable from strings (2.1.220: 20 [Q A4]) |
| **Workflow agent** | same as the in-process subagent [I]: node:vm async generator, no `child_process` [Q `A4-workflow-engine.md` §1, 2.1.220] | ≈0 [I] | same as the subagent [I] | 0 processes [Q A4]. Separate cap `CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS` [M: in the binary], a pool disjoint from the subagent cap [Q A4] | same hook exposure per tool call [I] |
| **Named teammate (own pane + worktree)** | **≈380 MB** fp (proc 277–281 + MCP 102) [Q A8, 2.1.220]; none live today, so it was not re-measured. It is the same binary and launch path as a session, so ≈ the session row [I]. Plus a worktree: **246 MB of disk** [M], no RAM | as a pane session: 0.7–3.5% [I] | as a session; Aug 0.03 load when API-blocked [Q A8] | a full session tree (6.4 resident procs, 28–30 fds + 23 for its MCP [Q A8]) + 1 kitty pane | **WorktreeCreate hook** (`worktree-setup.sh`, 180 s timeout, `git worktree add` + pnpm layout) + 18 SessionStart + 13 Stop per turn + the full per-tool chain. The most expensive kind per unit |
| **Headless `claude -p`** | **≈190 MB** proc + **≈101 MB** MCP ⇒ **≈295 MB** [Q A8 §3]; drops to ~190 MB with `--strict-mcp-config` and an empty config [I]. Proxy measured today: an unattached `bg-spare` = **298 MB** fp at **0.72% core** idle [M] | no TUI: ~0.7% (bg-spare proxy) [M] | Aug **1.0–1.3 R-procs (1.5–2.0 load)** at 100% mid-turn [Q A8] | 15 threads, 36–38 fds [Q A8] | Fires SessionStart + Stop + the per-tool chain [Q A8 §4]. **`--bare` strips hooks, but it never reads OAuth or the keychain** (API key only) [M `claude --help`], so it is **unusable on the Max accounts** |
| *(2.1.284-new)* daemon + `bg-spare` pool | daemon **107–173 MB** RSS; each pre-warmed spare **~298 MB** fp [M] | 0.36–1.56% (daemon), 0.72% (spare) [M] | — | 2 daemons, each with bg-pty-host + spare [M] | a hidden ~300 MB per warm spare that no census counts |

### Attached tool work (per agent, when it happens)

| Work | Cost | Evidence |
|---|---|---|
| **One Bash tool call** | **20 hook processes** (+ ~60–90 internal execs [I]); CPU floor 240 ms per 20-burst at load ~150, real chain ~0.5–1.1 s [I from Aug's 728 ms for 13 hooks × 20/13] | §2 |
| Fork-latency inflation under contention | `/usr/bin/true` **35.7 ms p50** today vs **2.4 ms** in Aug; `bash -c` 27 ms (Aug 5.0); `jq` 24 ms (5.0); `python3 -c pass` **126 ms** (39.5) [M vs Q `scaling-bottlenecks-2026-08-09/12-felt-lag.md`] | `/tmp/concurrency-scale/e_floor.py` |
| Agent tool-call rate (this research wave) | **2.56 tool calls/min/agent**, 85% Bash (411/485) [M] | sibling transcripts, 17.2 min |
| Lead with 10 subagents, fork rate | **≈18 new processes/s** (polling lower bound); an idle session runs 0.1–0.3/s [M] | `e_forkattr2.py` |
| **Browser run (`agent-browser`)** | **1.0–2.9 GB RSS per run and 0–1.6 cores**. The trees **outlive the agent**: 7 orphan trees (ppid 1, aged 70–80 min), **10.4 GB RSS, 23.6 runnable processes** (25% of the whole box's R) [M] | `ps` tree walk |
| MCP child per process | `ms-365-mcp-server` **101–103 MB** fp each (RSS 27–46 MB understates it) [M]. The 507 MB/session `chrome-devtools-mcp` of Aug is gone [Q `scaling-bottlenecks-2026-08-09.md:31`] | `footprint` |

---

## 2 · Per-tool-call hook cost (question b)

Taken from `~/.claude/settings.json`. `~/.claude-quaternary/settings.json` is a symlink to it [M].

| Event | Entries matching `Bash` | Hooks |
|---|---|---|
| PreToolUse | **11** | smart-bash-allowlist, curl-gate-scope, validate-bash (2,306 lines), git-worktree-guard, keychain-guard, rm-safe-allowlist, ship-rail-push-allow, qos-rewrite, coldcompile-admit, pr-gate, research-block (`*`) |
| PostToolUse | **8** | log-bash, waiting-recycle (1,593 lines), relay-verbatim, teammate-checkpoint (`""`), cc-permission-beacon (`""`), mailbox-drain (`""`), memory-index-drain, bash-output-offload |
| PostToolBatch | **1** | post-tool-batch |
| **Total per Bash call** | **20** | Aug 2026-08-09: 13 [Q `12-felt-lag.md:85`] |
| Non-Bash, non-edit tools | 1 Pre + 3 Post + 1 Batch = 5 | |
| Turn end (Stop) | 13 | session-continue, operator-readout, dispatch-assert… |
| Session start | 18 | |

- **The hooks fire inside subagents [M].** My own subagent transcript records a `hook_success` attachment with
  `hookName: "PostToolUse:Bash"` (`agent-a7b9ba866f225d2cf.jsonl`). An in-process agent avoids the session-level
  hooks (SessionStart and Stop) but **not** the per-tool chain.
- **Live wall-clock times, last 24 h, 278 transcripts [M]:**
  - `smart-bash-allowlist` p50 **89 ms** / p90 440 ms (n=1,901);
  - `qos-rewrite` p50 154 ms;
  - `bash-output-offload` p50 122 ms;
  - `mailbox-drain post-tool` p50 612 ms.

  Only hooks that emit output are recorded, so these are biased toward the slow path.
- **No-op dispatch floor [M]** (`/tmp/concurrency-scale/e_floor.py`; 20 parallel `bash -c 'cat | jq'` members, n=10):
  **636 ms wall p50 (846 max), 240 ms CPU per burst** at load ~150. So before any hook does real work, the
  *registration count alone* costs ~¼ s of CPU per Bash call at this load.
- `scripts/hook-dispatch-bench.sh` exists. It is synthetic-only by design and refuses on a loaded box (exit 4,
  `CC_HDB_MAX_START_LOAD`), so it was not run. Its header records the governing mechanism: cost per fork scales with
  load. Going from 4 to 16 concurrent made each fork ~21× dearer (`scripts/hook-dispatch-bench.sh:33-36`).
- **Scale arithmetic [I]:** 1,000 agents × 2.56 calls/min = **43 tool calls/s**. With today's chain that is ~850 hook
  processes/s, ~3,000–4,500 execs/s, and **10–47 cores** of hook CPU. **At 1,000-agent scale the hook chain alone
  exceeds the box.** Collapsing the per-tool chain to ≤ 2 cheap entries brings it to ~1 core.

---

## 3 · Agents-per-machine ceiling each implies (10 cores, 64 GB)

Budgets: ~**40 GB** usable for agents (prior 38–42 GB [Q `scaling-bottlenecks-2026-08-09.md:30`]; today browsers alone
hold >13 GB). About **5–7 cores** are usable before fork latency explodes (today's 0%-idle box gives `/usr/bin/true` a
15× latency).

| Kind | Memory ceiling | CPU ceiling (all mid-turn) | CPU ceiling (≤ 20% duty, i.e. most agents API-blocked) | Binding term |
|---|---|---|---|---|
| Pane session | 40 GB / 0.45 GB ≈ **~90** | ~8 active on the load gate [Q `CC_ADMIT_ACTIVE_CEILING=8`]; idle TUI cost alone: 100 × 2–3% = 2–3 cores | ~60–90 resident | memory + idle TUI CPU; GUI/pane count |
| Teammate (pane + worktree) | ≈ **~100** | same as a session | ~60–90 | memory; SessionStart/Stop/worktree churn |
| Headless `-p` (one process per agent) | 40 / 0.30 ≈ **~135** (≈210 without MCP) | ~50–70 (1.0–1.3 R each) | ~130 | memory + per-launch SessionStart chain (multi-second CPU each) |
| **In-process subagent / workflow agent** | **>4,000** (bounded only by its leads: 25 leads × 0.4 GB = 10 GB) | today's chain **~50–80**; stripped hooks **~150–200** | stripped hooks + headless leads: **~750–1,000** | **CPU: lead JS ~1.9%/active + hooks + commands**; ≤ ~40–50 active per lead (one JS main thread ≈ 1 core) |

The 50–80 and 150–200 figures come from 5–7 usable cores ÷ per-active-agent CPU:
- **today, ≈ 7–9% of a core** each: 1.9% lead JS + 2–4% hooks + 1–3% commands;
- **with ≤ 2 lean hooks, ≈ 3.5–4.5%** each.

Both figures are [I]: they are built from measured parts, but nobody has measured the sum at that N.

**The operator's ~15 sessions / ~100 agents lag is consistent with this [M+I].** Right now ~20 Claude trees hold only
**12.4 of 93 runnable processes (13%)**. Non-Claude work holds **80.2 (86%)**:
- `agent-browser` Chrome trees: 23.6
- Google Chrome: 10.2
- MTLCompilerService: 8.0
- launchd-bash automation (`deploy-live`/bats, `autonomy-sweep`, `capacity-alarm`, `cc-dispatch`, `cc-reaper`…): ~15

Measured by `e_perroot.py`/`e_nonclaude.py`. The claude processes themselves sum to **~0.8 cores** [M,
`cpudelta.py`]. The lag is **fork contention plus browser trees, both triggered by agents' tool work**, not the agents.

---

## 4 · Cheapest agent shape for 1,000-agent scale (question c)

**In-process subagents or workflow agents under ~25–50 long-lived leads**, with these properties:
1. **Headless leads** (`claude --bg` / `-p`, OAuth-compatible). This removes the 1–3% idle TUI cost per lead and probably
   part of the 1.9%/active render cost. The render share is unmeasured, and it is the next experiment (§6).
2. **≤ ~40 active agents per lead.** Each lead is one JS thread. Raise `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` or
   `CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS` per lead rather than adding panes.
3. **A lean per-tool hook profile for fleet agents.** The 20-entry chain is the largest per-call cost and scales linearly
   with agent count. `--bare` is out because it is API-key-only. Candidate routes [I, not verified here]:
   - `--setting-sources` excluding `user`, with the needed guards re-supplied via `--settings`;
   - an env-gated early `exit 0` in each hook;
   - fusing the guards into one dispatcher.

   Aug measured the dispatcher route as a latency regression in the *parallel* regime
   [Q `hook-forks.md` §7]. At 1,000 agents the box is in the contended regime, where `hook-dispatch-bench.sh` predicts
   the opposite.
4. **No per-agent MCP and no per-agent browser.** Use one shared, pooled browser with an enforced reaper. Today's 7 orphan
   Chrome trees (10 GB, 25% of the box's runnable processes) are the clearest single waste.
5. **Avoid** teammates (≈380 MB plus a pane, a worktree, 18+13 session hooks) and one `claude -p` per agent
   (≈300 MB plus a full SessionStart chain per launch) for the bulk fleet. Keep them for long-lived, code-writing,
   isolated work.

---

## 5 · Do the prior numbers hold on 2.1.284? (question d)

| Prior claim (version) | Today on 2.1.284 | Verdict |
|---|---|---|
| In-process subagent 0.6–11 MB fp; 0 processes or panes (A8, 2.1.220) | lead with 10 subagents 364–370 MB vs peers 347–397; no extra pids | **Holds** |
| Session footprint 290–460 MB tree-inclusive (A8) | proc 248–397 MB + MCP 101–103 MB | **Holds** |
| RSS overstates footprint 1.3–1.7× (A8) | 1.3–2.8× (lead 1,022 RSS / 364 fp) | **Holds, and is worse** |
| In-process subagent 0.315 R-procs active (A8) | **0.42** | Holds in order of magnitude |
| Idle session 0.02–0.06 R (A8) | 0.02–0.06 R; but **0.7–3.5% core CPU** | Holds; CPU% was not in A8 |
| claude.exe ≈4.7% of the load numerator (gc-cpu doc, process-only) | Claude *trees* 13% of R; claude processes ~0.8 cores | **Holds**: still not Claude itself |
| Per Bash call: 13 hook processes (Aug 9) | **20** | **Changed: +54%** |
| MCP ~507 MB/session (chrome-devtools-mcp) | ~101 MB (ms-365) | **Changed: better** |
| Fork rate 530–1,207 pids/s (A8) | ~400 pids/s | Lower; it was never a discriminator [Q A8 §3c] |
| Marginal 2.39 load / active session (2026-09-08) | not re-measured; it needs a 1–7 h window | **Unverified on 2.1.284** |
| Concurrency cap 20 per session, 200 lifetime (2.1.220) | knobs still present: `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`, `…_MAX_SUBAGENTS_PER_SESSION`, `…_WORKFLOW_MAX_CONCURRENT_AGENTS`; defaults not readable from strings | **Knobs exist; defaults unverified** |
| fds/pids are not walls | maxproc 16,000 (10,666/uid), maxfiles 491,520, `kern.num_files` 14,558; 1,448–1,691 procs live | **Holds**: 1,000 in-process agents add ~0 of each |

---

## 6 · Adversarial pass: gaps found and what was done

- **No teammate or `-p` session was live, and the brief forbids starting one.** Both rows rest on A8 (2.1.220) plus
  today's `bg-spare` proxy. They are marked [Q]/[I]; teammate and headless figures were not re-measured on 2.1.284.
- **The 1.9%/active-subagent lead CPU may include TUI render of the agent panel.** A headless lead would show the split.
  This is the single most decision-relevant unmeasured number: it alone decides whether 1,000 fits in ~19 cores or in a
  fraction of that. **Next experiment:** one `claude -p` lead running a 10-agent workflow, with `ps time` sampled every
  10 s, against this TUI lead's 15.3%/6.7 active.
- **Idle-session CPU varied between windows** (74 s: 1.2–1.9%; 150 s: 2.6–3.5%) under load 123–168. The range is quoted,
  not a point. A hook-free cause (Ink render timers) is likely but unverified.
- **Load-inflated measurements.** Every CPU and latency figure was taken at 0% idle. Fork latencies are ~10–15× the Aug
  quiet-box floors, so per-call ms are upper bounds for a calm box. They are also exactly the regime 1,000 agents create.
- **The fork-attribution polling is a lower bound** (it catches ~80/s of the ~400/s). It was used for shares only.
- **The API quota and rate limit for 1,000 concurrent agents is not a local resource and was not assessed.** It may bind
  before any number here.

## 7 · Artifacts (all under `/tmp/concurrency-scale/`)

| File | What it measures |
|---|---|
| `tree.py` | descendant census |
| `cpudelta.py` | 60 s CPU deltas |
| `e_sampler.sh` / `e_sampler.log` | lead RSS/CPU/TCP vs active subagents, 90 rows × ~11 s |
| `e_perroot.py` | runnable processes per root |
| `e_nonclaude.py` | non-Claude runnable processes by top-level root |
| `e_forkattr.py` / `e_forkattr2.py` | new-process attribution |
| `e_floor.py` | fork floors and the 20-member no-op burst |
| `e_hooks2.py` | live hook durations from transcripts |
| `e_rate.py` | tool-call rate |
| `e_idle.py` | 150 s idle CPU |
