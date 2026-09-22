# A02 — target selection for a VOLUNTARY in-place account switch

**Measured 2026-09-22, 11:34–11:45 PDT, against the live fleet. Read-only.**

## The rule, in one sentence

> A voluntary in-place switch takes the FIRST account down `claude-accounts --rank interactive`
> that is not the source, not undeclared by the account map, and not already holding this session —
> i.e. the soonest-resetting account inside the 5h-safe / weekly-safe set — and it fires ONLY when
> that account outscores the source's own interactive score; otherwise it stays put.

Everything in that sentence except the last clause and the `interactive`/`--recovery` composition
already exists in shipped code. **No new lane is needed. One CLI refusal must be lifted, and the
consumer must change which lane it asks.**

---

## Verdict table

| Question | Answer |
|---|---|
| Does a lane express "soonest weekly reset with headroom"? | **YES — the `interactive` (desk) lane**, `score_interactive`, `bin/claude-accounts:3650`. It is that sentence executed literally. |
| Is the polarity of the voluntary case really *inverse* to the recovery case? | **NO — the brief's premise is refuted.** Both lanes already score toward soonest-reset. `score_general` is `w_rem / T**2` (`:3521`) — γ=2 is *deadline-dominant urgency*, whose own docstring says "spend quota before it strands". The inversion is not in the score; it is that a voluntary source is **healthy**, so it is not auto-excluded and can win its own rank. |
| Is the lane the current recovery consumer asks the right one? | **NO.** `lr-fleet.sh:726` and `handoff-fire.sh:9491` both ask `general`. Measured today, `general` names the account that **reset 6.6 hours ago**; `interactive` names the one with the soonest reset. |
| Is the strand nowcast (`wk_strand_pp`) authoritative for this pick? | **NO at today's horizons.** Measured bias **+21.07 pp / MAE 28.68 pp / 62% alarm-agreement at the 96h bucket** (`claude-accounts --strand-score`, run below). It is admissible only inside ~12h (MAE 6.04, 91%). |
| Is a new lane needed? | **No.** Needed: (1) allow `--rank interactive --recovery`, (2) point the voluntary consumer at it, (3) add a stay-put threshold. |

---

## (a) Every scoring term, with file:line

### Shared eligibility — `_excluded()`, `bin/claude-accounts:3437`

