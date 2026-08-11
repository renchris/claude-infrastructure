# R1 — Route replay: was `next3` at 2026-08-11T20:05:28Z correct-by-policy?

**VERDICT: CORRECT-BY-POLICY. Margin +17.2%, not a tie. No defect, no stale cache, no phantom
feedback, no k_eff miscount.** The operator's expectation was formed on a surface that does not
render the lane bare `claude` uses. Two real (secondary) defects found: an observability gap and a
load-dependent k_eff discontinuity.

Source of every code claim: `/Users/chrisren/Development/claude-infrastructure/bin/claude-accounts`
(3348 lines), reached via `readlink -f ~/.claude/bin/claude-accounts`. Constants SSOT:
`/Users/chrisren/Development/claude-infrastructure/accounts.json` (`~/.claude/accounts.json` is a
symlink to it, verified `ls -la`).

---

## 1. The shipped policy, at source

### Constants (`accounts.json` `router` block — quoted values, live)

| key | value | consumed at |
|---|---|---|
| `S_CUT` | **0.85** | `_excluded` :1462, `_soft` :1124, `score_interactive` :1525 |
| `S_SOFT` | **0.5** | `_soft` :1124 (interactive does NOT use it — see :1521-1523) |
| `SF_FLOOR` | **0.05** | `_soft` :1124, `score_interactive` :1525 |
| `KMAX` | **8** | `_excluded` :1464, KF :1125/:1526 |
| `KFLOOR` | **0.1** | KF :1125/:1526 |
| `MARGIN_H` | **0.5** | `horizon` :1118 |
| `EPS_H` | **0.25** | `horizon` :1118, `_excluded` :1462 |
| `NO_RESET_H` | **168.0** | `horizon` :1117 |
| `WEEKLY_FLOOR` | **0.005** | :1484, :1519 |
| `FABLE_FLOOR` | 0.02 | `score_fable` :1554 |
| `JB_BONUS` | 1.25 | `score_fable` :1558 |
| `URGENCY_EXP` | **2.0** | `urgency_exp` :1261-1262 → `score_general` :1489 |
| `KWORK_WINDOW_MIN` | **10** | `working_concurrency` :461-463 |
| `ASSIGN_TTL_MIN` | **15** | `assignment_counts` :1283-1284 |
| `PROJ_LOOKAHEAD_H` | **1.0** | `_su_projected` :1348 |

Module-level defaults that back them: `KWORK_WINDOW_MIN=10.0`, `ASSIGN_TTL_MIN=15.0`,
`ASSIGN_PRUNE_LINES=400`, `URGENCY_EXP_DEFAULT=2.0`, `PROJ_LOOKAHEAD_H=1.0` (:1247-1251);
cliff bands `CLIFF_SOFT_H=168.0`, `CLIFF_DRAIN_H=48.0`, `CLIFF_SOFT_FACTOR=0.25` (:1150-1152).

### The two scorers

```
score_interactive (:1492-1528)  = w_rem · s_rem · KF · CF · cliff        NO 1/T term
    w_rem  = max(0, wtgt − weekly_pct/100),  wtgt = 0.98 if credits_on else 1.00   (:1517-1518)
    s_rem  = clamp((S_CUT − su_proj)/S_CUT, SF_FLOOR, 1.0)                          (:1525)
    KF     = clamp(1 − k_eff/KMAX, KFLOOR, 1.0)                                     (:1526)
    CF     = 1.0 (credits_on false on all four rows)                                (:1527)

score_general     (:1475-1489)  = (w_rem / T**γ) · SF · KF · CF · cliff,  γ = 2
    T      = horizon(weekly_reset_h) = max(reset_h − 0.5, 0.25)                     (:1117-1118)
    SF     = clamp((S_CUT − su_proj)/(S_CUT − S_SOFT), SF_FLOOR, 1.0)               (:1124)
```

`_excluded` (:1455-1472), shared by BOTH lanes, in order: `error` present → `session_pct is None`
→ `su ≥ S_CUT` → **`k_eff(r) ≥ KMAX`** → cliff drain.

