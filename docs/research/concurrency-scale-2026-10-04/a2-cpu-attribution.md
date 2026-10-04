# A2: CPU attribution by category of work (10-core Mac, 2026-10-04)

**Answer first.** About half of the CPU at busy times cannot be attributed to any process the samplers can see. Live samples taken while load was 109-153 on 10 cores found the CPU at 0% idle, split roughly 60% user and 40% sys. Of that capacity:

- Processes that `top` could still see across a 4 s window accounted for only **36-60% (mean 46%)**.
- The other **40-64% (mean 54%)** belongs to short-lived processes that started and exited between samples. The machine was creating **~500-700 processes per second** (MEASURED from how fast PIDs advanced).

Among the work that is visible:

- **Session-launched automation Chrome** is the largest category, at ~20% of the machine.
- **System** is next at ~13%. Part of it is caused by process churn: XprotectService and syspolicyd scan every new executable (INFERRED).
- **The `claude` processes themselves** take ~8% across 51-54 processes, which is ~1.6% of one core each.

The tool-call rate is a weak proxy for load (minute-level Pearson r = 0.33). The mid-load and busy bands had nearly the same tool-call rate (19.4 vs 26.9 calls/min) but **5× different load (33 vs 165)**. So load is driven by *what* a call launches (long-running ffmpeg, image cropping, agent-browser Chrome, polling loops), not by how many calls there are. That supports the operator's hypothesis.

There is **no continuous CPU-by-category history**. Every recurring sampler records RSS or aggregate load only. The single per-process CPU history is triggered by memory events and ranked by RSS.

Scripts and raw samples: `/tmp/concurrency-scale/a2work/` (`cat.py` classifier, `live.py`, `sent.py`, `stats.py`, `d.py`, `churn.py`, `ps*.txt`, `top*.txt`, `snaps.txt`).

---

## 1. Category → share of CPU, busy vs quiet

Shares are % of total machine capacity (1000% = 10 cores) unless marked "share of captured".

| Category | Busy NOW: live `top`, 6 × 4 s, load 109-153 (MEASURED) | Busy history: sentinel trips with load ≥ 60, n=95, mean load 224 (MEASURED, see bias) | Mid history: load 20-60, n=135 | Quiet history: load < 20, n=32 | Notes |
|---|---|---|---|---|---|
| Browser | **204%** (123-316) = 20.4% | 28% / 8.9% of captured | 32% / 10.5% | 20% / 5.6% | Live: ~95% of it is session-spawned. `agent-browser-chrome-*` and headless `/tmp` profiles used 222% of 232% in a ps snapshot; the operator's Dia used ~10%. The hottest profile's GPU helper used 49 min of CPU in 83 min of life (59% average), which stays under browser-spin-guard's ≥80%/≥900 s trigger. |
| System | **131%** (120-142) = 13.1% | 77% / 24.0% | 77% / 25.0% | 73% / 20.2% | WindowServer 38%, kernel_task 36%, XprotectService 16%, syspolicyd 9%, fseventsd 6%. In history fseventsd reaches 46-55%, i.e. file events from worktree, git and build churn. |
| `claude` processes | **84%** (40-153) = 8.4% | 54% / 17.1% | 55% / 17.9% | 28% / 7.7% | 51-54 claude processes and 23 sessions (capacity-alarm `sessions`), so ~1.6% of a core per process. |
| Shells/hooks | **16%** visible | 25% / 7.9% | 17% / 5.6% | 17% / 4.7% | Badly undercounted: these are the short-lived processes in the dark row below. |
| Search (ugrep/grep/find) | **13%** | 12% / 3.7% | 22% / 7.2% | 16% / 4.3% | `grep` is aliased to `ugrep … --exclude-dir=.git`. History has single ugrep runs of 63-90% CPU and up to 9 GB RSS scanning `node_modules`. |
| Test/lint/build | **6%** | 61% / 19.2% | 68% / 22.1% | 187% / 52.1% | History: next-server, next-build, tsc, eslint, tsgolint, swift-frontend. The quiet-band figure is dominated by one runaway clang-format at 100%. |
| Media/OCR | **~0%** in top; a crop.py was at 115% in a ps snapshot | 32% / 10.0% | 10% / 3.3% | 1% / 0.2% | Bursty. The operator's sample (magick, tesseract, ffmpeg ≈ 321% "other") was taken in a media burst. Hour 2026-10-04T01Z had load 359, ffmpeg as the top process by RSS in 268 of 197×3 top3 slots, and only 70 tool calls. |
| Git | **1%** | 1% / 0.4% | 2% / 0.6% | 3% / 0.8% | One git at 141% CPU and 16 GB RSS is in the 2026-10-04T00:21Z trip. |
| Terminal (kitty) | 2% | 0 | 2% | 0 | — |
| Other | 7% | 28% / 8.8% | 22% / 7.2% | 15% / 4.2% | Hammerspoon, OneDrive, llama-server, qemu, unidentified Python. |
| **Dark: CPU of processes that exited inside the window** | **~537% (396-639) = 54%** | not visible | not visible | not visible | INFERRED as the gap between `CPU usage: 0% idle` and the sum of per-process %CPU. Its scale matches measured churn × measured spawn cost (§5). |

