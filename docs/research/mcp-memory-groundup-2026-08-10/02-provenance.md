# 02 — Provenance of "340 MB/session" and "507 MB MCP children", + what prior art already DECIDED

**Agent:** provenance/prior-art axis · **Date:** 2026-08-10 · **Repo read-only**, in place at
`/Users/chrisren/Development/claude-infrastructure`.
**Contract:** doc claims reported AS claims. A sibling agent owns live truth. Where a doc and a
sibling measurement conflict I report the doc's METHOD, not a verdict.

---

## 0 · The two-line answer

- **340 MB is sound and is NOT an MCP number.** Origin `docs/research/scaling-bottlenecks-2026-08-09/01-memory-age.md:208-221`
  — a paired within-box differential on `active_gb`, n=1,194 transitions, symmetric on arrival AND
  departure, footprint-instrumented. It is a **marginal in-situ arrival cost**, not a per-process RSS.
- **507 MB is a DERIVED RATIO, not a measurement of a per-session term — and the same corpus has
  already refuted it, 8x down, in writing.** Origin `.../08-platform-terms.md:23,96-97` — `5,073 MB
  ps-RSS / 10 sessions`, with **no ppid attribution**, in **`ps` RSS** (the one instrument its own
  sibling axis banned). `docs/research/memory-econ-rearchitecture-2026-08-10/census-fleet.md:379-401`
  (section A3) re-measured argv[0]-anchored + ppid-walked: **62 MB/session fleet-average, 140 MB RSS
  per *hosting* session, 12% of sessions host** — and re-projects **5.9 GB at 150, not 49 GB**.

**=> The lead's live census (2 chains, ~595+145 MB, zero browsermcp) is not a surprise. It is the
THIRD consecutive timepoint consistent with A3 and inconsistent with 507.** The 507 figure's only
surviving life is in an **OPEN backlog item** (section 4) and in rollup tables nothing has amended
(section 5).

---

## 1 · Provenance table

