# Two watchdog panics in 37 minutes — the clang-format swarm is in both

**2026-09-16.** Forensics from the two panic reports themselves, not from live sampling.
Companion to the live captures by sibling sessions; this doc owns the *panic-report* evidence.

## The finding

Both panics are `watchdog timeout: no checkins from watchdogd`, and in **both** the top
eight memory consumers box-wide are `clang-format` processes at 26–32 GB resident each,
on a **64 GB** machine (`hw.memsize` 68,719,476,736; 10 cores).

| | P1 | P2 |
|---|---|---|
| report | `panic-full-2026-09-16-155400.0002.panic` | `panic-full-2026-09-16-162856.0002.panic` |
| boot → panic | 2026-08-25 02:16 → 09-16 15:50 (541.6 h) | 2026-09-16 15:50:58 → 16:28:04 (**37 min**) |
| panic string | no checkins in 91 s | no checkins in 94 s |
| processes in stackshot | 1032 | 815 |
| `clang-format` instances | **10** | **10** |
| their resident sum | 260.0 GB | 294.1 GB |
| their page-fault sum | 16,238,249 | 18,216,040 |
| free | **906 pages = 14.8 MB** | **906 pages = 14.8 MB** |
| wired | 21.71 GB | 3.84 GB |
| compressor | 26.96 GB | 37.71 GB |
| pagesWanted / reclaimed | 3094 / 52 = **1.7 %** | 3094 / 162 = **5.2 %** |
| `memoryPressure` flag | **false** | **false** |

Per-process in P2: pids 40214/40216/40217/40222/40229/40234/40250/40301/47395/70315,
`residentMemoryBytes` 19.5–31.8 GB, `pageFaults` 1.22–1.96 M, `userTimeTask` 41–80 s,
all in `jetsamCoalition` 663. The next-largest process on the box is `kitty` at 0.90 GB —
the swarm outweighs everything else by ~30×.

## The panic's own data corroborates the live ancestry walk

A sibling walked the tree live with `ps`:
`kitty(633) → reso-resume-one next3(98737) → expect(99821) → claude --resume(99828) →
zsh(38828) → python ./autoformat cwd=/Users/chrisren/kdev(38839) → clang-format children`.

P2's `jetsamCoalition` 663 contains **those exact pids** — 633 kitty, 99821 expect,
99828 claude.exe, 38828 zsh, 38839 Python (36.1 MB) — alongside ten ~10 MB `Python`
workers (40131, 40142, 40147, 40204, 40213, 40223, 40244, 40294, 47371, 70291) whose pids
**interleave one-for-one** with the ten clang-format pids. Two independent instruments,
same tree. P1's coalition 117715 has the same shape one boot earlier.

So the swarm is a Claude session's own subprocess tree, not a detached user job:
`kdev/autoformat` (kitty's upstream GPLv3 format script) fans out over every `.c/.h/.m/.slang`
file via `concurrent.futures`, one `clang-format` per worker, **unbounded**.

## Mechanism: the kernel never declared pressure, so nothing shed the load

`memoryPressure: false` in both reports. Jetsam therefore never killed anything, and the
swarm ran to the watchdog deadline. Free is pinned at **exactly 906 pages in both panics** —
the reserve floor — while the pageout scanner wants 3094 pages and reclaims 52 / 162 of them.
Everything is dirty anonymous memory: compressible, not evictable. `watchdogd` (2.2 MB RSS)
cannot fault in a page to make its checkin, misses the 91/94 s deadline, kernel panics.

That is why a per-process memory bound is the remedy and the OS is not: **the OS's own
pressure signal did not fire.**

## Correction — the checkin counts carry no signal

The panic strings read "26079 total checkins" (P1) and "197 total checkins" (P2), and the
34×-smaller number reads like watchdogd starvation. It is a denominator artifact: P1 ran
541.6 h and P2 ran 0.62 h, so the **rates** are 0.0134/s and 0.0885/s — P2's is 6.6× *higher*.
Checkin count scales with uptime and says nothing about starvation here. The starvation
evidence is the reclaim ratio and the pinned free floor, not the counter.

Likewise, the live `ps` reading of "~800 MB per instance / 16.6 GB total" understates the
panic's `residentMemoryBytes` by ~35×. The two fields are not the same measurement (`ps` RSS
counts resident pages; by sampling time most of the footprint had gone to the 37.7 GB
compressor). Either way the ranking is unchanged: clang-format is the memory event.