`k_eff` (:1265-1273): `(k_work if k_work is not None and CC_ROUTE_KWORK on else k) + k_phantom`.
`k_work` is produced by `working_concurrency` (:446-505) — transcripts written inside 10 min —
and is **`None` whenever the walk exceeds `budget_s=2.0`** (:457-459, :485-486, :492-493), in which
case `collect` (:1055, :1077) stamps `None` on **every** row and the whole sweep falls back to the
pane census `k`.

`_su_projected` (:1338-1352): `su + burn_5h_ph · min(PROJ_LOOKAHEAD_H, session_reset_h)`,
soften-only. `_cliff_factor` (:1206-1210): 1.0 outside the SOFT band. All four accounts had
`login_expires_h` 450–639 h ⇒ `cliff_band = "none"` ⇒ factor 1.0 (live cache
`/tmp/claude-accounts-cache.json`; `route-meta` line confirms `cliff_band=none cliff_h=450.8`).

The launcher's call site (`~/.claude/lib/claude-launcher.zsh` :84) backgrounds
`claude-accounts --assign "$acct" --src claude-launcher` **after** the pick.

---

## 2. State reconstruction at 2026-08-11T20:05:28Z

`--max-wait 0` is **cache-only** (:118-121, `get_data` :1856-1864), so the pick read the last cache
written. The utilization series (`~/.claude/logs/account-utilization.jsonl`, written by
`record_utilization` :1710-1740, rate-limited 1/300 s) gives the sweep at **20:03:33Z (d = −114 s)**
and four consecutive prior samples:

| sweep (local) | next k / 5h / wk | next4 | next3 | next2 |
|---|---|---|---|---|
| 12:45:37 | 1 / 3% / 44% | 1 / 7% / 38% | **2** / 10% / 2% | 4 / 9% / 46% |
| 12:51:10 | 1 / 3% / 44% | 1 / 7% / 38% | **2** / 11% / 2% | 6 / 10% / 46% |
| 12:57:25 | 0 / 3% / 44% | 1 / 8% / 38% | **2** / 11% / 3% | 6 / 10% / 46% |
| **13:03:33** | **0 / 3% / 44%** | **2 / 8% / 38%** | **2 / 11% / 3%** | **6 / 11% / 46%** |
| 13:08:39 | 0 / 3% / 44% | 2 / 8% / 38% | **3** / 11% / 3% | 6 / 12% / 47% |
| 13:14:47 | 0 / 3% / 44% | 2 / 8% / 38% | **7** / 12% / 3% | 5 / 12% / 47% |

next3's census `k = 2` across **four consecutive samples** spanning 12:45→13:03 — the input is not
a lucky single read.

**Phantoms at route time** (`assignment_counts` :1276-1298, TTL 900 s, replayed from
`~/.claude/logs/account-assignments.jsonl`):

| assign ts (UTC) | acct | src | age at 20:05:28 | inside 900 s TTL? |
|---|---|---|---|---|
| 19:06:59 | next4 | handoff-fire | 3508 s | no |
| 19:09:07 | next | handoff-fire | 3380 s | no |
| 19:40:58 | next3 | handoff-fire | 1470 s | no |
| 19:48:35 | next2 | handoff-fire | 1013 s | no |
| 19:49:46 | next2 | handoff-fire | 942 s | **no** (misses by 42 s) |
| 19:58:08 | **next4** | handoff-fire | 439 s | **YES → k_phantom(next4)=1** |
| 20:05:28.92 | next3 | claude-launcher | −0.9 s | written *after* the pick |

⇒ **`k_phantom` = {next4: 1}. next and next3 both carried ZERO phantoms.** The 19:40–19:58 fire
burst had already aged out for next3 and next2. Phantom feedback is **REFUTED** as a cause.

**Burn projection**: `apply_burn` (:1387-1425) uses the newest adjacent pair. 12:57:25→13:03:33:
next Δ5h = 0, next3 Δ5h = 0 ⇒ `burn_5h_ph = 0` for both ⇒ `_su_projected == su`. Projection is
**non-causal for the #1/#2 contest** (it does shave next2/next4, neither of which was in contention).

---

