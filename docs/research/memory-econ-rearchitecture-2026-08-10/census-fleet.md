# Axis A — Resident footprint census (measured 2026-08-10 00:28–00:55 PDT)

Host: MacBookPro18,2 · M1 Max 10-core · 68,719,476,736 B (64 GiB) · macOS 15.6.1 (24G90) ·
uptime 20h10m (booted 2026-08-09 04:18, i.e. **by the second kernel panic**).
Snapshot tool set: `ps -axo`, `top -l 1 -stats pid,mem,cmprs`, `/usr/bin/footprint -p`, `vmmap`,
`vm_stat`, plus two historical instruments nobody had read: `/Library/Logs/DiagnosticReports/*.panic`
(per-process JSON) and `~/.claude/logs/compressor-sentinel*` + `capacity-alarm.jsonl`.

> **⚠ The single most important line in this report.** The ~15-session ceiling is **not** built out
> of CC sessions. At both measured panics the Claude Code fleet was 3.5–7 GB total and *flat*; the
> machine died from two other things — a **736-process `node` storm (44.7 GB)** and an **unbounded
> `ugrep` that reaches 8–17.6 GB in a single process**. Re-architecting per-session CC memory buys
> ~2–4 GB. Bounding those two buys 20–45 GB.

---

## 0. Method note — RSS is the wrong meter, and it is the meter everything currently uses

