# Kernel watchdog panic, 2026-09-16 — the whole kitty fleet died at once

**Status:** DIAGNOSED AND FIXED (2026-09-16). Cause: ten `clang-format` processes, 242 GB and 274 GB
of anonymous footprint on a 64 GB box, from kitty `./autoformat` walking a dev tree's vendored SIMDe
headers. **The box panicked TWICE** — 15:54:00 and 16:28:56 — and the second one, with the swarm
observed live three minutes before it, is what settled the diagnosis. Prevention landed in
`scripts/compressor-sentinel.sh` (Part III). Three of the recovery session's hypotheses are refuted
by control arm, including one of its own framings. Residual, not fixed here: the generator lives in
`~/kitty-dev/autoformat`, another session's tree (§ 6.4).
**Owner:** the research session fired from this doc.
**Artifact:** `/Library/Logs/DiagnosticReports/panic-full-2026-09-16-155400.0002.panic` (4.5 MB, JSON;
a copy rides beside this doc as `panic-2026-09-16.panic.copy`, untracked).

## Scope (frozen)

Answer, from disk truth, WHY this box hard-panicked, and land a prevention design that makes the
same wedge either impossible or self-limiting. Two deliverables, both required:

1. **A diagnosis** naming the mechanism, with a `file:line`/field citation for every claim, and
   explicitly separating what the panic log PROVES from what it merely permits.
2. **A prevention design** — bounded, implementable in this repo, with the acceptance test that
   would show it works. Landing the implementation is IN scope if the design is settled and green.

## What is already established (do not re-derive; DO re-verify anything you rely on)

Anchors:
- Panic at **2026-09-16 15:54:00 -0500**; reboot at **15:50:58**. macOS 15.7.9 (24G830),
  MacBookPro18,2 (M1 Pro/Max, T6000), **64 GB** RAM, kernel `xnu-11417.140.69.711.44`.
- Previous reboot was **2026-08-25** — 22 days clean. This is NOT a recurring panic; there is
  exactly one `.panic` file on the box.

The panic string:

```
panic(cpu 2 caller 0xfffffe002b6b434c): watchdog timeout: no checkins from watchdogd
in 91 seconds (26079 total checkins since monitoring last enabled)
```

`AppleARMWatchdogTimer` fired because `watchdogd` could not be scheduled for 91 s. That is a
SYMPTOM of a system-wide wedge, not a cause — the cause is whatever starved it.

**Memory state at panic** (`memoryStatus`, pageSize 16384):

| field | pages | bytes |
|---|---|---|
| wired | 1,324,927 | **20.22 GB** |
| active | 550,132 | 8.39 GB |
| inactive | 550,086 | 8.39 GB |
| **free** | **906** | **14.8 MB** |

- `memoryPressureDetails`: **pagesWanted 3094, pagesReclaimed 52** → **1.7 % reclaim efficiency**.
  The pageout path was asking and getting nothing.
- `memoryPressure: false` — the kernel's own pressure flag read FALSE while reclaim was failing 98 %
  of the time. That discrepancy is itself a finding worth running down.
- `compressions: 352,601,482` / `decompressions: 257,553,952`; compressor size 1,645,483 pages.
- 20.2 GB WIRED on a 64 GB box is abnormal (normal here is single-digit GB). Wired is unswappable,
  so it is the term that can actually strangle reclaim. **Whose wired pages?** — unanswered.

**The blocking chain** (`processByPid`):

```
pid 0 kernel_task  thread 2298: kernel mutex 0xfffffe000c294940 owned by thread 101
                   turnstile: blocked on 101, hops: 1, priority 91
```

**680 of 1,032 processes carried a `waitInfo`** — most are ordinary `mach_msg receive` idles, so do
NOT read 680 as "680 hung tasks" without separating idle-receive from genuine blocking.

**Process census — 1,032 processes.** Top names:

| n | proc | n | proc | n | proc |
|---|---|---|---|---|---|
| 175 | xpcproxy | 123 | bash | 48 | zsh |
| 38 | sh | 31 | gitstatusd | 29 | Browser Helper (Renderer) |
| 24 | node | 23 | claude.exe | 22 | Python |
| 22 | ps | 19 | distnoted | 16 | tee |
| 13 | jq | 12 | Cursor Helper (Plugin) | 11 | login |

**This is overwhelmingly our own fleet.** 23 `claude.exe` + 24 node + 123 bash + 48 zsh + 38 sh +
31 gitstatusd + 22 ps + 16 tee + 13 jq is the hook/sweep/gate/session-shell layer of this repo,
not the OS. 175 `xpcproxy` is the spawn-storm signature (xpcproxy is the exec stub for a launchd
job — a high count means jobs being spawned faster than they exec).

`last started kext: com.apple.filesystems.smbfs` — an SMB mount is a classic kernel-wedge source.
Whether one was mounted, and whether it is on the mutex chain, is UNTESTED.

## Open questions — these are the work, not a list to file

