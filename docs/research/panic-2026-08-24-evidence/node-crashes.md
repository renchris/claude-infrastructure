# User-level crash cluster — node/agent process crashes, Aug 13–24 2026

Axis: what OUR node/agent processes were doing (user-level `~/Library/Logs/DiagnosticReports/*.ips`),
in service of root-causing the Aug 24 20:01:23 watchdog/compressor panic.
Analyst: read-only subagent, Mon 2026-08-24 ~20:30 PDT (post-reboot).
All 25 node reports + all 19 git + 2 win reports parsed (full-population, not a sample).

## Verdict (answer-first)

1. **(a) WHICH binary:** the node-*.ips crashes are **reso-management-app Next.js dev-stack
   processes running in `~/Development/.worktrees/` worktrees** — `next-server (v16.3.0)` dev
   workers, a vitest worker, and short-lived node children of two `node` supervisor processes —
   running on either fnm node (`/Users/USER/Library/Application Support/fnm/*/node`) or the stray
   system `/usr/local/bin/node` v22.12.0. They are **NOT Claude Code binaries** (CC 2.1.220's
   `claude` is a Bun-compiled native Mach-O — `__BUN` segment — so a CC session's procName is
   `claude`, never `node`), **not MCP servers** (`~/.claude.json` mcpServers = motion/motion-plus
   (http) + ms365 via npx; none uses the crashing addons), and **not launchd daemons** (daemon
   children carry their own coalition names — see the git section — while every node crash is
   coalition `net.kovidgoyal.kitty`, i.e. terminal/agent-session-descended).
2. **(b) WHY they died:** four distinct mechanisms, none of them jetsam:
   - 17/25: **SIGSEGV at spawn** (KERN_INVALID_ADDRESS at exactly `0x90`) inside
     `napi_module_register_by_symbol` while `DLOpen`-ing **better-sqlite3@13.0.3's
     `prebuilds/darwin-arm64.node`** — an **N-API version mismatch**: the prebuild exports
     `node_api_module_get_api_version_v1` (declares N-API 10); `/usr/local/bin/node` is v22.12.0
     = **N-API 9** (verified: `process.versions.napi` = 9; fnm v22.21.1 = 10; N-API 10 shipped in
     node 22.14). reso pins `.node-version` 22.15 / engines `>=22.15.0`, so any context that
     resolves `node` to /usr/local/bin/node is off-contract and crashes deterministically.
   - 6/25: **SIGSEGV at process exit** inside **@libsql/darwin-arm64@0.5.29 `index.node`**
     (Turso native client) — napi `Reference::Finalize` → identical index.node frame offsets
     every time, faulting address always in a GAP between MALLOC regions = use-after-free in the
     libsql finalizer during Environment teardown.
   - 1/25: **V8 heap OOM abort** (SIGABRT via `node::OOMErrorHandler` →
     `v8::internal::V8::FatalProcessOutOfMemory`) in a **vitest worker** (thread 0 name
     `node (vitest 1)`) — JS-heap-cap OOM, not machine OOM.
   - 1/25: **SIGABRT (Rust panic → abort)** in **next-swc.darwin-arm64.node** inside an orphaned
     **`next-server (v16.3.0)`** dev worker (faulting thread `tokio-rt-worker`).
   - **Zero** reports show `SIGKILL`, `CODESIGNING`, `EXC_RESOURCE`, or jetsam terminations.
3. **(c) the Aug 23 03:25 burst is ONE incident with TWO respawning parents, one shared root
   cause:** parent node **6127** spawned 9 children 03:25:09–03:25:35 (all crashed at spawn in
   better-sqlite3), then parent node **2888** spawned 9 more 03:26:44–03:27:21 (8 spawn-crashes +
   1 exit-crash). Same parent per wave, several same-second sibling spawns, every child dead
   <1.3 s after launch → a **crash-respawn loop** (shape and self-termination match `next dev`
   restart-on-crash supervision). The 04:11–04:27 stragglers are the aftermath on the CORRECT
   (fnm) node: four separate ~10 s attempts, each dying only in the libsql exit-finalizer.
