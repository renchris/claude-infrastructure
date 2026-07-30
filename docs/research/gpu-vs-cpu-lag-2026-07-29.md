# Can claude-infrastructure use the Mac GPU to cut lag / memory pressure? — 2026-07-29

**Question (operator):** to optimally reduce/eliminate device lag and memory pressure / leaks /
crashes, can we and should we have claude-infrastructure utilize the Mac GPU, or is it not possible —
CPU only?

**Verdict — three parts, in the order that matters:**

1. **For the repo's own work: no, and it is not a tuning gap — it is a category mismatch.** There is
   nothing to move. 100% of this repo's compute is shell process orchestration, `git`, regex, JSON and
   text. That work has no data parallelism, so no GPU programming model applies.
2. **The one place the GPU genuinely matters — terminal rendering — is ALREADY on the GPU.** Metal is
   active in iTerm2 right now (verified below). The 136–152% CPU it burns is *not* recoverable by
   "turning the GPU on"; it is already on.
3. **Memory pressure cannot be fixed by the GPU by construction.** On Apple Silicon the GPU allocates
   from the *same* 64 GB unified pool (measured: 6.59 GB GPU-allocated). GPU offload relocates nothing —
   there is no separate VRAM to move pages into. Memory is *tight* but not swapping (see the corrected
   reading below), and no GPU decision changes that either way.

**The lag is CPU oversubscription, and the largest single contributor is the render path — but its
cost is driven by display configuration, not by which processor does the drawing.**

---

## Evidence

### Machine

Measured with `top -l 2` **second sample** — the repo's mandated standard, because `ps %cpu` is a
*lifetime average* and has previously misread this box by ~4× (`MACHINE_CAPACITY_V2.md` §1.1). An
earlier `ps`-based pass in this same investigation is superseded by the numbers below.

| Fact | Value |
|---|---|
| Chip | Apple M1 Max — 10 CPU cores (8P + 2E), 32 GPU cores |
| Memory | 64 GB unified, Metal 3 |
| Uptime | 2 days, 3:41 |
| loadavg | 27.73 → 48.25 → **65.19 / 61.39 / 51.67** = **6.52 per core** |
| CPU | 70.19% user + 29.80% sys, **0.0% idle** |
| Processes / threads | 1,502 / 7,264 |
| PhysMem | **61 G used, 929 M unused, 6,097 M compressor** |
| Swap | **0 swapins, 0 swapouts** |
| GPU utilization | Device 36%, Renderer 33–34%, Tiler 36%, `recoveryCount` 0 |

Three readings follow immediately:

- **The machine is fully CPU-saturated: 0.0% idle at 6.52 load/core.** The lag is real and severe, and
  it is a scheduler-contention problem.
- **Memory — corrected.** An earlier `memory_pressure` reading in this investigation said "84% free"
  and I initially reported memory as a non-issue. That was too generous. `memory_pressure`'s
  free-percentage counts *reclaimable* pages (free + speculative + inactive + purgeable) as free; `top`'s
  strictly-unused figure is **929 MB**, and the **compressor holds 6.1 GB** — i.e. the VM system *is*
  doing pressure work. What remains true and load-bearing: **swap is still 0 in/0 out**, so nothing is
  paging to disk, and the repo's own live `capacity-alarm` (which correctly measures reclaimable
  headroom) reads **26.07 GB headroom, verdict `OK`, "room for ~41 more" sessions**. So: **tight, working
  the compressor, not swapping, and not near an OOM** — but "nothing to see here" was wrong.
- **The GPU is not saturated (36%) — it has headroom.** So GPU non-use is not a capacity problem. The
  work simply is not GPU-shaped. Those are different failures and only the second is true here.

Note also that a `ps`-derived RSS total **overcounts shared pages by ~2.34×** on this box
(`MACHINE_CAPACITY_V2.md` §8.5.6). My earlier "21.7 GB across 34 Claude processes" is an `rss` sum and
should be read as ≈9 GB of true private footprint. Use `footprint(1)`/phys_footprint for any real
accounting.

### The repo's compute is categorically not GPU-amenable

`git ls-files` by extension:

```
251 md   239 sh   204 bats   50 py   36 svg   23 plist   14 yaml   13 json
```

Dependency and library sweep for anything GPU-capable — `numpy`, `torch`, `tensorflow`, `mlx`, `jax`,
`scipy`, `cupy`, `opencl`, `coreml`, `Accelerate`: **zero real dependencies.** Every grep hit is prose
in a doc or skill description, not an import. The repo has one `package.json` and no numeric stack.

