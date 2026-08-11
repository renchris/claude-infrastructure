# R2 — Which objective is right for the human desk, and how the disagreement resolves

**Verdict.** The operator wins on the objective; the code wins on two of its subsidiary rules.
The shipped `interactive` lane rests on a claim this fleet's own data **falsifies** — that reusing
`score_general` would "manufacture the 5-hour wall." It would not, because `score_general` already
carries the 5-hour brake. Measured over 324 sweeps of real history, the survival lane is *worse*
at avoiding the 5-hour wall than the dispatch lane it replaced (4.6% vs 3.4% exposure). Replace the
score with a two-key rule that is literally the operator's sentence — **5h-safe set first, then
earliest weekly reset** — keep `interactive` as a distinct lane (for the cliff no-yield rule), and
make it visible on `/accounts`, in the table marker, and in `--json`.

---

## 1. The two arguments, stated faithfully

### The code's argument (extracted, with citations)

| # | Claim | Where |
|---|---|---|
| C1 | `score_general` is `w_rem / T**γ`, γ=2 — deadline-DOMINANT by construction, so it prefers the account nearest its weekly reset. | `bin/claude-accounts:1475-1490` (return at `:1489`) |
| C2 | A dispatched fire is SHORT; the objective there is to spend quota before it strands. | `:1494-1496`; `docs/plans/ACCOUNT_ROUTING_V2.md:757` (§13 scope) |
| C3 | "An interactive desk … lives for hours or days, and the cost of a wrong pick is the operator hitting a wall mid-work." | `:1496-1498` |
| C4 | Pointing bare `claude` at the dispatch score "would place the operator NEAREST exhaustion and manufacture the 5-hour wall this lane exists to prevent — while reading as an ordinary limit hit, with nothing anywhere pointing at routing as the cause." | `:1498-1502` |
| C5 | Therefore: maximise RUNWAY, no 1/T term — `w_rem × s_rem × KF × CF`, `s_rem` linear in projected 5h headroom. | `:1503-1507`, `:1520-1529` |
| C6 | Same exclusions as general (`_excluded`) — "a different objective over the same eligibility, never a second opinion about who is eligible." | `:1509-1511`, `_excluded` at `:1454-1473` |
| C7 | The interactive lane **never yields the login-cliff term**. Yielding is right for dispatch (a drained account still works; refusing it turns a scheduled cliff calendar into an outage) and wrong for a human, because past the cliff `invalid_grant` has **no reset to wait for** — a yielded pick hands the operator a desk that dies on auth mid-session, recoverable only by the interactive `/login` the lane exists to avoid. | `ranked()` at `:1577-1612`, the interactive branch at `:1600-1606` |
| C8 | Design intent also included **hysteresis** — "keep the incumbent unless beaten by a margin," because routed launches move burn, which feeds `record_utilization`, which feeds the next ranking. | `docs/plans/START_LATENCY_ROUTER.md:82-83`, build item `:108` |

### The operator's argument (verbatim, as evidence about their utility function)

- Expected account 1 (`next`); personal preference account 2 (`next2`) **"being earlier weekly expiry and low 5-hour used."**
- Their earlier, independently-recorded sentence, which M7 encoded as algebra: *"prioritize exhausting the most immediate expiry, especially when remaining is large for the time left."* — `docs/plans/ACCOUNT_ROUTING_V2.md:779`
- The stranding complaint that generated M7 in the first place: *"the fleet was stranding weekly quota at reset"* — `ACCOUNT_ROUTING_V2.md:757-760`, called "the operator's complaint verbatim" at `bin/claude-accounts:1220`.

**Read as a utility function, the operator's preference is not `score_general`.** It is a *two-key
rule*: soonest weekly expiry, **conditioned on** low 5-hour use. That conjunction is a hybrid, and
it is neither shipped lane.

---

## 2. Provenance — was the operator consulted?

**No. It was derived by an agent, on the same day the operator stated the opposite objective.**