4. **(d) footprints:** no enormous *resident* footprints. Largest per vmSummary: the next-server
   worker (64 KB report) — **5.6 GB writable virtual, 20.5 GB "Memory Tag 255" (V8 cage) virtual,
   2.9 GB IOAccelerator (GPU) + 128 MB reserved, 213.5 MB stacks/37 threads** but only ~31.7 MB
   written; the vitest OOM worker — **6.3 GB writable virtual, 14.3 GB Tag-255 virtual across
   16,326 regions** (fragmented V8 cage = heap-cap OOM fingerprint), 269.9 MB written. The
   spawn-crash children never got past ~2.2 GB virtual / ~11 MB dirty.
5. **(e) death window Aug 24 19:00–20:01: EMPTY.** Newest node crash content is Aug 23 04:27:18;
   newest user-level crash of any kind is git Aug 23 11:10. In the final hour the only artifacts
   anywhere are the system-level `JetsamEvent-2026-08-24-195524.ips` (19:55) and the panic itself
   (20:04). **User processes were not crashing while the machine died** — pressure built without
   a single process fault, until the kernel watchdog fired. This crash cluster ends ~40 h before
   the panic; it characterizes the workload population, it does not time-correlate with the death.

## Inventory + count-by-day

47 user-level .ips total: 25 node, 19 git, 2 win, 1 VoiceInk (source: `ls/find` on
`~/Library/Logs/DiagnosticReports/`).

node-*.ips by day (Aug 13–24):

| Day (2026-08) | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 | 21 | 22 | 23 | 24 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| node crashes | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | **1** | **1** | **23** | 0 |

(git-*.ips: Aug 20 ×6, Aug 21 ×7, Aug 22 ×4, Aug 23 ×2. win-*.ips: Aug 19 ×2.)

Anomaly noted: `node-2026-08-21-150202.ips` (crash content Aug 21 15:02) has **mtime Aug 24
02:20** — metadata-only re-touch (analytics/symbolication re-processing), not a new crash.
System-level context (in `/Library/Logs/DiagnosticReports/`, adjacent evidence only): node
CPU-resource `.diag`s Aug 18 03:41 + 23:31, rsync diag Aug 18, `fseventsd` **cpu_resource diag
Aug 23 19:28**, `ditto` diag **Aug 24 16:17** (~3.7 h pre-panic), Dia diags Aug 21/23.

## The 25 node crashes — full extraction table

All: procName `node`, responsibleProc `kitty` (pid 587), coalition `net.kovidgoyal.kitty`.
"usr-local" = `/usr/local/bin/node` v22.12.0 (N-API 9); "fnm" = `/Users/USER/Library/Application
Support/fnm/*/node` (installed: v18.18.0, v20.19.5/6, v22.21.1; v22.21.1 = N-API 10).

