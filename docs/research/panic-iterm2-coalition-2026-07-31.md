# The 2026-07-31 18:13 panic — iTerm2 was blamed for its 1,002 children

**Question (operator).** iTerm2 froze and took the machine down again; the macOS out-of-memory modal
named **iTerm2 at ~500 GB**. Root-cause it and stop it recurring.

**Answer, one line.** **iTerm2 did not allocate that memory.** The iTerm2 *coalition* held
**139.5 GiB (90% of all process memory on the box)** at the last sample before death, but the
iTerm2 **process** was only **983 MB**. The memory belonged to the coalition's **1,002 child
processes** — our own Claude Code fleet and its subprocesses, which grew from **257 → 1,002 procs**
and **5.46 → 139.50 GiB in under 12 minutes**. macOS attributes coalition memory to the owning app,
so the modal blamed the terminal for what we launched inside it. The kill mechanism was the same
**VM-compressor SEGMENT exhaustion** as 2026-07-30 — the second occurrence of that class.

Machine: MacBookPro18,2 · Apple M1 Max (8P+2E) · 64 GiB · macOS Darwin 24.6.0 · iTerm2 3.6.11.
Boot 11:46:08 → panic **18:13:11** (uptime 6h27m). All times PDT; systemstats/guard logs are UTC
(local = UTC−7) and are converted here.

---

## 1. The kill mechanism (from the panic log)

```
panic(cpu 2 …): watchdog timeout: no checkins from watchdogd in 93 seconds
Compressor Info: 31% of compressed pages limit (OK) and 100% of segments limit (BAD)
                 with 66 swapfiles and OK swap space
```

The watchdog is the **victim**, not the cause. `100% of segments limit (BAD)` at only 31% of the
*pages* limit is the under-packing signature documented in
[[compressor-segment-exhaustion-panic]]: the compressor pool is provisioned for 124.3 GiB on a
64 GiB box, so segments can only be exhausted by allocating them **sparsely**, never by filling
them. This is the **second** panic of this exact class (first: 2026-07-30 02:18:05).

---

## 2. The system-wide memory timeline — flat, then dead in one window

`systemstats --show-events` over the boot (SystemMemory records, 10-min cadence):

| Time (PDT) | free | compressed | swapouts | reading |
|---|---|---|---|---|
| 11:46 – 17:28 | 3.4 – 5.3 Gi | 93 – 167 Mi | **0** | flat, healthy, all afternoon |
| 17:38:01 | 620 Mi | 2.22 Gi | 0 | **precursor spike — recovered** |
| 17:48:01 | 6.64 Gi | 1.07 Gi | 0 | recovered |
| 17:58:01 | 4.92 Gi | 1.04 Gi | **0** | healthy |
| **18:08:51** | **3.86 Mi** | **32.30 Gi** | **53.31 Gi** | dying |
| 18:13:11 | — | — | — | **panic** |

Cumulative paging counters across that final interval: compressions **7.73 → 167.24 GiB**,
swapouts **0 → 53.31 GiB**, swapins **0 → 34.43 GiB**, reactivations **4.34 → 103.04 GiB**. The
swapin/reactivation figures mean the box was **thrashing**, not merely filling.

Two things to note. The **17:38 precursor spike recovered on its own** — so a single excursion is
not sufficient to kill the box, and an alarm on that one sample would have been a false positive.
And the 18:08:51 sample **landed 50 seconds late** (cadence was `:X8:01` all day); the sampler was
already being starved.

**This is a RATE failure, not accumulation.** Zero swapouts in the first 6h12m; 53.31 GiB in the
last ~11. Uptime bought nothing — the same conclusion, and the same *retraction* of the
long-uptime theory, as 2026-07-30.

---

## 3. Attribution — who held the memory (the decisive measurement)

Top coalitions by `PhysFootprint` at **18:09:51**, the last CoalitionMemory sample before the panic:

| cid | PhysFootprint | Compressed | identity |
|---|---|---|---|
| **640** | **139.50 GiB** | **128.90 GiB** | **`com.googlecode.iterm2`** |
| 4287 | 5.15 GiB | 2.80 GiB | — |
| 650 | 3.52 GiB | 2.34 GiB | — |
| 338 | 1.99 GiB | 0.16 GiB | — |
| 666 | 1.54 GiB | 1.23 GiB | — |
| | | | *(all others < 0.31 GiB)* |
| | **Σ 155.75 GiB** | **Σ 138.60 GiB** | iTerm2 = **89.6%** of total |

Identity is measured, not inferred — `CoalitionUsage` rows for cid 640 carry
`guessedBundleId:com.googlecode.iterm2` continuously through the window.

### The iTerm2 coalition series — the shape that names the cause

| Time (PDT) | PhysFootprint | Compressed | **Procs** | Δphys |
|---|---|---|---|---|
| 11:47:52 | 0.69 Gi | 0.00 | 24 | — |
| 12:48:01 | 14.29 Gi | 0.00 | 184 | +9.63 ← transient, recovered |
| 14:58:01 | 23.99 Gi | 0.34 | 244 | +18.91 ← transient, recovered |
| 16:38:01 | 11.22 Gi | 0.27 | 320 | +4.44 ← transient, recovered |
| 17:28:01 | 6.03 Gi | 0.12 | 293 | +1.39 |
| 17:48:01 | 5.30 Gi | 0.42 | 243 | −0.32 |
| **17:58:01** | **5.46 Gi** | **0.39** | **257** | +0.16 |
| **18:09:51** | **139.50 Gi** | **128.90** | **1002** | **+134.04 (+11.33 GiB/min)** |

**The `Procs` column is the finding.** 257 → **1,002** processes in one interval. Mean footprint
per process also rose, 21.8 MiB → 142 MiB. Both count and size exploded together.

**iTerm2.app itself was not the allocator.** Our own capacity guard sampled the top processes at
17:52:48 and recorded:

```
WindowServer  1711 MB   ·   kitty  1156 MB   ·   iTerm2  983 MB
```

A 983 MB app cannot be a 139.5 GiB coalition. The ~745 additional processes were launched **inside
iTerm2 panes** — Claude Code sessions and their node/git/hook subprocesses. macOS coalition
accounting rolls all of that up to the owning application, which is exactly what the operator's
modal displayed. **The eyewitness "500 GB from iTerm2" is corroborated in kind and in blame-target,
but the allocator was us, not iTerm2.**

### Candidates checked and killed

- **iTermMetalBench / the terminal bakeoff** — REFUTED. `iTermMetalBench` logged **zero** lines as
  a running process in 18:03–18:13; the `loginwindow` references are stale saved-app state from the
  14:03/14:11 crashes, and the bakeoff tmpdir no longer exists.
- **A fork storm as the trigger** — REFUTED by its own denominator. PID consumption ran at
  **300–970 pids/sec across the whole afternoon** (753/s and 968/s at 17:24, long before the event)
  and is still ~200–740/s on the current healthy boot. High fork rate is this machine's **baseline**.
  Same trap, same kill, as the git-fork-storm candidate in the 07-30 investigation.
- **Session-launch rate** — NOT anomalous. 5 session registrations in the 4 minutes before death
  vs 7 in 3 minutes at 17:22–17:25, a healthy period.

### What remains unresolved

**Exactly which child processes ballooned, and why, is NOT established.** The 10-minute sampling
cadence puts the entire event inside one interval, and no per-process sample survives the fatal
gap. This is named as an open question rather than guessed at. The `xpcproxy`/`amfid`/`sandboxd`
spawn counts in the window (5,731 distinct `xpcproxy` pids in 10 min) are *consequences* of heavy
process execution, not the cause, and cannot identify the allocator.

---

## 4. Guard post-mortem — why the 2026-07-30 mitigation did not prevent this

