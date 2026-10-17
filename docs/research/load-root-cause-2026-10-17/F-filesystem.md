# F — filesystem / kernel contention (2026-10-17)

**Verdict.** The largest filesystem-side term is a fault, not a workload. `fseventsd` is
**livelocked again**: one thread spinning in user space, no FSEvents delivered, and a queue that has
grown from 48 MB to **11 GB footprint** since **2026-10-16 17:16-17:21 CDT**. This is the third
recorded episode (2026-09-08 livelock, 2026-10-04 64 GB bloat, now). The root watchdog that exists
for it (`com.claude.fseventsd-watchdog`) only restarts at **16 GB**, so it has let the fault run for
9.5 h so far, and at the measured growth rate it will run for roughly 13 h in total.

Behind that fault are two structural terms:
- **vnode-cache thrash.** `kern.maxvnodes` is clipped at the 16 GB sizing on a 64 GB machine. The
  cache recycles **13.8k vnodes/s**, so the whole table turns over about every 19 s.
- **Small-block metadata I/O.** About 9.6k IOPS at about 11 KB per transfer, with no swap traffic in
  the sample.

Spotlight, Time Machine, `~/.claude/logs` and `gitstatusd` are **not** current load terms (measured,
§5).

Measurement window: 2026-10-17 02:33-02:50 CDT, load 60-170. The lead's own readings (load 365-520,
1.4 GB/s) came from an earlier, heavier window, and §4 reconciles the two.

---

## 1. fseventsd: livelock #3 (MEASURED, conviction 93%)

### 1.1 Signature, the same as docs/research/fseventsd-churn-2026-09-08.md §2

| probe | command | result |
|---|---|---|
| process | `ps -o pid,etime,time,%cpu,rss,stat -p $(pgrep -x fseventsd)` | pid 19766, etime 7-04:55, TIME 1217:18, 99.2%, RSS 7.2 GB, `Rs` |
| one thread spinning | `ps -M -p 19766`, 20 s apart | main thread `R`, 100%; UTIME 595:58.58 → 596:17.80 (**+19.22 s in 20 s**), STIME 30:52.96 → 30:53.08 (+0.12 s). 160:1 user:sys. The other 36 threads show 0.0% |
| total CPU rate | `ps -o time=` at 02:37, 30 s apart | 1221:24.95 → 1221:58.47 = **33.5 s / 30 s = 1.12 cores** |
| delivery | `node fs.watch(mkdtemp, {recursive:true})`, then a write at +300 ms | **TIMEOUT at 15,000 ms** |
| positive control | same harness with `fs.watchFile` (stat polling, no FSEvents) | **delivered in 20 ms** |
| footprint | `top -l 1 -pid 19766 -stats pid,cpu,mem,cmprs` | MEM **11G**, CMPRS **4231M** |

The control isolates the fault to the FSEvents delivery path: the directory, the writes and the
harness all work.

### 1.2 Onset, read from the watchdog's own log

`~/.claude/logs/fseventsd-watch.jsonl` (3,328 rows, one every 5 min) records `fp_mb` for pid 19766:

| time (CDT) | fp_mb |
|---|---|
| 10-11 … 10-15 | 7-13 |
| 10-16 03:44-17:16 | 48 |
| **10-16 17:21** | **69** |
| 17:31 | 406 |
| 18:01 | **1,009** |
| 19:03 | 1,790 |
| 22:18 | 6,174 |
| 10-17 01:59 | 9,937 |
| 02:25 → 02:42 | 11,264 |

Growth is about **1.2 GB/h** and roughly linear, which looks like an undelivered queue accumulating.
The main thread's 596 min of UTIME bounds the spin to at most about 10 h, consistent with a
17:16 onset.

The **trigger could not be determined**. `/usr/bin/log show --start '2026-10-16 17:12' --end
'17:24'` returns 0 lines even with no predicate. A positive control (`--last 3s`) returns 2,224
lines, and a 23:00 window returns 2,940. So the unified log keeps only about 4-9 h at the current
~775 msgs/s (`log show --last 10s | wc -l` = 7,756). No worktree or gate start lines up with 17:16:
the b13/r13-* worktrees were born 19:24-19:38 (`stat -f %SB`).

### 1.3 Why the existing watchdog has not acted