| # | file (node-2026-…) | launch → capture (PDT) | pid | parent | node | sig | died how |
|---|---|---|---|---|---|---|---|
| 1 | 08-21-150202 | 08-21 15:01:43.6 → 15:02:00.8 (~17 s) | 44792 | node 16123 | fnm | **A** | SIGSEGV libsql finalizer |
| 2 | 08-22-165727 | 08-22 16:50:31 → 16:57:26 (~7 min) | 38213 | **launchd 1** (orphan) | fnm | **C** | SIGABRT V8 heap OOM (vitest 1) |
| 3 | 08-23-012321 (64 KB) | 08-22 23:49:17 → 08-23 01:23:18 (94 min) | 68536 | **Exited process** 68378 (orphan) | fnm | **D** | SIGABRT next-swc Rust abort (next-server v16.3.0) |
| 4 | 08-23-032527 | 03:25:09.8 → 03:25:10.9 | 58162 | node **6127** | usr-local | **B** | SIGSEGV @0x90 DLOpen better-sqlite3 |
| 5 | 08-23-032527.0002 | 03:25:17.70 → :18.25 | 66557 | node 6127 | usr-local | B | same |
| 6 | 08-23-032527.000 | 03:25:17.73 → :18.43 | 66577 | node 6127 | usr-local | B | same |
| 7 | 08-23-032534 | 03:25:20.59 → :21.32 | 68366 | node 6127 | usr-local | B | same |
| 8 | 08-23-032533 | 03:25:21.23 → :21.81 | 68704 | node 6127 | usr-local | B | same |
| 9 | 08-23-032538 | 03:25:28.30 → :28.89 | 74408 | node 6127 | usr-local | B | same |
| 10 | 08-23-032538.0002 | 03:25:28.83 → :29.33 | 74729 | node 6127 | usr-local | B | same |
| 11 | 08-23-032538.000 | 03:25:29.38 → :29.94 | 75031 | node 6127 | usr-local | B | same |
| 12 | 08-23-032542 | 03:25:34.46 → :35.22 | 78581 | node 6127 | usr-local | B | same |
| 13 | 08-23-032703 | 03:26:44.76 → 03:26:54.79 (10 s) | 36719 | node **2888** | usr-local | **A** | SIGSEGV libsql finalizer (at exit) |
| 14 | 08-23-032713 | 03:27:02.80 → :03.37 | 55469 | node 2888 | usr-local | B | SIGSEGV @0x90 DLOpen better-sqlite3 |
| 15 | 08-23-032718 | 03:27:07.77 → :08.34 | 60615 | node 2888 | usr-local | B | same |
| 16 | 08-23-032719.000 | 03:27:07.91 → :08.52 | 60788 | node 2888 | usr-local | B | same |
| 17 | 08-23-032719 | 03:27:08.99 → :09.69 | 62286 | node 2888 | usr-local | B | same |
| 18 | 08-23-032726 | 03:27:10.12 → :10.70 | 63327 | node 2888 | usr-local | B | same |
| 19 | 08-23-032726.000 | 03:27:14.91 → :15.34 | 66209 | node 2888 | usr-local | B | same |
| 20 | 08-23-032727 | 03:27:18.30 → :18.94 | 68283 | node 2888 | usr-local | B | same |
| 21 | 08-23-032728 | 03:27:21.00 → :21.60 | 70005 | node 2888 | usr-local | B | same |
| 22 | 08-23-041100 | 04:10:42.8 → 04:10:59.5 (~17 s) | 85267 | node 60932 | fnm | A | SIGSEGV libsql finalizer |
| 23 | 08-23-041403 | 04:13:50.3 → 04:14:01.4 (~11 s) | 15675 | node 92007 | fnm | A | same |
| 24 | 08-23-041736 | 04:17:24.3 → 04:17:35.7 (~11 s) | 81543 | node 65595 | fnm | A | same |
| 25 | 08-23-042718 | 04:27:09.5 → 04:27:18.1 (~9 s) | 16503 | node 96441 | fnm | A | same |

Uptime field in the burst reports: 760000 s ≈ 8.8 d, consistent with the crashed boot
(Aug 13 22:42 → Aug 23 03:25 = 8d 4.7h; field is coarse-rounded).

## Signature detail

### Signature B — spawn-death loading better-sqlite3 (17 crashes, the burst)

- exception: `EXC_BAD_ACCESS SIGSEGV KERN_INVALID_ADDRESS at 0x0000000000000090` (identical all 17;
  vmRegionInfo: "0x90 is not in any region … UNUSED SPACE AT START" = NULL-struct field deref).
- Faulting thread 0 (`com.apple.main-thread`), 11 threads (bare early-startup node), identical stack:
  ```
  node`napi_module_register_by_symbol(...)+584
  node`std::__1::__function::__func<node::binding::DLOpen(...)::$_0 ...>::operator()(...)+736
  node`node::Environment::TryLoadAddon(...)+128
  node`node::binding::DLOpen(...)+500
  node`Builtins_CallApiCallbackGeneric+184
  node`Builtins_InterpreterEntryTrampoline+272   (+ 4 unsymbolicated JIT frames)
  ```