| Number | First appearance (file:line) | Measurement command / method | Population measured | Per-session or aggregate | Date / config state |
|---|---|---|---|---|---|
| **340 MB** — session arrival cost | `docs/research/scaling-bottlenecks-2026-08-09/01-memory-age.md:208-221` (section 4.3 "The per-session constant — 340 MB, not 232 MB") | **Paired adjacent-sample differential** on `active_gb` from the capacity log; transitions <=180 s apart; through-origin pooled slope. Instrument declared at `:5-8`: `vmmap -summary <pid>` *Physical footprint*, cross-checked vs `top -l1 -stats pid,mem` (<1 MB on 4/4). **"`ps` RSS is NOT used for any conclusion"** (`:7`) | 1,194 dS transitions over an 11-day capacity log; box-held-constant | **Per-session MARGINAL (in-situ)** — explicitly *not* the self-footprint. Self-footprint stated alongside as **269 MB**; process-only 235–270 MB | Measured 2026-08-09 23:13–23:30 PDT; M1 Max 64 GiB, macOS 15.6.1, kitty fleet |
| 340 MB — **DECOMPOSITION** | same, `:214-226` | dS table: -3 -> 560 · -2 -> 327 · **-1 -> 365** · **+1 -> 293** · +2 -> 361 · +3 -> 181 MB/session | as above | consistent in both directions, 293–365 MB band | same |
| **507 MB** — MCP children/session | `docs/research/scaling-bottlenecks-2026-08-09/08-platform-terms.md:23` (verdict row j) and `:96-97` (section 2(j) body) | **`ps -A -o rss=,command=`** -> count `chrome-devtools-mcp` procs, sum RSS, **DIVIDE BY SESSION COUNT**. Corroborating spot-reads via `top -l 2 -o mem` | **22 `chrome-devtools-mcp` procs / 5,073 MB, against 10 `claude` sessions** (command-position count). **No ppid walk, no argv[0] anchor, no cwd attribution** | **AGGREGATE / N** — a ratio presented as a per-session constant. 2.2 procs & 507 MB per session | Measured 2026-08-09; ambient stated at `:7-8` — 10 sessions, 921–927 procs, load1 24.9–27.1, iTerm2 not running, swap 0.00 M |
| 507 -> **~49 GB at 150** | same, `:102`; rollup `docs/research/scaling-bottlenecks-2026-08-09.md:31` | `150 MB (median proc) x 2.2 children x 150 sessions = 49.5 GB` — note this uses the **median-proc 150 MB**, not the 507, then labels the row 507 | projection, not measurement | aggregate projection | 2026-08-09 |
| **REFUTATION: 62 MB/session** | `docs/research/memory-econ-rearchitecture-2026-08-10/census-fleet.md:384-394` (section A3) | **argv[0]-anchored scan; each proc rooted to a session by ppid-walk**; RSS + `vmmap` footprint | **33 live sessions** (15 `claude` + 18 `claude.exe --agent-id`); 12 MCP-class procs / 2.00 GB | per-session **62 MB**; per **hosting** session **140 MB RSS / ~325 MB footprint**; **4 of 33 host (12%)** | 2026-08-10 01:05–01:20 PDT |
| **PRIOR (earlier) — 280 MB/session** | backlog `e34a0e48833e`, `~/.claude/autonomy/backlog.jsonl`, ts `2026-08-04T11:13:42Z` | not stated in the item; reported as measured | "3 procs / ~280MB per session, measured **3.07GB across 11 sessions**" | per-session, from an 11-session aggregate | 2026-08-04. **Closed 2026-08-10T04:29:09Z** — evidence: branch `cc-001759-77337` gone, `.mcp.json` still absent from `origin/main` |
| **PRIOR — ~165 MB x 3-deep chain** | `docs/research/panic-compressor-2026-08-05.md:107-109` | live fingerprint during panic forensics | "every Claude session spawns a 3-deep `chrome-devtools-mcp` node chain (`npm exec` -> shim -> main, ~165 MB each)"; 724 procs / 3 ~= 241 chains vs 6 live sessions | ~495 MB/session **if** residency — **but the doc REFUTES that reading itself** at `:113-121`: the cohort "arrived inside the final 12 minutes", is 8-thread parked-unconnected, i.e. a **BURST**, not residency | 2026-08-05 |
| **Per-chain structural cost** | `docs/research/memory-econ-rearchitecture-2026-08-10/session-cost.md:79-84`, `:150-155` | process-tree walk + `vmmap` footprint per member | `npm exec ...@latest` **117 MB** -> `chrome-devtools-mcp` **95–1900 MB** -> `telemetry/watchdog/main.js` **88–110 MB** | **312 MB per CHAIN** (the reusable unit); 4 chains live = 1.25 GB, of which ~830 MB is wrapper+telemetry | 2026-08-10 |
| **The leak (what actually made 507 big)** | `census-fleet.md:166`, `:394`; `session-cost.md:157-161` | `vmmap --summary 7993` | one pid: RSS 1,593 MB / **footprint 1,929 MB / peak 3,213 MB**, uptime 1h36m; **zero browser procs box-wide** (argv[0]-anchored grep for Chrome/Chromium/chromedriver -> 0) | **76% of the whole MCP class total sat in ONE pid** (1,519 of 2,000 MB) | 2026-08-10 |

---

## 2 · Adversarial pass — five defects in the 507 chain, none of which any doc names

Each is my own finding from reading the sources against each other; none appears in the corpus.

1. **507 is in the WRONG INSTRUMENT by its own wave's doctrine — and by ~3.3x.**
   `01-memory-age.md:7-8` (same wave, same night): *"`ps` RSS is NOT used for any conclusion — it
   read **916 MB against a 273.7 MB footprint on the same pid, a 3.3x shared-library double-count**."*
   `08-platform-terms.md:97` *itself* calls footprint "the metric S6.0 established as the correct one"
   — and then reports the headline number in `ps` RSS anyway. Nobody in the corpus reconciles this.

2. **The 507 population was never attributed.** The cited command `ps -A -o rss=,command=` cannot
   root a proc to a session. `:96` asserts *"10 of 10 claude sessions carry an MCP child"* — the
   command shown cannot establish it. **The same document contradicts it two rows up:** `:55-56`
   reports *"2 of 10 live sessions are cwd'd in the SHARED root
   /Users/chrisren/Development/claude-infrastructure"* — a repo whose `origin/main` carries **no
   `.mcp.json`** (backlog `e34a0e48833e`, closed with exactly that evidence). Those 2 sessions could
   not have hosted a `chrome-devtools` server. **10/10 was likely never true even on the night it
   was written.**