| Fact | Evidence |
|---|---|
| The lane landed 2026-08-10 22:56 PDT, one commit, agent-authored. | `git log -S 'score_interactive'` → `9a843f988` |
| Its justification is finding **S8** in an agent research wave ("The finding that changes the objective — S8, horizon mismatch"), sitting among machine-numbered findings F1–F12 and a "Refuted" table. | `docs/plans/START_LATENCY_ROUTER.md:70-83` |
| The M7 `/goal` that produced the *opposite* objective was the operator's own, dated **2026-08-10** — the same day. | `ACCOUNT_ROUTING_V2.md:757` ("2026-08-10, operator /goal") |
| Nothing in either plan doc records the operator being asked whether the desk should invert their stated rule. | grep of both plans for operator/consult/preference: only §13's quote, which points the other way. |
| The commit's own evidence is a **synthetic pair**, not live data: *"Both lanes name next4 on today's live fleet, so a live-data test alone could not have told these apart — hence the synthetic pair."* | `9a843f988` commit body |

That last line is the crux of the provenance problem. **The lane was validated on one constructed
example because the live snapshot could not discriminate.** It can be discriminated — over history,
not over one snapshot (§4 below), and when you do, the result goes the other way.

---

## 3. Measurement — how long is a desk session, really?

The claim under test is C3: "lives for hours or days." Sampled the 30 most recent transcripts with
≥20 messages across `~/.claude-next`, `~/.claude-secondary`, `~/.claude-tertiary`,
`~/.claude-quaternary` (n=30; timestamps parsed from each `.jsonl`):

| Metric | median | p75 | p90 | max | share > 5h |
|---|---|---|---|---|---|
| Wall-clock span (first→last message) | 0.32 h | 1.78 h | 12.80 h | **22.30 h** | 13% |
| **ACTIVE** hours (gaps > 45 min excluded) | 0.32 h | 1.75 h | 3.94 h | **4.43 h** | **0%** |
| Longest **unbroken** burst | 0.32 h | 1.16 h | 2.25 h | **2.39 h** | **0%** |

**C3 is true of wall-clock and false of quota.** A desk session does live for up to 22 hours — but
its burn is bursty: the longest unbroken burst in the sample is 2.39 h, and **no session in the
sample accumulates 5 hours of active work at all**, let alone inside one rolling 5-hour window. The
5-hour bucket is a *rolling* window; a 22-hour session with 4.4 h of scattered activity never
saturates it.

The runway argument therefore weakens sharply *as an argument about the desk's own burn*. What can
still saturate a 5-hour window is the **account's aggregate** load — the desk plus every dispatched
fire routed to the same account — and that is a real effect (§4).

---

## 4. Failure-mode cost, measured on this fleet

Store: `~/.claude/logs/account-utilization.jsonl` (`UTIL_PATH`, `bin/claude-accounts:1683-1684`),
written by `record_utilization` (`:1688`). **1,293 rows spanning 38.3 hours** —
2026-08-10T05:58Z → 2026-08-11T20:14Z. That is the entire store; it does not go back a week.

> ⚠️ **`com.claude.auth-timeseries` is NOT running** — `launchctl list | grep claude` does not list
> it; it sits in `~/.claude/autonomy/pending-activation/35-auth-timeseries-activate.sh`. It is also
> the wrong instrument for this question: it records *auth-token* rotation, not quota
> (`tools/auth/auth-timeseries.sh:1-30`). No prior stranding analysis exists in `docs/` beyond the
> M7 snapshot.

### (a) 5-hour walls

| account | samples | 5h max | 5h median | samples ≥85% | samples ≥95% |
|---|---|---|---|---|---|
| next | 323 | 58% | 5% | 0 | 0 |
| next2 | 323 | 61% | 8% | 0 | 0 |
| next3 | 324 | **100%** | 2% | 27 (8%) | 26 |
| next4 | 323 | 85% | 9% | 1 | 0 |

