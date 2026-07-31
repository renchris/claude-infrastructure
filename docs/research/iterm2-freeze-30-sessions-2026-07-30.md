# iTerm2 freeze at ~30 concurrent Claude Code sessions — 2026-07-30

**Question (operator).** iTerm2 was frozen and inoperable after a few hours away; sessions were
expected to keep running. Root-cause it, find any memory pressure / leak to fix, and make 30+
concurrent Claude Code sessions in iTerm2 sustainable.

**Answer, one line.** It is **not memory pressure**. The GUI died because **WindowServer saturated**
— it holds a full core (92.7–99.9% sustained), 1.75 GB, and a mach-port table that grows without
bound (4711 → 4743 in ~10 min) — while **iTerm2 itself sat at 0.0% CPU**. The proximate defect is a
population of **iTerm2 window objects that leak at ~12/hour and cannot be destroyed** — `close`
returns success and the window remains. 98 of them were live at the time of writing.

Machine: MacBookPro18,2 · Apple M1 Max (8P+2E = 10 cores, 32-core GPU) · 64 GiB · macOS Darwin
24.6.0 · iTerm2 3.6.11.

---

## 1. Memory pressure is RULED OUT — with the denominator

Measured 21:53:45 PDT, with 39 live sessions:

| Metric | Value | Reading |
|---|---|---|
| PhysMem | 48 G used / **15 G unused** | headroom |
| Swap | **0.00 M total, 0.00 M used** | swap never engaged this boot |
| Compressor | 1190 M | |
| **Compressor segments in use** | **69,522 / 1,629,615 = 4.3%** | far from the exhaustion axis |
| Load avg | 5.38 | 10 cores |
| CPU | 20.8% user / 7.0% sys / **72.2% idle** | machine is not CPU-bound |

The 4.3% segment figure matters specifically: the 2026-07-30 **02:18** kernel panic on this box was
**compressor-segment exhaustion** (`100% of segments limit (BAD)` with ~20 GB free — see
[[compressor-segment-exhaustion-panic]] and commits `d6ffb7cd`, `f8142d88`). That axis is currently
green and is **not** what froze the UI.

**Per-session footprint is flat, not growing.** `top` MEM for `claude.exe` clusters tightly at
**208–230 MB** across sessions of widely differing age (4–13 h). Note `ps` RSS overstates badly here
(600–950 MB) because it double-counts shared pages — the ~220 MB figure is the one to use. 30
sessions ≈ 6.6 GB, comfortably inside 64 GiB.

> Method note: `ps %cpu` is a **lifetime average** and misread this box ~4× (it showed WindowServer
> at 39.6% when the live value was 92.6%). Every CPU number in this doc is the **second sample** of
> `top -l 2`. Same trap recorded in [[capability-initialized-is-not-capability-used]].

---

## 2. What actually froze: WindowServer

| Measurement | Value |
|---|---|
| WindowServer CPU | **92.7 – 99.9% sustained** (5 independent samples) |
| WindowServer RSS | 1.74 GB |
| WindowServer mach ports | **4711 → 4743 in ~10 min, monotonic** |
| **iTerm2 CPU** | **0.0%** |
| iTerm2 mach ports | 1437 → 1470 in the same ~10 min |

**iTerm2 at 0.0% while WindowServer holds a core is the decisive attribution fact:** the burn is not
terminal glyph drawing. The two port counts climb in lockstep (+32 / +33), tracking window creation
at roughly ~16 ports per leaked window on each side.

100% CPU in `top` = one core. WindowServer's compositing critical path is effectively serialized, so
pegging it does **not** show up as a busy machine (72% idle) — it shows up as *the UI stops*, while
every background process keeps running normally. That is exactly the operator's report: the sessions
did keep working; the window server could no longer draw.

### CoreAnimation lock-imbalance storm

98.3% of all WindowServer log output is one message:

```
[com.apple.coreanimation:Render] Defer Lock context 0x… unlocked but lock count is not zero (was 4)
```