3. **340 + 507 may DOUBLE-COUNT, and the corpus adds them anyway.** The 340 is dACTIVE across
   session-count transitions **<=180 s apart** (`01-memory-age.md:198`). The MCP chain **starts 53 s
   after session init** (`session-cost.md:85` — *"pid 99699 elapsed 1:40:19, its `npm exec` child
   1:39:26"*). An MCP-carrying session's arrival therefore lands its MCP tree **inside** the 180 s
   differential window. Yet `bottleneck-refute.md:61` bills them additively: *"Session RSS
   (main+helpers, 340MB) + MCP where used (+507MB)"*. A grep for
   `double-count|already includes|overlap` across `01-memory-age.md`, `08-platform-terms.md`, the
   rollup, `census-fleet.md` and `bottleneck-refute.md` returns **zero** hits addressing this
   overlap. **Named uncertainty — I did not adjudicate it.**

4. **Three distinct ~340 numbers live in this corpus and will collide on a fast read:**

   | figure | quantity | cite |
   |---|---|---|
   | **340 MB** | session ARRIVAL cost (paired differential) | `01-memory-age.md:208-221` |
   | **~340 MB** | kitty **IOSurface per OS WINDOW** on a 5K display ("panes are ~free") | `terminal-layer.md:85`, `:341`, `:435` |
   | **343 MB** | **context term** at a full 1 M window (0.343 MB / 1 K input tokens) | `session-cost.md:60`, `:69`, `:163` |

   These are three unrelated quantities. Any synthesis must name which one it means.

5. **Four numbers exist for the same MCP class across 6 days, and each supersession is silent:**
   280 (08-04, backlog) -> ~495-if-resident (08-05, **self-refuted as burst**) -> 507 (08-09) ->
   62 fleet-avg / 140 per-host RSS / ~325 per-host footprint (08-10). Only the last carries per-proc
   attribution. **No doc supersedes the previous one by name.**

---

## 3 · What was already DECIDED about MCP — verbatim, with file:line

### 3a · The 08-09 wave: consolidation SCOPED as the top lever (this is the claim now in doubt)

- `scaling-bottlenecks-2026-08-09.md:31` — *"**~507 MB/session** ... ~49 GB at 150 — **forecloses
  150-resident on its own** unless MCP is consolidated/lazy for resident sessions"*
- `:67-69` — *"150 RESIDENT on-box: REACHABLE only with (a) **MCP consolidation/lazy-spawn for
  resident sessions (~0.5 GB/session back — the single biggest lever on the box)**, (b) the 340 MB
  constant held ... Otherwise the honest on-box ceiling is ~100-130 resident."*
- `:125-126` (P2 build list) — *"**MCP consolidation** for resident sessions (shared daemon or
  spawn-on-first-use): recovers ~0.5 GB/session — the difference between ~100 and 150+ resident (08)."*
- `08-platform-terms.md:23` (remedy column) — *"add an MCP row to the S6.2 budget; cap MCP servers
  per session or share one fleet-wide"*
- **Its own confidence caveat, at `:106-108`:** *"MCP presence is a **per-project config fact**
  (browsermcp / chrome-devtools-mcp), **not a per-session constant**. Today it is 10/10; at 150 it
  may not be."* — i.e. the source doc already flagged the exact assumption A3 later broke.

### 3b · The 08-10 wave: blanket consolidation REJECTED and RE-RANKED DOWN

- `census-fleet.md:401` — *"Re-architecture: Unchanged from section 4, but **re-ranked**: the lever is
  ***leak containment + no-MCP-for-subagents***, **not blanket consolidation** (there is little to
  consolidate — **29 of 33 sessions already carry zero MCP**)."*
- `census-fleet.md:399` — *"Re-projected: at 150 sessions with today's 12 % coverage, MCP = 18 hosts
  x 325 MB ~= **5.9 GB, not 49 GB**. **MCP children do not foreclose 150-resident.** The ***leak***
  does — one instance reached `phys_footprint 1929 MB, peak 3213 MB`."*