- `scripts/fseventsd-watch.sh:36-38,64-65` sets `WARN_MB=8192` and `ACT_MB=16384`, and the verdict
  is footprint-only (`:153-155`). The restart condition is `VERDICT=act && act_runs>=2` (`:166`).
- The root copy `/usr/local/libexec/claude-fseventsd-watch.sh` is byte-identical to the repo's
  (`diff` → SAME). It is installed: `/Library/LaunchDaemons/com.claude.fseventsd-watchdog.plist`
  runs it every 300 s.
- `/var/log/claude-fseventsd-restarts.jsonl` does not exist, so the watchdog has never restarted
  anything. The latest rows read `verdict:"warn", action:"page-damped"`.
- Projection: 11,264 MB at 02:25, growing 1.2 GB/h, reaches 16,384 MB at about **06:40**. That is
  about 13.4 h of a dead daemon. A 1 GB floor would have fired at **18:06** on 10-16, 45 min after
  onset.
- **The healthy envelope is measured**: 7-48 MB over 7 days of this pid, and 3.5 MB fresh (header,
  `fseventsd-watch.sh:9`). 1 GB is about 20× the healthy maximum.

### 1.4 What the livelock costs the sessions

- **CPU**: about 1.1 of 10 cores (MEASURED, §1.1). At 02:45, `top -o cpu` ranks it the single
  largest process: fseventsd 99.7%, kernel_task 28.9%, WindowServer 10.2%.
- **Memory**: 11 GB footprint against `PhysMem 61G used, 1.1-1.3G unused` (top). Its CMPRS column
  reads 3.8-4.6 GB while the machine's compressor is 11G. CMPRS units are ambiguous, so its share of
  the compressor is ESTIMATED at up to about 40%.
- **Every FSEvents consumer is dark.** This includes Claude Code's chokidar watchers, Hammerspoon,
  and launchd `WatchPaths` jobs. `launchd/com.claude.browse-mirror.plist:53` uses WatchPaths with an
  interval fallback, and `launchd/staged/com.claude.accounts-local.plist:23` already records that
  "FSEvents went dark … no WatchPaths job fired at all". Anything event-driven falls back to its
  timeout path, which slows session-visible latency.
- The unprivileged attribution tool `scripts/fsevents-top.py` subscribes through fseventsd, so it is
  **blind during a livelock** and reads 0. That is an instrument caveat, not a clean reading.

---

## 2. Spotlight (question 1)

### 2.1 Does macOS 15 honor `.metadata_never_index`? **No.**

