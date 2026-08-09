# Panel H-CAP-1 — raw return: `cap-kernel`

Fable 5 baseline-blind derivation panelist, 2026-08-09. Session `fde52a0f-c367-4d4b-93b7-86173a1238b3`.
Recovered from the teammate's own transcript after the named-teammate spawn returned no value to the lead (see the write-up for that defect). Verbatim, unedited.

---

<!-- 2026-08-09T21:02:12.591Z -->

Model built (pty namespace, per-uid proc table, system thread table, fd/vnode tables, compressor/swap, mach IPC, scheduler). Now confirming with read-only probes.

---

<!-- 2026-08-09T21:06:06.602Z -->

## RANKED EXHAUSTION TERMS — kernel-finite resources vs N=150+ sessions (M1 Max, 64GB, Darwin 24.6)

Measured baseline this box, quiet moment: 6 live claude sessions · 735 procs / 3,551 threads system-wide · 24 ptys · kern.num_files 6,831 · claude main-proc RSS 508–790MB (mean ~620MB), 19–31 threads, 27–38 fds, 1–2 distinct ptys each · swap 0, compressor 0 (recent boot).

---

### #1 — PTY namespace: `kern.tty.ptmx_max = 511` — **[DERIVED + CONFIRMED limit; breach-at-150 high-confidence derivation]**

- **Limit:** 511 concurrently-open pty masters, whole box, all users, confirmed by `sysctl kern.tty.ptmx_max`. Hard cap; `posix_openpt` returns ENXIO/EAGAIN past it.
- **Scaling:** measured 1–2 distinct ptys per session (24 total @ ~8 panes) ≈ **1.5×N steady**, but the fleet's own orchestration is the multiplier: every `--split-right` handoff pane, every teammate pane, every `script`/`tmux`/nested-pty wrapper is +1 from the same global pool, shared with every human terminal window. N=150 with 6-teammate bursts ≈ 260–350; any layering (tmux inside panes) doubles it → breach.
- **Gauge blindness: TOTAL.** No counter exists anywhere in the standard surface — `top`, Activity Monitor, `vm_stat`, load, memory pressure all read *perfectly healthy at the exact moment it binds*. The only gauge is `ls /dev/ttys* | wc -l`, which nothing monitors. Failure presents as the terminal emulator "unable to open pty" / spawn failures that look like app bugs, at a moment when every conventional metric is green. Ranked #1 on the brief's blindness criterion.
- Confidence: limit certain; breach at 150+ ~0.7 (depends on teaming density).

### #2 — Unified memory → compressor/swap **thrash + jetsam kill** (not space) — **[DERIVED + CONFIRMED arithmetic; space half REFUTED]**

- **Limit:** 64GB physical. 620MB/session mean **today** × 150 = **~93GB anon** before children, and per-session RSS grows with context fill (superlinear in wall-time, not just N). Swap *space* is a non-term — `/System/Volumes/VM` has 4.9TB free (refuting my swap-exhaustion derivation). What binds is compression/swap CPU+I/O latency and then **memorystatus (jetsam) killing the largest-footprint process — i.e. always a claude session**.
- **Gauge blindness: STRUCTURAL MISATTRIBUTION.** macOS gauges exist but lie in direction: `top` "PhysMem used" saturates at ~64G and stops moving; "unused" includes speculative pages; `kern.memorystatus_level` (now 93) is polled by nobody; the visible symptom at bind is **exploding sys% CPU and load average** (kernel_task compressing), which a normal operator reads as a *CPU* problem and answers by killing the wrong thing. The kill itself surfaces only as a JetsamEvent diagnostic report — the session just vanishes. This is very plausibly this box's existing "dies under load" signature.
- Confidence: 0.9 that this binds first *in wall-clock terms*; ranked #2 only because its gauges are partially present.

### #3 — Terminal emulator as single-process fd/pty concentrator — **[DERIVED + UNCONFIRMED]**

- All 150 ptmx masters + ~12 fds/pane (measured: kitty pid 600, 8 panes, 99 fds) live in **one** GUI process whose launchd soft `maxfiles` default is **256** (confirmed: `launchctl limit maxfiles → 256 unlimited`). If kitty does not `setrlimit` itself, EMFILE arrives at ~20 panes; if it raises, the ceiling is elsewhere (its single event loop backpressuring 150 pty streams — see negative space). ~1800 fds projected at 150 panes.
- **Deciding probe (needs root, did not run):** `sudo launchctl procinfo 600 | grep -i -A2 o_files` — soft limit 256 refutes-or-confirms in one line. Current data can't discriminate (99 < 256).
- **Gauge blindness: total** — EMFILE inside one GUI process; no system gauge moves.

### #4 — Vnode table: already pinned at max — **[DERIVED + CONFIRMED state; degradation not failure]**