**Sources and bias**
- Live column: `top -l 2 -s 4 -n 600 -o cpu -stats pid,cpu,command` (second sample) joined to `ps -Axo pid=,ppid=,args=` by pid, then classified by `/tmp/concurrency-scale/a2work/cat.py` (rules key on the executable; interpreters are classified by their script).
- History columns: `~/.claude/logs/compressor-sentinel-snap.log`, using the first "top 30 by RSS" block of each `═══ TRIP` (409 trips with rows, 2026-08-06 → 2026-10-04). Each trip is banded by the nearest `load_1m` within 300 s in `capacity-alarm.jsonl` (plus the `.20260919T081621Z.gz` archive) or by `load.jsonl`. 147 earlier trips have no load and are excluded.
- Bias: trips fire on memory pressure, not CPU, and rows are ranked by RSS. Captured CPU is only 300-360% per trip, roughly a third of a saturated machine. Small CPU-heavy processes (hooks, jq, tesseract, short git) never appear in it.
- **There is no quiet-period live sample.** The machine stayed at load 109-153 for the whole run. The quiet column comes only from the sentinel log (n=32).

## 2. (a) Tool-call rate from tool-batch-census (MEASURED)

Window: 2026-10-02T01:51Z → 2026-10-04T06:45Z, 3,173 minutes. 30,650 batch rows, 34,325 calls, 160 distinct sids, 0 abstain rows, 0 malformed. Query: `python3 /tmp/concurrency-scale/a2work/rate.py` then `stats.py`.

**Validity checks**
- **Bash coverage is complete.** Over 2026-10-02T22:30Z–2026-10-04T06:40Z the census Bash count was 13,636 against 13,579 in `bash-execution.log`, and every bash-exec sid also appears in the census.
- **Subagent and Workflow calls are included under the lead's sid.** The census records 62 `SubagentHandback` calls, a tool only subagents have. Sid 884aa5bc has 9 tool_use entries in its own transcript but 2,012 census calls, because its Workflow agents roll up into it.
- So "per session" means a lead plus all its agents.
- The hook is registered once in `~/.claude/settings.json:615-620`. That file is symlinked as the settings for the next, secondary, tertiary and quaternary accounts.

**Tool mix:** Bash 81.7% · Read 7.3% · Edit 3.3% · WebSearch 2.1% · Write 2.0% · StructuredOutput 1.1% · WebFetch 0.6% · ToolSearch 0.4% · **Agent 0.2% (80 calls)** · Workflow 28 calls. Mean batch size is 1.12. Effort: high 65%, xhigh 34%.

