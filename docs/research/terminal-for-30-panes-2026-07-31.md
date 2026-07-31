# Which terminal survives 30+ concurrent Claude Code panes on this M1 Max? — 2026-07-31

**Question (operator).** Find the absolute best terminal application — split panes, maximal GPU use —
such that 30+ concurrent Claude Code split-pane sessions do not lag the machine, drop sessions, or
freeze/crash it. Out of the box, or cheaply modifiable without constant re-work.

**Answer, one line.** **kitty** — it holds all 30–40 panes in **one OS window** (measured: the
cheapest possible grouping on this box) at **7–8 total threads whether it is running 2 panes or 36**,
against WezTerm's ~7 threads *per pane* and against iTerm2, whose only all-GPU layout **forces six
windows** and whose window leak is an open, unfixed upstream bug.

**The single most actionable sentence in this document, and it is not about which terminal:** on a
controlled benchmark here, the same 30 panes cost **2.35× more WindowServer CPU spread across 30
windows than gathered into 1**, while the number of surfaces *inside* a window barely matters
(1.17×). **Windows are the expensive unit. Panes are nearly free.** macOS itself has ample headroom —
30 panes repainting at 20 Hz in one window cost ~+10 pp of a single core — so the ceiling is the
application's window architecture, not the platform.

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

| Unit added | Cost | Source |
|---|---|---|
| one visible **pane** | ~3 IOSurfaces, **~0 net bytes** | measured, this box |
| one **window** | **28–34 MB** backing store + **~4.9 mach ports** | measured, this box |

**An order of magnitude apart on the app side**, and 98 zero-tab iTerm2 windows had accumulated, each
surviving `close()`.

### What the compositor actually charges for — a controlled benchmark, and it trims my own claim

A purpose-built Cocoa/IOSurface harness presented **30 panes in a fixed 6×5 grid, identical on-screen
geometry and identical pixels-per-second in every arm**, 20 Hz updates, 5 reps, with two controls that
both held: frame delivery was exactly 120/120 in every arm, and app-side CPU was 1.4–1.9% in every arm
— so the delta is entirely WindowServer. Mean percentage-points of one core added:

| grouping of the same 30 panes | WindowServer |
|---|---|
| **30 windows** × 1 surface | **+22.6 pp** |
| 6 windows × 5 surfaces | +17.5 pp |
| **1 window** × 30 surfaces | **+11.2 pp** |
| 1 window × 1 surface | +9.6 pp |

**Windows cost 2.35×. Surfaces *inside* one window cost only 1.17×.**

This **corrects the emphasis of this document, including my own earlier framing.** The
"one surface per pane vs one per window" axis — the thing that made kitty's architecture look
decisive — is worth about **17%**. The axis worth **2–4×** is simply *do not spray one OS window per
session*. kitty still wins, but the honest reason is narrower: it puts all 30 panes in **one window**
(the cheapest arm) with no per-pane thread cost, whereas iTerm2's only all-GPU layout **requires six
windows** and its leak manufactures more.

**And macOS is not the ceiling.** 30 panes repainting at 20 Hz in one window cost only ~+10 pp of a
single core. The platform has ample headroom for 30–40 panes; **the application's window architecture
is the constraint**, which is why this is a terminal-choice question at all.

> **A correction to the inherited freeze narrative, from the same harness.** Idle windows are nearly
> free: 200 idle on-screen windows were indistinguishable from baseline, 900 cost ~+30 pp, and
> WindowServer grew only ~78 KB per idle window. Window churn does **not** leak the compositor —
> 5,000 create/close cycles moved WindowServer RSS by −8 MB, and ~10,000 windows created across the
> session left **exactly 0** behind. ⇒ **98 leaked zombie windows cannot by themselves explain
> WindowServer at 94%.** Something else was also running, and the best candidate is the
> CoreAnimation defer-lock storm (§6.4) — one `CAContext` per layer-hosting window, 117/s across 33
> contexts, lock counts climbing monotonically and never released. The zombies remain a real defect
> and a real memory cost; they are no longer a sufficient explanation for the CPU.

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

### …but the cap does not need a source build at all — measured 2026-07-31

The paragraph above is about *rebuilding iTerm2*, and it stands. It does **not** establish that the
cap is unreachable, and §8's all-Metal row already said the counterfactual "needs no source build".
It is now scripted: `scripts/iterm-metal-bench-app.sh` clones the shipped app, raises the cap with a
**4-byte patch to the shipped binary**, re-signs, and verifies — 16 s end to end, no Xcode, no
`paranoid-deps`, no toolchain.