- **42,663 messages in 5 min = 142/s**, across only **33 distinct contexts**.
- Lock counts climb monotonically: `was 4` (37,389) → 5 → 6 → 7 → 8 → 9 → 10 → 11 → 12 → **13**.
  An unbalanced lock that is never released.
- Companion errors: `__CFRunLoopModeFindSourceForMachPort returned NULL … livePort: 1049355`
  (runloop waking on a port with no source — ~9/min, a symptom not the burner), and
  `[com.apple.coreanimation:WindowServer] Timer delayed by 49957.96s` — a CoreAnimation timer
  **13.9 hours late**. All 13 "Timer delayed" records extrapolate to the same origin instant,
  **07:47:23**, i.e. one timer scheduled once and never fired since.

**Self-inflicted-measurement control (mandatory, and it passed).** My own AppleScript polling
enumerates ~100 windows and could plausibly have *caused* the storm. A/B:

| Window | Defer Lock rate |
|---|---|
| While I was polling | 142.2 /s |
| **Zero osascript from me (3 min)** | **117.1 /s** |

My probing accounts for **≤18%**. The storm is autonomous.

---

## 3. The leak: iTerm2 window objects that cannot be destroyed

**Inventory (21:53, two independent enumerations):**

```
sessions=39  tabs=9  windowsWithTabs=8  zeroTabWindows=98
```

- The operator's 8 real windows carry IDs spread across the whole history: `238, 2136, 2212, 2249,
  9548, 12323, 16272, 16671`.
- All 98 zombies sit in **one contiguous recent block: 16335–16738**. ~400 IDs consumed for 98
  survivors ⇒ ~300 windows were created *and* released in the same span; these 98 were not.
- Each is `visible=false` and cascaded at the classic +29 px macOS offset (197 → 226 → 255 → 284 …).

**They survive `close`.** Two methods, both reporting success, both leaving the window alive:

```
close w  (iterated)      → "closed=16335";  16335 still present
close (first window whose id is 16335) → stillExists=true
```

Session count stayed **39 before and after every attempt** — nothing was lost, and nothing was
freed. This is why they accumulate: there is no scripting-API path that releases them.

**Rate, under a clean control** — monitors killed, zero osascript for 5m07s:

```
T0 21:47:16 → 103 windows / 95 zero-tab
T1 21:52:23 → 104 windows / 96 zero-tab      ⇒ +1 per 5 min ≈ 12/hour
```

12/hour × "a few hours away" ≈ 50–70 new zombies per unattended stretch; ~280/day. The 98 present
are consistent with the ID-block span.

> Earlier in the session I measured "+3 in 2 minutes (~90/hr)" **while my own monitors were running**.
> The controlled number is 12/hr. The uncontrolled one is not trustworthy and is recorded here only
> so it is not re-derived as fact.

### Producer — NOT yet identified (open)

Three code paths in this repo can create an iTerm2 window:

| Path | Loaded? |
|---|---|
| `scripts/handoff-fire.sh:3539` (`spawn_frontmost`, the `--window` surface) | on demand |
| `scripts/limit-recover/lr-reset-poller.sh:172` (`spawn_gui`) | **loaded**, `com.reso.lr-reset-poller`, 600 s |
| `scripts/boot-resume-launch.sh:71` | **NOT LOADED** |
| `scripts/desk-invariant.sh` | **NOT LOADED** |

Evidence that partly exonerates each:

- `spawn_frontmost`'s autonomous branch deliberately omits `activate` so the window is created **in
  the background** — which does match `visible=false`. But `spawn` is called at line **3840**, i.e.
  *after* the refusal gates at 3832–3833, so the day's **162 refused** fires exit before creating
  anything. Only **1** record carries `"surface":"window"` today.
- A 600 s poller can mint at most 6/hr; the measured rate is ~12/hr.

So the producer is **not established**. It may not be this repo at all — 98 windows that survive
`close` is equally consistent with an iTerm2-internal object leak whose creation path is iTerm2's
own. A catcher (`/tmp/catch2.sh`) was left running to correlate the next birth with concurrent
process activity.

**Prior-art caution.** The `--window` escape hatch caused a documented regression — *"174 anchorless
fires in one day, each its own iTerm2 window; 0 on any prior day"*
([[decision-moved-out-of-the-guarded-unit]]). That specific hole is **closed** on trunk:
`bin/cc-wave-plan:728` now asserts the headless plan emits `--split-right` and **never** `--window`.
Do not re-chase it without re-measuring.

---

## 4. Compounding factor: 27 of 38 sessions render on the CPU

iTerm2 3.6.11 **suppresses Metal per-TAB once a tab holds ≥6 sessions.** Re-verified this session on
the **arm64** slice that actually executes on this M1 Max (the earlier record was ambiguous because
`otool` defaults to the x86_64 slice of the universal binary):

```
otool -arch arm64 -tvV /Applications/iTerm.app/Contents/MacOS/iTerm2
  -[PTYTab updateUseMetal] … 0000000100491c34   cmp   x8, #0x6
