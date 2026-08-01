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

**And one premise has to be corrected, because it changes what to optimise.** The intuitive model —
more panes → more CPU work → the CPU saturates → shift the work onto the machine's idle 32-core GPU —
is **backwards**. The freeze was never a CPU/GPU balance problem inside one app; it was compositor
*objects* (windows, layers, Mach ports) piling up, and GPU rendering **adds** objects instead of
removing them. "Maximally utilise the GPU" is the **wrong goal on iTerm2** for exactly this reason —
the GPU path is what *creates* the compositor objects that saturated WindowServer. iTerm2's CPU
renderer allocates **no per-pane surface at all**; its Metal renderer allocates **one CAMetalLayer
(≈3 IOSurfaces) + several dispatch queues per pane** (confirmed by direct measurement), and is capped
at 5 panes per tab, foreground tab only — so lighting up 30 sessions on Metal forces **six windows**,
multiplying the exact axis that froze the machine. Ghostty is the clean refutation of the GPU-transfer
instinct, because it has **no CPU renderer to fall back to** — every pane is Metal, unconditionally —
and under matched load it is the *most* CPU-expensive candidate measured (27.3% app CPU vs kitty's
9.5%), with its thread count scaling **linearly, 4.00/pane, uncapped**: submitting frames to a GPU is
itself CPU work, paid per pane, with nothing shared across panes. Raising iTerm2's hardcoded 5-pane
Metal cap would add ~30 `CAMetalLayer`s and their dispatch queues to exactly the axis that froze the
machine. **The cap is protecting you.** The win is not more GPU — it is a renderer that needs only
one surface for all 30 panes, which is what kitty is.

Machine: MacBookPro18,2 · M1 Max (8P+2E, 32-core GPU) · 64 GiB · Darwin 24.6.0 · iTerm2 3.6.11.

> ## ⚠ UPDATE 2026-07-31 (afternoon measurement session) — read §9 before acting on anything above
>
> A live-measurement session (3 recon · 3 serial arms · 3 adversarial refuters) **ran the two biggest
> falsification tests in §8** and re-measured the challengers under matched load. Net effect on the
> answer above:
>
> - **kitty survives as the pick among the challengers, and for the first time it is measured under
>   load** — 18 panes, byte-identical 10 fps, all panes at 10.00 achieved fps: **kitty 9.5% app CPU vs
>   WezTerm 24.4% and Ghostty 27.3%** (2.6–2.9×, while kitty carried 22% *more* bytes). That is a
>   stronger result than anything in §2.
> - **"beating iTerm2" is still not measured, and the one iTerm2 datapoint in the cheap layout matched
>   kitty within ~10%.** The migration recommendation (§7 item 5) should **not** start yet.
> - **The stated reason kitty wins in the answer line above is retired.** WezTerm is **4.00** threads
>   per pane, not ~7.0 — and §8's own kill condition for the thread finding **fired**: 87 WezTerm
>   threads produced *fewer* context switches than kitty's 10. kitty still beats WezTerm, on **loaded
>   app CPU**, not on threads.
> - **§1's mechanism is half-refuted.** The per-pane `CAMetalLayer` is real and confirmed by direct
>   measurement; the per-pane **`CVDisplayLink` thread does not exist on 3.6.11** (+1.5 threads for 20
>   Metal panes, not +20). "Raising the cap adds ~30 display-link threads" is void. §1's *direction*
>   (Metal is not cheaper) survives; its *arithmetic* does not.
> - **Ghostty is measured and eliminated** (§6.7 closed): 4.00 threads/pane **linear**, highest loaded
>   CPU of the three, 3 processes per loaded pane.
>
> Full evidence, provenance and the corrected instrument list: **§9**.

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

> **⚠ SUPERSEDED 2026-07-31 PM — this subsection's number is wrong twice, and its axis is not a cost.**
> (a) **The constant is 4.00 threads/pane, not 7.0.** Two independent same-session measurements of
> WezTerm agree on 4.00 — recon 4 by symbol count (8 × `mux::read_from_pane_pty` + 8 ×
> `mux::parse_buffered_data` + 8 × `portable_pty Child::wait` + 8 × `mpmc Channel::recv` = 32 pane
> threads / 8 panes) and M2's loaded arm at 4.28 marginal. The 6→33 / 38→257 slope below was never
> reproduced and the box rebooted, so it cannot be re-checked. **Two oracles disagree; the shipping
> side is the 4.00 pair.**
> (b) **The axis is not a cost.** §8's own kill condition for this finding fired under load —
> see §9.2. Retain the *method* lesson (a perfect source review can be reversed only by running it);
> retire this number and this ranking rationale.

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
neither plain tmux nor `-CC` can offer under iTerm2.

#### Correction (2026-07-31): the hazard class does NOT disappear on kitty

This subsection previously closed by claiming kitty "makes the whole
`tmux-panes-inherit-server-iterm-session-id` hazard class disappear rather than be re-solved."
**That contradicts §5a and is withdrawn.** §5a establishes that Claude Code ships **no kitty
backend**, so on kitty *teammate spawning falls to the in-process or tmux path*. Re-verified by
`strings` on **both** live binaries — **0 `KittyBackend`, 0 `GhosttyBackend`** in 2.1.114 *and* 2.1.183.

The zeroes are the load-bearing fact and they are **method-independent**. *(The positive counts are
not: §5a above reports 43/39, the plan reports 40/32, and a re-count measures 47/41 occurrences or
21/24 matching lines for 2.1.183. Cite the zero; the positives read as contradiction and settle
nothing.)*

So the honest statement is: **kitty removes the hazard only for panes it owns natively** — `kitten @`
addressing with a real per-pane `$KITTY_WINDOW_ID`. The moment Agent Teams spawn teammates they land
on the **tmux** backend, and every tmux pane under one kitty window shares one `KITTY_WINDOW_ID`
exactly as they shared one `ITERM_SESSION_ID`. **Same hazard, new spelling** — re-solved, not
dissolved, which is precisely the argument for the `CC_PANE_ID` seam in
[`TERMINAL_AGNOSTIC_L3_L4.md`](../plans/TERMINAL_AGNOSTIC_L3_L4.md) rather than a terminal migration.

What kitty *does* remove is the **compositor** half (one surface for N panes). The **addressing** half
survives any terminal switch until the seam exists.

*Independent of the 2026-07-31 PM finding that §5b's dismissal of **plain tmux** rested on a false
premise: that one concerns whether tmux is viable as a substrate, this one concerns whether kitty
makes the addressing hazard go away. Both correct §5b; neither subsumes the other.*

---

## 6. What is NOT established

*(Status column added 2026-07-31 PM. Items 2, 6, 7 and 8 are CLOSED; 4 is partially closed; 1, 3 and
5 remain open, and item 1 got **further** from closure. Original text preserved.)*

> **Item 2 was closed by the LEAD, not by a workflow arm**, so the synthesis agent's own return still
> reports it open — it saw only the arms' digest. Recorded here because the discrepancy is otherwise
> unexplainable to a later reader, and because it is the general hazard of splitting work between a
> lead and a fan-out: **the synthesis surface only knows what was routed through it.**

