# E — Memory pressure: where the 64 GB went, and what can come back without limiting a session

Axis: E-memory · Measured 2026-10-17 07:30–07:50Z (02:30–02:50 local) · read-only
(no signals, no installs, no test runs; probe scratch files only under `/tmp/e-memory-*`).
Load fell during the window: 136 (top, 07:36Z) → 55 (`sysctl -n vm.loadavg`, 07:49Z). The
numbers below are a snapshot of a box that is recovering from the 365→520 peak, so they are
*lower bounds* on what that peak carried.

## 0. Verdict

The largest single memory consumer on the machine is **not a Claude process. It is `fseventsd`, at
an 11 GB footprint (3.7–4.5 GB of that in the compressor) and growing**. It is livelocked again with
the 2026-09-08 signature: one main thread at 99% R, user:system time 20:1, and FSEvents delivery
**dead**. Two probes out of two timed out at 15 s, while the polling control on the same file
delivered in 6–72 ms. It went from 48 MB to 11.26 GB between 22:00Z and 07:42Z, the same window as
the load storm. The installed root watchdog does not restart it, for two reasons. It triggers only on
footprint at or above 16 GB. And the footprint instrument it reads (`top`'s MEM column) quantizes to
whole GB above 10 GB, so it reads growth as 0. All 29 Claude sessions together are 8.9 GB.

Ranked recoveries that do not limit any session (footprint basis, so compressed pages count):

| # | Recovery | Measured now | Recoverable | How |
|---|---|---|---|---|
| 1 | fseventsd livelock restart, triggered by the delivery probe | 11,264 MB fp, 99% of a core | ≈11 GB + 1 core (MEASURED by `top`, `ps -M`) | root watchdog gets a `livelock` verdict (operator install) |
| 2 | one shared ms365 server instead of one per session | 2,417 MB / 29 procs | ≈2.2 GB (ESTIMATED: daemon ≈150–200 MB) | `type: http` in `mcp-servers.json` + launchd agent |
| 3 | orphaned headless Chrome + `./driver` | 1,179 + 584 MB | ≈1.76 GB | source fix: `--remote-debugging-pipe`; attribution open |
| 4 | finished bg worker 9aa483e9, never retired (15.5 d) | 457 MB (3 procs) | ≈0.46 GB + the resident 2.1.284 binary | CC's own bg retire; source is the recycle exit dialog |
| 5 | `npx`/`uvx` wrappers in `personal/.mcp.json`, `taxes-2026/.mcp.json` | 3×~64 MB npm-exec + 3×~21 MB uv | ≈0.25 GB | direct binaries (or delete the duplicate ms365) |
| 6 | session-start `claude mcp list` refresh | ~84 short-lived ms365 spawns in 26.6 h | transient ~80–100 MB + 1 claude CLI each | collapses into #2 (HTTP connect spawns nothing) |

Together these are ≈15.7 GB of footprint. The compressor currently holds 11.0 GB of compressed
segments (31.2 GB of logical data), plus 4.47 GB of swap. Recovering #1–#3 alone would remove more
footprint than the compressor and swap hold together (ESTIMATED: this is a footprint-vs-compressor
comparison, not a simulation). Of the 24–25 GB wired, 6.9–7.2 GB is GPU allocations. The remaining
~18 GB is kernel memory, which cannot be broken down without root.

## 1. Method and instruments

- **phys_footprint per process.** `/tmp/e-memory-footprint.py` calls
  `proc_pid_rusage(pid, RUSAGE_INFO_V4)` through ctypes on `/usr/lib/libproc.dylib`. It reads
  `ri_phys_footprint`, `ri_wired_size` and `ri_lifetime_max_phys_footprint`, groups processes by a
  command-line classifier, and dumps a TSV to `/tmp/e-memory-fp.tsv`. Run as
  `gtimeout 90 /usr/bin/python3 -I /tmp/e-memory-footprint.py`. It ran twice: pass 1 covered 1,508
  procs (519 denied, all root), pass 2 covered 1,341 procs (443 denied).
- **Root processes** (fseventsd, WindowServer, kernel_task) cannot be read with rusage as uid 501.
  For those, one `top -l 1 -o mem -stats pid,command,mem,cmprs,…` snapshot was used. top's MEM column
  is the same phys_footprint accounting.
- **System:** `vm_stat`, `sysctl -a` (vm.*, kern.*, vfs.vnstats.*), `ioreg -r -c AGXAccelerator`
  (GPU PerformanceStatistics) and `ioclasscount`.
- **Footprint/RSS ratios differ wildly**, so an RSS census misreads this box (pass 1):
  claude 1.20, ms365 2.42, Dia helpers 2.49, kitty 34.9, chrome-headless-shell 28.0, `./driver`
  145. Any RSS-ranked list hides the orphans and the compressed processes.

## 2. Q1 — TRUE memory by process group (phys_footprint, includes compressed)

Pass 1 (07:3xZ, 1,508 procs; user-owned total footprint 55.37 GB against 29.67 GB summed RSS):

| group | n | RSS MB | footprint MB | note |
|---|---|---|---|---|
| **`git grep` (one transient process)** | 1 | 3,515 | **18,998** (lifetime max 18,998) | pid 29346; argv began `git grep -n -E kitty +@\|kitten +@\|… -- :!docs/research/load-root-cause-20…`. It is a peer research agent's command and was gone seconds later. See §7 |
| claude sessions (`.claude-293/…/.bin/claude`, plus their bash wrappers) | 58 (≈29 claude + ≈29 wrappers) | 7,460 | 8,965 | ≈300 MB per claude main process (range 240–426 MB) |
| Dia helpers | 22 | 1,963 | 4,887 | GPU process alone 2,495 MB (lifetime 4,102) |
| python (other) | 65 | 1,179 | 4,071 | mostly execnet/xdist workers (`Python -u -c import sys;exec(eval(sys.stdin.readline()))`), plus natural-tts-helper 628 MB |
| **ms-365-mcp-server** | 29 | 998 | **2,417** | 26 direct `node …/ms-365-mcp-server` (78–105 MB each) + 3 `npm exec` wrappers (63–65 MB) |
| kitty | 1 | 68 | 2,360 | 212 `<defunct>` children (other axis, H) |
| Cursor | 17 | 1,082 | 2,172 | |
| Google (Chrome) | 25 | 1,764 | 1,207 | |
| **chrome-headless-shell** (orphan) | 4 | 42 | **1,179** | pid 13394, ppid 1, etime 12-23:47, playwright `chromium_headless_shell-1243`, `--remote-debugging-port=0` |
| Dia main | 2 | 403 | 1,057 | |
| bash/zsh | 244 | 458 | 1,040 | the per-session watcher fleet; ≈4 MB each |
| Notes | 1 | 20 | 681 | |
| **`./driver`** (orphan) | 1 | 4 | **583** | pid 22582, ppid 1, etime 5-02:28, cwd `/private/tmp/zfav-tools` |
| **bg-spare family** | 4 | 174 | 470 | + daemon 28218 95 MB, see §5 |
| Hammerspoon | 1 | 60 | 400 | 354 MB compressed |
| gitstatusd | 19 | 53 | 175 | |
| sleep | 86 | 53 | 80 | |

Root-owned, from `top -l 1 -o mem` (07:36Z): **fseventsd 11 GB (CMPRS 4,250 MB)**, WindowServer
2,052 MB, kernel_task 32 MB (top's kernel_task row excludes wired kernel memory).

Pass 2 (minutes later) shows how fast the population moves: total user footprint 32.98 GB, with the
git grep gone and python down to 53 procs / 2.47 GB. The claude group was stable at 8,883 MB and
ms365 at 2,417 MB.

Sum of `ri_wired_size` over every readable process (pass 2): **0.004 GB**. Wired memory is not
user-mlocked memory (§4).

## 3. Q2 — MCP servers: who spawns what, cost, the 30 s timeout, and the shared-server design

### 3.1 What each session spawns (config read live)

`jq` over `mcpServers` in every config file:

| config | servers |
|---|---|
| `~/.claude.json` | motion (http), motion-plus (http), **ms365 (stdio, direct fnm binary)** |
| `~/.claude-next/.claude.json`, `~/.claude-secondary/…`, `~/.claude-tertiary/…`, `~/.claude-quaternary/…`, `~/.claude/.claude.json` | the same three |
| `~/.claude-next4/.claude.json` | none |
| `~/.claude/.mcp.json` (4 dirs symlink to it) | 23 bytes (empty) |
| `~/Development/personal/.mcp.json:3-8` | **ms365 via `npx -y @softeria/ms-365-mcp-server`** (unpinned), `:13-17` **mac-messages via `uvx mac-messages-mcp`**. Untracked file |
| `~/Development/taxes-2026/.mcp.json:3-13` | ms365 via `node …/npx-cli.js -y @softeria/ms-365-mcp-server` with its **own** `MS365_MCP_TOKEN_CACHE_PATH`/`MS365_MCP_SELECTED_ACCOUNT_PATH` (`~/.config/ms365-mcp/…`). Not a git repo |

SSOT for user scope: `mcp-servers.json:29-33` (ms365 stdio), rendered by `scripts/mcp-ssot-wire.sh`
from `install.sh:645-660`. Fired sessions get a passthrough from `scripts/lib/mcp-noinherit.sh:100`
(`CC_MCP_USERSCOPE_STDIO_ALLOW`, default `ms365`). http servers pass through it automatically.

**The only stdio server every session spawns is ms365.** motion and motion-plus are remote http,
with no local process. Live census (`ps -axww -o pid,ppid,etime,rss,command` walked parent to child):
25 of 28 interactive claude main processes have an ms365 child. Three in `personal` have an
`npm exec` wrapper above it (sessions 5520, 16976 and 68377, `CLAUDE_CONFIG_DIR=~/.claude-quaternary`,
`PWD=~/Development/personal`, read by `ps -E`). The 2 `-p` headless runs are under `--strict-mcp-config`
and have none.

**Two live interactive sessions have no ms365 child at all:**
- 69161 (wt-stop-hook-ledger, strict, 2 h 53 m old)
- 19489 (non-strict, 3 h 6 m old)

### 3.2 Cost

- **Memory.** 26 direct servers at 78–105 MB footprint each, plus 3 npm-exec wrappers at 63–65 MB:
  2,417 MB footprint, 998 MB RSS (MEASURED, §2).
- **CPU.** About 1 CPU-second per spawn, almost all of it startup: `ps -o time` shows 0.86–1.17 s on
  servers aged 42 min to 7 h, and 1.73 s on the 15-day one.
- **Startup I/O.** Each spawn cold-loads a 6,265-file, 81 MB package (`find -maxdepth 6 -type f | wc -l`,
  `du -sh`). On this box the vnode table recycles about 2,600 vnodes/s
  (`kern.num_recycledvnodes` = 3.597e9 over 16.5 d of uptime).
- **Spawn rate.** 324 `mcp-logs-ms365/*.jsonl` files were created since 2026-10-16 00:00 local, i.e.
  in 26.6 h, about 290/day (`find ~/Library/Caches/claude-cli-nodejs -maxdepth 3 -path
  '*mcp-logs-ms365/*' -newermt …`). Of those, **84 closed within 5 s**. These are the session-start
  `claude mcp list` health probes: `hooks/session-start.sh:277-279` refreshes in the background
  whenever the cache is older than `MCP_CACHE_TTL=300` s (`:142`, `:385`). A probe spawns a whole
  extra claude CLI plus every stdio server, then sends them SIGINT.
- **Other callers.** `scripts/lib/ms365_stdio.py:35` (`subprocess.Popen` of the binary), used by
  `bin/dl` and `bin/cc-mail-images`, spawns yet another private server per invocation.

### 3.3 Is the per-session spawn under load the cause of the 30 s connect failure? — Yes (conviction 85)

From `/tmp/e-memory-ms365log.py` over those 324 logs:
- **Successful connects** (n = 307): p50 2,972 ms, p90 5,690 ms, p99 12,437 ms, max 21,441 ms. A clean
  bench measured 2.1–6.0 s on 2026-08-15 (`MS365_MCP_ALL_ACCOUNTS.md:188`).
- **Hard `CONNECT_TIMEOUT … timed out after 30000ms` failures:** 2, at
  **2026-10-17T04:32:58Z (this program's own lead session, wt-cc-233108-87354)** and
  **04:45:18Z (wt-stop-hook-ledger, the live 69161 that has no ms365 child)**. Both fall in the
  load-500 peak.
- **"version negotiation probe timed out … restarting it once":** 4, on 10-16 at 05:19, 05:51,
  13:53 and 13:56Z. These are near-misses that CC rescued by restarting the server.
- The server is already authenticated, and auth is not the failure (the 2026-08-15 plan ruled it out
  and `verify-login` succeeded). The tail is the cost of a cold node start with a 6,265-file module
  tree, under 0% idle CPU and a saturated vnode cache. CC's documented behaviour adds to it:
  *"Stdio servers are local processes, and Claude Code doesn't reconnect them automatically"*.
  For a remote HTTP server, by contrast, *"When an HTTP or SSE server's first connection fails with
  a transient error … a timeout, Claude Code retries up to three times"*, and on a mid-session drop
  it retries *"up to five times with exponential backoff"*
  (code.claude.com/docs/en/mcp, fetched 2026-10-17).

### 3.4 Shared-server design (one per type, auth preserved)

**Auth isolation is not needed across the CC accounts.** The ms365 token cache is per macOS user,
not per config dir. The 2026-08-15 plan confirmed it, and `dist/token-cache-storage.js:18-46` shows
keytar (Keychain) with a file fallback, keyed to the user. All five config dirs already share one
MSAL identity (`operator@example.com`). The **one real isolation case is `taxes-2026`**, which
pins a different token-cache path. It gets its own instance (second port) or stays stdio, where it
costs only taxes sessions.

**Does the 2026-08-11 "No shared daemon" decision apply?** That decision is at
`MCP_MEMORY_100P_IMPLEMENTATION.md:542-545` and in `06-daemon-multiplex.md`. Its five grounds were
chrome-devtools-specific. Re-checked against ms365:

| prior ground | ms365 reality |
|---|---|
| global `toolMutex` serialises all sessions | `grep -l -iE 'mutex\|Semaphore' -r dist/` finds **nothing**. Graph calls are independent async HTTPS |
| one browser per process, profile lock, `#selectedPage` hijack | N/A. The only process-global is `selectedAccountId` (`dist/auth.js:393-415`), which is **already** persisted to the shared store and shared by all 26 processes today |
| restart strand on ≤2.1.220 | the fleet runs 2.1.293 (`.claude-293/`). CC now reconnects HTTP servers (docs quote above) |
| localhost attack surface | real, so bind 127.0.0.1 and require a key (below) |
| activity-leak concentration / multi-day growth | unmeasured, so add a footprint watchdog. A restart is transparent because of CC's 5× backoff reconnect |

The revisit criteria (`MCP_MEMORY_100P_IMPLEMENTATION.md:544-545`) were: a concurrency-safe server,
CC ≥2.1.221, and the mcp-proxy + launchd recipe. All three now hold.

**Two equivalent shapes** (pick one; both keep identical tools and identity):

- **(A) Native Streamable HTTP + a key-checking front.** `ms-365-mcp-server --http 127.0.0.1:<P>
  --trust-proxy-auth`.
  - `--trust-proxy-auth`: *"skip the built-in Bearer-token check on /mcp … All callers share the
    locally cached MSAL identity (same path stdio mode uses). Use only when an upstream reverse proxy
    has already authenticated the caller"* (`dist/cli.js:61-62`; middleware short-circuit at
    `dist/lib/microsoft-auth.js:44-46`).
  - The HTTP path is **stateless**: `server.js:497-501` builds an `McpServer` + transport per POST,
    with `sessionIdGenerator: void 0`, so there is no per-session leak to bound.
  - The transport is created **without** DNS-rebinding protection (`server.js:498-502`). A ~40-line
    loopback front is therefore mandatory: it checks `X-CC-MCP-Key` and `Host ∈ {127.0.0.1:<P>}`
    and forwards to the ms365 port.
  - Native `--http` *without* that flag requires per-client OAuth (README §"OAuth Authorization Code
    Flow": *"the server **requires** OAuth authentication"*). That changes the auth model, so it is
    rejected.
- **(B) `punkpeye/mcp-proxy`** (`--host 127.0.0.1 --port <P> --apiKey <K> --no-eventStore
  --sessionIdleTimeout 900000 -- <ms365 binary>`). It was measured to run ONE stdio child for N
  sessions (`06-daemon-multiplex.md:134`). `--apiKey` is built in. Recipe and launchd keys are at
  `06-daemon-multiplex.md:182-237`: `ProcessType Interactive`, `NumberOfFiles 8192`,
  `KeepAlive {SuccessfulExit:false}`, `RunAtLoad true`.

Config change, either shape: `mcp-servers.json:29-33` becomes
`{"type":"http","url":"http://127.0.0.1:<P>/mcp","headers":{"X-CC-MCP-Key":"<literal>"}}`.
- Use a literal value, or `headersHelper`. Per the docs, CC reads *credential variables* in remote
  `url`/`headers` as empty.
- `scripts/mcp-ssot-wire.sh` renders it into all five dirs.
- The passthrough filter (`mcp-noinherit.sh`, `select(.value.command == null)`) already keeps http
  servers, so fired sessions inherit it with no allowlist entry.
- `claude mcp list` then health-checks it with an HTTP initialize instead of a node cold start.
- `personal/.mcp.json:3-8` should drop its duplicate ms365 entry; project scope otherwise shadows
  the shared one.

**Expected effect:**
- **Memory:** 2,417 MB → ≈150–200 MB (ESTIMATED: one ms365 at ≈100 MB, as measured per process, plus
  a node front or proxy at ≈50–80 MB, an assumption not measured here). About 2.2 GB back.
- **Spawns:** about 290 cold node starts/day of a 6,265-file tree go to 0.
- **Connect:** from p50 3 s / p99 12 s with 2 hard timeouts per peak, to a loopback HTTP initialize
  (ESTIMATED <100 ms), with 3 automatic retries.
- **Throughput:** sessions do no less work. Every session still lists and calls the same 188 tools
  under the same identity.

**Risks:**
- One process is a shared failure domain. Mitigation: KeepAlive plus CC's reconnect.
- A localhost endpoint that can send mail. Mitigation: 127.0.0.1 binding, a key held in a 0600 file,
  and a Host check.
- Multi-day growth is unmeasured. Mitigation: a footprint watchdog with restart.
- Under shape (B), upstream Graph telemetry sees one client. That is harmless here.

### 3.5 mac-messages (personal only)

`uvx mac-messages-mcp` keeps a `uv` parent resident: 3 × ≈21 MB, plus Python 3 × ≈60 MB, about
244 MB across 3 sessions (pass 2 grouped by parent). Installing it with `uv tool install` and
pointing `command` at the entrypoint drops the 3 uv processes (≈64 MB). It is a candidate for the
same daemon pattern, but its concurrency safety was not checked.

## 4. Q3 — What the 24–25 GB wired is

| item | value | source |
|---|---|---|
| wired | 1,649,104 pages × 16 KiB = **25.2 GiB** | `vm_stat` |
| compressor (separate from wired) | 718,969 pages = 11.0 GiB occupied, holding 2,046,626 pages (31.2 GiB logical), ratio 2.85× | `vm_stat`; `vm.compressor_bytes_used` = 10.80 GB |
| user-process wired (`ri_wired_size` Σ) | 0.004 GB | rusage pass 2 |
| **GPU (AGX) allocations** | **"Alloc system memory" 6.95–7.23 GB**, of which "In use system memory" 0.59–0.91 GB | `ioreg -r -c AGXAccelerator -d 1` (two reads) |
| IOSurfaces / IOKit buffers | 721 IOSurface, 62 IOSurfaceRootUserClient, **24,964 IOBufferMemoryDescriptor**, 3,654 IOGeneralMemoryDescriptor | `ioclasscount` |
| vnodes | 263,168 = max, but **233,229 are on the free list** (only ~30 k in use), 3.597e9 recycled | `vfs.vnstats.*` |
| GPU wired limits | `iogpu.wired_limit_mb` 0 (default) | sysctl |

Reading of the table:
- **About 7 GB is GPU-attributed.** These are window and tab backing stores and GPU heaps for
  WindowServer (2.0 GB fp), the Dia GPU process (2.5 GB fp), kitty and Cursor.
- **About 18 GB is kernel.** Zones and kalloc, the 24,964 IOKit buffer descriptors, APFS
  object/metadata caches over 156 GB of worktrees, page tables for 1,150–1,500 processes and 773,812
  VM regions (top `MemRegions`), and vnode/namecache.
- **Could not determine the kernel split** without root: `zprint`/`mach_memory_info` need host_priv.
  Operator command: `sudo zprint -t -s | head -40`, run at peak and again at idle.
- vnodes contribute well under 1 GB (ESTIMATED: 263 k × ~1–2 KB vnode + APFS inode). The
  "num_vnodes == maxvnodes" in the brief is the normal macOS steady state (the table pre-fills and
  keeps a free list). The signal is the **recycle rate**, which belongs to the filesystem axis.
- **Hammerspoon is not wired.** It is 400 MB footprint, 354 MB of it compressed.

## 5. Q4 — `claude bg-spare` processes

**What they are.** Claude Code ≥2.1.284 runs a per-config-dir supervisor (`claude.exe daemon run`).
It pre-warms "spare" workers (`claude bg-spare --bg-spare <claim.sock>`), each under its own
`claude bg-pty-host` (a built-in dtach). `/background`, the exit dialog's "Move to background", and
`--bg` claim a spare instead of cold-starting. Spares do not count as clients for idle-exit
(`docs/research/session-durability-2026-10/C5-cc-native-bg-sessions.md:49-100`).

**Live now** (`ps` + `~/.claude-next/daemon/roster.json` + `daemon.log`):

| pid | role | footprint | age | note |
|---|---|---|---|---|
| 28218 | supervisor (next), 2.1.293 | 95 MB | 8 d 11 h | the only live supervisor. Roster supervisor pids for secondary/tertiary/quaternary (80988, 49831, 97964) are dead |
| 93571 → 94449 | pty-host → **true pre-warmed spare** | 34 + 57 MB | 13 h | keep: it is what makes bg starts instant |
| 10027 → 10156 → 11252 | pty-host (ppid 1, 2.1.284 binary) → **claimed worker 9aa483e9** → its ms365 | 40 + **338** + 79 = **457 MB** | **15 d 12 h** | the 2026-10-01 forked copy of lead 09c26b2b (761,285 tokens, `jobs/9aa483e9/state.json` `state: done` since 2026-10-01T19:26:19Z). Adopted by supervisor 28218 on 2026-10-08T19:54:53Z (`bg adopt: adopted=1`), then *"respawned 0/1 stale workers, 1 refused"*. It has **never been idle-retired** despite the 8 h idle constant (C5 E1), and has 0 `retire` lines since. It also keeps the whole 2.1.284 binary resident for one process |

Total for the family: 643 MB. The recoverable part is the 9aa483e9 tree, 457 MB. Its source is
known: `handoff-fire.sh`'s recycle answers "2 / Move to background and exit"
(C5 E2 cites `scripts/handoff-fire.sh:4280-4292`, `:8531-8548`). C5 already classifies that path as
a hazard (stale authority, invisible to the registry). **Could not determine** why adoption disabled
retire. The only evidence is the "refused" stale-respawn line.

## 6. fseventsd — the dominant item (memory axis view; the cause belongs to the FS axis)

- **Size:** `top -l 1 -pid 19766 -stats mem,cmprs` gives 11 G / 3,832–4,250 MB compressed.
- **Trajectory:** `~/.claude/logs/fseventsd-watch.jsonl` rows for pid 19766 read 4 → 48 MB from
  2026-10-10 to 2026-10-16T22:00Z. Then 69 MB (22:21Z), 1,009 (23:01), 2,905 (01:09), 4,907 (02:25),
  6,949 (04:23), 8,701 (05:36, first `warn`), 10,240 (07:20), 11,264 (07:42Z). Peak growth reached
  2.2 GB/h.
- **Livelock signature:** `ps -M -p 19766` shows the main thread at 99.3% R, UTIME 604:46 against
  STIME 31:01. That is the same single-thread user-space spin that
  `docs/research/fseventsd-churn-2026-09-08.md` §2.1 diagnosed.
- **Delivery is dead.** `/tmp/e-memory-fsevprobe/probe.js` (node `fs.watch` on a dir, i.e. libuv's
  FSEvents path, against a `fs.watchFile` polling control; one write each) returned
  `{"poll_ms":72,"fsevents_ms":"TIMEOUT>15000"}` and `{"poll_ms":6,"fsevents_ms":"TIMEOUT>15000"}`.
  Every FSEvents consumer on the box is blind right now: Hammerspoon, launchd WatchPaths, editors,
  CC's chokidar watchers.
- **Why the installed cure did not fire:**
  - The root LaunchDaemon `com.claude.fseventsd-watchdog` is installed (`launchctl print system/…`:
    runs = 3,328, last exit 0), but `/var/log/claude-fseventsd-restarts.jsonl` does not exist, so it
    has never restarted anything.
  - Its trigger is `ACT_MB=16384` (`scripts/fseventsd-watch.sh:37,65,153`), footprint only.
  - Its reader is `top … -stats pid,mem,cmprs` (`:116`), which prints `11G`. Above 10 GB it
    quantizes to 1,024 MB steps, so `growth_mb_h` reads **0** while the daemon is still growing
    (last two rows: 10,240 → 11,264 with `g=0`).
  - A livelocked daemon that plateaus below 16 GB is therefore never cured. On 2026-10-04 one grew to
    64 GB (`launchd/com.claude.fseventsd-watch.plist:6`).

## 7. Other observations (not recoveries, recorded so they are not lost)

- **The 19 GB `git grep`.** A single short-lived `git grep -n -E …` from a peer research agent
  reached an 18,998 MB footprint (lifetime max). It was gone before `ps`/`lsof` could read its cwd.
  The claude-infrastructure tree is 251 MB tracked (`git ls-tree -r -l HEAD`), so a working-tree grep
  cannot explain 19 GB. A grep over many revisions, or over another repo's huge tracked files, could.
  Mechanism UNCONFIRMED. Transient tool processes at this scale can push the compressor on their own.
- **kitty:** 2.37 GB footprint with only 68–88 MB RSS (scrollback_lines 2000,
  `~/.config/kitty/kitty.conf:976`) and 251 children, 212 of them zombies. Zombies hold no memory
  beyond the proc slot. The footprint is kitty's own; not analysed here (axis H).
- **The per-session bash watcher fleet** (lead-crash-watchdog, cc-close-attrib, mailbox-wake-arm,
  cc-pane-runner, about 90 procs at ≈3–4 MB) is ≈0.3–1.0 GB of footprint. It matters more for the
  fork/CPU axes than for memory.

## 8. Options considered and rejected

- **Native ms365 `--http` with OAuth (no `--trust-proxy-auth`).** Rejected: it needs a browser OAuth
  per config dir and a Graph token validation per request. That changes the auth model, so the
  outcome is not equivalent.
- **`supergateway` as the bridge.** Rejected: one child per session (`--stateful`) or per request
  (stateless) gives no memory win, and the SSE mode broadcasts every response to every session
  (`06-daemon-multiplex.md:136-138`).
- **ms365 `--discovery` / `--preset` to shrink per-session cost.** Rejected as a memory lever.
  Deferral and tool filtering change tokens, not the process. `--preset` also narrows capability,
  which would limit sessions.
- **Raising `MCP_TIMEOUT` above 30 s.** Rejected: it hides the cold-start cost and adds wait time to
  session start. The shared server removes the cost instead.
- **Restarting fseventsd on a timer, or lowering ACT_MB a lot.** Rejected: restarts have rescan
  costs (fseventsd-churn §5). Triggering on *dead delivery* is the precise condition.
- **Killing bg spares, or disabling the bg pool.** Rejected: the true spare (91 MB + 95 MB supervisor)
  buys instant background starts. Only the finished 15-day worker is waste.
- **Using RSS for any of these rankings.** Rejected: footprint/RSS runs from 0.66 to 145 across
  groups (§1).

## 9. Recommendations (verify recipes)

**E1 · P0 · operator install — fseventsd `livelock` verdict.**
- **Change:** in `scripts/fseventsd-watch.sh`, add a delivery probe: an `fs.watch` dir probe with a
  `fs.watchFile` control, 15 s window. The verdict becomes `livelock` when the probe fails on 2
  consecutive runs, the control succeeds, and main-thread %CPU is ≥90 (`ps -M`). The root path
  restarts on `livelock` as it already does on `act`, keeping `RESTART_GAP_S` and the pre-restart
  stack sample.
- **Also:** replace the `top` MEM read at `:116` with `proc_pid_rusage` (exact bytes; root can read
  it) so that growth above 10 GB is visible.
- **Install:** re-run `migrations/0057-fseventsd-watchdog.sh`. It is root.
- **Verify:** `node /tmp/e-memory-fsevprobe/probe.js` should show `fsevents_ms` < 1000 after the
  restart, then `top -l 1 -pid $(pgrep fseventsd) -stats mem`. A ledger row should appear in
  `/var/log/claude-fseventsd-restarts.jsonl`.
- **Immediate one-off (operator):** `sudo launchctl kickstart -k system/com.apple.fseventsd`.

**E2 · P0 — one shared ms365 server.**
- **Change:** add a launchd agent `com.claude.mcp-ms365` running shape (A) or (B) from §3.4. Change
  `mcp-servers.json:29-33` to `type: http`, render it with `scripts/mcp-ssot-wire.sh`, and delete the
  duplicate in `personal/.mcp.json:3-8`.
- **Leave taxes-2026 on its own:** a second instance on its own port, or stdio.
- **Verify:**
  - `ps -axo pid,ppid,command | grep -c '[m]s-365-mcp-server'` should drop from 29 to 1–2.
  - A new session's `mcp-logs-ms365` should show `transport: http` connected in under 1 s.
  - `mcp__ms365__verify-login` should succeed from a desk session and from a fired session on
    two accounts.
  - Run the §3.3 parser again after 24 h: 0 `CONNECT_TIMEOUT`.

**E3 · P1 — orphan sources.**
- **Change:** have whatever launches the playwright `chrome-headless-shell` use `--remote-debugging-pipe`
  (Chrome exits on pipe EOF) instead of `--remote-debugging-port=0`. Attribution is still open.
  Identify the owner of `/private/tmp/zfav-tools/driver`.
- **Verify:** after a controller exits,
  `ps -axo pid,ppid,etime,command | awk '$2==1' | grep -E 'chrome-headless|driver'` should show
  nothing older than the run.

**E4 · P1 · operator decision — retire the finished bg worker 9aa483e9.**
- **Change:** retire it through CC's own bg lifecycle (`claude agents`). Separately, fix the
  recycle-exit-dialog answer that creates such copies (C5 hazard).
- **Verify:** `ps -p 10156,10027` shows nothing, and `~/.claude-next/daemon/roster.json` no longer
  lists 9aa483e9.

**E5 · P1 — direct binaries for the project-scope wrappers.**
- **Change:** `personal/.mcp.json:13-17` (uvx → installed entrypoint) and `taxes-2026/.mcp.json:3-8`
  (npx-cli → direct binary, keeping its token-cache env).
- **Verify:** `ps -axo command | grep -c '^npm exec @softeria'` should be 0, and there should be no
  `uv tool uvx` parent.

**E6 · P2 — session-start probe.**
- **Change:** none needed if E2 lands, because the `claude mcp list` refresh (`hooks/session-start.sh:142,385`)
  stops cold-starting node. Otherwise, the TTL is the knob.
- **Verify:** the count of `mcp-logs-ms365` files that close within 5 s per day.