- Loaded addon present in usedImages: `/Users/USER/*/darwin-arm64.node`,
  **UUID C87A9325-F748-3E31-91DC-18CFB1217A68** — exact match (dwarfdump) with
  `~/Development/.worktrees/wt-pool-4/node_modules/.pnpm/better-sqlite3@13.0.3/node_modules/better-sqlite3/prebuilds/darwin-arm64.node`
  (1,980,736 B, mtime Aug 10 00:37 — the pnpm-store hardlink shared across worktrees; NOT
  rewritten on Aug 23, so no install race — the file was stable and the crash deterministic).
- Mechanism: prebuild exports `_napi_register_module_v1` **and**
  `_node_api_module_get_api_version_v1` (nm -gU). It requests N-API 10;
  `/usr/local/bin/node` v22.12.0 provides N-API **9** (`process.versions.napi` = 9, modules=127).
  On the fnm v22.21.1 node (N-API 10) the same file loads fine — no sig-B crash exists on fnm
  node. reso pins `.node-version` **22.15** and engines `node >=22.15.0`; every sig-B process ran
  the off-contract `/usr/local/bin/node` (Dec 2024 pkg install). PATH-resolution escape: e.g.
  `scripts/worktree-pool.sh` only prepends fnm's default alias **if `command -v node` fails** —
  any context where /usr/local/bin/node is already on PATH keeps it (the repo's own
  "config flip ≠ shell flip" class).
- better-sqlite3 is a direct reso dependency (`package.json` line 182: `"better-sqlite3": "^13.0.3"`,
  present in reso root and the wt-pool/bake/provision worktrees; the pool seeds a per-worktree
  `sqlite.db`, so app/dev code touches it at startup).

### Signature A — exit-death in the libsql finalizer (6 crashes)

- `EXC_BAD_ACCESS SIGSEGV KERN_INVALID_ADDRESS` at a heap-adjacent address that is **always in a
  GAP between MALLOC_TINY/SMALL regions** (use-after-free), faulting thread 0, 17–21 threads.
- Identical top frames every time (same image offsets across 2 days ⇒ same binary):
  ```
  index.node+4618472 / +2513860 / +2740588 / +506516 / +380320 / +470324
  node`...CallIntoModule<...CallFinalizer...>+64
  node`node_napi_env__::CallFinalizer(...)+88
  node`v8impl::Reference::Finalize()+92
  node`node::CallbackQueue<...EnqueueFinalizer...>::Call(node::Environment*)+100
  ```
- `index.node` **UUID 15297104-5A23-3847-9A99-938DD2F1AC9E** — exact match with
  `.../node_modules/.pnpm/@libsql+darwin-arm64@0.5.29/node_modules/@libsql/darwin-arm64/index.node`
  (7,837,712 B, mtime May 18) = the **Turso/libsql native client**. Crash sits in napi reference
  finalization during Environment teardown ⇒ the process was EXITING; work likely completed, exit
  status became SIGSEGV (so callers see failure and retry — which the 04:11–04:27 sequence of four
  fresh parents shows). Happens on both fnm node and /usr/local/bin/node (libsql declares a
  compatible N-API level, so it loads everywhere; its bug is at teardown, not load).

### Signature C — vitest worker V8-heap OOM (1 crash, Aug 22 16:57)

- `EXC_CRASH SIGABRT`, termination `SIGNAL/6 Abort trap: 6 byProc=node byPid=38213`,
  asi `abort() called`. Thread 0 name **`node (vitest 1)`** (vitest worker-pool thread naming), 8 threads.