- `census-fleet.md:451` (final ranked list) — *"| 5 | **MCP: leak containment + no MCP for
  `--agent-id` subagents** (**re-ranked *down*** — A3 shows the fixed term is 5.9 GB at 150, not
  49 GB) | ~1.5 GB standing + 3.2 GB peak | S-M | none |"*
- `census-fleet.md:413` — *"**BrowserMCP / chrome-devtools-mcp browsers: 0 MB, 0 procs.** anchored
  argv[0] scan ... **zero**; the 2.0 GB in section 4/A3 is **server scaffolding driving no browser at
  all**."*
- `census-fleet.md:417-419` — *"**Infra-owned browser residency is 0 MB at rest** ... But it is
  **bimodal**: at the 2026-08-09 panic window the sentinel recorded `167.0 MB x4
  chrome-headless-shell` beside `2248.1 MB x4 Google Chrome Helper (Renderer)`. **Budget browser cost
  as an EVENT, not a residency:** a headless run is a ~2.4 GB burst that must be admission-gated."*

### 3c · The concrete config levers, already priced (`session-cost.md:104-115` = the G-table)

| # | Lever | Recovers | Risk | Exact change |
|---|---|---|---|---|
| **G1** | Heap-cap the server (**real node v22.21.1, `heap_size_limit 4144 MB` => `--max-old-space-size` DOES bind**, unlike the bun-compiled CC binary) | ~0.9 GB now, caps class at 1 GB | **Med** — can OOM mid-use; 946 real calls in 7 d | reso `.mcp.json` -> `env.NODE_OPTIONS=--max-old-space-size=1024` |
| **G2** | Kill the telemetry watchdog (`WatchdogClient.js:31` spawns a **detached third node** for Clearcut; gate at `chrome-devtools-mcp-cli-options.js:340`) | **88-110 MB/chain** (~410 MB now) | **Low** | `CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS=1` |
| **G3** | Drop `npm exec ...@latest` (leaves a resident **117 MB** parent + a registry re-resolve per session start) | ~470 MB now | **Low** (pins version — a feature) | direct node path; **`~/Development/taxes-2026/.mcp.json` already uses this pattern** |
| **G4** | chrome-devtools **opt-in, not always-on** | **312 MB** per non-user | **Med** — a browser task in a non-opted session fails until restart | `disabledMcpjsonServers` (**"already a supported key, currently unused"**, `:145`) or `.mcp.browser.json` |

**G4's own sizing line, the largest avoidable term in the corpus** (`session-cost.md:111`):
*"Started eagerly in **100 % of reso-worktree sessions**; **used in 19 of 600 transcripts (3.2 %)
over 7 d** (946 `tool_use` calls, so heavily used *when* used). It is also started per **teammate**
... a 12-member wave in a reso worktree = **13 chains ~= 4.0 GB**."*

Roll-up (`:118-119`): **"G1-G4 ~= 3.0 GB recoverable today with no operator decision, all inside one
MCP server family that has no browser attached."**

### 3d · The config ground truth every remedy depends on (`session-cost.md:87-95`)

- `$CFG/.claude.json` -> `mcpServers: {motion, motion-plus}`, **both `type: http` => 0 local processes**.
- `$CFG/.mcp.json` -> `browsermcp` via `bin/browsermcp-wrapper.sh` — **INERT.** *"CC reads `.mcp.json`
  from the **project root**, not the config dir. No `browsermcp` process exists, and
  `enabledMcpjsonServers: ["browsermcp","agent-browser"]` in settings.json **has nothing to enable**."*
  **=> This independently explains the lead's live "zero browsermcp procs" — by construction, not by chance.**
- **The only stdio server actually running is `chrome-devtools`, from the git-tracked
  `~/Development/reso-management-app/.mcp.json`**, inherited by all `~/Development/.worktrees/wt-cc-*`
  reso worktrees. `enableAllProjectMcpServers: true` is set in `~/.claude-next/settings.json`
  **(account 1 only)**.