| | |
|---|---|
| **Finding** | RSS overstates a Claude Code session by **1.6×–2.8×**, and understates `kitty` by **10×**. Every existing sensor in this repo (`compressor-sentinel` snap block, the pre-spawn census, `capacity-alarm`'s coarse rollup) ranks by RSS. |
| **Evidence** | `footprint -p` vs `ps rss` on the same pids, same minute: claude 71372 RSS 590 MB / **foot 219 MB**; claude 56864 RSS 734 MB / **foot 455 MB**; claude.exe 8042 RSS 632 MB / **foot 215 MB**; kitty 600 RSS 195 MB / **foot 1876 MB**. `vmmap 56864` shows `__BUN 182.5M 154.3M … SM=COW /…/claude.exe` + `__TEXT 60.3M 32.2M SM=COW` — ~188 MB per process is **clean, file-backed, copy-on-write from one file**, so the fleet's 34 claude/claude.exe processes hold it **once**, not 34 times. `footprint` TOTAL rows: 56864 `dirty=449MB clean=190MB`, 98361 `dirty=468MB clean=188MB`, 71372 `dirty=221MB clean=188MB`. |
| **Cost now** | Summed RSS across 1,072 procs = **41.4 GB** against a `PhysMem` line of 49 G used — RSS is not a budget. Summed `phys_footprint` across 1,104 procs = **29.3 GB**, which reconciles with `vm_stat` anonymous pages (1,742,970 × 16 KiB = **27.3 GB**). |
| **Re-architecture** | Every capacity estimator, alarm threshold and "per-session GB" constant in the fleet re-keyed to `phys_footprint` (`top -l 1 -stats pid,mem` returns it cheaply and matches `footprint` to ±1 %: kitty 1946 M vs 1876 M, 7993 1929 M vs 1929 M). Keep RSS only as a *secondary* rank. |
| **Sizing** | Corrects every published per-session figure downward ~2× · effort **S** (one metric swap in 2 scripts) · risk low. |
| **Existing mechanism** | `capacity-alarm.sh:641` already has a "per-proc physical-footprint outlier (M9b rung 4)" — **EXTEND that to the primary metric**, do not add a new instrument. |

`top`'s `MEM` column is `phys_footprint`; verified against `footprint` on 5 pids. Use it.

---

## 1. Where the 64 GB is — right now, and at the wall

### 1a. Now (00:35, mid-research-wave)

`vm_stat` (page = 16,384 B) reconciles the whole machine:

| Bucket | GB | Source |
|---|---|---|
| Anonymous (process-private) | 27.3 | `vm_stat` Anonymous pages 1,742,970 |
| File-backed (page cache + mapped binaries) | 14.1 | `vm_stat` File-backed 900,295 |
| Wired (kernel) | 5.6 | `vm_stat` wired 356,559 |
| Compressor pool | 3.6 | `vm_stat` occupied-by-compressor 231,103 (holding 553,518 compressed pages = 8.4 GB of data ⇒ **2.4:1**) |
| Free | 13.2 | `vm_stat` free 842,776 |

Class decomposition of the 29.3 GB of `phys_footprint` (own classifier over `top -l1 -o mem` × `ps args`):

| Class | GB | n | % |
|---|---|---|---|
| macOS system | 6.76 | 646 | 23.1 |
| **CC main sessions (`claude`)** | **5.61** | 16 | 19.2 |
| **CC subagents (`claude.exe --agent-id`)** | **4.09** | 18 | 14.0 |
| **chrome-devtools-mcp stack** | **3.02** | 13 | 10.3 |
| Dia (operator's browser) | 2.95 | 18 | 10.1 |
| Next.js dev servers + esbuild | 2.48 | 10 | 8.5 |
| kitty | 1.93 | 3 | 6.6 |
| other operator apps | 0.87 | 22 | 3.0 |
| shells + small helpers (279 procs!) | 0.84 | 279 | 2.9 |

**All of Claude Code — 16 sessions + 18 subagents — is 9.7 GB of 29.3 GB (33 %).**
By 00:55, still mid-census: `PhysMem: 62G used, 241M unused` — the machine reached **99.6 %** while
this report was being written, with load avg 104 at peak.

### 1b. At the wall — the panic reports are a full memory census and nobody had read them

`/Library/Logs/DiagnosticReports/panic-full-*.panic` are two-object JSON: object 2 carries
`memoryStatus.memoryPages` **and** `processByPid/<pid>/{procname,residentMemoryBytes,pageFaults,pageIns}`.
All three panics on disk are the same string: `watchdog timeout: no checkins from watchdogd in 91–94 seconds`.

| | 2026-08-05 00:19 PDT | 2026-08-09 03:41 PDT |
|---|---|---|
| free | **0.01 GB** | **0.01 GB** |
| wired | **14.07 GB** | **15.19 GB** (vs 5.6 GB idle — **+170 %**) |
| active / inactive | 9.60 / 9.60 | 9.38 / 9.38 |
| compressorSize | **28.83 GB** | **28.16 GB** (vs 3.6 GB now — **8×**) |
| pagesWanted / pagesReclaimed | 3094 / **77** | 3094 / **85** |
| `memoryPressure` | **False** | **False** |
| processes in snapshot | 1318 | 1454 (now: 1181) |
| `procname=node` | **724 procs, 145.3 GB Σ-RSS** | **780 procs, 144.0 GB Σ-RSS** |
| `procname=claude.exe` | 6 procs, 2.0 GB | 13 procs, 5.4 GB |
| `xpcproxy` in flight | **152** | (n/a) |

`node` RSS distribution at the 08-09 panic: n=780, median **178 MB**, 476 in the 100–200 MB band,
261 in 200–500 MB, only 5 above 500 MB. That is not a few fat dev servers — it is a **uniform swarm
of small node processes**. Sampled big node pid 36923: `pageFaults 2,166,134`, `pageIns 24,439`,
`copyOnWriteFaults 1,209,248`, thread names `next-server (v16.2.6)` + `tokio-runtime-worker`.

**Causal chain (measured, not inferred):** anonymous demand exceeds 64 GB → compressor absorbs to
28.8 GB → wired triples (compressor metadata + page tables for 1,454 tasks) → free → 0 → the pageout
scanner reclaims **85 of 3,094** wanted pages (2.7 %) → every thread stalls in the pager →
`watchdogd` misses 91 s of check-ins → kernel panic.
**Jetsam never fired** (`memoryPressure: False`; `log show --last 24h` for jetsam/memorystatus = **0
lines**). The machine has no OOM-killer relief valve on this path — it dies whole.

---

## 2. The two storms — both measured, neither is Claude Code

`~/.claude/logs/compressor-sentinel-snap.log` (8.5 MB, 33,825 lines) already records a
top-30-by-RSS-with-argv block on every trip. It had captured both storms and no one had read it.

### Storm A — the `node` swarm (killed the machine 2026-08-09)

| | |
|---|---|
| **Finding** | 736–780 `node` processes, ~44.7 GB of RSS, arriving in **under 5 minutes**. |
| **Evidence** | Sentinel trip `2026-08-09T11:14:03Z` (5 min before panic-2): `segments 1295076 of 1629615 (79.47%) · 8494.3 seg/s · swap +580,618,202 B/s`, class rollup **`44691.7 MB x736 node`** vs `3458.3 MB x14 claude`. `capacity-alarm.jsonl` at `11:04:46` → `compressor_gb 0.0, swap_used_mb 0.0, headroom_gb 39.86, sessions 25`; at **`11:09:46`** → `compressor_gb 32.33, swap_used_mb 30267.94, headroom_gb 10.81`. **40 GB of headroom to 10 GB, and 0 → 30 GB of swap, in 300 seconds.** Panic 11:18:59Z. |
| **Cost now** | 44.7 GB at the event; **69 % of RAM**, and the proximate cause of at least the 08-09 panics. |
| **Re-architecture** | A **process-class admission gate**: a supervisor that refuses/queues new node spawns above a per-class cardinality (e.g. `node > 120`) rather than a global memory threshold — cardinality is observable 60 s earlier than the memory it will consume. Sentinel already samples at ~9 s. |
| **Sizing** | Prevents the 44.7 GB excursion outright · effort **M** · risk medium (must fail-open, never block a lead's own tool call). |
| **Existing mechanism** | `compressor-sentinel.sh` (717 lines, `SNAP_TOPN=30`) + `capacity-alarm.sh` (1282 lines) — **both already sample it; neither acts on class cardinality.** |
| **GAP (named, not guessed)** | The snap block's argv section is `head -80` filtered and rank-bounded, so **I cannot attribute the 736 node processes to a parent.** The panic JSON has no ppid. Discriminating instrument: add `ps -axo comm= \| sort \| uniq -c` (2 forks) + a `ppid` histogram for the top class to every sentinel trip — it is ~200 bytes and would have named this in one line. |

### Storm B — `ugrep`, i.e. Claude Code's own `grep`, unbounded (live right now)

| | |
|---|---|
| **Finding** | `grep` in every Bash tool call is a **shell function that re-execs the Claude Code binary** as `ugrep`; a single such process reached **17.65 GB**, and one was **live at 8.2 → 11.1 GB and growing ~40 MB/s** during this census. |
| **Evidence** | `type grep` → a zsh function ending `exec -a ugrep "$_cc_bin" -G --ignore-files --hidden -I --exclude-dir=.git … "$@"` with `_cc_bin=${CLAUDE_CODE_EXECPATH:-/Users/chrisren/.local/bin/claude}`. Live: pid **68030** `ugrep … -o .{0,260}FOR…`, RSS **8,174 MB** at 02:45 → **11,147 MB** at 03:35. Parent chain (walked): `68030 → 68026 /bin/zsh -c … → 68002 → **99699 claude** → 99286 cc-close-attrib → 80524 zsh -l → 600 kitty` — i.e. an **ordinary agent Bash tool call in a live session**. Sentinel history: **747 logged rows with ugrep RSS > 500 MB, max 17.65 GB**; trip `2026-08-10T07:09:07Z` class rollup `10370.9 MB x5 ugrep` — **larger than all 13 `claude` sessions combined (7127.5 MB)**. Recurrent on 2026-08-07 (19 distinct trips) and 2026-08-10. |
| **Cost now** | 10.4 GB at the last trip; 11.1 GB in one live process; historical max 17.65 GB — **27 % of RAM in a single grep.** |
| **Re-architecture** | Bound the wrapper, not the caller: add `--max-count`/`-m`, a `--max-files`, and hard `ulimit -v`/`RLIMIT_AS` around the `exec -a ugrep` in the function; reject `-o` with an unanchored `.{0,N}` prefix over a directory root. The function is ours to edit — it is injected into the shell snapshot, not vendor-locked. |
| **Sizing** | Recovers **8–17 GB of peak** · effort **S** (one function body) · risk low (a bounded grep returns truncated results, which is strictly better than a panic). |
| **Existing mechanism** | The shell-snapshot `grep()` function itself; `mem-leash.sh` already exists in reso (`95787 bash scripts/mem-leash.sh pnpm test:unit`) — **generalise that leash**, don't invent one. |

---

## 3. Marginal cost of one Claude Code session — the number the ceiling should be computed from

Full ppid-walk trees over one `ps` snapshot, then `footprint` on every member.

| Component | RSS | **phys_footprint** | Notes |
|---|---|---|---|
| `claude` main, first 10 min | 576–626 MB | **219–221 MB** | pids 71372, 6205 |
| `claude` main, steady state (>1 h) | 675–955 MB | **378–463 MB** | 12 pids |
| `claude.exe` subagent, first 10 min | 547–634 MB | **206–226 MB** (n=15, σ ≈ 5 MB) | strikingly tight |
| `claude.exe` subagent at ~50 min | 590–827 MB | **307–354 MB** | 3 pids |
| `caffeinate -i -t 300` (1 per session) | 3.5 MB | ~3 MB | |
| `lead-crash-watchdog.sh` (1 per session **and per subagent**) | 1.7–2.4 MB | 1.9 MB | ppid 1 |
| `cc-await-ping` + its `sleep` (when waiting) | 5 MB | ~5 MB | |
| zsh/bash tool-call wrappers | 1–4 MB each | | |
| **chrome-devtools-mcp stack, if configured** | 137 MB | **325 MB** | see §4 |

**Marginal cost of session N+1**
- **without MCP: ≈ 230 MB on arrival, ≈ 400–460 MB at steady state.**
- **with chrome-devtools-mcp: ≈ 555 MB on arrival, ≈ 730–790 MB at steady state.**

Tree totals vary 723 MB → 6,962 MB, and **the variance is entirely the work the session spawns**,
not CC: tree(56864) = 723 MB (2 procs), tree(58413) = 900 MB (8), tree(88196) = 3,188 MB (21, holds a
`next-server` at 1,001 MB), tree(99699) = **6,962 MB (30 procs**, holds `next-server` 1,365 MB + three
`.next/dev/build` workers at 455/363/352 MB + three esbuild at 222/308/160 MB + a `vitest` at 387 MB).

> **Methodological warning for every other axis:** a naive `ps` ppid-walk **understates** a session,
> because session-spawned helpers detach to ppid 1. 28 `lead-crash-watchdog.sh` daemons and the
> `caffeinate` floor are invisible to a tree walk and must be attributed by registry, not by parent.

**At 400–460 MB steady-state each, 64 GB / 0.46 GB ≈ 139 sessions.** The ceiling is ~15. CC's own
per-session footprint is **not** the binding constraint — it is ~9 % of the way there.

---

## 4. `chrome-devtools-mcp` — 3.0 GB for a browser that does not exist

| | |
|---|---|
| **Finding** | Each instance is a **4-process chain** whose useful member is 97 MB; **four of the five have never launched a browser**, and the fifth has leaked to 1.93 GB (peak **3.21 GB**). |
| **Evidence** | Chain: `npm exec chrome-devtools-mcp@latest --isolated` (RSS 44.9 MB / **foot 118 MB**, peak 155 MB) → `chrome-devtools-mcp` (RSS 46.8 MB / **foot 97 MB**) → `node …/chrome-devtools-mcp/build/src/telemetry/watchdog/main.js --parent-pid=<mcp>` (RSS 47–64 MB / **foot 110 MB**). Instances: 95531, 53833, 69893, 84462 all at RSS 46.8 MB (never used); **7993 at RSS 1593 MB / foot 1929 MB / peak 3213 MB**, uptime 1h36m. Grep for any `Google Chrome`/`Chromium`/`Chrome for Testing`/`chromedriver` **anchored on argv[0]: zero matches** — the `--isolated` browser was never spawned. Config: `~/.claude.json` `projects["…/reso-management-app"].mcpServers = ["chrome-devtools"]`; global `mcpServers = [browsermcp, motion, motion-plus]`. **Two of the five belong to `claude.exe` subagents (73566, 40804) — subagents inherit the project MCP config and start their own servers.** |
| **Cost now** | **3.02 GB** across 13 procs; of that ≈ 1.6 GB is idle scaffolding (5 × 325 MB) and 1.9 GB is one leaked instance. Peak exposure 3.21 GB in that one pid. |
| **Re-architecture** | (a) drop the `npm exec …@latest` wrapper — pin a version and invoke the binary directly (kills 118 MB × N **and** a registry round-trip per session start); (b) `--no-telemetry` or equivalent to kill the watchdog child (110 MB × N); (c) **do not inherit MCP servers into `--agent-id` subagents** — a research subagent has no use for a browser; (d) an idle-TTL that exits an MCP server with zero tool calls after ~15 min; (e) restart-on-footprint for the leak. |
| **Sizing** | Recovers **~1.6 GB standing + up to 3.2 GB of peak** · effort **S–M** · risk low (MCP restarts on demand). |
| **Existing mechanism** | none for MCP lifecycle — this is a genuine gap. `MCP_TIMEOUT`/`MCP_TOOL_TIMEOUT` in `~/.claude/settings.json` bound *calls*, not *residency*. |

---

## 5. RSS growth over a session's lifetime — saturating, not leaking

Fitted `phys_footprint` against process age (n=16 MAIN, n=18 SUBAGENT, one snapshot):

| Model | MAIN r² | SUBAGENT r² |
|---|---|---|
| linear (MB/hour) | **0.227** (+8.3 MB/h) | 0.989 (+146.6 MB/h — leverage artefact, 15 of 18 points sit in a 525–718 s band) |
| **log(age)** | **0.695** — `foot ≈ −177 + 63.3·ln(age_s)` | **0.967** — `foot ≈ −206 + 65.4·ln(age_s)` |

Predicted vs observed MAIN: 10 min → 228 MB (obs 218–221) · 1 h → 342 MB (obs 343–410) · 4 h → 430 MB
(obs 447–463) · 20 h → 532 MB predicted, **observed 449 MB** (pid 56864, `etime 20:12:02`).

| | |
|---|---|
| **Finding** | A CC session's memory is a **saturating curve that plateaus at ~450 MB within ~1.5 h and does not move for the next 18.5 h.** There is no lifetime leak. On RSS alone the correlation is r² = 0.017 — i.e. RSS says "no growth at all", which is also wrong; only footprint shows the real shape. |
| **Evidence** | table above; pid 56864 at 72,885 s = 449 MB vs pid 58413 at 6,710 s = 452 MB. |
| **Cost now** | Implication: **age-based session recycling buys nothing in RAM.** Recycling a 20 h session frees ~230 MB (450 → 220 for its replacement) and costs a re-read of context. |
| **Re-architecture** | Retire "old sessions leak, recycle them" as a memory argument (it remains valid as a *context-rot* argument — a different axis). Spend the lever budget on §2 and §4 instead. |
| **Sizing** | Negative finding — prevents ~2 GB of misdirected effort · effort **0**. |
| **Existing mechanism** | `waiting-recycle.sh` / `boundary-handoff.sh` — keep them, but on the context rationale, not the memory one. |
| **Confound, stated** | Transcript size could not be separated from age: 33 of 34 processes share one cwd and therefore one transcript file (4.8 MB). The single distinct case (pid 4501, lakehouse-lecture, **34.5 MB** transcript) sits **+40 MB above** the log curve at its age — consistent with ~1.1 MB footprint per transcript-MB, but **n = 1, inferred, not established**. `lsof` shows CC does not hold the `.jsonl` open, so per-session transcript attribution needs the session-id, not fds. |

---

## 6. Process attribution — the 118 bash, the git daemons, the detached helpers

Anchored on **argv[0] basename** throughout (`awk '{a=$6; n=split(a,p,"/"); b=p[n]}'`), never `pgrep -f`
— sibling agents' briefs quote these names and a substring match would count them.

| Family | count | RSS | attribution (measured) |
|---|---|---|---|
| `bash` | **118** (155 by `comm`) | 318 MB | by parent argv[0]: **48 bash** (nested subshells) · **26 launchd (ppid 1)** · 25 zsh · 11 login · 4 claude.exe · 2 timeout · 1 npm · 1 git |
| `zsh` | 42 (53 by comm) | 140 MB | tool-call wrappers (`/bin/zsh -c source …shell-snapshots/snapshot-zsh-*.sh`) — **one per Bash tool call** |
| `lead-crash-watchdog.sh` | **28 daemons** (registry: **36 entries, 0 dead**) | 2 MB ea | ppid 1. Registry composition: **18 MAIN + 18 subagent** ⇒ **every `claude.exe` subagent gets its own watchdog daemon.** Poll loop `lead-crash-watchdog.sh:898–942`: `cat` + `ps -o lstart=` + `tr` + `sed` + `sleep 30` ≈ **6–7 forks / 30 s / daemon ⇒ ~22,000 forks/hour fleet-wide** |
| `caffeinate` | **32** | 112 MB | 31 × `caffeinate -i -t 300`, one per session/subagent, **respawned every 5 min**; plus pid 818 `caffeinate -i -s` running the full 20 h. The 31 are **redundant** — one `-i` assertion already holds the whole machine awake |
| `sleep` | **50** | 55 MB | 29 × `sleep 30` (the watchdogs) · 9 × `sleep 15` (`cc-await-ping --interval 15`) · 12 other |
| `gitstatusd-darwin-arm64` | **12** | 57 MB | **10 of 12 are ppid 1**, oldest `etime 07:43:50` — powerlevel10k daemons outliving their zsh. Only 2 have a live parent |
| `git` background daemons | **0** | 0 | **No `fsmonitor--daemon` and no `credential-cache--daemon` exist anywhere on the box** — anchored census of argv[0] `git`/`git-*` returns only two transient foreground ops (`git push`, `git checkout`). With **252 worktrees**, fsmonitor is absent, not misconfigured (→ axis E) |
| `mds`/`mds_stores` | 2 | 598 MB | `mdutil -s /System/Volumes/Data` = **Indexing enabled**; no `.metadata_never_index` in `~/Development` or `~/Development/.worktrees` ⇒ **Spotlight is indexing all 252 worktrees and their `node_modules`**. Panic-window snapshots show **3 concurrent `mds_stores` at ~565 MB each** |
| `login` | 11 (21 by comm) | 58 MB | kitty panes |

| | |
|---|---|
| **Finding** | The detached-helper layer costs little RAM (**~0.84 GB across 279 procs**) but is a **fork engine**: ~22 k/h from watchdogs, ~370/h from caffeinate respawns, plus one zsh per Bash tool call. Load average during this census ranged **44 → 104 on 10 cores.** |
| **Re-architecture** | (a) **one** watchdog daemon polling a directory of registrations, not 28 daemons — the registry `~/.claude/watchdog/*.pid` already exists and already holds the truth; (b) do **not** arm a crash-watchdog for `--agent-id` subagents (their lead's watchdog covers them); (c) drop the per-session `caffeinate` entirely — pid 818's `caffeinate -i -s` already asserts; (d) reap ppid-1 `gitstatusd` whose registering shell is gone; (e) `.metadata_never_index` in `~/Development/.worktrees`. |
| **Sizing** | ~0.7 GB RAM + ~22 k fewer forks/hour + a Spotlight indexer removed from 252 trees · effort **S–M** · risk low. |
| **Existing mechanism** | `~/.claude/watchdog/` registry (588 files, 8.5 MB) · `caffeinate-floor` (pid 818) · `qos-census.sh` — all present, none consolidated. |

---

## 7. Browser attribution — infra-owned vs the operator's own

Space-safe parse of `--user-data-dir=(.*?)(?= --|$)` (a naive `awk` split breaks on
`Application Support`).

| Owner | GB (footprint) | procs | verdict |
|---|---|---|---|
| **Dia** (`/Applications/Dia.app/`, `--user-data-dir=…/Dia/User Data`) | **2.95** | 18 | **operator's own browsing** — main 521 MB (peak 682), renderers to 1,369 MB (peak 1,519) and 1,197 MB. Out of scope per the negative-space list |
| **chrome-devtools-mcp** | **3.02** | 13 | **100 % infra-owned, 0 % browser** — §4 |
| `agent-server` (Dia helper, pid 68758) | 0.08 | 1 | Dia's own agent surface, not ours |
| Google Chrome / Chromium / agent-browser / auth-profiles | **0.00** | **0** | none running at snapshot |

At the 2026-08-09 panic window Google Chrome **was** present (`2248.1 MB x4 Google Chrome Helper
(Renderer)`, `167.0 MB x4 chrome-headless-shell`) — so browser residency is bimodal and the honest
statement is: **infra-owned browser cost is 3.0 GB of MCP scaffolding plus, when a headless run is in
flight, ~2.4 GB of Chrome.**

---

## 8. `kitty` — 1.93 GB, and it is not scrollback

| | |
|---|---|
| **Finding** | kitty's `phys_footprint` is **1876–1946 MB (RSS says 195 MB)**, and **1,511 MB of it is GPU window surfaces**, not text. The obvious remedy (trim scrollback) addresses ~7 % of it. |
| **Evidence** | `footprint -p 600`: `IOSurface 1350 MB / 29 regions`, `IOAccelerator (graphics) 161 MB / 198 regions`, `MALLOC_* total 112 MB`. `vmmap -summary 600`: `IOSurface VIRTUAL 1.3G RESIDENT 1.3G DIRTY 1.0G SWAPPED 281.2M NONVOL 1.3G`. At the 2026-08-09 panic kitty was **1,825 MB**; at 2026-08-05, **1,424 MB**. |
| **Cost now** | 1.93 GB standing, third-largest single process on the machine after the leaked MCP and WindowServer (1,525 MB — itself surface-backed). |
| **Re-architecture** | Fewer **OS windows/tabs** (each drawable costs ~46 MB of front+back buffer at this Retina geometry: 29 regions ≈ 1.3 GB), not smaller scrollback. Consolidating panes into fewer OS windows, and closing tabs whose sessions have ended, is the lever. WindowServer's 1.5 GB moves with the same variable. |
| **Sizing** | ~0.5–1.0 GB across kitty + WindowServer · effort **S** (a windowing habit / a pane-reaper) · risk low. |
| **Existing mechanism** | none — → axis H. **Correct axis H's likely default hypothesis before it spends effort on scrollback.** |

---

## 9. Peak vs current — how much burst the fleet is carrying

`phys_footprint_peak` over the top-30 by current footprint: **current 19.8 GB, peak-sum 22.3 GB
(+2.4 GB if all peaked at once).** Peak/current ratios:

| Class | ratio | reading |
|---|---|---|
| `claude` main sessions | **1.06–1.24** | CC sessions are **not bursty** — a session's peak is barely above its steady state |
| `next-server` / `.next/dev/build` workers | 1.01–1.52 | moderately bursty |
| Dia renderers | up to **2.69** | bursty |
| `chrome-devtools-mcp` (leaked pid) | **1.67** (1929 → 3213 MB) | the single largest burst on the box |
| `ugrep` | unbounded — 17.65 GB observed | not a burst, a runaway |

This kills a plausible-sounding lever: "sessions spike, so stagger them." They do not. The burst
budget belongs to §2 and §4.

---

## 10. Adversarial self-pass

Three things a hostile reviewer would say, each chased with real calls:

1. **"Your census is of a machine running your own 15-subagent wave — it is not representative."**
   Correct, and quantified: **16 wave subagents = 9.07 GB RSS / 3.70 GB footprint** live during the
   measurement, and `PhysMem` went 49 G → 54 G → **62 G used / 241 M unused** across 27 minutes while
   load avg ran 44 → 104. Mitigation: every *at-the-wall* number in §1b and §2 comes from the panic
   JSON and the 5-day sentinel/alarm jsonl, which are unperturbed by this session. **A 15-way research
   wave is itself a ~4 GB, 100-load-average event — the memory investigation is a member of the
   population it studies.**
2. **"You asserted swap is disabled."** I did infer that mid-census from `vm.swapusage total = 0.00M`
   and an empty `/System/Volumes/VM/`. **It is false and I retract it.** `capacity-alarm.jsonl` shows
   `swap_used_mb: 30267.94` at 2026-08-09 11:09:46Z and `1142.56` / `407.31` at other times; the
   sentinel shows `swap +580,618,202 B/s` at 11:14:03Z. What I measured was a **post-reboot** state, and
   post-reboot state is not configuration. (`vm.compressor_mode: 4`, `compressor_is_active: 1`.)
3. **"What dimension did you assume away?"** — the `grep` wrapper. I would never have looked at it; it
   surfaced only because the sentinel's snap block records full argv. It turned out to be the largest
   single class on the machine at the most recent trip (§2 Storm B). Generalisation: **the fleet's own
   tool shims are unbudgeted and unmeasured.** A second instance of the same class is `node
   …/cli.js mcp list` at **140.8 MB RSS for a 2-second lifetime** — an ephemeral full-node fork whose
   caller I could not locate by grep of `hooks/ scripts/ bin/ statusline*` (zero hits), i.e. it is
   emitted from inside the CC binary or from a path I did not search. Named as an open thread.

Two further checks that changed conclusions: `capacity-alarm`'s **`est_room_sessions` read 46–47
("room for 46 more sessions") eight minutes before the machine died**, and 17 five minutes before —
a linear headroom/per-session estimator cannot see a 40 GB → 10 GB burst, so **that field is actively
misleading and should be replaced by a burst-rate forecast** (`dseg`, `srate` and `swap +B/s` are
already logged and *did* move, from 6,318 → 8,494 seg/s). And the panic-window sentinel trips prove
the instrumentation is **not** missing — it is **unread and un-actuated**, which is a different (and
cheaper) problem than building a new sensor.

---

## 11. Ranked levers (measured recovery, per this axis)

| # | Lever | Recovers | Effort | Risk | Existing mechanism to EXTEND |
|---|---|---|---|---|---|
| 1 | **Bound `ugrep`** (RLIMIT_AS + `-m` + reject unanchored `-o .{0,N}` at a dir root) in the shell-snapshot `grep()` function | **8–17.6 GB of peak**, live today | S | low | the `grep()` function itself; reso's `mem-leash.sh` |
| 2 | **Class-cardinality admission gate on `node`** (queue/refuse above ~120), driven off the sentinel's existing 9 s sample | **up to 44.7 GB** of excursion; both 08-09 panics | M | med | `compressor-sentinel.sh` + `capacity-alarm.sh` |
| 3 | **chrome-devtools-mcp**: pin the version (drop `npm exec …@latest`), disable the telemetry watchdog, **stop inheriting MCP into `--agent-id` subagents**, idle-TTL + restart-on-footprint | **1.6 GB standing + 3.2 GB peak** | S–M | low | none — real gap |
| 4 | **Re-key every capacity estimator to `phys_footprint`** and delete `est_room_sessions` in favour of a burst-rate forecast | correctness, not GB — but it is why the operator got a "room for 46 sessions" reading 8 min before a panic | S | low | `capacity-alarm.sh:641` |
| 5 | **One watchdog daemon, not 28**; none for subagents | 0.06 GB + **~22,000 forks/hour** | M | low | `~/.claude/watchdog/` registry |
| 6 | **Kill the 31 redundant `caffeinate -i -t 300`** (pid 818 already asserts) | 0.11 GB + ~370 forks/h | S | low | `caffeinate-floor` |
| 7 | **kitty/WindowServer: fewer OS windows** (IOSurface, not scrollback); reap panes of dead sessions | 0.5–1.0 GB | S | low | none (→ axis H) |
| 8 | **`.metadata_never_index` in `~/Development/.worktrees`**; reap ppid-1 `gitstatusd` | ~0.5 GB + a 252-tree indexer | S | low | none (→ axes D/E) |
| 9 | **Do not** spend effort on age-based session recycling for memory | prevents ~2 GB of misdirected work | 0 | — | §5 is a negative result |

**Total addressable by this axis: ~3–4 GB standing + 20–45 GB of excursion.** The excursion is the
ceiling; the standing cost is not.

---

## 12. Open threads this axis could not close (for the lead's routing)

1. **Identity of the 736 `node` processes.** The panic JSON carries no ppid and the sentinel's argv
   block is `head -80`-filtered. *Instrument:* add `ps -axo comm= | sort | uniq -c | sort -rn | head -5`
   plus a ppid histogram of the top class to every sentinel trip (~2 forks, ~200 B). Circumstantial
   evidence points at node CLI shims — measured today, `pnpm dev` = 151.6 MB, `cli.js mcp list` =
   140.8 MB, `npm exec` wrapper = 118 MB footprint, and the panic band was **476 procs at 100–200 MB** —
   but this is **inferred, not established.**
2. **Caller of the ephemeral `node …/cli.js mcp list` (140.8 MB / 2 s).** Not in `hooks/`, `scripts/`,
   `bin/`, or `statusline*`.
3. **Transcript-size → footprint coefficient.** Confounded with age here (n=1 distinct transcript).
   Needs a per-session-id join, not an fd walk — CC does not hold the `.jsonl` open.
4. `~/.claude/watchdog/` holds **588 files / 8.5 MB** including hundreds of `.gc-stamp` entries → axis I.


---
---

# ADDENDUM — deltas against the settled figures (lead steer, same session, 01:05–01:20 PDT)

Settled baseline accepted, not re-derived: arrival **340 MB** (paired differential n=1,194,
`scaling-bottlenecks-2026-08-09.md:30`) · ACTIVE **~2.2 GB** vs resident **232 MB**
(`CONCURRENCY_PROGRAM.md:1877-1878`) · `ps` RSS charges **~992 MB** of shared libs per session,
`vmmap`/`footprint` is the instrument (`:1253-1258`) · session age ≤ 35 MB. My §0 and §5 corroborate
all four independently. Below is only what is **new or different today**.

## A1 · The `claude.exe` self-burst trigger — a named, live, reproducible candidate

`scaling-bottlenecks-2026-08-09.md:32` — *"claude.exe self-bursts (unbudgeted): 54 processes exceeded
**4 GB** in 11 days, max **41 GB**, ramp up to ~8 GB/min. **Trigger unknown — top open follow-on.**"*

| | |
|---|---|
| **Finding** | An `ugrep` — i.e. **the claude.exe binary re-exec'd under argv[0]=`ugrep` by the shell's `grep` function** — is indistinguishable from a session by every executable-keyed field, bursts to 8–17.6 GB, ramps at ~2.4 GB/min, and **vanishes within minutes**. It is a live, reproducible producer of exactly the recorded shape. |
| **Evidence — the masquerade** | `ps -o comm= -p 28377` → **`ugrep`**; `ps -o ucomm= -p 28377` → **`claude.exe`**; `lsof -a -p 28377 -d txt` → **`/Users/chrisren/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe`**. The shell function (`type grep`) ends `exec -a ugrep "${CLAUDE_CODE_EXECPATH:-/Users/chrisren/.local/bin/claude}" -G --ignore-files --hidden -I --exclude-dir=… "$@"`. A panic report's `procname` and any `ucomm`-keyed detector therefore **label it `claude.exe`**. |
| **Evidence — the burst** | Same pid observed at **8,174 → 11,147 → 9,216 MB over ~6 min, then gone** (pids 68030/68889 absent by the 3rd read). Sentinel history: **747 rows with ugrep RSS > 500 MB, max 17.65 GB**; trip `2026-08-10T07:09:07Z` class rollup `10370.9 MB x5 ugrep` vs `7127.5 MB x13 claude`. Parent chain walked: `68030 → zsh -c → zsh -c → **99699 claude** → cc-close-attrib → zsh -l → kitty 600` — an ordinary agent Bash tool call. |
| **Gap in the claim** | Their max is **41 GB**; my observed max is **17.65 GB**. So this mechanism is a **strong candidate for the class, not a proof it explains all 54 events.** |
| **Discriminating test (cheap, decisive)** | The burst detector must record **`argv[0]` alongside `ucomm`**. `argv[0]=="ugrep"` ⇒ the event is a *grep*, not a session; `argv[0]` matching the binary path ⇒ a genuine session burst. One extra `ps` column splits 54 events into two populations in one pass over the existing log. |
| **Existing mechanism** | `compressor-sentinel-snap.log` already stores full argv on every trip — **the answer is already on disk for 5 days; nothing reads argv[0] separately from comm.** |

## A2 · The memory actuator cannot touch the largest process on the box — proven by simulation

| | |
|---|---|
| **Finding** | `compressor-sentinel.sh`'s SIGSTOP cohort **structurally excludes the runaway**, twice over. The sentinel logs a 7–17 GB process at rank 1 of its own trip snapshot and then declines to act on it. |
| **Evidence (code)** | `select_stop_targets()` `scripts/compressor-sentinel.sh:334-337`: `if (base !~ /^node/) next` · `if (base=="claude.exe"\|\|base=="claude") next` · `if (args ~ /claude/ \|\| args ~ /mcp/) next`. `select_break_parents()` `:385`: `if (base=="claude.exe"\|\|base=="claude"\|\|args ~ /claude/\|\|args ~ /mcp/) protect[pid]=1`. `base` = basename of `$4` from `ps -axwwo pid=,ppid=,rss=,comm=,args=` (`:304`, `:802`) ⇒ for an ugrep, **`base == "ugrep"`**. |
| **Evidence (simulation, read-only, live table)** | Replayed the exact filter at `floor=200000`: the 9,216 MB `ugrep` is **EXCLUDED — `base!~^node`** *and* **`argv-names-claude/mcp`** (its own argument is `…/.claude-220/node_modules/@anthropic-ai/claude-code-darwin-arm64/claude`). Of the top 14 by RSS, **exactly one process is COHORT-ELIGIBLE** (a 2,062 MB `node`); 13 are excluded, 11 of them by `argv-names-claude/mcp`. |
| **Why the second guard is the nastier one** | `~/.claude` is in the *argument* of a large fraction of the greps agents run on this machine, so the rule written to spare the operator's sessions **also spares every grep that mentions them**. It is name-keyed, and the runaway is named after its victim. |
| **Secondary defect found in the same replay** | `comm` values containing spaces (`next-server (v16.2.12)`, `Browser Helper (Renderer)`, `Google Chrome Helper`) **shift the `args` reconstruction by ≥1 field** — the replay shows `comm=next-server` with `args` beginning `(v16`, and empty `comm` for the `claude` rows. Both the `base` test and the `args ~ /claude/` test can therefore read the wrong string. Fix: `ps -axwwo pid=,ppid=,rss=,ucomm=,args=` (no spaces in `ucomm`) or a NUL/tab-delimited read. |
| **Re-architecture** | Scope the guard to the **dangerous effect, not the location/name** (the standing lesson): protect a pid **iff it is a session leader we can prove** — `ucomm ∈ {claude, claude.exe}` **AND** `argv[0]` is the binary path (not `ugrep`) **AND** it has a live pane/registry entry. Drop `args ~ /claude/` entirely; drop `base !~ /^node/` in favour of an RSS+ramp test that is class-agnostic. |
| **Sizing** | Converts an existing, already-armed actuator from 0 % to ~100 % coverage of the largest observed excursion class · effort **S** (two awk predicates + one `ps` column) · risk **medium** — the guard exists for a reason; the mutation check must prove a real session is still protected. |

## A3 · MCP children — the settled per-session constant does not reproduce today (**8× lower**)

`scaling-bottlenecks-2026-08-09.md:31` — *"MCP children ~**507 MB/session** (22 `chrome-devtools-mcp`
procs / 5.1 GB at 10 sessions) ⇒ ~49 GB at 150 — **forecloses 150-resident on its own**."*

Measured now (argv[0]-anchored, each proc rooted to a session by ppid-walk):

| Quantity | Prior wave | **Today** |
|---|---|---|
| live sessions (`claude` + `claude.exe --agent-id`) | 10 | **15 + 18 = 33** |
| MCP-class processes | 22 | **12** |
| MCP-class RSS | 5.1 GB | **2.00 GB** |
| **per live session** | **~507 MB** | **62 MB** |
| sessions actually **hosting** a stack | (not split out) | **4 of 33 (12 %)** — MAIN 99699, 88196, 58413 + **SUBAGENT 73566** |
| per **hosting** session | — | **140 MB RSS / ~325 MB footprint** (npm-exec 44.9 + mcp 46.8 + telemetry-watchdog 48.2) |
| share of the class in **one leaked pid** | — | **1,519 of 2,000 MB = 76 %** (pid 7993) |

| | |
|---|---|
| **Finding** | The 507 MB/session constant is **not a per-session term at all**. It is a *fixed 140 MB per hosting session* (and only ~12 % of sessions host, because only `projects[".../reso-management-app"].mcpServers` declares `chrome-devtools`) **plus a heavy-tailed leak** that supplied 76 % of today's class total and 100 % of the gap between the two measurements. |
| **Consequence for the settled table** | Re-projected: at 150 sessions with today's 12 % coverage, MCP = 18 hosts × 325 MB ≈ **5.9 GB, not 49 GB**. **MCP children do not foreclose 150-resident.** The *leak* does — one instance reached `phys_footprint 1929 MB, peak 3213 MB`. |
| **Confirmed unchanged** | **Subagents inherit the project MCP config and start their own servers** — `claude.exe --agent-id dep-types-node` (73566) hosts a full 4-process stack. At a 15-way research wave in an MCP-configured project this multiplies the stack by the fan-out. |
| **Re-architecture** | Unchanged from §4, but **re-ranked**: the lever is *leak containment + no-MCP-for-subagents*, **not** blanket consolidation (there is little to consolidate — 29 of 33 sessions already carry zero MCP). |

## A4 · Browser attribution — infra-owned vs the operator's own (uncovered axis)

| Owner | RSS now | procs | verdict |
|---|---|---|---|
| **Operator's Dia** (`--user-data-dir=…/Dia/User Data`) | **5,821 MB** | 23 | operator browsing — **grew 2.76 → 6.73 GB in the 40 min of this census** |
| Dia, default profile | 909 MB | 2 | operator |
| Chrome, default profile | **12 MB** | 1 | a stub; not driving anything |
| **Dedicated auth-browser profiles** | **0 MB** | **0** | **none exist on disk** — `~/Library/Application Support/*auth-browser*` and `~/.claude/auth-browser*` return no matches |
| **dia-cdp** | **0 MB** | 0 | launcher present (`~/bin/dia-cdp-launch.sh`, 20,850 B, mtime 2026-08-09 23:07) — **not running** |
| **agent-browser** | **0 MB** | 0 | installed (fnm shim `…/fnm_multishells/7674_*/bin/agent-browser`) — **not running** |
| **BrowserMCP / chrome-devtools-mcp browsers** | **0 MB** | 0 | anchored argv[0] scan for `Google Chrome`/`Chromium`/`Chrome for Testing`/`chromedriver`: **zero**; the 2.0 GB in §4/A3 is server scaffolding driving **no browser at all** |

| | |
|---|---|
| **Finding** | **Infra-owned browser residency is 0 MB at rest.** 100 % of the 6.73 GB browser bill today is the operator's own Dia. The infra's browser *cost* is entirely the MCP scaffolding that has no browser attached. |
| **But it is bimodal** | At the 2026-08-09 panic window the sentinel recorded `167.0 MB x4 chrome-headless-shell` (unambiguously MCP-launched) beside `2248.1 MB x4 Google Chrome Helper (Renderer)`. So infra browser cost swings **0 → ~2.4 GB during a headless run**, and that run coincided with the panic window. |
| **Re-architecture** | Budget browser cost as an **event**, not a residency: a headless run is a ~2.4 GB burst that must be admission-gated the same way §2's storms are. Kill the idle MCP scaffolding (A3) — it is the one part that is pure loss. |

## A5 · Git background daemons — a genuine null, and the null is a config fact

| | |
|---|---|
| **Finding** | **Zero long-running git daemons exist on this machine.** All 18 live `git*` processes are transient foreground ops. This is not chance — the config cannot produce them. |
| **Evidence** | Anchored `comm`-position census: 18 live, all foreground (`git push -q -u origin main`, `git-receive-pack …/bats-run-…/o-d6c.git`, `git -C …/claude-infrastructure fetch origin main`). **`core.fsmonitor` is unset** globally and in both sampled repos ⇒ `fsmonitor--daemon` can never spawn. **`credential.helper=/usr/local/share/gcm-core/git-credential-manager`** — a per-invocation binary, **not** `credential-cache--daemon` ⇒ no cache daemon; each authenticated op forks GCM. `git config --global --get maintenance.repo` ⇒ **1 repo enrolled**; `maintenance.strategy=incremental` set only in `reso-management-app`. |
| **Cost now** | **0 MB.** Git daemons contribute nothing to the memory ceiling. |
| **Where the cost actually is** | With **252 worktrees** and no fsmonitor, every `git status` is a full lstat walk — a **CPU/fork and page-cache** cost, not RAM (it feeds the 14.1 GB file-backed bucket in §1a). Per-op GCM forks add to the same bill. → axis E owns the design question; this row is the census that closes it. |

## A6 · `claude.exe` subagent lifetimes — live distribution, and the instrument that cannot answer it

Live `--agent-id` processes, `etime` ascending: `23:51 24:06 24:20 24:30 24:46 25:01 25:13 25:28 25:40
25:54 26:07 26:22 26:38 26:49 27:04` (the 15-member wave, spawned ~15 s apart) plus three survivors
from earlier waves at **01:05:27, 01:06:03, 01:20:47**.

| | |
|---|---|
| **Finding** | Two populations: a **research wave** (uniform, ~15 s spawn cadence, all alive at ~25 min) and **long-runner teammates** (65–80 min). Combined with §3's growth curve this gives the wave's memory shape: **15 × 215 MB on arrival → 15 × ~310 MB by 50 min ⇒ a wave adds ~3.2 GB and grows to ~4.7 GB before it returns.** |
| **Instrument gap (named)** | **Lifetimes are not derivable from any store on disk.** `~/.claude/logs/pane-spawns.jsonl` has 521 rows and 12 keys (`ts, surface, backend, caller, pid, ppid, ppid_comm, chain, ancestry, pane, cwd, marker`) — **spawn events only, no exit event and no duration**, and no `kind` discriminator. `~/.claude/watchdog/*.pid` (36) + `*.daemon` (36) hold the registration but are removed on clean exit, so a completed subagent leaves no record. |
| **Re-architecture** | The watchdog daemon **already detects the lead's exit** (`local_watchdog()` loop) — have it append one `{sid, pid, kind, spawn_ts, exit_ts, peak_footprint}` row before it returns. That is the cheapest possible lifetime+peak ledger and it needs no new process. `phys_footprint_peak` is readable from `footprint` at exit and is the one number nothing currently records. |
| **Sizing** | Zero new residency; turns "trigger unknown" (A1) and "lifetime unknown" into log queries · effort **S** · risk low (append-only, best-effort). |

## A7 · Revised lever ranking (supersedes §11 where they differ)

| # | Lever | Recovers | Effort | Existing mechanism |
|---|---|---|---|---|
| 1 | **Fix the sentinel's cohort predicate** (drop `args ~ /claude/`; key protection on `ucomm` + `argv[0]` + a live registry entry; `ucomm` instead of `comm` to kill the space-split bug) | unlocks an **already-armed** actuator against **8–17.6 GB** excursions it currently cannot touch | S | `compressor-sentinel.sh:334-337, 385` |
| 2 | **Bound `ugrep`** in the shell-snapshot `grep()` (RLIMIT_AS + `-m` + reject unanchored `-o .{0,N}` at a dir root) | the same 8–17.6 GB, at the source rather than the actuator | S | the `grep()` function; reso `mem-leash.sh` |
| 3 | **Record `argv[0]` in the burst detector** and re-partition the 54 events | closes `scaling-bottlenecks:32` "trigger unknown" | XS | `compressor-sentinel-snap.log` (argv already stored) |
| 4 | **node class-cardinality admission gate** | up to **44.7 GB** (the 08-09 panic) | M | sentinel + `capacity-alarm.sh` |
| 5 | **MCP: leak containment + no MCP for `--agent-id` subagents** (re-ranked *down* — A3 shows the fixed term is 5.9 GB at 150, not 49 GB) | ~1.5 GB standing + 3.2 GB peak | S–M | none |
| 6 | **Watchdog writes an exit row** (`sid, kind, spawn/exit ts, peak_footprint`) | the missing lifetime + peak ledger | S | `lead-crash-watchdog.sh local_watchdog()` |
| 7–10 | unchanged from §11: one watchdog not 28 · kill 31 `caffeinate` · fewer kitty OS windows · `.metadata_never_index` + reap orphan `gitstatusd` | ~1.4 GB + ~22 k forks/h | S–M | existing |
| — | **Not levers**: age-based recycling for memory (§5, ≤35 MB — matches the settled figure) · staggering session starts (§9, peak/current 1.06–1.24) · git daemons (A5, 0 MB) · infra browser residency (A4, 0 MB at rest) | — | — | — |
