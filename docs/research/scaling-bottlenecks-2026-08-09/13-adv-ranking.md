# 13 · Adversarial audit of the WALLS RANKING (not the magnitudes, the comparison logic)

**Subject.** `docs/plans/CONCURRENCY_PROGRAM.md` §S6-UPDATE §6, the four-row table and the
conclusion drawn from it:

```
render   3.75 / 3.5 cores   107%   binds at ~140 panes     ← FIRST, and already over its alarm floor
memory     35 / ~45 GB       78%   binds at ~190 sessions
ptys      152 / 511          30%   binds at ~509 panes
load     0.46 / 20            2%   binds at ~4,300 sessions
⇒ C (burst survival) and the render half of E are the live path to 150; ptys and load are not.
```

**Verdict up front: the ordering does not survive. It inverts.** Not because any single magnitude is
wrong, but because the four rows are evaluated in **four different machine states**, the two leading
rows carry **opposite-signed constant selection** (most-optimistic for memory, most-pessimistic for
render), and the render row's numerator and denominator are measured on **two different terminal
emulators, one of which is not running on this box.**

Scope note: sibling audits own re-measurement and design-point failure modes. This audit changes no
magnitude that the program has not already published. Every correction below is derivable from the
program's own text, its own instrument sources, or one bounded read-only live sample.

---

## 1 · The ranking-logic audit table