`scripts/capacity-alarm.sh` (task #76, commits `d6ffb7cd` rung 5 + `f8142d88` ProcessType Adaptive).
Five-stage audit:

| Stage | Verdict | Evidence |
|---|---|---|
| Exists / committed | ✅ | `scripts/capacity-alarm.sh` tracked; 3 bats suites |
| Deployed live | ✅ | `~/.claude/scripts/capacity-alarm.sh` → symlink into checkout |
| Armed | ✅ | `launchctl list` shows `com.claude.capacity-alarm`; `StartInterval 600` |
| Ran in window | ✅ | rows at 17:42:42 and **17:52:48** |
| **Fired** | ❌ | both rows `verdict: OK` |

The last pre-panic reading, **20 min 23 s before death**:

```json
{"ts":"2026-08-01T00:52:48Z","verdict":"OK","sessions":17,"seg_pct":7.7,
 "headroom_gb":40.9,"compressor_gb":1.37,"swap_used_mb":0.0,"pressure_level":1}
```

Every field was **true at the time it was taken**. The guard did not malfunction. It failed on two
structural axes:

**(a) Sampling rate cannot resolve the event.** A 600 s interval against an ~11-minute
cold-to-dead transition gives at most one sample inside the event — and the sample due at
~18:02:48 PDT **never landed at all** (next row is 18:25:46, post-reboot). During the only twelve
minutes that mattered, the sensor was silent. This is the *same* conclusion reached and written
down after 2026-07-30 ("the rung would probably NOT have caught this panic") — it has now been
confirmed by a second death. A canary that is structurally slower than what it watches is not a
guard.

**(b) It measures the wrong nouns.** The guard tracks headroom, compressor GB, swap, kernel
pressure, `max_proc_gb`, and a **session count** (17). It has **no rung for coalition footprint and
no rung for process count** — the two quantities that actually moved (257 → 1,002 procs;
5.46 → 139.50 GiB in one coalition). `max_proc_gb` was 1.64 GB because no *single* process was
large; the mass was in the *population*. A per-process ceiling is blind to a population explosion
by construction.

**(c) It is alert-only.** Even had it fired, it pages; it does not throttle or shed. On an
unattended box that goes inoperable inside a single sampling interval, an alert is worth ~0.

---

## 5. A third defect this incident exposed: the crash disables its own investigation

Claude Code's `BackendRegistry` resolves the teammate backend **once per session** and caches the
result (`cachedDetectionResult`). With `teammateMode: "iterm2"` it gates on two probes:
`insideiTerm2` (satisfied by our `ITERM_SESSION_ID` shim, so it passes under kitty) and
`isIt2CliAvailable`, which runs **`it2 session list` and requires exit 0**.

Under kitty that path is `~/.claude/bin/it2` → `bin/it2-kitty` → `kitty @ ls` **+ a `python3`
interpreter start** to parse the JSON. During the post-panic boot storm (load 121, `mdsync`
saturating I/O) that probe failed once — and the cached failure **disabled all agent spawning for
the entire session**, with no retry. Verified: at steady state the identical probe returns rc 0.

So the failure mode is: *the panic reboot breaks the probe, and the broken probe removes the
parallelism you would use to investigate the panic.* The fleet's hot liveness probe — forked by
`cc-sessions`, `cc-notify`, `cc-inbox-guard`, `cc-reconcile`, `cc-teardown`, `handoff-fire` and
`teammate-auto-shutdown` — should not require an interpreter start to answer "list the panes".

---

## 6. What follows from this

Ranked by how directly each addresses the **measured** cause.

1. **The guard must count the population, not the individuals.** Add rungs for
   *per-coalition footprint* and *process count per coalition*, and alarm on **rate of change**,
   not level — the 17:38 precursor proves a level trigger produces false positives, while a
   +134 GiB/12 min slope does not occur benignly.
2. **The sampling interval must be shorter than the event it watches.** 600 s cannot see an 11-min
   transition. Either sample far faster when any rung is non-green (adaptive cadence), or accept
   that this guard is forensic-only and say so in its own output.
3. **It needs an actuator.** Detection without shedding cannot save an unattended box. The safe
   shed is bounded: refuse *new* session spawns above a coalition-proc ceiling. That is a decision
   with real cost (it can refuse legitimate work) and is flagged here rather than taken unilaterally.
4. **Cap concurrent sessions per terminal coalition.** 1,002 processes under one app is the
   proximate quantity. Whatever the per-session subprocess fan-out is, it is unbounded today.
5. **Make `it2 session list` interpreter-free** so the fleet's hot probe cannot fail under load.

Migrating off iTerm2 is **not** indicated by this evidence and would not have prevented this panic:
the memory was in our child processes, and those would have been children of kitty or Ghostty
instead. (The separate WindowServer-saturation case for migrating is unaffected — see
`iterm2-freeze-30-sessions-2026-07-30.md`, which is a *different* failure.)

---

## Method notes

- Every percentage here has its denominator computed over the full boot before any excursion was
  called anomalous — the trap that produced two false causes in the 07-30 investigation and that
  killed the fork-storm candidate here.
- `$?` after a pipe is the **last element's** exit code. The first pass at the `it2` probe read
  `head`'s rc as success and nearly mis-scored the defect; every exit code in §5 was re-measured
  into a variable. See [[pipefail-inverts-early-exit-probe]].
- Guard timestamps are UTC with a `Z` suffix; systemstats and the panic log are local. The 20-minute
  staleness figure is only correct after that conversion.

Related: [[compressor-segment-exhaustion-panic]] · [[agent-benchmark-panicked-the-box]] ·
[[darwin-qos-band-mechanics]] · [[liveness-proxy-cannot-be-output-age]] ·
[[positive-control-the-denominator]]

---

## 7. Implementation spec for rung 6 — with its denominator

`scripts/capacity-alarm.sh` has five rungs, max-combined in `classify()`. Rung 6 is
**process count under the controlling terminal coalition** — the one quantity that separated the
fatal sample from every healthy one.

**Measured denominator (this boot, 39 CoalitionMemory samples of cid 640 over 6h22m):**

| statistic | value |
|---|---|
| min | 24 |
| median | 226 |
| **max, healthy** | **353** |
| samples > 400 | **0** |
| samples > 500 | **0** |
| **fatal sample** | **1002** (2.84× healthy max) |

**Therefore:** `PROC_WARN=500` · `PROC_ALARM=700`. That is 1.42× and 1.98× the observed healthy
maximum, with **zero** false positives across the full boot, and the fatal sample clears both by a
wide margin. These numbers are derived, not chosen — do not adjust them without re-deriving against
a fresh series (published figures in this repo have gone stale inside 36 hours; see
[[published-figure-decays-with-its-source]]).

> 🚨 **SUPERSEDED 2026-08-01 — see §8.** Every figure in the table above reproduces exactly, but
> "zero false positives across the full boot" is true only of **this** boot. Against the *previous*
> boot's iTerm2 coalition (331 samples) the same thresholds fire on **6.0%** of the boot, including
> ten samples at or above the ALARM floor and a peak of **996 procs that the box survived** — six
> processes below the fatal sample. The derivation set was one boot; the population is not.
> **Do not treat `PROC_WARN`/`PROC_ALARM` as calibrated.** §8 has the wider denominator.

**Live read.** There is no cheap per-coalition sysctl. Walk `ps -Ao pid,ppid,comm` and count
descendants of the controlling terminal app pids (`iTerm2`, `kitty`, `ghostty`). Unreadable ⇒
**SKIPPED**, never a fabricated 0 — rung 3's standing policy.

**Alarm on slope as well as level.** The 17:38 precursor (free 620 Mi, compressed 2.22 GiB)
**recovered unaided**, so a level trigger alone will emit false positives. A +134 GiB / 12 min
slope has no benign counterpart in this series. Rung 6 should carry both, with the slope arm
requiring two consecutive samples.

**Cadence is a separate defect and rung 6 does not fix it.** At `StartInterval 600` the entire
fatal transition fits inside one interval, and the sample due mid-event never landed. Rung 6 makes
the guard *able* to see the event; it does not make it *fast enough*. Until the cadence is adaptive
(sample every ~60 s whenever any rung is non-green), this guard remains **forensic, not
preventive** — and its own output should say so rather than implying protection it cannot deliver.

**Sequencing note.** Rung 6 is specified here rather than implemented, because implementing it
touches `classify()`, the R6 positive-control probe table, and the JSON emitter in one edit, and a
half-applied change to a working five-rung guard is worse than none. It is the next commit, not a
research question — every input it needs is in this section.

---

## 8. Verification of the fan-out claim — REFUTED, and rung 6 is mis-nouned (2026-08-01)

§3 left the allocator unresolved. A follow-up reading proposed banking this:

> healthy fleet ≈ **13.7 procs/session** (151/11, live 05:35Z) vs ≈ **59/session** at the panic
> (1002/17) ⇒ the event was per-session subprocess **FAN-OUT**, not more sessions.

It was flagged "one sample; confirm before banking." Confirmed against a wider denominator, it does
not survive — and the failure is more useful than the claim would have been.

### 8.1 Neither ratio is a measurement

**The healthy side is not reproducible.** `~/.claude/logs/capacity-alarm.jsonl` now emits `coal_procs`
and `sessions` in the *same* row at 60 s cadence — a paired series, first row `2026-08-01T04:56:59Z`.
Over its 21 samples (all `coal_app:"kitty"`), `coal_procs/sessions` runs **min 3.47 · median 5.29 ·
max 6.76**. No row reads 151 procs; none reads 11 sessions (the 05:27→05:47Z window never drops below
16 sessions, and `coal_procs` peaks at 142). 13.7 is a hand-read the instrument does not corroborate.

**The panic side mixes two populations.** The numerator (1002) is systemstats `CoalitionMemory.
process_count` for cid 640 — **iTerm2 alone**. The denominator (17) is the guard's box-wide Claude
tree count from `2026-08-01T00:52:48Z`, **17 minutes earlier**. That boot had **seven** terminal
coalitions live — a terminal bakeoff: `com.googlecode.iterm2` (max 1002), `com.mitchellh.ghostty`
(97), `com.apple.Terminal` ×2 (62, 5), `com.cmuxterm.app` (10), `com.googlecode.iterm2.metalbench`
(61), `net.kovidgoyal.kitty` (99). The guard row's own `top_procs` lists **both** kitty (1156 MB)
*and* iTerm2 (983 MB). How many of the 17 sessions were inside cid 640 is unrecoverable, so 1002/17
has no defined value. (Direction, for the record: it can only *understate* the iTerm2-only ratio.)

### 8.2 The control the derivation never had: 996 procs, survived

Partitioning `systemstats --dump` by boot (cids are reused across boots — the 07-27 → 08-01 archive
holds five) gives the previous boot's iTerm2 coalition, cid 1121, **331 samples**:

| | boot 4 cid 640 (derivation set) | boot 2 cid 1121 |
|---|---|---|
| samples | 39 | **331** |
| max | 1002 (fatal) | **996 — survived** |
| samples ≥ 500 | 1 (the fatal one) | **20** |
| samples ≥ 700 | 1 (the fatal one) | **10** |
| % of boot ≥ WARN | 2.6% | **6.0%** |

Boot 2 held ≥500 procs continuously from **07-29 22:36 → 07-30 01:46 (3 h 10 m)** and peaked at 996.
The box stayed up. The fatal boot-4 sample was 1002. **The survived and fatal classes are separated
by six processes (0.6%)** — no threshold on this noun can distinguish them, at any setting.

### 8.3 What does separate them: mass per process

| sample | procs | anon | **MiB/proc** |
|---|---|---|---|
| boot 4 @17:58:01 healthy | 257 | 5.46 GiB | 21.8 |
| boot 4 @16:28:01 healthy peak | 353 | 6.78 GiB | 19.7 |
| boot 2 @00:36 **996 — survived** | 996 | 24.03 GiB | **24.7** |
| boot 2 @02:06 last before 02:18 panic | 473 | 16.80 GiB | 36.4 |
| boot 5 @today, peak | 224 | 6.29 GiB | 28.7 |
| **boot 4 @18:09:51 — FATAL** | **1002** | **139.50 GiB** | **142.6** |

Every healthy sample across four boots sits in **19.7–36.4 MiB/proc**; the fatal sample is **142.6**,
**3.9× outside the band**. Boot 2 and boot 4 held the *same population* at **5.8× different mass**.
So §3's "both count and size exploded together" is right, but only **size left the healthy envelope**
— and size is the term rung 6 does not measure.

### 8.4 The deployed rung would not have fired on its own event

Rung 6's thresholds were derived from systemstats `process_count`, but the live rung measures a
**`ps` tree-walk** (`read_coalition_procs`, `scripts/capacity-alarm.sh:343`). Those are different
instruments. Six time-aligned pairs on today's kitty coalition:

| systemstats (UTC) | procs | guard row | `coal_procs` | Δ | walk/ss |
|---|---|---|---|---|---|
| 04:56:21Z | 106 | 04:56:59Z | 64 | +38 s | 0.60 |
| 05:06:21Z | 97 | 05:07:05Z | 60 | +44 s | 0.62 |
| 05:16:21Z | 136 | 05:17:12Z | 59 | +51 s | 0.43 |
| 05:26:21Z | 108 | 05:27:16Z | 64 | +55 s | 0.59 |
| 05:36:21Z | 224 | 05:36:36Z | 130 | +15 s | 0.58 |
| 05:46:21Z | 158 | 05:46:30Z | 97 | +9 s | 0.61 |

**Mean 0.57 — the tree-walk reads 43% low.** Not a lag artifact: the two tightest-aligned pairs
(Δ +9 s, +15 s) sit at 0.61 and 0.58, right on the mean. **Mechanism, corroborated:** a kernel
coalition keeps a process that has been reparented away from the terminal, because membership is
inherited at `posix_spawn` and does not follow reparenting — but the walk stops at pid 1 by
construction (`while (q != "" && q + 0 > 1 && d < 64)`), so every orphan leaves its tree. Right now
**767 of 1125 live processes have ppid 1**, among them 21 `bash` and 6 `zsh`.

Consequence, in deployed units: `PROC_WARN=500` and `PROC_ALARM=700` correspond to roughly **877**
and **1228** coalition procs.

- The **fatal** sample (1002) would have walked to ≈ **571** → **WARN, never ALARM**.
- Boot 2's **survived** 996 would have walked to ≈ **568** → **WARN**.

The rung as deployed emits **the same verdict for the survived state and the fatal one**, and cannot
reach ALARM on the event it was built for. §7's "the fatal sample clears both by a wide margin" holds
only in the derivation instrument's units, not in the ones the code actually reads.

**Why the suite is green anyway — the test is blind by construction.** `capacity-alarm-segments.bats:128`
("the fatal 1002-proc coalition ALARMs, the healthy 353 max stays OK") calls `classify()` with the
literals **1002 and 353**, which are *systemstats* numbers, while the live caller passes
`read_coalition_procs` output, which is *walk* numbers. The test bypasses the instrument entirely, so
it asserts correct behaviour on values the instrument can never emit. Its own comment says that row
"IS the no-false-positive claim, executable" — but a claim pinned in the wrong units cannot go red for
this defect, and did not. All 48 tests pass on the code as it stands. A control has to replay the real
artifact, not a hand-picked stand-in for it: [[control-must-replay-the-real-artifact]],
[[sibling-guard-makes-the-fixture-vacuous]].

### 8.5 What reproduced, and what this changes

Every §7 figure reproduces exactly against its own denominator — N=39, median 226, healthy max 353,
`>400`=0, `>500`=0. §7 was accurate; it was **generalized past its population**. The correction is not
a new number, it is a wider one.

Standing conclusions:

1. **Do not bank "per-session fan-out."** The count did rise without a session rise, but that state
   has a survived precedent at the same magnitude. Fan-out is not what killed the box.
2. **Rung 6 counts the wrong noun.** Population size cannot separate the classes; **mass per process**
   separates them by 3.9×. Re-nouning is a design change, not a threshold tweak — the guard has no
   per-coalition footprint instrument, and the obvious one (summing `ps rss`) is the ~2.34× shared-page
   over-count this script's own header bans. Filed rather than half-applied, per §7's sequencing note.
3. **A threshold must be derived in the units its consumer reads.** The 43% instrument gap turned a
   correct derivation into a rung that cannot fire on its own event. See
   [[control-must-replay-the-real-artifact]] and [[proxy-must-be-independent-of-what-it-supplements]].

**Method note.** The claim's two halves failed for *different* reasons — the healthy half was
unreproducible, the panic half was incommensurable — and each looked plausible beside the other.
Two numbers that agree on a story are not corroboration when neither was measured against the same
population; see [[wrong-cause-corroborated-by-true-metric]] and
[[positive-control-the-denominator]].