**One account hit the wall once in 38 hours** — `next3`, the M7 pile-up, which is a *dispatch*
pathology (36 sessions stacked), not a desk one. Three of four accounts never exceeded 61%.

### (b) Stranded weekly quota

Two weekly rollovers observed:

- `next3` 58% → 18% at 2026-08-10T06:04Z ⇒ **≈42 percentage-points of one account-week stranded.**
- `next3` 100% → 0% at 2026-08-11T12:04Z ⇒ 0 stranded (fully spent).

And the **live forecast**, straight from the shipped pace surface, is that stranding is happening
right now on two accounts:

```
pace to 100%: next2 15%/d over 3d (recent 11%/d — BEHIND) · next 13%/d over 4d (recent 9%/d — BEHIND) · next4 14%/d over 4d (recent 38%/d) · next3 15%/d over 6d
```

Extrapolating each BEHIND account to its own reset: `next2` lands ≈87% (**≈13 pp stranded**),
`next` lands ≈83% (**≈17 pp stranded**). **≈30 percentage-points of weekly quota is forecast to
strand this week** — unrecoverable by construction, whereas a 5-hour wall self-heals in ≤5 h and
has three cheap escapes (`claude2`, window roll, `/limit-recover` transplant).

### (c) Which limit does the fleet actually hit?

Transcript-mention counts across all four dirs (⚠️ **contaminated** — the `limit-recover` skill
description is injected into most sessions, so treat as order-of-magnitude only):

| phrase | distinct transcripts (of 3,352) |
|---|---|
| "hit your session limit" | 94 |
| "hit your weekly limit" | 63 |
| "hit your monthly spend limit" | 5,558 ⇒ **boilerplate, discard** |

5-hour walls are ~1.5× more frequent than weekly walls, and both are rare (≤3%).

---

## 5. The falsification — `score_general` already carries the 5-hour brake

This is the load-bearing finding, and it is a code fact, not a measurement.

`score_general` (`:1489`) returns `(w_rem / T**γ) * _soft(r, R) * cliff_factor`, and

```python
def _soft(r, R):                                   # bin/claude-accounts:1121-1127
    su = _su_projected(r, R)                       # measured 5h util + measured burn × lookahead
    SF = clamp((R["S_CUT"] - su) / (R["S_CUT"] - R["S_SOFT"]), R["SF_FLOOR"], 1.0)
    KF = clamp(1 - k_eff(r) / R["KMAX"], R["KFLOOR"], 1.0)
    CF = (1.0 if wu < 0.90 else 0.5) if r.get("credits_on") else 1.0
    return SF * KF * CF
```

So `score_general` already applies: the **hard `S_CUT`=0.85 exclusion** (`_excluded:1461-1463`), a
**projected** 5h softening ramp from 50%→85% (`_su_projected:1339-1353`), the **same KF**, and the
**same CF** that `score_interactive` uses. The two lanes differ in exactly two ways:

| | general | interactive |
|---|---|---|
| weekly urgency `1/T**2` | **yes** | no |
| 5h term shape | ramp from su=0.50, denominator 0.35 | linear from su=0, denominator 0.85 |
| 5h hard cutoff, KF, CF, cliff exclusion | identical | identical |

**Claim C4 conflates two different buckets.** "NEAREST exhaustion" under `score_general` means
nearest its **weekly reset** — an account with a *long* runway on the metric the operator feels
(the 5-hour window) and a *short* runway on the metric that strands. `score_general` cannot route
the operator to a near-5h-wall account: `S_CUT` forbids it and `SF` penalises it from 50% up.
Interactive is *modestly* more 5h-conservative above su≈0.5 (2.4× at su=0.7), and *less* selective
below it. That is a tuning difference, not the categorical one the docstring asserts.

### The replay that settles it

Replayed both scorers over all 324 sweeps in the utilization series, then asked what actually
happened to each pick in the following 6 hours:

| lane | 5h wall (≥85%) within 6h | weekly exhaustion (≥99%) within 6h | median weekly headroom of pick | picks |
|---|---|---|---|---|
| `general` (shipped) | **11 (3.4%)** | 0 (0.0%) | 73% | next 144 · next4 94 · next2 83 · next3 3 |
| `interactive` (shipped) | **15 (4.6%)** | 0 (0.0%) | 91% | next4 162 · next3 81 · next 60 · next2 21 |
| hybrid-i (5h floor + general score) | 10 (3.1%) | 0 (0.0%) | 73% | next 144 · next4 94 · next2 84 · next3 2 |
| **hybrid-ii (5h-safe set, then earliest weekly reset)** | **2 (0.6%)** | 0 (0.0%) | 73% | **next2 300** · next 22 · next3 2 |

Three results, in order of importance:

1. **The survival lane is measurably worse at its own job.** 4.6% vs 3.4%. Because `w_rem` dominance
   sends it to the roomiest *weekly* account — which on this fleet is `next4`, the account burning
   38%/day and the one that touched 85% at 13:02Z. Runway on the weekly axis is not runway on the
   5-hour axis, and the lane optimises the wrong one.
2. **Weekly exhaustion never happened, for either lane** (0/324). The catastrophic failure the
   runway objective guards against has zero observed incidence on this fleet.
3. **The two lanes disagree on 92% of sweeps** (298/324) — so the commit's "both lanes name next4 on
   today's live fleet" is an artifact of one snapshot, and the lane has been making a materially
   different choice from the visible one all along.

**The one honest point for the code**: on the single genuinely stressed window
(2026-08-10T08:00–12:59Z, the M7 pile-up, n=34), `interactive` scored **0.0%** 5h-wall exposure and
`general` **2.9%**. The runway objective *does* help under saturation. But hybrid-ii also scored
**0.0%** there — while picking `next2`, the earliest-resetting account. Hybrid-ii dominates on both
axes even in the stress case.

---

## 6. Three more defects the disagreement exposed

| # | Defect | Evidence |
|---|---|---|
| D1 | **Hysteresis was designed and never shipped.** `START_LATENCY_ROUTER.md:82-83` and build item `:108` both specify "keep the incumbent unless beaten by a margin." No `hyster`/`incumbent`/`margin` term exists in `score_interactive` or the launcher. So every bare `claude` re-routes from scratch. | grep of `bin/claude-accounts` + `~/.claude/lib/claude-launcher.zsh` |
| D2 | **The desk is routed by *general* on recycle.** `handoff-fire.sh:6128,6130,6164` re-picks the operator's own pane with `--route general` (`♻ recycle RE-PICK … router: claude-accounts --route general`). So the same human desk is governed by two different objectives depending on how it started. *(Nuance: this fires only when the current account is not routable at all — a rescue path, not a preference.)* | `scripts/handoff-fire.sh:6095-6164` |
| D3 | **The interactive lane has no observability anywhere.** Not in the footer (`route_line` is called only for `general` and `fable`, `:2630-2632`), not in the table (`mark = "➤" if … r["acct"] == pick_general`, `:2432`), not in `--json` (`score_general` + `score_fable` only, `:3136-3138`). Its stderr — carrying the exclusion map and `route-meta:` — is discarded by the launcher (`claude-launcher.zsh:59`, `2>/dev/null`). | as cited |

D3 is why the operator's expectation broke. They do get a post-hoc token — `◆ routed → next4` at
launch (`claude-launcher.zsh:112`) — but **no way to see the pick before running, and no way to see
why**. Every surface that answers "which account will I get" answers with the *dispatch* pick.

---

## 7. Hybrid designs evaluated

### (i) general score + hard 5h-headroom floor
`hybrid-i` above. 3.1% wall exposure. **Barely differs from plain general (3.4%)** — because
general's `SF` already does most of what the floor does. Verdict: **redundant.** It buys 0.3 pp and
adds a constant.