## Open — for the operator

1. **Why does one `clang-format` reach 30 GB?** It normally uses single-digit MB. A sibling
   session is testing preprocessor-branch combinatorics (nested `#if`/`#elif`, K=3 at depth D
   ⇒ 3^D formatting runs) under `cc-jetsam-exec --mem 1500 --fatal`. Result pending there.
2. **The re-entry path.** Six sessions were restored after P1 with `/goal` still armed and
   auto-continued with no nudge; one of them re-ran `./autoformat` and the box panicked again
   37 minutes later. A third panic is reachable the same way.
3. **Whose fix.** `kdev/autoformat` is upstream kitty's script in the operator's own tree.
   Bounding it (worker cap, or a per-process memory ceiling) is his call, not ours.

## Current state (17:01, 33 min into boot 3)

Clear: 0 clang-format, load 14.5, 17.9 GB free, compressor 0, `memory_pressure` 95 % free.
Nothing to kill. A sibling has a 20 s watcher armed on the swarm signature.

---

## Landed 2026-09-17 — two corrections that arrived after this was written

This doc sat on `refs/land/failed/20260916T220556Z-…-docs-panic-clang-format-swarm` overnight
(its author's `ship-land` did not complete) and is landed here unchanged above this line.
`docs/research/kernel-watchdog-panic-2026-09-16.md` — the sibling record of the same incident —
landed in the meantime, went further, and **contradicts one claim made above**. Read that doc's
§ 4.3 before quoting anything from the table.

**1. The reclaim ratio is WITHDRAWN.** The table's `pagesWanted / reclaimed` row (`3094 / 52 =
1.7 %`, `3094 / 162 = 5.2 %`) and the sentence *"the starvation evidence is the reclaim ratio and
the pinned free floor"* rest on a denominator that is not a measurement.
`memoryStatus.memoryPressureDetails.pagesWanted` is the arithmetic identity
`vm_page_free_target − free_count` = `4000 − 906` = **3094 in both panics because both operands are
pinned**, so a ratio built on it describes the sysctl constant, not the storm. `pagesReclaimed`
(52 vs 162) is a real counter and keeps its value; the *ratio* does not. The surviving half of that
paragraph is the one this doc found independently and is still correct: **free landing on exactly
906 pages in two unrelated panics is itself the finding**, and `memoryPressure: false` is real,
which is why no pressure-keyed guard can work on this box. Sources:
`docs/research/kernel-watchdog-panic-2026-09-16.md` § 4.3 and
`docs/lessons/a-crash-dump-s-memory-fields-are-derived-check-their-arithmetic.md`.

**2. "Resident sum" is the wrong name for the right number.** The table's `260.0 GB` and `294.1 GB`
are sums of per-process `residentMemoryBytes` on a **64 GB** box — 4.1× and 4.6× physical, which is
impossible for resident pages and is the tell. The field is the task's **`phys_footprint`, which
counts COMPRESSED pages at their UNCOMPRESSED size**; the arithmetic closes against the sentinel's
own `vm_stat`. For *pricing* a compressor exhaustion it is the right unit — it is exactly the
anonymous demand that fills the segment table — but it must be named footprint. This doc's own
closing note (`ps` RSS understates it ~35×, "the two fields are not the same measurement") reaches
the same place from the other side and stands; what changes is only what the number is called. The
consequence the sibling doc draws and this one did not: a `ps`-RSS-keyed **actuator** is nearly
blind to these processes, because RSS is the one quantity the compressor is actively hiding.

**Cross-reference.** `kernel-watchdog-panic-2026-09-16.md` § 6.5 cites this record as
`docs/research/panic-2026-09-16-clang-format-swarm.md`. The path is
`docs/research/panic-clang-format-swarm-2026-09-16.md` (this file); that citation is corrected in
the same commit as this land. Nothing above this line was edited — the doc is the author's record
of what the panic reports said on 2026-09-16, corrections appended rather than folded in.
