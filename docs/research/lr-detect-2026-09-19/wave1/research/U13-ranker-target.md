# U13 — the ranker and the recovery target

**One line:** the fable score is `f_eff / (T−0.5)² × (1 − k_work/8)`, and today `next`'s 24× headroom
deficit against `next3` was cancelled almost exactly by a 40× urgency bonus for having its weekly
bucket 11 h from reset instead of 67 h — the two top scores then sat inside ONE working session's
worth of the concurrency term (12.5 %), so which one `--rank fable` names is decided by the pane
census at the instant of the call. lr-fleet did not walk past the top; it asked the *fable* lane while
the operator was reading the number the *same* lane printed a few minutes earlier under a different
census. Nothing in the eligibility gate asks the only question a recovery cares about — *will this
account still be alive in an hour* — and by measurement `next` hit weekly 100 % **1 h 54 m after the
dry run named it.**

---

## 0. The exact scorer, extracted

`score_fable`, bin/claude-accounts:3459-3489 — the whole of it, in the case that applies here
(permanent window ⇒ `h_deadline is None` ⇒ `JB = 1.0`, `H = T_fable`):

```
w_rem  = max(0, 1.00 − weekly_pct/100)                                   # :3481
f_eff  = min(0.5 × (1 − fable_pct/100), w_rem)                           # :3482   (coupling 0.5)
if f_eff <= FABLE_FLOOR (0.02): return None, "fable-exhausted"           # :3483-3484
T      = horizon(fable_reset_h) = max(reset_h − MARGIN_H(0.5), 0.25)     # :3485 → :1581-1599
score  = f_eff / T**URGENCY_EXP(2.0) × JB × _soft(r,R) × cliff_factor    # :3489
_soft  = SF × KF × CF,  KF = clamp(1 − k_eff/k_cap, 0.1, 1.0)            # :1602-1611
k_eff  = k_work + k_phantom   (falls back to the pane census)            # :1833-1840
k_cap  = KMAX (8) when k_src=="work"; KMAX_RESIDENT (40) otherwise       # :1929-1964
```

