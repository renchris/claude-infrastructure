# Which terminal survives 30+ concurrent Claude Code panes on this M1 Max? — 2026-07-31

**Question (operator).** Find the absolute best terminal application — split panes, maximal GPU use —
such that 30+ concurrent Claude Code split-pane sessions do not lag the machine, drop sessions, or
freeze/crash it. Out of the box, or cheaply modifiable without constant re-work.

**Answer, one line.** **kitty** — measured on this box at **7–8 total threads and 1 on-screen
surface whether it is running 2 panes or 36**, against WezTerm's ~7 threads *per pane* and iTerm2's
one CAMetalLayer + one CVDisplayLink thread per GPU-rendered pane.

**And one premise has to be corrected, because it changes what to optimise.** "Maximally utilise the
GPU" is the **wrong goal on iTerm2** — the GPU path is what *creates* the compositor objects that
saturated WindowServer. iTerm2's CPU renderer allocates **no per-pane surface at all**; its Metal
renderer allocates **one CAMetalLayer (≈3 IOSurfaces) + one CVDisplayLink thread + one NSTimer per
pane**, and `acquireScarceResources` blocks the **main thread** up to 16.7 ms per pane per frame.
Raising the hardcoded 5-pane Metal cap would add ~30 layers and up to ~90 IOSurfaces to exactly the
axis that froze the machine. **The cap is protecting you.** The win is not more GPU — it is a
renderer that needs only one surface for all 30 panes, which is what kitty is.

Machine: MacBookPro18,2 · M1 Max (8P+2E, 32-core GPU) · 64 GiB · Darwin 24.6.0 · iTerm2 3.6.11.

---

## 1. The two cost axes, and why they conflict on iTerm2

The 2026-07-30 freeze (`docs/research/iterm2-freeze-30-sessions-2026-07-30.md`) was **WindowServer
saturating a full core** (92.7–99.9%, mach-port table growing monotonically) while **iTerm2 itself
measured 0.0% CPU**. Memory was exonerated: 15 G free, swap never engaged, per-session footprint flat
at ~220 MB.

Measured this session, the two axes price very differently:

| Unit added | Cost to the window server | Source |
|---|---|---|
| one visible **pane** | ~3 IOSurfaces, **~0 net bytes** | measured, this box |
| one **window** | **28–34 MB** backing store + **~4.9 mach ports** | measured, this box |

**An order of magnitude apart, and the freeze was a *window*-count failure.** 98 zero-tab iTerm2
windows had accumulated, each surviving `close()`.

### The GPU path is the expensive one, and the cap's own justification is four years stale

Read from upstream source at master HEAD (`57857cd90fa`, 2026-07-30). Per **Metal-rendered** pane:

| allocation | source |
|---|---|
| 1 × `CAMetalLayer` (`maximumDrawableCount` never set ⇒ default **3 drawables**) | `iTermMetalView.swift:508-510`, `:749-751` |
| 1 × `CVDisplayLink` — **a dedicated high-priority thread each** | `iTermMetalView.swift:544-563` |
| 1 × `NSTimer` forcing redraw even when idle (`metalRedrawPeriod`, 0.5 s) | `iTermMTKView.swift:38-45` |

Per **CPU-rendered** pane: **none of the above.** `PTYTextView` draws via `-drawRect:` into the
window's shared backing store and never calls `wantsLayer`.

The cap's comment says *"each gets its own thread"* — that was true in 2018
(`5bbe97dbc`: a `dispatch_queue_create` per driver) and **false since 2022**: commit `28b98381f`
moved every Metal driver onto **one shared static serial queue**. So the stated reason is stale, but
the cap is accidentally right for a different reason: at 30 Metal panes you get 30 display-link
threads waking at 60–120 Hz (**1,800–3,600 wakeups/s**) funnelling into that one serial queue, while
`acquireScarceResources` runs **on the main thread** (`iTermMetalDriver.m:576-582`, `:944-1000`) and
waits up to 1/60 s for a drawable — up to **500 ms of main-thread block per frame** at 30 panes,
which is a positive feedback loop with the WindowServer saturation that was actually measured.