1. 🔴 **OPEN — and it moved backwards.** **No multi-hour run of any challenger.** Total kitty uptime
   across this investigation is well
   under an hour; the operator leaves the fleet up for hours. The churn control is encouraging but is
   a different measurement than sustained runtime. **This is the single largest gap.**
   → **2026-07-31 PM:** the 12 h / 48-pane kitty (`kadv`) that was the closest thing to this evidence
   **did not survive the 11:46 reboot** — `/tmp/kadv.sock-*` is gone and `pgrep -x kitty` returns only
   post-reboot agent probes (recon 3). The longest constant-layout drift reads taken since are M1's
   6 min on Ghostty (threads flat 118, ports non-monotonic range 8, RSS +1 MB ⇒ no drift) and a 3-point
   read on a live 30-pane kitty (RSS 318→319→322 MB, threads flat at 6) — both explicitly **too short
   for a leak verdict**. Note also that the ~23.7 MB/pane-at-48 kitty figure quoted from `kadv` appears
   nowhere on disk and is inconsistent with every kitty RSS reading available today (M2 loaded 18 panes
   = 223 MB; marginal ~5.8 MB/pane over a 157 MB base ⇒ ~435 MB projected at 48). It is now
   permanently unfalsifiable and must not be cited.

   → **2026-07-31 22:17Z — a 30-minute attempt that failed on its PRECONDITION, not its result.**
   Longer than any read above (`--interval 1800`, live kitty pid 26094, 21:46:59→22:16:59Z,
   `verdict=OK`) and still not a closure:

   ```
   mem MB         +20 over 1800s  = +40.0/hr
   mach ports      +5 over 1800s  = +10.0/hr
   windows        -17 over 1800s  = -34.0/hr
   offscreen win  -18 over 1800s  = -36.0/hr
   ```

   **Do not quote the +10 ports/hr as a drift bound.** The instrument is only meaningful at *constant
   visible layout*, and this window was not: the census fell **36 → 19** while it held — 17 windows
   closed underneath it. Ports and windows move together, so +5 across 17 closures cannot be separated
   into leaked-versus-released. Critically, **`verdict=OK` does not certify the precondition**: the
   token attests that two readings and a GPU profile were obtained, nothing about layout stability. A
   consumer trusting the token alone would file this as the clean bound it is not.

   What it *does* add is a **churn** result on a live fleet rather than a synthetic one: the window
   population fell by 17 and offscreen fell by 18 (**−17 total, −18 offscreen ⇒ onscreen +1** — this
   line read "−17 onscreen" until 2026-07-31; the drift row's `windows` is the on+off TOTAL, see the
   correction below) for +5 ports and +20 MB — kitty gave the windows back, where iTerm2 had **98
   survive `close()`**. Raw transcript: `docs/research/data/kitty-drift-30min-2026-07-31.txt`.

   **What would close item 1:** the same command over a window in which nothing opens or closes.
   Resolution scales with the interval — at 1800 s one mach port is 2/hr, sharp enough to discriminate
   against iTerm2's **+76/hr**; at 45 s it is ~80/hr and cannot. The obstacle is not instrument time,
   it is finding a half-hour on a shared box when no session opens a pane. **Gate the run on a
   layout-stability check that ABORTS rather than emitting a confounded row** — as shipped, the
   instrument cannot tell you its own precondition broke.

   → **2026-07-31 23:20Z — that gate is now BUILT. The item stays OPEN;** what changed is that the
   next attempt can no longer fail the same way silently. `scripts/terminal-bench.sh` now measures
   the precondition, re-checks it every `--watch` seconds (default 30), and on breach prints
   `verdict=LAYOUT-DRIFT`, exits 4, and **emits no drift row at all**. Five things a successor should
   not re-derive:

   1. **The obvious column is the wrong one, and choosing it would have been worse than no gate.** The
      tempting key is the `windows` column the script already reads — but per `window-census.swift`
      that is the **on- AND off-screen total**, and a *rising* offscreen count **is** the leak this
      instrument exists to convict. A gate keyed on it makes a leaking terminal abort its own
      measurement and become structurally incapable of reporting the leak. The gate is therefore
      asymmetric: **onscreen must be UNCHANGED · offscreen must not FALL · offscreen RISING is
      allowed**. Onscreen is census field 4, which the script did not read at all before this change.
   2. **The 22:17Z numbers were mislabelled, and the corrected reading strengthens the gate rather
      than weakening it.** The drift row's `windows` is the total, so "−17 onscreen, −18 offscreen"
      above was never onscreen: total −17 with offscreen −18 means **onscreen actually rose by +1**.
      What really happened is *18 offscreen windows released plus 1 new onscreen window* — a release
      event and a layout change together. Both trip the asymmetric gate independently, so the rule
      derived above is validated against the real failure, not only against the synthetic tests.
   3. **Endpoint comparison alone is insufficient**, which is why it polls. A window that opens and
      closes *inside* the interval leaves both endpoints equal while having allocated and freed its
      ports underneath the measurement. Pinned by a test driving onscreen 1 → 3 → 1 that asserts the
      abort is attributed to a poll (`t+Ns`) and not to the endpoint check.
   4. **The hold is deadline-corrected and the drift now divides by ACTUAL elapsed**, not by the
      requested interval. Sleeping in poll-sized slices would otherwise make the true window
      `INTERVAL + N×poll` while the per-hour arithmetic still divided by `INTERVAL` — the
      `poll-loop-bound-excludes-its-own-check` shape. A census call costs **0.080 s** measured, so at
      `--interval 1800 --watch 30` the polling overhead is 60 calls ≈ 4.8 s: **0.27 %** of the window.
   5. **Two further verdict defects were found beside it, both inside the same six lines.** (a) The
      header has always documented "window census missing ⇒ PARTIAL", but the code set `OK`
      unconditionally once two readings existed — so a run with **no census at all**, where layout
      stability is pure assumption, was filed as a full comparable row. (b) The `--out` JSONL row was
      appended **before** the final GPU downgrade, so a run whose stdout read `PARTIAL` could leave
      `"verdict":"OK"` in the machine-readable sink — the overclaim landing on the surface a consumer
      parses rather than the one a human reads. Both fixed; `LAYOUT-DRIFT` is sticky and cannot be
      softened by the downgrade.

   **RED proof, not an assertion.** The pre-fix script at `f8633b2c`, driven against a stubbed census
   whose onscreen count moves 1 → 4 mid-interval, prints
   `DRIFT (app, constant layout — this is the leak instrument): windows +3 over 20s = +540.0/hr` —
   a confounded row under a header that literally reads *constant layout*. That is the 22:17Z failure
   reproduced on demand. Six tests in `tests/terminal-bench.bats` pin the new behaviour, and each
   asserts the printed **baseline**, so a mistimed run fails loudly instead of certifying a layout
   that never moved — three of them did exactly that in their first form, because the script's
   baseline probe lands ~5 s in (two `top -l 2` samples plus the GPU sample) and a change scheduled
   at t+2 had already been folded into the baseline before there was anything to detect.

   **Still required to close item 1: a real multi-hour run.** The gate supplies no evidence; it only
   guarantees the next attempt is either clean or loudly void, and makes a wasted window cost seconds
   instead of the full interval — which is what makes retrying on a shared box practical at all.

   → **2026-07-31 23:57Z — the gate fired on its FIRST live run, and that failure is the most useful
   thing yet learned about how to close this item.** A gate-enforced `--interval 1800 --watch 30`
   against live kitty (pid 7089, baseline **onscreen=4 offscreen=46**) aborted at **t+211 s**:
   `onscreen 4→3, offscreen 46→47`, `verdict=LAYOUT-DRIFT`, exit 4, **no drift row emitted**. Three
   consequences, the third being the one that changes the plan:

   - **The abort economics are measured, not projected:** 211 s spent instead of 1800 s, and the
     operator learns immediately rather than being handed a number to re-litigate later.
   - **One close moved a window into the offscreen population rather than destroying it** (onscreen
     −1, offscreen +1, total unchanged at 50). n=1, and it **convicts nobody** — every macOS app
     carries a large offscreen population (§3), and this is precisely the single-reading inference the
     calibration section bans. Noted only because a leak would have this same shape, so a later reader
     must not mistake it for evidence in either direction.
   - 🚨 **The binding constraint on item 1 is FLEET QUIESCENCE, not instrument time.** The layout
     moved within **3.5 minutes** on an ordinarily-busy box. A 30-minute constant-layout window is
     therefore not something to *wait* for on a live fleet — at this churn rate a clean 1800 s window
     is improbable and a 6-hour one effectively unreachable. **Closing item 1 needs a kitty instance
     nothing else touches**: a fleet held deliberately still, which is an operator-scale provisioning
     decision (30 panes on a box that has panicked twice in 48 h, against the 64-pane / 512-thread
     ceiling) rather than something to attempt opportunistically between other work. That reframes
     the item from *"find a quiet half hour"* to *"provision a quiet fleet"*, and is why it stays
     🔴 OPEN here instead of being retried in a loop. Raw transcript of the abort is not committed —
     it contains no drift row by construction, and the four lines above are its entire content.
