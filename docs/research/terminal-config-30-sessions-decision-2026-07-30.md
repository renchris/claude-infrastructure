# Decision: stay on iTerm2, change the LAYOUT, do not fork and do not migrate

**Recommendation (one sentence):** Stay on iTerm2 unforked and re-lay the fleet as **6 windows × 5 panes** instead of 3 windows × 10 panes — that single zero-cost change flips all 30 visible panes from CPU rasterization to Metal (the gate is `sessions.count >= 6` **per foreground tab**, not per process), which is the same outcome a fork, a tmux migration, or a terminal switch would buy, at 0 engineer-days instead of 5–32.

---

## 1. The premise is shaky — read this before weighing any spend

**A terminal switch would not have prevented the freeze.** The freeze mechanism was WindowServer at 92.7–99.9% of one core *while iTerm2 itself measured 0.0% CPU*. The proximate producer was **98 invisible zero-tab iTerm2 windows leaking ~7.2/hour** (98 over the 13.55h iTermServer lifetime — the "~12/hr" figure came from a 5m07s window containing roughly one event), minted by **the repo's own `scripts/handoff-fire.sh`**, whose `resolve_headless_anchor()` returned `1` for both "iTerm2 has zero panes" and "probe failed", with the caller discarding the status. That is a repo bug, terminal-agnostic in cause.

Four corrections to the tidy version of that story, all from adversarial verification:

1. **The fix is landed but UNPROVEN, not "holding."** `cabf80f7` is on `origin/main` and the live symlinked layer is byte-identical. But iTerm2 was restarted at **22:04:55**, the fix landed at **22:25:30** — 20.6 minutes of post-restart runtime *with the bug still present* and **zero windows leaked**. The zero-growth predates the fix. The fixed path has **never executed once**: `handoffs.jsonl` is untouched since 21:39 and no `anchor probe INCONCLUSIVE` refusal exists in any log. The 8 bats assertions are all *source-shape greps* — they prove the text changed, not that no window is minted. The 98→2 window drop was the **restart**, as the commit message itself says. And the congestion precondition (30–44 sessions, load > 2.0/core) is currently absent, so the system isn't even being exercised.
2. **The leak is not provably the whole freeze.** The research doc's own §6 lists *"the 98 zombie windows cause the 94% CPU"* as **NOT ESTABLISHED** — WindowServer swung **52% → 98% at constant window count**. Three things changed simultaneously at the restart: windows cleared, **the Metal layout flipped** (12/9/6 panes-per-tab → ~1/tab, i.e. Metal OFF for 27 of 38 sessions → ON), and two 5Ks went 120Hz → 60Hz. Metal suppression on 71% of sessions is a **co-equal named candidate**, not a footnote.
3. **The canvas baseline is ~9.6%, not ~24%.** The properly controlled within-experiment measurement (iTerm2 *quit*, same displays, same minutes) is **9.6%** of one core. The "flat ~24%" was measured with iTerm2 actively rendering, ~50 minutes later, at 10 sessions, and is **not flat** — 19 samples give mean 28.2%, sd 6.14, range **23.2–44.8%**. At real load WindowServer reads 51.7 / 63.8 / 71 / 92.7–99.9%. So: canvas ≈ **10%** of the freeze; iTerm2-attributable ≈ **90%** — but that 90% splits across leak + Metal-off layout + refresh rate, unresolved.
4. **The cause is two-factor, not purely ours.** The repo's dispatcher was the *emitter*. iTerm2 supplied the *accumulator* (zero-tab windows that survive `close()` returning success — both `close w` and by-id close returned success and left the window alive) and the *amplifier* (a serialized Python API). And the hardcoded `maxNumberOfSplitPanesForMetal = 6` cliff is **purely an iTerm2 property, triggered by exactly the layout the operator's binding "~30 simultaneously visible" constraint demands.**

**Net premise:** the freeze was ~90% iTerm2-side but the dominant *lever* inside that 90% is a **layout property you control for free**, not an architecture you must escape. Spending 22–32 engineer-days on a terminal you have never measured, to fix a burn whose largest identified component is a 5-pane threshold, would be buying the wrong thing.

---

## 2. The one genuine iTerm2 ceiling, re-derived from the shipped binary

From `otool -arch arm64` on the shipped 3.6.11 (not master source — the paths differ):

- `-[PTYTab updateUseMetal]`: `ldr x8,[sp,#0x8]` / `cmp x8, #0x6` / `b.hs` → **`b.hs` is unsigned ≥, so `count >= 6` kills Metal for the whole tab.** Metal requires **≤ 5 panes per tab**.
- The key-window gate is **compiled off** in the shipped artifact: `bl _objc_msgSend$isKeyWindow` at `0x100491a2c` has its return clobbered by the very next instruction; reason code 20 (`NoFocus`) is never stored. **Unfocused windows keep Metal.**
- `isForegroundTab` at `0x100470e80` is a pure per-window tab-selection compare — **a 1-tab window's tab is always foreground.** Background tabs are always CPU.
- The occlusion gate (`usingIntegratedGPU && approximateFractionOccluded > 0.5`) is **dead code on this box**: measured `MTLDevice` is `isLowPower=0, hasUnifiedMemory=1`, single device. **Even overlapped windows keep Metal.**

