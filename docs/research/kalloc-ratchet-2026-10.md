# The data.kalloc.1024 ratchet: what drives it, measured without root (2026-09-30)

**Backlog:** `a417ab59e8f5` · plan ticket host-memory.1 (backlog master plan 2026-09-30, W1).
**Instruments and raw data:** [`kalloc-ratchet-2026-10/`](kalloc-ratchet-2026-10/) — every table
below is re-derivable from a script there.

Scope (frozen): correlate the capacity-alarm kalloc series (live + rotated logs, across the
reboots) against session count, process churn, coalition counts and top_procs; measure the
post-reboot slope; name a top driver at r ≥ 0.6, or say inconclusive and stage a root capture.

## Answer

1. **Driver, named: kernel credential churn.** Minute by minute, data.kalloc.1024 moves one-for-one
   with the kernel `cred` zone (r = **0.93**, 76 one-minute intervals; r = 0.94 at 47; r = 0.875 in an
   independent 20 s sampler, 44 windows) and with `kalloc.48` (r = 0.86–0.91). The three rise and
   fall together, roughly one element each, including through drops of −1,700 in seven seconds.
   Every other kernel zone and every IOKit class scores r ≤ 0.45. So the 1 KiB data buffers are
   allocated and freed together with process credentials, and a fraction of them is never freed.
2. **The inherited cause is refuted for this box.** The 2026-08-24 analysis attributed the zone to
   terminal rendering (upstream `claude-code#44824`: TUI redraw → WindowServer → AGX). A throwaway
   kitty window scrolling text at full speed adds nothing over an idle kitty window (17.4 vs 21.9
   elements/s, control 11.6; 4 rounds). Nor does any single fork/exec, pty, pipe, socket, kqueue,
   `ps`/`pgrep` argv read, `notifyutil` or `git` call add ≥ 1 element per operation.
3. **Which processes carry it.** A process started under a unique sandbox profile holds about one
   `cred` and one data.kalloc.1024 element while it lives (+280–370 of each per 300 held), while a
   plain process holds neither. The fleet starts ~15 such credential-bearing processes a second.
   **Which process class leaves its element behind at exit is not isolated without root**: a 1 s
   `ps` poll misses short-lived execs, and the per-name regression is in § 5. The root capture that
   isolates it is staged (§ 6).
4. **Post-reboot slope: 1.9 GB/day**, measured over the first 1.3 h of this boot (0.05 → 0.16 GB,
   77 samples; mean since boot 1.77 GB/day), under the restart surge (load 50–155). The previous
   boot averaged **1.05 GB/day** over 13.8 days; the one before, 0.57 GB/day. At 1.05–1.9 GB/day the
   6 GB alarm fires **3–6 days** after a reboot (10-03 to 10-06) and the 9.9 GB panic-#5 level comes
   **5–9 days** after it. The live alarm row prints the current since-boot rate and days-to-alarm.

## 1. The series (capacity-alarm.jsonl + rotated .gz, measured samples only)

`analyze.py` keeps rows whose kalloc value was read that tick (`src=measured`), orders them by time
(the rotated files are not in time order by name) and splits at reboots.

| Boot segment (UTC) | Samples | Level | Days | Slope (least squares) |
|---|---|---|---|---|
| 2026-09-10 11:39 → 09-16 20:41 (rung 8 starts mid-boot) | 555 | 10.52 → 14.53 GB | 6.4 | 0.57 GB/day |
| 2026-09-16 20:56 → 09-30 15:29 | 993 | 0.00 → 14.78 GB | 13.8 | **1.05 GB/day** |
| 2026-09-30 20:48 → (live, co-growth sampler) | 77 | 0.05 → 0.16 GB | 0.05 | 1.9 GB/day |

The plan's "2.43 GB on 09-19" start point was an artifact of reading the rotated file as if it were
the start of the boot; the boot began 09-16 after the double panic.

## 2. Correlation against fleet activity (the ticket's columns)

Pearson r between the kalloc increment per bucket and the bucket's mean of each column, and between
the detrended level and the detrended cumulative integral of each column (does the level track
accumulated activity better than wall time?).

| Column | 1 h increments, boot 1 / boot 2 | 24 h increments, boot 1 (n=6) / boot 2 (n=14) | Detrended cumulative, boot 1 / boot 2 |
|---|---|---|---|
| sessions | 0.26 / 0.21 | 0.66 / 0.28 | 0.60 / 0.56 |
| load_1m | 0.11 / 0.29 | 0.96 / 0.57 | 0.30 / 0.71 |
| coal_true_procs (kitty coalition) | 0.39 / 0.27 | 0.62 / 0.38 | 0.65 / 0.62 |
| max_proc_gb (top_procs head) | −0.05 / 0.24 | 0.36 / 0.31 | 0.08 / 0.70 |
| swapfiles | −0.01 / 0.28 | −0.06 / 0.52 | −0.05 / 0.82 |

