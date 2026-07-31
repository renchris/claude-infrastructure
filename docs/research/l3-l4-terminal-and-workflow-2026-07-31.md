# The terminal and the workflow for 30+ visible Claude Code panes — adjudicating two AI reports against this box — 2026-07-31

**Question (operator).** Best terminal application *and* workflow for a Level 3–4 AI engineer per Boris
Cherny's adoption ladder, given 30+ concurrent Claude Code sessions as **visible** split panes across 3
external monitors on an M1 Max / 64 GiB, which currently lags, freezes and crashes the box. Two
deep-research reports (attributed to ChatGPT 5.6 and Gemini 3.1 Pro) were supplied for adjudication.

---

## 0. Bottom line, four sentences

1. **The two supplied reports are the same document**, so they corroborate nothing.
2. **Their shared diagnosis — V8 heaps → 45 GB → swap thrashing → freeze/crash — is falsified by this
   machine's own panic logs, twice**, and their headline remedy (`NODE_OPTIONS=--max-old-space-size=1024`)
   treats a cause that has not occurred while risking OOM-kills of live agents.
3. **Measured today: the terminal + compositor cost 2.3× the entire agent fleet** (iTerm2 122.1% +
   WindowServer 49.0% ≈ 1.7 cores, versus ~0.75 cores for all 15 live sessions), and iTerm2's tuning is
   *already exhausted* — all 9 render knobs verify `MATCH`, drift 0, and it still burns 1.2 cores at
   **half** the target session count. What remains is architectural.
4. **The requirement that makes this hard — "I must watch 30 panes to catch permission prompts" — is
   itself the Step-2 interaction model** that Boris's Step 3→4 explicitly replaces with *monitor by
   exception*. The terminal decision is real, but it is downstream of that.

---

## 1. The two reports are one report

The text supplied as *ChatGPT 5.6 Deep Research* and the text supplied as *Gemini 3.1 Pro Deep Research*
are the same document: identical title, identical section order, identical Table 1 values
(`5.1s / 22.1s`, `~2ms / ~12ms`, `~28-35 MB`, `~290 MB`), the identical E-core QoS paragraph, the
identical `autoMode` JSON with the same `2.1.207` claim, and an identical closing synthesis.

This matters for weighting, not for politeness: **two models agreeing is evidence; one text pasted twice
is not.** Every claim below is therefore adjudicated once, against measurement.

---

## 2. What actually crashed this machine — twice, and neither is what the reports say

Both panics are on disk. Their panic strings are the discriminator, and they disagree with each other
*and* with the reports.

| | **2026-07-30 08:30** | **2026-07-31 11:46** (46 min before this study) |
|---|---|---|
| panic | `watchdog timeout: no checkins from watchdogd in 92 seconds` | `Spinlock[…] timeout after 12583200 ticks @locks.c:446` |
| panicked task | `pid 0: kernel_task`, 731 threads | **`pid 57267: threadprice`, 8,368 threads** |
| Compressor | 33% pages (OK), **100% of segments (BAD)** | **0% pages (OK), 7% segments (OK)** |
| swap | 67 swapfiles, OK space | **0 swapfiles, OK space** |
| free RAM at death | **~20 GB free** | healthy |
| cause | VM-compressor **segment** exhaustion — structural, a *rate* failure | a research probe's **thread bomb** |

**Neither crash was memory exhaustion. Neither involved swap thrashing.**

- The 07-30 panic killed the box with ~20 GB free, `swap_low:0`, `swap_exhausted:0`, on the first swap
  write of a 55-hour boot. The compressor pool is provisioned for 124.3 GiB on a 64 GiB machine, so
  exhaustion is reachable only through *under-packing*. Guard shipped (`d6ffb7cd`, `f8142d88`).
- The 07-31 panic — the one that has this box at 46 minutes of uptime — was **self-inflicted by this
  very investigation.** A research subagent asked to "price a parked thread" wrote a spawner and ran an
  unbounded ladder `2000 → 8000 → 16000`; at 8,368 live threads the kernel took a spinlock-timeout
  panic. It killed 19 live sessions and the 11h57m/48-pane kitty run that was the evidence for the open
  §6.1 gap. Documented at `a123c35d` (branch `docs/panic-threadprice`).