**Rates**
- All minutes: mean 10.8 calls/min, p50 0, p90 38, p99 95, max 156.
- Active sids per minute (minutes with any call): mean 2.47, p50 2, p90 5, max 9.
- Distinct sids active per hour: up to 31.
- **Calls per active sid per minute: mean 9.4, p50 5.3, p90 22.**
- Normalised by hour (calls ÷ 60 ÷ sids active that hour): 0.02-4.5. The busiest hours (2026-10-04T05-06Z) ran 3.2-4.5 calls/min per sid across 14-15 sids.
- Live now: ~108 calls in ~2 min from 4 sids, against ~700 new processes per second. So **hundreds of processes are spawned per tool call**, which means long-running Bash commands (loops, pipelines, pollers) are the unit of cost, not the call.

## 3. (b) Which samplers carry CPU (MEASURED, from source)

| Sampler | Cadence | Per-process CPU? | What it carries |
|---|---|---|---|
| `~/.reso/load.jsonl[.YYYYMMDD]`, from `reso-management-app/scripts/load-sampler.sh` (identical to the `cf-audit-target` copy; launched by `~/.reso/load-sampler-run.sh`) | 10 s (`:29`) | **No.** RSS only. | `loadavg` (`:58`), `runnable` = count of processes in state R (`:62`), top3 by **RSS** (`:66`), cc-sem holders. Kept for 14 days (`:49`), so history starts 2026-09-18. |
| `capacity-alarm.jsonl` (`scripts/capacity-alarm.sh`) | ~65-110 s | **No.** `top_procs` comes from `read_top_procs` (`:752`) and the `ps -eo pid=,rss=,comm=` fallback (`:826`), i.e. RSS. | load_1m/5m/15m, memory, sessions, ptys, coalition process counts. |
| `qos-census.jsonl` (`scripts/qos-census.sh`) | 600 s | **Bats runner frames only.** `cpu_total` sums `%cpu` over bats-core frames (`:300-351`), not the commands under test. | PRI band per bats process and run. Mean `cpu_total` is 0.3-2.5%, so it is useless as a CPU measure. |
| `compressor-sentinel-snap.log` | event-driven (452 trips) | **Yes, but RSS-ranked and memory-triggered.** Top 30 by RSS on the trip, then 12 follow-ups of the top 10. | **The only per-process CPU history.** |
| `browser-spin-guard.log` | ~5 min | Only automation browsers at ≥80% for ≥900 s | 100 SPIN events since 2026-08-17; otherwise "clean". |
| `coreaudiod-watch.jsonl` | — | coreaudiod only | — |
| `tool-batch-census.jsonl` / `bash-execution.log` | per batch / per call | **No CPU or duration** | Counts, tools, exit codes. |
| `render-census.sh` (writes `render-census.jsonl`) | not scheduled | would carry `%cpu` | No such log exists in `~/.claude/logs`. |

**Is there any CPU-by-category history?** Only what can be reconstructed from the sentinel snaps (§1), which is biased. Nothing samples per-process CPU unconditionally.

**ps `%cpu` semantics, corrected (MEASURED).** I ran a 6 s busy-loop and then let it sleep. It read `6.5` at 5 s and **`0.0` from 3 s after the loop ended**, while cumulative CPU time stayed at 0.65 s. On this Darwin build `ps %cpu` is a fast-decaying near-instantaneous figure, *not* a lifetime average. This contradicts the comments in `scripts/browser-spin-guard.sh:27-30,78` and `scripts/render-census.sh:46`.

The same test also measured contention directly: the CPU-bound loop received **0.65 s of CPU in 6 s of wall time**, i.e. ~11% of a core, at load ~110.

## 4. (c) QoS census: does batch work run outside the background band when busy? (MEASURED)

`qos-census.jsonl`: 8,157 rows from 2026-07-29 to 2026-10-04, median gap 605 s. Banded by each row's own `loadavg1`.

