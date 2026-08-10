# 05 — Is the crash side closed at scale? Live-layer verification of the armed guards

**Measured:** 2026-08-09 23:18–23:32 PDT (UTC 2026-08-10 06:18–06:32), read-only.
**Scope owned:** the STATIC question — does ~35 GB resident engage the compressor at rest, what
segment margin remains — plus live-layer reachability of every crash-adjacent guard. The dynamic
memory-growth curve is a sibling axis and is deliberately absent here.
**Boundary honoured:** no SIGSTOP/SIGCONT, no job reload, no config edit, no compile triggered.

---

## 1. Verdict table

| # | Guard / fix | Landed sha | Live-layer reachable? | Binds the measured storm shape? | Evidence |
|---|---|---|---|---|---|
| 1 | **compressor-sentinel SIGSTOP actuator** (arm + 40 MB floor + cap 400) | `bed531d7` (+ plist, in `~/Library/LaunchAgents`) | **YES — armed and executing** | Partially: freezes the `^node` horde, not its spawner | `launchctl print gui/501/com.claude.compressor-sentinel` → `state = running`, `pid = 48326`, ProgramArguments export `CC_SENTINEL_ACT=stop CC_SENTINEL_ACT_RSS_KB=40960 CC_SENTINEL_ACT_CAP=400`; `inherited environment = { CC_SENTINEL_ACT => stop }` |
| 2 | **Sentinel parent-breaker** (SIGSTOP the spawner, `next-server`, comm ≠ `^node`) | `cb21783b` 08-09 16:40:37 | 🚨 **NO — landed, on disk, NOT in the running process** | **No.** The running image predates it by 9.5 h | `lsof -p 48326` fd `255r` → **inode 389784937, 33,200 B**; on-disk `scripts/compressor-sentinel.sh` → **inode 427219920, 42,679 B**. The 33,200-B blob is `ba1caec5` (**2026-08-07 01:36:56**). `grep -c 'select_break_parents\|ACT_PARENT'` = **0** in the running image, **18** on disk |
| 3 | **Wave C cold-compile admission gate** (`bin/cc-ignition-gate` + `hooks/coldcompile-admit.sh` + `config/coldcompile.patterns`) | `8db131c2` | **Files reachable, hook UNREGISTERED** | **No — inert.** And even if registered, see §3 | `coldcompile-admit` appears in **0 of 5** live `settings.json` (`~/.claude`, `-next`, `-secondary`, `-tertiary`, `-quaternary`; each carries 7 PreToolUse/Bash hooks, none this one). Running sessions use `CLAUDE_CONFIG_DIR=/Users/chrisren/.claude-tertiary` |
| 4 | **Migration 0006** (the registration half) | `087ebec5` | **STAGED, not applied** | n/a | `~/.claude/autonomy/migrations/staged/0006-coldcompile-admit-registration.json` (08-09 16:19); `applied/` holds only `0001`. `failed/` empty. Its own header: *"until it is registered the fix is a file nobody executes"* |
| 5 | **Turbopack worker-pool "cap"** (`scripts/turbopack-worker-cap-audit.sh`) | `812dab35` | Script present | **No — it is an AUDITOR, not a cap** | §S6.5 asked to *"cap the worker pool"*; what shipped observes 75 Next apps and files items. Naming it a cap in the wave summary overstates the artifact |
| 6 | **`workerThreads` generator kill** (`experimental.turbopackPluginRuntimeStrategy`) | not applicable (app-side) | **NOT SET in any of the 3 eligible apps** | **No** | `grep turbopackPluginRuntimeStrategy` → 0 hits in `reso-management-app/next.config.js`, `reso-qa-runner/next.config.js`, `agent-build-hackathon/next.config.ts`. `reso-management-app` has next **16.2.6** installed. Filed: `d60fd1f9c375` (reso-qa-runner, `add` 2026-08-09T22:14:51Z), `0e4f795b3a20` (agent-build-hackathon, 22:14:53Z) |
| 7 | **devserver-gc** (`DEVGC_ACT=1`) | pre-existing | **UNARMED, by design** | No (between-storm hygiene, not a burst guard) | `plutil -p com.claude.devserver-gc.plist` has **no `EnvironmentVariables` key at all**; the plist's own line 19 states there is deliberately no `DEVGC_ACT`. `state = not running`, `runs = 19`, `StartCalendarInterval Minute 40`. `~/.claude/logs/devserver-gc.last` → `verdict=none ts=20260810T054008Z act=0`. Backlog `898f8eafb809` state **block** — honestly filed |
| 8 | **Wave D memory term** (D7: gate can bind on segments) | not built | n/a | **No** | D7's own predicate: `grep -c compressor_segment scripts/lib/capacity-admit.sh` = **0**. The live term is still `free+speculative+inactive+purgeable` (`scripts/lib/capacity-admit.sh:163`). Computed live this session: **32.12 GB → ADMIT** against a 4 GB floor. Confirms §S6.6 — it cannot bind |
| 9 | **`memorystatus_control` per-pid memlimit** | not built | n/a | No | Backlog `7b762bcbbe11` (`add` 2026-08-09T11:45:39Z) — honestly filed |