2. ✅ **CLOSED 2026-07-31 PM — it renders correctly.** **No real Claude Code in a kitty pane.** Every
   challenger measurement used a synthetic alternate-screen repainter. kitty is a strict VT
   implementation and should render Ink correctly — but "should" is the word the evidence rules ban.
   → **Run by the lead, not by an arm** (which is why the synthesis agent's own return still lists
   this as open — it saw only the workflow's digest). Claude Code **v2.1.220** was launched into a
   kitty window and captured by window id (`screencapture -l1056`, image kept at
   `/tmp/cc-in-kitty.png`). Verified present and correct in the frame: the pixel-art sprite logo, the
   box rule above the input, the glyphs `⚠ ⓘ ▶▶ ›`, 24-bit colour on three status lines, full-frame
   alternate screen, and **no column offset or tearing**.
   **Bounded honestly:** this is ONE STATIC FRAME. Resize reflow and long-run alt-screen behaviour are
   *not* proven by it, and remain open (§8 keeps the resize row).
   **Incidental, and not a kitty defect:** the pane reported `Transcript saving is off — inherited
   CLAUDE_CODE_CHILD_SESSION marker`, because it was launched from an agent-owned shell. A session
   started that way keeps no transcript — relaunch from a clean terminal or set
   `CLAUDE_CODE_FORCE_SESSION_PERSISTENCE=1`.
   ⚠ **The classifier blocked the agent from doing this itself** (spawning a nested Claude Code
   session is denied in auto mode, and driving it via `kitten @ send-text` would launder the same
   denied action). It took an operator-run command. Any future item of this shape must be handed to
   the operator, not scheduled as agent work.
3. 🔴 **OPEN — and currently NOT RUNNABLE.** **No 4-display test.** Challenger windows were cascaded,
   not tiled one per monitor at 5120×2880,
   so per-display `CVDisplayLink` behaviour at mixed refresh is unmeasured.
   → **2026-07-31 PM:** only **3** displays are attached now, both externals at 60.00 Hz (recon 3;
   re-verified this session, `system_profiler SPDisplaysDataType | grep -c Resolution:` = 3). The
   freeze ran on **4** displays, ~52 Mpx, **two at 120 Hz**. Compositing work scales as Mpx × Hz, so
   the display configuration has changed by roughly the size of the whole freeze excursion — which
   makes this both un-runnable today *and* a live alternative explanation for the freeze that no arm
   in this investigation controls for.
4. 🟡 **PARTIALLY CLOSED — the "exogenous floor" half is refuted.** **The CoreAnimation defer-lock
   storm is only ~half iTerm2's, and is now the leading suspect for
   the CPU that the zombie windows do not explain.** Restarting iTerm2 took it 117/s → 58/s, so
   another client produces the remainder; **switching terminals does not obviously fix it.** The
   three format strings were located in the dyld shared cache and belong to QuartzCore
   (`"Defer Lock context 0x%x unlocked but lock count is not zero (was %d)"`,
   `"…not found in defer lock watchlist"`, `"Defer Lock missing release ?"`) — an instrumented
   balance check on deferred presentation locks against a `CAContext`, **one per layer-hosting
   window**. There is **no public documentation, no userspace diagnostic, and no workaround short of
   restarting the offending client.** The emitting symbol could not be resolved, so the mechanism is
   inferred from the strings, not from Apple.
   → **2026-07-31 PM (measured live, refuter 2, with a positive control that mattered):** a 65 s
   foreground `log stream --level debug --predicate 'eventMessage CONTAINS "Defer Lock" OR
   eventMessage CONTAINS "lock count"'` (rc=124, ran to timeout) at 3 h uptime, loadavg 54.8, iTerm2
   at 20 windows returned **48 records in ~47 s ≈ 1.0/s across 12 distinct contexts, lock counts 4–6**
   — versus **117/s across 33 contexts, counts to 13** at the freeze. Positive control: a 20 s
   `process == "WindowServer"` debug stream returned 978 lines, so a zero would have been
   distinguishable from no-data — and this mattered, because a narrower
   `subsystem == "com.apple.coreanimation"` predicate returned **0** Defer Lock records and would have
   been a **false clean**.
   **Two consequences.** (a) The "**58/s is a floor another client produces ⇒ switching terminals does
   not fix it**" reading is **refuted** — the remainder decayed to 1.0/s, so it was not a floor and
   there is no longer a basis for calling the residue exogenous-and-unfixable. (b) The drift signature
   the rules require **is present now**: identical 12-context population in two bursts 46 s apart,
   burst 1 = 12 × `was 4`, burst 2 = 12 × `was 4` + 12 × `was 5` + 12 × `was 6` — a **monotonic climb
   at constant layout**, i.e. an **accumulator over uptime** (4–6 at 3 h; 13 by the freeze) with 12
   contexts against 314 live CGWindows. Still NOT established: that this is what took WindowServer to
   95% — 1.0/s is ~120× below the freeze rate, so the accumulator was caught early, not proven causal.
   Neither "group the windows" nor "switch terminals" touches its independent variable.
5. 🔴 **OPEN — and the metric now cuts against kitty.** **kitty's load-bearing claim rests on CGWindow
   counts**, not IOSurfaces, CALayers, or
   per-window WindowServer mach ports — and the freeze was characterised by *ports* and *CA
   contexts*. One `NSOpenGLContext` could in principle be backed by several IOSurfaces.
   → **2026-07-31 PM:** a live census (refuter 2, `tools/terminal-bench/window-census.swift`) reads
   **kitty pid 26094: win=36, on=0, off=36, 8 zero-area** — the *highest* CGWindow count of any app on
   the box, above iTerm2's 20. Either offscreen windows are free (in which case the 2.35× arm
   describes no layout the operator runs) or kitty is the worst offender on the model's own metric.
   Not both. Note also that `window-census.swift`'s `layers=N` column is the count of distinct
   **CGWindowLayer Z-order values**, not CALayers (recon 3, `window-census.swift:30,101`) — reading it
   as a CALayer count would be a false close of this very item. IOSurface counts remain unavailable
   root-free.
6. ✅ **CLOSED by §9.2 — with a caveat on N.** ~~No candidate was load-tested by me.~~ Every
   challenger figure above is from **idle** panes
   (Stage A), which is what isolates the structural axes — threads, surfaces, ports — but says
   nothing about CPU under load. The only loaded challenger measurement in this document is the
   fleet agent's kitty run (36 panes at 10 Hz → 12.9–13.9% CPU, main thread 89% idle).
   → **2026-07-31 PM:** M2 ran a byte-matched Stage-B head-to-head — kitty, WezTerm, Ghostty at 18
   panes / 10 fps, **every loaded pane at exactly 10.00 achieved fps, zero SUSPECT rows**. Result in
   §9.2. **Caveat:** N=18, not 30–40 (bound by the 64-process safety ceiling, not by any terminal
   refusing a split), and **iTerm2 was excluded by construction** — so this closes "no challenger was
   load-tested", *not* "kitty beats iTerm2".