### (ii) two-key sort — 5h-safe set first, then earliest weekly reset  ← **RECOMMENDED**
`hybrid-ii`. **0.6% wall exposure** (5–8× better than either shipped lane), 0% weekly exhaustion,
0.0% on the stress window, and it concentrates on `next2` — **the exact account the operator named,
for the exact reason they gave.** It is their sentence executed literally.

Floor sensitivity (5h-safe threshold ∈ {50%, 60%, 70%, 85%} × weekly-headroom floor ∈ {0%, 15%,
30%}): the result is **flat at 0.6%** for every combination except the degenerate `s<85%` (0.9%).

> **State this honestly: the floor is untested by this data, not validated by it.** The fleet almost
> never approaches 60% 5h utilisation (3 of 4 accounts never exceeded 61%), so the floor almost never
> binds and its insensitivity is an absence of evidence, not evidence of robustness. Keep it as
> insurance — its whole value is the `next3`-shaped case, which happened once in 38 h and is exactly
> when a naive earliest-reset sort would hand the operator a capped desk. Set it at **60%**: below
> `S_CUT`=0.85 with real margin, above the 61% ceiling three accounts observed, so it binds on
> pathology and never on ordinary load.

Add a **weekly-headroom minimum** (`w_rem ≥ 15%`) as the second guard — it made no difference here
(0/324) but it is the only thing standing between a pure earliest-reset sort and the pathological
case it invites: routing the desk to an account with 2% of its week left and 3 hours to reset,
producing a **weekly** wall, which is the genuinely expensive one. Both guards must **degrade, not
empty**: safe-set → 5h-safe-only → all eligible.

### (iii) a knob with a documented default
**Reject as the primary answer, adopt as the escape hatch.** Every M7 term already ships a kill
switch (`CC_ROUTE_KWORK`, `CC_ROUTE_ASSIGN`, `CC_ROUTE_URGENCY_EXP`, `CC_ROUTE_PROJ`) — that is the
house pattern, and this should match it (`CC_ROUTE_DESK_5H_FLOOR`, `CC_ROUTE_DESK_W_FLOOR`, and
`CC_CLAUDE_ROUTE=off` already exists). But a knob is not a resolution: the operator does not
model-switch or tune routing, and shipping a knob in place of a decision reproduces the original
defect — an invisible policy the operator has no occasion to inspect.

### What must be KEPT from the shipped lane
- **C7, the cliff no-yield rule, survives intact and unchanged.** It is a statement about
  *eligibility*, not about the objective, and its argument is airtight: `invalid_grant` has no reset.
  Keep `interactive` as a distinct lane precisely so this rule has somewhere to live.
- **`_excluded` sharing** (C6). Same eligibility, different objective — right, and the hybrid keeps it.
- **The lane's existence.** The recommendation is to change the score, not to delete the lane.

---

## 8. Should `/accounts` display the `interactive` pick?

**Yes — and the sharper fix is that the table's `➤` marks the wrong pick.**

Three changes, in decreasing order of value:

1. **Re-point the table's `➤` to the interactive pick.** The comment at `:2402-2405` says the marker
   exists because *"the answer to 'which account do I use' was previously only in the footer"* —
   operator feedback, 2026-07-30. That question is asked **by a human, at an interactive desk**. The
   marker was wired to `pick_general` because the interactive lane did not exist for another eleven
   days. It is now a pre-lane artifact answering the wrong question to the only reader who sees it.
   The general pick is consumed programmatically by `handoff-fire`, which does not read tables.
   *(The 8-wide column holds `next3 ←➤` exactly (`:2430-2431`), so this must be a re-point, not a
   second glyph.)*
2. **Add a third footer line**: `➤ desk → **next2**` beside general and fable (`:2630-2632`). One
   line, inside the 82-col budget, and it makes a lane divergence legible instead of silent.
3. **Emit `score_interactive` + its `route_reasons` in `--json`** (`:3136-3138`). Today the lane is
   unobservable from disk, so nothing can audit it — which is how a 92%-disagreement rate survived
   a landing that claimed the lanes agree.

