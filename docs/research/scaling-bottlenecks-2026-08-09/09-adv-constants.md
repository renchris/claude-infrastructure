# Adversarial constants audit — the ranking's #1 wall is built from three artifacts (2026-08-09/10)

**Slot:** 09-adv (hostile review). **Subject:** every constant under `CONCURRENCY_PROGRAM.md`
§S6-UPDATE §6's wall ranking. **Method:** re-read each instrument's source, then re-derive each
constant live (read-only sampling, ≤1 Hz, ≤120 s/instrument; box under a real 9-session all-active
research wave, load1 27→44 during the audit — an unusually good stress fixture).

**Verdict in one line: the FIFTH instrument artifact exists and is live-demonstrated —
`render-census.sh`'s render sum matches only `iTerm2` while the fleet renders in kitty, so the
instrument that owns the program's #1 wall reads 0.33 cores where the render class measures
0.42–0.47 — and correcting the render row's three stacked artifacts plus the load row's
regime-mixing INVERTS the published ranking almost exactly: memory → load(active) → ptys → render,
not render → memory → ptys → load.**

---

## 1 · Constants table

Every live figure below: 2026-08-09 23:17–23:28 PDT, 10-core M1 Max / 64 GiB, 9 sessions (all
active — sibling audit workers), kitty fleet, browsers open. Measuring command cited per row.