A GPU needs thousands of identical operations over a contiguous array. Shell orchestration is the
opposite: `fork`/`exec`, syscalls, file I/O, and serial control flow. `git`, `shellcheck`, `bats`, and
JSON parsing are branch-heavy and pointer-chasing. **No amount of engineering moves them to a GPU** —
this is not a limitation we could remove with effort.

### CPU composition by GPU-amenability

`top -l 2` second sample, top consumers:

| %CPU | Process | GPU-amenable? |
|---|---|---|
| **94.7** | **iTerm2** (single process, 1946 M) | **Already on GPU via Metal** |
| **51.7** | **WindowServer** (1799 M) | **Already on GPU** |
| 40.5 | `kernel_task` | No — interrupt/thermal handling |
| 25.4 | `syspolicyd` | No |
| 22.6 | `SystemUIServer` | No |
| 18.2 + 8.7 | Google Chrome Helpers | Already GPU-accelerated |
| 9.8 / 8.9 / 6.1 / 4.7 / 4.6 | `claude.exe` ×5 (largest individually ≤9.8%) | No — network-bound LLM waits |
| 7.4 / 6.7 / 6.3 / 5.2 / 5.0 | `fontd`, `fseventsd`, `trustd`, `opendirectoryd`, `tccd` | No |
| 5.4 | `Python` (gate script) | No |
| 5.0 | `shellcheck` | No |

**iTerm2 + WindowServer = 146.4% ≈ 1.46 cores, the two largest consumers on the machine by a wide
margin — and the ONLY GPU-relevant slice. It is already GPU-accelerated.** No individual Claude session
exceeds 9.8%.

This independently reproduces the repo's four prior measurement passes, which concluded *the sessions
are not the load; the TUI renderer is*: 33 sessions across 38 panes measured iTerm2 ~115% +
WindowServer ~50% ≈ **1.6 cores spent purely drawing** (`MACHINE_CAPACITY_V2.md` §1, §8.5.7 — where a
single `iTerm.app` process at 125.2% **exceeded the entire 31-session fleet summed at 111.9%**).

### Metal is already active in iTerm2 — verified, not assumed

`defaults read com.googlecode.iterm2` has **no** metal/gpu keys at all (`UseMetal`,
`MetalMaximizeThroughput`, `DisableMetalWhenUnplugged`, `MetalDisableForceAlpha` all unset), so
iTerm2 3.6.11 runs on compiled-in defaults. Rather than trust a default, the running process was
inspected directly — iTerm2 pid 57251:

```
txt  /System/Library/Extensions/AGXMetalG13X.bundle/Contents/MacOS/AGXMetalG13X   ← M1 Max GPU driver
 4r  /Applications/iTerm.app/Contents/Resources/default.metallib                 ← iTerm2's own shaders
```

It has the **AGX (Apple GPU) driver loaded and its own Metal shader library open**.

Linking Metal is not the same as *running* it, so this was falsified one step further — the Metal
**compiled-shader cache** proves pipeline execution, not mere linkage:

```
$TMPDIR/../C/com.googlecode.iterm2/com.apple.metal/   →  1.2 MB total
  16777235_530/functions.data   884,736 bytes   Jul 27 19:01
  16777235_530/functions.list    23,116 bytes   Jul 28 07:59
```

A shader cache only exists once a process has compiled and executed Metal render pipelines, and these
entries are days-recent. **Metal is on and actively rendering.**

The known Metal-disqualifying profile settings are also all absent — `Transparency = 0.0`,
`Blur = false`, no background image, `Scrollback Lines = 1000` (not unlimited), on **AC power**
(so any battery-based Metal disable is moot), `reduceTransparency` already enabled.

**Therefore: iTerm2's 136–152% CPU is being spent *while* Metal renders.** That CPU is the
irreducibly serial half of terminal emulation — VT/ANSI parsing of the output stream, glyph layout,
and damage tracking for ~20+ continuously-repainting TUI panes — plus driving Metal. Per-character
stream parsing is inherently sequential. Enabling a GPU path that is already enabled buys zero.

### The actual driver of the render cost: display configuration

