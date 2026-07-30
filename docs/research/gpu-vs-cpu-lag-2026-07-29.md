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
   from the *same* 64 GB unified pool (measured: 6.59 GB GPU-allocated). GPU offload relocates
   nothing. And memory is not actually the problem: **84% free, 0.00 MB swap in use.**

**The lag is CPU oversubscription, and the largest single contributor is the render path — but its
cost is driven by display configuration, not by which processor does the drawing.**

---

## Evidence

### Machine

| Fact | Value |
|---|---|
| Chip | Apple M1 Max — 10 CPU cores (8P + 2E), 32 GPU cores |
| Memory | 64 GB unified, Metal 3 |
| Uptime | 2 days, 3:41 |
| loadavg | 27.73 / 32.55 / 37.95 → climbed to 48.25 during this session |
| CPU actually busy | 761% of 1000% = **7.6 of 10 cores** |
| Processes / threads | 1,417 / 81,920 |
| Memory free | **84%** |
| Swap used | **0.00 MB** |
| GPU utilization | Device 36%, Renderer 33–34%, Tiler 36%, `recoveryCount` 0 |

Two independent readings follow immediately:

- **Memory is not under pressure.** 84% free and *zero* swap. The 6.3M cumulative compressed pages are
  a 2-day historical total, not present-tense pressure. There is no leak signature at the system level
  to chase. (Per-process leak check delegated to a subagent; see Open Items.)
- **The GPU is not saturated (36%) — it has headroom.** So GPU non-use is not a capacity problem.
  The work simply is not GPU-shaped. Those are different failures and only the second one is true here.

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

Live classification of all 761% busy CPU:

| Cores | Class | GPU-amenable? |
|---|---|---|
| 2.12 | Claude agent sessions (network-bound LLM waits) | No |
| **1.89** | **RENDER — iTerm2 + WindowServer** | **Already on GPU** |
| 1.75 | Python glue / gate scripts | No |
| 0.97 | other | — |
| 0.78 | Shell + `bats` + `shellcheck`, fork-heavy | No |
| 0.41 | Browsers (Chrome/Dia) | Already GPU-accelerated |
| 0.02 | Spotlight indexing | No |

**Only the 1.89-core render slice is GPU-relevant at all — and it is already GPU-accelerated.**

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
| 1 | Set the two 120 Hz displays to **60 Hz** | Halves frame production across the 1.89-core render slice — the largest available win | Low; reversible in Displays. Costs pointer smoothness |
| 2 | Serialize the gate/test suites (one `bats` corpus at a time) | Reclaims ~2–3 cores at peak; fixes a *recorded recurring* class | Low; already the known remedy |
| 3 | Reduce **visible** iTerm2 panes | iTerm2 renders visible sessions; each repainting TUI multiplies items 1 and 4 | Low; costs at-a-glance monitoring |
| 4 | Consider unscaled 3840 × 2160 on the Dells | Removes rendering 78% surplus pixels ×3 | Medium — UI becomes physically smaller; a genuine ergonomic tradeoff, operator's call |
| 5 | `h264_videotoolbox` for intermediate media encodes only | Faster demo/banner renders | Medium — see the seaming caveat; never for final assets unreviewed |
| 6 | **Enabling iTerm2 Metal** | **Zero — already enabled** | — |
| 7 | **GPU-offloading infrastructure compute** | **Not possible; no applicable work exists** | — |

**Do not** pursue a load-or-core-based spawn ceiling as the fix. That was already tried and recorded as
a permanent outage (memory: *Load ≠ session count*, *Gate admit-ceiling starvation*): loadavg swings 2×
at constant session count, and sessions cost ~0.036 cores each while one iTerm2 process exceeds the
entire fleet — so a load-keyed gate blocks work that is not causing the load.

---

## Open items

Three subagents were dispatched; their findings are to be integrated here:

- `iterm-gpu-axis` — iTerm2 Metal defaults, disqualifying conditions, and whether Metal ever *raises* CPU
- `memory-fleet-axis` — per-process RSS-vs-age leak correlation across the 34-process Claude fleet
  (~21.7 GB), real crash/jetsam evidence from DiagnosticReports, Spotlight indexing scope, and whether
  the 179 `bash` / 60 `zsh` processes are orphans
- `prior-art-axis` — existing capacity/admission mechanisms in-repo and their LIVE/STAGED/INERT status,
  to avoid rebuilding what exists

The crash half of the operator's question ("crashes") is **not yet answered from disk** — pending
`memory-fleet-axis`. Nothing above depends on it: no GPU recommendation would change, since crashes on
a machine with 84% free RAM and zero swap are not memory-exhaustion crashes.
