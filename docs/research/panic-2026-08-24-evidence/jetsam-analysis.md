# JetsamEvent forensics — 2026-08-24 watchdog panic (#5)

**Axis: who held the memory, and who was killed.** Sources: the two bug_type-298 (jetsam/memorystatus)
reports in `/Library/Logs/DiagnosticReports/`, parsed with `tail -n +2 FILE | jq`. Page size 16384 B;
GB figures are `rpages x 16384 / 1e9` (decimal) throughout. Analysis run ~20:15 PDT, 2026-08-24,
read-only. Intermediate TSVs + scripts sit beside this file in the scratchpad.

## Verdict (answer first)

**A fork storm of `node` processes inside the kitty-hosted Claude Code fleet allocated ~126 GB in
four minutes (19:51-19:55) and is what exhausted the VM compressor.** At 19:55:24 — six minutes
before the 20:01:23 watchdog panic — the box held **747 `node` processes totalling 128.40 GB
(85.9% of all process memory, 8.2M of 9.6M rpages)**; **731 of them had been spawned since 19:00,
and 728 of those within 19:51:00-19:55:24** (344 in the 19:51 minute alone). All 731 storm nodes
belong to **coalition 621 — the kitty coalition** (kitty pid 587 + 13 in-terminal `claude.exe`
sessions + the fleet's bash/zsh scaffolding), so the spawner is inside the terminal-hosted CC fleet,
not Cursor (coalition 65601), not Dia (69675), not launchd daemons. The population is homogeneous —
median 188 MB, p90 211 MB per process — i.e. ~730 copies of the same worker, and 93.3% of their
memory had already been squeezed into the compressor (119.4 GB of the fleet's 135.3 GB), which is
exactly the "100% of segments limit" the panic log records. Jetsam fought back the only way macOS
lets it: it killed **3,109 processes — every one of them an idle system daemon, zero fleet members**
(fleet and apps sat at jetsam priority 180/100, band-protected above the priority-0 idle band) —
reclaiming a useless **9.28 GB total across the whole 10.9-day uptime**, ~3 GB of it on Aug 24.
The 11:26 report is a different, routine event (one `per-process-limit` kill of Apple's
IntelligencePlatformComputeService) whose value here is the healthy baseline snapshot it carries:
22 node procs / 4.0 GB, compressor at 1.0 GB, 4.4 GB free.

## 1. Report inventory — ALL JetsamEvent files on the box

| file | size | event time | nature |
|---|---|---|---|
| `JetsamEvent-2026-08-24-112657.ips` | 526,174 B | Aug 24 11:26:57 | single `per-process-limit` kill + full process snapshot (954 survivors) |
| `JetsamEvent-2026-08-24-195524.ips` | 2,708,517 B | Aug 24 19:55:24 | accumulated kill ledger for the whole boot session (3,109 kills / 1,086 generations) + full snapshot (1,368 survivors) |

Searched `/Library/Logs/DiagnosticReports/` (including `Retired/` — empty of jetsam files) and
`~/Library/Logs/DiagnosticReports/` with `find -iname '*jetsam*'`: **these two files are the only
JetsamEvent reports that exist** — nothing else from Aug 13-24 or any other date. (Context from the
same directory: `ditto_2026-08-24-161720...diag` — a 2.9 MB resource diag on `ditto` at 16:17 the
same afternoon — and the 20:04 panic files.)

## 2. What each bug_type-298 event was FOR

A bug_type 298 .ips is a jetsam/memorystatus event report, not a crash of one process. The subject
is carried per-process: entries with a `reason` field are the kills; `genCount`-less entries are the
survivor snapshot at write time (pid overlap between the two sets: zero, verified).

- **11:26:57** — written FOR the kill of **`IntelligencePlatformComputeService` (pid 18566), reason
  `per-process-limit`**, 1,307 rpages (21 MB) at jetsam priority 0; `genCounter` 0, `timeDelta` 69.
  A process that exceeded its own memorystatus footprint limit — routine, not a system-pressure
  event. The system around it was healthy (see memoryStatus below).
- **19:55:24** — the accumulated pressure ledger, flushed six minutes before the panic. `genCounter`
  1086, `timeDelta` 38678. Kill reasons: **`vm-compressor-space-shortage` x 3,092** and
  `highwater` x 17. The newest recorded kill is 16 s before the write (19:55:08); the oldest maps to
  Aug 14 02:04 — 1.3 h after the Aug 13 22:42 boot — i.e. this file is the whole boot session's
  jetsam history, written out when the compressor hit terminal exhaustion. `largestProcess:
  "WindowServer"` names only the largest single process (1.61 GB, 1.0% of the total) — a red
  herring next to the fleet's aggregate.

## 3. memoryStatus, verbatim

### 19:55:24 (6 min pre-panic)

```json
"memoryStatus": {
  "compressorSize": 1610185,
  "compressions": 245704174,
  "decompressions": 197037922,
  "zoneMapCap": 24949260288,
  "largestZone": "data.kalloc.1024",
  "largestZoneSize": 9886433280,
  "pageSize": 16384,
  "uncompressed": 8772415,
  "zoneMapSize": 11828101120,
  "memoryPages": {
    "active": 535889,
    "throttled": 0,
    "fileBacked": 370714,
    "wired": 1389270,
    "anonymous": 699787,
    "purgeable": 0,
    "inactive": 534326,
    "free": 3838,
    "speculative": 286
  }
}
```

### 11:26:57 (healthy baseline)

```json
"memoryStatus": {
  "compressorSize": 66897,
  "compressions": 199737713,
  "decompressions": 165076000,
  "zoneMapCap": 24949260288,
  "largestZone": "data.kalloc.1024",
  "largestZoneSize": 9532801024,
  "pageSize": 16384,
  "uncompressed": 541772,
  "zoneMapSize": 11156815872,
  "memoryPages": {
    "active": 1409154,
    "throttled": 0,
    "fileBacked": 678387,
    "wired": 942185,
    "anonymous": 2138137,
    "purgeable": 8034,
    "inactive": 1369417,
    "free": 286031,
    "speculative": 37953
  }
}
```

### Read side by side (pages x 16384)

| metric | 11:26 | 19:55 | delta |
|---|---|---|---|
| compressor occupancy (RAM) | 1.10 GB | **26.38 GB** | x24 |
| uncompressed data held by compressor | 8.88 GB | **143.73 GB** | **+134.8 GB** |
| resident anonymous | 35.03 GB | 11.47 GB | -23.6 GB (squeezed into compressor) |
| free | 4.69 GB | **0.06 GB** | dead |
| wired | 15.44 GB | 22.76 GB | +7.3 GB (kernel under stress; zone map 11.16->11.83 GB, `data.kalloc.1024` at 9.89 GB) |
| active+inactive+speculative | 45.6 GB | 17.5 GB | working set crushed |

RAM reconciliation at 19:55: active+inactive+speculative+free+wired+compressorSize = 4,073,794
pages = 62.1 GiB ~= 64 GB physical. Checks out.
Survivor `rpages` sum = 9,608,594 pages = **157.4 GB**, vs compressor-held-uncompressed 143.7 GB +
resident anon 11.5 GB ~= 155 GB: `rpages` is phys_footprint (resident + compressed attributed at
uncompressed size), so the survivor tables below attribute the compressor's contents by owner. The
`resident/compressed pgs` columns are `physicalPages.internal[0]/[1]`.

## 4. Who held the memory

### Top 30 processes by rpages — 19:55:24 (6 min before panic)

| # | process | pid | class | rpages | GB | jetsam pri | states | resident pgs | compressed pgs |
|---|---------|-----|-------|--------|----|------------|--------|--------------|----------------|
| 1 | WindowServer | 380 | WindowServer | 97,995 | 1.61 | 170 | active | 6,923 | 13,577 |
| 2 | node | 42897 | claude/node fleet | 92,300 | 1.51 | 180 | active | 10,359 | 81,369 |
| 3 | kitty | 587 | terminals | 84,379 | 1.38 | 100 | active | 3,136 | 14,334 |
| 4 | Dia | 98016 | browsers | 49,214 | 0.81 | 100 | active | 11,848 | 34,777 |
| 5 | claude.exe | 91882 | claude/node fleet | 39,603 | 0.65 | 180 | active | 1,949 | 38,328 |
| 6 | Browser Helper | 143 | browsers | 36,760 | 0.60 | 180 | active | 256 | 9,090 |
| 7 | claude.exe | 29540 | claude/node fleet | 35,464 | 0.58 | 180 | active | 426 | 34,931 |
| 8 | claude.exe | 60323 | claude/node fleet | 32,825 | 0.54 | 180 | active | 3,082 | 29,670 |
| 9 | node | 55127 | claude/node fleet | 30,506 | 0.50 | 180 | active | 71 | 28,481 |
| 10 | Browser Helper (Renderer) | 59620 | browsers | 30,325 | 0.50 | 0 | idle | 1,047 | 29,179 |
| 11 | claude.exe | 57788 | claude/node fleet | 30,229 | 0.50 | 180 | active | 2,672 | 27,483 |
| 12 | Browser Helper (Renderer) | 34751 | browsers | 30,122 | 0.49 | 180 | active | 9,745 | 20,409 |
| 13 | Browser Helper (Renderer) | 92640 | browsers | 30,075 | 0.49 | 180 | active | 9,231 | 20,744 |
| 14 | claude.exe | 12355 | claude/node fleet | 28,918 | 0.47 | 180 | active | 3,170 | 25,681 |
| 15 | Browser Helper (Renderer) | 25897 | browsers | 27,221 | 0.45 | 180 | active | 10,527 | 16,564 |
| 16 | claude.exe | 61612 | claude/node fleet | 26,640 | 0.44 | 180 | active | 3,486 | 23,086 |
| 17 | Browser Helper | 440 | browsers | 26,498 | 0.43 | 180 | active | 308 | 10,988 |
| 18 | claude.exe | 91821 | claude/node fleet | 26,114 | 0.43 | 180 | active | 5,547 | 20,503 |
| 19 | node | 55839 | claude/node fleet | 26,003 | 0.43 | 180 | active | 217 | 24,032 |
| 20 | claude.exe | 4730 | claude/node fleet | 25,971 | 0.43 | 180 | active | 4,470 | 21,433 |
| 21 | Cursor Helper (Renderer) | 77824 | Electron apps | 24,470 | 0.40 | 180 | active | 1,817 | 22,558 |
| 22 | claude.exe | 7485 | claude/node fleet | 24,115 | 0.40 | 180 | active | 3,313 | 20,734 |
| 23 | Browser Helper (Renderer) | 94178 | browsers | 23,475 | 0.38 | 180 | active | 179 | 23,182 |
| 24 | claude.exe | 44520 | claude/node fleet | 22,661 | 0.37 | 180 | active | 2,568 | 20,026 |
| 25 | claude.exe | 21808 | claude/node fleet | 22,602 | 0.37 | 180 | active | 376 | 22,162 |
| 26 | claude.exe | 21952 | claude/node fleet | 22,411 | 0.37 | 180 | active | 4,913 | 17,431 |
| 27 | claude.exe | 33802 | claude/node fleet | 22,312 | 0.37 | 180 | active | 2,039 | 20,215 |
| 28 | Finder | 850 | system/other | 21,862 | 0.36 | 100 | active | 631 | 18,970 |
| 29 | VTDecoderXPCService | 862 | system/other | 21,796 | 0.36 | 40 | active | 238 | 1,167 |
| 30 | Browser Helper (Renderer) | 74307 | browsers | 21,308 | 0.35 | 180 | active | 189 | 21,026 |

### Top 30 processes by rpages — 11:26:57 (healthy morning baseline)

| # | process | pid | class | rpages | GB | jetsam pri | states | resident pgs | compressed pgs |
|---|---------|-----|-------|--------|----|------------|--------|--------------|----------------|
| 1 | WindowServer | 380 | WindowServer | 91,957 | 1.51 | 170 | active | 15,170 | 5,529 |
| 2 | kitty | 587 | terminals | 84,866 | 1.39 | 100 | active | 12,768 | 2,956 |
| 3 | node | 77131 | claude/node fleet | 65,723 | 1.08 | 180 | active | 62,475 | 0 |
| 4 | mediaanalysisd | 77330 | system/other | 44,345 | 0.73 | 40 | active | 33,922 | 257 |
| 5 | Browser Helper | 143 | browsers | 42,114 | 0.69 | 180 | active | 8,009 | 0 |
| 6 | node | 18711 | claude/node fleet | 38,959 | 0.64 | 180 | active | 37,152 | 0 |
| 7 | Dia | 98016 | browsers | 37,668 | 0.62 | 100 | active | 35,584 | 0 |
| 8 | claude.exe | 29540 | claude/node fleet | 35,366 | 0.58 | 180 | active | 20,945 | 14,314 |
| 9 | claude.exe | 91882 | claude/node fleet | 32,512 | 0.53 | 180 | active | 22,700 | 10,278 |
| 10 | claude.exe | 60323 | claude/node fleet | 29,475 | 0.48 | 180 | active | 24,135 | 5,264 |
| 11 | Browser Helper (Renderer) | 14099 | browsers | 28,580 | 0.47 | 180 | active | 28,482 | 0 |
| 12 | VTDecoderXPCService | 862 | system/other | 27,588 | 0.45 | 40 | active | 588 | 629 |
| 13 | Browser Helper (Renderer) | 12863 | browsers | 27,215 | 0.45 | 180 | active | 27,042 | 0 |
| 14 | Browser Helper | 440 | browsers | 26,314 | 0.43 | 180 | active | 11,205 | 0 |
| 15 | claude.exe | 57788 | claude/node fleet | 26,143 | 0.43 | 180 | active | 23,357 | 2,713 |
| 16 | Cursor Helper (Renderer) | 77824 | Electron apps | 25,278 | 0.41 | 180 | active | 19,713 | 5,470 |
| 17 | node | 19043 | claude/node fleet | 24,806 | 0.41 | 180 | active | 22,874 | 0 |
| 18 | claude.exe | 12355 | claude/node fleet | 23,273 | 0.38 | 180 | active | 20,768 | 2,435 |
| 19 | Finder | 850 | system/other | 22,630 | 0.37 | 100 | active | 11,702 | 8,421 |
| 20 | smd | 311 | system/other | 22,619 | 0.37 | 0 | idle | 1,508 | 21,085 |
| 21 | claude.exe | 21808 | claude/node fleet | 22,260 | 0.36 | 180 | active | 16,550 | 5,646 |
| 22 | claude.exe | 44520 | claude/node fleet | 22,228 | 0.36 | 180 | active | 16,958 | 5,203 |
| 23 | claude.exe | 21952 | claude/node fleet | 22,022 | 0.36 | 180 | active | 16,594 | 5,361 |
| 24 | Browser Helper (Renderer) | 44846 | browsers | 21,361 | 0.35 | 180 | active | 21,189 | 0 |
| 25 | node | 36098 | claude/node fleet | 20,153 | 0.33 | 180 | active | 18,970 | 0 |
| 26 | Cursor Helper (Plugin) | 78185 | Electron apps | 17,290 | 0.28 | 180 | active | 11,799 | 5,408 |
| 27 | soffice | 762 | system/other | 16,630 | 0.27 | 0 | idle | 1,827 | 12,391 |
| 28 | AdobeResourceSynchronizer | 1106 | system/other | 16,216 | 0.27 | 100 | active | 5,471 | 10,696 |
| 29 | claude.exe | 683 | claude/node fleet | 14,970 | 0.25 | 180 | active | 14,901 | 0 |
| 30 | claude.exe | 4730 | claude/node fleet | 14,953 | 0.24 | 180 | active | 14,885 | 0 |

### Class totals — 19:55:24

| class | procs | rpages | GB | % of total | resident GB | compressed GB |
|-------|-------|--------|----|------------|-------------|---------------|
| claude/node fleet | 765 | 8,256,910 | 135.28 | 85.9% | 8.83 | 119.39 |
| browsers | 74 | 610,727 | 10.01 | 6.4% | 1.14 | 7.94 |
| system/other | 322 | 392,489 | 6.43 | 4.1% | 0.62 | 5.40 |
| Electron apps | 20 | 109,972 | 1.80 | 1.1% | 0.13 | 1.57 |
| WindowServer | 1 | 97,995 | 1.61 | 1.0% | 0.11 | 0.22 |
| terminals | 2 | 84,701 | 1.39 | 0.9% | 0.05 | 0.24 |
| fleet shell scaffolding | 184 | 55,800 | 0.91 | 0.6% | 0.04 | 0.83 |
| **TOTAL** | 1368 | 9,608,594 | 157.43 | 100% | | |

### Class totals — 11:26:57

| class | procs | rpages | GB | % of total | resident GB | compressed GB |
|-------|-------|--------|----|------------|-------------|---------------|
| system/other | 690 | 683,596 | 11.20 | 33.6% | 5.49 | 5.00 |
| claude/node fleet | 37 | 551,537 | 9.04 | 27.1% | 7.57 | 1.18 |
| browsers | 70 | 477,905 | 7.83 | 23.5% | 6.76 | 0.03 |
| Electron apps | 18 | 102,190 | 1.67 | 5.0% | 1.17 | 0.42 |
| WindowServer | 1 | 91,957 | 1.51 | 4.5% | 0.25 | 0.09 |
| terminals | 2 | 85,188 | 1.40 | 4.2% | 0.21 | 0.05 |
| fleet shell scaffolding | 136 | 39,231 | 0.64 | 1.9% | 0.31 | 0.29 |
| **TOTAL** | 954 | 2,031,604 | 33.29 | 100% | | |

### Class delta 11:26 -> 19:55

| class | procs 11:26 | procs 19:55 | dProc | GB 11:26 | GB 19:55 | dGB |
|-------|-------------|-------------|-------|----------|----------|-----|
| claude/node fleet | 37 | 765 | +728 | 9.04 | 135.28 | +126.24 |
| browsers | 70 | 74 | +4 | 7.83 | 10.01 | +2.18 |
| fleet shell scaffolding | 136 | 184 | +48 | 0.64 | 0.91 | +0.27 |
| Electron apps | 18 | 20 | +2 | 1.67 | 1.80 | +0.13 |
| WindowServer | 1 | 1 | +0 | 1.51 | 1.61 | +0.10 |
| terminals | 2 | 2 | +0 | 1.40 | 1.39 | -0.01 |
| system/other | 690 | 322 | -368 | 11.20 | 6.43 | -4.77 |

### Biggest movers by process name (sum rpages), 11:26 -> 19:55

| name | n 11:26 | n 19:55 | GB 11:26 | GB 19:55 | dGB |
|------|---------|---------|----------|----------|-----|
| node | 22 | 747 | 4.02 | 128.40 | +124.37 |
| claude.exe | 13 | 16 | 4.69 | 6.83 | +2.14 |
| Browser Helper (Renderer) | 37 | 41 | 4.66 | 6.73 | +2.07 |
| mediaanalysisd | 1 | 0 | 0.73 | 0.00 | -0.73 |
| smd | 1 | 0 | 0.37 | 0.00 | -0.37 |
| Cursor Helper (Plugin) | 8 | 4 | 0.77 | 0.43 | -0.33 |
| esbuild | 2 | 2 | 0.32 | 0.05 | -0.27 |
| WiFiAgent | 1 | 0 | 0.23 | 0.00 | -0.23 |
| Signal Helper (Renderer) | 0 | 1 | 0.00 | 0.22 | +0.22 |
| Signal | 0 | 1 | 0.00 | 0.20 | +0.20 |
| textunderstandingd | 1 | 0 | 0.19 | 0.00 | -0.19 |
| Dia | 1 | 1 | 0.62 | 0.81 | +0.19 |
| bash | 57 | 94 | 0.16 | 0.34 | +0.18 |
| VTDecoderXPCService | 4 | 1 | 0.46 | 0.36 | -0.11 |
| WindowServer | 1 | 1 | 1.51 | 1.61 | +0.10 |
| Signal Helper | 0 | 4 | 0.00 | 0.10 | +0.10 |
| syspolicyd | 1 | 0 | 0.10 | 0.00 | -0.10 |
| Creative Cloud Content Manager.n | 1 | 1 | 0.23 | 0.14 | -0.09 |
| Calendar | 0 | 1 | 0.00 | 0.08 | +0.08 |
| Browser Helper | 7 | 7 | 1.29 | 1.22 | -0.07 |

### node fleet forensics

- node procs 11:26: **22** (sum 4.02 GB) -> 19:55: **747** (sum 128.40 GB)
- of the 747 node procs at 19:55: **738 have pids NOT present at 11:26** (new or pid-recycled), holding 127.61 GB; 8 same-pid survivors grew -0.06 GB
- node rpages distribution 19:55: min 607 / median 11,454 / p90 12,864 / max 92,300 pages (median 0.188 GB, max 1.51 GB)
- node aggregate split 19:55: resident 8.10 GB vs compressed 113.25 GB (93.3% of node anon sits in the compressor)
- node states 19:55: 747 'active', 0 idle/other; priorities: [('180', 746), ('40', 1)]

- claude.exe procs: 13 (4.69 GB) -> 16 (6.83 GB)

## 5. The storm, at minute resolution

Every survivor entry carries `age`; between-report deltas on long-lived anchors (WindowServer,
kitty) date it as Mach ticks at ~24 MHz (agreement 0.4%). Spawn time = 19:55:24 - age/24e6:

| spawn minute (Aug 24) | node procs | GB held at 19:55 |
|---|---|---|
| 19:47 | 1 | 0.08 |
| 19:49 | 2 | 0.16 |
| **19:51** | **344** | **67.63** |
| **19:52** | **131** | **26.21** |
| **19:54** | **215** | **30.65** |
| 19:55 (to :24) | 38 | 1.48 |

728 processes / ~126 GB in 4.5 minutes; two bursts (19:51-52, 19:54) with a quiet 19:53. The
largest single node (pid 42897, 1.51 GB) was 4.1 minutes old at snapshot; at 11:26 the same
signature existed in miniature — node pid 77131 was 8.5 s old holding 1.08 GB, all-resident.
The remaining 16 of 747: 8 predate 11:26 (the survivors of the morning's 22), 8 spawned
11:00-18:00. **Sessions did not multiply — workers did**: `claude.exe` went 13 -> 16 while `node`
went 22 -> 747.

### Coalition attribution (the spawner's neighborhood)

All 731 storm nodes share **coalition 621**, whose other members are: kitty (pid 587), kitten x2,
zsh x24, bash x59, tee x11, gitstatusd x12, **claude.exe x13**, and 6 Google Chrome Helper
(Renderer) procs (fleet browser automation). Cursor is coalition 65601, Dia 69675, WindowServer
347, launchd 3 — none contributed a storm node. Jetsam records no argv/ppid, so the report cannot
name WHICH member forked them; it proves the storm ran under the kitty-hosted CC fleet.

## 6. Kill timeline

### When were the 747 node processes spawned? (age in Mach ticks / 24MHz, relative to 19:55:24)

| spawn hour | nodes spawned | their rpages GB (at 19:55) |
|-----------|---------------|-----------------------------|
| Aug 19 17:00 | 1 | 0.08 |
| Aug 23 13:00 | 1 | 0.08 |
| Aug 23 16:00 | 2 | 0.15 |
| Aug 23 19:00 | 1 | 0.08 |
| Aug 24 01:00 | 1 | 0.08 |
| Aug 24 02:00 | 1 | 0.08 |
| Aug 24 03:00 | 1 | 0.08 |
| Aug 24 11:00 | 5 | 1.34 |
| Aug 24 12:00 | 1 | 0.08 |
| Aug 24 15:00 | 1 | 0.04 |
| Aug 24 18:00 | 1 | 0.08 |
| Aug 24 19:00 | 731 | 126.21 |

- node procs older than the 11:26 report (age > 8h28m): **8** — cross-checks the 738-new-pids figure

### Jetsam kill timeline (killDelta read as ms-before-report; direction inferred, see caveat)

| day | kills | of them compressor-space | reclaimed GB |
|-----|-------|--------------------------|--------------|
| Aug 14 | 280 | 280 | 0.59 |
| Aug 15 | 356 | 355 | 0.66 |
| Aug 16 | 487 | 487 | 0.76 |
| Aug 17 | 380 | 380 | 0.72 |
| Aug 18 | 446 | 445 | 0.91 |
| Aug 19 | 406 | 406 | 0.69 |
| Aug 20 | 220 | 219 | 0.63 |
| Aug 21 | 143 | 143 | 0.44 |
| Aug 22 | 115 | 115 | 0.50 |
| Aug 23 | 78 | 77 | 0.37 |
| Aug 24 | 198 | 185 | 3.01 |

Aug 24 kills by hour: 11:00=2, 12:00=60, 13:00=46, 14:00=31, 15:00=23, 16:00=19, 17:00=2, 19:00=15

- newest kill: Aug 24 19:55:08 (16s before report write); oldest: Aug 14 02:04:25 (1.3h after the Aug 13 22:42 boot)
## 7. Who was killed — census

- **3,109 kills, zero fleet members, zero apps.** Not one entry in the kill list is node,
  claude.exe, kitty, iTerm2, Cursor*, Dia, Browser Helper*, Chrome*, or WindowServer (verified by
  name scan). The fleet sat at jetsam priority **180** with `active` state (746/747 nodes;
  claude.exe all 180) — above WindowServer (170) and far above the priority-0 idle band jetsam
  drains first. macOS jetsam therefore spent the whole event relaunch-killing idle Apple daemons.
- Top repeat victims (kill count over the uptime): sandboxd x239, amfid x229, online-auth-agent
  x203, com.apple.geod x182, com.apple.CodeSigningHelper x136, OSDUIHelper x112, trustd x98,
  keybagd x91, calaccessd x74, logd_helper x69 — launchd relaunches them, jetsam kills them again.
- Total reclaimed by all 3,109 kills: **566,479 rpages = 9.28 GB** — over 10.9 days. On Aug 24
  itself: 198 kills / 3.01 GB (largest single victim: mediaanalysisd, 13,205 rpages = 0.22 GB,
  killed ~19:03 — it had been 0.73 GB at 11:26). Against a 126 GB/4-minute storm this is not a
  control loop; it is noise.
- The 17 `highwater` kills (footprint-threshold reports, not pressure): amsengagementd, DockHelper,
  SoftwareUpdateNotificationManager, BiomeAgent, com.apple.amp.devicesui, syspolicyd,
  com.apple.dock.extra x5 (one per ~2 days — it regrows and re-trips), dock.external.extra x2,
  SafariPlatformSupport, siriinferenced, ControlCenterHelper, WiFiAgent (0.23 GB, ~19:14 Aug 24).
- **Chronic pressure all week**: compressor-space-shortage kills happened EVERY day of the boot
  session (280 on Aug 14, peaking 487 on Aug 16, still 78 on Aug 23) — consistent with the 73
  swapfiles the panic log records. The box lived near compressor limits for its entire 10.9-day
  uptime; Aug 24 19:51 was the acute overdose on a chronic patient.

## 8. Semantics and caveats (inferences labeled)

- **`rpages` = phys_footprint** (resident + compressed at uncompressed size): survivor sum 157.4 GB
  reconciles with memoryStatus (S3); per-process `physicalPages.internal = [resident, compressed]`
  (sums match rpages minus shared/IOKit).
- **`killDelta` = ms before report write** (so kill time = 19:55:24 - killDelta). Inferred, not
  documented: (a) it is monotone with `genCount` (gen 0 newest: 15.7 s .. 7.5 h; gen 1085: 10.74 d);
  (b) the since-boot reading is refuted by mediaanalysisd pid 77330 — alive in the 11:26 snapshot,
  killed in gen 0 — and by high pids (87xxx) on kills that reading would place minutes after boot.
  `genCount` on a kill = generations before the current one (0 = newest).
- **`age` = Mach ticks at ~24 MHz**: WindowServer/kitty deltas between the two independent reports
  match the 8h28m wall gap to 0.4%. Oddity kept honest: WindowServer/kitty ages put their start at
  ~Aug 14 07:40, ~9 h after the Aug 13 22:42 boot in the reboot history — either a login/WindowServer
  restart that morning or a boot-record subtlety; it does not affect the storm timing, which is
  minutes-scale and cross-validated.
- The 11:26 file proves the compressor was at 1.0 GB that morning: the fatal fill is entirely an
  afternoon/evening event, dominated by the 19:51-19:55 storm (+126 GB node) plus ~23 GB of existing
  resident anon squeezed compressor-ward.
- Jetsam reports carry no argv/ppid/cwd: "which script forked 344 node/minute" is answerable only
  from fleet-side logs (spawn logs, launchd, shell history), not from these files.

## 9. Implication for the shipped compressor-segment guard (timing fact only)

Whatever the guard's design, the window it had here was: **baseline-normal at 19:47, 67 GB
committed by 19:52, segments at 100% and free at 60 MB by ~19:55, watchdog dead at 20:01:23** — a
zero-to-fatal ramp of ~4 minutes at ~344 forks/min, during which the box was already too starved to
schedule much userspace. Any polling guard with a minutes-scale cadence, or one that acts by asking
a starving userspace to run something, structurally cannot catch this shape; prevention has to sit
at the spawn path (rate/count limit on the forker) or in kernel-enforced per-coalition/process
limits (the fleet's priority-180 band placement is itself part of why jetsam never touched the
actual owner).

## Appendix — reproduction one-liners

```
tail -n +2 JetsamEvent-2026-08-24-195524.ips | jq '.memoryStatus'
tail -n +2 ... | jq '[.processes[] | select(.genCount == null)] | sort_by(-.rpages) | .[0:30]'
tail -n +2 ... | jq '[.processes[] | select(.reason != null) | .reason] | group_by(.) | map({r: .[0], n: length})'
# survivors=1368 (no reason field), kills=3109 (reason field), pid overlap 0
```