## 3. Hand computation — `score_interactive`, 20:05:28Z

Re-run through the module's own `score_interactive` (SourceFileLoader replay, not re-implemented
arithmetic) under both `k_work` branches — **the answer is identical**, because next3's census and
its working count were both 2:

**Branch A — `k_work` present {next 0, next4 1, next3 2, next2 4}** (the mapping observed in the
13:13:34 cache):

| acct | w_rem | s_rem | KF | CF | cliff | **score** |
|---|---|---|---|---|---|---|
| **next3** | 1.00−0.03 = **0.97** | (0.85−0.11)/0.85 = **0.87059** | 1−2/8 = **0.750** | 1.0 | 1.0 | **0.633353** |
| next | 1.00−0.44 = 0.56 | (0.85−0.03)/0.85 = 0.96471 | 1−0/8 = 1.000 | 1.0 | 1.0 | 0.540235 |
| next4 | 0.62 | 0.90588 | 1−2/8 = 0.750 | 1.0 | 1.0 | 0.421235 |
| next2 | 0.54 | 0.87059 | 1−4/8 = 0.500 | 1.0 | 1.0 | 0.235059 |

**Branch B — `k_work` absent ⇒ census fallback {0, 2, 2, 6}:** next3 0.633353, next 0.540235,
next4 0.351029, next2 0.117529.

**Ranking (both branches): next3 ▸ next ▸ next4 ▸ next2.**
**Margin #1 over #2 = 0.633353 / 0.540235 = 1.1724 → +17.24 %.**

The pick is driven by **weekly headroom**: next3 had used **3%** of its week (w_rem 0.97) against
next's **44%** (w_rem 0.56) — a 1.73× advantage that next's cleaner 5h window (0.965 vs 0.871,
1.11×) and zero concurrency (1.00 vs 0.75, 1.33×) together (1.48×) could not overcome. That is
exactly the objective `score_interactive`'s docstring states (:1503-1506): *maximise RUNWAY* for a
desk that "lives for hours or days".

## 3b. `score_general` on the same inputs — why general says `next`

γ = 2, `T = weekly_reset_h − 0.5`:

| acct | w_rem | T (h) | T² | SF | KF | **score** |
|---|---|---|---|---|---|---|
| **next** | 0.56 | 103.4 | 10 690 | 1.00 | 1.000 | **5.238e-05** |
| next4 | 0.62 | 108.4 | 11 751 | 1.00 | 0.750 | 3.957e-05 |
| next2 | 0.54 | 86.4 | 7 465 | 1.00 | 0.500 | 3.617e-05 |
| next3 | 0.97 | 159.4 | 25 408 | 1.00 | 0.750 | 2.863e-05 |

Margin +32.4% (branch A) / +58.8% (branch B). **The γ=2 deadline term inverts the two lanes:**
next3's 97% headroom is divided by a 159 h horizon squared, which is 2.38× next's — so the account
that *wins* the interactive lane comes **LAST** in general. Live confirmation, run this session:
`claude-accounts --rank general` → `next 0.000053 · next4 0.000040 · next2 0.000027`.

**This is the whole explanation of the operator's surprise, and it is by design** (:1493-1501): the
two lanes are deliberately opposite-shaped, and `next3` topping interactive while bottoming general
is the *signature* of the policy working, not of a fault.

---

## 4. What flipped the pick between 13:05 and now — verdict per mechanism

### (a) `k_eff` / live-session count — **THE CAUSE, and it is the router observing its own correct pick**

Full causal chain, every link measured:

1. 13:05:28 — route reads the 13:03:33 sweep: next3 `k`=2, `k_work`=2, `k_phantom`=0 ⇒ k_eff **2**.
2. 13:05:28.92 — launcher appends `{"acct":"next3","src":"claude-launcher"}` ⇒ next3 carries
   **+1 phantom** until 13:20:28.
3. 13:06:06 — a transcript is BORN under `~/.claude-tertiary/projects/-Users-chrisren-Development--worktrees-wt-pool-1/dde93546-….jsonl`
   (`st_birthtime`, 38 s after the assign). `~/.claude-tertiary` **is** account `next3`
   (`cfg["accounts"]`: next→`.claude-next`, next2→`.claude-secondary`, next3→`.claude-tertiary`,
   next4→`.claude-quaternary`). **That session is this research wave's lead — the launch under
   investigation.**