| Display | Framebuffer | Presented as | Refresh |
|---|---|---|---|
| Internal Color LCD (XDR) | 3456 × 2234 | native Retina | — |
| DELL S2725QC | 5120 × 2880 | 2560 × 1440 | 60 Hz |
| DELL S2725QC | 5120 × 2880 | 2560 × 1440 | **120 Hz** |
| DELL S2725QC | 5120 × 2880 | 2560 × 1440 | **120 Hz** |

**Total: 52.0M pixels composited per frame, two panels demanding 120 fps.**

Two compounding costs, both configuration, neither fixable by choosing a different processor:

1. **Refresh rate.** Two displays at 120 Hz means iTerm2 and WindowServer produce and composite frames
   at *twice* the rate of 60 Hz. This multiplies the entire 1.89-core render slice — and it multiplies
   the **CPU-side** per-frame work (parse, layout, damage, draw-call submission), which is exactly the
   part the GPU does not absorb.
2. **Scaled HiDPI.** The S2725QC is a 4K (3840 × 2160) panel, but macOS renders a
   **5120 × 2880** framebuffer and GPU-downsamples to the panel. That is the classic scaled-resolution
   penalty: ~78% more pixels rendered than the panel can show, **three times over**.

### Crashes: real, ongoing — and unrelated to memory or the GPU

The operator's question included crashes. Answered from disk:

| Finding | Value |
|---|---|
| Total diagnostic reports | 41 |
| **`bash` crashes** | **37** |
| `node` | 2 |
| Docker / "Retired" | 1 / 1 |
| iTerm2 / WindowServer / `claude` crashes | **0** |
| **jetsam / memorystatus / OOM kills, last 12h** | **0** |

So: **there are no memory-exhaustion crashes.** Nothing was killed for RAM. Consistent with 84% free
and zero swap — and further confirmation that the GPU cannot help here, since GPU offload only
addresses memory or compute saturation, neither of which is occurring.

But there *is* a real, ongoing crash class, and it is ours:

```
procPath:    /bin/bash          ← all 37, macOS system bash 3.2
parentProc:  bash
termination: Segmentation fault: 11  (SIGSEGV)
frames:      libsystem_kernel __kill ← bash re-raising, below it bash's own evaluator
```

- **All 37 are `/bin/bash`** — not Homebrew bash. macOS ships **bash 3.2 (2007)**, held there for
  licensing reasons.
- Rate: **Jul 24 → Jul 29, ~7/day, still occurring** (newest today 21:14).
- Parent is `bash`, faulting inside bash's own execution path — a genuine interpreter segfault, not a
  child process failing.

This aligns with the recorded *bash 3.2 runtime deaths* class (silent no-ops and runtime deaths that
`bash -n`, shellcheck, and zsh all pass). With 239 `.sh` + 204 `.bats` files and every hook running
under `/bin/bash`, plus an observed hook load-test piping an **8 MB** JSON payload into a hook, large
input or deep recursion in bash 3.2 is the leading hypothesis.

**This is the single most concrete defect surfaced by this investigation** — but it is a *shell runtime*
problem. Direction: run hooks under Homebrew `bash` 5 (`/opt/homebrew/bin/bash`) and/or bound hook
payload size. Not scoped here; filed as a follow-on because it needs its own RED-proof (reproduce the
segfault, then show it gone) rather than a speculative interpreter swap.

### Self-inflicted CPU found incidentally

Unrelated to the GPU question but material to the felt lag — at census time the machine was running
its own test infrastructure at high concurrency:

- **96 `bats` processes**, 179 `bash`, 60 `zsh`
- ~10 concurrent `python@3.13` procs at ~20% CPU each (≈2 cores) from a **single** parent (pid 61955)
- `shellcheck` at 20% over the whole `bin/` corpus
- `scripts/gates/marker_completeness.py` and a hook load-test allocating an **8 MB JSON payload**
- Multiple concurrent `bats -f ... tests/ship-land.bats` gate runs

This is the previously-recorded gate-contention class recurring live (see memory
*Gate admit-ceiling starvation*: concurrent ship-land gates starve each other because each one's bats
corpus *is* the load the others wait on). It is a scheduling/serialization problem, and 100% CPU-bound.

---

## The only genuine GPU lever in the repo

One real, non-trivial exception exists, and it is in media encoding — not infrastructure:

`skills/demo-recording/SKILL.md` (lines ~226, ~290) encodes with **`libx264`**, a pure-software
encoder. This machine has hardware encoders available:

```
h264_videotoolbox    VideoToolbox H.264 Encoder
hevc_videotoolbox    VideoToolbox H.265 Encoder
prores_videotoolbox  VideoToolbox ProRes Encoder
```

Switching demo/banner encodes to `h264_videotoolbox` moves that work to the media engine and is a
real multi-x speedup on M1 Max. **Caveat that decides it:** VideoToolbox is quality-per-bit inferior
to `libx264 -crf 18 -preset slow` at matched bitrate, and this repo has a *recorded regression* about
exactly this class of mistake — lossy compression seaming flat terminal regions, undetected by SSIM/PSNR
(memory: *README inline media*). So: **worth using for intermediate/proxy encodes and contact sheets,
NOT for the final README asset** without the mandatory visual contact-sheet review.

This is occasional work, so it does nothing for steady-state lag.

---

## Recommendations — ranked by measured impact

Note the shape of this list: **none of the top items are "use the GPU"**, because the GPU is already
doing everything it can do here.

| # | Action | Expected effect | Risk |
|---|---|---|---|
| 1 | **Close Chrome and Dia** | Largest *measured* lever in the repo's history: load **88–104 → 10–16** after closing them (`RESTART-BRIEF-2026-07-27.md` §1; Dia held 10.6 GB over 41 procs). Currently 26.9% CPU + ~2.1 GB | None |
| 2 | **Reduce visible iTerm2 panes** | iTerm2 renders *visible* sessions; at 94.7% it is the #1 consumer. Pane count is a first-class cost independent of session count | Low; costs at-a-glance monitoring |
| 3 | Set the two 120 Hz displays to **60 Hz** | **New finding — halves frame production** across the 1.46-core render slice. Untried; no prior pass measured display config | Low; reversible in Displays. Costs pointer smoothness |
| 4 | Consider unscaled 3840 × 2160 on the Dells | **New finding** — removes rendering 78% surplus pixels, ×3 displays | Medium — UI becomes physically smaller; a real ergonomic tradeoff, operator's call |
| 5 | Shim `/opt/homebrew/bin/bats` → `bin/cc-bats` | Closes the ~30% absolute-path bypass that ceilings QoS coverage at ~70%; worth ~0.5–0.7 cores. **Already named as an operator call, not taken** | Medium — brew-upgrade-fragile; needs a parity check |
| 6 | `h264_videotoolbox` for intermediate media encodes only | Faster demo/banner renders | Medium — see the seaming caveat; never for final assets unreviewed |
| 7 | **Enabling iTerm2 Metal** | **Zero — already enabled and executing shaders** | — |
| 8 | **GPU-offloading infrastructure compute** | **Not possible; no applicable work exists** | — |

Items 3 and 4 are the only *new* levers this investigation contributes to lag; 1, 2 and 5 were already
known and are simply not being exercised. Items 7 and 8 are the direct answer to the question asked.

**Do not build a load-or-core-based spawn ceiling — because one already exists and is live.**

`capacity_gate()` (`scripts/handoff-fire.sh:1282–1315`, enforced at `:2273`) refuses a net-new session
fire when 1-min loadavg ÷ `hw.ncpu` exceeds `CC_FIRE_MAX_LOAD_PER_CORE`, default **2.0**. It is LIVE with
no activation step — `~/.claude/scripts/handoff-fire.sh` is a per-file symlink into the checkout, so
landing *is* deploying. Landed `0fc3a3d3`.

⚠️ **A correction to my own earlier guidance in this document.** I first wrote "do not pursue a load
ceiling — already tried, recorded as a permanent outage," citing memory *Load ≠ session count*. **That
memory is stale against its own source.** `MACHINE_CAPACITY_V2.md` §9.5 **self-retracts** the
permanent-outage projection: the gate is not inert (symlink), and not an outage — load did fall back
(fleet drained 31→8, 1.55/core ⇒ ADMITS), and the IDL holds **1,498 `reason:"capacity"` rows**, proving
both verdicts fire. Anyone reading only the memory index line gets the falsified verdict.

What *does* survive is the **instrument** critique, and it is the useful part: **loadavg is not
session-attributable.** It is dominated by iTerm2, WindowServer and browsers — none of which a refused
session fire can shed. So the gate throttles the wrong population. The named-but-unbuilt improvement is
a ceiling keyed on a **sheddable, session-attributable** quantity (session count, or session RSS against
a memory budget) rather than system-wide loadavg.