1. ~~Who owned thread 101?~~ **ANSWERED § 2 — `VM_pageout_scan`, not smbfs.** Resolve the mutex owner. `binaryImages` + the kext load list are in the
   same JSON. If it is `smbfs`, the story is a network-filesystem stall; if it is the VM/compressor,
   the story is memory. These imply different fixes.
2. ~~Which subsystem holds 20.2 GB wired?~~ **ANSWERED § 4.2 — `data.kalloc.1024`, 14.53 of 19.47 GB; and § 1 shows it is not the mechanism.** The panic log may not answer it; if not, say so and
   design the instrument that WOULD (a wired-memory sampler is cheap and we have none).
3. ~~Is `memoryPressure: false` with 1.7 % reclaim a kernel bug, a definitional artifact, or our
   misreading?~~ **ANSWERED § 4.3 — the ratio is an artifact (`pagesWanted` = free_target − free_count, 3094 in BOTH panics); the FLAG is real and is why no pressure-keyed guard can work here.**
4. ~~Did our fleet CAUSE it, CONTRIBUTE to it, or merely die with it?** Be honest about which the
   evidence supports. 1,032 processes is a fact; "1,032 processes panicked the box" is a hypothesis,
   and the corpus rule is that a mechanism must be priced in the units of the observed cost before
   it is accepted (see `.claude/rules/agent-operating-lessons.md`, "price a proposed cause").
5. ~~What is the fleet's steady-state process count, and what is its ceiling?** Nothing on this box
   measures or bounds it. `hooks/`, `scripts/autonomy-sweep.sh`, `cc-reaper`, the postland lane and
   the per-session shells all spawn; no admission gate counts TOTAL processes.
6. ~~Prevention.~~ **DELIVERED Part III — landed, 138/138.** Candidates, none yet argued: a process-count admission gate; a wired-memory
   watchdog that sheds sessions before the kernel watchdog fires; bounding concurrent sessions;
   bounding hook fan-out; a pre-panic tripwire that at least LEAVES A RECORD (we got none —
   the first thing anyone knew was a black screen).

## Method constraints (this repo's corpus, and they bind)

- **Every claim needs a citation** — a panic-log field, a `file:line`, or a command you ran and
  printed. A mechanism that cannot reach the observed magnitude is not a candidate.
- **A one-armed search cannot acquit.** If you look for evidence that our fleet caused this, also
  run the arm that could refute it.
- **Write incrementally.** Append to this doc as each question resolves — do not hold the findings
  and write at the end. (A prior session lost a full editing pass to a turn cap doing exactly that.)
- **Do not commit in `~/Development/claude-infrastructure`** — it is the shared checkout and the
  symlink source for `~/.claude`. You are in a dedicated worktree; commit here, land via the
  project-local `/ship`.
- The 6 recovered sessions are LIVE in other panes and were deliberately NOT nudged. Do not send
  them keystrokes, and do not `kill`/`pkill` anything broadly — an empty selector on this box has
  already caused a mass-termination incident (see the corpus rule of that name).

## Status log

- **2026-09-16 (recovery session):** panic anchored, memory + census + blocking chain extracted,
  6 crashed sessions restored unnudged. Analysis not started. This doc created; nothing implemented.
- **2026-09-16 16:28 (during the investigation):** **the box panicked a second time.** One of the
  restored sessions came back with its `/goal` armed, auto-continued, re-ran `./autoformat`, and
  reached 21 concurrent `clang-format` processes. A peer session captured the swarm live and walked
  its ancestry to a `claude --resume` with `ps`. That reproduction is Part II § 1 and it is the
  reason this diagnosis rests on a control arm rather than on a single log.
- **2026-09-16 17:0x (research session):** fix landed `b11d92f53..82cd45371`, content-verified on
  trunk; live layer converged on the degraded tier and the sentinel daemon restarted onto it
  (pid 1055 → 9749), so the repair is RUNNING and not merely on a git ref. Live acceptance check:
  cohort 0 on the healthy box, node-only without a baseline.
- **2026-09-16 (research session):** Part II diagnosis and Part III prevention written and landed.
  All six open questions answered with citations; two of them re-posed because the evidence did not
  support the question as asked (§ 4.1 process count, § 4.3 the reclaim ratio). Fix landed in
  `scripts/compressor-sentinel.sh` with 9 new cases in `tests/compressor-sentinel.bats`, 138/138.

---

# PART II — Diagnosis (research session, 2026-09-16 16:30–)

## 0. Answer, one line

**Both of today's panics were caused by ten `clang-format` processes holding 242 GB and 274 GB of
resident memory on a 64 GB machine** — spawned by kitty's `./autoformat` walking a dev tree's
vendored SIMDe headers — which filled **100 % of the VM compressor's 1,629,609 segment slots in
~130 seconds**, wedged `VM_pageout_scan` against the compressor lock, and starved `watchdogd` for
91 s / 94 s. **Our fleet caused it**, but not in the way the recovery session's framing suggests:
the process COUNT is exonerated and the RSS CONCENTRATION is the culprit. The shipped guard
detected both storms correctly and **actuated on nothing, twelve times**, because its cohort
selector is keyed on the executable name `^node` and the culprit is not node.