4. 13:08:39 — census next3 = 3 (the new desk). k_eff = 2 (k_work) + 1 (phantom) = **3** ⇒
   next3 0.52779 < next 0.54024. **The pick had already flipped ~3 minutes after the launch.**
5. 13:13:22 – 13:16:36 — **eight** sibling transcripts born in the same worktree slug: the research
   wave this brief belongs to.
6. 13:14:47 — census next3 = 7, `k_work` absent that sweep ⇒ k_eff = 7 + 1 = **8 = KMAX** ⇒
   `_excluded` → `kmax-concurrency`. Live: `claude-accounts --rank interactive` prints
   `interactive excluded — next3=kmax-concurrency`.
7. Measured live during this investigation: `concurrency()` = {next 0, next4 2, **next3 12**,
   next2 5}; `working_concurrency()` = {next 0, next4 1, **next3 10**, next2 5}.

**Verdict: not a defect. Negative feedback, working as designed.** The router routed a desk to the
idlest-by-quota account; that desk then became the fleet's busiest account; the router now routes
away from it. `--assign` phantoms were **not** implicated in the original pick (proven in §2) and
account for only 1 of the 8 units of k_eff now.

### (b) Cache staleness — **REFUTED as causal**

Served cache age at route time ≈ **115 s** (13:03:33 sweep, `--max-age 600` admits it; the 90 s
default TTL would have rejected it). But the quota inputs were **flat for the whole preceding hour**
(next 3%/44%, next3 10-11%/2-3% across five sweeps), and next3's census read 2 in four consecutive
samples. A perfectly fresh sweep at 13:05:28 would have produced the same ranking. `--max-age 600`
is not what chose next3.

Recovered snapshots used: `~/.claude/logs/claude-accounts-lastgood.json` (mtime 13:12:11, quotas
`quota_as_of` 20:12:10Z — next 3/44, next2 12/47, next3 11/3, next4 8/38) and
`/tmp/claude-accounts-cache.json` (single-slot, overwritten; the 20:05 generation is **UNRECOVERABLE**
— reconstructed instead from the utilization series, which is the durable store).

*(Note: the launchd job the brief guessed at, `com.claude.auth-timeseries`, does not exist by that
name here. The live producer is the keep-warm daemon, `~/.claude/logs/accounts-keepwarm.out.log`,
whose recent sweeps take 2.4 s – 24.4 s; it has no per-sweep timestamps, so its own cadence around
20:05 is **UNKNOWN**.)*

### (c) 5h window rollover — **REFUTED, definitively**

Session resets from the live cache: next **23:40:00Z**, next2 21:59:59Z, next3 **22:50:00Z**,
next4 22:59:59Z. The interval under study is 20:05Z → 20:16Z. **No 5h window rolled.** Also
irrelevant by construction: `s_rem` moved next3 0.87059 → 0.85882 over the interval (5h 11%→12%),
worth −1.35% of score — an order of magnitude short of the 17.2% margin.

---

## 5. Verdict + stability analysis

**CORRECT-BY-POLICY — and not near-tie at the moment of decision (+17.24%).**
But the *stability* answer is the more important one, and it is worse than the incident:

**`KF` is quantized in 1/8 steps ⇒ one session moves any score by 12.5–100% of a KF unit.**
Sweeping k_eff(next3) against a fixed next (0.540235):

| k_eff(next3) | next3 score | winner | ratio |
|---|---|---|---|
| 0 | 0.84447 | next3 | 1.563 |
| 1 | 0.73891 | next3 | 1.368 |
| **2** | **0.63335** | **next3** | **1.172** ← the actual decision |
| **3** | **0.52779** | **next** | **0.977** ← one session later |
| 4 | 0.42224 | next | 0.782 |
| 7 | 0.10556 | next | 0.195 |
| 8 | — | excluded (`kmax-concurrency`) | — |