Constants live in `~/.claude/accounts.json` `.router` (= the repo's `accounts.json`):
`URGENCY_EXP 2.0 · MARGIN_H 0.5 · KMAX 8 · KMAX_RESIDENT 40 · S_CUT 0.85 · S_SOFT 0.50 ·
WEEKLY_FLOOR 0.005 · FABLE_FLOOR 0.02`; `.frontier.coupling 0.5`.

**The printed triple is reproduced exactly.** Feeding the 17:00:14 Z utilization sample
(`~/.claude/logs/account-utilization.jsonl`: next weekly 98 / fable 7, next3 weekly 11 / fable 0,
next2 weekly 0 / fable 0) and the recorded `weekly_reset_at` values (next 2026‑09‑20T04:00 Z = 11.0 h
out, next3 2026‑09‑22T12:00 Z = 67.0 h, next2 2026‑09‑26T11:00 Z = 162.0 h) into the real module:

| acct | f_eff | T | T² | KF (k_work) | score | lead observed |
|---|---|---|---|---|---|---|
| next3 | 0.5000 | 66.5 | 4 422 | 0.625 (k=3) | **0.000071** | 0.000071 |
| next  | 0.0200 | 10.5 | 110 | 0.375 (k=5) | **0.000068** | 0.000069 |
| next2 | 0.5000 | 161.5 | 26 082 | 1.000 (k=0) | **0.000019** | 0.000019 |

`=> python3` against `importlib` load of `bin/claude-accounts`, `score_fable(row, cfg, {"active":True,"deadline":None})`.
next2 matches to the last printed digit, which pins the model as the real one.

---

## 1. Why 99 % weekly scores within 3 % of 11 % weekly

**The urgency denominator dominates, and it is pricing something real — for the wrong decision.**

- headroom ratio next3 : next = `0.50 / 0.02` = **24×** in next3's favour
- urgency ratio next : next3 = `66.5² / 10.5²` = **40×** in next's favour
- concurrency ratio = `0.625 / 0.375` = 1.67× in next3's favour
- net = 24 × (1/40) × 1.67 = **1.00** → a coin flip.

γ = 2 is not an accident and not under-weighting by oversight: it is the operator's own
use-it-or-lose-it rule written as algebra (bin/claude-accounts:1715-1727 — *"quota expiring tomorrow
has no later chance"*), and it was landed BECAUSE linear scoring starved an expiring account
(accounts.json `.router._`). **`next`'s 2 pp of weekly is not scored as 2 pp; it is scored as 2 pp that
must be spent in the next 10.5 hours or vanish.** That is exactly right for a *dispatch* — placing a
new, sizeable unit of work — and exactly wrong for a *recovery*, where the single requirement is that
the transplanted session does not die again.

The three structural facts behind it:

1. **`fable_reset_h == weekly_reset_h` on every account** (`--json` today: next 9.0275/9.0273, next3
   65.0275/65.0275, next2 160.0275/160.0275). So in the fable lane the urgency term is the *weekly*
   deadline, and headroom and deadline are therefore correlated: an account that burned 98 % of its
   week is also, usually, an account near its reset. γ=2 turns that correlation into a near-exact
   cancellation.
2. **Headroom enters LINEARLY and the horizon QUADRATICALLY.** Halving the time-to-reset is worth 4×;
   halving the headroom is worth 2×. Weekly headroom is therefore structurally under-weighted
   *relative to the deadline*, by construction.
3. **f_eff for `next` was capped by `w_rem`, not by the Fable lane** — `min(0.5×0.93, 0.020)` = 0.020.
   The model is correct (Fable is a 50 % sub-cap of weekly), but the surviving number is 2 pp.

**And it survived the floor by a floating-point ULP.** `FABLE_FLOOR = 0.02` and the test is
`f_eff <= 0.02` (`:3483`). At weekly 98, `1.0 − 98/100` evaluates to `0.020000000000000018`, which is
`> 0.02` → **not** excluded. At weekly 99 it is `0.010000000000000009` → excluded. So `next` was
routable in the fable lane on the far side of a rounding error. (`=> python3 -c "w=1.0-98/100.0;
print(repr(w), w<=0.02)"` → `0.020000000000000018 False`.)

**Eligibility has no weekly gate at all.** `_excluded` (bin/claude-accounts:3170-3205) tests, in order:
row error · missing session data · **5 h cutoff `session_pct >= S_CUT (0.85)`** (:3182) ·
concurrency-unmeasured · `k_eff >= k_cap` · login-cliff drain. There is **no weekly test**. The only
weekly guards anywhere are the two in-scorer floors — `WEEKLY_FLOOR 0.005` (general, excludes at
weekly ≥ 99.5) and `FABLE_FLOOR 0.02` (fable, ≥ 98). An account at 97 % of its week is fully routable.

**Noise, measured.** With `k_src == "work"` the cap is `KMAX = 8` (:1962-1964), so **one working
session is worth 12.5 % of the score** — four times the observed 3 % gap. Sweeping k_work around the
reconstructed snapshot:

| k_work next3 | k_work next | next3 | next | rank[0] |
|---|---|---|---|---|
| 3 | 5 | 0.000071 | 0.000068 | next3 |
| 2 | 5 | 0.000085 | 0.000068 | next3 |
| 4 | 5 | 0.000057 | 0.000068 | **next** |
| 3 | 4 | 0.000071 | 0.000091 | **next** |

Within one cache TTL the ranking is deterministic — three back-to-back `--rank fable` calls today all
printed `next3 0.000092 / next2 0.000016`, `route-meta … cached=1 quota_age_s=38/39/39`. Across a
sweep boundary it is not. A second instrument flip lurks underneath: `route-meta` on the *first*
(uncached) call today read `k_src=panes k_cap=40 k_work=- k=8 kwork_to=1` — the transcript walk timed
out, so the charge silently moved from `k_work/8` to `k/40`, a different gradient. `k_cap`'s own
docstring says this happens "whenever the box is pathologically loaded, i.e. exactly when the
concurrency count matters most" (:1946-1948) — i.e. during a fleet recovery.

---

## 2. Why lr-fleet picked `next` — it did not walk past the ranker's top

`lf_pick_target`, scripts/limit-recover/lr-fleet.sh:294-308:

```sh
local kind=general t
case "$2" in claude-fable-*) kind=fable ;; esac          # :296
[ "$TARGET" != auto ] && { printf '%s' "$TARGET"; return 0; }
t="$("$ACCOUNTS" --rank "$kind" 2>/dev/null | awk -v s="$1" '$1 != s { print $1; exit }' || true)"   # :301
[ "$t" = none ] && t=""                                  # :306
```

The dry run's own record settles it. `~/.reso/limit-recover/fleet/20260919T170307Z/census.tsv` +
`results.tsv`, 17:04:09-11 Z:

| sid | pane | tier | lane | source | target |
|---|---|---|---|---|---|
| d02d8feb | 112 | `claude-fable-5-1/xhigh` | fable | next4 | **next** |
| 09e64dcb | 111 | `claude-opus-5/high` | general | next4 | **next3** |
| e442434c | 121 | `claude-fable-5-1/xhigh` | fable | next4 | **next** |

The source was `next4` in all three, so the `$1 != s` walk never fired — every pick is rank[0] of its
lane. And both lanes are self-consistent with the reconstructed snapshot at that sweep
(k_work ≈ next 4 / next3 2): `score_fable` → next 0.000091 > next3 0.000085 (**next** wins the fable
lane), `score_general` → next3 0.000151 > next 0.000091 (**next3** wins the general lane).

So the answer to (2) is **not a walk defect and not a lane mismatch in lr-fleet — it is that the
fable lane's top two are separated by less than the resolution of its own concurrency term.** The
operator's `--rank fable` print and lr-fleet's dry run are two samples of the same near-tie taken
under different pane censuses; both are faithful, and they disagree.

Three real defects in `lf_pick_target` nonetheless:

- **D1 — no floor on the walk.** `awk '$1 != s {print; exit}'` accepts the first non-source name
  whatever its score. If the source HAD been next3, this hands back `next` at 2 pp of weekly with no
  test of any kind. It is a *skip-one* filter, not a *fitness* filter.
- **D2 — the reasons are thrown away.** `2>/dev/null` at :301 discards the line
  `claude-accounts: fable excluded — next=fable-exhausted; next4=5h-cutoff` (observed verbatim today).
  When the walk returns empty, lr-fleet:313 prints `no routable target account (claude-accounts --rank
  returned nothing past $acct)` — the operator gets a tautology instead of the four per-account
  reasons the router already computed. This is the fault-visibility half of the operator's ask.
- **D3 — the M7 spread mechanism is structurally unreachable on the recovery path.** `--assign`
  charges the chosen account one phantom working session for `ASSIGN_TTL_MIN` (15 min) so a burst of
  fires walks DOWN the ranking (bin/claude-accounts:70; the term at :1716-1719). It is written at
  scripts/handoff-fire.sh:9296-9299 under the guard `[ "$RECYCLE" = 0 ]`, justified in the comment as
  *"--recycle (same account, no NET new session)"*. **That justification is false for a limit
  recovery**: `lr-handoff.sh --in-place` is a recycle onto a *different* account, and the recovery
  path is the only one that runs N picks back-to-back. So the one caller that most needs spread is the
  one caller the spreader skips, and lr-fleet records no assignment of its own (`grep -n assign
  scripts/limit-recover/*.sh` → no hits).

---

## 3. The rule for recovery targets

### 3a. What a recovery needs that a dispatch does not

A dispatch places a *sizeable* new unit that can be cut to fit the quota. A recovery transplants an
*existing* long session that will immediately replay a cold, large context and keep burning — and a
re-limit costs a whole second recovery cycle (today: ~2.5 min automated per `lr-fleet --one`, plus up
to 15 min of manual pane repair when it lands PARTIAL). The asymmetry is roughly 10:1 against a
re-limit, so the recovery lane must trade strand-avoidance for survival.

**Measured, from `~/.claude/logs/account-utilization.jsonl`, 16:32→18:58 Z today (2.43 h):**

| acct | weekly | pp/h | mean k | **pp per session-hour** |
|---|---|---|---|---|
| next | 97 → 100 | +1.23 | 3.4 | 0.365 |
| next3 | 11 → 16 | +2.05 | 5.1 | 0.406 |
| next2 | 0 → 5 | +2.05 | 1.9 | 1.096 |
| next4 | 88 → 92 | +1.64 | 5.4 | 0.302 |

Median ≈ 0.39 pp per session-hour; worst observed 1.10. **`next` held 2.0 pp at 17:04 and reached
weekly 100 % at 18:58 Z — 1 h 54 m later.** Had lr-fleet fired the two Fable sessions onto it as its
dry run proposed, both would have re-limited inside two hours, and the second recovery would have run
against a fleet one account thinner.

### 3b. The rule: **filter for survival, then rank with the existing score**

Not a new score. The strand objective is correct *among accounts that can host the session*; it is
only the eligibility set that is wrong. Add a **recovery** modifier to `_excluded` plus one floor
inside `score_fable`, all SSOT-optional with code defaults and one kill switch, in the house pattern
(`_cliff_env`, `_term_on`, fail-soft, `CC_ROUTE_*=off` restores byte-identical routing).

| floor | value | maps to | why this number |
|---|---|---|---|
| `RECOVERY_W_FLOOR` | **0.10** on `w_rem` | excludes weekly ≥ 90 | 10 pp ÷ 1.10 pp/session-h (worst observed) = **9 h of survival**; ÷ 0.39 (median) = 26 h. The operator's proposed 0.05 (weekly ≥ 95) gives only 4.5 h at the worst rate — thinner than one 5 h window, and it would have ADMITTED `next4` at 92 % today. |
| `RECOVERY_S_CEIL` | **0.60** on projected 5 h utilization | tighter than `S_CUT` | **Reuse `DESK_5H_FLOOR = 0.60`, already in the SSOT and already argued** (accounts.json `.router._desk`). ⚠️ The operator's proposed "5 h ≥ 90" is **weaker than the gate already in force** — `_excluded:3182` cuts at `S_CUT = 0.85`. Shipping 0.90 as the only 5 h test would be a *loosening*, not a guard. |
| `RECOVERY_F_FLOOR` | **0.05** on `f_eff` | fable ≥ 90 when weekly is not binding (`0.5 × (1−0.90) = 0.05`) | exactly the operator's proposal, expressed in the unit `score_fable` already computes, so it also catches the weekly-capped case that today slipped past `FABLE_FLOOR` on a float ULP. |

Applied to today's 17:00 Z snapshot: `next` (98) excluded `recovery-weekly-thin`; `next4` (92, and 5 h
= 100) excluded; **survivors next3 (11) and next2 (0)**, ranked by the unchanged score → next3 first
(nearest reset among survivors, which is still the right strand answer). No recovery would have been
parked for want of a target.

**Reason strings classify as POLICY, not data** (`reason_class`, bin/claude-accounts:3551 ff) so an
all-thin fleet exits 2 and lr-fleet parks loudly rather than firing blind.

**Declined, with the reason (so it is not silently missing):** *"an imminent weekly reset rescues a
thin account"* — true (3 pp with a reset in 40 min is a fine target if 40 min of stall is acceptable)
but it re-imports the deadline reasoning that caused this bug, and the stall is invisible to every
watchdog. Excluded conservatively; the residual is a small amount of end-of-window capacity.

### 3c. Spreading N simultaneous recoveries

Do not build a second spreader. **Make the recovery path record the phantom the router already
consumes.** Each phantom adds 1 to `k_eff` (:1839) against `KMAX = 8`, i.e. **−12.5 % of score per
pick** — measured above as more than enough to flip a 3-7 % gap, so N picks inside one 90 s TTL walk
down the ranking instead of stacking. Two edits:

1. `lf_pick_target` records `"$ACCOUNTS" --assign "$t" --src lr-fleet` after a successful pick
   (skipped when `$DRY = 1`, mirroring handoff-fire's own guard).
2. handoff-fire's `[ "$RECYCLE" = 0 ]` guard at :9296 gains `|| [ -n "$TARGET_ACCOUNT_DIFFERS" ]` —
   or, more simply, the comment's premise is corrected and the guard becomes "skip only when the
   recycle stays on the same account".

---

## 4. The exact code change

### 4a. `accounts.json` `.router` (SSOT, all OPTIONAL — code defaults match)

```json
"_recovery": "Recovery lane (U13, 2026-09-19). A recovery is not a dispatch: the session being placed is an EXISTING long context that resumes burning immediately, and a re-limit costs a whole second recovery cycle (~2.5 min automated + up to 15 min manual pane repair, measured 2026-09-19), so survival outranks strand-avoidance. Measured weekly burn that day: 0.30-1.10 pp per session-hour (median 0.39) across four accounts over 2.43 h. RECOVERY_W_FLOOR 0.10 = 9 h of survival at the WORST observed rate. RECOVERY_S_CEIL reuses DESK_5H_FLOOR's already-argued 0.60 -- note S_CUT (0.85) is ALREADY stricter than the 0.90 first proposed. RECOVERY_F_FLOOR 0.05 = fable_pct 90 at coupling 0.5, and it also catches the weekly-capped case that passed FABLE_FLOOR on a float ULP at weekly 98. Kill: CC_ROUTE_RECOVERY=off.",
"RECOVERY_W_FLOOR": 0.10,
"RECOVERY_S_CEIL": 0.60,
"RECOVERY_F_FLOOR": 0.05
```

### 4b. `bin/claude-accounts`

```python
# --- after CLIFF_* constants, ~:1695 -----------------------------------------------------------
RECOVERY_W_FLOOR_DEFAULT = 0.10
RECOVERY_S_CEIL_DEFAULT  = 0.60
RECOVERY_F_FLOOR_DEFAULT = 0.05

def recovery_floors(R):
    """(w_floor, s_ceil, f_floor) for the recovery lane. CC_ROUTE_RECOVERY=off neutralises all
    three (byte-identical pre-U13 routing), per the R8 kill-switch pattern."""
    if not _term_on("CC_ROUTE_RECOVERY"):
        return 0.0, 1.0, 0.0
    return (_cliff_env("CC_ROUTE_RECOVERY_W_FLOOR", R.get("RECOVERY_W_FLOOR", RECOVERY_W_FLOOR_DEFAULT)),
            _cliff_env("CC_ROUTE_RECOVERY_S_CEIL",  R.get("RECOVERY_S_CEIL",  RECOVERY_S_CEIL_DEFAULT)),
            _cliff_env("CC_ROUTE_RECOVERY_F_FLOOR", R.get("RECOVERY_F_FLOOR", RECOVERY_F_FLOOR_DEFAULT)))

# --- _excluded, :3170 — new kwarg, default False so every existing caller is byte-identical ----
def _excluded(r, R, cliff=True, k_of=None, recovery=False):
    ...
    if su >= R["S_CUT"] and (sr is None or sr >= R["EPS_H"]):
        return "5h-cutoff"
    if recovery:
        w_floor, s_ceil, _ = recovery_floors(R)
        # The floors are SURVIVAL facts, so they sit here (eligibility) and not in the score.
        # PROJECTED 5h, same input the desk lane and _soft use -- a recovered session resumes
        # burning at once, so what matters is where the window is HEADING, not where it is.
        if _su_projected(r, R) >= s_ceil:
            return "recovery-5h-thin"
        wp = r.get("weekly_pct")
        if wp is None:
            return "no-weekly-data"          # unknown headroom is not headroom (fail closed)
        if max(0.0, 1.0 - wp / 100.0) < w_floor:
            return "recovery-weekly-thin"
    if k_src(r) == "unmeasured":
        ...

# --- score_fable, :3483 — the fable floor rises for a recovery --------------------------------
def score_fable(r, cfg, win, cliff=True, recovery=False):
    R, F = cfg["router"], cfg["frontier"]
    reason = _excluded(r, R, cliff, recovery=recovery)
    ...
    floor = max(R["FABLE_FLOOR"], recovery_floors(R)[2]) if recovery else R["FABLE_FLOOR"]
    if f_eff <= floor:
        return None, "recovery-fable-thin" if recovery and f_eff > R["FABLE_FLOOR"] else "fable-exhausted"

# --- score_general, :3209 — same kwarg, passed straight through --------------------------------
def score_general(r, cfg, cliff=True, recovery=False):
    reason = _excluded(r, R, cliff, recovery=recovery)

# --- _rank_pass / ranked, :3491 / :3505 — thread the flag; the cliff YIELD is unchanged --------
def _rank_pass(rows, cfg, win, kind, cliff, recovery=False): ...
def ranked(rows, cfg, win, kind, recovery=False): ...
#   NB: the recovery floors are NEVER yielded the way the cliff is. A drained account still works;
#   a thin one does not. If the floors empty the set, that is a real refusal -> exit 2.

# --- argv, :5620-5632 — a MODIFIER, not a fourth lane (a `recovery` kind would need a
#     recovery-general and a recovery-fable twin; the doubling is the tell -- same argument the
#     --max-wait comment at :5374-5376 makes against `--route-cached`) ---------------------------
recovery = "--recovery" in args
...
cand, reasons = ranked(rows, cfg, win, kind, recovery=recovery)
#   and route-meta gains `recovery=1|0` so the decision is answerable from disk afterwards.
```

Reason strings `recovery-weekly-thin` / `recovery-5h-thin` / `recovery-fable-thin` are POLICY (they
must NOT appear in the data-unavailable set at :3551 ff), so an all-thin fleet exits 2.

### 4c. `scripts/limit-recover/lr-fleet.sh`

```sh
lf_pick_target() { # $1=source account $2=tier → account name on stdout / rc 1
  local kind=general t err
  case "$2" in claude-fable-*) kind=fable ;; esac
  [ "$TARGET" != auto ] && { printf '%s' "$TARGET"; return 0; }
  [ -x "$ACCOUNTS" ] || return 1
  err="$FLEET_DIR/$RUN/rank.$kind.stderr"; mkdir -p "$FLEET_DIR/$RUN"
  # --recovery: survival floors, because a target that re-limits costs a whole second recovery
  # cycle (U13: `next` at 2pp of weekly reached 100% 1h54m after being named on 2026-09-19).
  # stderr is KEPT: the router already names every excluded account and its reason, and
  # discarding it left the caller printing "returned nothing past $acct", a tautology.
  t="$("$ACCOUNTS" --rank "$kind" --recovery 2>"$err" | awk -v s="$1" '$1 != s { print $1; exit }' || true)"
  [ "$t" = none ] && t=""
  [ -n "$t" ] || { LF_RANK_WHY="$(tr '\n' ' ' < "$err")"; return 1; }
  # M7 spread: charge the pick one phantom so N back-to-back recoveries inside the 90s rank cache
  # TTL walk DOWN the ranking instead of stacking. handoff-fire skips this for a --recycle
  # (handoff-fire.sh:9296, "same account, no NET new session") -- false for an in-place recovery,
  # which is a recycle onto a DIFFERENT account.
  [ "$DRY" = 1 ] || "$ACCOUNTS" --assign "$t" --src lr-fleet >/dev/null 2>&1 || true
  printf '%s' "$t"
}
```

and at :313 the parked note carries the reasons:

```sh
target="$(lf_pick_target "$acct" "$tier")" || {
  echo "lr-fleet: $sid — no routable target past $acct: ${LF_RANK_WHY:-no reason reported by claude-accounts}" >&2
  lf_row "$sid" "$pane" "$pane" "$acct" "-" "parked" "no routable target: ${LF_RANK_WHY:-unknown}"; return 1; }
```

---

## 5. The bats test shape

Two suites. The scorer suite copies `tests/account-cliff-routing.bats`'s harness verbatim (fixture
`$HOME`, `CLAUDE_ACCOUNTS_JSON` pointing at a scratch cfg built FROM the repo `accounts.json` so
constants are DERIVED not hand-copied, unreachable endpoints, `ca.LOG_PATH` redirected, and the
`LOAD` / `row()` helpers). The fleet suite copies `tests/lr-fleet.bats`'s stub harness.

### `tests/account-recovery-lane.bats`

```bash
setup() {
  unset CC_BATS_ACTIVE
  unset CC_ROUTE_RECOVERY CC_ROUTE_RECOVERY_W_FLOOR CC_ROUTE_RECOVERY_S_CEIL CC_ROUTE_RECOVERY_F_FLOOR
  # ... identical to tests/account-cliff-routing.bats:34-72 ...
}

@test "floors are DERIVED from the repo SSOT, never hand-copied" {
  run python3 -c "$LOAD"'
w,s,f = ca.recovery_floors(R)
assert (w,s,f) == (R["RECOVERY_W_FLOOR"], R["RECOVERY_S_CEIL"], R["RECOVERY_F_FLOOR"]), (w,s,f)
assert w == 0.10 and s == 0.60 and f == 0.05'
  [ "$status" -eq 0 ]
}

@test "THE INCIDENT: weekly 98 / fable 7 / reset 11h is rank[0] for dispatch and EXCLUDED for recovery" {
  # The pre-fix behaviour is asserted first, so this case can only go green by the FIX and not by
  # an unrelated change to the fixture (the arms must differ in one thing).
  run python3 -c "$LOAD"'
nxt  = row(acct="next",  weekly_pct=98, weekly_reset_h=11.0, fable_pct=7, fable_reset_h=11.0,
           session_pct=3, k_work=4, k=4)
nxt3 = row(acct="next3", weekly_pct=11, weekly_reset_h=67.0, fable_pct=0, fable_reset_h=67.0,
           session_pct=2, k_work=2, k=2)
cfg2 = {"router": R, "frontier": cfg["frontier"]}
s_n,_  = ca.score_fable(nxt,  cfg2, WIN_OPEN)
s_3,_  = ca.score_fable(nxt3, cfg2, WIN_OPEN)
assert s_n > s_3, (s_n, s_3)                      # the dispatch lane, unchanged: next wins
assert ca.score_fable(nxt,  cfg2, WIN_OPEN, recovery=True) == (None, "recovery-weekly-thin")
assert ca.score_fable(nxt3, cfg2, WIN_OPEN, recovery=True)[0] is not None'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "the float ULP at weekly 98 cannot admit a thin account any more" {
  run python3 -c "$LOAD"'
r = row(weekly_pct=98, fable_pct=7)
assert (1.0 - 98/100.0) > R["FABLE_FLOOR"]        # the ULP is real; pin it so the case is honest
assert ca._excluded(r, R, recovery=True) == "recovery-weekly-thin"'
  [ "$status" -eq 0 ]
}

@test "the 5h ceiling is TIGHTER than S_CUT, in the direction the guard needs" {
  run python3 -c "$LOAD"'
assert R["RECOVERY_S_CEIL"] < R["S_CUT"], "a recovery 5h floor at/above S_CUT is a LOOSENING"
r = row(session_pct=70, session_reset_h=4.0)      # routable for dispatch, thin for recovery
assert ca._excluded(r, R) is None
assert ca._excluded(r, R, recovery=True) == "recovery-5h-thin"'
  [ "$status" -eq 0 ]
}

@test "fable-lane floor bites at fable 90 while weekly is fat" {
  run python3 -c "$LOAD"'
cfg2 = {"router": R, "frontier": cfg["frontier"]}
r = row(weekly_pct=5, fable_pct=91, fable_reset_h=40.0, weekly_reset_h=40.0)
assert ca.score_fable(r, cfg2, WIN_OPEN)[0] is not None            # dispatch: fine
assert ca.score_fable(r, cfg2, WIN_OPEN, recovery=True) == (None, "recovery-fable-thin")'
  [ "$status" -eq 0 ]
}

@test "KILL SWITCH: CC_ROUTE_RECOVERY=off is byte-identical to pre-U13" {
  run env CC_ROUTE_RECOVERY=off python3 -c "$LOAD"'
cfg2 = {"router": R, "frontier": cfg["frontier"]}
for wp in (0, 50, 98, 99):
    r = row(weekly_pct=wp, fable_pct=7, session_pct=70)
    assert ca.score_fable(r, cfg2, WIN_OPEN, recovery=True) == ca.score_fable(r, cfg2, WIN_OPEN)'
  [ "$status" -eq 0 ]
}

@test "the floors are NOT yielded the way the cliff is: an all-thin fleet exits 2, never a pick" {
  seed "next3:none:98" "next2:none:99"
  run "$CA_BIN" --rank fable --recovery
  [ "$status" -eq 2 ]                              # POLICY, not data (exit 3)
  [[ "$output" == *none* ]]
  [[ "$stderr" == *recovery-weekly-thin* ]] || true   # reasons are named on stderr
}

@test "existing callers are untouched: --rank fable without --recovery is unchanged" {
  seed "next3:none:98" "next2:none:0"
  run "$CA_BIN" --rank fable
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == next3* ]] || [[ "${lines[0]}" == next2* ]]
}
```

**Mutation arms this suite must kill** (per `green-in-both-arms-is-an-equivalence-guard`): flip
`>=` to `>` in the `w_floor` test; drop `recovery=recovery` from the `_excluded` call in
`score_fable`; set `RECOVERY_S_CEIL` to 0.90. Each must turn exactly one case red.

### `tests/lr-fleet-recovery-target.bats` (or three cases appended to `tests/lr-fleet.bats`)

```bash
# harness: tests/lr-fleet.bats:6-45 verbatim, with a RECORDING claude-accounts stub
cat > "$CC_ACCOUNTS_BIN" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "${CA_LOG:?}"
case "$*" in
  *--assign*)   exit 0 ;;
  *--rank*)     printf 'next3 0.9\nnext4 0.5\n'
                echo "claude-accounts: fable excluded — next=recovery-weekly-thin" >&2 ;;
esac
SH

@test "the recovery pick asks for --recovery" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  run bash "$FLEET" --recover
  grep -q -- '--rank fable --recovery' "$CA_LOG" || { cat "$CA_LOG"; false; }
}

@test "SPREAD: a successful pick charges the target one phantom (handoff-fire skips it on --recycle)" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  run bash "$FLEET" --recover
  grep -q -- '--assign next3 --src lr-fleet' "$CA_LOG" || { cat "$CA_LOG"; false; }
}

@test "--dry-run picks but charges NOTHING" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  run bash "$FLEET" --recover --dry-run
  ! grep -q -- '--assign' "$CA_LOG" || { cat "$CA_LOG"; false; }
}

@test "FAULT VISIBILITY: an empty rank parks with the router's OWN reasons, not a tautology" {
  printf '#!/bin/bash\ncase "$*" in *--rank*) echo none; echo "claude-accounts: no routable account for fable: next=recovery-weekly-thin; next4=recovery-5h-thin" >&2; exit 2 ;; esac\n' > "$CC_ACCOUNTS_BIN"
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  run bash "$FLEET" --recover
  [[ "$output" == *"recovery-weekly-thin"* ]] || { echo "$output"; false; }
  [[ "$output" != *"returned nothing past"* ]] || { echo "$output"; false; }
}
```

---

## 6. Residuals and open questions

- **Burn rate is measured over ONE 2.43 h window on one day, n = 4 accounts.** 0.30-1.10 pp per
  session-hour is the whole calibration basis for `RECOVERY_W_FLOOR = 0.10`. Re-derive before
  quoting: the command is in §3a. `claude-accounts` already computes `burn_wk_ppd` (`apply_burn`,
  :2409-2430) and `exchange_rate` (:2323) — a later version of this floor should read those instead
  of a constant, but doing it now would put a runtime dependency on a measurement that abstains under
  load, which is exactly when a recovery runs.
- **The instrument flip is untreated.** `k_src` moving between `work` (cap 8) and `panes` (cap 40)
  changes the concurrency gradient by 5×, and it flips precisely when the box is loaded. Today's
  first uncached call read `kwork_to=1`. A recovery lane that leans on `_soft` inherits that. Not
  fixed here; worth its own unit.
- **The near-tie itself is not fixed, only made harmless.** With survival floors in place a coin flip
  between two *survivable* accounts is fine. If the lead wants determinism, the cheap rule is a
  tie-break on absolute weekly headroom when the top two scores are within `REPICK_RATIO`'s noise
  band — but `REPICK_RATIO = 4.0` (:1787) was sized for a different question (should a recycle move a
  pane) and should not be reused without argument.
- **Unmeasured:** whether a transplanted session's first hour burns *faster* than the 0.39 pp/h fleet
  median (a cold cache replaying a large context plausibly does). If it does, `RECOVERY_W_FLOOR`
  should rise. The measurement is available — diff `weekly_pct` across a recovery's first hour in
  `account-utilization.jsonl`, keyed on the fleet run timestamps in
  `~/.reso/limit-recover/fleet/one-*/results.tsv` — and I did not run it.