7. ✅ **CLOSED by §9.1 — and the desk figure it rested on was wrong.** ~~Ghostty was not measured.~~
   It scored lowest of the survivors (52) on the strength of its
   scripting story rather than its renderer: per pane it allocates one `NSView` + one plain
   `IOSurfaceLayer` (not a `CAMetalLayer`) and, in the shipped 1.3.1, **three OS threads**. It has no
   working CLI IPC on macOS (`performIpc` returns false) but does ship a full AppleScript dictionary.
   Given WezTerm's measured 7 threads/pane, Ghostty's 3/pane deserves a measurement before it is
   dismissed — it may sit between kitty and WezTerm.
   → **2026-07-31 PM:** measured at 8 and 24 panes. **4.00 threads/pane exactly, linear, `threads =
   4N + 6` with residual 0 at three independent pane counts.** The desk "3 threads/pane" figure missed
   the `cf_release` thread. Ghostty lands **with WezTerm, not near kitty**, and under load it was the
   most expensive of the three (27.3% app CPU). The one axis where it beats iTerm2's Metal path
   decisively: **zero** CVDisplayLink threads at any N, and zero added CGWindows from 8→24 panes. Its
   CLI-IPC gap is real (`+new-window is not supported on this platform`) but AppleScript `split`
   drives it fine. **Ghostty is eliminated as the recommendation, on measurement.**
8. ✅ **CLOSED by §9.3 — and it split.** ~~The all-Metal iTerm2 configuration has never been run~~,
   here or upstream. The claim that
   raising the cap makes things worse is INFERRED from source (§1) and is the sharpest falsifiable
   claim in this document.
   → **2026-07-31 PM:** the arm **ran**, in an ad-hoc-signed sandbox bundle with its own bundle id and
   its own `iTermServer`, with both controls passing (positive: `iTermMetalDriver`=158 frames;
   negative: **exactly 0**). Verdict in §9.3: the per-pane `CAMetalLayer` is **confirmed**, the
   per-pane `CVDisplayLink` thread is **refuted**, the WindowServer question is **UNDECIDED**, and
   Metal did **not** come out cheaper on any CPU axis. §1's conclusion survives; §1's mechanism does
   not.

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

   ⛔ **HOLD 2026-07-31 PM — do not start this.** Three reasons from §9, none of which existed when
   this item was written: (a) **"kitty beats iTerm2" is unmeasured** and the only iTerm2 datapoint in
   the cheap layout matched kitty within ~10% (§9.4a); (b) **two cheaper, more reversible rungs are
   live and unevaluated** — the 8 knobs have now passed their own recycle gate unmeasured, and plain
   tmux was dismissed on a premise that is false (§9.6); (c) **the port is ~3× the advertised size**
   — 611 `it2` hits across 119 files, not 209/73 (§9.4c). Ordering by reversibility is
   **knobs < tmux ≪ kitty**, and rungs 1 and 2 have not been climbed.

**New rung, ahead of everything expensive.**

6. **Fix the instruments before the next campaign** — §9.5. In particular `terminal-bench.sh` cannot
   see iTerm2 at all (`pgrep -x iTerm2` rc=1 against a live pid), which makes item 1's own
   re-measurement command unrunnable, and `terminal-bakeoff.sh` has no lock, a 5 s settle that
   under-reports 2×, and per-pane arithmetic that overstated Ghostty by 2×.

---

## 8. Falsification plan

The recommendation is **wrong** if any of these come back negative, and each is cheap.
**Status column added 2026-07-31 PM — 3 of 7 have now run; the results are in §9.**

| Test | Kills the recommendation if | Status |
|---|---|---|
| kitty, 30 panes, real Claude Code, **6+ hours**, `terminal-bench.sh --interval 1800` | windows/ports/RSS drift is non-zero at constant layout | 🔴 **NOT RUN** — and further away: the 12 h `kadv` evidence was destroyed by the 11:46 reboot (§6.1). Longest read since is 6 min. |
| Claude Code TUI in a kitty pane, visual check | Ink renders incorrectly (glyphs, resize, alt-screen) | ✅ **RAN — PASSED (glyphs + alt-screen).** CC v2.1.220 captured by window id; sprite logo, box rule, `⚠ ⓘ ▶▶ ›`, 24-bit colour, full-frame alt-screen, no column offset (§6.2). **Resize reflow NOT covered** — one static frame. Operator-run: the classifier denies an agent spawning a nested CC session. |
| kitty across 4 displays at mixed refresh | WindowServer CPU scales with display count worse than iTerm2's | ⛔ **NOT RUNNABLE** — only 3 displays attached, both externals at 60.00 Hz (§6.3) |
| `kitten @ launch --next-to` **without** `--match` | (already known to silently mis-place — needs a guard, not a test) | 🔴 **guard still not written** |
| **all-Metal iTerm2** — 5 windows × 5 panes (Metal, under the cap) vs 5 × 8 (CPU), matched pane count and pixels, `top -l 2` second sample | WindowServer CPU goes **down** in the Metal case ⇒ §1 is wrong, the cap is a real ceiling worth patching, and iTerm2's score rises sharply. **Needs no source build.** | ✅ **RAN (§9.3)** — as specified it was **confounded** (varies renderer *and* pane count *and* pixels), so it was rerun as `UseMetal` flipped at byte-identical layout. **Did not kill it:** Metal cost **+1.07 pp** WindowServer (wrong direction for the kill, and 12× below the noise floor ⇒ UNDECIDED) and **+20.3 pp app CPU** (wrong direction, n=1). But it **voided §1's mechanism** — no per-pane CVDisplayLink thread exists. |
| Ghostty at 24+ panes, same Stage-A protocol | Ghostty's 3 threads/pane lands near kitty rather than WezTerm | ✅ **RAN (§9.1) — did not kill it.** 4.00 threads/pane linear (`4N+6`, residual 0 at 3 pane counts); lands with WezTerm. The "3 threads/pane" premise was itself wrong. |
| kitty and WezTerm under **load** (Stage B), not idle | WezTerm's 210 parked threads at 30 panes cost nothing measurable ⇒ the thread finding is a curiosity, not a risk | ✅ **RAN (§9.2) — this kill condition FIRED.** WezTerm's 87 threads under load produced **4,917 csw/s vs kitty's 10 threads at 5,280 csw/s**, 0 idle wakeups, 2 of 86 runnable. **The thread finding is a curiosity.** The recommendation survives on a *different* axis (loaded app CPU 9.5% vs 24.4%), not on threads. |

### New falsification tests this session opened