*(Mechanism INFERRED from source by a fleet agent; the 6-window/5-pane all-Metal configuration has
never been run, here or upstream. Recorded as a falsifiable claim in §8, not as a measurement.)*

Now the gate itself (`sources/TerminalView/PTYTab.m`, `-updateUseMetal`):

```objc
const NSInteger maxNumberOfSplitPanesForMetal = 6;   // hardcoded; no pref, no defaults key
const BOOL numberOfSplitPanesIsReasonable = self.sessions.count < maxNumberOfSplitPanesForMetal;
...
const BOOL foregroundTab = [self isForegroundTab];   // background tabs NEVER get Metal
```

Only the **foreground** tab of a window may use Metal, at **≤5 panes**. So the only layout that puts
every pane on the GPU is `N windows × exactly ONE tab × ≤5 panes` — for 30 sessions, **6 windows**.

**That is the trap, and it closes from both sides.** Chasing the GPU either (a) multiplies *windows*,
the unit that costs 28–34 MB and ~4.9 mach ports each and whose leak actually froze the box, or
(b) if you patched the cap out, multiplies *per-pane CAMetalLayers and display-link threads* on that
same compositor axis. There is no iTerm2 configuration that escapes both, because the `6` is a
compile-time `const NSInteger` — no preference, no defaults key — and the foreground-tab gate is
unconditional.

### The leak is a known upstream bug, open 19 months — and someone has reported our exact failure

This is not a local misconfiguration, and it is not fixable by tuning:

| issue | state | relevance |
|---|---|---|
| **#12097** "Strange blank window" | **OPEN since 2025-01-01** | hidden, zero-tab `Untitled — 0x0` windows accumulating over hours — the operator's object exactly |
| **#12645** keyboard lag in *other* apps | **OPEN since 2025-12-10** | **our signature, independently reported** |
| **#12905** "Ghost Window" (3.6.11) | **OPEN since 2026-06-23** | another NSWindow that will not die, after display reconfiguration |

The partial fix for #12097 (`4a0eed48f`, 2025-02-05) addressed one manifestation, and its own commit
message says: *"The underlying problem is a very hard to diagnose leak of the NSWindow, which I'll
keep looking for."* **Still unfixed in 3.6.11 (current stable), in the 3.7.0beta line, and on master
HEAD (2026-07-30).** That is consistent with the measurement here that `close()` reports success and
the window survives — which is what a retained `NSWindow` does.

#12645 deserves quoting, because it is this operator's failure described by a stranger: *"if I have a
few iTerm windows open, and especially if I have one or more using OpenAI's codex tool"* — an agentic
TUI of exactly this class — *"over a few hours"* other applications develop 5+ second input lag;
*"iTerm is not using any significant amounts of CPU or memory… WindowServer's CPU usage goes up";*
*"Closing all open iTerm windows or just quitting iTerm will immediately fix the problem."* Reported
on an M3 Pro and an M3 Studio. No maintainer diagnosis. **Independent corroboration that this is
iTerm2 + long-running agent TUIs, not this machine.**

### "Easily modifiable in source" — measured as NO for iTerm2

The operator's question explicitly allows a source patch. For iTerm2 the *patch* is trivial (one
`const NSInteger`); the **build** is not. Measured on this box, three consecutive failures:

- `xcodebuild` → rc=65 at 32 s, refused by a hard version gate: repo wants **Xcode 26.5 (17F42)**,
  this box has 26.3 (17C529).
- `make paranoid-deps` → rc=2 at 189 s (Rust toolchain too old for `clap_lex`), then rc=2 at 31 s
  (**not idempotent** after a partial failure — aborts on its own leftover artifacts), then rc=2 at
  217 s (`sfsymbolenum` needs `/Applications/SF Symbols.app`, absent).
- `make doctor` → `pyobjc NOT FOUND · cbindgen NOT FOUND · sf-symbols NOT FOUND`.

And `paranoid-deps` must be re-run on every Xcode bump, against ~7 stable releases + 8 betas + nightlies.
**That is the "constant re-work" the operator wanted to avoid, and it is the maximum case of it.**
(kitty and WezTerm need no patch at all; their scaling behaviour is the shipped default.)

---

## 2. Measured on this box, one ruler for every candidate