⇒ **The report's causal chain is wrong at every link**, and its remedy targets the link that does not
exist. Measured `claude.exe` RSS today is **~215 MB** (range 211–295 MB across 15 live sessions), so 30
sessions project to **~6.5 GB, not 45 GB** — the report's premise is off by ~7×. Capping old-space at
1024 MB would clamp a heap that is not the problem, and a Claude Code session carrying a large
transcript that hits that ceiling dies mid-task.

### The natural experiment — 31 sessions, live, mid-study

The session count rose **15 → 31 during this investigation**, i.e. to the exact scale the reports say
collapses the machine. Measured at 31:

```
load avg 10.8 · CPU 41.3% IDLE · 4,955 threads · 905 procs
iTerm2 87.6%   WindowServer 47.0%
System-wide memory free: 93%          Pageouts: 0
```

**93% memory free and literally zero pageouts at 31 concurrent sessions.** There is no memory pressure,
no swap, and no thrashing at the load the reports model as fatal. This is a direct, in-situ
falsification of their premise — not an inference from a panic log.

Second-order note worth keeping: **iTerm2 fell 122.1% → 87.6% while the session count doubled.** Its CPU
is not proportional to session count, which is consistent with the prior finding that loadavg on this
box is not session-attributable. Whatever iTerm2 is spending, it is not spending it *per session*.

---

## 3. What the terminal actually costs — measured today, on the correct instrument

`top -l 2`, **second sample** (never `ps %cpu` — a lifetime average that misreads this box ~2.3×):

```
PID    COMMAND          %CPU   MEM     #TH
591    iTerm2           122.1  820M    12
371    WindowServer      49.0  1305M   28
584    ghostty            2.7  502M    127     ← 117–127 threads for 3 windows
…      claude.exe ×15   3.6–8.7  211–295M  ~29 each
```

- **iTerm2 + WindowServer ≈ 1.7 cores. All 15 Claude sessions ≈ 0.75 cores.**
  The terminal and compositor cost **2.3× the entire agent fleet** — at *half* the target load.
- This reproduces the prior finding (31 sessions = 111.9% total; one iTerm2 process exceeded the whole
  fleet) on a fresh boot and a fresh sample.

### The incumbent leaks mach ports at constant layout — measured, `verdict=OK`

