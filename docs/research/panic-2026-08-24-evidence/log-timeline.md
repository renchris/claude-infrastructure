# Unified-log timeline of the 2026-08-24 20:01:23 watchdog panic (panic #5) + shutdown-cause history

Axis: unified-log death-spiral timeline + previous-shutdown-cause history for the 8 reboots since Jul 30.
All timestamps PDT. Evidence = `log show` over the persisted unified log (survives reboot), plus
/Library/Logs/DiagnosticReports artifacts. Raw query outputs are preserved in this directory
(`A-kernel-1830-2002.txt`, `A-kills.txt`, `B1-watchdogd-1830-2002.txt`, `C1-kernel-1100-1140.txt`,
`D1/D2-*`, `E-*`, `F-lastlines-1954-200205.txt`, `K1-aug13-preboot.txt`, `L-afternoon-1200-1830.txt`).

## 0. Verdict (this axis)

The machine died of **VM compressor SEGMENT exhaustion, not RAM or swap-space shortage** — the kernel said so
itself at **19:53:34.098**: `System is unhealthy. memorystatus_available_pages: 1072819 compressor_size:1610187`
followed by `{"compressor_exhausted": 1, "zone_map_is_exhausted": 0, "swap_low": 0, "swap_exhausted": 0}`.
16.4 GB of `memorystatus_available_pages` existed at that moment; the segment pool (100 % of segments limit,
73 swapfiles) was the exhausted resource. Jetsam then spent ten minutes killing **2,740** processes — every one
of them a small Apple daemon (8.43 GB reclaimed in total; largest single victims: smd 374 MB, WiFiAgent 221 MB,
mediaanalysisd 206 MB) — while logging **1,951** `failed to kill a process and no memory was reclaimed` and
**87,152** `skipping idle but not idle-exitable process` lines across only **83 distinct pids**, dominated by
**Browser Helper (Renderer) ×46,208** and **Google Chrome Helper (Renderer) ×15,579**. It never used
`killing_top_process` (count 0) and never touched a single fleet process (no node / claude / Cursor / iTerm /
kitty / Chrome / Browser Helper / WindowServer kill in the entire window). The kill/respawn/re-kill loop
(online-auth-agent killed ×176, sandboxd ×155, amfid ×151, trustd ×115) plus the skip-enumeration spin is what
the panic header shows as three kernel_task threads at priority 91 topping CPU. logd persisted its last line at
**19:59:36.655**, watchdogd's last kernel checkin was **~19:59:50** (panic − 93 s), and the box was silent for
1 m 47 s until the AppleARMWatchdogTimer panic at **20:01:23**.

Shutdown-cause history: **structurally unavailable from the unified log on this machine.** macOS 15 on Apple
Silicon emits no "Previous shutdown cause" message at boot (verified on both retained boots, including the
known-panic Aug 24 boot: zero matches), and log retention on this box starts at the Aug 13 22:42 boot — all 7
earlier reboots have zero log lines. The Aug 24 reboot is proven a watchdog reset by
`ResetCounter-2026-08-24-200414.diag` (**"Boot faults: wdog,reset_in1"**) and the
`panic-base+socd-2026-08-24-200410.000.panic` file. The Aug 13 reboot's cause is indeterminate from logs.

## 1. Sources and method

Primary queries (each reproducible):

- Kernel memory channel 18:30–20:02:30: `log show --start '2026-08-24 18:30:00' --end '2026-08-24 20:02:30'
  --style compact --predicate 'process == "kernel" AND (eventMessage CONTAINS[c] "memorystatus" OR … "jetsam"
  OR … "swap" OR … "compressor" OR … "watchdog")'` → 97,407 lines.
- watchdogd's own messages, same window, `--info` → 3,892 lines (10 s heartbeat, 6–7 lines/beat).
- All-process firehose 19:54–20:02:05 → 576,562 lines; 20:00:00–20:02:05 → **0 lines** (logd already dead).
- Prescribed non-kernel kill query (`process/subsystem CONTAINS "memorystatus"` + "kill") → 0 matches on this
  macOS; the kernel lines are the authoritative kill record.
- Afternoon control 12:00–18:30 (same kernel predicate) → 364 lines; 11:00–11:40 → 26 lines.
- Shutdown-cause probes: per-boot windows for `"shutdown cause"` (8 windows), retention controls (kernel-line
  counts in the first 2 min of each boot), pmset -g log, DiagnosticReports listing, nvram.

