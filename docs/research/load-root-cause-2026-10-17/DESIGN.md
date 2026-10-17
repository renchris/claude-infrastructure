# Load root cause 2026-10-17: synthesis and design

Inputs: the axis files A-J in this directory, plus two skeptic verdicts per recommendation (constraint lens and
evidence lens). Rules applied: a recommendation refuted at severity major or fatal was **amended to its skeptic's
correction where that correction fixes it, otherwise dropped**. Every row below says which. Tags: **[M]** measured
(the command is named here or in the cited axis file), **[E]** estimated (the method is named). Re-reads by this lead
at 03:11-03:13 local on 2026-10-17: `uptime` 105.5/107.6/89.4, then `sysctl -n vm.loadavg` 57.0/73.1/79.5; fseventsd
pid 19766 `ps -o etime,time,pcpu` 07-05:40, 1266:09 CPU-min, 113.7%; `top -l 1 -pid 19766 -stats mem,cmprs` **13G
footprint, 5760M compressed**.

**Revision (gap closure, 08:41-08:58Z on 2026-10-17, load 18-30 by `sysctl -n vm.loadavg`).** This pass closes 19
material gaps raised against the first draft. Its new measurements were all non-root, read-only and bounded, and
each is tagged [M] with its command where it appears: the `git grep` footprint mechanism (§1.1a, X25), wired memory
at low load (§1.1b), IOKit disk counters (§1.1c), and a 10 s unified-log census with the Rosetta pandoc deny
mechanism (§1.1d, X26). fseventsd was still pid 19766 at 08:50Z (1297:46 CPU-min, 99.2%, 7.1 GB RSS) [M, `ps`], so
X1 had not run. Amended rows: X4, X5, X6, X7, X9, X10, X24 and X-POOL; §3.2-§3.7; WP-9, WP-11-WP-17, WP-21 and
WP-22. New: rows X25 and X26, detector D9, operator steps OP-2b and OP-2c, WP-30, and a Spotlight precondition on
OP-1.

**Second revision (gap closure, about 09:20-09:55Z on 2026-10-17, load 15-21 by `sysctl -n vm.loadavg`).** This pass
closes 10 more material gaps, all in the worktree lifecycle (§3), the permission flow, the live limiters and X21. Its
new measurements were read-only and bounded, and each is tagged [M] with its command where it appears:
- reso's janitor removes with a plain `git worktree remove` and keeps no residue. 10 of 35 reso linked worktrees hold
  a `.claude/settings.local.json`, and all 10 differ from main's copy (`cmp`).
- `cleanupPeriodDays` is **365** in `~/.claude/settings.json`, not the 30 the draft assumed. The other config roots
  symlink that file, except `.claude-next4`, which has none and so takes the default of 30. At least 300 transcripts
  in `~/.claude/projects` are older than 30 d.
- 7 of 40 sampled infra worktrees hold reflog-only commits that are not patch-equivalent to trunk, and 2 of those 7
  are landed-clean.
- 7 of 8 sampled `.next` dirs are over 50 MB.
- Raw `git worktree remove` and `prune` counts come from the 7-day bash log.
- `CC_BATS_MAX_ROOTS=0` waivers appear 228 times in the same log.
- The live permission rules contain no allow rule for the guard's rewrite.

Amended: X6, X7, X9, X17, X21 and X25's Verify; §1.1b-§1.1c (the X21 references); §3.1-§3.7; the §5 order paragraph;
§6; WP-5, WP-9-WP-13, WP-15-WP-17, WP-22 and OP-3; Q14; Appendix A. New: row X27, WP-31 (reso repo), WP-32, OP-5
and OP-6, Q19 and Q20, and a single numbering owner for the live-settings migrations (WP-16). The first revision's
24 h DETACH is replaced by **PARK as the default for every quiescent tree** (§3.2). The guard's command rewrite is
replaced by an in-hook tombstone that leaves the command unchanged (note X6).

The worktree answer to the operator's question, in one place. "Prune old worktrees" becomes event driven: SessionEnd,
pane teardown, teammate close, a merged branch and drift each enqueue a path. A WatchPaths wake or a 600 s tick then
acts only on paths that are due. Trees still needed later are not deleted early, because every quiescent tree is
first **moved, not removed**. PARK is lossless and undone in O(1) on resume, and every remover first writes a
tombstone that a restore can use. Nothing is deleted while a transcript can still resume the tree (365 d today),
except on a disk-pressure event.

Operator constraint, binding throughout: no throttling, demotion, capping, kill policy or session reduction. A fix
either does the same work with less machine work, or lowers the load on shared resources at equal-or-better wall
time for the session that started the work.

---

## 1. Root cause