| Test | Kills the recommendation if | Why it is now the priority |
|---|---|---|
| **iTerm2 vs kitty, byte-matched Stage-B load, same session, 1 window each** | iTerm2 in one window matches kitty ⇒ there is no measured performance case for migrating | The only iTerm2 loaded datapoint that exists (§9.3 arm B: 1 window × 20 panes, CPU renderer → **10.5% app CPU, 9 threads**) sits within ~10% of kitty's 9.48% / 10 threads — **and its own load telemetry recorded 0 frames, 0 bytes, fps 0.00 SUSPECT**, so it proves nothing in either direction. Blocked on the `pgrep` defect in §9.5. |
| **Re-measure the 8 render knobs now that the panes have recycled** (§7.1's own gate) | the knobs recover a meaningful share of the cost ⇒ the free rung beats the expensive one | The gate is now satisfiable: knobs written 06:50Z, iTerm2 pid 591 started 11:46:52 — the whole app is post-write, `iterm2-perf-parity.sh` reads `match=9 drift=0 unset=0`, and a live profile shows two knobs working on the exact named mechanisms. **Never evaluated.** |
| **Plain tmux inside one iTerm2 window, per-pane addressing via `#{pane_id}`** | it delivers one surface for N panes *and* real per-pane ids ⇒ kitty's structural advantage is not unique | §5b dismissed plain tmux on "per-pane addressing is architecturally absent". Refuted live in an isolated tmux 3.6a server: `list-panes -F '#{pane_id}'` → `%0`; `split-window -t %0 -h -P -F '#{pane_id}'` → `%1`; `display -p -t %1 '#{pane_tty}'` → `/dev/ttys050`. All three primitives exist natively. See §9.6. |
| **Replicate the 2.35× window/surface harness** | it does not reproduce ⇒ the document's most-cited number has no artifact | The Cocoa/IOSurface harness was **never committed** (`git log --all --diff-filter=A` finds no such file) and `/tmp` was destroyed by the reboot. See §9.4. |

---

## 9. 2026-07-31 PM — live measurement session

**What ran:** 4 recon agents (Ghostty drivability · all-Metal protocol design · noise-floor
characterisation · WezTerm thread pricing), 3 serial measurement arms (M1 Ghostty Stage-A · M2 loaded
head-to-head · M3 all-Metal counterfactual), and 3 adversarial refuters against the three most
load-bearing claims in §§1–5. **All three refutations came back REFUTED** — unlike the 2026-07-30
adversarial phase, which never returned.

**Box state — measure it, do not inherit it.** The machine **hard-rebooted at 11:46:47** (kernel
spinlock-timeout panic, `locks.c:446`, provoked by an earlier agent's thread-exhaustion probe at
8,368 threads in one task). Every pre-11:46 absolute in this document is stale. During this session
loadavg swung **6.06 → 132.76** with sibling agents on the box, so **only interleaved bracketed
deltas are admissible**, and several arms were cut short by the >12-WAIT / >25-ABORT rule.

### 9.0 The measurement result that governs how to read every number here

Recon 3 characterised this box's noise before any arm ran, and the answer is that **the axis the
freeze actually lived on is not measurable here at the n this session could afford.**

| axis | verdict | evidence |
|---|---|---|
| per-process **threads** | ✅ trustworthy | WezTerm held th=40 / ports=389 / RSS=188M **identical across 12 consecutive samples** spanning loadavg 11.49→23.86 and WindowServer 33.1→48.0%. iTerm2 threads sd **0.00** over n=10. |
| per-process **ports**, **RSS** | ✅ trustworthy | cv 0.5–2.5% |
| **CGWindow** counts | ✅ trustworthy | single instantaneous enumeration, no CPU term |
| GPU:CPU **symbol ratio** | ✅ trustworthy | contamination scales numerator and denominator together |
| **WindowServer CPU %** | ❌ **unusable at low n** | bracketed-residual SD **4.44 pp** intra-arm ⇒ **MDD 12.44 pp at n=1, 4.15 pp at n=9**. Worse, it is **sign-inverted**: removing a live 40-thread arm moved WindowServer CPU **UP by 8.11 pp**. |
| **WindowServer mach ports** | ❌ **instrument dead** | range 193 across 12 samples at constant layout, non-monotonic. Historical leak signal was "+32 ports over ~10 min". **Noise ≈ 6× signal.** |
| **loadavg**, box **idle %**, box **total threads** | ❌ never a readout | loadavg 2.08× swing at constant layout; idle% cv ~50% in *both* conditions |

⇒ Every WindowServer-CPU number below is reported with its noise floor attached, and none of them
decides anything. The structural axes carry this session's conclusions.

### 9.1 Ghostty, measured (closes §6.7) — LINEAR, not flat

Driven via AppleScript `split` (no CLI IPC exists on macOS: `+new-window is not supported on this
platform`), scoped to a window id the arm created, bracketed by baselines on both sides because
another agent's 4 stale Ghostty terminals could not be torn down under the safety rule.

| N (app-wide terminals) | threads | ports | RSS | CGWindows (onscreen) |
|---|---|---|---|---|
| 4 (baseline, foreign) | 24 | 438.7 | 134 MB | 16 (2) |
| 12 (8 mine) | 54 | ~584 | 237 MB | 17 (3) |
| 28 (24 mine) | 118 | ~867 | 418 MB | **17 (3)** |
| 4 (post-teardown) | 22 | 427 | 158 MB | 16 (2) |

- **`threads = 4N + 6`, residual 0 at three independent pane counts** (N=12 → 54; N=28 → 118;
  post-teardown N=4 → 22). Slope `(118−54)/(28−12)` = **exactly 4.00/pane**.
- **Independently confirmed by thread-name census**, which is immune to base-pool drift: at 12
  terminals `renderer=12, io=12, io-reader=12, cf_release=12`; at 28 terminals `28/28/28/28`. The
  prior desk figure of 3 threads/pane **missed `cf_release`**.
- **Growing 8 → 24 panes added 0 CGWindows and 0 onscreen pixels.** Linear in the cheap axis only.
- **Zero CVDisplayLink threads at any N** — the axis §1 convicts iTerm2's Metal path on.
- **Metal is the only backend in the binary** (`strings` yields exactly `renderer.generic.Renderer`
  and `renderer.Metal`; no OpenGL, no CPU rasterizer to fall back to). Under repaint at 24 panes: **48
  call-graph frames** in `renderer.Metal.{updateFrame, rebuildRow, addGlyph, rebuildCells}` vs **0**
  in `CGContext|ripc_|argb32|CGSBlend`. **21 distinct renderer threads** built frames concurrently
  while the main thread sat **6312/6312 samples** parked in the AppKit event loop with **0** frames in
  `psynch_mutexwait|semaphore_wait_trap|ulock_wait`.
- **No drift** over 6 min at constant 24-pane layout: threads flat at 118, ports non-monotonic range
  8, RSS +1 MB. (Too short for a leak verdict — see §6.1.)
- **Ceiling reached, not omission:** Ghostty spends **2 processes per idle pane** (3 per *loaded*
  pane — it inserts `/usr/bin/login`), so 24 panes = 56 processes against the 64-process safety
  ceiling. 30 panes would be 68. **Nothing above 24 was measured**; the 30/40-pane rows are arithmetic
  from `4N+6`, not readings.

> **Not established:** GPU *submission* at 24 panes. The frame **build** is proven Metal, but 0
> AGX/IOSurface/QuartzCore frames were recorded because Ghostty's window was **occluded** (census
> `on=0, 0.00 Mpx`) — the driving tooling runs inside the operator's iTerm2, which re-raises itself.
> Recon 1 *did* observe the full `renderer.Metal.drawFrame → AGXG13XFamilyRenderContext::drawPrimitives
> → AGX::RenderContext::encodeAndEmitRenderState` chain at 4 panes with a visible window. It was not
> reproduced at 24.

### 9.2 The first byte-matched loaded head-to-head (closes §6.6)

18 panes per candidate, 10 fps, `scripts/tui-load.sh`. **Load parity verified, not assumed:** every
loaded pane in every arm reported **exactly 10.00 achieved fps** (min = max = 10.00 for 18/18, 19/19,
18/18), **zero SUSPECT rows**. kitty's window resize succeeded so its panes were *larger* — it carried
**8.45 MB/pane vs 6.90 / 6.94** for the others.

| | kitty | WezTerm | Ghostty |
|---|---|---|---|
| **app CPU under load** | **9.48%** (replicate 8.77%) | **24.36%** (replicate 23.28%) | **27.32%** (no replicate) |
| **CPU per KB/s delivered** | **0.0122** | 0.0364 (**3.0×**) | 0.0429 (**3.5×**) |
| threads (marginal/loaded pane) | 10 (**0.11**) | 87 (4.28) | 98 (4.89) |
| **context switches/s** | 5,280 | **4,917** | 6,386 |
| idle wakeups added | 2 | **0** | 0 |
| runnable threads at profile | 0 R / 9 S | **2 R / 84 S** | 0 R / 97 S |
| GPU : CPU-raster frames | 375 : 15 | 299 : 0 | 897 : 0 |
| RSS / loaded pane | 3.7 MB | 5.8 MB | 22.4 MB |
| onscreen painted area | 4.61–6.15 Mpx | **0.26 Mpx** | 2.48 Mpx |

**Two conclusions, and they are not the same conclusion.**

1. **kitty is 2.6–2.9× cheaper on app CPU than either rival, and that ordering is a lower bound** —
   kitty simultaneously carried the most bytes per pane *and* ~18× the painted area of WezTerm, and
   still spent the least CPU. This is the strongest challenger result in the document.