Applied identically to all three lanes ("a different objective over the same eligibility, never a
second opinion about who is eligible", `:3441-3443`). In evaluation order:

| Gate | Line | Fires on | Class |
|---|---|---|---|
| `r["error"]` present | `:3450` | auth/probe failure (today: `next`) | data |
| `session_pct is None` | `:3452` | unreadable 5h meter | data |
| `wire_rejects(r,"7d")` | `:3458` | server said it would refuse | policy |
| `wire_rejects(r,"5h")` | `:3460` | server said it would refuse | policy |
| `su >= S_CUT` (0.85) | `:3469` | 5h hard cutoff | policy |
| `_su_projected >= RECOVERY_S_CEIL` (0.60) | `:3477` | **`--recovery` only** | policy |
| `weekly headroom < RECOVERY_W_FLOOR` (0.10) | `:3488` | **`--recovery` only** | policy |
| `k_src == "unmeasured"` | `:3497` | concurrency unmeasurable | data |
| `k_of(r) >= k_cap(r,R)` | `:3499` | `kmax-concurrency` | policy |
| `cliff_band(r) == "drain"` (≤48h to login expiry) | `:3504` | login cliff | policy, **yieldable** |

`k_of` defaults to `k_eff`; the desk lane passes `k_eff_desk` (`:2234`) so the desk's own launcher
phantoms cannot lock it out of the account it is already on.
`recovery_floors()` at `:2083`; SSOT values `RECOVERY_W_FLOOR 0.1 / _S_CEIL 0.6 / _F_FLOOR 0.05` in
`~/.claude/accounts.json` `.router`.

### `score_general` — `bin/claude-accounts:3509`

```
(w_rem / T**γ) * _soft(r) * cliff_factor(r)
```

| Term | Line | Value / constant | Kill switch |
|---|---|---|---|
| `w_rem` = `weekly_headroom` | `:1009`, used `:3516` | `(0.98 if credits_on else 1.00) − used` | — |
| `T` = `horizon(weekly_reset_h)` | `:1809`, used `:3519` | `max(reset_h − MARGIN_H, EPS_H)`; absent/elapsed ⇒ `NO_RESET_H`=168 (far, never imminent) | — |
| `γ` = `urgency_exp` | `:2057` | **`URGENCY_EXP = 2.0`** | `CC_ROUTE_URGENCY_EXP=1` |
| `SF` (5h softening) | `:1833` | `clamp((S_CUT−su_proj)/(S_CUT−S_SOFT), SF_FLOOR, 1)`; `0.85 / 0.50 / 0.05` | `CC_ROUTE_PROJ=off` (projection only) |
| `KF` (concurrency) | `:1837` | `clamp(1 − k_eff/k_cap, KFLOOR=0.1, 1)`; `k_cap` = `KMAX`=8 when `k_src=="work"`, else `KMAX_RESIDENT`=40 (`:2196`) | `CC_ROUTE_KWORK=off`, `CC_ROUTE_ASSIGN=off` |
| `CF` (credits) | `:1838` | `0.5` if `credits_on` and weekly ≥90%, else `1.0`. **Inert on this fleet — `credits_on=false` on all 4 rows.** | — |
| `cliff_factor` | `:1918` | `CLIFF_SOFT_FACTOR = 0.25` inside the 168h soft band | `CC_ROUTE_CLIFF_TERM=off` |
| `WEEKLY_FLOOR` cut | `:3517` | `0.005` | — |

**There is no gamma/decay constant other than `URGENCY_EXP`.** The repo lesson
*"a ranker preferring less headroom may be pricing decay"* was checked against every term above:
the only term that can invert an order at near-equal headroom on this fleet is **`KF`, concurrency**
— not decay. See the worked example.

### `score_interactive` (the desk lane) — `bin/claude-accounts:3650`

```
tier + min(key, DESK_KEY_MAX)      where key = 1/(1 + horizon(weekly_reset_h)) * cliff_factor * (1+hyst)
```

| Term | Line | Value | Kill switch |
|---|---|---|---|
| `tier` from `desk_keys()` | `:3614`, used `:3733` | `2` = 5h-safe AND weekly-safe · `1` = 5h-safe only · `0` = eligible (`:3594-3596`) | per-key, below |
| `DESK_5H_FLOOR` | `:2037` | `0.60` projected 5h utilisation | `CC_ROUTE_DESK_5H_FLOOR=off` (a number moves it; `0` means MAXIMAL strictness, not off — `:3535-3540`) |
| `DESK_W_FLOOR`, horizon-scaled | `desk_w_floor_at`, `:3561` | `0.15`, ramped linearly to 0 at the reset from `DESK_W_FLOOR_FULL_H = 24.0` | `CC_ROUTE_DESK_W_FLOOR=off`, `CC_ROUTE_DESK_W_RAMP=off` |
| within-tier key | `:3740` | `1/(1+T)` ∈ (0,1) — **largest for the soonest reset**; bounded so it can never cross a tier | — |
| `cliff_factor` | `:3748` | `0.25`, demotes *inside* the tier | `CC_ROUTE_CLIFF_TERM=off` |
| `DESK_HYST_MARGIN` | `:2040`, applied `:3754` | `key *= 1.15` when the row is the **desk incumbent** (`desk_incumbent()`, `:2292`, newest `--assign --src claude-launcher` inside `DESK_HYST_TTL_MIN=300`) | `CC_ROUTE_DESK_HYST=off` |
| `DESK_KEY_MAX` | `:2035` | `0.999` ceiling | — |

**No `KF` term at all.** `k_eff_desk`'s docstring states it: *"The desk lane's two-key sort has no
KF term, so this reaches routing through exactly ONE gate — `_excluded`'s KMAX cap"*
(`bin/claude-accounts:2237-2239`). That is why this lane is stable where `general` flaps.

🚨 **The usage text for this lane is STALE and describes the pre-reversal score.**
`bin/claude-accounts:84-87` reads *"maximise runway (absolute weekly headroom x projected 5h
headroom), **NO urgency term**"*. That was the 2026-08-10 survival score, **reversed on 2026-08-11**
— `score_interactive`'s own docstring (`:3652-3682`) records the reversal and the measurement
(survival lane hit the 5h wall on 4.6% of picks vs the dispatch lane's 3.4%; the two lanes
disagreed on 92% of 324 sweeps). Line `:88` also advertises `--rank general|fable` while the CLI
accepts `interactive` for both flags (`:6168`). Anyone reading the `--help` will build the wrong rule.