The gate is one instruction in `-[PTYTab updateUseMetal]`, at vmaddr `0x100491c34` in the arm64
slice (file offset `0x31adc34`): `cmp x8, #0x6` followed by `b.hs`. Rewriting the immediate is the
whole patch. The site is located by **anchor, not offset** — the symbol is looked up, the function
disassembled, and the `cmp x8,#N`+`b.hs` pair required to occur **exactly once** — because the bare
`cmp x8,#6` encoding occurs 21 times across the fat binary, and an iTerm2 update that reshapes this
code must make the script *refuse* rather than silently patch an unrelated comparison.

**This does not soften the recommendation.** It removes an obstacle to *testing* it. The cost model
in §1 is unchanged; what changes is that the §8 falsification row is now cheap to run, and it should
be run before iTerm2's score is treated as settled. Note also that the patch is per-iTerm2-release
rework, so it is a *bench* instrument, not a migration path.

#### Two traps, both of which produced a confidently wrong artifact first

Recorded because each failed while looking like success, and both cost a crash report to find:

1. **The clone would not launch, and blamed a file that was present.** It died with
   `Library not loaded: @rpath/iTermSwiftPackages.framework` — while that framework sat intact in
   the bundle, and `codesign --verify --deep --strict` returned **rc=0**. iTerm2 ships with the
   hardened runtime; editing `Info.plist` to change the bundle id breaks the seal and forces a
   re-sign; an ad-hoc re-sign has **no Team ID**; and hardened runtime implies **Library
   Validation**, which admits a non-platform library only on a Team ID *identity match* — which
   "absent" never satisfies, not even against another "absent". So AMFI refused to map the app's own
   framework and dyld reported that refusal as a missing library. Proven by a three-arm control, all
   three built from one bundle with only the signing differing:

   | Arm | Signing | `flags` | Result |
   |---|---|---|---|
   | A | adhoc + runtime, no entitlements | `0x10002` | **DIED** rc=134, dyld halt |
   | B | adhoc, runtime dropped | `0x2` | LAUNCHED |
   | C | adhoc + runtime + `disable-library-validation` | `0x10002` | LAUNCHED |

   Arm A is the negative control and it **must** fail; B and C prove nothing without it. The builder
   takes **C, not B**: dropping the hardened runtime also changes JIT policy and `DYLD_*` acceptance,
   and this bundle's only purpose is to be comparable to the shipping iTerm2. C relaxes exactly the
   one check an ad-hoc signature cannot satisfy, and nothing else.

2. **The first clone was never patched at all.** Its `cmp x8,#0x6` count was *identical* to stock
   iTerm2 — a plain second iTerm2 carrying the stock 5-pane cap. Had trap 1 been fixed without
   noticing, the counterfactual would have produced a confident all-Metal measurement of an iTerm2
   that was never all-Metal. This is why the builder re-reads the cap **back out of the patched
   binary by disassembly**, and deletes any bundle it cannot prove patched rather than trusting that
   it once wrote bytes. Same class as [[control-must-replay-the-real-artifact]].

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
4. **The CoreAnimation defer-lock storm is only ~half iTerm2's, and is now the leading suspect for
   the CPU that the zombie windows do not explain.** Restarting iTerm2 took it 117/s → 58/s, so
   another client produces the remainder; **switching terminals does not obviously fix it.** The
   three format strings were located in the dyld shared cache and belong to QuartzCore
   (`"Defer Lock context 0x%x unlocked but lock count is not zero (was %d)"`,
   `"…not found in defer lock watchlist"`, `"Defer Lock missing release ?"`) — an instrumented
   balance check on deferred presentation locks against a `CAContext`, **one per layer-hosting
   window**. There is **no public documentation, no userspace diagnostic, and no workaround short of
   restarting the offending client.** The emitting symbol could not be resolved, so the mechanism is
   inferred from the strings, not from Apple.
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

1. ✅ **DONE 2026-07-31T06:50Z — the 8 render knobs are applied and parity-verified**
   (`match=9 drift=0 unset=0`, undo saved to `~/.claude/autonomy/iterm2-perf-undo.tsv`; activation
   marked `.done`). `config/iterm2-perf.keys` prices them at **~1–2 cores**.

   **Effect so far: NOT YET MEASURABLE, and that is the expected reading, not a failure.** Five
   post-change samples of iTerm2 gave 25.2–30.1% CPU (median 29.3) against a pre-change 19.6–31.5%
   (median 29.4) — indistinguishable. Both the activation script and the SSOT say why:
   `activeUpdateCadence` is **new-sessions-only**, and the keys file warns verbatim *"Do not read an
   unchanged live number as a failed setting."* The knobs govern panes created **after** the write.
   ⇒ The real test is after the panes recycle, or after an iTerm2 restart — which is **safe on this
   box and already proven**: the shells are children of `iTermServer`, not of iTerm2, and all 40
   sessions survived the 2026-07-30 restart with the same PIDs.
   ⇒ Re-measure with `scripts/terminal-bench.sh --app iTerm2 --interval 1800` **after** a recycle
   before crediting these knobs with anything.

   Two of the eight are independently corroborated from upstream source:
   - `disableAdaptiveFrameRateInInteractiveApps` — the default of **YES** *exempts* alternate-screen
     TUI panes (i.e. all ~30 agent panes) from the frame-rate throttle. Largest single lever.
   - `DimInactiveSplitPanes` — currently **on** (with `SplitPaneDimmingAmount 0.4`). Dimming makes
     `-[iTermTextDrawingHelper textAppearanceDependsOnBackgroundColor]` return YES, which routes each
     dimmed pane through the **slower** `drawForegroundForBackgroundRunArrays` path. With one pane
     focused out of 30–40, that is 29–39 panes on the slow CPU text path, every frame.