## 1. THE SECOND PANIC — a natural experiment nobody had to design

**The box panicked again at 16:28:56, 38 minutes after the reboot from the first one**, while this
investigation was in flight. `/Library/Logs/DiagnosticReports/panic-full-2026-09-16-162856.0002.panic`
(3.2 MB). `kern.shutdownreason: wdog,reset_in1 unknown`; `ResetCounter-2026-09-16-162908.diag`
`Boot faults: wdog,reset_in1`. A peer session (`claude-infrastructure-1`) captured the swarm LIVE at
16:25–16:27, three minutes before it died, and walked the full ancestry with `ps`.

This is worth more than any amount of re-reading of the first log: it is a **replication with the
generator observed in flight**, and it holds two variables that the first panic left confounded.

| | **PANIC 1** 15:54:00 | **PANIC 2** 16:28:56 | reading |
|---|---|---|---|
| panic string | `no checkins from watchdogd in 91 seconds` | `…in 94 seconds` | same class |
| checkins since enabled | 26,079 (≈ 22 d) | **197** (≈ 33 min) | uptime is irrelevant |
| Compressor Info | 64 % pages (OK) / **100 % segments (BAD)**, 74 swapfiles | 67 % pages (OK) / **100 % segments (BAD)**, 65 swapfiles | **the invariant** |
| panicked task | pid 0 `kernel_task`, 778 threads | pid 0 `kernel_task`, 712 threads | same |
| **wired** | **20.22 GB** | **3.57 GB** | **wired is NOT the mechanism** |
| free | 906 pages (14.2 MB) | 906 pages (14.2 MB) | identical — see § 4.3 |
| `memoryPressure` | `false` | `false` | false at both deaths |
| last started kext | **`com.apple.filesystems.smbfs`** | **`com.apple.filesystems.autofs`** | **smbfs is NOT the mechanism** |
| processes | 1,032 | **815** | **count is NOT the mechanism** |
| total process RSS | 269.8 GB | 289.5 GB | 4.2–4.5× RAM |
| **`clang-format`** | **10 procs, 242.2 GB = 89.8 %** | **10 procs, 273.9 GB = 94.6 %** | **the mechanism** |
| largest non-`clang-format` | WindowServer, 1,528 MB | kitty, 856 MB | nothing else is close |

Two of the recovery session's three live hypotheses die on this table, and they die by a control
arm rather than by argument:

- **smbfs is refuted.** `last started kext` is `smbfs` in panic 1 and `autofs` in panic 2. It names
  the most recently loaded kext, not a participant; on this box an `smbfs` load is what happens the
  first time anything touches an SMB path, and it had been loaded at `mach_absolute_time`
  33,434,671,703,740 against a panic at 39,631,829,001,741 — **84 % of the way through a 22-day
  boot**, i.e. hours to days before the storm, not adjacent to it. There were no SMB mounts at the
  panic (`mount` shows none now; the only smb-shaped process in the 1,032 was
  `smb-sync-preferences`, RSS 1 MB, not on any lock chain).
- **The 20.2 GB of wired is refuted as the mechanism.** Panic 2 reproduced the identical kill with
  **3.57 GB wired**, 5.7× less. Wired was a real *accelerant* on panic 1 (§ 4.2) and it is a real
  standing defect, but a mechanism that is absent from a reproduction of the same death cannot be
  the cause of it.
- **"1,032 processes panicked the box" is refuted.** Panic 2 died with **815**. This box is running
  **1,019 processes right now, healthy, at idle**, with 9 sessions
  (`ps -ax | wc -l` = 1019 at 16:12 post-boot). `xpcproxy` — the "spawn-storm signature" — reads
  **175 / 170 / (idle) comparable**, i.e. it is a *constant of this fleet*, not a storm indicator.
  Process count carried no information about either death.

## 2. Q1 — Who owned thread 101? **`VM_pageout_scan`. Not smbfs.**

Resolved directly out of the panic log's own thread table, which carries kernel thread NAMES that
nobody had read:

```
processByPid["0"].waitInfo      = ["thread 2298: kernel mutex 0xfffffe000c294940 owned by thread 101"]
processByPid["0"].turnstileInfo = ["thread 2298: blocked on 101, hops: 1, priority: 91"]
processByPid["0"].threadById["101"]  = {name: "VM_pageout_scan",  state: [TH_RUN],
                                        schedPriority: 91, systemTime: 1604.12 s}
processByPid["0"].threadById["2298"] = {name: "VM_compressor",    state: [TH_WAIT, TH_UNINT],
                                        schedFlags: [TH_SFLAG_RW_PROMOTED], systemTime: 989.76 s}
```