### `score_fable` — `bin/claude-accounts:3758`

`(f_eff / H**γ) * JB * _soft * cliff_factor`, with `f_eff = min(coupling × fable_headroom, w_rem)`,
`coupling = 0.5` (`.frontier.coupling`), `H = min(T_fable, window_deadline)`, `JB_BONUS = 1.25`,
`FABLE_FLOOR = 0.02` (recovery: `max(FABLE_FLOOR, 0.05)`, `:3785`).
**There is no earliest-reset twin of the desk lane for Fable.** On this fleet that costs nothing
today: measured, `fable_reset_h` and `weekly_reset_h` are the same stamp to within 0.3 s on all
four rows (e.g. `next4` 112.38778960 vs 112.38753703), so `H` already carries weekly perishability.

### Threshold constants that decide *whether to move*

| Constant | Line | Value | Kill switch |
|---|---|---|---|
| `REPICK_RATIO_DEFAULT` | `:1989` | **`4.0`** — best/incumbent score ratio at which `handoff-fire`'s recycle moves a pane | `CC_ROUTE_REPICK=off` (→ `repick_ratio=off`); `CC_ROUTE_REPICK_RATIO=<float>` tunes |
| emitted on every `--route`/`--rank` | `:6252` | `repick_ratio=4` on the route-meta line | — |

---

## (b) The lane exists. What is missing is three things, not a lane.

**Existing prior art — this is a *consumer* change, not a router change:**