- **Subagents inherit it and start their own servers** — `census-fleet.md:400`: *"`claude.exe
  --agent-id dep-types-node` (73566) hosts a full 4-process stack."* Also `orchestration-econ.md:133-136`
  (Finding 7) and `:67`.

### 3e · Decision-store status — **NOTHING about MCP has ever been ratified**

- `~/.claude/autonomy/decisions/` holds **117 packets**; `/usr/bin/grep -l -i 'mcp\|chrome-devtools'`
  over all of them -> **ZERO matches**. There is **no `cc-decide` packet on MCP**, consolidation or
  otherwise.
- The one class-C packet the 08-09 wave DID open (`scaling-bottlenecks-2026-08-09.md:111-117`) is the
  **c10 staged-migration ratification** (0006 cold-compile admission + 0007 mailbox-wake-arm +
  boot-resume plist + `DEVGC_ACT=1`) — **MCP is not in it.**
- **=> Every MCP remedy above is unratified prose.** Per the repo's own standing lesson
  (memory `conclusion-must-reach-the-enforcing-store`), none of it binds: `.mcp.json` /
  `settings.json` are the enforcing stores and **neither has been touched**.

---

## 4 · The live open item carrying the refuted number

```
{"id":"1ab1d8b66098","ts":"2026-08-10T06:52:31Z","event":"add","project":"claude-infrastructure",
 "title":"MCP child memory is absent from every capacity budget (~507MB/session measured; ~49GB at 150)
          - consolidate or lazy-spawn MCP servers for resident sessions",
 "source":"docs/research/scaling-bottlenecks-2026-08-09/08-platform-terms.md"}