- Local controlled experiment, already on record: `docs/plans/MACHINE_CAPACITY_V2.md:1141-1152`
  ("`.metadata_never_index` is **DEAD** (probe dir indexed anyway); `.noindex` suffix and
  dot-prefix both work"). The same result appears in `scripts/iterm2-perf-parity.sh:14-28` and
  `scripts/render-census.sh:60-62`.
- External: Eclectic Light says the `.metadata_never_index` file "no longer works in recent macOS"
  and lists `.noindex` and a leading dot as the methods that work. The Search Privacy list stops
  indexing entirely ("listed items won't be indexed at all"). Sources:
  https://eclecticlight.co/2024/07/09/excluding-folders-and-files-from-time-machine-spotlight-and-icloud-drive/
  and https://eclecticlight.co/2024/11/29/using-and-troubleshooting-spotlight-in-sequoia-summary/ .
  The 2026-01 revision names only `.noindex`, the leading dot and the Privacy list:
  https://eclecticlight.co/2026/01/06/exclude-or-include-items-in-backup-search-icloud-drive-and-quicklook-preview/
- `~/Development/.worktrees/.metadata_never_index` exists (`ls -la`, created Aug 19). It is
  **redundant and dead**: `.worktrees` is dot-prefixed and so already excluded. Every `.venv` and
  `~/.claude*` directory is excluded the same way (MACHINE_CAPACITY_V2.md:1142).

### 2.2 The working mechanisms

| target | already excluded? | mechanism |
|---|---|---|
| `~/Development/.worktrees/**` (327 entries) | **yes**, by the dot prefix | none needed |
| any `.venv` | **yes**, by the dot prefix | none |
| `~/.claude*` (postland worktrees live in `~/.claude/autonomy/postland`) | **yes**, by the dot prefix | none |
| `~/Development/<repo>/node_modules` (**103**, `ls -d ~/Development/*/node_modules \| wc -l`) and main checkouts | **no** | Privacy list entry `/Users/chrisren/Development`. Renaming to `.noindex` would break module resolution, so it is rejected |
| `~/Development/_worktrees/e3-orphan-rescue` (a non-dot container) | no | covered by the same `~/Development` entry |
| `$TMPDIR` (`/private/var/folders/...`), pytest basetemps | **could not determine**, see §2.3 | add `/private/var/folders` to the Privacy list only if a rebuilt index shows it |

How to apply it:
- **GUI (operator):** System Settings → Spotlight → Search Privacy → add `~/Development`.
- **CLI (sudo):** `sudo /usr/libexec/PlistBuddy -c "Add :Exclusions: string /Users/chrisren/Development" /System/Volumes/Data/.Spotlight-V100/VolumeConfiguration.plist`.
  Back up the plist first, then restart mds. Sources: https://alexwlchan.net/2021/ignore-lots-of-folders-in-spotlight/
  and https://gist.github.com/ecklf/68a6c43c1443b61e0c3cdeb571fe5f8c . The plist is root-only, so an
  agent cannot read it to drift-check it (MACHINE_CAPACITY_V2.md:1145).
- **Tooling impact: none.** No tooling in this repo uses Spotlight (`mdfind|mdls|mdutil` have 0
  consumers, MACHINE_CAPACITY_V2.md:1010).

### 2.3 The Data-volume index is not serving at all (MEASURED)

- `mdutil -s /System/Volumes/Data` → `Error: unexpected indexing state. kMDConfigSearchLevelTransitioning`.
  The same error appears for `/System/Volumes/Data/Applications`. `mdutil -s /` → enabled.
- `mdfind -count -onlyin ~/Documents 'kMDItemFSName == "*.pdf"'` → **0**, while
  `ls ~/Documents/*.pdf | wc -l` → **90**.
- `mdls` returns "could not find" for every probe file, including the `~/Documents` control, so the
  per-file probe is **NO-DATA** on this run.
- Spotlight is therefore not providing file search right now. Its **current** cost is still small:
  over 30 s, mds took 0.52 s (1.7% of a core) and mds_stores 0.04 s (0.1%), from `ps -o time=`
  deltas. The 3,380 CPU-min that mds_stores has accumulated over 16.5 d (a 14% lifetime average) is
  **historical and bursty**, which matches MACHINE_CAPACITY_V2.md:1146-1147.
- **Ordering matters.** Put the `~/Development` exclusion in place *before* the index leaves
  "Transitioning" or anyone runs `sudo mdutil -E /System/Volumes/Data`. Otherwise the rebuild crawls
  the 103 node_modules and main checkouts. The volume holds 49M used inodes (`df -h`).
- If the operator does not use Spotlight file search, `sudo mdutil -i off /System/Volumes/Data`
  removes the class outright. That is the operator's choice, and it does not affect session work.
- Spotlight exclusion **cannot** reduce FSEvents load. The event stream is volume-wide with no
  opt-out (MACHINE_CAPACITY_V2.md:1151).

---

## 3. vnodes (question 3)

### 3.1 The numbers (MEASURED)

| sysctl | value |
|---|---|
| `kern.maxvnodes` / `kern.num_vnodes` | 263,168 / 263,168 |
| `kern.free_vnodes` | 234,852-236,635 (**about 90% of the table is free cached vnodes**, not in use) |
| `kern.num_recycledvnodes` | 3,595,239,723 lifetime, a mean of **2,528/s** over 16.46 d |
| recycle rate now | 20 s delta = **13,806/s**, 5.5× the lifetime mean, so the table turns over about every 19 s |
| `hw.memsize` | 68,719,476,736 (64 GiB) |

**`num_vnodes == maxvnodes` is normal and not itself the fault.** The table fills and then works as
an LRU cache. The fault signal is the **recycle rate**.

### 3.2 Why 263,168 on a 64 GB machine

The XNU source (`bsd/dev/unix_startup.c:172-189`, fetched from apple-oss-distributions/xnu main)
sizes the table as:

```
desiredvnodes = (int)(sane_size / 65536) + 1024;   // "we are clipping the max based on 16G"
if (desiredvnodes > CONFIG_VNODES) desiredvnodes = CONFIG_VNODES;  // 263168
```

Apple's own formula without the cap gives **1,049,600** for 64 GiB. The cap is a build-config
constant sized for 16 GB.

### 3.3 Cost of raising it (ESTIMATED from `zprint` element sizes)

Per-vnode zones from `zprint`: `vnodes` 264 B, `APFS_INODES` 424 B, `namecache` 104 B, `ubc_info`
96 B, `vnode.pager` 32 B. That is about **0.9 KB per vnode**, all wired.
- 263,168 → 1,049,600 adds about 786k × 0.9 KB ≈ **0.7 GB wired**.
- 263,168 → 524,288 adds about 0.23 GB.

### 3.4 Benefit (ESTIMATED, mechanism-level)

Reclaiming a vnode tears down its `ubc_info`. That drops the file's cached pages and its name-cache
entries, so the next access pays an APFS lookup and a re-read. With the table turning over every
~19 s:
- any file not touched in the last ~19 s has lost its metadata cache;
- `git status` in a 9,018-file claude-infrastructure worktree (`git ls-files | wc -l`) re-materialises
  thousands of vnodes each time;
- four concurrent pytest gates each walk a 3,665-entry `.venv` (`find -maxdepth 6 | wc -l`).

The only published measurement found is old: a WebKit developer's `git status` time dropped by over
50% after raising `kern.maxvnodes` on 4-8 GB Intel Macs, and the same thread confirms the cost is
wired memory (https://lists.webkit.org/pipermail/webkit-dev/2010-December/015283.html). Treat the
effect size on this box as **unmeasured**.

### 3.5 Is it safe?

- The value comes from Apple's own sizing formula.
- Wired memory is the only cost, and 0.7 GB is about 6% of what the fseventsd leak holds today.
  So apply it **after** the fseventsd restart (R1), which leaves memory net positive.
- `kern.maxvnodes` can be raised live with `sysctl -w`. Lowering it again may need a reboot (same
  thread). `/etc/sysctl.conf` persistence is reported unreliable, so persist it with a root
  LaunchDaemon that runs `sysctl -w kern.maxvnodes=…` at load. The boot-arg path (`PE_get_default`
  at `unix_startup.c:173`) needs reduced SIP on Apple Silicon, so it is rejected.

### 3.6 Who drives the 13.8k/s

**Could not determine without root.** `fs_usage` needs sudo, and the FSEvents tap is blind (§1.4).

Candidates, with measured sizes:
- 48 worktrees created on 10-16 (`stat -f %SB` histogram), 9,018 files each for claude-infrastructure.
- 4 concurrent `pytest -n 4` gates in b13/r13-*.
- 64 `.venv` and 171 `node_modules` directories under `.worktrees`.
- The postland bats run (`~/.claude/autonomy/postland/wt-run-65926`).
- `session-index-sweep` stats about **9,483** transcripts per pass (`find ~/.claude*/projects
  -maxdepth 4`, `hooks/lib/session-index-helpers.sh:990`). At once a minute that is about 158/s,
  roughly 1% of the recycle rate.

What an operator run would show: §6, recipe A.

---

## 4. Disk I/O (question 5)

| probe | command | result |
|---|---|---|
| device throughput | `iostat -d -c 3 -w 10` | disk0: **98-105 MB/s, 3.0k-9.6k tps, 11-12 KB/t** in steady samples |
| swap traffic | `top -l 2 -s 10`: `VM: … swapins, … swapouts` | 35,379,077 / 75,192,985, **unchanged across 10 s, so 0 swap I/O in the window** |
| disk ops | same top, `Disks:` | +38.1k reads and +32.4k writes in 10 s |
| lifetime | same | 28 TB read, **106 TB written** in 16.46 d: a 74.5 MB/s write average, about 6.4 TB/day |
| lifetime swap share | 75.19M swapouts × 16 KB | about 1.15 TB, roughly **1% of bytes written** |
| user-attributable I/O | lead: about 5 MB/s | so ≥95% is root or kernel |
| `~/.claude/logs` | `stat -f %z` sum, 30 s apart | **1,082 B/s**, negligible |
| Time Machine | `defaults read /Library/Preferences/com.apple.TimeMachine` | `AutoBackup = 0`, so not a term |

**Attribution (ESTIMATED).** Small 11 KB transfers at about 10k IOPS, with no swap and only about
5 MB/s of user data, point to **APFS metadata writeback**. Each create, unlink, rename or setattr
copy-on-writes B-tree nodes, and the writeback is charged to the kernel. That means the bytes scale
with **file-operation count, not file size**. The I/O levers are therefore the same as the vnode
levers: fewer file creates and deletes for the same outcome (R4, R5, R6, and the worktree items in
R8).

The lead's 1.4 GB/s came at load 365-520 with the compressor at 53 GB and swap at 4.7/5.1 GB. That
window may have included compressor-to-swap traffic, but **it could not be re-measured here**
because swap was static in this window. §6 recipe B separates paging from metadata and data writes
per process.

A side finding outside this axis, in the kernel log (`log show --last 10s`):
- **576 lines/10 s** of `process_is_plugin_host: running binary "bash"`, i.e. about 58 bash execs/s.
- `ecosystemanalyticsd` produced about 670 lines/10 s, including **51 sandbox denies per 10 s** on
  `…/.worktrees/b13/r13-b/.venv/…/pypandoc/files/pandoc`.
- Each worktree's venv carries its own 114 MB pandoc binary as a separate inode
  (`stat -f '%i %l %z'`: 2015213023 and 2015293114, both nlink 1).

This is cross-axis (logd and exec work). It is addressed by R4 below (shared inodes) or by pointing
`pandoc_path` at `/opt/homebrew/bin/pandoc` (agent-context-sync `src/agentsync/config.py:213`).

---

## 5. Other candidates, with numbers (question 2)

| candidate | measurement | verdict |
|---|---|---|
| **pytest basetemps** (`$TMPDIR/pytest-of-chrisren`) | `ls` gives **40** numbered dirs plus 1 `garbage-*`. **37 hold a `.lock`; 36 of those lock pids are dead** (cross-read against one `ps` snapshot); the live one is 97048, `pytest -n 4` in r13-ra. Sampled sizes: 556, 359, 335, 140, 110, 15, 1 MB, a 217 MB mean, so about **8.7 GB total (ESTIMATED)**. A separate `/private/tmp/pytest-of-chrisren` holds 3 more | Leak mechanism, read in the installed pytest 8.4.2: `_pytest/pathlib.py:46` sets `LOCK_TIMEOUT = 3 days`; `:310-330` `ensure_deletable` keeps any dir whose lock is younger than that; `:377-404` releases the lock and cleans up only through `atexit`. Python's default SIGTERM skips atexit, so every gate killed by `timeout` leaks its basetemp, live-locked, for 3 days. The "keep 3" default never applies |
| **Python mkdtemp leaks** in `$TMPDIR` | `/bin/ls -f $TMPDIR \| wc -l` = **87,247** entries, of which **44,198** match `tmp[a-z0-9_]{8}`. A 249-entry sample is all directories, dated 09-30 → 10-16 (the box has been up since about 09-30), empty, each with about 15 subdirectories (`home/`, `lr/recon/{quarantine,plans,shadow,cohorts,…}`) | Producer, matched by layout: `scripts/limit-recover/lr_recon/tests/test_main.py:84-89` calls `mkdtemp()` and creates `home` and `lr`, with **no rmtree or addCleanup** in the file. The same holds for test_census.py (6 sites), test_act.py (2), test_plan.py (3), test_in_place.py and test_evidence.py, all at cleanup=0 (grep count). Roughly 660k leaked inodes (ESTIMATED). It is a hygiene and inode cost, **not a CPU term**: no runtime code enumerates `$TMPDIR` (`git grep 'TMPDIR' … '\*'` returns 2 non-enumerating hits) |
| node_modules / .venv per worktree | 171 node_modules and 64 .venv under `.worktrees`. `.venv` is 377 MB (`du -sk`), and uv 0.12.17 uses its macOS default **clone** link mode: the same file in two worktrees gets two inodes (`msal/__init__.py`: 2015211233 and 2015233236, both nlink 1) | APFS clones share disk blocks but **not vnodes, page cache or code-signing validation**. Four concurrent gates hold four copies (R4) |
| gitstatusd | 19 processes, **18 with ppid 1** (orphans); every one at 0.0% CPU in the snapshot, with cumulative CPU 0.2-12 s each and RSS 0.5-21 MB | **Not a load term.** It is read-only, so there are no index rewrites to blame |
| `~/.claude/logs` | 479 MB across 208 files; 30 files written in 5 min; **1 KB/s** growth | **Not a term** |
| Time Machine | `AutoBackup = 0`; the destination fails to mount | **Not a term** |
| Spotlight | 1.7% + 0.1% of a core now (§2.3) | **Not a current term**; a future-crawl hazard |
| worktree population | 327 entries under `.worktrees`, 156 GB (lead). claude-infrastructure has 147 registered, 0 prunable and 3 locked (`git worktree list --porcelain`). Ownership by `.git` gitdir: claude-infrastructure 133, doc_classifier 62, reso-management-app 35, reso-web-app 16, lakehouse-lecture 12, others ≤8 | Idle worktrees cost about **0 CPU**: they are not indexed and not backed up. They cost disk, inodes, and time whenever something walks them (the nightly GC runs `git status` on every candidate). This is hygiene, not a load lever; it is still answered in R8 because the operator asked for it |

---

## 6. Operator measurement recipes (root; what they would show)

- **A. Per-process syscalls behind the vnode churn:**
  `sudo fs_usage -w -f filesys -t 10 > /tmp/fsu-fs.txt; awk '{print $NF}' /tmp/fsu-fs.txt | sed -E 's/\.[0-9]+$//' | sort | uniq -c | sort -rn | head -30`
  ranks processes by filesystem call count (stat64, open, getattrlist, mkdir, unlink, rename). The
  prediction to falsify: git, Python (pytest), bats/bash and node dominate, and mds is near zero.
- **B. Split of the 100 MB/s-1.4 GB/s:**
  `sudo fs_usage -w -f diskio -t 20 > /tmp/fsu-io.txt`, then group by the type column (`WrMeta`,
  `WrData`, `RdMeta`, `PgIn`, `PgOut`) and by process. If §4's inference holds, `WrMeta` charged to
  kernel_task/apfs dominates the IOPS, and `PgOut` is near zero except while the compressor spills.
- **C. Livelock evidence for Apple Feedback** (before the restart):
  `sudo sample fseventsd 3 -file /var/log/claude-fseventsd-samples/manual-$(date +%s).txt`.

---

## 7. Recommendations, ranked

**R1 — P0, operator: restart the livelocked fseventsd now.**
- Command: `sudo launchctl kickstart -k system/com.apple.fseventsd` (or `sudo killall fseventsd`),
  after recipe C.
- Expected effect: −1.1 cores (MEASURED), −11 GB footprint and −3.8 to −4.6 GB of compressed pages
  (MEASURED), and FSEvents delivery back from TIMEOUT to the 8 ms median measured after the
  2026-09-10 cure.
- Constraint: this repairs a dead system daemon; it does not throttle session work. Its only cost is
  that FSEvents clients rescan once, which the 2026-09-08 and 2026-10-04 restarts already paid
  without incident.
- Verify: rerun the §1.1 probe pair (expect delivered in under 50 ms, control 20 ms) and
  `top -l 1 -pid $(pgrep -x fseventsd) -stats mem` (expect under 50 MB).

**R2 — P0, code plus an operator re-install: give the watchdog a livelock criterion so the cure
fires 45 min after onset instead of about 13 h.**
- In `scripts/fseventsd-watch.sh`:
  - add `FSE_WATCH_EARLY_MB` (default 1024), so that `act` is also reached when
    `FP_MB >= EARLY_MB` on 2 consecutive runs of one pid (`:64-65`, `:153-160`);
  - add a CPU criterion: store `ps -o time=` for the pid in the state file (`:140-151`), and treat
    ≥90% of the 300 s interval on 3 consecutive runs as `act`.
- The restart path (`:166-200`), the 30 min gap and the stack sample stay as they are.
- Refresh the root copy with migrations/0057-fseventsd-watchdog.sh, which is operator-only because
  the copy is root-owned in `/usr/local/libexec`.
- Replaying the timeline: the early floor would have fired at 18:06 on 10-16.
- False-positive margin: the 7-day healthy range is 7-48 MB, about 20× below the floor.

**R3 — P1, operator: raise `kern.maxvnodes` to 1,049,600, Apple's own uncapped formula for 64 GiB.**
- Persist it with a root LaunchDaemon running `/usr/sbin/sysctl -w kern.maxvnodes=1049600` with
  RunAtLoad. Apply only after R1.
- Cost: about 0.7 GB wired (ESTIMATED, §3.3).
- Benefit: recycling of the 13.8k/s kind, which today discards a file's page cache and name-cache
  entries, should fall in proportion to the larger table. Magnitude ESTIMATED.
- Verify: re-sample `kern.num_recycledvnodes` over 20 s (expect a large drop), the `iostat` tps,
  and the top sys%.
- A cautious first step is 524,288.

**R4 — P1, code: share dependency inodes across worktrees.**
- Set uv's hardlink link mode: `UV_LINK_MODE=hardlink` in the worktree bootstrap
  (scripts/new-worktree.sh / worktree-setup), or `[tool.uv] link-mode = "hardlink"` in each
  pyproject.
- Effect: one inode per installed file across all 64 venvs, so concurrent gates share vnodes, page
  cache and code-signing validation. The per-copy pandoc work in §4 disappears.
- Outcome is equivalent: the same files sit at the same paths. The risk is that an in-place edit of
  site-packages would propagate to the uv cache.
- The node equivalent is pnpm's hardlinked store, larger and P2.
- Effect: vnode working set for the dependency set ÷ (number of concurrent gates), ESTIMATED.

**R5 — P1, code (agent-context-sync, and any pytest repo gated under `timeout`): make SIGTERM run
pytest's teardown.**
- In `tests/conftest.py`, add `pytest_configure` and install
  `signal.signal(SIGTERM, lambda *a: (_ for _ in ()).throw(KeyboardInterrupt()))`. A KeyboardInterrupt
  is a normal interruption, so the `.lock` is released and the stock keep-3 cleanup runs.
- Effect: about 8.7 GB and 36 dead-locked trees reclaimed, and the population stays bounded at 3 per
  user (MEASURED leak; size ESTIMATED).
- No extra work lands on the gate's critical path: the same deletion already happens, just 3 days
  late.

**R6 — P2, code: clean up the lr_recon tests' temp trees.**
- Add `self.addCleanup(shutil.rmtree, self.tmp, True)`, or use `TemporaryDirectory`, at
  `scripts/limit-recover/lr_recon/tests/test_main.py:84` and the cleanup=0 sites in test_census.py,
  test_act.py, test_plan.py, test_in_place.py and test_evidence.py.
- Effect: stops about 2,700 leaked trees/day (44,198 over 16.5 d, MEASURED) and about 40k inodes/day
  (ESTIMATED).

**R7 — P2, operator: keep Spotlight off the code tree before the index ever rebuilds.**
- Add a Privacy-list entry for `/Users/chrisren/Development` (GUI, or PlistBuddy as in §2.2).
- Then either rebuild with `sudo mdutil -E /System/Volumes/Data` or turn indexing off with `-i off`;
  the index currently serves nothing (§2.3).
- Leave the dead `.metadata_never_index` marker alone; it is harmless and redundant.
- Effect: prevents a crawl of the 103 node_modules and main checkouts. Current cost is about 0
  (MEASURED).

**R8 — P1, code: event-driven worktree pruning that cannot strand later references** (the
operator's explicit question).

Today's state (MEASURED):
- The only claude-infrastructure sweep is nightly at 04:15. Its last verdict
  (`~/.claude/logs/worktree-gc-infra.log`, 10-16) was `stranded-over-ceiling removed=11 kept=105
  refusals=135 pop=284 pop_foreign=184 ceiling=150 stranded_branches=53 rc=3`.
- 184 worktrees of other repos have no janitor at all, apart from reso-management-app's
  `gl.reso.worktree-gc` (`scripts/worktree-gc-infra-run.sh:5-8,22` hardcodes REPO).
- bin/cc-reaper removes a reaped session's landed worktree (`:1814`), but only for reaped sessions.

Design:
- **(a) Session end.** The SessionEnd hook (`hooks/live-session-registry.sh:12`) and
  `bin/cc-teardown` spawn a detached, scoped `worktree-gc.sh --only <cwd>` once the owner pid has
  exited. `--only` does not exist yet; the flags are at `scripts/worktree-gc.sh:175-180`. Spawn it
  directly, not through launchd WatchPaths, which dies with fseventsd (§1.4).
- **(b) Land.** After `scripts/ship-land.sh` advances the trunk, run the same scoped pass for the
  landed branch's worktree. Gate 4 keeps it while its session is live; (a) catches it afterwards.
- **(c) All repos.** The nightly backstop iterates every repo that owns a worktree under
  `.worktrees`, derived from each worktree's `.git` gitdir. Each repo still decides from its own
  `git worktree list --porcelain`, never from a directory glob (safety model, `worktree-gc.sh:13-15`).
- **(d) Make removal reversible, so it can be eager.** All six existing gates stay. On top of them,
  the disposal ledger row (`cc-reaper:1825`, `CC_WTGC_DISPOSAL_LOG`) gains a small tarball of the
  non-regenerable gitignored content: everything `ignored_inventory` (`worktree-gc.sh:856`) lists,
  minus node_modules, .venv and `__pycache__`. A `worktree-gc.sh --restore <path>` then rebuilds the
  worktree with `git worktree add <path> <branch>` and unpacks that tarball. Explicit pins use
  `git worktree lock --reason '<why/until>'`, which gate 2 already honours.
- **(e) Stranded work.** Unlanded worktrees are kept unconditionally (gate 6), as today. The warrant
  prompt moves from the nightly log into that session's close summary, so the decision is made while
  context exists.

Effect: the population tracks the live set within minutes of each session end or land, instead of
growing until the next nightly sweep. Disk and inodes shrink (ESTIMATED). CPU and load effect is
small, stated honestly (§5).

Rejected options are listed below.

---

## 8. Refuted or rejected

- **`.metadata_never_index` as the Spotlight lever**: dead on this OS (§2.1). The `.worktrees`
  marker does nothing.
- **"Spotlight is the I/O/CPU hog now"**: refuted for this window. mds and mds_stores together take
  1.8% of a core (§2.3). The 3,380 CPU-min is historical.
- **"`kern.num_vnodes == maxvnodes` means vnode exhaustion"**: refuted. 90% of the table is on the
  free list (`kern.free_vnodes`). The real signal is the 13.8k/s recycle rate.
- **Swap as the source of the I/O**: refuted for this window (0 swapins or swapouts over 10 s;
  lifetime about 1% of bytes written). The lead's 1.4 GB/s window is unverified.
- **gitstatusd index rewrites, `~/.claude/logs` writes, Time Machine**: refuted, each measured at
  about 0 (§5).
- **`tmp_path_retention_count = 0`** to stop basetemp leaks: rejected. With keep=0 pytest takes
  **no lock** (`pathlib.py:389-391`), so one run's exit cleanup could delete a concurrent gate's
  live basetemp.
- **`tmp_path_retention_policy = "failed"`**: rejected as the fix. It moves deletion onto each
  gate's critical path and does nothing for killed runs.
- **Sparse checkout of docs/research** (5,763 of 9,018 files, 64%) to shrink worktree checkouts:
  rejected. Sessions grep docs/research routinely, so it limits session work.
- **A periodic `$TMPDIR` reaper**: rejected in favour of fixing the producers (R5, R6). A
  path-pattern reaper over a shared temp dir is a kill-policy shape with false-positive risk against
  live runs.
- **Renaming node_modules to `.noindex`**: rejected, it breaks module resolution.
- **A boot-arg for maxvnodes**: rejected, it needs reduced SIP on Apple Silicon.
- **Cutting Claude Code's FSEvents registrations (CHOKIDAR_USEPOLLING)**: still rejected, for the
  reasons in docs/research/fseventsd-churn-2026-09-08.md §4. Registrations do not cause the livelock.

## 9. Open questions

- What triggers the livelock? It is unknowable from the logs (retention under 9.5 h). R2's stack
  sample at restart plus recipe C is the path to an Apple Feedback report.
- Which processes drive 13.8k vnode recycles/s, and how the I/O splits between metadata, data and
  paging, need recipes A and B (root).
- Whether `/private/var/folders` is in the Spotlight scope cannot be tested while the Data index is
  in `kMDConfigSearchLevelTransitioning`.
- R3's effect size is unmeasured on this hardware, so A/B it with `num_recycledvnodes` and iostat.