```

Live topology — sessions per tab:

```
WINDOW 1: 12      ← ≥6, Metal OFF
WINDOW 2:  9      ← ≥6, Metal OFF
WINDOW 3:  4, 1
WINDOW 4:  6      ← ≥6, Metal OFF
WINDOW 5:  4
WINDOW 6:  1
WINDOW 7:  1
```

**27 of 38 sessions draw glyphs on the CPU rasterizer.** The lever is *"≤5 sessions per tab"*, never
"enable Metal" — Metal is already enabled and is being overridden per-tab.

## 5. Compounding factor: a ~52 Mpx, 4-display, 120 Hz canvas

```
Built-in Liquid Retina XDR   3456 x 2234
DELL S2725QC   5120 x 2880   (UI 2560x1440 @  60 Hz)
DELL S2725QC   5120 x 2880   (UI 2560x1440 @ 120 Hz)
DELL S2725QC   5120 x 2880   (UI 2560x1440 @ 120 Hz)
```

3 × 14.75 Mpx + 7.7 Mpx ≈ **52 Mpx of framebuffer**, two of them at 120 Hz. Display count,
resolution and refresh are the dominant WindowServer cost drivers in every public account of
WindowServer CPU. This is the load *on top of which* the window leak accumulates.

---

## 6. What is proven vs. what is not

**Measured:** memory pressure absent (15 G free, 0 swap, 4.3% segments) · per-session footprint flat
at ~220 MB · WindowServer 92.7–99.9% sustained with iTerm2 at 0.0% · WindowServer ports monotonically
rising · 98 undestroyable zero-tab windows leaking ~12/hr under control · CA defer-lock storm 117/s
autonomous with lock counts climbing to 13 · CA timer 13.9 h late · Metal suppressed on 3 of 8 tabs
covering 27 of 38 sessions · 4 displays ≈ 52 Mpx.

**NOT established — do not assert:**
1. **That the 98 zombie windows *cause* the 94% CPU.** WindowServer CPU swung 52% → 98% at
   *constant* window count, so window count does not explain short-term variance. The clean test is
   to restart iTerm2 and re-measure; it requires closing the operator's panes, so it is theirs to run.
2. **The producer** of the leaked windows (§3).
3. **The storm's onset time.** Not reconstructable: `Defer Lock` is debug-level, and debug records
   are rate-suppressed and in-memory-only. A persisted-store query returned 70 debug lines for a
   window in which the in-memory ring held 42,522. My initial hourly probes returned "1" — that was
   the **header line only**, i.e. no data, and must not be read as "zero storm all day".

---

## 7. Remediation

**Immediate (operator's call — it closes panes):**
1. **Restart iTerm2.** The only way to clear 98 undestroyable windows and reset WindowServer's leaked
   port table. This is also the decisive experiment for open question (1).

**Structural, in descending leverage:**
2. **Cap sessions per tab at 5.** Moves 27 sessions off the CPU rasterizer. Purely a layout change:
   30 sessions = 6 tabs × 5, not 2 tabs × 12/9.
3. **Drop the two 120 Hz 5K displays to 60 Hz.** Roughly halves WindowServer's compositing rate over
   29.5 Mpx of the 52 Mpx canvas. Costs nothing for terminal work.
4. **Identify and gate the window producer** (§3), then add a guard that fails loud on any surface
   choice made outside the chokepoint — the lesson already recorded in
   [[decision-moved-out-of-the-guarded-unit]].
5. **Add a zombie-window rung to `capacity-alarm.sh`.** Nothing currently watches window-object
   count; it is invisible to every existing headroom/swap/pressure rung, exactly as the compressor
   segment count was before `d6ffb7cd`. Suggested signal: `zeroTabWindows` from the §3 enumeration,
   warn at 25, page at 60.

**Explicitly NOT a fix:** adding RAM, reducing session count for memory reasons, or rebooting on a
schedule. None of them touch the compositor path, and "reboot weekly" was already retracted as
wrong on this box for the panic axis.

---

## 7a. RESOLVED — iTerm2 restarted 22:04, outcome measured

Operator authorised the restart (they could not quit it themselves — the UI was wedged). Sequence:
capture restore manifest → `kill -TERM` → verify → `open -a iTerm`.

**All 40 sessions survived the quit.** The shells are children of **`iTermServer` (pid 1362)**, not
of iTerm2 — `claude.exe → zsh → login → iTermServer`. iTerm2 exited in 2 s; `pgrep -P 1362` stayed at
40 throughout, and iTerm2 restored them on relaunch. **Quitting iTerm2 is not destructive to sessions
on this box** — a fact worth knowing before any future emergency.

| Metric | Before | iTerm2 down | After relaunch |
|---|---|---|---|
| WindowServer CPU | 92.7–99.9% | 9.6% | **17.6%** |
| WindowServer RSS | 1746 M | 1157 M | **1139 M** |
| WindowServer ports | 4743 | 3730 | 4169 |
| **iTerm2 RSS** | **2594 M** | — | **257 M** |
| Zombie windows | 98 | — | **0** |
| CA `Defer Lock` rate | 117/s | — | **58/s** |

**Metal is now actually being taken — by profile, not by flag.** Restoration landed 44 sessions
across **41 tabs** (≈1 per tab), so no tab trips the `>= 6` cap:

```
sample <iterm-pid> 4
  iTermTextDrawingHelper (CPU rasterizer):   7
  iTermMetalDriver       (GPU path):       100      ← 14:1 FOR the GPU