```

`~/.claude/autonomy/backlog.jsonl` — **still OPEN** (no `done`/`block` event follows).

**Filed 2026-08-10T06:52Z; refuted by `census-fleet.md` A3, measured 2026-08-10 01:05-01:20 PDT
(= 08:05-08:20Z).** The refutation is ~75 min LATER in wall-clock than the filing, so the filer
could not have seen it. The item now carries a number its own corpus has superseded 8x down, and
prescribes the remedy (**"consolidate or lazy-spawn"**) that A3 explicitly rejected
(*"not blanket consolidation"*). **This is the single most actionable integration point for the
lead: the item needs RE-TITLING to leak-containment + no-MCP-for-subagents + G1-G4, not closing.**

Related, already closed: `e34a0e48833e` (2026-08-04 -> done 2026-08-10T04:29:09Z) — the 280 MB/session
datapoint, closed on *"branch `cc-001759-77337` does not exist; `.mcp.json` still absent from
`origin/main` - nothing can land it."*

---

## 5 · Ranked bottleneck order — and where MCP sits (the two waves DISAGREE)

| | **08-09 wave** (`scaling-bottlenecks-2026-08-09.md:29-36`) | **08-10 red-team** (`bottleneck-refute.md:52-58`) |
|---|---|---|
| 1 | **Memory — composite** (340 MB, N~=103-132) | **ACTIVE-session CPU load** — binds at **~4-8 concurrently-active**; 127/127 historic gate refusals were load, **0 memory** |
| 1a | +- **MCP children ~507 MB — "forecloses 150-resident on its own"** | **VM-compressor SEGMENT TABLE** under node dev-tooling bursts — *the killer*; 5/5 panics at 31-33% pages / **100% segments**; deaths at **5-17 sessions** |
| 1b | +- `claude.exe` self-bursts (54 procs >4 GB in 11 d, max 41 GB) | Fleet self-imposed caps (KMAX refuses the 33rd session; quota ~~~3.9~~ **6.2-11.0** sustained-active — corrected 2026-08-24, `../scaling-bottlenecks-2026-08-09.md` §2a) |
| 1c | +- toolchain bursts (the crash igniter) | Exec-path serialization (launchd/xpcproxy/tccd/syspolicyd) — **no guard exists** |
| 2 | Active-session load | **RAM total — "real but FAR out", N~=103-132 resident** |
| 3 | Fleet self-imposed caps | — |
| 4 | Account quota | — |

**Verdict headline, `bottleneck-refute.md:3-8`:** *"**RAM total has never been the binding
constraint** — the box has died 5x of a STRUCTURE limit (VM-compressor segment table, exhausted at
28-33% packing with 20GB free and `memoryPressure=false`) ... Live control at this instant: **14-15
sessions + a 15-agent research wave = load 100.77 on 10 cores while memory idles** (segments 3.3%,
swap 0, 10.4GB free)."*

**=> MCP moved from "wall #1a, forecloses 150 alone" to "a sub-term of the #5 constraint, re-ranked
down to lever #5, ~5.9 GB at 150".** `bottleneck-refute.md:61` still shows the un-amended additive
row (`340MB + 507MB`) because axis L was written against the settled table, not against A3 — **the
two 08-10 siblings do not agree with each other.** Named uncertainty; not adjudicated here.

Also load-bearing (`bottleneck-refute.md:65`): *"Sessions are **1.4-3.7%** of death-time footprint;
node dev-tooling is **91-92%**."* MCP scaffolding is a subset of the 1.4-3.7%, **except** in its
bimodal headless-burst mode (3b), which is where it touched a panic window.

---

## 6 · Every other in-repo MCP-memory surface the lead must integrate with

| Surface | file:line | What it holds |
|---|---|---|
| **Top-level synthesis (already written)** | `docs/research/memory-econ-rearchitecture-2026-08-10.md:117` (**T2.7 MCP lifecycle**), `:257`, `:275-287` (**T9.1-T9.4**) | The G-table already promoted into thesis form: *"MCP lifecycle (**no mechanism exists — genuine gap**)"* — (a) don't inherit into `--agent-id` subagents, (b) pin the version, (c) idle-TTL ~15 min, (d) restart-on-footprint. **~1.6GB standing + 3.2GB peak, effort S-M.** |
| Dev-tool/editor residency axis | `memory-econ-.../devtools-residency.md:1-40` | Trip rollup putting `chrome-devtools-mcp` at **1,152.7 MB x5, rank 8** — *below* `ugrep` (10,370 MB x5), `claude` (7,127 MB), `node` (3,272 MB). Also: **`Google Chrome Helper (Renderer)` 2,248 MB at the trip was puppeteer under chrome-devtools-mcp — infra-owned, mis-attributed to "the operator's browsing"** in the anchor census. |
| Orchestration economics | `memory-econ-.../orchestration-econ.md:67`, `:133-136`, `:240` | Finding 7 (subagent inheritance, pid 74513 <- ppid 73566). `:136` *"gate MCP startup on **agent type**, or ship a **research-agent config** with the browser MCP absent."* `:144` — *"Any daemon-consolidation case must be argued on fork/CPU, **never RAM**."* |
| Adversary/defend | `memory-econ-.../adversary-defend.md:27-50` | The general anti-consolidation law (SPOF, band diversity, *"the consolidation was already built and its premise measured FALSE"* for hooks). **MCP is NOT one of its rows** — so it neither defends nor indicts MCP consolidation. |
| Prior-art ledger | `memory-econ-.../prior-art.md:29`, `:61` | Carries **507 as "LIVE, OPEN — the single biggest lever on the box"**. **Stale vs A3 in the same directory.** Also `:164` — the *poller* consolidation precedent: **DECLINED, nothing built** (*"idle sessions were already free"*). |
| **Code/hook surface** | `hooks/session-start.sh:61` | The **MCP connectivity probe uses a bare `command -v claude`** -> per backlog `aac347ddc003`, *"the MCP probe is always skipped and CONNECTED_COUNT stays 0"* on the hook PATH. **The only in-repo MCP sensor is inert.** |
| Other code touchpoints | `bin/browsermcp-wrapper.sh` · `bin/dia-cdp-launch.sh` · `bin/cc-spawn-verify` · `scripts/deploy-parity-assert.sh` · `bin/kitty-confirm-close` · `tests/completion-assert.bats` | Full census of `browsermcp\|chrome-devtools\|mcpServers\|disabledMcpjsonServers` across `scripts/ hooks/ bin/ tests/`. **No memory-governing code exists for MCP anywhere.** |
| Earliest forensic sighting | `docs/research/panic-compressor-2026-08-05.md:107-121`, `:165` | 3-deep chain @ ~165 MB; **the doc's own reconciliation refutes the residency reading** (burst-spawned, parked unconnected, 8 threads). `:165` puts MCP execs in **ARM 2 (exec-path serialization)** — a CPU/exec term, not a memory one. |
| **`docs/ground-up-payloads/`** (row9, row11, row6, row7, **LOCUS-GAP-BRIEF-2026-08-08.md**) | — | **ZERO MCP mentions.** `rg -i 'mcp\|chrome-devtools\|browsermcp'` over the whole directory returns **nothing**. The ground-up program does not intersect this investigation. |
| Landmine on that directory | `prior-art.md:247` (C20) | *"`docs/ground-up-payloads/LOCUS-GAP-BRIEF-2026-08-08.md` is **UNTRACKED** — absent from `origin/main`, present only in the shared checkout's working tree, and a backlog item depends on it. **The next `git clean` destroys it.**"* — **confirmed still untracked in this session's `git status`.** Out of this axis's scope; surfaced because it is irrecoverable. |

---

## 7 · The INTEGRATE target — `docs/plans/CONCURRENCY_PROGRAM.md` section S6.2

**Recommendation: `docs/plans/CONCURRENCY_PROGRAM.md` (`status: open`), S6.2 at `:1275-1300`.**
Reasons, each cited:

1. **It is the doc that owns the defective budget.** `:1290-1293` reads
   `150 sessions x 232 MB ~= 35 GB` / `macOS + render + baseline ~= 10 GB` /
   `remaining for bursts ~= 19 GB` — **no MCP row, and the 232 constant that 340 supersedes.** Both
   source axes name it by section (`08-platform-terms.md:23` *"add an MCP row to the S6.2 budget"*;
   `01-memory-age.md:245` *"S6.2 [D] reads 150 x 232 MB ~= 35 GB ... Corrected:"*).
2. **The 08-09 wave already designated it as intake owner** — `scaling-bottlenecks-2026-08-09.md:166`:
   *"the **S6 program (scale-150 session) owns intake** — notified."*
3. **`docs/plans/MACHINE_CAPACITY_V2.md` is the WRONG target.** `/usr/bin/grep -i mcp` -> **zero hits**;
   its frozen scope (`:6-13`) is *"sustains **30 concurrent** sessions ... >=95% of gate-suite CPU in
   Darwin's BACKGROUND band"* — a QoS-band rebuild at N=30, not the 150-resident memory budget.
   Writing MCP findings there would breach its frozen DoD.
4. **Secondary target, same edit:** `docs/research/memory-econ-rearchitecture-2026-08-10.md` **T2.7 /
   T9.1-T9.4** (`:117`, `:275-278`) is where the *remedy* already lives in thesis form — it needs the
   **507 -> 62/140/325 correction and the re-rank** stitched in, since `prior-art.md:29,61` in the
   same directory still carries 507 as LIVE.

**Third, non-doc target — and the only one that ENFORCES anything:** backlog `1ab1d8b66098` (section 4).
A plan edit that leaves that item reading *"~507MB/session ... consolidate or lazy-spawn"* re-creates
the stale oracle the repo's own memory warns about (`resident-policy-must-not-restate-perishable-facts`,
`published-figure-decays-with-its-source`).

---

## 8 · Uncertainties, named

1. **340-vs-507 overlap is UNRESOLVED** (2.3). A <=180 s differential window vs a 53 s MCP start
   implies the marginal already contains the MCP tree for hosting sessions. No doc addresses it; I
   did not measure it. **If it overlaps, `bottleneck-refute.md:61`'s additive row over-bills.**
2. **Which 10 sessions the 507 measured is unrecoverable.** No ppid/cwd data was captured; the doc's
   own section 2(g) puts >=2 of them outside any MCP-declaring project. The ratio cannot be re-derived.
3. **A3 and the live census are both single-timepoint, in a config state that may itself be the
   variable.** A3's 12%-hosting figure rests on *"only `projects[".../reso-management-app"].mcpServers`
   declares `chrome-devtools`"* — a fact about `~/.claude.json` on 2026-08-10. A reso-heavy wave
   moves it; `session-cost.md:111` prices that at **13 chains ~= 4.0 GB** for a 12-member wave.
4. **The leak is uncharacterized.** One pid at footprint 1,929 MB / peak 3,213 MB with **zero
   browsers attached** supplied 76% of the class. No doc names a trigger, a reproduction, or a rate.
   This — not consolidation — is what both 08-10 docs say the lever should be.
5. **`bottleneck-refute.md` and `census-fleet.md` are siblings from the same wave that disagree on
   whether MCP forecloses 150.** I report both; adjudicating needs a live measurement, not a read.
6. **The 3.2% usage figure (`session-cost.md:111`, 19 of 600 transcripts / 7 d) is the load-bearing
   input to G4** and I did not re-derive it.
