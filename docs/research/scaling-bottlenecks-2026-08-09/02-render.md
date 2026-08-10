# 02 · Render — the "first wall to 150" is an average divided by a pane count, and it does not bind

**Measured 2026-08-09 23:15 → 2026-08-10 06:45, this box (10 cores: 8P+2E, `sysctl hw.perflevel*`).**
Instruments: `top -l N -s 1` second-sample-onward means (never `ps %cpu`, a lifetime average — the
same rule `scripts/render-census.sh:17-20` states); `kitten @ ls`; `kitten @ load-config -o`;
kitty `--debug-rendering` occlusion events. **No config file was edited, no operator window was
closed, no operator pane was touched.** Every controlled measurement ran in a *separate kitty
instance* (`--instance-group ccprobe`) that was torn down at the end (`pgrep -f 'ccprobe|spin.py'`
= 0); the operator's kitty (pid 600) was never modified and finished as it started, 3 OS windows,
frontmost app Dia.

---

## 1 · Verdict

**Render does not bind at 150, and the 140-pane wall is not a measurement.** `3.75 cores` and
`~140 panes` are both pure arithmetic on one number: `150 × 0.025 = 3.75` and `3.5 ÷ 0.025 = 140`
(verified exactly). That `0.025 cores/pane` is `0.42 ÷ 17` — a **total divided by a pane count**,
i.e. an average of a *largely fixed* cost, published and then re-multiplied as if it were a
marginal. The marginal is 3–5× smaller, and at the design point (150 resident / ~10 active) it is
two orders smaller, because **an idle pane draws nothing and a pane that is not on screen draws
nothing.**

| | plan §S6-UPDATE §6 | measured here |
|---|---|---|
| render at 150 | **3.75 cores (107% of the 3.5 alarm floor)** | **0.2–0.5 cores** at 150-resident/10-active; **2.2–2.6 cores** in the absurd worst case of 150 simultaneously VISIBLE and ACTIVE panes |
| binds at | **~140 panes** | **~226–440 panes**, all visible AND all active; never at the design point |
| rank | **FIRST wall** | **not a wall.** Below memory, below burst survival |

Three separate defects produce the 3.75: (1) a fixed cost divided by panes and re-multiplied;
(2) the census that supplies the alarm floor **does not count kitty at all**; (3) it counts **100%
of WindowServer** as terminal render, on a box with four displays and a browser running at 73% CPU.

---

## 2 · Attribution — where the "render" cores actually are