Rendering artifact to know: early-boot kernel lines (before timezone init) render with UTC wall-clock text
(e.g. the 20:02 PDT boot's first lines print as `2026-08-25 03:02:…`) while still being window-matched
correctly. They are not future events.

## 2. Long-lead context (same boot session, before the spiral)

| Time | Event | Source |
|---|---|---|
| Aug 13 22:42:30 | Boot of the session that crashed (panic file epoch `Boot 0x6a7eaac6`) | .contents.panic |
| Aug 22 21:17:14 → 21:26:00 | Last sleep → last wake. From here the box ran awake **46 h 35 m** straight to the panic. Cross-check: panic says 16,763 watchdog checkins since monitoring enabled × 10 s = 46.6 h ✓ | .contents.panic epochs; pmset -g log |
| Aug 24 11:26:56–58 | Two **per-process-limit** fatal kills: IntelligencePlatformComputeServi (20 MB cap, 20.9 MB), knowledgeconstructiond (15 MB cap, 16.2 MB). `memorystatus_available_pages: 3,070,877` (~46.9 GB) — **zero system pressure**. This is what JetsamEvent-2026-08-24-112657.ips records; nothing to recover from, and nothing else happened until 13:08. | C1 file |
| 13:08:22 | spotlightknowledged exceeded ActiveSoft 45 MB (non-fatal warning) | L file |
| 15:04:29–15:08:07 | **Afternoon tremor**: 134 idle-exit kills at the 1/s metronome cadence (per minute: 31/3/33/60/7), all small daemons (intents_helper, MessagesBlastDoorService, MTLCompilerService, PlugInLibraryService…). Stops by itself; **zero kills 15:08 → 19:49**. This is the first evidence of real pressure, 4.7 h before the panic. | L file |
| 16:17:20 | `ditto` CPU-resource diag written (2.9 MB) — a heavy copy was running mid-afternoon | DiagnosticReports ls |
| 18:30–19:49 | Kernel memory channel entirely routine (WebKit opt-ins, ANE init/deinit stats, 30-min CoreAnalytics counters). No kills, no exceeded-limit events. | A file |

## 3. Minute-by-minute: 19:30 → 20:02:30

Kernel memory-channel line volume per minute (A file): 19:39 ×3 · 19:48 ×1 · 19:49 ×9 · 19:50 ×60 · 19:51 ×32 ·
19:52 ×0 · **19:53 ×52,009** · **19:54 ×31,066** · 19:55 ×6 · 19:56 ×39 · 19:57 ×63 · 19:58 ×6 ·
**19:59 ×13,999** · then nothing until post-reboot 20:04.

All-process log volume per minute (F file): 19:54 ×183,836 · 19:55 ×133,452 · 19:56 ×21,743 · 19:57 ×57,309 ·
19:58 ×54,732 · 19:59 ×71,089 (ends :36) · 20:00–20:02:05 ×0.

| Time | Event |
|---|---|
| 19:30–19:49:51 | Quiet. Only routine ANE/WebKit/CoreAnalytics kernel lines. watchdogd heartbeating normally (37–38 log lines/min all hour). |
| **19:49:51.937** | **Spiral onset.** Idle-exit metronome starts at exactly 1 kill/s: ciphermld, metrickitd, FPCKService, milod, homeenergyd, storagekitd, com.apple.geod, webprivacyd… (osr_code 9 = idle-exit). 8 kills in 19:49, 60 in 19:50, 32 in 19:51. |
| ~19:51:31 | Metronome stops after ~100 kills — the idle-exitable queue is exhausted. |
| 19:52 | **Zero** kernel memory events for 2 m 02 s. Pressure climbs invisibly. |
| **19:53:34.098** | Kernel declares the emergency, once and unambiguously: `triggering no paging space action` (8 such lines in the window) · `System is unhealthy. memorystatus_available_pages: 1072819 compressor_size:1610187` · `{"compressor_exhausted": 1, "zone_map_is_exhausted": 0, "swap_low": 0, "swap_exhausted": 0}`. Note: 1,072,819 pages × 16 KB = **16.4 GB available** — this was never a free-memory shortage. |
| 19:53:34.1–.5 | Highwater sweep (21 `killing_highwater_process` total: amsengagementd 22 MB, DockHelper 35 MB, syspolicyd 82 MB, **WiFiAgent 221 MB**, dock extras, siriinferenced…) interleaved with big idle kills under reason `vm-compressor-space-shortage`: **smd 374 MB** (19:53:34.228), **mediaanalysisd 206 MB** (.518), mobileassetd 49 MB. |
| **19:53:35.230** | First `failed to kill a process and no memory was reclaimed` — repeated **1,951** times through 19:59. |
| 19:53–19:54 | Main storm: 1,158 + 505 kills/min; `killing due to "vm-compressor-space-shortage" - compression_ratio=5` ×2,694; the **87,152** `skipping idle but not idle-exitable process` lines begin — the kernel re-enumerating the same **83 pids** it is not allowed to idle-kill (§4). System-wide log rate peaks at ~3,000 lines/s (launchd respawn churn; syspolicyd, fseventsd, trustd, `deleted` purging caches). |
| **19:55:24** | JetsamEvent-2026-08-24-195524.ips written (2.7 MB): compressorSize 1,610,185 pages, uncompressed 8,772,415 pages (≈5.4:1, matching the kernel's `compression_ratio=5`), wired 1,389,270, **free 3,838 pages (60 MB)**, largestProcess "WindowServer". (`free` is the raw free queue; `memorystatus_available_pages` includes reclaimable — both true simultaneously.) |
| 19:56:23–19:58:03 | Metronome round 2 (1/s): now killing **freshly-respawned** daemons — pids in the 91xxx range (amfid, keybagd, GSSCred, cfprefsd ×2, photoanalysisd, maild…), many killed with `0s rf:high` (age < 1 s). 36 + 60 + 4 kills. |
| **19:58:39.614** | watchdogd's **last logged line**. Its 10 s beats in 19:58: :09 ×7, :19 ×6, :29 ×6, :39 ×2 — truncated mid-beat. (Userspace logging died here; kernel checkins continued ~70 s more.) |
| 19:58:55.823 | Respawned mediaanalysisd already exceeded ActiveSoft 600 MB. |
| 19:59:20.754–19:59:34.992 | Final kernel storm: 877 kills + skip sweeps, 13,999 kernel lines in ~15 s. **Last kernel line of the boot: 19:59:34.992** `killing due to "vm-compressor-space-shortage"`. |
| 19:59:32.583 / 33.083 | WindowServer's final words: CoreAnimation `timed out fence 1632089250545` / `timed out batch 14ff43`. It was never killed — it starved. |
| 19:59:36.315 | A **new node process** (pid 81853) logs a MallocStackLogging complaint — the fleet was still spawning processes into the dying machine. |
| **19:59:36.655** | **Absolute last persisted unified-log line of the boot**: launchd mid-spawn of iconservicesagent — `service state: spawning`. logd persistence ends here. |
| **~19:59:50** | Last watchdogd checkin the kernel received (20:01:23 − 93 s, from the panic string). |
| 19:59:36 → 20:01:23 | **1 m 47 s of machine-wide darkness** — no process persisted a single log line. |
| **20:01:23** | PANIC (cpu 3, kernel_task, AppleARMWatchdogTimer): `watchdog timeout: no checkins from watchdogd in 93 seconds (16763 total checkins since monitoring last enabled)`. `Compressor Info: 33% of compressed pages limit (OK) and 100% of segments limit (BAD) with 73 swapfiles and OK swap space`. Top CPU: three kernel_task threads at pri 91 (cpu_usage 3.0 M / 2.15 M / 2.14 M). Stackshot incomplete (240 bytes, err 52) — the panic path itself could not allocate. |
| 20:02:10 | Reboot. (Early-boot lines render as `2026-08-25 03:02` UTC.) |
| 20:04:10 / 20:04:14 | `panic-base+socd-….panic` (366 KB) and `ResetCounter-….diag` written: **`Boot faults: wdog,reset_in1`**, Reset count 1, Boot failure count 0. |
| 20:04–20:15 | Normal boot noise; routine soft-limit warnings (amsengagementd, DockHelper, mds). |

## 4. The kill ledger (whole window 19:49:51–19:59:34)

- Types: `killing_idle_process` **2,719** · `killing_highwater_process` **21** · `killing_top_process` **0** ·
  `killing_specific_process` **0**. Kills carrying reason `vm-compressor-space-shortage`: 2,499.
- Kills per minute: 19:49 ×8 · 19:50 ×60 · 19:51 ×32 · 19:53 ×1,158 · 19:54 ×505 · 19:56 ×36 · 19:57 ×60 ·
  19:58 ×4 · 19:59 ×877 = **2,740**.
- Reclaimed: **8.43 GB total** across 2,520 kills-with-size — while compressor_size moved only from ~1,610,187
  to ~1,588,585 segments (−1.3 %). The reclaim was arithmetic noise against a 24.6 GB compressor.
- Respawn/re-kill loop (top victims by kill count): online-auth-agent ×176, sandboxd ×155, amfid ×151,
  trustd ×115, com.apple.geod ×109, CodeSigningHelper ×75, UIKitSystem ×71, OSDUIHelper ×64,
  AquaAppearanceHelper ×59… launchd respawned them; jetsam re-killed them, often at age `0s`.
- Largest single reclaims: smd 374,497 KB · WiFiAgent 226,178 KB · mediaanalysisd 211,282 KB ·
  syspolicyd 82,034 KB · WiFiAgent (respawn) 54,881 KB.
- **Zero kills of anything that held real memory**: no node, claude, Cursor, iTerm2, kitty, Chrome,
  Browser Helper, soffice, Notes, or WindowServer kill anywhere in the window (grep of all 2,740 kill lines;
  the only case-insensitive "dia/chrome/node"-ish hits are substring artifacts like media**analysisd**).
- The skip census — who jetsam wanted to reap but could not (`not idle-exitable`), 87,152 lines over 83 pids:
  **Browser Helper (Renderer) ×46,208** (≈44 pids — The Browser Company renderers: Dia/Arc)
  · **Google Chrome Helper (Renderer) ×15,579** (≈15 pids) · TGOnDeviceInferenceProviderService ×2,637
  · QLPreviewGenerationExtension ×2,494 · soffice ×2,328 · Notes ×2,317 · systemstats ×1,938 · Console ×1,415
  · Signal Helper (Renderer) ×769 · ~15 Apple widget extensions ×~600 each. Skip counts measure enumeration
  frequency × process count, not bytes — but ~60 of the 83 unkillable pids were browser renderers.

## 5. Why this is compressor-segment exhaustion, on the log's own words

1. The kernel's health verdict names it: `compressor_exhausted: 1` with `swap_low: 0`, `swap_exhausted: 0`,
   `zone_map_is_exhausted: 0` (19:53:34.098, printed exactly once).
2. `memorystatus_available_pages` stayed at 1.05–1.08 M pages (16+ GB) through the entire storm — every kill
   line prints it. A free-RAM- or pressure-percentage-keyed monitor would have seen a healthy machine.
3. `compression_ratio=5` (kernel) ≈ 8,772,415 uncompressed / 1,610,185 compressed pages (JetsamEvent) — data
   was compressing fine; the segment pool (100 % of segments limit, 73 swapfiles) was the wall.
4. Panic header agrees: `33% of compressed pages limit (OK) and 100% of segments limit (BAD)`.

## 6. The instrument-death cascade (why the last 105 s are dark)

| Layer | Last sign of life |
|---|---|
| Kernel memory channel | 19:59:34.992 |
| WindowServer | 19:59:33.083 (render fence/batch timeouts) |
| launchd / any userspace via logd | 19:59:36.655 |
| watchdogd's own log | 19:58:39.614 |
| watchdogd kernel checkin | ~19:59:50 (panic − 93 s) |
| Panic | 20:01:23 |

Consequence for any log-watching guard: the actionable window closed ~19:59; detection had to happen between
19:49:51 (metronome) or 19:53:34 (unambiguous kernel verdict) and roughly 19:58. Userspace was still fully
functional in that window — daemons were spawning, syspolicyd was assessing them, logd was persisting ~3 k
lines/s.

## 7. Shutdown-cause history for the 8 reboots

Structural findings first:

- **macOS 15 / Apple Silicon writes no "previous shutdown cause" line to the unified log.** Both retained boots
  (Aug 13, Aug 24 — the latter a *known* panic) show zero matches for `"shutdown cause"`; the only hits in the
  entire retained log are this investigation's own `log` invocations (argv echo). The Intel/SMC-era numeric
  code (−20 watchdog / 5 clean / 3 hard-power) is simply not emitted here.
- **Unified-log retention on this box starts at the Aug 13 22:42 boot.** Control: kernel-line counts in the
  first 2 min after each reboot — Jul 30, Jul 31 ×2, Aug 5, Aug 9 ×2: **0 lines each**; Aug 13: 3,336;
  Aug 24: 79,135. Even Aug 13's pre-boot window (22:20–22:41:59) is empty, and its early-boot chunk is itself
  partially aged (3,336 vs 79,135 lines) — so gap-analysis for the Aug 13 reboot is impossible too.
- pmset -g log retains only from Aug 17 20:22 and contains no shutdown-cause records on this platform.
- Apple Silicon's actual cause records: `ResetCounter-*.diag` ("Boot faults") and the `.panic` file — present
  only for the latest event; `/Library/Logs/DiagnosticReports/Retired/` is empty, so earlier panic artifacts
  are gone from disk (prior panics are documented in the repo instead).

| # | Reboot | Cause per unified log | Cause per other evidence |
|---|---|---|---|
| 1 | Jul 30 02:18 | unknowable (no retention) | Panic #1, documented in repo (context: 2026-07-30 watchdog/compressor panic) |
| 2 | Jul 31 11:46 | unknowable | undetermined |
| 3 | Jul 31 18:13 | unknowable | undetermined |
| 4 | Aug 5 00:19 | unknowable | Panic #2, documented in repo (2026-08-05 00:18 compressor-segment panic) |
| 5 | Aug 9 03:39 | unknowable | ~Aug 9 "4th watchdog panic — dev-worker memory storms" documented in repo; which of the two Aug 9 reboots was the panic is not recoverable from logs |
| 6 | Aug 9 04:18 | unknowable | undetermined (39 min after #5 — plausibly recovery/manual) |
| 7 | Aug 13 22:42 | **indeterminate** — no pre-boot data, partial boot chunk, no "panic" mentions in what survives, no surviving .ips | no artifact either way |
| 8 | Aug 24 20:02 | full in-log death spiral (this doc) | **PROVEN watchdog reset**: ResetCounter `Boot faults: wdog,reset_in1`; panic-base+socd file; panic string (watchdog timeout, 93 s) |

So: of 8 reboots, **4 are confirmed crashes** (Jul 30, Aug 5, ~Aug 9, Aug 24 — the first three via repo
documentation, the last via on-disk artifacts + the log), 3 are undetermined (Jul 31 ×2, Aug 9 04:18), and 1
(Aug 13) is undetermined with all log evidence aged out. The unified log alone can confirm exactly one.

## 8. The 11:26 JetsamEvent vs the 19:55 one — different species

- **11:26:56–58**: two `killing_specific_process` per-process-limit kills (fatal 20 MB / 15 MB caps on
  IntelligencePlatformComputeServi and knowledgeconstructiond) at `memorystatus_available_pages: 3,070,877`
  (~46.9 GB). No pressure transition, no sweep, no other kernel memory events for minutes on either side.
  "Recovery" required nothing; the .ips (526 KB) is bookkeeping for a routine cap enforcement.
- **19:55:24**: the real thing — written mid-storm between the 19:53–54 main massacre and the 19:56 metronome,
  2.7 MB, free = 3,838 pages, largestProcess WindowServer.

## 9. Implications this axis contributes to the guard question (panic #5 despite a shipped guard)

1. **The kernel gave one unambiguous, greppable verdict** (`System is unhealthy` + `compressor_exhausted`)
   at 19:53:34 — 7 m 49 s before the panic — and an 8-minute prodrome before that (the 19:49:51 metronome).
   The afternoon tremor (15:04, 134 kills) preceded the panic by 4.7 h.
2. **Free-memory/pressure-keyed detection is the wrong key for this panic class**: 16.4 GB
   `memorystatus_available_pages` throughout. The correct keys visible in the log: segment count
   (`compressor_size` ≥ ~1.6 M), swapfile count (73), the unhealthy line, the metronome cadence.
3. **After ~19:58 no userspace remedy could run reliably**; after 19:59:36 nothing could even log. A guard must
   fire minutes early, not seconds.
4. **Jetsam cannot save this machine**: its entire arsenal reclaimed 8.43 GB of daemons while ~60 browser
   renderers (Browser Helper/Chrome Helper) sat unkillable and `killing_top_process` was never invoked. Any
   effective in-window action must target the big holders directly (or prevent the segment pool from filling).

## 10. Limits and refuters

- Per-process memory attribution is NOT in this axis: skip counts prove who was *unkillable*, not who held the
  24.6 GB compressor footprint. The 19:55 JetsamEvent .ips body (per-process pages) is the store that can
  confirm/refute the renderer-holders inference.
- watchdogd's 19:58:39 log stop vs ~19:59:50 last checkin: the gap could be logd loss rather than watchdogd
  stall; the panic string's 93 s figure is the authoritative endpoint either way.
- The Aug 13 verdict "indeterminate" would flip if a .logarchive snapshot or repo note covering that reboot
  exists elsewhere.
- Repo-documented panic dates (Jul 30, Aug 5, ~Aug 9) were taken from the task context as given facts; if the
  repo dates them differently, the 4-of-8-crash tally shifts.