| Band | Rows | SIGNAL-DEAD (control failed) | Bats runs full / demoted | Procs pri 4 (background) / pri 20 (utility) / full |
|---|---|---|---|---|
| quiet <20 | 4,932 | 21 (0.4%) | 237 / 7,504 (3.1% undemoted) | 22,348 / 28,207 / 1,661 |
| mid 20-60 | 1,928 | 252 (13%) | 209 / 3,506 (5.6%) | 6,483 / 17,147 / 1,400 |
| **busy ≥60** | 292 | **149 (51%)** | 25 / 478 (5.0%) | 702 / 2,661 / 160 |

- **Bats runs:** about 95% are demoted at every load, but only **~20% of bats processes in the busy band sit in the background band (PRI 4).** ~76% are at utility (PRI 20). That is by design: `qos-census.sh:26` says the actuators deliberately moved to utility, which is P-core-eligible. Strictly, then, most batch work runs outside the background band, and that is intentional.
- **When busy, the census is blind half the time.** 51% of its busy-band rows are SIGNAL-DEAD.
- **It also drops rows under load.**
  - qos-census: 0 rows in hour 2026-10-04T01Z (load 359) and 1 row in T05Z, against the normal 6/h.
  - capacity-alarm: falls from ~55/h to 9/h.
  - load-sampler: falls from ~354/h to 186-197/h.
  - Busy periods are therefore under-sampled by every instrument, exactly the risk `load-sampler.sh:17-21` warns about.
- **Non-bats batch work (live, MEASURED).** I ran `ps -Axo pri,pcpu,args` across all categories:
  - **692 of 722 visible %CPU is at normal floating priority.** Only 8% is at PRI 4 and 22% at PRI 20.
  - Media at normal priority: 24 of 26%, including crop.py.
  - Search: 31 of 31%.
  - Agent-browser Chrome: 207 of 207%.
  - Test/lint was almost entirely demoted, but used only 2% at that moment.
  - So the heavy session work that is running right now (browser automation, image processing, search) is **not** in any reduced band. The QoS actuator covers only bats.

## 5. (d) Tool-call rate vs load over time (MEASURED except where marked)

Per-minute join of the census with `load.jsonl` (minute means), 3,173 minutes (`stats.py`, `d.py`):

- Pearson r: calls/min vs load1 = **0.33**, vs runnable = 0.41. Active sids vs load1 = 0.35. With trailing 5/15/60-minute sums, 0.35-0.36. Hourly: 0.39.
- Spearman: calls vs load1 = 0.57. The rank correlation mostly separates "machine idle" from "machine working".

| Load band | Minutes | % of minutes with zero calls | Calls/min | Active sids/min | Mean runnable | Mean load1 |
|---|---|---|---|---|---|---|
| quiet <20 | 1,877 | 76.8% | 2.6 | 0.34 | 8.7 | 10.4 |
| mid 20-60 | 731 | 17.1% | 19.4 | 2.26 | 23.7 | 33.1 |
| busy ≥60 | 565 | 18.2% | 26.9 | 2.53 | 93.3 | 165.0 |

- **Mid and busy bands have nearly the same call rate and active-session count, but 5× the load and 4× the runnable count.** Load per call/min is 1.7 in the mid band and 6.1 in the busy band.
- The clearest counter-example is 2026-10-04T01Z: load 359, runnable 167, **70 tool calls from 6 sids**, ffmpeg and next-server top by RSS, and the qos-census missing entirely.

**Where the processes come from (MEASURED; sample biased toward longer-lived processes).**
- Method: 20 `ps` snapshots over 15 s caught 795 new PIDs (`churn.py`).
- Attribution by ancestry:

| Origin | Share | Main processes |
|---|---|---|
| Claude Bash-tool descendants | 42% | bhget.sh, magick, curl, sleep/ps polling loops, grep |
| Children of the claude process that are not Bash-tool commands | 25% | hooks such as post-tool-batch.sh, jq, git, curl |
| launchd infrastructure daemons | 24% | deploy-live.sh, lead-supervisor.sh, land-turn.sh, postland-verify.sh, compressor-sentinel.sh, e_sampler.sh, lead-crash-watchdog.sh, boot-resume.sh, load-sampler.sh, capacity-alarm.sh, test-hermeticity-lint.sh |
| Chrome | 9% | — |