**Consequence:** 3 windows × 10 panes = **0 of 30** Metal-eligible. 6 windows × 5 panes = **30 of 30**. This matches the profiles exactly — and note those profiles are *not* a GPU-vs-CPU comparison, they are **gate-admitted vs gate-refused**:

| Layout | `iTermTextDrawingHelper` : `iTermMetalDriver` | What it actually measures |
|---|---|---|
| 42 panes / 5 windows (~8.4/tab) | 361 : 72 | Metal **refused** on every tab — the legacy path alone |
| 44 sessions / 41 tabs (~1/tab) | 7 : 100 | Metal **admitted** on ~1–5 panes/tab |
| Current live (tabs of 2 and 4) | 9 : 158 | Metal admitted, 17.6:1 for GPU |

---

## 3. Decision table

Scored on the six binding constraints. Numbers, not adjectives. `n/m` = not measured.

| Option | 30 visible / 3 monitors | All panes GPU | Freeze / leak / crash at scale | Source-modifiable | Upfront days | Ongoing burden |
|---|---|---|---|---|---|---|
| **iTerm2, relayout 6×5** ✅ **RECOMMENDED** | **Yes** — 6 win × 5 panes, ~70 cols × ~44 rows each (Ink verified good at 51 cols) | **30/30** Metal (count 5 < 6; foreground tab; key-gate off; occlusion gate dead) | Leak fix landed `cabf80f7`, **UNPROVEN** (path never executed). 30 Metal panes in one process **never profiled** | n/a | **0** | **0** |
| iTerm2, status-quo 3×10 | Yes | **0/30** — `b.hs` on count 10; = the measured 361:72 profile | Same leak exposure **plus** the CPU-rasterization path that was live during the freeze | n/a | 0 | 0 |
| iTerm2 + nightly, `MetalSynchronizedDrawing` + `MetalRowOutputCacheEnabled` | Yes | 30/30 (with 6×5) | Targets the *actual* bottleneck (main-thread drawable acquisition); nightly tags land ~daily | n/a (unshipped flags, not in 3.6.11) | **0** (one `defaults write`, revert = `defaults delete`) | nightly churn |
| **Fork iTerm2** (cap → 11) | Yes, folded into 3 windows | 30/30 but via 3 tabs of 10 → **600 drawable acquisitions/s/window through ONE static `com.iterm2.get-drawable` serial queue**, `dispatchPrecondition(.onQueue(.main))`, blocking ≤16.7 ms/pane/frame — n/m | **2× blast radius**: any 1 of 10 sessions tripping any of 33 reasons (ligatures, transparency<1, flashing tab bar, illegal view size) drops the whole tab to CPU | Yes, GPL-2.0; patched lines unchanged 8 years | ~1 (patch) + **n/m** (first `make setup` + `paranoid-deps` + `Development`; 19 submodules + Rust) | **~12 rebuilds/yr** + TCC/AppleEvents re-grant + Keychain re-grant per rebuild (use a stable self-signed cert, never ad-hoc) |
| **iTerm2 + plain tmux** (3 servers) | Yes — 3 windows × 1 native pane; tmux tiles 10/monitor at ~70×44 | **3/3 native sessions Metal** (count 1 < 6) — entire canvas through 3 MTKViews | tmux server is **single-threaded** (`ps -M` = 1 thread), **68% of one core** under a 30-pane blast; mitigate with `-L mon1/2/3`. Memory **hard-capped** by `history-limit` (~320 B/line vs iTerm2's ~5 KB/line) | Yes (tmux stable, already installed, 200-line tuned conf) | **~5–10** (derived, not measured) | Low — `$TMUX_PANE` cannot be shared or stale, retiring the whole ISID bug class |
| iTerm2 + `tmux -CC` | Yes | **0/30** — 1:1 native `PTYSession` per tmux pane, **no tmux exemption in the Metal gate** | Claude Code's fullscreen renderer is **explicitly incompatible** with `-CC` (mouse wheel dead, double-click corrupts state) | — | — | **DISQUALIFIED** |
| **kitty** | Yes, no cap | All panes; **1 GL context per OS window**, one shared atlas, one buffer swap. But **OpenGL 3.3 Core** via `AppleMetalOpenGLRenderer` compat layer — n/m on 52 Mpx | n/m — **not installed**. Control channel: dedicated `talk_thread`, `PEER_LIMIT 256` poll-multiplex (structural, not load-tested); commands still funnel into one Python `boss` on the main thread | Yes, **GPL-3.0** (C + Python) | **22–32** (median 26) | Second treadmill |
| **WezTerm** | Yes, no cap | All panes, 1 render context/window — but shipped **default `front_end` is OpenGL/glium, not wgpu/Metal**; needs explicit `front_end = "WebGpu"` | n/m. Every accepted cli connection is `spawn_into_main_thread` — a lighter version of iTerm2's pattern, not an escape | Yes, MIT (Rust) | 22–32 | Second treadmill; `cli list --format json` carries **no env** → needs an external pane_id map |
| **Ghostty** | Yes, no cap | Per-pane: own renderer **thread**, own `CVDisplayLink`, own `MTLDevice`+queue, own `CALayer`, **`swap_chain_count = 3` with a full grayscale+color atlas copy per frame slot** ⇒ 120 atlas textures at 40 panes; 674 MiB VRAM reported at 20 windows | **Highest risk of reproducing the exact failure class.** Its two mitigations (QoS demotion when not visible; display link only for visible **and** focused) **never engage** — the operator's panes are all visible by requirement | Yes, MIT (Zig + Swift) | 22–32 **+ a from-scratch identity resolver** (no per-pane env var; pane capture only via `perform action "write_scrollback_file:copy"` → **global clipboard** + temp file, must be serialized across 30–44 panes, clobbers the clipboard, leaks a temp dir per capture) | Second treadmill |
| **Rio** | Yes | All panes, 1 Sugarloaf/window, **native Metal** default | — | Yes, MIT (Rust) | **Unbounded** — 0 of 8 control capabilities; no IPC, no socket, no remote control | **DISQUALIFIED** |
| **Alacritty** | **No** — no split panes by design | — | — | — | — | **DISQUALIFIED** |

---

## 4. The recommended configuration, concretely

### 4.1 Topology — 6 windows × 5 panes = 30 visible, 30 Metal

Per DELL S2725QC: `5120×2880` physical, **"UI looks like 2560×1440"** (exact 2× integer HiDPI — no fractional-scaling render penalty). At Monaco 12 with spacing 1 (~7.2 × ~15 pt cells) that is ~355 cols × ~96 rows per monitor.

**Per monitor: two windows stacked vertically (each full-width, half-height), each holding 5 side-by-side vertical splits.**

```
┌─ Monitor N ──────────────── 2560 × 1440 logical ────────────────┐
│ Window A (full width, top half)                                  │
│ ┌────────┬────────┬────────┬────────┬────────┐                  │
│ │ pane 1 │ pane 2 │ pane 3 │ pane 4 │ pane 5 │  ~70c × ~44r each │
│ └────────┴────────┴────────┴────────┴────────┘                  │
│ Window B (full width, bottom half)                               │
│ ┌────────┬────────┬────────┬────────┬────────┐                  │
│ │ pane 6 │   7    │   8    │   9    │  10    │                  │
│ └────────┴────────┴────────┴────────┴────────┘                  │
└──────────────────────────────────────────────────────────────────┘
        × 3 monitors  =  6 windows, 30 panes, all Metal
```

Derivation: 2560 ÷ 5 = 512 pt ÷ ~7.2 = **~70 cols**; 1440 ÷ 2 = 720 pt, minus title + tab-bar chrome ≈ 670 pt ÷ ~15 = **~44 rows**. **Measure this after setup** — chrome height eats rows and is the one number here I computed rather than observed. The Ink TUI was verified rendering correctly (logo glyphs, box rules, `❯` input, mode line, statusline, 24-bit truecolor) at **51 cols**, so ~70 has real headroom. The built-in Retina XDR carries the desk session and any overflow; it is not needed for the 30.

**Why this and not 3 windows × 10:** `count >= 6` → `b.hs` → Metal off for the entire tab. 5 clears it; 10 does not. Every window's single tab is by definition its foreground tab, the key-window gate is compiled off, and the occlusion gate is dead on this GPU — so all six windows render on GPU simultaneously, focused or not, overlapped or not.

**Do not use tabs to reach 30.** Background tabs are always CPU, unconditionally.

### 4.2 Settings to change

| # | Change | Command / edit | What it buys |
|---|---|---|---|
| 1 | **Relayout to 6 × 5** | manual (above) | **30/30 panes on Metal** instead of 0/30. The single highest-value change in this document. 0 days. |
| 2 | **Cap the dispatcher at 5, not 6** | `export CC_FIRE_MAX_PANES=5` (consumed at `scripts/handoff-fire.sh:3617`) | Today's default is 6, and the guard is `npanes -ge cap` — so at 5 panes it *permits* a split, producing **6 panes and silently killing Metal for that tab.** A cap of 5 refuses the 6th and holds the gate. Keep the constant **at the chokepoint**; do not re-implement it in callers. |
| 3 | **Prove the leak fix** | `CC_FIRE_HEADLESS_ANCHOR=off` (returns state 2) + a headless no-anchor fire; expect a logged `anchor probe INCONCLUSIVE` refusal **and no new window** | Converts `cabf80f7` from *structurally asserted* to *behaviorally verified*. Currently the fixed path has executed **zero times**. |
| 4 | **Close the second caller** | `scripts/handoff-fire.sh:3806` still uses `_a="$(resolve_headless_anchor 2>/dev/null \|\| true)"` | Preview-only so it cannot mint a window, but it re-swallows the stderr the fix deliberately stopped discarding and prints "would fall back to a fresh window" on INCONCLUSIVE — i.e. the dry-run still *documents the leaking behavior*. |
| 5 | **Keep all three 5Ks at 60 Hz** | already done | Roughly halves the compositing rate over 29.5 Mpx of the 52 Mpx canvas. |
| 6 | **Throttle the chrome-headless churn** | audit `scripts/banner-shots.sh:45,256,287` (`resolve_headless_chrome` → `"$CHROME" --headless`) | Measured at **130–222 spawn/exit cycles per minute**, each minting a `NoDisplaySleepAssertion` (41,797 cumulative); only 2 alive at any `ps` sample ⇒ **pure churn**. Repo-owned, terminal-agnostic, and the leading (though unproven) candidate for the unattributed half of the CoreAnimation storm. |
| 7 | *(Stage 1 only)* Nightly + drawable-queue fix | `defaults write com.googlecode.iterm2 MetalSynchronizedDrawing -bool true`<br>`defaults write com.googlecode.iterm2 MetalRowOutputCacheEnabled -bool true` | **These keys do not exist in 3.6.11** — a `strings -x` scan of the shipped binary returns only `disableMetalWhenIdle`, `metalDeferCurrentDrawable`, `metalRedrawPeriod`, `metalSlowFrameRate`, `showMetalFPSmeter`, `throttleMetalConcurrentFrames`. They exist in master and move drawable acquisition **off the main thread onto the private render queue** — exactly the funnel identified as the real ceiling. Testing the nightly is a **zero-fork** experiment. |

### 4.3 What NOT to do, and why

**Do not fork.** The iterm2-ceiling axis argued the fork is cheap because "the per-pane thread rationale is obsolete" and "extra Metal panes cost none." **Both were refuted.** The 2022 commit `28b98381f` merged only the *driver's* dispatch queue; the per-pane **thread moved to the view** — `iTermMetalView.swift:31` holds a per-instance `CVDisplayLink`, created and started per view (494–501), running its callback on its own CoreVideo thread. And each pane still costs: an **unconditional `NSLog` on every display-link tick** (`iTermMetalView.swift:797`, string confirmed in the shipped binary — 30 panes × 60 Hz = **1,800 NSLogs/s**), a main-queue `draw()` dispatch, a main-thread `currentDrawableWithTimeout` blocking up to 16.7 ms/frame, plus a per-driver `MTLCommandQueue`, texture pool and frame-in-flight budget. The shared serial queue is now itself a *contention* point — merging removed parallelism without removing work.

Raising the cap to 11 does **not add Metal panes**; it only lets you fold the same 30 into 3 windows. You trade 3 fewer NSWindows for WindowServer against **2× the all-or-nothing blast radius** and a 2× denser main-thread drawable funnel that nobody has measured. That is a bad trade bought with ~12 rebuilds/year — precisely the second treadmill that was ruled out.

**Do not adopt `tmux -CC`.** It allocates a full native `PTYSession` per tmux pane, so the Metal gate applies unchanged (there is no tmux exemption; the sibling `_isDraggingSplitInTmuxTab` branch proves tmux tabs flow through the same code). Separately, Claude Code's fullscreen renderer is **explicitly incompatible** with `-CC`. Note also that the prior-work claim "`-CC` does not bound memory (+303 MB for 60k lines)" was **refuted**: control-mode sessions use the dedicated `tmux` profile, minted with `KEY_SCROLLBACK_LINES` **hardcoded to 1000** (`ProfileModel.m:188-189`), a ~2.4 MB/pane ceiling — 125× below the reported figure. The +303 MB was the **window leak** (reproduced live: one leaked window = **+126 MB phys_footprint that never returns**, with zero scrollback written), measured on `ps` RSS which overstates iTerm2 by **2.85×** (RSS 2250 MB vs `footprint` 790 MB).

**Do not go to Ghostty first.** It is the one alternative that *repeats* iTerm2's per-pane architecture, with a 3-deep swap chain duplicating the font atlas per frame slot, and its two saving mitigations are both keyed on panes being invisible or unfocused — which the operator's binding constraint forbids. Its AppleScript surface is genuinely good (19 commands, stable per-terminal UUIDs, verified by live execution on 1.3.1) and pane capture *is* possible via `perform action "write_scrollback_file:copy"` (correcting the "hard blocker" finding), but that route rides the **single global clipboard**, must be serialized across 30–44 panes, clobbers the operator's clipboard, and leaks a temp dir per successful capture. If a terminal migration ever happens, it is **kitty**.

---

## 5. Where the axes conflicted — adjudicated

| Conflict | Adjudication |
|---|---|
| **iterm2-ceiling**: "you're already running 30 Metal panes at 5×6, the fork is unnecessary" vs the **verified binary**: 3×10 = **zero** Metal | Both resolve the same way: **the fork is unnecessary, but not for the stated reason.** The relayout — not the existing layout — is what delivers 30 Metal panes. The fork's only remaining benefit (folding into 3 windows) is outweighed by 2× blast radius and an unmeasured main-thread funnel. **Recommend the relayout, reject the fork.** |
| **multiplexer**: "tmux precedes and largely subsumes the terminal switch" vs **root-cause-recheck**: "the zero-cost relayout does the same thing" | **Root-cause-recheck wins on ordering.** Both collapse the Metal gate; the relayout costs 0 days and the tmux path costs ~5–10 plus the ⌘D handoff-invariant rework. tmux's *additional* wins (control channel, non-stale pane ids, 15× better scrollback memory) are real but are **not freeze fixes** — the multiplexer axis says so itself. **tmux is Stage 2, not Stage 0.** |
| **multiplexer**: "prior work (task #59) rejected plain tmux — per-pane addressing is architecturally absent" | **The premise was falsified by direct experiment.** Three plain-tmux panes in one iTerm2 session have distinct TTYs (`/dev/ttys013/015/016`) and stable ids (`%0/%1/%2`); `send-keys -t %1` delivered to the **non-focused** pane with both siblings as clean negative controls. What is absent is an *iTerm2 UUID* — a **transport coupling** (0 `send-keys` sites in the repo; `cc-notify:343` keys solely on `${ITERM_SESSION_ID##*:}`), not an architectural limit. Also: nothing was actually adopted — all four resolver artifacts are absent from `origin/main`, the branch is 564 commits behind, task #62 is still `in_progress`. **Plain tmux is back on the table, at Stage 2.** |
| **multiplexer**: "tmux control channel is 3–4 orders of magnitude better; concurrency helps, it does not queue" | **Refuted twice.** Healthy `it2 session list` is **481 ms**, not minutes (the "5–8 min" was the *spacing of piled-up clients in a collapsed state*, not a latency, and that pathology's root cause is fixed). Real ratio: **79× serial / 97× amortized ≈ 2 orders**, not 3–4. And tmux **does** queue — `ps -M` shows a single-threaded server, ~0.73 ms/call of serialized work, linear scaling past N=100. Also ~240 ms of iTerm2's 481 ms is pure **Python CLI import**, not API serialization. Directionally tmux still wins; the 3–4-order framing must not be used to justify spend. |
| **migration-cost**: "~147 call sites / 74 executable files" | **Corrected to ~100 sites.** 37 it2-CLI invocations (not 38), **33** osascript invocations (not 58 — 16 are comments, 8 are `command -v` probes, 1 an assignment), ~30 ISID reads across 26 files. Critically, **only 12 of the 33 osascript calls carry `tell application "iTerm2"`** — the other 21 (13 `display notification`, 4 `delay`, 2 System Events, 1 clipboard, 1 Dia) survive any migration untouched. **True iTerm2-coupled surface ≈ 79 sites.** Executable file count is 65 shebang-bearing non-test files (14 of the "74" are prose/plists; 5 real executables hide under `docs/activation/`). |
| **migration-cost**: "AppleScript adds what the it2 CLI cannot do" | **Refuted.** `it2 session list --json` performs the identical window→tab→session walk with `window_id`+`tab_id` per row; `it2 window new` exists (and the axis counts it); and the repo's own `skills/resume-sessions/REFERENCE.md:76` calls osascript `write text` **unreliable** for a live Claude TUI, with `tests/handoff-fire-tab-window-typing.bats:37,48` actively forbidding it. AppleScript here is **redundant legacy transport over the same API**, not a second capability surface — so the migration surface is smaller than estimated. This pushes the 22–32 day figure toward its **low end**, but that figure remains the only **inferred** number in the axis. |

---

## 6. What we still don't know

### Unexplained CoreAnimation residue — named explicitly, not papered over

- **The storm does not currently reproduce.** A live 20-second `log stream --predicate 'process == "WindowServer"' --level debug` captured **40,570 records with ZERO matches** for "Defer Lock", "Timer delayed", or any `coreanimation|CA::` pattern. The persisting 58/s figure (down from 117/s) is from the earlier observation window.
- **The `chrome-headless-shell` attribution for "the other half" is INFERRED, never measured** — from client class, rate order-of-magnitude, and time-window coincidence only. A definitive answer requires capturing the stream **while the storm is live**.
- **`Timer delayed by 49957.96s` (13.9 h) is genuinely unexplained**, and the leading hypothesis was **refuted**: `pmset -g log` reports *"Total Sleep/Wakes since boot: 0"*, so no sleep event exists to explain a 13.9-hour timer starvation. **This is the best frontier-hole candidate in the whole investigation.**
- **WindowServer's mach ports are still climbing monotonically post-restart** (4558 → 4567 over ~2 min) — the same signature that preceded the freeze. Unexplained.
- **No call-graph for WindowServer's baseline.** `sample 889` requires sudo. **This is the single highest-value next measurement.**
- **The hot-corner test was a NON-VERDICT.** The displays never slept — `displaysleep 0` on both power sources, 12 live `caffeinate -i -t 300` processes (each a child of a `claude.exe`), plus a chrome assertion every ~0.3 s. "It froze anyway with displays asleep" rules **nothing** in or out.
- **120 Electron/Chromium helpers (Cursor + Dia) holding 16.5 GB RSS** are first-class CoreAnimation clients nobody has counted (one helper: 435 M / 32 threads / 481 ports at 10.7% CPU).
- **The Gatekeeper/TCC/font stack is entirely unexplored**: XprotectService 29.3%, fontd 10.7%, syspolicyd 9.2%, tccd 7.7%, `kernel_task` 24–29%, 1,137 live processes, 543 launchd entries. The exec-rate measurement **failed** (PIDs had wrapped near 99999, giving a false delta of 0), so this is supported by consumer CPU% only.
- **Ink damage-rect rate to the compositor was never measured** — no read-only instrument available without sudo/Instruments.

### iTerm2 / Metal

- **Nobody has ever profiled 30 Metal panes in one iTerm2 process.** Both existing profiles are gate-admitted vs gate-refused, **not** a GPU-vs-CPU comparison.
- **Unmeasured and decision-relevant:** whether 30 independently-presenting `CAMetalLayer`s make WindowServer **better or worse** than legacy drawing. This is the one plausible downside of the recommendation, and it points at the exact resource that froze the box. **Cheap decisive test, no fork:** run 6 windows × 5 panes (all Metal) vs 6 windows × 7 panes (all legacy) and `sample` WindowServer in both.
- `disableMetalWhenIdle` is at default (no Metal pref key is set on this box) and will drop any tab whose 5 sessions are **all idle** — 6 Metal-flip domains, thrash cost unmeasured. `willEnableMetal` can also fail on context allocation.
- Build wall-clock for `make setup` + `make paranoid-deps` + `make Development` is **unmeasured** (nothing was built).
- `iTermMetalView_full.swift` also declares `@objc(iTermMetalView)`; target membership in `project.pbxproj` was never confirmed.

### Alternatives

- **None of kitty / WezTerm / Ghostty / Rio is installed** (Ghostty was installed for verification and removed). **Zero measured per-pane RSS, VRAM, or WindowServer CPU for any candidate.** The claim that per-window rendering collapses the WindowServer burn is a **structural inference from source**, not a measurement.
- kitty's macOS OpenGL-on-`AppleMetalOpenGLRenderer` path is unmeasured at 3 windows × ~14 panes on 52 Mpx. Its commands still dispatch into a single Python `boss` on the main thread — `PEER_LIMIT 256` is a structural argument, not a load test. Whether `get-text` is safe against a live alternate-screen Ink app is unverified. A **mixed-scale display setup would mint a second FontGroup + atlas** (all four displays are currently 2×, so moot today).
- WezTerm's `cli list --format json` carries **no env**, so env-keyed matching needs an external `pane_id →` session map.
- Multi-monitor / many-window behavior was verified from source for **no** candidate; a known-issue survey at high pane counts was run only against Ghostty's tracker.
- **Not examined at all:** Warp (closed source ⇒ fails source-modifiable *by inference, not by check*), Wave / Tabby / Hyper (Electron), Contour. **zellij: DROP** — pre-1.0 after five years, would require redoing the Ink validation tmux already has plus a second addressing shim.

### Migration cost

- **The 22–32 engineer-day figure is INFERRED** — a decomposition estimate, never calibrated against observed velocity. (346 of 1,295 commits = **26.7% of this repo's entire history** mention iterm/it2/osascript/pane/split, but the days those consumed were never reconstructed.)
- **The weakest line is the 3–5 days for re-deriving iTerm2's three interceptions on a new backend.** Each was found by a *production incident* (2026-06-09 close-modal; 2026-07-25/26 API deadlock; ⌘W profile), so by construction the equivalent set on an unfamiliar backend **cannot be enumerated in advance.**
- The 46-suite / 1,240-test / 18,775-LOC rewrite figure is a **static classification**, never run against a stubbed backend.
- **Non-code coupling is counted but uncosted:** `config/iterm2-perf.keys` (8 required `defaults` render knobs as machine-state SSOT), `install.sh:625` (`PreventEscapeSequenceFromClearingHistory` as an autonomous-resume prereq), 4 launchd plists referencing iTerm2 paths, 84 docs files. None has an automatic analogue elsewhere.
- `feat/tmux-isid-resolver` (564 commits behind main) was **not** verified to still apply.

### tmux

- **The decisive end-to-end number was never taken:** no real Claude Code TUI ran in plain tmux at 10 panes/monitor with iTerm2 CPU / WindowServer CPU / typing latency measured against today's baseline. Every throughput claim is component-level on synthetic load.
- Whether **one** Metal render thread per window sustains ~10 concurrently-streaming Claude TUIs is unmeasured.
- **The fullscreen-renderer lever is blocked and unconfirmed:** `/tui fullscreen` / `CLAUDE_CODE_NO_FLICKER=1` renders only visible messages and keeps memory flat, and is explicitly aimed at "terminal emulators where rendering throughput is the bottleneck, such as … tmux, and iTerm2" — but the pinned `claude` is **2.1.114** and the feature references 2.1.17x–2.1.21x. Which track the live 30–44 sessions run on was **never determined**.
- Separately: Claude Code exposes **no** spinner-disable, reduced-motion, or FPS-cap knob. A `strings` scan of the arm64 binary returns exactly `CLAUDE_CODE_EXIT_AFTER_FIRST_RENDER`, `CLAUDE_CODE_TMUX_TRUECOLOR`, `CLAUDE_CODE_TUI_JUST_SWITCHED`. **This is a hard negative and a legitimate upstream feature request.**

---

## 7. Staged path — every gate is a measurable trigger

### Stage 0 — this week. ~0 engineer-days. Do all of it.

1. Relayout to **6 windows × 5 panes** (§4.1).
2. `export CC_FIRE_MAX_PANES=5` at the chokepoint.
3. **Force the third state** and confirm the refusal: `CC_FIRE_HEADLESS_ANCHOR=off` + a headless no-anchor fire → expect `anchor probe INCONCLUSIVE` in `handoffs.jsonl` **and no new window**.
4. Fix the surviving `|| true` at `handoff-fire.sh:3806`.
5. Throttle `scripts/banner-shots.sh` chrome-headless churn (130–222 spawn/exit per minute today).
6. **Instrument, so the next verdict is not another non-verdict:** log hourly `osascript -e 'tell application "iTerm2" to count windows'` alongside the live pane count, and a `top -l 2` WindowServer sample, for a full multi-hour dispatch wave at 30+ sessions.
7. Take the one measurement that closes the biggest gap: **`sudo sample 889`** (WindowServer) during a real 30-session wave, plus the free A/B — 6×5 (all Metal) vs 6×7 (all legacy), `sample` WindowServer in both.

**Advance to Stage 1 if ANY of these fires:**
- **T0-a (leak):** iTerm2 window count exceeds (live pane-hosting windows + 2) at any point in a ≥4-hour dispatch wave.
- **T0-b (compositor):** WindowServer sustains **> 60% of one core for > 5 minutes** with ≤ 30 panes and every foreground tab at ≤ 5 panes.
- **T0-c (gate silently refusing):** `sample <iterm2-pid> 5` at 30 panes shows `iTermTextDrawingHelper` > `iTermMetalDriver`.
- **T0-d (main-thread funnel):** keystroke-to-echo latency **> 250 ms** at 30 panes, or a visible beachball, with iTerm2 process CPU below one core.

### Stage 1 — only on a Stage-0 trigger. ~1–3 days. No fork, no migration.

- **On T0-c:** identify which per-session gate trips, using the 33-value `iTermMetalUnavailableReason` enum. Known trip-wires: ligatures (`PTYSession.m:8847`), `transparencyAlpha < 1` (8901–8912), illegal view size (8859), flashing tab bar (`PseudoTerminal.m:13489`), and `disableMetalWhenIdle` at default. Each drops the **whole tab**.
- **On T0-d:** install the **nightly** (no fork) and set `MetalSynchronizedDrawing` + `MetalRowOutputCacheEnabled`. These move drawable acquisition off the main thread onto the private render queue — the exact funnel identified as the real ceiling. A/B typing latency. Revert = `defaults delete`.
- **On T0-b with iTerm2 near 0% CPU:** the burn is **not glyph rendering**. Go after the CoreAnimation residue, not the terminal — capture `log stream` *while the storm is live*, and count the 120 Electron helpers and the Gatekeeper/TCC stack as first-class clients.
- **On T0-a:** the leak is not fixed. Re-open `resolve_headless_anchor` with runtime evidence, and treat the iTerm2 side (zero-tab windows surviving a successful `close()`) as an upstream bug to file.

### Stage 2 — plain tmux pilot on ONE monitor. ~5–10 days. Only if Stage 1 fails.

**Entry trigger (must be measured, not assumed):** Stage-1 instrumentation shows **iTerm2's own per-pane cost** is the binding constraint at 30 panes — i.e. the iTerm2 process sustains **> 100% of one core** — **or** the Metal gate provably cannot be satisfied at the required visibility.

- **Plain tmux, never `-CC`.** Three iTerm2 windows (one per monitor), each a single native pane, each attached to a **separate tmux session on a separate server** (`-L mon1/mon2/mon3`) to restore 3-way parallelism against the single-threaded server. Set `aggressive-resize on`; do **not** share one session across three clients (`window-size latest` + `aggressive-resize off` would thrash on every focus change).
- **`brew upgrade tmux` first.** 3.6a honors DECSET 2026 but does not **respond to the DECRQM 2026 query** until 3.6b; Claude Code probes at startup and therefore never emits synchronized output → flicker. `terminal-features` currently shows no `:sync` while the binary contains the capability. 3.7b is bottled.
- Re-point the **7 verbs** at the byte-identical chokepoint (`~/.claude/bin/it2` ≡ `bin/it2-wrapper`): `list → list-panes -aF`, `send → send-keys -t %N`, `close → kill-pane -t %N`, `focus → select-pane/-window`, `split → split-window -t %N`, `read → capture-pane -p -t %N`, `id → $TMUX_PANE`.
- Re-key identity on **`$TMUX_PANE`**, which tmux sets per-pane and which cannot be shared or stale — this **retires the entire `tmux-panes-inherit-server-iterm-session-id` bug class** and makes the parked `feat/tmux-isid-resolver` unnecessary rather than a prerequisite.
- **The real rework bill is the ⌘D handoff invariant**, not the addressing: `scripts/handoff-fire.sh` makes split-right the standing default anchored on `$ITERM_SESSION_ID` and was re-fixed three commits ago (`d6b417e9`). It must move to `tmux split-window -t $TMUX_PANE`, and the repo's own memory records that this exact invariant **regressed once with the suite 100% green** — so record the guarded property, or the regression is unfalsifiable.

**Abort Stage 2 if:** any single monitor's tmux server exceeds **80% of one core at 10 panes**, or the Ink TUI corrupts at the achieved pane width (~70 cols; verified good at 51).

### Stage 3 — terminal migration. 22–32 engineer-days (median 26; corrected surface pushes toward the low end).

**Entry trigger:** **both** the Stage-0 relayout **and** the Stage-2 tmux pilot fail to hold 30 visible panes without freeze, *and* the failing resource has been positively identified as iTerm2-internal (not WindowServer, not the CoreAnimation residue, not the Gatekeeper stack).

**Target: kitty.** One GL context per OS window, one shared glyph atlas, all panes in a single pass ending in one buffer swap; **no pane-count threshold exists anywhere in its source**; control channel on a dedicated `pthread` with 256-peer `poll()` multiplex; all 8 required capabilities with JSON output; and an identity story **strictly stronger** than `$ITERM_SESSION_ID` (`kitty @ launch --env CC_SESSION_ID=x` then `--match env:CC_SESSION_ID=x`, with `launch` returning the new window id on stdout and `close-window` bypassing every confirmation path).

**Before committing, close these three:** measure kitty's OpenGL-on-Metal compat path at 3 windows × ~14 panes on the 52 Mpx canvas; load-test 30–44 concurrent `kitty @` clients against the single Python `boss` on the main thread; and verify `get-text --extent scrollback` against a **live** alternate-screen Claude Code TUI. GPL-3.0 constrains redistribution of a patched build — irrelevant for personal use.

**Second choice: WezTerm** (architecture sound, but shipped default `front_end` is OpenGL/glium — you would be opting into `front_end = "WebGpu"` — and its cli dispatches every connection onto the GUI main thread). **Not Ghostty** (per-pane architecture, mitigations that cannot engage for this workload, no per-pane env var, clipboard-mediated pane capture). **Not Rio** (no control plane at all). **Not Alacritty** (no splits).

---

**Bottom line:** the expensive options all buy the same thing — every visible pane on the GPU — that a free relayout already delivers, and none of them addresses the residue that is still unexplained (a 13.9-hour timer delay with zero sleep events, monotonically climbing WindowServer mach ports, and an unreproduced CoreAnimation lock-imbalance storm whose leading suspect is one of our own scripts spawning 222 headless Chromes a minute). Change the layout, prove the leak fix actually executes, instrument, and let a named trigger — not a hunch — authorize any spend.