Controlled probe workload = `spin.py 20 frame`: each pane redraws a 20-line × 60-char frame at
**20 Hz** (~24 KB/s/pane). That is **heavier than a real Claude Code pane**, which redraws a 1–3
line spinner/token-counter at ~10 Hz when working and nothing at rest — so every per-pane number
below is an **upper bound** on a real CC pane. (Corroborated: the operator's real 18-pane fleet
measured 0.0054–0.008 cores/pane of kitty, inside the probe's 0.011 upper bound — §4.)

| Component | cores/pane (or per unit) | Measured / inferred | Evidence |
|---|---|---|---|
| **Idle pane, visible, child writes nothing** | **~0.0001** (8 panes = **0.001 cores** total) | measured | `P2_probe-8-idle-panes` → `kitty_probe=0.1%` at 8 panes; 1 pane read `0.0%` |
| **Cursor blink** | **0 — already off** | measured (config) | `~/.config/kitty/kitty.conf` → `cursor_blink_interval 0`. The canonical idle-terminal draw source is disabled fleet-wide |
| **Statusline (`~/.claude/statusline.sh`)** | **0 in the render term** | inferred + measured | `settings.json.statusLine.command`; it is a bash fork whose CPU lands on `bash`, not on kitty/WindowServer. It cannot appear in `render_cores`, which sums only kitty+WS+iTerm2 |
| **Active pane DRAW, inside an already-drawn OS window** | **~0.004** | measured | same-run pair: 4 animators = `7.0%`, 8 animators = `8.8%` in ONE OS window ⇒ `(8.8−7.0)/4.5 ≈ 0.4 %/pane` |
| **Per DRAWN OS WINDOW, fixed** | **~0.05 cores** | measured (derived) | `7.0% − 4.5×0.4% ≈ 5.2%`. Cross-check: 4 animators in **4** OS windows = `9.5%` vs the same 4 in **1** = `7.0%` |
| **VT parse / pty read (paid even when NOT drawing)** | **~0.004** | measured | 8 animators hidden = `3.0%`; background tab = `3.7%`; SIGSTOPped = `0.0%`. So parse ≈ 34–42% of an active pane's kitty cost and survives occlusion |
| **WindowServer attributable to terminal draw** | **0.002–0.009** | measured, wide | probe drawing vs not-drawing, pooled 4 rounds: WS `36.9` vs `29.7` ⇒ Δ`7.2` for 8 heavy panes. The tightest-controlled arm (animate vs SIGSTOP, window state unchanged) gave Δ`1.7` |
| **WindowServer NOT attributable to the terminal** | **0.20–0.42 cores, flat** | measured | 4 displays: built-in 3456×2234 + **3× DELL S2725QC 5120×2880 @60 Hz** = **~52 Mpx** composited (`system_profiler SPDisplaysDataType`). Concurrent browser: `Dia 13.7% + Browser Helper 45.4% + 14.3%` (`top -l 2 -o cpu`) |

**The single most load-bearing line:** an idle pane costs ~nothing, and 8 of them cost 0.001 cores.
The plan's model charges each of them 0.025.

---

## 3 · Occlusion, hiding and background tabs — this decides the 150-resident topology

kitty is damage-driven and **stops drawing whatever is not on screen**. Mechanism confirmed in the
shipped binary before it was measured: `strings kitty.fast_data_types.so` →
`glfwSetWindowOcclusionCallback`, `GLFW_ICONIFIED`, `update_window_visibility`, and the live log
line `OSWindow %llu occlusion state changed, occluded: %d`. kitty's own docs state the damage model
("updates to the screen typically require sending just a few bytes to the GPU",
<https://sw.kovidgoyal.net/kitty/performance/>).

Every row below is the **same 8 animators at 20 Hz**, only the visibility changes. State was
verified from kitty's own occlusion log, never assumed.

| State | kitty CPU | vs visible | Verified by |
|---|---|---|---|
| Visible, foreground tab, 1 OS window | **8.9%** (8.7/9.3/8.7, 3 rounds) | — | `occluded: 0` in `probe2.log` |
| **OS window HIDDEN** (`resize-os-window --action=hide`) | **3.0%** (2.8/3.1/3.1) | **−66%** | `occlusion state changed, occluded: 1` |
| **BACKGROUND TAB** (same window, another tab focused) | **3.7%** (paired foreground reading `8.3%`) | **−55%** | `kitten @ ls` → `tab 1 ACTIVE False panes 8` |
| Animators SIGSTOPped (control) | **0.0%** (0.0/0.0/0.0) | −100% | `ps -o stat` → `T` |

Three consequences:

1. **A pane not on screen costs only its parse.** The residual 3.0–3.7% is pty-read + VT-parse +
   scrollback maintenance for 8 panes each writing 24 KB/s. A *real* resident-but-idle CC session
   writes ~nothing, so its hidden cost is ~0 (the idle-pane row of §2 measured 0.0%).
2. **kitty tabs are free residency.** Only the ACTIVE tab of each OS window draws. 150 sessions can
   be 150 panes across a handful of OS windows with only the focused tab of each rendering.
3. **Minimize is unnecessary.** Natural occlusion by another window already flips the state — the
   probe went `occluded: 1` on its own, 2 seconds after launch, simply because other windows sat on
   top of it. No fleet-wide window-management discipline is needed to collect this; it is the
   default behaviour of a stacked desktop.

---

## 4 · Linearity — sublinear in panes, superlinear in OS WINDOWS

The plan's model is `cost = panes × 0.025`. Measured, the render unit is the **drawn OS window**,
not the pane.

| Config (identical 20 Hz animators) | kitty CPU | Reading |
|---|---|---|
| 4 animators, **1** OS window | **7.0%** | same run, same instance |
| 8 animators, **1** OS window | **8.8%** | **+100% panes ⇒ +26% CPU** — strongly sublinear |
| 4 animators, **4** OS windows | **9.5%** | **half the panes, 4× the windows ⇒ +36% CPU** |

⇒ kitty renders **one frame per OS window**, whose cost is dominated by a fixed per-frame term
(~0.05 cores) with a small per-pane increment (~0.004 cores). Splitting the same work across more
OS windows multiplies the fixed term. WindowServer, over the same two configurations, did not move
(`35.7` at 4 windows vs `36.2` at 1 window) — consistent with a compositor whose cost is set by
total pixels and refresh, not by client count.

**Real-fleet slope (uncontrolled, reported with its confound).** The operator's fleet grew 9 → 18
panes across the session, both times in 3 OS windows:

| | panes | WindowServer | kitty (pid 600) | total |
|---|---|---|---|---|
| 23:15 | 9 | 22.8% | 9.7% | **0.325 cores** (0.036/pane) |
| 06:43 | 18 | 41.6% | 14.6% | **0.561 cores** (0.031/pane) |

kitty's own slope across that pair is **0.0054 cores/pane** with a ~0.048-core intercept — inside
the probe's upper bound and *below* the plan's 0.025. WindowServer's apparent +82% is **not
attributable to panes**: the two snapshots are 7.5 h apart, the window count never changed (which
the per-window model says is what matters), and the later sample was taken while `Dia` + two
`Browser Helper` processes were consuming 73% CPU. The controlled arm bounds 8 heavy panes'
WindowServer contribution at Δ1.7–7.2 points; 9 real panes moving WS by 18.8 points is ~10× that
and is exogenous. **This is the one number in this document I cannot pin, and §8 names the
measurement that would.**

---

## 5 · Levers — every row measured, and the config levers are weak

Changed live on the **probe instance only**, via `kitten @ load-config -o` (verified as a working
channel: `sync_to_monitor` responded immediately). No config file was written.

| Lever | Measured Δ (8 animators, 1 OS window) | Risk / cost | Verdict |
|---|---|---|---|
| `cursor_blink_interval 0` | **already set** — 0 further gain | none | **spent.** The obvious idle-draw lever was harvested before this session |
| `repaint_delay 16 → 200` | **8.9% → 7.1% = −20% kitty** (≈ −0.018 cores at 8 heavy panes) | up to 200 ms added draw latency on every keystroke echo | **weak.** −20% of the *smaller* half of the render term ≈ −5% of render cores |
| `repaint_delay` via `load-config -o` | **no effect** (16/50/100/200 → 8.7/8.4/8.7/8.9) | — | **must be set at LAUNCH.** The reload path silently does not apply it; a "we tuned it" claim made by reloading is false |
| `sync_to_monitor yes → no` | **8.7% → 11.3% = +30% kitty** | tearing | **NEGATIVE lever — do not.** The default is already the cheaper setting |
| `input_delay 5` (current) | not isolated | — | dominated by the above; not worth a wave |
| `scrollback_lines 2000` (kitty default) | not measured | memory, not CPU, at this size | **unmeasured** — named in §8 |
| **Panes into background TABS** | **8.3% → 3.7% = −55%** | pane not visible | **strong, free, no config change** |
| **Occlude / hide the OS window** | **8.9% → 3.0% = −66%** | pane not visible | **strong; happens by default** on a stacked desktop |
| **Consolidate OS windows** (4 → 1, same panes) | **9.5% → 7.0% = −26%** | fewer independent windows to arrange | **strong, and it is a topology choice, not a setting** |
| Sleep/disconnect the 5K displays | not measured directly | operator's displays — not an agent's call | **largest single WS term** (52 Mpx of the 0.2–0.42 flat cores) but out of scope |

**The shape of the answer: config tuning cannot move this wall, and does not need to.** The three
strong levers are all topology, all already available, and none requires a line of code.

---

## 6 · Two defects in `scripts/render-census.sh` — the instrument the alarm floor is quoted from

**D1 — kitty is not counted. On a kitty fleet, `render_cores` is WindowServer alone.**
`scripts/render-census.sh:129-149`:

```awk
if (cmd == "iTerm2")       { ipid = $1; icpu += cpu }
if (cmd == "WindowServer") { wcpu += cpu }
```
```bash
RENDER_CORES="$(awk -v a="${ITERM_CPU:-0}" -v b="${WS_CPU:-0}" 'BEGIN{printf "%.2f", (a+b)/100}')"
```

There is no `cmd == "kitty"` arm anywhere in the file (`grep -n kitty scripts/render-census.sh`
returns only binary-resolution and pane-count code). Live proof, this box:

```
{"verdict":"OK","render_cores":0.43,"iterm_cpu_pct":0.0,"windowserver_cpu_pct":42.8,"panes":18,...}
```

`iterm_cpu_pct 0.0` — iTerm2 is gone. The same 5 s window measured kitty at **14.6%**, so the true
WS+kitty figure was **0.58**, not the reported **0.43** — a **26% under-report**. This is the exact
class of defect the file's own header documents having already fixed once for the *pane* column
("CORRECT and USELESS: it measures 0 iTerm2 panes truthfully while the fleet it was built to watch
is elsewhere", `render-census.sh:210-214`). The pane column was migrated to kitty on 2026-07-31;
**the CPU column was not.**

**D2 — 100% of WindowServer is charged to "terminal render".** WindowServer is the whole-desktop
compositor. Concurrently measured on this box: `Dia 13.7% + Browser Helper 45.4% + Browser Helper
14.3%`, against 4 displays totalling ~52 Mpx. A census row that reads `top_consumer WindowServer
42.8%` and calls it render is naming the browser and the monitors, and then dividing them by the
pane count. **The two defects push in opposite directions**, which is why the number looked
plausible: D1 removes ~26% of the real terminal cost, D2 adds a browser-and-display term that is
several times larger than everything the terminal does.

Both are gauge fixes, not behaviour changes: add a `cmd == "kitty"` arm, and split the emitted JSON
into `terminal_cores` (kitty + iTerm2) and `compositor_cores` (WindowServer), so the alarm is
keyed on a quantity panes can actually move.

---

## 7 · Topology at 150 resident / ~10 active — how many panes must be VISIBLE

**Today, measured:** `kitten @ ls` → 3 OS windows / 3 tabs / **18 panes**, 18 sessions — a strict
1 pane : 1 session : 1 tab-less window layout, 5+5+8 panes per window. Every pane is in the active
tab of its OS window, so today the fleet draws **everything it owns**. That is the worst possible
arrangement, and it is what the 0.025 average was measured on.

**At 150 resident / 10 active, the fleet needs ~3–6 drawn OS windows and ~10 drawn panes** —
because a session needs a *pty and a pane*, not a *visible* pane, and both non-drawing states are
free (§3). One concrete arrangement, all of it available today with zero new code:

```
3 OS windows  ×  25 kitty tabs  ×  2 panes   = 150 panes, 150 sessions
   drawn:     3 OS windows      ×  2 panes   =   6 panes actually rendering
```

Cost of that, from §2's measured terms:

```
3 drawn OS windows × 0.05                       = 0.15 cores
6 drawn active panes × 0.004                    = 0.024
144 non-drawn panes × ~0 (idle CC writes nothing) = ~0.00
                                          kitty ≈ 0.17 cores
+ WindowServer flat (displays + browser)        = 0.20-0.42 cores  ← does not scale with sessions
                                          TOTAL ≈ 0.4-0.6 cores
```

Against a 3.5-core alarm floor that is **6-9× above it**, and against the plan's forecast of 3.75.

---

## 8 · The corrected wall, and what is still unknown

**Worst case that still respects the measurements** — all 150 panes simultaneously VISIBLE *and*
ACTIVE, in 3 OS windows, using the upper-bound WS slope:

```
kitty      0.048 + 150 × 0.0054                    = 0.86 cores
WS (term)  150 × 0.002-0.009                       = 0.30-1.35 cores
WS (flat)  displays + browser                      = 0.20-0.42 cores
                                             TOTAL = 1.4-2.6 cores      (alarm floor 3.5)
```

**Binds at ~226-440 panes** — `(3.5 − 0.25) ÷ 0.0144` with the pessimistic WS slope,
`(3.5 − 0.25) ÷ 0.0074` with the tight one — versus the plan's **140**. Either way it lands
**behind memory (~190 sessions)** and behind burst survival, and it is unreachable at the design
point by a factor of ~6.

**Re-ranked, replacing the §S6-UPDATE §6 block:**

```
memory     35 / ~45 GB      78%   binds at ~190 sessions   ← FIRST
render      0.4-0.6 / 3.5   ~14%  binds at ~226-440 VISIBLE ACTIVE panes; ~0 at the design point
ptys      152 / 511         30%   binds at ~509 panes
load      0.46 / 20          2%   binds at ~4,300 sessions
```

**Not established (named, not hedged):**

- **WindowServer's true pane slope.** Bounded 0.002-0.009 cores/pane across four A/B arms; the
  operator's uncontrolled 9→18 growth implies 10× that and is confounded by a browser at 73% CPU.
  **The measurement that settles it:** run `render-census` (with the kitty arm added) at a fixed
  pane count while toggling *only* the browser — or take a paired reading with all Dia windows
  closed. That is an operator action; it is not an agent's call to close their browser.
- **`scrollback_lines` pressure.** Not measured. All probe panes had shallow scrollback. A pane
  with 2000 lines of retained history may cost more to re-render on resize/reflow than a fresh one;
  reflow, not steady draw, is where it would show.
- **The fourth cell at scale.** Every controlled reading used ≤8 probe panes. The per-OS-window
  fixed term and per-pane increment are measured over 4→8; extrapolating to 150 panes *in one
  window* assumes the slope holds, which no reading here proves. (It is the plan's own generating
  defect — an 8× extrapolation from a small sample — so it must be said out loud rather than
  repeated.)
- **Whether `repaint_delay` at launch is worth a fleet change.** −20% of kitty ≈ −5% of render
  cores, against added input latency. Measured, but the trade is a judgment, not a number.

---

## 9 · Adversarial pass — what I assumed, and what checking it changed

| Assumption I started with | What checking it produced |
|---|---|
| "3.75 cores is a measurement of a loaded box" | **False.** `150 × 0.025 = 3.75` and `3.5 ÷ 0.025 = 140` exactly. Both are arithmetic on the one average. No reading at or near 140 panes exists anywhere in the program |
| "`render-census.sh` measures what the alarm floor is about" | **False, twice** (§6): kitty absent from the CPU sum, WindowServer charged whole |
| "The per-pane cost is a pane cost" | **False.** It is a per-drawn-OS-window cost with a small per-pane increment; 4 panes in 4 windows beat 8 panes in 1 |
| "Panes must be visible to host a session" | **False.** Background tabs cost the same as hidden windows (3.7% vs 3.0% on identical load) — 150 sessions can live in tabs |
| "Occlusion needs a fleet window-management policy" | **False.** The probe self-occluded 2 s after launch under other windows; kitty logs the transition. It is the desktop default |
| "Config levers (`repaint_delay`) are the lever" | **Weak** (−5% of render cores), and `load-config -o` **silently fails to apply it** — a tuning claim made that way would be false |
| "`sync_to_monitor=no` would reduce CPU" | **Inverted.** +30%. The lever runs the wrong way |
| I had not looked at the display topology at all | **Four displays, ~52 Mpx**, three of them 5K@60. This is the dominant WindowServer term and it has nothing to do with sessions — it would read identically with zero panes open |
| I had not considered non-terminal WindowServer clients | **Browser at 73% CPU** during the second real-fleet sample; it invalidates the uncontrolled 9→18 slope that would otherwise have been reported as linearity |

---

## 10 · Reproduce

```bash
# per-state kitty CPU, second-sample means (probe pid from `pgrep -f instance-group\ ccprobe`)
top -l 13 -s 1 -stats pid,command,cpu | awk '/^Processes:/{b++} b>=2 && $1~/^[0-9]+$/ {...}'
# occlusion state, verified not assumed
kitty --debug-rendering --instance-group ccprobe ...   # → "OSWindow N occlusion state changed, occluded: 1"
kitten @ --to unix:/tmp/kitty-ccprobe resize-os-window --action=hide|show
kitten @ --to unix:/tmp/kitty-ccprobe focus-tab --match id:N       # background-tab arm
kitten @ --to unix:/tmp/kitty-ccprobe load-config -o sync_to_monitor=no   # applies live
kitty -o repaint_delay=200 ...                                     # only applies at LAUNCH
# the census's own reading, kitty-blind:
CC_RENDER_LOG=/tmp/rc.jsonl bash scripts/render-census.sh --json --no-append
```

Scratch artifacts (sampler + animator, disposable):
`/private/tmp/claude-501/-Users-chrisren-Development--worktrees-wt-crash-rootcause-2026-08-09/e0670908-e54b-46b9-986b-7900a68f9de8/scratchpad/{rs2.sh,rsample.sh,spin.py,probe*.log}`