**Breakeven `KF* = 0.6397 ⇒ k* = 2.88`.** next3 wins iff `k_eff ≤ 2`, loses at `k_eff ≥ 3`.
**The entire decision turned on a single concurrent session** — and the launcher's own `--assign`
supplies exactly one, with a 15-minute TTL.

Three properties make the pick non-reproducible minute to minute:

1. **Self-inflicted 15-min anti-stickiness.** A second bare `claude` inside 15 min sees
   `k_phantom = 1` on the account the first one got, i.e. −12.5% of a KF unit. At the 13:05 state
   that alone was enough to hand launch #2 a different account. Correct for dispatch spread
   (`--src handoff-fire`); **arguably wrong for a human's desk**, which the operator may reasonably
   expect to be sticky. *Design question, not a bug.*
2. **A binary, load-dependent `k_eff` source.** `working_concurrency` returns `None` past a **2.0 s**
   budget (:457-459) and the whole sweep silently reverts to the pane census. Measured here: the
   walk normally takes **0.04–0.07 s** (826 transcripts), but the 13:14:47 cache had `k_work`
   absent while the 13:13:34 cache had it present — 73 s apart, same box. For next3 that switch is
   `k_eff` 2 → 7, i.e. `KF` 0.750 → 0.125 (−83%) or outright exclusion. **A routing input that
   changes by 6× depending on whether a filesystem walk finished inside 2 s is a real fragility**,
   and it degrades hardest exactly when the box is loaded — the moment the count matters most.
   (Whether the 13:14:47 absence was the timeout or a `CC_ROUTE_KWORK` env difference is **UNKNOWN**;
   the code emits no diagnostic on the `None` return.)
3. **Lane inversion with no visible arbiter.** next3 was #1 interactive and #4 general on the same
   snapshot.