| # | Claim in the ranking | Hidden assumption | Holds? | Consequence for priority order |
|---|---|---|---|---|
| A1 | The four percentages are comparable | All four are measured in the **same machine state** | **N** | render/ptys are priced at **150 visible panes**; memory/load at **150 idle sessions, zero active**. Two different fleets. No ordering is defined over them. |
| A2 | `load 0.46/20 = 2%` ⇒ load is a non-issue | The fleet at 150 does **no work** | **N** | The design point is *150 resident + ~10 active*. 10 × 1.6 + 150 × 0.0031 = **16.5/20 = 82%**. Load moves from last to second. S6.2 *derived* the design point by saturating this term — it is at ~100% **by construction**. |
| A3 | `render 3.75/3.5 = 107%` ⇒ render is first | 150 sessions ⇒ **150 visible panes** | **N** | Phase E's own prescription is **≤20 visible panes**. At the design point render is 20 × 0.025 = **0.5/3.5 = 14%**. Render is first only in the configuration the remediation forbids. |
| A4 | `3.5 cores` is render's ceiling | An alarm floor is a failure point | **N** | `scripts/render-census.sh` header: thresholds "set ABOVE today's measured 2.0-core floor **deliberately**… speaks on REGRESSION, not on the steady state it was calibrated against." A regression tripwire in a denominator makes the percentage a statement about **knob calibration**, not about the box. |
| A5 | `0.025 cores/pane` extrapolates linearly to 150 | Render cost is **proportional to pane count** | **N** | `MACHINE_CAPACITY_V2.md:1019,1037` (M8): render is **single-thread-bound** — one iTerm2 thread at **98.7%**, 8,268 csw/s, at 5 windows/**34 panes** — ⇒ *"**PTY OUTPUT VOLUME, not pane count, is the binding term**."* The program's own prior finding refutes the model the ranking's #1 row is built on. |
| A6 | The render numerator and denominator measure one thing | Both are the same renderer | **N** | Numerator: `0.42 cores at 17 panes` = **WindowServer + kitty** (`session-capacity-ceiling-2026-08-09.md:118,134`). Denominator `3.5`: calibrated on **iTerm2 + WindowServer** at a 2.0-core floor. **107% is a ratio between two emulators.** |
| A7 | `render-census.sh` can falsify the render row | The census measures this box's renderer | **N** | `render-census.sh:129,149` — `RENDER_CORES = (iTerm2 + WindowServer)/100`, exact command match; **kitty is never summed**. Live `ps` on this box: `2 kitty, 4 kitten, 1 WindowServer, **zero iTerm2**`. Panes come from `kitty @ ls` (`:231`). **One row, two applications: panes from kitty, CPU from iTerm2.** The instrument is structurally blind to the term it exists to bound. |
| A8 | `memory 35/45 GB = 78%` | 45 GB is available to sessions | **N** | S6.2's own block: 35 (sessions) + 10 (macOS/render baseline) + 19 (burst reserve) = 64. The session ceiling is **64 − 10 − 19 = 35 GB**. The row divides by *sessions + baseline*. Corrected with **no new measurement**: **35/35 = 100%**. |
| A9 | `232 MB/session` is the memory constant | n=4 `vmmap` generalises | **N** | Same repo, same box: `MACHINE_CAPACITY_V2.md:1021` — **22.07 GB / 39 procs**, p50 **555 MB**, p95 986. Live read today: **10 claude procs, mean RSS 792 MB, max 1063**. S6-DOD-V2 (2026-08-10): active session **2.2 GB**. The ranking used the **minimum of four**, from the **smallest sample**. |
| A10 | Bursts are an *orthogonal* crash term | Bursts draw on a different resource than residency | **N** | The 19 GB burst budget is the **residual of the same 64 GB**. Wave C's admission gate can only admit into headroom the memory row leaves. At memory = 100% the residual is 0 and C is inert. Not orthogonal — **serially dependent**. |
| A11 | Load and render are separate walls | Render CPU is outside the load term | **N** | `load = mean simultaneously-runnable threads`, box-wide. 3.75 cores of WindowServer/kitty **is ~3.75 runnable threads inside the same loadavg**. The ranking spends one quantity twice and reports 2% for the budget that contains it. |
| A12 | Memory and load are independent terms | Compression is free of CPU | **N** | Compressor/`kernel_task` threads are runnable threads. Memory pressure ⇒ compressor CPU ⇒ load. The coupling exists but is **proven insufficient as protection**: §S6.6 — at the panic the memory gate term read **29.79 GB → ADMIT** while segments were at **100%**. |
| A13 | `ptys 30%`, `load 2%` are proximities | 511 and 20 are ceilings | **partly** | `kern.tty.ptmx_max=511` is a **sysctl**, raisable toward ~999; load `20` is a **gate policy constant**. Two of four denominators are knobs. Percent-of-own-ceiling ranks **how tightly a knob was set**. |
| A14 | Load "binding" is a wall | A gate refusal is a failure | **N** | Load at 100% breaks nothing; it declines spawns. It is the **mechanism**, not the failure. Ranking it alongside three physical failures is a category error — and inverted: **load at 2% means the only admission control on this box is inert at the design point.** |
| A15 | The ranking is stable under the day's corrections | Four instrument corrections were the last | **N** | See §5. A **fifth** of the same family (A7) is verifiable today and lands squarely on the #1 row. |
| A16 | ≤10 active is a property of the system | Something bounds active concurrency | **N** | Nothing does. Wave D (admit on ACTIVE concurrency) is **undecided (D7)**, and §S6.6 measures the memory gate term firing **0 times in 127 refusals**, unable to bind by construction. **The ranking assumes the outcome of the wave its own conclusion deprioritises.** Circular. |

---

## 2 · (a) Percent-of-own-ceiling is the wrong comparator — re-derived on severity × proximity × reversibility

Percent-of-own-ceiling is a **proximity** measure only, and only when the ceilings are commensurable.
These four are not: one physical residual (memory), one regression tripwire (render), one sysctl
(ptys), one policy constant (load). Priority needs the other two axes.

| Term | Failure mode | Severity | Reversible? | Remediation cost | Realised incidents |
|---|---|---|---|---|---|
| **memory** | compressor segment exhaustion → **kernel panic** | total fleet loss, unrecoverable, takes the operator's browsers with it | **No** | a build (B and/or D) | **6 panics, one day** |
| **render** | frame lag / dropped output | degradation, monotone, visible | **Yes, in seconds** | **free, already available** — close panes, `/handoff` idle sessions | 0 |
| **ptys** | hard spawn failure | new session refused; running work untouched | Yes | `sysctl` raise toward ~999 | 0 |
| **load** | **gate refusal** | none — this is the protection working | n/a | knob | 127 refusals |

**Corrected priority = memory ≫ render ≈ ptys ≫ load.** Memory wins on *every* axis simultaneously:
highest severity, only irreversible one, only one with realised incidents, only one needing a build —
and, after A8/A9, the highest proximity too. Render leads on exactly one axis (a proximity computed
against a tripwire, in a configuration the plan forbids) and is last on the other two.

The brief's framing — *"a 30% hard-failure term can outrank a 107% soft term"* — is right in form and
turns out not to be needed: once A8 and A9 are applied, the soft term is not even ahead on proximity.

---

## 3 · (b) Couplings the independent-walls frame misses, and the stage-by-stage ramp

**Three couplings, all load-bearing.**

1. **Memory ⊃ bursts (A10).** Not orthogonal terms — the same 64 GB. The burst budget is what
   residency leaves. This makes Wave C's value a **function of** the memory row: C bounds ignition
   into headroom that the memory row must first prove exists. Ranking C as "the live path" while
   ranking memory second reverses the dependency.
2. **Load ⊃ render (A11).** Render's cores are runnable threads inside the load ceiling. They cannot
   be spent twice.
3. **Memory → compressor CPU → load (A12).** Real, and measured to be **too slow to protect**: at the
   panic the gate read ADMIT with segments at 100%.

**Stage-by-stage on the 19 → 40 → 80 → 150 ramp.** Governing variable is the **active fraction**,
which nothing enforces (A16). The only observed datum: S6-DOD-V2 records **10 active** sessions
consuming ~22 GB with available memory falling **29.04 → 3.94 GB** — at a fleet no larger than 19.
Live sample today, 10 claude processes: **7.74 GB RSS, mean 792 MB, `vm_stat` free pages ≈ 2.5 GB.**

| Stage | Nearest wall | Second | Render's position |
|---|---|---|---|
| **19 (only stage ever observed)** | **memory** — box reached 3.94 GB available | load (via active mix) | render measured 0.42–2.0 cores = **12–57% of floor**; alarm never fired |
| **40** | **memory** at any active fraction ≥ ~15% (20 active × 2.2 GB = 44 GB alone); otherwise the **load gate refuses the spawn** and 40 is never reached | load | 40 panes = 1.0 core = **29%** |
| **80** | **memory**, decisively — even at 25% active: 20 × 2.2 + 60 × 0.232 = **58 GB > 35 GB budget** | load | 80 panes = 2.0 cores = **57%** |
| **150** | **memory** | load | 150 panes = 107% *only if* 150 panes are visible, which E forbids |

**Render is never the nearest wall at any stage of the actual ramp.** And a harder statement follows
from the same arithmetic: **the design point itself does not fit.** 140 resident × 232 MB + 10 active
× 2.2 GB = **54.5 GB against a 35 GB session budget (156%)**; using today's live mean instead of the
n=4 figure it is ~72 GB, i.e. **larger than the box**. This is not a wall-ordering problem; the design
point is unbudgeted under every per-session memory figure measured after 2026-08-09 morning.

---

## 4 · (c) Alarm floors vs failure points — and the direction each error runs

| Term | Denominator used | What it actually is | True failure point | Direction of error |
|---|---|---|---|---|
| render | 3.5 cores | **regression tripwire**, set ~1.75× above an observed 2.0-core steady state, by the instrument's own header | **not a CPU number at all** — iTerm2's render thread was already at **98.7%** at 34 panes; past saturation the CPU number goes **flat** and the failure appears as **latency** | **both ways.** vs 10 physical cores the floor understates headroom 2.9×; vs thread saturation it overstates the safe pane count |
| memory | ~45 GB | sessions + baseline (A8) | **compressor segment exhaustion** (`seg_pct`), not a GB figure — compression ratio 2.35:1 + swap | conservative — the true session ceiling is 35 GB ⇒ **100%, not 78%** |
| ptys | 511 | `sysctl`, raisable to ~999 | hard `openpty` failure | conservative |
| load | 20 | gate policy constant (2.0/core) | **no failure — a refusal** | category error (A14) |

**Does floors-vs-failure-points re-order the list? Yes, and it demotes render specifically.** Render
is the only row whose denominator is an explicitly-declared *regression* threshold rather than a
capacity limit, and the only one whose true failure mode (thread saturation → lag at flat CPU) is
**invisible to the instrument that would measure it**. Corollary worth landing on its own: a
CPU-budget census cannot detect a single-thread-bound renderer's wall by construction — it will read
a comfortable, flat ~1.9 cores while the UI becomes unusable.

---

## 5 · (e) The fifth instrument correction — it exists, and it lands on the #1 row

The program logged four corrections today, all of the same family (*an instrument counting the wrong
population*): poller census = argv contamination · pty census = +16 static legacy nodes · 1.6 load =
active-only · hook cost figures = wrapper-billed, do not reproduce.

**The fifth, verified in this audit:** `render-census.sh` sums CPU for **iTerm2**, which is **not
running on this box**, while taking its pane count from **kitty**, which is. `render-census.sh:129`
matches `cmd == "iTerm2"` exactly; `:149` computes `RENDER_CORES=(iTerm2+WindowServer)/100`; `:231`
reads panes from `kitty @ ls`. Live: `2 kitty, 4 kitten, 1 WindowServer, 0 iTerm2`. Consequences:
the census **under-reads render by the whole kitty term**; its 2.5/3.5 thresholds were calibrated on
a renderer that is absent, so they cannot fire where designed; and the row it feeds is the one the
ranking puts first.

**Fragility ranking of the four constants:**

| Rank | Constant | Why fragile | Effect if corrected |
|---|---|---|---|
| **1** | **`0.025 cores/pane`** | three independent defects at once: numerator = kitty, denominator = iTerm2 (A6); linear model contradicted by the program's own single-thread finding (A5); its verifying instrument is blind to the running renderer (A7) | render leaves first place under any of the three |
| **2** | **`232 MB/session`** | the repo already holds **555 MB** (n=39), **792 MB** (n=10, live today), **2.2 GB** (active). **No new measurement is needed to flip this row** | memory ≥ 100% ⇒ **first**, on the smallest available substitute |
| 3 | `~45 GB` denominator | pure arithmetic slip (A8) | 78% → **100%** with zero measurement |
| 4 | `3.5-core alarm floor` | declared as a regression tripwire by its own author | the render percentage stops meaning anything |

**Answer to (e): yes — and not one but three single corrections flip the order, each derivable from
the repo today without new instrumentation.** The order survives only under a selection of constants
that is optimistic on memory and pessimistic on render *at the same time*.

---

## 6 · (d) Remediation priority — does "C + render-half-of-E" survive?

**No.**

| Wave | Program's stance | Audit verdict |
|---|---|---|
| **C** (bursts) | landed, "highest-value" | **Correctly landed; nothing dispatchable remains.** Its own acceptance run did not reproduce the 372–736-proc storm (§S6.5-DONE caveat) and **D8 requires proof at ≥80 resident** — which requires the memory question answered first. C is *blocked behind* memory, not ahead of it (A10). |
| **E-render** (substrate) | "the live path" | **Worst risk/reward on the board.** Rationale = the row refuted by A3/A5/A6/A7. Surface = `handoff-fire.sh`, 7,461 lines, the plan's own *"strands real work box-wide if wrong"*. Blocked on two unbuilt comms prerequisites. And the wall it targets has a **free, instant, already-available remedy** — close panes. |
| **B** (per-session cost) | "the only load lever"; landed as evidence only, no runtime change | **The right target, aimed at the wrong quantity.** §S6.4 briefs B as *CPU occupancy 1.6 → 0.5*; S6-DOD-V2 §D1a — one day newer — assigns B a **memory** objective (*"2.2 GB per active session is what must come down… D1a is the real work and it is Wave B's"*). Nobody re-scoped B. It cannot be dispatched until it is told which number it is chasing. |
| **D** (gate re-term) | "operator's call", not on the live path | **The only mechanism that can bind anything** (A14/A16). Its replacement memory term needs no inventing — `compressor-sentinel.sh` already computes it every 10 s. Blocked on a **decision**, not on work. |

**The first wave to dispatch tomorrow: settle the per-session memory constant under real active
load** — a read-only measurement wave, half a day, no operator decision required, no runtime surface
touched.

**Why it goes first, ahead of everything:**

- Four figures span **9.5×** (232 MB / 555 MB / 792 MB / 2.2 GB) on one box. **Every** downstream
  decision keys on it: the ranking's #2 row, D1a's entire acceptance criterion, Wave B's target, and
  the burst headroom Wave C admits into (A10).
- It is the constant whose correction is **most certain** (three larger measurements already exist)
  and it decides first place.
- The 2.2 GB figure is a **delta-of-available attribution** — it sweeps in page cache, spawned
  toolchains and compressor. That weakness is the *reason* to measure, not a reason to discount:
  for a capacity ranking the **pool** is what binds, and under the friendly reading the ranking's
  35 GB still understates it.
- It is the input **both** B and D need, and it converts D from a value judgment into arithmetic.

**Then, in order:** D's memory term (the box currently has no admission control that can bind on the
wall that actually kills it — 0 of 127 refusals), then B re-scoped onto memory, then C's D8
re-verification at real residency. **E-render moves to the back of the queue** until the render
numerator and denominator are measured on the same, running, renderer.

---

## 7 · Adversarial self-pass — the three strongest defences of the ranking, and why they fail

1. **"The table is a *residency* ranking; of course it prices zero active sessions."** The sentence
   immediately below it is a **remediation** conclusion for the whole program (*"C and the render
   half of E are the live path to 150"*). And the table is not residency-pure on its own terms:
   render's numerator prices **150 visible panes**, which is an activity/topology assumption the
   design point explicitly forbids. Consistent residency accounting would put render at 14%.
2. **"2.2 GB is a bad attribution, so the memory row is fine at 232 MB."** The attribution is weak —
   which is exactly the recommendation in §6. But the ranking does not need 2.2 GB to lose: **A8
   alone** (its own arithmetic, zero measurement) puts memory at 100%, and the n=39 p50 already in
   the repo puts it at 185%. Memory outranks render on the friendly reading too.
3. **"Single-thread saturation is an iTerm2 finding; the fleet runs kitty, which is GPU-accelerated."**
   Granted — and it makes the row worse, not better: it means the program's **strongest render
   mechanism-claim describes an emulator that is not running**, its **alarm floor was calibrated on
   that same absent emulator**, and its **census cannot see the one that is**. There is currently no
   valid measurement of render cost on this box's actual renderer. A term with no valid measurement
   cannot be ranked first.

**Residual uncertainty, named.** (i) RSS overstates footprint — S6.0's own deflation ratio
(511 → 232, ≈0.45×) applied to today's live mean 792 MB still yields ~**360 MB**, ⇒ 150 × 360 MB =
54 GB vs a 35 GB budget; the direction is robust, the magnitude is what §6's wave must settle.
(ii) `vm_stat` free pages ≈ 2.5 GB is not the same as *available* — inactive pages are partly
reclaimable; this is the very conflation §S6.6 says makes the current gate term unable to bind, and
it is cited here only as corroboration, not as the measurement.