2. **Stop the automation minting windows.** This is the highest-value change that requires no
   migration at all: windows are the 2.35× unit. The producer was caught on the `--split-right`
   path, one surface over from the closed `--window` regression.

   ⚠ **This supersedes the layout advice in `iterm2-freeze-30-sessions-2026-07-30.md` §7b, which
   recommended `6 windows × 1 tab × 5 panes`.** That layout is correct *for the Metal gate* and
   measured **+17.5 pp**, versus **+11.2 pp** for the same 30 panes in one window. So on iTerm2 the
   two goals genuinely conflict and neither is free:
   - `6 × 5` → every pane on the GPU, but 6 windows and 30 CAMetalLayers + 30 CVDisplayLink threads.
   - `1 × 30` → cheapest on WindowServer, but every pane on the CPU rasterizer (>5 per tab), which
     is the 1.39-core main-thread glyph-drawing bottleneck already measured on this box.

   **Unresolved for iTerm2, and it is the §8 experiment.** It is resolved *structurally* by kitty,
   which has no cap and therefore takes the cheap grouping and the GPU at the same time.
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

## Provenance, and one phase that did not complete

Evidence came from a 13-agent workflow (3 recon · 7 candidate deep-dives · a compositor cost model ·
an adversarial phase) plus direct measurement by the lead. **The adversarial phase did not return** —
its three refutation agents started and the run stalled with no further journal writes. That is
stated rather than papered over, because "the top 3 were adversarially verified" would otherwise be
implied and it is not true.

**What substitutes for it is stronger than a desk refutation on the one claim that mattered:** the
lead *ran* the candidates. WezTerm entered as the front-runner on the best source review of any
candidate and **the measurement reversed it** (~7 threads/pane, §2). kitty's central claim was
likewise checked twice, on two instruments, by two parties — a fleet agent's CGWindow census and the
lead's independent `terminal-bench.sh` — agreeing that thread count is flat in pane count.

**What remains unrefuted by anyone**, and is therefore where a reader should push first: kitty's
multi-hour behaviour, kitty under real Claude Code, and the all-Metal iTerm2 counterfactual (§6, §8).

## Instruments added by this investigation

- `tools/terminal-bench/window-census.swift` — root-free `CGWindowList` census, app-agnostic, sends
  no Apple events (the prior AppleScript census was iTerm2-only and perturbed its own subject).
- `scripts/terminal-bench.sh` — the one ruler; `verdict=OK|PARTIAL|NO-DATA` so a non-running app can
  never be filed as "measured: costs nothing".
- `scripts/tui-load.sh` + `tools/terminal-bench/tui-emit.pl` — identical reproducible Ink-shaped load.
- `scripts/terminal-bakeoff.sh` — drives a candidate to N panes; iTerm2 is measure-only so the
  operator's live sessions are never disturbed.
- `tests/terminal-bench.bats` — 9 tests, all asserting the *failure* paths.
- `scripts/iterm-metal-bench-app.sh` — builds the all-Metal counterfactual bundle §8 needs: clones
  the shipped iTerm2 under its own bundle id (own defaults domain, runs alongside the operator's
  live one), raises the hardcoded Metal cap by a 4-byte anchored binary patch, and re-signs it so it
  can actually launch. Verifies the cap by reading it back out by disassembly, and **deletes any
  bundle whose launch probe does not survive dyld** — so a bundle it returns has run at least once.
- `tests/iterm-metal-bench-app.bats` — 8 tests. The two that matter are negative controls for the
  two ways this artifact silently lied: a bundle that `codesign --verify` passes but cannot launch,
  and a bundle that launches but carries the stock cap.

Related: `iterm2-freeze-30-sessions-2026-07-30.md` · `gpu-vs-cpu-lag-2026-07-29.md` ·
[[capability-initialized-is-not-capability-used]] · [[positive-control-the-denominator]] ·
[[load-is-not-a-function-of-session-count]] · [[decision-moved-out-of-the-guarded-unit]]