**So: chaotic in magnitude, but self-correcting in direction.** The feedback loop is *negative*
(routing to X raises k_X, which lowers X's score), so it spreads load rather than oscillating
destructively. The reproducibility complaint is real; the "wrong pick" complaint is not.

### Secondary defect found (observability, not scoring) — the actual source of the surprise

`render_readout`'s footer (:2630-2632) prints **exactly two** route lines:
```python
print("  " + route_line("general", rank_g, gre, …))
print("  " + route_line("fable",   rank_f, fre, …))
```
**There is no `interactive` line.** So `/accounts` shows the operator the pick for the two lanes
`bare claude` does **not** use, and never shows the lane it does. The operator expected `next`
because that is the only answer the dashboard has ever given them — and it was, and still is, the
correct answer *for general*. **One-line fix: add a third `route_line("interactive", …)`.**

---

## 6. Routing decision log + churn

The "931 recorded routing decisions" in `claude-launcher.zsh` :26-27 refers to
**`~/.claude/route/route.jsonl`** (1254 lines, 2026-07-16 → 2026-08-11, written by
`bin/cc-route`; `claude-accounts` :3141 references it). Schema: `ts · slot · outcome · detail
("model=… acct=… effort=… reason=general route") · cliff_band · cliff_h · quota_age_s ·
quota_cached · cliff_yielded`.

**Consecutive-pick churn (1234 entries carrying an `acct=`):**

| window | n | changes | **churn** | distribution |
|---|---|---|---|---|
| all | 1234 | 254 | **20.6%** | next4 456 · next3 378 · next2 217 · next 183 |
| last 100 | 100 | 43 | **43.4%** | next2 31 · next 26 · next3 26 · next4 17 |
| **last 40** | 40 | 15 | **38.5%** | next2 21 · next 11 · next4 7 · next3 1 |
| slot=lead | 1220 | 251 | 20.6% | — |
| slot=judgment-dense | 8 | 4 | 57.1% | — |
| slot=adversarial | 3 | 2 | 100% | — |

Last-40 sequence:
`next next next2 next4 next2 next4 next next next2 next2 next2 next2 next2 next2 next2 next next next2 next2 next2 next2 next2 next2 next2 next2 next2 next2 next4 next next next next4 next4 next4 next3 next2 next2 next next next4`

**Churn has roughly DOUBLED recently — 20.6% lifetime vs 43.4% over the last 100 decisions.** Long
runs (11× `next2`) alternate with 4-decision flip storms. Consistent with §5: the fleet is currently
sitting inside a KF-quantization band where one session's arrival re-orders the top two.

🚨 **The interactive lane has NO decision log at all.** `route.jsonl` records only `cc-route`
(general/fable). The launcher's sole footprint is the `--assign` line, and
`~/.claude/logs/account-assignments.jsonl` is **pruned to its newest 200 lines at 400**
(`ASSIGN_PRUNE_LINES = 400`, :1249, :1320-1324) while sharing the file with `handoff-fire`
(214 of 218 current lines). **Only FOUR launcher-routed launches survive in the entire ledger**
(05:59:49 next4 · 09:34:33 next ×2 · 20:05:28 next3), and interactive history older than ~2 days
is **destroyed**. Interactive churn beyond n=4 is therefore **UNKNOWN and unrecoverable** — this
investigation was only possible because the 20:05:28 entry was the ledger's last line.

---

## 7. Adversarial pass — what a hostile reviewer would ask

| Challenge | Answer |
|---|---|
| "You used a readout taken 7 min AFTER the launch — circular." | Rejected the readout as primary. Reconstructed from `account-utilization.jsonl`, which is append-only and timestamped, at d = −114 s, corroborated by four earlier sweeps. |
| "k_work at 13:03:33 is not recorded — you assumed 2." | Both branches computed. `k_work=2` and census-fallback `k=2` give the **same** score and the **same** ranking. The assumption is not load-bearing. |
| "The 19:40–19:58 fire burst poisoned it." | Refuted by arithmetic: the only in-TTL phantom at 20:05:28 was next4's (439 s); next3's own fire was 1470 s old — 570 s past the 900 s TTL. |
| "All four rows carry `error: poll throttled` — `_excluded` :1456-1457 should have excluded everything." | The 13:03:33 sweep's `stale` flag is `stale_quota or error` (:1735). `inherit_lastgood` sets `stale_quota` (:866, :875) **without** setting `error`; `error` is set only on an actual throttle (:1013). A route did return an account, which proves `error` was unset on that generation. |
| "Would a fresh sweep have changed it?" | No — quotas were flat for an hour and next3's census read 2 four times running. |
| "Did the operator get a *worse* desk?" | No. next3 had **97%** of its week free and resets furthest out (6d15h). For a long-lived desk that is strictly the better account; `next` at 44% used is the one that would hit a wall first. The pick was substantively right, not merely formally right. |
| "Is `--rank` disturbing the state you measure?" | `--rank`/`--route` never call `record_assignment` (:3090+ gates it on `--assign`), and all replays ran cache-only or in a loaded module. My own probes wrote nothing to the ledger — verified: the only next3 assign in the TTL is the 20:05:28 launcher line. |

---

## 8. Recommendations (leverage-ordered)

1. **Add `route_line("interactive", …)` to the readout footer** (:2630). One line; removes the
   entire class of "I expected next" surprises. *This is the fix for the reported incident.*
2. **Log the interactive decision.** Have the launcher write to `route.jsonl` (slot=`interactive`)
   with the score vector, not just an `--assign` row into a 400-line-pruned ledger shared with
   `handoff-fire`. Today the lane that serves the human is the only one that is unauditable.
3. **Instrument the `k_work` timeout.** `working_concurrency` returning `None` silently swings
   `k_eff` by up to 6× and can trip `KMAX`. Emit a `log_event` on the `None` return and surface it
   in `route-meta`, so "was this pick made on working sessions or on panes?" is answerable.
   Consider raising `budget_s` above 2.0 — the measured walk is 0.04–0.07 s over 826 transcripts,
   so a 2 s trip means the box is pathologically loaded, which is when the count matters most.
4. **Consider exempting `--src claude-launcher` from the interactive lane's own phantom charge**, or
   giving it a shorter TTL. Spread is the right objective for dispatch bursts; for a human desk the
   15-minute self-penalty makes two consecutive `claude` invocations land on different accounts by
   design — and §5 shows one phantom is enough to flip the top two at the current fleet state.