- `lf_pick_target()`, `scripts/limit-recover/lr-fleet.sh:683-738` — already the exact shape:
  `--rank <kind> --recovery --max-wait 3`, **walk down the list**, `continue` past the source
  (`:707`, comment: *"Walk past the SOURCE account: the router may well rank the limited account
  first on weekly headroom while its 5-hour window is what just closed"*), reject names
  `lib/account-map.generated.sh` does not declare (`:714`), skip a candidate already holding this
  sid (`:719`), `--assign` charge the winner (`:723`). `lf_admit_section` then re-refuses
  `target == acct` (`:767`).
- `recycle_repick()`, `scripts/handoff-fire.sh:9463-9603` — already moves a **healthy** pane in
  place, on exclusion OR on the router's own score ratio ≥ `repick_ratio`. (A11 documents this verb.)
- `lr-handoff.sh:417-429` — resolves `--target auto` via `--route general|fable` and refuses a
  target that shares the source's session store **by realpath of `$CFG/projects`**, which catches
  two account names symlinked to one store where a name comparison would not.

**The three gaps:**

| # | Gap | Evidence |
|---|---|---|
| G1 | **`--recovery` is refused for `interactive`.** Measured: `claude-accounts --rank interactive --recovery` → `"--recovery is not defined for --rank interactive (the desk lane hosts no transplanted session)"`, rc 1. Code: `bin/claude-accounts:6177-6183`. But a voluntary in-place switch **is** a transplant of a live session onto the desk objective — precisely the combination the CLI forbids. | measured |
| G2 | **Every existing consumer asks `general`.** `lr-fleet.sh:726`, `handoff-fire.sh:9491`, `lr-handoff.sh:419`. `general` has a `KF` term and `w_rem` in the numerator; `interactive` has neither and sorts on `1/(1+T)`. They disagree today. | measured |
| G3 | **No stay-put threshold on the interactive lane.** `repick_ratio=4.0` is calibrated against `score_general`'s multiplicative spread (measured 80–130× between top and rest, `:1985-1987`). `score_interactive` returns `tier + key ∈ [0,3)`, so a *ratio* is meaningless there — today's top two differ by **0.14%** (2.008861 vs 2.006103) while representing a 51-hour difference in reset horizon. A ratio threshold on this lane would move a pane on every call or never. | measured |

**Hysteresis has the wrong polarity for this decision** and must be handled: `desk_hyst_margin`
multiplies the **incumbent's** key by 1.15 (`:3754`). If the source pane *is* the desk incumbent,
the lane is biased toward staying — correct for a human's desk, wrong for a deliberate move. It is
moot only when the caller walks past the source, which is why the walk (not `CC_ROUTE_DESK_HYST=off`)
is the right lever: disabling the term globally would also un-damp the operator's own launcher,
whose flip rate was measured at 43.4% over the last 100 decisions (`:3760-3764`).

---

## (c) The strand nowcast — which surface is authoritative

Three surfaces, and they are **not** interchangeable:

| Surface | What it is | Authoritative for |
|---|---|---|
| `weekly_pct` / the `/accounts` weekly column | the vendor meter, read live | **the eligibility gates** (`w_rem`, `WEEKLY_FLOOR`, the recovery floor). Nothing else can gate. |
| `wk_strand_pp` (`:3176`) — the `weekly drain` block in `/accounts` | nowcast: `100 − (weekly_pct + burn_wk_ewma_ph × weekly_reset_h)`, clamped at 0 | **a tie-break inside ~12h of a reset, and nothing else.** |
| `claude-accounts --strand-score` (`:3214`) + `scripts/desk-strand-replay.py` | the scoring harness for the nowcast, and the policy replay | **the authority on whether to believe `wk_strand_pp` at a given horizon.** |

**Measured this session** (`claude-accounts --strand-score`, 22 completed weekly windows, 4 accounts):

```
  horizon   cells      bias       MAE   alarm-agree
      96h   21/22     +21.07     28.68   13/21 (62%)
      48h   22/22      +6.07     10.25   17/22 (77%)
      24h   22/22      +4.13      9.13   16/22 (73%)
      12h   22/22      +4.56      6.04   20/22 (91%)
       6h   22/22      +0.19      3.94   19/22 (86%)
```

Today's nearest reset among **routable** accounts is 112h (`next4`); the soonest on the fleet is
90h (`next2`, excluded). **Every candidate sits at or beyond the 96h bucket — the worst one.** The
nowcast there is biased **+21 pp high** and agrees with the realised outcome 62% of the time, i.e.
barely better than a coin. So: **`wk_strand_pp` must not be a scoring term, and must not be quoted
as a reason for a switch at these horizons.** Its own docstring says so — *"a good NOWCASTER for
exactly the reason it is a bad forecaster"* (`:3184-3186`), and it explicitly withdraws the
published `4/4 recall / 0 FP / median ~20h lead` claim (`:3179-3183`).

**Corroborating instrument.** `scripts/desk-strand-replay.py` over 8,290 sweeps
(2026-08-10 → 2026-09-22), 25 observed weekly resets:

```
    next3   2026-09-08T12:02  reset at  62% used  -> 38pp stranded   (meter read 49%; zeroed mid-window)
    next2   2026-09-12T11:00  reset at 100% used  ->  0pp stranded
    next    2026-09-13T04:02  reset at 100% used  ->  0pp stranded
    next4   2026-09-13T10:57  reset at 100% used  ->  0pp stranded
    next3   2026-09-15T12:12  reset at 100% used  ->  0pp stranded
    next2   2026-09-19T11:05  reset at 100% used  ->  0pp stranded
    next    2026-09-20T04:04  reset at 100% used  ->  0pp stranded
    next4   2026-09-20T09:15  reset at 100% used  ->  0pp stranded
    next3   2026-09-22T12:01  reset at 100% used  ->  0pp stranded
                policy | desk-time on an expiring account | guard
    SHIPPED (ramp/24h) | on-target  714/1976  =  36.1% | wall-exposure    0
```

🚨 **The last SEVEN completed windows stranded 0 pp.** The `~30 pp/week` figure in
`score_interactive`'s docstring (`:3672`) is a mid-August measurement and is **currently false**.
So the *expected value* of a voluntary switch on this fleet right now is near zero — while
`wk_strand_pp` simultaneously nowcasts 75/65/24 pp of strand. Two independent instruments
(the +21 pp bias at 96h, and seven consecutive 0 pp realisations) say the nowcast over-predicts
at long horizon. **Do not build an actuator that fires on it.**

**On "the `/accounts` weekly column UNDERSTATES spend."** Measured, the mechanism is a **mid-window
zeroing of the vendor meter**, first observed 2026-09-01 and unexplained
(`scripts/desk-strand-replay.py:127-140, 308-312`). The replay adds the forgotten segments back as
`pct_used` and annotates the row (`meter read 22%; zeroed mid-window, so >= 73%`). **The live router
does no such correction** — `weekly_headroom()` (`:1009`) reads the raw meter. Consequence, stated
rather than hidden: after a zeroing, `w_rem` is **over**stated, so `score_general` over-rates that
account and the recovery weekly floor under-protects it. The interactive lane is less exposed
(headroom enters only as a tier test, not as the numerator), which is a second reason to prefer it.

---

## (d) What the rule must refuse

| Must refuse | Mechanism today | State |
|---|---|---|
| the source's own account | `lf_pick_target:707` `[ "$cand" = "$1" ] && continue`; `lf_admit_section:767` re-refuses `target == acct`; `lr-handoff.sh:425-429` refuses by **realpath of `$CFG/projects`**, catching two names on one store | **exists** — reuse verbatim |
| a logged-out account | `_excluded:3450` `if "error" in r`. Measured today: `next=keychain item present but carries no OAuth credentials`, excluded from all three lanes | **exists** |
| an account inside its login-cliff drain band (≤48h) | `_excluded:3504` `cliff_band == "drain"` | **exists — but `ranked()` YIELDS it** for `general`/`fable` when it is what emptied the candidate set (`:3844-3862`), and **never yields it for `interactive`** (`:3851-3855`). For a long-lived transplanted session, yielding onto an account whose refresh token dies in <48h hands it a mid-session `invalid_grant` with **no reset to wait for**. **This is a third, independent reason the voluntary switch belongs on the `interactive` lane.** |
| an account with no Fable headroom, for a Fable session | `score_fable:3781-3790` — `no-fable-limit` (a missing scoped limit is an *entitlement* fact, not 100% headroom, `:3771`), `fable-exhausted`, `recovery-fable-thin`. Caller picks the kind from the model: `lf_pick_target:685` `case "$2" in claude-fable-*) kind=fable`; `lr-handoff.sh:418` | **exists** — and note `recycle_repick` **declines outright** for `claude-fable-5*` panes (`handoff-fire.sh:9473`), residual R14A-2 |
| an account that already holds this session | `lf_pick_target:719` `_lf_target_holds_sid` | **exists** |
| a name the account map does not declare | `lf_pick_target:714` / `recycle_repick:9580` | **exists** |
| the literal sentinel `none` | `lf_pick_target:704` — *"observed 2026-09-10, the poller's own log reading 'in-place recovery of 2d71c6d8 onto none' for 480s"* | **exists** |
| **a target that is not materially better than the source** | **nothing** — G3 | **MISSING** |

---

## (e) The rule's verdict on today's live state

`claude-accounts --json --no-heal`, 2026-09-22 ~11:38 PDT:

| acct | 5h % | ↻5h | weekly % | ↻weekly | fable % | login cliff h | k / k_work | auth |
|---|---|---|---|---|---|---|---|---|
| next | 0 | — | 18 (last-known) | 107.39h | 0 | — | 0/0 | **no-oauth-blob** |
| next4 | 5 | 3.72h | 10 | **112.39h** | 0 | 378.1 | 6/6 | ok |
| next3 | 22 | 3.72h | 6 | **163.39h** | 6 | 219.1 | 5/3 | ok |
| next2 | 6 | 4.05h | 38→39 | **90.39h** | 33 | 657.5 | 6/13 | ok |

Exclusions (identical across all three lanes, measured):
`next=keychain item present but carries no OAuth credentials; next2=kmax-concurrency`.

Ranks, measured, same minute:

```
--rank general      → next4 0.000018   next3 0.000018      (a TIE at 6 s.f.)
--rank interactive  → next4 2.008861   next3 2.006103      (tier 2 both; T=111.9h vs 162.9h)
--rank fable        → next3 0.000011   next4 0.000010
```

Five minutes earlier the same `--rank general` returned **`next3 0.000022  next4 0.000018`** — the
order **flipped**, on `KF` alone (`next3` `k_eff=3`/`k_cap=8` ⇒ KF 0.625; `next4` `k_eff=6` ⇒ KF
0.25), while the headroom/horizon inputs were unchanged. `--rank interactive` was **byte-identical
across three consecutive calls**.

### The worked verdict

**Source = `next3`** (this fleet's least-urgent account — its week rolled over at 12:01 UTC today,
~6.6 h ago, and sits at 6% used with 163 h to run):

1. `--rank interactive` → `next4 2.008861`, `next3 2.006103`.
2. Walk: `next4` ≠ source, declared in the map, does not hold this sid → **TARGET = `next4`**.
3. Refusals cleared: `next4` auth ok · cliff 378 h (outside the 168 h soft band) · 5h 5% ⇒ tier 2 ·
   weekly headroom 0.90 ≥ recovery floor 0.10 · projected 5h well under the 0.60 ceiling.
4. Materiality: `next4`'s reset is **51 hours sooner** than the source's. Under the stay-put rule
   proposed below (absolute tier + horizon-gap), this **FIRES**.
5. For a Fable session the same source routes to **`next3` (itself)** on `--rank fable` ⇒ the walk
   falls through to `next4` at 0.000010. Same target, arrived at by a different route.

**Source = `next4`** (the current `--route interactive` desk pick): the only other candidate is
`next3`, whose reset is **51 h later**. The rule **REFUSES** — a voluntary move onto a
later-resetting account is anti-objective. This is the case G3 exists for, and today `general`
would have licensed exactly that move (a tie, resolved by `accounts.json` order `next, next4,
next3, next2`).

**And the headline the operator needs:** `--rank general` at 11:34 named **`next3`** — the account
that had reset **6.6 hours earlier** and had the *farthest* deadline on the fleet. That is the
literal inverse of the stated rule, and it is the lane every existing consumer asks.

---

## Change list

Three changes, smallest first. No new scoring lane; no new constant class.

| # | File | Change | Why |
|---|---|---|---|
| **C1** | `bin/claude-accounts:6177-6183` | Allow `--rank/--route interactive --recovery`: apply `recovery_floors` (`:2083`) to the interactive lane via the existing `_excluded(recovery=True)` path. The current refusal text (*"the desk lane hosts no transplanted session"*) becomes false the moment a voluntary switch exists. **Keep the refusal for `--route interactive`** if the launcher path must stay byte-identical; only `--rank` needs it. | G1. `recovery_floors`'s `S_CEIL` already **equals** `DESK_5H_FLOOR` (0.60) — the two lanes agree on the 5h test by construction, so this composes without a new number. |
| **C2** | new consumer (or `lr-handoff.sh:417-421` behind a flag) | Ask `--rank interactive --recovery --max-wait 3` and reuse `lf_pick_target`'s walk verbatim (source-skip, map-declare, holder-skip, `none`-sentinel break, `--assign <new> --src <verb>`). Do **not** copy `lf_pick_target`; call it, or factor it — a second copy of the walk is a second policy. | G2. Also inherits the non-yielding cliff term for free (`:3851`). |
| **C3** | `bin/claude-accounts`, beside `repick_ratio()` (`:1991`) | A **desk-lane** materiality threshold, declared by the router and emitted on route-meta like `repick_ratio` — **not** a ratio. Proposed shape: fire only when `tier(target) >= tier(source)` **AND** `horizon(source) − horizon(target) >= DESK_SWITCH_GAP_H`. Seed `DESK_SWITCH_GAP_H = 24.0` (the already-argued `DESK_W_FLOOR_FULL_H`: below 24 h out, the floor has ramped away and the move buys nothing the source could not still burn). Kill switch `CC_ROUTE_DESK_SWITCH=off` via `_term_on` (**not** `_cliff_env` — see `repick_ratio`'s docstring, `:2000-2010`: a term that AUTHORISES an action must fail *off*). | G3. A ratio is meaningless on `tier + key ∈ [0,3)`; today's top two differ by 0.14% across 51 h. |
| **C4** (doc, free) | `bin/claude-accounts:84-88` | Rewrite the `interactive` usage text — it still describes the **pre-2026-08-11 survival score** (*"maximise runway … NO urgency term"*), which the reversal at `:3652-3682` refuted. Add `interactive` to line `:88`'s `--rank general\|fable`. | A reader of `--help` builds the inverse rule. |

**Explicitly NOT recommended, and why:**

- *A fourth `voluntary` lane.* The CLI's own argument against `--recovery` as a kind applies
  (`:6171-6173`): it would need a general-twin and a fable-twin, "and the doubling is the tell".
- *`wk_strand_pp` as a scoring term.* +21 pp bias / 62% agreement at the horizons that matter today.
- *`CC_ROUTE_DESK_HYST=off` to defeat incumbent stickiness.* The source-skip in the walk already
  makes it moot for the source, and the term damps a measured 43.4% flip rate on the operator's
  own desk.
- *Changing `score_general`.* It is correct for its job (short dispatched fires). The defect is
  which lane the voluntary consumer asks, not the lane's arithmetic.

---

## Adversarial self-pass

Three gaps hunted with tool calls, not assumption:

1. **"The premise — weekly quota is being stranded — may be false right now."** Checked. It is.
   Seven consecutive completed windows at 0 pp stranded (`desk-strand-replay.py`, above); the
   `~30 pp/week` in `score_interactive:3672` is an August figure. **Consequence for the change
   list: build C1/C2/C4, but C3's threshold should be sized so the switch is RARE.** An actuator
   sized against a 30 pp/week strand that is currently 0 pp/week will churn panes for nothing —
   and a flip costs `--resume` visibility, because `projects/sessions/history.jsonl` are
   per-account (`:3762-3764`).
2. **"Is `--rank interactive` reachable at all, or is it desk-launcher-only?"** Checked: the CLI
   kind check at `:6168` covers **both** `--route` and `--rank`; `--rank interactive` ran clean
   (rc 0, with `desk_tier=2 desk_incumbent=0 desk_k_eff=6` on route-meta). The launcher's own call
   is `--route interactive --max-wait 0 --max-age 600` (`lib/claude-launcher.zsh:85`). Only the
   `--recovery` composition is blocked.
3. **"The repo lesson says read the scorer's OTHER terms before overriding a ranker that prefers
   less headroom."** Done — all seven `score_general` terms enumerated above. The finding is the
   *opposite* of that lesson's case: `general` preferred **more** headroom and a **later** reset,
   and the term that decided it today was `KF` (concurrency), which the interactive lane does not
   have. `CF` is inert on this fleet (`credits_on=false` on all four rows), so it cannot be the
   hidden term. The one term I could **not** decorrelate is `KF` vs the operator's real objective:
   an account with 6 working sessions genuinely is less able to absorb a transplant, so the
   general lane is not simply *wrong* — it is answering a different question. That is why the
   recommendation is "ask the other lane", not "fix this lane".

## Residuals / uncertainties, named

- **R1 — `wk_strand_pp` is currently the only surface the global `CLAUDE.md` tells sessions to
  read for capacity** (*"read the strand nowcast, never the percentage"*). Measured here, that
  instruction is sound for *detecting a zeroed meter* and unsound as a *forecast* beyond ~24 h.
  Not filed — outside this brief's scope; flagged for the wave lead.
- **R2 — a Fable voluntary switch has no earliest-reset lane.** Harmless on today's fleet only
  because `fable_reset_h == weekly_reset_h` to within 0.3 s on all four rows. If the vendor ever
  decouples the two buckets, C2's `kind=fable` branch silently reverts to `general`-shaped
  arithmetic. `recycle_repick` declines Fable panes outright (`handoff-fire.sh:9473`, residual
  R14A-2 in `ACCOUNT_ROUTING_V2.md` §14.1).
- **R3 — `next` is logged out** (`no-oauth-blob`, `ichris96+claude@hotmail.com`), so today's
  worked example ran on a 3-account fleet, one of which (`next2`) was `kmax-concurrency`-excluded.
  **The live decision was effectively binary.** A 2-candidate ranking is a weak test of any
  selection rule; re-run the worked example when the fleet is whole.
- **R4 — the 0 pp/week strand and the 62%-agreement nowcast are both measurements of a 6-week
  window** that includes an unexplained vendor meter-zeroing event starting 2026-09-01
  (`desk-strand-replay.py:139`). Neither should be quoted past its next re-derivation:
  `claude-accounts --strand-score` and `python3 scripts/desk-strand-replay.py`.