2. **§8's thread kill-condition fired.** WezTerm's **87 threads produced FEWER context switches than
   kitty's 10** (4,917 vs 5,280/s), zero idle wakeups, and 2 of 86 runnable. Recon 4 priced a parked
   thread independently: **24.4 KB user-resident** (`vmmap`: 992 KB dirty / 40 threads) + **16 KB
   wired kernel stack** (`kern.stack_size`) ≈ 40 KB, i.e. **~4.8 MB for 30 panes** — 0.55% of
   WezTerm's own per-pane RSS, and 1.4% of the 8,368-thread empirical panic point. Recon 4 also
   classified the quartet: `mux::read_from_pane_pty` (blocking pty read) · `mux::parse_buffered_data`
   (VT parse) · `portable_pty Child::wait` (reap) · `mpmc Channel::recv` (park) — **0 of 40 runnable**
   at idle, all in a kernel trap, spawned at split time, one shared `async-io` reactor. **Threads are
   not the cost. Retire the §2 ranking rationale.**

> **The WezTerm-vs-Ghostty ordering is NOT safe and should be read as a tie**: the forced 1600×1000
> geometry took for kitty and Ghostty and **silently failed for WezTerm** (0.26 Mpx), so Ghostty
> painted ~6× WezTerm's area and renderer cost cannot be separated from pixel count. Only the
> kitty-vs-both ordering survives the confound, and it survives it in the conservative direction.
>
> **N=18, not 30–40.** The binding constraint was the **64-process safety ceiling**, not any terminal
> refusing a split — `tui-load.sh` costs 2 processes per pane (3 under Ghostty). All three spawners
> reported "spawned 18 of 18". Reaching 30–40 inside the ceiling requires `tui-load` to **exec** the
> perl emitter instead of forking it (1 proc/pane) — a change to a shared instrument, deliberately not
> made mid-campaign.

### 9.3 The all-Metal iTerm2 counterfactual (closes §6.8) — §1 splits in half

Run in an **ad-hoc-signed sandbox copy** with its own bundle id (`com.googlecode.iterm2.allmetalbench`)
and its own `iTermServer` — the operator's live iTerm2 was never a target (only two read-only
`count of windows` queries were addressed to it; pid 591 ended the session with the same 3 windows).

Three protocol defects were found and fixed **before** the arm, each of which would have produced a
vacuous pass:

1. **Recon 2's sandbox was unlaunchable as specified** — `-o runtime` re-enables Library Validation,
   so an ad-hoc main binary may not load ad-hoc frameworks (`dyld` abort: *"mapping process and mapped
   file (non-platform) have different Team IDs"*). Fix: drop the hardened-runtime flag (flags
   `0x10002` → `0x2`). The entitlement route (`disable-library-validation`) was **classifier-denied**.
2. **The `UseMetal` lever was inert.** The protocol wrote prefs to `$BENCH_HOME/Library/Preferences/`
   (353 B, never read); the app reads `~/Library/Preferences/<bundleid>.plist` —
   `NSSearchPathForDirectoriesInDomains` ignores `$HOME`. **Arm C would have been a second Metal arm.**
3. **The handed-down Metal verifier was wrong.** Distinct `CAMetalLayerEventListenerQueue` dispatch
   ids read **4, then 0, then 2** at unchanged layout while `iTermMetalDriver` read **75, 70, 98** in
   the same samples — used as the negative control it would have **passed vacuously on a fully-Metal
   arm**. Control moved onto `iTermMetalDriver == 0`.

Controls then held: positive `iTermMetalDriver`=158 frames vs `iTermTextDrawingHelper`=20; negative
**`iTermMetalDriver` = 0 exactly**, `get-drawable` = 0, layer queues = 0. One rep was **discarded as
void** on three independent grounds (achieved 8w/40p instead of 4w/20p; positive control gpu=0 with
UseMetal=YES; probe returned `0 0 0 0` = NO-DATA) — **including it inverted the result to "Metal 12.2
pp cheaper", the exact vacuous-pass shape.**

| §1 sub-claim | verdict | measurement |
|---|---|---|
| one **`CAMetalLayer`** per Metal pane | ✅ **CONFIRMED** | **20 distinct** `CAMetalLayerEventListenerQueue` ids at 20 Metal panes, **0** in both CPU arms. Plus 20 `com.Metal.CommandQueueDispatch` + 21 `CompletionQueueDispatch` ⇒ **~3 dispatch queues per Metal pane**, *more* granular than §1 states. (Lower bound that saturated at the pane count — a layer-tree read is still the missing instrument.) |
| one **`CVDisplayLink` thread** per Metal pane | 🚨 **REFUTED** | **0** occurrences of `CVDisplayLink\|CADisplayLink\|iTermDisplayLink` in **either** arm. Threads: **12.0** (20 Metal panes) vs **10.5** (20 CPU panes) = **+1.5 total = +0.075/pane**. §1 predicts +20. **At 30 panes: §1 says +30 threads; measurement says +2.3 to +4.5.** |
| one **`NSTimer`** per Metal pane | ⚪ untested | 2 hits vs 0 in 10 s samples — presence, not a per-pane count |
| **the ≤5-panes-per-tab cap** | ✅ **CONFIRMED BY MEASUREMENT** (first direct observation; previously only read from source) | `UseMetal=YES` with **20 sessions in ONE tab** → `iTermMetalDriver` = **0 frames**, drawable = 0, layer queues = 0. **The pref was ON; the cap overrode it.** |
| **Metal costs more WindowServer CPU** | ⚠️ **UNDECIDED** | Metal − CPU = **+1.07 pp** at 20 panes (Δ_Metal −1.40, Δ_CPU −2.47 mean of 2), against an **MDD of 12.44 pp at n=1**. ~12× below the noise floor. **An underpowered null is not a confirmation of §1** — §1 predicts a *positive* effect. Needed n≥9; a sibling agent drove loadavg to 132 and the ABORT rule fired. |
| **Metal costs more app CPU** | 🟡 **SUGGESTIVE** | **96.5%** (20 Metal panes) vs **76.2%** mean of 71.9/80.5 (20 CPU panes, identical geometry/fps) = **+20.3 pp, +1.01 pp per Metal pane**. n=1 vs n=2, **no measured noise band for the sandbox**. Metal was *cheaper* on memory (−58 MB) and cost +89.5 mach ports. |

**Net effect on §1: the conclusion survives, the mechanism does not.** Metal did not come out cheaper
on any CPU axis, so "the cap is protecting you" is not contradicted — but it is now supported (weakly,
n=1) by *app* CPU and per-pane `CAMetalLayer`/dispatch-queue count, **not** by display-link threads,
which do not exist on 3.6.11. Any future argument for or against raising the cap must be rebuilt on
the confirmed half.

**Also unmeasured, and it is the test that would actually decide whether raising the cap is
dangerous:** §1's freeze path is main-thread blocking in `acquireScarceResources` /
`com.iterm2.get-drawable`. The drawable queue was observed present in the Metal arm and absent in the
CPU arms, but **main-thread samples inside `psynch_mutexwait` versus paint frames were never counted**.

**Bonus result — the window axis relocates into the application.** Renderer held **constant** (both
CPU-rendered), 20 panes, matched **3.36 Mpx** onscreen: **4 windows × 5 panes = 76.2% app CPU vs
1 window × 20 panes = 10.5% app CPU — 7.3×** — while every WindowServer bracketed delta in that same
run was *negative*. ⚠️ **n=1 and work-matching is unproven** (see §9.4). Direction corroborates
"windows are the expensive unit"; magnitude does not transfer, and the *location* of the cost does not.

### 9.4 Adversarial phase — all three load-bearing claims REFUTED