If the recommendation in §7 is adopted the lanes will agree far more often, which *lowers* the
urgency of (2) and (3) but not of (1): a marker that answers the human's question with the machine's
answer is wrong even when the two answers coincide.

---

## 9. Adversarial self-pass — what a hostile reviewer would say

| Objection | Response |
|---|---|
| **"38 hours is not a week. Your empirics don't generalise."** | Conceded, and stated as a limit. But it is the *entire* store, and it is 324 sweeps against the other side's **one synthetic pair** — the commit itself records that live data could not discriminate. Asymmetric evidence, both thin. Re-run after ≥2 full weekly cycles before treating the 0.6% as durable. |
| **"Your replay is observational, not counterfactual — routing the desk somewhere *changes* that account's future burn."** | Valid and unfixable from this data. Mitigated by volume: the assignment ledger (`~/.claude/logs/account-assignments.jsonl`, 219 rows / 32.6 h) shows **214 `handoff-fire` fires vs 4 `claude-launcher` launches** — the interactive lane governs **1.8% of routed launches**, so the desk's marginal contribution to any account's 5h window is small and observational ≈ counterfactual here. |
| **"Then the whole question is 1.8% of the traffic — why does it matter?"** | Two reasons. (a) The *stranding* lever is indeed dispatch, not the desk — so the operator's preference, though correctly reasoned, is aimed at a small lever, and the honest note is that fixing stranding means looking at the 214 fires. (b) The desk is nonetheless where the operator sits and forms their model of the system, so this is a **trust** defect at least as much as an efficiency one: they read `/accounts`, formed an expectation, and got something else with no way to have known. |
| **"You used `k` (pane census) in the replay; the shipped code charges `k_work` + phantoms."** | True — the utilization series records only `k`, so the replay is *stricter* on the concurrency axis than production (it excludes `next3` more often, the exact defect M7 fixed). This inflates all lanes' exclusions equally, so the between-lane comparison holds; absolute rates are approximate. Flagged, not hidden. |
| **"You ignored that the 5-hour wall is worse than you say — losing a desk mid-session is expensive."** | Priced it: three escapes exist (`claude2` pinned relaunch, ≤5 h window roll, `/limit-recover` transcript transplant), and the wall self-heals. Stranded weekly quota has **no** recovery. Asymmetry favours the deadline objective. |
| **"Cliff no-yield is the real reason the lane exists; you're gutting it."** | Explicitly preserved (§7). The recommendation changes the score, keeps the lane and keeps C7 verbatim. |
| **"You never checked whether other consumers depend on the interactive lane's current behaviour."** | Checked: `grep -rn 'route interactive'` finds **exactly one runtime caller** — `claude-launcher.zsh:59`. Everything else is documentation (`migrations/0009`, `README.md:252`, the two plans). Blast radius of a score change: one call site. |
| **"`/accounts` already shows the pace line — the operator could have inferred it."** | The pace line shows *stranding risk per account*; it does not show *which account the launcher will pick*. Inference across four rows and a footer is exactly the burden operator feedback 2026-07-30 already rejected once. |

### Gaps found in the self-pass and investigated

- **D1 (hysteresis never shipped)** — found by grepping for the design term; absent.
- **D2 (recycle uses `general` for the desk)** — found by grepping consumers of `--route`.
- **D3 (no `score_interactive` in `--json`)** — found by running `--json` and inspecting keys.
- **The `_soft` falsification (§5)** — found by reading `score_general`'s multiplicands rather than
  trusting the docstring's characterisation of them. This is the finding that flips the verdict.

### UNKNOWN (unmeasurable from available data)

- Weekly stranding over any period longer than 38.3 h — no store exists; `com.claude.auth-timeseries`
  is unactivated and measures the wrong thing anyway.
- True incidence of operator-experienced 5-hour walls — transcript phrase-matching is contaminated by
  the injected `limit-recover` skill description.
- Whether the desk's own burn would have changed any account's trajectory (counterfactual, above).

---