🚨 **Live consequence, right now:** at **6.52 load/core** against a 2.0 ceiling, `capacity_gate` is
**refusing every net-new session fire** — the lag has become a dispatch outage. Worse, the gate being
on-by-default makes **16 postland corpus tests fail BY LOAD, not by code** (`handoff-fire-focus` 8,
`handoff-fire-payload-lint` 6, `fire-engagement` 2 — all pass at 0.5/core, all fail at 2.78/core;
memory *Metric zero by refusing gate*), a plausible contributor to the 0-green-of-33 deploy-stamp
condition. **Any gate run in this window is red-by-load and must not be read as red-by-code.**

**Also do not** re-add a shedder that *waits*. `gate_admit()` was deleted and its absence is
**lint-enforced** (`scripts/postland-verify.sh:1245–1246`): a per-call bound multiplied across a
per-suite loop into 126 × 600 s = **21 h** of "bounded" waiting, and five concurrent gates sat at load
16–18 waiting for a ceiling of 8 **while their own corpora were the load**. The standing invariant is
**priority demotion, never queueing or sleeping** — refuse-and-report is fine, sleeping is not.

---

## Where this sits against existing work

**The lag question has been investigated exhaustively twice and closed.** The SSOT is
`docs/plans/MACHINE_CAPACITY_V2.md` (706 lines, ground-up campaign row 13; frontmatter still reads
`status: open` while the map's row-13 cell reads RATIFIED AND CLOSED — a documentation defect worth
fixing). Anyone touching lag should read it, plus `GROUND_UP_REBUILD_MAP.md` row 13,
`RESTART-BRIEF-2026-07-27.md` §1/§6, and `SESSION_CLOSE_AND_LAG_2026-07-26.md` §2, **before measuring
the box again.**

**This investigation's genuinely new contributions are narrow, and worth stating plainly so they are not
mistaken for a rediscovery:**

1. **The GPU question itself.** No prior pass addressed GPU/Metal at all. It is now answered with
   execution-level proof (shader cache), not inference.
2. **Display configuration as the mechanism behind the render cost.** Prior passes established *that*
   iTerm2 + WindowServer ≈ 1.6 cores of pure drawing, and that pane count is a first-class cost. None
   measured **why it is that expensive**: 52.0M pixels/frame across 4 displays, two demanding 120 fps,
   with 4K panels rendered at 5K and downsampled. That converts a known cost into two new levers
   (refresh rate, scaling) that no prior doc lists.
3. **The `/bin/bash` 3.2 SIGSEGV class** — 37 crashes, ~7/day, ongoing. Prior work examined abrupt
   *session* ends (husk panes, mis-owned teardown markers) and noted an unaudited 81% crash-path exit
   rate, but this specific interpreter-segfault class does not appear in any existing doc.

Everything else here reproduces prior findings, which is itself useful: independent confirmation that
**the sessions are not the load, the renderer is.**

Prior art also **exonerates** the leak framing, consistent with what I measured: per-session RSS does
not grow with age (a 30 h session held 417 MB; a 33 min one 700 MB — RSS tracks context size, not
uptime), fds do not leak (22–24 against a 1,048,576 limit), and `gitstatusd` and Spotlight are innocent
(`mds` 1.1%, `mds_stores` 0.7%; my own measurement: 0.02 cores). The real accumulation engine is named
differently: `owned-wait` is a never-reap **and** never-surface terminal bucket (13 sessions, 5 idle
47–222 h, ~3.5 GB) and pane-less `claude.exe` trees (~3 GB) are invisible to all reapers by
construction.

## Open items

Two subagents are still running; their findings will be integrated:

- `iterm-gpu-axis` — iTerm2 Metal per-session disqualifying conditions, and whether Metal can ever
  *raise* CPU. Does not change the verdict (Metal is empirically active and executing), but may sharpen
  lever #3/#4.
- `memory-fleet-axis` — per-process RSS-vs-age correlation, DiagnosticReports detail, and whether the
  179 `bash` / 60 `zsh` processes are orphans. Prior art already answers the leak half in the negative.

**Not pursued here** (named, not scoped into this investigation):

- The `/bin/bash` 3.2 SIGSEGV class needs its own RED-proof — reproduce the segfault, then show it gone
  under Homebrew `bash` 5 and/or a bounded hook payload. An interpreter swap on 239 `.sh` files is not a
  speculative change.
- Fixing the stale memory entry *Load ≠ session count*, which still asserts a verdict its own source
  retracted.
