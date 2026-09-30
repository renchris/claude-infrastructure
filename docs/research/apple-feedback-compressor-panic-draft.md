# Apple Feedback draft — VM compressor segment-limit panic, and a per-boot data.kalloc.1024 ratchet

**Status:** DRAFT, not yet filed. The operator files it in Feedback Assistant under the operator's
Apple ID (backlog `f525c9cb7983`); an agent then records the Feedback number on the line below.
**Feedback number:** _(pending — record it here after filing)_
**Why file it:** the panic class recurred five times in seven weeks on one machine, and nothing on
the user side can see it coming: the kernel's own `memoryPressure` flag read `false` at every death
we could read, so no pressure-keyed API, guard or jetsam band reacts before the watchdog fires.

---

## Paste into Feedback Assistant

**Area:** macOS › Kernel / Virtual memory · **Type:** Incorrect/Unexpected Behavior (panic)

**Title:** Kernel watchdog panic when the VM compressor hits 100% of its segment limit at 31–67% of
its page limit, with memoryPressure=false; separately, data.kalloc.1024 grows without bound each boot

**Environment:** MacBook Pro (MacBookPro18,2, Apple M1 Max), 64 GB. macOS 15.7.9 (24G830),
kernel `xnu-11417.140.69.711.44~1/RELEASE_ARM64_T6000` at the September panics; macOS 15.x at the
July–August ones. No third-party kexts, no roots installed, secure boot on.

**Workload:** a developer machine running 20–30 concurrent terminal sessions (kitty), each driving
a Node.js CLI that spawns build/test tools (Node workers, Next.js builds, Playwright Chromium,
clang-format). Process creation runs at roughly 1,000+ forks/second at peak.

**Steps to reproduce (the shape; the trigger is a burst of anonymous memory demand):**
1. Run a workload whose anonymous footprint exceeds physical RAM several times over within a few
   minutes (in two September cases: ten `clang-format` processes at 242–274 GB total RSS; in
   August: 670–747 Node workers at ~128 GB).
2. The compressor compresses at hundreds of MB/s while recently compressed pages fault back in.
3. Within minutes `c_segment_count` reaches the segment limit while compressed pages sit at 31–67%
   of the page limit; the system wedges and `watchdogd` misses check-ins for 91–94 s.

**Expected:** memory pressure is signalled (memoryPressure=true / pressure notifications / jetsam
kills of the largest consumers) before the compressor runs out of segments, and the system either
recovers or kills the offending processes. **Actual:** kernel panic, `watchdog timeout: no
checkins from watchdogd`, with `memoryPressure: false` in the panic's memory status.

**The five occurrences (panic-log compressor line):**

| Panic time (local) | Uptime | Compressor Info line | Swapfiles |
|---|---|---|---|
| 2026-07-30 02:18 | 55 h | 33% of compressed pages limit (OK), 100% of segments limit (BAD) | 67 |
| 2026-07-31 18:13 | 6.5 h | 31% pages (OK), 100% segments (BAD) | 66 |
| 2026-08-05 00:18 | 102 h | 31% pages (OK), 100% segments (BAD); panicked thread was `VM_compressor` | 68 |
| 2026-09-16 15:54 | ~22 d | 64% pages (OK), 100% segments (BAD) | 74 |
| 2026-09-16 16:28 | ~33 min | 67% pages (OK), 100% segments (BAD) | 65 |

A sixth panic on 2026-08-24 20:01 printed the same line (33% pages, 100% segments, 73 swapfiles).

**Why the segment limit is reached at a fraction of the page limit (our reading of xnu-11417):**
- `vm_compressor_out_of_space()` compares the raw `c_segment_count`, which includes segments that
  have been swapped out, to `compressor_segment_limit` (1,629,615 on this machine). The limit is
  effectively "compressed data the kernel may track, RAM plus disk" (about 124 GiB here).
- The page limit is the segment limit × 16, i.e. it assumes 4:1 compression. At death the ratio
  was 31% pages to 100% segments: about 5 of 16 page slots used per 64 KiB segment, an effective
  compression near 1.25:1. Either incompressible pages stored raw, or segments left mostly empty by
  decompress-and-refault churn, can produce that; both exhaust segments long before pages.
- On 2026-08-05, at death about 472K segments were resident (≈28.8 GB) and about 1.16M lived in
  the 68 swapfiles, while the swap volume had space ("OK swap space").
- The kernel's own edge notification fires at 98% of the segment limit, which at the measured
  consumption rate left about 7.6 s of warning.

**memoryPressure=false:** the panic reports for 2026-08-05 and both 2026-09-16 panics show
`memoryPressure: false` with 906 free pages. Anything keyed on memory pressure (dispatch memory
pressure sources, jetsam pressure bands) therefore did not engage before the watchdog fired.

**Related: data.kalloc.1024 grows for the whole boot and only a reboot releases it.** Read with
unprivileged `zprint data.kalloc.1024` (in-use elements × 1 KiB):
- 2026-08-24: 9.53 GB at 11:26 and 9.89 GB at the 20:01 panic, 10.9 days after boot.
- 2026-09-16: 14.53 GB of 19.47 GB wired at the 15:54 panic, 22.6 days after boot.
- 2026-09-16 → 09-30 boot: 0.00 → 14.78 GB over 13.8 days (least-squares 1.05 GB/day, 993 samples).
- After each reboot it reads 10–30 MB. It is never returned while the machine runs.
- Its short-term changes track the `cred` zone: over 47 one-minute windows the per-window change
  in data.kalloc.1024 correlated r = 0.94 with the change in `cred` (and r = 0.91 with
  `kalloc.48`), rising and falling about one-for-one. Processes started with a unique sandbox
  profile each hold about one `cred` and one data.kalloc.1024 element while alive. We could not
  identify, without root, what keeps the 1 KiB elements after the credentials are freed.
  This wired growth is not the panic mechanism (the 16:28 panic had 3.57 GB wired), but it removes
  up to 15 GB of RAM from a 64 GB machine and brings every burst that much closer to the limit.

**Attached** (copies of all four files, ready to drag in, are gathered in
`~/.claude/logs/panic-evidence/`; the panic text is there as `contents-2026-09-16-1628.panic`):
- `/Library/Logs/DiagnosticReports/.contents.panic` — the 2026-09-16 16:28 panic (the only full
  panic text macOS still retains here; the other `.panic` files have rotated away).
- `/Library/Logs/DiagnosticReports/JetsamEvent-2026-09-24-093745.ips`,
  `JetsamEvent-2026-09-24-235621.ips`, `JetsamEvent-2026-09-29-065125.ips` — jetsam reports from the
  last boot, carrying the zone and compressor state while data.kalloc.1024 was 9–14 GB.
- A sysdiagnose taken while data.kalloc.1024 is high (the operator runs `sudo sysdiagnose` before
  the next alarm reboot, if Apple asks for one).

---

## Sources in this repo

- Panic table, segment arithmetic, 98% edge: `docs/research/panic-compressor-2026-08-05.md` §§2, 4, 4a.
- September pair and `memoryPressure: false`: `docs/research/kernel-watchdog-panic-2026-09-16.md` §§1, 4.2, 4.3.
- 2026-08-24 panic and the 9.53/9.89 GB zone readings: `docs/research/panic-2026-08-24-fifth-watchdog.md`,
  `docs/research/panic-2026-08-24-evidence/kernel-zone.md`.
- Zone series, slopes and the `cred` co-growth: `docs/research/kalloc-ratchet-2026-10.md`.
- A preserved copy of the surviving panic text, outside the repo:
  `~/.claude/logs/panic-evidence/contents-2026-09-16-1628.panic`.