- `kern.num_vnodes = kern.maxvnodes = 263,168` **right now**, with 160M recycles since boot; free_vnodes 203k. Soft cap: kernel recycles, so it never "fails" — it binds as **namecache-miss latency** during fleet-wide git/node_modules churn (150 worktrees ≈ 10⁷ file paths cycling through 2.6×10⁵ slots).
- **Gauge blindness: high** — presents as "git status got slow" and elevated sys%, no gauge names vnodes; `kern.num_recycledvnodes` rate is the only tell.

### REFUTED by measurement (derived first, killed by probes)

- **Per-uid process table** — kern.maxprocperuid = 10,666; measured ~5–8 procs/session-tree steady → ~1,200 at N=150. Not binding. (My prior on the default was 10× too low.)
- **System thread table** — kern.num_threads = 81,920; ~25–60 threads/session-tree → ~12k projected. Not binding.
- **System file table** — kern.maxfiles = 491,520 vs kern.num_files = 6,831 now; ~35 fds/session main proc → ~20k projected. Not binding.
- **Swap-file space** — 4.9TB free on the VM volume. Never binds; the memory term is thrash, not space.
- **Ephemeral ports / mbufs** — h2-multiplexed API connections, ~4/session → ~600 of 16,383. Not binding.

### NEGATIVE SPACE (adjacent, unwatched)

1. **Pty flow-control deadlock, not exhaustion:** one emulator event loop consuming 150 pty streams → tty buffers fill → sessions block in `write(2)` to their own tty and read as "hung Claude", with zero kernel resource exhausted. Nobody instruments pty backpressure.
2. **Mach port / IPC kernel memory in launchd, WindowServer, notifyd** at 150+ registered tasks — invisible without root `lsmp`; darwin-notify registration failures degrade silently (16 distnoted instances already running).
3. **Wired-memory amplification** (pmap/pv-entries, kernel thread stacks) — every projected page of that 93GB costs kernel wired bookkeeping that shrinks the usable 64GB from below; wired is visible in vm_stat but nobody subtracts it from the budget.

### FALSIFIABLE RUNTIME PREDICTIONS

1. **PTY census tracks pane count 1:1.** `ls /dev/ttys* | wc -l` now reads **24**; after ramping to 50 sessions it will read **60–90**; at 150 sessions + teaming ≥**230**, while `top`/`vm_stat`/load show no anomaly of any kind. Breach point: count = 511 → next pane fails with openpt ENXIO.
2. **Compressor engages long before any "used" gauge alarms.** At ~75 sessions: `sysctl vm.compressor_bytes_used` > 8×10⁹ while `top` header still shows nonzero "unused" PhysMem. At ~100: `vm_stat` pageouts increment >1,000/s during concurrent active turns while `memory_pressure -Q` free% still reads >20%.
3. **First session death is jetsam, not crash:** a file matching `JetsamEvent-*.ips` appears in `/Library/Logs/DiagnosticReports` (or `~/Library/Logs/DiagnosticReports`) naming the highest-RSS claude pid, at a moment load-avg < 2×ncpu — i.e. the postmortem will say memory while the live gauges said CPU.
4. **Kitty's fd ceiling is decidable in one root command:** `sudo launchctl procinfo 600 | grep -i o_files` reads either 256 (→ hard bind at ~20 panes; the fleet's current 15-session operation was already within 40% of death) or a raised value (→ term #3 dissolves into the flow-control negative-space item).
5. **Vnode churn during a fleet git sweep:** two reads of `sysctl kern.num_recycledvnodes` 60s apart during concurrent `git status` across worktrees delta >100k, while `kern.free_vnodes` dips <50k and no conventional gauge moves.

### CAMPAIGN / GENERATOR CANDIDATE

**A "kernel headroom" sampler** (one launchd daemon, one JSON line/min: pty count vs 511 · num_files vs maxfiles · procs-per-uid · threads · compressor_bytes_used + pageout rate · free_vnodes · jetsam-report tail) — dissolves the entire blindness class this panel found: every term above becomes "alarm at 70% of the real counter" instead of "invisible until ENXIO/EMFILE/jetsam"; scale-up to 150 becomes a measured walk instead of a discovery-by-death. Bonus: the same feed gives the session-recycle machinery a *memory* trigger (compressor bytes) to complement its context-fill trigger — per-session RSS never shrinks, so recycling is currently the only memory reclaim the fleet has, and it fires on the wrong variable.

---
Contamination: none — brief withheld prior findings; I read no repo docs or ledgers. Probes spent: 7 bash probe batches, all read-only (`sysctl`, `ps`, `lsof -p` on 7 pids, `top -l1`, `ls /dev`, `df`, `vm_stat`); nothing allocating or forking wide. One stray probe (`lsof` with an empty pid arg) produced a system-wide-looking listing — its numbers were discarded, not used in any claim.