Reading: growth follows *activity*, not wall time — but no activity column clears 0.6 consistently
across both boots and both resolutions (swapfiles is itself a per-boot ratchet, so its detrended
0.82 is collinearity, not cause). The alarm log's columns are too coarse to name a driver; the
instruments below were built for that.

## 3. No-root instruments, and what each found

| Instrument | Question | Result |
|---|---|---|
| `probe.py` (11 arms × A/B, control-bracketed) | does one operation add elements? | No arm ≥ 1 element/op reproducibly; the noise band is ±300–500 per 10 s window (`probe-arms-r*.jsonl`) |
| `render_ab.sh` (throwaway kitty, `--single-instance=no --config NONE`) | does terminal rendering drive it (#44824)? | **Refuted**: flood 17.4, idle window 21.9, control 11.6 elements/s (`render-ab.jsonl`) |
| `probe.py --sample-all` (every zone + every IOKit class, 60 s) | what co-grows with it? | **`cred` r = 0.93, `kalloc.48` r = 0.86**; next best 0.39 (`cogrowth-report.txt`) |
| `carry_ab.py` (hold 300 processes of a class alive) | which processes carry an element? | unique-sandbox-profile processes: +280–370 `cred` and data.kalloc.1024 per 300; plain `sleep`: neither (`carry-ab.jsonl`) |
| `sandbox_churn.py` (1 s `ps` poll + `sandbox_check`, 20 s windows) | does sandboxed-process churn track it? | ~15 births/s; r(Δkalloc, births) only 0.27–0.35 because short execs are missed, but r(Δkalloc, Δcred) = 0.875 again (`sandbox-churn-1.jsonl`) |

Two caveats on `sandbox_churn.py`: `sandbox_check()` also answers 1 for processes that are exiting
(`(bash)`, `<defunct>`) and for setuid `ps`, so its "sandboxed" label over-counts; and a 1 s poll
cannot see a process that lives less than a second.

## 4. What the credential link means

`cred` holds kernel credentials (`struct ucred`, 144 B); identical credentials are shared, so a new
one is created only when a process gets a credential no other process has: a uid change (setuid
exec), or a MAC-policy label change at exec (sandbox profile, entitlements). `kalloc.48` moving with
it is consistent with the credential's companion allocation. A 1 KiB **data** buffer (no pointers —
the `data.*` heap) created and freed with each such credential, and occasionally not freed, is the
shape the measurements fit. The standing stock of credentials stays around 2.5–10 K while the zone
passes 150 K elements, so the kept buffers outlive the credentials they came with.

## 5. Which process class — the per-name regression

`attribute.py` regresses each window's Δdata.kalloc.1024 on that window's births per process name
(`sandbox_churn.py` v2 logs them). Over 47 twenty-second windows (+34,793 elements):

| Best per-name r | Joint fit over the top 12 names | Verdict |
|---|---|---|
| 0.38 (`tr` caught mid-exit), then 0.31 (`bash` mid-exit), all others ≤ 0.21 | R² = 0.28 | **inconclusive** |

No process name clears r = 0.6, and the names that lead are ones the poll caught while exiting, which
is the instrument's blind spot rather than a finding: most of the ~1,000 forks/s live less than the
1 s poll interval. The kernel-side driver (§ Answer 1) is named; the userspace class that originates
the leaked credentials' buffers is **not**, and needs the exec-complete trace in § 6.
(Data: `~/.claude/logs/kalloc-sandbox-churn-2.jsonl`, rerun `python3 attribute.py <that file>`.)

## 6. The staged root capture

What the no-root instruments cannot see is every short-lived exec. `root_capture.sh` runs
`eslogger exec` (Endpoint Security; root) for 5 minutes beside a 20 s zone sampler and writes the
same window rows, so `attribute.py` ranks every exec'd binary (setuid execs tagged) against
Δdata.kalloc.1024. `--sysdiagnose` adds a sysdiagnose taken while the zone is high, for the Apple
report. It is staged as `~/.claude/autonomy/kalloc-root-capture.cmd`, which
`scripts/alarm-reboot-prep.sh` prints as the step **before** the next alarm reboot. `eslogger` needs
Full Disk Access for the launching app; without it the script says so and keeps the zprint snapshot.

A `sudo zprint` capture was considered and dropped: on SIP-enabled Apple Silicon, `zprint` shows
the same columns as root, and per-callsite zone logging (`zlog=` boot-args) needs Reduced Security.

## 7. Standing procedure until a fix holds the zone under 6 GB for 14 days

`scripts/capacity-alarm.sh`'s kalloc page now carries the procedure, and
`scripts/alarm-reboot-prep.sh` runs its agent half: start epoch, session roster, a land-in-flight
check that counts ship-land.sh processes (not `pgrep -f`, which matched 6 of 6 claude sessions whose
briefs merely mention the name), the staged capture, and the kitty-restart marker.