| # | Constant | Program's value | Independent re-derivation (instrument) | Verdict | Consequence if corrected |
|---|---|---|---|---|---|
| 1 | `kern.tty.ptmx_max` | 511 | 511 (`sysctl kern.tty.ptmx_max`) | **CONFIRMED** | — |
| 2 | pty legacy offset | +16 static nodes | 16 static `/dev/ttys[0-9a-f]` seen; census excludes them; 18–20 dynamic 3-digit nodes live | **CONFIRMED** | — |
| 3 | ptys per pane | 1 | 9 panes → exactly 9 claude-pane ptys (`ps -axo tty=,pid=,comm=` attribution: each pane pty holds login/zsh+bash+tee+claude+caffeinate) | **CONFIRMED** | — |
| 4 | pty ambient | "~2" | **9–11 today**: 8 held by bare `Python` (MCP/pyexpect harnesses), 1 by `expect`. pty-census read 20 used / 9 panes; the doc's own prediction 1 ("pty_used within ±3 of panes, else refuted") is **breached by 9** | **CORRECTED (0–11, uncontrolled foreign term)** | Wall barely moves (150+ambient ≈ 150–161/511 = 29–32%); but the "+2" is a snapshot of third-party tooling, not a fleet property — model it as a measured offset, not a constant |
| 5 | pty wall | binds ~509 panes (30% at 150) | same arithmetic, corrected ambient | **CONFIRMED** (margin item) | ranking position unchanged (#3) |
| 6 | resident session memory | 232 MB median phys_footprint | **235 MB median**, mean 239, max 402, n=10 (`top -l 1` MEM col — the doc's own 4/4 vmmap cross-check accepted) — and these sessions were ACTIVE, not idle | **CONFIRMED** | The session *process* stays ~235–400 MB even under heavy tool work — see #8 |
| 7 | memory numerator at 150 | 35 GB (150×232 MB) | arithmetic reproduces; **but omits the spawned-tree term**: live, a mere research wave adds 3.8 GB of `node-other` (next-server, MCP…); the program's own §11.1 measured dev-toolchain storms at 23–44 GB | **INCOMPLETE** | at the program's own design mix (150 resident/~10 active) numerator = 33 GB + 4–23 GB workload term → 37–56 GB |
| 8 | active-session memory (S6-DOD-V2) | 2.2 GB/active | Sessions active right now median 235 MB (row 6). The 2.2 GB was available-decline ÷ 10 — it bundles spawned toolchains, browsers and cache drift into the session process | **CORRECTED (attribution)**: session ≈ 0.24–0.4 GB; the rest is the per-WORKLOAD spawned tree | the memory model needs a burst/tree term (Wave C's subject), not a bigger per-session constant |
| 9 | memory denominator | ~45 GB usable | 64 − wired 5.2 − non-Claude process footprint 20.7 (browsers 5.9 + other-daemons 7.8 + WS 1.4 + terminal 1.5 + spotlight 0.3 + node-other 3.8) = **38–42 GB** with browsers open; soft ±5 GB (file-backed cache 21 GB is partially reclaimable) | **CORRECTED (38–42 GB, range)** | all-idle memory wall ~160–180 sessions, not 190; at the design mix with one dev burst it is already breached — which is precisely how the box panicked 6× today (compressor segments) |
| 10 | render slope | 0.025 cores/pane | Two-point: doc's 0.42 cores @ ~17 panes vs live 0.42–0.47 @ 9 panes (`top -l 2 -s 5`, WS+kitty, two samples) ⇒ **marginal slope ≈ 0**; WindowServer baseline 0.32–0.35 alone is 75–80% of the total and pane-independent | **CORRECTED (≈0 per resident pane; render = ~0.33 baseline + activity/visibility term)** | the 3.75-at-150 numerator has no mechanism; occluded panes aren't composited at all, so compositing is bounded by visible screen area, not resident pane count |
| 11 | render denominator | 3.5 cores ("alarm floor") | `render-census.sh:47-49,56`: `CC_RENDER_ALARM_CORES` default, **deliberately set above the then-measured 2.0-core steady state so the alarm "speaks on REGRESSION, not the steady state"** — an attention threshold; no degradation was ever measured at 3.5 | **CORRECTED (policy constant, not a wall)** | "binds at ~140 panes" = alarm-floor ÷ zero-intercept-slope — both factors artifacts; the render WALL is unmeasured and, mechanism-wise, unreachable via resident panes |
| 12 | render at 150 ("3.75/3.5, 107%") | projection 150×0.025 | today's actual render class: 0.42–0.47 cores; the shipped census reads **0.33** of it (see §2) | **REFUTED as a wall quantity** | render drops from #1 to #4; Phase E's render rationale dies (its pty rationale died earlier the same day) |
| 13 | active load slope | 1.6 runnable threads/session | live: load1 27.4→44.4 at 9 sessions all-active ⇒ **3.0–4.9 per ACTIVE session**; the 1.6 came from load 19 @ 12 *mixed* sessions — a fleet-mix average, not a per-active slope | **CORRECTED (≈2.5–5 per ACTIVE session; 1.6 is mix-dependent)** | at the design mix (10 active): load 25–50 vs ceiling 20 ⇒ the load gate binds at ~4–8 concurrent actives — load re-enters as a top-2 wall |
| 14 | idle slope | 0.0031 | no idle population exists on the box right now (9/9 active); method (per-process Δcpu/Δwall) is sound and immune to the sweep's ambient-decay failure | **UNMEASURABLE-now** (accepted provisionally) | note: "binds ~4,300" does not reproduce from it (20 ÷ 0.0031 = 6,452; ~4,300 needs an undocumented ambient intercept ≈ 6.6) |
| 15 | load ceiling | 20 (2.0/core) | `capacity-admit.sh` `CC_HW_DEFAULT_MAX_LOAD_PER_CORE=2.0` × 10 — a gate policy with real teeth (127/127 refusals), not a physical wall: the box ran load 44.4 during this audit, degraded but alive | **CONFIRMED as policy** | of the four denominators only ptys (511) and RAM (64 GiB) are physical; render (3.5) and load (20) are chosen thresholds |
| 16 | dispatch occupancy ratio | 3.46× parallel vs serial | bench's own null control FAILED (median 1.00 but spread 0.29–1.51, ±50% noise floor) — the doc self-flags "directional, not certified"; grep confirms the uncertified figure did NOT leak bare into the plan | **CONFIRMED as directional-only** | quote only "live floor 2.10 > control ceiling 1.51"; certify on a quiet box before sizing Wave B on it |
| 17 | R-state sampler | "1 Hz" per plan; process-R count | script default is **2 Hz** (`CC_OCC_HZ:-2`); live cross-check: mean_runnable 27.7 vs mean load1 31.0 over the same 45 s ⇒ ~11% undercount at this mix (multi-thread + churn) — the in-source "lower bound" caveat holds | **CONFIRMED (bounded low, self-documented)** | Nyquist concern is real for a single periodic poller (quantization ≫ signal at idle scale) but the idle constants came from Δcpu/Δwall, not this sampler; at fleet scale phase-wash makes the point-sample fair |

## 2 · The fifth instrument artifact — the render alarm cannot see the fleet's terminal

The four known artifacts (ps-RSS double-count · argv-contamination · pty +16 · ΔCPU fork-churn
blindness) are all population-predicate defects. The fifth is the same genus, live in shipped code:

- `render-census.sh:129-132` sums `render_cores` from exactly two top command names: `iTerm2` and
  `WindowServer`. **kitty is not in the sum.**
- The fleet renders in kitty: `KITTY_WINDOW_ID=5` in-session, **zero** iTerm2 processes exist
  (`pgrep -x iTerm2` → none), 2 kitty processes live.
- Same script, same run: census printed `iTerm2/WindowServer: 0.0% / 33.2% → render cores 0.33`
  while an independent `top -l 2 -s 5` in the same minute read WindowServer 31.8–35.0% **plus kitty
  9.8–11.6%** → true render class 0.42–0.47 cores. The shipped gauge under-reads by 23–26% today.
- The asymmetry that makes it an artifact and not a nit: the WindowServer share it DOES see is the
  pane-independent baseline; the kitty share it CANNOT see is the per-pane/per-activity term — the
  instrument is blind to exactly the slope its 3.5-core alarm exists to catch. And the same file's
  *pane-count* arm was given a kitty branch on 2026-07-31 (`render-census.sh:228-244`) — the render
  sum never was. Two halves of one instrument disagree about which terminal exists.
- Compounding: the 0.025 slope was derived from a WindowServer+**kitty** measurement (ceiling doc
  §2.5), then enforced by an iTerm2-only alarm — the constant and its enforcing instrument measure
  different populations.

**Fix (one line + a rebase):** add `kitty` to the render sum; then re-derive WARN/ALARM from a
measured degradation point, or relabel them explicitly as attention thresholds.

## 3 · The ranking's construction defect — rows priced in different regimes

The §6 table prices all four rows "at 150" but not in the same 150:

| Row | Regime priced | Consistent design-mix repricing (150 resident, ~10 active) |
|---|---|---|
| render 3.75/3.5 (107%) | 150 panes **all streaming-visible** (linear ×150) | ~0.33 + activity term ≈ **0.5–1.1 cores = 14–31%** of even the alarm floor |
| memory 35/45 (78%) | 150 **all idle** | 33 GB + workload tree (4–23 GB) vs 38–42 GB usable = **90–130%** |
| ptys 152/511 (30%) | mix-independent (correct) | **29–32%** |
| load 0.46/20 (2%) | 150 **all idle** | 10 × (2.5–5) + 140 × 0.0031 = **25–50 vs 20 = 125–250%** |

Render's #1 position exists only because its row was priced in the active regime while load's row
was priced in the idle regime. Priced consistently at the program's own design point:

**Corrected ranking: memory/burst (≥90%, and the actual 6×-today panic mechanism) → load-on-active
(125–250% of the gate; binds at ~4–8 concurrent actives — matches the 127/127 refusals) → ptys
(~30%, margin) → render (≤31% of an alarm floor that isn't a wall).**

## 4 · What this does to the program

- **Wave C (burst survival) stays the live path — strengthened.** The #1 wall is the memory/burst
  term, and it is the confirmed kill mechanism (compressor segments), not a projection.
- **Wave B is promoted, with a corrected target:** the design point breaches the load gate unless
  concurrent actives are capped ~6 or per-active occupancy is cut 2–3×. B should measure per-ACTIVE
  slope (2.5–5 observed band), not inherit 1.6.
- **Phase E loses its second rationale in one day.** Its pty justification was an instrument
  artifact (+16); its render justification is three stacked artifacts (§1 rows 10–12). Headless's
  real remaining value: pty margin beyond ~500 panes and operational decoupling — re-justify or
  shelve.
- **Wave D confirmed directionally:** an admission gate keyed on ACTIVE concurrency (+ the sentinel's
  segment term) is exactly what the corrected ranking demands.
- **Instrument debts:** render-census kitty term (§2); pty-census ambient is a foreign uncontrolled
  term (row 4); plan says "1 Hz" where the probe defaults 2 Hz; "binds ~4,300" arithmetic
  unreproducible from its own constants.

## 5 · Falsifiable predictions

1. Adding `kitty` to `render_cores` raises the census by 0.08–0.15 cores on today's fleet; a
   9-pane fleet then reads ~0.45, not 0.33. (Refutes §2 if the delta is <0.05.)
2. At 60 resident panes, mostly occluded, WS+kitty reads **< 1.0 core** (linear model predicts 1.5).
3. 10 concurrent ACTIVE sessions push load1 ≥ 25 within 90 s (refutes 1.6/active; confirms 2.5–5).
4. Killing the 8 `Python` pty-holders drops `pty_used` to panes+1±1 — the ambient term follows the
   harness census, not the session census.
5. On a quiesced box, 20 idle-only sessions show per-session load slope < 0.01 (would confirm row 14).

## 6 · Audit trail

Sources read: `scripts/occupancy-probe.sh`, `scripts/render-census.sh`, `scripts/pty-census.sh`,
`scripts/lib/capacity-admit.sh` (grep), CONCURRENCY_PROGRAM.md:1625-1843, and all five 2026-08-09
capacity docs (ceiling, idle, active, pty, blind-terms) in the read-only `scale-150` worktree.
Live instruments: `sysctl` (memsize/ncpu/ptmx_max/loadavg/swap ×3), `vm_stat`, `pty-census.sh`,
`render-census.sh --no-append`, `occupancy-probe.sh --hz 1 --seconds 45`, `top -l 2 -s 5` ×2,
`top -l 1` full-fleet MEM/CMPRS census, `ps -axo tty=,pid=,comm=` pty attribution,
`ps -axo comm=` family census. No writes outside this file; no load generated; no process touched.