**(a) "kitty beats iTerm2" — REFUTED as stated (high confidence).** The compression half survives;
the performance half was never measured and the instrument forbids it.
`scripts/terminal-bakeoff.sh:200-201` **hard-forces `MEASURE_ONLY=1` for iTerm2**, so the shipped
driver *structurally cannot* run a loaded iTerm2 arm — and §9.2, the only byte-matched head-to-head,
excluded it. The one iTerm2 arm in the cheap layout (§9.3 arm B: 1 window × 20 panes, CPU renderer)
read **10.5% app CPU / 9 threads / 683 ports / 1 window** against kitty's **9.48% / 10 threads** at 18
loaded panes — **within ~10% on both axes**, and iTerm2 there is 0.45 threads/pane, **as flat as
kitty**. The thread axis that "reversed the desk ranking" convicts WezTerm and Ghostty, not iTerm2.
**But that arm's own load telemetry is void**: `/tmp/allmetal/load.tsv` exists (816 B) and every data
row reads `frames=0 bytes=0 fps=0.00 SUSPECT` — all arms wrote to one shared path. **So iTerm2 has
zero valid loaded measurements at any pane count, and the comparison fails in both directions.**
Separately, the live "kitty at 30 panes" evidence on the box is **not a load**: all 30 children are
`while :; do date +%H:%M:%S; sleep 5; done` ≈ **1.8 B/s/pane**, against tui-load's ~35 KB/s/pane —
~19,000× less — and its window is **not composited at all** (`win=36 on=0 0.00 Mpx`) while iTerm2 sits
at `win=20 on=7 9.77 Mpx`.

**(b) "Windows are the expensive unit (2.35×), panes nearly free (1.17×), so the fix is grouping, not
the renderer" — REFUTED (high confidence) on the second clause; the ordering survives.**
- **The harness does not exist.** `git log --all --diff-filter=A` since 2026-07-25 finds no
  `.swift`/`.m` harness file but `window-census.swift`; it is absent from this document's own
  artifacts list; `/tmp` was destroyed by the reboot. **The most load-bearing number here is a
  citation, not a replayable artifact.**
- **The 1.17× half is an underpowered null.** The pane effect is 11.2 − 9.6 = **1.6 pp** at 5 reps,
  against this box's MDD(n=5) of **5.56 pp** intra-arm. "Panes are nearly free" is a **non-verdict read
  as a measurement**. (The 11.4 pp window effect *does* clear even the pessimistic MDD.)
- **The effect cannot explain the phenomenon.** The harness's entire dynamic range across all four
  arms is **13.0 pp**; the freeze was WindowServer at **92.7–99.9%** — an ~85 pp excursion. At the
  operator's actual ~8 real windows the realizable grouping gain interpolates to **~6.3 pp**, i.e.
  ~7–13% of the observed event.
- **The freeze doc already falsified window-count as the driver**, verbatim: *"WindowServer CPU swung
  52% → 98% at **constant** window count."* A 46 pp swing at constant windows is 3.5× the whole harness
  range.
- **The two halves are inconsistent unless "window" is silently redefined** — the same harness found
  200 idle onscreen windows indistinguishable from baseline, so 2.35× applies **only** to windows
  repainting at 20 Hz. Live census now: **314 CGWindows, 296 offscreen, 18 onscreen, 37.7 Mpx**, with
  WindowServer at 52.3% and not frozen. The applicable population is ~18, of which iTerm2 owns 7 — not
  30, not 98. And 314 × 30 MB = 9.2 GB against WindowServer's actual **1,283 MB** RSS: the per-window
  memory figure fails by ~8× on the same census.
- **On real terminals the window penalty relocates OUT of the compositor** (§9.3 bonus: 7.3× on *app*
  CPU while every WindowServer delta was negative), which makes "grouping, **not** the renderer" the
  wrong disjunction — an app-CPU window penalty *is* a per-terminal renderer property.
- **What survives:** the **ordering**. The marginal decomposition of the harness's own arms is
  stronger than 2.35× (0.393 pp/window vs 0.055 pp/surface ≈ 7×), and §9.3's 7.3× points the same way.
  Grouping is probably a real win. It is small, unreproducible, inapplicable to the layout the operator
  actually runs, and insufficient as a cause — so it cannot carry the "so".

**(c) "Migrating off iTerm2 is worth it — 209 hits collapse to 13 capabilities" — REFUTED (medium
confidence) on the cost framing, not the arithmetic.** The **13 capabilities figure held under attack**
(the distinct `it2` verb set really is ~13: session, close, window, ls, split, write, send, keystroke,
capture, force-close, notify, run, ping). What failed:
- **The counts are wrong and internally inconsistent.** At the doc's own commit `git grep` returns
  **217 hits / 75 files**, not 209/73. §4's decomposition says "36 (of 41 …) plus 48 test files" =
  89 files, which cannot sit inside a 73-file total; the tree has **21** test files, not 48.
- **`ITERM_SESSION_ID` is ~35% of the coupling.** On the same tree: `it2` = **611 hits / 119 files**;
  `osascript` = 288 / 80; `iTerm2|iTerm.app|com.googlecode.iterm2` = 621 / 144. **The port is ~3×
  larger than "209 hits" implies.**
- **The two cheaper rungs were never evaluated, and one was dismissed on a false premise.** See §9.6.
- **The reversibility ordering is knobs < tmux ≪ kitty**, and the two cheap rungs are unmeasured.

### 9.5 Instrument defects found this session — fix before the next campaign

| defect | location | consequence |
|---|---|---|
| 🚨 **`pgrep` cannot see iTerm2 on this box** | `scripts/terminal-bench.sh` keys presence on `pgrep -x` | `pgrep -x iTerm2` **and** `pgrep iTerm` both return rc=1 against live pid 591 whose `ps -o ucomm` is exactly `iTerm2` (`pgrep -x ghostty` works; re-verified this session). ⇒ `--app iTerm2` emits **`verdict=NO-DATA` for the one terminal the decision is about**, and §7.1's own re-measurement command is structurally unrunnable. `ps` reads the same kernel table and *does* see it. |
| per-pane arithmetic divides app-wide totals by the **user-typed** `--panes` | `terminal-bench.sh:235-242` | no baseline subtraction, no measured denominator. Printed **8.00 threads/pane** for Ghostty against a marginal truth of **4.00**, and `threads/pane 0.87 · MB/pane 49.5` for iTerm2 whose numerator contains 20 CGWindows and hours of scrollback. |
| driver invokes the bench with `--interval 0` | `terminal-bakeoff.sh:242` | the bench's own header says `--interval 0` **always yields PARTIAL**. ⇒ every driven arm has **no drift verdict and no bracketing baseline** — absolute levels only. |
| **no serialization** | zero `flock` in `terminal-bakeoff.sh` | a sibling agent drove a 24-pane Ghostty arm **through** M2's WezTerm round-2 arm. Needs a repo-wide lock held across spawn + settle + reps + teardown + recovery. |
| `sleep 5` settle **under-reports 2×** | `terminal-bakeoff.sh:135` | WezTerm climbed 14 → 17 → 21 → **40** threads over ~90 s. A read at +5 s records ~17 against a true 40. Criterion: two consecutive equal thread reads. |
| `BAKEOFF_MAXLOAD` defaults to **40** | `terminal-bakeoff.sh:36` | 3.3× looser than the safety rule (WAIT 12 / ABORT 25). Gate **admission only** — never retroactively void a completed reading on load, since load is not attributable to the arm. |
| kitty control socket is a **global** path | `terminal-bakeoff.sh:111,223` | `unix:${TMPDIR:-/tmp}/kitty-bakeoff` — `$TMPDIR` is one per-*user* directory. Two concurrent kitty arms silently merge and each reads the other's denominator. |
| `tui-load.sh` costs **2 processes per pane** (3 under Ghostty) | shared instrument | the 64-process ceiling binds at **18–24 panes**, which is why nothing in this session reached 30–40. Fix: `exec` the perl emitter instead of forking it. |
| `--interval 0` / shared load-stats path ⇒ matched-work control silently absent | M3 harness | `load.tsv` rows all `fps=0.00 SUSPECT` ⇒ the one iTerm2 loaded datapoint has **no verified work behind it**. |
| a **CPU-ordered `top`** manufactures NO-DATA | ad-hoc census scripts | `top -l 2 -n 400 -o cpu` dropped Ghostty from two consecutive samples purely because it sat at 0.0% CPU, while `ps` proved it alive with 22 threads. Presence must be `pgrep -x` or pid-scoped. (`terminal-bench.sh` is already pid-scoped and immune.) |