```
versus the prior measurement at 42 panes over 5 windows: **361 : 72, i.e. 5:1 AGAINST**. The ratio
inverted purely from layout. No config change, no fork, no patch.

**Two things this did NOT fix — both still open:**
- **The CA lock storm persists at 58/s** (down from 117/s). iTerm2 accounted for roughly half; the
  remainder is another client. So the storm is **not** solely an iTerm2 defect.
- **The producer still runs.** Caught in the act 21:59:39: `cc-dispatch --once` →
  `handoff-fire.sh --prompt-file … --account next3 --split-right`, 5 s before zombie `16745`
  appeared. Note the surface is **`--split-right`, not `--window`** — so the husk-minting defect now
  lives on the *split* path, one surface over from the closed `--window` regression. Until that is
  fixed the 98 will simply re-accumulate at ~12/hr.

**Display compositing is exonerated as the primary driver.** The operator hot-cornered the displays
to sleep before leaving, and it froze anyway. `displaysleep 0` on both AC and battery means no
*timer* would have slept them, but the manual sleep happened and did not prevent the freeze — so the
52 Mpx / 120 Hz canvas is a constant-factor aggravator, not the cause. (Operator has since set the
two 120 Hz panels to 60 Hz; that is a free win regardless, but do not credit it with the recovery —
the restart is what moved the numbers, and the two changes overlapped in time.)

## 7b. CORRECTION — the Metal rule is not "≤5 per tab", it is "≤5 panes in a FOREGROUND tab"

Upstream source settles it (`sources/TerminalView/PTYTab.m`, `-updateUseMetal`, fetched via `gh api`
— note the path moved to `sources/TerminalView/`, the old `sources/PTYTab.m` 404s):

```objc
// Limit the number of split panes using metal because each gets its own thread and I've seen
// some crazy stuff where people have over 50 split panes.
const NSInteger maxNumberOfSplitPanesForMetal = 6;
const BOOL numberOfSplitPanesIsReasonable = self.sessions.count < maxNumberOfSplitPanesForMetal;
```

**Hardcoded `const NSInteger`. No advanced setting, no preference, no defaults key** — confirmed
independently by string-scanning the shipped binary (the only Metal advanced settings are
`disableMetalWhenIdle`, `metalDeferCurrentDrawable`, `metalRedrawPeriod`, `metalSlowFrameRate`,
`showMetalFPSmeter`, `throttleMetalConcurrentFrames`). The stated reason is **one thread per
Metal-rendered pane**, and the architecture backs it: each `PTYSession` owns its own
`iTermMetalView`/MTKView (`-[PTYSession sessionViewRecreateMetalView]`), and the driver's own step is
named `acquireScarceResources`. Cost scales with **pane count, not pixels**.

**The gate I initially missed, which inverts the layout advice:**

```objc
const BOOL foregroundTab = [self isForegroundTab];
if (!foregroundTab) { _metalUnavailableReason = iTermMetalUnavailableReasonTabInactive; }
if (allowed && satisfiesKeyRequirement && foregroundTab) { useMetal = … }
```

**Only the FOREGROUND tab of a window can use Metal.** Background tabs are on the CPU rasterizer at
any pane count. Therefore **tabs are the worst container for Metal and panes are the best** — the
opposite of what §7a's restored layout (40 tabs in 1 window) produces. The 100:7 profile in §7a
measured the single foreground tab and must not be read as "all 44 sessions are on GPU".

**Full gate list (all must hold), in source order:** not dragging a tmux split · not resizing ·
`iTermPowerManager metalAllowed` (battery / low-power / unplugged) · every session in the tab allows
Metal · NOT (all sessions idle AND `disableMetalWhenIdle`) · **`sessions.count < 6`** ·
`tabCanUseMetal` · not screens-changing · not swiping tabs · **`isForegroundTab`** ·
`willEnableMetal` per session (can fail on context-allocation).

**Optimal layout for "all sessions visible AND all on GPU":**
**N windows × exactly ONE tab × ≤5 panes.** A window's only tab is always the foreground tab, so
every pane qualifies. 30 sessions = **6 windows of 5 panes** — 2 per monitor on a 3-monitor desk.
This satisfies the operator's scanning workflow (everything visible simultaneously) and the Metal
gate at the same time; they were never actually in conflict. Also keep the machine on AC, and leave
`disableMetalWhenIdle` off if idle panes should stay on the GPU (relevant precisely to the
away-from-desk case).

**Caveat worth stating plainly:** the freeze was **not** caused by CPU rasterization. iTerm2 measured
**0.0% CPU** while the UI was dead, and the CPU-heavy 361:72 profile coexisted with a healthy
machine. Metal layout is a responsiveness/efficiency win, **not** the fix for the freeze — the leak
in §3/§7a is. Do not trade away workflow to chase it.

## 8. Reusable method notes

- `ps %cpu` is a lifetime average — it misread WindowServer by 2.3× (39.6% vs 92.6%). Always use
  `top -l 2` second sample.
- `ps` RSS double-counts shared pages: the claude fleet read 15.7 GB by RSS and ~6.6 GB by footprint.
  Naming the wrong one would have manufactured a memory leak that does not exist.
- `otool -tvV` disassembles the **x86_64** slice of a universal binary by default. On Apple Silicon
  a threshold check must use `-arch arm64` or it silently reads instructions that never execute.
- **Absence in `log show --start/--end` is not absence of the event.** Debug-level records are
  in-memory-only and rate-suppressed; a header-only result reads as "1 line", not "0 events".
- A measurement that perturbs its subject needs a control. Killing my own pollers and re-measuring
  turned an alarming "90 windows/hr" into a correct "12/hr", and confirmed the CA storm was real
  rather than mine.

Related: [[compressor-segment-exhaustion-panic]] · [[capability-initialized-is-not-capability-used]]
· [[decision-moved-out-of-the-guarded-unit]] · [[load-is-not-a-function-of-session-count]] ·
[[positive-control-the-denominator]]