On Darwin the load average is the time-averaged count of runnable threads, so 365-520 on 10 cores is a run queue
36-52 deep. About 30 Claude processes cannot produce that: their own share is **at most 36-48 load units (9-13%)**
[E: 2.390±0.533 per active session, from marginal-load-per-active-session-2026-08-19 §6e, times 15-20 active; B3
independently puts Claude plus all descendants at 12.7%]. The ambient non-session baseline is 8-46 [M, prior docs,
J]. The **excess of about 305-490 units was concurrent agent-context-sync test gates.** Four full
`pytest -n auto` suites ran at once in `~/Development/.worktrees/b13/r13-{p,b,d,ra}`: about 40 xdist workers, every
test forking bash, git and installer trees. Those tests were **84% of all execs on the box** [M, 30 s root eslogger
trace, O5-EXEC-TRACE.md:7], and the load fell as gates dropped out: 365-520 with four, 135 with one full suite, 44-107
with one `-n 4` gate under lockf [M, `uptime`/`vm.loadavg`, A and J; confounded by time of day]. So gates are **about
65-85% of the excess** [E, natural experiment]. Four kernel-side effects made that work superlinear at 45% sys.
First, the fork rate is 830-2,280/s across samples, not the ~30/s a ps diff suggests [M, pid-counter deltas, C/D/I
and skeptics]. Second, memory is exhausted (1.1 GB free, a 21 GB compressor holding about 53 GB, 4.7 GB swap). Its
largest measured *transient* was session-originated: one peer research agent's `git grep -n -E` reached an 18,998 MB
footprint for a few seconds (E §2), through a regex leak on binary files that this revision reproduced (§1.1a, X25).
Its largest *standing* consumer is not a session but **fseventsd**, livelocked or bloated for at least the fourth time
(09-08, 10-04, 10-09, now) at **12-13 GB footprint (5.0-5.8 GB compressed) and 1.0-1.7 cores**, with FSEvents
delivery degraded to 3.5 s-TIMEOUT>15 s [M: `top -pid`, `ps -o time=` deltas, an `fs.watch` probe against an
`fs.watchFile` control]; it went undetected because the root watchdog acts only at 16 GB [M,
scripts/fseventsd-watch.sh:65]. Third, every fresh test HOME misses the 90 MB per-user xcrun cache, and each miss
forks `xcodebuild -license check` (about 620M instructions) and rewrites the whole file (about 77M instructions,
30 ms sys, about 90 MB of page churn) [M per miss, `/usr/bin/time -l`]; at 0.8-1.4 misses/s [M, inode/size stat
loops] that is about 0.13 core and 70-110 MB/s of page-cache churn [E]; whether that churn reaches the disk is
re-opened in §1.1c. Fourth, compressor-sentinel kills under that
pressure throw away whole suites: at 05:14:53Z KILL-ESCALATE killed 4 and two ~9-minute runs were restarted [M, log],
and 11 of 36 leaked pytest basetemps are sentinel SIGKILLs [M]. Smaller contributors, each removable on its own, are
per-session helper daemons at about 54 forks/s (3-6% of forks, 0.1-0.2 core; cc-await-ping is about 40-45/s of it,
the crash watchdog only 5.6) [E, static count calibrated by measured CPU per poll]; hooks and the statusline at 66-83
execs/s (4-5.5% of forks, under 5% CPU) [E]; one ms365 node server per session, 29 processes holding 2.4 GB footprint
(0.86-1.0 GB RSS), whose cold connects take p50 3.0 s and p99 12.4 s and time out at 30 s under load [M, n=307];
about 2.2 GB of orphans with no controller [M, footprint]; instruments at 0.5-0.9% CPU [M/E]; and WindowServer,
Hammerspoon and kitty at about 1.3% of capacity [M, lifetime]. At about 0 [M] are the 222 zombies (kitty 0.48.2 bug
#10436), idle worktrees (156 GB), Spotlight, Time Machine, `~/.claude/logs` and gitstatusd. **So the load is
legitimate test work multiplied by removable per-test waste (shim misses, duplicated and killed suites, polling
forks) and by the memory a broken system daemon holds; the fixes remove that waste and repair the daemon, and the
measured numbers do not support pooling the gates (row X-POOL).**

### 1.1 Contributors the chain above does not cover (added in revision)

**(a) A session-originated transient: one `git grep` at 19 GB.** E §2 and §7 caught pid 29346 at an 18,998 MB
footprint with 3,515 MB RSS, the rest compressed [M, `proc_pid_rusage` via /tmp/e-memory-footprint.py]. The
transcript of the peer research agent that ran it gives the exact command, run in this worktree at 07:34:39Z
(`~/.claude-next/projects/…wt-cc-233108-87354/87e54489…/subagents/workflows/wf_b758372c-e0c/agent-ab5d0c11dcb528903.jsonl`):
`gtimeout 60 git grep -n -E 'kitty +@|kitten +@|kitty"? *@|KITTY_LISTEN_ON|--type[= ](background|os-window|tab|window|overlay)' -- ':!docs/research/load-root-cause-2026-10-17' | cut -c1-220 | head -120`.

It was reproduced read-only in this worktree under `/usr/bin/time -l`, one tracked file at a time, so no run went
past 0.4 GB. A scratch clone was not needed, because `git grep` writes nothing.

| Input (tracked file), same pattern unless noted | Bytes | Peak footprint | Instructions |
|---|---|---|---|
| bin/cc-kitty-wash (text) | 7,611 | 5.0 MB | 66M |
| docs/plans/BACKLOG_DRAIN_24_7.md (text) | 2,977,374 | 8.8 MB | 1,850M |
| assets/hero/poster.jpg | 524,048 | 97.4 MB | 108M |
| assets/demo/handoff-real.webp | 633,570 | 122.7 MB | 120M |
| assets/demo/terminal-bench.webp | 912,818 | 188.1 MB | 147M |
| the three binaries in one run, `--threads=1` (default threads: 397.0 MB) | 2,070,436 | 396.9 MB | 248M |
| terminal-bench.webp with `-I` / `LC_ALL=C` / `-P` | 912,818 | 5.5 / 5.5 / 6.1 MB | 60M / 606M / 59M |
| terminal-bench.webp, BSD `/usr/bin/grep -E` | 912,818 | 1.5 MB | 500M |
| terminal-bench.webp, Apple `/usr/bin/git` 2.50.1 instead of Homebrew 2.54.0 | 912,818 | 188.5 MB | 239M |
| terminal-bench.webp, one-branch BRE `kitty *@` / two-branch ERE `kitty +@\|kitten +@` | 912,818 | 11.2 / 18.4 MB | 69M / 67M |

What the table shows [M]:
- **The mechanism.** git hands each whole binary buffer to the libc POSIX regex in the UTF-8 locale
  (`LANG=en_CA.UTF-8`). For this 5-branch pattern the footprint grows by about 176-200 bytes per binary byte above
  the ~5 MB baseline; a one-branch BRE grows by about 6.5 B/B and two branches by about 14 B/B. Text files do not
  grow.
- **It is not threads × buffers.** The growth is cumulative across files (the three-file run is the sum, not the
  max), it is the same with `--threads=1`, and it is the same in both gits. It behaves as a leak in the regex path;
  which library fails to free is [E] unconfirmed.
- **The projection.** This worktree tracks 275 binary files totalling 133.8 MB, 133.1 MB of it in 29 files under
  `assets/` [M: `git ls-files` minus `git grep -I -l -F -e ''`, then `stat -f %z`]. `assets/` sorts before `bin/`,
  so the whole leak happens before the `head -120` pipe closes. A complete run projects to about 24-27 GB [E:
  linear at 176-200 B/B]. E's reading of 19.0 GB had a lifetime maximum equal to its current footprint, so it was
  taken while the process was still growing.
- **The equivalent-outcome form.** No binary file matches this pattern. Over the same pathspec, `git grep -n -P` and
  `git grep -n -I -E` return the same 1,854 lines (`diff` empty). The engine also sets the CPU cost: `-I -E` took
  80.5G instructions and 1.38 s, and `-P` took 2.0G and 0.13 s, both at 111-113 MB [M, `/usr/bin/time -l`].
- **Frequency.** On 2026-10-16, `~/.claude/logs/bash-execution.log` holds 46 `git grep` calls: 11 with `-E`, 0 with
  `-I` [M, grep count]. That is rare, but any regex `git grep` here without a pathspec that excludes `assets/` walks
  all 134 MB.

A transient this size can trip compressor-sentinel kills on its own, which is the multiplier §1 blames for the
restarted suites. Fix: X25. Detector: D9.

**(b) Wired memory, 24-25 GB, is standing rather than load-driven.**
- **The known part.** E §4 attributes 6.95-7.23 GB to GPU allocations [M, `ioreg -r -c AGXAccelerator -d 1`] and
  leaves about 18 GB of kernel memory unattributed; user-wired is 0.004 GB [M].
- **A re-read at low load.** At load 22-29 on 2026-10-17 08:4xZ, `top -l 1 -n 0` read
  `PhysMem: 60G used (24G wired, 12G compressor)`, `MemRegions: 622494 total`, `Processes: 1147 total`, 6,102
  threads, and `vm_stat` read wired 1,575,894 pages, 24.0 GiB [M].
- **So it does not track the gates.** Wired barely moved while load fell from 365-520 to about 25 and the region
  count fell from 773,812 to 622,494.

Candidate drivers, with the rows that would shrink each:

| Candidate | Size | Rows that shrink it |
|---|---|---|
| GPU and IOKit buffers (WindowServer, Dia GPU, kitty, Cursor) | 7 GB [M]; 24,964 IOBufferMemoryDescriptor [M, `ioclasscount`] | none here (desktop apps); X14 for kitty only |
| Page tables for 1,150-1,500 processes | ~1-4 GB [E: 16 KiB L3 tables, ~1-3 MB per process for its private mappings; the shared cache is nested, not per process] | X4 (29 → 1-2 node servers), X11(a) sleep orphans, X12 and X15 (fewer transient processes), X24 orphans |
| VM map entries and VM objects for 622k-774k regions | ~0.1-0.2 GB [E: ~100-200 B per entry] | the same process-count rows; X1 (a 12 GB fseventsd holds many regions) |
| Kernel stacks | ~0.1 GB [E: 6,102 threads × 16 KiB] | the thread-count rows (X4, X12) |
| vnodes and namecache | <1 GB [E, E §4] | X3c and X20 (fewer files created and looked up); X21 is now only an experiment on shared vnodes (second revision) |
| APFS object-map and B-tree node caches, kalloc zones | the remaining ~10-14 GB [E, by subtraction] | the file-operation rows X3c, X20 and X21, plus X9 (PARK takes trees out of every sweep's walk) |

The split cannot be read without host_priv. OP-2b runs `sudo zprint -t -s | head -40`, which ranks zones, and also
saves the full `sudo zprint` output, because its trailing wired-by-tag section is what `head -40` cuts off. It runs
at peak and again at idle, and the result is recorded here. Until then this block stays unattributed and no row
claims a wired saving.

**(c) Disk I/O.** IOKit's per-device counters are readable without root [M: `ioreg -c IOBlockStorageDriver -r -w 0
-d 1`, 08:54Z; uptime 16.52 d from `sysctl kern.boottime`].
- **Lifetime totals.** 116.89 TB written and 30.77 TB read: **7.08 TB/day written** (6.4 TiB/day, 81.9 MB/s on
  average) over 1,236,753,431 write operations.
- **The op size contradicts F §4.** Writes average **94.5 KB per operation** and reads 9.9 KB. F §4's [E] attribution
  to APFS metadata writeback would show writes the size of B-tree nodes. The small operations are reads; most written
  bytes come in large operations.
- **Writes are bursty.** A 10 s delta of the same counters at load 22 gave 2.34 MB/s written (142 ops/s) and 9.9 MB/s
  read [M], so the writes are concentrated in busy periods.
- **The leading candidate** is [E] the xcrun_db rewrite: §1 measures 70-110 MB/s of 90 MB files while gates run.
  With 1.1 GB free, the pageout path has to clean dirty file pages, so a rewrite that would normally be unlinked
  before writeback can reach the disk. That re-opens Q3.
- **The 1.4 GB/s reading.** The lead's 1.4 GB/s at about 4,000 IOPS (about 350 KB per op) is still a single
  unverified reading.
- **SSD wear.** The device is an 8 TB APPLE SSD AP8192R with S.M.A.R.T. status Verified [M,
  `system_profiler SPNVMeDataType`]. Apple publishes no endurance rating, and smartmontools is not installed
  [M, `which smartctl`]. If the rating were about 4.8 PB written (an assumed ~600 TB per TB of capacity), today's
  rate would reach it in about 1.9 years [E: extrapolation of the measured rate].

Per-process attribution needs root, so OP-2c runs F §6 recipes A and B. The I/O levers are the rows that cut file
operations and bytes written for the same outcome:
- X3: the 90 MB rewrite per miss, the largest candidate;
- X20: 36 leaked basetemps and about 2,700 leaked mkdtemp trees a day;
- X11: orphaned and polling processes;
- X21: no longer a lever. uv already clones (F §5), so venv creation writes metadata only; X21 survives as a vnode
  experiment (second revision);
- X9 / PARK: fewer sweep walks.

X5 records bytes and operations written in its series, so each of these lands with a before and an after.

**(d) logd.** logd pid 313 has used 2,006 CPU-min in 16.52 d: 8.4% of a core on average and 2.0% now [M,
`ps -o time,pcpu`]. Its producers come from `log show --last 10s --style ndjson` grouped by process and subsystem
[M]:
- **At gate time.** F §4 measured about 775 msgs/s. That included 576 lines per 10 s of
  `process_is_plugin_host: running binary "bash"` (one per bash exec) and about 670 lines per 10 s from
  ecosystemanalyticsd, with 51 sandbox denies per 10 s on a worktree venv's pypandoc `pandoc`.
- **At 08:46Z, load 18.** The rate was 277 msgs/s. **coreaudiod wrote 1,716 of the 2,770 lines (62%)**, every one
  `HALB_MachPort::SendMessageWithReply: mach_msg() returned error 0x10000003`. That is MACH_SEND_INVALID_DEST, a send
  to a dead client port, about every 5.8 ms from one thread. coreaudiod pid 54565 has used 723 CPU-min and runs at
  5.7% [M]. Next came the kernel with 173 lines (61 bash `process_is_plugin_host` lines and 36 syspolicyd denies on
  `/private/var/db/oah/…`, Rosetta's translation cache), then smd with 120.

**The pandoc denies are explained [M].** `src/agentsync/ops/doctor.py:99-102` (agent-context-sync) records that the
pypandoc_binary wheel ships an **x86_64** pandoc. Here that is wheel 1.17, tag `macosx_11_0_arm64`, carrying pandoc
3.9 (`file` confirms x86_64). So every exec runs under Rosetta. One exec of the main checkout's copy took 0.16-0.19 s
and 399-462M instructions [M, `/usr/bin/time -l`]. Within 8 s it produced in ecosystemanalyticsd
`RosettaCoordinator: Performing rosetta analysis`, `Sandbox: ecosystemanalyticsd deny(1) file-read-data
…/pypandoc/files` and `…/files/pandoc`, and `SecStaticCodeCreate Failed` [M, `log show --last 8s`]. The copy had
been run many times before, so **the analysis fires on every Rosetta launch**, not only on the first launch of a new
copy. A shared path or a hardlinked inode would therefore not stop the denies; a native binary does. Rows: X26 for
the native pandoc, X24 for the coreaudiod restart.

---

## 2. Ranked fixes

How rows are ordered: priority first (P0 now; P1 large and low-risk; P2 moderate; P3 hygiene, conditional or
experiment), then effect per unit of effort within a priority. "Op" = needs sudo, GUI, a daemon load or a live
settings write. Row notes after the table give the full mechanism wherever a skeptic amended the row.

| ID | P | Fix (source; skeptic disposition) | Mechanism | Effect | Why it does not limit work | Files (file:line) | Op? | Verify |
|---|---|---|---|---|---|---|---|---|
| X1 | P0 | **Restart fseventsd now** (F-R1, E1, J-R2; amended: use the proven kill path, take a sample first, narrow the claim) | **Precondition (added in revision):** the Spotlight Privacy entry for `/Users/chrisren/Development` is in place first, because the restart makes mds rescan while the Data volume's index is `Transitioning` (F §2.3; OP-1). Then `sudo sample` the daemon; `sudo kill -TERM <pid>`, wait up to 10 s, then `-KILL` if alive; confirm a new pid. `launchctl kickstart -k` only as a fallback, since SIP may refuse it | −1.0-1.7 cores and −12-13 GB footprint (−5.0-5.8 GB compressed) [M now]; delivery back to ~8 ms [M 09-08 precedent]; one-time client rescan of about 3 CPU-h, front-loaded [E, churn §8.1] | Repairs a root daemon that delivers late or not at all; no session is touched; watchers that already get nothing cannot get less | scripts/fseventsd-watch.sh:181-198 (the path to mirror) | yes | `fs.watch` probe with an `fs.watchFile` control before and after; `footprint`/`top` under 100 MB; touch a Hammerspoon-watched file and a WatchPaths target (launchd/com.claude.browse-mirror.plist:53) and confirm they fire; check `tmutil status` and `mdutil -s /System/Volumes/Data` first, and record `mdutil -s` and mds/mds_stores CPU (`ps -o time=` deltas) before, 10 min after and 1 h after the restart |
| X2 | P0 | **Early footprint floor in the fseventsd watchdog** (F-R2, E1; amended: CPU arm log-only, exact bytes, no node as root) | `FSE_WATCH_EARLY_MB=1024` on 2 consecutive runs of one pid feeds the existing act/restart path. Footprint is read as exact bytes from `/usr/bin/footprint -p` (top's G rounding kept only as fallback). The CPU arm is **log-only for at least 7 d**. The delivery probe stays in the user agent and only pages | A replay restarts at ~18:11 on 10-16 (the 16 GB path projects ~06:40 on 10-17) and ~15:09 on 10-09 (that episode was manual): about 12.5 h less spin per episode, ~1 core and up to 12+ GB each [M, replay of /var/log/claude-fseventsd-watchdog.jsonl]; healthy maximum 92 MB over 12 d, an 11× margin [M] | Repairs a broken daemon sooner; RESTART_GAP_S 1800 unchanged; caps nothing | scripts/fseventsd-watch.sh:23-45,64-66,116-127,153-160,169; launchd/system/com.claude.fseventsd-watchdog.plist:33,45 (comment); migrations/0057-fseventsd-watchdog.sh:63,83,90-91 (re-install) | code: no. Root install: yes | bats with the FSE_WATCH_TOP/PS seams: 1100 MB ×2 → act; 48 MB at 100% CPU → ok (CPU arm log-only); fresh pid at 95% CPU, 40 MB, age 10 min → ok; replay both episodes from the jsonl |
| X3 | P1 | **Resolve git once; confine xcrun misses to a small test db** (B1+B2+B3, A-R1/R7; amended: all entry points, parent-shell resolve, warm dated db, demoted from P0) | (a) `gitops.git_executable()` and `setup_report._git_ro_err`: when /usr/bin/git is the shim, run `xcrun --find git` once, accept only an absolute executable named `git`, memoize success only. (b) install.sh: `git_ro_resolve` in the **parent shell** before each `$(…)` site. (c) Test harness: `os.environ.setdefault("xcrun_db", <DARWIN_USER_TEMP_DIR>/cc-test-xcrun_db.<yyyymmdd>)` in `pytest_configure`, plus a session fixture that resolves git under the real HOME; cc-bats gets the same `xcrun_db` | Per eliminated miss: −77M instructions, −30 ms sys, −~90 MB page churn, and the xcodebuild child (~620M instructions, 24 MB) [M]. At 0.8-1.4 misses/s: about −0.1 core and −70-110 MB/s of page churn [E]. (a) alone removes ⅓-⅔ of pytest misses; (c) covers the subprocess rest [E]. A hit goes from 96-99M to 27M instructions only in processes that make ≥2 git calls [M] | Same Apple git 2.50.1 binary and the same arguments [M]; only a cache location changes; the warm dated db means no cold-start stall (an empty db costs 1.9-4.3 s [M]) | agent-context-sync: src/agentsync/gitops.py:133-157; src/agentsync/setup_report.py:3445; src/agentsync/ops/doctor.py:181-196,581; docs/design/CONTRACTS.md:2943-2944; tests/test_gitops.py:42; scripts/install.sh:489-536,945-976,3131-3136,3697-3703; tests/conftest.py:131-151. CI: bin/cc-bats:131 | no (product change: repo owner decides) | `strings xcrun_db \| grep -c 'pytest-N/popen-gw'` per gate, before (~1,100) and after; inode of the shared db stable during a suite (1 s stat loop; today 71 rewrites in 90 s [M]); doctor line names the Xcode path |
| X4 | P1 | **One shared ms365 server** (E2; amended to shape B only, a selection guard, a tools/list equality gate, demoted from P0) | A launchd agent (KeepAlive) runs **punkpeye mcp-proxy** on `127.0.0.1` with `--apiKey` from a 0600 file, wrapping ONE unchanged stdio `ms-365-mcp-server`. Native `--http` is rejected: it drops the auth tools (server.js:77) and `download-bytes-to-file` (graph-tools.js:1151, stdioOnly), which hooks/enforce-email-formatting.py:532,585,1179 and bin/ms365-reply-splice.py:159 depend on. mcp-servers.json becomes type http with a header, rendered by mcp-ssot-wire.sh. A Host check is added. Selection loads once per process (auth.js:393-399, index.js:81), so a shared server must not let one session's `select-account` move every session. **Amended in revision: no deny.** `select-account` becomes a per-session default (row note X4); `login`, `verify-login` and `logout` pass through. The server restarts when the package version changes; taxes-2026 stays stdio | 29 → 1-2 processes [M baseline]; −1.3-1.5 GB physical (−2.2 GB footprint) [E: 857 MB RSS plus the compressed share at ~2.5:1]; connect becomes a loopback initialize (<100 ms [E]) instead of p50 3.0 s / p99 12.4 s with 2 hard 30 s timeouts [M]; −~290 cold starts/day of a 6,265-file package [E] | Same 188 tools, the same input schemas and the same Graph identity; no global mutex (grep of dist [M]), so sessions do not queue; sessions connect sooner and more reliably. No ability is removed: switching accounts stays per session, and re-auth runs through the daemon | CI mcp-servers.json:29-33; scripts/mcp-ssot-wire.sh; install.sh:645-660; scripts/lib/mcp-noinherit.sh:100; new hooks/ms365-shared-guard.sh; new migrations/00NN-ms365-shared.sh; new launchd/com.claude.mcp-ms365.plist | code: no. Load and settings: yes | **Gate before cutover (amended):** `tools/list` identical to a direct stdio spawn in names **and inputSchema**, by a byte-compare of canonical JSON (188, incl. download-bytes-to-file and verify-login). Every Graph tool must carry an `account` property; the server adds one only when it starts multi-account (graph-tools.js:136-139,216-219,343; server.js:117), so a single-account start fails the gate. A `login` through the proxy must return its device-code text to the calling session. If any check fails, the proxy routes by a per-session header to per-account children instead (row note X4); a deny is never the fallback. Then: process count 29 → 1-2; mcp-logs show `transport: http` under 1 s; verify-login + list-mail-folders from a desk session and a fired session on 2 accounts; per-call latency A/B stdio vs proxy; kill-test the daemon; 24 h with 0 CONNECT_TIMEOUT |
| X5 | P1 | **Fork-free 5 s sampler plus accounting fixes** (I-R1, I-R3; both amended) | `capacity-attrib.py --daemon` on its **own** KeepAlive label, in the Standard band; capacity-alarm stays on StartInterval 60 and keeps its exit-code contract, reading `attrib-latest.json` only when it is fresh. Alias and underflow flags in the accounting. Added in revision: the series also carries the IOKit block-storage counters (bytes and operations, written and read, so TB/day written is a tracked quantity, §1.1c) and each uid-501 pid's `lifetime_max_phys_footprint` (D9). Detail in §4 | Tick gap about 5 s, against el_s p90 251 s / max 496 s today [M, 477 rows]. CPU 4.6-7.1 ms per tick, about 0.1-0.2% of one core [M bench at load ~60], against 0.162 CPU-s per 65.7 s (~0.25%) today [M]: CPU neutral, a detection fix. Corrects 319/478 alias-exposed rows and 17 underflow rows marked ok [M] | Drops repeated python start-up; gates nothing | scripts/lib/capacity-attrib.py:192-246,345-374,432,597-611,648-650,678-693; tests/capacity-attrib.bats:98-101; capacity-alarm side is X17 | code: no. Activation (C10): yes | 10 min run to a tmp log at load ≥300 (record `vm.loadavg` as the positive control): p99 el under 15 s, CPU under 0.5% of a core; 60 s rows agree with the one-shot within 5%; forks/s within 10-15% of a pid-delta probe; the 07:16:44Z row comes out `forks_alias:true` |
| X6 | P1 | **One repo-qualified tombstone before every automated worktree removal** (G-P0-1; amended per actor; amended again in the second revision) | `scripts/lib/wt-tombstone.sh` appends a full row to the existing `worktree-disposals.jsonl` and preserves the non-cache residue. It never follows symlinks, and a failed write aborts the removal. **First revision:** a provisioning copy (`.env*`, `.claude/settings.local.json`) is left out only when `cmp` shows it byte-identical to the main checkout's copy, and the tombstone dir is 0700 with files 0600. **Second revision:** (1) the cache class is G §5.1's allowlist, with `git check-ignore -q` true, and **no longer only `node_modules` and `.venv`**; (2) residue is captured by a **same-volume APFS clone** (`cp -RPc`, clonefile(2)) or a `mv`, with **no size cap**, so no tree is KEPT and no session removal is refused for size; (3) a forced removal of a dirty tree also snapshots tracked and untracked files to `refs/wt-tombstone/<id>/wip`; (4) every `git worktree prune` writes `admin-pruned` rows first; (5) the residue never expires automatically; (6) the guard does its tombstone **inside the hook**, so the permission flow sees the original command unchanged. Per-actor rules in note X6 and §3 | Removers that write a tombstone: **2 → 5 of 7** with this repo's WPs: A1, A3 (now an enqueue to A1), A4, A5, and A9 through the guard. A6 is excluded by design. The count reaches **6 of 7 only if the reso owner takes WP-31**, which covers A2. The first revision's "6 of 7" counted A2, but no WP touched it. Rows carrying `repo`: 0/637 → every new row [M baseline]. Loss of ignored files that cannot be recreated → 0 [E] for every automated actor in claude-infrastructure and for raw `git worktree remove` / `prune` through the guard. **reso's janitor (A2) stays unprotected until WP-31 lands.** It removes with a plain `git worktree remove` (reso scripts/launchd/bin/worktree-gc-run.sh:155), and 10 of 35 reso linked worktrees hold a `settings.local.json` that differs from main's [M, `cmp`] | Background actors and the teammate hook's detached subshell: one append and one clone, which is O(entries) and copies no data blocks. The guard path: the same clone inside the hook, bounded well under its 10 s timeout [M, settings.json]. It is typically well under a second for post-cache residue [E: tens of entries], so a manual removal waits about as long as today and is never refused for size | new scripts/lib/wt-tombstone.sh; scripts/worktree-gc.sh:1000-1020,1109-1112; bin/cc-reaper:1756-1829; hooks/teammate-auto-shutdown.sh:1559-1564; scripts/handoff-fire.sh:16609; hooks/git-worktree-guard.sh:72-145; scripts/branch-prune-landed.sh; bin/reso-resume-one:490; scripts/postland-verify.sh:1133,1171; scripts/desk-land.sh:94; scripts/cloud-reconcile.sh:359 (prune lines only); reso scripts/launchd/bin/worktree-gc-run.sh:155,157 (WP-31) | no | Throwaway-repo lab (HAZARD RULE), §3.7 |
| X7 | P1 | **Restore a worktree on resume, keyed to the session** (G-P0-2; amended: session-keyed, `--detach` never `-b`, demand logging first, unattended refusal kept) | `cc-resume-resolve` emits `tomb_*` keys only for a tombstone whose sid is the resumed sid, or whose branch is the transcript's last gitBranch. **Amended in revision:** a PARKED tree is unparked on a **path match, with no sid needed** (it is lossless and pool slots are never parked), in every launcher: `cc-resume-shell`, `reso-resume-one`, `scripts/limit-recover/lr-fire-resume.sh`, and through reso-resume-one `cc-resume-layout`, `cc-relayout` and boot-resume. A DETACHED tree gets a default-yes prompt in cc-resume-shell that runs `cc-wt-restore`; with no tombstone, today's `mkdir -p`. `reso-resume-one` and `lr-fire-resume.sh` restore a DETACHED tree only on a sid match and otherwise keep today's refusal (:472-474; lr :491-523). Full design in §3.5 | 147 transcripts active in the last 7 d point at a missing cwd [M]; of 85 tombstoned paths, 70 heads still resolve, so their tracked tree can come back [M]; demand is unmeasured, so phase 1 logs it | **Corrected in revision.** The draft claimed "only a resume that is broken today pays a cost". That was false under a ~31-40 min DETACH, which would have turned the 36 landed-clean trees under 1 d old that have resumable transcripts (G §1.4 [M]) into restores. **Corrected again in the second revision.** The first revision's 24 h DETACH argument held only under the infra nightly (worktree-gc-infra-run.sh:22 hardcodes one repo). In doc_classifier, reso-web-app, lakehouse-lecture, sevenrooms-bridge and personal, trees live indefinitely today: G §1.2 counts about 60 landed-clean trees over 7 d old there, and G §1.4 counts 7 landed-clean trees with transcripts 7-30 d old. Only reso-management-app has a SessionStart install hook [M, `jq .hooks.SessionStart` per repo]. So the default quiescent action is now **PARK**, which is undone in O(1) on a path match with caches and reflog intact. DETACH waits until the newest transcript is older than the effective `cleanupPeriodDays` (365 d today [M]), or a disk-pressure event (§3.2). No resume that works today becomes a restore. A restore (seconds of checkout [E]) is paid only by a resume that today opens an empty dir, and it is logged | new bin/cc-wt-restore; bin/cc-resume-resolve:30-35,151-160; lib/cc-resume-shell.sh:138-155; bin/reso-resume-one:439-545; scripts/limit-recover/lr-fire-resume.sh:491-523 | no | Lab: land, remove, `branch -d`, then `_cc_resume_pin` with a fixture transcript: HEAD equals the tombstone head and the residue is byte-identical; RED against unpatched code (empty dir); a pool path reused by another sid → refuse; a stale batch row with its branch gone → refuse. Added in revision: park a tree, then run `reso-resume-one` and `lr-fire-resume.sh` against its original path with a sid that is **not** in the park row: each ends in a working cwd with `git status` and reflog identical to before the park (RED today: the add fails because the branch is checked out at `.parked/<id>`); repeat with a `mkdir -p` husk holding only `.claude-tasks` at the path; repeat after `git reflog expire --expire=now --all && git gc --prune=now` for a DETACHED restore |
| X8 | P1 | **cc-gc `worktrees` store becomes ASSERT** (G-P0-3; amended: ASSERT only, also reads verdict/rc, demoted from P0) | Replace the EXEC delegate. Today it passes `--apply`, which worktree-gc.sh rejects with rc 2 (:182-185), and its dry-run arm runs the janitor's **destructive default** (:152). The ASSERT reads `~/.claude/autonomy/worktree-gc-infra.last` and reports inert if the file is missing, older than 26 h, or shows `verdict` ∉ {ok, disabled} or rc ≠ 0 | 171/171 red runs → 0 [M]; one latent destructive path removed | Deletes a broken duplicate; touches no session | scripts/cc-gc.sh:374-386,448; tests/cc-gc.bats:39,455-461; docs/GC-FRANCHISE.md:17; docs/activation/pending-activation/40-cc-gc-activate.sh:40-41 | no | Stub `CC_GC_WORKTREE_BIN` that rejects unknown flags and records argv: never executed in either mode; the row reads ASSERT ok/stale/inert from fixture `.last` files, and today's `rc=3` reads non-green |
| X9 | P2 | **Event-driven worktree lifecycle** (G-P1-4, F-R8, J-R3, I-R5 merged; amended: durable deferred queue, a lossless PARK tier replacing G-P1-5, no fetch or branch prune on wake runs) | SessionEnd, pane teardown, teammate close, a merged PR and a drift detector each enqueue a path with `not_before`. A WatchPaths wake or a 600 s due-tick evaluates **only due paths**, and only in repos promoted out of observe-only (§3.4). **Second revision: PARK is the default for every quiescent tree.** A landed-clean tree is PARKED ≥24 h after its last transcript write and SessionEnd. A tree that is unlanded or dirty is PARKED once its tip, newest transcript **and** working-tree mtime are all idle ≥7 d. PARK is `git worktree move` plus a lock; a landed tree's HEAD is also detached so branch-prune can still delete the branch. DETACH happens only once the newest transcript is older than the effective `cleanupPeriodDays`, or on the disk-pressure path. Everything else → KEEP and requeue. §3 | **Corrected in revision:** landed-clean trees leave their path ≥24 h after their last write, at least as late as today's nightly run ever removes them (0-24 h) [design]. **Second revision:** they leave by a lossless move, not a removal, so the comparison no longer depends on the infra-only nightly. The draft's ~31-40 min bought no load, since idle trees cost about 0 (G §0) and disk is not binding (3.71 TiB free), and it would have broken same-day resumes (X7). The gains are: ~129-149 trees in repos with no janitor get a backstop [M, gitdir count]; 26 of the 32 nightly "unowned" trees (tip ≥7 d) become PARKED with no warrant [M]; each wake costs O(due paths) against the 370 s full sweep [M]. The grace is shortened only when the X7 phase-1 `resume-reaped.jsonl` shows the restore rate and the cost of each restore at load | Second revision: within the effective `cleanupPeriodDays` nothing is deleted, absent a disk-pressure event. Every quiescent tree is moved, not removed, and parking deletes nothing. Every action is reversible (X7), and no session waits | §3.4 and §5 (WP-10, WP-11, WP-12, WP-15, WP-16) | **Corrected in revision.** Code: no. The plist edit goes live when it lands: com.claude.worktree-gc-infra is `run` (launchd/fleet.manifest:370), and install.sh reloads a changed `run` plist on the next 600 s deploy advance (install.sh:1292-1317 select it, :1374-1382 bootout and bootstrap). So the event mode ships gated in code, `WTGC_EVENTS=observe` by default plus a switch file, and the activation script that flips it: yes | §3.7 |
| X10 | P2 | **One repo gate script; remove the measured duplicates** (A-R3 → log-only; A-R4, A-R5 amended) | `agent-context-sync/scripts/gate.sh` replaces the hand-copied /tmp/r13*-gate.sh. Order: statics; `uv sync --locked`; fail-fast `-n 4 tests/test_deploy_pack.py`; then the full `-n auto --ignore=tests/test_deploy_pack.py`, with a `--collect-only` union check. `--affected` (lane pre-gates only) = statics + touched test files + tests importing the changed src modules + the whole-tree scanners **always** (test_contracts, test_lints, test_governance, test_deploy_pack) + explicit maps for CONTRACTS.md, README, docs/deploy and .github. It logs `tree salt rc skipped_timing` to `<git-common-dir>/gate-verdicts.log`. **No verdict cache** until that log shows a tree gated green twice (0 of ~20 today [M]). **Added in revision: a kill-resume journal** (row note X10). Each test outcome is appended as it finishes, keyed on tree + salt; a lane run killed by the sentinel (rc 137, or xdist `OSError: cannot send`) on an unchanged tree then runs only the remainder, with skip reasons recorded | deploy_pack de-dup: ~1-2% of a land gate's worker-seconds, 8-60 s per land [M ratio, /tmp/r13d-gate6.log: 199 in 20.78 s vs 4605 in 761 s]. Affected pre-gates: 10-39% of test functions per lane [M on the round-13 diffs], ≈10-30% fewer local full-suite core-seconds per round [E]. Kill-resume: keeps the share a killed run had already completed. At 05:14:53Z that was about 9 min of each of 2 gates [M, A Q1], about 18 gate-minutes that today are re-run, and their re-run is why all four gates overlapped from 00:15 | The land gate stays the identical full suite; lanes get feedback sooner; a killed lane run finishes sooner, because it no longer starts from zero | ACS new scripts/gate.sh; new tests/_gate_journal.py (pytest plugin); CLAUDE.md:7-28; the lane template COMMON12.md:51-57 (in ~/.cache, not a repo) | no | Collection union equals the full collection; for one round, record every land-gate red that falls outside the affected set (the map's miss rate). Journal: SIGKILL a `-n 4` lane run halfway, re-run on the same tree, and the union of journal passes and remainder results equals a clean full run's nodeid → outcome map; a changed tree or salt ignores the journal; the land gate never reads it |
| X11 | P2 | **Installer polling forks and sleep orphans** (A-R6, plus this lead's reading of install.sh: not skeptic-verified) | (a) `with_timeout` kills the watcher subshell but not its `sleep "$t"`, which is orphaned to launchd for t seconds; 85 such orphans sat under one gate [M ps, C open item]. Fix: `sleep "$t" & s=$!; trap 'kill $s' TERM; wait $s; kill "$pid"`. (b) `with_progress` forks `/bin/sleep 0.2` five times a second for the whole wait: replace with `wait "$pid"` plus one ticker child that prints the same lines on the same PROGRESS_EVERY schedule. (c) Tests that wait out AGENTSYNC_WAIT_SECONDS poll at 0.05 s, with 8-10 substitutions per pass: use 0.5 s in timeout-path tests only | (b) −5 forks/s per in-flight with_progress [code count, E]; (c) −~90% of poll forks in those tests [E]; (a) −1 resident process per call, for t seconds [M count of the leak] | Same printed lines, same verdicts, same wall time | ACS scripts/install.sh:1012-1026,1033-1047,4940-4994; tests/test_install_oneshot.py:461,475,7101 | no | Exec count per test via a PATH stub; output byte-identical, including the "still running" cadence; `ps -axo ppid,comm \| awk '$1==1&&$2=="sleep"'` shows no new orphans after a run |
| X12 | P2 | **cc-await-ping: per-poll trim, then a kqueue wait** (C-R3, C-R2; both amended) | R3: iterate `$BEAT_KEYS` within the poll (no memo across polls); read the forward alias without forks (builtin read + parameter expansion); `_woke_get` sets a variable (no `$(…)`, no here-doc temp file); one direct `grep -c`; `[ -d ] \|\| mkdir -p`. R2 (after WP-18): `cc-kqwait` waits on a directory NOTE_WRITE for `$MAILBOX_DIR`, `.alias` and the registry dir, and on per-`.md` EXTEND/WRITE/DELETE/RENAME; the **full body runs on every wake**, heartbeat 30 s; `cc-kqwait … & wait $!` so traps run at once; a dead pid is reported once and then dropped; a fast failure falls back to `sleep "$INTERVAL"` | R3: ~38 → ~11 forks/s [E, static count over 14 measured watchers]; R3+R2: about 5/s [E]; mail wake from ≤15 s to milliseconds | Same predicates over the same files; every wake is at least as fast as today | bin/cc-await-ping:295-301,409-423,1314-1340,1568-1603,1685-1686; new bin/cc-kqwait | no | tests/cc-await-ping*.bats green; new cases: alias re-pointed in the same second, so the very next poll uses the new key; a reverse-edge alias with mail already pending pings without a further append; a vetoed dead owner does not spin (≤1 helper call per 30 s) |
| X13 | P2 | **Hook fork trims on the per-Bash-call path** (D-R2, D-R3, D-R1; amended) | D-R2 items 1-3 and 5-8, with fixes. Item (4) uses `[ -e /dev/fd/0 ] && INPUT="$(</dev/stdin)"` (never `read -d ''` on PostToolUse: 7× slower at 240 KB [M]). Item (8) keeps da3949756's dirname guard for no-slash and root paths. Item (9) is dropped. D-R3: one drained `grep -E -e …` union per table; only rc 1 counts as a miss, so rc 0, 2 and 141 fall through to today's walk. D-R1: `python3 -S`, with a stdlib-only import guard | ~13-15 execs/s, ~1% of forks [E]; union grep about −14 ms per compound call [M bench]; `-S` −5-12 ms per Bash call [M] | Byte-identical decisions; every Bash call returns sooner | hooks/curl-gate-scope.sh:52-58; rm-safe-allowlist.sh:46-66; pr-gate.sh:41; cc-permission-beacon.sh:66-67; teammate-checkpoint.sh:49; log-bash.sh:37-41,57; waiting-recycle.sh:638,734-763; research-block.sh:21-23; lib/research-router.sh:18-19; memory-index-drain.sh:80-86; bash-output-offload.sh:51-59; qos-rewrite.sh:108,336-365; coldcompile-admit.sh:75,103-153; smart-bash-allowlist.sh:138; scripts/pipefail-sigpipe-allow.txt | no | Per-hook `*-forks.bats` built on tests/stop-hook-forks-helpers.bash (rebuild the pre-change hook from git, byte-compare); a 240 KB PostToolUse payload must not get slower; fixtures for an invalid ERE row and for a command over 64 KB; `scripts/pipefail-sigpipe-lint.sh` passes |
| X14 | P2 | **kitty: adopt the signal fix with a signature kitty already holds grants under** (H0; amended: the staged bundle is ad-hoc signed) | Path A, at the next **planned** reboot: the stock Developer-ID cask 0.49.2. It keeps all 31 user and 4 system TCC grants; it lacks the talk-thread accept fix, which the existing detection keeps covering. Path B: re-sign the patched build under one stable identity as net.kovidgoyal.kitty, then an **attended** re-grant sitting. Add a gate to `kitty-build-swap.sh arm/swap` that refuses `Signature=adhoc` | Zombies 222 → 0 [E from upstream f3fdc218]; SIGUSR1 reload and a graceful SIGTERM come back; load ≈0 | Removes a defect; done at a reboot that is already planned; Path A keeps every privacy grant | scripts/kitty-build-swap.sh:22-35,74-93; docs/patches/kitty-talk-thread-survives-v0.48.2.patch | yes | `codesign -dv` shows the expected authority; in a new pane `ls ~/Documents` and `osascript -e 'tell application "System Events" to count processes'` work with no prompt; zombie count 0 after closing panes; USR1 applies a kitty.conf edit |
| X25 | P2 | **`git grep`: the same text matches from the PCRE engine** (added in revision; §1.1a) | hooks/qos-rewrite.sh gains transform (d). It runs before the compound exclusion (:304-306), because the measured command was a pipeline. It acts only on a leading segment `[gtimeout N] git [-C dir] grep [flags] (-E\|no engine flag) '<pattern>' [-- pathspecs]` where the single-quoted pattern is ASCII with no backslash, no `{` and no bracket holding `\` or `[:`; where the flags hold none of `-o`, `--column`, `-a`, `-F`, `-P`; and, for a BRE pattern, the pattern holds none of `+ ? \| ( ) { }`, so BRE, ERE and PCRE read it identically. It swaps that one `-E` token for `-P`, or inserts `-P` for a BRE, and leaves the rest of the command byte-identical. A one-token swap is not a wrap, so the file's rule against wrapping compounds (§11.3 M7) still holds | For the measured command: the same 1,854 lines [M]; the binary-file leak gone (6.1 MB against 188 MB per 0.9 MB of binary, and 19 GB observed) [M]; on the text-only `-I` form, 2.0G vs 80.5G instructions and 0.13 vs 1.38 s [M]. About 11 `-E` calls a day [M] | Selected text lines are identical within the safe subset. On binary files today's `-E` under-reports: `V.8` on terminal-bench.webp gives 3 matching lines under `-E` and 504 under `-P`, and poster.jpg gives 0 under `-E` for three patterns that `-P` finds [M, `git grep -c`]. So any "Binary file … matches" line `-P` adds is a true match the leaking path missed, not a changed outcome. Every call finishes sooner and smaller; outside the subset nothing is rewritten | hooks/qos-rewrite.sh:296-306 (new transform placed before it); new tests/qos-rewrite-git-grep.bats | no | Differential lab: every `git grep` pattern from 30 d of bash-execution.log that the transform would rewrite, run both ways over a fixture tree of text and small binary files. Text-file lines must be byte-identical with identical exit codes; binary-file lines from `-P` must be a superset of `-E`'s. A pattern outside the subset is not rewritten; a pipeline's tail is byte-identical; a `git worktree remove` or `prune` command gets no output from this hook (so it stays disjoint from X6's guard, which since the second revision rewrites nothing); `/usr/bin/git` and Homebrew git both accept `-P` [M today] |
| X26 | P2 | **Native arm64 pandoc of the same version, at one shared path** (added in revision; §1.1d; product change, repo owner decides) | `_bundled_pandoc()` (ACS src/agentsync/convert/pandoc.py:262-270) first maps the wheel's pandoc to its upstream version **without executing it**: the wheel's RECORD already lists its sha256 (pypandoc_binary-1.17.dist-info/RECORD:6 [M]), which a small in-repo table maps to `3.9`. If a native copy of exactly that version sits at `~/.local/share/agentsync/pandoc/<ver>-arm64/bin/pandoc`, it returns that path. The copy is unpacked by the operator from upstream's `pandoc-<ver>-arm64-macOS.zip` (published for 3.9 [M, GitHub releases API]) and checked once with `codesign -dv` for the wheel copy's signer, `Developer ID Application: John Macfarlane (5U2WKE6DES)` [M]. An unknown hash or a missing copy returns the wheel's binary, as today | Per exec [M, `/usr/bin/time -l`, `--version`, warm]: Rosetta 3.9 took 0.16 s, 399M instructions and 68 MB; native arm64 (Homebrew 3.11 as the proxy) took 0.03 s, 170M and 30 MB. The Rosetta analysis in ecosystemanalyticsd → 0 [M mechanism]. Within 8 s of one exec it wrote 6 `Sandbox … deny` lines plus 3 duplicate-report lines, and a 15 s window holding 1-2 execs had 53 lines naming ecosystemanalyticsd or pypandoc [M, `log show`]. The first-start translation of each fresh venv copy (10-67 s, doctor.py:99-102 [M 2026-10-07]) → 0 | Same pandoc version and the same flags; only the CPU architecture changes. The output must be byte-identical, which Verify proves | ACS src/agentsync/convert/pandoc.py:262-270; new tests/test_pandoc_native.py; the native copy is an operator step in OP-3 | code: no. Native copy: yes | Run the converter corpus (tests/test_convert_formats.py, test_convert_determinism.py, test_convert_builders.py) once per binary and byte-compare every output; during a gate, `log show --last 10s` grouped as in §1.1d: pandoc denies per 10 s go from 51 [M, F §4] to 0; test_convert_formats.py:135 (`path == _bundled_pandoc()`) still holds |
| X27 | P2 (operator ruling) | **Retire the live limiters once the waste that triggered them is gone** (added in the second revision; §6 already rules out each class) | Three limiters are live today, and §6 lists each one as violating the constraint. (1) Transform (b): `taskpolicy -c utility` demotion of agent `pytest`, `npm install` / `npm ci` and similar (hooks/qos-rewrite.sh:30; config/qos-batch.patterns:44-46). (2) Transform (c): the `cc-cpubound` RLIMIT_CPU ceiling of 60 CPU-s on agent `grep`/`ugrep`/`rg`/`ag`/`ack`/`find` (hooks/qos-rewrite.sh:31,33-43; config/qos-bound.patterns). (3) cc-bats admission: rc 75 refuses a third concurrent bats root when 1-min load per core is ≥2.0 (bin/cc-bats:459-466, refusal at :654, waiver at :675). Each was a response to waste that waves 0-1 remove or re-measure: shim misses (X3), duplicated and killed suites (X10), the fseventsd fault (X1), and the binary-file regex leak (X25, D9). The row is sequenced after waves 0-1 and decided by the extended Q14 A/B (§5, §7). On the operator's ruling, each limiter is retired by data or switch, not by code: its rows leave the two config tables, and cc-bats reads a mode file (WP-5) that turns admission into record-only. The registry is kept, because D1 counts bats roots from it | Unmeasured today; the A/B measures it. Demotion: the lone-gate slowdown that Q14 suspects. Refusal: **228** lines of the 7 d bash log carry `CC_BATS_MAX_ROOTS=0`, and 229 carry `CC_BATS_WAIVER_REASON` [M, `grep -c` on ~/.claude/logs/bash-execution.log, 2026-10-10T03:22Z..10-17T09:32Z]. Each waiver is a gate that was refused, or that a session waived in advance; the log cannot tell which. Ceiling: no firing ledger exists [M, `ls ~/.claude/logs`], so its kill count is unknown | Removes a demotion, a ceiling and a refusal; adds nothing. A runaway is still *seen*, by D2 and D9 (record-only, then paged), and the binary-file `git grep` case is fixed at its cause by X25 | config/qos-batch.patterns; config/qos-bound.patterns; bin/cc-bats:459-466 (mode-file read only, WP-5); tests/qos-rewrite.bats, tests/cc-qos-exec.bats, tests/coldcompile-admit.bats and tests/curl-gate-redirect.bats (all four read the tables) | yes: an operator ruling, like the sentinel kill rung (§6) | The extended Q14 A/B: per-gate wall time and gates/h with each limiter on vs off at matched background load, plus `ps -o pid,pri,ni,comm` per worker. Off arms: (b) and (c) skip compound commands, so `true && …` turns them off; cc-bats uses `CC_BATS_MAX_ROOTS=0`, its documented admission-only switch (bin/cc-bats:62). Also count SIGXCPU exits (status 152) of grep/find over 7 d from PostToolUse records, which is (c)'s kill count. Retire a limiter only if its off arm is no slower for every gate |
| X15 | P3 | Sentinel tick: one named `sysctl` call + one awk (C-R4; amended) | Parse by name and ignore the rc; keep the SKIP order; keep the rounding before every comparison (`%.2f` pct, `%.1f` srate); per-field failure modes stay distinct; one predicate text shared by the wrappers and the tick | −2.8 forks/s [E]; non-census tick ~1-1.7 s shorter, from 12.0-12.3 s [M baseline] | Same samples and the same JSON rows | scripts/compressor-sentinel.sh:363-366,387,417-463,1878-1982; tests/compressor-sentinel.bats:114-131 | no | Differential replay of old vs new through a multi-name stub, including 59.995/60.00 and srate == rmin; rows byte-identical |
| X16 | P3 | Statusline (D-R5; amended: **no** time-based cache) | `GIT_OPTIONAL_LOCKS=0`; the oid comes from `# branch.oid` of the status call already made; one jq; `${PWD##*/}`; a flag in the telemetry row replaces the 439 KB grep | ~10-11 → ~6 execs per refresh; 0.15% of forks at 0.30 renders/s [M rate] | Display stays exact | statusline.sh:77-86,222,237-246,299-303,343-348 | no | tests/statusline-identity.bats unchanged and green (incl. :370-399); index mtime unchanged over 100 renders |
| X17 | P3 | capacity-alarm: load becomes a chronic, record-only rung; "close sessions" advice removed (I-R4; amended; **after** X5 and D2) | Rung 7 is computed and logged, but no longer raises `v` in classify(). The live stale load page is retracted once; *actor named in the second revision:* capacity-alarm itself does it, with no hand step. That page is `~/.claude/autonomy/pages/capacity-alarm-load.page` (404 B, written 04:34 on 10-17 [M, `ls -la`]). In record-only mode the per-rung loop treats the load rung as SKIPPED, so the existing retract branch (capacity-alarm.sh:1967, "OK / SKIPPED / NO-DATA all RETRACT") removes it on the first run after the operator's activation script flips `capacity-alarm-load-rung.mode` (WP-17). The combined page clears through :1948-1951 once no other rung holds ALARM. Remedy strings are rewritten; the jsonl and the exit-code channel are kept | Retires the combined-page ALARM that load alone drives in 97.6% of ALARM rows (~45% of all rows) [M recompute over 8,816 rows] | Removes advice to shed sessions; adds no limit | scripts/capacity-alarm.sh:1512-1517,1568,1943,1966-2009,2052-2053; tests/capacity-alarm*.bats; launchd/com.claude.capacity-alarm.plist:89 | no | load 13/core with every other rung OK → exit 0, verdict OK, no page, `load_1m` still logged; `grep -i CLOSING` finds nothing; `scripts/pool-floor.sh --json` before and after, floor delta recorded next to CC_SP_DEFAULT_CEILING |
| X18 | P3 | Hook `if` filters; unregister inert ship-rail-push-allow (D-R4; amended patterns) | Remove the ship-rail-push-allow entry: it cannot override the `Bash(git push:*)` ask (settings.json:437). `if: Bash(*gh pr create*)` and `Bash(*gh pr edit*)` for pr-gate; one leading-wildcard handler per renderer for relay-verbatim | ~0.3-0.5% of forks [E] | Over-firing is the safe direction; the deny gates stay unconditional | new migrations/00MM-hook-if-filters.sh (edits settings.json:494,786,801) | yes | Scratch-config probe on 2.1.291, 2.1.293 and 2.1.114, including absolute-path and `bash -c` spellings |
| X19 | P3 | ms365 npx wrappers → direct binary, **same env** (E5; amended: not a delete) | personal/.mcp.json:3-8 → the fnm `aliases/default` binary with `MS365_MCP_TENANT_ID=consumers` and no CLIENT_ID; taxes-2026 likewise, env kept; mac-messages via `uv tool install` | −83 MB footprint per personal session (65+18) [M], ~0.25 GB today | Same app, authority and tokens | /Users/chrisren/Development/personal/.mcp.json:3-17; /Users/chrisren/Development/taxes-2026/.mcp.json:3-15 (outside git) | yes | `claude mcp list` Connected; `verify-login` returns the same account; compare tool counts (0.134.4 → 0.143.0) |
| X20 | P3 | Disk and inode hygiene: dead basetemp locks, lr_recon mkdtemp leaks (F-R5 amended, F-R6) | At session start, the controller unlinks `pytest-of-$USER/pytest-N/.lock` when the pid is dead or was recycled; the stock keep-3 cleanup then runs (this covers SIGKILL). `addCleanup(shutil.rmtree)` in lr_recon tests | 36 dead locks / ~8.7 GB [M count, E size]; ~2,700 leaked trees/day [M] | Same deletions, 3 days earlier; zero work inside a gate | ACS tests/conftest.py (WP-3); CI scripts/limit-recover/lr_recon/tests/test_main.py:84, test_census.py:32,367,411,439,493,645, test_act.py:19,152, test_evidence.py:27, test_in_place.py:28, test_plan.py | no | SIGKILL a `-n 4` controller, run again: the lock is gone and ≤3 dirs remain, while a live concurrent run's lock survives |
| X21 | P3 exp. | **uv hardlink vs clone: a vnode and page-cache experiment only** (F-R4; first revision: disk only, drop pandoc_path; **second revision: the disk claim is withdrawn and the row is restated as an operator-only experiment**) | F §5 (F-filesystem.md:279) measured that uv 0.12.17 already uses the macOS default **clone** link mode: separate inodes with nlink 1, and APFS clones already share disk blocks. So the first revision's "~300 MB disk per venv" is **already saved today**, and hardlinks add no disk effect. The only effect hardlinks could add is the one F R4 names: shared vnodes, page cache and code-signing validation across concurrent gates. The hazard F R4 names also stays: an in-place edit of site-packages would propagate to the uv cache and to every venv. The experiment: in two scratch venvs synced from the same `uv.lock`, one with `UV_LINK_MODE=clone` and one with `UV_LINK_MODE=hardlink`, run 4 concurrent `-n 4` gates per arm at matched background load. Record vnodes in use, the `vfs.vnstats` new-vnode and recycle counters, and syspolicyd and amfid CPU from `ps -o time=` deltas | Unknown. No disk effect (already cloned [M, F §5]). The vnode and validation effect is unmeasured | Same files and paths. Run in scratch venvs only, and adopted only on a measured gain | none in a repo. The arm is a per-venv env var; `~/.config/uv/uv.toml` is changed only if the operator adopts it (OP-3) | yes (operator only) | Per arm: Δvnodes-in-use and Δ(syspolicyd+amfid CPU-s) per gate, gate wall time, and `stat -f %l` showing nlink ≥2 in the hardlink arm. Keep it only if the vnode or validation delta is material and wall time is no worse |
| X22 | P3 | Hammerspoon: 10 ms base tick, 5 ms settle tick only while a shot is pending (H1) | The settle timer starts on onCandidate and stops when pending is empty | 200 → 100 wakeups/s when idle [code count]; ~0.2% of the machine [E] | Detection stays at 10 ms and settle at 5 ms | /Users/chrisren/Development/hammerspoon-config/hsc/screenshot/init.lua:30-32,247,385-398 | no | Bench p50/p90/p99 match C1 (4.7/10.0/11.1 ms) with 35/35 caught; `top -stats idlew` before and after |
| X23 | P3 | `kern.maxvnodes` A/B experiment (F-R3; amended to an experiment) | Only after X1, with page_free plus reclaimable above ~3 GB; 524,288 via `sysctl -w`; keep only if sys% and tps improve at matched load. With vn_dealloc_level=0 the wired memory stays until reboot (vfs_subr.c:244-251) | Unknown; steady state 1.5-5.7k recycles/s with 45-59k vnodes in use [M], and the 13.8k/s figure was a burst | Removes re-lookups if it helps; a removal is reversible only by reboot | new /Library/LaunchDaemons/com.claude.maxvnodes.plist (only if kept) | yes | Matched-load A/B: fixed `git status` wall time, `iostat -d` tps, top sys% |
| X24 | P3 | One-time operator cleanups (B4, E3, E4; amended) | `xcrun --kill-cache`, re-check the size after a few seconds (a rename race can restore the old db), remove `xcrun_db-*` files older than 1 h (245 MB); `CLAUDE_CONFIG_DIR=~/.claude-next claude stop 9aa483e9` (the conversation is kept; check `inFlight.queued=1` first); decide whether to reap orphan 13394 (render.mjs, fixed since d8011e0) and 22582 (zfav driver) | ~335 MB in /var/folders; ~270 MB RSS / 459 MB footprint; ~1.76 GB footprint, mostly compressed [M]. Added in revision: restart coreaudiod (`sudo killall coreaudiod`; launchd respawns it) at a moment with no audio in use. It sends to a dead port about every 5.8 ms, writes 62% of all log lines at idle and runs at 5.7% of a core [M, §1.1d] | One-off removal of things no live controller owns; not a policy. coreaudiod is a repair of a broken system daemon, like X1 | — | yes | `stat -f %z` xcrun_db; `ps -p 10027,10156,11252` is empty; `jq .state` reads stopped; `log show --last 10s` shows no `HALB_MachPort::SendMessageWithReply` lines and coreaudiod near 0% |
| X-POOL | P3 cond. | **Machine-wide test-slot pool: OFF by default, conditional** (A-R2, J-R1, A-R8; refuted major as written) | Built only if the A/B below passes: per-test tokens, FIFO by gate-arrival ticket, non-blocking LOCK_NB over all slots, runs under 50 items or with `-n ≤4` exempt, stopped holders counted as lost capacity, timing-skip counts recorded, `AGENTSYNC_TEST_SLOTS=on` to opt in, T swept over 8-16 | **The numbers argue against it today.** 4 concurrent suites finished in 2,402 s, 6.0 suites/h [M]. The one solo full suite measured took 761 s [M, /tmp/r13d-gate6.log at load 73-140], so 4 back to back take 3,044 s, 4.7 suites/h (−21%), and the last gate gets slower. Break-even solo time is **600 s**. A processor-sharing pool would make the first finisher (1,762 s today) slower. **Caveat added in revision:** the 761 s run was taken with another suite starting (A Q1), and neither it nor any X10 timing records the gate's QoS band. The live demotion (config/qos-batch.patterns:44, `(uv run +)?pytest` → `taskpolicy -c utility` via hooks/qos-rewrite.sh transform (b), :30, simple commands only) may have applied. So 761 s is an upper bound, not a solo baseline | Fails the constraint unless the A/B shows every gate's max and min wall time no worse and the aggregate better | ACS new tests/_slotpool.py; pyproject.toml addopts | no | After X1, X3, X10 and X11: 4 concurrent gates with the pool on vs off, plus a staggered-start arm and a lone-gate arm, at a background load of 60-70; record per-gate wall time, gates/h, `vm_stat` compressor pages and sentinel TRIP/KILL lines. **Added in revision:** (1) a true solo baseline at background load ≤20 with no other suite running; (2) the Q14 lone-gate A/B with transform (b) on vs off, where "off" needs no settings change, because (b) skips compound commands (`true && uv run pytest …` is not rewritten); (3) `ps -o pid,pri,ni,comm` of every gate's controller and xdist workers in every X-POOL and X10 measurement, so the band is on record |

### Row notes (mechanism detail where a skeptic amended the row)

- **X1.** Delivery right now is *degraded*, not dead: probes gave TIMEOUT>15 s, 3,503 ms and 5,281 ms; one 20 s probe
  on a busy directory delivered 29 events with the first at 2,273 ms [M, axis E/F/J skeptics]. The case for
  restarting holds for either fault class: 12-13 GB of footprint plus a core spinning at about 150-500:1 user:sys on
  one thread [M, `ps -M`]. launchd shows `runs = 3`, last exit `JETSAM_REASON_MEMORY_HIGHWATER` [M, `launchctl
  print`]. The claim is narrowed to new FSEvents streams; existing watchers are checked, and any that do not fire
  are reloaded. No Claude session is restarted.
- **X2.** The future actionable CPU arm requires all of: main-thread UTIME delta (`ps -M`) ≥90% of the interval,
  user:sys ≥20:1, other threads near 0, 3 runs, daemon age ≥2 h (so the post-restart rescan cannot re-fire it), and
  a cooldown longer than the footprint arm's. It goes live only after a week of rows shows zero firings on healthy
  intervals; that is the 10-09 plan's F8c condition (freeze-convoy PLAN.md:113,142), met rather than overridden.
  The ledger gains `verdict` and the trigger term. The script header (:28-32) gets a note that a SIGKILL restart can
  force one Time Machine deep scan.
- **X3.** For install.sh, resolving lazily inside `git_ro` is wrong: the call sites are `$(…)`, so the cached value is
  lost in each subshell [M, bash probe]. Call `git_ro_resolve` at top level, after `have_devtools`, at the start of
  read_commit, show_version, unread_reason, checkout_is_installed, write_fallback_report and newer_copy_fix. Never
  call it at script start, because runs that make no git call would then pay a miss. In product code, memoize only a
  successful resolution, so a test that monkeypatches `subprocess.run` cannot pin the fallback for the rest of a
  worker. The doctor and CONTRACTS wording becomes "prefers Apple's git, resolved through xcrun once per process".
  The dated test db is one per day, warm across runs, ~1-2 MB/day; it shares the cleanup step with X24's size check.
  A bare `pytest` has `xcrun_db` set by the controller; explicit `env={…}` dicts that drop os.environ lose only the
  gain. WP-4 adds the variable to the 13 sites in test_install_oneshot.py and to test_deploy_pack.py:404,1162,1218,
  1595,1945 and test_install_next_line.py:42. The sites in test_launcher, test_ops_doctor, test_report_redaction,
  test_setup_report and test_ocr are left as they are (only the gain is lost; test_ocr.py:521-534 asserts an exact
  env built by the product, which never carries it).
- **X4.** The email guard's R2 covers sends, not reads. One shared server's default account becomes shared state.
  The draft answered that with a PreToolUse deny on `select-account|login|logout`. That would have taken away two
  abilities sessions have today, switching accounts within a session and device-code re-auth, and its names-only
  gate could not show that an equivalent per-call path exists. **Amended in revision:**
  - **Per-session default.** `hooks/ms365-shared-guard.sh` handles `mcp__ms365__select-account` by writing the
    chosen account to `~/.claude/state/ms365-account/<session_id>` and answering with a deny whose reason text reads
    "selected <account> for this session". That is the only way a hook can answer a call. On every later
    `mcp__ms365__*` call from that session that has no `account`, it injects one through `updatedInput`. The effect
    is today's per-process selection, scoped to the session, with nothing leaking to other sessions.
  - **Pass-through.** `login`, `verify-login` and `logout` pass through to the daemon. The MSAL cache is already one
    identity, shared through keytar by every config dir (E §3), so their blast radius equals today's. A `logout`
    applies at once to every session instead of at each one's next token refresh.
  - **The cutover gate** compares full inputSchemas and asserts the `account` property (row X4 Verify). The server
    adds that property only when it starts multi-account (graph-tools.js:136-139,216-219,343, from
    `isMultiAccount()` at server.js:117), so a daemon started with one cached account fails the gate.
  - **Fallback if the gate fails.** mcp-proxy routes on a per-session header, `X-CC-MS365-Account`, to one stdio
    child per account. That is still 1-3 processes instead of 29. A deny is not the fallback.

  Pinning `list-accounts == 1` stays an alternative precondition. The personal/.mcp.json entry is a **different
  OAuth app and tenant** (Softeria default client 084a3e9f…, `consumers`), so X19 keeps it as its own direct-binary
  entry instead of folding it in.
- **X6, per actor.**
  - worktree-gc: tombstone, then remove without `--force`.
  - **cc-reaper no longer removes (second revision).** bin/cc-reaper `worktree_cleanup` (:1756-1822, called at :2672
    right after a confirmed teardown) removes a clean linked worktree in **any** repo within one 300 s sweep of
    pane teardown (StartInterval 300, launchd/com.chrisren.cc-reaper.plist:22). It has no grace, and no exclude or
    pin check. The first revision kept that removal and added only `wt_pinned` and a tombstone, so §3.2's 24 h
    grace covered only the wake path. Pane teardown is the usual end of a fired session [E: not re-measured
    here], so this is the remover most likely to meet a resumable cwd. G §1.4 [M] counts 147 transcripts active
    in the last 7 d whose cwd is gone, and 36 landed-clean trees under 1 d old with resumable transcripts. The ledger holds 15 cc-reaper removals since
    2026-08-22, and 13 of those paths are still gone [M, `jq 'select(.actor=="cc-reaper")'` on
    worktree-disposals.jsonl, then `[ -d ]`]. The reasons for a grace apply here unchanged: idle trees cost about
    0 and disk is not binding. So WP-11 replaces the `worktree remove` at :1814 with an **enqueue**: one `printf >>`
    of `{ev:"pane-teardown",path,sid,repo,ts}` to `~/.claude/state/wt-events.jsonl` and a `touch` of the wake file.
    The wake run then applies the same grace, pins, repo scope and PARK-first rule as every other event. The
    sweep does less work (no `status --ignored` and no remove), and no session waits. The status read at :1770, the
    runaway bound at :1782-1793 and the log-after disposal call at :1817 have nothing left to guard on this path.
    WP-11 keeps the bound's code for any later caller and updates the tests that pin the removal
    (tests/cc-reaper.bats).
  - teammate-auto-shutdown keeps `--force`, because "checkpointed" means the tree is still dirty. Its row records
    `checkpoint_ref=refs/wip/<member>/LAST`, and a `refs/wt-tombstone/<id>` is created at that commit. This covers
    247 untombstoned removals [M, teammate-lifecycle.log]. **Amended in revision: it writes the full tombstone,
    residue included** (the second revision makes that a clone, not a tar). The checkpoint ref holds only
    non-ignored content. The removal already runs in a detached subshell
    after the hook has returned (hooks/teammate-auto-shutdown.sh:1533-1568, subshell from :1537; the remove is at
    :1559-1564), so the draft's "no added wall time" reason for skipping the tar did not apply. `wt_tombstone` runs inside that subshell
    before the remove. Two things keep it clear of cc-reaper's 600 s orphan-bash reap (bin/cc-reaper:565, :725): it
    is bounded with `gtimeout 300`, and WP-11 adds `wt-tombstone` to GARBAGE_WL. On a timeout or a failed write the
    tree is **kept**, never removed without its residue.
  - handoff-fire :16609 removes a cold worktree that "never landed a pane". It writes the same tombstone. Its
    ignored content is normally just the provisioning copies, which the `cmp` rule below excludes, so the residue
    is empty and the failed fire path gains about no wall time. A non-empty residue is cloned in O(entries) on a
    fire that has already failed.
  - cloud-reconcile :357 is excluded: it removes transient `.desk-land-<pid>` sandboxes, the same class as A7, and
    blocking it would block a land retry.
  - git-worktree-guard (PreToolUse) covers a raw `git worktree remove`: A9, the 68 b13 lanes with no record, and the
    reactive "prune old worktrees" sessions. Today the guard blocks only live trees (hooks/git-worktree-guard.sh:72-145)
    and has no `prune` arm. [M, `grep -o -E 'git (-C [^ ]+ )?worktree (remove|prune)' | wc -l` on
    ~/.claude/logs/bash-execution.log, 2026-10-10T03:22Z..10-17T09:32Z]: **109** `git worktree remove` calls, 30 of
    them with `--force`/`-f` in the same segment, and **11** `git worktree prune` calls. In the same log, 1 command
    matches `rm -rf … .worktrees/`.
    **The first revision's guard design is replaced (second revision).** It rewrote the command through
    `updatedInput` to `wt-tombstone <path> guard-raw && <original>`. That has three faults:
    - **The permission flow judges the rewrite.** hooks/qos-rewrite.sh:118 records the rule: a rewrite with no
      `permissionDecision` leaves the permission flow to judge the *rewritten* command. Here that is a compound
      naming a new binary. [M, `jq` of the live ~/.claude/settings.json]: `defaultMode` is `auto`, and none of
      the 366 `permissions.allow` rules names `wt-tombstone` or `git worktree`. A fired session or a subagent that
      meets a prompt hangs (docs/lessons/a-subagent-cannot-answer-a-permission-prompt-so-a-prompt-trigger.md).
    - **Size refusal.** Under the old tar-plus-cap rule a large residue meant a refused removal.
    - **Tracked and untracked content.** The tar captured only ignored residue.

    So the guard now does the tombstone **inside the hook**, bounded, and never rewrites the command:
    - **Order.** The live-tree check stays first (:72-144), unchanged.
    - **Bound.** The tombstone work runs under `gtimeout 6`, inside the hook's own 10 s timeout [M, `jq` of the
      guard's entry in settings.json]. A hook killed by its outer timeout is [E] treated as a non-blocking error,
      so the command would run anyway, fail-open. That is why the bound is internal; Q20 settles the timeout
      semantics.
    - **Ignored residue.** One `git status --porcelain --ignored` call, then the cache and `cmp` rules below. The
      non-cache remainder is **cloned** with `cp -RPc` into the 0700 tombstone dir: clonefile(2), no data blocks
      copied, symlinks never followed. It is a clone and not a `mv` because a PreToolUse hook runs **before** the
      permission decision and before later hooks. If the removal is then denied or never runs, the tree must be
      untouched. The row is written `event=guard-snapshot`; the janitor marks it `superseded` if the path is
      still a worktree at its next visit.
    - **Forced removal of a dirty tree** (closes G §5.3's "the one thing a tombstone does not carry"). When the
      command carries `--force`/`-f` and `git status --porcelain` is non-empty, the guard also writes a plumbing
      snapshot of tracked plus untracked non-ignored files. It uses hooks/teammate-checkpoint.sh's own mechanism
      (:375-415): a temp index seeded from the real one so `add -A` hashes only what changed, then `write-tree`
      and `commit-tree -p HEAD`, then `update-ref refs/wt-tombstone/<id>/wip`. Nothing in the tree is written. If
      the bound is reached first, the untracked remainder is cloned instead, so no removal is refused for size.
    - **Success path.** On success the hook exits 0 with **no output**. The permission flow therefore sees exactly
      the command the session typed, as today, and no allow rule or settings migration is needed.
    - **Failure path.** On any failure or internal timeout, the hook exits 2 with a reason naming the failed step
      and the exact retry. A blocked removal is recoverable; an unrecorded one is not.
    - **Raw `git worktree prune`** (new arm). Before allowing it, the guard reads
      `git worktree prune --dry-run -v` and writes one `admin-pruned` row per entry: path, repo, the head and
      branch from the admin dir's `HEAD`, and a copy of its `logs/HEAD`. For every reflog commit that no ref
      reaches and that is not patch-equivalent to trunk, it creates `refs/wt-tombstone/<id>/reflog-<n>`. It then
      allows the command unchanged. This closes G D7 for the hand path, and covers an `rm -rf` followed by a
      prune.

    qos-rewrite.sh emits nothing for these commands (no table row matches `git worktree`), so the two hooks stay
    disjoint; the X25 lab asserts it.
  - **Every other `git worktree prune` site** calls `wt_prune_logged <repo>` from wt-tombstone.sh, which does the
    same as the guard's prune arm (dry-run, rows, reflog refs, then prune). The sites are scripts/worktree-gc.sh:1109-1112
    (WP-10, which already reads the dry-run), bin/reso-resume-one:490 on every recreate (WP-13),
    scripts/postland-verify.sh:1133,1171, scripts/desk-land.sh:94 and scripts/cloud-reconcile.sh:359 (WP-12, the
    prune lines only). A prune is repo-wide, so even a site that prunes only its own temp tree erases other trees'
    admin records.
  - **reso's janitor (A2), second revision.** reso scripts/launchd/bin/worktree-gc-run.sh:155 removes with a plain
    `git worktree remove "$p"`, and :157 runs a plain `git worktree prune`. It is woken through WatchPaths by
    reso's own SessionStart and SessionEnd hooks (reso `.claude/settings.json:140,162`) and by
    `scripts/worktree-pool.sh:592,629`. Its ledger shows 5 reaps between 2026-10-13 and 10-16 [M, `grep '^reaped: [^ ]'`
    on ~/.reso/worktree-gc.log, which is trimmed to 500 lines]. Its `classify_dirt` (reso `scripts/worktree-gc.sh`
    on origin/main :514-537) runs `git status --porcelain` without `--ignored`, so ignored content is deleted
    without a word, the class cc-reaper:1795-1798 measured on 2026-07-30. reso's .gitignore on origin/main lists
    `.claude/settings.local.json` (:81) and "Generated image assets (expensive to regenerate, protect from git
    clean)" (:85). 10 of 35 reso linked worktrees under `~/Development/.worktrees` hold a `settings.local.json`,
    and all 10 differ from main's copy [M, `cmp` against reso-management-app/.claude/settings.local.json]. **WP-31
    (reso repo, the repo owner decides)** therefore sources `~/.claude/scripts/lib/wt-tombstone.sh` and calls
    `wt_pinned "$p"` and then `wt_tombstone "$p" reso-janitor two-strike` before :155. A missing library, a pin, or
    a failed tombstone **keeps** the tree and logs `kept=<b>:<reason>`. It also replaces :157 with
    `wt_prune_logged`. Until WP-31 lands, X6's coverage is 5 of 7 and **reso's residue is unprotected**.
  - branch-prune-landed writes `branch-deleted` rows, so a later restore knows to use the sha.
  - **Residue rule, corrected in revision.** The draft left `.env*` and `.claude/settings.local.json` out of every
    tar because "provisioning re-copies them". That premise was false. scripts/new-worktree.sh:92-98 copies them and
    never symlinks them, precisely so that each worktree mutates its own settings.local.json. G §1.5 measured 87 of
    those files destroyed, plus 3 `.env.local`. A restore that takes main's current copy loses the worktree's accrued
    permission grants, so the resumed session re-prompts and runs slower, and any edit to `.env.local` is gone. Now
    a provisioning file is left out only when `cmp` shows it byte-identical to the main checkout's copy at tombstone
    time. Otherwise it goes in the residue. The tombstone dir is created 0700 and its files 0600 (`umask 077`),
    because they hold secrets.
  - **Cache rule, restored from G §5.1 (c) and §5.2, widened to G's full allowlist in the second revision.** A
    path is a cache only when `git check-ignore -q` is true **and** it is on G §5.1's allowlist. The first
    revision named only `node_modules` and `.venv`, so the rest of the allowlist fell into residue and was tarred,
    or the tree was KEPT once it passed 50 MB. On the guard path that meant a refused session removal. The
    ledger shows how often these paths go: `__pycache__` 908 destroyed, `.ruff_cache` 170 (G §1.5). The allowlist
    has two tiers:
    - **Always regenerable:** `.next`, `__pycache__`, `.ruff_cache`, `.pytest_cache`, `.mypy_cache`, `.turbo`,
      `.eslintcache` and `*.tsbuildinfo`. They are build or tool outputs with no lockfile, as G §5.1 (c) has it.
      7 of 8 sampled worktree `.next` dirs are 72-195 MB [M, `du -sk`, `ls -d ~/Development/.worktrees/*/.next`
      gives 24], so under the first revision's rule every such Next.js tree would have been KEPT or refused.
    - **Reproducible only from a lockfile in the tree:** `node_modules` and `.venv`.
      - `.venv`: `uv sync --check --locked` (uv 0.12.17 has `--check` [M, `uv sync --help`]) exits 0;
      - `node_modules` with pnpm: `node_modules/.pnpm/lock.yaml` `cmp`-equal to `pnpm-lock.yaml`;
      - `node_modules` with npm: `npm ls --all` exits 0.

    The row records `lockfiles: {name: sha256}`. A cache dir with no lockfile, or one that has diverged from it
    (ad-hoc `uv pip install`, private-index or licensed wheels, a hand-patched module), counts as residue. On the
    guard path, a check that does not finish inside the hook's bound also counts its dir as residue. Never an
    arbitrary ignored path: `.env*`, `*.db`, `*.sqlite`, `brag-output/`, `screenshots/`, `out/`, `dist/`,
    `asset-workspace/` and `.claude/settings.local.json` are always residue.
  - **Residue capture, second revision: a clone or a move, no cap.** The first revision tarred the residue and
    KEPT a tree over 50 MB. A tar is O(bytes), and the cap turned a large residue into a refusal. Both
    `~/.claude/autonomy` and every worktree root in use (`~/Development/.worktrees`, `/private/tmp`,
    `/private/var/folders`) sit on one APFS volume, device 16777233 [M, `stat -f %d`]. So residue goes into
    `~/.claude/autonomy/worktree-tombstones/<id>/residue/` by one of two same-volume operations. A background
    actor that removes immediately afterwards (worktree-gc, teammate, handoff-fire, WP-31) uses `mv`, a rename.
    The guard, which runs before the permission decision, uses `cp -RPc`, clonefile(2), which copies no data blocks
    and leaves the tree untouched. Both are O(entries), lossless, and need no cap, so **no tree is KEPT and no
    removal is refused for size**. If a `mv`-ed tree's removal is then refused by git, the caller moves the
    residue back before it logs the refusal. A cap and a tar (50 MB, over the cap → KEEP) apply **only** when
    `stat -f %d` of the tree and of the tombstone dir differ, which is true of no tree today.
  - **Retention, second revision.** The residue (moved or cloned), the `guard-snapshot`, `admin-pruned` and
    disposal rows, the copied `logs/HEAD`, and the park index **never expire automatically**, because disk is not
    binding. They hold exactly the gitignored paid assets that .gitignore files warn about:
    - reso-landing-app/.gitignore:39-41 reads "paid AI source renders … Never `git clean -x` this away", and the
      main checkout's `asset-workspace` is 48,992 KB [M, `du -sk`], just under the old 50 MB cap;
    - reso-management-app/.gitignore:85 on origin/main lists expensive generated image assets.

    A residue is removed only by an explicit operator command (`wt-tombstone purge <id>`, never run by an agent or
    a janitor), or when every file in it is `cmp`-identical to a copy that still exists (the restored tree or the
    main checkout). **A ref expiry never removes residue**, and refs/wt-tombstone expire on the effective
    `cleanupPeriodDays` (§3.2), not on a fixed 30 d. A bats case asserts both (WP-9).
- **X10, kill-resume journal (added in revision).** pytest's own `--lf` cache cannot do this job: it is written at
  session end, so a SIGKILLed run leaves nothing. The journal works like this:
  - **Writing.** `tests/_gate_journal.py`, loaded only by `gate.sh`, appends one line per `pytest_runtest_logreport`
    (call phase, plus setup errors and skips) on the xdist controller: `nodeid outcome skip_reason`. The file is
    `<git-common-dir>/gate-journal/<tree>-<salt>.jsonl`, where `tree` is `git write-tree` of the index plus a hash
    of `git status --porcelain` for untracked inputs, and `salt` is the same `uv.lock` + Python + AGENTSYNC_*
    switch set that `gate-verdicts.log` uses. Each line is one unbuffered `os.write` append with no fsync. A SIGKILL
    leaves every completed write in the kernel, so at most a torn last line is lost, and the reader drops it.
  - **Resuming.** `gate.sh` may start on a tree and salt whose last journal has no summary line and no live holder,
    meaning the run died: rc 137, or a log ending in xdist `OSError: cannot send (already closed?)`, which
    `gate-verdicts.log` records when `gate.sh` itself survived. It then passes the journal's passed nodeids as
    `--deselect` and runs the remainder. The verdict combines both, and the log says
    `resumed=<n_passed_from_journal>`.
  - **Scope.** Lane pre-gates and lane full runs only. The land gate never reads the journal, and a changed tree or
    salt starts fresh.
  - **Skips stay visible.** `skip_reason` is kept per test, so the load-gated `@timing` skips (conftest.py:103-115,
    the A-R3 objection) are counted in the verdict line as `skipped_timing=<n>` across both halves.
  - **Equivalence.** The verdict equals what the unkilled run would have produced for the same tree, except for a
    flaky test that passed before the kill and would have failed after it; a full fresh run does not rule that out
    either. Order-dependent interactions between halves are not exercised, and that is what the unchanged land gate
    is for.
- **X17.** This is sequenced last on the instrument track. The load rung is today the only signal that saw the
  2026-08-05 node-spawn burst (capacity-alarm.sh:155-158), so it stops counting toward the verdict only after D2
  (§4) has run in record-only mode for 7 days. pool-floor.sh:106 counts verdict=OK rows as healthy; its population
  grows from 1,570 to about 3,371 [M], so the re-derived floor is written down as a declared change.

---

## 3. Event-driven worktree lifecycle

### 3.1 Principle

Pruning becomes safe to run on events once every action is **reversible**. Adding gates or sweeping more often does
not achieve that. Today, removal cannot be undone:
- 7 actors remove worktrees and 2 write a tombstone; 0 of 637 rows carry the repo [M];
- resume recreates a reaped cwd as an **empty** directory (lib/cc-resume-shell.sh:138-155).

So the safe actors keep 163 unlanded or dirty trees indefinitely and wait for hand-written warrants, while ad-hoc
removals strand 147 resumable transcripts [M]. The design:
1. makes every automated action recordable (X6) and undoable (X7);
2. makes a lossless PARK the **default action for every quiescent tree**, landed-clean ones included (second
   revision). A path is freed by a same-volume move that keeps caches, untracked files and the reflog. A real
   removal (DETACH) waits until no transcript can resume the tree, or until disk pressure;
3. drives everything from events, with the 04:15 sweep kept only as a backstop.

### 3.2 States and predicates

**G-live** (all must pass, using the existing oracles unchanged):
- `is_live_cwd`, `registry_live` (scripts/worktree-gc.sh:503), `session_registry_occupied` and
  `session_occupancy_keep` (:559-600), `op_in_progress` (:755);
- not locked, no `.teammate-busy`, not in `CC_WTGC_EXCLUDE`, not a pool slot (`wt-pool-N`, which the pool re-lets);
- an act-time `recheck_live` (:951) of `recently_active` and lsof immediately before any move or remove ("Ship owns
  the tree": removing a cwd under a running process turns its git calls into exit 128).

**Grace** (all must pass, measured per cwd):
- **≥24 h (`GRACE_PARK_S=86400`; named `GRACE_DETACH_S` before the second revision, since it now gates PARK arm
  (i))** since the last SessionEnd or registry removal **and** since the last transcript write for this cwd, with
  "transcript" defined as for PARK below. *Amended in revision from 30 min.* In claude-infrastructure today a
  landed-clean tree survives until the next 04:15 run, between 0 and 24 h. G §1.4 [M] counts 36 landed-clean trees
  under 1 d old with resumable transcripts. At 30 min each would have lost `node_modules` and `.venv` and come back
  through a restore, and lr-fire-resume would bring them back with no residue at all, which the draft's own X7 claim
  ruled out. The speed bought no load either: idle trees cost about 0 (G §0) and disk is not binding (3.71 TiB
  free). The first revision then said "24 h is the longest a tree survives today". **That is true only under the
  infra nightly (second revision).** worktree-gc-infra-run.sh:22 hardcodes one repo. In doc_classifier,
  reso-web-app, lakehouse-lecture, sevenrooms-bridge and personal, trees live indefinitely unless cc-reaper catches
  them at teardown:
  - G §1.2 lists about 60 landed-clean trees over 7 d old in those repos (doc_classifier 26, reso-web-app 13,
    lakehouse-lecture 10, sevenrooms-bridge 8, personal 2, plus reso-landing-app 1);
  - G §1.4 counts 7 landed-clean trees with transcripts 7-30 d old;
  - only reso-management-app has a SessionStart install hook [M, `jq '.hooks.SessionStart'` of each repo's
    `.claude/settings.json`]. The global `worktree-setup.sh` fires on WorktreeCreate only [M, `jq` of
    ~/.claude/settings.json].

  So a 24 h DETACH, once a repo was promoted, would turn a day 2-30 resume that works today into a restore with
  `node_modules` and `.venv` gone. It would also discard reflog-only commits (DETACHED row). The grace now only
  gates **PARK**, which loses nothing. Shortening it is a declared change, made after the X7 phase-1
  `resume-reaped.jsonl` shows the restore rate and the cost of each restore at load;
- plus the existing `ACTIVE_MIN` (30) untracked-write check and the `IDLE_MIN` (30) tip floor (:28, :257-259).

The tip floor alone fails here: a landed tree with an old tip would otherwise qualify 60 s after its session ends.

**Pins** (KEEP while present; every pin is derived and expires, so none can leak):
- a CRASH row in `~/.claude/logs/claude-crashes.jsonl` whose sid's transcript cwd is this path, younger than 7 d, and
  with no later SessionStart for that sid. 3,395 CRASH rows exist, 92 on 10-16 [M], so a stored lock with no unpin
  would freeze collection. hooks/lead-crash-watchdog.sh needs no edit;
- an open cc-backlog row or plan doc naming the path;
- a positive owner signal: a live session whose branch namespace or plan covers the branch, or a commit minutes old
  (docs/lessons/a-cwd-census-cannot-see-a-worktrees-owner.md);
- **(added in revision) an open resume record** in any store that records "this cwd will be resumed". Each pin
  expires with its record, and in any case at the effective `cleanupPeriodDays`. *Corrected in the second
  revision:* that value is **365 d** in ~/.claude/settings.json, which the other config roots symlink. Only
  `.claude-next4` has no settings file, so it takes the default of 30 d [M, `jq .cleanupPeriodDays` and
  `readlink` per root]. At least 300 transcripts in ~/.claude/projects are older than 30 d [M,
  `find -maxdepth 2 -name '*.jsonl' -mtime +30 | wc -l`]. So the first revision's "30 d" understated how long a
  transcript stays resumable. Every "cleanupPeriodDays" below means the maximum over the config roots, read at
  run time:
  - an open debt under `~/.claude/autonomy/resume-debt` (`bin/cc-resume-debt:1-19`: a close is a debt until the
    resumed session is proven alive), keyed through its sid's transcript cwd;
  - a limit-recover resume that is queued or not yet proven, under `~/.reso/limit-recover/<sid>/`. lr-select's rows
    carry `acct sid cwd branch` (scripts/limit-recover/lr-select.py:54), and lr-reset-poller resolves cwd from the
    transcript (lr-reset-poller.sh:599-606). This matters most: limit-recover waits hours for a quota reset, longer
    than any grace, so without the pin a landed tree could be DETACHED under a queued resume;
  - a recycle-failed packet `~/.claude/autonomy/recycle-failed/<sid>.json`. Its keys are `sid`, `relaunch_cmd`,
    `refire_cmd` and others but no `cwd` [M, key list of the newest packet], so it is keyed through the sid's
    transcript;
  - a boot-resume event or snapshot under `~/.claude/autonomy/boot-resume` (scripts/boot-resume.sh:129) or a
    cc-resume-layout tree snapshot (bin/cc-resume-layout.sh) whose rows name the path, until that event is marked
    done.

**One predicate, called by every remover (added in revision).** The draft derived the crash pin only as
`CC_WTGC_EXCLUDE` in the worktree-gc wrapper. But bin/cc-reaper `worktree_cleanup` (:1756-1830) has no exclude or
pin check, hooks/teammate-auto-shutdown.sh does not read it either, and cc-reaper is the remover that fires right
after a crash, on pane teardown (G D8). So "KEEP for 7 d unless the sid is resumed" did not hold for that remover.
Two layers fix it:
1. **`wt_pinned <path>`** in scripts/lib/wt-tombstone.sh (WP-9) evaluates every pin above from its source with
   bounded reads: a 7 d tail of the crash log, one directory listing per resume store, and sid → cwd through the
   transcript. It returns the pin kind. worktree-gc, teammate-auto-shutdown (before :1559), handoff-fire (before
   :16609) and, through WP-31, reso's janitor (before its :155) all call it, and a pinned tree is KEPT with the
   kind logged. *Second revision:* cc-reaper no longer removes. It enqueues, so the wake run applies the pin. This
   closes the window between a crash and the janitor's next run.
2. **Materialized as a lock for removers outside this design.** Each wake or due-tick run takes every pinned,
   unlocked tree **inside its repo scope** and applies
   `git worktree lock --reason "cc-pin:<kind> sid=<sid> until=<epoch>"`. *Scope added in the second revision:* the
   lock and unlock step uses the same `--path` table as every other action (§3.4, "How a wake run evaluates").
   reso-management-app is skipped and logged `scope=excluded`, because a lock there would also stop reso's pool
   (`scripts/worktree-pool.sh`) and its janitor, which calls `wt_pinned` itself under WP-31. A repo not listed in
   `worktree-gc-repos.promoted` gets `would_lock` / `would_unlock` log lines only. A raw
   `git worktree remove`, and even a single `--force`, then refuses it; git needs `--force` twice for a locked tree.
   The same run unlocks only locks whose reason starts with `cc-pin:` and whose record has closed or whose `until`
   has passed. It never touches a human lock or a PARK lock. A tree that is already locked is already protected and
   is skipped. This is G's original lock design, made derived and self-expiring so it cannot freeze collection.

| State | Entry predicate | Action | Reversal |
|---|---|---|---|
| ACTIVE | default; any G-live oracle positive, or inside grace | none | n/a |
| QUEUED | an event names the path (§3.4); `not_before = event_ts + GRACE_PARK_S` (24 h; amended in revision from `max(IDLE_MIN, ACTIVE_MIN) + 1 min`; renamed in the second revision, because the grace now gates PARK) | wait | n/a |
| PARKED (**the default quiescent action, second revision**; replaces G-P1-5 "detach unlanded" and the first revision's 24 h DETACH) | G-live ∧ no pin (`wt_pinned`) ∧ no positive owner signal ∧ no submodules, and one of: **(i) landed-clean**: `landed()` (:630, `git cherry` zero `+`) ∧ (clean ∨ `dirt_landed` :655) ∧ no untracked non-ignored files ∧ grace (≥24 h since the last SessionEnd or registry removal **and** the last transcript write); **(ii) anything else** (unlanded, dirty, untracked, detached HEAD): tip ≥7 d ∧ newest transcript for this cwd ≥7 d ∧ **newest working-tree file mtime ≥7 d** (legs below) | `git worktree move <path> ~/Development/.worktrees/.parked/<id>`, then `git worktree lock --reason "parked <ts> from <path> sids=<…>"`, plus a tombstone row `event=worktree-parked` and an index entry `~/.claude/state/wt-parked/<sha1(path)>` holding `<repo> <parked-path>`. This is a same-volume rename, O(1): nothing is deleted, and caches, untracked files, reflog and config.worktree are all kept. **Second revision:** for arm (i), with HEAD on a branch, it also runs `git -C <parked> checkout --detach`. That rewrites HEAD only, with no file change, and adds one reflog entry. The row records `branch` and `branch_tip`. Detaching lets branch-prune-landed and `--prune-branches` still delete a landed branch, which git refuses while a worktree has it checked out. An arm (ii) tree stays attached, so the guard's `branch -D` refusal (hooks/git-worktree-guard.sh:62-65) keeps covering an unlanded branch. Detaching would gain nothing there, since nothing automated deletes unlanded branches | `wt_unpark <path>` (WP-9): look up the index by path, then `git worktree unlock` and `git worktree move` back to the exact original path. **Path-match, no sid needed (amended in revision):** it is lossless and pool slots are never parked. An occupied path is refused, except a NOGIT husk holding only `.claude-*` or `.next` entries (what cc-resume-shell's `mkdir -p` at lib/cc-resume-shell.sh:151 and a session's first writes leave). Such a husk is moved aside to `<path>.husk-<ts>`, never deleted, and then the move proceeds. **Re-attach (second revision):** if the recorded branch still exists, is checked out in no other worktree, and its tip equals HEAD, run `git checkout <branch>`, a HEAD rewrite only. Otherwise stay detached at the same commit and log `reattach=skipped:<reason>`. The files are identical either way. O(1), no reinstall |
| DETACHED (late; second revision) | PARKED by arm (i) ∧ the newest transcript for this cwd is **older than the effective `cleanupPeriodDays`** (365 d today [M], §3.2 pins), so no `--resume` can target the path ∧ the lockfile rules of note X6 | `git worktree unlock`, then `wt_tombstone`: the row, the residue `mv` (note X6; no cap on one volume), the tombstone ref and the **reflog refs** below. Then `git worktree remove` without `--force`, then `verify_preserved` (:990). **Tombstone ref, amended in revision:** `refs/wt-tombstone/<id>` is created at the head **unless** `git merge-base --is-ancestor <head> <trunk>` holds. The draft created it only for a detached HEAD, but `landed()` is patch-id based, and worktree-gc.sh:630-637 records that 638 of 721 landed branches had tips that are **not** ancestors of trunk, because rebased lands rewrite the objects. After `--prune-branches` or branch-prune-landed plus a `fetch --prune`, such a head is unreachable and gc may delete it. **Reflog refs, second revision:** removal deletes `.git/worktrees/<id>/logs/HEAD`. A commit reachable only from that reflog (after a reset, amend, squash or rebase inside the tree) is work that `landed()` cannot see, because it runs `git cherry` on HEAD, and gc may then delete it. Before any DETACH, for every reflog commit that `git rev-list --stdin --not --branches --tags --remotes` returns and for which `git cherry <trunk> <c> <c>^` prints `+`, create `refs/wt-tombstone/<id>/reflog-<n>`. Then copy `logs/HEAD` into the tombstone dir. A ref that cannot be created keeps the tree PARKED. [M, /tmp/dz-reflog-probe.sh over the first 40 infra worktrees]: 7 of 40 hold such commits (33 in all), and 2 of those 7 are landed-clean (23 commits), which made them first-revision DETACH candidates. The commits in one of them read as rebase and fixup intermediates (`git log -1 --format=%s`), so most are probably superseded drafts. The predicate cannot tell, and a ref costs about 0. The refs are kept for at least the effective `cleanupPeriodDays` after the DETACH. After that the janitor deletes refs that no restore has used and records `ref-expired`. A ref expiry never removes residue (note X6, Retention) | `cc-wt-restore`: `git worktree add --detach <path> <head>` (never re-create a pruned branch with `-b`), put back the residue, reinstate the copied `logs/HEAD` as the worktree's reflog, provision lazily |
| ARCHIVED | PARKED ∧ **a disk-pressure event** (free space below an operator-set floor). *Second revision:* with PARK the default, this path is a real backstop and no longer "never". [E] If every removal at today's rate became a park, 18.3 trees/day (the mean of G §1.6's 14 daily counts [M]) at ≤0.54 GB each (156 GB / 291; an upper bound, since per-tree `du` counts APFS clones and pnpm hardlinks in full) gives ≤9.9 GB/day, or ≤3.6 TB after 365 d, against 3.71 TiB (4.08 TB) free today [M]. The floor is the operator's, recorded in the activation script. Trees go oldest newest-transcript first | `git bundle` of any branch with unlanded patches, the reflog refs and residue as for DETACHED (a cap only across volumes), then remove | `git fetch <bundle>`, then as DETACHED |

**PARK's activity and transcript legs (added in revision; they gate arm (ii) only, since arm (i) is gated by the
24 h grace).** Tip age does not move with uncommitted edits, and
`recently_active` (:616-628) looks back only 30 min. G §1.4 [M] counts many trees with no transcript at all: 48
landed-clean, 73 unlanded and 52 dirty. G also scanned only 4 config roots, while 6 have a `projects` dir [M,
`ls -d ~/.claude*/projects`]. A tree edited 2 days ago by a human or by Cursor (17 Cursor processes, E §2), or by a
session in an unscanned config dir or a subdirectory cwd, would otherwise be moved and leave nothing visible at its
path. So:
- **Working-tree floor.** `find <path> -name .git -prune -o -mtime -7 -print -quit` must print nothing. It is one
  bounded walk that stops at the first recent file, and it runs only for PARK candidates. Today's 30 min check stays
  the KEEP gate for everything else.
- **Transcript coverage.** "Newest transcript" is the newest `*.jsonl` mtime over **every** `~/.claude*/projects/*`
  slug that prefix-matches the path's slug. That covers the subdirectory-cwd slugs (AC-6) and the
  `<sid>/subagents/**` transcripts, and the scan is over all 6 roots.
- **No transcript means unknown, not old.** For such a tree the transcript leg fails closed. PARK then also needs the
  worktree's own git activity to be ≥7 d old: the mtime of `$(git rev-parse --git-dir)/logs/HEAD` and of its
  `index`, which a checkout, commit, reset or `git add` by anyone updates. Without that, it stays KEPT and reported.

PARK also has these properties:
- A locked record short-circuits gate 2 (:1127) before the status fork (:1132), so sweeps stop walking parked trees.
  The `.parked` path is dot-prefixed, so Spotlight already skips it.
- Parked trees stay in `git worktree list`, so `stranded_scan` (worktree-gc-infra-run.sh:162-185) still counts their
  branches: parking cannot hide the landing alarm.
- Population reporting splits into `pop_active` and `pop_parked`. The ceiling applies to active trees only.
- This settles the AC-2 dispute (WORKTREE_MANAGEMENT_V2.md:358-375). An ignored-only tree is neither kept as inert
  nor destroyed. *Second revision:* it is PARKED, by arm (i) if landed. It is DETACHED with its residue preserved
  only after the effective `cleanupPeriodDays`.
- **Load (second revision).** A park is one rename, one lock, one append and, for arm (i), one HEAD rewrite. A
  DETACH also walks and deletes the tree. Making PARK the default moves the delete work off the event path. It
  also skips the lockfile checks (`uv sync --check`, `npm ls --all`), which now run only for the rare late
  DETACH. So the wake run's machine work per tree falls [E: by construction].

### 3.3 What WORKTREE_MANAGEMENT_V2 and prior work already provide

- **Met and kept unchanged:**
  - AC-1, the `--ignored` inventory;
  - AC-3, disposal ledger rows with `destroyed_ignored`;
  - AC-7, `CC_WTGC_DISABLE` plus a file kill switch;
  - AC-8 (plan §7.4:374-379, §8);
  - gates 1-6 and no `--force` (worktree-gc.sh:32-34); lock honoured (:1127);
  - live-session protection (:1135-1141); A2 ownership oracles (backlog `wt-<id>`, team `wt-tm-*`, :45-60);
  - the warrant path;
  - the landed-dirt class (E4 edge, plan §9; on since 2026-09-30, worktree-gc-infra-run.sh:463-473).
- **Open, and still required (taken into WP-10):**
  - AC-4: a distinct verdict token when the trunk is unresolvable;
  - AC-5: refuse on a degraded oracle;
  - AC-6: subdirectory-cwd and command-position liveness (plan §7.4:377);
  - F-9: lock heartbeat (plan §3:227).

  The 2026-08-10 edges E1, E2, E3, E5, E8 and E9 were never built (G §2).
- **Never addressed, and added here:**
  - repos other than this one (worktree-gc.sh:13-15 is single-repo by construction);
  - the resume dependency;
  - the 5 removers that write no tombstone;
  - event triggering.

  Prior art for events exists in reso: `gl.reso.worktree-gc` uses WatchPaths on `~/.reso/worktree-gc.wake`, a 60 s
  debounce, a mkdir singleton and two-strike grace (reso `scripts/launchd/bin/worktree-gc-run.sh:43-66`). This
  design ports that pattern.

### 3.4 Events and the code that emits them

Every emit is one `printf >>` of `{ev,path,sid,repo,ts}` to `~/.claude/state/wt-events.jsonl` plus a `touch` of
`~/.claude/state/worktree-gc.wake`. The queue file is the source of truth; the wake file is only a hint (memory-econ
§15: the janitor re-derives everything at act time).

| Event | Emit site | Effect |
|---|---|---|
| SessionEnd | hooks/live-session-registry.sh:47-56 (the payload already has cwd, sid and reason) | enqueue cwd |
| Pane teardown | bin/cc-reaper `worktree_cleanup` :1756-1822, called at :2672 (today it removes any clean linked tree, at :1814, within one 300 s sweep) | **Second revision: enqueue only; it never removes.** One append of `{ev:"pane-teardown",path,sid,repo,ts}` plus a touch of the wake file replaces the remove. The wake run applies the 24 h grace, pins, repo scope and PARK-first rule (note X6). The first revision kept a zero-grace removal here |
| Teammate close | hooks/teammate-auto-shutdown.sh:1559-1564, inside the detached subshell :1537-1568 | `wt_pinned`, then the full tombstone with checkpoint_ref and the residue moved (second revision; was a tar), bounded at 300 s. The remove (keeps `--force`) runs only after the tombstone is written (amended in revision) |
| Failed fire | scripts/handoff-fire.sh:16609 | `wt_pinned`, then the same tombstone; its residue is normally empty (the `cmp` rule) |
| Raw `git worktree remove` | hooks/git-worktree-guard.sh:72-145 (already parses it, `-C` normalized at :38-39) | **Second revision:** the tombstone runs inside the hook, bounded under its 10 s timeout. It writes the row and a `cp -RPc` clone of the non-cache residue, plus a `refs/wt-tombstone/<id>/wip` snapshot when the command is forced and the tree is dirty. It then exits 0 with no output, so the permission flow judges the original command exactly as today. On failure it blocks with a reason. The first revision's `updatedInput` rewrite is dropped (note X6) |
| Raw `git worktree prune` (new, second revision) | hooks/git-worktree-guard.sh (a new arm), and `wt_prune_logged` at every scripted prune site (note X6) | `admin-pruned` rows from `git worktree prune --dry-run -v`, a copy of each entry's `logs/HEAD`, and reflog refs for unreachable, non-patch-equivalent commits; then the prune runs unchanged |
| PR merged / remote branch pruned | scripts/branch-prune-landed.sh (autonomy-sweep.sh:946 runs it each tick) | `branch-deleted` row; enqueue that branch's local worktree, if any |
| Crash | none: `wt_pinned` derives the pin from claude-crashes.jsonl at every remover's act time, and the wake run materializes it as a `cc-pin:` lock (§3.2) | KEEP for 7 d unless the sid is resumed, against **every** remover: worktree-gc (and cc-reaper's enqueued trees through it), teammate-auto-shutdown and handoff-fire through the predicate; reso's janitor through it only with WP-31; and raw git through the lock, inside the lock's repo scope (amended in revision; the draft's `CC_WTGC_EXCLUDE` covered worktree-gc only; scope and the cc-reaper change added in the second revision) |
| Resume queued or owed | none: the same predicate reads cc-resume-debt, limit-recover, recycle-failed, boot-resume and cc-resume-layout records (§3.2) | KEEP while the record is open (added in revision) |
| Resume restored | bin/cc-wt-restore | `restored` row; resets grace |
| Drift | D6 in §4 (GC rc ≠0, or registered growth >20 since the last OK row) | touch wake + one condition-keyed backlog row |
| Wake actuator | launchd/com.claude.worktree-gc-infra.plist: add `WatchPaths` on the wake file **and** `StartInterval 600`, which exits in O(1) when nothing is due | **Corrected in revision.** The draft said "operator bootout and bootstrap", but the label is declared `run` (launchd/fleet.manifest:370), and install.sh reloads a changed `run` plist on the next 600 s deploy advance (install.sh:1292-1317, then bootout and bootstrap at :1374-1382), which deploy-live runs on converge. So the plist edit goes live when it lands. The safety stage is therefore in code: a wake or tick run acts only when `WTGC_EVENTS=act`, and the default is `observe`, which evaluates and logs `would_detach` / `would_park` / `would_keep` with reasons and touches nothing. The switch file `~/.claude/autonomy/worktree-gc-events.mode` (one word: observe or act) is written only by the explicit activation script `docs/activation/pending-activation/NN-load-2026-10-17-activate.sh`, after the observe log and the §3.7 lab are reviewed. The 600 s tick fires due entries whose wake was debounced, and is the fallback if WatchPaths stops delivering during an fseventsd fault (open question Q8) |
| Backstop | the existing 04:15 calendar run | full sweep. Repos other than this one: resolve the trunk with `git symbolic-ref refs/remotes/origin/HEAD` and skip repos with none. reso-management-app is excluded, because it has its own janitor. That janitor's removals get a tombstone only through WP-31; until then they remain unprotected (note X6). Each such repo is **observe-only first** (`WTGC_OBSERVE=1`) until the operator promotes it (OP-5). After that it parks first (§3.2) and never runs `--dispose-landed-dirt` or `--prune-branches`. Each repo is listed by its own porcelain, never by glob (worktree-gc.sh:13-15) |

Dropped emits: the ship-land `attest_land` emit, because at land time the session is still live in the tree and
SessionEnd follows anyway; and "fetch flipped to landed", because detecting it is the sweep itself.

How a wake run evaluates:
- only due entries, by the new `--path` mode;
- **repo scope first (added in revision).** SessionEnd (hooks/live-session-registry.sh) enqueues every cwd, while
  §3.4's backstop excludes reso-management-app and runs other repos observe-only until promoted. Without a scope
  check, a wake run could DETACH or PARK (move plus lock) a reso tree that reso's own janitor and
  `scripts/worktree-pool.sh:592,629` (reso) manage, or act on another repo before its observe-only phase. So
  `--path` first drops a path that is not a linked worktree. It then resolves the repo with
  `git -C <path> rev-parse --path-format=absolute --git-common-dir` and applies the backstop's table before any
  action: reso-management-app is skipped and logged `scope=excluded`, and any repo not listed in
  `~/.claude/autonomy/worktree-gc-repos.promoted` gets observe-only, whatever `WTGC_EVENTS` says. *Second
  revision:* the same table governs the `cc-pin:` lock and unlock step (§3.2 layer 2). The promoted file has one
  owner: **the operator writes it (OP-5)**, one absolute common-dir per line, after reviewing that repo's
  `would_park` / `would_detach` / `would_lock` log. No agent or script writes it. WP-15's code only reads it, and a
  bats case greps the shipped sources for any writer;
- **no fetch** (it uses the last-known trunk: a stale trunk can only turn a remove into a keep, per
  worktree-gc-infra-run.sh:394-397), and no `--prune-branches`;
- dequeue only on a terminal decision (PARK, DETACH, or a non-time KEEP such as dirty-and-young or locked). A PARKED
  tree is not requeued: the late DETACH (newest transcript older than the effective `cleanupPeriodDays`) and the
  disk-pressure ARCHIVE are found by the 04:15 backstop, which reads the park index;
- time-based KEEPs are requeued with a new `not_before`;
- singleton lock plus 60 s debounce, as in reso.

`worktree-gc` matches cc-reaper's GARBAGE_WL (bin/cc-reaper:725 [M]), so the job is not reaped at 600 s.

### 3.5 Keeping references alive, and restoring automatically on resume

`SessionStart(source=resume)` fires too late, because the cwd must exist before Claude Code resolves the transcript
(bin/cc-resume-resolve:5-14). Restore therefore lives in the launchers:
1. **Phase 1 (logging demand, first commit).** Every `cwd_exists=0` recreate in lib/cc-resume-shell.sh:152, every
   reso-resume-one refusal, and every lr-fire-resume.sh exit at :521/:523 writes a row to
   `~/.claude/autonomy/resume-reaped.jsonl`, carrying the cwd's age since its last transcript write. Today they
   print to the TTY only, so demand is unmeasured. This ledger is also what may later shorten the 24 h PARK grace,
   or bring the late DETACH below the effective `cleanupPeriodDays` (§3.2). Either is a declared change.
2. **Matching.** `bin/cc-resume-resolve` emits `tomb_repo/branch/head/state/preserved` only when the tombstone's sid
   list contains the resumed sid, or its branch equals the transcript's last `gitBranch`. Matching on path alone is
   unsafe, because pool paths are re-let to other sessions.
   **PARKED is the exception (amended in revision):** unpark matches on **path alone**, through the park index
   (§3.2). It restores the exact tree that stood at that path, so it is lossless, and pool slots are never parked,
   so the re-let objection does not apply. Without this, PARK would break resumes that work today. Today a 7-30 d
   idle tree still exists, so every resume path works. Once it is parked: reso-resume-one's
   `git worktree add "$wt" "$br"` (:491-492) fails, because the branch is checked out at `.parked/<id>`, and then it
   calls `rr_refused_exit`; the draft's sid-only restore would not have caught it; and lr-fire-resume.sh has its
   own recreate path (below).
3. **lib/cc-resume-shell.sh:138-155.**
   - PARKED: `wt_unpark <path>` before the `_cwd_exists != 1` branch (O(1), lossless; no prompt and no sid needed).
     It re-attaches the recorded branch when it is still free at the same tip (§3.2, PARKED reversal). Under the
     second revision this is the common case: every quiescent tree, including a landed-clean one a day old, comes
     back by unpark, never by restore.
   - DETACHED: a default-yes prompt, "restore worktree <branch>@<head> (~N files)?", which runs `cc-wt-restore`.
     Answering no keeps today's `mkdir -p` and prints the one-line command.
   - No tombstone: today's behaviour.
4. **bin/reso-resume-one:439-545.** `wt_unpark "$wt"` runs first, before the `[[ ! -d "$wt" ]]` recreate at :476.
   A DETACHED tree is restored only on a sid match. Otherwise the deliberate refusal for gone branches stays
   (:472-474, :486-509): a prompted unattended resume must never revive work that has already landed. The existing
   identity check (:497-545) still guards an occupied path. cc-resume-layout and cc-relayout launch through
   reso-resume-one (bin/cc-resume-layout.sh:167), and so do boot-resume (scripts/boot-resume-launch.sh) and the
   pane successor, so they inherit both behaviours.
4a. **scripts/limit-recover/lr-fire-resume.sh:491-523 (added in revision).** This is a third, independent
   recreate-from-branch path, which the draft left out of X7 and WP-13. It exits 1 when the add fails (:521) and 2
   when the branch has been pruned (:523). It gets the same two steps as reso-resume-one: `wt_unpark "$WT"` before
   :492, and a DETACHED restore through `cc-wt-restore` only on a sid match, placed before the exit-2 refusal. Its
   per-repo git lock (:498-503, released at :520) also wraps the unpark, because `git worktree move` writes `.git/worktrees` like an
   add does.
5. **Legacy rows** (637, no repo): restore only the tracked tree, inferring the repo by
   `git cat-file -e <head>^{commit}` over `~/Development/*` and accepting exactly one match. Never claim the residue
   comes back.
6. **The restored tree** gets a `restored` row that restarts its grace clock, and the resumed session's
   SessionStart makes it live again; it cannot be re-reaped while in use.
7. **Optional.** hooks/git-worktree-guard.sh prints a one-line `cc-wt-restore` hint on a `cd` or `git -C` into a
   tombstoned path, at the cost of a single stat. It never runs the restore itself.

### 3.6 Why none of this slows a session

- Each emit is one append and one touch, in hooks that already run.
- The janitor runs in its own launchd job.
- Total work falls:
  - each wake costs O(due paths), against a 370 s, ~290-tree sweep [M];
  - parked trees drop out of every sweep;
  - the 4 red cc-gc runs a day disappear (X8);
  - the reactive "prune old worktrees" sessions (~10 since 2026-08-25 [E]) have nothing left to do.
- Resume becomes correct instead of opening an empty dir. Unparking is O(1) on a path match in every launcher. A
  DETACHED restore costs seconds of checkout [E], logged per restore. *Corrected in revision:* at the draft's 30 min,
  same-day resumes that work today would have paid it. *Corrected again in the second revision:* the first
  revision's defence ("DETACH waits ≥24 h, the longest a tree survives today") held only for claude-infrastructure.
  The defence now is that every quiescent tree is PARKED, so no automated actor removes a tree while any
  transcript can still resume it, absent a disk-pressure event. cc-reaper's teardown removal is now an enqueue as
  well (note X6).
- No session removal is refused or slowed for size. The guard clones residue in O(entries) inside its hook and
  never rewrites the command, so the permission flow is unchanged (note X6). A session's "prune old worktrees" run
  is therefore never pushed toward `rm -rf`, which writes no tombstone.
- A resumed tree keeps its own `settings.local.json` grants and `.env.local` edits (the `cmp` rule, note X6), so a
  restored session does not re-prompt.

### 3.7 Verification (throwaway repo only, per the G HAZARD RULE; never real worktrees)

1. **Lab.** States: landed-clean, unlanded, dirty, ignored-only (`node_modules/x` and `.env.local`, with main
   holding its own `.env.local`), detached, locked, checkpointed-dirty teammate, submodule.
2. **Tombstone.** Every removed or parked path has a row with `repo` set. The residue excludes `node_modules` only
   when it is reproducible from the tree's lockfile, and `.env.local` only when it is `cmp`-identical to main's
   (amended in revision; case 7). Locked, dirty-and-young and submodule trees are KEPT. The teammate tree is removed and
   restorable from its tombstone ref. A6's behaviour is unchanged.
3. **Restore.** Land, remove, `branch -d`, then `cc-wt-restore`: HEAD equals the tombstone head and the residue is
   byte-identical. Parked → unpark: identical `git status` and reflog. RED-prove both against unpatched code.
4. **Events.** A SessionEnd JSON with a fixtured HOME writes one queue line and advances the wake mtime. A woken run
   before `not_before` evaluates nothing and requeues; after it, it evaluates only that path.
5. **Equivalence.** Pre-fix and post-fix `--dry-run` over a 50-tree lab give identical REMOVE/DISPOSE sets
   (comparing all of stdout) and fewer `find` calls (PATH shim).
6. **After every run.** `git rev-parse --is-inside-work-tree` on the shared checkout (the lesson "worktree ops can
   bare the shared checkout").
7. **Cases added in revision**, each RED against unpatched code where the defect exists today:
   - **Unpark on resume.** Park a tree, then run `reso-resume-one` and `lr-fire-resume.sh` against its original
     path with a sid that is not in the park row: each ends in a working cwd, with `git status` and reflog
     identical to before the park. Repeat with a `mkdir -p` husk holding only `.claude-tasks` at the path: the husk
     is moved to `<path>.husk-<ts>` and the unpark proceeds. A husk holding any other file is refused.
   - **Crash pin against cc-reaper.** Write a CRASH row for a fixture sid whose transcript cwd is a landed-clean
     tree, then run `worktree_cleanup` as on pane teardown, then a wake run past the grace. The tree survives and
     the wake log names `pin=crash`. After a fixture SessionStart for that sid, or 7 d of clock, it is parkable
     again. A raw `git worktree remove --force` on the materialized `cc-pin:` lock is refused. (Second revision:
     `worktree_cleanup` only enqueues, so the pin is applied in the wake run.)
   - **Resume-record pins.** An open cc-resume-debt row and a queued limit-recover row for a sid whose cwd is a
     landed-clean tree each keep it, past the 24 h grace, through a wake run, cc-reaper and teammate-auto-shutdown.
     Closing the record releases it.
   - **Durable sha.** Land by rebase (patch-id equal, not an ancestor), DETACH, delete the branch, then
     `git reflog expire --expire=now --all && git gc --prune=now` before the restore: `cc-wt-restore` still checks
     out the head, through `refs/wt-tombstone/<id>`. A fast-forward-landed head gets no ref, and its restore also
     passes.
   - **Per-worktree settings.** The worktree's `.claude/settings.local.json` differs from main's (an extra grant) and
     its `.env.local` was edited: both come back byte-identical, and identical copies are left out of the residue.
     The tombstone dir is mode 0700 and its files 0600.
   - **Teammate and guard residue** (amended in the second revision: clone or move, no tar). A teammate tree holding
     `brag-output/x.json` (ignored, not a cache) is removed with the file in its residue, and the hook returns
     before the capture starts. A raw `git worktree remove` through the guard on the same shape is **not
     rewritten**. The hook's stdout is empty, the same residue is cloned, and the tree is byte-identical until the
     command runs. One holding only `node_modules` with a matching lock writes a row and nothing else.
   - **Cache divergence** (amended in the second revision). `.venv` with an extra `uv pip install`ed package (so
     `uv sync --check --locked` fails) is preserved as residue **whatever its size**, and the tree is never KEPT
     for size. `uv sync --check` leaves the mtimes of `.venv` and `uv.lock` unchanged.
   - **PARK floors.** An unlanded tree with a 10 d tip, a file edited 2 d ago and no transcript stays KEPT. The same
     tree with every mtime ≥7 d but no transcript and a 2 d-old `logs/HEAD` stays KEPT. A transcript under a
     subdirectory-cwd slug in a fifth config root counts.
   - **Repo scope.** A reso-shaped tree (common dir under `reso-management-app`) and a tree of an unpromoted repo are
     enqueued by SessionEnd: the wake run logs `scope=excluded` and `scope=observe`, and nothing happens to either.
   - **Activation.** With no switch file, a due landed-clean tree past grace yields `would_park` (second revision;
     was `would_detach`) and stays at its path.
8. **Cases added in the second revision**, each RED against unpatched code (or against the first revision's design)
   where the defect exists:
   - **Teardown keeps the tree.** After a pane teardown, a landed-clean tree whose transcript is younger than 24 h
     is still on disk after the cc-reaper sweep. `wt-events.jsonl` gains one `pane-teardown` row and the wake file
     mtime advances. RED today: removed at bin/cc-reaper:1814.
   - **PARK by default, with detach and re-attach.** A landed-clean tree past the 24 h grace in a promoted fixture
     repo with **no provisioning hook** is PARKED, not removed, and its HEAD is detached. branch-prune-landed can
     then delete its branch. A resume through `_cc_resume_pin` 3 d later ends in the same tree with `node_modules`
     present and `git status` and reflog unchanged. With the branch kept, unpark re-attaches it; with the branch
     deleted, the tree stays detached at the same commit. An unlanded parked tree keeps its branch attached, and
     the guard still refuses `git branch -D` on it. RED against the first revision's 24 h DETACH, which loses
     `node_modules`.
   - **Reflog-only commits survive a DETACH.** In a tree: commit A, `git reset --hard HEAD~1`, commit B, land B.
     Age the newest transcript past `cleanupPeriodDays` on the lab clock, DETACH, delete the branch, then
     `git reflog expire --expire=now --all && git gc --prune=now`. A still resolves through
     `refs/wt-tombstone/<id>/reflog-<n>`. A commit patch-equivalent to trunk gets no ref. `cc-wt-restore`
     reinstates the copied `logs/HEAD`. If ref creation is made to fail, the tree stays PARKED.
   - **Large caches and large residue are never refused.** A Next.js-shaped tree with a 120 MB `.next` is removed
     through the guard with `.next` not captured. One with a 120 MB non-cache `asset-workspace/` is also removed,
     and its residue is cloned: the `df` free-space delta during the clone is about 0, because APFS shares the
     blocks. Neither tree is KEPT and neither command is blocked.
   - **Forced removal of a dirty tree.** A tree with a modified tracked file and an untracked file, removed with
     `git worktree remove --force` through the guard: `refs/wt-tombstone/<id>/wip` holds both files at their
     working-tree content. A fixture hook that denies after the guard leaves the tree untouched, and its row reads
     `guard-snapshot`.
   - **Prune is recorded.** `rm -rf` a lab worktree's dir, then run a raw `git worktree prune` through the guard,
     and separately `reso-resume-one`'s recreate (:490, through `wt_prune_logged`). Each leaves an `admin-pruned`
     row with head and branch, the copied `logs/HEAD`, and reflog refs, and the prune itself runs unchanged.
   - **No new permission surface.** In a scratch config, run a `claude -p` session that issues a guarded
     `git worktree remove` on a tree with residue, once with `--permission-mode default` and once with `auto`. To
     isolate the variable, the lab config allows the original command. Neither run prompts, and the permission
     outcome equals that of the same command with the guard's tombstone arm switched off by a test seam.
   - **Hook timeout (Q20).** A guard stub that sleeps past its configured timeout. Record whether Claude Code runs
     the command anyway. The internal `gtimeout 6` bound must fire first and exit 2.
   - **Retention.** After its ref expires, a tombstone still has its residue. `wt-tombstone purge <id>` refuses
     without the operator flag. A residue that is `cmp`-identical to the restored tree may be dropped.
   - **reso janitor (WP-31, in reso's own repo and lab).** A reso-shaped tree with a `settings.local.json` that
     differs from main's and a `bottle-photography` symlink, through two strikes: the file is in the residue and the
     symlink's target is untouched. With `~/.claude/scripts/lib/wt-tombstone.sh` absent, the tree is KEPT and
     logged.
   - **Lock scope.** A pinned reso-shaped tree and a pinned tree of an unpromoted repo get no `cc-pin:` lock. The log
     reads `scope=excluded` and `would_lock`.

---

## 4. Continuous instrument and alarm

### 4.1 Sampler (X5)

**`capacity-attrib.py --daemon --interval 5`** runs under a new KeepAlive label, `com.claude.capacity-attrib`, in
the Standard band. Nice 10 and LowPriorityIO are dropped: they confound tick stretch, since the sentinel's Standard
band stretches 2× at p90 against capacity-alarm's 4× [M].

Each tick:
- one `sysctl(KERN_PROC_ALL)` read (pid, ppid, stat, comm and start time for every uid; no setuid ps);
- `KERN_PROCARGS2` and `PROC_PIDVNODEPATHINFO` for **new** pids only (argv and cwd, for D1);
- one `proc_pid_rusage` pass over the uid-501 pids;
- counters: `host_processor_info`, `vfs.vnstats.num_newvnode_calls`, `num_recycledvnodes`, `exec_hook_count`,
  `vm.swapusage`, the compressor sysctls, `vm.page_free_count`;
- (added in revision) `lifetime_max_phys_footprint` from the same `proc_pid_rusage` pass. capacity-attrib already
  reads `ri_phys_footprint` (capacity-attrib.py:227), and the struct it uses carries the lifetime field
  (:137). Because the field is a lifetime maximum, a transient that lives only between two ticks is still caught if
  it is alive at one of them;
- (added in revision, in the 60 s pass) the IOKit `IOBlockStorageDriver` `Statistics` dictionary: bytes and
  operations, written and read, through `IOServiceGetMatchingServices` and `IORegistryEntryCreateCFProperty` by ctypes,
  with no fork (`ioreg` shows the same values without root [M]). These become `disk_write_mb_s`, `disk_write_ops_s`,
  `disk_kb_per_write` and a rolling `disk_tb_written_per_day`, the tracked quantity for §1.1c and the SSD-wear
  estimate.

Fork rate comes from the pid cursor. A negative delta is reported as no reading unless elapsed time × the trailing
rate exceeds 50k. Every tick runs inside its own try/except and writes a heartbeat. The 60 s full attribution row is
unchanged, but its setuid ps runs on a bounded thread so it cannot stall the 5 s loop. Output: `attrib-latest.json`,
written atomically, plus a rotated 5 s series.

**capacity-alarm.sh** stays a StartInterval-60 job. It reads `attrib-latest.json` only when the file is under 15 s
old and the daemon's pid@start is alive; otherwise it runs today's one-shot path unchanged (capacity-alarm.sh:842-860).
Its exit-code contract stays: `ok_exits 0,1,2` (launchd/fleet.manifest:199-209), and NO-DATA = 3 still raises the
cc-fleet S4 row (bin/cc-fleet:356-359).

Accounting fixes (I-R3, amended):
- `forks_per_s: null` with `forks_alias: true` when `el_s × 1,567 > 99,899`, i.e. el_s >63.7 s; 1,567/s is the
  measured maximum;
- `accounting = underflow` when `attrib_s < 0` or `uid501_s < 0`; `neg_session` set when `neg_s > 0`;
- `neg_s` also sums negative buckets, `rest` included;
- the reap correction (capacity-attrib.py:597-611) is clamped at 0, and the excess goes to `reap_unabsorbed_s`;
- tests/capacity-attrib.bats:98-101 accepts the null and the new values.

### 4.2 Detectors (I-R2, amended): `scripts/lib/capacity-detect.py`, run inside the daemon over its series

| ID | Signal | Raise (3 consecutive ticks over the high line) / clear (10 min under the low line) | Occurrence key (cause identity; never counts or times) | Remedy text names the streamline action | Sink |
|---|---|---|---|---|---|
| D1 | concurrent full gates in one repo (pytest `-n`/xdist with no file args, bats roots, xcodebuild) | ≥2 roots in one repo | repo + sorted worktree set | "N full gates in <repo>: use gate.sh `--affected` for pre-gates (X10); one land queue" | desk page (acute) |
| D2 | fork/exec storm | pid-cursor rate >2,000/s for 1 min (a physical floor) | parent comm + pid@start, from reaped-child sys-CPU lineage | names the lineage and its fix row | desk page |
| D3 | vnode churn | 5 min window of `num_newvnode_calls` rate >4× its 7 d median **and** >10k/s | `vnode-churn` + top sys-CPU lineage (correlational without root) | names the lineage | chronic backlog row |
| D4 | zombie slope per parent | 1 h slope >0 **and** count >100 | parent comm + pid@start | kitty #10436 → X14 | chronic |
| D5 | MCP fan-out / orphans | server count > live sessions + 2, or ppid-1 servers | server name | X4 / X19 | chronic |
| D6 | worktree drift | GC `.last` rc ≠0, or registered growth >20 since the last OK row | `worktrees:<repo>:<reason>` | touches `worktree-gc.wake` (§3.4) | chronic |
| D7 | instrument starved | tick >3× nominal, or a StartInterval job still running past its interval (read from its state files, no fork) | job label | names the job | chronic |
| D8 | fseventsd unhealthy (user side; complements X2) | CPU delta from the 60 s ps pass ≥0.8 core-s/s for 15 min, or the fseventsd-watch.jsonl footprint ≥1 GB | pid@start | the X1 command | desk page |
| D9 | session-originated memory spike (added in revision; §1.1a) | one uid-501 process with `phys_footprint` or `lifetime_max_phys_footprint` **>4 GB** on **one** tick: the lifetime field is monotonic, so one reading is proof, and the 3-tick rule would miss a 20 s transient. It clears when the pid is gone. Long-lived processes already known at that size are keyed separately, by name, so a slow grower is not re-raised every tick | lineage, not count: the process's comm plus its first two argv words (`git grep`), the session root found by walking ppid to the `claude` ancestor (pid@start), and that session's cwd | names the lineage and, for a known signature, the equivalent-outcome form: `git grep` with a regex on binary files → X25's `-P` (or a pathspec excluding binaries); otherwise "<comm> in session <sid> reached <N> GB" | desk page (acute: one such process can trip compressor-sentinel kills); record-only for the first 7 d like every detector |

Rules for every detector:
- **Keys.** The fingerprint is state, never a timestamp (hooks/lib/page-damp.sh:14-17).
- **Retraction.** A clear retracts the **same occurrence**: desk pages get a follow-up "cleared" page on the same key;
  backlog rows are filed with a `--falsifier` probe. The probe must exit 0 only when the condition is ABSENT ("Arming
  ≠ mootness" lesson), so the row closes itself.
- **Cause or silence.** A detector with no named cause only records; after 6 h it files one `instrument-gap` row.
- **Flapping.** More than 6 raises in a day files one `detector-flapping` row, and the detector drops to record-only.
- **No agent work.** Chronic rows are filed **needs-operator**, never dispatchable, so a detector cannot start agent
  sessions on a loaded box.
- **Never paged:** load per core, the headroom scalar, vnode fill (kern.num_vnodes == maxvnodes by design: the free
  list holds 232-240k [M]), or "close sessions".
- **Rollout.** Record-only for ≥7 d on the new series (today's logs hold none of the inputs D1, D3, D4 and D5 need
  [M, key census]). Then replay with controls: a staged two-gate synthetic run in a tmp repo must raise D1, and a
  gate-free window must raise nothing. Only then do sinks go live. Today's D7 can be replayed from el_s gaps at once.
- **Target.** ≤6 raises/day/detector, against today's load rung at 81-183 raise transitions/day [M, 10-09..10-16].
- **Verification.** Each verification records a positive control proving the causing load was present ("verify a
  cure under its load" lesson).

### 4.3 Escalation that stays operator-only

When D2 raises and less than 50% of the excess has a name, an operator-approved root helper may run `eslogger fork
exec exit` for 20 s (I-R6). It is never always-on.

---

## 5. Implementation waves

The rules: every file is owned by exactly one WP across all waves. LOC are [E] by size of change. WPs inside a wave
can run in parallel.

**Owned elsewhere, not touched by any WP:** live Wave 4c (Stop-hook ledger;
`~/.claude/handoff-briefs/load-wave-4c-stop-hook-ledger.md`) owns `scripts/wrap-ledger.sh`,
`hooks/operator-readout.sh`, the session-continue, completion-assert and boundary-handoff Stop hooks, their bats
files and `cutreplay.py`. hooks/lead-crash-watchdog.sh is also left untouched (crash pins are derived, §3.2), and so
is C-R1 (see §6).

| WP | Wave | Repo | Files owned | LOC | Depends | Agent / operator | Fixes |
|---|---|---|---|---|---|---|---|
| OP-1 | 0 | — | none (sudo kill path). **Precondition added in revision:** first add `/Users/chrisren/Development` to Spotlight's Privacy list (System Settings → Spotlight → Search Privacy, or PlistBuddy as in F §2.2 with the plist backed up first). F §2.3 [M] found /System/Volumes/Data in `kMDConfigSearchLevelTransitioning`, and an fseventsd restart forces every FSEvents client, mds included, to rescan; without the entry, a rebuild would crawl the 103 node_modules and the main checkouts (49M inodes in use). Record `mdutil -s /System/Volumes/Data` and mds/mds_stores CPU (`ps -o time=` deltas over 30 s) before the restart and 10 min and 1 h after | 0 | the Privacy entry | **operator** | X1, F-R7 |
| OP-2 | 0 | — | none (`xcrun -k`, `claude stop 9aa483e9`, orphan decision, coreaudiod restart) | 0 | — | **operator** | X24 |
| OP-2b | 0 (added in revision) | — | none. `sudo zprint -t -s \| head -40 > /tmp/zprint-<peak\|idle>-top.txt` plus the full `sudo zprint > /tmp/zprint-<peak\|idle>.txt` (its trailing wired-by-tag section), with `vm_stat`, `top -l 1 -n 0` (MemRegions, Processes) and `ioreg -r -c AGXAccelerator -d 1` alongside. Once at peak (≥2 gates running) and once at idle; the split goes into §1.1b | 0 | — | **operator** | §1.1b (wired attribution) |
| OP-2c | 0 (added in revision) | — | none. F §6 recipe A (`sudo fs_usage -w -f filesys -t 10`, ranked by process) and recipe B (`sudo fs_usage -w -f diskio -t 20`, grouped by type `WrMeta`/`WrData`/`RdMeta`/`PgIn`/`PgOut`, by process and by path, including `xcrun_db`), each once during a ≥2-gate window and once at idle, with the IOKit `Statistics` counters read before and after as the positive control | 0 | — | **operator** | §1.1c, Q3, Q17 |
| WP-1 | 1 | CI | scripts/fseventsd-watch.sh; tests/fseventsd-watch.bats; launchd/system/com.claude.fseventsd-watchdog.plist; migrations/0057-fseventsd-watchdog.sh | 200 | — | agent; root install **operator** | X2 |
| WP-2 | 1 | ACS | src/agentsync/gitops.py; src/agentsync/setup_report.py; src/agentsync/ops/doctor.py; docs/design/CONTRACTS.md; tests/test_gitops.py; tests/test_ops_doctor.py | 150 | — | agent (owner review) | X3a |
| WP-3 | 1 | ACS | tests/conftest.py | 130 | — | agent | X3c, X20 basetemp |
| WP-4 | 1 | ACS | scripts/install.sh; tests/test_install_oneshot.py; tests/test_deploy_pack.py; tests/test_install_next_line.py | 300 | — | agent | X3b, X11 |
| WP-5 | 1 | CI | bin/cc-bats; tests/cc-bats-admission.bats | 60 | — | agent | X3 (bats). *Second revision (X27):* the admission block (bin/cc-bats:459-466) also reads `~/.claude/autonomy/cc-bats-admission.mode`. Its default is today's refusal; `record` keeps the registry and logs would-refuse without exiting 75. Only the operator writes the file, after the X27 ruling (WP-32). WP-5 does not change the default |
| WP-6 | 1 | CI | scripts/cc-gc.sh; tests/cc-gc.bats; docs/GC-FRANCHISE.md; docs/activation/pending-activation/40-cc-gc-activate.sh | 120 | — | agent | X8 |
| WP-7 | 1 | CI | scripts/lib/capacity-attrib.py; tests/capacity-attrib.bats | 350 | — | agent | X5 |
| WP-8 | 1 | CI | mcp-servers.json; scripts/mcp-ssot-wire.sh; scripts/lib/mcp-noinherit.sh; install.sh; new hooks/ms365-shared-guard.sh; new scripts/mcp-ms365-proxy.sh; new tests/mcp-ms365-shared.bats; tests/mcp-ssot-wire.bats; tests/mcp-no-inherit.bats; new migrations/00NN-ms365-shared.sh | 400 | — | agent; tools/list gate before cutover | X4 |
| WP-9 | 2 | CI | new scripts/lib/wt-tombstone.sh (row; residue by same-volume `mv` or `cp -RPc` clone with no cap, and a tar plus cap only across volumes; G §5.1's full cache allowlist plus the `cmp` and lockfile rules; 0700/0600 modes; tombstone ref unless `--is-ancestor`; **reflog refs and a `logs/HEAD` copy**; the **`wip` snapshot** for a forced dirty removal; **`wt_prune_logged`**; ref expiry on the effective `cleanupPeriodDays`, which **never removes residue**; `purge` behind an operator flag; park/unpark with the path index, husk handling and **landed-branch detach and re-attach**; **`wt_pinned`** over crash, backlog, owner and resume-record pins; `cc-pin:` lock materialize and unlock, with repo scope); new bin/wt-tombstone (CLI for operators and the lab; no hook rewrites to it); new tests/wt-tombstone.bats | 750 | — | agent | X6 core, PARK, pins (amended in revision and again in the second revision) |
| WP-10 | 2 | CI | scripts/worktree-gc.sh; tests/worktree-gc.bats | 520 | WP-9 | agent | X6 callers, `--path`, PARK-first tiers (second revision: arm (i) PARK at 24 h, late DETACH past the effective `cleanupPeriodDays`, disk-pressure ARCHIVE), `wt_prune_logged` at :1109-1112, per-repo trunk, AC-4/5/6, F-9, pure-KEEP gate reorder (G-P1-6 amended: only pure KEEPs move ahead of recently_active and lsof) |
| WP-11 | 2 | CI | bin/cc-reaper; tests/cc-reaper.bats | 90 | WP-9 | agent | X6 (A3). *Second revision:* `worktree_cleanup` (:1756-1822) stops removing and only **enqueues** (one append to `wt-events.jsonl` plus a touch of the wake file). The remove at :1814 and its log-after disposal call go, and the tests pinning them are rewritten. New lab case: a landed-clean tree with a transcript under 24 h old survives the sweep. `wt-tombstone` is added to GARBAGE_WL (:725) for the teammate subshell (amended in revision) |
| WP-12 | 2 | CI | hooks/teammate-auto-shutdown.sh; scripts/handoff-fire.sh; hooks/git-worktree-guard.sh; scripts/branch-prune-landed.sh; scripts/postland-verify.sh (prune lines :1133,1171 only); scripts/desk-land.sh (:94 only); scripts/cloud-reconcile.sh (:359 only); tests/teammate-auto-shutdown.bats; tests/handoff-fire-failed-cleanup.bats; tests/git-worktree-guard.bats; tests/branch-prune-landed.bats | 420 | WP-9 | agent | X6 (A4, A5, A9, branch-deleted), X13 item (2) (guard superset pre-test). Amended in revision: teammate full residue inside the detached subshell; `wt_pinned` in teammate and handoff-fire. *Second revision:* the guard's tombstone runs **inside the hook** under `gtimeout 6`, exits 0 with no output on success and 2 on failure, and **never rewrites the command**, so no allow rule and no settings migration is needed. It adds the forced-dirty `wip` snapshot and a new `git worktree prune` arm. The three other prune sites call `wt_prune_logged`. Lab: a headless `-p` run in default and auto modes, plus the hook-timeout probe (Q20) |
| WP-13 | 2 | CI | new bin/cc-wt-restore; bin/cc-resume-resolve; lib/cc-resume-shell.sh; bin/reso-resume-one; **scripts/limit-recover/lr-fire-resume.sh**; tests/cc-resume-resolve.bats; tests/reso-resume-one.bats; **tests/lr-fire-resume-\*.bats** (the 7 existing files); new tests/cc-wt-restore.bats | 570 | WP-9 (phase 1 logging has no dependency) | agent | X7, including path-match unpark in all three launchers and the lr-fire-resume recreate path (amended in revision). *Second revision:* bin/reso-resume-one:490's `git worktree prune` becomes `wt_prune_logged`; restore reinstates the copied `logs/HEAD`; unpark re-attaches the recorded branch |
| WP-14 | 2 | CI | new scripts/lib/capacity-detect.py; new tests/capacity-detect.bats | 450 | WP-7 + 7 d of series | agent (record-only) | §4.2 |
| WP-15 | 3 | CI | hooks/live-session-registry.sh; scripts/worktree-gc-infra-run.sh; tests/worktree-gc-infra.bats; tests/live-session-registry-atomic.bats | 450 | WP-10, WP-13 | agent | X9 queue, 24 h grace, pins, multi-repo backstop; the `--path` repo scope (exclude reso, observe-only per repo until listed in `worktree-gc-repos.promoted`); `WTGC_EVENTS=observe` default and the mode-file read (amended in revision). *Second revision:* the same scope table gates the `cc-pin:` lock and unlock step; the promoted file is **read only**, written by the operator (OP-5), with a bats grep proving no shipped writer; the backstop reads the park index for the late DETACH and the disk-pressure ARCHIVE |
| WP-16 | 3 | CI | launchd/fleet.manifest; new launchd/com.claude.capacity-attrib.plist; new launchd/com.claude.mcp-ms365.plist; launchd/com.claude.worktree-gc-infra.plist; new docs/activation/pending-activation/NN-load-2026-10-17-activate.sh | 200 | WP-7, WP-8, WP-15 | **Corrected in revision.** The agent declares the two new labels `staged` in fleet.manifest, so install.sh deploys them without activating them (install.sh:1300-1309). The worktree-gc-infra plist edit is `run` and goes live on its deploy, which is safe only because WP-15's code defaults to observe. The **operator** runs the activation script, which bootstraps the staged labels, flips them to `run`, and writes `worktree-gc-events.mode = act` (C10). *Second revision:* the script does **not** write `worktree-gc-repos.promoted` (OP-5 does), and it records the operator's ARCHIVE free-space floor. **WP-16 is also the single numbering owner for every migration that edits the live ~/.claude/settings.json.** Today that is WP-8's `00NN-ms365-shared` and WP-28's `00MM-hook-if-filters`; WP-12 no longer needs one. The highest number on trunk today is 0065 [M, `ls migrations`], and migrations run in lexical order (migrations/README.md:22). Each is numbered at land time as max+1 on the trunk it rebases onto. Before the activation script lands, WP-16 checks that the numbers are distinct and that no two migrations write the same settings key | X5, X4, X9 activation; migration numbering |
| WP-17 | 3 | CI | scripts/capacity-alarm.sh; tests/capacity-alarm*.bats; launchd/com.claude.capacity-alarm.plist | 250 | WP-7; WP-14 D2 record-only for 7 d | agent | X5 consumer, X17. Grep tests/ for counted pins of alarm sites. **Amended in revision:** capacity-alarm is `run` (fleet.manifest:209), so a merged plist or script change is live on the next deploy advance. The X17 rung change therefore reads a switch, `~/.claude/autonomy/capacity-alarm-load-rung.mode`, that defaults to today's behaviour and is flipped by the same activation script once D2's 7 d record-only window is reviewed. *Second revision:* WP-17's code is the actor that retracts the stale load page. In record-only mode the load rung maps to SKIPPED in the per-rung loop, so the existing retract branch (:1967) removes `capacity-alarm-load.page` on the first run after the flip. A bats case asserts the page is gone after one run |
| WP-18 | 4 | CI | new bin/cc-kqwait (embedded C, hash-keyed build cache as in bin/cc-jetsam-exec:205-245); new tests/cc-kqwait.bats | 300 | — | agent | X12 R2 helper |
| WP-19 | 4 | CI | bin/cc-await-ping; tests/cc-await-ping.bats; tests/cc-await-ping-dup-wake.bats | 400 | R3 none; R2 needs WP-18 | agent | X12 |
| WP-20 | 4 | CI | hooks/pr-gate.sh; hooks/cc-permission-beacon.sh; hooks/waiting-recycle.sh; hooks/log-bash.sh; hooks/teammate-checkpoint.sh; new tests/{pr-gate,cc-permission-beacon,waiting-recycle,log-bash,teammate-checkpoint}-forks.bats | 300 | — | agent | X13 (readers) |
| WP-21 | 4 | CI | hooks/qos-rewrite.sh (union grep only); hooks/coldcompile-admit.sh; hooks/curl-gate-scope.sh; hooks/rm-safe-allowlist.sh; hooks/research-block.sh; hooks/lib/research-router.sh; hooks/memory-index-drain.sh; hooks/bash-output-offload.sh; hooks/smart-bash-allowlist.sh; scripts/pipefail-sigpipe-allow.txt; new forks bats; new tests/qos-rewrite-git-grep.bats | 450 | — | agent | X13 (patterns, -S); X25 transform (d) in qos-rewrite.sh (added in revision; transform (b) stays untouched) |
| WP-22 | 4 | ACS | new scripts/gate.sh; new tests/_gate_journal.py; CLAUDE.md; **new docs/lanes/COMMON.md** (second revision) | 470 | — | agent | X10, including the kill-resume journal (amended in revision). *Second revision:* X10 reaches the lanes that drive the gate load only through the lane template. That template lives in `~/.cache/agentsync-bring-back/b13/lanes/COMMON12.md` (71 lines; the gate and push steps are at :49-57 [M]). It is outside any repo, so no WP may edit it, and wave leads keep hand-copying `/tmp/r13*-gate.sh`. WP-22 therefore **moves the template into the repo** as `docs/lanes/COMMON.md`. It is the COMMON12 text with the gate step replaced: `scripts/gate.sh --affected` for lane pre-gates, and `scripts/gate.sh` for the land gate. Pointing the next round at it is OP-6 |
| WP-23 | 5 | CI | statusline.sh; tests/statusline-identity.bats; tests/statusline-telemetry-path.bats | 150 | — | agent | X16 |
| WP-24 | 5 | CI | scripts/compressor-sentinel.sh; tests/compressor-sentinel.bats | 250 | — | agent | X15 |
| WP-25 | 5 | CI | scripts/kitty-build-swap.sh; tests/kitty-build-swap.bats | 60 | — | agent; adoption **operator** at a planned reboot | X14 |
| WP-26 | 5 | CI | scripts/limit-recover/lr_recon/tests/*.py | 60 | — | agent | X20 |
| WP-27 | 5 | hammerspoon-config | hsc/screenshot/init.lua | 80 | — | agent | X22 |
| WP-28 | 5 | CI | new migrations/00MM-hook-if-filters.sh | 80 | probe | agent writes; **operator** applies | X18 |
| OP-3 | 5 | — | personal/.mcp.json, taxes-2026/.mcp.json (outside git; copy each original first); ~/.config/uv/uv.toml; (added in revision) unpack pandoc's `pandoc-3.9-arm64-macOS.zip` from the GitHub release into `~/.local/share/agentsync/pandoc/3.9-arm64/`, check `codesign -dv` against 5U2WKE6DES and the release's checksum | 0 | WP-8; WP-30 for pandoc | **operator** | X19, X26; X21 only as its experiment, and `uv.toml` only if the experiment shows a gain (second revision) |
| OP-5 | 3 (added in the second revision) | — | `~/.claude/autonomy/worktree-gc-repos.promoted`. For each foreign repo, after at least 7 d of its observe-only wake and backstop log (`would_park`, `would_detach`, `would_lock`, each with reasons) and the §3.7 lab, the operator appends that repo's absolute common dir as one line. The operator removes the line to demote. No agent and no script writes this file. Without it, no foreign repo's trees are ever moved or removed | 0 | WP-15, WP-16 activation | **operator** | X9 per-repo promotion |
| OP-6 | 4 (added in the second revision) | — | The next agent-context-sync round's lane briefs (`~/.cache/agentsync-bring-back/b13/round<N>/fire-lanes.sh` and its COMMON include) point at the repo's `docs/lanes/COMMON.md` instead of `~/.cache/…/COMMON12.md`, and the hand-copied `/tmp/r13*-gate.sh` are retired. This is an operator-applied edit outside any repo, or a wave lead's edit with the operator's OK | 0 | WP-22 | **operator** | X10 reach |
| WP-31 | 2 (added in the second revision) | **reso-management-app** (the repo owner decides) | scripts/launchd/bin/worktree-gc-run.sh (:155, :157) and a new reso bats or shell test for the janitor | 60 | WP-9 live in ~/.claude | owner; agent on request | X6 for A2. Source `~/.claude/scripts/lib/wt-tombstone.sh`; before :155 call `wt_pinned "$p"` and then `wt_tombstone "$p" reso-janitor two-strike`; a missing library, a pin or a failed tombstone keeps the tree (`kept=<b>:<reason>`); :157 becomes `wt_prune_logged`. If WP-31 is not done, X6 stays at 5 of 7 and reso's residue is unprotected |
| WP-32 | 6 (conditional; an operator ruling) | CI | config/qos-batch.patterns; config/qos-bound.patterns; tests/qos-rewrite.bats; tests/cc-qos-exec.bats; tests/coldcompile-admit.bats; tests/curl-gate-redirect.bats | 60 | the extended Q14 A/B after waves 0-1; the operator's ruling | agent writes; **operator** rules | X27: remove the (b) and (c) rows the ruling retires. Writing `cc-bats-admission.mode = record` is the operator's step. hooks/qos-rewrite.sh is not touched; it stays WP-21's |
| WP-30 | 5 (added in revision) | ACS | src/agentsync/convert/pandoc.py (`_bundled_pandoc` resolver and the sha256 → version table); new tests/test_pandoc_native.py | 120 | OP-3 pandoc copy for the live effect (the code falls back without it) | agent (owner review) | X26 |
| WP-29 | 6 (conditional) | ACS | new tests/_slotpool.py; pyproject.toml | 250 | X-POOL A/B passes | agent | X-POOL |
| OP-4 | 6 (conditional) | — | `sysctl -w kern.maxvnodes=524288` (the Spotlight exclusion moved to OP-1 in revision) | 0 | X1 done | **operator** | X23 |

Order by effect over effort:
1. Wave 0. OP-1 alone is the largest single measured gain: about 1-1.7 cores and 12-13 GB. Its Spotlight Privacy
   precondition comes first. OP-2b (wired split) and OP-2c (fs_usage capture) are measurements only, and they are
   taken in the same window, so that the post-X1 state is the baseline for §1.1b and §1.1c.
2. Wave 1. WP-1, WP-2, WP-3, WP-4 and WP-5 remove the per-test shim cost. WP-6 is a five-minute safety fix. WP-7
   and WP-8 are self-contained.
3. Wave 2. This is the reversibility foundation, which must ship before any event actuator removes faster.
4. Wave 3. Wiring and activation.
5. Waves 4-5. Fork trims and hygiene.
6. Wave 6. Measured experiments only.

The re-measurement after waves 0-1, with a positive control proving the load was present, decides X-POOL. **Amended
in revision:** that re-measurement also carries (1) a true solo full-suite baseline at background load ≤20 with no
other suite running, since the 761 s figure was taken at load 73-140 with another suite starting; (2) the Q14
lone-gate A/B, with transform (b) on (`uv run pytest …`) vs off (`true && uv run pytest …`, which qos-rewrite.sh:304-306
leaves alone); and (3) `ps -o pid,pri,ni,comm` of every gate's controller and workers in every X-POOL and X10
measurement. Q14 thereby gets a wave. Its result goes to the operator, who rules on transform (b); this design does
not change (b) without that ruling. **Extended in the second revision (X27):** the same A/B also covers transform
(c) and the cc-bats rc-75 refusal, with each one on and off. (c) is off for `true && …`. The refusal is off with
`CC_BATS_MAX_ROOTS=0` (bin/cc-bats:62). The A/B records per-gate wall time, gates/h and the SIGXCPU kill count.
On the ruling, WP-32 removes the retired table rows and the operator writes the cc-bats mode file.

---

## 6. Rejected or refuted levers

**Ruled out by the operator constraint** (never re-propose):
- nice or taskpolicy demotion (no PRI change on Darwin; background QoS starved must-finish work and piled up 133
  processes, DESIGN.md:227 in load-hook-timeouts-2026-10-11);
- load-threshold hook exits; waiting shedders (gate_admit is lint-enforced absent);
- cc-bats-style refusal; turning off the sentinel kill rung (operator ruled to keep it);
- load-per-core ceilings (no separating threshold: the fatal 2.53/core is below 14 of 15 survived readings,
  max-load-per-core-derivation §3);
- PYTEST_XDIST_AUTO_NUM_WORKERS=3 (migration 0064, unapplied): a lone gate would run about 3.3× slower;
- "run fewer sessions", and the capacity-alarm advice to close sessions.

*Second revision:* three of these classes are **live today**. They are transform (b)'s demotion, transform (c)'s
CPU ceiling (hooks/qos-rewrite.sh:30-31) and cc-bats's rc-75 refusal (bin/cc-bats:459-466). Listing them here does
not retire them, so X27 schedules their retirement behind the extended Q14 A/B and an operator ruling.

**Refuted on evidence:**
- "xcodebuild -license check runs on every git call": it runs only on an xcrun_db miss keyed by `DEVELOPER_DIR|HOME`.
- "R1 lowers every shim call's cost": a hit costs 96-99M instructions on a 1 KB db and on the 90 MB db alike [M].
- "install.sh --report-only calls itself": the chains are forked subshells carrying the parent's argv.
- "lead-crash-watchdog is the top per-session cost": cc-await-ping is ~8× larger.
- "150 pids/5 s": the pid counter shows 830-2,280/s.
- "kern.num_vnodes == maxvnodes is exhaustion": by design; the free list holds 90%.
- Spotlight, Time Machine, ~/.claude/logs, gitstatusd, swap and zombies as load sources: each measured at ≈0.
- Idle worktrees and disk as load or binding constraints: 3.71 TiB free.
- "ms365 times out on auth": 307 of 324 connects succeeded; the timeouts are cold start under load.
- "Hammerspoon adds wired memory": user wired totals 0.004 GB.
- "Claude Code title-spinner drives WindowServer": 0 glyph changes in 6 busy panes over 5.1 s.

**Rejected or amended designs from the axes:**
- **A-R3 tree-keyed verdict cache.** 0 hits in ~20 round-12/13 gates; its key cannot cover the load-gated
  `@timing` skips (conftest.py:103-115) or the AGENTSYNC_* switches. Replaced by log-only in X10.
- **J-R1 start-time fair share.** xdist fixes the worker count at start (plugin.py:305-315), so late gates get
  leftovers, and 4 staggered gates still spawn 20 workers.
- **A-R2 / A-R8 pool as written.** Not work-conserving; per-gate wall time gets worse. Now conditional X-POOL.
- **G-P1-5 "detach unlanded after 7 d".** It deletes caches and the reflog and depends on unshipped restore.
  Replaced by PARK.
- **G-P1-4 parts (b) and (d).** Dead triggers (see §3.4).
- **Lazy `git_ro` cache (B2).** Lost in each `$(…)` subshell [M].
- **Native ms365 `--http`.** Drops tools (X4).
- **Deleting the personal ms365 entry (E5).** It changes app and tenant.
- **E4 Fix 2.** Already landed as `rcy_bgcopy_stop` (5cd333f16, handoff-fire.sh:7087-7119).
- **E3 "Chrome owner unknown".** It is render.mjs, already fixed in d8011e0.
- **C-R1 kqueue watchdog as written.** It would skip `handle_crash` on clean-end pidfile deletes (4,761 vs 339
  log lines [M]) and race cc-close-attrib's closed record. Deferred: it needs a NOTE_DELETE grace re-arm plus a wait
  for the close record, and saves only ~5 forks/s.
- **C-R2 timeout-only heartbeat body.** Misses reverse-edge alias keys.
- **C-R3 cross-poll memo.** Stale at one-second `-nt` resolution.
- **D-R2(4) `read -d ''` and D-R2(9) `read -n`.** Byte-at-a-time reads, 7× slower at 240 KB [M].
- **D-R5 2 s git cache.** An unbounded stale display on idle panes; it breaks statusline-identity.bats:378-380.
- **D-R4 `Bash(git push origin HEAD:*)`.** It never matches `HEAD:main`.
- **I-R1 hosting capacity-alarm as a child of the daemon.** It loses the exit-code channel and creates a single
  point of failure.
- **I-R4 at the per-rung page only.** The combined page stays ALARM in ~45% of rows.
- **F-R3 as a P1 fix.** The burst was misread as steady state.
- **F-R4 via new-worktree.sh, and pandoc_path.** No effect, and a different binary.
- **F-R5 SIGTERM-only handler.** ≥31% of the leaks are SIGKILL.
- **H0 ad-hoc bundle swap at an unattended reboot.** TCC grants are tied to the Developer ID csreq.
- **Rejected in revision:**
  - **`git grep`: insert `-I` instead of swapping to `-P`.** It drops every "Binary file … matches" line, and it keeps
    the slow TRE engine on text (80.5G against 2.0G instructions on the measured command [M]).
  - **`git grep`: an `LC_ALL=C` prefix.** It costs 606M against 147M instructions per 0.9 MB of binary [M], and it
    changes `.` and `-i` to byte semantics for non-ASCII text.
  - **`git grep`: a memory or CPU ceiling** in the style of transform (c). That is a limit, not the same work done
    with less machine work.
  - **pandoc: one shared path or a hardlinked inode for the x86_64 binary.** It saves only the first-start translation
    of each copy. The Rosetta analysis and its sandbox denies fire on every launch [M, §1.1d].
  - **pandoc: `pandoc_path` → /opt/homebrew/bin/pandoc.** That is 3.11, not 3.9, so it is a different binary (as X21
    already found). X26 uses the same version.
  - **PARK: a symlink left at the original path.** A process's cwd resolves to the physical `.parked/<id>` path, so a
    resumed session would hash to a different project slug and miss its transcript [E: getcwd returns the resolved
    path]. The symlink would also count as "occupied" for unpark.
  - **DETACH 30 min after the last write.** It bought no load (idle trees ≈0, G §0) and would have broken same-day
    resumes (X7). Replaced by a 24 h grace that shortens only on measured demand.
  - **The ms365 select-account/login/logout deny with a names-only gate.** It removed abilities and could not prove
    an equivalent. Replaced by a per-session account default, a schema-level gate, and per-account routing as the
    fallback (note X4).
  - **The crash pin as `CC_WTGC_EXCLUDE` only.** It covered 1 of the 4 automated removers. Replaced by `wt_pinned`
    plus a `cc-pin:` lock (§3.2).
- **Rejected in the second revision:**
  - **DETACH at 24 h as the landed-clean default.** Its premise ("the longest a tree survives today") held only
    under the infra nightly. It would turn day 2-30 resumes in five other repos into restores without caches, and
    it discards reflog-only commits that `landed()` cannot see. Replaced by PARK by default, with DETACH after the
    effective `cleanupPeriodDays` or on disk pressure.
  - **Detaching HEAD on every park.** For an unlanded tree it gains nothing, since nothing automated deletes
    unlanded branches. It would also drop the guard's `branch -D` refusal for that branch. So only arm (i) (landed)
    detaches.
  - **Tar plus a 50 MB cap for residue.** A tar is O(bytes), and the cap turned a large residue into a KEEP, or on
    the guard path into a refused session removal. Replaced by a same-volume clone or move with no cap.
  - **`mv` of residue inside the guard.** A PreToolUse hook runs before the permission decision and before later
    hooks, so a denied removal would leave the tree stripped of its ignored files. The guard clones instead.
  - **The guard's `updatedInput` rewrite to `wt-tombstone … && <original>`.** The permission flow judges the
    rewritten compound (qos-rewrite.sh:118), no allow rule covers it, and a headless session that meets a prompt
    hangs. Replaced by an in-hook tombstone that leaves the command unchanged. An allow-rule migration was the
    alternative, and it is not needed.
  - **Keeping cc-reaper's teardown removal with only a pin and a tombstone.** It left the remover most likely to
    meet a resumable cwd with zero grace. It now enqueues.
  - **Expiring the residue with the refs.** It would delete gitignored paid assets (reso-landing-app/.gitignore:39-41).
  - **X21 as a disk saving.** uv already clones (F §5), so the saving already exists today. Restated as a vnode
    experiment.
- **The long tail.** One whole-suite FIFO lock; make jobserver tokens; pytest-testmon; DEVELOPER_DIR=CLT (git 2.39.5,
  not equivalent); host-PATH git (Homebrew 2.54.0); shared synced-repo fixtures; merge-queue batching (owner policy);
  a hook-chain dispatcher; `async:true` hooks; a unix-socket hook broker; one machine-wide kqueue hub; a python
  deathwatch per session; fswatch/FSEvents/WatchPaths as watcher substrates for daemons; CHOKIDAR polling; worktree
  GC driven by disk or `--force`; globbing `.worktrees`; WorktreeRemove as the event; restore from
  SessionStart(resume); a periodic TMPDIR reaper; sparse checkout of docs/research; `.noindex` on node_modules;
  `tmp_path_retention_count=0`; an always-on eslogger; kqueue NOTE_TRACK; snapshot-diff fork lineage (5.5%
  coverage).

---

## 7. Open questions (conviction = the lead's probability that the stated answer is true)

| # | Question | Current best answer | Conviction | How to settle |
|---|---|---|---|---|
| Q1 | Does a test-slot pool beat today's oversubscription once the waste is removed? | No, unless the true solo time is under 600 s | 35% that a pool passes | the X-POOL A/B after waves 0-1 |
| Q2 | What drives the fseventsd bloat and livelock? | Clients that stop draining, possibly processes SIGSTOPped by compressor-sentinel (`held=17` for ~2.7 min [M]). That would be a loop: memory pressure → SIGSTOP → fseventsd buffering → more pressure | 35% | correlate the footprint slope with sentinel `held=N` windows; the pre-restart `sudo sample` (X1/X2); Apple Feedback |
| Q3 | Does the 90 MB xcrun rewrite reach the disk? | Re-opened in revision. It is renamed and unlinked within ~1 s with no fsync, but at 1.1 GB free the pageout path must clean dirty file pages. The lifetime write average (81.9 MB/s at 94.5 KB per write [M, IOKit]) sits inside the xcrun churn band (70-110 MB/s) and is far above the 2.34 MB/s idle rate | 50% that most never hits the disk (was 70%) | OP-2c recipe B, `WrData` by path for `xcrun_db`; then the X5 disk series across X3's landing |
| Q4 | Share of excess load from gates vs time of day | 65-85% gates | 65% | D1 plus the 5 s series across the next 4-gate round |
| Q5 | How often are reaped worktrees resumed? | Rarely, but it is what the empty-dir harm hangs on | 60% that it is under 5/week | WP-13 phase 1 ledger |
| Q6 | Restore wall time under load for a ~9k-file checkout | seconds | 60% under 15 s at load ≥100 | the WP-13 lab, logged per restore |
| Q7 | Does stock kitty 0.49.x fix the talk-thread accept death? | No (v0.49.2 accept_peer still returns false) | 85% not fixed | upstream diff on each release |
| Q8 | Does launchd WatchPaths depend on fseventsd? | Uncertain; the 600 s due-tick covers either way | 50% | touch the wake file during the next fseventsd fault and watch `launchctl print` |
| Q9 | Is a command hook 1 or 2 execs (is `args` worth it)? | Unknown | 50% | operator `eslogger exec` for 30 s |
| Q10 | Does 2.1.114 tolerate unknown hook keys and types? | Unknown; R6/R7 stay blocked until 114 leaves the shared settings | 40% that it tolerates them | scratch-config probe |
| Q11 | Does raising maxvnodes measurably cut sys%? | Unlikely at steady state | 25% | X23 A/B |
| Q12 | Multi-day growth of one shared ms365 process | Bounded | 60% | 72 h soak; footprint watchdog |
| Q13 | Who removed the 68 b13 lane worktrees? | A wave lead using raw git | 80% | WP-12's guard row covers the next time |
| Q14 | Do the existing demotions and limits slow session work against the constraint? They are qos-rewrite transform (b) (`taskpolicy -c utility` for agent pytest/npm, config/qos-batch.patterns), transform (c) (the `cc-cpubound` 60 CPU-s ceiling on grep/rg/find, config/qos-bound.patterns; added in the second revision), and cc-bats's demotion and rc-75 refusal (cc-bats:465-466,626-731). *Second revision:* 228 waivers (`CC_BATS_MAX_ROOTS=0`) in 7 d of the bash log [M], and their retirement is row X27 | Likely yes for lone gates; an operator decision, not changed here (WP-21 owns qos-rewrite.sh and must not touch transform (b) without a ruling) | 60% | **Scheduled in revision:** the Wave 0-1 re-measurement (§5), as a lone-gate A/B with transform (b) on (`uv run pytest …`, config/qos-batch.patterns:44) vs off (`true && uv run pytest …`, which :304-306 leaves alone), recording `ps -o pri` of every worker. It also confounds the X-POOL baseline, so X-POOL is not decided before it |
| Q15 | Does Wave 4c's ledger work interact with any WP here? | No: the files are disjoint (§5) | 90% | re-check its diff before landing WP-20 and WP-21 |
| Q16 | What are the ~10-14 GB of unattributed wired kernel memory? (added in revision) | APFS node caches and kalloc zones by subtraction; page tables 1-4 GB [E] | 40% that APFS/kalloc is the largest single tag | OP-2b at peak and at idle |
| Q17 | Who writes 7.08 TB/day at 94.5 KB per write? (added in revision) | Busy-period data writes, with the xcrun_db rewrite the leading candidate; not metadata writeback, which F §4 had inferred | 45% that xcrun_db is the largest writer | OP-2c recipe B; the X5 disk series before and after X3 |
| Q18 | Which library leaks in `git grep` on binaries? (added in revision) | The libc regex multibyte path, as git calls it on whole buffers (BSD grep's line-at-a-time use does not grow) | 60% | `leaks --atExit -- git grep -E … -- <one binary>` on a scratch copy; then report upstream to git or Apple |
| Q19 | With PARK as the default and DETACH only after a 365 d `cleanupPeriodDays`, how fast do parked trees use disk? (added in the second revision) | At most ~9.9 GB/day and ≤3.6 TB at 365 d [E: 18.3 removals/day, G §1.6, times ≤0.54 GB per tree, an upper bound because per-tree `du` counts APFS clones and pnpm hardlinks in full], against 4.08 TB free. So the disk-pressure ARCHIVE is a real backstop within about a year | 60% that real block use is under half the bound | `df` and the `pop_parked` trend from the backstop row over the first 30 d of act mode; `du` of 5 parked trees against their `df` delta at park time |
| Q20 | When a PreToolUse command hook passes its `timeout`, does Claude Code run the tool call anyway? (added in the second revision) | Probably yes, as a non-blocking error [E]. That is why the guard bounds its own tombstone at 6 s under the 10 s hook timeout, and blocks on its own timeout | 70% | the §3.7 hook-timeout lab case on the live Claude Code versions (2.1.291, 2.1.293, 2.1.114) |

---

## Appendix A. Disposition of every axis recommendation

**Kept or amended, with the row each one landed in:**

| Axis | Recommendations → row |
|---|---|
| A | Q1 kill-restart waste → X10 kill-resume journal (revision); R1 → X3 (amended); R2 → X-POOL (refuted, conditional); R3 → X10 (log-only); R4 → X10 (amended); R5 → X10 (amended selector); R6 → X11; R7 → X3; R8 → X-POOL |
| B | B1 → X3 (amended, P1); B2 → X3 (amended: parent-shell resolve); B3 → X3 (dated warm db); B4 → X24 (amended) |
| C | R2 → X12 (amended); R3 → X12 (amended: no memo); R4 → X15 (P3) |
| D | R1 → X13 (P3 within it); R2 → X13 (amended); R3 → X13 (amended); R4 → X18 (amended); R5 → X16 (amended) |
| E | E1 → X1/X2; E2 → X4 (shape B; amended in revision: no deny); E3 → X24; E4 → X24 (Fix 1 only); E5 → X19 (amended); §4 operator `zprint` → OP-2b (revision); §7 19 GB `git grep` → X25 and D9 (revision) |
| F | R1 → X1; R2 → X2; R3 → X23; R4 → X21 (second revision: disk claim withdrawn, restated as a vnode experiment); R5 → X20 (amended); R6 → X20; R7 → OP-1 precondition (moved in revision from OP-4); R8 → X9; §4 pandoc denies → X26 (revision); §6 recipes A and B → OP-2c (revision) |
| G | P0-1 → X6; P0-2 → X7; P0-3 → X8; P1-4 → X9; P1-5 → replaced by PARK; P1-6 → in WP-10; P2-7 DEHYDRATE → not scheduled, since disk is not binding (its condition (c) and lockfile hashes are carried into X6 in revision); the D8 crash pin as a `git worktree lock` → `wt_pinned` plus a `cc-pin:` lock (revision). Second revision: §5.1's full cache allowlist → X6 cache rule; §5.3 "untracked files are the one thing a tombstone does not carry" → the guard's `wip` snapshot; D7 native prune → `wt_prune_logged` and the guard's prune arm; A2 (reso janitor) → WP-31; A3 → enqueue (WP-11); §5.1 arm (i) 30 min DETACH → PARK at 24 h |
| H | H0 → X14; H1 → X22 |
| I | R1 → X5; R2 → §4.2; R3 → X5; R4 → X17; R5 → D6; R6 → §4.3 |
| J | R1 → refuted (X-POOL); R2 → X1/X2; R3 → X9; R4 → §6; R5 → X3 |

**Deferred or diagnostic only, with no WP:**
- C: R1 (§6); R5, the python sidecar fold (63 MB, after WP-18); R6, mailbox-wake-arm reorder (under 1/s).
- B: B5, the hermetic bats git dir.
- D: R6 `args` and R7 `http` hooks (Q9, Q10).
- E: E6 (falls out of X4).
- H: H3 reduce-motion (unmeasured; operator A/B); H4 Dia URL capture (diagnostic).