## 10. Recommendation

**Change the score, keep the lane, make it visible.**

1. `score_interactive` → **two-key**: among eligible accounts, take those with projected 5h
   utilisation `< 0.60` **and** weekly headroom `≥ 0.15`; among those, pick the **earliest weekly
   reset**. Degrade the filters one at a time rather than emptying the set. Kill switches
   `CC_ROUTE_DESK_5H_FLOOR` / `CC_ROUTE_DESK_W_FLOOR` per the M7 house pattern.
2. **Keep C7 verbatim** — the interactive lane still never yields the login cliff. That rule, not the
   score, is why the lane deserves to exist.
3. **Ship the hysteresis** the design already specified (`START_LATENCY_ROUTER.md:82-83`) — the desk
   should not silently move accounts between consecutive launches, and per-account
   `projects`/`sessions`/`history.jsonl` isolation makes flapping a real cost for `--resume`.
4. **Re-point the table `➤` to the desk pick**, add `➤ desk → **X**` to the footer, and emit
   `score_interactive` in `--json`.
5. **Record the reversal in the docstring at `:1492-1511`** — INTEGRATE, do not overwrite. The C4
   claim should be marked measured-false with the 3.4%-vs-4.6% number and the `_soft` reason, so the
   next reader does not re-derive S8 from the same plausible-but-wrong premise.

**Tradeoff, named:** this trades a *hypothetical* mid-session 5-hour wall — 0.6% exposure under the
recommendation, and never once observed on a desk in 38 h — for **≈30 percentage-points of weekly
quota per week that is currently forecast to strand unrecoverably**. The 5-hour wall is bounded,
recoverable in three ways, and self-heals. Stranded weekly quota is gone. When the operator said
*"earlier weekly expiry and low 5-hour used,"* they were not expressing a taste — they were naming
the correct objective and the correct guard, in that order.

---

## Appendix — live `/accounts` readout at time of research (reproduced verbatim)

```
| account | live | 5h used | 5h resets | weekly used | Fable used | weekly resets | login expires |
|---|---|---|---|---|---|---|---|
| next | 0 | 3%* | Tue 16:40 (in 3.4h) | 44%* | 18%* | Sat 21:00 (in 4d 7h) | Sun Aug 30 08:03 (in 18d 18h) |
| **next4** ➤ | 2 | 8% | Tue 15:59 (in 2.7h) | 38% | 22% | Sun 02:00 (in 4d 12h) | Sun Aug 30 08:36 (in 18d 19h) |
| next3 ← you | 12 | 15% | Tue 15:49 (in 2.5h) | 3% | 3% | Tue Aug 18 04:59 (in 6d 15h) | Thu Sep 03 10:27 (in 22d 21h) |
| next2 | 5 | 12% | Tue 15:00 (in 1.7h) | 47% | 20% | Sat 04:00 (in 3d 14h) | Mon Sep 07 04:28 (in 26d 15h) |
- ↻ `next` — poll throttled (a 90s endpoint throttle, NOT a usage cap); numbers are last-known as of 13:17; `--fresh` retries

➤ general → **next4** · ➤ fable → **next4**
pace to 100%: next2 15%/d over 3d (recent 11%/d — BEHIND) · next 13%/d over 4d (recent 9%/d — BEHIND) · next4 14%/d over 4d (recent 38%/d) · next3 15%/d over 6d
Fable window: **permanent** (no expiry).
_Cache ≤90s old; `--fresh` forces a live sweep._
```

Note what this board does and does not say. `next2` has the **soonest weekly reset (3d 14h)**, is
**BEHIND pace** (11%/d vs 15%/d needed), and its 5-hour window sits at **12%** — the operator's
reading is factually exact. The board's `➤` marks `next4`, the general pick. The desk pick appears
nowhere. At the moment of measurement `--route interactive` also returned `next4`, so the operator
would have been routed to neither the account they expected (`next`) nor the one they prefer
(`next2`) — and had no surface on which to see that coming.