So the blocking chain is **`VM_compressor` blocked, uninterruptibly, on a kernel mutex held by
`VM_pageout_scan`, which was ON CORE and had burned 1,604 s of system time.** Both at priority 91.
The panicking thread, tid 2299, is a **second `VM_compressor`** thread, also `TH_RUN`, 179 s.
The two threads at the top of the panic log's CPU table are both `kernel_task` (2,781,816 and
1,890,233 — the same two VM threads).

This is a **memory** wedge end to end. There is no filesystem, no network, no driver on the chain.
The pageout scanner is spinning through a page queue it cannot reclaim from while the compressor
waits on it, and every userspace thread that faults — `watchdogd` among them — queues behind that.

*What this PROVES:* the lock holder is the VM pageout scanner, and the waiter is the compressor.
*What it only PERMITS:* it does not prove pageout_scan was making no progress — a `TH_RUN` sample
is one instant. The corroboration is `memoryPressureDetails` and the compressor's own 100 %-of-
segments verdict, both below.

## 3. Q4 — Did our fleet cause it? **Yes, and here is the price.**

The corpus rule binds: a mechanism must be priced in the units of the observed cost before it is
accepted. The observed cost is *the VM compressor's segment table, 1,629,609 slots, driven to
100 %*.

**The generator, named:** `clang-format`, 10 processes, one coalition (`jetsamCoalition` 117715 in
panic 1 — the same coalition as this fleet's `bash`/`zsh`/`claude.exe`/`node`; 663 in panic 2).
Their argv is preserved verbatim in our own sentinel's trip snapshot
(`~/.claude/logs/compressor-sentinel-snap.log:72245+`, trip `2026-09-16T20:46:29Z`):

```
  PID    PPID     RSS_KB   %CPU  ARGV
92423   91887    971504   45.7  clang-format --style=file:.clang-format \
                                --assume-filename=/private/tmp/kitty-dev/dependencies/darwin-arm64/include/xxhash.h
92469   91887    922288   59.1  … /simde/x86/avx.h
92467   91887    905600   60.2  … /simde/x86/avx2.h
92461   91887    875552   56.5  … /simde/x86/sse4.2.h
…
```

`pid 91887` is `Python`, RSS 32 MB, in the fleet's coalition — that is `python3 ./autoformat`.
The transcript holds the exact tool call that started it
(`~/.claude-tertiary/projects/…/wf_20caef3b-51e/agent-a1f6652a41a091e36.jsonl`,
**2026-09-16T20:46:07.797Z**, i.e. **22 seconds before the sentinel's first trip**):

```
cd /private/tmp/kitty-dev && export PATH="…/XcodeDefault.xctoolchain/usr/bin:$PATH" \
  && clang-format --version && python3 ./autoformat 2>&1 | tail -20
```

And the peer session walked the SECOND storm's ancestry live, with `ps`, at 16:25:

```
kitty(633) → reso-resume-one next3 …/kitty-drag-impl (98737) → expect(99821)
  → claude --resume 1e0730c9 (99828) → zsh(38828)
  → python ./autoformat  cwd=/Users/chrisren/kdev  (38839) → 21 × clang-format
```

**So the answer to Q4 is CAUSED, not merely died-with** — and the second storm settles the residual
doubt the first left, because it was observed from outside while it ran.

**The price, in the units of the cost:**

| quantity | measured |
|---|---|
| clang-format processes | 10 (panic 1 and 2); 21 seen live at 16:25 |
| RSS **per process** | 23.8–27.9 GB (panic 1), 28.5–30.4 GB (panic 2) |
| RSS **summed** | 242.2 GB / 273.9 GB |
| machine RAM | 64 GB |
| overcommit | **3.8× / 4.3× physical memory** |
| ignition → 100 % segments | **128 s** (panic 1: 13.79 % @20:46:18Z → 93.91 % @20:48:26Z) and **133 s** (panic 2: 8.71 % @21:23:45Z → 92.65 % @21:25:58Z) |
| swap created in that window | 3.1 GB → 73.3 GB (panic 1); 0 → 61.3 GB (panic 2) |

A 3.8× overcommit of anonymous memory is *exactly* the shape that exhausts a compressor segment
table, and the sentinel's own segment counter recorded it happening twice, at ~9,000–15,000
segments/second. **The mechanism reaches the observed magnitude with two orders of margin.** No
other candidate on this box comes within 1.5 GB of it.

**The refuting arm, run:** if the fleet did not cause this, some non-fleet process must hold the
memory. The full RSS ranking says otherwise — the largest non-`clang-format` process at panic 1 is
`WindowServer` at 1,528 MB and at panic 2 is `kitty` at 856 MB. Removing every `clang-format` row
leaves 27.6 GB and 15.6 GB of total process RSS respectively, on a 64 GB box: no storm, no panic.
The arm that could have acquitted us was run, and it convicts.

**Why `clang-format` at 27 GB is itself pathological** (and worth its own follow-up): `clang-format`
on ordinary source uses single-digit MB. The files here are `dependencies/darwin-arm64/include/simde/**`
— vendored SIMD-everywhere headers, the largest generated C headers in common circulation. Whether
this is quadratic behaviour in `clang-format` or merely a very large input, **10 concurrent copies
of it is a fleet decision and a fleet defect**, not an upstream one.

## 4. The remaining open questions

### 4.1 Q5 — steady-state process count and its ceiling: **the question is mis-posed**

Measured three ways: **1,032** at panic 1, **815** at panic 2, **1,019 at idle** 22 minutes after
the first reboot with 9 sessions and nothing wrong. Process count does not separate the healthy box
from the dying one; it is dominated by a constant tail (`xpcproxy` 175/170, `bash` 123/105, and the
per-session shell layer) that is present in all three readings.

**A process-count admission gate would not have prevented either panic, and would fire constantly
in normal operation.** Building one is the single most tempting wrong fix available here, and the
evidence forecloses it. The quantity that separates the three readings is **summed RSS**: 269.8 GB /
289.5 GB at the two deaths against roughly 25 GB at idle.

### 4.2 Q2 — who holds the wired memory: **`data.kalloc.1024`, ~75 % of it, and it is a separate defect**

Our own `capacity-alarm` already samples this, so no new instrument was needed:
`~/.claude/logs/capacity-alarm.jsonl`, row `2026-09-16T20:45:40Z` (8 minutes before panic 1) reads
`"wired_gb":19.47, "kalloc1024_gb":14.53, "uptime_days":22.6, "chronic_verdict":"ALARM"`.
So **14.53 of 19.47 GB — 75 % — of the wired footprint was the `data.kalloc.1024` zone**, the
boot-scoped ratchet attributed to upstream `anthropics/claude-code#44824` and already tracked as
capacity-alarm rung 8 (`docs/research/panic-2026-08-24-fifth-watchdog.md` § 10 follow-up). The
post-reboot rows read `"wired_gb":2.92, "kalloc1024_gb":0.02` — a clean before/after that confirms
the attribution and confirms it is uptime-scoped.

**It did not cause this panic** (panic 2 reproduced at 3.57 GB wired) but it is not innocent either:
20.2 GB of unswappable memory is 32 % of RAM taxed before the storm began, so panic 1 started
~5.7 GB closer to the cliff than panic 2 did. **Accelerant, not trigger** — the same verdict the
2026-08-24 synthesis reached for the same zone, now with a control arm behind it.

### 4.3 Q3 — `memoryPressure: false` with "1.7 % reclaim": **the reclaim figure is an artifact; the flag is real and is a genuine trap**

The recovery session read `pagesWanted 3094 / pagesReclaimed 52` as a 1.7 % reclaim efficiency.
**`pagesWanted` is not a demand measurement.** It reads **3094 in BOTH panics**, and:

```
vm.vm_page_free_target = 4000        (sysctl, this box)
free at panic 1        =  906 pages
free at panic 2        =  906 pages
4000 − 906             = 3094        ← exactly pagesWanted, both times
```

`pagesWanted` is the arithmetic identity *free_target − free_count*, so quoting a ratio built on it
describes the constant 4000, not the storm. The ratio is withdrawn. (`pagesReclaimed` does differ —
52 vs 162 — and is a real counter, but it has no denominator here.) **Free landing on exactly 906
pages in two independent panics is itself the finding**: the pageout path holds the free list pinned
just under its target and cannot get above it.

**The `memoryPressure: false` flag, however, is real, was `false` at both deaths, and is the reason
no pressure-keyed guard can ever work on this box.** It was `false` at the 2026-08-05 panic too
(`docs/research/panic-compressor-2026-08-05.md:196`). It is not a kernel bug: the flag tracks
*physical page scarcity*, and this kill axis is **segment-table exhaustion at 64–67 % of the pages
limit** — the compressor has plenty of pages and no free slots to put them in. Any future guard
keyed on `memoryPressure`, `DISPATCH_SOURCE_MEMORYPRESSURE`, jetsam bands, or "free RAM" is
**structurally blind to the only axis that has ever killed this machine.** The segment percentage
is the instrument, and we already compute it.

## 5. Q6 precondition — why the shipped guard did not prevent either panic

`scripts/compressor-sentinel.sh` was alive, sampling every 10 s, and **detected both storms
correctly and early**. It tripped at 27.68 % on panic 1 and at 8.71 % on panic 2. It then
**SIGSTOPped zero processes, on every single trip, twelve times across the two storms**, with its
own write-ahead evidence on disk:

```
~/.claude/logs/compressor-sentinel-snap.log
  ═══ TRIP 2026-09-16T20:46:29Z  why=seg+cbu ═══      (panic 1: 6 trips)
  actuator: INTENT SIGSTOP cohort_n=0 cliff=0 (write-ahead; signals follow)
  actuator: SIGSTOPped 0 process(es) (cap 400, floor 40960 kB)
  actuator: parent-break none — no eligible parent owns >= 3 of the 0 selected burst procs
  …
  ═══ TRIP 2026-09-16T21:25:58Z  why=seg+swap+cliff ═══  (panic 2: 6 more trips)
  actuator: SIGSTOPped 0 process(es) (cap 400, floor 40960 kB)
```

**The cause is one line of the cohort selector**, `scripts/compressor-sentinel.sh:517`:

```awk
      if (b !~ /^node/) next          # b = executable basename
```

`select_stop_targets` is keyed on **the executable NAME `^node`**, and `clang-format` is not node.
The parent-breaker cannot help either: `select_break_parents` ranks parents by *how many of the
selected cohort they own* (`:574`, `if (index(cohort, " " pid " ") > 0) kids[ppid]++`), and the
cohort was empty, so its threshold of 3 was unreachable by construction — the log line
`no eligible parent owns >= 3 of the 0 selected burst procs` is that arithmetic, printed.

This is the **empty-population** failure this repo has now met four times
(`.claude/rules/agent-operating-lessons.md`: *"A gate's surface is not its traffic"*). The guard was
built in August against a `next-server`/`postcss` node fork storm and encodes that storm's SPELLING
as its class test. The file's own header already anticipates the objection and accepts it
deliberately — *"Deliberately UNDER-inclusive: the cohort test is the EXECUTABLE NAME… a missed
worker costs one more tick of ramp, a wrongly-stopped process costs the operator's session"*
(`:487`). That cost model was wrong: **a missed worker cost the whole machine, twice in 35 minutes.**

Nothing else in the chain got a chance to matter. The kill rung (`kill_due` / `kill_escalate`,
`:909`) acts only on pids already in `FROZEN_DB`; with `cohort_n=0` the debt is 0 and `kill_due`
exits 1 at its first line (`if (debt + 0 < 1) exit 1`). The release-policy repairs, the probation
arm, the cliff regime and the write-ahead intent — the whole of the August remediation — all
functioned exactly as designed and all operated on the empty set.

---

# PART III — Prevention

## 6. The design, and the three candidates it beats

The measured defect is precise: **the actuator's cohort was an allow-list of one executable name.**
Everything downstream of it — the parent-breaker, the freeze ledger, probation, the cliff regime,
the kill rung — was built correctly in August and ran twelve times on the empty set. So the design
is to **repair the predicate and let the shipped machine work**, not to add a new mechanism.

Three candidates were considered and rejected on evidence, which is worth recording because each is
the obvious thing to reach for:

| candidate | why not |
|---|---|
| **A process-count admission gate** (the recovery session's first suggestion) | Refuted by § 4.1: 1,032 / 815 / 1,019 processes at panic 1, panic 2 and healthy idle. The signal carries no information, and a gate on it would fire permanently. |
| **A wired-memory watchdog** | Refuted by the second panic: 3.57 GB wired. It would not have fired. |
| **A pressure- or jetsam-keyed guard** | Refuted by `memoryPressure: false` at both deaths and at 2026-08-05 (§ 4.3). The kill axis is segment exhaustion at 64–67 % of the *pages* limit; every pressure API is blind to it by construction. |

### 6.1 What changed (`scripts/compressor-sentinel.sh`)

**One predicate, one new safety flag, one population floor.**

1. **`exe_table` gained two fields** — the full executable path (5) and a **path-protection flag**
   (6). The flag is computed in ONE place because three consumers read it, and three copies of a
   safety predicate are three chances to drift. Protected: a comm that is not an absolute path
   (a zombie renders as `(git)`; `kernel_task` has no path), and `/System/`, `/usr/libexec/`,
   `/usr/sbin/`, `/sbin/` — Apple's own daemons, the only processes here whose death is an OS event.
   `/usr/bin` and `/opt` are deliberately **not** protected: both of today's generators lived
   outside the system prefixes, one in an Xcode toolchain and one in a Python venv.
2. **`census()`'s pid roster became name-agnostic** (its three logged numbers stay node-only, so
   70,000+ historical rows keep their meaning). This is half the repair: with a node-only roster a
   `clang-format` pid was never in `prev`, so the *newness* gate was inert for it and the name test
   was the only thing between a storm and the actuator.
3. **`select_stop_targets` tests protection instead of the name** — `if (b !~ /^node/) next` became
   `if (eprot[pid] == 1) next`. The flag **fails closed**: anything not literally `0`, including a
   short row from an older capture, reads as protected.
4. **`ACT_MIN_COHORT` (3)** — the new class must show a *population*. **Scoped**: a cohort holding a
   node-named member is one the pre-fix selector would also have produced, so the floor never
   touches it and every shipped behaviour is preserved bit for bit.

The blast radius is unchanged in kind: `SIGSTOP` first, reversible, every existing exclusion intact
(`claude`/`claude.exe` by name, anything claude- or mcp-shaped by argv, this daemon and its
launcher), capped at `ACT_CAP`, and `SIGKILL` still reachable only through `kill_escalate`, only over
pids already in custody, only at ≥ 60 % and climbing.

### 6.2 Why this is safe — the control, run on the live box rather than argued

The honest objection to widening a cohort off a name is that it will freeze the operator's work.
The discriminator that answers it is **not** the protection flag; it is the **newness gate**, and its
strength is measurable. Two censuses 60 s apart on this box, healthy, under load 29:

| | measured |
|---|---|
| processes ≥ 40 MB (the actuator's floor) | **175** → 176 |
| of those, new since 60 s ago, not claude/mcp | **2** |
| after the path-protection rules | **0** — `/usr/libexec/coreduetd` and a `(git)` are exactly what those two rules remove |
| during the storm, same predicate | **10** `clang-format`, plus their spawner |

A process that has been running for hours — every browser renderer, every editor helper, the
operator's whole desktop — is on the previous census and cannot be in the cohort. Measured at the
panic: 90 of the 175 over-floor processes live in a GUI app bundle, and not one of them was new.

`.app/Contents/MacOS/` was tested as an explicit GUI exclusion and **rejected**, because it would
have spared the spawner: `python3` on this box resolves to Xcode's
`…/Python3.framework/…/Python.app/Contents/MacOS/Python`, a framework stub wearing a bundle path.
That near-miss is pinned as a test.

### 6.3 The acceptance test

`tests/compressor-sentinel.bats` § 5d, 8 cases, run against a **pinned pre-fix artifact**
(`a37feb5a9`, marked by the literal `b !~ /^node/` that this diff deletes — an unpinned
`origin/main` control would compare the fix to itself the moment it lands).

**The red-proof is the panic itself, replayed.** The ten real `clang-format` rows, transcribed from
the trip our own sentinel wrote 22 seconds after the generator started
(`compressor-sentinel-snap.log`, `TRIP 2026-09-16T20:46:29Z`), with the `exe_table` capture written
by hand so that `argv[0]` is the bare word `clang-format` while the path is the Xcode toolchain —
because a fixture that derived the path from `argv[0]` would hold constant the one axis under test.

```
PRE-FIX  (a37feb5a9): select_stop_targets → ""            ← the twelve-trip cohort_n=0, reproduced
POST-FIX            : select_stop_targets → 10 rows       ← plus the spawner
PRE-FIX  parent-break → ""                                 ← "no eligible parent owns >= 3 of the 0"
POST-FIX parent-break → "91887 10 Python"                  ← the autoformat driver, frozen first
```

The other six cases pin the safety argument: Apple daemons never selectable (with a positive control
proving the emptiness is the exclusion and not a broken selector), unidentifiable and short rows fail
closed, `claude.exe` still excluded now that `^node` is not doing it for free, the roster generalises
while the logged numbers do not, the toolchain-inside-a-bundle near-miss, and the population floor's
node escape hatch.

**Full suite: 137/137.** One pre-existing red was repaired on the way: the single-instance case
called a bare `timeout`, which is coreutils and is absent from the stock macOS PATH bats builds, so
it had been failing 127 on trunk independently of any subject — the very class
`scripts/unattended-path-lint.sh` exists to prevent, reproduced inside the suite.

### 6.4 What this does NOT fix, stated plainly

- **The generator is not in this repo.** `~/kitty-dev/autoformat` walks every directory under the
  checkout except `dist`, `build`, `bypy`, `3rdparty` and dotfiles — and a dev tree that has run
  `./dev.sh build` contains **`dependencies/darwin-arm64/include/simde/**`**, thousands of vendored
  SIMD headers among the largest generated C in circulation. `.clang-format-ignore` lists
  `3rdparty/**` and not `dependencies/`. Adding `dependencies` to either list ends this storm class
  at its source for one line. That tree is another session's working copy and is **not** edited here.
- **`clang-format` at 25–30 GB for one header is itself pathological** and is worth its own
  measurement; ten concurrent copies is our decision, but the per-process figure is not.
- **The `data.kalloc.1024` wired ratchet** (§ 4.2, 14.53 GB at 22.6 days) is untouched. It is
  already tracked as capacity-alarm rung 8 and is an accelerant, not a trigger.
- **`ACT_RSS_KB` may be the wrong instrument at the cliff.** `ps` RSS reports *resident* pages, and
  under an active compressor a process's footprint hides: the ten `clang-format`s read 530 MB–1 GB
  in `ps` at the trip while the panic log records 24–28 GB of footprint each. The 40 MB floor is low
  enough that this did not matter here, but a future storm of processes whose *resident* share falls
  below 40 MB while their footprint climbs would evade the floor. Naming it rather than fixing it:
  no cheap per-process footprint instrument exists for a 10-second shell tick.

### 6.5 A second session reached the same verdict independently

While this was in flight, a peer session working the same incident wrote
`actuator-roster-keyed-on-the-last-culprits-shape` into project memory, with the same mechanism
(`clang-format`, the `^node` allow-list, twelve trips, zero processes stopped) derived from its own
reads. Two sessions converging on one call without coordination is evidence **for** the call. Its
prescription — *"an actuator selects its targets by the same axis the detector trips on … never by a
list of binaries"* — is what § 6.1 implements; its own deliverable is the complementary one, a
post-panic **replay quarantine** (`docs/plans/KPANIC_DEFENSE_2026-09-16.md`), aimed at the fact that
a crashed session is auto-resumed carrying a brief that still names the fatal command as a required
gate. Neither change touches the other's code.

Its note contributes one residual that this diff does **not** close, recorded here rather than
silently inherited:

- **A 1:1 wrapper parent defeats the parent-breaker.** `select_break_parents` ranks a parent by how
  many of the selected cohort it owns (`≥ ACT_PARENT_MIN`, default 3). When each worker is launched
  through its own wrapper — which is exactly the shape now running on this box, `cc-jetsam-exec` →
  `cc-jetsam-launch` → `clang-format`, one wrapper per worker — every parent owns exactly one child
  and no spawner clears the threshold. The cohort arm still selects all ten workers, and they are the
  ones holding the memory, so the reclaim path is intact; what is lost is the *stop-the-minting* half.
  Walking ancestry to depth 2 before deciding nobody owns the swarm is the fix, and it is left to the
  peer's change rather than written twice into one function.

  **Corroborated in the panic log, not only in the live `ps` walk.** Panic 2's ten `clang-format`
  processes sit in `jetsamCoalition` **663**, and that coalition's membership is this fleet and
  nothing else — 67 `bash`, 24 `zsh`, 21 `Python`, **17 `claude.exe`**, 12 `kitten`, 7 `kitty`,
  6 `expect` — 211 of the 815 processes on the box. `Python` **pid 38839** (RSS 34 MB) is a member:
  that is the exact pid the peer named as `python ./autoformat cwd=/Users/chrisren/kdev`, so the
  ancestry it walked live is independently reproduced from the crash dump. And beside the ten
  `clang-format` pids (40214–40301) sit **eight `Python` processes at ~10 MB each in the same pid
  range** (40131, 40142, 40147, 40204, 40213, 40223, 40244, 40294) — the per-worker wrappers, which
  is the 1:1 parent shape above, visible in the panic data rather than inferred from it.

### 6.6 The fix is inert until the live layer converges

`~/.claude/scripts/compressor-sentinel.sh` is a **symlink** into the shared checkout, and the launchd
job execs that path (`launchd/com.claude.compressor-sentinel.plist:96`). Landing on trunk therefore
changes nothing by itself: the shared checkout was 19 commits behind at the time of this land, and
the running daemon has the pre-fix script already open. Two steps make the repair real, both taken
here under this repo's standing-converge authorization:

```
bash scripts/deploy-live.sh                                   # fast-forward the symlink source
launchctl kickstart -k gui/$UID/com.claude.compressor-sentinel  # the daemon re-reads the script
```

The restart is not optional and is not merely hygiene: bash reads a script incrementally, so a
long-running daemon whose file changes underneath it is in an undefined state — restarting is both
how the fix takes effect and the safe response to the file having moved. The freeze ledger was empty
(`compressor-sentinel-frozen.tsv`, 0 bytes), so no custody is stranded by the restart.

**Both were run, and verified by CONTENT rather than by a lag counter.** The converge was taken on
the degraded tier while the ordinary budget still read `lag 6 commit(s) / 0h32m, inside the degrade
budget (25 / 6h)` — i.e. no advance was due for up to six hours, which is the wrong trade for a
guard against a fault that has already recurred once today at a 35-minute interval.

```
~/.claude/scripts/compressor-sentinel.sh:597   if (eprot[pid] == 1) next        ← the new cohort test
~/.claude/scripts/compressor-sentinel.sh:598   if (!has_prev && b !~ /^node/) next
~/.claude/scripts/compressor-sentinel.sh:592   # WAS `if (b !~ /^node/) next` …  ← comment only
daemon pid 1055 → 9749, started 17:31:10, lsof confirms the fixed script open
```

### 6.7 The acceptance test, re-run against the DEPLOYED script on the live machine

The suite proves the predicate; this proves the thing actually running on the box. Functions
extracted from `~/.claude/scripts/compressor-sentinel.sh` (the live symlink), given a real census
roster taken 45 s earlier and the real `ps` table:

| | measured, 2026-09-16 17:32 |
|---|---|
| census roster (unprotected, ≥ 40 MB) | **87 pids** |
| **cohort the actuator would freeze right now** | **0** |
| same call with NO baseline (positive control) | **1 row, `node`** — pre-fix behaviour, exactly |

Zero on a healthy box and ten on the storm is the whole safety argument, and both halves are now
measurements rather than predictions.