**Protocol for the next campaign** (recon 3, derived from measured noise, **not yet validated by
running it**): repo-wide `flock`; **ABBA** arm ordering, never AABB (the box drifted loadavg 10 → 24 →
9 inside 12 minutes); statistic = `arm_i − mean(base_before, base_after)` (SD = 1.22σ vs 1.41σ for a
single trailing baseline, and it is the only form that removes drift); settle ≥60 s **with a
stationarity check**; minimum reps **per axis** — threads n=1, ports n=3, app RSS n=5, WindowServer CPU
**n=9 floor**, WindowServer ports **no n closes it**; tear down and re-verify the floor between arms.

### 9.6 The two cheaper rungs, both unevaluated — this is now the top of §7

**(i) The 8 render knobs are LIVE and have never been measured.** §7.1 gated them on "re-measure after
a recycle". **That gate is now satisfiable and nobody has walked through it:** the knobs were written
**06:50Z**, iTerm2 pid 591 **started 11:46:52** — the entire app and every `PTYSession` in it is
post-write; `scripts/iterm2-perf-parity.sh` returns **`match=9 drift=0 unset=0`**; and a live 5 s
`sample 591` shows two knobs working on the exact mechanisms the SSOT names — `__sysctl` = **8**
samples (against 803 samples doing `__sysctl` ×387 pre-change ⇒ `fastForegroundJobUpdates=false`
landed) and `drawForegroundForBackgroundRunArrays` = **3** (⇒ `DimInactiveSplitPanes=false` landed, the
slow dimmed-text path is gone).
**But the knobs have a measured ceiling:** the same post-knob profile reads
`iTermTextDrawingHelper` = **247** call-graph frames vs `iTermMetalDriver` = **110** — the legacy CPU
glyph path still carries **~69% of drawing frames**, which is the 1.39-core main-thread bottleneck, and
**no knob in the set addresses it**. Note also that "iTerm2 is at ~83% CPU" is **not evidence in either
direction**: five interleaved second-samples of pid 591 gave **52.6, 112.3, 112.6, 101.5, 101.3%** — a
60 pp swing inside 20 seconds — against an MDD of 30.4 pp at n=1.

**(ii) Plain tmux was dismissed on a defect that does not exist.** §5b rejects it because *"every tmux
pane shares ONE iTerm2 UUID … no resolver can recover an id that was never allocated."* All three
required primitives were tested live in an isolated tmux 3.6a server (own socket, torn down):

```
tmux list-panes  -F '#{pane_id}'                    → %0        # (1) opaque pane id
tmux split-window -t %0 -h -P -F '#{pane_id}'       → %1        # (2) create adjacent, learn id
tmux display -p  -t %1 '#{pane_tty}'                → /dev/ttys050   # (3) id → tty
```

The objection is to keying on `ITERM_SESSION_ID` — which §4 counts as a **free** port for kitty
(`→ $KITTY_WINDOW_ID`) and a **fatal** one for tmux (`→ $TMUX_PANE`). **Same call sites, same work,
opposite verdict.** Nor does the `-CC` evidence bear on plain tmux: the 2960 → 3263 MB result is
*control mode*, where iTerm2 allocates a native session per tmux pane. **Plain tmux is ONE iTerm2
session for N panes** — which is simultaneously (a) the cheap grouping §1 credits only to kitty and
(b) the configuration in which the ≤5-panes-per-tab Metal cap **stops binding at all** (§9.3 measured
that cap directly). And the integration cost runs the *other* way: the Claude Code binary ships
**`TmuxBackend` (39 symbols) and a persisted `preferTmuxOverIterm2` flag**, and ships **no kitty
backend** (§5a) — so kitty forfeits a native backend that tmux keeps.

### 9.7 Safety record

- **One incident.** M2's teardown reaped "all descendants of the app pid" and **killed 4 foreign
  Ghostty pane processes** belonging to another agent's earlier probe, closing their 2 windows.
  Ghostty (pid 584) survived and no operator work was in it — it had 0 windows at boot and every
  surface since has been an agent probe — but this violated *"only tear down terminals YOU launched"*.
  A `PRE_DESC` snapshot-and-exclude guard was added immediately after and reported "foreign descendants
  EXCLUDED: 0" on the two subsequent arms, i.e. **the guard is present but has never had a foreign
  descendant to exclude — untested against the condition it exists for.** Same for an EXIT-trap
  teardown added after a loadavg abort left 18 loaded panes live.
- **Ghostty is one shared process** — `pkill -x ghostty` would take foreign surfaces with it. Teardown
  must always be by window id.
- **The operator's iTerm2 was never written to.** pid 591 untouched from boot through session end,
  same 3 windows; `iTermServer` pid 1067 alive.
- **Ceilings held.** Peak footprint across all arms: 24 panes / 119 threads / 63 processes / 8 windows,
  against 512 threads / 64 panes / 16 windows / 64 processes. No escalation ladder was run anywhere;
  every slope is a two-or-three-point fit inside the cap. `kern.num_taskthreads` = 16,384 and
  `kern.num_threads` = 81,920 were **read from sysctl, never probed** — note the 11:46 panic occurred
  at **8,368 threads in one task, ~51% of the documented per-task limit**, and the failure mode was a
  **spinlock-timeout panic, not `EAGAIN`**. That is a finding in its own right: the practical ceiling
  is roughly half the documented one and it does not fail safe.

### 9.8 Where the answer stands after this session

| | before | after |
|---|---|---|
| kitty vs WezTerm | on **threads** (~7/pane) | on **loaded app CPU** (2.6×). The thread rationale is retired — WezTerm is 4.00/pane and its threads cost nothing measurable. |
| kitty vs Ghostty | unmeasured | **kitty**, on loaded app CPU (2.9×) and threads (0.11 vs 4.89/pane). Ghostty eliminated. |
| **kitty vs iTerm2** | asserted | **still unmeasured** — and the single iTerm2 datapoint in the cheap layout matched kitty within ~10% on CPU *and* threads, with void load telemetry. |
| §1 "the cap is protecting you" | inferred from source | **conclusion holds, mechanism half-refuted**; the cap itself is now confirmed by direct measurement |
| "windows are the 2.35× unit" | headline | **ordering survives; magnitude unreproducible, the pane null is underpowered, and the cost relocates into the app on real terminals** |
| migration | recommended after §6.1 closes | **do not start.** Two cheaper rungs (knobs, plain tmux) are live/available and unevaluated, and the port is ~3× the advertised size. |

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

> **UPDATE 2026-07-31 PM — the adversarial phase ran, and it returned.** Three refuters attacked the
> three most load-bearing claims in this document (§§1, 2, 4/5) and **all three came back REFUTED**
> — see §9.4. The all-Metal counterfactual named above as unrefuted has now also been **run** (§9.3).
> The two that remain genuinely untouched are **kitty's multi-hour behaviour** (which moved
> *backwards* — the 12 h evidence was destroyed by the reboot) and **kitty under real Claude Code**
> (never attempted, and the cheapest open item in the document).

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

⚠ **2026-07-31 PM: every instrument above has at least one measured defect — see §9.5 before
believing any per-pane figure it prints.** The most severe: `terminal-bench.sh` **cannot see iTerm2**
(`pgrep -x` rc=1 against live pid 591) and emits `verdict=NO-DATA` for the incumbent; both scripts
compute per-pane figures by dividing app-wide totals by the *requested* pane count, with no baseline
subtraction and no measured denominator; and `terminal-bakeoff.sh` holds no lock, so concurrent arms
silently interleave. Also note `window-census.swift`'s `layers=N` column counts distinct **CGWindow
Z-order values, not CALayers** — reading it as a CALayer count would falsely close §6.5.

Related: `iterm2-freeze-30-sessions-2026-07-30.md` · `gpu-vs-cpu-lag-2026-07-29.md` ·
[[capability-initialized-is-not-capability-used]] · [[positive-control-the-denominator]] ·
[[load-is-not-a-function-of-session-count]] · [[decision-moved-out-of-the-guarded-unit]]