All figures from `scripts/terminal-bench.sh` (this repo, added by this investigation): per-pid
CPU/RSS/threads/mach-ports from the **second sample** of `top -l 2` (never `ps %cpu`, a lifetime
average that misread this box 2.3×), window counts from a root-free `CGWindowListCopyWindowInfo`
census, and the GPU path established **by profile, not by flag**.

| | iTerm2 (live, operator's own) | kitty | WezTerm |
|---|---|---|---|
| panes | ~10–23 | 24 / 26 | 6 / 38 |
| **threads** | **11–12** | **8 / 7** | **33 / 257** |
| **threads / pane** | ~1.1 (near-constant) | **0.33 → 0.27 — FLAT** | **5.50 → 6.76 — SCALES** |
| mach ports | 729–756 | 385 / 377 | 418 / 757 |
| RSS | 705–790 MB | 187 / 186 MB | 70 / 133 MB |
| CGWindows (onscreen) | 21–24 (4–5) | 21 (**1**) | 20 (**1**) |
| CPU (idle) | 19.6–29.8% | 0.0% | 0.0–0.6% |
| GPU:CPU frame ratio | 2.69–11.64 : 1 | 13–17 : 1 | 16 : 1 |

### The decisive number, and it reversed a desk-research ranking

WezTerm's source review was the strongest of any candidate — one `NSView` + one `CAMetalLayer` per
*window*, all panes composited by a single `paint_impl`, and `wezterm cli` covering all five required
automation capabilities. On surfaces it is correct: **1 on-screen CGWindow for 38 panes.** It was
provisionally the front-runner.

Then it was run. **Two pane counts give the slope:**

```
 6 panes →  33 threads
38 panes → 257 threads
slope = (257-33)/(38-6) = 7.0 threads per additional pane, intercept ≈ 0
```

**~7 OS threads per pane, linear** — about **210 threads at 30 panes** on a 10-core machine. kitty
over the same range is flat at 7–8 threads *total*. Two independent readings of each confirmed both.

This is the one place where measurement overturned the reading: a candidate can present a perfect
*surface* story and still scale badly on *threads*, and only running it distinguishes them. Stated
fairly: **257 parked threads is not 257 busy threads** — WezTerm measured 0.0% CPU idle, so the cost
is stack memory and scheduler bookkeeping, not burn. It is a structural risk under load, not a
demonstrated slowdown, and it was not load-tested here.

An independent fleet agent measured kitty further on this same machine, and the flatness is the
finding: **36 panes in one OS window → 1 onscreen CGWindow, 10 threads — identical to the 2-pane
count** — 12.9–13.9% CPU with every pane repainting a full frame at 10 Hz, main thread 89% idle. Six
OS windows / 41 panes → 6 onscreen CGWindows, still 9–10 threads.

> **Not apples-to-apples, stated plainly:** iTerm2's RSS/CPU here carry the operator's *real*
> sessions with real scrollback and live Claude Code output; kitty's panes were idle shells. The
> **threads** and **window** columns are structural and do compare; RSS and CPU do not. The one
> loaded comparison that exists is the fleet agent's 36-pane 10 Hz run above.

### Leak behaviour — the axis that actually froze the box

kitty was churned 101 panes over ~12 minutes (3 cycles × 20 create/destroy). RSS and mach ports
returned **exactly** to their resting values (283 → 270 MB; ports 421 → 445 → settled back to 421
within ~18 s), with a 60-call remote-control control run adding **zero** ports. That is the direct
counterpart to iTerm2's 98 windows that survive `close()`, and it came back clean.

---

## 3. Calibration that prevents a false positive

**Offscreen windows are the normal resting state of a macOS app, not a leak signal.** Measured
simultaneously across the desktop: Finder 20 offscreen, Terminal 18, Cursor 22, Console 17, kitty 20,
iTerm2 17. Reading iTerm2's offscreen count as "17 zombies" would have manufactured a defect out of
the baseline. The window-server census cannot see the property that actually defined the 98 zombies
(an iTerm2 window holding zero *tabs* — tabs are an application concept invisible to the compositor),
and those windows had ordinary non-zero bounds, so a zero-area filter does not catch them either.

⇒ **The leak instrument is DRIFT at constant layout, never level.** Two readings, known interval,
visible layout unchanged; attribute only the growth.

**Correction to an earlier read in this session.** I reported iTerm2's port growth as the zombie leak
re-accumulating ~7.5 h after the restart. That was wrong on both halves: `ps -o lstart` puts this
iTerm2 at **22:04:55, ~30 minutes before the reading**, and a direct enumeration showed
**`zeroTabWindows=0`**. Port growth is real and unexplained, but it is not the zombie mechanism.

---

## 4. Migration cost — the 209 hits are 13 capabilities

A dedicated agent read the coupling rather than counting it. The **209 `ITERM_SESSION_ID` hits across
73 files** and **91 split-surface hits** collapse to **13 distinct capabilities over 3 primitives**:

1. address a pane by an opaque id,
2. create a pane adjacent to a named one and learn its id,
3. turn a pane id into a tty.

Load-bearing production files: **36** (of 41 that grep positive; 5 are prose/self-test), plus 48 test
files. Two files carry ~80% of the work: `scripts/handoff-fire.sh` (4,024 lines) and `bin/it2-wrapper`.
A meaningful share of the remaining coupling exists only to work around iTerm2-specific defects (a
confirmation modal, a sticky-command profile bug, an unbounded AppleEvent) and **disappears** on
migration rather than being ported.

### kitty covers all three primitives — verified live, not from docs

```
kitten @ launch --type=window --match window_id:$ANCHOR --next-to id:$ANCHOR \
        --location=vsplit -- CMD      # prints the new pane id on stdout
```

`ITERM_SESSION_ID` → **`$KITTY_WINDOW_ID`**, injected per child before spawn (`kitty/tabs.py:713`).

> **A trap found in kitty's source that the migration must respect:** `launch.py:663` does
> `if (target_tab && next_to && next_to not in target_tab) next_to = NULL`, and with `--match`
> omitted the target tab defaults to the *active* tab. **You must pass `--match window_id:<ID>`
> alongside `--next-to id:<ID>`** or the anchor is silently dropped — the pane is created somewhere
> else and nothing errors. This is the same shape as the ⌘D-split invariant already recorded in
> `decision-moved-out-of-the-guarded-unit`, and it needs a guard, not a comment.

**What has no equivalent:** the 7 AppleScript files. kitty ships no `.sdef` and sets
`NSAppleScriptEnabled=false`. Those must be re-expressed as `kitten @` calls.

---

## 5. Two findings that change the economics

### 5a. Claude Code already ships a tmux pane backend — verified in the live binary

Independently confirmed by string-reading `2.1.183/.../claude.exe` (counts are symbol occurrences):

```
48 InProcessBackend   44 BackendRegistry   43 ITermBackend   40 PaneBackendExecutor
39 TmuxBackend         4 registerITermBackend   2 registerTmuxBackend   3 getBackendByType
```

This is **not** dead code — the selection tree, its outcomes and its error paths are all present:

```
[BackendRegistry] Environment: insideTmux=
[BackendRegistry] Selected: tmux (running inside tmux session)
[BackendRegistry] Selected: tmux (external session mode)
[BackendRegistry] Selected: tmux (fallback in iTerm2, it2 setup recommended)
[BackendRegistry] Selected: iterm2 (native iTerm2 with it2 CLI)
[BackendRegistry] User prefers tmux over iTerm2, skipping iTerm2 detection
[BackendRegistry] ERROR: iTerm2 detected but no it2 CLI and no tmux
```

and it is user-selectable via a persisted config flag **`preferTmuxOverIterm2`** (read by `wt()`, set
by `it2Setup`). **Currently unset on this box** (`TERM_PROGRAM=iTerm.app`, `it2` present ⇒ the iTerm2
backend is live).

Scope, stated precisely so this is not over-read: `PaneBackendExecutor` governs **spawning
agent-team teammates into panes** (`Spawned teammate`, `killing pane for`, `sendMessage() to`). It is
not the renderer for Claude Code's own TUI. Claude Code also detects `KITTY_WINDOW_ID` (8 refs) and
`GHOSTTY_RESOURCES_DIR` (1), but ships **no dedicated backend** for either — so on kitty, teammate
spawning falls to the in-process or tmux path, not a native kitty one.

### 5b. The tmux lead was already evaluated here — and its result kills the naive version

Prior work on branch **`feat/tmux-isid-resolver`** (2 commits, worktree `~/Development/wt-tmux-isid`
intact) is **100% stranded: zero tmux files on `origin/main`**, and `git merge-tree` still reports
**0 conflicts**. Verified by content this session.

Its measured verdict matters because it refutes the obvious "just put tmux inside one GPU terminal"
answer *for the iTerm2 case*:

- **Plain tmux is unusable here** — every tmux pane shares ONE iTerm2 UUID, so per-pane addressing is
  not broken but *architecturally absent*; no resolver can recover an id that was never allocated.
- **tmux `-CC` (control mode) does NOT bound iTerm2's memory** — iTerm2 allocates a full native
  session per tmux pane and holds its scrollback. Measured: 60k lines into one `-CC` pane moved
  iTerm2 RSS **2960 → 3263 MB (+303 MB)** and it did not come back. (Confound stated in the original:
  ~3 probe windows were open, so the direction is unambiguous, the magnitude is not.)
- What control mode *does* deliver is the **zero-loss property**: the claude process survived its
  iTerm2 pane being closed — same PID, same lstart, TUI intact.

**This is why kitty wins over "iTerm2 + tmux".** kitty needs no multiplexer to get one surface for N
panes, so it gets the compositor win *and* keeps genuine per-pane addressing — the combination
neither plain tmux nor `-CC` can offer under iTerm2. It also makes the whole
`tmux-panes-inherit-server-iterm-session-id` hazard class disappear rather than be re-solved.

---

## 6. What is NOT established

1. **No multi-hour run of any challenger.** Total kitty uptime across this investigation is well
   under an hour; the operator leaves the fleet up for hours. The churn control is encouraging but is
   a different measurement than sustained runtime. **This is the single largest gap.**
2. **No real Claude Code in a kitty pane.** Every challenger measurement used a synthetic
   alternate-screen repainter. kitty is a strict VT implementation and should render Ink correctly —
   but "should" is the word the evidence rules ban.
3. **No 4-display test.** Challenger windows were cascaded, not tiled one per monitor at 5120×2880,
   so per-display `CVDisplayLink` behaviour at mixed refresh is unmeasured.
4. **The CoreAnimation defer-lock storm is only ~half iTerm2's.** Restarting iTerm2 took it 117/s →
   58/s, so another client produces the remainder. **Switching terminals does not obviously fix
   this**, and its producer is still unidentified.
5. **kitty's load-bearing claim rests on CGWindow counts**, not IOSurfaces, CALayers, or
   per-window WindowServer mach ports — and the freeze was characterised by *ports* and *CA
   contexts*. One `NSOpenGLContext` could in principle be backed by several IOSurfaces.
6. **No candidate was load-tested by me.** Every challenger figure above is from **idle** panes
   (Stage A), which is what isolates the structural axes — threads, surfaces, ports — but says
   nothing about CPU under load. The only loaded challenger measurement in this document is the
   fleet agent's kitty run (36 panes at 10 Hz → 12.9–13.9% CPU, main thread 89% idle).
7. **Ghostty was not measured.** It scored lowest of the survivors (52) on the strength of its
   scripting story rather than its renderer: per pane it allocates one `NSView` + one plain
   `IOSurfaceLayer` (not a `CAMetalLayer`) and, in the shipped 1.3.1, **three OS threads**. It has no
   working CLI IPC on macOS (`performIpc` returns false) but does ship a full AppleScript dictionary.
   Given WezTerm's measured 7 threads/pane, Ghostty's 3/pane deserves a measurement before it is
   dismissed — it may sit between kitty and WezTerm.
8. **The all-Metal iTerm2 configuration has never been run**, here or upstream. The claim that
   raising the cap makes things worse is INFERRED from source (§1) and is the sharpest falsifiable
   claim in this document.

---

## 7. Remediation, ordered by leverage per unit of effort

**Free, today, no migration — and these are worth doing regardless of the terminal decision.**

1. **Apply the 8 measured render knobs that are already declared and never activated.**
   `config/iterm2-perf.keys` is a checked-in SSOT priced at **~1–2 cores**; `scripts/iterm2-perf-parity.sh`
   currently reports `match=1 drift=1 unset=7` — i.e. **the app defaults are still live.** Two of the
   eight are now independently corroborated from upstream source:
   - `disableAdaptiveFrameRateInInteractiveApps` — the default of **YES** *exempts* alternate-screen
     TUI panes (i.e. all ~30 agent panes) from the frame-rate throttle. Largest single lever.
   - `DimInactiveSplitPanes` — currently **on** (with `SplitPaneDimmingAmount 0.4`). Dimming makes
     `-[iTermTextDrawingHelper textAppearanceDependsOnBackgroundColor]` return YES, which routes each
     dimmed pane through the **slower** `drawForegroundForBackgroundRunArrays` path. With one pane
     focused out of 30–40, that is 29–39 panes on the slow CPU text path, every frame.
2. **Stop the window leak, which is the actual freeze cause** — the producer was caught on the
   `--split-right` path, one surface over from the closed `--window` regression.
3. **Add a window-count rung to `capacity-alarm.sh`.** Nothing watches window-object count today; it
   is invisible to every existing headroom/swap/pressure rung. Warn at 25, page at 60 — measured as
   **drift**, per §3.

**Cheap, reversible, high information.**

4. **Run the challengers for hours, not minutes**, with real Claude Code sessions in the panes. The
   instrument for this is `scripts/terminal-bench.sh --interval`; the gap in §6.1 is the one that
   should decide the migration.

**Expensive — do not start before §6.1 closes.**

5. Migrate the 13 capabilities to `kitten @`, starting with `bin/it2-wrapper` (175 lines, the
   chokepoint) rather than `handoff-fire.sh` (4,024 lines).

---

## 8. Falsification plan

The recommendation is **wrong** if any of these come back negative, and each is cheap:

| Test | Kills the recommendation if |
|---|---|
| kitty, 30 panes, real Claude Code, **6+ hours**, `terminal-bench.sh --interval 1800` | windows/ports/RSS drift is non-zero at constant layout |
| Claude Code TUI in a kitty pane, visual check | Ink renders incorrectly (glyphs, resize, alt-screen) |
| kitty across 4 displays at mixed refresh | WindowServer CPU scales with display count worse than iTerm2's |
| `kitten @ launch --next-to` **without** `--match` | (already known to silently mis-place — needs a guard, not a test) |
| **all-Metal iTerm2** — 5 windows × 5 panes (Metal, under the cap) vs 5 × 8 (CPU), matched pane count and pixels, `top -l 2` second sample | WindowServer CPU goes **down** in the Metal case ⇒ §1 is wrong, the cap is a real ceiling worth patching, and iTerm2's score rises sharply. **Needs no source build.** |
| Ghostty at 24+ panes, same Stage-A protocol | Ghostty's 3 threads/pane lands near kitty rather than WezTerm |
| kitty and WezTerm under **load** (Stage B), not idle | WezTerm's 210 parked threads at 30 panes cost nothing measurable ⇒ the thread finding is a curiosity, not a risk |

---

## Instruments added by this investigation

- `tools/terminal-bench/window-census.swift` — root-free `CGWindowList` census, app-agnostic, sends
  no Apple events (the prior AppleScript census was iTerm2-only and perturbed its own subject).
- `scripts/terminal-bench.sh` — the one ruler; `verdict=OK|PARTIAL|NO-DATA` so a non-running app can
  never be filed as "measured: costs nothing".
- `scripts/tui-load.sh` + `tools/terminal-bench/tui-emit.pl` — identical reproducible Ink-shaped load.
- `scripts/terminal-bakeoff.sh` — drives a candidate to N panes; iTerm2 is measure-only so the
  operator's live sessions are never disturbed.
- `tests/terminal-bench.bats` — 9 tests, all asserting the *failure* paths.

Related: `iterm2-freeze-30-sessions-2026-07-30.md` · `gpu-vs-cpu-lag-2026-07-29.md` ·
[[capability-initialized-is-not-capability-used]] · [[positive-control-the-denominator]] ·
[[load-is-not-a-function-of-session-count]] · [[decision-moved-out-of-the-guarded-unit]]