### The one-line reading

**Of the two mechanisms that could stop the measured storm, one is landed-but-not-running and the
other is landed-but-not-registered.** What is genuinely armed and executing tonight is the
08-07 cohort-only actuator — the exact version whose successor commit is titled *"the horde's
spawner is not in the horde, so freezing the horde changed nothing."*

---

## 2. The sentinel is armed on STALE BYTES — the load-bearing finding

`com.claude.compressor-sentinel` is `KeepAlive`, `runs = 1`, `last exit code = (never exited)`,
started **04:36:15 PDT** by the arming reload. It therefore pinned its execution image at 04:36 and
has not re-read the script since. `execs = 2` (the `bash -c` and the `exec`), `forks = 1849` (the
per-cycle `ps`/`awk`) — no re-exec.

```
fd 255r  → inode 389784937   33,200 B   = ba1caec5, 2026-08-07 01:36:56
on disk  → inode 427219920   42,679 B   = post-cb21783b (parent-breaker)
```

Different inodes: the file was replaced (land sync, mtime 2026-08-09 20:52:01), so even a re-read
would return the old bytes. Verified by extracting the `ba1caec5` blob and grepping it.

**What IS live in the running image** (verified in the extracted blob):
`ACT="${CC_SENTINEL_ACT:-off}"` (line 80) · `ACT_RSS_KB` seam (line 81, default 102400) ·
`ACT_CAP` seam (line 82, default 200) · the `SIGSTOPped` / `DISARMED` printers (lines 552, 555).
Because the floor and cap are **env seams** and the plist exports `40960` / `400`, **the storm-shape
tuning is in force on the stale image.** The arming is real.

**What is NOT live:** the parent-breaker in its entirety — `ACT_PARENT`, `ACT_PARENT_MIN`,
`ACT_PARENT_CAP`, `select_break_parents`. Zero occurrences in the running image. So on the next
genuine storm the actuator freezes up to 400 `^node` children and leaves `next-server` running to
re-mint across the whole 60 s cooldown, which is precisely the failure `cb21783b` was written to
close.

**This is a class, and it was already filed.** Backlog `d74191a99b5f` (2026-08-09T23:52:28Z):
*"KeepAlive daemons keep running PRE-LAND bytes: install.sh reloads a job only on a CHANGED PLIST."*
`cb21783b` changed the **script**, not the plist, so nothing reloaded.

**A full audit of every running claude LaunchAgent found exactly one offender** — fd-inode vs
disk-inode, per job:

| Job | pid | Verdict |
|---|---|---|
| `com.claude.log-rotation` | 69747 | LIVE-BYTES |
| `com.chrisren.cc-reaper` | 80314 | LIVE-BYTES |
| **`com.claude.compressor-sentinel`** | **48326** | 🚨 **STALE-BYTES** |
| `com.claude.discovery` | 77808 | LIVE-BYTES |
| `com.chrisren.autonomy-sweep` | 15394 | LIVE-BYTES |
| `com.claude.lead-supervisor` | 821 | LIVE-BYTES |

Every other job is periodic and re-execs; the sentinel is the only never-exiting one, so it is the
only one that can hold pre-land bytes. **Remedy is one command and it is a job reload, outside this
session's boundary:** `launchctl kickstart -k gui/501/com.claude.compressor-sentinel` (re-execs from
the current file, preserving the plist's arming exports).

### The standing observable, checked

`crash-rootcause-2026-08-09.md:175` sets it: *"any `actuator: DISARMED` line after 2026-08-09 04:36
PDT is a regression to escalate."*

- `~/.claude/logs/compressor-sentinel-snap.log` — 33,564 lines, **54 `DISARMED` lines, 95 `TRIP`
  blocks, last TRIP `2026-08-09T11:14:03Z` (= 04:14:03 PDT)**. Every one predates the 04:36:15 arm.
  **No regression.**
- …but the pass is **vacuous**: there have been **zero trips since arming**. The snap log's mtime is
  04:14; the JSONL has written 6,603 rows since 11:36Z with **max `pct` = 0.20 %**, max `seg` 3,279,
  max node `n` = 7, max node RSS 5,498 MB, **max swap 0**. The armed actuator has never fired in the
  field. Verification still rests on the three legs the doc names — and one of those legs has drifted:
  the doc cites `tests/compressor-sentinel.bats:434` for *"`CC_SENTINEL_ACT=stop` reaches the actuator
  branch"*; the parent-breaker commit shifted the file and that test is now at **line 581**
  (line 434 is now a burst-cohort case). Citation drift, not a broken leg.

---

## 3. Does Wave C's admission path bind the MEASURED shape? No — and registration is only the first reason

**Reason 1 — it is unregistered.** 0 of 5 config dirs. Migration 0006 stages and never runs its body
(class `c10`: it edits `settings.json`, the live permission surface, which `migrations/README.md`
says a human ratifies once). Until then the gate is a file nobody executes.

**Reason 2 — the chokepoint does not intersect the generator's trigger, and this survives registration.**

- The hook is `PreToolUse(Bash)`. It rewrites an agent's **Bash command** to `gate ; <original>`.
- Term 1 (incumbent) matches an ignition-shaped argv younger than `SETTLE_S` **90 s** — deliberately
  blind to a long-lived `next-server`, whose etime is hours.
- Term 2 (burst) fires above `BURST_N` **100** non-fleet `node` processes.
- **But W11's generator is repeated mass invalidation of an already-running `next-server` under
  continuous fleet EDITS.** Fleet edits arrive through `Edit` / `Write` / `MultiEdit` — a different
  PreToolUse matcher group, with no ignition gating registered (live chain: `backup-before-write.sh`,
  `check-edit-boundary.sh`, `plan-agent-teams-default.sh`). **No agent Bash call is required for the
  storm to start.** The gate is a serializer on the *agent-initiated ignition edge*; the panic-#5/#6
  shape (postcss children-of-children minted by pid 36923) does not cross that edge.
- Term 2 therefore only ever evaluates *if some unrelated agent happens to issue an ignition-shaped
  Bash command mid-storm*. It is a second-compile suppressor, not a storm brake.