- In other words, **monitoring and automation daemons are about a quarter of the churn.**

**Spawn cost (MEASURED, child user+sys from bash `times`, under current load):**

| Process | CPU per spawn |
|---|---|
| `/usr/bin/true` | ~2 ms |
| `jq -n 1` | ~4 ms |
| `python3 -c pass` | ~29 ms |

At ~600 spawns/s and an average of ~9 ms, that is ~5.4 cores, the size of the dark row (INFERRED; consistent, not proven).

**Hook load per Bash call (INFERRED from config).** Each Bash call fires about 18 hook processes:
- PreToolUse: 10 [Bash] + 1 [*]
- PostToolUse: 3 [Bash] + 3 ["" = all]
- PostToolBatch: 1

`docs/plans/HOOK_CHAIN_COST.md:112` measured ~404 ms of wall time per Bash call at load 16 for an 11-hook chain, rising to ~800 ms at load 58. Even at 1 call/s that is under one core. Hooks are a real cost but not the dominant one.

## 6. Gaps: what cannot be attributed with existing samplers

1. **Short-lived processes, ~54% of busy CPU.**
   - No sampler sees processes that exit between samples.
   - Darwin needs root for `dtrace`, `eslogger`, `taskinfo` and `accton`, so per-category CPU for hooks, jq, git, grep and the short media steps cannot be recovered after the fact.
   - Ancestry sampling (§5) gives shares of process-lifetime, not CPU.
2. **No continuous per-process CPU sampler.** load-sampler and capacity-alarm record RSS only. The sentinel log is memory-triggered and RSS-ranked, and sees roughly a third of CPU.
3. **No per-session CPU.**
   - Tool calls carry sid but no duration or CPU.
   - Process trees carry no sid. The only link is the shell-snapshot path, which identifies the account, not the session.
   - "CPU per tool call" or "per agent" cannot be stated.
4. **Subagent identity is folded into the lead's sid.** The census lacks `agent_id`, so per-agent rates for the ~100-agent claim are not observable.
5. **Busy periods are under-sampled** by qos-census (0-1 rows/h), capacity-alarm (9/h) and load-sampler (~55% of rows).
6. **No quiet-period live sample**, and only n=32 quiet trips in history.
7. **qos-census covers bats only** and measures runner-frame CPU rather than the work under test. Its control fails in 51% of busy rows.
8. **System-category causality.** XprotectService/syspolicyd (exec scanning) and fseventsd (file events) are probably driven by session churn, but no sampler links them (INFERRED).
9. **Load is thread-based.** XNU loadavg counts runnable threads, while `runnable` counts R-state processes. The two are not interchangeable in correlations.

## 7. Adversarial self-pass: gaps found and checked

| Concern | Check | Result |
|---|---|---|
| Does the census undercount, e.g. missing accounts? | Settings symlinks; Bash cross-check against bash-execution.log | Complete for Bash; all four accounts register the hook. |
| Is "browser" the operator's own browsing? | Grouped by `--user-data-dir` | No. ~95% is agent-browser or headless automation profiles. |
| Is the dark CPU a `top` artifact? | Compared sys% (35-44%) with fork rate and measured spawn cost | Magnitudes agree. One top row (jq at 230,704,132%) was an overflow artifact and was dropped. |
| Does `ps %cpu` mean what the repo says? | Busy-loop test | No: it decays within seconds (§3). |
| Classifier error | Unit-checked the rewritten exe-keyed classifier on 12 argv forms | Fixed: the first version sent `grep … strings.txt` to media via `gs\b`. |

Not checked, and no tool call I could make would close these:
- Whether the hottest agent-browser profile is productive or stuck. browser-spin-guard's threshold is ≥80%, so this instrument cannot tell.
- Per-day stability of the busy-band shares beyond the 95 sentinel trips.