`scripts/terminal-bench.sh --app iTerm2 --panes 15 --interval 900`, two readings 900 s apart with the
visible layout unchanged (the repo's defined leak instrument — **drift, never level**):

```
T0  app cpu=95.5 mem=743MB th=13 ports=659      T1  app cpu=98.9 mem=736MB th=12 ports=678
DRIFT (app, constant layout):
  mem MB        -7 over 900s  = -28.0/hr      ← no memory leak; RSS falls
  mach ports   +19 over 900s  = +76.0/hr      ← LEAK
PER-PANE at n=15:  threads/pane 0.87 · ports/pane 43.93 · MB/pane 49.5 · cpu%/pane 6.37
verdict=OK
```

**Memory is exonerated again and the port axis convicts.** ~76 ports/hour at a frozen layout is ~900
over a 12-hour day — on precisely the axis whose unbounded growth characterised the 2026-07-30 freeze
(WindowServer's mach-port table). This is the first clean drift reading on the incumbent, and it
converts the earlier "port growth is real and unexplained" note from an observation into a measured
rate. It also independently corroborates that the failure is **not** memory: RSS drifted *negative*
over the same window.

### Configuration is exhausted — this is the new finding

`scripts/iterm2-perf-parity.sh` → **`match=9 drift=0 unset=0 · VERDICT: MATCH`**. Every render knob in
the SSOT (`config/iterm2-perf.keys`) is applied and survived the reboot: adaptive-frame-rate throttle
re-enabled for TUI panes, `maximumFrameRate 30`, `slowFrameRate 10`, `activeUpdateCadence 30`,
`fastForegroundJobUpdates false`, `DimInactiveSplitPanes false`, `DimOnlyText true`.

**And iTerm2 still burns 122% CPU at 15 sessions.** A 5-second `sample` of pid 591 shows the CPU glyph
rasterizer still leading the Metal driver (`iTermTextDrawingHelper` 231 : `iTermMetalDriver` 134 — an
improvement on the 361:72 measured 07-29 at higher pane counts, because fewer panes now sit under the
≤5-per-tab Metal gate).

⇒ **There is no remaining configuration lever on iTerm2.** The next move is architectural.

---

## 4. The cost model the reports get backwards

The reports' central engineering recommendation is *"maximise GPU/Metal use."* On iTerm2 that is the
**wrong goal**, and the repo's controlled Cocoa/IOSurface benchmark (30 panes, fixed 6×5 grid, identical
geometry and pixels/second in every arm, 20 Hz, 5 reps) says why:

| same 30 panes, regrouped | WindowServer cost |
|---|---|
| **30 windows** × 1 surface | **+22.6 pp** |
| 6 windows × 5 surfaces | +17.5 pp |
| **1 window** × 30 surfaces | **+11.2 pp** |

**Windows cost 2.35×. Surfaces inside one window cost only 1.17×.** Windows are the expensive unit;
panes are nearly free (~3 IOSurfaces, ~0 net bytes per pane, vs 28–34 MB + ~4.9 mach ports per window).

Now the trap: iTerm2 hard-disables Metal for any tab holding ≥6 sessions (`cmp x8, #0x6` in
`-[PTYTab updateUseMetal]`, a compile-time `const NSInteger`, no preference, no defaults key) **and**
only for the *foreground* tab. So the only all-GPU layout for 30 sessions is **6 windows × 1 tab × 5
panes** — which pushes you into the 2.35× unit. And patching the cap out would add ~30 `CAMetalLayer`s
(~90 IOSurfaces) and 30 `CVDisplayLink` threads to the exact axis that froze the box, while
`acquireScarceResources` blocks the **main thread** up to 16.7 ms per pane per frame.

⇒ **Chasing the GPU on iTerm2 closes the trap from both sides. The cap is protecting you.** The win is
not more GPU — it is a renderer that needs *one surface for all 30 panes*.

*(Caveat kept honest: the all-Metal 6×5 configuration has never actually been run, here or upstream.
This is the sharpest falsifiable claim in the file.)*

---

## 5. Terminal verdict — one ruler, this box

| | iTerm2 (live) | **kitty** | WezTerm | Ghostty |
|---|---|---|---|---|
| panes measured | 15–23 | **24 / 26 / 36 / 48** | 6 / 38 | *pending* |
| **threads** | 11–12 | **8 / 7 / 10 / 10 — FLAT** | 33 / 257 | 117–127 @ 3 windows |
| **threads / pane** | ~1.1 | **0.33 → 0.21, flat** | **7.0, linear** | 3 (from source) |
| OS windows for N panes | 4–6 (forced) | **1** | 1 | ? |
| per-pane addressing | `ITERM_SESSION_ID` | `$KITTY_WINDOW_ID` + `kitten @` | `wezterm cli` | **no CLI IPC on macOS** |
| leak behaviour | **98 windows survived `close()`**; upstream #12097 OPEN since 2025-01-01 | churn-clean: 101 panes, RSS/ports returned exactly | untested | untested |

**kitty is the measured winner**, and the strongest single datum is the one salvaged from the crash:
**48 panes, 12 hours uptime, 10 threads, 710 MB, 4 OS windows** — flat threads at *double* the
previously tested pane count, while iTerm2 at the same moment read 83.4% CPU with ~19 sessions.

**Both reports pick Ghostty.** Their stated grounds are (a) a benchmark table, (b) "the only terminal
that renders via Metal", and (c) automatic E-core QoS demotion of unfocused panes. (a) iTerm2 also has
a Metal renderer, so (b) is false on its face. (c) is the load-bearing claim and is under adversarial
verification. The live reading — **117–127 threads for 3 windows** — is not encouraging on the exact
discriminator that reversed WezTerm from front-runner to reject. Ghostty additionally has **no working
CLI IPC on macOS** (`performIpc` returns false; AppleScript only), which matters because 22 load-bearing
files here address panes programmatically.

**Also relevant and independently reported:** iTerm2 upstream **#12645** describes this operator's exact
signature — hours of an agentic TUI, 5+ s input lag in *other* apps, iTerm2 itself near-idle, cured only
by quitting iTerm2, on an M3 Pro and an M3 Studio. **Not this machine.**

---

## 6. Claim-by-claim adjudication of the supplied report

| # | Claim | Verdict |
|---|---|---|
| 1 | Crash = V8 heaps → 45 GB → swap thrashing | **REFUTED** — both panics on disk; neither is memory exhaustion; no swap thrashing in either |
| 2 | Each CC instance grows to ~1.5 GB | **REFUTED** — measured 211–295 MB across 15 live sessions |
| 3 | `NODE_OPTIONS=--max-old-space-size=1024` | **REJECTED** — treats a non-cause; risks OOM-killing agents mid-task |
| 4 | Maximise Metal/GPU | **BACKWARDS on iTerm2** — the GPU path allocates the objects that saturate the compositor |
| 5 | Ghostty is "the only" terminal rendering via Metal | **FALSE** — iTerm2 has a Metal renderer |
| 6 | Ghostty auto-demotes unfocused panes to E-cores via QoS | *under verification* — the decisive claim |
| 7 | Table 1 benchmark numbers | *provenance under verification*; presented as "2026 benchmarking data" without a source |
| 8 | Avoid fractional display scaling | *under verification against the actual monitor config* — plausible in mechanism, but the prescribed fix ("set to 1080p") would destroy the 30-pane visibility requirement |
| 9 | Use allow/ask/deny lists + auto mode to cut prompt fatigue | **DIRECTIONALLY RIGHT, mis-sized** — measured here, 88.3% of prompting Bash calls are *compound*, so a `Bash(prefix:*)` allow-list caps at ~2.4% coverage; the `ask` gates fired 22/41,829 = 0.05% |

---

## 7. The workflow half — the requirement is the bottleneck

Placed against the ladder: this setup is **Step 3 in mechanism, Step 2 in interaction model.** The
Step-3 machinery is present (worktree isolation, subagents, dynamic workflows, `/loop`, `/batch`,
`/goal`, Skills, CLAUDE.md standards, launchd routines, a paging channel). What is Step-2 is the
*human loop*: eyeballing 30 panes for permission prompts.

**That is the thing to fix, and it is upstream of the terminal choice.** Boris's Step 3→4 transition is
explicitly "steer by intent and **monitor by exception**". A pane grid is a polling interface: its cost
scales with agent count, and it is exactly the cost that is saturating the compositor. Exception
routing does not scale with agent count at all.

The uncomfortable implication, stated plainly: **the visibility requirement is not a constraint to
design around — it is the Step-2 residue to retire.** Not by hiding panes (that only trades
observability for silence), but by making a blocked session *reach out* rather than be *found*.

### The gap is not the notifier — it is that the notifier has no face

`~/.claude/hooks/cc-permission-beacon.sh` is **already wired on `PermissionRequest`** (with
PostToolUse / Stop / SessionEnd clears) and writes `{ts, tool_name, tool_input, cwd}` per blocked
session to `/tmp/cc-permission-pending/<sid>.json`. Its own header records why it exists: an
unattended session that hits a prompt hangs until a human answers — the 133-minute `git reset --hard`
incident.

**So the exception-routing primitive is built, wired and firing. What does not exist is anything that
renders that queue as the operator's primary surface.** That is precisely why the operator falls back
on eyes, and why 30 panes of continuous rendering are being paid for a job a 3-row list does better.

**Caught live while writing this file** — two sessions blocked simultaneously, with full pane
visibility across three monitors, one unattended for **6.6 minutes**:

```
83726a35  BLOCKED 0.1 min  Bash: cd /tmp && rm -rf ccmail-test && mkdir … && cp … && git show …
abf47077  BLOCKED 6.6 min  Bash: cd …/wt-capacity-chokepoint; REPO=$PWD; TMPH=$(mktemp -d); …
```

Both are **compound** commands — the structural reason the allow-list has plateaued: 88.3% of
prompting Bash calls are compound, so a `Bash(prefix:*)` allow-list caps at ~2.4% coverage regardless
of rule count. Live config confirms the plateau is not for lack of effort: `defaultMode: auto`,
**350 allow / 6 ask / 41 deny** rules, `autoMode` block present.

⇒ **Stop growing the allow-list; it is bounded by structure, not by effort.** And do not try to
eliminate the residue — a compound command touching `rm -rf`, a keychain and a worktree *should* stop
and ask. The defect is not that it blocks; it is that *discovering* the block costs a full-screen poll.

### Corollary: do not build a terminal from scratch

Considered and rejected on this box's own numbers. **WindowServer is the ceiling and it is Apple's** —
30 panes in one window cost ~+11.2 pp of a core inside the compositor, the floor for *any*
application, and kitty already sits on it (10 threads at 48 panes). A from-scratch emulator's best
case is matching something already installed and free. Worse, "maximise Metal" is the premise that
**already inverted here**: every GPU surface is a compositor object, and compositor objects are what
saturated WindowServer, so a Metal-maximising terminal would allocate exactly the thing that froze the
box. Add the real difficulty — VT correctness under Ink's alternate-screen / resize / wide-char usage
— plus permanent maintenance, and it is the maximum case of the "constant re-work" the operator ruled
out.

**What is worth building is ~2% of that work: a console, not a terminal.** One row per session
(status / blocked / last line), a queue fed by the beacon, zoom-to-full-screen on demand, and a
dispatch composer. It implements **no VT at all** — it drives kitty underneath — and its inputs already
exist here (the beacon, `cc-notify`, the mailbox, the session registry). Rendering then scales with how
many sessions are *blocked* (0–3), not how many are *running* (30+). Check Claude Code's own **Agent
view** and mobile/remote approval first; they may cover most of this for zero build.

---

## 8. What to do — ordered by (relief now) / (effort)

1. **Do not apply the `NODE_OPTIONS` cap.** It treats a falsified cause and can kill live agents.
2. **Stop the automation minting windows.** Windows are the 2.35× unit; this needs no migration.
3. **Recycle iTerm2** to make `activeUpdateCadence` (new-sessions-only) actually take effect. Verified
   safe on this box: all 15 sessions descend from `iTermServer-3.6.11` (pid 1067), a *separate* process
   — confirmed by ancestry walk this session; all 40 sessions survived the 07-30 restart with identical
   PIDs.
4. **Add a window-count rung to `capacity-alarm.sh`** (warn 25 / page 60, measured as *drift* at constant
   layout, never level).
5. **Migrate to kitty** — 22 load-bearing files over 3 primitives, chokepoint `bin/it2-wrapper`
   (175 lines), not `handoff-fire.sh` (4,024). Guard the known trap: `kitten @ launch --next-to id:$X`
   **silently mis-places** the pane unless `--match window_id:$X` is also passed.
6. **Retire the polling interface** — route blocked sessions to an exception channel so pane visibility
   stops being load-bearing.

---

## 9. What is NOT established

1. **kitty multi-hour drift at constant layout** — the 12-hour run existed and was destroyed by the
   07-31 panic before its second reading. §6.1 remains **OPEN**. A sampler is running.
2. **Ghostty is unmeasured** at pane scale.
3. **No Stage-B load test of any challenger.**
4. **No 4-display test** — per-display `CVDisplayLink` behaviour at mixed refresh is unmeasured.
5. **The all-Metal iTerm2 counterfactual has never been run.**
6. **The CoreAnimation defer-lock storm** is the leading suspect for the CPU the zombie windows do not
   explain; restarting iTerm2 took it 117/s → 58/s, so **another client produces the remainder** —
   switching terminals may not fully fix it.

Related: `terminal-for-30-panes-2026-07-31.md` · `iterm2-freeze-30-sessions-2026-07-30.md` ·
`gpu-vs-cpu-lag-2026-07-29.md` · `docs/panic-threadprice` (`a123c35d`)