- **Precision matters here**: the gate would *detect* the horde if invoked (postcss workers carry
  comm `node`, which is what term 2 counts, and what the sentinel's `^node` cohort already selects).
  The failure is invocation, not detection.

**What the gate DOES bind, and it is real:** a *new* cold compile issued from an agent Bash call
while another is inside its 90 s window, or while >100 non-fleet node processes are up. Against the
Aug-5 panic's ignition (`pnpm design:gate` → `next dev`, an agent Bash call) it binds squarely.
Against Aug-9's it does not.

**Design quality is high and independently verifiable.** The `gate ; <original>` shape (not a
prefix wrapper) is calibrated on the fleet's own 49,510-entry Bash corpus — 231 of 232 real ignition
entries are compound, so a wrapper would have covered 1 of 232. Disjointness with `qos-rewrite.sh`
is structural, and confirmed live: **exactly two** hooks in `~/.claude/hooks/` emit `updatedInput`
(`coldcompile-admit.sh`, `qos-rewrite.sh`), and the former declines every shape the latter accepts.
Fail-open on every path. Argv-anchoring is load-bearing and proven end-to-end twice on live pids.

**Tests carry real mutation checks.** 43 cases across the three files (doc says 42 — off by one),
with 6 mutation/positive-control markers: `coldcompile-admit.bats` 27 cases / 4 controls (incl.
*"07 MUTATION CONTROL — a word-anchored table DOES gate a mention"*, *"22 … a settle window of 0
makes the incumbent invisible"*, *"24 … an UNANCHORED ignition ERE convicts that same bash row"*),
`coldcompile-admit-migration.bats` 7 / 1, `turbopack-worker-cap-audit.bats` 9 / 1.

**Live corroboration of the acceptance-run caveat.** A `next-server (v16.2.12)` was born mid-session
(pid 80034, ppid 79973, etime 1:05, RSS 1.28 GB). Sampled 6 × 10 s: **`srv_children` = 3, `postcss` =
3, node census 8–10, `seg_pct` 0.19 %, node RSS 1.40 GB — flat.** A fresh server compiling does not
storm. §S6.5-DONE's caveat is confirmed by independent observation, not just restated.

---

## 4. STATIC compressor engagement at ~35 GB resident (the question I own)

### The kernel constants, read live

```
hw.memsize                                     68,719,476,736   (64 GiB, 16 KB pages)
vm.compressor_segment_limit                         1,629,615
vm.compressor_segment_alloc_size                       81,920   (80 KB pool cost / segment)
vm.compressor_segment_buffer_size                      65,536   (64 KB payload / segment)
vm.compressor_segment_pages_compressed_limit       26,073,840   = 16.0 pages per segment
vm.compressor_pool_size                       133,498,077,184   = 1,629,615 x 81,920  (identity)
```

The segment limit **is** `pool_size ÷ alloc_size`. Two axes, and the panic signature is the gap
between them: segments **100 %** while the pages axis read **31–32 %** ⇒ 0.31 × 16 = **4.96 of 16
slots filled**, i.e. the documented ~28 % mean fill, arithmetically closed.

### Measured at rest, at and past the design point

| | Sample A 23:18 PDT | Sample B 23:32 PDT | 150-resident design point |
|---|---|---|---|
| Anonymous pages | 2,074,553 pg = **31.65 GiB** | **34.48 GiB** (37.03 GB) | 150 × 232 MB = **32.41 GiB** |
| Compressor segments | 3,235 / 1,629,615 = **0.20 %** | 3,506 = **0.22 %** | — |
| `pages_compressed` | 41,420 | 46,092 | — |
| Packing | 12.8 / 16 (80 %) | **13.15 / 16 (82 %)** | — |
| Swap used | **0.00 MB** | 0.00 MB | — |
| `vm.compressor_is_active` | 1 | 1 | — |
| Claude sessions | 18 | — | 150 |
| loadavg | 34.76 (3.48/core) | — | ceiling 20 (2.0/core) |

**Answer (a): yes, the compressor is engaged at rest at the design-point footprint — and it costs
0.2 % of the segment budget.** `is_active = 1`, 47,791 lifetime compressions, 46,092 pages currently
held. Engagement is driven by free-page shortfall, not by occupancy, and the pages it takes are cold
and pack near-ideally (82 % fill vs the panic's 31 %). **Static residency is not what spends
segments.** Sample B is 6.4 % *above* the 150-resident anon design point with zero swap — the
strongest available evidence that the crash axis is a burst axis, not a residency axis.

⚠️ **Composition caveat, stated because it bounds the claim.** The 34.48 GiB anon is 18 sessions +
a 2.6 GB `next-server` + Dia + this research wave — not 150 sessions. The compressor is
owner-blind, so the *page-count* claim transfers; a *per-session* claim does not, and that belongs to
the sibling axis.

### Segment margin, converted into the only unit that matters

Margin at rest: **1,626,109 of 1,629,615 segments free (99.78 %)**. To D3's 15 % bar:
**244,442 segments**. Segments are spent by *compressed-anon routed through a given packing*, so the
margin is a band, not a number:

| Packing regime | Original anon to reach D3's 15 % | To reach 100 % |
|---|---|---|
| **today, 13.15/16 (82 %)** | **52.7 GB** | 350 GB (unreachable) |
| **panic, 4.96/16 (31 %)** | **19.9 GB** | 132 GB — needs 66–68 swapfiles, which is exactly what the panics grew |

🚨 **The finding: at the panic's packing, the D3 bar costs 19.9 GB — the entire 19 GB burst budget
§S6.2 allocates at 150 resident.** There is no second margin. A burst that spends the whole budget
through a fragmenting compressor arrives *at* the sentinel's trip level, not comfortably under it.
The measured 372-proc wave (~23 GB) exceeds it; the 736-proc wave (~45 GB) is 2.3× past it. The
19 GB budget is a RAM figure that silently assumes ideal packing, and the failure mode is precisely
the loss of that assumption.

Swapped-out segments count against the same limit, which is why 100 % is reachable at all on a
64 GiB box — the panics carried 66–68 swapfiles. Today swap is 0.00 MB (fresh since reboot), so the
box currently starts from the best possible position on this axis.

**Corroborating D7 live:** the gate's memory term computes to **32.12 GB → ADMIT**
(free 2.26 + speculative 0.84 + inactive 28.72 + purgeable 0.31). Against a 4 GB floor it cannot
bind, exactly as §S6.6 says — 28.7 of its 32.1 GB is `inactive`, which includes dirty anon.

---

## 5. D8 — what "cold compile at ≥80 resident, seg_pct < 15 %" concretely requires

D8 is currently **unsatisfiable as written**, for five independent reasons. Each is a precondition,
not a nuance.

| | Requirement | State today | What must change |
|---|---|---|---|
| **P1** | The gate must actually run | Registered in 0 of 5 config dirs | Promote migration 0006 (`c10` → `mechanical`, one-word diff on line 2) after operator ratification. **Coverage hole:** 0006's loop covers `.claude`, `-secondary`, `-tertiary`, `-quaternary` — **not `~/.claude-next`**, which also has a `settings.json` (7 Bash hooks) and whose hook symlink is **absent** (`bin/cc-ignition-gate` present, `hooks/coldcompile-admit.sh` missing) |
| **P2** | The backstop must be the version that was verified | Running image = `ba1caec5`, no parent-breaker | `launchctl kickstart -k gui/501/com.claude.compressor-sentinel`, then confirm a trip prints a parent-break verdict (the disk version prints one on **every** armed trip, including `none`) |
| **P3** | ≥80 resident sessions | 18 | 🚨 **Conflicts with S6-DOD-V2.** V2 forbids synthetic spawning outright (*"No criterion in this plan requires spawning sessions to pass"*) and caps natural-growth verification at **40** (D1b). **D8 was not re-specified by V2 and still demands 80.** Either re-spec D8 to ≥40-natural, or record a waiver |
| **P4** | The storm must actually reproduce | It does not | Per W11 the generator is *repeated mass invalidation of a long-lived `next-server` under continuous fleet edits* — not a one-shot cold compile. Measured live tonight: a fresh `next-server` at 3 postcss children, flat over 60 s, `seg_pct` 0.19 %. §S6.5-DONE's own caveat says the `< 15 %` bar is satisfiable by a run that never approaches the failure mode; that is still true |
| **P5** | The generator's state must be declared | `workerThreads` unset in all 3 eligible apps | If it is set in the app under test, D8 measures a box where the child-process pool is structurally gone — a valid but *different* test. State which, in writing, or the result is uninterpretable |

**A D8 that would actually prove something** — the minimum honest shape:

1. Promote 0006 (P1) and kickstart the sentinel (P2). Verify both by evidence, not by intent:
   `jq '.hooks.PreToolUse[]|select(.matcher=="Bash")' ~/.claude-tertiary/settings.json` names the
   hook, and `lsof -p <new pid> | awk '$4=="255r"'` reports the **current** inode.
2. Reach residency by natural fleet growth only. Sample `capacity-ramp.sh stat` per V2's D1a/D1c.
3. Drive the generator, not a cold compile: one long-lived `next-server` in a real app, plus a
   sustained edit stream across its module graph (the invalidation spike is the input, the compile
   is not). Abort bound: kill the server at `seg_pct` 10 %, independent of the mechanism under test.
4. Read `seg_pct` from `~/.claude/logs/compressor-sentinel.jsonl` `.pct` at 10 s cadence. Record
   **packing** (`vm.compressor_segment_pages_compressed ÷ seg`) alongside it — the D3 bar means
   19.9 GB at panic packing and 52.7 GB at today's, so a `pct` reading without its packing is
   uninterpretable.
5. Record which arm bound: `ignition-gate.jsonl` `verdict` (`busy` / `admit-after-wait` /
   `admit-timeout`) vs the sentinel's `actuator:` line. An `admit-timeout` residual is the designed
   handoff to the sentinel and must be counted, not treated as a pass.
6. Declare P5's flag state in the result.

---

## 6. Gap list

| # | Gap | Severity | Class | Disposition |
|---|---|---|---|---|
| G1 | **Sentinel runs pre-parent-breaker bytes** (inode 389784937 / 33,200 B vs disk 427219920 / 42,679 B) | **Critical** | `conclusion-must-reach-the-enforcing-store`; `landed-remedy-with-surviving-symptom` | One command, operator/next-session: `launchctl kickstart -k gui/501/com.claude.compressor-sentinel`. Related filed item `d74191a99b5f` |
| G2 | **Wave C hook registered in 0 of 5 config dirs** — the crash fix is inert | **Critical** | migration `0006` staged, `c10` awaiting ratification | Promote after ratification; the migration re-derives its own preconditions at consumption |
| G3 | **Migration 0006 does not cover `~/.claude-next`**, whose hook symlink is also absent | Medium | `caller-census-keyed-on-path-misses-the-name` | Add the dir to 0006's loop, or record why `-next` is out of scope |
| G4 | **The gate's chokepoint (Bash) does not intersect the storm's trigger (fleet edits)** | **High** | scope mismatch, not a defect in the artifact | Wave C binds the agent-initiated ignition edge only. The children-of-children shape needs the sentinel (G1) or the generator kill (G5). Record this in §S6.5 so a later reader does not mistake registration for closure |
| G5 | **`workerThreads` set in 0 of 3 eligible apps** — the only structural fix is unapplied | **High** | cross-repo; execution via reso's own rails | `d60fd1f9c375`, `0e4f795b3a20` filed 2026-08-09T22:14:5xZ; `reso-management-app` item pre-existing. Honest, but unlanded |
| G6 | **The armed actuator has zero field trips** (0 trips in 6,603 samples since arming; max `pct` 0.20 %) | Medium | vacuous pass | The `DISARMED`-regression check passes because nothing tripped. Do not read it as confirmation |
| G7 | **D8 demands ≥80 resident; S6-DOD-V2 forbids the only means of getting there and caps natural verification at 40** | Medium | spec conflict introduced by a partial re-spec | Re-spec D8 or waive in writing. V2 re-specified D1 only |
| G8 | **"Worker-pool cap" is an auditor, not a cap** | Low | naming overstates the artifact | Wording fix in §S6.5-DONE; the auditor itself is correct and found 2 uncovered apps |
| G9 | **D7 unsatisfied**: `grep -c compressor_segment scripts/lib/capacity-admit.sh` = 0; live term reads 32.12 GB → ADMIT | Medium | operator's call (Wave D) | Named in the plan; unchanged |
| G10 | **`crash-rootcause-2026-08-09.md:172` cites `tests/compressor-sentinel.bats:434`; the test is now at line 581** | Low | `scan-revision-predates-the-fix` | Re-cite by test name, not line |
| G11 | **The 19 GB burst budget assumes ideal packing.** At the panics' measured packing it is exactly the D3 15 % bar | **High** | new this session | Re-state §S6.2's budget as a packing-dependent band (19.9 GB fragmented / 52.7 GB packed), or the budget will read as headroom it does not have |

---

## 7. Adversarial self-pass — what I initially missed

Three gaps found and closed with real calls, not assumptions:

1. **"You checked `~/.claude`, but the fleet runs from `~/.claude-220` with `CLAUDE_CONFIG_DIR=~/.claude-tertiary`."**
   Correct, and it nearly produced a wrong verdict. Re-checked **all five** settings.json-bearing
   config dirs: `coldcompile-admit` in none, `qos-rewrite` in all five, 7 PreToolUse/Bash hooks each.
   The unregistered verdict holds — and G3 (the `-next` coverage hole) only surfaced because of it.

2. **"`launchctl print` shows the arming exports — but does the running PROCESS carry the code?"**
   This is the finding. `launchctl print` reports the *job definition*; `ps` reports the *process*;
   neither reports the *execution image*. Only `lsof` fd-inode vs disk-inode does. The
   `crash-rootcause` doc's arming evidence (leg 1: *"verified by the loaded job definition"*) is a
   correct claim about the wrong object — it proves the env reaches the process, and is silent on
   which bytes the process is running. Auditing all six running LaunchAgents the same way isolated
   the sentinel as the only offender, which also makes the finding a *class* with one instance rather
   than a one-off.

3. **"You are reasoning about compressor engagement from a doc's '28 % fill' rather than from the kernel."**
   Fair. Read the constants directly and closed the arithmetic: `segment_limit = pool_size ÷
   alloc_size`, `pages_compressed_limit ÷ segment_limit = 16.0` slots. The panic signature
   (segments 100 % / pages 31 %) then resolves to 4.96 of 16 slots, and the 15 %-bar cost falls out
   as 19.9 GB — which is G11, the sharpest number in this report and one I would not have reached
   from the prose.

**One thing a hostile reviewer would still hold against this report:** the sentinel's launchd
`jetsam priority = 40` puts the guard in a band jetsam reaches *before* the band-180 CC fleet it
guards. At the Aug-5 04:27 near-miss jetsam was walking low bands (it killed a 15 MB Apple daemon).
The sentinel is 3.4 MB and `KeepAlive`, so a kill yields nothing and launchd restarts it — but a
restart mid-storm costs the burst census and a cycle. Not measured here (no storm to observe);
named, not resolved.

---

## 8. Method and honesty notes

- Everything in §1, §2, §4 is **measured** this session by the cited command. §3's chokepoint
  analysis is **inferred** from the registered hook matchers plus W11's source-level generator model
  — the inference is falsifiable: register the hook, drive a mass-invalidation storm, and see whether
  `ignition-gate.jsonl` records anything at all.
- Sampling bound honoured: the longest instrument ran 60 s (6 × 10 s next-server child census).
- Ambient caveat: `loadavg 34.76` (3.48/core) during the measurement window — this research wave is
  itself part of the load. It does not affect the compressor readings (segments are an allocation
  count, not a rate), but it does mean the anon figures include this session's own footprint.
- Nothing was armed, reloaded, stopped, continued, or edited.
