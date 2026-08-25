# Adversarial verification — 2026-08-24 20:01:23 watchdog panic (panic #5)

Verifier: independent re-read of PRIMARY artifacts only (JetsamEvent .ips files, the .panic file,
ResetCounter .diag, live sysctls, the sentinel's own JSONL/snap logs, the guard's source, the
unified log, reso checkouts, team-session state). Analysis files by the claimant agents were NOT
used as evidence. Verdict: **CONFIRMED, with detail-level corrections** (listed at the end).

## 1. The panic itself — confirmed verbatim

`/Library/Logs/DiagnosticReports/panic-base+socd-2026-08-24-200410.000.panic`:

- `panic(cpu 3 caller 0xfffffe002a24434c): watchdog timeout: no checkins from watchdogd in 93
  seconds (16763 total checkins since monitoring last enabled)`
- `Compressor Info: 33% of compressed pages limit (OK) and 100% of segments limit (BAD) with 73
  swapfiles and OK swap space`
- Thread table: exactly **3 kernel_task threads at pri 91** — cpu_usage 3,007,781 / 2,150,087 /
  2,143,006, the three busiest threads in the whole table (claim: "pegs three kernel_task threads
  at pri 91" — exact).
- `otherString`: `** Stackshot Incomplete ** Bytes Filled 240, err 52 **` (claim: "even the
  stackshot fails (err 52)" — exact).
- `ResetCounter-2026-08-24-200414.diag`: `Boot faults: wdog,reset_in1` — exact.
- 20:01:23 − 93 s = 19:59:50 = "watchdogd's last kernel checkin ~19:59:50" (arithmetic, consistent).

Live sysctls (same hardware, post-reboot): `vm.compressor_segment_limit: 1629615` — the claimed
1,629,615-slot pool is the kernel's own constant. `vm.compressor_segment_pages_compressed_limit:
26073840` → 16 compressed pages per segment; 33% of the pages limit spread over 100% of segments
= 26,073,840 × 0.33 ÷ 1,629,615 ≈ **5.3 pages per 16-page segment** — the claimed "thrash
fragmentation ~5.4/16" is the panic header's own arithmetic. Segment exhaustion at only 33% of
pages limit = fragmentation, as claimed.

## 2. The before/after portrait — confirmed from both JetsamEvent files

Parsed `JetsamEvent-2026-08-24-195524.ips` (4,477 processes) and `-112657.ips` (955 processes),
page size 16,384:

| | 11:26:57 | 19:55:24 | claim |
|---|---|---|---|
| node process count | **22** | **747** | 22 → 747 ✓ |
| node rpages | **4.0 GB** | **128.4 GB** | 4.0 → 128.4 GB ✓ |
| node compressed share of internal | 9.0% | **93.3%** | "93% compressed" ✓ |
| free pages | 286,031 | **3,838 (~60 MB)** | "free 60MB" ✓ |
| largestZone | data.kalloc.1024 = 9.53 GB | data.kalloc.1024 = **9.89 GB** | "~9.5GB" ≈ ✓ |
| wired | 942,185 pg | 1,389,270 pg = **21.2 GiB** | "21.2GB total wired" ✓ |
| compressorSize | 66,897 pg | 1,610,185 pg (~24.6 GB) | ✓ |

- Node priorities at 19:55: **746 of 747 at priority 180** (1 at 40) — "the holders sit
  band-protected at priority 180" ✓.
- pid **42897** present: name `node`, rpages 92,300 (1.5 GB), internal [10,359, 81,369],
  priority 180, states [active].
- pid **39672 NOT present** at 19:55:24 (see correction 7).
- Browser renderers: 41 × "Browser Helper (Renderer)" + 11 × "Google Chrome Helper (Renderer)"
  + 7 × "Browser Helper" ≈ **59-60** — the "~60 unkillable browser renderers" ✓.
- The snapshot's compressorSize (1,610,185) matches the 19:53:34.098 kernel log's
  `compressor_size:1610187` to ±2 pages → the report was indeed captured starting at the
  19:53:34 event, as the claim states ("captured ~19:53:34-19:55:0x").

## 3. The sentinel's own record — the claimed timeline is digit-for-digit real

`~/.claude/logs/compressor-sentinel.jsonl` (survived the reboot; rows are UTC = PDT+7):

```
02:49:22 pct 7.21  n=17                       ← quiet baseline
02:49:50 pct 7.21  n=166 nrss=23,648MB crate=88,756,259 B/s   ← wave 1 ignition
02:50:03 pct 36.75 srate 17,190/s             ← TRIP 1 (claim: 19:50:03 @36.75% ✓)
02:52:02 pct 77.42 el=121s                    ← tick stretched to 121 s ✓
02:52:14 pct 78.14 swap 56.2GB                ← TRIP 2 (claim: 78%, 56GB, 19:52:14 ✓)
02:55:02 pct 32.49 el=146s                    ← tick stretched to 146 s ✓
02:55:16 pct 8.38  swap 5.9GB n=18 nrss=589MB ← collapse 78→8%, mass exit ✓
02:56:27 pct 18.5  crate=925,737,305 B/s el=23 ← wave 2: +21.3 GB in 23 s ✓
02:56:43 pct 43.66 n=427 nrss=29,338MB        ← TRIP 3 @43.66% ✓
02:57:54 pct 71.81 srate 536.2                ← THE FATAL RELEASE TICK ✓
02:58:54 pct 82.68 swap 61.7GB n=672(census)  ← last row ever written ✓
```

`compressor-sentinel-snap.log` (last write 19:59):

- `═══ TRIP 2026-08-25T02:50:03Z why=seg+cbu+swap ═══` — top row of its argv table:
  `42897 42856 715792 65.0 next-server (v16.2.6)`; its children:
  `node /Users/chrisren/Development/reso-qa-runner/.next/dev/build/postcss.js NNNNN` (PPID 42897).
  Actuation: `SIGSTOP parent pid=42897 kids=249 comm=next-server_(v16.2.6)` → claim "SIGSTOPs
  42897 + 249 workers" ✓.
- TRIP 2 (02:52:14): `SIGSTOP parent pid=42897 kids=57`, `freeze debt 308 pid(s)` → claim
  "freezes 57 more; debt 308" ✓.
- Releases: batch 1 `released=184 held=108 stale=16` with **held_s 60-116** (claim ✓ for this
  batch); batch 2 `released=108` with held_s 159-205 (see correction 4).
- TRIP 3 (02:56:43): `SIGSTOP parent pid=39672 kids=58 comm=next-server_(v16.2.6)`, debt 59 ✓.
- **The fatal release** (02:57:54 tick): `SIGCONT pid=39672 held_s=68 kind=parent
  comm=next-server_(v16.2.6)` + 36 worker SIGCONTs, `release mode=clear released=37 held=22` —
  claim "SIGCONTs spawner 39672 (held 68s) + 37 workers" ✓ (37 = spawner + 36 workers).
- TRIP 4: `═══ TRIP 2026-08-25T02:58:54Z why=seg+swap ═══  segments 1347363 of 1629615 (82.68%)`.
  Its aggregate reads `39942.8 MB x713 node` (source of the claim's "n 427->713 / 39.9GB").
  **No SIGSTOP / actuator line exists anywhere after this header** — the file ends in the trip
  snapshot's vm_stat (free 4,096 pages = 67 MB). Claim "TRIP 4 writes its snapshot but no
  actuation reaches disk" ✓.

## 4. The guard's design flaw — real in the code, and it fired

`scripts/compressor-sentinel.sh` (repo; launchd job com.claude.compressor-sentinel):

- Trip predicate (`classify_breach`): seg arm = `seg > lim×15% AND rate > 600/s` (level AND rate).
- Release arm (main loop): `if [ -z "$WHY" ]; then RELMODE=clear` — i.e. **"breach over" is the
  single-tick negation of the same AND'd predicate**, and clear-mode releases everything held
  ≥ HOLD_MIN_S=60. At 02:57:54 the machine sat at **71.81% of the segment limit** but srate read
  536.2 < 600 (swapout lull) and crate/wrate were under their arms → WHY empty → clear →
  the still-loaded spawner and cohort were resumed into a 72%-full compressor. The claimed
  mechanism is exactly what the shipped code does, and the log shows it doing it.
- The re-minted pool then drove 82.68% (+ swap 61.7 GB) within 60 s; TRIP 4's actuation never
  reached disk (ticks already stretched 12×); the kernel hit 100% of segments before any
  further sentinel action. Panic header records the end state.

## 5. Kernel/system terminal sequence — unified log (crashed boot persisted store)

- `19:53:34.098 kernel: memorystatus: System is unhealthy. memorystatus_available_pages: 1072819`
  (= 17.6 GB ≈ claim "16.4GB still available" in GiB) and
  `{"compressor_exhausted": 1, "zone_map_is_exhausted": 0, ...}` — exact, plus
  `triggering no paging space action` the same instant.
- Kills 19:49-20:00: 5,446 raw "killing" lines; unique (pid,name) pairs ≈ **2,740**; raw lines
  run almost exactly 2× the claim's figures (3,459 lines in 19:53:34-19:55:24 vs claimed 1,663
  kills; 1,775 lines in 19:59 vs claimed 877) → the claim's numbers are deduplicated kill
  counts, consistent with the store. **Zero** killed names match node/claude/next/postcss —
  "zero fleet members" ✓ (the fleet sat in the priority-180 band; jetsam harvested idle daemons:
  killing_idle_process 2,719, killing_highwater 21).
- Skips: **87,153** "idle but not idle-exitable" lines in 19:50-20:00 (claim 87,152 — boundary
  off-by-one), dominated by Browser Helper (Renderer) 46,208 + Google Chrome Helper (Renderer)
  15,579 → "mostly on ~60 unkillable browser renderers" ✓.
- `19:58:39.614` — watchdogd's last log line ever ✓ ("log dies 19:58:39").
- `19:59:32.583 WindowServer [com.apple.coreanimation:Render] timed out fence` (+ timed out
  batch 19:59:33) ✓.
- Last persisted line of the boot: `19:59:36.655` (launchd, iconservicesagent spawn) — exact to
  the millisecond ✓.
- Log rate: 70,927 lines in 19:59:00-36 ≈ 1,970 lines/s average (claim "~3,000/s" — same order,
  see correction 3).

## 6. The standing generator and its never-applied fix — confirmed

- Both spawners are **`next-server (v16.2.6)`** by their own process titles (sentinel argv +
  comm), children `postcss.js` under `~/Development/reso-qa-runner/.next/dev/build/` — the
  postcss worker pool of Next.js turbopack's process_pool, the same class as Aug-9.
- `~/Development/reso-qa-runner/package.json`: name **reso-management-app**, next **16.2.6**
  (a reso clone pinned at the indicted version; reso-management-app proper is on next 16.3.0).
  `grep -c turbopackPluginRuntimeStrategy next.config.js` = **0 in both checkouts** — the named
  fix is absent where it matters ✓.
- `docs/research/crash-rootcause-2026-08-09.md` row 5 + W11: indicts `next-server (v16.2.6)`
  pid 36923 postcss workers (700 procs) for the Aug-9 03:39 panic; names the exact remedy
  "`experimental.turbopackPluginRuntimeStrategy: 'workerThreads'` in reso's next.config" and
  the process_pool/mod.rs mechanism ✓.
- Task **#151** "Permanent fix: dev-worker memory storms panic the box (4th watchdog panic,
  Aug 9)" is **in_progress** on the live task board — filed Aug 9, 15 days ✓.
- Crash cluster: **25 node .ips crash reports across Aug 21-23** in the user's
  DiagnosticReports (burst 03:25-03:27 Aug 23; SIGSEGV children of node parents) — "dev-worker
  class churning unattended" is directionally supported (class identity of each crash not
  individually proven).

## 7. The driver — QA team session-6ee7e044, confirmed

- `~/.claude-tertiary/teams/session-6ee7e044/config.json`: team created epoch 1787625934 =
  **19:45:34 PDT**, lead `team-lead@session-6ee7e044`; member **reso-qa** joined 1787626038 =
  **19:47:18 PDT** — 2.5 minutes before wave-1 ignition (19:49:50).
- Both teammates' claude.exe processes (`--agent-id reso-qa@session-6ee7e044`,
  `--agent-id infra-nightly@session-6ee7e044`) appear in the sentinel's trip-time top-30 argv
  tables at TRIP 1 and TRIP 4, actively burning CPU during the storm.
- The causal step "the QA agents' activity is what made the dev server mint" is the one link
  that rests on temporal correlation + the Aug-9 mechanism analysis (mass invalidation →
  process_pool spawn burst) rather than on a direct artifact; given the 2.5-minute fuse and the
  workers being that team's QA app, it is the reasonable reading.

## 8. Chronic-base claims — mixed

- 73 swapfiles ✓ (panic header). data.kalloc.1024 largest zone in BOTH same-day snapshots,
  ratcheting 9.53 → 9.89 GB ✓; zoneMapSize 11.8 GB of 24.9 GB cap ✓.
- "vm-compressor-space-shortage jetsam kills every single day (78-487/day)": **not verifiable
  now** — the unified log has rotated (Aug 23 full-day query returns 0 kill lines; Aug 16/22
  return 0; store reaches back < ~1 day at kernel-Default level). Direction (chronic daily
  pressure) is supported by 245.7M lifetime compressions, 73 swapfiles, and two same-day
  JetsamEvents, but the specific per-day range could not be reproduced from any surviving store.
- "upstream claude-code#44824" as the kalloc.1024 attribution: appears in no repo doc I could
  find (only in session transcripts = testimony). The zone growth is real; the upstream-issue
  attribution is unverified.

## 9. Verdict

**CONFIRMED.** Every load-bearing element of the primary-cause claim is independently
reproducible from primary artifacts: the two-wave next-server (v16.2.6) postcss/dev-worker
storm under QA team session-6ee7e044 (22→747 node procs, 4.0→128.4 GB, 93.3% compressed,
746/747 at band 180), segment exhaustion by fragmentation (100% of 1,629,615 slots at 33% of
pages limit, ~5.3/16 pages per segment), the shipped guard detecting and freezing correctly but
releasing the spawner at 19:57:54 on a one-tick rate lull (srate 536 < 600 at 71.81% — the
release arm literally negates the AND'd trip predicate), the re-mint to 82.68%+61.7 GB swap with
TRIP 4's actuation never reaching disk, jetsam's futile idle-band harvest (thousands of kills,
zero fleet, 87k not-idle-exitable skips), and the userspace starvation sequence ending in
watchdogd silence 19:59:50 → panic 20:01:23. Corrections are magnitude/attribution details
that do not move the mechanism or the culprit.

## Corrections (detail level)

1. "= 85.9% of all process memory" mixes instruments: by the 19:55:24 jetsam ledger node is
   77.0% of all-process rpages (128.4/166.7 GB) and 78.3% of internal footprint (121.3/155.1 GB);
   85.9% corresponds to node's share of resident RSS in the sentinel's 19:58:54 ps aggregate
   (39.9 GB of ~46.5 GB). Node ANONYMOUS footprint at 19:55 is 121.3 GB (the "~126-134GB" range
   fits the rpages ledger, slightly overstates the anonymous figure).
2. The jetsam kill figures (1,663; 877) are deduplicated counts; the persisted store carries
   ~2× raw lines (3,459 in 19:53:34-19:55:24; 1,775 in 19:59:00-36). Direction unchanged; the
   "8.4GB reclaimed" sum was not independently verified.
3. Log-flood rate measured ~1,970 lines/s averaged over 19:59:00-36 (70,927 lines), not ~3,000/s
   (plausible as peak-second).
4. "clear-mode releases begin (all held_s 60-116)" is true of the first batch only
   (released=184, held_s 60-116); the second batch (released=108) held 159-205 s.
5. Chronic "78-487 vm-compressor-space-shortage kills every single day" could not be reproduced
   from any surviving store (unified log rotated; no sampler records kills) — unverified, though
   the chronic-pressure direction is well supported.
6. The kalloc.1024 attribution to "upstream claude-code#44824" exists only in transcripts, not
   in any repo doc or system artifact — the zone growth (9.53→9.89 GB, largest zone) is
   confirmed, the attribution is not.
7. Wave-2 spawner pid 39672 is ABSENT from the 19:55:24 jetsam snapshot: it is a second,
   distinct next-server whose birth/provenance is undocumented (fresh spawn or snapshot
   incompleteness); by 19:56:43 the sentinel proves it live with 58 postcss children.
8. The storming server ran from `~/Development/reso-qa-runner` (a reso-management-app clone
   pinned at next 16.2.6); reso-management-app proper is on next 16.3.0. The named fix is absent
   from BOTH next.config.js files, so the "verified absent from reso next.config.js" clause
   holds — but the operative checkout is the QA runner clone.
9. Last-sentinel-row worker count: the JSONL census field read n=672 at 02:58:54 while the same
   trip's ps aggregate read x713 (the claim's number); nrss census 39,043 MB vs aggregate
   39,942.8 MB ("39.9GB"). Both are artifact values from different instruments at the same tick.