- Stack: `abort → node::OOMErrorHandler → v8::internal::V8::FatalProcessOutOfMemory →
  Heap::FatalProcessOutOfMemory → Heap::CollectGarbage...` = **JS heap hit V8's own cap** (a
  test blew old-space), not system memory exhaustion.
- Parent **launchd(1)** = its original parent (vitest main / the session) had ALREADY exited —
  an orphaned test worker ran ~7 min detached and OOM'd.
- vmSummary: writable total 6.3 GB virtual, written 269.9 MB; **Memory Tag 255 = 14.3 GB virtual
  across 16,326 regions** (fragmented V8 cage — the heap-cap-OOM fingerprint).

### Signature D — orphaned next-server, next-swc Rust abort (1 crash, the 64 KB report)

- `node-2026-08-23-012321.ips`: launched Aug 22 23:49:17, crashed Aug 23 01:23:18 (94 min).
  Parent: **"Exited process" 68378** — an orphaned dev worker whose supervisor died.
- Thread 0 name **`next-server (v16.3.0)`**; 36 threads: 4 `libuv-worker`, ~19
  tokio-rt/tokio-runtime workers, **`notify-rs fsevents loop`** (Rust file-watcher). Faulting
  thread 16 `tokio-rt-worker`: `abort()` ← 7 frames inside `next-swc.darwin-arm64.node`
  (UUID 4C4C44B6-5555-3144-A110-75A83FC34CD6, mapped 85.4 MB) = SWC Rust panic → abort.
- vmSummary: writable 5.6 GB virtual (31.7 MB written), **Memory Tag 255 = 20.5 GB virtual**,
  **IOAccelerator 2.9 GB (79 regions) + 128 MB reserved** (a node dev worker holding GPU address
  space — unusual; see cross-axis note), Stack 213.5 MB / 37 stacks, `__LINKEDIT` 641.8 MB.
  Also loads the same libsql `index.node` (UUID match) — the whole reso native stack in one image list.

## (c) What happened Aug 23 03:25–04:27 — reconstruction

Two long-lived node supervisor processes (pids 6127 and 2888, both kitty-descended, both running
/usr/local/bin/node judging by their children's inherited execPath) each entered a
**spawn→crash→respawn loop** against the same broken combination (better-sqlite3 N-API 10 prebuild
× N-API 9 node): 9 children in 25 s (6127), then 9 in 37 s (2888), including same-second sibling
pairs/triples (a small concurrent worker pool per round). The loops self-terminated after ~9
attempts. Shape, concurrency, and restart cadence match **`next dev` supervision restarting its
crashed `next-server`/worker children** — independently corroborated by the confirmed
`next-server (v16.3.0)` crash in the same fleet 2 h earlier, and by 2888's one 10-second child
that loaded libsql (fine on N-API 9) and died only at exit. CC itself is excluded as the parent
binary (Bun-native `claude`, would not be procName `node`); launchd daemons are excluded by
coalition. By 04:11–04:27 the spawning contexts were on the CORRECT fnm node (four fresh parents,
one ~10 s child each) and only the libsql exit-finalizer crash remained. This was the overnight
agent fleet cycling reso dev servers in pool/bake/provision worktrees (`wt-pool-N`,
`wt-re1-bake-d`, `wt-denver-provision`; `scripts/worktree-pool.sh` + worktree-gc were active —
gc log entries at 03:38/03:39/03:44/03:46 that night). The parents' exact command lines are
unrecoverable post-reboot (pids from the dead boot; /tmp wiped; no fleet log records those pids).

## git-*.ips (19) and win-*.ips (2) — the rest of the user-level cluster

- **git (19, Aug 20–23, ~10.6 KB each):** all one signature — `EXC_BAD_ACCESS SIGSEGV` at 0x8 in
  `CoreFoundation __CFCheckCFInfoPACSignature` under `Foundation LocaleCache.init()`, asi
  `"*** multi-threaded process forked ***"` + `"crashed on child side of fork pre-exec"` — the
  classic macOS **fork-safety crash** in a forked git child before exec (git = /opt/homebrew).
  Parents: launchd; coalitions name OUR daemons: **com.claude.deploy-live ×13,
  com.claude.postland-verify ×5, com.chrisren.autonomy-sweep ×1** (several with responsibleProc
  `gtimeout`). Chronic, ~1–5/day, memory-irrelevant; each one is a failed git op inside a daemon run.
- **win (2, Aug 19 06:57):** procName `win`, procPath `/private/tmp/*/win` — a fleet-built test
  binary run from /tmp (terminal-bench era), SIGSEGV, parents already exited, kitty coalition. Noise.

## (e) Death-window and panic-relevance assessment

- **No user-level crash report of any kind exists between Aug 23 11:10 and the panic** — 33 h of
  crash-silence, and specifically ZERO in Aug 24 19:00–20:01. The 19:55 JetsamEvent (system-level)
  and the 20:04 panic file are the only death-window artifacts.
- Therefore the node crash cluster is **not the proximate event** of the panic. What it DOES
  establish about the workload: the fleet runs reso Next.js dev workers, vitest workers, and
  worktree-pool churn around the clock (03:25 AM storms), workers get **orphaned and keep
  running detached** (2 of 25 crashes are orphans: one for 94 min, one OOM'd under launchd), and
  each live next-server carries a 20 GB-virtual V8 cage plus **2.9 GB of IOAccelerator (GPU)
  address space**. On unified-memory Apple Silicon, GPU/IOAccelerator backing is wired kernel
  memory: dozens of such workers is a plausible feeder for the panic's 21.2 GB wired /
  `data.kalloc.1024` 9.2 GB zone / WindowServer-largest-process picture — flagged as a
  **cross-axis hypothesis** (this axis cannot measure kernel-side backing), alongside the
  system-level `ditto` CPU diag at Aug 24 16:17 and `fseventsd` CPU diag Aug 23 19:28.
- The cluster also shows the **"dev-worker memory storm" population named in the Aug 9 panic
  investigation (task #151, still in_progress) was alive and churning after the
  compressor-segment guard shipped** — the guard did not remove the workload class, and the
  crash-respawn loop shows the fleet spawning that class unattended at 03:25 AM.

## Refuters (what would overturn this reading)

1. A recovered command line for pid 6127/2888 showing something other than a next/dev supervisor
   (e.g. a custom fleet script) — would re-attribute the burst's PARENT, not the mechanism.
2. better-sqlite3@13.0.3's prebuild shown to declare N-API ≤9 (e.g. by reading its
   get_api_version return) — would shift sig-B's root cause from version-gate to a different
   registration bug; the /usr/local-only distribution of all 17 crashes would still stand.
3. Any user-level .ips or jetsam kill of a node process found inside Aug 24 19:00–20:01 —
   would directly connect this axis to the death window (none exists in either
   DiagnosticReports directory).
4. Evidence that IOAccelerator regions in next-server are unbacked reservations only —
   would kill the wired-memory cross-axis hypothesis.

## Sources

- `~/Library/Logs/DiagnosticReports/` (all 47 .ips parsed; extractor + raw dump:
  this scratchpad's `parse_ips.py`, `node-raw.txt`)
- `/Library/Logs/DiagnosticReports/` directory listing (system-level context)
- `dwarfdump --uuid`, `nm -gU` on wt-pool-4's better-sqlite3/libsql binaries (UUID matches)
- `/usr/local/bin/node -p process.versions` (napi 9, modules 127, v22.12.0);
  fnm v22.21.1 (napi 10); `~/Library/Application Support/fnm/node-versions/`
- reso: `package.json` (better-sqlite3 line 182, engines >=22.15.0), `.node-version` (22.15),
  `scripts/worktree-pool.sh`, `~/.reso/worktree-gc.log`
- `~/.claude-220/node_modules/.bin/claude` (Mach-O with `__BUN` segment), `~/.claude.json` mcpServers
